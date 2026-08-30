public enum CapMath {
    /// Splits a purchase into the portion still earning the accelerated rate and the post-cap portion.
    public static func split(amount: Double, capLimit: Double, usage: Double)
        -> (inCap: Double, overCap: Double) {
        let room = max(0, capLimit - usage)
        let inCap = min(amount, room)
        return (inCap, amount - inCap)
    }

    /// Splits a purchase against multiple racing caps. The bottleneck cap (the one with the least room)
    /// constrains the in-cap amount.
    public static func splitMulti(amount: Double, caps: [(limit: Double, usage: Double)])
        -> (inCap: Double, overCap: Double) {
        let minRoom = caps.map { max(0, $0.limit - $0.usage) }.min() ?? Double.infinity
        let inCap = min(amount, minRoom)
        return (inCap, amount - inCap)
    }
}
