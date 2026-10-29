import Foundation

/// The "new issue" page on GitHub with the feedback form, its facts filled in from the
/// query (GitHub issue forms prefill fields by id; see .github/ISSUE_TEMPLATE/feedback.yml).
/// Nothing is sent: the browser opens the page and the person decides what to submit.
public enum FeedbackLink {
    public static func url(project: String, version: String, macOS: String, architecture: String) -> URL {
        var components = URLComponents(string: project + "/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "feedback.yml"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "macos", value: macOS),
            URLQueryItem(name: "arch", value: architecture),
        ]
        return components.url!
    }
}
