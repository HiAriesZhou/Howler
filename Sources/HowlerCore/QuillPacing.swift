import Foundation

/// How fast the quill writes. Network deltas arrive in uneven bursts; the panel reveals
/// them at a smooth handwriting pace that speeds up as the backlog grows, so the ink
/// never lags the stream by more than a fraction of a second.
public enum QuillPacing {
    /// Characters per second when the quill has nearly caught up.
    public static let minimumSpeed: Double = 60
    /// Time constant for draining a backlog.
    public static let catchUpTime: Double = 0.35

    /// The next reveal position, in characters, after `elapsed` seconds.
    public static func advance(_ progress: Double, toward target: Int, elapsed: TimeInterval) -> Double {
        let goal = Double(target)
        let backlog = goal - progress
        guard backlog > 0 else { return goal }
        let speed = max(minimumSpeed, backlog / catchUpTime)
        return min(goal, progress + speed * max(0, elapsed))
    }
}
