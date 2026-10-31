# cdbg local debugger prototype

`cdbg` is a separate Cwhip/GTK/GtkSourceView application, inspired by KDbg's
source-and-inspector layout. This is a working **local GDB/MI2 prototype**, not
an editor mode or a finished debugger. The Cwhip compiler is still `cwhip`.

## Build and launch

Install CMake 3.24+, Python 3.11+, GTK 4.10+, GtkSourceView 5 development
files, and an installed Cwhip 0.0.2 SDK (ABI `numeric-v2`) built with GTK and GtkSourceView.
The debugger build does not use a compiler checkout:

```sh
export CWHIP_SDK=/path/to/cwhip-sdk
./scripts/setup --clean debug
build cdbg
cdbg ../examples/debugger.cw
exit
```

Run `build test-all` inside the project shell for the component's build and test
suite; `cmake --install build --prefix /path/to/install` installs the
executable and language resource. See [BUILD.md](doc/BUILD.md) for prerequisites,
test detection, the optional no-op check and cleaning. `rebuild [TARGET...]`
does a clean-first build; `clean` removes generated outputs and the configured
build tree, while `./scripts/setup --clean` cleans before configuring again.
The project-owned setup shell follows the Cwhip template. Without a mode it
inherits the installed SDK's application build type or the existing CMake
cache; `debug`, `release` and `profile` explicitly select `Debug`, `Release`
and `RelWithDebInfo`. It starts in `build/`; the executable is written to the
repository's `bin/`, with its language resource under `share/`. Direct CMake
configuration is only needed for custom CMake options such as output-directory
overrides, which are documented in the build guide. The installed SDK needs
application output-directory support in
addition to version `0.0.2` and ABI `numeric-v2`.

`cdbg [SOURCE.cw|EXECUTABLE [-- ARGS...]]` opens the GUI in the foreground;
arguments after the target are passed individually to the inferior, without a
shell. Command-line arguments override the target's saved Session arguments for
that command-line session (including Restart) but are not saved; applying Session
Preferences replaces them, and a later File > Load Executable uses the saved arguments.
A `.cw` command-line target is compiled
asynchronously using `cwhip -g` to an owned temporary executable. Compilation
failure summaries appear in a parented modal dialog, the status line, Debugger
Console and stderr; upstream compiler output remains in the Debugger Console.
User source/output files
are not overwritten. Other paths are treated as prebuilt executables; compile
these with debug information. Temporary compiler outputs are removed when the
session ends or the window closes.

### Diagnostics and exit status

`cdbg` incrementally follows the shared
[Cwhip diagnostics contract](https://github.com/chucktilbury/cwhip/blob/master/doc/DIAGNOSTICS.md):
`cdbg: severity[CODE]: explanation`. Diagnostics go to stderr, and `--help`
goes to stdout via the shared stdlib `cli` `helpText()`. Output is plain text,
including when redirected or `NO_COLOR` is set. Unknown options and unexpected
positionals exit with status 2 using stdlib wording (`unknown option: …`,
`unexpected positional argument: …`). `--help` ignores trailing argv; a bare
`--` is the remainder terminator, not a usage error. A missing/non-file
command-line target exits with status 1 before GTK starts, so those errors
work without a display. Prefix a target beginning with `-` with `./`; after
`--`, options/arguments belong to the inferior.

No arguments opens the GUI. Once the GUI is running, errors remain interactive:
failed compile/load/debug operations are **not** reported as loaded/running,
but closing the window retains the existing exit status 0. Rejected source
opens and nonexistent replacement targets preserve the current session and
tabs. Accepting a valid replacement target still starts a fresh session as
described below; this is not a transactional rollback to an earlier GDB session.

| Code | Boundary |
|------|----------|
| `CDBG0001` | Command-line usage |
| `CDBG1000` | Operation rejected in the current debug state |
| `CDBG1001` | Target/source file loading or reading |
| `CDBG2001` | Saved-state read, validation, restore or save warning (includes settings path) |
| `CDBG3001` | Compiler startup, temporary build directory or compilation failure |
| `CDBG3002` | GDB startup, command rejection or unexpected session exit |
| `CDBG3003` | Program-output PTY or GDB input transport |
| `CDBG3004` | GDB protocol or queue/record limit |
| `CDBG9001` | Owned temporary-output cleanup |

Codes identify stable categories, not individual wordings. GUI error summaries
use the same header in the status line and Debugger Console; existing file-load
alerts also show it. Startup/transport failures name the affected target and
reason, with applicable retry/configuration guidance. Routine progress and
ignored busy-state actions stay in the status line, without new modal dialogs.
Raw compiler headers, source locations and GDB details are not parsed or
rewritten by this layer. The existing bounded console history remains 64 KiB;
the full current compilation output is also retained in the session's compiler
output buffer.

This is not a rewrite of every message. Legacy inline watch/locals evaluation
details, optional value-inspector/start-breakpoint fallback notices, Session/find
validation, ordinary status messages, SDK/setup-script/CMake diagnostics and
upstream GTK/runtime failures retain their existing presentation. Compiler and
GDB output keep their own formats; these codes are not a machine-readable
output protocol.

### File operations

The **File** menu separates the two kinds of file:

- **Load Executable…** opens a file chooser and starts a fresh GDB session for
  the chosen executable: the old GDB breakpoint IDs are cleared, saved
  breakpoints for that target are restored, and the target is prepared but
  not run. Its source tabs come from the readable source paths in its debug
  information. A command-line `.cw` target is compiled first, as above.
- **Open Source Code…** opens a text file in a read-only source tab without
  compiling it or changing the debug session. An already open file reuses its
  tab. Executables (ELF), binary files and invalid UTF-8 are rejected.
- **Quit** (Ctrl+Q) ends the session and closes cdbg.

A stripped executable or missing source file shows an explicit
source-unavailable message. Any target/source open failure shows a modal
**Could not load file** dialog parented to the cdbg window and leaves the source
area and its existing tabs visible and unchanged; with no file tab, a "No source"
placeholder page is kept instead of hiding the area.

**Search > Find…** (Ctrl+F) opens a Find dialog with a text box, **Find Next**,
**Find Previous** and **Close**. It searches the active source tab, wraps around
the ends of the file (reported as "Wrapped"), and reports "Not found" when there
is no match.

`CDBG_COMPILER` can select a compiler (otherwise cdbg first tries its sibling
`cwhip`, then PATH); `CDBG_GDB` can select the GDB executable (default `gdb` on
PATH). The compiler's existing package discovery and project lock rules apply.
GDB runs with user init files and auto-load scripts disabled. Programs are
launched in cdbg's current working directory.

## Controls and inspection

1. Load an executable (or start cdbg with a source/executable). Click a source
   line (gutter or text) to select it, then **Breakpoint > Set/Clear Breakpoint**
   (F9) — or click the gutter line number area and press F9. This sets a
   breakpoint when none exists there, otherwise clears its breakpoint(s).
   **Breakpoint > Enable/Disable Breakpoint** (Ctrl+F9) toggles their enabled
   state; if no breakpoint exists at the line, the status says so.
   Both commands use the cursor line of the active source tab, require a loaded,
   paused target and use MI-quoted file:line locations. The menu items are
   disabled without a ready target/source; shortcuts explain unavailable actions
   in the status line. For the example above, line 10 stops before the method call.
   Multi-location breakpoint actions affect the parent breakpoint and all its
   locations. If GDB relocates a non-executable line to nearby code, toggling
   again at the original requested line still clears that breakpoint.
   The **Breakpoints** tab lists each breakpoint as
   `#N enabled|disabled installed file:line in FUNCTION hits COUNT`, with
   `pending … (not yet installed)` for locations GDB could not yet resolve and
   `(multiple locations)` for multi-location parents. GDB errors (for example
   "No compiled code" for a line without code) appear in the status line,
   Debugger Console and stderr. When the program exits, each enabled breakpoint
   whose hit count did not change during that run is listed in the Debugger
   Console as "Not reached during this run … (that code did not execute)", and
   the exit status counts them. A breakpoint in a method that the program never
   calls is installed correctly but cannot stop it.
   The old source and Breakpoints-tab action popovers are removed;
   normal read-only text selection/copy remains available.
   Breakpoint lines have a red-tinted background and a gutter icon, distinct
   from the current-line highlight; disabled breakpoints are gray. Marks follow
   GDB's resolved locations, including multiple locations, and remain in sync
   when tabs close/reopen. Restart preserves them; a fresh load restores the
   chosen target's saved locations and enabled states.
2. **Run / Continue** (F5), **Step Into** (F11), **Step Over** (F10),
   **Step Out** (Shift+F11) and **Pause** use GDB's
   run/continue/step/next/finish/interrupt commands. Controls reflect running
   versus stopped state.    F10 is reserved for Step Over (GTK's menubar F10
   accelerator is disabled on the debugger window).    Toolbar buttons do not take focus and activate on press, so a mouse press on
   **Step Over** steps on the first click while the source pane keeps keyboard
   focus. On a Cwhip (`.cw`) session,
   **Step Into** finishes out of thin GC/trace prologues and frames with no
   source until the next `.cw` stop or a runtime frame that has debug info and
   is real work (for example `cwhip_string_format_new` when stepping into
   `print`/`format`; capped; the status notes how many frames were skipped).
   The first time a runtime source tab opens, centering waits until the page is
   mapped so the stop line is highlighted immediately. **Step Over** continues
   through extra same-line stops so one press advances one source statement.
   Pure C sessions keep every stop. **File >
   Load Executable…** ends the old GDB process group and starts a fresh session.
   **Restart** stops the current inferior and runs again from the beginning,
   preserving breakpoints, watches and arguments. When the session target is a
   `.cw` file, Restart recompiles with `cwhip -g` into the temporary executable
   first, then relaunches; prebuilt executables restart without rebuilding.
3. **Edit > Preferences…** (Ctrl+comma) opens a cedit-style preferences window
   with **Session**, **Appearance** and **Keyboard** categories.
   **Session** keeps **Break at start** (on by default for a new configuration),
   a program **Arguments** field, optional **Working directory** and
   **Environment** (`KEY=VALUE` lines; `#` comments; blank lines ignored), and
   **Apply** / **Cancel**. Arguments use shell-like quoting without running a
   shell: whitespace separates words, `'…'` is literal, `"…"` allows `\"`,
   `\\`, `\$` and `` \` `` escapes, an unquoted backslash escapes the next
   character, and `''` or `""` is an empty argument. Each argument is MI-quoted
   separately for `-exec-arguments`. Empty cwd uses cdbg's current directory;
   a non-empty cwd must exist and is sent with `-environment-cd` before
   `-exec-run`. Environment pairs use `-environment-set-variable` (no unset in
   v1). Malformed input is reported in the dialog and leaves previous Session
   values unchanged. Apply never restarts a running program; the settings take
   effect at the next Run from a not-started target, Restart or Load. Cancel
   changes nothing. With no target loaded, Apply sets this directory's default
   Break at start (arguments/cwd/env require a target).
   **Appearance** (font, size, tab width, source line numbers) and **Keyboard**
   (searchable Record/Reset/Disable bindings) auto-save to
   `$XDG_CONFIG_HOME/cwhip/cdbg.toml`. Keyboard lists View panel commands with
   empty defaults so stepping F-keys stay free unless you bind them.

   Break at start inserts a temporary GDB breakpoint on the entry symbol for each
   new run, so it never accumulates duplicates and is not saved with the user's
   breakpoints. For Cwhip programs the entry symbol is the generated `main`
   function, which is the program's `start { … }` block, so it stops on the
   `start {` line; the status reads "Stopped at start". For native programs it
   stops in `main()`. If the executable has no entry symbol (for example a
   stripped binary), the Debugger Console reports "Break at start unavailable"
   and the program runs without it. cdbg sets no other automatic breakpoint.
4. The right-hand side is a fixed multi-pane layout (not one notebook of seven
   tabs): Locals/Watches/Runtime Values share a top notebook; Stack/Breakpoints/
   Threads share a middle notebook; Program Output and Debugger Console sit
   side by side at the bottom. **View** menu check items show or hide each pane
   (Runtime Values and Threads are hidden by default). View toggles have no
   default shortcuts; assign them under **Preferences > Keyboard** if wanted.
   At each stop the source location/current line, Locals / Arguments, Stack,
   Threads, and Watches are refreshed.
   Right-click the **Watches (Cwhip / Native)** tab and choose **Add Watch…**.
   The parented dialog has an expression entry and **Add** / **Cancel**
   buttons. Out-of-scope/evaluation errors are displayed alongside the
   expression. Activating a Locals or Watches row (or **Add Watch for Symbol**)
   adds a watch for the left-hand name; **Copy Friendly Value** copies the
   right-hand summary.
5. Single-click a **Stack** entry to inspect that frame's source, locals and
   watches. Single-click a **Threads** entry to select that thread
   (`-thread-select`) then refresh stack/locals/watches. Both are browse-only
   (no thread create/control). Step/continue operations restore the actual
   execution frame (frame zero) first, and the next stop brings the source
   view back to the executing file and line.

### Cwhip values and runtime values

**Locals / Arguments (Cwhip / Native)** and **Watches (Cwhip / Native)** use
the same read-only inspector. **Runtime Values** separately retains both
groups' GDB type names and raw values, including watch expressions and errors.
All three views follow the selected stack frame and refresh at each stop.
Native/runtime C frames keep GDB's native formatting; a native pointer is not
treated as a Cwhip object merely because of its address.

In Cwhip frames, identified by source-file DWARF and named DWARF types:

- `int8`/`uint8`, `int16`/`uint16`, `int32`/`uint32`, `int64`/`uint64`,
  `fp32`/`fp64` and `bool` have scalar values (`true`/`false` for booleans);
  null object references show `null`. Small integers display as decimal
  numbers, not character literals; Runtime Values retains GDB's raw formatting.
- `String` shows quoted UTF-8 contents with escaped quotes, backslashes and
  control characters, including embedded NUL. Those bytes are the string
  object's own `data` and `length`, not a nested buffer. Invalid UTF-8 bytes
  are escaped.
- `list` and `dict` show their length and up to eight entries; `buffer` shows
  its length and up to 256 bytes in hexadecimal. Runtime-tagged
  signed/unsigned integers of all four widths, fp32/fp64, boolean and String
  entries are decoded. Floating payloads are bit-decoded at their actual width.
  Typed `range<T>` values show their inclusive typed bounds, including
  descending ranges; boxed ranges in lists and maps use the same summary, and
  typed or boxed null ranges display as `null`. Range-loop iterators appear as
  their current scalar values in locals and watches. Nested containers are
  bounded to two levels; other tags remain explicitly labeled runtime tags.
- User classes with complete `-g` DWARF members show named fields (bounded by
  the same child/depth limits as containers), for example
  `Counter {value: 0}`. Watches such as `worker.value` or nested members use
  GDB member access. Forward-declared or unreadable types still report
  **members unavailable**. `any`/`type` structures and opaque handles are not
  decoded.

The helper uses named runtime struct DWARF, not guessed memory offsets, and
never calls inferior functions. Missing runtime DWARF, unreadable memory,
optimized-out/unavailable values and out-of-scope expressions are reported
explicitly. Reads are bounded to 256 bytes per string/buffer, eight children
per container, two container levels and 64 locals; raw formatting is bounded
to eight elements/two levels and 4096 characters per value. Truncation is
marked. Watches support read-only identifiers, member/index access and
arithmetic, not calls, assignments or increment/decrement. This is GDB's
expression syntax, not a full Cwhip expression evaluator.

The inspector is embedded in cdbg and requires Python-enabled GDB with
`gdb.MICommand` (validated with GDB 16.3). If unavailable, the Debugger Console
reports the limitation; debugging and raw native locals remain usable, but
watches explicitly report that the value inspector is unavailable.
No compiler, ABI or runtime behavior changes are needed for these summaries.

Each Step Into, Step Over or Step Out activation sends one GDB execution
command, including after browsing a caller. Dedicated shortcuts are F5
(continue), F10 (over), F11 (into) and Shift+F11 (out); toolbar buttons remain.
Run/Continue and the step buttons stay enabled while the post-stop
locals/stack/watch refresh is still running: a press discards the queued
refresh requests, ignores the reply to one already sent, restores frame 0 if a
caller was browsed, and then sends the command. Only one execution command may
be outstanding; a second press before GDB reports `*running`/`*stopped` is not
sent and the status line says it was ignored.
The stopped status includes GDB's stop reason and program counter. Consecutive
stops at the same file/line/function explicitly say **same source line** and
show the previous PC when Step Over did not already absorb them. On Cwhip
sessions, Step Into finishes out of thin runtime prologues and sourceless
frames until a Cwhip stop or an openable runtime frame (status notes skipped
runtime frames). Step Over stays at the current call depth and absorbs
same-line PC moves. Pure C sessions keep every stop.

Use freshly compiled `-g` targets: the compiler avoids no-op dispatch thunks
and emits complete class member DWARF for user types. Restart of a `.cw`
session recompiles before relaunching; Restart of a prebuilt executable does
not rebuild.

There are no breakpoint/watch/frame entry rows or End Session button in the
main window. **Quit** (or closing the window) stops GDB and its owned inferior,
closes the output PTY and dialogs, cancels polling, and removes temporary
compiler outputs.

Source files occupy separate notebook tabs. Debug-info sources are opened on
load, and stopping in another file opens/selects its tab without duplicates.
Every source and inspector tab is drawn with a border, and each source tab has a
close icon. Closing a tab never ends the debug session; if execution later stops
in a closed file, its tab is reopened (once).
The highlighted stopped line is centered vertically where the buffer allows;
stepping in the same file reuses its buffer rather than reloading/re-scrolling
the entire file. Load Executable reloads source contents; **Restart** retains them.
Source and inspector panes are read-only, retain text selection/copy, and omit
Insert Emoji from their right-click menus.

**Program Output** shows the inferior's stdout and stderr, combined in arrival
order through an owned local pseudo-terminal set with GDB's `-inferior-tty-set`.
**Debugger Console** shows GDB diagnostics and compiler output separately.
Inferior output cannot be mistaken for GDB/MI records. Terminal newline conversion
is disabled; terminal escape sequences are displayed as text, not interpreted.
Invalid UTF-8 uses replacement characters and NUL bytes are displayed as `\0`.
Right-click **Program Output** for **Clear**, **Copy** (the current selection)
and **Copy All**. Clear only discards the displayed history: the program keeps
running and later output is appended. Right-clicking inside a selection keeps
it, and normal keyboard selection/Ctrl+C copy remains available.
Watch expressions for the current target are persisted in `.cdbg.toml` with
breakpoints and restored on load. GDB command/result records use numeric
correlation tokens, a bounded
queue and a structured parser for nested tuples/lists and C-string escapes;
paths and expressions are MI-quoted rather than executed through a shell.
The GUI polls the async process with a bounded 10 ms wait, processing up to 64
events per callback. Each output history is limited to 64 KiB and an individual MI
record to 1 MiB.

## Saved settings

Settings live in `.cdbg.toml` in the directory cdbg runs in (the debugger and
inferior working directory), so each project keeps its own breakpoints and
watches:

```toml
version = 1
break_at_start = true          # directory default for targets without Session Apply
width = 1100
height = 760
maximized = false
pane = 600
right_split = 420
mid_split = 220
bottom_split = 400
show_locals = true
show_watches = true
show_stack = true
show_breaks = true
show_output = true
show_console = true
show_runtime = false
show_threads = false

["/abs/path/program.cw"]       # canonical executable, or .cw for cdbg file.cw
break_at_start = false
arguments = "one 'two words' ''"
cwd = "/abs/path/project"
env = "FOO=bar\nBAZ=1"
points = [
{ file = "/abs/path/program.cw", line = 4, enabled = true, condition = "", hit_count = 0 },
]
watches = [
{ expression = "worker.value" },
]
```

Appearance, keyboard shortcuts and the global default break-at-start also live
in `$XDG_CONFIG_HOME/cwhip/cdbg.toml` (or `~/.config/cwhip/cdbg.toml`).

Target tables are keyed by canonical executable path; for `cdbg file.cw` the
key is the canonical source path, never the temporary compiled executable.
Symlink aliases share a key. Resolved locations are saved as file:line entries;
multi-location groups are restored as individual file:line breakpoints rather
than recreating a function breakpoint. A target's `break_at_start`, `arguments`, `cwd` and `env` are written only after
Session Apply for it. Watch expressions are saved with the target whenever they
change.

Earlier versions used a global `$XDG_CONFIG_HOME/cdbg/state.toml` (or
`~/.config/cdbg/state.toml`). That file is now neither read nor modified, so
breakpoints from other projects are never imported. When it exists, the
Debugger Console notes that it is ignored. To migrate, copy the wanted
`["/target"]` tables (and layout keys) by hand into the project's
`.cdbg.toml`.

Snapshots are written atomically after breakpoint/Session changes and on Quit,
using private file permissions and a content/ETag guard against concurrent
changes. If the directory is not writable, the status line, Debugger Console
and stderr report "Settings not saved to …" (once per distinct error) and
debugging continues; Session Apply reports that settings were not saved.
Restore occurs after GDB accepts the target. Invalid, missing or unresolvable
locations are skipped with a Debugger Console/stderr diagnostic; the session
continues. Up to 256 resolved locations per target and a 256 KiB file are
supported; limits are reported rather than silently ignored.

Quit also saves window width/height, maximized state, the source/right divider
(`pane`), right-column vertical dividers (`right_split`, `mid_split`), the
bottom output/console divider (`bottom_split`), and View-menu panel visibility
flags. Startup clamps size to 640–3840 by 400–2160 and the main divider to 100
through width minus 100; GTK may further constrain dimensions to the available
screen. An obsolete `inspector` key is ignored.
Notebook headers scroll when necessary, so tab titles do not force the divider
away from its saved position. A malformed/unreadable file falls back to
defaults, logs a diagnostic and disables saving to preserve the original file
for repair. Invalid individual values use defaults; out-of-range numbers are
clamped; invalid saved arguments are ignored with a diagnostic.

## Boundaries

Only local launch is supported: no remote debugging, attach, DAP, LLDB,
multitarget sessions, disassembly or register view yet. The Threads pane is
browse/select only (`-thread-info` / `-thread-select`); there is no thread
create or control UI. Session Preferences can set inferior working directory
and environment variables for the next run; unsetting variables is not
supported. Inferior interactive stdin/terminal emulation is not provided: the
output PTY supplies no user input, so programs waiting on stdin must be
paused/ended. The stack view is capped at 31 frames. Watches use the read-only
subset of GDB expressions described above; calls and mutations are rejected and
inferior function calls are disabled in the session.

cdbg provides bounded String/container/class field summaries, not an expandable
object tree. Watch expressions and breakpoints for the current target are
persisted in `.cdbg.toml`. Watches and Breakpoints tabs have context menus for
add/delete, enable/disable/delete, and breakpoint **Edit Condition…** /
**Hit Count…** (GDB `-break-condition` / `-break-after`). LLDB, DAP,
remote/attach, inferior stdin, register/disassembly views and embedding into
cedit remain deferred.

## Debug a Cwhip app (walkthrough)

```sh
cdbg app.cw
```

1. Wait for compile/`Loaded`, then click a source line and press F9 to set a
   breakpoint.
2. Press F5 (**Run / Continue**). When stopped, Locals shows scalars, Strings,
   containers and class fields from DWARF.
3. Press F11 (**Step Into**) on a method call — the stop should be the callee's
   first `.cw` line, not `RuntimeGc.c`.
4. Right-click Watches → **Add Watch…**, enter `self.x` or `obj.child.count`.
5. Read stdout on the **Program Output** tab; use **Restart** after editing
   `app.cw` to rebuild and relaunch.

## Checks

With Xvfb, dbus-daemon and GDB installed, run the standalone component suite:

```sh
./scripts/setup
build test-all
```

The suite checks MI quoting/parsing (including fragmented transport input),
real local GDB launch, source compilation with `-g`, source locations,
breakpoints, stepping, locals, watches, stack-frame selection, errors and
teardown under a private GTK display/session bus with local GIO backends, so
desktop GVFS services cannot pollute the test diagnostics. Stderr assertions
remain strict. Missing GDB is reported
explicitly at configuration time rather than counted as a passing GUI test.
The value regression compiles real Cwhip `-g` code and compares the exact local
and watch representations for scalars, escaped/non-ASCII Strings, null, classes,
lists, dictionaries, buffers and truncated Strings. It checks separate raw
types/values, refresh after stepping/frame selection, rejected calls/mutations,
out-of-scope watches and native/runtime-frame behavior. Formatter checks run
inside real GDB for unreadable pointers, unknown runtime tags, native-pointer
fallback and escaping; a real optimized native frame verifies `<optimized out>`,
and the optimized/unavailable branches also have isolated checks.
Load-time source checks cover source paths (including relative paths), executables
with DWARF, and explicit missing-debug-source feedback. Restart checks cover
stopped, running and exited targets, retained breakpoints/watches, and cleanup
of the previous inferior.
UI regressions check source-tab reuse across files, read-only/no-Emoji panes and
the actual source popup, parented modal load-error dialogs, measured viewport
centering and unchanged buffer content on step, and stdout/stderr isolation
(including MI-looking program output). A File/Search regression drives the real
menus, file chooser, Ctrl+F/Ctrl+Q shortcuts and Find dialog: failed opens
(missing, binary, ELF executable, invalid UTF-8) keep the source area and tabs
unchanged, Load Executable versus Open Source Code, Find Next/Previous with
wraparound and not-found, tab close/reopen-on-stop without duplicates, and tab
borders/close icons.
Further live interaction checks exercise source clicks, both Breakpoint menu
items and F9/Ctrl+F9, enabled/disabled source marks for resolved/multiple GDB
locations and reopened tabs, absence of the old action popovers, watch dialog Add/Cancel
and evaluation failures, stack single-click navigation, and Step Over returning
to frame zero's actual next line. They also check the absence of the removed
controls, marker preservation on Restart/restoration on fresh load, and complete
Quit cleanup. Real quit/relaunch checks cover executable and `.cw` keys,
canonical symlink keys, disabled states, window/layout restoration, stale and
corrupt state, range clamping, local `.cdbg.toml` per working directory, an
ignored (unchanged, not imported) global XDG file and an unwritable directory.
A Cwhip `-g` regression sets line breakpoints with F9 and the Breakpoint menu in
a method and in `start`, and checks that the running program actually stops at
start, then in the method, then at the later line; that an uncalled method's
breakpoint is reported as not reached; Session Preferences Apply/Cancel and invalid quoting;
arguments with spaces, quotes and an empty string reaching the program; Program
Output Copy, Copy All (via the real clipboard) and Clear followed by new output;
Restart without duplicate start breakpoints; and a real relaunch restoring
breakpoints, arguments and Break at start off (first stop in the method; Apply
while stopped does not restart).
The stepping regression drives each toolbar button by click and focused GTK
keyboard activation, starting at Break at start, a method breakpoint and after
stack navigation. It checks exact source lines and one stop per activation,
including method returns and consecutive caller lines. Compiler-internal
`RuntimeGc.c` source-line checks run only when configured explicitly with
`-DCDBG_RUNTIME_SOURCE=/path/to/RuntimeGc.c`; otherwise the test reports that
coverage as excluded and still runs the rest of the stepping session. When
enabled, a real instruction-level same-line runtime stop verifies the PC/reason
display without automatically skipping it. The raw GDB stdin/stdout transcript
is retained in the test work directory as `stepping.mi`.
The suite also presses Step Over while the post-stop refresh is still pending,
presses it again before `*running` (one `-exec-next` is sent and the status
reports the ignored press), and presses Step Out while a stack-frame browse is
in flight (frame 0 is restored first).
An external-edit check verifies that atomic saving does not overwrite another writer.
When `xfwm4` is available the private test display also verifies actual
maximization/restore; its session management is disabled.
