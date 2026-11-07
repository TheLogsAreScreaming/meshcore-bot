"""Compile the Intel Mac app and exercise its INI helpers when a Swift toolchain is present."""
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "macos/MeshCoreDesktop.swift").read_text()
MAIN = "let app = NSApplication.shared\nlet delegate = MeshCoreDesktop()\napp.delegate = delegate\napp.run()\n"

HARNESS = r'''
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: " + message); exit(1) }
}
let ini = "[Bot]\nbot_name = Test\n\n[Connection]\n# serial_port = /dev/commented\nconnection_type = serial\nserial_port = /dev/ttyUSB0\n\n[Web_Viewer]\nenabled = false\nport = 8080\n"
check(MeshCoreDesktop.iniValue("serial_port", section: "Connection", in: ini) == "/dev/ttyUSB0", "reads value, skipping comments")
check(MeshCoreDesktop.iniValue("port", section: "Web_Viewer", in: ini) == "8080", "reads last section")
check(MeshCoreDesktop.iniValue("missing", section: "Connection", in: ini) == nil, "missing key is nil")
check(MeshCoreDesktop.iniValue("port", section: "Nope", in: ini) == nil, "missing section is nil")
let updated = MeshCoreDesktop.settingIniValue("serial_port", "/dev/cu.usbmodem1", section: "Connection", in: ini)
check(MeshCoreDesktop.iniValue("serial_port", section: "Connection", in: updated) == "/dev/cu.usbmodem1", "updates in place")
check(updated.contains("# serial_port = /dev/commented"), "comments survive")
check(updated.components(separatedBy: "\n").filter { $0.hasPrefix("serial_port =") }.count == 1, "no duplicate key")
let added = MeshCoreDesktop.settingIniValue("auto_start", "true", section: "Web_Viewer", in: updated)
check(MeshCoreDesktop.iniValue("auto_start", section: "Web_Viewer", in: added) == "true", "adds missing key")
check(MeshCoreDesktop.iniValue("bot_name", section: "Bot", in: added) == "Test", "other sections untouched")
let newSection = MeshCoreDesktop.settingIniValue("enabled", "true", section: "Extra", in: ini)
check(MeshCoreDesktop.iniValue("enabled", section: "Extra", in: newSection) == "true", "creates missing section")
check(MeshCoreDesktop.iniValue("enabled", section: "Web_Viewer", in: newSection) == "false", "keeps other values")
print("ini helpers ok")
'''


pytestmark = [
    # Needs the macOS SDK (AppKit); Linux runners may have swiftc without it.
    pytest.mark.skipif(sys.platform != "darwin" or shutil.which("swiftc") is None,
                       reason="macOS Swift toolchain not available"),
    # Optimised Swift builds of the whole app take longer than the suite-wide default.
    pytest.mark.timeout(900),
]


def test_app_compiles_and_ini_helpers_preserve_comments(tmp_path):
    """Builds the full app source (so it must type-check) and runs the INI helper checks."""
    assert MAIN in SOURCE
    harness = tmp_path / "main.swift"
    harness.write_text(SOURCE.replace(MAIN, HARNESS))
    binary = tmp_path / "ini-check"
    build = subprocess.run(
        ["swiftc", "-module-cache-path", str(tmp_path / "cache"), "-target", "x86_64-apple-macos11.0",
         "-framework", "AppKit", str(harness), "-o", str(binary)],
        capture_output=True, text=True, timeout=600,
    )
    assert build.returncode == 0, build.stderr
    run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    assert run.returncode == 0 and "ini helpers ok" in run.stdout, run.stdout + run.stderr
