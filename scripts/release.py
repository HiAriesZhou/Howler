import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def version(tag):
    require(re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag),
            "expected a stable vX.Y.Z tag")
    return tuple(int(part) for part in tag[1:].split("."))


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    require(result.returncode == 0, f"{Path(args[0]).name} {args[1]} failed; release state must be checked before retry")
    return result.stdout


class Publisher:
    def __init__(self):
        self.repo = os.environ["GITHUB_REPOSITORY"]
        self.tag = os.environ["GITHUB_REF_NAME"]
        self.app = os.environ["APP_NAME"]
        self.bundle_id = os.environ["BUNDLE_ID"]
        self.build = int(os.environ["BUILD_NUMBER"])
        self.feed_root = os.environ["SPARKLE_FEED_URL"].split("/releases/")[0]
        require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", self.repo), "invalid repository")
        require(re.fullmatch(r"[A-Za-z0-9_-]+", self.app), "invalid application name")
        require(self.tag == "v" + os.environ["VERSION"], "tag does not match VERSION in app.config")
        version(self.tag)
        require(self.build > 0, "BUILD_NUMBER must be positive")
        self.names = [f"{self.app}.zip", f"{self.app}.dmg", "appcast.xml"]

    def gh(self, *args):
        return run(["gh", *args])

    def release(self, allow_missing=False):
        result = subprocess.run(["gh", "api", "--method", "GET", "--include",
                                 f"repos/{self.repo}/releases/tags/{self.tag}"], capture_output=True)
        header, separator, body = result.stdout.replace(b"\r\n", b"\n").partition(b"\n\n")
        status = re.match(rb"HTTP/\S+ (\d{3})\b", header)
        require(separator and status, "release lookup failed without an HTTP response")
        code = int(status[1])
        if code == 404 and result.returncode != 0 and allow_missing:
            return None
        require(code == 200 and result.returncode == 0, f"release lookup failed (HTTP {code})")
        release = json.loads(body)
        require(release["tag_name"] == self.tag and type(release["draft"]) is bool
                and release["prerelease"] is False, "unexpected release identity or state")
        return release

    def assets(self, release):
        assets = {}
        for name in self.names:
            matches = [asset for asset in release["assets"] if asset["name"] == name]
            require(len(matches) == 1, f"release requires exactly one {name}")
            asset = matches[0]
            require(asset["state"] == "uploaded" and type(asset["size"]) is int and asset["size"] > 0,
                    f"incomplete release asset: {name}")
            require(re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest") or ""),
                    f"release asset has no SHA-256: {name}")
            require(type(asset["id"]) is int and asset["id"] > 0, f"invalid asset ID: {name}")
            assets[name] = asset
        return assets

    def download(self, asset):
        data = self.gh("api", "--method", "GET", f"repos/{self.repo}/releases/assets/{asset['id']}",
                       "--header", "Accept: application/octet-stream")
        require(len(data) == asset["size"] and "sha256:" + hashlib.sha256(data).hexdigest() == asset["digest"],
                f"downloaded asset differs from published metadata: {asset['name']}")
        return data

    def feed(self, data, tag):
        items = ET.fromstring(data).findall("./channel/item")
        require(len(items) == 1, "appcast must contain one release")
        item = items[0]
        require(item.findtext(SPARKLE + "shortVersionString") == tag[1:], "appcast version differs from tag")
        build = item.findtext(SPARKLE + "version", "")
        require(re.fullmatch(r"[1-9][0-9]*", build), "invalid appcast build number")
        enclosure = item.find("enclosure")
        require(enclosure is not None, "missing appcast enclosure")
        require(enclosure.get("url") == f"{self.feed_root}/releases/download/{tag}/{self.app}.zip",
                "appcast URL differs from release archive")
        require(enclosure.get(SPARKLE + "edSignature"), "missing archive signature")
        return int(build), enclosure

    def monotonic(self):
        pages = json.loads(self.gh("api", "--method", "GET", f"repos/{self.repo}/releases?per_page=100",
                                   "--paginate", "--slurp"))
        require(isinstance(pages, list) and all(isinstance(page, list) for page in pages), "invalid release listing")
        stable = [release for page in pages for release in page
                  if release["draft"] is False and release["prerelease"] is False]
        if not stable:
            return
        latest = max(stable, key=lambda release: version(release["tag_name"]))
        require(version(self.tag) > version(latest["tag_name"]), "refusing to publish an old or duplicate stable version")
        for release in stable:
            if release != latest and not any(asset["name"] == "appcast.xml" for asset in release["assets"]):
                continue
            data = self.download(self.assets(release)["appcast.xml"])
            previous_build, _ = self.feed(data, release["tag_name"])
            require(self.build > previous_build, "BUILD_NUMBER must exceed every published Sparkle build")

    def verify(self, release, expected=None):
        assets = self.assets(release)
        with tempfile.TemporaryDirectory(prefix="howler-publish-") as scratch:
            directory = Path(scratch)
            for name, asset in assets.items():
                data = self.download(asset)
                if expected is not None:
                    require(hashlib.sha256(data).hexdigest() == expected[name], f"uploaded batch differs: {name}")
                (directory / name).write_bytes(data)
            build, enclosure = self.feed((directory / "appcast.xml").read_bytes(), self.tag)
            archive = directory / self.names[0]
            require(build == self.build, "appcast build differs from app.config")
            require(enclosure.get("length") == str(archive.stat().st_size), "appcast archive length differs")
            key = os.environ.get("SPARKLE_ED_PRIVATE_KEY", "")
            require(key, "SPARKLE_ED_PRIVATE_KEY is not set")
            run([os.environ["SIGN_UPDATE"], "--ed-key-file", "-", "--verify", str(archive),
                 enclosure.get(SPARKLE + "edSignature")], input=(key + "\n").encode())
            extracted = directory / "archive"
            run(["ditto", "-x", "-k", str(archive), str(extracted)])
            self.verify_app(extracted / (self.app + ".app"))
            dmg = str(directory / self.names[1])
            run(["codesign", "--verify", "--strict", dmg])
            run(["xcrun", "stapler", "validate", dmg])
            run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", dmg])
            mount = directory / "mount"
            mount.mkdir()
            run(["hdiutil", "attach", dmg, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount)])
            try:
                self.verify_app(mount / (self.app + ".app"))
            finally:
                run(["hdiutil", "detach", str(mount)])

    def verify_app(self, app):
        with (app / "Contents/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        require(info.get("CFBundleShortVersionString") == self.tag[1:]
                and info.get("CFBundleVersion") == str(self.build)
                and info.get("CFBundleIdentifier") == self.bundle_id,
                "archive application version, build or identity differs from app.config")
        run(["codesign", "--verify", "--deep", "--strict", str(app)])
        run(["xcrun", "stapler", "validate", str(app)])
        run(["spctl", "--assess", "--type", "execute", str(app)])

    def publish(self):
        release = self.release(allow_missing=True)
        if release is not None and not release["draft"]:
            self.verify(release)
            print(f"Verified existing {self.tag}; published assets and latest were left untouched.")
            return
        notes = Path("docs/releases") / (self.tag[1:] + ".md")
        require(notes.is_file() and re.search(r"^[*-] \S", notes.read_text(), re.MULTILINE),
                f"add user-facing release notes to {notes} before publishing")
        for name in self.names[:2]:
            require((Path("build") / name).is_file() and (Path("build") / name).stat().st_size > 0,
                    f"missing build/{name}")
        self.monotonic()
        run(["bash", "scripts/appcast.sh", str(notes)])
        paths = [str(Path("build") / name) for name in self.names]
        expected = {name: hashlib.sha256(Path(path).read_bytes()).hexdigest() for name, path in zip(self.names, paths)}
        if release is None:
            self.gh("release", "create", self.tag, *paths, "--repo", self.repo, "--draft", "--verify-tag",
                    "--title", f"{self.app} {self.tag}", "--notes-file", str(notes))
        else:
            require(self.release()["draft"], "release became public; refusing to replace its assets")
            self.gh("release", "upload", self.tag, *paths, "--repo", self.repo, "--clobber")
        release = self.release()
        require(release["draft"], "release became public before draft verification; refusing to edit it")
        self.verify(release, expected)
        self.monotonic()
        require(self.release()["draft"], "release became public; refusing to edit it")
        self.gh("release", "edit", self.tag, "--repo", self.repo, "--draft=false", "--latest", "--notes-file", str(notes))
        release = self.release()
        require(not release["draft"], "release is still a draft after publication")
        self.verify(release)
        print(f"Published and verified {self.tag}.")


if __name__ == "__main__":
    try:
        Publisher().publish()
    except (ValueError, KeyError, TypeError, OSError, ET.ParseError, plistlib.InvalidFileException) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
