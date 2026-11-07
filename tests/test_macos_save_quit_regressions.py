"""Regression checks for user-reported Intel Mac desktop issues."""
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / "macos/MeshCoreDesktop.swift").read_text()


def test_config_save_reports_errors():
    editor = SOURCE.split("@objc private func saveConfig()", 1)[1].split("@objc private func openFolder()", 1)[0]
    assert "Could not save config.ini:" in editor
    assert "config.ini.bak.pending" in editor
    assert "updated.write(to: config, atomically: true" in editor


def test_shutdown_clears_pipe_reader_without_waiting():
    shutdown = SOURCE.split("func applicationShouldTerminate(", 1)[1].split("func applicationShouldTerminateAfterLastWindowClosed", 1)[0]
    assert "logPipe?.fileHandleForReading.readabilityHandler = nil" in shutdown
    assert "running.terminationHandler = nil" in shutdown
    assert "running.terminate()" in shutdown
    assert "waitUntilExit" not in shutdown


def test_quit_when_last_window_closes():
    assert "func applicationShouldTerminateAfterLastWindowClosed" in SOURCE
    assert "true" in SOURCE.split("func applicationShouldTerminateAfterLastWindowClosed", 1)[1].split("private func createConfigIfNeeded", 1)[0]
