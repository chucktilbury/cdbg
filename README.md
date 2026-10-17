# cdbg

`cdbg` is a Cwhip source debugger proof of concept built with GTK 4,
GtkSourceView and GDB/MI. It can compile Cwhip source with debug information,
launch local executables, set and manage breakpoints, inspect frames, locals
and watches, and show both Cwhip-friendly values and their GDB runtime
representations.

This repository is independently buildable against an installed Cwhip SDK; it
does not require a Cwhip compiler checkout. See [BUILD.md](doc/BUILD.md) for
standalone configure, build, test, clean and install instructions, and read the
[cdbg guide](CDBG.md) for controls and behavior.

## Project environment

This project owns its setup files following the
[Cwhip template](https://github.com/chucktilbury/cwhip-template) conventions;
it does not depend on or embed a template checkout.

```sh
export CWHIP_SDK=/path/to/installed/cwhip-sdk
./scripts/setup                 # debug; also accepts release or profile
cmake --build . --target cdbg   # the new shell starts in build/
cdbg ../examples/debugger.cw
exit                           # return to the original shell
```

The SDK must include application output-directory support. Setup configures
before opening a fresh Bash shell, sources your existing `~/.bashrc`, and adds
the project's `bin/` and `scripts/` to PATH. It never downloads dependencies,
changes Git state or writes your shell configuration. Both setup and direct
CMake configuration select a non-empty `CWHIP_SDK` first, then the top-level
TOML `sdk_prefix` in `$XDG_CONFIG_HOME/cwhip/settings.toml` (or
`$HOME/.config/cwhip/settings.toml` when XDG_CONFIG_HOME is unset/empty), then
ordinary CMake discovery. Reading settings requires Python 3.11+.
Setup exports a settings-selected prefix as `CWHIP_SDK`; its `bin/` joins PATH
so the debugger can compile `.cw` targets with that SDK.

Executables default to root `bin/`, native libraries to root `lib/`, and
intermediate files to `build/`; output directories are created during the build,
not configuration. All are ignored. See [BUILD.md](doc/BUILD.md) for output
overrides, shell helpers and direct CMake commands.

## Source

- `src/cdbg.cw` and `src/mi.cw` — GTK application and GDB/MI client/parser
- `src/terminal.c` and `src/terminal.cw` — local inferior output PTY
- `src/values.py` and `src/embed_values.py` — bounded Python-enabled GDB
  value inspector
- `examples/debugger.cw` — example program
- `CDBG.md` — controls, behavior, requirements and current limitations

The initial source import preserves the history of `tools/cdbg/` from
[Cwhip commit `5a229c6`](https://github.com/chucktilbury/cwhip/commit/5a229c632a1bddd01891c0ef0776f37e34ab8290).
The Cwhip repository remains the source of shared compiler, runtime, GTK binding
and package APIs, consumed through the installed SDK rather than a source-tree
dependency.

## Requirements and status

The current prototype uses local GDB; its friendly value inspector requires
Python-enabled GDB with `gdb.MICommand`. It is an active proof of concept and
compiler-testing workload, not a finished production debugger. Its CMake
configuration requires the exact Cwhip SDK version `0.0.1`.
Project changes are recorded in [the changelog](doc/CHANGELOG.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
