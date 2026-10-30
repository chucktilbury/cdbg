void Cdbg.resume() {
        if (!loaded || running || restarting) {
            fail("Run ignored: the target is not loaded and stopped")
            return
        }
        if (executing) { ignored("Run ignored: the previous execution command is still pending")
            return }
        skipRuntimeLeft = 0
        skipSameLineLeft = 0
        skippedSameLineStops = 0
        if (hasRun) { execute("-exec-continue", "Continue") }
        else {
            executing = true
            startRun()
            controls()
        }
    }

// Every fresh run resends the current arguments, so Session Preferences
// Apply takes effect on the next Run/Restart. "Break at start" is a temporary
// breakpoint on the entry symbol: for Cwhip programs `main` is the generated
// start block, so it stops on the `start {` line; native programs stop in main().
void Cdbg.startRun() {
        String args = "-exec-arguments"
        int64 i = 0
        while (i < arguments.length) {
            args.append(format(" {}", MiParser().quote(arguments[i] as String)))
            i = i + 1
        }
        enqueue(args, "arguments", "")
        runHits = []
        i = 0
        while (i < breakpointEntries.length) {
            MiValue entry = breakpointEntries[i] as MiValue
            runHits.append(format("{}={}", entry.field("number").text, entry.field("times").text))
            i = i + 1
        }
        startMissing = false
        if (breakAtStart && startBreakpoint.equals("")) {
            enqueue("-break-insert -t main", "start-break", "")
        }
        enqueue("-exec-run", "execute", "")
    }

void Cdbg.restart() {
        if (!loaded || active != null || requests.length > 0 || restarting || executing) {
            fail("Wait for GDB to be ready before restarting")
            return
        }
        if (targetPath.endsWith(".cw")) {
            restartWithRebuild()
            return
        }
        skipRuntimeLeft = 0
        restarting = true
        if (running) { enqueue("-exec-interrupt", "restart-interrupt", "") }
        else { restartStopped() }
        controls()
    }

// Recompile a .cw target, reopen GDB on the new image, then run again.
void Cdbg.restartWithRebuild() {
        list kept = []
        int64 i = 0
        while (i < expressions.length) {
            kept.append(expressions[i] as String)
            i = i + 1
        }
        String path = targetPath
        bool keepBreak = breakAtStart
        saveState(false)
        endSession()
        pendingWatchRestore = kept
        expressions = kept
        rebuildPendingRun = true
        rebuildBreakAtStart = keepBreak
        targetPath = path
        launch()
        controls()
    }

void Cdbg.restartStopped() {
        if (hasRun) {
            enqueue("-interpreter-exec console \"kill\"", "restart-kill", "")
        } else {
            restarting = false
            startRun()
        }
    }

// Browsing a caller selects that frame for inspection, not for execution.
// A press during the post-stop refresh is accepted: queued inspection and
// frame-browse requests are discarded, an in-flight one is answered as
// stale, and only one execution command may be outstanding.
void Cdbg.execute(String command, String label) {
        if (executing) {
            ignored(format("{} ignored: the previous execution command is still pending", label))
            return
        }
        bool restoreFrame = selectedFrame != 0
        list kept = []
        int64 i = 0
        while (i < requests.length) {
            DebugRequest request = requests[i] as DebugRequest
            if (request.purpose.equals("frame")) { restoreFrame = true }
            if (!inspection(request) && !request.purpose.equals("frame")) { kept.append(request) }
            i = i + 1
        }
        requests = kept
        if (active != null && (inspection(active) || active.purpose.equals("frame"))) {
            if (active.purpose.equals("frame")) { restoreFrame = true }
            active.purpose = "stale"
        }
        executing = true
        if (hasRun && restoreFrame) {
            enqueue("-stack-select-frame 0", "execution-frame", command)
        } else { enqueue(command, "execute", "") }
        controls()
    }

void Cdbg.stepInto() {
        if (stopped()) {
            skipSameLineLeft = 0
            skippedSameLineStops = 0
            skipRuntimeLeft = 32
            skippedRuntimeFrames = 0
            skipOrigin = stopPosition
            execute("-exec-step", "Step Into")
        }
    }

void Cdbg.stepOver() {
        skipRuntimeLeft = 0
        skipOrigin = ""
        skippedRuntimeFrames = 0
        skipSameLineLeft = 16
        skippedSameLineStops = 0
        if (stopped()) { execute("-exec-next", "Step Over") }
    }

void Cdbg.stepOut() {
        skipRuntimeLeft = 0
        skipOrigin = ""
        skipSameLineLeft = 0
        skippedSameLineStops = 0
        if (stopped()) { execute("-exec-finish", "Step Out") }
    }

bool Cdbg.cwhipFrame(String path) {
        return(path.endsWith(".cw"))
    }

bool Cdbg.openableSource(String path) {
        if (path.equals("") || path.equals("??")) { return(false) }
        String absolute = System.FileSystem().absolutePath(path)
        if (absolute.equals("")) { absolute = path }
        return(System.FileSystem().isFile(absolute))
    }

// Thin runtime guards injected around calls; keep finishing through these so
// Step Into on a Cwhip method still reaches the method body. Real runtime
// work such as cwhip_string_format_new is not a prologue and is presented.
bool Cdbg.runtimePrologue(String func) {
        if (func.startsWith("cwhip_gc_") || func.startsWith("cwhip_trace_") ||
            func.startsWith("cwhip_runtime_")) { return(true) }
        if (func.equals("cwhip.require_nonnull") || func.equals("find_containing_object") ||
            func.equals("find_object")) { return(true) }
        return(false)
    }

// After Step Into on a Cwhip app, finish out of frames with no source and
// out of thin GC/trace prologues, then step again when finish returns to
// the call site, until a different .cw stop or a runtime frame that has
// debug info and is real work (so Step Into on print opens RuntimeGc.c).
// Pure C sessions keep every stop.
bool Cdbg.skipRuntimeStop(String path, String func, String position, String reason) {
        if (skipRuntimeLeft <= 0 || !preferCwhipStops) { return(false) }
        if (reason.startsWith("exited") || reason.equals("breakpoint-hit") ||
            reason.equals("watchpoint-trigger") || reason.equals("read-watchpoint-trigger") ||
            reason.equals("access-watchpoint-trigger") || reason.equals("signal-received")) {
            skipRuntimeLeft = 0
            skipOrigin = ""
            return(false)
        }
        bool atOrigin = !skipOrigin.equals("") && position.equals(skipOrigin)
        if (cwhipFrame(path) && !atOrigin) {
            skipRuntimeLeft = 0
            skipOrigin = ""
            return(false)
        }
        if (cwhipFrame(path) && atOrigin) {
            // Finish bounced back to the call site; step in again.
            skipRuntimeLeft = skipRuntimeLeft - 1
            skippedRuntimeFrames = skippedRuntimeFrames + 1
            executing = true
            enqueue("-exec-step", "execute", "")
            controls()
            return(true)
        }
        // Non-.cw frame with openable source that is not a thin prologue: show it.
        if (openableSource(path) && !runtimePrologue(func)) {
            skipRuntimeLeft = 0
            skipOrigin = ""
            return(false)
        }
        skipRuntimeLeft = skipRuntimeLeft - 1
        skippedRuntimeFrames = skippedRuntimeFrames + 1
        executing = true
        enqueue("-exec-finish", "execute", "")
        controls()
        return(true)
    }

// Step Over can stop again on the same file:line at a later PC (for example
// after returning to a call site mid-line). Continue nexting until the
// source line changes so one toolbar press matches one statement.
bool Cdbg.skipSameLineStop(String position, String reason) {
        if (skipSameLineLeft <= 0) { return(false) }
        if (!reason.equals("end-stepping-range")) {
            skipSameLineLeft = 0
            return(false)
        }
        if (stopPosition.equals("") || !position.equals(stopPosition)) {
            skipSameLineLeft = 0
            return(false)
        }
        skipSameLineLeft = skipSameLineLeft - 1
        skippedSameLineStops = skippedSameLineStops + 1
        executing = true
        enqueue("-exec-next", "execute", "")
        controls()
        return(true)
    }

void Cdbg.interrupt() {
        if (!loaded || !running) { fail("No running target to pause")
            return }
        enqueue("-exec-interrupt", "interrupt", "")
    }
