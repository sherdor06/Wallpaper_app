#!/usr/bin/env python3
"""Find and repair the states that stop this app from building.

Every check here is a failure that has actually happened on this project,
paired with the fix that worked. Run it whenever `flutter run` dies before
the app starts — on the simulator, the emulator or a device:

    python3 scripts/doctor.py           # check, and repair what is safe
    python3 scripts/doctor.py --clean   # wipe build output and Pods first

Repairs that only regenerate local state (the Flutter engine cache, pub get,
pod install, stale build copies) run on their own. Anything that would change
a tracked file — a dependency upgrade, a pubspec edit — is reported with the
command to run, never applied behind your back.

Standard library only; no venv needed.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"

failures: list[str] = []


def report(status: str, message: str) -> None:
    print(f"  [{status}] {message}")
    if status == "FAIL":
        failures.append(message)


def run(cmd: list[str], cwd: Path = ROOT, env: dict | None = None,
        quiet: bool = False) -> bool:
    """Runs a repair command. True on success.

    [quiet] holds the output back and shows its tail only on failure — for
    commands like pub get whose success is sixty lines of "x.y available".
    """
    print(f"      $ {' '.join(cmd)}")
    if not quiet:
        return subprocess.run(cmd, cwd=cwd, env=env).returncode == 0
    done = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    if done.returncode != 0:
        print("\n".join((done.stdout + done.stderr).splitlines()[-25:]))
    return done.returncode == 0


def flutter_root() -> Path | None:
    exe = shutil.which("flutter")
    return Path(exe).resolve().parent.parent if exe else None


# --- Flutter engine cache ---------------------------------------------------
# Seen: every simulator `Flutter` binary vanished from the SDK's engine cache
# (debug, profile and release at once; device slices untouched). Builds then
# fail at "Run Prepare Flutter Framework Script" with "Binary …/Flutter does
# not exist, cannot thin" — and keep failing, because each build copies the
# broken framework out of the cache again.

def check_engine() -> None:
    root = flutter_root()
    if root is None:
        report("FAIL", "flutter is not on PATH")
        return

    def missing() -> list[str]:
        engine = root / "bin/cache/artifacts/engine"
        gone = []
        for mode in ("ios", "ios-profile", "ios-release"):
            for slice_ in ("ios-arm64", "ios-arm64_x86_64-simulator"):
                binary = (engine / mode / "Flutter.xcframework" / slice_
                          / "Flutter.framework" / "Flutter")
                if not binary.is_file():
                    gone.append(f"{mode}/{slice_}")
        return gone

    gone = missing()
    if not gone:
        report("ok", "Flutter iOS engine artifacts are complete")
    else:
        report("fixed" if run(["flutter", "precache", "--ios", "--force"])
               and not missing() else "FAIL",
               f"Flutter engine cache was missing {', '.join(gone)}")

    # A framework already copied out of a broken cache stays broken in build/.
    for framework in (ROOT / "build/ios").glob("*/Flutter.framework"):
        if not (framework / "Flutter").is_file():
            shutil.rmtree(framework)
            report("fixed", f"removed a Flutter.framework without its binary "
                            f"from build/ios/{framework.parent.name}")


# --- Dart packages ----------------------------------------------------------

def check_pub() -> None:
    report("ok" if run(["flutter", "pub", "get"], quiet=True) else "FAIL",
           "flutter pub get")


# --- FlutterFire lockstep ---------------------------------------------------
# Seen: adding firebase_messaging moved remote_config to a release built on
# firebase-ios-sdk 12.18.0 while crashlytics stayed on 12.17.0. Each plugin
# pins its SDK exactly, so the two could not resolve together. Pub cannot see
# this — the conflict lives on the native side.

def check_firebase() -> None:
    lock = (ROOT / "pubspec.lock").read_text()
    plugins = {
        m.group(1): m.group(2)
        for m in re.finditer(
            r'^  (firebase_[a-z_]+):\n(?:    .*\n)*?    version: "([^"]+)"',
            lock, re.M)
        if not m.group(1).endswith(("_platform_interface", "_web"))
    }
    cache = Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))
    pins: dict[str, str] = {}
    for name, version in plugins.items():
        for spec in (cache / "hosted/pub.dev" / f"{name}-{version}"
                     / "ios").glob("*/Package.swift"):
            m = re.search(r'firebaseSdkVersion:\s*Version\s*=\s*"([^"]+)"',
                          spec.read_text())
            if m:
                pins[name] = m.group(1)
    if len(set(pins.values())) <= 1:
        sdk = next(iter(pins.values()), "?")
        report("ok", f"Firebase plugins agree on firebase-ios-sdk {sdk}")
        return
    detail = ", ".join(f"{n} {plugins[n]} -> {p}" for n, p in sorted(pins.items()))
    report("FAIL", "Firebase plugins come from different releases "
                   f"({detail}). Upgrade them together:\n"
                   "        flutter pub upgrade " + " ".join(sorted(plugins)))


# --- Swift Package Manager --------------------------------------------------
# Seen: yandex_mobileads is CocoaPods-only and its pod pulls KSCrash; with SPM
# on, appmetrica_plugin pulled a second KSCrash through SPM and the link
# failed on 2183 duplicate symbols. The project opts out of SPM in pubspec.

def check_spm() -> None:
    if re.search(r"^\s+enable-swift-package-manager:\s*false\b",
                 (ROOT / "pubspec.yaml").read_text(), re.M):
        report("ok", "Swift Package Manager is off for this project")
    else:
        report("FAIL", "pubspec.yaml no longer turns Swift Package Manager "
                       "off — KSCrash will link twice. Restore "
                       "`config: enable-swift-package-manager: false` under "
                       "`flutter:`")


# --- CocoaPods --------------------------------------------------------------
# Seen: Xcode refusing to build with "The sandbox is not in sync with the
# Podfile.lock" after an interrupted pod install left no Pods/Manifest.lock.
# pod install also needs a UTF-8 locale, or CocoaPods' own error reporter
# crashes and hides the real error.

def check_pods() -> None:
    lock, manifest = IOS / "Podfile.lock", IOS / "Pods/Manifest.lock"
    if lock.is_file() and manifest.is_file() and \
            lock.read_bytes() == manifest.read_bytes():
        report("ok", "CocoaPods sandbox matches Podfile.lock")
        return
    if shutil.which("pod") is None:
        report("FAIL", "CocoaPods is not installed (brew install cocoapods)")
        return
    env = {**os.environ, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"}
    ok = run(["pod", "install"], cwd=IOS, env=env) and \
        manifest.is_file() and lock.read_bytes() == manifest.read_bytes()
    report("fixed" if ok else "FAIL",
           "CocoaPods sandbox was out of sync with Podfile.lock")


# --- Android: JDK -----------------------------------------------------------
# Seen: Android Studio's bundled JDK 25 broke Gradle's embedded Kotlin with a
# bare "25.0.2" error. Flutter is pointed at JDK 21 with `flutter config`.

def check_jdk() -> None:
    out = subprocess.run(["flutter", "config", "--list"],
                         capture_output=True, text=True).stdout
    m = re.search(r"jdk-dir:\s*(\S.*)", out)
    java = Path(m.group(1).strip()) / "bin/java" if m else shutil.which("java")
    if not java or not Path(java).exists():
        report("FAIL", "no JDK found for Gradle — install JDK 21 and run "
                       "`flutter config --jdk-dir=<its Home>`")
        return
    version = subprocess.run([str(java), "-version"], capture_output=True,
                             text=True).stderr
    major = re.search(r'version "(\d+)', version)
    major = int(major.group(1)) if major else 0
    if 17 <= major <= 21:
        report("ok", f"Gradle runs on JDK {major}")
    else:
        report("warn", f"Gradle runs on JDK {major}; this project is known "
                       "good on 17–21. If Android builds fail with a bare "
                       "version number, run `flutter config --jdk-dir=` "
                       "with a JDK 21 home")


# --- Xcode ------------------------------------------------------------------
# Seen: with the Xcode app open on this workspace, `flutter run` failed with
# "Could not compute dependency graph", and Xcode started its own package
# resolution that the command-line build then queued behind for minutes.

def check_xcode() -> None:
    running = subprocess.run(["pgrep", "-x", "Xcode"],
                             capture_output=True).returncode == 0
    if running:
        report("warn", "Xcode is open. Close it while running from Android "
                       "Studio or the terminal — two build services on one "
                       "workspace fail with \"Could not compute dependency "
                       "graph\"")
    else:
        report("ok", "Xcode is not competing for the workspace")


def clean() -> None:
    print("Cleaning build output and Pods…")
    run(["flutter", "clean"])
    for path in (IOS / "Pods", IOS / ".symlinks"):
        if path.exists():
            shutil.rmtree(path)
            print(f"      removed {path.relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--clean", action="store_true",
                        help="wipe build/, ios/Pods and ios/.symlinks first")
    args = parser.parse_args()

    os.chdir(ROOT)
    if args.clean:
        clean()

    # Order matters: pub get writes the files pod install reads, and the
    # engine has to be whole before anything copies it into build/.
    for title, check in (
        ("Flutter SDK", check_engine),
        ("Dart packages", check_pub),
        ("Firebase", check_firebase),
        ("Swift Package Manager", check_spm),
        ("CocoaPods", check_pods),
        ("Android JDK", check_jdk),
        ("Xcode", check_xcode),
    ):
        print(title)
        check()

    print()
    if failures:
        print(f"{len(failures)} problem(s) need you — see [FAIL] above.")
        return 1
    print("Ready to build.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
