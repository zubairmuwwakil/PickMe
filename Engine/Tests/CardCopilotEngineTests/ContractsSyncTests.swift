import XCTest

/// contracts/ is the canonical home for card data (spec: docs/plans/2026-08-16-card-contract-spec.md).
/// SPM can't declare package resources outside a package's own root, so Engine keeps checked-in
/// copies at the old resource/fixture paths. This test is the drift guardrail: it fails the moment
/// those copies diverge from contracts/, the same failure mode MoneyTalks' vendored-copy drift
/// check will use. Run scripts/sync-contracts-into-engine.sh to resync after editing contracts/.
final class ContractsSyncTests: XCTestCase {
    /// #filePath is resolved at compile time from this source file's checked-out location, so it
    /// finds the repo root regardless of the working directory `swift test` is invoked from.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CardCopilotEngineTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // Engine/
            .deletingLastPathComponent()  // repo root
    }

    private func assertSynced(contractsRelativePath: String, engineRelativePath: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let contractsURL = Self.repoRoot.appendingPathComponent("contracts/\(contractsRelativePath)")
        let engineURL = Self.repoRoot.appendingPathComponent("Engine/\(engineRelativePath)")
        let contractsData = try Data(contentsOf: contractsURL)
        let engineData = try Data(contentsOf: engineURL)
        XCTAssertEqual(contractsData, engineData, """
            Engine/\(engineRelativePath) has drifted from contracts/\(contractsRelativePath). \
            Run scripts/sync-contracts-into-engine.sh to resync.
            """, file: file, line: line)
    }

    func testCardCatalogueMatchesContract() throws {
        try assertSynced(contractsRelativePath: "card-catalogue.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/card-catalogue.json")
    }

    func testCandidateCatalogueMatchesContract() throws {
        try assertSynced(contractsRelativePath: "candidate-catalogue.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/candidate-catalogue.json")
    }

    func testBenefitsCatalogueMatchesContract() throws {
        try assertSynced(contractsRelativePath: "benefits-catalogue.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/benefits-catalogue.json")
    }

    func testProgramDefaultsMatchContract() throws {
        try assertSynced(contractsRelativePath: "programs.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/programs.json")
    }

    func testOwnerConditionsMatchContract() throws {
        try assertSynced(contractsRelativePath: "owner-conditions.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/owner-conditions.json")
    }

    func testEngineFixturesMatchesContract() throws {
        try assertSynced(contractsRelativePath: "engine-fixtures.json",
                         engineRelativePath: "Tests/CardCopilotEngineTests/Fixtures/engine-fixtures.json")
    }

    func testReleaseStampMatchesContract() throws {
        try assertSynced(contractsRelativePath: "RELEASE.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/RELEASE.json")
    }
}
