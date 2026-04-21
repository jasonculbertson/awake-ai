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
            switch httpResponse.statusCode {
            case 429:
                throw AIServiceError.apiError("Too many requests. Wait a moment and try again.")
            case 401, 403:
                throw AIServiceError.apiError("Subscription not valid. Check your purchase in Settings.")
            case 500, 502, 503:
                throw AIServiceError.apiError("AI service temporarily unavailable. Try again in a moment.")
            default:
                let msg = json["error"] as? String ?? "Something went wrong. Please try again."
                throw AIServiceError.apiError(msg)
            }
        }

        guard let result = json["result"] as? String else {
            throw AIServiceError.invalidResponse
        }

        return parseCommand(result)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(currentRules: [AwakeRule], watchList: [AppWatchEntry]) -> String {
        let rulesDescription = currentRules.filter(\.isEnabled).map { "- \($0.label)" }.joined(separator: "\n")
        let watchDescription = watchList.filter(\.isEnabled).map { "- \($0.appName)" }.joined(separator: "\n")

        return """
        Awake AI: macOS sleep-prevention app. Parse user commands into JSON only. Refuse unrelated requests with {"command":"unknown","message":"I only handle sleep prevention commands."}.

        Commands:
        set_timer(duration_minutes) | set_delayed_timer(delay_minutes,duration_minutes) | extend_timer(minutes) | awake_until(hour,minute) | awake_at(hour,minute,duration_minutes?) | sleep_at(hour,minute) | pause(minutes)
        watch_app(app_name,mode:"running"|"frontmost") | unwatch_app(app_name) | watch_process(process_name)
        set_schedule(start_hour,end_hour,days:[1-7]) | set_battery_threshold(percentage)
        toggle(state:"on"|"off") | cancel_rule(name) | clear_rules | list_rules | list_apps | status

        Use 24h time. "turn on"=toggle on. "until build"=watch_process swift-build.
        Active rules: \(rulesDescription.isEmpty ? "none" : rulesDescription)
        Watched apps: \(watchDescription.isEmpty ? "none" : watchDescription)
        Return ONLY valid JSON.
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
            // Friendly messages for common HTTP errors
            switch httpResponse.statusCode {
            case 429:
                throw AIServiceError.apiError("You've hit the rate limit for your API key. Wait a moment and try again.")
            case 401, 403:
                throw AIServiceError.apiError("Invalid API key. Check your key in Settings.")
            case 500, 502, 503:
                throw AIServiceError.apiError("The AI service is temporarily unavailable. Try again in a moment.")
            default:
                break
            }

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
            throw AIServiceError.apiError("Something went wrong. Please try again.")
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
