# Reliable model configuration

## Approved scope

Make configuration failures actionable before refining the model card's layout.
The assistant configures the service, model and request parameters. The user
enters or replaces the API key inside Howler and explicitly saves and checks it.
CLI key input remains available for deliberate terminal use.

## Behavior

- A Keychain record's presence does not establish readability or connectivity.
- Preserve Keychain operation and status errors. Missing keys, denied access and
  service failures have different messages. Failed reads replace stale check results.
- An update denied by Keychain must never automatically delete the old item.
- The native key editor uses a secure field, never loads the existing secret,
  identifies the destination, clears its draft on dismissal and after saving,
  and rejects saving against a changed configuration.
- Save & Check performs one bounded connection probe. No automatic retry or
  configuration reset occurs. The current configuration must still match before
  a result can mark it ready.
- Keep native settings typography and controls, explicit progress and accessible
  labels. Avoid additional animation. The existing setup-help placement is outside
  this change; replace its misleading title with a description of what it does.
- The copied setup prompt directs key entry to the app. Authentication and
  permission failures stop immediately; other failures allow one diagnosed retry.

## Implementation and commit boundaries

1. Keychain/store/CLI: inject Security operations for tests, reproduce the unsafe
   replacement branch, preserve read errors and record pre-network failures.
2. Native configuration: secure key editor, destination fencing, save/check states,
   bounded probe and actionable conversation errors.
3. Setup guidance: update the copied prompt, both READMEs, release notes and manual
   acceptance checks. Retain the shortened privacy footer.

## Verification

Use synthetic keys and in-memory stores for denial, cancellation, missing-item,
replacement, stale-result and destination-change tests. Verify denied writes never
delete or add an item. Test CLI diagnostics without a real Keychain or network.
Render the native editor and its error states in light and dark appearances.
Run the suite, review the diff, then verify and install an exact-head signed CI
artifact with a rollback backup. Distinguish native fixture evidence, installed
startup, actual interactions and bounded real-service checks.

Release remains gated on explicit final confirmation.
