# cdbg local debugger prototype

`cdbg` is a separate Cwhip/GTK/GtkSourceView application, inspired by KDbg's
source-and-inspector layout. This is a working **local GDB/MI2 prototype**, not
an editor mode or a finished debugger. The Cwhip compiler is still `cwhip`.

## Build and launch

Install the same GTK 4.10+ and GtkSourceView 5 development dependencies as
[cedit](https://github.com/chucktilbury/cedit/blob/main/CEDIT.md), plus `gdb` at runtime:

```sh
cmake -S . -B build -DCWHIP_GTK=ON -DCWHIP_GTK_SOURCEVIEW=ON
cmake --build build --target cedit cdbg -j4
./bin/cdbg examples/debugger.cw
```

The build stages `<CWHIP_STAGE_PREFIX>/bin/cdbg` (by default `<source>/bin/cdbg`).
Like cedit, it is not currently a `cmake --install` target and does not install
desktop metadata. Compiler-only configurations provide a `cdbg` target which
fails with a clear missing-GUI dependency message.

`cdbg [SOURCE.cw|EXECUTABLE [-- ARGS...]]` opens the GUI in the foreground;
arguments after the target are passed individually to the inferior, without a
shell. Command-line arguments override the target's saved Setup arguments for
that command-line session (including Restart) but are not saved; applying Setup
replaces them, and a later File > Load Executable uses the saved arguments.
A `.cw` command-line target is compiled
asynchronously using `cwhip -g` to an owned temporary executable. Compilation
errors appear in a parented modal dialog, the status line, Debugger Console and
stderr; user source/output files
are not overwritten. Other paths are treated as prebuilt executables; compile
these with debug information. Temporary compiler outputs are removed when the
session ends or the window closes.

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
   line and choose **Breakpoint > Set/Clear Breakpoint** (F9). This sets a
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
2. **Run / Continue**, **Step Into**, **Step Over**, **Step Out** and **Pause**
   use GDB's run/continue/step/next/finish/interrupt commands. Controls reflect
   running versus stopped state. **File > Load Executable…** ends the old GDB
   process group and starts a fresh session. **Restart** stops the current inferior
   and runs the already loaded executable from the beginning, preserving
   breakpoints, watches and arguments. It works while running, stopped or after
   exit; it does not recompile source. Restart cdbg with the `.cw` path, or load
   a rebuilt executable, after changing the source.
3. **Debug > Setup…** opens a dialog parented to the main window with
   **Break at start** (on by default for a new configuration), a program
   **Arguments** field, and **Apply** / **Cancel**. Arguments use shell-like
   quoting without running a shell: whitespace separates words, `'…'` is
   literal, `"…"` allows `\"`, `\\`, `\$` and `` \` `` escapes, an unquoted
   backslash escapes the next character, and `''` or `""` is an empty
   argument. Each argument is MI-quoted separately for `-exec-arguments`.
   Malformed input (unterminated quote, trailing backslash) is reported in the
   dialog and leaves the previous arguments and session unchanged. Apply never
   restarts a running program; the settings take effect at the next Run from a
   not-started target, Restart or Load. Cancel changes nothing. With no target
   loaded, Apply sets this directory's default Break at start.

   Break at start inserts a temporary GDB breakpoint on the entry symbol for each
   new run, so it never accumulates duplicates and is not saved with the user's
   breakpoints. For Cwhip programs the entry symbol is the generated `main`
   function, which is the program's `start { … }` block, so it stops on the
   `start {` line; the status reads "Stopped at start". For native programs it
   stops in `main()`. If the executable has no entry symbol (for example a
   stripped binary), the Debugger Console reports "Break at start unavailable"
   and the program runs without it. cdbg sets no other automatic breakpoint.
4. At each stop the source location/current line, Locals / Arguments, Stack,
   and Watches are refreshed. Right-click the **Watches (Cwhip / Native)** tab and choose
   **Add Watch…**. The parented dialog has an expression entry and **Add** /
   **Cancel** buttons. Out-of-scope/evaluation errors are displayed alongside
   the expression.
5. Single-click a **Stack** entry to inspect that frame's source, locals and
   watches. This browses the stack without executing. Step/continue operations
   restore the actual execution frame (frame zero) first, and the next stop
   brings the source view back to the executing file and line.

### Cwhip values and runtime values

**Locals / Arguments (Cwhip / Native)** and **Watches (Cwhip / Native)** use
the same read-only inspector. **Runtime Values** separately retains both
groups' GDB type names and raw values, including watch expressions and errors.
All three views follow the selected stack frame and refresh at each stop.
Native/runtime C frames keep GDB's native formatting; a native pointer is not
treated as a Cwhip object merely because of its address.

In Cwhip frames, identified by source-file DWARF and named DWARF types:

- `int`, `unsigned`, `float` and `bool` have scalar values (`true`/`false`
  for booleans); null object references show `null`.
- `String` shows quoted UTF-8 contents with escaped quotes, backslashes and
  control characters, including embedded NUL. Invalid UTF-8 bytes are escaped.
- `list` and `dict` show their length and up to eight entries; `buffer` shows
  its length and up to 256 bytes in hexadecimal. Runtime-tagged integer,
  unsigned, float, boolean and String entries are decoded. Nested containers
  are bounded to two levels; other tags remain explicitly labeled runtime tags.
- Classes show their DWARF type, runtime field count and address with
  **members unavailable**. The compiler currently emits forward declarations,
  not member DWARF: the inspector does not invent field offsets. `any`/`type`
  structures and opaque handles are not decoded.

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
command, including after browsing a caller. The focused toolbar buttons also
support GTK keyboard activation; there are no dedicated step-key shortcuts.
Run/Continue and the step buttons stay enabled while the post-stop
locals/stack/watch refresh is still running: a press discards the queued
refresh requests, ignores the reply to one already sent, restores frame 0 if a
caller was browsed, and then sends the command. Only one execution command may
be outstanding; a second press before GDB reports `*running`/`*stopped` is not
sent and the status line says it was ignored.
The stopped status includes GDB's stop reason and program counter. Consecutive
stops at the same file/line/function explicitly say **same source line** and
show the previous PC. A return can legitimately land back on the caller's call
line, and runtime C code can have multiple instruction positions on one line;
cdbg does not auto-step past these stops. Step Into may enter runtime checks
before a Cwhip method, whereas Step Over stays at the current call depth.

Use freshly compiled `-g` targets: the compiler now avoids no-op dispatch
thunks and tail-transfers receiver-adjustment thunks, so method returns do not
land in anonymous dispatch frames with missing GDB function bounds. Restart
alone does not rebuild an already loaded executable.

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
Watch expressions persist in memory between loads but not across application
restarts. GDB command/result records use numeric correlation tokens, a bounded
queue and a structured parser for nested tuples/lists and C-string escapes;
paths and expressions are MI-quoted rather than executed through a shell.
The GUI polls the async process with a bounded 10 ms wait, processing up to 64
events per callback. Each output history is limited to 64 KiB and an individual MI
record to 1 MiB.

## Saved settings

Settings live in `.cdbg.toml` in the directory cdbg runs in (the debugger and
inferior working directory), so each project keeps its own breakpoints:

```toml
version = 1
break_at_start = true          # directory default for targets without Setup
width = 1100
height = 760
maximized = false
pane = 600
inspector = 0

["/abs/path/program.cw"]       # canonical executable, or .cw for cdbg file.cw
break_at_start = false
arguments = "one 'two words' ''"
points = [
{ file = "/abs/path/program.cw", line = 4, enabled = true },
]
```

Target tables are keyed by canonical executable path; for `cdbg file.cw` the
key is the canonical source path, never the temporary compiled executable.
Symlink aliases share a key. Resolved locations are saved as file:line entries;
multi-location groups are restored as individual file:line breakpoints rather
than recreating a function breakpoint. A target's `break_at_start` and
`arguments` are written only after Setup is applied for it. Watches remain
memory-only.

Earlier versions used a global `$XDG_CONFIG_HOME/cdbg/state.toml` (or
`~/.config/cdbg/state.toml`). That file is now neither read nor modified, so
breakpoints from other projects are never imported. When it exists, the
Debugger Console notes that it is ignored. To migrate, copy the wanted
`["/target"]` tables (and layout keys) by hand into the project's
`.cdbg.toml`.

Snapshots are written atomically after breakpoint/Setup changes and on Quit,
using private file permissions and a content/ETag guard against concurrent
changes. If the directory is not writable, the status line, Debugger Console
and stderr report "Settings not saved to …" (once per distinct error) and
debugging continues; Setup reports that settings were not saved. Restore occurs
after GDB accepts the target. Invalid, missing or unresolvable locations are
skipped with a Debugger Console/stderr diagnostic; the session continues. Up to
256 resolved locations per target and a 256 KiB file are supported; limits are
reported rather than silently ignored.

Quit also saves window width/height, maximized state, the source/inspector
divider position and selected inspector tab. Startup clamps size to 640–3840
by 400–2160, the divider to 100 through width minus 100, and the inspector index
to 0–5; GTK may further constrain dimensions to the available screen.
Notebook headers scroll when necessary, so tab titles do not force the divider
away from its saved position. A malformed/unreadable file falls back to
defaults, logs a diagnostic and disables saving to preserve the original file
for repair. Invalid individual values use defaults; out-of-range numbers are
clamped; invalid saved arguments are ignored with a diagnostic.

## Boundaries

Only local launch is supported: no remote debugging, attach, DAP, LLDB,
multitarget sessions, thread-selection UI, disassembly, register view, or
environment/working-directory settings yet. Inferior interactive stdin/terminal emulation is not
provided: the output PTY supplies no user input, so programs waiting on stdin
must be paused/ended. The stack view is capped at 31 frames. Watches use the
read-only subset of GDB expressions described above; calls and mutations are
rejected and inferior function calls are disabled in the session.

Cwhip's current DWARF exposes scalar locals/arguments and pointer-backed class
values; it does not yet describe full class member layouts. cdbg provides the
bounded String/container/class summaries described above, not an expandable
Cwhip object tree. Step Into may enter compiler/runtime
helpers; use Step Out or file:line breakpoints to return to source. LLDB/DAP and
richer Cwhip object inspection are follow-up work, not implemented features.
Gutter-click breakpoint toggles remain future work. The Breakpoint menu,
Watches context dialog, tab borders and source-tab close icons are implemented.

## Checks

With Xvfb, dbus-daemon and GDB installed:

```sh
ctest --test-dir build -R '^cdbg_' --output-on-failure
```

The suite checks MI quoting/parsing (including fragmented transport input),
real local GDB launch, source compilation with `-g`, source locations,
breakpoints, stepping, locals, watches, stack-frame selection, errors and
teardown under a private GTK display/session bus. Missing GDB is reported
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
breakpoint is reported as not reached; Setup Apply/Cancel and invalid quoting;
arguments with spaces, quotes and an empty string reaching the program; Program
Output Copy, Copy All (via the real clipboard) and Clear followed by new output;
Restart without duplicate start breakpoints; and a real relaunch restoring
breakpoints, arguments and Break at start off (first stop in the method; Apply
while stopped does not restart).
The stepping regression drives each toolbar button by click and focused GTK
keyboard activation, starting at Break at start, a method breakpoint and after
stack navigation. It checks exact source lines and one stop per activation,
including actual `RuntimeGc.c` steps, method returns and consecutive caller
lines. A real instruction-level same-line runtime stop verifies the PC/reason
display without automatically skipping it. Its raw GDB stdin/stdout transcript
It also presses Step Over while the post-stop refresh is still pending,
presses it again before `*running` (one `-exec-next` is sent and the status
reports the ignored press), and presses Step Out while a stack-frame browse is
in flight (frame 0 is restored first). is retained in the test work directory as `stepping.mi`.
An external-edit check verifies that atomic saving does not overwrite another writer.
When `xfwm4` is available the private test display also verifies actual
maximization/restore; its session management is disabled.
