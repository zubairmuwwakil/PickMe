import Foundation

/// What submitting a merchant search field means, independent of which screen sent it.
///
/// Both entry points must answer this the same way, and they did not. `HomeView` trimmed and
/// dropped an empty query; `MerchantConfirmView` forwarded the raw text, so hitting return on an
/// empty search field replaced the nearby list with `Nothing found for “”.` and the owner had to
/// re-run the GPS scan mid-checkout. Before the decomposition that was a silent no-op, because
/// the guard sat ahead of the `.locating` assignment inside the view's own `search`.
enum SearchSubmission {
    /// `nil` when there is nothing to search for. Whitespace is not a query: trimming here also
    /// stops a stray space reaching MapKit as a real lookup, which the original never guarded.
    static func query(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
