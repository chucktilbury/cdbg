# Build, test and install

`cdbg` is a standalone CMake application. It consumes the installed Cwhip SDK
and does not read from or build a compiler workspace checkout.

## Requirements

- CMake 3.24 or newer, a C compiler, Python 3.11 or newer and `pkg-config`
- An installed Cwhip SDK version `0.0.2`, ABI `numeric-v2`, with GTK,
  GtkSourceView, application output-directory and application-defaults support
  enabled
- GTK 4.10 or newer and GtkSourceView 5 development files
- For the GUI/GDB integration tests: GDB, Xvfb and `dbus-daemon`

The installed SDK supplies `cwhip`, `cwhip-pkg`, the runtime, C headers,
language modules, builtins and Clang selection. No compiler source or compiler
checkout path is needed. The GUI libraries above are native build dependencies.
Runtime object inspection also needs the SDK runtime's type debug information;
the SDK retains it for GNU/Clang builds, including Release. Stripping it from
the runtime archive disables those inspection capabilities.

### Syntax cleanup

The application, example and embedded test programs require an SDK containing
[chucktilbury/cwhip#37](https://github.com/chucktilbury/cwhip/pull/37); the
parser regression for chained conditional branches also uses
[chucktilbury/cwhip#38](https://github.com/chucktilbury/cwhip/pull/38).
Value returns use `return(expr)` and dictionary literals use `[key: value]`
(`[:]` for an empty dictionary); lists still use `[]`. Use `#`, `//` or
`/* ... */` for Cwhip comments, not `;`. Native C code is unchanged.
Bare `return` and `return()` are valid void returns; parenthesize arguments to
`raise` as `raise(expr)` (`raise()` rethrows). Conditional chains use
`else(condition)`, not `else if`; these conditions may chain. Collection
literals can span lines and include a trailing comma. The source audit found
no mixed bitwise/comparison expressions requiring parentheses to preserve
their original grouping, and no remaining legacy syntax in the app, examples
or embedded Cwhip fixtures.

The GtkSourceView language definition is supplied by the selected SDK and
staged next to the build-tree executable and in the install tree; cdbg does
not bundle a separate copy.

Use a fresh build directory when changing SDKs so package lock files are
regenerated for the selected SDK.

### Numeric-v2 migration

This version depends on the compiler numeric migration in
[chucktilbury/cwhip#25](https://github.com/chucktilbury/cwhip/pull/25) and the
SDK/stdlib migration in
[chucktilbury/cwhip#26](https://github.com/chucktilbury/cwhip/pull/26). Both are
merged. Build a fresh SDK from those changes; do not mix rebuilt applications
with old native packages.
CMake checks both the exact SDK version and `Cwhip_SDK_ABI = numeric-v2`.
Rebuilt packages declare `sdk-abi = "numeric-v2"` under `[package]` in their
package manifests; the SDK's package helper generates cdbg's build manifest.
No user-installed SDK or configuration is rewritten by this project.

The application uses `int64` for indices, counts and callback parameters,
`uint64` for unsigned counts, and the new `String.toInt64()` parser.
The old language types `int`, `unsigned` and `float` are reserved, not aliases.
Typical source migrations use `int64`, `uint64` and `fp64`, respectively,
but dynamic extraction must match the actual boxed type: small integer
literals now box as `int8`/`int16`/`int32`, not automatically as `int64`.
Extract the original type before explicitly converting.

Unsuffixed decimal literals select `fp32`; use the `f64` suffix when the old
direct-to-`fp64` rounding matters (`0.1f64`, not `fp64(0.1)`).
Small integer arithmetic also retains its inferred width; widen operands
before the operation when the previous 64-bit intermediate is required.
Native C `int`/`unsigned`/`float` declarations are unchanged.

Run focused migration coverage without the broad legacy session suite:

```sh
ctest --test-dir build -R 'cdbg_(numeric|parser|cli|terminal|sdk_discovery)$' --output-on-failure
```

`cdbg_numeric` requires GDB, Xvfb and `dbus-daemon`. It checks all ten
scalar and list/dict numeric representations, exact runtime tags, fp32 bit
decoding (including signed zero, infinity, NaN and a subnormal), locals,
watches, source breakpoints, Step Into/Over/Out and frame selection through
real GDB/MI and the GTK debugger. It retains `numeric-values.mi` and
`numeric-stepping.mi` in the test work directory for diagnosis.

The selected installed SDK must provide `cwhip_apply_application_defaults`
through its CMake package. An SDK installation that satisfies the version and
ABI checks can still lack this capability if it predates application-defaults
support. If configuration reports missing application-defaults support, rebuild
and reinstall an updated Cwhip SDK to
the prefix named in the error, or select an updated installation with
`CWHIP_SDK`, then rerun setup/configuration. Updating the compiler source alone
does not update an existing installed SDK. cdbg does not skip shared defaults
when this capability is missing.

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

`scripts/setup [debug|release|profile]` inherits the installed SDK's application
build type when no mode is given. The explicit choices map to CMake `Debug`,
`Release` and `RelWithDebInfo`, respectively, in the same `build/` directory.
Setup runs `cmake -S "$project_root" -B "$project_root/build"` without changing
the caller's working directory, and opens a fresh interactive Bash using
`.project_env` only if configuration succeeds. It reads the configured build
type back from `CMakeCache.txt` for `CWHIP_BUILD_TYPE` and the prompt's
`_BUILD_TYPE` label. Configuration failures report an error and return status 1;
after a successful configuration, setup returns the interactive shell's exit
status.
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

### Application defaults

The SDK also records its common application defaults in the same `sdk.toml`:

```toml
[applications]
install_prefix = "/path/to/application-install"
build_type = "Release"
```

The installed Cwhip package applies these values as CMake defaults for this
application. They are separate from SDK selection: `sdk_prefix` selects the SDK,
while `[applications]` supplies only the shared install prefix and build type.
The SDK registers values derived from its actual install prefix and build
configuration; cdbg does not modify the settings file. Defaults are used only
for fresh/default CMake cache values. Explicit CMake options such as
`-DCMAKE_INSTALL_PREFIX=...` and `-DCMAKE_BUILD_TYPE=...`, as well as existing
cache values (including an empty `CMAKE_BUILD_TYPE` or `/usr/local` install
prefix), take precedence; the `CMAKE_INSTALL_PREFIX` environment override is
also preserved, as is the `CMAKE_BUILD_TYPE` environment override. An explicit
`scripts/setup` mode passes the
corresponding `-DCMAKE_BUILD_TYPE`; omitting the mode lets the SDK defaults or
existing build cache decide. No shared build directory or other CMake flags are
inherited. `install_prefix` affects `cmake --install`; build-tree executables
and staged language resources remain controlled by `CWHIP_BIN_DIR` and
`CWHIP_LIB_DIR`.

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

The shell exports `_PROJECT_NAME`, `_PROJECT_LOC`, `_BUILD_TYPE` and the
effective `CWHIP_BUILD_TYPE` read from the configured CMake cache.
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
