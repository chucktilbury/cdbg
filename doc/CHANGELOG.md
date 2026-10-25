# Changelog

## Unreleased

- Migrate application/example value returns and embedded debugger fixtures to
  the Cwhip syntax cleanup in compiler PR #37, including bracket dictionaries.
  Preserve native C fixtures, GDB/MI syntax and existing callable declarations.
- Make old-SDK rejection tests explicitly select the incompatible prefix through
  settings and environment overrides, even with a compatible SDK discoverable
  through PATH or CMake. Normal discovery may legitimately skip an old SDK.
  Accept CMake's line wrapping in path diagnostics under long, nested test roots.
- Migrate to Cwhip SDK `0.0.2` / `numeric-v2`, explicitly rejecting missing or
  incompatible SDK ABI identifiers. Update application/example/test Cwhip
  sources and numeric string parsers while retaining exact dynamic extraction.
- Decode all ten boxed numeric types, including low-bit fp32 payloads, and
  display scalar small integers as numbers rather than GDB character literals.
  Keep native/raw values separate. Add focused real GDB/GTK numeric, locals,
  watches, source-breakpoint and stepping regression coverage.
- Reject SDKs lacking the application-defaults helper with an actionable error
  naming the selected SDK prefix and explaining how to update the installation.
- Apply the installed Cwhip SDK's shared `[applications]` install-prefix and
  build-type defaults before cdbg's own CMake cache defaults. Preserve explicit
  CMake options and existing cache values; let setup inherit defaults when no
  mode is specified, while explicit setup modes still select their build type.
  Cover inheritance, overrides, cache retention and setup behavior.
- Adopt shared plain-text diagnostics at CLI and representative GUI
  load/compiler/GDB/transport boundaries using stable `CDBG` category codes.
  Keep upstream output, existing interactive exit behavior and session/tab
  preservation on rejected opens. Reject usage errors (2) and missing CLI
  targets (1) before GTK starts. Include target/path, reason and applicable
  recovery guidance in failure summaries; classify saved-state issues as warnings.
- Cover headless CLI channels/exits, compiler startup/failure (including the
  new upstream header), GDB startup/exit/protocol and PTY allocation failures.
  Assert exact owned stderr categories without allowing GTK/GVFS noise.
  Let test alerts finish dismissal before closing their parent, and release
  the PTY if GDB startup fails after successful compilation.
- Discover installed SDKs using `CWHIP_SDK` > dedicated `cwhip/sdk.toml`
  > normal CMake discovery, with legacy `settings.toml` compatibility only
  when the dedicated file is absent. Export selected SDKs to the project shell
  and cover precedence, config locations, cache replacement, failures and PATH
  behavior.
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
