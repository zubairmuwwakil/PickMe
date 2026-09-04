import Foundation
import CardCopilotStore

/// Where the answer card's current subject came from.
///
/// Home used to infer this. `repeatContext` labelled the first remembered merchant "nearby"
/// whenever the cached fix happened to be recent, even when Radar had never returned that place.
/// A subject now carries its own provenance, so the badge states a fact instead of a guess.
enum HomeSubjectProvenance: Equatable {
    case nearby
    case recent
    /// The owner named this place in the search field. Distinct from `.nearby` because a search
    /// carries no location bias at all (Apple guideline 5.1.1), so claiming it is near the owner
    /// would be a fabrication.
    case searched

    var eyebrow: String {
        switch self {
        case .nearby: return "NEAR YOU"
        case .recent: return "RECENT PLACE"
        case .searched: return "SEARCHED"
        }
    }

    var symbol: String {
        switch self {
        case .nearby: return "location.fill"
        case .recent: return "clock.fill"
        case .searched: return "magnifyingglass"
        }
    }

    /// Whether the owner chose this subject on purpose. A deliberate choice is never
    /// second-guessed by the confidence rule that governs a Radar guess.
    var isDeliberate: Bool { self != .nearby }
}

/// One place the answer card can be pointed at, from either source.
///
/// Radar returns `NearbyPlace`; visit history returns `StoredMerchant`. The two already
/// project onto the same shape — `StoredMerchant.identifier` holds the MapKit POI id, which is
/// also `NearbyPlace.id` — so home carries this instead of two incompatible types rendered by
/// two near-identical views.
struct HomeAnswerSubject: Identifiable, Equatable {
    let id: String
    let name: String
    let prediction: CategoryPrediction
    let distanceMeters: Double?
    let provenance: HomeSubjectProvenance
    /// The owner has confirmed this merchant's category at least once. Only ever true for a
    /// remembered place: Radar alone cannot establish it.
    let isConfirmed: Bool
    /// Carried verbatim so the card can hand `CopilotSession.recommend` a merchant unchanged.
    let merchant: NearbyPlace

    init(nearby: NearbyPlace, provenance: HomeSubjectProvenance = .nearby) {
        id = nearby.id
        name = nearby.name
        // The same ladder `CheckoutService` scores on. Calling `predict` directly here dropped
        // both the merchant's MCC and the pack, so a searched brand could show `other` on the
        // card while the recommendation underneath it scored `streaming`.
        prediction = resolveCategory(for: nearby)
        distanceMeters = provenance == .nearby ? nearby.distanceMeters : nil
        self.provenance = provenance
        isConfirmed = false
        merchant = nearby
    }

    /// A remembered place keeps `predictionForKnownMerchant`, which prefers a category the owner
    /// confirmed over one guessed from the POI type. Projecting through `NearbyPlace` first
    /// would silently discard that confirmation.
    init(stored: StoredMerchant) {
        let identifier = stored.identifier ?? stored.id.uuidString
        id = identifier
        name = stored.name
        prediction = predictionForKnownMerchant(stored)
        distanceMeters = nil
        provenance = .recent
        isConfirmed = stored.confirmedCategory != nil
        merchant = NearbyPlace(id: identifier,
                                  placeID: stored.placeID,
                                  name: stored.name,
                                  poiCategoryRaw: stored.poiCategoryRaw,
                                  latitude: stored.latitude,
                                  longitude: stored.longitude,
                                  distanceMeters: nil)
    }
}

extension HomeAnswerSubject {
    /// Radar results first — they are ranked by distance and provably present — then remembered
    /// places Radar did not already return. A place that is both appears once, as nearby, because
    /// a live fix is better evidence than a past visit.
    static func merged(nearby: [NearbyPlace],
                       remembered: [StoredMerchant],
                       limit: Int = 20,
                       nearbyLimit: Int = 5,
                       rememberedLimit: Int = 10) -> [HomeAnswerSubject] {
        var seen = Set<String>()
        var subjects: [HomeAnswerSubject] = []

        var nearbyCount = 0
        for merchant in nearby where seen.insert(merchant.id).inserted {
            subjects.append(HomeAnswerSubject(nearby: merchant))
            nearbyCount += 1
            if nearbyCount >= nearbyLimit { break }
        }
        for merchant in remembered {
            let key = merchant.identifier ?? merchant.id.uuidString
            guard seen.insert(key).inserted else { continue }
            subjects.append(HomeAnswerSubject(stored: merchant))
            if subjects.count - nearbyCount >= rememberedLimit { break }
        }

        return Array(subjects.prefix(limit))
    }
}
