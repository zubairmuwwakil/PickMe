import Foundation
import XCTest

final class AgentRouterTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CardCopilotEngineTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // Engine/
        .deletingLastPathComponent()  // repository root

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testRootRouterStaysInsideTheAlwaysLoadedBudget() throws {
        let agents = try read("AGENTS.md")
        let claude = try read("CLAUDE.md")
        let nonEmptyLines = agents.split(separator: "\n").filter {
            !String($0).trimmingCharacters(in: .whitespaces).isEmpty
        }

        XCTAssertLessThanOrEqual(nonEmptyLines.count, 40)
        XCTAssertLessThanOrEqual(agents.utf8.count + claude.utf8.count, 2_400)
    }

    func testClaudeOnlyImportsTheCanonicalRouter() throws {
        XCTAssertEqual(try read("CLAUDE.md"), "@AGENTS.md\n")
    }

    func testDemotedContextUsesMarkdownLinksNeverEagerImports() throws {
        let agents = try read("AGENTS.md")
        for target in [
            "REPO_MAP.md",
            "docs/policies/product-boundaries.md",
            "ECOSYSTEM.md",
            "FLEET.md",
        ] {
            XCTAssertTrue(agents.contains("(\(target))"), "Missing Markdown link to \(target)")
        }
        XCTAssertFalse(agents.contains("@ECOSYSTEM.md"))
        XCTAssertFalse(agents.contains("@FLEET.md"))
    }

    func testEveryStackSpecificRouterExists() throws {
        for path in ["Engine/AGENTS.md", "android/AGENTS.md", "catalogue-pipeline/AGENTS.md"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: Self.repoRoot.appendingPathComponent(path).path
                ),
                "Missing nested router \(path)"
            )
        }
    }

    func testFreedomClauseRequiresDirectWorkOnMain() throws {
        let agents = try read("AGENTS.md")
        XCTAssertTrue(agents.contains("Work directly on `main`"))
        XCTAssertTrue(agents.contains("Do not create branches or pull requests"))
    }
}
