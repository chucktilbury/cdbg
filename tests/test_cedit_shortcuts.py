"""Drive cedit with real X key events and window-manager close.

Ctrl+W must close only the focused tab, while Ctrl+Q and the window close
button must quit cleanly; closing from inside a shortcut callback previously
aborted with "cannot release an in-flight registration".
"""

import argparse
import ctypes
import os
from pathlib import Path
import subprocess
import tempfile
import time

from gtk_support import headless
from program_runner import environment


class XEventData(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong),
                ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
                ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                ("format", ctypes.c_int), ("data", ctypes.c_long * 5)]


class XEvent(ctypes.Union):
    _fields_ = [("client", XEventData), ("pad", ctypes.c_long * 24)]


class Display:
    def __init__(self, name: str):
        self.x11 = ctypes.CDLL("libX11.so.6")
        self.xtest = ctypes.CDLL("libXtst.so.6")
        x11, xtest = self.x11, self.xtest
        x11.XOpenDisplay.restype = ctypes.c_void_p
        x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
        x11.XStringToKeysym.restype = ctypes.c_ulong
        x11.XStringToKeysym.argtypes = [ctypes.c_char_p]
        x11.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x11.XDefaultRootWindow.restype = ctypes.c_ulong
        x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        x11.XQueryPointer.argtypes = [ctypes.c_void_p, ctypes.c_ulong] + [ctypes.c_void_p] * 7
        x11.XSetInputFocus.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                                       ctypes.c_ulong]
        x11.XCreateSimpleWindow.restype = ctypes.c_ulong
        x11.XCreateSimpleWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong,
                                            ctypes.c_int, ctypes.c_int,
                                            ctypes.c_uint, ctypes.c_uint, ctypes.c_uint,
                                            ctypes.c_ulong, ctypes.c_ulong]
        x11.XMapWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x11.XDestroyWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x11.XInternAtom.restype = ctypes.c_ulong
        x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
        x11.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                                   ctypes.c_long, ctypes.POINTER(XEvent)]
        x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
        xtest.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int,
                                            ctypes.c_ulong]
        xtest.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                               ctypes.c_int, ctypes.c_ulong]
        xtest.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int,
                                               ctypes.c_ulong]
        self.display = x11.XOpenDisplay(name.encode())
        assert self.display, f"cannot open X display {name}"
        self.root = x11.XDefaultRootWindow(self.display)

    def close(self) -> None:
        self.x11.XCloseDisplay(self.display)

    def settle(self, delay: float = 0.5) -> None:
        self.x11.XSync(self.display, 0)
        time.sleep(delay)

    def window_at(self, x: int, y: int) -> int:
        self.xtest.XTestFakeMotionEvent(self.display, -1, x, y, 0)
        self.x11.XSync(self.display, 0)
        root, child = ctypes.c_ulong(), ctypes.c_ulong()
        value = ctypes.c_int()
        mask = ctypes.c_uint()
        self.x11.XQueryPointer(self.display, self.root, ctypes.byref(root),
                               ctypes.byref(child), ctypes.byref(value),
                               ctypes.byref(value), ctypes.byref(value),
                               ctypes.byref(value), ctypes.byref(mask))
        return child.value

    def focus_editor(self, x: int = 500, y: int = 400) -> int:
        """Click into the source view; no window manager runs, so focus explicitly."""
        deadline = time.monotonic() + 15
        window = 0
        while not window and time.monotonic() < deadline:
            window = self.window_at(x, y)
            if not window:
                time.sleep(0.1)
        assert window, "cedit window never appeared"
        time.sleep(0.5)
        # The pointer entered while GTK was mapping/layouting the notebook.
        # Move again so GTK repicks the now-allocated SourceView as its target.
        self.xtest.XTestFakeMotionEvent(self.display, -1, x + 1, y, 0)
        self.xtest.XTestFakeMotionEvent(self.display, -1, x, y, 0)
        self.x11.XSetInputFocus(self.display, window, 1, 0)
        self.xtest.XTestFakeButtonEvent(self.display, 1, 1, 0)
        self.xtest.XTestFakeButtonEvent(self.display, 1, 0, 0)
        self.settle()
        return window

    def keys(self, combo: str) -> None:
        codes = [self.x11.XKeysymToKeycode(self.display, self.x11.XStringToKeysym(name.encode()))
                 for name in combo.split("+")]
        assert all(codes), combo
        for code in codes:
            self.xtest.XTestFakeKeyEvent(self.display, code, 1, 0)
        for code in reversed(codes):
            self.xtest.XTestFakeKeyEvent(self.display, code, 0, 0)
        self.settle()

    def delete_window(self, window: int) -> None:
        event = XEvent()
        event.client.type = 33  # ClientMessage
        event.client.window = window
        event.client.message_type = self.x11.XInternAtom(self.display, b"WM_PROTOCOLS", 0)
        event.client.format = 32
        event.client.data[0] = self.x11.XInternAtom(self.display, b"WM_DELETE_WINDOW", 0)
        assert self.x11.XSendEvent(self.display, window, 0, 0, ctypes.byref(event))
        self.settle()


def finish(process: subprocess.Popen, expect_running: bool) -> str:
    if expect_running:
        assert process.poll() is None, (
            f"cedit exited with {process.returncode}:\n{process.communicate()[0]}")
        process.terminate()
        output = process.communicate(timeout=10)[0]
    else:
        output = process.communicate(timeout=10)[0]
        assert process.returncode == 0, f"cedit exited with {process.returncode}:\n{output}"
    for marker in ("callback error", "in-flight", "CRITICAL", "AddressSanitizer",
                   "runtime error:", "LeakSanitizer"):
        assert marker not in output, output
    return output


def scenario(executable: Path, work: Path, env: dict[str, str], name: str, action) -> None:
    case = work / name
    case.mkdir(parents=True, exist_ok=True)
    for file_name, text in (("a.txt", "hello\n"), ("b.txt", "world\n")):
        (case / file_name).write_text(text)
    case_env = dict(env, HOME=str(case / "home"), XDG_CONFIG_HOME=str(case / "config"))
    if name == "focus_save":
        settings = case / "config/cwhip/settings.toml"
        settings.parent.mkdir(parents=True, exist_ok=True)
        settings.write_text("version = 1\n[editor]\nsave_on_window_loss = true\n")
    process = subprocess.Popen([str(executable), "--foreground", "a.txt", "b.txt"], cwd=case, env=case_env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    display = Display(env["DISPLAY"])
    try:
        action(display, process, case)
    finally:
        display.close()
        if process.poll() is None:
            process.kill()
            process.communicate()
    print(f"PASS {name}")


def close_tabs(display: Display, process: subprocess.Popen, case: Path) -> None:
    display.focus_editor()
    display.keys("Control_L+w")  # closes b.txt only
    assert process.poll() is None, "Ctrl+W must not quit cedit"
    display.keys("x")
    display.keys("Control_L+s")
    saved_path = case / "a.txt"
    deadline = time.monotonic() + 5
    saved = saved_path.read_text()
    while "x" not in saved and time.monotonic() < deadline:
        time.sleep(0.05)
        saved = saved_path.read_text()
    assert "x" in saved and "hello" in saved, saved
    assert (case / "b.txt").read_text() == "world\n"
    display.keys("Control_L+w")  # closes the last tab; a fresh Untitled replaces it
    display.keys("Control_L+w")  # closes that Untitled; another replaces it
    finish(process, expect_running=True)


def dirty_close(display: Display, process: subprocess.Popen, case: Path) -> None:
    display.focus_editor()
    display.keys("x")
    display.keys("Control_L+w")  # prompts Save/Discard/Cancel instead of closing
    display.keys("Control_L+q")  # a pending prompt blocks quitting
    finish(process, expect_running=True)
    assert (case / "b.txt").read_text() == "world\n"


def quit_shortcut(display: Display, process: subprocess.Popen, case: Path) -> None:
    display.focus_editor()
    display.keys("Control_L+q")
    finish(process, expect_running=False)


def quit_after_close(display: Display, process: subprocess.Popen, case: Path) -> None:
    display.focus_editor()
    display.keys("Control_L+w")
    display.keys("Control_L+q")
    finish(process, expect_running=False)


def window_close(display: Display, process: subprocess.Popen, case: Path) -> None:
    window = display.focus_editor()
    display.delete_window(window)
    finish(process, expect_running=False)


def focus_save(display: Display, process: subprocess.Popen, case: Path) -> None:
    display.focus_editor()
    display.keys("x")
    assert (case / "b.txt").read_text() == "world\n", "save must wait for loss of focus"
    sink = display.x11.XCreateSimpleWindow(display.display, display.root,
                                           0, 0, 100, 100, 0, 0, 0)
    assert sink, "focus target window"
    try:
        display.x11.XMapWindow(display.display, sink)
        display.settle()
        display.x11.XSetInputFocus(display.display, sink, 1, 0)
        display.settle()
        deadline = time.monotonic() + 5
        while "x" not in (case / "b.txt").read_text() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert "x" in (case / "b.txt").read_text(), "native window focus loss must save"
    finally:
        display.x11.XDestroyWindow(display.display, sink)
        display.settle()
    display.focus_editor()
    display.keys("Control_L+q")
    finish(process, expect_running=False)


def background_startup(executable: Path, work: Path, env: dict[str, str]) -> None:
    """Reap the detached GUI explicitly instead of leaking a test process."""
    libc = ctypes.CDLL(None)
    assert libc.prctl(36, 1, 0, 0, 0) == 0  # PR_SET_CHILD_SUBREAPER (Linux)
    children_path = Path(f"/proc/{os.getpid()}/task/{os.getpid()}/children")
    before = set(children_path.read_text().split())
    case = work / "background"
    case.mkdir(parents=True, exist_ok=True)
    (case / "a.txt").write_text("hello\n")
    display = Display(env["DISPLAY"])
    child = None
    with (case / "output.log").open("w+") as output:
        process = subprocess.Popen([str(executable), "a.txt"], cwd=case, env=env,
                                   stdin=subprocess.DEVNULL, stdout=output, stderr=output)
        try:
            assert process.wait(timeout=20) == 0, "launcher failed"
            children = set(children_path.read_text().split()) - before
            gui = [int(pid) for pid in children
                   if Path(f"/proc/{pid}/exe").resolve() == executable.with_name("cedit.bin")]
            if gui:
                child = gui[0]
            assert len(gui) == 1, children
            assert os.kill(child, 0) is None, "GUI child did not survive launcher exit"
            display.focus_editor()
            remote = subprocess.run([str(executable)], cwd=case, env=env,
                                    stdout=output, stderr=output, timeout=20)
            assert remote.returncode == 0, "forwarded activation reports readiness"
            display.keys("Control_L+q")
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                pid, status = os.waitpid(child, os.WNOHANG)
                if pid:
                    child = None
                    assert os.waitstatus_to_exitcode(status) == 0, status
                    break
                time.sleep(0.05)
            assert child is None, "background GUI failed to exit normally"
            output.seek(0)
            assert output.read() == "", "background startup emitted diagnostics"
        finally:
            display.close()
            if process.poll() is None:
                process.kill()
                process.wait()
            if child is not None:
                os.kill(child, 9)
                os.waitpid(child, 0)
    invalid_env = dict(env, DISPLAY=":65530")
    invalid_env.pop("WAYLAND_DISPLAY", None)
    failure = subprocess.run([str(executable)], cwd=case, env=invalid_env,
                             capture_output=True, text=True, timeout=20)
    assert failure.returncode != 0 and "display unavailable" in failure.stderr, failure
    print("PASS background_startup")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--xvfb", required=True)
    parser.add_argument("--work", type=Path)
    args = parser.parse_args()
    executable = args.executable.resolve()
    with tempfile.TemporaryDirectory() as temporary:
        work = (args.work or Path(temporary)).resolve()
        work.mkdir(parents=True, exist_ok=True)
        env = environment(work)
        env.pop("WAYLAND_DISPLAY", None)
        env["GDK_BACKEND"] = "x11"
        with headless(args.xvfb, work, env) as gui_env:
            background_startup(executable, work, gui_env)
        for name, action in (("close_tabs", close_tabs), ("dirty_close", dirty_close),
                             ("quit_shortcut", quit_shortcut),
                             ("quit_after_close", quit_after_close),
                             ("window_close", window_close), ("focus_save", focus_save)):
            with headless(args.xvfb, work, env) as gui_env:
                scenario(executable, work, gui_env, name, action)


if __name__ == "__main__":
    main()
