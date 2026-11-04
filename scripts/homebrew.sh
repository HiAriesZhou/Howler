#!/usr/bin/env bash
# CI entry points: verify TAG MANIFEST, then pr MANIFEST. Tokens stay in GH_TOKEN.
set -euo pipefail

SOURCE="HiAriesZhou/Howler"
TAP="HiAriesZhou/homebrew-tap"
CASK="Casks/howler.rb"

fail() { echo "error: $*" >&2; exit 1; }
api() { gh api --method "$1" "repos/$2" "${@:3}"; }
valid_tag() { [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; }
latest_tag() { api GET "$SOURCE/releases/latest" | jq -er '.tag_name'; }

verify() {
    local tag="$1" manifest="$2" scratch mounted=0 digest actual app version latest
    valid_tag "$tag" || fail "expected a stable vX.Y.Z tag"
    latest="$(latest_tag)"
    [[ "$latest" == "$tag" ]] || fail "only the latest stable release can update the cask"
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/howler-release.XXXXXX")"
    # This subshell owns its temporary directory and read-only mount, including on failure.
    (
        cleanup() {
            if [[ "$mounted" == 1 ]]; then
                hdiutil detach "$scratch/mount" >/dev/null || return 1
            fi
            rm -rf "$scratch"
        }
        trap cleanup EXIT
        api GET "$SOURCE/releases/tags/$tag" > "$scratch/release.json"
        jq -e --arg tag "$tag" '
            .tag_name == $tag and .draft == false and .prerelease == false and
            ([.assets[] | select(.name == "Howler.dmg" or .name == "Howler.zip" or .name == "appcast.xml")]
             | length == 3 and (map(.name) | unique | length == 3) and
               all(.state == "uploaded" and .size > 0))
        ' "$scratch/release.json" >/dev/null || fail "release assets are incomplete"
        digest="$(jq -er '.assets[] | select(.name == "Howler.dmg") | .digest' "$scratch/release.json")"
        [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "release has no valid DMG SHA-256"
        curl --fail --location --silent --show-error --retry 2 --connect-timeout 30 --max-time 180 \
            "https://github.com/$SOURCE/releases/download/$tag/Howler.dmg" -o "$scratch/Howler.dmg"
        actual="$(shasum -a 256 "$scratch/Howler.dmg" | awk '{print $1}')"
        [[ "sha256:$actual" == "$digest" ]] || fail "downloaded DMG checksum differs from the published digest"
        xcrun stapler validate "$scratch/Howler.dmg" >/dev/null
        spctl --assess --type open --context context:primary-signature "$scratch/Howler.dmg"
        mkdir "$scratch/mount"
        hdiutil attach "$scratch/Howler.dmg" -readonly -nobrowse -noautoopen \
            -mountpoint "$scratch/mount" >/dev/null
        mounted=1
        app="$scratch/mount/Howler.app"
        version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
        [[ "v$version" == "$tag" ]] || fail "DMG application version differs from the release tag"
        [[ "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" == com.hiarieszhou.howler ]] \
            || fail "unexpected application identity"
        codesign --verify --deep --strict "$app"
        xcrun stapler validate "$app" >/dev/null
        spctl --assess --type execute "$app"
        local archs
        archs="$(lipo -archs "$app/Contents/MacOS/Howler")"
        [[ " $archs " == *' arm64 '* && " $archs " == *' x86_64 '* ]] || fail "DMG is not universal"
        jq -n --arg tag "$tag" --arg version "$version" --arg sha256 "$actual" \
            '{tag: $tag, version: $version, sha256: $sha256}' > "$manifest"
        echo "Verified published Howler $version: $actual"
    )
}

pr() {
    local manifest="$1" version tag sha scratch branch base_sha old_version old_sha contents existing ref latest
    : "${GH_TOKEN:?set HOMEBREW_TAP_TOKEN in the workflow secrets}"
    version="$(jq -er '.version' "$manifest")"
    tag="$(jq -er '.tag' "$manifest")"
    sha="$(jq -er '.sha256' "$manifest")"
    valid_tag "$tag" && [[ "$tag" == "v$version" && "$sha" =~ ^[0-9a-f]{64}$ ]] || fail "invalid verified manifest"
    latest="$(latest_tag)"
    [[ "$latest" == "$tag" ]] || { echo "A newer release exists; skipping $tag."; return; }
    # Detect asset replacement between verification and the write step.
    api GET "$SOURCE/releases/tags/$tag" | jq -e --arg digest "sha256:$sha" '
        .draft == false and .prerelease == false and
        ([.assets[] | select(.name == "Howler.dmg")] | length == 1 and .[0].digest == $digest)
    ' >/dev/null || fail "published DMG changed after verification"

    scratch="$(mktemp -d "${TMPDIR:-/tmp}/howler-cask.XXXXXX")"
    (
        trap 'rm -rf "$scratch"' EXIT
        base_sha="$(api GET "$TAP/git/ref/heads/main" | jq -er '.object.sha')"
        api GET "$TAP/contents/$CASK?ref=$base_sha" > "$scratch/base.json"
        jq -ej '.content | @base64d' "$scratch/base.json" > "$scratch/base.rb"
        # Edit only the two literal stanzas; never evaluate tap Ruby or release text.
        jq -Rse '
            split("\n") |
            (map(select(test("^  version \"[0-9]+\\.[0-9]+\\.[0-9]+\"$"))) | length == 1) and
            (map(select(test("^  sha256 \"[0-9a-f]{64}\"$"))) | length == 1)
        ' "$scratch/base.rb" >/dev/null || fail "cask version/checksum stanzas need manual review"
        old_version="$(sed -nE 's/^  version "([0-9.]+)"$/\1/p' "$scratch/base.rb")"
        old_sha="$(sed -nE 's/^  sha256 "([0-9a-f]+)"$/\1/p' "$scratch/base.rb")"
        if [[ "$version" == "$old_version" ]]; then
            [[ "$sha" == "$old_sha" ]] || fail "same version has a different checksum; manual review required"
            echo "Howler $version is already in the tap."
            return
        fi
        jq -ne --arg old "$old_version" --arg new "$version" \
            '($new | split(".") | map(tonumber)) > ($old | split(".") | map(tonumber))' >/dev/null \
            || fail "refusing to downgrade the cask"
        contents="$(jq -Rrs --arg version "$version" --arg sha "$sha" '
            split("\n") | map(
                if test("^  version \"[0-9.]+\"$") then "  version \"\($version)\""
                elif test("^  sha256 \"[0-9a-f]{64}\"$") then "  sha256 \"\($sha)\""
                else . end
            ) | join("\n") | @base64
        ' "$scratch/base.rb")"
        branch="automation/howler-$version"
        api GET "$TAP/pulls?head=HiAriesZhou:$branch&base=main&state=all&per_page=100" > "$scratch/prs.json"
        jq -e 'all(.state == "open")' "$scratch/prs.json" >/dev/null \
            || fail "this version already has a closed PR; review it manually"
        existing="$(jq -r '.[0].html_url // empty' "$scratch/prs.json")"
        ref="$(api GET "$TAP/git/matching-refs/heads/$branch" | jq -r --arg ref "refs/heads/$branch" \
            '.[] | select(.ref == $ref) | .object.sha')"
        if [[ -z "$ref" ]]; then
            # Re-check immediately before the first write so stale runs remain read-only.
            latest="$(latest_tag)"
            [[ "$latest" == "$tag" ]] || fail "a newer release appeared; retry for that release"
            jq -n --arg ref "refs/heads/$branch" --arg sha "$base_sha" '{ref: $ref, sha: $sha}' > "$scratch/ref.json"
            api POST "$TAP/git/refs" --input "$scratch/ref.json" >/dev/null
            ref="$base_sha"
        fi
        api GET "$TAP/contents/$CASK?ref=$ref" > "$scratch/branch.json"
        jq -ej '.content | @base64d' "$scratch/branch.json" > "$scratch/branch.rb"
        if [[ "$(jq -Rrs '@base64' "$scratch/branch.rb")" != "$contents" ]]; then
            if [[ "$ref" != "$base_sha" ]]; then
                # A failed first attempt may have created only the branch. It is
                # safe to resume after main advances only if it has no unmerged commits.
                api GET "$TAP/compare/$ref...$base_sha" | jq -e \
                    '.behind_by == 0 and (.status == "ahead" or .status == "identical")' >/dev/null \
                    || fail "existing automation branch differs; refusing to overwrite it"
            fi
            latest="$(latest_tag)"
            [[ "$latest" == "$tag" ]] || fail "a newer release appeared; retry for that release"
            jq -n --arg branch "$branch" --arg content "$contents" \
                --arg sha "$(jq -r '.sha' "$scratch/branch.json")" --arg message "chore: bump Howler to $version" \
                '{branch: $branch, content: $content, sha: $sha, message: $message}' > "$scratch/update.json"
            api PUT "$TAP/contents/$CASK" --input "$scratch/update.json" >/dev/null
        fi
        api GET "$TAP/compare/$base_sha...$branch" | jq -e --arg path "$CASK" \
            '.files | length == 1 and .[0].filename == $path and .[0].status == "modified"' >/dev/null \
            || fail "automation branch changes files beyond the cask"
        if [[ -n "$existing" ]]; then
            echo "Existing upgrade PR: $existing"
            return
        fi
        jq -n --arg head "$branch" --arg title "chore: bump Howler to $version" \
            --arg body "Update Howler to [$tag](https://github.com/$SOURCE/releases/tag/$tag).

The published universal DMG passed checksum, version, signature and notarization verification.

SHA-256: \`$sha\`

The existing tap CI must pass before maintainer merge." \
            '{base: "main", head: $head, title: $title, body: $body}' > "$scratch/pr.json"
        api POST "$TAP/pulls" --input "$scratch/pr.json" | jq -er '.html_url'
    )
}

[[ $# == 3 && "$1" == verify || $# == 2 && "$1" == pr ]] \
    || fail "usage: scripts/homebrew.sh verify TAG MANIFEST | pr MANIFEST"
case "$1" in
    verify) verify "$2" "$3" ;;
    pr) pr "$2" ;;
esac
