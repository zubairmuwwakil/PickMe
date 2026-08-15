public enum CapMath {
    /// Splits a purchase into the portion still earning the accelerated rate and the post-cap portion.
    public static func split(amount: Double, capLimit: Double, usage: Double)
        -> (inCap: Double, overCap: Double) {
        let room = max(0, capLimit - usage)
        let inCap = min(amount, room)
        return (inCap, amount - inCap)
    }
}
