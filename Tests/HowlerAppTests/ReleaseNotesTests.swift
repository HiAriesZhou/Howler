import Foundation
import XCTest

final class ReleaseNotesTests: XCTestCase {
    private struct Result {
        let status: Int32
        let appcast: String
        let publishedNotes: String
        let calls: String
    }

    /// Run the real publish step with local gh/signing substitutes, without contacting GitHub.
    private func publish(existing: Bool, includeNotes: Bool = true) throws -> Result {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let workflow = try String(contentsOf: root.appendingPathComponent(".github/workflows/build.yml"))
        let step = try XCTUnwrap(workflow.components(separatedBy: "      - name: Publish release").last)
        let body = try XCTUnwrap(step.components(separatedBy: "        run: |\n").last)
            .components(separatedBy: "\n").map { String($0.dropFirst(10)) }.joined(separator: "\n")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["scripts", "build", "bin", "docs/releases"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        func write(_ text: String, _ path: String, executable: Bool = false) throws {
            let url = directory.appendingPathComponent(path)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        try write("""
        APP_NAME="Howler"
        VERSION="0.1.99"
        BUILD_NUMBER="99"
        MIN_MACOS="14.0"
        SPARKLE_FEED_URL="https://example.invalid/releases/latest/download/appcast.xml"
        """, "app.config")
        try write("fixture archive", "build/Howler.zip")
        let notes = "## What's Changed\n\n* A visible reminder for available updates.\n* Install and restart from one Update button.\n"
        if includeNotes { try write(notes, "docs/releases/0.1.99.md") }
        try write(try String(contentsOf: root.appendingPathComponent("scripts/appcast.sh")), "scripts/appcast.sh", executable: true)
        try write("""
        #!/bin/bash
        cat >/dev/null
        echo 'sparkle:edSignature="fixture-signature" length="15"'
        """, "bin/sign-update", executable: true)
        try write("""
        #!/bin/bash
        echo "$*" >> "$FIXTURE_ROOT/calls"
        if [[ "$1 $2" == "release view" ]]; then
            [[ "$FIXTURE_EXISTING" == 1 ]] || exit 1
            echo '* feat: old technical title'
        elif [[ "$1" == api ]]; then
            echo '* feat: generated technical title'
        else
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == --notes-file ]]; then
                    cp "$2" "$FIXTURE_ROOT/published-notes"
                    break
                fi
                shift
            done
        fi
        """, "bin/gh", executable: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-e", "-u", "-o", "pipefail", "-c", body]
        process.currentDirectoryURL = directory
        process.environment = ["PATH": directory.appendingPathComponent("bin").path + ":/usr/bin:/bin",
                               "FIXTURE_ROOT": directory.path, "FIXTURE_EXISTING": existing ? "1" : "0",
                               "GITHUB_REF_NAME": "v0.1.99", "GITHUB_REPOSITORY": "fixture/howler", "RUNNER_TEMP": directory.path,
                               "SPARKLE_ED_PRIVATE_KEY": "fixture-only",
                               "SIGN_UPDATE": directory.appendingPathComponent("bin/sign-update").path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        func read(_ path: String) -> String { (try? String(contentsOf: directory.appendingPathComponent(path))) ?? "" }
        return Result(status: process.terminationStatus, appcast: read("build/appcast.xml"),
                      publishedNotes: read("published-notes"), calls: read("calls"))
    }

    func testNewReleaseAndUpdaterUseTheSameAuthoredNotes() throws {
        let result = try publish(existing: false)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.appcast.contains("A visible reminder for available updates."))
        XCTAssertTrue(result.appcast.contains("Install and restart from one Update button."))
        XCTAssertTrue(result.publishedNotes.contains("A visible reminder for available updates."))
        XCTAssertFalse(result.appcast.contains("technical title"))
        XCTAssertFalse(result.calls.contains("generate-notes"))
    }

    func testRerunningReleaseRefreshesBothSurfacesFromAuthoredNotes() throws {
        let result = try publish(existing: true)
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.appcast.contains("Install and restart from one Update button."))
        XCTAssertTrue(result.publishedNotes.contains("Install and restart from one Update button."))
        XCTAssertFalse(result.appcast.contains("technical title"))
    }

    func testMissingNotesStopsBeforeAnyGitHubMutation() throws {
        let result = try publish(existing: false, includeNotes: false)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(result.calls.contains("release create"))
        XCTAssertFalse(result.calls.contains("release upload"))
        XCTAssertFalse(result.calls.contains("release edit"))
    }
}
