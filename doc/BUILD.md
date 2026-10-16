# Build, test and install

`cdbg` is a standalone CMake application. It consumes the installed Cwhip SDK
and does not read from or build a compiler workspace checkout.

## Requirements

- CMake 3.24 or newer, a C compiler, Python 3.11 or newer and `pkg-config`
- An installed Cwhip SDK version `0.0.1` with GTK and GtkSourceView enabled
- GTK 4.10 or newer and GtkSourceView 5 development files
- For the GUI/GDB integration tests: GDB, Xvfb and `dbus-daemon`

The installed SDK supplies `cwhip`, `cwhip-pkg`, the runtime, C headers,
language modules, builtins and Clang selection. No compiler source or compiler
checkout path is needed. The GUI libraries above are native build dependencies.
Runtime object inspection also needs the SDK runtime's type debug information;
the SDK retains it for GNU/Clang builds, including Release. Stripping it from
the runtime archive disables those inspection capabilities.

## Configure and build

Set `CMAKE_PREFIX_PATH` to the SDK install prefix:

```sh
cmake -S . -B build -DCMAKE_PREFIX_PATH=/path/to/cwhip-sdk
cmake --build build --target cdbg
```

Use an out-of-source build; configuring in the source directory is rejected.
The build creates `build/bin/cdbg`. The SDK toolchain stages package inputs
inside the binary tree and generates isolated project lock files there. The
application's language definition is copied to `build/share/cwhip/modules`
for build-tree execution.

## Test

```sh
cmake --build build --target test-all
```

`test-all` first builds the debugger and native PTY test, then runs serial CTest with
failure output. The suite includes the real Cwhip MI parser, native PTY
transport and exact embedded inspector-byte checks, plus GUI/GDB sessions when
GDB, Xvfb and `dbus-daemon` are found during configuration. CTest itself never
starts a nested build.

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
helper stages that resource next to build-tree executables as well, allowing
GTK's executable-relative module discovery in either layout. The clean target
removes generated executables, native test artifacts, transient staged project
inputs and test work directories while preserving the configured CMake build
tree and toolchain input manifest. A normal build after clean does not need a
new configure command.

`cdbg` remains a local GDB/MI proof of concept, not a production debugger:
there is no remote/attach, LLDB, DAP, inferior stdin, or complete Cwhip object
layout inspection. See [CDBG.md](../CDBG.md) for detailed behavior and
limitations.
