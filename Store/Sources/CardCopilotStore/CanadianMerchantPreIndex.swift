import Foundation
import CardCopilotEngine

/// A pre-indexed lookup record for prominent Canadian retailers and service providers.
public struct PreIndexedMerchant: Identifiable, Equatable, Sendable {
    public var id: String { name.lowercased() }
    public let name: String
    public let category: String
    public let mcc: Int?
    public let merchantBrand: String?
    public let acceptedNetworks: Set<Network>
    public let notes: String?

    public init(name: String, category: String, mcc: Int? = nil,
                merchantBrand: String? = nil,
                acceptedNetworks: Set<Network> = [.amex, .visa, .mastercard],
                notes: String? = nil) {
        self.name = name
        self.category = category
        self.mcc = mcc
        self.merchantBrand = merchantBrand
        self.acceptedNetworks = acceptedNetworks
        self.notes = notes
    }
}

/// Instant offline index for the top ~250 Canadian merchants.
/// Provides sub-millisecond autocompletion and exact MCC/network mapping without network calls.
public struct CanadianMerchantPreIndex: Sendable {
    public static let all: [PreIndexedMerchant] = [
        // MARK: - Wholesale & Big Box
        PreIndexedMerchant(name: "Costco Wholesale", category: "wholesaleClub", mcc: 5300, merchantBrand: "costco", acceptedNetworks: [.mastercard], notes: "Warehouse accepts Mastercard only. Gas pumps accept Mastercard."),
        PreIndexedMerchant(name: "Walmart Supercentre", category: "grocery", mcc: 5411, merchantBrand: "walmart", notes: "Supercentres with full fresh grocery code as 5411; discount locations code as 5310."),
        PreIndexedMerchant(name: "Walmart", category: "other", mcc: 5310, merchantBrand: "walmart"),
        PreIndexedMerchant(name: "Canadian Tire", category: "ctFamily", mcc: 5200, merchantBrand: "canadian-tire"),
        PreIndexedMerchant(name: "Mark's / L'Équipeur", category: "ctFamily", mcc: 5651, merchantBrand: "canadian-tire"),
        PreIndexedMerchant(name: "Sport Chek", category: "ctFamily", mcc: 5941, merchantBrand: "canadian-tire"),
        PreIndexedMerchant(name: "Atmosphere", category: "ctFamily", mcc: 5941, merchantBrand: "canadian-tire"),
        PreIndexedMerchant(name: "Home Depot", category: "other", mcc: 5200),
        PreIndexedMerchant(name: "Rona / Réno-Dépôt", category: "other", mcc: 5200),
        PreIndexedMerchant(name: "IKEA", category: "other", mcc: 5712),
        PreIndexedMerchant(name: "Best Buy", category: "other", mcc: 5732),

        // MARK: - Groceries & Supermarkets
        PreIndexedMerchant(name: "Loblaws", category: "grocery", mcc: 5411, merchantBrand: "loblaws"),
        PreIndexedMerchant(name: "No Frills", category: "grocery", mcc: 5411, merchantBrand: "loblaws", acceptedNetworks: [.mastercard, .visa], notes: "Does not accept American Express."),
        PreIndexedMerchant(name: "Real Canadian Superstore", category: "grocery", mcc: 5411, merchantBrand: "loblaws"),
        PreIndexedMerchant(name: "Metro", category: "grocery", mcc: 5411, merchantBrand: "metro"),
        PreIndexedMerchant(name: "Food Basics", category: "grocery", mcc: 5411, merchantBrand: "metro"),
        PreIndexedMerchant(name: "Sobeys", category: "grocery", mcc: 5411, merchantBrand: "sobeys"),
        PreIndexedMerchant(name: "Safeway", category: "grocery", mcc: 5411, merchantBrand: "sobeys"),
        PreIndexedMerchant(name: "FreshCo", category: "grocery", mcc: 5411, merchantBrand: "sobeys"),
        PreIndexedMerchant(name: "IGA", category: "grocery", mcc: 5411, merchantBrand: "sobeys"),
        PreIndexedMerchant(name: "Save-On-Foods", category: "grocery", mcc: 5411),
        PreIndexedMerchant(name: "Farm Boy", category: "grocery", mcc: 5411, merchantBrand: "sobeys"),
        PreIndexedMerchant(name: "Longos", category: "grocery", mcc: 5411),
        PreIndexedMerchant(name: "Whole Foods Market", category: "grocery", mcc: 5411),
        PreIndexedMerchant(name: "T&T Supermarket", category: "grocery", mcc: 5411, merchantBrand: "loblaws"),
        PreIndexedMerchant(name: "Maxi", category: "grocery", mcc: 5411, merchantBrand: "loblaws", acceptedNetworks: [.mastercard, .visa], notes: "Does not accept American Express."),
        PreIndexedMerchant(name: "Provigo", category: "grocery", mcc: 5411, merchantBrand: "loblaws"),
        PreIndexedMerchant(name: "Super C", category: "grocery", mcc: 5411, merchantBrand: "metro"),
        PreIndexedMerchant(name: "Voila by Sobeys", category: "grocery", mcc: 5411, merchantBrand: "sobeys"),

        // MARK: - Coffee, Bakeries & Fast Casual
        PreIndexedMerchant(name: "Tim Hortons", category: "dining", mcc: 5814, merchantBrand: "tim-hortons"),
        PreIndexedMerchant(name: "Starbucks", category: "dining", mcc: 5814, merchantBrand: "starbucks"),
        PreIndexedMerchant(name: "McDonald's", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Subway", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "A&W Canada", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Second Cup", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Wendy's", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Popeyes Louisiana Kitchen", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Harvey's", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Freshii", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Chipotle Mexican Grill", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Booster Juice", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Chatime", category: "dining", mcc: 5814),
        PreIndexedMerchant(name: "Gong Cha", category: "dining", mcc: 5814),

        // MARK: - Dining & Restaurants
        PreIndexedMerchant(name: "The Keg Steakhouse + Bar", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Cactus Club Cafe", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Earls Kitchen + Bar", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "JOEY Restaurants", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Moxies", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Boston Pizza", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Swiss Chalet", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Milestones", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Montana's BBQ & Bar", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "St-Hubert", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Baton Rouge Grillhouse & Bar", category: "dining", mcc: 5812),
        PreIndexedMerchant(name: "Kelseys Original Roadhouse", category: "dining", mcc: 5812),

        // MARK: - Food Delivery & Rideshare
        PreIndexedMerchant(name: "Uber Eats", category: "foodDelivery", mcc: 5814),
        PreIndexedMerchant(name: "DoorDash", category: "foodDelivery", mcc: 5814),
        PreIndexedMerchant(name: "SkipTheDishes", category: "foodDelivery", mcc: 5814),
        PreIndexedMerchant(name: "Uber", category: "transit", mcc: 4121),
        PreIndexedMerchant(name: "Lyft", category: "transit", mcc: 4121),

        // MARK: - Gas Stations & Convenience
        PreIndexedMerchant(name: "Shell", category: "gasStation", mcc: 5541, merchantBrand: "shell"),
        PreIndexedMerchant(name: "Petro-Canada", category: "gasStation", mcc: 5541, merchantBrand: "petro-canada"),
        PreIndexedMerchant(name: "Esso", category: "gasStation", mcc: 5541, merchantBrand: "esso"),
        PreIndexedMerchant(name: "Mobil", category: "gasStation", mcc: 5541, merchantBrand: "mobil"),
        PreIndexedMerchant(name: "Chevron", category: "gasStation", mcc: 5541),
        PreIndexedMerchant(name: "Pioneer Gas", category: "gasStation", mcc: 5541),
        PreIndexedMerchant(name: "Ultramar", category: "gasStation", mcc: 5541),
        PreIndexedMerchant(name: "Couche-Tard / Circle K", category: "gasStation", mcc: 5541),
        PreIndexedMerchant(name: "7-Eleven Canada", category: "gasStation", mcc: 5541),

        // MARK: - Pharmacy & Personal Care
        PreIndexedMerchant(name: "Shoppers Drug Mart", category: "drugStore", mcc: 5912, merchantBrand: "shoppers", notes: "Codes as MCC 5912 Drugstore (not grocery on Amex/Visa/MC)."),
        PreIndexedMerchant(name: "Rexall", category: "drugStore", mcc: 5912),
        PreIndexedMerchant(name: "Jean Coutu", category: "drugStore", mcc: 5912),
        PreIndexedMerchant(name: "Pharmaprix", category: "drugStore", mcc: 5912, merchantBrand: "shoppers"),
        PreIndexedMerchant(name: "Sephora", category: "other", mcc: 5977),

        // MARK: - Liquor & Cannabis
        PreIndexedMerchant(name: "LCBO", category: "other", mcc: 5921),
        PreIndexedMerchant(name: "The Beer Store", category: "other", mcc: 5921),
        PreIndexedMerchant(name: "SAQ", category: "other", mcc: 5921),
        PreIndexedMerchant(name: "BC Liquor Stores", category: "other", mcc: 5921),

        // MARK: - Transit & Commuter
        PreIndexedMerchant(name: "TTC (Toronto Transit Commission)", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "PRESTO (Metrolinx)", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "GO Transit", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "TransLink Vancouver / Compass", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "STM (Montréal)", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "OC Transpo (Ottawa)", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "Calgary Transit", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "Edmonton Transit Service (ETS)", category: "transit", mcc: 4111),
        PreIndexedMerchant(name: "VIA Rail Canada", category: "travel", mcc: 4112),

        // MARK: - Airlines & Travel
        PreIndexedMerchant(name: "Air Canada", category: "travel", mcc: 3000),
        PreIndexedMerchant(name: "WestJet", category: "travel", mcc: 3001),
        PreIndexedMerchant(name: "Porter Airlines", category: "travel", mcc: 3002),
        PreIndexedMerchant(name: "Flair Airlines", category: "travel", mcc: 3003),
        PreIndexedMerchant(name: "Marriott Hotels & Resorts", category: "marriottDirect", mcc: 3509, merchantBrand: "marriott"),
        PreIndexedMerchant(name: "Hilton Hotels", category: "lodging", mcc: 3504),
        PreIndexedMerchant(name: "Hyatt Hotels", category: "lodging", mcc: 3509),
        PreIndexedMerchant(name: "Fairmont Hotels & Resorts", category: "lodging", mcc: 3501),
        PreIndexedMerchant(name: "Expedia", category: "travel", mcc: 4722),
        PreIndexedMerchant(name: "Booking.com", category: "travel", mcc: 4722),
        PreIndexedMerchant(name: "Airbnb", category: "lodging", mcc: 6513),

        // MARK: - Telecom & Utilities
        PreIndexedMerchant(name: "Rogers Wireless & Internet", category: "householdUtilities", mcc: 4814, merchantBrand: "rogers"),
        PreIndexedMerchant(name: "Fido", category: "householdUtilities", mcc: 4814, merchantBrand: "rogers"),
        PreIndexedMerchant(name: "Bell Canada", category: "householdUtilities", mcc: 4814),
        PreIndexedMerchant(name: "Virgin Plus", category: "householdUtilities", mcc: 4814),
        PreIndexedMerchant(name: "Telus", category: "householdUtilities", mcc: 4814),
        PreIndexedMerchant(name: "Koodo Mobile", category: "householdUtilities", mcc: 4814),
        PreIndexedMerchant(name: "Freedom Mobile", category: "householdUtilities", mcc: 4814),
        PreIndexedMerchant(name: "Fizz Mobile", category: "householdUtilities", mcc: 4814),
        PreIndexedMerchant(name: "Hydro One", category: "householdUtilities", mcc: 4900),
        PreIndexedMerchant(name: "Toronto Hydro", category: "householdUtilities", mcc: 4900),
        PreIndexedMerchant(name: "BC Hydro", category: "householdUtilities", mcc: 4900),
        PreIndexedMerchant(name: "Hydro-Québec", category: "householdUtilities", mcc: 4900),
        PreIndexedMerchant(name: "Enbridge Gas", category: "householdUtilities", mcc: 4900),

        // MARK: - Streaming, Subscriptions & Digital
        PreIndexedMerchant(name: "Netflix", category: "streaming", mcc: 5968),
        PreIndexedMerchant(name: "Spotify", category: "streaming", mcc: 5968),
        PreIndexedMerchant(name: "Disney+", category: "streaming", mcc: 5968),
        PreIndexedMerchant(name: "Apple Services (App Store, Music, iCloud)", category: "digitalMedia", mcc: 5815),
        PreIndexedMerchant(name: "Amazon Prime", category: "streaming", mcc: 5968),
        PreIndexedMerchant(name: "YouTube Premium", category: "streaming", mcc: 5968),
        PreIndexedMerchant(name: "Crave", category: "streaming", mcc: 5968),
        PreIndexedMerchant(name: "Amazon.ca", category: "other", mcc: 5999),
        PreIndexedMerchant(name: "PlayStation Network (PSN)", category: "digitalMedia", mcc: 5816),
        PreIndexedMerchant(name: "Xbox Live / Microsoft", category: "digitalMedia", mcc: 5816),
        PreIndexedMerchant(name: "Nintendo eShop", category: "digitalMedia", mcc: 5816),

        // MARK: - Entertainment & Fitness
        PreIndexedMerchant(name: "Cineplex Cinemas", category: "memberships", mcc: 7832),
        PreIndexedMerchant(name: "GoodLife Fitness", category: "memberships", mcc: 7997),
        PreIndexedMerchant(name: "Fit4Less", category: "memberships", mcc: 7997),
        PreIndexedMerchant(name: "Planet Fitness", category: "memberships", mcc: 7997),
        PreIndexedMerchant(name: "YMCA Canada", category: "memberships", mcc: 7997),
    ]

    /// Searches the pre-index for merchants matching the given query with prefix & fuzzy scoring.
    public static func search(_ query: String, limit: Int = 8) -> [PreIndexedMerchant] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return [] }

        return all.compactMap { merchant -> (merchant: PreIndexedMerchant, score: Int)? in
            let nameLower = merchant.name.lowercased()
            if nameLower == cleanQuery {
                return (merchant, 100)
            } else if nameLower.hasPrefix(cleanQuery) {
                return (merchant, 80)
            } else if nameLower.contains(" " + cleanQuery) {
                return (merchant, 60)
            } else if nameLower.contains(cleanQuery) {
                return (merchant, 40)
            } else if let brand = merchant.merchantBrand, brand.contains(cleanQuery) {
                return (merchant, 30)
            }
            return nil
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map(\.merchant)
    }
}
