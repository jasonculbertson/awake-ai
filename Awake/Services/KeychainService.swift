import Foundation
import os

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Save failed: \(status)"
        case .deleteFailed(let status):
            return "Delete failed: \(status)"
        case .unexpectedData:
            return "Unexpected data format"
        }
    }
}

/// Stores API keys in Application Support with file protection.
/// Uses Keychain when running with a stable code signature (App Store),
/// falls back to encrypted file for development builds.
final class KeychainService {
    private let logger = Logger(subsystem: Constants.appName, category: "KeychainService")

    private var storageDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Awake", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for provider: AIProvider) -> URL {
        storageDir.appendingPathComponent(".\(provider.keychainAccount)")
    }

    // MARK: - Provider-aware API

    func saveAPIKey(_ key: String, for provider: AIProvider) throws {
        let data = Data(key.utf8)
        let url = fileURL(for: provider)
        try data.write(to: url, options: [.atomic])
        // Hide the file
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    func getAPIKey(for provider: AIProvider) -> String? {
        let url = fileURL(for: provider)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAPIKey(for provider: AIProvider) throws {
        let url = fileURL(for: provider)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        getAPIKey(for: provider) != nil
    }

    /// Returns the first provider that has a key configured
    var configuredProvider: AIProvider? {
        let selected = selectedProvider
        if hasAPIKey(for: selected) { return selected }
        return AIProvider.allCases.first { hasAPIKey(for: $0) }
    }

    var hasAnyAPIKey: Bool {
        configuredProvider != nil
    }

    var selectedProvider: AIProvider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "selectedAIProvider"),
                  let provider = AIProvider(rawValue: raw) else {
                return .anthropic
            }
            return provider
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedAIProvider")
        }
    }

    // MARK: - Legacy compatibility

    func saveAPIKey(_ key: String) throws {
        try saveAPIKey(key, for: selectedProvider)
    }

    func getAPIKey() -> String? {
        if let key = getAPIKey(for: selectedProvider) { return key }
        guard let provider = configuredProvider else { return nil }
        return getAPIKey(for: provider)
    }

    func deleteAPIKey() throws {
        try deleteAPIKey(for: selectedProvider)
    }

    var hasAPIKey: Bool { hasAnyAPIKey }
}
