"""Protect critical Intel Mac configuration editor safety guarantees."""
from pathlib import Path

SWIFT = (Path(__file__).resolve().parents[1] / "macos/MeshCoreDesktop.swift").read_text()
# The save path: the editor's Save action, its helper, and the single config writer.
EDITOR = SWIFT.split("@objc private func saveConfig()", 1)[1].split("@objc private func openFolder()", 1)[0]


def test_config_is_not_overwritten_without_changes():
    assert "guard updated != contents else { return true }" in EDITOR


def test_empty_and_missing_required_sections_rejected():
    assert "trimmingCharacters(in: .whitespacesAndNewlines).isEmpty" in EDITOR
    assert "let sectionHeaders = Set(" in EDITOR
    assert 'sectionHeaders.contains("[Connection]")' in EDITOR
    assert 'sectionHeaders.contains("[Bot]")' in EDITOR


def test_backup_created_before_atomic_write():
    assert "config.ini.bak" in EDITOR
    assert EDITOR.index("copyItem(at: config") < EDITOR.index("updated.write(to: config")
    assert "atomically: true" in EDITOR


def test_config_editor_does_not_invoke_external_textedit():
    assert "TextEdit.app" not in EDITOR
    assert "NSWorkspace.shared.open" not in EDITOR


def test_every_config_write_goes_through_the_safe_writer():
    # Only writeConfigSafely may write config.ini after first-launch seeding.
    writes = SWIFT.count("write(to: config, atomically: true")
    seeding = SWIFT.split("private func createConfigIfNeeded()", 1)[1].split("// MARK: Menu bar", 1)[0]
    assert writes == seeding.count("write(to: config, atomically: true") + 1
    assert "private func writeConfigSafely(" in EDITOR


def test_restore_backup_requires_confirmation_and_uses_safe_writer():
    restore = SWIFT.split("@objc private func restoreBackup()", 1)[1].split("private func confirmDiscardOrSaveUnsavedConfig", 1)[0]
    assert "hasDestructiveAction = true" in restore
    assert 'addButton(withTitle: "Cancel")' in restore
    assert "writeConfigSafely(backupText)" in restore
