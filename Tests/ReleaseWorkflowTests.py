import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


TAG = "v0.1.99"
NAMES = ["Howler.zip", "Howler.dmg", "appcast.xml"]
NOTES = "## What's Changed\n\n* A visible reminder for available updates.\n* Install and restart from one Update button.\n"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def bundle_info(version="0.1.99", build=99, identity="com.example.howler"):
    return {"CFBundleShortVersionString": version, "CFBundleVersion": str(build), "CFBundleIdentifier": identity}


def archive_bytes(info=None, payload=b"original archive"):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr(zipfile.ZipInfo("Howler.app/Contents/Info.plist"), plistlib.dumps(info or bundle_info()))
        archive.writestr(zipfile.ZipInfo("Howler.app/Contents/MacOS/Howler"), payload)
    return output.getvalue()


def feed(version="0.1.99", build=99, archive=None, signature=None):
    archive = archive if archive is not None else archive_bytes(bundle_info(version, build))
    signature = signature or hashlib.sha256(archive).hexdigest()
    return f'''<rss xmlns:sparkle="{NS}"><channel><item>
<sparkle:version>{build}</sparkle:version>
<sparkle:shortVersionString>{version}</sparkle:shortVersionString>
<enclosure url="https://example.invalid/releases/download/v{version}/Howler.zip"
length="{len(archive)}" sparkle:edSignature="{signature}"/>
</item></channel></rss>'''.encode()


def metadata(root, tag, draft=False, build=99):
    directory = root / "remote" / tag
    directory.mkdir(parents=True, exist_ok=True)
    contents = [archive_bytes(bundle_info(tag[1:], build)), json.dumps(bundle_info(tag[1:], build)).encode(), feed(tag[1:], build)]
    assets = []
    for index, (name, data) in enumerate(zip(NAMES, contents)):
        (directory / name).write_bytes(data)
        assets.append({"id": build * 10 + index, "name": name, "size": len(data),
                       "state": "uploaded", "digest": digest(data)})
    return {"id": build, "tag_name": tag, "draft": draft, "prerelease": False,
            "body": "original published notes", "assets": assets}


def mock_gh():
    root = Path(os.environ["FIXTURE_ROOT"])
    args = sys.argv[2:]
    with (root / "calls").open("a") as log:
        log.write(json.dumps(args) + "\n")
    state = json.loads((root / "state.json").read_text())

    def save():
        (root / "state.json").write_text(json.dumps(state))

    def response(data, status=200):
        if "--include" in args:
            print(f"HTTP/2.0 {status} Fixture\nContent-Type: application/json\n")
        if isinstance(data, bytes):
            sys.stdout.flush()
            sys.stdout.buffer.write(data)
        else:
            print(json.dumps(data))
        sys.exit(0 if status == 200 else 1)

    def event(kind):
        with (root / "mutations").open("a") as log:
            tools = (root / "tools").read_text() if (root / "tools").exists() else ""
            log.write(json.dumps({"kind": kind, "release": state["release"], "tools": tools}) + "\n")

    def option(name):
        return args[args.index(name) + 1]

    if args[0] == "api":
        endpoint = next(arg for arg in args[1:] if arg.startswith("repos/"))
        if "/releases/tags/" in endpoint:
            failure = state.get("lookup_error")
            if failure == "transport":
                print("transport error; unrelated upstream text HTTP 404", file=sys.stderr)
                sys.exit(1)
            if failure:
                response({"message": "fixture failure"}, int(failure))
            response(state["release"] or {"message": "Not Found"}, 200 if state["release"] else 404)
        elif "/releases/assets/" in endpoint:
            asset_id = int(endpoint.rsplit("/", 1)[1])
            for release in [state["release"], *state["others"]]:
                if release:
                    for asset in release["assets"]:
                        if asset["id"] == asset_id:
                            if state.get("download_error"):
                                response({"message": "download failed"}, state["download_error"])
                            data = (root / "remote" / release["tag_name"] / asset["name"]).read_bytes()
                            response(data + b"corrupt" if state.get("corrupt_download") else data)
            response({"message": "Not Found"}, 404)
        elif endpoint.endswith("/releases?per_page=100"):
            state["list_reads"] = state.get("list_reads", 0) + 1
            if state["list_reads"] == 2 and state.get("newer_after_upload"):
                state["others"].append(state["newer_after_upload"])
            save()
            if state.get("list_error"):
                response({"message": "list failed"}, state["list_error"])
            if state.get("invalid_list"):
                print("not JSON")
                sys.exit(0)
            releases = [state["release"]] if state["release"] else []
            response([releases, state["others"]])
        raise SystemExit("unexpected API request")
    if args[:2] == ["release", "view"]:
        if state.get("lookup_error") or not state["release"]:
            sys.exit(1)
        print(json.dumps(state["release"]))
        return
    if args[:2] in [["release", "create"], ["release", "upload"], ["release", "edit"]]:
        kind = args[1]
        if kind == "create":
            if state["release"]:
                sys.exit(1)
            state["release"] = {"id": 99, "tag_name": args[2], "draft": True,
                                "prerelease": False, "assets": [], "body": ""}
            event("create draft")
        release = state["release"]
        if "--notes-file" in args:
            release["body"] = Path(option("--notes-file")).read_text()
        if kind in ["create", "upload"]:
            directory = root / "remote" / TAG
            directory.mkdir(parents=True, exist_ok=True)
            for name in NAMES:
                path = next((Path(arg) for arg in args if arg.endswith("/" + name)), None)
                if path is not None:
                    data = path.read_bytes()
                    (directory / name).write_bytes(data)
                    release["assets"] = [asset for asset in release["assets"] if asset["name"] != name]
                    release["assets"].append({"id": 990 + NAMES.index(name), "name": name,
                                              "size": len(data), "state": "uploaded", "digest": digest(data)})
                    if state.get("upload_error"):
                        event("partial upload")
                        if kind == "create" and "--draft" not in args:
                            state["release"] = None
                            event("cleanup draft")
                        save()
                        sys.exit(1)
            if state.get("bad_uploaded_digest") and release["assets"]:
                release["assets"][0]["digest"] = "sha256:" + "0" * 64
        if "--draft=false" in args or kind == "create" and "--draft" not in args:
            release["draft"] = False
        event(kind)
        if "--latest" in args:
            state["latest"] = TAG
        save()
        return
    raise SystemExit("unexpected gh command")


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.source = Path(__file__).resolve().parents[1]
        for name in ["scripts", "build", "bin", "docs/releases"]:
            (self.root / name).mkdir(parents=True)
        for name in ["appcast.sh", "release.py"]:
            if (self.source / "scripts" / name).exists():
                shutil.copy(self.source / "scripts" / name, self.root / "scripts" / name)
        (self.root / "app.config").write_text('''APP_NAME="Howler"
BUNDLE_ID="com.example.howler"
VERSION="0.1.99"
BUILD_NUMBER="99"
MIN_MACOS="14.0"
SPARKLE_FEED_URL="https://example.invalid/releases/latest/download/appcast.xml"
''')
        self.fresh_archive = archive_bytes(payload=b"freshly signed archive")
        (self.root / "build/Howler.zip").write_bytes(self.fresh_archive)
        (self.root / "build/Howler.dmg").write_bytes(json.dumps(bundle_info()).encode())
        (self.root / "docs/releases/0.1.99.md").write_text(NOTES)
        self.state = {"release": None, "others": [], "latest": None}
        self.write_tool("gh", 'exec "$FIXTURE_PYTHON" "$FIXTURE_TEST" --gh "$@"')
        for tool in ["ditto", "hdiutil"]:
            self.write_tool(tool, 'exec "$FIXTURE_PYTHON" "$FIXTURE_TEST" --tool ' + tool + ' "$@"')
        self.write_tool("sign-update", '''if [[ "$*" == *--verify* ]]; then
  echo "verify $*" >> "$FIXTURE_ROOT/tools"
  [[ "${FIXTURE_BAD_SIGNATURE:-0}" != 1 ]] || exit 1
  for arg in "$@"; do if [[ "$arg" == *.zip ]]; then zip="$arg"; fi; done
  actual="$(shasum -a 256 "$zip" | awk '{print $1}')"
  [[ "${@: -1}" == "$actual" ]]
else
  cat >/dev/null
  echo sign >> "$FIXTURE_ROOT/tools"
  for arg in "$@"; do if [[ "$arg" == *.zip ]]; then zip="$arg"; fi; done
  echo "sparkle:edSignature=\\"$(shasum -a 256 "$zip" | awk '{print $1}')\\" length=\\"$(wc -c < "$zip" | tr -d ' ')\\""
fi''')
        for tool in ["xcrun", "spctl", "codesign"]:
            self.write_tool(tool, f'''echo '{tool} '"$*" >> "$FIXTURE_ROOT/tools"
[[ "{tool}" != xcrun || "$*" != *.dmg || "${{FIXTURE_BAD_TICKET:-0}}" != 1 ]] || exit 1
''')

    def write_tool(self, name, body):
        path = self.root / "bin" / name
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body + "\n")
        path.chmod(0o755)

    def run_publish(self, **extra):
        (self.root / "state.json").write_text(json.dumps(self.state))
        workflow = (self.source / ".github/workflows/build.yml").read_text()
        step = workflow.split("      - name: Publish release\n", 1)[1]
        run = step.split("        run: |\n", 1)[1]
        lines = []
        for line in run.splitlines():
            if line and not line.startswith("          "):
                break
            lines.append(line[10:])
        env = {"PATH": str(self.root / "bin") + ":" + str(Path(sys.executable).parent) + ":/usr/bin:/bin",
               "FIXTURE_ROOT": str(self.root), "FIXTURE_PYTHON": sys.executable,
               "FIXTURE_TEST": str(Path(__file__).resolve()), "GITHUB_REF_NAME": TAG,
               "GITHUB_REPOSITORY": "fixture/howler", "RUNNER_TEMP": str(self.root),
               "SPARKLE_ED_PRIVATE_KEY": "fixture-only", "SIGN_UPDATE": str(self.root / "bin/sign-update")}
        env.update(extra)
        result = subprocess.run(["/bin/bash", "-euo", "pipefail", "-c", "\n".join(lines)],
                                cwd=self.root, env=env, capture_output=True, text=True, timeout=30)
        self.state = json.loads((self.root / "state.json").read_text())
        return result

    def records(self, name):
        path = self.root / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_new_release_stays_draft_until_all_assets_are_verified(self):
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = self.records("mutations")
        self.assertTrue(mutations[0]["release"]["draft"])
        self.assertEqual({asset["name"] for asset in mutations[-1]["release"]["assets"]}, set(NAMES))
        self.assertFalse(self.state["release"]["draft"])
        self.assertEqual(self.state["latest"], TAG)
        self.assertEqual(self.state["release"]["body"], NOTES)
        self.assertIn("verify ", mutations[-1]["tools"])
        self.assertIn("xcrun stapler validate", mutations[-1]["tools"])
        self.assertIn("Install and restart", (self.root / "remote" / TAG / "appcast.xml").read_text())
        self.assertIn("verify ", (self.root / "tools").read_text())
        self.assertIn("xcrun stapler validate", (self.root / "tools").read_text())

    def test_draft_retry_replaces_partial_batch(self):
        self.state["release"] = metadata(self.root, TAG, draft=True)
        self.state["release"]["assets"] = self.state["release"]["assets"][:1]
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "remote" / TAG / "Howler.zip").read_bytes(), self.fresh_archive)
        self.assertFalse(self.state["release"]["draft"])
        uploads = [call for call in self.records("calls") if call[:2] == ["release", "upload"]]
        self.assertEqual(len(uploads), 1)
        self.assertIn("--clobber", uploads[0])

    def test_public_retry_verifies_originals_without_mutation_or_signing(self):
        self.state["release"] = metadata(self.root, TAG)
        before = json.dumps(self.state, sort_keys=True)
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.dumps(self.state, sort_keys=True), before)
        self.assertEqual(self.records("mutations"), [])
        tools = (self.root / "tools").read_text()
        self.assertIn("verify ", tools)
        self.assertIn("xcrun stapler validate", tools)
        self.assertNotIn("sign\n", tools)

    def test_old_public_retry_does_not_promote_latest(self):
        self.state["release"] = metadata(self.root, TAG)
        self.state["others"] = [metadata(self.root, "v0.1.100", build=100)]
        self.state["latest"] = "v0.1.100"
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state["latest"], "v0.1.100")
        self.assertEqual(self.records("mutations"), [])

    def test_public_invalid_signature_is_rejected(self):
        self.state["release"] = metadata(self.root, TAG)
        self.assertNotEqual(self.run_publish(FIXTURE_BAD_SIGNATURE="1").returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_public_invalid_dmg_ticket_is_rejected(self):
        self.state["release"] = metadata(self.root, TAG)
        self.assertNotEqual(self.run_publish(FIXTURE_BAD_TICKET="1").returncode, 0)
        self.assertEqual(self.records("mutations"), [])
        self.assertRegex((self.root / "tools").read_text(), r"xcrun stapler validate [^\n]*Howler\.dmg")

    def test_public_incomplete_assets_are_rejected_without_repair(self):
        self.state["release"] = metadata(self.root, TAG)
        self.state["release"]["assets"].pop()
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_public_duplicate_assets_are_rejected(self):
        self.state["release"] = metadata(self.root, TAG)
        self.state["release"]["assets"].append(self.state["release"]["assets"][0])
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_missing_notes_stops_before_mutation(self):
        (self.root / "docs/releases/0.1.99.md").unlink()
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_non_404_lookup_errors_never_create_release(self):
        for failure in [401, 403, 429, 500, "transport"]:
            with self.subTest(failure=failure):
                self.state["lookup_error"] = failure
                self.assertNotEqual(self.run_publish().returncode, 0)
                self.assertEqual(self.records("mutations"), [])

    def test_failed_release_listing_never_mutates(self):
        self.state["list_error"] = 503
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_invalid_release_listing_never_mutates(self):
        self.state["invalid_list"] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_newer_stable_release_on_later_page_blocks_old_tag(self):
        self.state["others"] = [metadata(self.root, "v0.1.100", build=100)]
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_newer_version_requires_higher_build_number(self):
        self.state["others"] = [metadata(self.root, "v0.1.98", build=100)]
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_build_must_exceed_every_published_sparkle_build(self):
        self.state["others"] = [metadata(self.root, "v0.1.97", build=120), metadata(self.root, "v0.1.98", build=98)]
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_legacy_release_without_a_sparkle_feed_keeps_version_guard(self):
        legacy = metadata(self.root, "v0.1.1", build=2)
        legacy["assets"].pop()
        self.state["others"] = [legacy, metadata(self.root, "v0.1.98", build=98)]
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_stable_versions_compare_numerically(self):
        self.state["others"] = [metadata(self.root, "v0.1.9", build=9)]
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state["release"]["draft"])

    def test_unpublished_and_prerelease_versions_do_not_block_stable(self):
        draft = metadata(self.root, "v0.1.101", draft=True, build=101)
        prerelease = metadata(self.root, "v0.1.100", build=100)
        prerelease["prerelease"] = True
        self.state["others"] = [draft, prerelease]
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_tag_config_mismatch_stops_before_mutation(self):
        self.assertNotEqual(self.run_publish(GITHUB_REF_NAME="v0.1.98").returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_upload_failure_leaves_draft_and_is_retryable(self):
        self.state["upload_error"] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertIsNotNone(self.state["release"])
        self.assertTrue(self.state["release"]["draft"])
        self.state.pop("upload_error")
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state["release"]["draft"])

    def test_uploaded_batch_digest_mismatch_never_publishes(self):
        self.state["bad_uploaded_digest"] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertTrue(self.state["release"]["draft"])
        self.assertIsNone(self.state["latest"])

    def test_download_failure_never_repairs_public_assets(self):
        self.state["release"] = metadata(self.root, TAG)
        self.state["download_error"] = 404
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_remote_digest_mismatch_never_repairs_public_assets(self):
        self.state["release"] = metadata(self.root, TAG)
        self.state["corrupt_download"] = True
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_source_config_failure_is_not_absence(self):
        (self.root / "app.config").write_text("return 7\n")
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_newer_release_between_upload_and_publish_blocks_promotion(self):
        self.state["newer_after_upload"] = metadata(self.root, "v0.1.100", build=100)
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertTrue(self.state["release"]["draft"])
        self.assertIsNone(self.state["latest"])

    def test_public_appcast_must_match_original_zip(self):
        self.state["release"] = metadata(self.root, TAG)
        data = feed(archive=b"different original zip")
        (self.root / "remote" / TAG / "appcast.xml").write_bytes(data)
        asset = self.state["release"]["assets"][2]
        asset.update(size=len(data), digest=digest(data))
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])

    def test_public_verification_does_not_need_new_build_artifacts(self):
        self.state["release"] = metadata(self.root, TAG)
        shutil.rmtree(self.root / "build")
        result = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.records("mutations"), [])

    def test_public_zip_bundle_version_build_and_identity_are_checked(self):
        for info in [bundle_info(version="0.1.98"), bundle_info(build=98), bundle_info(identity="com.example.other")]:
            with self.subTest(info=info):
                self.state["release"] = metadata(self.root, TAG)
                data = archive_bytes(info)
                remote = self.root / "remote" / TAG
                (remote / "Howler.zip").write_bytes(data)
                xml = feed(archive=data)
                (remote / "appcast.xml").write_bytes(xml)
                for index, contents in [(0, data), (2, xml)]:
                    self.state["release"]["assets"][index].update(size=len(contents), digest=digest(contents))
                self.assertNotEqual(self.run_publish().returncode, 0)
                self.assertEqual(self.records("mutations"), [])

    def test_public_dmg_bundle_is_checked_and_unmounted_on_failure(self):
        self.state["release"] = metadata(self.root, TAG)
        data = json.dumps(bundle_info(build=98)).encode()
        (self.root / "remote" / TAG / "Howler.dmg").write_bytes(data)
        self.state["release"]["assets"][1].update(size=len(data), digest=digest(data))
        self.assertNotEqual(self.run_publish().returncode, 0)
        self.assertEqual(self.records("mutations"), [])
        self.assertIn("hdiutil detach", (self.root / "tools").read_text())

    def test_publication_lock_is_separate_from_build_and_homebrew(self):
        workflow = (self.source / ".github/workflows/build.yml").read_text()
        jobs = workflow.split("\n  publish-release:\n")
        self.assertEqual(len(jobs), 2)
        publish = jobs[1].split("\n  build:\n")[0]
        self.assertIn("group: howler-release", publish)
        self.assertIn("cancel-in-progress: false", publish)
        self.assertIn("queue: max", publish)
        self.assertNotIn("github.ref", publish.split("concurrency:")[1].split("steps:")[0])
        self.assertIn("needs: build-app", publish)
        self.assertIn("actions/download-artifact@", publish)
        self.assertNotIn("Publish release", jobs[0])
        self.assertIn("needs.build-app.result", workflow)
        self.assertIn("needs.publish-release.result", workflow)
        homebrew = workflow.split("\n  homebrew:\n")[1]
        self.assertNotIn("concurrency:", homebrew)
        self.assertIn("needs: build", homebrew)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--gh"]:
        mock_gh()
    elif sys.argv[1:2] == ["--tool"]:
        tool, args = sys.argv[2], sys.argv[3:]
        root = Path(os.environ["FIXTURE_ROOT"])
        with (root / "tools").open("a") as log:
            log.write(tool + " " + " ".join(args) + "\n")
        if tool == "ditto":
            with zipfile.ZipFile(args[-2]) as archive:
                archive.extractall(args[-1])
        elif tool == "hdiutil" and args[0] == "attach":
            destination = Path(args[args.index("-mountpoint") + 1]) / "Howler.app/Contents"
            destination.mkdir(parents=True)
            (destination / "Info.plist").write_bytes(plistlib.dumps(json.loads(Path(args[1]).read_bytes())))
    else:
        unittest.main()
