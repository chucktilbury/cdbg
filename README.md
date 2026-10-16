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

## Source

- `src/cdbg.cw` and `src/mi.cw` — GTK application and GDB/MI client/parser
- `src/terminal.c` and `src/terminal.cw` — local inferior output PTY
- `src/values.py` and `src/embed_values.py` — bounded Python-enabled GDB
  value inspector
- `examples/debugger.cw` — example program
- `CDBG.md` — controls, behavior, requirements and current limitations

The initial source import preserves the history of `tools/cdbg/` from
[Cwhip commit `5a229c6`](https://github.com/chucktilbury/cwhip/commit/5a229c632a1bddd01891c0ef0776f37e34ab8290).
The original Cwhip repository remains the source of shared compiler, runtime,
GTK binding and package APIs until the standalone dependency boundary is
implemented.

## Requirements and status

The current prototype uses local GDB; its friendly value inspector requires
Python-enabled GDB with `gdb.MICommand`. It is an active proof of concept and
compiler-testing workload, not a finished production debugger. Its CMake
configuration requires the exact Cwhip SDK version `0.0.1`.

## License

No standalone license has been selected for this repository yet. The public
source listing does not by itself grant reuse or redistribution rights.
