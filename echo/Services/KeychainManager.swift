import Foundation
import Security

class KeychainManager: ObservableObject {
    static let shared = KeychainManager()
    
    private let service = "com.echo.app"
    private let account = "groq-api-key"
    
    private init() {}
    
    // Save API key to keychain
    func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }
        
        // Delete any existing key first
        deleteAPIKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // Retrieve API key from keychain
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // Check if API key exists in keychain
    func hasAPIKey() -> Bool {
        return getAPIKey() != nil
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