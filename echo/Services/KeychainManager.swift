import Foundation
import Security

class KeychainManager: ObservableObject {
    static let shared = KeychainManager()

    private let service = "com.echo.app"

    private init() {}

    /// Keychain account name for each provider's key. The Groq name predates OpenRouter
    /// support and must not change, or existing installs would lose their key.
    private func account(for provider: APIProvider) -> String {
        switch provider {
        case .groq: return "groq-api-key"
        case .openRouter: return "openrouter-api-key"
        }
    }

    // Save API key to keychain
    func saveAPIKey(_ apiKey: String, for provider: APIProvider = .groq) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        // Delete any existing key first
        deleteAPIKey(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // Retrieve API key from keychain
    func getAPIKey(for provider: APIProvider = .groq) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let apiKey = String(data: data, encoding: .utf8) {
            return apiKey
        }

        return nil
    }

    // Delete API key from keychain
    @discardableResult
    func deleteAPIKey(for provider: APIProvider = .groq) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // Check if API key exists in keychain
    func hasAPIKey(for provider: APIProvider = .groq) -> Bool {
        return getAPIKey(for: provider) != nil
    }

    // Migrate from UserDefaults to Keychain
    func migrateFromUserDefaults() {
        if let apiKey = UserDefaults.standard.string(forKey: "apiKey"), !apiKey.isEmpty {
            // Save to keychain
            if saveAPIKey(apiKey) {
                // Remove from UserDefaults
                UserDefaults.standard.removeObject(forKey: "apiKey")
                UserDefaults.standard.synchronize()
                print("Successfully migrated API key from UserDefaults to Keychain")
            }
        }
    }
}
