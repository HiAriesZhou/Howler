import Foundation
import XCTest

final class HomebrewTests: XCTestCase {
    private final class Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/homebrew.sh")
        let tag = "v0.1.13"
        var digest = ""

        init() throws {
            for path in ["bin", "tmp", "Howler.app/Contents/MacOS"] {
                try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
            }
            try write("fixture DMG bytes", "download.dmg")
            let hash = try runProgram("/usr/bin/shasum", ["-a", "256", root.appendingPathComponent("download.dmg").path])
            digest = String(hash.output.prefix(64))
            try write(tag, "latest")
            try release()
            try base(version: "0.1.12")
            try write("[]", "prs.json")
            try write(#"{"files":[{"filename":"Casks/howler.rb","status":"modified"}]}"#, "compare.json")
            let info: [String: String] = ["CFBundleShortVersionString": "0.1.13", "CFBundleIdentifier": "com.hiarieszhou.howler"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: root.appendingPathComponent("Howler.app/Contents/Info.plist"))
            try write("fixture executable", "Howler.app/Contents/MacOS/Howler")
            try write(#"""
            #!/bin/bash
            set -euo pipefail
            [[ "$1 $2" == 'api --method' ]] || exit 91
            method="$3" endpoint="$4" payload="${6:-}"
            echo "$method $endpoint" >> "$FIXTURE_ROOT/calls"
            if [[ "$method" != GET && "$method" == "${FIXTURE_FAIL_METHOD:-}" ]]; then exit 7; fi
            case "$method $endpoint" in
              'GET repos/HiAriesZhou/Howler/releases/latest')
                [[ "${FIXTURE_FAIL_LATEST:-}" != 1 ]] || exit 9
                if [[ "${FIXTURE_FAIL_LATEST:-}" == json ]]; then echo 'invalid JSON'; exit; fi
                jq -n --arg tag "$(cat "$FIXTURE_ROOT/latest")" '{tag_name:$tag}' ;;
              'GET repos/HiAriesZhou/Howler/releases/tags/'*) cat "$FIXTURE_ROOT/release.json" ;;
              'GET repos/HiAriesZhou/homebrew-tap/git/ref/heads/main')
                jq -n --arg sha "$(cat "$FIXTURE_ROOT/main.ref" 2>/dev/null || echo base)" '{object:{sha:$sha}}' ;;
              'GET repos/HiAriesZhou/homebrew-tap/contents/Casks/howler.rb?ref=base')
                cat "$FIXTURE_ROOT/initial.json" 2>/dev/null || cat "$FIXTURE_ROOT/base.json" ;;
              'GET repos/HiAriesZhou/homebrew-tap/contents/Casks/howler.rb?ref=advanced') cat "$FIXTURE_ROOT/base.json" ;;
              'GET repos/HiAriesZhou/homebrew-tap/contents/Casks/howler.rb?ref=updated') cat "$FIXTURE_ROOT/branch.json" ;;
              'GET repos/HiAriesZhou/homebrew-tap/pulls?'*) cat "$FIXTURE_ROOT/prs.json" ;;
              'GET repos/HiAriesZhou/homebrew-tap/git/matching-refs/heads/'*)
                if [[ -f "$FIXTURE_ROOT/branch.ref" ]]; then
                  jq -n --arg ref "refs/heads/${endpoint##*heads/}" --arg sha "$(cat "$FIXTURE_ROOT/branch.ref")" '[{ref:$ref,object:{sha:$sha}}]'
                else echo '[]'; fi ;;
              'POST repos/HiAriesZhou/homebrew-tap/git/refs')
                cp "$payload" "$FIXTURE_ROOT/ref-request.json"
                cp "$FIXTURE_ROOT/base.json" "$FIXTURE_ROOT/initial.json"
                jq -r '.sha' "$payload" > "$FIXTURE_ROOT/branch.ref"
                echo '{}' ;;
              'PUT repos/HiAriesZhou/homebrew-tap/contents/Casks/howler.rb')
                cp "$payload" "$FIXTURE_ROOT/update-request.json"
                jq '{content:.content,sha:"newblob"}' "$payload" > "$FIXTURE_ROOT/branch.json"
                echo 'updated' > "$FIXTURE_ROOT/branch.ref"
                echo '{}' ;;
              'GET repos/HiAriesZhou/homebrew-tap/compare/base...advanced') echo '{"status":"ahead","behind_by":0}' ;;
              'GET repos/HiAriesZhou/homebrew-tap/compare/'*) cat "$FIXTURE_ROOT/compare.json" ;;
              'POST repos/HiAriesZhou/homebrew-tap/pulls')
                cp "$payload" "$FIXTURE_ROOT/pr-request.json"
                echo '[{"state":"open","html_url":"https://example.invalid/pull/1"}]' > "$FIXTURE_ROOT/prs.json"
                echo '{"html_url":"https://example.invalid/pull/1"}' ;;
              *) echo "unexpected fixture API: $method $endpoint" >&2; exit 92 ;;
            esac
            """#, "bin/gh", executable: true)
            try write(#"""
            #!/bin/bash
            set -euo pipefail
            echo "curl" >> "$FIXTURE_ROOT/tools"
            while [[ $# -gt 0 ]]; do
              if [[ "$1" == -o ]]; then cp "$FIXTURE_ROOT/download.dmg" "$2"; exit; fi
              shift
            done
            exit 93
            """#, "bin/curl", executable: true)
            try write(#"""
            #!/bin/bash
            set -euo pipefail
            echo "hdiutil $1" >> "$FIXTURE_ROOT/tools"
            if [[ "$1" == attach ]]; then
              while [[ $# -gt 0 ]]; do
                if [[ "$1" == -mountpoint ]]; then cp -R "$FIXTURE_ROOT/Howler.app" "$2/Howler.app"; exit; fi
                shift
              done
              exit 94
            fi
            [[ "$1" == detach ]]
            """#, "bin/hdiutil", executable: true)
            for tool in ["codesign", "spctl", "xcrun", "lipo"] {
                try write("""
                #!/bin/bash
                echo '\(tool)' >> "$FIXTURE_ROOT/tools"
                [[ "${FIXTURE_FAIL_TOOL:-}" != '\(tool)' ]] || exit 8
                \(tool == "lipo" ? "echo 'x86_64 arm64'" : "exit 0")
                """, "bin/\(tool)", executable: true)
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }
        func write(_ text: String, _ path: String, executable: Bool = false) throws {
            let url = root.appendingPathComponent(path)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        func read(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path))) ?? "" }
        func json(_ path: String) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(path))) as? [String: Any])
        }
        func save(_ value: [String: Any], _ path: String) throws {
            try JSONSerialization.data(withJSONObject: value).write(to: root.appendingPathComponent(path))
        }
        func wrapContent(_ path: String, lineEnding: String) throws {
            var response = try json(path)
            let characters = Array(try XCTUnwrap(response["content"] as? String))
            response["content"] = stride(from: 0, to: characters.count, by: 60).map {
                String(characters[$0..<min($0 + 60, characters.count)])
            }.joined(separator: lineEnding) + lineEnding
            try save(response, path)
        }
        func release(draft: Bool = false, prerelease: Bool = false, missing: String? = nil, checksum: String? = nil) throws {
            let names: [String] = ["Howler.dmg", "Howler.zip", "appcast.xml"]
            let assets = names.filter { $0 != missing }.map {
                ["name": $0, "state": "uploaded", "size": 17, "digest": "sha256:\(checksum ?? digest)"] as [String: Any]
            }
            try save(["tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": assets], "release.json")
        }
        func base(version: String, checksum: String? = nil) throws {
            let cask = """
            cask "howler" do
              version "\(version)"
              sha256 "\(checksum ?? String(repeating: "a", count: 64))"

              url "https://example.invalid/v#{version}/Howler.dmg"
              auto_updates true
              depends_on macos: :sonoma
              app "Howler.app"
            end

            """
            try write(cask, "base.rb")
            try save(["content": Data(cask.utf8).base64EncodedString(), "sha": "oldblob"], "base.json")
        }
        func manifest() throws {
            try save(["tag": tag, "version": "0.1.13", "sha256": digest], "manifest.json")
        }
        func run(_ mode: String, tag: String? = nil, extra: [String: String] = [:]) throws -> (status: Int32, output: String) {
            var env = ["PATH": root.appendingPathComponent("bin").path + ":/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin",
                       "TMPDIR": root.appendingPathComponent("tmp").path, "FIXTURE_ROOT": root.path, "GH_TOKEN": "fixture-only"]
            env.merge(extra) { _, new in new }
            let args = [script.path, mode] + (mode == "verify" ? [tag ?? self.tag] : []) + [root.appendingPathComponent("manifest.json").path]
            return try runProgram("/bin/bash", args, env: env)
        }
        private func runProgram(_ binary: String, _ args: [String], env: [String: String]? = nil) throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = args
            process.environment = env
            let log = root.appendingPathComponent(UUID().uuidString + ".log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close() }
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, try String(contentsOf: log))
        }
    }

    func testVerificationChecksDownloadedBytesAndNeverWritesToGitHub() throws {
        let f = try Fixture()
        let result = try f.run("verify")
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(try f.json("manifest.json")["sha256"] as? String, f.digest)
        XCTAssertTrue(f.read("tools").contains("codesign"))
        XCTAssertTrue(f.read("tools").contains("hdiutil detach"))
        XCTAssertFalse(f.read("calls").contains("POST"))
        XCTAssertFalse(f.read("calls").contains("PUT"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("tmp").path), [])
    }

    func testInvalidTagsAndIncompleteOrUnstableReleasesStopBeforeDownload() throws {
        let f = try Fixture()
        XCTAssertNotEqual(try f.run("verify", tag: "v0.1.13;echo injected").status, 0)
        for (draft, prerelease, missing) in [(true, false, nil), (false, true, nil), (false, false, "appcast.xml")] as [(Bool, Bool, String?)] {
            try f.release(draft: draft, prerelease: prerelease, missing: missing)
            XCTAssertNotEqual(try f.run("verify").status, 0)
        }
        XCTAssertFalse(f.read("tools").contains("curl"))
    }

    func testChecksumVersionAndSignatureFailuresProduceNoManifestAndCleanMounts() throws {
        for failure in ["checksum", "version", "codesign", "xcrun", "spctl", "lipo"] {
            let f = try Fixture()
            if failure == "checksum" { try f.release(checksum: String(repeating: "0", count: 64)) }
            if failure == "version" {
                try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "0.1.12"], format: .xml, options: 0)
                    .write(to: f.root.appendingPathComponent("Howler.app/Contents/Info.plist"))
            }
            let result = try f.run("verify", extra: ["FIXTURE_FAIL_TOOL": failure])
            XCTAssertNotEqual(result.status, 0, failure)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("manifest.json").path), failure)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.root.appendingPathComponent("tmp").path), [], failure)
        }
    }

    func testUpgradeChangesOnlyTwoStanzasAndRerunReusesThePR() throws {
        let f = try Fixture()
        try f.manifest()
        let first = try f.run("pr")
        XCTAssertEqual(first.status, 0, first.output)
        let request = try f.json("update-request.json")
        let content = try XCTUnwrap(String(data: try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(request["content"] as? String))), encoding: .utf8))
        let expected = f.read("base.rb").replacingOccurrences(of: "0.1.12", with: "0.1.13")
            .replacingOccurrences(of: String(repeating: "a", count: 64), with: f.digest)
        XCTAssertEqual(content, expected)
        let pr = try f.json("pr-request.json")
        XCTAssertEqual(pr["base"] as? String, "main")
        XCTAssertEqual(pr["head"] as? String, "automation/howler-0.1.13")
        XCTAssertTrue((pr["body"] as? String ?? "").contains("\n\nSHA-256:"))
        let second = try f.run("pr")
        XCTAssertEqual(second.status, 0, second.output)
        XCTAssertEqual(f.read("calls").components(separatedBy: "POST repos/HiAriesZhou/homebrew-tap/pulls").count - 1, 1)
        XCTAssertEqual(f.read("calls").components(separatedBy: "PUT ").count - 1, 1)
    }

    func testRetryAfterBranchCreationCompletesWithoutDuplicateBranch() throws {
        let f = try Fixture()
        try f.manifest()
        XCTAssertNotEqual(try f.run("pr", extra: ["FIXTURE_FAIL_METHOD": "PUT"]).status, 0)
        let retry = try f.run("pr")
        XCTAssertEqual(retry.status, 0, retry.output)
        XCTAssertEqual(f.read("calls").components(separatedBy: "POST repos/HiAriesZhou/homebrew-tap/git/refs").count - 1, 1)
    }

    func testRetryAfterCommitCreatesTheMissingPR() throws {
        let f = try Fixture()
        try f.manifest()
        XCTAssertEqual(try f.run("pr").status, 0)
        try f.write("[]", "prs.json")
        let retry = try f.run("pr")
        XCTAssertEqual(retry.status, 0, retry.output)
        XCTAssertEqual(f.read("calls").components(separatedBy: "PUT ").count - 1, 1)
    }

    func testCurrentCaskDecodesWrappedGitHubContentsWithoutWriting() throws {
        for lineEnding in ["\n", "\r\n"] {
            let f = try Fixture()
            try f.manifest()
            try f.base(version: "0.1.13", checksum: f.digest)
            try f.wrapContent("base.json", lineEnding: lineEnding)
            XCTAssertTrue((try f.json("base.json")["content"] as? String ?? "").contains(lineEnding))

            let result = try f.run("pr")
            XCTAssertEqual(result.status, 0, result.output)
            XCTAssertTrue(result.output.contains("Howler 0.1.13 is already in the tap."))
            XCTAssertFalse(f.read("calls").contains("POST"))
            XCTAssertFalse(f.read("calls").contains("PUT"))
        }
    }

    func testRetryDecodesWrappedGitHubBranchContentsWithoutWriting() throws {
        for lineEnding in ["\n", "\r\n"] {
            let f = try Fixture()
            try f.manifest()
            let first = try f.run("pr")
            XCTAssertEqual(first.status, 0, first.output)
            try f.wrapContent("branch.json", lineEnding: lineEnding)
            XCTAssertTrue((try f.json("branch.json")["content"] as? String ?? "").contains(lineEnding))
            try f.write("", "calls")

            let retry = try f.run("pr")
            XCTAssertEqual(retry.status, 0, retry.output)
            XCTAssertTrue(retry.output.contains("Existing upgrade PR:"))
            XCTAssertTrue(f.read("calls").contains("contents/Casks/howler.rb?ref=updated"))
            XCTAssertFalse(f.read("calls").contains("POST"))
            XCTAssertFalse(f.read("calls").contains("PUT"))
        }
    }

    func testInterruptedBranchCanResumeAfterUnrelatedMainChanges() throws {
        let f = try Fixture()
        try f.manifest()
        XCTAssertNotEqual(try f.run("pr", extra: ["FIXTURE_FAIL_METHOD": "PUT"]).status, 0)
        try f.write("advanced", "main.ref")
        var current = try f.json("base.json")
        current["sha"] = "advancedblob"
        try f.save(current, "base.json")
        let retry = try f.run("pr")
        XCTAssertEqual(retry.status, 0, retry.output)
        XCTAssertEqual(try f.json("update-request.json")["sha"] as? String, "oldblob")
        XCTAssertEqual(f.read("calls").components(separatedBy: "POST repos/HiAriesZhou/homebrew-tap/git/refs").count - 1, 1)
    }

    func testAPIFailureIsAnErrorRatherThanASuccessfulStaleSkip() throws {
        for mode in ["verify", "pr"] {
            for failure in ["1", "json"] {
                let f = try Fixture()
                try f.manifest()
                let result = try f.run(mode, extra: ["FIXTURE_FAIL_LATEST": failure])
                XCTAssertNotEqual(result.status, 0, result.output)
                XCTAssertFalse(result.output.contains("newer release"))
                XCTAssertFalse(f.read("calls").contains("POST"))
                XCTAssertFalse(f.read("calls").contains("PUT"))
            }
        }
    }

    func testCurrentStaleAndDowngradeCasesDoNotWrite() throws {
        for state in ["current", "stale", "downgrade", "checksum", "asset-replaced"] {
            let f = try Fixture()
            try f.manifest()
            if state == "current" { try f.base(version: "0.1.13", checksum: f.digest) }
            if state == "stale" { try f.write("v0.1.14", "latest") }
            if state == "downgrade" { try f.base(version: "0.1.14") }
            if state == "checksum" { try f.base(version: "0.1.13") }
            if state == "asset-replaced" { try f.release(checksum: String(repeating: "0", count: 64)) }
            let result = try f.run("pr")
            XCTAssertEqual(result.status == 0, state == "current" || state == "stale", result.output)
            XCTAssertFalse(f.read("calls").contains("POST"), state)
            XCTAssertFalse(f.read("calls").contains("PUT"), state)
        }
    }

    func testClosedPRAndModifiedBranchesArePreserved() throws {
        for state in ["closed", "modified", "extra-file"] {
            let f = try Fixture()
            try f.manifest()
            XCTAssertEqual(try f.run("pr").status, 0)
            try f.write("", "calls")
            if state == "closed" { try f.write(#"[{"state":"closed"}]"#, "prs.json") }
            if state == "modified" { try f.save(["content": Data("user edits".utf8).base64EncodedString()], "branch.json") }
            if state == "extra-file" { try f.write(#"{"files":[{"filename":"other.rb","status":"modified"}]}"#, "compare.json") }
            XCTAssertNotEqual(try f.run("pr").status, 0, state)
            XCTAssertFalse(f.read("calls").contains("POST"), state)
            XCTAssertFalse(f.read("calls").contains("PUT"), state)
        }
    }

    func testMissingWriteTokenFailsBeforeAnyRequest() throws {
        let f = try Fixture()
        try f.manifest()
        let result = try f.run("pr", extra: ["GH_TOKEN": ""])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("HOMEBREW_TAP_TOKEN"))
        XCTAssertEqual(f.read("calls"), "")
    }
}
