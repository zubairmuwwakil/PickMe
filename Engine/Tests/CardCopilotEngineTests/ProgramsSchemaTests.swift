import XCTest
@testable import CardCopilotEngine

/// `contracts/programs.json` had no validation anywhere — not in CI, not in Swift, not in
/// Kotlin, not in `scripts/`. That is how the `noRewards` valuation shipped in
/// card-contracts@2.4 against a schema whose `oneOf` still listed only four models.
///
/// This is a structural check rather than a full JSON Schema implementation: every model name
/// appearing in the data must have a matching variant in the schema, and vice versa. That is the
/// exact class of drift that shipped, and it needs no schema engine to catch.
final class ProgramsSchemaTests: XCTestCase {

    private static var repoRoot: URL {
        var dir = URL(fileURLWithPath: #filePath).standardizedFileURL
        if !dir.path.hasPrefix("/") {
            dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(dir.path)
        }
        var current = dir.deletingLastPathComponent()
        while current.pathComponents.count > 1 {
            let candidate = current.appendingPathComponent("contracts/programs.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadJSON(_ relativePath: String) throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testEveryModelInProgramsJsonHasASchemaVariant() throws {
        let programs = try loadJSON("contracts/programs.json")
        let schema = try loadJSON("contracts/schema/programs.schema.json")

        let defaults = try XCTUnwrap(programs["defaults"] as? [String: Any])
        let dataModels = Set(defaults.values.compactMap { ($0 as? [String: Any])?["model"] as? String })

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let schemaModels = Set(defs.compactMap { name, body -> String? in
            guard let body = body as? [String: Any],
                  let props = body["properties"] as? [String: Any],
                  let model = props["model"] as? [String: Any],
                  let constant = model["const"] as? String else { return nil }
            _ = name
            return constant
        })

        XCTAssertEqual(dataModels.subtracting(schemaModels), [],
            "programs.json declares valuation model(s) with no variant in programs.schema.json. "
            + "The data does not validate against its own schema.")
    }

    func testEverySchemaVariantIsReachableFromTheOneOf() throws {
        let schema = try loadJSON("contracts/schema/programs.schema.json")
        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let valuation = try XCTUnwrap(defs["programValuation"] as? [String: Any])
        let branches = try XCTUnwrap(valuation["oneOf"] as? [[String: Any]])
        let referenced = Set(branches.compactMap { $0["$ref"] as? String })

        let variantNames = defs.compactMap { name, body -> String? in
            guard let body = body as? [String: Any],
                  let props = body["properties"] as? [String: Any],
                  props["model"] != nil else { return nil }
            return "#/$defs/\(name)"
        }

        XCTAssertEqual(Set(variantNames).subtracting(referenced), [],
            "schema variant(s) defined but not listed in programValuation.oneOf, so no data can "
            + "ever match them.")
    }
}
