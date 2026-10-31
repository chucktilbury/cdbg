# cdbg

`cdbg` is a Cwhip source debugger proof of concept built with GTK 4,
GtkSourceView, and GDB/MI. It compiles Cwhip sources with debug information,
launches local executables, and inspects breakpoints, frames, locals, and
watches. Source: [github.com/chucktilbury/cdbg](https://github.com/chucktilbury/cdbg).

This directory contains the debugger in `src/`, examples in `examples/`, tests
in `tests/`, and build helpers in `scripts/`. It is independently buildable
against an installed Cwhip SDK; no compiler checkout is required.

With a current Cwhip SDK installed, run `scripts/setup [--clean] [debug|release|profile]`
from the checkout, then `build` in the project shell. Use `rebuild` for a
clean-first build, or `clean` to remove generated outputs; exit the shell before
running setup again. See the build guide for SDK selection.

```sh
export CWHIP_SDK=/path/to/installed/cwhip-sdk
./scripts/setup --clean
build cdbg
cdbg ../examples/debugger.cw
exit
```

- [Debugger guide](CDBG.md)
- [Build and installation](doc/BUILD.md)
- [Changelog](doc/CHANGELOG.md)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
