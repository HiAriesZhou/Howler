#!/usr/bin/env bash
# Test the real core sources in an isolated package; leave the app's lockfile untouched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE="$ROOT/.build/core-package"
mkdir -p "$PACKAGE/Sources" "$PACKAGE/Tests"
for entry in Sources/HowlerCore Tests/HowlerCoreTests; do
  link="$PACKAGE/$entry"
  if [[ -L "$link" ]]; then
    [[ "$(readlink "$link")" == "$ROOT/$entry" ]] || { echo "error: unexpected core test source link" >&2; exit 1; }
  elif [[ -e "$link" ]]; then
    echo "error: core test source path already exists" >&2; exit 1
  else
    ln -s "$ROOT/$entry" "$link"
  fi
done
cat > "$PACKAGE/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "HowlerCoreChecks",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HowlerCore"),
        .testTarget(name: "HowlerCoreTests", dependencies: ["HowlerCore"]),
    ]
)
SWIFT
exec swift test --package-path "$PACKAGE" --scratch-path "$ROOT/.build/core-tests" "$@"
