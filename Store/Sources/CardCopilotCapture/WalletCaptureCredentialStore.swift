import Foundation
import Security

public struct WalletCaptureCredential: Codable, Sendable, Equatable {
    public let token: String
    public let installationID: String
    public let boundUserID: String
    public init(token: String, installationID: String, boundUserID: String) {
        self.token = token; self.installationID = installationID; self.boundUserID = boundUserID
    }
}

public struct WalletCaptureCredentialStore: Sendable {
    private let service: String
    private let account: String
    public init(service: String = "ca.pickme.wallet-capture", account: String = "installation") {
        self.service = service; self.account = account
    }

    public func save(_ credential: WalletCaptureCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public func load() -> WalletCaptureCredential? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WalletCaptureCredential.self, from: data)
    }

    public func remove() { SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                          kSecAttrService as String: service,
                                          kSecAttrAccount as String: account] as CFDictionary) }
}
