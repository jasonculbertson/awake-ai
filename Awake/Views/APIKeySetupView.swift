import AppKit
import SwiftUI

/// Retained reference to prevent the window from being deallocated
private var apiKeyWindow: NSWindow?

/// Opens the API key setup in a standalone NSWindow.
func openAPIKeyWindow(keychainService: KeychainService, initialProvider: AIProvider? = nil, onDismiss: (() -> Void)? = nil) {
    apiKeyWindow?.close()
    let window = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
        styleMask: [.titled, .closable, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    window.title = "Awake - API Key Setup"
    window.center()
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.becomesKeyOnlyIfNeeded = false
    window.hidesOnDeactivate = false

    let hostingView = NSHostingView(
        rootView: APIKeyWindowContent(
            keychainService: keychainService,
            initialProvider: initialProvider ?? keychainService.selectedProvider
        ) {
            window.orderOut(nil)
            apiKeyWindow = nil
            onDismiss?()
        }
    )
    window.contentView = hostingView
    apiKeyWindow = window
    window.makeKeyAndOrderFront(nil)
}

private struct APIKeyWindowContent: View {
    let keychainService: KeychainService
    let onDone: () -> Void

    @State private var selectedProvider: AIProvider
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var isTesting = false
    @State private var testSuccess: String?
    @FocusState private var isFieldFocused: Bool

    init(keychainService: KeychainService, initialProvider: AIProvider, onDone: @escaping () -> Void) {
        self.keychainService = keychainService
        self.onDone = onDone
        _selectedProvider = State(initialValue: initialProvider)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Key icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "key.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-45))
            }

            Text("API Key Setup")
                .font(.headline)

            Picker("Provider", selection: $selectedProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 300)
            .onChange(of: selectedProvider) {
                apiKey = ""
                errorMessage = nil
            }

            Text("Your key is stored securely in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .focused($isFieldFocused)
                .onSubmit { save() }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let success = testSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(success)
                        .foregroundStyle(.green)
                }
                .font(.caption)
            }

            HStack(spacing: 12) {
                if keychainService.hasAPIKey(for: selectedProvider) {
                    Button("Remove") {
                        try? keychainService.deleteAPIKey(for: selectedProvider)
                        errorMessage = nil
                        testSuccess = nil
                        apiKey = ""
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }

                Spacer()

                Button("Cancel") { onDone() }
                    .buttonStyle(.bordered)

                Button(action: { save() }) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || isTesting)
            }
            .frame(width: 300)

            Link("Get a key at \(selectedProvider.consoleURL.replacingOccurrences(of: "https://", with: ""))",
                 destination: URL(string: selectedProvider.consoleURL)!)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFieldFocused = true
            }
        }
    }

    private func save() {
        guard !apiKey.isEmpty else { return }
        errorMessage = nil
        testSuccess = nil
        isTesting = true

        Task {
            let result = await validateKey(apiKey, provider: selectedProvider)
            await MainActor.run {
                isTesting = false
                    if result.success {
                    do {
                        try keychainService.saveAPIKey(apiKey, for: selectedProvider)
                        keychainService.selectedProvider = selectedProvider
                        testSuccess = "Key verified and saved!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            onDone()
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } else {
                    errorMessage = result.error ?? "Validation failed"
                }
            }
        }
    }

    private func validateKey(_ key: String, provider: AIProvider) async -> (success: Bool, error: String?) {
        do {
            var request: URLRequest
            switch provider {
            case .anthropic:
                request = URLRequest(url: URL(string: provider.endpoint)!)
                request.httpMethod = "POST"
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": provider.defaultModel,
                    "max_tokens": 10,
                    "messages": [["role": "user", "content": "hi"]],
                ])

            case .openai:
                request = URLRequest(url: URL(string: provider.endpoint)!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": provider.defaultModel,
                    "max_tokens": 10,
                    "messages": [["role": "user", "content": "hi"]],
                ])

            case .gemini:
                var urlComponents = URLComponents(string: provider.endpoint)!
                urlComponents.queryItems = [URLQueryItem(name: "key", value: key)]
                request = URLRequest(url: urlComponents.url!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "content-type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "contents": [["parts": [["text": "hi"]]]],
                    "generationConfig": ["maxOutputTokens": 10],
                ])
            }

            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response")
            }

            if httpResponse.statusCode == 200 {
                return (true, nil)
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return (false, "Invalid API key. Please check and try again.")
            } else {
                if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = body["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return (false, message)
                }
                return (false, "API returned HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }
}
