import Foundation

/// What one reward currency is worth, keyed in owner state and the catalogue by `programId`.
///
/// A sum type rather than a flattened struct of optional factors, for the same reason `Earn` is
/// one: CT Money's usability discount and CRO's hold-risk factor are different *models*, not
/// different values of one model. Flattening them into anonymous factors would destroy the
/// disclosure the valuation UI depends on — point values are disclosed assumptions, not facts,
/// and an owner has to be able to see which assumption is being made.
///
/// Deliberately NOT an expression language. A condition encoded as a string ("croHandling ==
/// autoSell") would need a parser, and the parser would be code — moving the closed set rather
/// than opening it. Model-specific behaviour stays in `Scorer`, keyed by case.
public enum ProgramValuation: Equatable, Sendable {
    case points(PointValuation)
    case cashback(CashBackValuation)
    case ctMoney(CtMoneyValuation)
    case cro(CroValuation)
}

extension ProgramValuation: Codable {
    private enum ModelKey: String, CodingKey { case model }

    /// The discriminator and the payload share one JSON object: `model` is read from this type's
    /// own container, then the payload struct decodes from the *same* decoder. Encoding mirrors
    /// it. This is why no payload struct may own a `model` key — see `CroValuation.redemptionModel`.
    public init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: ModelKey.self)
        switch try keyed.decode(String.self, forKey: .model) {
        case "points":   self = .points(try PointValuation(from: decoder))
        case "cashback": self = .cashback(try CashBackValuation(from: decoder))
        case "ctMoney":  self = .ctMoney(try CtMoneyValuation(from: decoder))
        case "cro":      self = .cro(try CroValuation(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .model, in: keyed,
                debugDescription: "unknown valuation model: \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: ModelKey.self)
        switch self {
        case .points(let v):   try keyed.encode("points", forKey: .model);   try v.encode(to: encoder)
        case .cashback(let v): try keyed.encode("cashback", forKey: .model); try v.encode(to: encoder)
        case .ctMoney(let v):  try keyed.encode("ctMoney", forKey: .model);  try v.encode(to: encoder)
        case .cro(let v):      try keyed.encode("cro", forKey: .model);      try v.encode(to: encoder)
        }
    }
}

/// Catalogue-shipped default valuations, keyed by `programId`.
///
/// Exists so that adding a rewards program is one data edit rather than two. Without defaults a
/// new program has to be valued in the catalogue *and* in every owner-state file that will ever
/// see it — which is how sixteen catalogue programIds came to face six valuations.
///
/// `defaults` is deliberately allowed to be incomplete: a program with no default and no owner
/// override has no honest number, and inventing one is worse than admitting it. Callers must
/// treat a missing key as "no valuation" — note that `Scorer.valueCad` still answers 0.0 for one
/// today, which is the half of this defect that remains open.
public struct ProgramCatalogue: Codable, Equatable, Sendable {
    public var programsVersion: String
    public var defaults: [String: ProgramValuation]

    public init(programsVersion: String = "1.0", defaults: [String: ProgramValuation] = [:]) {
        self.programsVersion = programsVersion
        self.defaults = defaults
    }
}
