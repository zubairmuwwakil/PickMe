import CardCopilotStore

/// Proves `MerchantProviding` is consumable by call sites without ever importing MapKit.
struct StubMerchantProvider: MerchantProviding {
    var nearbyResult: [NearbyPlace] = []
    var searchResult: [NearbyPlace] = []
    var nearbyError: Error?
    var searchError: Error?

    func nearby(latitude: Double, longitude: Double) async throws -> [NearbyPlace] {
        if let nearbyError { throw nearbyError }
        return nearbyResult
    }

    func search(text: String) async throws -> [NearbyPlace] {
        if let searchError { throw searchError }
        return searchResult
    }
}
