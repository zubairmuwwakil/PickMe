import Foundation

public extension SeedLoader {
    static var supportedMerchantMCCGraphMajorVersion: Int { 1 }

    static func loadMerchantMCCRuntimeSeed() throws -> MerchantMCCRuntimeSeed {
        let resourceName = "merchant-mcc-runtime-seed.zlib"
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "b64") else {
            throw SeedLoaderError.resourceMissing(resourceName)
        }
        let seed = try MerchantMCCRuntimeSeedCodec.decode(Data(contentsOf: url))
        guard let majorComponent = seed.graphVersion.split(separator: ".", maxSplits: 1).first,
              let major = Int(majorComponent), major == supportedMerchantMCCGraphMajorVersion else {
            throw SeedLoaderError.unsupportedCatalogueVersion(seed.graphVersion)
        }
        return seed
    }

    /// The 500-merchant bootstrap is a build resource just like merchant-pack.json. Treat failure
    /// to decode it as a broken build rather than silently reverting to a second handwritten list.
    static var merchantMCCRuntimeSeed: MerchantMCCRuntimeSeed {
        MerchantMCCRuntimeSeedHolder.value
    }
}

private enum MerchantMCCRuntimeSeedHolder {
    static let value: MerchantMCCRuntimeSeed = {
        do { return try SeedLoader.loadMerchantMCCRuntimeSeed() }
        catch { preconditionFailure("merchant MCC runtime seed is unreadable: \(error)") }
    }()
}
