#!/usr/bin/env python3
"""Exercise tray registration and shutdown across watcher lifecycle changes."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
from typing import Callable


WATCHER_NAME = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
WATCHER_INTERFACE = "org.kde.StatusNotifierWatcher"
ITEM_BUS_NAME = "io.github.milofax.KeyLights.Tray"
WAIT_SECONDS = 3.0


@dataclass
class WatcherProcess:
    process: subprocess.Popen[str]
    registrations: Path
    entered: Path | None = None
    release: Path | None = None


def wait_for(predicate: Callable[[], bool], description: str) -> None:
    deadline = time.monotonic() + WAIT_SECONDS
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.01)
    raise RuntimeError(f"timed out waiting for {description}")


def run_watcher(
    ready_path: Path,
    registrations_path: Path,
    entered_path: Path | None = None,
    release_path: Path | None = None,
) -> int:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    lifecycle = {"stopping": False}
    reject_registration = os.environ.get("KEYLIGHTS_TEST_WATCHER_REJECT", "") == "1"

    class Watcher(dbus.service.Object):
        @dbus.service.method(WATCHER_INTERFACE, in_signature="s", out_signature="")
        def RegisterStatusNotifierItem(self, service: str) -> None:
            with registrations_path.open("a", encoding="utf-8") as registrations:
                registrations.write(f"{service}\n")
            if reject_registration:
                raise dbus.exceptions.DBusException("registration rejected by test watcher")
            if entered_path is None or release_path is None:
                return
            entered_path.touch()
            deadline = time.monotonic() + WAIT_SECONDS
            while (
                not release_path.exists()
                and not lifecycle["stopping"]
                and time.monotonic() < deadline
            ):
                time.sleep(0.01)

    watcher = Watcher(bus, WATCHER_PATH)
    bus_name = dbus.service.BusName(
        WATCHER_NAME,
        bus=bus,
        allow_replacement=False,
        replace_existing=False,
        do_not_queue=True,
    )
    loop = GLib.MainLoop()

    def stop_watcher(*_args: object) -> None:
        lifecycle["stopping"] = True
        loop.quit()

    signal.signal(signal.SIGTERM, stop_watcher)
    signal.signal(signal.SIGINT, stop_watcher)
    ready_path.touch()
    loop.run()
    watcher.remove_from_connection()
    bus.release_name(WATCHER_NAME)
    return 0


def registered(registrations_path: Path) -> bool:
    if not registrations_path.exists():
        return False
    return ITEM_BUS_NAME in registrations_path.read_text(encoding="utf-8").splitlines()


def stop(process: subprocess.Popen[str] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=WAIT_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=WAIT_SECONDS)


def start_watcher(
    test_dir: Path,
    label: str,
    blocked: bool = False,
    reject_registration: bool = False,
) -> WatcherProcess:
    ready_path = test_dir / f"{label}.ready"
    registrations_path = test_dir / f"{label}.registrations"
    entered_path = test_dir / f"{label}.entered" if blocked else None
    release_path = test_dir / f"{label}.release" if blocked else None
    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "--watcher",
        str(ready_path),
        str(registrations_path),
    ]
    if entered_path is not None and release_path is not None:
        command.extend([str(entered_path), str(release_path)])
    environment = os.environ.copy()
    if reject_registration:
        environment["KEYLIGHTS_TEST_WATCHER_REJECT"] = "1"
    process = subprocess.Popen(command, env=environment, text=True)
    wait_for(lambda: ready_path.exists() or process.poll() is not None, f"{label} startup")
    if process.poll() is not None:
        raise RuntimeError(f"{label} exited during startup with {process.returncode}")
    return WatcherProcess(process, registrations_path, entered_path, release_path)


def stop_watcher(watcher: WatcherProcess | None) -> None:
    if watcher is None:
        return
    if watcher.release is not None:
        watcher.release.touch()
    stop(watcher.process)


def start_helper(helper_path: Path, test_mode: str = "") -> subprocess.Popen[str]:
    environment = os.environ.copy()
    if test_mode:
        environment["KEYLIGHTS_TRAY_TEST"] = test_mode
    return subprocess.Popen(
        [str(helper_path)],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def wait_for_registration(
    watcher: WatcherProcess,
    helper: subprocess.Popen[str],
    description: str,
) -> None:
    wait_for(
        lambda: registered(watcher.registrations) or helper.poll() is not None,
        description,
    )
    if registered(watcher.registrations):
        if helper.stdout is None:
            raise RuntimeError("tray helper stdout was not captured")
        readable, _, _ = select.select([helper.stdout], [], [], WAIT_SECONDS)
        if not readable:
            raise RuntimeError(f"timed out waiting for readiness after {description}")
        line = helper.stdout.readline().strip()
        if line != "ready":
            raise RuntimeError(
                f"tray helper emitted {line!r} instead of readiness after {description}"
            )
        return
    stderr = helper.communicate(timeout=WAIT_SECONDS)[1].strip()
    raise RuntimeError(
        f"tray helper exited before {description} ({helper.returncode}): {stderr}"
    )


def restart_regression(helper_path: Path, test_dir: Path) -> None:
    first: WatcherProcess | None = None
    second: WatcherProcess | None = None
    helper: subprocess.Popen[str] | None = None
    try:
        first = start_watcher(test_dir, "restart-first")
        helper = start_helper(helper_path)
        wait_for_registration(first, helper, "the initial tray registration")
        stop_watcher(first)
        first = None
        second = start_watcher(test_dir, "restart-second")
        wait_for_registration(second, helper, "registration with the replacement watcher")
        print("PASS: Key Lights re-registered after the tray watcher restarted.")
    finally:
        stop(helper)
        stop_watcher(first)
        stop_watcher(second)


def initial_no_owner_regression(helper_path: Path) -> None:
    helper = start_helper(helper_path)
    try:
        wait_for(lambda: helper.poll() is not None, "initial missing-watcher grace")
        if helper.returncode != 4:
            raise RuntimeError(
                f"initial missing-watcher grace returned {helper.returncode}, expected 4"
            )
        print("PASS: initial missing watcher exited with status 4 after its short grace.")
    finally:
        stop(helper)


def initial_exhaustion_regression(helper_path: Path, test_dir: Path) -> None:
    watcher: WatcherProcess | None = None
    helper: subprocess.Popen[str] | None = None
    try:
        watcher = start_watcher(
            test_dir,
            "rejecting",
            reject_registration=True,
        )
        helper = start_helper(helper_path, "fast-watcher-retry")
        wait_for(lambda: helper.poll() is not None, "initial registration exhaustion")
        if helper.returncode != 4:
            raise RuntimeError(
                f"initial registration exhaustion returned {helper.returncode}, expected 4"
            )
        attempts = watcher.registrations.read_text(encoding="utf-8").splitlines()
        if len(attempts) != 3:
            raise RuntimeError(
                f"registration exhaustion made {len(attempts)} attempts, expected 3"
            )
        print("PASS: rejecting watcher exhausted three attempts and exited with status 4.")
    finally:
        stop(helper)
        stop_watcher(watcher)


def watcher_loss_regression(helper_path: Path, test_dir: Path) -> None:
    watcher: WatcherProcess | None = None
    helper: subprocess.Popen[str] | None = None
    try:
        watcher = start_watcher(test_dir, "loss")
        helper = start_helper(helper_path, "fast-watcher-retry")
        wait_for_registration(watcher, helper, "registration before watcher loss")
        stop_watcher(watcher)
        watcher = None
        wait_for(lambda: helper.poll() is not None, "registration exhaustion after watcher loss")
        if helper.returncode != 4:
            raise RuntimeError(
                f"watcher-loss exhaustion returned {helper.returncode}, expected 4"
            )
        print("PASS: watcher loss without replacement exited with status 4.")
    finally:
        stop(helper)
        stop_watcher(watcher)


def blocked_sigterm_regression(helper_path: Path, test_dir: Path) -> None:
    watcher: WatcherProcess | None = None
    helper: subprocess.Popen[str] | None = None
    try:
        watcher = start_watcher(test_dir, "blocked", blocked=True)
        helper = start_helper(helper_path)
        if watcher.entered is None or watcher.release is None:
            raise RuntimeError("blocked watcher fixture was not configured")
        wait_for(
            lambda: watcher.entered.exists() or helper.poll() is not None,
            "the blocked initial registration",
        )
        if helper.poll() is not None:
            raise RuntimeError(
                f"tray helper exited before blocked registration ({helper.returncode})"
            )
        helper.terminate()
        time.sleep(0.05)
        watcher.release.touch()
        wait_for(lambda: helper.poll() is not None, "SIGTERM during initial registration")
        if helper.returncode != 0:
            raise RuntimeError(f"SIGTERM shutdown returned {helper.returncode}, expected 0")
        print("PASS: SIGTERM during blocked initial registration exited cleanly.")
    finally:
        stop(helper)
        stop_watcher(watcher)


def run_regressions() -> int:
    if "DBUS_SESSION_BUS_ADDRESS" not in os.environ:
        print(
            "Run these regressions inside an isolated bus: "
            "dbus-run-session -- python3 tests/tray-restart-repro.py",
            file=sys.stderr,
        )
        return 2

    helper_path = Path(__file__).resolve().parents[1] / "bin" / "keylights-tray"
    with tempfile.TemporaryDirectory(prefix="keylights-tray-repro-") as raw_test_dir:
        test_dir = Path(raw_test_dir)
        restart_regression(helper_path, test_dir)
        initial_no_owner_regression(helper_path)
        initial_exhaustion_regression(helper_path, test_dir)
        watcher_loss_regression(helper_path, test_dir)
        blocked_sigterm_regression(helper_path, test_dir)
    print("All tray lifecycle regressions passed.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) in (4, 6) and sys.argv[1] == "--watcher":
        entered = Path(sys.argv[4]) if len(sys.argv) == 6 else None
        release = Path(sys.argv[5]) if len(sys.argv) == 6 else None
        raise SystemExit(
            run_watcher(Path(sys.argv[2]), Path(sys.argv[3]), entered, release)
        )
    if len(sys.argv) == 1:
        raise SystemExit(run_regressions())
    raise SystemExit("usage: tray-restart-repro.py")
