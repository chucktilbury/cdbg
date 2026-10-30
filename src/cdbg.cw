import gtk
import sourceview
import system
include "mi.cw"
include "terminal.cw"
include "debugTypes.cw"

class Cdbg {
    Cdbg _self()
    Gtk.Window window
    Gtk.MenuBar menu
    int64 loadItem
    int64 openItem
    int64 quitItem
    int64 findItem
    Gtk.FileDialog fileDialog
    Gtk.TransientWindow findWindow
    Gtk.Entry findEntry
    Gtk.Label findStatus
    String targetPath
    String sourceText
    int64 toggleBreakItem
    int64 toggleEnableItem
    int64 setupItem
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
    int64 restorePending
    Gtk.ContextMenu watchMenu
    Gtk.TransientWindow watchWindow
    Gtk.Entry watchEntry
    Gtk.Label watchStatus
    list breakpointRows
    list breakpointEntries
    list breakpointLocations
    list stackFrames
    int64 selectedFrame
    bool executing
    int64 skipRuntimeLeft
    int64 skippedRuntimeFrames
    String skipOrigin
    // After Step Over, GDB can stop again on the same source line at a later
    // PC (mid-line after a call return). Keep nexting until the line changes.
    int64 skipSameLineLeft
    int64 skippedSameLineStops
    // Newly opened source tabs are not allocated yet; center/focus after idle.
    int64 pendingRevealLine
    int64 pendingRevealTries
    bool rebuildPendingRun
    bool rebuildBreakAtStart
    bool preferCwhipStops
    list pendingWatchRestore
    int64 selectedWatch
    int64 deleteWatchItem
    int64 disableBreakItem
    int64 enableBreakItem
    int64 deleteBreakItem
    Gtk.ContextMenu breakMenu
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
    GtkSource.View runtimeValues
    String runtimeLocals
    String runtimeWatches
    bool valueInspector
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
    int64 sequence
    int64 mode
    int64 pollToken
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
    int64 stopCount

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
        skipRuntimeLeft = 0
        skippedRuntimeFrames = 0
        skipOrigin = ""
        skipSameLineLeft = 0
        skippedSameLineStops = 0
        rebuildPendingRun = false
        rebuildBreakAtStart = true
        preferCwhipStops = false
        pendingWatchRestore = []
        selectedWatch = -1
        deleteWatchItem = 0
        disableBreakItem = 0
        enableBreakItem = 0
        deleteBreakItem = 0
    }
    Gtk.Button button(Gtk.Box row, String title, void<> action)

    GtkSource.View pane()

    Gtk.ScrolledWindow scroll(GtkSource.View view)

    void activate()

    String initialPath()

    void chooseExecutable()

    void chooseSource()

    void executableChosen(String path)

    void sourceChosen(String path)

    void quit()

    void loadTarget(String path)

    bool openSource(String path)

    bool executableImage(String path)

    void showFind()

    void closeFind()

    bool findCloseRequested()

    void findNext()

    void findPrevious()

    void find(bool backward)

    void stateDiagnostic(String text)

    int64 stateNumber(String key, int64 fallback, int64 minimum, int64 maximum)

    void readState()

    bool savedFlag(String table, String key, bool fallback)

    void loadTargetSettings()

    void saveState(bool layout)

    void saveError(String error)

    void restoreBreakpoints()

    void restoreWatches()

    void maybeRebuildRun()

    void clearSources()

    void sourceMessage(String text)

    void removeSourcePage(DebugSource file)

    void removeMessagePage()

    void closeSource(DebugSource file)

    String compiler()

    void cleanup()

    void endSession()

    bool closeRequested()

    void launch()

    void startDebugger()

    void enqueue(String command, String purpose, String expression)

    void sendNext()

    String processOutcome()

    bool stopped()

    void resume()

    void startRun()

    void restart()

    void restartWithRebuild()

    void restartStopped()

    void execute(String command, String label)

    void stepInto()

    void stepOver()

    void stepOut()

    bool cwhipFrame(String path)

    bool openableSource(String path)

    bool runtimePrologue(String func)

    bool skipRuntimeStop(String path, String func, String position, String reason)

    bool skipSameLineStop(String position, String reason)

    void interrupt()

    bool identifier(String text)

    void addBreakpoint(String text)

    list lineBreakpoints(DebugSource file)

    void deleteBreakpoint(String number)

    void breakpointClicked(int64 line)

    void watchClicked(int64 line)

    void deleteSelectedWatch()

    String selectedBreakpointNumber()

    void disableSelectedBreakpoint()

    void enableSelectedBreakpoint()

    void deleteSelectedBreakpoint()

    bool breakpointReady()

    void toggleBreakpoint()

    void toggleEnabled()

    void requestBreakpoints()

    bool sameSource(String path, String file)

    void syncBreakpointMarks()

    void breakpointLocation(MiValue item, String parent, bool enabled)

    String breakpointSummary(MiValue item, bool enabled)

    int64 reportUnreached()

    void showWatch()

    void closeWatch()

    bool watchCloseRequested()

    void showSetup()

    void closeSetup()

    bool setupCloseRequested()

    void applySetup()

    void clearOutput()

    void copyOutput()

    void copyAllOutput()

    void acceptWatch()

    bool addWatch(String expression)

    void stackClicked(int64 line)

    void selectFrame(String number)

    bool inspection(DebugRequest request)

    void refresh()

    void updateRuntimeValues()

    void showLocation(MiValue frame)

    void revealPendingSource()

    bool readText(String path)

    bool readableText(String path)

    bool showSource(String path, String line)

    void response(MiParser record)

    void record(String line)

    void consume(String chunk)

    void poll()

    DebugSource currentSource()

    void sourceChanged()

    void sourceLineClicked(int64 line)

    void controls()

    String outputHistory(String previous, String text)

    void log(String text)

    void programLog(String text)

    void readProgramOutput()

    void ignored(String text)

    void fail(String text)

    void failWith(String code, String text)

    void loadFailure(String text)

    void fileFailure(String code, String text)

    int64 byteSpanBound(int64 value, int64 length)

    String byteSpan(String text, int64 first, int64 last)
}

include "cdbgActivate.cw"
include "cdbgTarget.cw"
include "cdbgFind.cw"
include "cdbgState.cw"
include "cdbgSession.cw"
include "cdbgExecution.cw"
include "cdbgBreakpoints.cw"
include "cdbgWatches.cw"
include "cdbgSource.cw"
include "cdbgGdb.cw"
include "cdbgUi.cw"

Cdbg Cdbg._self() from "cwhip_gtk_self"

start {
    String target = System.Process().arg(1)
    if ((target.equals("--help") && System.Process().argc() != 2) ||
        (target.startsWith("-") && !target.equals("--help"))) {
        DebugDiagnostic().emit("error", "CDBG0001",
            format("Unexpected option {}; use cdbg --help for usage (prefix a target beginning with '-' with ./)", target))
        System.Process().exit(2)
    }
    if (target.equals("--help")) {
        print("Usage: cdbg [SOURCE.cw|EXECUTABLE [-- ARGS...]]\nLocal GDB/MI GTK prototype. Sources compile with -g. No LLDB, remote, or attach.\n")
    } else {
        if (System.Process().argc() > 1 && !System.FileSystem().isFile(target)) {
            DebugDiagnostic().emit("error", "CDBG1001",
                format("Target is not a local file: {}; choose an existing source or executable file", target))
            System.Process().exit(1)
        }
        Gtk.Application app = Gtk.Application("org.cwhip.Cdbg")
        Cdbg debugger = Cdbg()
        app.onActivate(debugger.activate)
        app.run()
        debugger.endSession()
    }
}
