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
