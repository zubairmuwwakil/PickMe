import Foundation
import Observation
import CardCopilotEngine

/// Personal benefit documents stay on this iPhone. The catalogue contains public issuer
/// references; this vault contains the owner's actual certificate or agreement, which is the
/// only thing that can move a card from issuer-page research to owner-confirmed coverage.
@Observable
@MainActor
final class BenefitsDocumentVault {
    private(set) var documents: [PersonalBenefitsDocument] = []

    private let fileManager = FileManager.default
    private var directoryURL: URL
    private let indexURL: URL

    init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
        var directory = applicationSupport.appendingPathComponent("CardCopilot/BenefitsDocuments",
                                                                  isDirectory: true)
        directoryURL = directory
        indexURL = directory.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        load()
    }

    @discardableResult
    func addDocument(cardId: String, sourceURL: URL, kind: String,
                     effectiveDate: String? = nil, jurisdiction: String? = nil,
                     notes: String? = nil) -> PersonalBenefitsDocument? {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directoryURL.setResourceValues(values)
            let id = UUID()
            let ext = sourceURL.pathExtension.isEmpty ? "document" : sourceURL.pathExtension
            let storedFileName = "\(id.uuidString).\(ext)"
            let destination = directoryURL.appendingPathComponent(storedFileName)
            try fileManager.copyItem(at: sourceURL, to: destination)

            let record = PersonalBenefitsDocument(
                id: id,
                cardId: cardId,
                kind: kind,
                fileName: sourceURL.lastPathComponent,
                storedFileName: storedFileName,
                addedAt: Self.todayString(),
                effectiveDate: effectiveDate,
                jurisdiction: jurisdiction,
                ownerConfirmed: false,
                verifiedAt: nil,
                notes: notes)
            documents.append(record)
            persist()
            return record
        } catch {
            return nil
        }
    }

    func confirmOwnerDocument(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].ownerConfirmed = true
        documents[index].verifiedAt = Self.todayString()
        persist()
    }

    func removeDocument(id: UUID) {
        guard let record = documents.first(where: { $0.id == id }) else { return }
        try? fileManager.removeItem(at: fileURL(for: record))
        documents.removeAll { $0.id == id }
        persist()
    }

    func fileURL(for record: PersonalBenefitsDocument) -> URL {
        directoryURL.appendingPathComponent(record.storedFileName)
    }

    func clearAll() {
        for record in documents {
            try? fileManager.removeItem(at: fileURL(for: record))
        }
        documents = []
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([PersonalBenefitsDocument].self, from: data) else {
            return
        }
        documents = decoded.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(documents)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            // A failed index write never deletes the imported file. The next app launch can still
            // recover the file manually, and the caller keeps its current in-memory state.
        }
    }

    private static func todayString() -> String {
        Date.now.formatted(.iso8601.year().month().day())
    }
}

struct PersonalBenefitsDocument: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let cardId: String
    let kind: String
    let fileName: String
    let storedFileName: String
    let addedAt: String
    let effectiveDate: String?
    let jurisdiction: String?
    var ownerConfirmed: Bool
    var verifiedAt: String?
    let notes: String?

    var status: BenefitVerification {
        ownerConfirmed ? .certificateVerified : .issuerPage
    }
}
