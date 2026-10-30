import Foundation
import XCTest

final class ReleaseSigningTests: XCTestCase {
    /// Execute the actual workflow's import preflight with no credentials. Its early
    /// exit must protect tagged releases while allowing ordinary ad-hoc builds.
    func testMissingCertificateRejectsTagsButAllowsOrdinaryBuilds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/build.yml"))
        let step = try XCTUnwrap(workflow.components(separatedBy: "      - name: Import signing certificate").last)
            .components(separatedBy: "      - name: Build app bundle")[0]
        let body = try XCTUnwrap(step.components(separatedBy: "        run: |\n").last)
            .components(separatedBy: "\n").map { String($0.dropFirst(10)) }.joined(separator: "\n")
        func run(_ ref: String) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-e", "-u", "-o", "pipefail", "-c", body]
            process.environment = ["PATH": "/usr/bin:/bin", "GITHUB_REF": ref, "CERT_P12_BASE64": ""]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        XCTAssertEqual(try run("refs/heads/fixture"), 0)
        XCTAssertNotEqual(try run("refs/tags/v0.1.99"), 0)
    }
}
