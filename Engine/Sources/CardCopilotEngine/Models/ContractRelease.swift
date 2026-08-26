import Foundation

/// The stamp describing which contract bytes this build shipped.
///
/// Mirrors `contracts/RELEASE.json`, which `scripts/release-catalogue.sh` writes and
/// `scripts/publish-catalogue.sh` publishes. Bundling it is what lets a prediction record the
/// contract that scored it rather than leaving that answerable only by implication from the
/// build number.
///
/// `digest` carries its `sha256:` prefix exactly as recorded, so a stored value stays
/// self-describing if the algorithm ever changes.
public struct ContractRelease: Codable, Equatable, Sendable {
    /// The published release id, e.g. `card-contracts@1.6`. Immutable once published: a release
    /// id never describes two different byte sets (publish-catalogue.sh refuses).
    public var release: String
    public var catalogueVersion: String
    /// sha256 over the sorted "name<TAB>sha256" lines of `files`.
    public var digest: String
    /// Filename → sha256 of that file's bytes.
    public var files: [String: String]

    public init(release: String, catalogueVersion: String, digest: String, files: [String: String]) {
        self.release = release
        self.catalogueVersion = catalogueVersion
        self.digest = digest
        self.files = files
    }
}
