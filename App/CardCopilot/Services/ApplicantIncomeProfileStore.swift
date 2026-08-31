import Foundation
import CardCopilotEngine
import Security

/// Income is deliberately local-only. It is sensitive screening input, not wallet state, and is
/// never uploaded through the OwnerState/MoneyTalks sync path.
final class ApplicantIncomeProfileStore {
    private let service: String

    init(service: String = "ca.pickme.applicant-income-profile.v1") {
        self.service = service
    }

    func load(profileId: String?) -> ApplicantIncomeProfile {
        var query = baseQuery(profileId: profileId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let profile = try? JSONDecoder().decode(ApplicantIncomeProfile.self, from: data)
        else { return ApplicantIncomeProfile() }
        return profile
    }

    func save(_ profile: ApplicantIncomeProfile, profileId: String?) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        let query = baseQuery(profileId: profileId)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private func baseQuery(profileId: String?) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: storageId(profileId),
        ]
    }

    private func storageId(_ profileId: String?) -> String { profileId ?? "local-device-profile" }
}
