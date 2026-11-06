# Settings and letter controls

This revision updates the screenshot-conversation design following acceptance feedback.

## Interaction

- The menu bar menu contains Open Howler, Settings, the existing update and feedback actions, and Quit Howler. All rows are text-only, share one leading edge, and use full labels without trailing ellipses. An available update changes the action label and menu bar indicator, without adding a menu-row icon. Neutral actions prevent system-provided action images from reappearing.
- Settings > Shortcut contains Open Howler, Open Settings and Capture and Explain. Their defaults are Option-H, Option-Comma and Option-Shift-H.
- Each shortcut can be recorded, cleared or restored to its default. An empty shortcut means that global keyboard action is disabled. It remains empty after restart. No separate switch, mechanical control or cloud overlay is shown.
- Click the clear button next to a recorded shortcut, or press unmodified Delete while recording, to clear it. Escape cancels recording. An empty field shows a quiet Not set placeholder and remains available for recording.
- Clearing a shortcut unregisters it and releases its combination for another action. Recording and restoring defaults check conflicts against the other configured shortcuts. A failed reset preserves the current value and explains the conflict. Registration failures are shown only for configured shortcuts, never for intentional empty fields.
- The menu bar remains available to open Howler or Settings. Attach retains its manual capture action even when the capture shortcut is empty. Clearing a shortcut does not cancel an in-progress capture, a model response or the reply queue.
- The flame stays fixed at the bottom-right corner of the paper, matching the bottom-to-top burn animation. Its hit area remains 40 points; footer content leaves space for it. Escape retains the existing composition, preview and burn ordering.

## Settings layout

The tabs are General, Prompt, Shortcut, in that order.

| Tab | Contents |
| --- | --- |
| General | Model setup, reply language, launch at login, automatic updates, feedback, privacy notice and version/update footer |
| Prompt | Existing system-prompt editor and reset action |
| Shortcut | Three configurable shortcut recorders, including clear and reset controls |

Reuse the existing native cards, typography, segmented toolbar and focus handling. The fixed window width accommodates three labels and icons alongside the title. General and Shortcut contribute their natural height; all three pages share the larger height, and Prompt fills it. Hidden pages remain excluded from interaction and accessibility.

## Persistence and migration

Missing preferences mean the factory default; an explicitly saved empty value means disabled. Use the existing preference keys with nullable shortcut data so these states cannot be confused. Corrupt or invalid data falls back to the corresponding default. Reset removes the stored override only after conflict checking.

Retain the one-time historical Option-Space and mistaken Option-Comma letter-default migrations. Explicitly empty values must survive those migrations. Convert a previously disabled capture switch to an empty capture shortcut, then retire that switch preference so recording a new shortcut cannot be disabled again on restart. Existing enabled custom shortcuts remain unchanged.

## Implementation and verification

1. Make each shortcut optional and persist explicit empty values. Update migration, conflict checks, reset behavior and global registration.
2. Remove the standalone capture switch and overlay. Add shared clear controls, empty placeholders and Delete-to-clear handling to the recorder. Keep manual capture available and preserve in-progress work.
3. Test default versus explicit-empty persistence, reset conflicts, released combinations, old-switch migration, historical migrations and manual capture with an empty shortcut.
4. Render configured and empty shortcut fields in light and dark appearances. Check layout, clear/reset controls and absence of false conflict warnings.
5. Run the complete test suite and obtain a fresh review of this user-requested behavior revision. Verify and install the signed candidate with a rollback backup. Distinguish native renders and startup checks from installed-app interaction acceptance.

This revision supersedes the earlier standalone switch designs. It does not authorize publication. Final release confirmation remains required.
