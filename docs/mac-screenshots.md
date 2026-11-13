# Capturing verified MeshCore Bot screenshots

Use the **latest successful Intel Mac build** from [GitHub Actions](https://github.com/TheLogsAreScreaming/meshcore-bot/actions/workflows/build-intel-mac.yml). Screenshots should show the real running application, not a mockup.

1. Open **MeshCore Bot.app** on an Intel Mac and ensure the control center is visible. Capture its overview and activity panel using **Shift–Command–4**, then Space, then click the window.
2. Click **Edit Config** and capture the built-in editor. Before capturing, replace or hide any passwords, tokens, radio IDs, personal messages, and private hostnames.
3. With a test bot and the web viewer running, open **Dashboard** and capture a clean browser view. Hide location, contacts and private mesh data.
4. Save the reviewed images as `docs/screenshots/mac-overview.png`, `docs/screenshots/mac-radio-connection.png` and `docs/screenshots/mac-config-editor.png` (window capture: `screencapture -o -l <window id>`). A `docs/screenshots/web-dashboard.png` can be added once there is a dashboard view with no private mesh data.
5. Once the files are committed, replace the screenshot table in the main README with these image links:

```markdown
![Intel Mac desktop overview](docs/screenshots/mac-overview.png)
![Built-in configuration editor](docs/screenshots/mac-config-editor.png)
![MeshCore Bot web dashboard](docs/screenshots/web-dashboard.png)
```

Do not add image links before the corresponding files exist. GitHub Actions currently builds the app but does not provide verified runtime screenshots. Do not imply that screenshot capture establishes radio connectivity or validates the quit issue.
