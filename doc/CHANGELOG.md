# Changelog

## Unreleased

- Add the MIT license.
- Adopt the project-owned Cwhip template conventions without replacing the
  debugger application, tests or imported history: executable `scripts/setup`,
  customizable `.project_env`, generated-output ignore rules and build guide.
- Configure debug (default), release and profile builds before entering a fresh
  Bash shell. Support an optional installed `CWHIP_SDK` prefix without copying
  an SDK, downloading dependencies or changing user configuration.
- Default executable/native library outputs to root `bin/` and `lib/`, with
  `CWHIP_BIN_DIR`/`CWHIP_LIB_DIR` overrides for private workspace builds.
  Require the SDK's application output-directory support and keep language
  resources executable-relative for build and relocated install trees.
- Isolate GTK tests from desktop GVFS services before starting the private
  display/session bus, retaining strict stderr assertions and adding an
  environment regression test.
- Refresh standalone SDK documentation and retain optional compiler-internal
  source stepping as explicit opt-in coverage.

## 0.0.1 - Standalone debugger

- Import `tools/cdbg/` with its history from the Cwhip compiler repository.
- Build, test, install and clean against the installed Cwhip `0.0.1` SDK
  independently of a compiler checkout, retaining GDB/MI and GTK coverage.
