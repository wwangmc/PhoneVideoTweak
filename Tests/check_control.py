"""Verify standalone packaging and desktop/plugin route compatibility without Theos."""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "Sources/Control"


def main():
    server = (CONTROL / "PMControlServer.xm").read_text(encoding="utf-8")
    required = {
        "/deviceInfo", "/screenshot", "/screenshot_original", "/touch", "/input",
        "/keypress", "/del", "/moveCursor", "/pressHome", "/doublePressHome",
        "/pressPowerBtn", "/setAllSetting", "/runShell",
    }
    registered = set(re.findall(r'(?:path:|server,)\s*@"(/[^"?]*)"', server))
    assert required <= registered, f"Missing desktop routes: {required - registered}"
    assert "GCDWebServerOption_BindToLocalhost: @YES" in server
    assert "#define PM_CONTROL_PORT 27185" in (CONTROL / "PMControlServer.h").read_text()
    assert not re.search(r'@"/(?:apps|keychain|setLocation|resetAV|readPlist)"', server)
    assert "writeToFile:" not in server and "PMControlSaveCarrierSettings" not in server

    library = CONTROL / "libs/libGCDWebServers.a"
    assert hashlib.sha256(library.read_bytes()).hexdigest() == "aa53767ad3938f3fc35a85669953621525118b38c46e01082ffc00b55e677a41"
    notification = "com.phonemanager.phonevideo.keyboard"
    for name in ["PMControlServer.xm", "PMControlSocketHandler.xm"]:
        text = (CONTROL / name).read_text(encoding="utf-8")
        assert notification in text and "com.csmk.keyboardcontrol" not in text
    assert notification in (ROOT / "Sources/Keyboard/PMKeyboard.m").read_text(encoding="utf-8")
    helper = "/usr/local/bin/phonevideo-roothelp"
    assert helper in (CONTROL / "PMControlExecutor.xm").read_text(encoding="utf-8")
    makefile = (ROOT / "Makefile").read_text()
    for token in ["PhoneVideoKeyboard", "RootHelper/main.m", "RootHelper/TSUtil.m", "-lGCDWebServers"]:
        assert token in makefile, f"Missing build dependency: {token}"
    for path in [ROOT / "RootHelper/entitlements.plist", ROOT / "PhoneVideoKeyboard.plist"]:
        assert path.is_file()
    for path in (ROOT / "Sources").rglob("*"):
        if path.suffix in {".h", ".m", ".xm"}:
            for include in re.findall(r'^\s*#(?:import|include)\s+"([^"]+)"', path.read_text(encoding="utf-8"), re.M):
                assert any((base / include).is_file() for base in [path.parent, CONTROL / "hid"]), (path, include)

    # Optional cross-project check in the PhoneManager workspace; standalone CI
    # still verifies the fixed main-branch contract above.
    desktop = ROOT.parent / "GoScrcpy"
    if desktop.is_dir():
        client = (desktop / "internal/phonevideo/client.go").read_text(encoding="utf-8")
        assert "Port uint16 = 27185" in client and "LegacyPort uint16 = 8081" in client
        paths = set()
        for directory in [desktop / "internal/phonevideo", desktop / "internal/iossettings", desktop / "internal/mobileshell"]:
            for path in directory.glob("*.go"):
                if path.name.endswith("_test.go"):
                    continue
                paths.update(re.findall(r'"(/[A-Za-z][A-Za-z_]*)(?:[?" ])', path.read_text(encoding="utf-8")))
        assert paths <= registered, f"Unimplemented Go callers: {paths - registered}"
        assert not (desktop / "internal/iossettings/data/opt.json").exists()
    print("PASS: standalone dependencies, keyboard/helper isolation, desktop routes, control ports and library hash")


if __name__ == "__main__":
    main()
