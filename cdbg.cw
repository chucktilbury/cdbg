import gtk
import sourceview
import system
include "mi.cw"
include "terminal.cw"

class DebugRequest {
    String token
    String command
    String purpose
    String expression
    DebugRequest(String number, String text, String kind, String watch) {
        token = number
        command = text
        purpose = kind
        expression = watch
    }
}

class DebugSource {
    DebugSource _self()
    String path
    GtkSource.View view
    Gtk.ScrolledWindow scroll
    int centeredStop
    callback<void(DebugSource)> closeAction
    DebugSource(String filename, GtkSource.View text, Gtk.ScrolledWindow container) {
        path = filename
        view = text
        scroll = container
    }
    void close() { closeAction(_self()) }
}
DebugSource DebugSource._self() from "cwhip_gtk_self"

class Cdbg {
    Cdbg _self()
    Gtk.Window window
    Gtk.MenuBar menu
    int loadItem
    int openItem
    int quitItem
    int findItem
    Gtk.FileDialog fileDialog
    Gtk.TransientWindow findWindow
    Gtk.Entry findEntry
    Gtk.Label findStatus
    String targetPath
    String sourceText
    Gtk.Entry breakpoint
    Gtk.Entry breakpointNumber
    Gtk.Entry watch
    Gtk.Entry frameNumber
    Gtk.Label status
    GtkSource.View source
    Gtk.Notebook sourceTabs
    list sourceFiles
    GtkSource.View locals
    GtkSource.View stack
    GtkSource.View watches
    GtkSource.View breaks
    GtkSource.View console
    GtkSource.View programOutput
    Gtk.Button runButton
    Gtk.Button stepButton
    Gtk.Button nextButton
    Gtk.Button finishButton
    Gtk.Button interruptButton
    Gtk.Button restartButton
    Process.AsyncProcess process
    DebugTerminal terminal
    Process.OutputDecoder output
    Process.OutputDecoder errors
    list requests
    list expressions
    list arguments
    DebugRequest active
    int sequence
    int mode
    int pollToken
    bool closed
    bool loaded
    bool running
    bool hasRun
    bool restarting
    String pending
    String executable
    String temporary
    String compilerOutput
    String location
    String failure
    String inferiorPid
    int stopCount

    Cdbg() {
        requests = []
        expressions = []
        arguments = []
        pending = ""
        temporary = ""
        failure = ""
        inferiorPid = ""
        location = ""
        targetPath = ""
        sourceText = ""
        sourceFiles = []
    }
    Gtk.Button button(Gtk.Box row, String title, callback<void()> action) {
        Gtk.Button item = Gtk.Button(title)
        item.onClicked(action)
        row.append(item)
        return item
    }
    GtkSource.View pane() {
        GtkSource.View view = GtkSource.View()
        view.configure("monospace", 11, 4, true, true, false, true)
        view.setEmojiMenu(false)
        view.setEditable(false)
        view.widget().setHExpand(true)
        view.widget().setVExpand(true)
        return view
    }
    Gtk.ScrolledWindow scroll(GtkSource.View view) {
        Gtk.ScrolledWindow item = Gtk.ScrolledWindow()
        item.setChild(view.widget())
        item.setHExpand(true)
        item.setVExpand(true)
        return item
    }
    void activate() {
        if (window != null && !window.disposed()) { window.present()
            return }
        window = Gtk.Window("cdbg - local GDB prototype")
        window.setDefaultSize(1100, 760)
        window.onCloseRequest(_self().closeRequested)
        Gtk.Box layout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        window.setChild(layout)
        menu = Gtk.MenuBar()
        layout.append(menu)
        int fileMenu = menu.addMenu("File")
        loadItem = menu.addItem(fileMenu, "Load Executable...", _self().chooseExecutable)
        openItem = menu.addItem(fileMenu, "Open Source Code...", _self().chooseSource)
        menu.addSeparator(fileMenu)
        quitItem = menu.addItem(fileMenu, "Quit", _self().quit)
        int searchMenu = menu.addMenu("Search")
        findItem = menu.addItem(searchMenu, "Find...", _self().showFind)
        window.bindShortcut("<Control>q", _self().quit)
        window.bindShortcut("<Control>f", _self().showFind)
        findWindow = Gtk.TransientWindow("Find")
        findWindow.setDefaultSize(420, 100)
        findWindow.setTransientFor(window)
        findWindow.setVisible(false)
        findWindow.onCloseRequest(_self().findCloseRequested)
        Gtk.Box findLayout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        findWindow.setChild(findLayout)
        findEntry = Gtk.Entry("")
        findEntry.setHExpand(true)
        findLayout.append(findEntry)
        Gtk.Box findButtons = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        findLayout.append(findButtons)
        button(findButtons, "Find Next", _self().findNext)
        button(findButtons, "Find Previous", _self().findPrevious)
        button(findButtons, "Close", _self().closeFind)
        findStatus = Gtk.Label("")
        findLayout.append(findStatus)
        Gtk.Box control = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        layout.append(control)
        runButton = button(control, "Run / Continue", _self().resume)
        restartButton = button(control, "Restart", _self().restart)
        stepButton = button(control, "Step Into", _self().stepInto)
        nextButton = button(control, "Step Over", _self().stepOver)
        finishButton = button(control, "Step Out", _self().stepOut)
        interruptButton = button(control, "Pause", _self().interrupt)
        button(control, "End Session", _self().endSession)
        Gtk.Box breakRow = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        layout.append(breakRow)
        breakRow.append(Gtk.Label("Breakpoint (function or file:line)"))
        breakpoint = Gtk.Entry("main")
        breakpoint.setHExpand(true)
        breakRow.append(breakpoint)
        button(breakRow, "Add", _self().addBreakpoint)
        breakpointNumber = Gtk.Entry("")
        breakRow.append(breakpointNumber)
        button(breakRow, "Delete ID", _self().deleteBreakpoint)
        Gtk.Box watchRow = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        layout.append(watchRow)
        watchRow.append(Gtk.Label("Watch expression"))
        watch = Gtk.Entry("")
        watch.setHExpand(true)
        watchRow.append(watch)
        button(watchRow, "Watch", _self().addWatch)
        watchRow.append(Gtk.Label("Stack frame"))
        frameNumber = Gtk.Entry("0")
        watchRow.append(frameNumber)
        button(watchRow, "Select Frame", _self().selectFrame)
        Gtk.Paned body = Gtk.Paned()
        body.setPosition(600)
        body.setVExpand(true)
        layout.append(body)
        source = pane()
        sourceTabs = Gtk.Notebook()
        sourceTabs.setBorderedTabs()
        sourceTabs.setHExpand(true)
        sourceTabs.setVExpand(true)
        body.append(sourceTabs)
        sourceMessage("No source loaded. Use File > Load Executable... or File > Open Source Code...")
        Gtk.Notebook inspection = Gtk.Notebook()
        inspection.setBorderedTabs()
        inspection.setHExpand(true)
        inspection.setVExpand(true)
        body.append(inspection)
        locals = pane()
        stack = pane()
        watches = pane()
        breaks = pane()
        console = pane()
        programOutput = pane()
        inspection.appendPage(scroll(locals), "Locals / Arguments")
        inspection.appendPage(scroll(stack), "Stack")
        inspection.appendPage(scroll(watches), "Watches")
        inspection.appendPage(scroll(breaks), "Breakpoints")
        inspection.appendPage(scroll(programOutput), "Program Output")
        inspection.appendPage(scroll(console), "Debugger Console")
        status = Gtk.Label("Load a local target. GDB only; no attach/remote or LLDB yet.")
        layout.append(status)
        controls()
        window.present()
        if (System.Process().argc() > 1) {
            int i = 2
            if (System.Process().arg(i).equals("--")) { i = i + 1 }
            while (i < System.Process().argc()) {
                arguments.append(System.Process().arg(i))
                i = i + 1
            }
            loadTarget(System.Process().arg(1))
        }
    }
    String initialPath() {
        if (!targetPath.equals("")) { return System.FileSystem().absolutePath(targetPath) }
        if (source != null) {
            int i = 0
            while (i < sourceFiles.length) {
                DebugSource file = sourceFiles[i] as DebugSource
                if (file.view == source && !file.path.equals("")) { return file.path }
                i = i + 1
            }
        }
        return ""
    }
    void chooseExecutable() {
        if (fileDialog != null && fileDialog.pending()) { return }
        fileDialog = Gtk.FileDialog(window, false, initialPath(), _self().executableChosen)
    }
    void chooseSource() {
        if (fileDialog != null && fileDialog.pending()) { return }
        fileDialog = Gtk.FileDialog(window, false, initialPath(), _self().sourceChosen)
    }
    void executableChosen(String path) {
        fileDialog = null
        if (!path.equals("")) { loadTarget(path) }
    }
    void sourceChosen(String path) {
        fileDialog = null
        if (!path.equals("")) { openSource(path) }
    }
    void quit() {
        if (window != null && !window.disposed()) { window.close() }
    }
    // Load Executable: a fresh GDB session with breakpoints cleared, prepared
    // but not run. A .cw path (command line) is compiled with -g first. A path
    // that is not a regular file is rejected before the current session or
    // source tabs are touched.
    void loadTarget(String path) {
        String absolute = System.FileSystem().absolutePath(path)
        if (absolute.equals("")) { absolute = path }
        if (path.equals("") || !System.FileSystem().isFile(absolute)) {
            loadFailure(format("Target is not a local file: {}", absolute))
            return
        }
        targetPath = path
        launch()
    }
    // Open Source Code: shows a text file read-only without compiling it or
    // touching the debug session. Binary, invalid UTF-8 and executable files
    // are rejected with an error dialog and no tab change.
    bool openSource(String path) {
        String absolute = System.FileSystem().absolutePath(path)
        if (absolute.equals("")) { absolute = path }
        if (!System.FileSystem().isFile(absolute)) {
            loadFailure(format("Source is not a local file: {}", absolute))
            return false
        }
        if (executableImage(absolute)) {
            loadFailure(format("{} is an executable, not source code; use File > Load Executable...",
                absolute))
            return false
        }
        return showSource(absolute, "")
    }
    bool executableImage(String path) {
        System.File file = null
        try {
            file = System.File(path, "rb")
            String magic = file.read(4)
            file.close()
            return (magic.length == 4 && magic.byteAt(0) == 127u && magic.byteAt(1) == 69u &&
                magic.byteAt(2) == 76u && magic.byteAt(3) == 70u)
        } except(Exception) {
            if (file != null && file.isOpen()) { file.close() }
        }
        return false
    }
    void showFind() {
        if (findWindow == null || findWindow.disposed()) { return }
        findStatus.setText("")
        if (source != null && source.hasSelection()) {
            String selected = source.selectedText()
            if (!selected.contains("\n")) { findEntry.setText(selected) }
        }
        findWindow.setVisible(true)
        findWindow.present()
        findEntry.focus()
    }
    void closeFind() {
        if (findWindow != null && !findWindow.disposed()) { findWindow.setVisible(false) }
    }
    bool findCloseRequested() {
        findWindow.setVisible(false)
        return true
    }
    void findNext() { find(false) }
    void findPrevious() { find(true) }
    void find(bool backward) {
        String query = findEntry.text()
        if (query.equals("")) { findStatus.setText("Enter text to find")
            return }
        if (source == null || currentSource() == null) {
            findStatus.setText("No source file is open")
            return
        }
        int before = source.line()
        int options = 0
        if (backward) { options = GtkSource.View.BACKWARD }
        if (!source.findWith(query, options)) {
            findStatus.setText(format("Not found: {}", query))
            return
        }
        int after = source.line()
        if ((!backward && after < before) || (backward && after > before)) {
            findStatus.setText(format("Wrapped: {} at line {}", query, after))
        } else { findStatus.setText(format("Found: {} at line {}", query, after)) }
    }
    DebugSource currentSource() {
        int page = sourceTabs.currentPage()
        if (page < 0 || page >= sourceFiles.length) { return null }
        DebugSource file = sourceFiles[page] as DebugSource
        if (file.path.equals("")) { return null }
        return file
    }
    void controls() {
        if (window == null || window.disposed()) { return }
        bool ready = loaded && !running && active == null && requests.length == 0
        runButton.setSensitive(ready)
        stepButton.setSensitive(ready && hasRun)
        nextButton.setSensitive(ready && hasRun)
        finishButton.setSensitive(ready && hasRun)
        interruptButton.setSensitive(loaded && running)
        restartButton.setSensitive(loaded && active == null && requests.length == 0 && !restarting)
    }
    String outputHistory(String previous, String text) {
        previous.append(text)
        if (previous.length <= 65536) { return previous }
        int first = previous.length - 65536
        while (first < previous.length && previous.byteAt(first) >= 128u &&
            previous.byteAt(first) <= 191u) { first = first + 1 }
        return previous.slice(first, previous.length)
    }
    void log(String text) {
        console.setText(outputHistory(console.text(), text))
    }
    void programLog(String text) {
        if (text.equals("")) { return }
        text = text.replace(Process.OutputDecoder().decode(buffer[0u]), "\\0")
        programOutput.setText(outputHistory(programOutput.text(), text))
    }
    void readProgramOutput() {
        if (terminal == null) { return }
        programLog(terminal.read())
        if (!terminal.error().equals("")) {
            fail(format("Program output transport failed: {}", terminal.error()))
        }
    }
    void fail(String text) {
        failure = text
        System.StandardIO().writeErrorLine(format("cdbg: {}", text))
        if (window != null && !window.disposed()) {
            status.setText(format("Error: {}", text))
            log(format("Error: {}\n", text))
        }
    }
    void loadFailure(String text) {
        fail(text)
        if (window != null && !window.disposed()) {
            Gtk.AlertDialog().show(window, "Could not load file", text)
        }
    }
    // The source notebook always keeps at least one page: a message page
    // (path "") stands in when no file tab is open, so the area never hides.
    void clearSources() {
        sourceMessage("Loading source...")
        list kept = []
        int i = 0
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
    void sourceMessage(String text) {
        int i = 0
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
    void removeSourcePage(DebugSource file) {
        list remaining = []
        int i = 0
        while (i < sourceFiles.length) {
            DebugSource item = sourceFiles[i] as DebugSource
            if (item != file) { remaining.append(item) }
            i = i + 1
        }
        sourceTabs.remove(file.scroll)
        file.scroll.dispose()
        sourceFiles = remaining
    }
    void removeMessagePage() {
        if (sourceFiles.length < 2) { return }
        int i = 0
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
    void closeSource(DebugSource file) {
        bool open = false
        int i = 0
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
    String compiler() {
        String explicit = System.Process().getEnv("CDBG_COMPILER")
        if (!explicit.equals("")) { return explicit }
        String own = System.Process().arg(0)
        if (!own.contains("/")) {
            list paths = System.Process().getEnv("PATH").split(":")
            int i = 0
            while (i < paths.length) {
                String candidate = System.FileSystem().join(paths[i] as String, own)
                if (System.FileSystem().isFile(candidate)) { own = candidate
                    break }
                i = i + 1
            }
        }
        String sibling = System.FileSystem().join(System.FileSystem().dirname(
            System.FileSystem().absolutePath(own)), "cwhip")
        if (System.FileSystem().isFile(sibling)) { return sibling }
        return "cwhip"
    }
    void cleanup() {
        if (!temporary.equals("")) {
            if (System.FileSystem().exists(executable) && !System.FileSystem().remove(executable)) {
                fail(format("Could not remove temporary executable {}", executable))
            }
            if (!System.FileSystem().rmdir(temporary)) {
                fail(format("Could not remove temporary directory {}", temporary))
            }
            temporary = ""
        }
    }
    void endSession() {
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
        mode = 0
        cleanup()
        controls()
        if (window != null && !window.disposed() && failure.equals("")) {
            status.setText("Session ended")
        }
    }
    bool closeRequested() {
        closed = true
        if (fileDialog != null) {
            fileDialog.cancel()
            fileDialog = null
        }
        if (findWindow != null && !findWindow.disposed()) { findWindow.dispose() }
        endSession()
        return false
    }
    void launch() {
        endSession()
        failure = ""
        stopCount = 0
        inferiorPid = ""
        location = ""
        executable = System.FileSystem().absolutePath(targetPath)
        if (executable.equals("")) { executable = targetPath }
        if (!System.FileSystem().isFile(executable)) { loadFailure(format("Target is not a local file: {}", executable))
            return }
        output = Process.OutputDecoder()
        errors = Process.OutputDecoder()
        pending = ""
        console.setText("")
        programOutput.setText("")
        locals.setText("")
        stack.setText("")
        watches.setText("")
        breaks.setText("")
        if (executable.endsWith(".cw")) {
            String input = executable
            if (!readableText(input)) { return }
            temporary = System.FileSystem().tempDir()
            if (temporary.equals("")) { fail("Could not create a temporary compilation directory")
                return }
            executable = System.FileSystem().join(temporary, "target")
            compilerOutput = ""
            status.setText("Compiling with Cwhip -g...")
            process = Process.AsyncProcess(compiler(), [input, "-g", "-o", executable],
                System.FileSystem().dirname(input))
            mode = 1
        } else { startDebugger() }
        if (process == null || !process.started()) {
            if (process != null) { fail(process.error()) }
            if (process != null) { process.close()
                process = null }
            cleanup()
            if (terminal != null) { terminal.close()
                terminal = null }
            return
        }
        pollToken = Gtk.Application().post(_self().poll)
    }
    void startDebugger() {
        terminal = DebugTerminal()
        if (!terminal.error().equals("")) {
            fail(format("Could not allocate program output terminal: {}", terminal.error()))
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
        if (!process.started()) { fail(format("Could not start GDB: {}", process.error()))
            return }
        status.setText("Starting GDB...")
        enqueue("-gdb-set pagination off", "setup", "")
        enqueue("-gdb-set mi-async on", "setup", "")
        enqueue("-gdb-set confirm off", "setup", "")
        enqueue(format("-inferior-tty-set {}", MiParser().quote(terminal.path())), "setup", "")
        enqueue(format("-file-exec-and-symbols {}", MiParser().quote(executable)), "target", "")
        String args = "-exec-arguments"
        int i = 0
        while (i < arguments.length) {
            args.append(format(" {}", MiParser().quote(arguments[i] as String)))
            i = i + 1
        }
        enqueue(args, "loaded", "")
        enqueue("-file-list-exec-source-files", "sources", "")
    }
    void enqueue(String command, String purpose, String expression) {
        if (requests.length >= 256) { fail("GDB request queue is full")
            return }
        sequence = sequence + 1
        requests.append(DebugRequest(format("{}", sequence), command, purpose, expression))
        sendNext()
    }
    void sendNext() {
        if (active != null || requests.length == 0 || process == null) { return }
        active = requests[0] as DebugRequest
        requests = requests[1:]
        if (!process.write(format("{}{}\n", active.token, active.command))) {
            fail(format("GDB command write failed: {}", process.inputError()))
            active = null
            requests = []
            loaded = false
        }
        controls()
    }
    bool stopped() {
        if (!loaded || running || !hasRun) { fail("This operation requires a stopped target")
            return false }
        return true
    }
    void resume() {
        if (!loaded || running || active != null || requests.length > 0) {
            fail("Wait for GDB to be ready before running")
            return
        }
        String command = "-exec-run"
        if (hasRun) { command = "-exec-continue" }
        enqueue(command, "execute", "")
    }
    void restart() {
        if (!loaded || active != null || requests.length > 0 || restarting) {
            fail("Wait for GDB to be ready before restarting")
            return
        }
        restarting = true
        if (running) { enqueue("-exec-interrupt", "restart-interrupt", "") }
        else { restartStopped() }
        controls()
    }
    void restartStopped() {
        if (hasRun) {
            enqueue("-interpreter-exec console \"kill\"", "restart-kill", "")
        } else {
            restarting = false
            enqueue("-exec-run", "execute", "")
        }
    }
    void stepInto() { if (stopped()) { enqueue("-exec-step", "execute", "") } }
    void stepOver() { if (stopped()) { enqueue("-exec-next", "execute", "") } }
    void stepOut() { if (stopped()) { enqueue("-exec-finish", "execute", "") } }
    void interrupt() {
        if (!loaded || !running) { fail("No running target to pause")
            return }
        enqueue("-exec-interrupt", "interrupt", "")
    }
    bool identifier(String text) {
        if (text.equals("")) { return false }
        int i = 0
        while (i < text.length) {
            if (int(text.byteAt(i)) < 48 || int(text.byteAt(i)) > 57) { return false }
            i = i + 1
        }
        return true
    }
    void addBreakpoint() {
        String text = breakpoint.text().trim()
        if (!loaded || running || text.equals("")) { fail("Load and stop a target, then enter a breakpoint")
            return }
        enqueue(format("-break-insert {}", MiParser().quote(text)), "break", "")
        enqueue("-break-list", "breaks", "")
    }
    void deleteBreakpoint() {
        if (!loaded || running || !identifier(breakpointNumber.text())) {
            fail("Enter a numeric breakpoint ID while the target is stopped")
            return
        }
        enqueue(format("-break-delete {}", breakpointNumber.text()), "break", "")
        enqueue("-break-list", "breaks", "")
    }
    void addWatch() {
        String expression = watch.text().trim()
        if (expression.equals("") || expression.length > 4096 || expressions.length >= 64) {
            fail("Enter a watch expression (maximum 4096 bytes, 64 watches)")
            return }
        int i = 0
        while (i < expressions.length) {
            if ((expressions[i] as String).equals(expression)) { return }
            i = i + 1
        }
        expressions.append(expression)
        if (loaded && !running && hasRun) { refresh() }
        else { watches.setText("Watches will be evaluated at the next stop") }
    }
    void selectFrame() {
        if (!stopped()) { return }
        if (!identifier(frameNumber.text())) { fail("Enter a numeric stack frame")
            return }
        enqueue(format("-stack-select-frame {}", frameNumber.text()), "frame", "")
    }
    bool inspection(DebugRequest request) {
        return (request.purpose.equals("location") || request.purpose.equals("locals") ||
            request.purpose.equals("stack") || request.purpose.equals("watch"))
    }
    void refresh() {
        if (!loaded || running || !hasRun) { return }
        list pendingRequests = []
        int requestIndex = 0
        while (requestIndex < requests.length) {
            DebugRequest request = requests[requestIndex] as DebugRequest
            if (!inspection(request)) { pendingRequests.append(request) }
            requestIndex = requestIndex + 1
        }
        requests = pendingRequests
        if (active != null && inspection(active)) { active.purpose = "stale" }
        watches.setText("")
        enqueue("-stack-info-frame", "location", "")
        enqueue("-stack-list-variables --all-values", "locals", "")
        enqueue("-stack-list-frames 0 30", "stack", "")
        int i = 0
        while (i < expressions.length) {
            String expression = expressions[i] as String
            enqueue(format("-data-evaluate-expression {}", MiParser().quote(expression)), "watch", expression)
            i = i + 1
        }
    }
    void showLocation(MiValue frame) {
        String path = frame.field("fullname").text
        if (path.equals("")) { path = frame.field("file").text }
        String line = frame.field("line").text
        location = format("{}:{} ({})", path, line, frame.field("func").text)
        status.setText(format("Stopped: {}", location))
        if (path.equals("")) { sourceMessage("Source unavailable: stopped frame has no source path") }
        else { showSource(path, line) }
    }
    // Reads a source file for display; on failure shows the parented error
    // dialog and returns false without touching any tab.
    bool readText(String path) {
        sourceText = ""
        if (path.equals("") || !System.FileSystem().isFile(path)) {
            loadFailure(format("Source unavailable: {}", path))
            return false
        }
        System.File file = null
        try {
            file = System.File(path, "r")
            String text = file.readAll()
            String readError = System.System().lastError()
            file.close()
            if (!readError.equals("")) {
                loadFailure(format("Could not read source {}: {}", path, readError))
                return false
            }
            if (!GtkSource.Content().isText(text)) {
                loadFailure(format("Source is not a text file: {}", path))
                return false
            }
            sourceText = text
            return true
        } except(Exception) as err {
            if (file != null && file.isOpen()) { file.close() }
            loadFailure(format("Could not display source {}: {}", path, err.message))
        }
        return false
    }
    bool readableText(String path) {
        bool readable = readText(path)
        sourceText = ""
        return readable
    }
    bool showSource(String path, String line) {
        String absolute = System.FileSystem().absolutePath(path)
        if (!absolute.equals("")) { path = absolute }
        int i = 0
        while (i < sourceFiles.length) {
            DebugSource file = sourceFiles[i] as DebugSource
            if (file.path.equals(path)) {
                bool switched = sourceTabs.currentPage() != i
                source = file.view
                sourceTabs.setCurrentPage(i)
                if (identifier(line) && line.toInt() > 0 &&
                    (switched || source.line() != line.toInt() || file.centeredStop != stopCount)) {
                    source.centerCursor(line.toInt(), 1)
                    file.centeredStop = stopCount
                }
                removeMessagePage()
                return true
            }
            i = i + 1
        }
        if (!readText(path)) { return false }
        source = pane()
        source.setText(sourceText)
        sourceText = ""
        source.setLanguage(GtkSource.Content().languageFor(path))
        Gtk.ScrolledWindow container = scroll(source)
        DebugSource document = DebugSource(path, source, container)
        document.closeAction = _self().closeSource
        sourceFiles.append(document)
        sourceTabs.appendClosablePage(container, System.FileSystem().basename(path), document.close)
        removeMessagePage()
        sourceTabs.setCurrentPage(sourceFiles.length - 1)
        if (identifier(line) && line.toInt() > 0) {
            source.centerCursor(line.toInt(), 1)
            document.centeredStop = stopCount
        }
        return true
    }
    void response(MiParser record) {
        if (active == null || !record.token.equals(active.token)) {
            fail("Unexpected GDB response token")
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
            if (done.purpose.startsWith("restart-")) { restarting = false }
            String message = record.data.field("msg").text
            if (done.purpose.equals("watch")) {
                watches.setText(format("{}{} = <{}>\n", watches.text(), done.expression, message))
            } else {
                if (done.purpose.equals("target")) { loadFailure(message) }
                else { fail(message) }
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
        if (done.purpose.equals("target")) { clearSources() }
        if (done.purpose.equals("loaded")) {
            loaded = true
            status.setText("Loaded. Add breakpoints, then Run.")
        }
        if (done.purpose.equals("sources")) {
            MiValue files = record.data.field("files")
            bool cwhipSources = false
            int i = 0
            while (i < files.values.length) {
                MiValue file = files.values[i] as MiValue
                if (file.field("file").text.endsWith(".cw")) { cwhipSources = true }
                i = i + 1
            }
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
            enqueue("-exec-run", "execute", "")
        }
        if (record.result.equals("running")) {
            hasRun = true
            running = true
            locals.setText("Target running")
            watches.setText("Target running")
            status.setText("Running")
        }
        if (done.purpose.equals("locals")) {
            MiValue variables = record.data.field("variables")
            String text = ""
            int i = 0
            while (i < variables.values.length) {
                MiValue variable = variables.values[i] as MiValue
                text.append(format("{} = {}\n", variable.field("name").text, variable.field("value").text))
                i = i + 1
            }
            if (text.equals("")) { text = "(No variables in this frame)" }
            locals.setText(text)
        }
        if (done.purpose.equals("stack")) {
            MiValue frames = record.data.field("stack")
            String text = ""
            int i = 0
            while (i < frames.values.length) {
                MiValue frame = frames.values[i] as MiValue
                text.append(format("#{} {} {}:{}\n", frame.field("level").text, frame.field("func").text,
                    frame.field("file").text, frame.field("line").text))
                i = i + 1
            }
            stack.setText(text)
        }
        if (done.purpose.equals("watch")) {
            watches.setText(format("{}{} = {}\n", watches.text(), done.expression, record.data.field("value").text))
        }
        if (done.purpose.equals("location")) {
            showLocation(record.data.field("frame"))
        }
        if (done.purpose.equals("frame")) {
            refresh()
        }
        if (done.purpose.equals("breaks")) {
            MiValue rows = record.data.field("BreakpointTable").field("body")
            String text = ""
            int i = 0
            while (i < rows.values.length) {
                MiValue item = rows.values[i] as MiValue
                text.append(format("#{} {} {}:{} {}\n", item.field("number").text,
                    item.field("enabled").text, item.field("file").text, item.field("line").text,
                    item.field("original-location").text))
                i = i + 1
            }
            breaks.setText(text)
        }
        sendNext()
        controls()
    }
    void record(String line) {
        if (line.endsWith("\r")) { line = line.slice(0, line.length - 1) }
        if (line.equals("") || line.trim().equals("(gdb)")) { return }
        MiParser parsed = MiParser()
        parsed.parse(line)
        if (!parsed.valid) {
            // Inferior stdout can arrive unframed on GDB's own output pipe.
            if (line.startsWith("^") || line.startsWith("*stopped") ||
                (active != null && line.startsWith(format("{}^", active.token)))) {
                fail(format("Malformed GDB record: {}", line))
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
        if (parsed.kind.equals("*") && parsed.result.equals("stopped")) {
            running = false
            String reason = parsed.data.field("reason").text
            if (restarting) {
                if (reason.startsWith("exited")) { hasRun = false }
                restartStopped()
                controls()
                return
            }
            if (reason.startsWith("exited")) {
                readProgramOutput()
                hasRun = false
                locals.setText("Target exited")
                watches.setText("Target exited")
                status.setText(format("Target {} {}", reason, parsed.data.field("exit-code").text))
            } else {
                hasRun = true
                stopCount = stopCount + 1
                showLocation(parsed.data.field("frame"))
                refresh()
            }
            controls()
        }
        if (parsed.kind.equals("*") && parsed.result.equals("running")) {
            running = true
            controls()
        }
    }
    void consume(String chunk) {
        pending.append(chunk)
        if (pending.length > 1048576) {
            fail("GDB record exceeded the 1 MiB prototype limit")
            endSession()
            return
        }
        int newline = pending.find("\n")
        while (newline >= 0) {
            String line = pending.slice(0, newline)
            pending = pending.slice(newline + 1, pending.length)
            record(line)
            newline = pending.find("\n")
        }
    }
    void poll() {
        pollToken = 0
        if (closed || process == null) { return }
        readProgramOutput()
        if (terminal != null && !terminal.error().equals("")) {
            endSession()
            return
        }
        if (mode == 2 && !process.inputError().equals("")) {
            fail(format("GDB stdin failed: {}", process.inputError()))
            endSession()
            return
        }
        Process.ProcessEvent event = process.next(10)
        int count = 0
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
                    process.close()
                    process = null
                    log(compilerOutput)
                    if (!success) { loadFailure("Cwhip -g compilation failed; see Debugger Console")
                        cleanup()
                        return }
                    startDebugger()
                    if (process == null || !process.started()) {
                        if (process != null) { process.close()
                            process = null }
                        cleanup()
                        return }
                } else {
                    consume(output.finish())
                    if (process == null) { return }
                    log(errors.finish())
                    String error = process.error()
                    process.close()
                    process = null
                    loaded = false
                    running = false
                    requests = []
                    active = null
                    controls()
                    fail(format("GDB session ended unexpectedly: {}", error))
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
}

Cdbg Cdbg._self() from "cwhip_gtk_self"

start {
    if (System.Process().arg(1).equals("--help")) {
        print("Usage: cdbg [SOURCE.cw|EXECUTABLE [-- ARGS...]]\nLocal GDB/MI GTK prototype. Sources compile with -g. No LLDB, remote, or attach.\n")
    } else {
        Gtk.Application app = Gtk.Application("org.cwhip.Cdbg")
        Cdbg debugger = Cdbg()
        app.onActivate(debugger.activate)
        app.run()
        debugger.endSession()
    }
}
