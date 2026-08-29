import Foundation
import CardCopilotEngine

struct BenefitsSourceHealth {
    let cardCount: Int
    let cardsWithSources: Int
    let ownerVerifiedCards: Int
    let staleCards: Int
    let documentCount: Int
    let staleDocuments: Int

    init(catalogue: BenefitsCatalogue, now: Date = .now) {
        cardCount = catalogue.cards.count
        cardsWithSources = catalogue.cards.filter { !$0.documents.isEmpty || $0.certificate.sourceUrl != nil }.count
        ownerVerifiedCards = catalogue.cards.filter { $0.certificate.verificationStatus == .certificateVerified }.count
        documentCount = catalogue.cards.reduce(0) { $0 + max($1.documents.count, $1.certificate.sourceUrl == nil ? 0 : 1) }
        staleCards = catalogue.cards.filter { Self.isStale($0.certificate.lastVerifiedAt, now: now) }.count
        staleDocuments = catalogue.cards.flatMap(\.documents).filter { Self.isStale($0.lastVerifiedAt, now: now) }.count
    }

    var sourceCoverageLabel: String {
        "\(cardsWithSources) of \(cardCount) cards have source documents"
    }

    private static func isStale(_ value: String?, now: Date) -> Bool {
        guard let value, let date = parse(value) else { return true }
        return now.timeIntervalSince(date) > 365 * 24 * 60 * 60
    }

    private static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
