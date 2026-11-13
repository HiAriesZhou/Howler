import Foundation

/// `howler://capture` starts the same interactive capture as the keyboard shortcut.
/// The link has no room for a question, image or other parameter: anything extra is ignored.
public enum CaptureLink {
    public static func requestsCapture(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "howler" else { return false }
        guard url.host?.lowercased() == "capture" else { return false }
        guard url.port == nil, url.user == nil, url.password == nil else { return false }
        guard url.query == nil, url.fragment == nil else { return false }
        return url.path.isEmpty || url.path == "/"
    }
}

/// Holds a capture request that may arrive before the letter is ready to start one.
public struct CaptureLinkGate {
    private var requested = false
    private var ready = false

    public init() {}

    /// Returns whether a capture should start now.
    public mutating func receive<S: Sequence>(_ urls: S) -> Bool where S.Element == URL {
        guard urls.contains(where: CaptureLink.requestsCapture) else { return false }
        requested = true
        return take()
    }

    /// Returns whether a capture requested earlier should start now.
    public mutating func becomeReady() -> Bool {
        ready = true
        return take()
    }

    private mutating func take() -> Bool {
        guard ready, requested else { return false }
        requested = false
        return true
    }
}
