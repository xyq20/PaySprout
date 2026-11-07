"""Exercise the shipped installer in isolated app bundles, including rollback."""
import os
import plistlib
import signal
import subprocess
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
fixture_source = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc < 2) return 1;
    const char *folder = getenv("PAYSPROUT_TEST_WORKSPACE");
    if (!strcmp(argv[1], "--old")) { sleep(60); return 0; }
    if (!folder) return 1;
    if (!strcmp(argv[1], "--paysprout-updated") && getenv("PAYSPROUT_TEST_FAIL")) return 1;
    char path[4096];
    snprintf(path, sizeof(path), "%s/%s", folder,
        !strcmp(argv[1], "--paysprout-updated") ? "ready.txt" : "restored.txt");
    FILE *file = fopen(path, "w"); if (!file) return 1;
    fprintf(file, "%d", getpid()); fclose(file);
    if (!strcmp(argv[1], "--paysprout-updated")) sleep(3);
    return 0;
}
'''

with tempfile.TemporaryDirectory(prefix="PaySprout 更新 ' ") as temporary:
    base = Path(temporary)
    source = base / "fixture.c"
    source.write_text(fixture_source)
    executable = base / "fixture"
    subprocess.run(["xcrun", "clang", str(source), "-o", str(executable)], check=True)
    for failure in (False, True):
        workspace = base / ("rollback" if failure else "success")
        workspace.mkdir()
        target = workspace / "上班鼓励器.app"
        incoming = workspace / ".incoming.app"
        backup = workspace / ".previous.app"
        for app, version in ((target, "0.1.0"), (incoming, "0.1.1")):
            (app / "Contents/MacOS").mkdir(parents=True)
            (app / "Contents/MacOS/Encourager").write_bytes(executable.read_bytes())
            (app / "Contents/MacOS/Encourager").chmod(0o755)
            with (app / "Contents/Info.plist").open("wb") as handle:
                plistlib.dump({"CFBundleExecutable": "Encourager", "CFBundleIdentifier": "local.gentlework.encourager", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version}, handle)
            subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        environment = dict(os.environ, PAYSPROUT_TEST_WORKSPACE=str(workspace))
        if failure:
            environment["PAYSPROUT_TEST_FAIL"] = "1"
        old = subprocess.Popen([str(target / "Contents/MacOS/Encourager"), "--old"], env=environment)
        helper = subprocess.Popen(["/bin/sh", str(root / "Resources/install-update-macos.sh"), str(old.pid), str(target), str(incoming), str(backup), str(workspace), "fixture"], env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        old.terminate()
        old.wait(timeout=10)
        output, errors = helper.communicate(timeout=45)
        status = (workspace / "result.txt").read_text().strip()
        assert status == ("rolled-back" if failure else "installed"), (status, errors)
        assert helper.returncode == (1 if failure else 0), (helper.returncode, errors)
        with (target / "Contents/Info.plist").open("rb") as handle:
            assert plistlib.load(handle)["CFBundleShortVersionString"] == ("0.1.0" if failure else "0.1.1")
        if failure:
            for _ in range(30):
                if (workspace / "restored.txt").exists():
                    break
                time.sleep(0.1)
            assert (workspace / "restored.txt").exists(), "Restored app did not launch"
        else:
            try:
                os.kill(int((workspace / "ready.txt").read_text()), signal.SIGTERM)
            except ProcessLookupError:
                pass
            assert not backup.exists()
        print("Passed Mac installer:", status, "(isolated paths with spaces, quotes and Chinese)")
