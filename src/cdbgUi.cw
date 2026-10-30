DebugSource Cdbg.currentSource() {
        int64 page = sourceTabs.currentPage()
        if (page < 0 || page >= sourceFiles.length) { return(null) }
        DebugSource file = sourceFiles[page] as DebugSource
        if (file.path.equals("")) { return(null) }
        return(file)
    }

void Cdbg.sourceChanged() {
        int64 page = sourceTabs.currentPage()
        if (page >= 0 && page < sourceFiles.length) {
            source = (sourceFiles[page] as DebugSource).view
        }
        controls()
    }

// Primary click selects the source line (gutter and text). Toggle with F9
// or Breakpoint > Set/Clear so positioning clicks never clear breakpoints.
void Cdbg.sourceLineClicked(int64 line) {
        DebugSource file = currentSource()
        if (file != null && line > 0) { file.view.centerCursor(line, 1) }
        controls()
    }

void Cdbg.controls() {
        if (window == null || window.disposed()) { return }
        bool ready = loaded && !running && !executing && active == null && requests.length == 0
        bool canBreak = ready && currentSource() != null
        menu.setItemEnabled(toggleBreakItem, canBreak)
        menu.setItemEnabled(toggleEnableItem, canBreak)
        // Execution controls stay live while a stop refresh is pending; execute()
        // discards that refresh and reports presses it cannot accept.
        bool canExecute = loaded && !running && !restarting
        runButton.setSensitive(canExecute)
        stepButton.setSensitive(canExecute && hasRun)
        nextButton.setSensitive(canExecute && hasRun)
        finishButton.setSensitive(canExecute && hasRun)
        interruptButton.setSensitive(loaded && running)
        restartButton.setSensitive(loaded && active == null && requests.length == 0 && !restarting)
    }

String Cdbg.outputHistory(String previous, String text) {
        previous.append(text)
        if (previous.length <= 65536) { return(previous) }
        int64 first = previous.length - 65536
        while (first < previous.length && previous[first] >= 128u &&
            previous[first] <= 191u) { first = first + 1 }
        return(byteSpan(previous, first, previous.length))
    }

void Cdbg.log(String text) {
        console.setText(outputHistory(console.text(), text))
    }

void Cdbg.programLog(String text) {
        if (text.equals("")) { return }
        text = text.replace(Process.OutputDecoder().decode(buffer[0u]), "\\0")
        programOutput.setText(outputHistory(programOutput.text(), text))
    }

void Cdbg.readProgramOutput() {
        if (terminal == null) { return }
        programLog(terminal.read())
        if (!terminal.error().equals("")) {
            failWith("CDBG3003", format("Program output transport for {} failed: {}; reload the target to retry",
                targetPath, terminal.error()))
        }
    }

// Presses refused while an execution command is pending are expected user
// activity, so they are reported in the status line rather than as errors.
void Cdbg.ignored(String text) {
        status.setText(text)
        log(format("{}\n", text))
    }

void Cdbg.fail(String text) {
        failWith("CDBG1000", text)
    }

void Cdbg.failWith(String code, String text) {
        failure = text
        String message = DebugDiagnostic().emit("error", code, text)
        if (window != null && !window.disposed()) {
            status.setText(message)
            log(format("{}\n", message))
        }
    }

void Cdbg.loadFailure(String text) {
        fileFailure("CDBG1001", text)
    }

void Cdbg.fileFailure(String code, String text) {
        failWith(code, text)
        if (window != null && !window.disposed()) {
            Gtk.AlertDialog().show(window, "Could not load file",
                DebugDiagnostic().header("error", code, text))
        }
    }

int64 Cdbg.byteSpanBound(int64 value, int64 length) {
        int64 index = value
        if (index < 0) { index = index + length }
        if (index < 0) { return(0) }
        if (index > length) { return(length) }
        return(index)
    }

String Cdbg.byteSpan(String text, int64 first, int64 last) {
        int64 lower = byteSpanBound(first, text.length)
        int64 end = byteSpanBound(last, text.length)
        if (end <= lower) { return("") }
        return(text[lower..(end - 1)])
    }
