# MeshCore Bot — Intel Mac Control Center

The native Intel Mac control center is a single window with a sidebar:

| Page | What it's for |
| --- | --- |
| **Overview** (⌘1) | Bot status with uptime, Start/Stop, Open Dashboard, radio and dashboard summaries, latest log lines, and a "Finish setting up" card until a radio is chosen |
| **Radio & Connection** (⌘2) | Pick USB / Bluetooth / Network, choose the USB port from a detected list, set the radio address, turn the web dashboard on or off; advanced timeout and reconnect settings are tucked under **Advanced** |
| **Configuration** (⌘3) | Full `config.ini` editor with unsaved-changes indicator, Save (⌘S), Revert, Restore Backup…, and Find (⌘F) |
| **Activity Log** (⌘4) | Live bot output with errors in red and warnings in orange; Follow new output, Copy All, Save Log…, Clear |
| **Help & Files** (⌘5) | Where your files are, troubleshooting for common problems, version |

The window follows the system Light/Dark appearance and Reduce Motion setting, and has standard menus (Edit, Bot, View, Window, Help) so copy/paste, undo and keyboard shortcuts work. The web dashboard is a separate local interface; it now follows the system appearance too until you pick a theme with its toggle. Design tokens and rules for both are described in [the design system notes](../docs/mac-design-system.md).

## Download and open

Open **Actions → Build Intel Mac Desktop App**, select a successful run for the PR or `main`, and download **MeshCore-Bot-Intel-Mac** (GitHub sign-in required). Unzip the artifact, then open the DMG and drag **MeshCore Bot.app** to Applications. Alternatively unzip the inner app ZIP. Double-click the app; Python is bundled and no Terminal setup is needed.

The workflow uses `macos-26-intel` (Tahoe), Python 3.11 x64, and verifies the launcher and bundled CLI are x86_64. The build includes command source files needed for dynamic plugin discovery, templates, static assets, translations and data. A frozen-runtime smoke check imports the core, web viewer and command modules without connecting to a radio.

The app is **ad-hoc signed, not Apple Developer ID signed or notarized**. macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. Only approve a build you trust. A notarized release requires the maintainer's Apple signing credentials.

## Configure and run

1. Open the app and go to **Radio & Connection** (or click **Set Up Radio Connection** on Overview). Settings remain at `~/Library/Application Support/MeshCore Bot/config.ini`. Updating the app never replaces this file. Back up this whole folder before migrating an existing installation; copy your config and databases there while the bot is stopped.
2. Choose **USB cable (serial)**, **Bluetooth LE** or **Network (TCP)**. For USB, plug the radio in and pick its `/dev/cu.usbmodem…` or `/dev/cu.usbserial…` port from the list (click Refresh if it isn't there). Click **Save Connection**. Everything else is on the **Configuration** page; every save keeps the previous file as `config.ini.bak`, which **Restore Backup…** can bring back.
3. New installs enable the dashboard on `127.0.0.1:8080` and start it with the bot (`[Web_Viewer]` `enabled = true`, `auto_start = true`). Configs created by older builds keep those settings off; set both to `true` to use the dashboard. Turn the dashboard on or off with **Start the web dashboard with the bot** on Radio & Connection. **Open Dashboard** always opens `127.0.0.1` on the configured port and works only while the bot is running. If the radio can't connect, the bot stops and the dashboard stops with it.
4. Click **Start Bot** (⌘R), watch the Activity Log, and open the dashboard. If a USB port is set but nothing is plugged in, the app warns before starting. **Stop Bot** (⌘.), quitting, or closing the window requests bot shutdown; a bot that hasn't exited after 15 seconds is force-stopped. Closing with unsaved Configuration edits asks whether to save them first. Do not run another service against the same radio simultaneously.

First launch copies the example configuration with a loopback-only dashboard that starts with the bot. It does not start the bot automatically. Existing configuration, credentials, plugins and bot behavior are preserved; optional Python plugin dependencies must be included when building a custom app.

## Build this checkout

On an Intel Mac with Apple Command Line Tools and Intel Python 3.11:

```sh
python3.11 -m venv .venv
.venv/bin/python -m pip install --prefer-binary -r requirements.txt 'pyinstaller>=6,<7'
PYTHON="$PWD/.venv/bin/python" bash macos/build-app.sh
```

Outputs are `output/MeshCore Bot.app`, a DMG, an app ZIP and SHA-256 checksums. Move old `output/` aside before rebuilding. `macos/local-builder/build-on-intel-mac.command` is an alternative double-click builder that downloads **main**, not an unmerged PR. To test a PR use its Actions artifact or build its checkout.

## Automation and verification

PRs, pushes to main and the desktop feature branches, and manual dispatch build downloadable artifacts. Pushing a `mac-v*` tag creates a **draft** release with the DMG, ZIP and checksums; it does not publish or merge automatically.

Before merging or publishing, verify on the target Intel Tahoe Mac: first launch, existing config retained after replacing the app, resize and log readability, Start/Stop/Start, quit/close shutdown, actual serial/BLE/TCP operation, and dashboard login and commands. Radio hardware checks cannot be established by the packaging smoke test. The dashboard retains upstream CDN dependencies for Bootstrap, icons and other libraries.

## Intel Mac smoke test and troubleshooting

1. Launch the downloaded app and visit all five pages in both Light and Dark appearance. Confirm nothing is clipped and the window resizes cleanly.
2. On **Configuration**, edit a value: the indicator should change to *Unsaved changes*. **Revert** discards, **Save** (⌘S) writes `config.ini` atomically and creates `config.ini.bak`. **Restore Backup…** asks for confirmation and swaps the two. Confirm copy/paste (⌘C/⌘V) and undo (⌘Z) work in the editor.
3. On **Radio & Connection**, confirm your plugged-in radio appears in the port list, save it, and check Overview shows the port without "(not connected)".
4. Confirm the app quits normally with the bot stopped. Then start the bot (with a valid MeshCore radio configuration), and confirm quitting while running does not hang.
5. If the app cannot close, record whether the bot was running, capture the Activity Monitor process state and logs, and report the exact steps. A passing CI build cannot establish that a hardware-specific hang is fixed.
6. The app is ad-hoc signed and not notarized. The radio send/receive and reconnect paths require a real MeshCore companion radio before a stable release.

Existing configuration is stored under `~/Library/Application Support/MeshCore Bot/config.ini`. Back it up before extensive edits.

For reproducible bug reports and Activity Monitor troubleshooting, see [Intel Mac diagnostics](../docs/mac-diagnostics.md).

For the release candidate hardware checklist, see [Intel Mac verification matrix](../docs/mac-release-test-matrix.md).

If a configuration edit causes startup issues, follow the [configuration recovery guide](../docs/mac-config-recovery.md).
