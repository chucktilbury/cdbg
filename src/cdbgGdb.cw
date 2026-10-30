void Cdbg.response(MiParser record) {
        if (active == null || !record.token.equals(active.token)) {
            failWith("CDBG3004", format("Unexpected GDB response token for {}; reload the target to retry", targetPath))
            endSession()
            return
        }
        DebugRequest done = active
        active = null
        if (done.purpose.equals("stale")) {
            sendNext()
            controls()
            return
        }
        if (record.result.equals("error")) {
            if (done.purpose.equals("value-setup")) {
                log(format("Cwhip value inspector unavailable: {}. Python-enabled GDB with gdb.MICommand is required; native locals only.\n",
                    record.data.field("msg").text))
                valueInspector = false
                sendNext()
                controls()
                return
            }
            if (done.purpose.equals("start-break")) {
                startMissing = true
                log(format("Break at start unavailable: {}; running without a start breakpoint\n",
                    record.data.field("msg").text))
                sendNext()
                controls()
                return
            }
            if (done.purpose.equals("restore-break")) {
                stateDiagnostic(format("Could not restore {}: {}; skipped", done.expression,
                    record.data.field("msg").text))
                restorePending = restorePending - 1
                if (restorePending == 0) {
                    restoringBreakpoints = false
                    maybeRebuildRun()
                }
                sendNext()
                controls()
                return
            }
            if (done.purpose.startsWith("restart-")) { restarting = false }
            if (done.purpose.equals("execute") || done.purpose.equals("execution-frame")) { executing = false }
            String message = record.data.field("msg").text
            if (done.purpose.equals("watch")) {
                watches.setText(format("{}{} = <{}>\n", watches.text(), done.expression, message))
                runtimeWatches.append(format("{} = <{}>\n", done.expression, message))
                updateRuntimeValues()
            } else {
                if (done.purpose.equals("locals")) {
                    locals.setText(format("<{}>", message))
                    runtimeLocals = format("<{}>", message)
                    updateRuntimeValues()
                }
                message = format("GDB {} for {} failed: {}; see Debugger Console",
                    done.command, targetPath, message)
                if (done.purpose.equals("target")) { fileFailure("CDBG3002", message) }
                else { failWith("CDBG3002", message) }
                if (done.purpose.equals("setup") || done.purpose.equals("target") ||
                    done.purpose.equals("loaded")) {
                    requests = []
                    loaded = false
                    endSession()
                }
            }
            sendNext()
            controls()
            return
        }
        if (done.purpose.equals("value-setup")) { valueInspector = true }
        if (done.purpose.equals("target")) { clearSources() }
        if (done.purpose.equals("execution-frame")) {
            selectedFrame = 0
            enqueue(done.expression, "execute", "")
        }
        if (done.purpose.equals("break")) { requestBreakpoints() }
        if (done.purpose.equals("loaded")) {
            loaded = true
            status.setText("Loaded. Add breakpoints, then Run.")
            restoreWatches()
            restoreBreakpoints()
            maybeRebuildRun()
        }
        if (done.purpose.equals("restore-break")) {
            MiValue point = record.data.field("bkpt")
            String number = point.field("number").text
            list parts = done.expression.split("\n")
            String condText = ""
            String hitsText = "0"
            if (parts.length > 1) { condText = parts[1] as String }
            if (parts.length > 2) { hitsText = parts[2] as String }
            if (!condText.equals("") && !number.equals("")) {
                enqueue(format("-break-condition {} {}", number, MiParser().quote(condText)), "break", "")
            }
            if (identifier(hitsText) && hitsText.toInt64() > 0 && !number.equals("")) {
                enqueue(format("-break-after {} {}", number, hitsText), "break", "")
            }
            restorePending = restorePending - 1
            if (restorePending == 0) {
                restoringBreakpoints = false
                maybeRebuildRun()
            }
        }
        if (done.purpose.equals("sources")) {
            MiValue files = record.data.field("files")
            bool cwhipSources = false
            int64 i = 0
            while (i < files.values.length) {
                MiValue file = files.values[i] as MiValue
                if (file.field("file").text.endsWith(".cw")) { cwhipSources = true }
                i = i + 1
            }
            preferCwhipStops = cwhipSources
            i = 0
            while (i < files.values.length) {
                MiValue file = files.values[i] as MiValue
                String path = file.field("fullname").text
                if (path.equals("")) { path = file.field("file").text }
                if (!path.equals("") && !path.startsWith("/usr/") &&
                    !path.contains("/modules/") && !path.contains("/builtin/") &&
                    (!cwhipSources || path.endsWith(".cw"))) {
                    if (!showSource(path, "")) { break }
                }
                i = i + 1
            }
            if (sourceFiles.length > 0 && !(sourceFiles[0] as DebugSource).path.equals("")) {
                sourceTabs.setCurrentPage(0)
                source = (sourceFiles[0] as DebugSource).view
            } else { sourceMessage("Source unavailable: no readable source files in debug information") }
        }
        if (done.purpose.equals("restart-kill")) {
            hasRun = false
            running = false
            restarting = false
            startRun()
        }
        if (done.purpose.equals("start-break")) {
            MiValue point = record.data.field("bkpt")
            startBreakpoint = point.field("number").text
            startNumber = startBreakpoint
            log(format("Break at start: temporary breakpoint at {}:{} ({})\n", point.field("file").text,
                point.field("line").text, point.field("func").text))
        }
        if (record.result.equals("running")) {
            hasRun = true
            running = true
            locals.setText("Target running")
            watches.setText("Target running")
            runtimeValues.setText("Target running")
            if (startMissing) { status.setText("Running; Break at start unavailable (no entry symbol)") }
            else { status.setText("Running") }
        }
        if (done.purpose.equals("locals")) {
            MiValue variables = record.data.field("variables")
            String text = ""
            runtimeLocals = ""
            int64 i = 0
            while (i < variables.values.length) {
                MiValue variable = variables.values[i] as MiValue
                String value = variable.field("friendly").text
                if (!valueInspector) { value = variable.field("value").text }
                text.append(format("{} = {}\n", variable.field("name").text, value))
                String raw = variable.field("raw").text
                if (!valueInspector) { raw = variable.field("value").text }
                runtimeLocals.append(format("{} : {} = {}\n", variable.field("name").text,
                    variable.field("type").text, raw))
                i = i + 1
            }
            if (text.equals("")) { text = "(No variables in this frame)" }
            if (record.data.field("truncated").text.equals("true")) {
                text.append("\n<Locals truncated at 64>")
                runtimeLocals.append("\n<Locals truncated at 64>")
            }
            locals.setText(text)
            updateRuntimeValues()
        }
        if (done.purpose.equals("stack")) {
            MiValue frames = record.data.field("stack")
            stackFrames = frames.values
            String text = ""
            int64 i = 0
            while (i < frames.values.length) {
                MiValue frame = frames.values[i] as MiValue
                text.append(format("#{} {} {}:{}\n", frame.field("level").text, frame.field("func").text,
                    frame.field("file").text, frame.field("line").text))
                i = i + 1
            }
            if (!stack.text().equals(text)) { stack.setText(text) }
        }
        if (done.purpose.equals("watch")) {
            watches.setText(format("{}{} = {}\n", watches.text(), done.expression, record.data.field("friendly").text))
            runtimeWatches.append(format("{} : {} = {}\n", done.expression,
                record.data.field("type").text, record.data.field("raw").text))
            updateRuntimeValues()
        }
        if (done.purpose.equals("location")) {
            showLocation(record.data.field("frame"))
        }
        if (done.purpose.equals("frame")) {
            selectedFrame = done.expression.toInt64()
            refresh()
        }
        if (done.purpose.equals("breaks")) {
            MiValue rows = record.data.field("BreakpointTable").field("body")
            breakpointEntries = rows.values
            breakpointRows = []
            breakpointLocations = []
            String text = ""
            bool startSeen = false
            int64 i = 0
            while (i < rows.values.length) {
                MiValue item = rows.values[i] as MiValue
                String number = item.field("number").text
                breakpointRows.append((number.split(".")[0] as String))
                bool enabled = !item.field("enabled").text.equals("n")
                if (number.contains(".")) {
                    String parent = number.split(".")[0] as String
                    int64 j = 0
                    while (j < rows.values.length) {
                        MiValue root = rows.values[j] as MiValue
                        if (root.field("number").text.equals(parent) && root.field("enabled").text.equals("n")) {
                            enabled = false
                        }
                        j = j + 1
                    }
                }
                String parentNumber = number.split(".")[0] as String
                if (parentNumber.equals(startBreakpoint)) { startSeen = true }
                if (item.field("disp").text.equals("del")) {
                    text.append(format("#{} start (temporary) {}:{} in {}\n", number, item.field("file").text,
                        item.field("line").text, item.field("func").text))
                } else {
                    breakpointLocation(item, "", enabled)
                    text.append(format("#{} {}\n", number, breakpointSummary(item, enabled)))
                }
                i = i + 1
            }
            if (!startSeen) { startBreakpoint = "" }
            breaks.setText(text)
            syncBreakpointMarks()
            if (!restoringBreakpoints) { saveState(false) }
        }
        sendNext()
        controls()
    }

void Cdbg.record(String line) {
        if (line.endsWith("\r")) { line = byteSpan(line, 0, line.length - 1) }
        if (line.equals("") || line.trim().equals("(gdb)")) { return }
        MiParser parsed = MiParser()
        parsed.parse(line)
        if (!parsed.valid) {
            // Inferior stdout can arrive unframed on GDB's own output pipe.
            if (line.startsWith("^") || line.startsWith("*stopped") ||
                (active != null && line.startsWith(format("{}^", active.token)))) {
                failWith("CDBG3004", format("Malformed GDB record for {}: {}", targetPath, line))
                endSession()
            } else { log(format("{}\n", line)) }
            return
        }
        if (parsed.kind.equals("^")) { response(parsed) }
        if (parsed.kind.equals("~") || parsed.kind.equals("&")) {
            log(parsed.data.text)
        }
        if (parsed.kind.equals("@")) { programLog(parsed.data.text) }
        if (parsed.kind.equals("=") && parsed.result.equals("thread-group-started")) {
            inferiorPid = parsed.data.field("pid").text
        }
        if (parsed.kind.equals("=") && loaded &&
            (parsed.result.equals("breakpoint-created") || parsed.result.equals("breakpoint-modified") ||
             parsed.result.equals("breakpoint-deleted"))) { requestBreakpoints() }
        if (parsed.kind.equals("*") && parsed.result.equals("stopped")) {
            running = false
            executing = false
            String reason = parsed.data.field("reason").text
            if (restarting) {
                skipRuntimeLeft = 0
                if (reason.startsWith("exited")) { hasRun = false }
                restartStopped()
                controls()
                return
            }
            if (reason.startsWith("exited")) {
                skipRuntimeLeft = 0
                readProgramOutput()
                hasRun = false
                locals.setText("Target exited")
                watches.setText("Target exited")
                runtimeValues.setText("Target exited")
                String exitText = format("Target {}", reason)
                if (!parsed.data.field("exit-code").text.equals("")) {
                    exitText.append(format(" {}", parsed.data.field("exit-code").text))
                }
                int64 missed = reportUnreached()
                if (missed > 0) { exitText.append(format("; {} breakpoint(s) not reached", missed)) }
                startBreakpoint = ""
                startNumber = ""
                status.setText(exitText)
            } else {
                MiValue frame = parsed.data.field("frame")
                String stopPath = frame.field("fullname").text
                if (stopPath.equals("")) { stopPath = frame.field("file").text }
                String stopFunc = frame.field("func").text
                String position = format("{}:{} ({})", stopPath,
                    frame.field("line").text, stopFunc)
                if (skipRuntimeStop(stopPath, stopFunc, position, reason)) { return }
                if (skipSameLineStop(position, reason)) { return }
                hasRun = true
                selectedFrame = 0
                stopCount = stopCount + 1
                String address = frame.field("addr").text
                stopDetail = format("{}; PC {}", reason, address)
                if (position.equals(stopPosition)) {
                    stopDetail.append(format("; same source line (previous PC {})", stopAddress))
                }
                if (skippedRuntimeFrames > 0) {
                    stopDetail.append(format("; skipped {} runtime frame(s)", skippedRuntimeFrames))
                    skippedRuntimeFrames = 0
                }
                if (skippedSameLineStops > 0) {
                    stopDetail.append(format("; advanced over {} same-line stop(s)", skippedSameLineStops))
                    skippedSameLineStops = 0
                }
                skipSameLineLeft = 0
                stopPosition = position
                stopAddress = address
                String hit = parsed.data.field("bkptno").text
                // GDB may delete the temporary breakpoint before *stopped.
                atStart = !hit.equals("") && hit.equals(startNumber)
                if (atStart) {
                    startBreakpoint = ""
                    startNumber = ""
                }
                showLocation(parsed.data.field("frame"))
                refresh()
            }
            controls()
        }
        if (parsed.kind.equals("*") && parsed.result.equals("running")) {
            running = true
            executing = false
            controls()
        }
    }

void Cdbg.consume(String chunk) {
        pending.append(chunk)
        if (pending.length > 1048576) {
            failWith("CDBG3004", format("GDB record for {} exceeded the 1 MiB prototype limit", targetPath))
            endSession()
            return
        }
        int64 newline = pending.find("\n")
        while (newline >= 0) {
            String line = byteSpan(pending, 0, newline)
            pending = byteSpan(pending, newline + 1, pending.length)
            record(line)
            newline = pending.find("\n")
        }
    }

void Cdbg.poll() {
        pollToken = 0
        if (closed || process == null) { return }
        readProgramOutput()
        if (terminal != null && !terminal.error().equals("")) {
            endSession()
            return
        }
        if (mode == 2 && !process.inputError().equals("")) {
            failWith("CDBG3003", format("GDB stdin for {} failed: {}; reload the target to retry",
                targetPath, process.inputError()))
            endSession()
            return
        }
        Process.ProcessEvent event = process.next(10)
        int64 count = 0
        while (event != null && count < 64) {
            if (event.isStdout()) {
                String text = output.decode(event.data())
                if (mode == 1) { compilerOutput.append(text) }
                else { consume(text) }
                if (process == null) { return }
            }
            if (event.isStderr()) {
                String text = errors.decode(event.data())
                if (mode == 1) { compilerOutput.append(text) }
                else { log(text) }
            }
            if (event.isCompleted()) {
                if (mode == 1) {
                    compilerOutput.append(output.finish())
                    compilerOutput.append(errors.finish())
                    bool success = process.state() == Process.AsyncProcess.EXITED && process.exitCode() == 0
                    String reason = processOutcome()
                    process.close()
                    process = null
                    log(compilerOutput)
                    if (!success) { fileFailure("CDBG3001",
                        format("Cwhip -g compilation of {} failed ({}); see Debugger Console for compiler details",
                            targetPath, reason))
                        cleanup()
                        mode = 0
                        controls()
                        return }
                    startDebugger()
                    if (process == null || !process.started()) {
                        if (process != null) { process.close()
                            process = null }
                        if (terminal != null) { terminal.close()
                            terminal = null }
                        cleanup()
                        mode = 0
                        controls()
                        return }
                } else {
                    consume(output.finish())
                    if (process == null) { return }
                    log(errors.finish())
                    String error = processOutcome()
                    process.close()
                    process = null
                    loaded = false
                    running = false
                    requests = []
                    active = null
                    controls()
                    failWith("CDBG3002", format("GDB session for {} ended unexpectedly ({}); reload the target to retry",
                        targetPath, error))
                    endSession()
                    return
                }
            }
            count = count + 1
            if (process != null && count < 64) { event = process.next(0) }
            else { event = null }
        }
        if (process != null && !closed) { pollToken = Gtk.Application().post(_self().poll) }
    }
