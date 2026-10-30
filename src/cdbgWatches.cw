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

void Cdbg.showSetup() {
        setupStart.setActive(breakAtStart)
        setupArguments.setText(ArgumentList().display(arguments))
        if (stateTarget.equals("")) {
            setupStatus.setText("No target loaded: Break at start becomes this directory's default")
        } else { setupStatus.setText(format("Settings for {}", stateTarget)) }
        setupWindow.setVisible(true)
        setupWindow.present()
        setupArguments.focus()
    }
void Cdbg.closeSetup() { setupWindow.setVisible(false) }
bool Cdbg.setupCloseRequested() { closeSetup()
        return(true) }

// Apply never restarts a running program: arguments and Break at start
// take effect on the next Run (from not started), Restart or Load.
void Cdbg.applySetup() {
        ArgumentList parsed = ArgumentList()
        if (!parsed.parse(setupArguments.text())) {
            String message = format("Invalid arguments: {}; previous arguments kept", parsed.error)
            setupStatus.setText(message)
            status.setText(message)
            return
        }
        if (stateTarget.equals("") && parsed.values.length > 0) {
            setupStatus.setText("Load a target before setting program arguments")
            return
        }
        breakAtStart = setupStart.active()
        arguments = parsed.values
        argumentText = parsed.display(parsed.values)
        String message = "Setup applied; takes effect on the next Run, Restart or Load"
        if (running) {
            message = "Setup applied; the running program is unchanged; takes effect on the next Run, Restart or Load"
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
