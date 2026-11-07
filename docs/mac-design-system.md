# MeshCore Bot design system

The Intel Mac app (`macos/MeshCoreDesktop.swift`) and the web dashboard (`modules/web_viewer/static/css/theme.css`) share one visual language: neutral surfaces, a single brand teal for identity and selection, and green / amber / red reserved for status. Both follow the system Light/Dark appearance. The approach borrows from Apple's Human Interface Guidelines (native controls, sidebar navigation, standard menus) without copying any one app.

## Tokens

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| Brand | `#0B7A68` | `#3CCFAE` | App mark, selected navigation, primary web buttons, focus ring |
| Surface / card | white on `#F5F6F8` | `#1C1E22` on `#141518` | Cards, panels |
| Border | 9% black | 9% white | Card and input outlines |
| Text | label / `#1C1F24` | label / `#ECEEF1` | Body text |
| Secondary text | secondary label / `#545B66` | secondary label / `#B2B8C1` | Descriptions, keys, hints |
| Success · Warning · Danger | system green · orange · red | same, dark variants | Status only |

Spacing uses a 4-point scale (4, 8, 12, 16, 24, 32). Corner radii are 6 (controls), 10 (cards) and 14 (web modals). Type sizes on the Mac are 24 bold (page title), 17 semibold (status), 13 (body), 12 (callouts), 11 semibold uppercase (card labels) and 12 monospaced (editor and log).

In Swift every value lives in `enum Theme` (`Space`, `Radius`, `Palette`, `Typography`, `Motion`); views never create colors or fonts directly, and a regression test enforces that. On the web the tokens are CSS custom properties (`--mc-*`), mapped onto the variables older page styles already use, so every page picks them up without template changes.

## Components (Mac)

- **CardView** — rounded surface with a hairline border; re-resolves its colors when the appearance changes.
- **Sidebar item** — symbol + label, brand-tinted when selected; reachable by keyboard and ⌘1–⌘5.
- **Buttons** — native push buttons. One accent-filled primary action per area; others are standard; destructive confirmations use `hasDestructiveAction`.
- **Status** — always symbol + color + words (e.g. ✓ green "Running"), never color alone.
- **Key/value grid** and **form grid** — secondary keys beside values; right-aligned form labels in a shared 160-pt column so forms line up.
- **Wrapping paragraph** — multi-line label that re-wraps as the window resizes.

## Behavior rules

- Show what matters first: status and the next action on Overview; advanced settings behind **Advanced**.
- Plain words over config keys ("Connect using", "Radio port"), with a hint under each choice.
- Every change to `config.ini` goes through one writer that validates, keeps `config.ini.bak`, and writes atomically.
- Confirm only destructive or lossy actions: restoring a backup, discarding edits, closing with unsaved changes.
- Respect Reduce Motion (Mac page fade and web transitions are turned off) and keep web touch targets at least 40–44 px on small screens.
