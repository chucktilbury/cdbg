import gtk
import sourceview
import system
include "mi.cw"

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

class Cdbg {
    Cdbg _self()
    Gtk.Window window
    Gtk.Entry target
    Gtk.Entry breakpoint
    Gtk.Entry breakpointNumber
    Gtk.Entry watch
    Gtk.Entry frameNumber
    Gtk.Label status
    GtkSource.View source
    GtkSource.View locals
    GtkSource.View stack
    GtkSource.View watches
    GtkSource.View breaks
    GtkSource.View console
    Gtk.Button runButton
    Gtk.Button stepButton
    Gtk.Button nextButton
    Gtk.Button finishButton
    Gtk.Button interruptButton
    Gtk.Button restartButton
    Process.AsyncProcess process
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
        Gtk.Box launchRow = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        layout.append(launchRow)
        launchRow.append(Gtk.Label("Source (.cw) or executable"))
        target = Gtk.Entry("")
        target.setHExpand(true)
        launchRow.append(target)
        button(launchRow, "Load", _self().launch)
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
        body.append(scroll(source))
        Gtk.Notebook inspection = Gtk.Notebook()
        inspection.setHExpand(true)
        inspection.setVExpand(true)
        body.append(inspection)
        locals = pane()
        stack = pane()
        watches = pane()
        breaks = pane()
        console = pane()
        inspection.appendPage(scroll(locals), "Locals / Arguments")
        inspection.appendPage(scroll(stack), "Stack")
        inspection.appendPage(scroll(watches), "Watches")
        inspection.appendPage(scroll(breaks), "Breakpoints")
        inspection.appendPage(scroll(console), "Console")
        status = Gtk.Label("Load a local target. GDB only; no attach/remote or LLDB yet.")
        layout.append(status)
        controls()
        window.present()
        if (System.Process().argc() > 1) {
            target.setText(System.Process().arg(1))
            int i = 2
            if (System.Process().arg(i).equals("--")) { i = i + 1 }
            while (i < System.Process().argc()) {
                arguments.append(System.Process().arg(i))
                i = i + 1
            }
            launch()
        }
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
    void log(String text) {
        String current = console.text()
        current.append(text)
        if (current.length > 65536) { current = current.slice(current.length - 65536, current.length) }
        console.setText(current)
    }
    void fail(String text) {
        failure = text
        System.StandardIO().writeErrorLine(format("cdbg: {}", text))
        if (window != null && !window.disposed()) {
            status.setText(format("Error: {}", text))
            log(format("Error: {}\n", text))
        }
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
        endSession()
        return false
    }
    void launch() {
        endSession()
        failure = ""
        stopCount = 0
        inferiorPid = ""
        location = ""
        executable = System.FileSystem().absolutePath(target.text())
        source.setText("")
        if (!System.FileSystem().isFile(executable)) { fail("Target is not a local file")
            return }
        output = Process.OutputDecoder()
        errors = Process.OutputDecoder()
        pending = ""
        console.setText("")
        locals.setText("")
        stack.setText("")
        watches.setText("")
        breaks.setText("")
        if (executable.endsWith(".cw")) {
            String input = executable
            showSource(input, "")
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
            return
        }
        pollToken = Gtk.Application().post(_self().poll)
    }
    void startDebugger() {
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
        showSource(path, line)
    }
    void showSource(String path, String line) {
        if (!path.equals("") && System.FileSystem().isFile(path)) {
            try {
                System.File file = System.File(path, "r")
                String text = file.readAll()
                file.close()
                source.setText(text)
                source.setLanguage(GtkSource.Content().languageFor(path))
                if (identifier(line) && line.toInt() > 0) { source.setCursor(line.toInt(), 1) }
            } except(Exception) as err { fail(format("Could not display source {}: {}", path, err.message)) }
        } else { source.setText(format("Source unavailable: {}", path)) }
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
                fail(message)
                if (done.purpose.equals("setup") || done.purpose.equals("target") ||
                    done.purpose.equals("loaded")) {
                    requests = []
                    loaded = false
                }
            }
            sendNext()
            controls()
            return
        }
        if (done.purpose.equals("loaded")) {
            loaded = true
            status.setText("Loaded. Add breakpoints, then Run.")
        }
        if (done.purpose.equals("sources") && source.text().equals("")) {
            MiValue files = record.data.field("files")
            String candidate = ""
            int i = 0
            while (i < files.values.length) {
                MiValue file = files.values[i] as MiValue
                String path = file.field("fullname").text
                if (path.equals("")) { path = file.field("file").text }
                if (System.FileSystem().isFile(path)) {
                    if (candidate.equals("")) { candidate = path }
                    if (path.endsWith(".cw") && !path.contains("/modules/") &&
                        !path.contains("/builtin/")) { candidate = path
                        break }
                }
                i = i + 1
            }
            if (!candidate.equals("")) { showSource(candidate, "") }
            else { source.setText("Source unavailable: no readable source files in debug information") }
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
        if (parsed.kind.equals("~") || parsed.kind.equals("@") || parsed.kind.equals("&")) {
            log(parsed.data.text)
        }
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
                    if (!success) { fail("Cwhip -g compilation failed; see Console")
                        cleanup()
                        return }
                    startDebugger()
                    if (!process.started()) { process.close()
                        process = null
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
