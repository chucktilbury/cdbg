"""Exercise real CMake discovery and setup without requiring a compiler SDK."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]


class SdkDiscoveryTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="cdbg sdk ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.project = self.root / "project"
        self.project.mkdir()
        for name in ("CMakeLists.txt", ".project_env"):
            shutil.copy2(PROJECT / name, self.project / name)
        for name in ("scripts", "src", "tests"):
            shutil.copytree(PROJECT / name, self.project / name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.settings = self.home / ".config/cwhip/settings.toml"
        self.build = self.project / "build"
        self.env = os.environ.copy()
        for name in (
            "CWHIP_SDK", "CMAKE_PREFIX_PATH", "Cwhip_DIR", "Cwhip_ROOT",
            "_PROJECT_NAME", "XDG_CONFIG_HOME",
        ):
            self.env.pop(name, None)
        self.env["HOME"] = str(self.home)
        self.fallback = self.make_sdk("fallback")
        self.env["CMAKE_PREFIX_PATH"] = str(self.fallback)
        self.shell_record = self.root / "shell-sdk.txt"
        self.tools = self.root / "tools"
        self.tools.mkdir()
        shell = self.tools / "bash"
        shell.write_text('#!/bin/sh\nprintf "%s" "${CWHIP_SDK-}" > "$SHELL_RECORD"\n')
        shell.chmod(0o755)
        self.env["PATH"] = f"{self.tools}:{self.env['PATH']}"
        self.env["SHELL_RECORD"] = str(self.shell_record)

    def make_sdk(self, name):
        prefix = self.root / name
        package = prefix / "lib/cmake/Cwhip"
        package.mkdir(parents=True)
        (package / "CwhipConfig.cmake").write_text(
            'get_filename_component(prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)\n'
            'file(WRITE "${CMAKE_BINARY_DIR}/selected-sdk.txt" "${prefix}")\n'
            'set(Cwhip_APPLICATION_OUTPUT_DIRECTORIES TRUE)\n'
            'set(Cwhip_INCLUDE_DIR "${prefix}/include")\n'
            'function(cwhip_require_sourceview)\n'
            '    file(WRITE "${CMAKE_BINARY_DIR}/sourceview-args.txt" "${ARGV}")\n'
            'endfunction()\n'
            'function(cwhip_add_program name)\n'
            '    add_custom_target("${name}")\n'
            '    set_target_properties("${name}" PROPERTIES\n'
            '        CWHIP_EXECUTABLE "${CMAKE_BINARY_DIR}/cdbg")\n'
            'endfunction()\n'
        )
        (package / "CwhipConfigVersion.cmake").write_text(
            'set(PACKAGE_VERSION "0.0.1")\n'
            'set(PACKAGE_VERSION_COMPATIBLE TRUE)\n'
            'set(PACKAGE_VERSION_EXACT TRUE)\n'
        )
        return prefix

    def write_settings(self, content):
        self.settings.parent.mkdir(parents=True, exist_ok=True)
        self.settings.write_text(content)

    def select(self, prefix):
        self.write_settings(f"sdk_prefix = {json.dumps(str(prefix))}\n")

    def configure(self, setup=False, success=True, extra=(), shell_input=None):
        self.shell_record.unlink(missing_ok=True)
        if setup:
            command = ["/bin/bash", str(self.project / "scripts/setup"), *extra]
        else:
            command = [
                "cmake", "-S", str(self.project), "-B", str(self.build),
                "-DBUILD_TESTING=OFF", *extra,
            ]
        result = subprocess.run(
            command, cwd=self.root, env=self.env, capture_output=True, text=True,
            input=shell_input, timeout=60,
        )
        output = result.stdout + result.stderr
        if success:
            self.assertEqual(result.returncode, 0, output)
        else:
            self.assertNotEqual(result.returncode, 0, output)
            if setup:
                self.assertFalse(self.shell_record.exists(), output)
        return output

    def assert_selected(self, prefix):
        self.assertEqual((self.build / "selected-sdk.txt").read_text(), str(prefix))

    def assert_both_select(self, prefix, shell_prefix=None):
        self.configure()
        self.assert_selected(prefix)
        self.configure(setup=True)
        self.assert_selected(prefix)
        self.assertEqual(self.shell_record.read_text(), str(shell_prefix or ""))

    def test_missing_settings_preserves_normal_discovery(self):
        self.assert_both_select(self.fallback)
        self.assertFalse(self.settings.exists())
        self.assertFalse((self.project / "bin").exists())
        self.assertFalse((self.project / "lib").exists())
        self.assertEqual(
            (self.build / "sourceview-args.txt").read_text(),
            f"RESOURCE_DIRECTORY;{self.project}/share/cwhip/modules/sourceview/0.1.0/language-specs",
        )

    def test_missing_top_level_key_preserves_cmake_dir(self):
        self.write_settings('[compiler]\nsdk_prefix = "/not/top-level"\n')
        self.env.pop("CMAKE_PREFIX_PATH")
        self.env["Cwhip_DIR"] = str(self.fallback / "lib/cmake/Cwhip")
        self.assert_both_select(self.fallback)

    def test_xdg_wins_over_home(self):
        self.select(self.make_sdk("home-sdk"))
        home_settings = self.settings
        before = home_settings.read_bytes()
        self.env["XDG_CONFIG_HOME"] = str(self.root / 'XDG with "quotes"') + "/"
        self.settings = Path(self.env["XDG_CONFIG_HOME"]) / "cwhip/settings.toml"
        sdk = self.make_sdk("xdg-sdk")
        self.select(sdk)
        xdg_before = self.settings.read_bytes()
        self.assert_both_select(sdk, sdk)
        self.assertEqual(home_settings.read_bytes(), before)
        self.assertEqual(self.settings.read_bytes(), xdg_before)

    def test_empty_xdg_uses_home(self):
        self.env["XDG_CONFIG_HOME"] = ""
        sdk = self.make_sdk("home-sdk")
        self.select(sdk)
        self.assert_both_select(sdk, sdk)

    def test_missing_xdg_does_not_fall_back_to_home(self):
        self.write_settings("not valid TOML\n")
        self.env["XDG_CONFIG_HOME"] = str(self.root / "missing-config")
        self.assert_both_select(self.fallback)

    def test_relative_xdg_error_and_override_bypass(self):
        self.env["XDG_CONFIG_HOME"] = "relative-config"
        for setup in (False, True):
            self.assertIn("not absolute", self.configure(setup=setup, success=False))
        self.env["CWHIP_SDK"] = str(self.fallback)
        self.assert_both_select(self.fallback, self.fallback)

    def test_xdg_without_home(self):
        self.env.pop("HOME")
        self.env["XDG_CONFIG_HOME"] = str(self.root / "xdg")
        self.settings = Path(self.env["XDG_CONFIG_HOME"]) / "cwhip/settings.toml"
        self.select(self.fallback)
        self.assert_both_select(self.fallback, self.fallback)

    def test_no_home_retains_normal_discovery(self):
        self.env.pop("HOME")
        self.assert_both_select(self.fallback)

    def test_escaped_path_and_empty_override(self):
        sdk = self.make_sdk('SDK with spaces and "quotes" ')
        self.env["CWHIP_SDK"] = ""
        self.select(sdk)
        self.assert_both_select(sdk, sdk)

    def test_literal_string_and_comments(self):
        sdk = self.make_sdk('literal "SDK"')
        self.write_settings(f"# SDK\nsdk_prefix = '{sdk}' # prefix\n")
        self.assert_both_select(sdk, sdk)

    def test_settings_are_never_evaluated_as_shell_code(self):
        sdk = self.make_sdk("SDK $(touch SHELL_CODE_RAN)")
        self.select(sdk)
        self.assert_both_select(sdk, sdk)
        self.assertFalse((self.root / "SHELL_CODE_RAN").exists())
        self.assertFalse((self.build / "SHELL_CODE_RAN").exists())

    def test_explicit_override_wins_over_settings_and_cmake_dir(self):
        self.select(self.make_sdk("settings-sdk"))
        sdk = self.make_sdk('explicit SDK "quotes"')
        self.env["CWHIP_SDK"] = str(sdk)
        self.env["Cwhip_DIR"] = str(self.fallback / "lib/cmake/Cwhip")
        self.assert_both_select(sdk, sdk)
        self.write_settings('sdk_prefix = "unterminated\n')
        self.assert_both_select(sdk, sdk)

    def test_changed_selection_replaces_cached_package(self):
        self.configure(extra=(f"-DCwhip_DIR={self.fallback / 'lib/cmake/Cwhip'}",))
        sdk = self.make_sdk("settings-sdk")
        self.select(sdk)
        self.configure()
        self.assert_selected(sdk)
        explicit = self.make_sdk("explicit-sdk")
        self.env["CWHIP_SDK"] = str(explicit)
        self.configure()
        self.assert_selected(explicit)

    def test_invalid_settings_are_errors(self):
        invalid = (
            'sdk_prefix = "unterminated\n', "sdk_prefix = 42\n",
            'sdk_prefix = ""\n', 'sdk_prefix = "relative/sdk"\n',
            'sdk_prefix = "/has\\nnewline"\n', 'sdk_prefix = "/has\\u0000nul"\n',
            f"sdk_prefix = {json.dumps(str(self.root / 'missing'))}\n",
            f"sdk_prefix = {json.dumps(str(self.project / 'CMakeLists.txt'))}\n",
        )
        for content in invalid:
            for setup in (False, True):
                with self.subTest(content=content, setup=setup):
                    self.write_settings(content)
                    output = self.configure(setup=setup, success=False)
                    self.assertIn("sdk_prefix", output)
                    self.assertIn("settings.toml", output)

    def test_invalid_selected_packages_never_use_cached_sdk(self):
        self.configure()
        for prefix in (self.root / "missing", self.home):
            for setup in (False, True):
                with self.subTest(prefix=prefix, setup=setup):
                    self.env["CWHIP_SDK"] = str(prefix)
                    self.assertIn("Cwhip", self.configure(setup=setup, success=False))
        self.env.pop("CWHIP_SDK")
        self.select(self.home)
        for setup in (False, True):
            self.assertIn("Cwhip", self.configure(setup=setup, success=False))

    def test_unreadable_settings(self):
        self.select(self.fallback)
        self.settings.chmod(0)
        self.addCleanup(self.settings.chmod, 0o600)
        if os.access(self.settings, os.R_OK):
            self.skipTest("Current user can read mode-000 files")
        for setup in (False, True):
            self.assertIn("sdk_prefix", self.configure(setup=setup, success=False))

    def test_settings_directory_is_error(self):
        self.settings.mkdir(parents=True)
        for setup in (False, True):
            self.assertIn("settings.toml", self.configure(setup=setup, success=False))

    def test_setup_real_shell_path_and_release_mode(self):
        sdk = self.make_sdk('shell SDK "quotes"')
        self.select(sdk)
        before = self.settings.read_bytes()
        self.env["PATH"] = os.environ["PATH"]
        self.configure(
            setup=True, extra=("release",),
            shell_input='printf "%s" "$PATH" > "$SHELL_RECORD"\nexit\n',
        )
        self.assertEqual(self.shell_record.read_text().split(":")[:3], [
            str(self.project / "bin"), str(self.project / "scripts"), str(sdk / "bin"),
        ])
        self.assert_selected(sdk)
        self.assertIn("CMAKE_BUILD_TYPE:STRING=Release", (self.build / "CMakeCache.txt").read_text())
        self.assertEqual(self.settings.read_bytes(), before)

    def test_setup_only_needs_python_for_existing_settings(self):
        python = self.tools / "python3"
        python.write_text("#!/bin/sh\necho 'unexpected python invocation' >&2\nexit 99\n")
        python.chmod(0o755)
        cmake = self.tools / "cmake"
        cmake.write_text("#!/bin/sh\nexit 0\n")
        cmake.chmod(0o755)
        self.configure(setup=True)
        self.env["CWHIP_SDK"] = str(self.fallback)
        self.write_settings("not valid TOML\n")
        self.configure(setup=True)
        self.env.pop("CWHIP_SDK")
        self.assertIn("unexpected python", self.configure(setup=True, success=False))

    def test_cmake_only_needs_tomllib_for_existing_settings(self):
        # cdbg itself still needs Python for embedding values after SDK discovery.
        helper = self.project / "scripts/sdk-prefix.py"
        helper.write_text("raise RuntimeError('unexpected settings parser invocation')\n")
        self.configure()
        self.env["CWHIP_SDK"] = str(self.fallback)
        self.write_settings("not valid TOML\n")
        self.configure()
        self.env.pop("CWHIP_SDK")
        self.assertIn("unexpected settings parser", self.configure(success=False))


if __name__ == "__main__":
    unittest.main()
