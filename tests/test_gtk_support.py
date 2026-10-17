"""Check GTK isolation before the private bus or application can start."""

import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from gtk_support import headless


class GtkEnvironmentTest(unittest.TestCase):
    def test_local_gio_backends_before_startup(self):
        inherited = {
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/inherited-bus",
            "GIO_USE_VFS": "gvfs",
            "GIO_USE_VOLUME_MONITOR": "proxy",
        }
        original = inherited.copy()
        server = Mock()
        server.poll.return_value = None
        bus = Mock()
        bus.poll.return_value = None
        bus.stdout = io.StringIO("unix:path=/private-test-bus\n")
        launches = []

        def launch(command, **kwargs):
            env = kwargs["env"]
            self.assertEqual(env["GIO_USE_VFS"], "local")
            self.assertEqual(env["GIO_USE_VOLUME_MONITOR"], "unix")
            self.assertNotIn("DBUS_SESSION_BUS_ADDRESS", env)
            launches.append(command[0])
            if len(launches) == 1:
                return server
            self.assertEqual(env["DISPLAY"], ":42")
            return bus

        with tempfile.TemporaryDirectory() as directory:
            with patch("gtk_support.subprocess.Popen", side_effect=launch), \
                    patch("gtk_support.select.select", return_value=([1], [], [])), \
                    patch("gtk_support.os.read", return_value=b"42\n"):
                with headless("test-Xvfb", Path(directory), inherited) as env:
                    self.assertEqual(env["GIO_USE_VFS"], "local")
                    self.assertEqual(env["GIO_USE_VOLUME_MONITOR"], "unix")
                    self.assertEqual(env["DBUS_SESSION_BUS_ADDRESS"],
                                     "unix:path=/private-test-bus")
                    self.assertEqual(env["DISPLAY"], ":42")
        self.assertEqual(launches, ["test-Xvfb", "dbus-daemon"])
        self.assertEqual(inherited, original)
        server.terminate.assert_called_once_with()
        server.wait.assert_called_once_with(timeout=10)
        bus.terminate.assert_called_once_with()
        bus.wait.assert_called_once_with(timeout=10)
        self.assertTrue(bus.stdout.closed)


if __name__ == "__main__":
    unittest.main()
