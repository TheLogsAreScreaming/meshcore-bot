# Intel Mac release candidate verification

Complete this checklist on the **actual Intel Mac** using a build from the current main branch. Record the GitHub Actions run URL, macOS version, and whether a real MeshCore radio was attached. CI is not a substitute for the device tests.

| Scenario | Expected behavior | Result |
| --- | --- | --- |
| Fresh app launch | Window opens on Overview; "Finish setting up" card shown for a new config | Not tested |
| Navigation | Sidebar and ⌘1–⌘5 switch between all five pages; nothing clipped | Not tested |
| Light and Dark | Switching System Settings → Appearance restyles the open window | Not tested |
| Radio port list | Plugged-in radio appears under Radio & Connection; Save Connection updates config | Not tested |
| Edit Config | Configuration page shows current INI; copy/paste/undo work | Not tested |
| Revert changes | Original config remains unchanged | Not tested |
| Save changes | Config saved; backup exists; restart offered if bot is running | Not tested |
| Restore backup | Confirmation shown; config and backup swap | Not tested |
| Unsaved edits on close | Save / Don't Save / Cancel prompt appears | Not tested |
| Invalid config | Empty/missing required sections rejected | Not tested |
| Quit while stopped | App exits without Force Quit | Not tested |
| Quit while running | App exits; bot subprocess stops | Not tested |
| Start and stop bot | UI status and log update | Not tested |
| Radio reconnect | Bot recovers from disconnect with valid radio | Not tested |
| Local dashboard | Dashboard opens on loopback only | Not tested |

**Release gate:** Do not mark the quit and editor bugs resolved based solely on compilation or static checks. Attach sanitized screenshots and reproduction details to any failure. Do not publish a stable release until physical radio tests pass. The candidate may be marked prerelease with limitations clearly stated.
