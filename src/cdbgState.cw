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
        inspection.setCurrentPage(stateNumber("inspector", 0, 0, 6))
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
        breakAtStart = savedFlag("", "break_at_start", true)
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
            updates.append(format("width = {}\nheight = {}\nmaximized = {}\npane = {}\ninspector = {}\n",
                window.defaultWidth(), window.defaultHeight(), window.maximized(), body.position(),
                inspection.currentPage()))
        }
        bool points = loaded && !restoringBreakpoints
        if (!stateTarget.equals("") && (points || targetSettings)) {
            updates.append(format("[{}]\n", Gtk.Config().quote(stateTarget)))
            if (targetSettings) {
                updates.append(format("break_at_start = {}\narguments = {}\n", breakAtStart,
                    Gtk.Config().quote(argumentText)))
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
                    updates.append(format("{{ file = {}, line = {}, enabled = {} }},\n",
                        Gtk.Config().quote(point.path), point.line, enabled))
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
                if (!file.startsWith("s") || !line.startsWith("i") || line.length > 8 ||
                    !identifier(byteSpan(line, 1, line.length)) || byteSpan(line, 1, line.length).toInt64() < 1 ||
                    (!enabled.equals("btrue") && !enabled.equals("bfalse"))) {
                    stateDiagnostic(format("Invalid saved breakpoint {}; skipped", i + 1))
                } else {
                    file = byteSpan(file, 1, file.length)
                    line = byteSpan(line, 1, line.length)
                    if (!System.FileSystem().isFile(file)) {
                        stateDiagnostic(format("Stale breakpoint {}:{}; skipped", file, line))
                    } else {
                        String command = "-break-insert"
                        if (enabled.equals("bfalse")) { command.append(" -d") }
                        restorePending = restorePending + 1
                        enqueue(format("{} {}", command, MiParser().quote(format("{}:{}", file, line))),
                            "restore-break", format("{}:{}", file, line))
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
