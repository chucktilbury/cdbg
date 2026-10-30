void Cdbg.showWatch() {
        watchMenu.setVisible(false)
        watchEntry.setText("")
        watchStatus.setText("")
        watchWindow.setVisible(true)
        watchWindow.present()
        watchEntry.focus()
    }
void Cdbg.closeWatch() { watchWindow.setVisible(false) }
bool Cdbg.watchCloseRequested() { closeWatch()
        return(true) }

// Apply never restarts a running program: arguments, cwd, env and Break at
// start take effect on the next Run (from not started), Restart or Load.
void Cdbg.applySetup() {
        ArgumentList parsed = ArgumentList()
        if (!parsed.parse(setupArguments.text())) {
            String message = format("Invalid arguments: {}; previous arguments kept", parsed.error)
            setupStatus.setText(message)
            status.setText(message)
            return
        }
        EnvironmentList env = EnvironmentList()
        if (!env.parse(setupEnv.text())) {
            String message = format("Invalid environment: {}; previous environment kept", env.error)
            setupStatus.setText(message)
            status.setText(message)
            return
        }
        String cwd = setupCwd.text().trim()
        if (!cwd.equals("")) {
            String absolute = System.FileSystem().absolutePath(cwd)
            if (absolute.equals("")) { absolute = cwd }
            if (!System.FileSystem().isDir(absolute)) {
                String message = format("Working directory must be an existing directory: {}", cwd)
                setupStatus.setText(message)
                status.setText(message)
                return
            }
            cwd = absolute
        }
        if (stateTarget.equals("") && (parsed.values.length > 0 || env.pairs.length > 0 ||
            !cwd.equals(""))) {
            setupStatus.setText("Load a target before setting program arguments, cwd or environment")
            return
        }
        breakAtStart = setupStart.active()
        arguments = parsed.values
        argumentText = parsed.display(parsed.values)
        sessionCwd = cwd
        environmentPairs = env.pairs
        environmentText = env.display(env.pairs)
        setupCwd.setText(sessionCwd)
        setupEnv.setText(environmentText)
        String message = "Session applied; takes effect on the next Run, Restart or Load"
        if (running) {
            message = "Session applied; the running program is unchanged; takes effect on the next Run, Restart or Load"
        }
        if (stateTarget.equals("")) { defaultChanged = true }
        else { targetSettings = true }
        if (!breakAtStart && !startBreakpoint.equals("") && loaded && !running) {
            enqueue(format("-break-delete {}", startBreakpoint), "break", "")
            startBreakpoint = ""
        }
        saveState(false)
        if (!stateError.equals("")) { message.append(format("; settings NOT saved: {}", stateError)) }
        else { message.append(format("; saved to {}", statePath)) }
        status.setText(message)
        log(format("{}\n", message))
        closeSetup()
    }

// Clearing only discards displayed history; the program keeps running and
// later output is appended as usual.
void Cdbg.clearOutput() {
        outputMenu.setVisible(false)
        programOutput.setText("")
        status.setText("Program Output cleared")
    }

void Cdbg.copyOutput() {
        outputMenu.setVisible(false)
        if (!programOutput.hasSelection()) {
            status.setText("Select Program Output text to copy")
            return
        }
        programOutput.copy()
        status.setText("Copied Program Output selection")
    }

void Cdbg.copyAllOutput() {
        outputMenu.setVisible(false)
        programOutput.selectAll()
        programOutput.copy()
        programOutput.setCursor(1, 1)
        status.setText("Copied all Program Output")
    }

void Cdbg.acceptWatch() {
        if (addWatch(watchEntry.text())) { closeWatch() }
    }

bool Cdbg.addWatch(String expression) {
        expression = expression.trim()
        if (expression.equals("") || expression.length > 4096 || expressions.length >= 64) {
            watchStatus.setText("Enter a watch expression (maximum 4096 bytes, 64 watches)")
            fail("Enter a watch expression (maximum 4096 bytes, 64 watches)")
            return(false) }
        int64 i = 0
        while (i < expressions.length) {
            if ((expressions[i] as String).equals(expression)) { return(true) }
            i = i + 1
        }
        expressions.append(expression)
        saveState(false)
        if (loaded && !running && hasRun) { refresh() }
        else { watches.setText("Watches will be evaluated at the next stop") }
        return(true)
    }

void Cdbg.stackClicked(int64 line) {
        int64 row = line - 1
        if (row < 0 || row >= stackFrames.length) { return }
        MiValue frame = stackFrames[row] as MiValue
        selectFrame(frame.field("level").text)
    }

void Cdbg.selectFrame(String number) {
        if (!stopped()) { return }
        if (executing) { fail("Frame selection ignored: an execution command is pending")
            return }
        if (!identifier(number)) { fail("Select a stack frame")
            return }
        enqueue(format("-stack-select-frame {}", number), "frame", number)
    }

void Cdbg.threadClicked(int64 line) {
        int64 row = line - 1
        if (row < 0 || row >= threadIds.length) { return }
        selectThread(threadIds[row] as String)
    }

void Cdbg.selectThread(String number) {
        if (!stopped()) { return }
        if (executing) { fail("Thread selection ignored: an execution command is pending")
            return }
        if (!identifier(number)) { fail("Select a thread")
            return }
        enqueue(format("-thread-select {}", number), "thread", number)
    }
