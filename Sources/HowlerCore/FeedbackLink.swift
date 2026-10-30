import Foundation

/// The "new issue" page on GitHub with the feedback form, its facts filled in from the
/// query (GitHub issue forms prefill fields by id; see .github/ISSUE_TEMPLATE/feedback.yml).
/// Opening the page sends these query fields to GitHub; creating the issue still
/// requires the person to submit the form in their browser.
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
