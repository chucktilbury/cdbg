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

class DebugBreakpoint {
    String number
    String path
    String line
    bool enabled
    DebugBreakpoint(String id, String file, String row, bool active) {
        number = id
        path = file
        line = row
        enabled = active
    }
}

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
    int toggleBreakItem
    int toggleEnableItem
    int setupItem
    Gtk.TransientWindow setupWindow
    Gtk.CheckButton setupStart
    Gtk.Entry setupArguments
    Gtk.Label setupStatus
    Gtk.ContextMenu outputMenu
    bool breakAtStart
    bool targetSettings
    String argumentText
    list cliArguments
    bool cliPending
    String startBreakpoint
    bool startMissing
    list runHits
    String stateError
    String stateNote
    bool defaultChanged
    String startNumber
    bool atStart
    Gtk.Paned body
    Gtk.Notebook inspection
    String statePath
    String stateText
    bool stateWritable
    String stateTarget
    bool restoringBreakpoints
    int restorePending
    Gtk.ContextMenu watchMenu
    Gtk.TransientWindow watchWindow
    Gtk.Entry watchEntry
    Gtk.Label watchStatus
    list breakpointRows
    list breakpointEntries
    list breakpointLocations
    list stackFrames
    int selectedFrame
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
    String stopDetail
    String stopPosition
    String stopAddress
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
        stopDetail = ""
        stopPosition = ""
        stopAddress = ""
        targetPath = ""
        sourceText = ""
        sourceFiles = []
        breakpointRows = []
        breakpointEntries = []
        breakpointLocations = []
        stackFrames = []
        breakAtStart = true
        argumentText = ""
        cliArguments = []
        startBreakpoint = ""
        startNumber = ""
        runHits = []
        stateError = ""
        stateNote = ""
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
        int breakpointMenu = menu.addMenu("Breakpoint")
        toggleBreakItem = menu.addItem(breakpointMenu, "Set/Clear Breakpoint", _self().toggleBreakpoint)
        toggleEnableItem = menu.addItem(breakpointMenu, "Enable/Disable Breakpoint", _self().toggleEnabled)
        int debugMenu = menu.addMenu("Debug")
        setupItem = menu.addItem(debugMenu, "Setup...", _self().showSetup)
        window.bindShortcut("<Control>q", _self().quit)
        window.bindShortcut("<Control>f", _self().showFind)
        window.bindShortcut("F9", _self().toggleBreakpoint)
        window.bindShortcut("<Control>F9", _self().toggleEnabled)
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
        body = Gtk.Paned()
        body.setPosition(600)
        body.setVExpand(true)
        layout.append(body)
        source = pane()
        sourceTabs = Gtk.Notebook()
        sourceTabs.onPageChanged(_self().sourceChanged)
        sourceTabs.setBorderedTabs()
        sourceTabs.setScrollable(true)
        sourceTabs.setHExpand(true)
        sourceTabs.setVExpand(true)
        body.append(sourceTabs)
        sourceMessage("No source loaded. Use File > Load Executable... or File > Open Source Code...")
        inspection = Gtk.Notebook()
        inspection.setBorderedTabs()
        inspection.setScrollable(true)
        inspection.setHExpand(true)
        inspection.setVExpand(true)
        body.append(inspection)
        locals = pane()
        stack = pane()
        watches = pane()
        breaks = pane()
        stack.setLineSelection(true)
        stack.onLineActivated(_self().stackClicked)
        breaks.setLineSelection(true)
        breaks.onLineActivated(_self().breakpointClicked)
        watchMenu = Gtk.ContextMenu(watches.widget())
        Gtk.Box watchActions = Gtk.Box(Gtk.Box.VERTICAL, 0)
        watchMenu.setChild(watchActions)
        button(watchActions, "Add Watch...", _self().showWatch)
        watchWindow = Gtk.TransientWindow("Add Watch")
        watchWindow.setTransientFor(window)
        watchWindow.setDefaultSize(420, 100)
        watchWindow.setVisible(false)
        watchWindow.onCloseRequest(_self().watchCloseRequested)
        Gtk.Box watchLayout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        watchWindow.setChild(watchLayout)
        watchLayout.append(Gtk.Label("Expression"))
        watchEntry = Gtk.Entry("")
        watchLayout.append(watchEntry)
        watchStatus = Gtk.Label("")
        watchLayout.append(watchStatus)
        Gtk.Box watchButtons = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        watchLayout.append(watchButtons)
        button(watchButtons, "Add", _self().acceptWatch)
        button(watchButtons, "Cancel", _self().closeWatch)
        console = pane()
        programOutput = pane()
        outputMenu = Gtk.ContextMenu(programOutput.widget())
        Gtk.Box outputActions = Gtk.Box(Gtk.Box.VERTICAL, 0)
        outputMenu.setChild(outputActions)
        button(outputActions, "Clear", _self().clearOutput)
        button(outputActions, "Copy", _self().copyOutput)
        button(outputActions, "Copy All", _self().copyAllOutput)
        setupWindow = Gtk.TransientWindow("Setup")
        setupWindow.setTransientFor(window)
        setupWindow.setDefaultSize(480, 160)
        setupWindow.setVisible(false)
        setupWindow.onCloseRequest(_self().setupCloseRequested)
        Gtk.Box setupLayout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        setupWindow.setChild(setupLayout)
        setupStart = Gtk.CheckButton("Break at start")
        setupLayout.append(setupStart)
        setupLayout.append(Gtk.Label("Program arguments (shell-style quoting; no shell is run)"))
        setupArguments = Gtk.Entry("")
        setupArguments.setHExpand(true)
        setupLayout.append(setupArguments)
        setupStatus = Gtk.Label("")
        setupLayout.append(setupStatus)
        Gtk.Box setupButtons = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        setupLayout.append(setupButtons)
        button(setupButtons, "Apply", _self().applySetup)
        button(setupButtons, "Cancel", _self().closeSetup)
        inspection.appendPage(scroll(locals), "Locals / Arguments")
        inspection.appendPage(scroll(stack), "Stack")
        inspection.appendPage(scroll(watches), "Watches")
        inspection.appendPage(scroll(breaks), "Breakpoints")
        inspection.appendPage(scroll(programOutput), "Program Output")
        inspection.appendPage(scroll(console), "Debugger Console")
        status = Gtk.Label("Load a local target. GDB only; no attach/remote or LLDB yet.")
        layout.append(status)
        readState()
        controls()
        window.present()
        if (System.Process().argc() > 1) {
            int i = 2
            if (System.Process().arg(i).equals("--")) { i = i + 1 }
            while (i < System.Process().argc()) {
                cliArguments.append(System.Process().arg(i))
                i = i + 1
            }
            cliPending = cliArguments.length > 0
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
    void sourceChanged() {
        int page = sourceTabs.currentPage()
        if (page >= 0 && page < sourceFiles.length) {
            source = (sourceFiles[page] as DebugSource).view
        }
        controls()
    }
    void sourceLineClicked(int line) { controls() }
    void controls() {
        if (window == null || window.disposed()) { return }
        bool ready = loaded && !running && active == null && requests.length == 0
        bool canBreak = ready && currentSource() != null
        menu.setItemEnabled(toggleBreakItem, canBreak)
        menu.setItemEnabled(toggleEnableItem, canBreak)
        runButton.setSensitive(ready)
        stepButton.setSensitive(ready && hasRun)
        nextButton.setSensitive(ready && hasRun)
        finishButton.setSensitive(ready && hasRun)
        interruptButton.setSensitive(loaded && running)
        restartButton.setSensitive(loaded && active == null && requests.length == 0 && !restarting)
    }
    void stateDiagnostic(String text) {
        log(format("State: {}\n", text))
        System.StandardIO().writeErrorLine(format("cdbg state: {}", text))
    }
    int stateNumber(String key, int fallback, int minimum, int maximum) {
        String raw = Gtk.Config().value(stateText, "", key)
        if (!raw.startsWith("i") || raw.length > 8 || !identifier(raw.slice(1, raw.length))) {
            if (!raw.equals("")) { stateDiagnostic(format("Invalid {}; using default", key)) }
            return fallback
        }
        int value = raw.slice(1, raw.length).toInt()
        if (value < minimum) { return minimum }
        if (value > maximum) { return maximum }
        return value
    }
    void readState() {
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
        int width = stateNumber("width", 1100, 640, 3840)
        window.setDefaultSize(width, stateNumber("height", 760, 400, 2160))
        body.setPosition(stateNumber("pane", 600, 100, width - 100))
        inspection.setCurrentPage(stateNumber("inspector", 0, 0, 5))
        String maximized = Gtk.Config().value(stateText, "", "maximized")
        if (maximized.equals("btrue")) { window.setMaximized(true) }
        else { if (!maximized.equals("") && !maximized.equals("bfalse")) {
            stateDiagnostic("Invalid maximized; using default")
        } }
    }
    bool savedFlag(String table, String key, bool fallback) {
        String raw = Gtk.Config().value(stateText, table, key)
        if (raw.equals("btrue")) { return true }
        if (raw.equals("bfalse")) { return false }
        if (!raw.equals("")) { stateDiagnostic(format("Invalid {}; using default", key)) }
        return fallback
    }
    // Per-target setup: Break at start defaults to the directory default
    // (true for a new configuration). Command-line arguments after -- override
    // saved arguments for that command-line session only and are not saved.
    void loadTargetSettings() {
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
            if (parsed.parse(saved.slice(1, saved.length))) {
                arguments = parsed.values
                argumentText = saved.slice(1, saved.length)
                targetSettings = true
            } else { stateDiagnostic(format("Invalid saved arguments ({}); ignored", parsed.error)) }
        } else { if (!saved.equals("")) { stateDiagnostic("Saved arguments must be a string; ignored") } }
        if (cliPending) {
            arguments = cliArguments
            cliPending = false
            log(format("Using command-line arguments: {}\n", ArgumentList().display(arguments)))
        }
    }
    void saveState(bool layout) {
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
            int i = 0
            while (i < breakpointLocations.length && locations.length < 256) {
                DebugBreakpoint point = breakpointLocations[i] as DebugBreakpoint
                String key = format("{}:{}", point.path, point.line)
                bool duplicate = false
                int j = 0
                while (j < locations.length) {
                    if ((locations[j] as String).equals(key)) { duplicate = true }
                    j = j + 1
                }
                if (!duplicate && !point.path.equals("") && identifier(point.line)) {
                    locations.append(key)
                    bool enabled = point.enabled
                    int k = 0
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
    void saveError(String error) {
        String text = format("Settings not saved to {}: {}", statePath, error)
        if (!stateError.equals(error)) { stateDiagnostic(text) }
        stateError = error
        if (window != null && !window.disposed()) { status.setText(text) }
    }
    void restoreBreakpoints() {
        restoringBreakpoints = true
        restorePending = 0
        String kind = Gtk.Config().value(stateText, stateTarget, "points")
        int count = Gtk.Config().arraySize(stateText, stateTarget, "points")
        if (count > 256) { stateDiagnostic("Saved breakpoint limit exceeded; restoring first 256 entries") }
        if (!kind.equals("") && count < 0) {
            stateDiagnostic("Saved breakpoints must be an array; skipped")
        } else {
            int i = 0
            while (i < count && i < 256) {
                String file = Gtk.Config().item(stateText, stateTarget, "points", i, "file")
                String line = Gtk.Config().item(stateText, stateTarget, "points", i, "line")
                String enabled = Gtk.Config().item(stateText, stateTarget, "points", i, "enabled")
                if (!file.startsWith("s") || !line.startsWith("i") || line.length > 8 ||
                    !identifier(line.slice(1, line.length)) || line.slice(1, line.length).toInt() < 1 ||
                    (!enabled.equals("btrue") && !enabled.equals("bfalse"))) {
                    stateDiagnostic(format("Invalid saved breakpoint {}; skipped", i + 1))
                } else {
                    file = file.slice(1, file.length)
                    line = line.slice(1, line.length)
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
        sourceChanged()
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
    bool closeRequested() {
        saveState(true)
        closed = true
        if (fileDialog != null) {
            fileDialog.cancel()
            fileDialog = null
        }
        if (findWindow != null && !findWindow.disposed()) { findWindow.dispose() }
        if (watchWindow != null && !watchWindow.disposed()) { watchWindow.dispose() }
        endSession()
        return false
    }
    void launch() {
        saveState(false)
        endSession()
        stateTarget = System.FileSystem().absolutePath(targetPath)
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
        if (!stateWritable) { log("State file is invalid/unreadable; defaults in use, saving disabled\n") }
        if (!stateNote.equals("")) { log(stateNote) }
        if (!stateError.equals("")) { log(format("Settings not saved to {}: {}\n", statePath, stateError)) }
        loadTargetSettings()
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
        if (hasRun) { execute("-exec-continue") }
        else { startRun() }
    }
    // Every fresh run resends the current arguments, so Setup changes apply to
    // the next Run/Restart. "Break at start" is a temporary breakpoint on the
    // entry symbol: for Cwhip programs `main` is the generated start block, so
    // it stops on the `start {` line; native programs stop in main().
    void startRun() {
        String args = "-exec-arguments"
        int i = 0
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
            startRun()
        }
    }
    // Browsing a caller selects that frame for inspection, not for execution.
    void execute(String command) {
        if (active != null || requests.length > 0) { fail("Wait for GDB to be ready before executing")
            return }
        if (hasRun && selectedFrame != 0) {
            enqueue("-stack-select-frame 0", "execution-frame", command)
        } else { enqueue(command, "execute", "") }
    }
    void stepInto() { if (stopped()) { execute("-exec-step") } }
    void stepOver() { if (stopped()) { execute("-exec-next") } }
    void stepOut() { if (stopped()) { execute("-exec-finish") } }
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
    void addBreakpoint(String text) {
        text = text.trim()
        if (!loaded || running || text.equals("")) { fail("Load a target and pause it before adding a breakpoint")
            return }
        enqueue(format("-break-insert {}", MiParser().quote(text)), "break", "")
        requestBreakpoints()
    }
    void deleteBreakpoint(String number) {
        if (!loaded || running || !identifier(number)) {
            fail("Select a breakpoint while the target is stopped")
            return
        }
        enqueue(format("-break-delete {}", number), "break", "")
        requestBreakpoints()
    }
    list lineBreakpoints(DebugSource file) {
        list ids = []
        int i = 0
        while (i < breakpointLocations.length) {
            DebugBreakpoint item = breakpointLocations[i] as DebugBreakpoint
            if (sameSource(item.path, file.path) && item.line.equals(format("{}", file.view.line()))) {
                bool duplicate = false
                int j = 0
                while (j < ids.length) {
                    if ((ids[j] as String).equals(item.number)) { duplicate = true }
                    j = j + 1
                }
                if (!duplicate) { ids.append(item.number) }
            }
            i = i + 1
        }
        i = 0
        while (i < breakpointEntries.length) {
            MiValue entry = breakpointEntries[i] as MiValue
            if (entry.field("original-location").text.equals(format("{}:{}", file.path, file.view.line()))) {
                String number = entry.field("number").text.split(".")[0] as String
                bool duplicate = false
                int j = 0
                while (j < ids.length) {
                    if ((ids[j] as String).equals(number)) { duplicate = true }
                    j = j + 1
                }
                if (!duplicate) { ids.append(number) }
            }
            i = i + 1
        }
        return ids
    }
    void breakpointClicked(int line) {}
    bool breakpointReady() {
        if (!loaded || running || active != null || requests.length > 0 || currentSource() == null) {
            status.setText("Load a target, pause it, and select a source file before changing breakpoints")
            return false
        }
        return true
    }
    void toggleBreakpoint() {
        if (!breakpointReady()) { return }
        DebugSource file = currentSource()
        list ids = lineBreakpoints(file)
        if (ids.length == 0) { addBreakpoint(format("{}:{}", file.path, file.view.line()))
            return }
        int i = 0
        while (i < ids.length) { deleteBreakpoint(ids[i] as String)
            i = i + 1 }
    }
    void toggleEnabled() {
        if (!breakpointReady()) { return }
        list ids = lineBreakpoints(currentSource())
        if (ids.length == 0) { status.setText("No breakpoint at the current source line")
            return }
        bool enabled = false
        int i = 0
        while (i < breakpointLocations.length) {
            DebugBreakpoint point = breakpointLocations[i] as DebugBreakpoint
            int j = 0
            while (j < ids.length) {
                if (point.number.equals(ids[j] as String) && point.enabled) { enabled = true }
                j = j + 1
            }
            i = i + 1
        }
        String command = "-break-enable"
        if (enabled) { command = "-break-disable" }
        i = 0
        while (i < ids.length) { command.append(format(" {}", ids[i] as String))
            i = i + 1 }
        enqueue(command, "break", "")
        requestBreakpoints()
    }
    void requestBreakpoints() {
        if (active != null && active.purpose.equals("breaks")) { return }
        int i = 0
        while (i < requests.length) {
            if ((requests[i] as DebugRequest).purpose.equals("breaks")) { return }
            i = i + 1
        }
        enqueue("-break-list", "breaks", "")
    }
    bool sameSource(String path, String file) {
        if (path.equals("")) { return false }
        if (System.FileSystem().absolutePath(path).equals(file)) { return true }
        return !path.contains("/") && System.FileSystem().basename(file).equals(path)
    }
    void syncBreakpointMarks() {
        if (window == null || window.disposed()) { return }
        int i = 0
        while (i < sourceFiles.length) {
            DebugSource file = sourceFiles[i] as DebugSource
            file.view.clearLineMarks("breakpoint")
            file.view.clearLineMarks("disabled-breakpoint")
            int j = 0
            while (j < breakpointLocations.length) {
                DebugBreakpoint point = breakpointLocations[j] as DebugBreakpoint
                if (sameSource(point.path, file.path) && identifier(point.line) && point.line.toInt() > 0) {
                    String category = "disabled-breakpoint"
                    if (point.enabled) { category = "breakpoint" }
                    file.view.addLineMark(category, point.line.toInt())
                }
                j = j + 1
            }
            i = i + 1
        }
    }
    void breakpointLocation(MiValue item, String parent, bool enabled) {
        String number = item.field("number").text
        if (parent.equals("")) { parent = (number.split(".")[0] as String) }
        if (item.field("enabled").text.equals("n")) { enabled = false }
        String path = item.field("fullname").text
        if (path.equals("")) { path = item.field("file").text }
        String line = item.field("line").text
        if (!path.equals("") && identifier(line)) {
            breakpointLocations.append(DebugBreakpoint(parent, path, line, enabled))
        }
        MiValue locations = item.field("locations")
        int i = 0
        while (i < locations.values.length) {
            breakpointLocation(locations.values[i] as MiValue, parent, enabled)
            i = i + 1
        }
    }
    // Pending breakpoints have no code yet; installed ones show the function
    // and hit count so a breakpoint in code that never runs is visible.
    String breakpointSummary(MiValue item, bool enabled) {
        String state = "enabled"
        if (!enabled) { state = "disabled" }
        if (item.field("pending").text.length > 0) {
            return format("{} pending {} (not yet installed)", state, item.field("pending").text)
        }
        String where = format("{}:{}", item.field("file").text, item.field("line").text)
        if (item.field("addr").text.equals("<MULTIPLE>")) {
            where = format("{} (multiple locations)", item.field("original-location").text)
        }
        String text = format("{} installed {}", state, where)
        if (!item.field("func").text.equals("")) { text.append(format(" in {}", item.field("func").text)) }
        text.append(format(" hits {}", item.field("times").text))
        return text
    }
    // Lists enabled breakpoints whose hit count did not change during the run.
    int reportUnreached() {
        int count = 0
        int i = 0
        while (i < breakpointEntries.length) {
            MiValue entry = breakpointEntries[i] as MiValue
            String number = entry.field("number").text
            String key = format("{}={}", number, entry.field("times").text)
            bool same = false
            int j = 0
            while (j < runHits.length) {
                if ((runHits[j] as String).equals(key)) { same = true }
                j = j + 1
            }
            if (same && !number.contains(".") && !entry.field("enabled").text.equals("n") &&
                !entry.field("disp").text.equals("del")) {
                log(format("Not reached during this run: #{} {}:{} in {} (that code did not execute)\n", number,
                    entry.field("file").text, entry.field("line").text, entry.field("func").text))
                count = count + 1
            }
            i = i + 1
        }
        return count
    }
    void showWatch() {
        watchMenu.setVisible(false)
        watchEntry.setText("")
        watchStatus.setText("")
        watchWindow.setVisible(true)
        watchWindow.present()
        watchEntry.focus()
    }
    void closeWatch() { watchWindow.setVisible(false) }
    bool watchCloseRequested() { closeWatch()
        return true }
    void showSetup() {
        setupStart.setActive(breakAtStart)
        setupArguments.setText(ArgumentList().display(arguments))
        if (stateTarget.equals("")) {
            setupStatus.setText("No target loaded: Break at start becomes this directory's default")
        } else { setupStatus.setText(format("Settings for {}", stateTarget)) }
        setupWindow.setVisible(true)
        setupWindow.present()
        setupArguments.focus()
    }
    void closeSetup() { setupWindow.setVisible(false) }
    bool setupCloseRequested() { closeSetup()
        return true }
    // Apply never restarts a running program: arguments and Break at start
    // take effect on the next Run (from not started), Restart or Load.
    void applySetup() {
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
    void clearOutput() {
        outputMenu.setVisible(false)
        programOutput.setText("")
        status.setText("Program Output cleared")
    }
    void copyOutput() {
        outputMenu.setVisible(false)
        if (!programOutput.hasSelection()) {
            status.setText("Select Program Output text to copy")
            return
        }
        programOutput.copy()
        status.setText("Copied Program Output selection")
    }
    void copyAllOutput() {
        outputMenu.setVisible(false)
        programOutput.selectAll()
        programOutput.copy()
        programOutput.setCursor(1, 1)
        status.setText("Copied all Program Output")
    }
    void acceptWatch() {
        if (addWatch(watchEntry.text())) { closeWatch() }
    }
    bool addWatch(String expression) {
        expression = expression.trim()
        if (expression.equals("") || expression.length > 4096 || expressions.length >= 64) {
            watchStatus.setText("Enter a watch expression (maximum 4096 bytes, 64 watches)")
            fail("Enter a watch expression (maximum 4096 bytes, 64 watches)")
            return false }
        int i = 0
        while (i < expressions.length) {
            if ((expressions[i] as String).equals(expression)) { return true }
            i = i + 1
        }
        expressions.append(expression)
        if (loaded && !running && hasRun) { refresh() }
        else { watches.setText("Watches will be evaluated at the next stop") }
        return true
    }
    void stackClicked(int line) {
        int row = line - 1
        if (row < 0 || row >= stackFrames.length) { return }
        MiValue frame = stackFrames[row] as MiValue
        selectFrame(frame.field("level").text)
    }
    void selectFrame(String number) {
        if (!stopped()) { return }
        if (!identifier(number)) { fail("Select a stack frame")
            return }
        enqueue(format("-stack-select-frame {}", number), "frame", number)
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
        if (atStart) { status.setText(format("Stopped at start: {}", location)) }
        else { status.setText(format("Stopped: {}", location)) }
        if (selectedFrame == 0 && !stopDetail.equals("")) {
            status.setText(format("{}; {}", status.text(), stopDetail))
        }
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
        source.onLineActivated(_self().sourceLineClicked)
        Gtk.ScrolledWindow container = scroll(source)
        DebugSource document = DebugSource(path, source, container)
        document.closeAction = _self().closeSource
        source.setMarkStyle("breakpoint", "media-record-symbolic", "#f4b4b4")
        source.setMarkStyle("disabled-breakpoint", "media-record-symbolic", "#cccccc")
        sourceFiles.append(document)
        syncBreakpointMarks()
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
                if (restorePending == 0) { restoringBreakpoints = false }
                sendNext()
                controls()
                return
            }
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
        if (done.purpose.equals("execution-frame")) {
            selectedFrame = 0
            enqueue(done.expression, "execute", "")
        }
        if (done.purpose.equals("break")) { requestBreakpoints() }
        if (done.purpose.equals("loaded")) {
            loaded = true
            status.setText("Loaded. Add breakpoints, then Run.")
            restoreBreakpoints()
        }
        if (done.purpose.equals("restore-break")) {
            restorePending = restorePending - 1
            if (restorePending == 0) { restoringBreakpoints = false }
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
            if (startMissing) { status.setText("Running; Break at start unavailable (no entry symbol)") }
            else { status.setText("Running") }
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
            stackFrames = frames.values
            String text = ""
            int i = 0
            while (i < frames.values.length) {
                MiValue frame = frames.values[i] as MiValue
                text.append(format("#{} {} {}:{}\n", frame.field("level").text, frame.field("func").text,
                    frame.field("file").text, frame.field("line").text))
                i = i + 1
            }
            if (!stack.text().equals(text)) { stack.setText(text) }
        }
        if (done.purpose.equals("watch")) {
            watches.setText(format("{}{} = {}\n", watches.text(), done.expression, record.data.field("value").text))
        }
        if (done.purpose.equals("location")) {
            showLocation(record.data.field("frame"))
        }
        if (done.purpose.equals("frame")) {
            selectedFrame = done.expression.toInt()
            refresh()
        }
        if (done.purpose.equals("breaks")) {
            MiValue rows = record.data.field("BreakpointTable").field("body")
            breakpointEntries = rows.values
            breakpointRows = []
            breakpointLocations = []
            String text = ""
            bool startSeen = false
            int i = 0
            while (i < rows.values.length) {
                MiValue item = rows.values[i] as MiValue
                String number = item.field("number").text
                breakpointRows.append((number.split(".")[0] as String))
                bool enabled = !item.field("enabled").text.equals("n")
                if (number.contains(".")) {
                    String parent = number.split(".")[0] as String
                    int j = 0
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
        if (parsed.kind.equals("=") && loaded &&
            (parsed.result.equals("breakpoint-created") || parsed.result.equals("breakpoint-modified") ||
             parsed.result.equals("breakpoint-deleted"))) { requestBreakpoints() }
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
                String exitText = format("Target {}", reason)
                if (!parsed.data.field("exit-code").text.equals("")) {
                    exitText.append(format(" {}", parsed.data.field("exit-code").text))
                }
                int missed = reportUnreached()
                if (missed > 0) { exitText.append(format("; {} breakpoint(s) not reached", missed)) }
                startBreakpoint = ""
                startNumber = ""
                status.setText(exitText)
            } else {
                hasRun = true
                selectedFrame = 0
                stopCount = stopCount + 1
                MiValue frame = parsed.data.field("frame")
                String stopPath = frame.field("fullname").text
                if (stopPath.equals("")) { stopPath = frame.field("file").text }
                String position = format("{}:{} ({})", stopPath,
                    frame.field("line").text, frame.field("func").text)
                String address = frame.field("addr").text
                stopDetail = format("{}; PC {}", reason, address)
                if (position.equals(stopPosition)) {
                    stopDetail.append(format("; same source line (previous PC {})", stopAddress))
                }
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
