# Release signing and notarization

Tagged releases require a **Developer ID Application** certificate and Apple notarization; missing signing credentials fail the release. Ordinary branch and pull-request builds can fall back to an ad-hoc signature, as Howler shipped with up to v0.1.3.

A stable signature matters beyond Gatekeeper. macOS ties Keychain access and privacy grants (screen recording) to the app's signing identity. An ad-hoc signature changes with every build, so each update asks for Keychain access again. A Developer ID signature stays the same across builds.

## One-time setup

These steps need the Apple Developer Program **Account Holder** role. Only the Account Holder can create Developer ID certificates.

1. **Create the certificate.** In Xcode, open Settings › Accounts, choose the team, then Manage Certificates. Click **+** and choose **Developer ID Application**. The certificate and its private key land in the login keychain.
2. **Export it as .p12.** In Keychain Access › login › My Certificates, right-click **Developer ID Application: … (TEAM ID)**, choose **Export**, and save as `.p12` with a strong password.
3. **Create a notarization key.** In App Store Connect › Users and Access › Integrations › App Store Connect API › Team Keys, click **Generate API Key** with **Developer** access. Download `AuthKey_<KEYID>.p8`; it can only be downloaded once. Note the **Key ID** and the **Issuer ID**, which is shown above the key list.
4. **Store the secrets in GitHub.** Run these in Terminal. The values never pass through a chat or a file in the repo:

   ```bash
   export GH_TOKEN="$(gh auth token --user HiAriesZhou)" R=HiAriesZhou/Howler
   base64 -i ~/Downloads/<certificate>.p12 | gh secret set MACOS_CERT_P12_BASE64 -R $R
   gh secret set MACOS_CERT_PASSWORD -R $R          # prompts for the .p12 password
   base64 -i ~/Downloads/AuthKey_<KEYID>.p8 | gh secret set NOTARY_KEY_P8_BASE64 -R $R
   gh secret set NOTARY_KEY_ID -R $R                # prompts; paste the Key ID
   gh secret set NOTARY_ISSUER_ID -R $R             # prompts; paste the Issuer ID
   K="$(mktemp)"; generate_keys --account howler -x "$K" && gh secret set SPARKLE_ED_PRIVATE_KEY -R $R < "$K"; rm -f "$K"   # Sparkle's tool; see below
   gh secret list -R $R
   ```

   Then move the `.p12` and `.p8` files somewhere safe, such as a password manager, and delete the copies in Downloads.

## What CI does

1. When `MACOS_CERT_P12_BASE64` is set, CI imports the certificate into a throwaway keychain and exports its identity as `SIGN_IDENTITY`.
2. `scripts/bundle.sh` signs the app with the hardened runtime and a secure timestamp.
3. On `v*` tags, `scripts/notarize.sh app` submits the app, staples the ticket and rebuilds the zip.
4. `scripts/dmg.sh` builds the disk image from the stapled app and signs it. `scripts/notarize.sh dmg` then notarizes and staples the disk image.
5. A tagged build that is signed but has no notarization secrets fails on purpose. Gatekeeper would still block such a release.
6. On `v*` tags, CI fetches Sparkle's `sign_update` (the version `Package.swift` pins, checked against its SHA-256). `scripts/appcast.sh` then signs the stapled zip with `SPARKLE_ED_PRIVATE_KEY` and writes `appcast.xml`, which is attached to the release. Installed copies read it through `SUFeedURL` (`app.config`). A tag without the secret fails, because installed copies would never be offered that release.

## The update key

Sparkle verifies every update against `SPARKLE_PUBLIC_KEY` in `app.config`, the public half of an EdDSA key. The private half lives in the login keychain (account `howler`, made with Sparkle's `generate_keys --account howler`), in a backup outside the repo, and in the `SPARKLE_ED_PRIVATE_KEY` secret. If it is lost, installed copies can't verify new updates and need one manual download. Never put it in the repo or a chat.

## Homebrew upgrade PRs

After a tagged Build succeeds, the Homebrew workflow downloads that release's
`Howler.dmg`, calculates SHA-256 and compares it with GitHub's published digest.
It requires a complete stable release (`Howler.dmg`, `Howler.zip`, `appcast.xml`),
checks the mounted app's version and bundle ID, and validates the universal binary,
signature, notarization tickets and Gatekeeper acceptance. Verification mounts the
DMG read-only and never installs or launches the app.

Only then does it create `automation/howler-X.Y.Z` in
[`HiAriesZhou/homebrew-tap`](https://github.com/HiAriesZhou/homebrew-tap), changing
only `Casks/howler.rb`'s version and SHA-256. The existing tap CI runs style, strict
online audit and download verification. A maintainer reviews and merges the PR;
the automation does not merge it.

### One-time token setup

The default `GITHUB_TOKEN` is limited to Howler. Use a dedicated
[fine-grained PAT](https://github.com/settings/personal-access-tokens/new) so the
workflow can write to the tap and its PR can trigger CI automatically:

1. Sign in as `HiAriesZhou`, the owner of `homebrew-tap`. Give the
   token a descriptive name such as `Howler Homebrew updates` and an expiration
   date you can renew before it expires.
2. Set **Resource owner** to `HiAriesZhou`. Under **Repository access**, choose
   **Only select repositories** and select **homebrew-tap**.
3. Grant these **Repository permissions**: **Contents — Read and write** and
   **Pull requests — Read and write**. Metadata read access is included. No
   account permissions, Actions write or Workflows write permission is needed.
4. Generate the token and store it directly in
   [Howler → Settings → Secrets and variables → Actions](https://github.com/HiAriesZhou/Howler/settings/secrets/actions)
   as a **New repository secret** named **`HOMEBREW_TAP_TOKEN`**. Store it in
   Howler, not the tap. Do not paste it into an issue, chat, shell command or file.
5. Renew the token before expiration and replace that secret. If it is revoked or
   expires, the PR step fails visibly; the existing app release remains published.

The token is available only to the PR step, after verification; normal builds and
fork PRs do not receive it. Its write permissions cover only the selected tap.
See GitHub's [token permissions](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
and [workflow-trigger rules](https://docs.github.com/en/actions/concepts/security/github_token).

### Retry and acceptance

To retry a failed Homebrew job, use **Re-run failed jobs** on the tagged Build.
For an already published release, open
[Actions → Homebrew](https://github.com/HiAriesZhou/Howler/actions/workflows/homebrew.yml),
choose **Run workflow** on **main**, and enter the stable tag, for example
`v0.1.13`. This runs only verification and tap delivery, without rebuilding or
republishing the app. The workflow must be merged into main before this entry appears.

Runs are serialized. Repeating a version reuses its branch and open PR; a cask
already at that version and checksum is a no-op. Older releases cannot downgrade
the cask. A different checksum for the same version, a modified automation branch,
or a closed version PR needs maintainer review rather than an automatic overwrite.

Acceptance: the Homebrew run succeeds, its PR changes exactly the two cask stanzas,
and the tap's **check** CI passes. Repeating the run must not create another PR.
Running against an already synchronized release verifies the no-op path only; it
does not prove the token's write permissions or PR-triggered CI. Exercise those on
the next real release. No new application release is needed to enable this workflow.

Local fixture checks run with `swift test --filter HomebrewTests` (included in
`make test`). They exercise the actual shell script with local API and macOS tool
substitutes, including validation failures and interrupted retries; they do not
prove real signing, GitHub permissions or remote CI. To disable delivery, remove
the Homebrew caller job from `build.yml` through a PR and revoke the dedicated token.

## Local builds

With the certificate in the login keychain, a local build can use the same signature:

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAM ID>)" make app
```

Builds signed this way keep Keychain access across reinstalls. Running `scripts/notarize.sh` locally takes the same `NOTARY_KEY_PATH`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` as CI.

## Check a release

```bash
spctl --assess --type execute --verbose=2 /Applications/Howler.app   # "source=Notarized Developer ID"
xcrun stapler validate /Applications/Howler.app
```

The current certificate (G2 Sub-CA) expires on **2027-11-26**. Before then, create a new one, export it, and update the two `MACOS_CERT_*` secrets. Releases signed before expiry keep working, because each signature carries a secure timestamp.
