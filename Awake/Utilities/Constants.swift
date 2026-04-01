import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case gemini = "Google AI"

    var id: String { rawValue }

    var endpoint: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
        }
    }

    var keychainAccount: String {
        switch self {
        case .anthropic: return "anthropic-api-key"
        case .openai: return "openai-api-key"
        case .gemini: return "gemini-api-key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        }
    }

    var consoleURL: String {
        switch self {
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .openai: return "https://platform.openai.com/api-keys"
        case .gemini: return "https://aistudio.google.com/apikey"
        }
    }

    var icon: String {
        switch self {
        case .anthropic: return "brain"
        case .openai: return "cpu"
        case .gemini: return "sparkles"
        }
    }
}

enum Constants {
    static let appName = "Awake"
    static let keychainService = "com.jasonculbertson.awake"
    static let evaluationInterval: TimeInterval = 5
    static let processPollingInterval: TimeInterval = 15
    static let batteryPollingInterval: TimeInterval = 60
    static let processMinRuntime: TimeInterval = 30

    static let defaultWatchedApps: [(bundleID: String, name: String)] = [
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.microsoft.VSCode", "VS Code"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm2"),
        ("com.anthropic.claudefordesktop", "Claude"),
        ("dev.warp.Warp-Stable", "Warp"),
    ]

    static let defaultWatchedProcesses = [
        "npm", "node", "docker", "ffmpeg", "cargo",
        "swift-build", "swift-frontend", "xcodebuild",
        "python", "python3", "ruby", "go", "rustc",
        "webpack", "vite", "esbuild", "tsc",
    ]

    static let defaultBatteryThreshold = 20
}
