# Settings and letter controls

This revision updates the screenshot-conversation design following acceptance feedback.

## Interaction

- The menu bar menu contains Open Howler, Settings, the existing update and feedback actions, and Quit Howler. All rows are text-only, share one leading edge, and use full labels without trailing ellipses. An available update changes the action label and menu bar indicator, without adding a menu-row icon. Use neutral menu actions so system-provided action images cannot reappear.
- Capture and Explain is a permanent setting in Settings > Shortcut, enabled by default. Its default shortcut is Option-Shift-H; an existing custom shortcut is retained.
- Switching capture off unregisters its global shortcut and disables the capture action in Attach. The setting and selected shortcut survive restart. Switching it back on restores the saved shortcut. Normal text and pasted-image questions remain available.
- A capture result delivered while capture is off is discarded. Turning capture off does not clear the letter, cancel an existing model request or pause its queue.
- The flame stays fixed at the bottom-right corner of the paper, matching the bottom-to-top burn animation. Its hit area remains 40 points; footer content leaves space for it. Escape retains the existing composition, preview and burn ordering.

## Settings layout

The tabs are General, Prompt, Shortcut, in that order.

| Tab | Contents |
| --- | --- |
| General | Model setup, reply language, launch at login, automatic updates, feedback, privacy notice and version/update footer |
| Prompt | Existing system-prompt editor and reset action |
| Shortcut | Open Howler shortcut, fixed Open Settings shortcut, Capture and Explain switch and its shortcut recorder |

Reuse the existing native cards, typography, segmented toolbar and focus handling. The fixed window width accommodates three labels and icons alongside the title. General and Shortcut contribute their natural height; all three pages share the larger height, and Prompt fills it. Hidden pages remain excluded from interaction and accessibility.

## Implementation and verification

1. Persist the capture switch in AppSettings; connect it to hotkey registration, capture entry and completion guards.
2. Split the settings panes and their shared height calculation. Retain shortcut editing, conflict warnings and stopping recording on tab changes.
3. Remove all menu-row images, remove the menu capture action, and move the flame with footer clearance.
4. Cover capture persistence, disabled entry, delayed capture completion, re-enabling and update-menu states with focused tests.
5. Render General, Prompt, Shortcut on/off, and empty/long letters in the existing visual style. Check toolbar fit, footer clearance and tab-switch size stability.
6. Run the complete tests and signed app build. Install the candidate under the existing installation authorization; distinguish synthetic renders and tests from actual installed-app interaction acceptance.

This revision does not authorize publication. Final release confirmation remains required.
