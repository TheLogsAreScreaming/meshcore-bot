"""Static checks for the Intel Mac UI fixes found during hardware smoke testing."""
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "macos/MeshCoreDesktop.swift").read_text()


def test_config_editor_is_native_and_in_window():
    page = SOURCE.split("private func buildConfigurationPage()", 1)[1].split("func textDidChange(", 1)[0]
    assert "NSTextView" in page
    for title in ('"Save"', '"Revert"', '"Restore Backup…"'):
        assert title in page
    assert "NSWorkspace.shared.open(config)" not in SOURCE
    assert "TextEdit.app" not in SOURCE


def test_config_editor_disables_smart_substitutions():
    # Smart quotes/dashes silently corrupt INI values typed in the editor.
    page = SOURCE.split("private func buildConfigurationPage()", 1)[1].split("func textDidChange(", 1)[0]
    for flag in ("isAutomaticQuoteSubstitutionEnabled = false",
                 "isAutomaticDashSubstitutionEnabled = false",
                 "isAutomaticTextReplacementEnabled = false"):
        assert flag in page


def test_unsaved_config_prompts_before_close_or_quit():
    assert "func windowShouldClose(" in SOURCE
    quit_section = SOURCE.split("func applicationShouldTerminate(", 1)[1].split("func applicationShouldTerminateAfterLastWindowClosed", 1)[0]
    assert "confirmDiscardOrSaveUnsavedConfig()" in quit_section
    assert ".terminateCancel" in quit_section


def test_app_quit_does_not_wait_synchronously_for_bot():
    section = SOURCE.split("func applicationShouldTerminate(", 1)[1].split("func applicationShouldTerminateAfterLastWindowClosed", 1)[0]
    assert "readabilityHandler = nil" in section
    assert "running.terminate()" in section
    assert "waitUntilExit()" not in section


def test_ui_preserves_controls_and_status():
    for name in ("Start Bot", "Stop Bot", "Edit Config", "Open Dashboard", "Open Bot Folder"):
        assert name in SOURCE
    for page in ("Overview", "Radio & Connection", "Configuration", "Activity Log", "Help & Files"):
        assert f'return "{page}"' in SOURCE


def test_sidebar_items_are_real_navigation_controls():
    sidebar = SOURCE.split("private func buildSidebar(", 1)[1].split("@objc private func selectSection(", 1)[0]
    assert "NSButton(title: section.title, target: self, action: #selector(selectSection(_:)))" in sidebar


def test_main_menu_provides_edit_commands_and_shortcuts():
    # Without an Edit menu, Cmd-C/Cmd-V/Cmd-Z do nothing in AppKit text views.
    menu = SOURCE.split("private func buildMainMenu()", 1)[1].split("func validateMenuItem(", 1)[0]
    for selector in ("NSText.copy(_:)", "NSText.paste(_:)", "NSText.cut(_:)", "NSText.selectAll(_:)", '"undo:"'):
        assert selector in menu
    assert 'item("Quit MeshCore Bot"' in menu
    assert 'item("Save Configuration", #selector(saveConfig), "s")' in menu


def test_styling_comes_from_the_design_system():
    # Raw colors and fonts are defined once, in Theme, not scattered through views.
    body = SOURCE.split("// MARK: - Reusable components", 1)[1]
    assert "NSColor(srgbRed" not in body
    assert "NSFont.systemFont(ofSize" not in body
    assert "window.appearance = NSAppearance(named: .darkAqua)" not in SOURCE


def test_page_transition_respects_reduce_motion():
    assert "accessibilityDisplayShouldReduceMotion" in SOURCE


def test_log_strips_terminal_color_codes():
    log = SOURCE.split("private func appendLog(", 1)[1].split("private func showError(", 1)[0]
    assert "removingTerminalCodes(s)" in log


def test_key_value_grid_keeps_values_beside_keys():
    grid = SOURCE.split("static func keyValueGrid(", 1)[1].split("static func formGrid(", 1)[0]
    assert "grid.column(at: 0).width" in grid
    assert "grid.column(at: 1).xPlacement = .leading" in grid


def test_labels_cannot_lock_the_window_width():
    # A label left on autoresizing constraints froze the window at 916 pt in full screen.
    for factory, end in (("static func label(", "static func paragraph("),
                         ("static func paragraph(", "static func sectionLabel(")):
        body = SOURCE.split(factory, 1)[1].split(end, 1)[0]
        assert "translatesAutoresizingMaskIntoConstraints = false" in body


def test_radio_connect_failure_gets_its_own_status():
    # The bot exits with code 0 when it can't reach the radio, which used to
    # leave Overview saying a plain "Stopped" with the error scrolled away.
    marker = 'connectFailureMarker = "Failed to connect to MeshCore node"'
    assert marker in SOURCE
    core = (Path(__file__).resolve().parents[1] / "modules/core.py").read_text()
    assert 'self.logger.error("Failed to connect to MeshCore node")' in core
    handler = SOURCE.split("p.terminationHandler = {", 1)[1].split("do {", 1)[0]
    assert "!requested && couldNotConnect" in handler
    assert "self.state = .couldNotConnect" in handler
    assert 'title: "Couldn\'t connect to the radio"' in SOURCE


def test_bot_menu_opens_the_nearby_repeater_test():
    # The Mac menu item must land on the dashboard section that starts the test.
    assert 'item("Test Nearby Repeaters", #selector(testNearbyRepeaters))' in SOURCE
    action = SOURCE.split("@objc private func testNearbyRepeaters()", 1)[1].split("}", 1)[0]
    assert 'path: "/radio"' in action and 'fragment: "nearby-test"' in action
    radio = (Path(__file__).resolve().parents[1] / "modules/web_viewer/templates/radio.html").read_text()
    assert 'id="nearby-test"' in radio
    assert "window.location.hash === '#nearby-test'" in radio
    # Only offered while the bot (and so the dashboard) is running.
    assert "#selector(testNearbyRepeaters): return process?.isRunning == true" in SOURCE
    # The dashboard address stays on loopback whichever page is opened.
    page = SOURCE.split("private func openDashboardPage(", 1)[1].split("// MARK: INI helpers", 1)[0]
    assert 'let host = "127.0.0.1"' in page
