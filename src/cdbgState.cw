void Cdbg.stateDiagnostic(String text) {
        String message = DebugDiagnostic().emit("warning", "CDBG2001",
            format("{}: {}", statePath, text))
        log(format("{}\n", message))
    }

int64 Cdbg.stateNumber(String key, int64 fallback, int64 minimum, int64 maximum) {
        String raw = Gtk.Config().value(stateText, "", key)
        if (!raw.startsWith("i") || raw.length > 8 || !identifier(byteSpan(raw, 1, raw.length))) {
            if (!raw.equals("")) { stateDiagnostic(format("Invalid {}; using default", key)) }
            return(fallback)
        }
        int64 value = byteSpan(raw, 1, raw.length).toInt64()
        if (value < minimum) { return(minimum) }
        if (value > maximum) { return(maximum) }
        return(value)
    }

void Cdbg.readState() {
        stateText = ""
        stateWritable = true
        stateTarget = ""
        stateError = ""
        stateNote = ""
        // Settings are local to the directory cdbg runs in. The earlier global
        // XDG state file is neither read nor written; migrate it by hand.
        statePath = System.FileSystem().join(System.FileSystem().getCwd(), ".cdbg.toml")
        String home = System.Process().getEnv("XDG_CONFIG_HOME")
        if (home.equals("") && !System.Process().getEnv("HOME").equals("")) {
            home = System.FileSystem().join(System.Process().getEnv("HOME"), ".config")
        }
        if (!home.equals("") && System.FileSystem().isFile(System.FileSystem().join(home, "cdbg/state.toml"))) {
            stateNote = format("Note: global {} is ignored; settings now live in {} (copy entries by hand to migrate)\n",
                System.FileSystem().join(home, "cdbg/state.toml"), statePath)
        }
        String presence = Gtk.Config().fileStatus(statePath)
        if (presence.equals("missing")) { return }
        if (!presence.equals("") || !System.FileSystem().isFile(statePath) ||
            System.FileSystem().fileSize(statePath) > 262144) {
            stateWritable = false
            stateDiagnostic("Cannot read state; using defaults and leaving file unchanged")
            return
        }
        System.File file = null
        try {
            file = System.File(statePath, "r")
            stateText = file.readAll()
            String error = System.System().lastError()
            file.close()
            if (!error.equals("")) { raise(Exception(error)) }
            String problem = Gtk.Config().validate(stateText)
            if (!GtkSource.Content().isText(stateText) || !problem.equals("") ||
                !Gtk.Config().value(stateText, "", "version").equals("i1")) {
                raise(Exception(format("Invalid state TOML/version: {}", problem)))
            }
        } except(Exception) as error {
            if (file != null && file.isOpen()) { file.close() }
            stateWritable = false
            stateText = ""
            stateDiagnostic(format("{}; using defaults and leaving file unchanged", error.message))
            return
        }
        int64 width = stateNumber("width", 1100, 640, 3840)
        window.setDefaultSize(width, stateNumber("height", 760, 400, 2160))
        body.setPosition(stateNumber("pane", 600, 100, width - 100))
        int64 height = stateNumber("height", 760, 400, 2160)
        if (rightColumn != null) {
            rightColumn.setPosition(stateNumber("right_split", 420, 80, height - 80))
        }
        if (topMid != null) {
            topMid.setPosition(stateNumber("mid_split", 220, 60, height - 60))
        }
        if (bottomRow != null) {
            bottomRow.setPosition(stateNumber("bottom_split", 400, 80, width - 80))
        }
        showLocals = savedFlag("", "show_locals", true)
        showWatches = savedFlag("", "show_watches", true)
        showStack = savedFlag("", "show_stack", true)
        showBreaks = savedFlag("", "show_breaks", true)
        showOutput = savedFlag("", "show_output", true)
        showConsole = savedFlag("", "show_console", true)
        showRuntime = savedFlag("", "show_runtime", false)
        showThreads = savedFlag("", "show_threads", false)
        syncInspectionPages()
        syncViewMenuChecks()
        String maximized = Gtk.Config().value(stateText, "", "maximized")
        if (maximized.equals("btrue")) { window.setMaximized(true) }
        else { if (!maximized.equals("") && !maximized.equals("bfalse")) {
            stateDiagnostic("Invalid maximized; using default")
        } }
    }

bool Cdbg.savedFlag(String table, String key, bool fallback) {
        String raw = Gtk.Config().value(stateText, table, key)
        if (raw.equals("btrue")) { return(true) }
        if (raw.equals("bfalse")) { return(false) }
        if (!raw.equals("")) { stateDiagnostic(format("Invalid {}; using default", key)) }
        return(fallback)
    }

// Per-target setup: Break at start defaults to the directory default
// (true for a new configuration). Command-line arguments after -- override
// saved arguments for that command-line session only and are not saved.
void Cdbg.loadTargetSettings() {
        breakAtStart = savedFlag("", "break_at_start", settings.defaultBreakAtStart)
        targetSettings = false
        arguments = []
        argumentText = ""
        startBreakpoint = ""
        if (!Gtk.Config().value(stateText, stateTarget, "break_at_start").equals("")) {
            breakAtStart = savedFlag(stateTarget, "break_at_start", breakAtStart)
            targetSettings = true
        }
        String saved = Gtk.Config().value(stateText, stateTarget, "arguments")
        if (saved.startsWith("s")) {
            ArgumentList parsed = ArgumentList()
            if (parsed.parse(byteSpan(saved, 1, saved.length))) {
                arguments = parsed.values
                argumentText = byteSpan(saved, 1, saved.length)
                targetSettings = true
            } else { stateDiagnostic(format("Invalid saved arguments ({}); ignored", parsed.error)) }
        } else { if (!saved.equals("")) { stateDiagnostic("Saved arguments must be a string; ignored") } }
        sessionCwd = ""
        String cwdSaved = Gtk.Config().value(stateText, stateTarget, "cwd")
        if (cwdSaved.startsWith("s")) {
            String path = byteSpan(cwdSaved, 1, cwdSaved.length)
            String absolute = System.FileSystem().absolutePath(path)
            if (absolute.equals("")) { absolute = path }
            if (System.FileSystem().isDir(absolute)) {
                sessionCwd = absolute
                targetSettings = true
            } else {
                stateDiagnostic(format("Saved working directory missing or not a directory ({}); ignored", path))
            }
        } else { if (!cwdSaved.equals("")) { stateDiagnostic("Saved cwd must be a string; ignored") } }
        environmentText = ""
        environmentPairs = []
        String envSaved = Gtk.Config().value(stateText, stateTarget, "env")
        if (envSaved.startsWith("s")) {
            EnvironmentList env = EnvironmentList()
            if (env.parse(byteSpan(envSaved, 1, envSaved.length))) {
                environmentPairs = env.pairs
                environmentText = env.display(env.pairs)
                targetSettings = true
            } else { stateDiagnostic(format("Invalid saved environment ({}); ignored", env.error)) }
        } else { if (!envSaved.equals("")) { stateDiagnostic("Saved env must be a string; ignored") } }
        if (cliPending) {
            arguments = cliArguments
            cliPending = false
            log(format("Using command-line arguments: {}\n", ArgumentList().display(arguments)))
        }
    }

void Cdbg.saveState(bool layout) {
        if (!stateWritable || statePath.equals("") || window == null || window.disposed()) { return }
        String updates = "version = 1\n"
        if (defaultChanged) { updates.append(format("break_at_start = {}\n", breakAtStart)) }
        if (layout) {
            int64 bottom = 400
            int64 right = 420
            int64 mid = 220
            if (bottomRow != null) { bottom = bottomRow.position() }
            if (rightColumn != null) { right = rightColumn.position() }
            if (topMid != null) { mid = topMid.position() }
            updates.append(format("width = {}\nheight = {}\nmaximized = {}\npane = {}\nright_split = {}\nmid_split = {}\nbottom_split = {}\nshow_locals = {}\nshow_watches = {}\nshow_stack = {}\nshow_breaks = {}\nshow_output = {}\nshow_console = {}\nshow_runtime = {}\nshow_threads = {}\n",
                window.defaultWidth(), window.defaultHeight(), window.maximized(), body.position(),
                right, mid, bottom, showLocals, showWatches, showStack, showBreaks, showOutput,
                showConsole, showRuntime, showThreads))
        }
        bool points = loaded && !restoringBreakpoints
        if (!stateTarget.equals("") && (points || targetSettings)) {
            updates.append(format("[{}]\n", Gtk.Config().quote(stateTarget)))
            if (targetSettings) {
                updates.append(format("break_at_start = {}\narguments = {}\ncwd = {}\nenv = {}\n",
                    breakAtStart, Gtk.Config().quote(argumentText), Gtk.Config().quote(sessionCwd),
                    Gtk.Config().quote(environmentText)))
            }
        }
        if (points && !stateTarget.equals("")) {
            if (breakpointLocations.length > 256) {
                stateDiagnostic("Only the first 256 resolved breakpoint locations will be saved")
            }
            updates.append("points = [\n")
            list locations = []
            int64 i = 0
            while (i < breakpointLocations.length && locations.length < 256) {
                DebugBreakpoint point = breakpointLocations[i] as DebugBreakpoint
                String key = format("{}:{}", point.path, point.line)
                bool duplicate = false
                int64 j = 0
                while (j < locations.length) {
                    if ((locations[j] as String).equals(key)) { duplicate = true }
                    j = j + 1
                }
                if (!duplicate && !point.path.equals("") && identifier(point.line)) {
                    locations.append(key)
                    bool enabled = point.enabled
                    int64 k = 0
                    while (k < breakpointLocations.length) {
                        DebugBreakpoint other = breakpointLocations[k] as DebugBreakpoint
                        if (other.path.equals(point.path) && other.line.equals(point.line) && other.enabled) {
                            enabled = true
                        }
                        k = k + 1
                    }
                    updates.append(format(
                        "{{ file = {}, line = {}, enabled = {}, condition = {}, hit_count = {} }},\n",
                        Gtk.Config().quote(point.path), point.line, enabled,
                        Gtk.Config().quote(point.condition), point.ignoreCount))
                }
                i = i + 1
            }
            updates.append("]\n")
            updates.append("watches = [\n")
            i = 0
            while (i < expressions.length && i < 64) {
                updates.append(format("{{ expression = {} }},\n",
                    Gtk.Config().quote(expressions[i] as String)))
                i = i + 1
            }
            updates.append("]\n")
        }
        String text = Gtk.Config().merge(stateText, updates)
        if (text.equals("") || text.length > 262144) {
            saveError("snapshot exceeds its limit or cannot be serialized")
            return
        }
        String error = Gtk.Config().saveNow(statePath, text, stateText)
        if (!error.equals("")) { saveError(error)
            return }
        stateText = text
        stateError = ""
        defaultChanged = false
    }

// An unwritable directory is reported once per distinct error; debugging
// continues and nothing claims the settings were saved.
void Cdbg.saveError(String error) {
        String text = format("Settings not saved to {}: {}", statePath, error)
        if (!stateError.equals(error)) { stateDiagnostic(text) }
        stateError = error
        if (window != null && !window.disposed()) { status.setText(text) }
    }

void Cdbg.restoreBreakpoints() {
        restoringBreakpoints = true
        restorePending = 0
        String kind = Gtk.Config().value(stateText, stateTarget, "points")
        int64 count = Gtk.Config().arraySize(stateText, stateTarget, "points")
        if (count > 256) { stateDiagnostic("Saved breakpoint limit exceeded; restoring first 256 entries") }
        if (!kind.equals("") && count < 0) {
            stateDiagnostic("Saved breakpoints must be an array; skipped")
        } else {
            int64 i = 0
            while (i < count && i < 256) {
                String file = Gtk.Config().item(stateText, stateTarget, "points", i, "file")
                String line = Gtk.Config().item(stateText, stateTarget, "points", i, "line")
                String enabled = Gtk.Config().item(stateText, stateTarget, "points", i, "enabled")
                String condition = Gtk.Config().item(stateText, stateTarget, "points", i, "condition")
                String hits = Gtk.Config().item(stateText, stateTarget, "points", i, "hit_count")
                if (!file.startsWith("s") || !line.startsWith("i") || line.length > 8 ||
                    !identifier(byteSpan(line, 1, line.length)) || byteSpan(line, 1, line.length).toInt64() < 1 ||
                    (!enabled.equals("btrue") && !enabled.equals("bfalse"))) {
                    stateDiagnostic(format("Invalid saved breakpoint {}; skipped", i + 1))
                } else {
                    file = byteSpan(file, 1, file.length)
                    line = byteSpan(line, 1, line.length)
                    String condText = ""
                    if (condition.startsWith("s")) { condText = byteSpan(condition, 1, condition.length) }
                    else { if (!condition.equals("")) {
                        stateDiagnostic(format("Invalid condition on saved breakpoint {}; ignored", i + 1))
                    } }
                    int64 ignore = 0
                    if (hits.startsWith("i") && identifier(byteSpan(hits, 1, hits.length))) {
                        ignore = byteSpan(hits, 1, hits.length).toInt64()
                    } else { if (!hits.equals("")) {
                        stateDiagnostic(format("Invalid hit_count on saved breakpoint {}; ignored", i + 1))
                    } }
                    if (!System.FileSystem().isFile(file)) {
                        stateDiagnostic(format("Stale breakpoint {}:{}; skipped", file, line))
                    } else {
                        String command = "-break-insert"
                        if (enabled.equals("bfalse")) { command.append(" -d") }
                        restorePending = restorePending + 1
                        enqueue(format("{} {}", command, MiParser().quote(format("{}:{}", file, line))),
                            "restore-break", format("{}\n{}\n{}", format("{}:{}", file, line), condText, ignore))
                    }
                }
                i = i + 1
            }
        }
        if (restorePending == 0) { restoringBreakpoints = false }
        requestBreakpoints()
    }

void Cdbg.restoreWatches() {
        if (pendingWatchRestore.length > 0) {
            expressions = pendingWatchRestore
            pendingWatchRestore = []
            return
        }
        String kind = Gtk.Config().value(stateText, stateTarget, "watches")
        int64 count = Gtk.Config().arraySize(stateText, stateTarget, "watches")
        if (!kind.equals("") && count < 0) {
            stateDiagnostic("Saved watches must be an array; skipped")
            return
        }
        if (count <= 0) { return }
        list restored = []
        int64 i = 0
        while (i < count && i < 64) {
            String expression = Gtk.Config().item(stateText, stateTarget, "watches", i, "expression")
            if (!expression.startsWith("s") || expression.length > 4097) {
                stateDiagnostic(format("Invalid saved watch {}; skipped", i + 1))
            } else {
                expression = byteSpan(expression, 1, expression.length).trim()
                if (!expression.equals("")) {
                    bool duplicate = false
                    int64 j = 0
                    while (j < restored.length) {
                        if ((restored[j] as String).equals(expression)) { duplicate = true }
                        j = j + 1
                    }
                    if (!duplicate) { restored.append(expression) }
                }
            }
            i = i + 1
        }
        expressions = restored
    }

void Cdbg.maybeRebuildRun() {
        if (!rebuildPendingRun || restoringBreakpoints || restorePending > 0) { return }
        rebuildPendingRun = false
        status.setText("Rebuilt; restarting inferior")
        startRun()
    }
