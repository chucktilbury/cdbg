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
            shutil.copy2(PROJECT / "scripts/clean", root / "scripts/clean")
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
                    "    generated = [Path(os.environ['PROJECT_ROOT']) / name for name in\n"
                    "        ('bin', 'build', 'lib', 'doc/out', 'share')]\n"
                    "    log.write(json.dumps({'tool': Path(sys.argv[0]).name,\n"
                    "        'args': sys.argv[1:], 'cwd': os.getcwd(),\n"
                    "        'generated': [path.exists() for path in generated],\n"
                    "        'env': {key: os.environ.get(key, '') for key in\n"
                    "            ('_PROJECT_LOC', '_PROJECT_NAME', '_BUILD_TYPE',\n"
                    "             'CWHIP_BUILD_TYPE', 'CWHIP_SDK')}}) + '\\n')\n"
                    "if Path(sys.argv[0]).name == 'cmake':\n"
                    "    build_type = next((arg.split('=', 1)[1] for arg in sys.argv[1:]\n"
                    "        if arg.startswith('-DCMAKE_BUILD_TYPE=')),\n"
                    "        os.environ.get('MOCK_DEFAULT_BUILD_TYPE', ''))\n"
                    "    build = Path(sys.argv[sys.argv.index('-B') + 1])\n"
                    "    build.mkdir(parents=True, exist_ok=True)\n"
                    "    (build / 'CMakeCache.txt').write_text(\n"
                    "        f'CMAKE_BUILD_TYPE:STRING={build_type}\\n')\n"
                    "    sys.exit(int(os.environ.get('CONFIGURE_STATUS', '0')))\n"
                    "if Path(sys.argv[0]).name == 'bash' and '--rcfile' not in sys.argv:\n"
                    "    os.execv('/bin/bash', ['/bin/bash', *sys.argv[1:]])\n"
                    "sys.exit(int(os.environ.get('SHELL_STATUS', '0')))\n"
                )
                tool.chmod(0o755)
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       SETUP_LOG=str(log), PROJECT_ROOT=str(root),
                       CWHIP_SDK=str(root / "sdk prefix"),
                       MOCK_DEFAULT_BUILD_TYPE="RelWithDebInfo")
            for name in ("_PROJECT_NAME", "_PROJECT_LOC", "_BUILD_TYPE",
                         "_PROJECT_BUILD_DIR", "CWHIP_BUILD_TYPE"):
                env.pop(name, None)
            for mode, cmake_type, label in (
                (None, "RelWithDebInfo", "profile"), (None, "", "default"),
                (None, "MinSizeRel", "minsizerel"), ("debug", "Debug", "debug"),
                ("release", "Release", "release"), ("profile", "RelWithDebInfo", "profile"),
            ):
                with self.subTest(mode=mode, configured_type=cmake_type):
                    log.unlink(missing_ok=True)
                    result = subprocess.run(
                        [BASH, str(root / "scripts/setup")] + ([mode] if mode else []),
                        cwd=tools, env=dict(env, MOCK_DEFAULT_BUILD_TYPE=cmake_type),
                        capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    configure, shell = [json.loads(line) for line in log.read_text().splitlines()]
                    self.assertEqual(configure["tool"], "cmake")
                    expected_args = ["-S", str(root), "-B", str(root / "build")]
                    if mode is not None:
                        expected_args.append(f"-DCMAKE_BUILD_TYPE={cmake_type}")
                    self.assertEqual(configure["args"], expected_args)
                    self.assertEqual(configure["cwd"], str(tools))
                    self.assertEqual(shell["args"], ["--rcfile", str(root / ".project_env"), "-i"])
                    self.assertEqual(shell["cwd"], str(tools))
                    self.assertEqual(shell["env"]["_PROJECT_LOC"], str(root))
                    self.assertEqual(shell["env"]["_PROJECT_NAME"], root.name)
                    self.assertEqual(shell["env"]["_BUILD_TYPE"], label)
                    self.assertEqual(shell["env"]["CWHIP_BUILD_TYPE"], cmake_type)
                    self.assertEqual(shell["env"]["CWHIP_SDK"], str(root / "sdk prefix"))
                    self.assertFalse((root / "bin").exists())
                    self.assertFalse((root / "lib").exists())
            log.unlink()
            result = subprocess.run([BASH, str(root / "scripts/setup")],
                                    env=dict(env, CONFIGURE_STATUS="7"), capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn(b"CMake configuration failed; project shell was not started.",
                          result.stderr)
            self.assertEqual(len(log.read_text().splitlines()), 1)
            log.unlink()
            result = subprocess.run([BASH, str(root / "scripts/setup")],
                                    env=dict(env, SHELL_STATUS="23"), capture_output=True)
            self.assertEqual(result.returncode, 23)
            self.assertEqual(len(log.read_text().splitlines()), 2)
            for arguments in (["invalid"], ["debug", "extra"],
                              ["--clean", "--clean"], ["debug", "release"]):
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

    def test_setup_clean_removes_generated_outputs_before_configuring(self):
        with tempfile.TemporaryDirectory(prefix="cdbg setup clean ") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy2(PROJECT / "scripts/setup", root / "scripts/setup")
            shutil.copy2(PROJECT / "scripts/clean", root / "scripts/clean")
            (root / ".project_env").write_text("")
            for path in ("bin/generated", "build/generated", "lib/generated",
                         "doc/out/generated", "share/generated"):
                generated = root / path
                generated.parent.mkdir(parents=True, exist_ok=True)
                generated.write_text("generated")
            (root / "src").mkdir()
            (root / "src/kept").write_text("source")
            tools = root / "tools"
            tools.mkdir()
            log = root / "calls.jsonl"
            cmake = tools / "cmake"
            cmake.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "from pathlib import Path\n"
                "root = Path(os.environ['PROJECT_ROOT'])\n"
                "generated = [root / name for name in ('bin', 'build', 'lib', 'doc/out', 'share')]\n"
                "with open(os.environ['SETUP_LOG'], 'a') as log:\n"
                "    log.write(json.dumps({'tool': 'cmake', 'generated': "
                "[path.exists() for path in generated]}) + '\\n')\n"
                "build = Path(sys.argv[sys.argv.index('-B') + 1])\n"
                "build.mkdir(parents=True, exist_ok=True)\n"
                "(build / 'CMakeCache.txt').write_text('CMAKE_BUILD_TYPE:STRING=Debug\\n')\n"
            )
            cmake.chmod(0o755)
            bash = tools / "bash"
            bash.write_text(
                f"#!{sys.executable}\n"
                "import os, sys\n"
                "if '--rcfile' not in sys.argv:\n"
                "    os.execv('/bin/bash', ['/bin/bash', *sys.argv[1:]])\n"
                "sys.exit(0)\n"
            )
            bash.chmod(0o755)
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       PROJECT_ROOT=str(root), SETUP_LOG=str(log),
                       CWHIP_SDK=str(root / "sdk"))
            for name in ("_PROJECT_NAME", "_PROJECT_LOC", "_BUILD_TYPE",
                         "_PROJECT_BUILD_DIR", "CWHIP_BUILD_TYPE"):
                env.pop(name, None)

            result = subprocess.run(
                [BASH, str(root / "scripts/setup"), "debug", "--clean"],
                cwd=root, env=env, capture_output=True, text=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            configure = json.loads(log.read_text())
            self.assertEqual(configure["tool"], "cmake")
            self.assertEqual(configure["generated"], [False] * 5)
            self.assertEqual((root / "src/kept").read_text(), "source")
            self.assertTrue((root / "build/CMakeCache.txt").exists())

    def test_project_environment(self):
        with tempfile.TemporaryDirectory(prefix="cdbg shell ") as directory:
            root = Path(directory)
            (root / "build").mkdir()
            (root / ".bashrc").write_text(
                "export CDBG_RC_LOADED=yes\nPS1='user prompt> '\n")
            build_log = root / "build-calls.jsonl"
            tools = root / "tools"
            tools.mkdir()
            cmake = tools / "cmake"
            cmake.write_text(
                f"#!{sys.executable}\n"
                "import json, os, sys\n"
                "with open(os.environ['BUILD_LOG'], 'a') as log:\n"
                "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "sys.exit(17 if 'fail' in sys.argv else 0)\n"
            )
            cmake.chmod(0o755)
            env = dict(os.environ, HOME=str(root), _PROJECT_LOC=str(root),
                       _PROJECT_NAME=root.name, _BUILD_TYPE="profile",
                       CWHIP_BUILD_TYPE="RelWithDebInfo", CWHIP_SDK=str(root / "sdk prefix"),
                       PATH=f"{tools}:{os.environ['PATH']}", BUILD_LOG=str(build_log))
            command = (
                '[[ $CDBG_RC_LOADED == yes && $PWD == "$_PROJECT_LOC/build" ]] && '
                '[[ $PATH == "$_PROJECT_LOC/bin:$_PROJECT_LOC/scripts:$CWHIP_SDK/bin:"* ]] && '
                '[[ $PS1 == "\\[\\e[0;31;1m\\]${_PROJECT_NAME}(profile):'
                '\\[\\e[0m\\]user prompt> " ]] && '
                '[[ $HISTCONTROL == ignoreboth:erasedups && ! -v project_path ]] && '
                'declare -F build rebuild status add commit push all dbg >/dev/null || exit; '
                'build cdbg || exit; rebuild cdbg || exit; build fail; '
                '[[ $? == 17 ]]'
            )
            result = subprocess.run(
                [BASH, "--noprofile", "--rcfile", str(PROJECT / ".project_env"), "-ic", command],
                env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                [json.loads(line) for line in build_log.read_text().splitlines()],
                [
                    ["--build", str(root / "build"), "--parallel", "12", "--target", "cdbg"],
                    ["--build", str(root / "build"), "--parallel", "12", "--clean-first",
                     "--target", "cdbg"],
                    ["--build", str(root / "build"), "--parallel", "12", "--target", "fail"],
                ],
            )

    def test_project_environment_without_sdk(self):
        with tempfile.TemporaryDirectory(prefix="cdbg shell ") as directory:
            root = Path(directory)
            (root / "build").mkdir()
            env = dict(os.environ, HOME=str(root), _PROJECT_LOC=str(root),
                       _PROJECT_NAME=root.name, _BUILD_TYPE="default",
                       EXPECTED_PROMPT=(r"\[\e[0;31;1m\]" + root.name +
                                        r"(default):\[\e[0m\]\u@\h:\w\$ "))
            env.pop("CWHIP_SDK", None)
            result = subprocess.run(
                [BASH, "--noprofile", "--norc", "-c",
                 'unset PS1; source "$1"; '
                 '[[ $PWD == "$_PROJECT_LOC/build" && '
                 '$PATH == "$_PROJECT_LOC/bin:$_PROJECT_LOC/scripts:$2" && '
                 '$PS1 == "$EXPECTED_PROMPT" ]]',
                 "shell-test", str(PROJECT / ".project_env"), env["PATH"]],
                env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
