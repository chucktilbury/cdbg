# Build, test and install

`cdbg` is a standalone CMake application. It consumes the installed Cwhip SDK
and does not read from or build a compiler workspace checkout.

## Requirements

- CMake 3.24 or newer, a C compiler, Python 3.11 or newer and `pkg-config`
- An installed Cwhip SDK version `0.0.1` with GTK, GtkSourceView and application
  output-directory support enabled
- GTK 4.10 or newer and GtkSourceView 5 development files
- For the GUI/GDB integration tests: GDB, Xvfb and `dbus-daemon`

The installed SDK supplies `cwhip`, `cwhip-pkg`, the runtime, C headers,
language modules, builtins and Clang selection. No compiler source or compiler
checkout path is needed. The GUI libraries above are native build dependencies.
Runtime object inspection also needs the SDK runtime's type debug information;
the SDK retains it for GNU/Clang builds, including Release. Stripping it from
the runtime archive disables those inspection capabilities.

## Configure and build

The project-owned setup script follows the
[Cwhip template](https://github.com/chucktilbury/cwhip-template) conventions.
Run it from any working directory; paths containing spaces are supported:

```sh
export CWHIP_SDK="/path/to/cwhip-sdk"
./scripts/setup debug
cmake --build . --target cdbg
cdbg ../examples/debugger.cw
exit
```

`scripts/setup [debug|release|profile]` defaults to `debug`. The choices map to
CMake `Debug`, `Release` and `RelWithDebInfo`, respectively, in the same `build/`
directory. Setup creates `build/`, runs `cmake ..` there, and opens a fresh
interactive Bash using `.project_env` only if configuration succeeds.
Nested project shells are rejected; exit the current one before running setup
again.

### SDK selection protocol

Both direct CMake configuration and setup use this exact precedence:

1. A non-empty `CWHIP_SDK` environment override.
2. The top-level TOML string `sdk_prefix` in
   `$XDG_CONFIG_HOME/cwhip/sdk.toml` when XDG_CONFIG_HOME is non-empty,
   otherwise `$HOME/.config/cwhip/sdk.toml`.
3. Normal CMake discovery (`CMAKE_PREFIX_PATH` or `Cwhip_DIR`, for example)
   when the selected file or its top-level key is missing.

The SDK selection file is separate from application preferences:

```toml
sdk_prefix = "/absolute/path/to/installed/cwhip-sdk"
```

For compatibility, `$XDG_CONFIG_HOME/cwhip/settings.toml` (or
`$HOME/.config/cwhip/settings.toml`) is consulted only when `sdk.toml` is
absent. A present `sdk.toml` is authoritative: malformed/unreadable content or
an invalid value is an error, and a missing `sdk_prefix` key proceeds to normal
CMake discovery without consulting the legacy file.

The value is the whole installed SDK prefix, not its `bin/` or CMake package
directory. Settings values must be non-empty absolute paths to existing
directories without NUL or line breaks. Spaces, TOML-escaped quotes and literal
strings are supported. The SDK file is parsed as TOML, never sourced as shell
code.

A non-empty XDG_CONFIG_HOME must be absolute and selects the only config home:
missing files there do not fall back to HOME. Without either config home,
normal discovery applies. A non-empty `CWHIP_SDK` bypasses config lookup
entirely, including relative XDG_CONFIG_HOME and malformed files.
Malformed/unreadable selected files or invalid values stop configuration and
prevent setup from opening a shell. Explicitly chosen prefixes clear cached
`Cwhip_DIR` and are searched exclusively; incompatible or missing SDK packages
cannot silently fall back to another installation.

Reading an existing SDK config file needs Python 3.11+ `tomllib` (setup uses
`python3`, direct configuration uses CMake's Python3 discovery). Missing files
and explicit overrides do not invoke the settings parser or impose that Python
version requirement; cdbg still requires Python separately to embed its values
inspector. Lookup never creates, changes or migrates either config file. To
return to normal discovery, unset `CWHIP_SDK` and remove the top-level
`sdk_prefix` selection from `sdk.toml`.

The shell sources a readable `~/.bashrc`, adds root `bin/` and `scripts/` to
PATH, shows the project/build type in its prompt and starts in `build/`. It
also adds `CWHIP_SDK/bin` when set, including when setup exports a prefix from
settings, so `.cw` targets can find the selected compiler.
With ordinary CMake discovery instead, put `cwhip` on PATH or set `CDBG_COMPILER`
to its executable path before launching the debugger.

The shell exports `_PROJECT_NAME`, `_PROJECT_LOC`, `_BUILD_TYPE` and `CWHIP_BUILD_TYPE`.
Its project-root Git helpers are `status`, `add` (defaults to `add .`), `commit` and `push`; `all`
explicitly runs `add -A`, `commit` and `push` in sequence, and `dbg` invokes
`cdbg`. Arguments are passed through. Customize these project-owned files as
needed. Starting the shell never runs Git mutations, downloads dependencies or
writes user rc files; any commands in your own `.bashrc` remain user-controlled.
Exit returns to the original shell without changing its environment.

Alternatively, configure directly using `CMAKE_PREFIX_PATH` (or `CWHIP_SDK`):

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH=/path/to/cwhip-sdk
cmake --build build --target cdbg
```

Use an out-of-source build; configuring in the source directory is rejected.
The build creates root `bin/cdbg`; the native test executable stays inside
`build/test-bin/` so CMake's native-target generation cannot create root `bin/`
during configuration.
Native shared/static library outputs default to root `lib/` when present.
`bin/` and `lib/` are created by builds, not configuration, with no placeholders.
Override the cache paths for isolated workspace builds, for example:

```sh
cmake -S . -B build \
  -DCMAKE_PREFIX_PATH=/path/to/cwhip-sdk \
  -DCWHIP_BIN_DIR="$PWD/build/bin" -DCWHIP_LIB_DIR="$PWD/build/lib"
```

`CWHIP_BIN_DIR` controls both native and Cwhip executable outputs;
`CWHIP_LIB_DIR` controls native library/archive outputs. Use absolute override
paths as shown above. Native test artifacts stay in the binary tree.
The SDK toolchain stages package inputs
inside the binary tree and generates isolated project lock files there. The
application's language definition is built under the executable directory's
sibling `share/cwhip/modules` tree (root `share/` by default) for build-tree
execution. Generated outputs and Python caches are ignored by Git.

## Test

```sh
cmake --build build --target test-all
```

`test-all` first builds the debugger and native PTY test, then runs serial CTest with
failure output. The suite checks setup modes, configure-failure propagation and
the project shell environment, then includes the real Cwhip MI parser, native PTY
transport and exact embedded inspector-byte checks, plus GUI/GDB sessions when
GDB, Xvfb and `dbus-daemon` are found during configuration. CTest itself never
starts a nested build.

`cdbg_cli` checks stdout/stderr separation and exit status for help, invalid
options and missing/non-file targets without a display. `cdbg_session` covers
failed compiler launch/compilation, unchanged upstream compiler details,
GDB startup/session/protocol failures and injected PTY allocation failure,
alongside existing source-tab/session preservation and saved-state regressions.
The adopted codes and intentional legacy boundaries are documented in the
[diagnostics guide](../CDBG.md#diagnostics-and-exit-status).

GTK fixtures use a private X display and session bus, with `GIO_USE_VFS=local`
and `GIO_USE_VOLUME_MONITOR=unix` set before either service or the application
starts. This prevents installed GVFS services from auto-activating on the test
bus and polluting application diagnostics; stderr assertions remain strict.
The `cdbg_gtk_environment` test checks this setup without requiring GTK or GVFS.
SDK discovery and setup regressions can also run without an installed SDK:

```sh
python3 -B -m unittest discover -s tests -p 'test_*setup.py' -v
python3 -B -m unittest discover -s tests -p 'test_sdk_discovery.py' -v
```

The discovery suite uses isolated settings and mock SDK packages with real CMake
configuration, including precedence, error handling, cache replacement and a
real Bash PATH handoff. It is also registered as `cdbg_sdk_discovery` in CTest.
To check GUI/GDB session stability on a host with GVFS installed, run:

```sh
ctest --test-dir build -R '^cdbg_session$' --repeat until-fail:20 --output-on-failure
```

Compiler-internal `RuntimeGc.c` source-line stepping is excluded unless that
source is explicitly provided:

```sh
cmake -S . -B build \
  -DCMAKE_PREFIX_PATH=/path/to/cwhip-sdk \
  -DCDBG_RUNTIME_SOURCE=/path/to/RuntimeGc.c
```

The rest of the GUI/GDB session tests run using only the installed SDK and
debugger repository. Run the separate opt-in no-op incremental-build check with
`cmake --build build --target check-noop`. It is never part of ordinary CTest.

## Install and clean

```sh
cmake --install build --prefix /path/to/install
cmake --build build --target clean
```

Installation includes the `cdbg` executable and the GtkSourceView language
definition under `share/cwhip/modules/sourceview/0.1.0/language-specs`. The
SDK helper stages that resource next to build-tree executables as well, allowing
GTK's executable-relative module discovery in either layout. The clean target
removes generated executables, native test artifacts, transient staged project
inputs and test work directories while preserving the configured CMake build
tree and toolchain input manifest. A normal build after clean does not need a
new configure command. Clean also removes the configured `bin/` executable
outputs and staged language resource; it does not delete source files or the
SDK. Installation remains independent of the chosen build output directories,
and the installed tree can be moved intact to another prefix.

`cdbg` remains a local GDB/MI proof of concept, not a production debugger:
there is no remote/attach, LLDB, DAP, inferior stdin, or complete Cwhip object
layout inspection. See [CDBG.md](../CDBG.md) for detailed behavior and
limitations.
