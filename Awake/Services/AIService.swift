import Foundation
import os

enum AIServiceError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case networkError(Error)
    case subscriptionRequired

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Add an API key in Settings."
        case .invalidResponse:
            return "Could not understand the AI response."
        case .apiError(let message):
            return "API error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .subscriptionRequired:
            return "A subscription is required to use AI commands."
        }
    }
}

final class AIService {
    private let keychainService: KeychainService
    private let logger = Logger(subsystem: Constants.appName, category: "AIService")

    /// True if user has their own API key (BYOK — always free)
    var isConfigured: Bool { keychainService.hasAnyAPIKey }

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    // MARK: - Main entry point

    func interpretCommand(
        _ userInput: String,
        currentRules: [AwakeRule],
        watchList: [AppWatchEntry],
        transactionJWS: String? = nil
    ) async throws -> AICommand {
        // BYOK path — use user's own key, no limits
        if let provider = keychainService.configuredProvider,
           let apiKey = keychainService.getAPIKey(for: provider) {
            let systemPrompt = buildSystemPrompt(currentRules: currentRules, watchList: watchList)
            let text: String
            switch provider {
            case .anthropic:
                text = try await callAnthropic(apiKey: apiKey, systemPrompt: systemPrompt, userInput: userInput)
            case .openai:
                text = try await callOpenAI(apiKey: apiKey, systemPrompt: systemPrompt, userInput: userInput)
            case .gemini:
                text = try await callGemini(apiKey: apiKey, systemPrompt: systemPrompt, userInput: userInput)
            }
            return parseCommand(text)
        }

        // Managed AI path — use our backend (free tier or subscription)
        return try await callManagedAI(
            userInput: userInput,
            currentRules: currentRules,
            watchList: watchList,
            transactionJWS: transactionJWS
        )
    }

    // MARK: - Managed AI (our backend)

    private func callManagedAI(
        userInput: String,
        currentRules: [AwakeRule],
        watchList: [AppWatchEntry],
        transactionJWS: String?
    ) async throws -> AICommand {
        let rules = currentRules.filter(\.isEnabled).map { "- \($0.label)" }
        let apps = watchList.filter(\.isEnabled).map { "- \($0.appName)" }

        guard let jws = transactionJWS else {
            throw AIServiceError.subscriptionRequired
        }

        let payload: [String: Any] = [
            "command": userInput,
            "deviceId": Constants.deviceId,
            "transactionJWS": jws,
            "context": ["rules": rules, "watchList": apps],
        ]

        var request = URLRequest(url: URL(string: Constants.managedAIEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        if let code = json["code"] as? String, code == "SUBSCRIPTION_REQUIRED" {
            throw AIServiceError.subscriptionRequired
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let msg = json["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError.apiError(msg)
        }

        guard let result = json["result"] as? String else {
            throw AIServiceError.invalidResponse
        }

        return parseCommand(result)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(currentRules: [AwakeRule], watchList: [AppWatchEntry]) -> String {
        let rulesDescription = currentRules.filter(\.isEnabled).map { rule in
            "- \(rule.label) (type: \(rule.type.rawValue))"
        }.joined(separator: "\n")

        let watchDescription = watchList.filter(\.isEnabled).map { entry in
            "- \(entry.appName) (\(entry.mode.rawValue))"
        }.joined(separator: "\n")

        return """
        You are the AI assistant for Awake, a macOS menu bar app that prevents the computer from sleeping.
        Your ONLY job is to interpret sleep/wake commands and return structured JSON.
        You MUST refuse any request that is not related to controlling Awake (sleep prevention, timers, app watching, schedules, battery, or status).
        For unrelated requests, return: {"command": "unknown", "message": "I can only help with sleep prevention commands."}
        Keep all responses to valid JSON only — no markdown, no explanation, no general chat.

        Interpret the user's natural language command and return a JSON object with a single "command" key.

        TIMER COMMANDS:
        - {"command": "set_timer", "duration_minutes": <int>} — "stay awake for 2 hours"
        - {"command": "set_delayed_timer", "delay_minutes": <int>, "duration_minutes": <int>} — "start in 5 min, run for 30 min"
        - {"command": "extend_timer", "minutes": <int>} — "extend timer by 30 minutes" / "add 1 hour"
        - {"command": "awake_until", "hour": <int 0-23>, "minute": <int 0-59>} — "stay awake until 5pm"
        - {"command": "awake_at", "hour": <int 0-23>, "minute": <int 0-59>, "duration_minutes": <int or null>} — "turn on at 3am" / "activate at 3am for 30 min"
        - {"command": "sleep_at", "hour": <int 0-23>, "minute": <int 0-59>} — "go to sleep at midnight" / "allow sleep at 11pm"
        - {"command": "pause", "minutes": <int>} — "pause for 10 minutes" / "take a break for 5 min" (disables then re-enables)

        APP COMMANDS:
        - {"command": "watch_app", "app_name": "<string>", "mode": "running" | "frontmost"} — "stay awake when Chrome is open"
        - {"command": "unwatch_app", "app_name": "<string>"} — "stop watching Chrome"
        - {"command": "watch_process", "process_name": "<string>"} — "stay awake while npm is running" / "watch for ffmpeg"

        SCHEDULE COMMANDS:
        - {"command": "set_schedule", "start_hour": <int 0-23>, "end_hour": <int 0-23>, "days": [<int 1-7, 1=Sun>]} — "stay awake weekdays 9-5"
        - {"command": "set_battery_threshold", "percentage": <int 0-100>} — "don't keep awake below 20%"

        CONTROL COMMANDS:
        - {"command": "toggle", "state": "on" | "off"} — "turn on" / "turn off" / "stay awake indefinitely" (on) / "allow sleep" (off)
        - {"command": "cancel_rule", "name": "<string>"} — "cancel the Chrome rule" / "remove the timer"
        - {"command": "clear_rules"} — "clear everything" / "remove all rules"

        INFO COMMANDS:
        - {"command": "list_rules"} — "what are my rules?" / "show rules"
        - {"command": "list_apps"} — "what apps are you watching?"
        - {"command": "status"} — "why are you awake?" / "what's happening?" / "are you on?"

        RULES:
        - Use 24-hour format: "5pm" = hour 17, "3am" = hour 3, "midnight" = hour 0, "noon" = hour 12
        - "stay awake indefinitely" or just "turn on" = toggle on
        - "until my build finishes" = watch_process with "swift-build" or relevant process
        - For app names, use the common name (e.g. "Chrome" not "Google Chrome")

        Current rules:
        \(rulesDescription.isEmpty ? "None" : rulesDescription)

        Watched apps:
        \(watchDescription.isEmpty ? "None" : watchDescription)

        Respond with ONLY valid JSON. No explanation or markdown.
        """
    }

    // MARK: - Anthropic

    private func callAnthropic(apiKey: String, systemPrompt: String, userInput: String) async throws -> String {
        let body: [String: Any] = [
            "model": AIProvider.anthropic.defaultModel,
            "max_tokens": 150,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userInput]],
        ]

        var request = URLRequest(url: URL(string: AIProvider.anthropic.endpoint)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(data: data, response: response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    // MARK: - OpenAI

    private func callOpenAI(apiKey: String, systemPrompt: String, userInput: String) async throws -> String {
        let body: [String: Any] = [
            "model": AIProvider.openai.defaultModel,
            "max_tokens": 150,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userInput],
            ],
        ]

        var request = URLRequest(url: URL(string: AIProvider.openai.endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(data: data, response: response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    // MARK: - Gemini

    private func callGemini(apiKey: String, systemPrompt: String, userInput: String) async throws -> String {
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [
                ["parts": [["text": userInput]]],
            ],
            "generationConfig": [
                "maxOutputTokens": 200,
                "temperature": 0.1,
            ],
        ]

        var urlComponents = URLComponents(string: AIProvider.gemini.endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(data: data, response: response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    // MARK: - Helpers

    private func checkHTTPStatus(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        if httpResponse.statusCode != 200 {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try common error formats
                if let errorInfo = errorBody["error"] as? [String: Any],
                   let message = errorInfo["message"] as? String {
                    throw AIServiceError.apiError(message)
                }
                if let message = errorBody["message"] as? String {
                    throw AIServiceError.apiError(message)
                }
            }
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }

    private func parseCommand(_ text: String) -> AICommand {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            return .unknown(raw: text)
        }

        switch command {
        case "set_timer":
            guard let minutes = json["duration_minutes"] as? Int else { return .unknown(raw: text) }
            return .setTimer(durationMinutes: minutes)
        case "set_delayed_timer":
            guard let delay = json["delay_minutes"] as? Int,
                  let duration = json["duration_minutes"] as? Int else { return .unknown(raw: text) }
            return .setDelayedTimer(delayMinutes: delay, durationMinutes: duration)
        case "awake_until":
            guard let hour = json["hour"] as? Int,
                  let minute = json["minute"] as? Int else { return .unknown(raw: text) }
            return .awakeUntil(hour: hour, minute: minute)
        case "awake_at":
            guard let hour = json["hour"] as? Int,
                  let minute = json["minute"] as? Int else { return .unknown(raw: text) }
            let duration = json["duration_minutes"] as? Int
            return .awakeAt(hour: hour, minute: minute, durationMinutes: duration)
        case "watch_app":
            guard let name = json["app_name"] as? String else { return .unknown(raw: text) }
            let modeStr = json["mode"] as? String ?? "running"
            let mode: WatchMode = modeStr == "frontmost" ? .whenFrontmost : .whenRunning
            return .watchApp(appName: name, mode: mode)
        case "unwatch_app":
            guard let name = json["app_name"] as? String else { return .unknown(raw: text) }
            return .unwatchApp(appName: name)
        case "extend_timer":
            guard let minutes = json["minutes"] as? Int else { return .unknown(raw: text) }
            return .extendTimer(minutes: minutes)
        case "sleep_at":
            guard let hour = json["hour"] as? Int,
                  let minute = json["minute"] as? Int else { return .unknown(raw: text) }
            return .sleepAt(hour: hour, minute: minute)
        case "pause":
            guard let minutes = json["minutes"] as? Int else { return .unknown(raw: text) }
            return .pause(minutes: minutes)
        case "watch_process":
            guard let name = json["process_name"] as? String else { return .unknown(raw: text) }
            return .watchProcess(processName: name)
        case "set_schedule":
            guard let start = json["start_hour"] as? Int,
                  let end = json["end_hour"] as? Int else { return .unknown(raw: text) }
            let days = json["days"] as? [Int] ?? Array(1...7)
            return .setSchedule(startHour: start, endHour: end, days: days)
        case "set_battery_threshold":
            guard let pct = json["percentage"] as? Int else { return .unknown(raw: text) }
            return .setBatteryThreshold(percentage: pct)
        case "toggle":
            guard let state = json["state"] as? String else { return .unknown(raw: text) }
            return .toggle(state: state == "on")
        case "cancel_rule":
            guard let name = json["name"] as? String else { return .unknown(raw: text) }
            return .cancelRule(name: name)
        case "clear_rules":
            return .clearRules
        case "list_rules":
            return .listRules
        case "list_apps":
            return .listApps
        case "status":
            return .status
        default:
            return .unknown(raw: text)
        }
    }
}
