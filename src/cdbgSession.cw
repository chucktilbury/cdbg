// The source notebook always keeps at least one page: a message page
// (path "") stands in when no file tab is open, so the area never hides.
void Cdbg.clearSources() {
        sourceMessage("Loading source...")
        list kept = []
        int64 i = 0
        while (i < sourceFiles.length) {
            DebugSource file = sourceFiles[i] as DebugSource
            if (file.path.equals("")) { kept.append(file) }
            else {
                sourceTabs.remove(file.scroll)
                file.scroll.dispose()
            }
            i = i + 1
        }
        sourceFiles = kept
        sourceTabs.setCurrentPage(0)
        source = (sourceFiles[0] as DebugSource).view
    }

void Cdbg.sourceMessage(String text) {
        int64 i = 0
        while (i < sourceFiles.length) {
            DebugSource document = sourceFiles[i] as DebugSource
            if (document.path.equals("")) {
                source = document.view
                source.setText(text)
                sourceTabs.setCurrentPage(i)
                return
            }
            i = i + 1
        }
        source = pane()
        source.setText(text)
        Gtk.ScrolledWindow container = scroll(source)
        sourceTabs.appendPage(container, "No source")
        sourceFiles.append(DebugSource("", source, container))
        sourceTabs.setCurrentPage(sourceFiles.length - 1)
    }

void Cdbg.removeSourcePage(DebugSource file) {
        list remaining = []
        int64 i = 0
        while (i < sourceFiles.length) {
            DebugSource item = sourceFiles[i] as DebugSource
            if (item != file) { remaining.append(item) }
            i = i + 1
        }
        sourceTabs.remove(file.scroll)
        file.scroll.dispose()
        sourceFiles = remaining
        sourceChanged()
    }

void Cdbg.removeMessagePage() {
        if (sourceFiles.length < 2) { return }
        int64 i = 0
        while (i < sourceFiles.length) {
            DebugSource file = sourceFiles[i] as DebugSource
            if (file.path.equals("")) {
                removeSourcePage(file)
                return
            }
            i = i + 1
        }
    }

// Closing a file tab never touches the debug session; a later stop in the
// file reopens it.
void Cdbg.closeSource(DebugSource file) {
        bool open = false
        int64 i = 0
        while (i < sourceFiles.length) {
            if ((sourceFiles[i] as DebugSource) == file) { open = true }
            i = i + 1
        }
        if (!open) { return }
        if (sourceFiles.length == 1) {
            sourceMessage("No source open. Use File > Open Source Code...")
        }
        removeSourcePage(file)
        source = (sourceFiles[sourceTabs.currentPage()] as DebugSource).view
        status.setText(format("Closed {}", System.FileSystem().basename(file.path)))
    }

String Cdbg.compiler() {
        String explicit = System.Process().getEnv("CDBG_COMPILER")
        if (!explicit.equals("")) { return(explicit) }
        String own = System.Process().arg(0)
        if (!own.contains("/")) {
            list paths = System.Process().getEnv("PATH").split(":")
            int64 i = 0
            while (i < paths.length) {
                String candidate = System.FileSystem().join(paths[i] as String, own)
                if (System.FileSystem().isFile(candidate)) { own = candidate
                    break }
                i = i + 1
            }
        }
        String sibling = System.FileSystem().join(System.FileSystem().dirname(
            System.FileSystem().absolutePath(own)), "cwhip")
        if (System.FileSystem().isFile(sibling)) { return(sibling) }
        return("cwhip")
    }

void Cdbg.cleanup() {
        if (!temporary.equals("")) {
            if (System.FileSystem().exists(executable) && !System.FileSystem().remove(executable)) {
                failWith("CDBG9001", format("Could not remove temporary executable {}; remove it manually", executable))
            }
            if (!System.FileSystem().rmdir(temporary)) {
                failWith("CDBG9001", format("Could not remove temporary build directory {}; remove it manually", temporary))
            }
            temporary = ""
        }
    }

void Cdbg.endSession() {
        if (pollToken > 0) { Gtk.Application().cancel(pollToken)
            pollToken = 0 }
        if (process != null) {
            if (mode == 2 && process.started() && !process.finished()) {
                if (process.write("-gdb-exit\n")) { process.wait(100) }
            }
            process.close()
            process = null }
        if (terminal != null) {
            readProgramOutput()
            terminal.close()
            programLog(terminal.read())
            terminal = null
        }
        requests = []
        active = null
        pending = ""
        loaded = false
        running = false
        hasRun = false
        restarting = false
        executing = false
        skipRuntimeLeft = 0
        skippedRuntimeFrames = 0
        skipOrigin = ""
        skipSameLineLeft = 0
        skippedSameLineStops = 0
        preferCwhipStops = false
        valueInspector = false
        selectedFrame = 0
        stopDetail = ""
        stopPosition = ""
        stopAddress = ""
        stackFrames = []
        breakpointRows = []
        breakpointEntries = []
        breakpointLocations = []
        syncBreakpointMarks()
        if (window != null && !window.disposed() && breaks != null) { breaks.setText("") }
        mode = 0
        cleanup()
        controls()
        if (window != null && !window.disposed() && failure.equals("")) {
            status.setText("Session ended")
        }
    }

bool Cdbg.closeRequested() {
        saveState(true)
        closed = true
        if (fileDialog != null) {
            fileDialog.cancel()
            fileDialog = null
        }
        if (findWindow != null && !findWindow.disposed()) { findWindow.dispose() }
        if (watchWindow != null && !watchWindow.disposed()) { watchWindow.dispose() }
        endSession()
        return(false)
    }

void Cdbg.launch() {
        saveState(false)
        endSession()
        stateTarget = System.FileSystem().absolutePath(targetPath)
        failure = ""
        if (!rebuildPendingRun) { stopCount = 0 }
        inferiorPid = ""
        location = ""
        executable = System.FileSystem().absolutePath(targetPath)
        if (executable.equals("")) { executable = targetPath }
        if (!System.FileSystem().isFile(executable)) { loadFailure(format("Target is not a local file: {}", executable))
            return }
        output = Process.OutputDecoder()
        errors = Process.OutputDecoder()
        pending = ""
        // Rebuild-on-Restart keeps the Debugger Console so start-breakpoint
        // and other session notes accumulate across recompiles.
        if (!rebuildPendingRun) { console.setText("") }
        if (!stateWritable) { log("State file is invalid/unreadable; defaults in use, saving disabled\n") }
        if (!stateNote.equals("")) { log(stateNote) }
        if (!stateError.equals("")) { log(format("Settings not saved to {}: {}\n", statePath, stateError)) }
        loadTargetSettings()
        if (rebuildPendingRun) { breakAtStart = rebuildBreakAtStart }
        if (!rebuildPendingRun) { programOutput.setText("") }
        locals.setText("")
        stack.setText("")
        watches.setText("")
        breaks.setText("")
        if (executable.endsWith(".cw")) {
            String input = executable
            if (!readableText(input)) { return }
            temporary = System.FileSystem().tempDir()
            if (temporary.equals("")) { failWith("CDBG3001",
                format("Could not create a temporary build directory for {}; check temporary-directory permissions and free space", input))
                return }
            executable = System.FileSystem().join(temporary, "target")
            compilerOutput = ""
            status.setText("Compiling with Cwhip -g...")
            process = Process.AsyncProcess(compiler(), [input, "-g", "-o", executable],
                System.FileSystem().dirname(input))
            mode = 1
        } else { startDebugger() }
        if (process == null || !process.started()) {
            if (mode == 1 && process != null) { failWith("CDBG3001",
                format("Could not start compiler {} for {}: {}; check CDBG_COMPILER or PATH",
                    compiler(), targetPath, process.error())) }
            if (process != null) { process.close()
                process = null }
            cleanup()
            if (terminal != null) { terminal.close()
                terminal = null }
            mode = 0
            controls()
            return
        }
        pollToken = Gtk.Application().post(_self().poll)
    }

void Cdbg.startDebugger() {
        terminal = DebugTerminal()
        if (!terminal.error().equals("")) {
            failWith("CDBG3003", format("Could not allocate program output terminal for {}: {}; check PTY availability",
                targetPath, terminal.error()))
            terminal.close()
            terminal = null
            cleanup()
            return
        }
        String gdb = System.Process().getEnv("CDBG_GDB")
        if (gdb.equals("")) { gdb = "gdb" }
        list argv = ["--nx", "--quiet", "--interpreter=mi2",
            "-iex", "set auto-load off"]
        process = Process.AsyncProcess(gdb, argv, System.FileSystem().getCwd(), true)
        mode = 2
        output = Process.OutputDecoder()
        errors = Process.OutputDecoder()
        pending = ""
        if (!process.started()) { failWith("CDBG3002",
            format("Could not start GDB {} for {}: {}; check CDBG_GDB or PATH",
                gdb, targetPath, process.error()))
            return }
        status.setText("Starting GDB...")
        enqueue("-gdb-set pagination off", "setup", "")
        enqueue("-gdb-set mi-async on", "setup", "")
        enqueue("-gdb-set confirm off", "setup", "")
        enqueue("-gdb-set host-charset UTF-8", "setup", "")
        enqueue("-gdb-set may-call-functions off", "setup", "")
        enqueue("-gdb-set print elements 8", "setup", "")
        enqueue("-gdb-set print max-depth 2", "setup", "")
        String script = format("python exec({})", MiParser().quote(terminal.valuesScript()))
        enqueue(format("-interpreter-exec console {}", MiParser().quote(script)), "value-setup", "")
        enqueue(format("-inferior-tty-set {}", MiParser().quote(terminal.path())), "setup", "")
        enqueue(format("-file-exec-and-symbols {}", MiParser().quote(executable)), "target", "")
        String args = "-exec-arguments"
        int64 i = 0
        while (i < arguments.length) {
            args.append(format(" {}", MiParser().quote(arguments[i] as String)))
            i = i + 1
        }
        enqueue(args, "loaded", "")
        enqueue("-file-list-exec-source-files", "sources", "")
    }

void Cdbg.enqueue(String command, String purpose, String expression) {
        if (requests.length >= 256) { failWith("CDBG3004", "GDB request queue is full; wait for pending commands before retrying")
            return }
        sequence = sequence + 1
        requests.append(DebugRequest(format("{}", sequence), command, purpose, expression))
        sendNext()
    }

void Cdbg.sendNext() {
        if (active != null || requests.length == 0 || process == null) { return }
        active = requests[0] as DebugRequest
        requests = requests[1:]
        if (!process.write(format("{}{}\n", active.token, active.command))) {
            failWith("CDBG3003", format("GDB command write for {} failed: {}; reload the target to retry",
                targetPath, process.inputError()))
            active = null
            requests = []
            loaded = false
        }
        controls()
    }

String Cdbg.processOutcome() {
        String reason = format("process state {}", process.state())
        if (process.state() == Process.AsyncProcess.EXITED) {
            reason = format("exit {}", process.exitCode())
        }
        if (!process.error().equals("")) { reason.append(format(": {}", process.error())) }
        return(reason)
    }

bool Cdbg.stopped() {
        if (!loaded || running || !hasRun) { fail("This operation requires a stopped target")
            return(false) }
        return(true)
    }
