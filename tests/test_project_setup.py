"""Exercise the project shell contract without configuring a real SDK."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]
BASH = shutil.which("bash")


class ProjectSetupTest(unittest.TestCase):
    def test_setup_modes_and_failure(self):
        with tempfile.TemporaryDirectory(prefix="cdbg setup ") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy2(PROJECT / "scripts/setup", root / "scripts/setup")
            (root / ".project_env").write_text("")
            tools = root / "tools"
            tools.mkdir()
            log = root / "calls.jsonl"
            for name in ("cmake", "bash"):
                tool = tools / name
                tool.write_text(
                    f"#!{sys.executable}\n"
                    "import json, os, sys\n"
                    "from pathlib import Path\n"
                    "with open(os.environ['SETUP_LOG'], 'a') as log:\n"
                    "    log.write(json.dumps({'tool': Path(sys.argv[0]).name,\n"
                    "        'args': sys.argv[1:], 'cwd': os.getcwd(),\n"
                    "        'env': {key: os.environ[key] for key in\n"
                    "            ('_PROJECT_LOC', '_PROJECT_NAME', '_BUILD_TYPE',\n"
                    "             'CWHIP_BUILD_TYPE', 'CWHIP_SDK')}}) + '\\n')\n"
                    "if Path(sys.argv[0]).name == 'cmake':\n"
                    "    sys.exit(int(os.environ.get('CONFIGURE_STATUS', '0')))\n"
                )
                tool.chmod(0o755)
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       SETUP_LOG=str(log), CWHIP_SDK=str(root / "sdk prefix"))
            env.pop("_PROJECT_NAME", None)
            for mode, cmake_type in ((None, "Debug"), ("debug", "Debug"),
                                     ("release", "Release"), ("profile", "RelWithDebInfo")):
                log.unlink(missing_ok=True)
                result = subprocess.run(
                    [BASH, str(root / "scripts/setup")] + ([mode] if mode else []),
                    cwd=tools, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                configure, shell = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(configure["tool"], "cmake")
                self.assertEqual(configure["args"], ["..", f"-DCMAKE_BUILD_TYPE={cmake_type}"])
                self.assertEqual(configure["cwd"], str(root / "build"))
                self.assertEqual(shell["args"], ["--rcfile", str(root / ".project_env"), "-i"])
                self.assertEqual(shell["env"]["_PROJECT_LOC"], str(root))
                self.assertEqual(shell["env"]["_PROJECT_NAME"], root.name)
                self.assertEqual(shell["env"]["_BUILD_TYPE"], mode or "debug")
                self.assertEqual(shell["env"]["CWHIP_BUILD_TYPE"], cmake_type)
                self.assertEqual(shell["env"]["CWHIP_SDK"], str(root / "sdk prefix"))
                self.assertFalse((root / "bin").exists())
                self.assertFalse((root / "lib").exists())
            log.unlink()
            result = subprocess.run([BASH, str(root / "scripts/setup")],
                                    env=dict(env, CONFIGURE_STATUS="7"), capture_output=True)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(len(log.read_text().splitlines()), 1)
            for arguments in (["invalid"], ["debug", "extra"]):
                log.unlink(missing_ok=True)
                result = subprocess.run([BASH, str(root / "scripts/setup"), *arguments],
                                        env=env, capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertTrue(result.stderr)
                self.assertFalse(log.exists())
            result = subprocess.run([BASH, str(root / "scripts/setup")],
                                    env=dict(env, _PROJECT_NAME="existing project"),
                                    capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn(b"already active", result.stderr)
            self.assertFalse(log.exists())

    def test_project_environment(self):
        with tempfile.TemporaryDirectory(prefix="cdbg shell ") as directory:
            root = Path(directory)
            (root / "build").mkdir()
            (root / ".bashrc").write_text("export CDBG_RC_LOADED=yes\n")
            env = dict(os.environ, HOME=str(root), _PROJECT_LOC=str(root),
                       _PROJECT_NAME=root.name, _BUILD_TYPE="profile",
                       CWHIP_BUILD_TYPE="RelWithDebInfo", CWHIP_SDK=str(root / "sdk prefix"))
            command = (
                '[[ $CDBG_RC_LOADED == yes && $PWD == "$_PROJECT_LOC/build" ]] && '
                '[[ $PATH == "$_PROJECT_LOC/bin:$_PROJECT_LOC/scripts:$CWHIP_SDK/bin:"* ]] && '
                'declare -F status add commit push all dbg >/dev/null'
            )
            result = subprocess.run(
                [BASH, "--noprofile", "--rcfile", str(PROJECT / ".project_env"), "-ic", command],
                env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
