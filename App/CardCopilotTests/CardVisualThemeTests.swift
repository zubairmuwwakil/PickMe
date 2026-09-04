import XCTest
import SwiftUI
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot
import UIKit

/// Drift-prevention and branding validation test suite for CardVisualTheme and CategoryVisuals.
///
/// Ensures that visual theme styling never drifts from the live card catalogue in contracts/card-catalogue.json:
/// - Every defined theme key must correspond to an actual card in the live catalogue.
/// - Every card in the live catalogue must have a dedicated theme style (never silently falling back to generic gray).
/// - Every card style must have valid non-empty branding attributes and multi-stop gradients.
/// - Every category dynamically derived by CategoryPickerAdvisor must resolve to a dedicated visual icon, color, and label.
final class CardVisualThemeTests: XCTestCase {

    func testAllDefinedThemeKeysExistInCatalogue() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let catalogueCardIds = Set(catalogue.cards.map(\.cardId))

        let unknownThemeKeys = CardVisualTheme.definedCardIds.subtracting(catalogueCardIds)
        XCTAssertTrue(
            unknownThemeKeys.isEmpty,
            "CardVisualTheme defines theme keys that do not exist in card-catalogue.json: \(unknownThemeKeys). Fix the keys to match the canonical catalogue."
        )
    }

    func testAllCatalogueCardsHaveDedicatedVisualTheme() throws {
        let catalogue = try SeedLoader.loadCatalogue()

        for card in catalogue.cards {
            let style = CardVisualTheme.style(for: card.cardId)

            XCTAssertEqual(style.cardId, card.cardId, "Style cardId mismatch for \(card.cardId)")
            XCTAssertFalse(style.shortName.trimmingCharacters(in: .whitespaces).isEmpty, "shortName must not be empty for \(card.cardId)")
            XCTAssertFalse(style.issuer.trimmingCharacters(in: .whitespaces).isEmpty, "issuer must not be empty for \(card.cardId)")
            XCTAssertNotEqual(style.issuer, "Card", "\(card.cardId) unexpectedly resolved to generic fallback issuer 'Card'")
            XCTAssertGreaterThanOrEqual(style.gradientColors.count, 2, "gradientColors must contain at least 2 gradient stops for \(card.cardId)")
        }
    }

    func testEveryDefinedCardProducesNonGenericStyle() {
        for cardId in CardVisualTheme.definedCardIds {
            let style = CardVisualTheme.style(for: cardId)

            XCTAssertEqual(style.cardId, cardId, "Style cardId mismatch for \(cardId)")
            XCTAssertFalse(style.shortName.trimmingCharacters(in: .whitespaces).isEmpty, "shortName must not be empty for \(cardId)")
            XCTAssertFalse(style.issuer.trimmingCharacters(in: .whitespaces).isEmpty, "issuer must not be empty for \(cardId)")
            XCTAssertNotEqual(style.issuer, "Card", "\(cardId) unexpectedly resolved to generic fallback issuer 'Card'")
            XCTAssertGreaterThanOrEqual(style.gradientColors.count, 2, "gradientColors must contain at least 2 gradient stops for \(cardId)")
        }
    }

    func testUnknownCardFallsBackToGenericStyle() {
        let unknownId = "custom-store-card"
        let fallback = CardVisualTheme.style(for: unknownId)

        XCTAssertEqual(fallback.cardId, unknownId)
        XCTAssertEqual(fallback.issuer, "Card")
        XCTAssertGreaterThanOrEqual(fallback.gradientColors.count, 2)
        XCTAssertTrue(fallback.isDark)

        // Verify smart inference for unknown cards with network keywords
        let unknownAmex = CardVisualTheme.style(for: "custom-amex-card")
        XCTAssertEqual(unknownAmex.network, .amex)
        XCTAssertEqual(unknownAmex.issuer, "American Express")

        let unknownVisa = CardVisualTheme.style(for: "custom-visa-infinite-card")
        XCTAssertEqual(unknownVisa.network, .visaInfinite)

        let unknownMC = CardVisualTheme.style(for: "custom-mastercard-card")
        XCTAssertEqual(unknownMC.network, .mastercard)
    }

    func testCardVisualThemeNetworksAlignWithCatalogue() throws {
        let catalogue = try SeedLoader.loadCatalogue()

        for card in catalogue.cards {
            let style = CardVisualTheme.style(for: card.cardId)
            switch card.network {
            case .amex:
                XCTAssertEqual(style.network, .amex, "Amex card \(card.cardId) must have .amex network in CardVisualTheme")
            case .visa:
                XCTAssertTrue(
                    style.network == .visa || style.network == .visaInfinite || style.network == .visaInfinitePrivilege || style.network == .prepaid,
                    "Visa card \(card.cardId) has unexpected network \(style.network) in CardVisualTheme"
                )
            case .mastercard:
                XCTAssertTrue(
                    style.network == .mastercard || style.network == .mastercardWorldElite,
                    "Mastercard \(card.cardId) has unexpected network \(style.network) in CardVisualTheme"
                )
            case .discover:
                XCTAssertEqual(style.network, .discover,
                               "Discover card \(card.cardId) must have .discover network in CardVisualTheme")
            case .privateLabel:
                XCTAssertEqual(style.network, .privateLabel,
                               "Private-label card \(card.cardId) must be identified as a store card in CardVisualTheme")
            }
        }
    }

    func testAmbientLocationServiceShortCardNamesCoversAllCatalogueCards() throws {
        let catalogue = try SeedLoader.loadCatalogue()

        for card in catalogue.cards {
            let shortName = AmbientLocationService.shortCardName(card)
            XCTAssertFalse(shortName.isEmpty, "Ambient short card name must not be empty for \(card.cardId)")
            XCTAssertFalse(shortName.hasSuffix(" Credit Card"), "Ambient short card name should trim 'Credit Card' suffix for \(card.cardId)")
        }
    }

    // MARK: - CategoryVisuals Dynamic Coverage Tests

    func testAllDerivedCategoriesResolveToDedicatedVisualMeta() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let derivedCategories = CategoryPickerAdvisor.derivedCategories(catalogue: catalogue)

        XCTAssertFalse(derivedCategories.isEmpty, "CategoryPickerAdvisor.derivedCategories must not be empty")

        for category in derivedCategories {
            let meta = CategoryVisuals.meta(for: category)

            let isDefaultFallback = meta.icon == "bag.fill" && meta.color == .secondary && meta.displayName == "General"
            XCTAssertFalse(
                isDefaultFallback,
                "Category '\(category)' derived by CategoryPickerAdvisor resolved to generic default visual fallback. Add a dedicated case in CategoryVisuals.meta(for:)."
            )
            XCTAssertFalse(meta.icon.trimmingCharacters(in: .whitespaces).isEmpty, "Icon for '\(category)' must not be empty")
            XCTAssertFalse(meta.displayName.trimmingCharacters(in: .whitespaces).isEmpty, "DisplayName for '\(category)' must not be empty")
        }
    }

    func testAllObservableCategoriesResolveToDedicatedVisualMeta() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let observable = observableCategories(in: catalogue)

        XCTAssertFalse(observable.isEmpty, "observableCategories must not be empty")

        for category in observable {
            let meta = CategoryVisuals.meta(for: category)

            let isDefaultFallback = meta.icon == "bag.fill" && meta.color == .secondary && meta.displayName == "General"
            XCTAssertFalse(
                isDefaultFallback,
                "Observable category '\(category)' resolved to generic default visual fallback. Add a dedicated case in CategoryVisuals.meta(for:)."
            )
        }
    }

    func testSpecificCategoryVisualMappings() {
        XCTAssertEqual(CategoryVisuals.meta(for: "ctFamily").icon, "triangle.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "wholesaleClub").icon, "building.2.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "digitalMedia").icon, "play.square.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "evCharging").icon, "bolt.car.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "entertainment").icon, "ticket.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "householdUtilities").icon, "lightbulb.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "marriottDirect").icon, "crown.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "memberships").icon, "person.2.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "other").icon, "tag.fill")
        XCTAssertEqual(CategoryVisuals.meta(for: "travel").icon, "airplane")
    }

    func testCategoryVisualAliasesShareCanonicalMetadata() {
        XCTAssertEqual(CategoryVisuals.meta(for: "groceries").icon,
                       CategoryVisuals.meta(for: "grocery").icon)
        XCTAssertEqual(CategoryVisuals.meta(for: "gas").displayName,
                       CategoryVisuals.meta(for: "gasStation").displayName)
        XCTAssertEqual(CategoryVisuals.meta(for: "pharmacy").icon,
                       CategoryVisuals.meta(for: "drugStore").icon)
        XCTAssertEqual(CategoryVisuals.meta(for: "hotel").displayName,
                       CategoryVisuals.meta(for: "lodging").displayName)
    }

    func testUnknownCategoryFallsBackToGenericBagMeta() {
        let unknown = "unmappedCategory_\(UUID().uuidString)"
        let fallback = CategoryVisuals.meta(for: unknown)

        XCTAssertEqual(fallback.icon, "bag.fill")
        XCTAssertEqual(fallback.color, .secondary)
        XCTAssertEqual(fallback.displayName, "General")
    }

    @MainActor
    func testRenderCategoryPickerGridScreenshot() throws {
        let schema = Schema([
            StoredPrediction.self, StoredPurchase.self, StoredObservation.self, StoredMerchant.self,
            ExploredCell.self, ShoppingArea.self, AreaMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CardVisualThemeTests.\(UUID().uuidString)"))
        let sync = SyncCoordinator(
            ownerStateLocalStore: OwnerStateLocalStore(defaults: defaults),
            accountOwnerStateStore: AccountOwnerStateStore(defaults: defaults))
        let environment = CopilotEnvironment(modelContext: context, sync: sync,
                                             ambient: AmbientLocationService())
        environment.load(session: CopilotSession())

        let view = NavigationStack {
            CategoryPickerView()
        }
        .environment(environment)
        .frame(width: 430, height: 1650)

        let hosting = UIHostingController(rootView: view)
        hosting.view.frame = CGRect(x: 0, y: 0, width: 430, height: 1650)
        // Dark mode screenshot
        hosting.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1650))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: hosting.view.bounds)
        let darkImage = renderer.image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }

        XCTAssertNotNil(darkImage.pngData(), "Dark category picker render must encode as PNG")
        let darkAttachment = XCTAttachment(image: darkImage)
        darkAttachment.name = "category-picker-grid-dark"
        darkAttachment.lifetime = .keepAlways
        add(darkAttachment)

        // Light mode screenshot
        hosting.overrideUserInterfaceStyle = .light
        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()

        let lightImage = renderer.image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }

        XCTAssertNotNil(lightImage.pngData(), "Light category picker render must encode as PNG")
        let lightAttachment = XCTAttachment(image: lightImage)
        lightAttachment.name = "category-picker-grid-light"
        lightAttachment.lifetime = .keepAlways
        add(lightAttachment)
    }

    func testMerchantBrandIconMonogramAndColor() {
        XCTAssertEqual(MerchantBrandIconView.monogram(for: "JRSports"), "JR")
        XCTAssertEqual(MerchantBrandIconView.monogram(for: "MugUpCanada"), "MU")
        XCTAssertEqual(MerchantBrandIconView.monogram(for: "Joe's Hardware"), "JH")
        XCTAssertEqual(MerchantBrandIconView.monogram(for: "A"), "A")
        XCTAssertEqual(MerchantBrandIconView.monogram(for: ""), "")

        let color1 = MerchantBrandIconView.deterministicColor(for: "JRSports")
        let color2 = MerchantBrandIconView.deterministicColor(for: "JRSports")
        XCTAssertEqual(color1, color2, "Deterministic color must be stable for identical merchant names")

        XCTAssertEqual(MerchantBrandIconView.monogramPalette.count, 8)
    }

    func testMerchantBrandIconVisualConfig() {
        let mcdonalds = MerchantBrandIconView.visualConfig(for: "McDonald's")
        XCTAssertEqual(mcdonalds.letter, "M")

        let dollarama = MerchantBrandIconView.visualConfig(for: "Dollarama")
        XCTAssertEqual(dollarama.letter, "D")

        let petroCan = MerchantBrandIconView.visualConfig(for: "Petro-Canada")
        XCTAssertEqual(petroCan.icon, "fuelpump.fill")

        let dq = MerchantBrandIconView.visualConfig(for: "Dairy Queen")
        XCTAssertEqual(dq.letter, "DQ")

        let subway = MerchantBrandIconView.visualConfig(for: "Subway")
        XCTAssertEqual(subway.letter, "S")

        let wendys = MerchantBrandIconView.visualConfig(for: "Wendy's")
        XCTAssertEqual(wendys.letter, "W")

        let aw = MerchantBrandIconView.visualConfig(for: "A&W Canada")
        XCTAssertEqual(aw.letter, "A&W")

        let bulkBarn = MerchantBrandIconView.visualConfig(for: "Bulk Barn")
        XCTAssertEqual(bulkBarn.letter, "BB")

        let winners = MerchantBrandIconView.visualConfig(for: "Winners")
        XCTAssertEqual(winners.letter, "W")

        let londonDrugs = MerchantBrandIconView.visualConfig(for: "London Drugs")
        XCTAssertEqual(londonDrugs.letter, "LD")

        let pizzaPizza = MerchantBrandIconView.visualConfig(for: "Pizza Pizza")
        XCTAssertEqual(pizzaPizza.icon, "fork.knife")

        let fortinos = MerchantBrandIconView.visualConfig(for: "Fortinos")
        XCTAssertEqual(fortinos.letter, "L")
        XCTAssertEqual(fortinos.icon, "cart.fill")

        let zehrs = MerchantBrandIconView.visualConfig(for: "Zehrs")
        XCTAssertEqual(zehrs.letter, "L")
        XCTAssertEqual(zehrs.icon, "cart.fill")
    }
}
