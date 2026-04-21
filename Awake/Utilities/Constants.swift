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
    static let appName = "Awake AI"
    static let keychainService = "com.jasonculbertson.awake"
    static let managedAIEndpoint = "https://backend-gilt-one-75.vercel.app/api/ai"
    static let evaluationInterval: TimeInterval = 5

    /// Stable UUID per device, generated once and stored in UserDefaults
    static var deviceId: String {
        let key = "awake_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
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

    /// Maps app bundle IDs to the child process names that indicate active work.
    /// When an app spawns these children, it's considered "actively working."
    static let appChildProcessMap: [String: [String]] = [
        "com.apple.dt.Xcode": ["xcodebuild", "clang", "swiftc", "swift-frontend", "ld", "libtool"],
        "com.todesktop.230313mzl4w4u92": ["node", "tsc", "esbuild", "webpack"],  // Cursor
        "com.microsoft.VSCode": ["node", "tsc", "esbuild", "webpack"],
        "com.adobe.Premiere Pro": ["AMECommandLine", "dynamiclinkmanager"],
        "com.adobe.AfterEffects": ["aerendercore"],
        "com.blackmagic-design.DaVinci-Resolve": ["DaVinci Resolve"],
        "com.apple.Terminal": ["bash", "zsh", "sh", "python", "python3", "node", "npm", "ruby", "go"],
        "com.googlecode.iterm2": ["bash", "zsh", "sh", "python", "python3", "node", "npm", "ruby", "go"],
        "dev.warp.Warp-Stable": ["bash", "zsh", "sh", "python", "python3", "node", "npm"],
    ]

    /// AI command bar example suggestions (shown as rotating placeholder text)
    static let aiCommandSuggestions = [
        "Stay awake for 2 hours",
        "Keep on while Xcode is running",
        "Stay awake until 11pm",
        "Don't sleep while Docker runs",
        "Wake me at 9am for 1 hour",
        "Stay awake while my build finishes",
        "Keep awake until 5pm then sleep",
        "Pause for 30 minutes",
    ]
}
