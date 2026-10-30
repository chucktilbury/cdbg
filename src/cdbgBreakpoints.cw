bool Cdbg.identifier(String text) {
        if (text.equals("")) { return(false) }
        int64 i = 0
        while (i < text.length) {
            if (int64(text[i]) < 48 || int64(text[i]) > 57) { return(false) }
            i = i + 1
        }
        return(true)
    }

void Cdbg.addBreakpoint(String text) {
        text = text.trim()
        if (!loaded || running || text.equals("")) { fail("Load a target and pause it before adding a breakpoint")
            return }
        enqueue(format("-break-insert {}", MiParser().quote(text)), "break", "")
        requestBreakpoints()
    }

void Cdbg.deleteBreakpoint(String number) {
        if (!loaded || running || !identifier(number)) {
            fail("Select a breakpoint while the target is stopped")
            return
        }
        enqueue(format("-break-delete {}", number), "break", "")
        requestBreakpoints()
    }

list Cdbg.lineBreakpoints(DebugSource file) {
        list ids = []
        int64 i = 0
        while (i < breakpointLocations.length) {
            DebugBreakpoint item = breakpointLocations[i] as DebugBreakpoint
            if (sameSource(item.path, file.path) && item.line.equals(format("{}", file.view.line()))) {
                bool duplicate = false
                int64 j = 0
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
                int64 j = 0
                while (j < ids.length) {
                    if ((ids[j] as String).equals(number)) { duplicate = true }
                    j = j + 1
                }
                if (!duplicate) { ids.append(number) }
            }
            i = i + 1
        }
        return(ids)
    }

void Cdbg.breakpointClicked(int64 line) {
        selectedWatch = -1
        controls()
    }

void Cdbg.watchClicked(int64 line) {
        selectedWatch = line - 1
        controls()
        String expression = rowExpression(watches, line)
        if (!expression.equals("")) { addWatch(expression) }
    }

void Cdbg.localsClicked(int64 line) {
        String expression = rowExpression(locals, line)
        if (!expression.equals("")) { addWatch(expression) }
    }

String Cdbg.rowExpression(GtkSource.View view, int64 line) {
        if (view == null || line < 1) { return("") }
        list rows = view.text().split("\n")
        if (line > rows.length) { return("") }
        String row = (rows[line - 1] as String).trim()
        if (row.equals("") || row.startsWith("Locals") || row.startsWith("Watches") ||
            row.startsWith("(") || row.startsWith("<")) { return("") }
        int64 i = 0
        int64 eq = -1
        while (i + 2 < row.length) {
            if (row[i] == 32u && row[i + 1] == 61u && row[i + 2] == 32u) {
                eq = i
                i = row.length
            } else { i = i + 1 }
        }
        if (eq < 1) { return("") }
        return(row[0..(eq - 1)].trim())
    }

String Cdbg.rowFriendly(GtkSource.View view, int64 line) {
        if (view == null || line < 1) { return("") }
        list rows = view.text().split("\n")
        if (line > rows.length) { return("") }
        String row = (rows[line - 1] as String).trim()
        int64 i = 0
        int64 eq = -1
        while (i + 2 < row.length) {
            if (row[i] == 32u && row[i + 1] == 61u && row[i + 2] == 32u) {
                eq = i
                i = row.length
            } else { i = i + 1 }
        }
        if (eq < 0 || eq + 3 >= row.length) { return(row) }
        return(row[(eq + 3)..(row.length - 1)].trim())
    }

void Cdbg.watchSymbolFromLocals() {
        String expression = rowExpression(locals, locals.line())
        if (expression.equals("")) {
            status.setText("Select a local row with a name = value")
            return
        }
        addWatch(expression)
    }

void Cdbg.watchSymbolFromWatches() {
        String expression = rowExpression(watches, watches.line())
        if (expression.equals("")) {
            status.setText("Select a watch row with a name = value")
            return
        }
        addWatch(expression)
    }

void Cdbg.copyLocalsFriendly() { copyFriendlyFrom(locals) }
void Cdbg.copyWatchFriendly() { copyFriendlyFrom(watches) }

void Cdbg.copyFriendlyFrom(GtkSource.View view) {
        if (view == null) { return }
        int64 line = view.line()
        String text = rowFriendly(view, line)
        if (text.equals("")) {
            status.setText("Select a value row to copy")
            return
        }
        String previous = view.text()
        view.setText(text)
        view.selectAll()
        view.copy()
        view.setText(previous)
        if (line > 0) { view.centerCursor(line, 1) }
        status.setText("Copied friendly value")
    }

void Cdbg.deleteSelectedWatch() {
        if (selectedWatch < 0 || selectedWatch >= expressions.length) {
            status.setText("Select a watch to delete")
            return
        }
        list kept = []
        int64 i = 0
        while (i < expressions.length) {
            if (i != selectedWatch) { kept.append(expressions[i] as String) }
            i = i + 1
        }
        expressions = kept
        selectedWatch = -1
        saveState(false)
        if (loaded && !running && hasRun) { refresh() }
        else { watches.setText("Watches will be evaluated at the next stop") }
    }

String Cdbg.selectedBreakpointNumber() {
        int64 row = breaks.line() - 1
        if (row < 0 || row >= breakpointRows.length) { return("") }
        return(breakpointRows[row] as String)
    }

void Cdbg.disableSelectedBreakpoint() {
        String number = selectedBreakpointNumber()
        if (number.equals("") || !identifier(number)) {
            status.setText("Select a breakpoint to disable")
            return
        }
        if (!breakpointReady()) { return }
        enqueue(format("-break-disable {}", number), "break", "")
        requestBreakpoints()
    }

void Cdbg.enableSelectedBreakpoint() {
        String number = selectedBreakpointNumber()
        if (number.equals("") || !identifier(number)) {
            status.setText("Select a breakpoint to enable")
            return
        }
        if (!breakpointReady()) { return }
        enqueue(format("-break-enable {}", number), "break", "")
        requestBreakpoints()
    }

void Cdbg.deleteSelectedBreakpoint() {
        String number = selectedBreakpointNumber()
        if (number.equals("") || !identifier(number)) {
            status.setText("Select a breakpoint to delete")
            return
        }
        deleteBreakpoint(number)
    }

bool Cdbg.breakpointReady() {
        if (!loaded || running || active != null || requests.length > 0 || currentSource() == null) {
            status.setText("Load a target, pause it, and select a source file before changing breakpoints")
            return(false)
        }
        return(true)
    }

void Cdbg.toggleBreakpoint() {
        if (!breakpointReady()) { return }
        DebugSource file = currentSource()
        list ids = lineBreakpoints(file)
        if (ids.length == 0) { addBreakpoint(format("{}:{}", file.path, file.view.line()))
            return }
        int64 i = 0
        while (i < ids.length) { deleteBreakpoint(ids[i] as String)
            i = i + 1 }
    }

void Cdbg.toggleEnabled() {
        if (!breakpointReady()) { return }
        list ids = lineBreakpoints(currentSource())
        if (ids.length == 0) { status.setText("No breakpoint at the current source line")
            return }
        bool enabled = false
        int64 i = 0
        while (i < breakpointLocations.length) {
            DebugBreakpoint point = breakpointLocations[i] as DebugBreakpoint
            int64 j = 0
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

void Cdbg.requestBreakpoints() {
        if (active != null && active.purpose.equals("breaks")) { return }
        int64 i = 0
        while (i < requests.length) {
            if ((requests[i] as DebugRequest).purpose.equals("breaks")) { return }
            i = i + 1
        }
        enqueue("-break-list", "breaks", "")
    }

bool Cdbg.sameSource(String path, String file) {
        if (path.equals("")) { return(false) }
        if (System.FileSystem().absolutePath(path).equals(file)) { return(true) }
        return(!path.contains("/") && System.FileSystem().basename(file).equals(path))
    }

void Cdbg.syncBreakpointMarks() {
        if (window == null || window.disposed()) { return }
        int64 i = 0
        while (i < sourceFiles.length) {
            DebugSource file = sourceFiles[i] as DebugSource
            file.view.clearLineMarks("breakpoint")
            file.view.clearLineMarks("disabled-breakpoint")
            int64 j = 0
            while (j < breakpointLocations.length) {
                DebugBreakpoint point = breakpointLocations[j] as DebugBreakpoint
                if (sameSource(point.path, file.path) && identifier(point.line) && point.line.toInt64() > 0) {
                    String category = "disabled-breakpoint"
                    if (point.enabled) { category = "breakpoint" }
                    file.view.addLineMark(category, point.line.toInt64())
                }
                j = j + 1
            }
            i = i + 1
        }
    }

void Cdbg.breakpointLocation(MiValue item, String parent, bool enabled) {
        String number = item.field("number").text
        if (parent.equals("")) { parent = (number.split(".")[0] as String) }
        if (item.field("enabled").text.equals("n")) { enabled = false }
        String path = item.field("fullname").text
        if (path.equals("")) { path = item.field("file").text }
        String line = item.field("line").text
        if (!path.equals("") && identifier(line)) {
            DebugBreakpoint point = DebugBreakpoint(parent, path, line, enabled)
            point.condition = item.field("cond").text
            if (identifier(item.field("ignore").text)) {
                point.ignoreCount = item.field("ignore").text.toInt64()
            }
            breakpointLocations.append(point)
        }
        MiValue locations = item.field("locations")
        int64 i = 0
        while (i < locations.values.length) {
            breakpointLocation(locations.values[i] as MiValue, parent, enabled)
            i = i + 1
        }
    }

// Pending breakpoints have no code yet; installed ones show the function
// and hit count so a breakpoint in code that never runs is visible.
String Cdbg.breakpointSummary(MiValue item, bool enabled) {
        String state = "enabled"
        if (!enabled) { state = "disabled" }
        if (item.field("pending").text.length > 0) {
            return(format("{} pending {} (not yet installed)", state, item.field("pending").text))
        }
        String where = format("{}:{}", item.field("file").text, item.field("line").text)
        if (item.field("addr").text.equals("<MULTIPLE>")) {
            where = format("{} (multiple locations)", item.field("original-location").text)
        }
        String text = format("{} installed {}", state, where)
        if (!item.field("func").text.equals("")) { text.append(format(" in {}", item.field("func").text)) }
        text.append(format(" hits {}", item.field("times").text))
        if (!item.field("cond").text.equals("")) {
            text.append(format(" if {}", item.field("cond").text))
        }
        if (identifier(item.field("ignore").text) && item.field("ignore").text.toInt64() > 0) {
            text.append(format(" ignore {}", item.field("ignore").text))
        }
        return(text)
    }

void Cdbg.showBreakpointCondition() {
        String number = selectedBreakpointNumber()
        if (number.equals("") || !identifier(number)) {
            status.setText("Select a breakpoint to edit its condition")
            return
        }
        if (!breakpointReady()) { return }
        breakMenu.setVisible(false)
        conditionNumber = number
        conditionEntry.setText(breakpointField(number, "cond"))
        conditionStatus.setText("")
        conditionWindow.setVisible(true)
        conditionWindow.present()
        conditionEntry.focus()
    }

void Cdbg.showBreakpointHitCount() {
        String number = selectedBreakpointNumber()
        if (number.equals("") || !identifier(number)) {
            status.setText("Select a breakpoint to edit its hit count")
            return
        }
        if (!breakpointReady()) { return }
        breakMenu.setVisible(false)
        hitCountNumber = number
        hitCountEntry.setText(breakpointField(number, "ignore"))
        hitCountStatus.setText("")
        hitCountWindow.setVisible(true)
        hitCountWindow.present()
        hitCountEntry.focus()
    }

String Cdbg.breakpointField(String number, String name) {
        int64 i = 0
        while (i < breakpointEntries.length) {
            MiValue item = breakpointEntries[i] as MiValue
            if (item.field("number").text.equals(number) ||
                (item.field("number").text.split(".")[0] as String).equals(number)) {
                return(item.field(name).text)
            }
            i = i + 1
        }
        return("")
    }

void Cdbg.acceptBreakpointCondition() {
        String expression = conditionEntry.text().trim()
        if (expression.length > 1024) {
            conditionStatus.setText("Condition must be at most 1024 bytes")
            return
        }
        if (conditionNumber.equals("")) { return }
        if (expression.equals("")) {
            enqueue(format("-break-condition {}", conditionNumber), "break", "")
        } else {
            enqueue(format("-break-condition {} {}", conditionNumber, MiParser().quote(expression)),
                "break", "")
        }
        requestBreakpoints()
        conditionWindow.setVisible(false)
    }

void Cdbg.acceptBreakpointHitCount() {
        String text = hitCountEntry.text().trim()
        if (text.equals("")) { text = "0" }
        if (!identifier(text) || text.toInt64() < 0 || text.toInt64() > 1000000) {
            hitCountStatus.setText("Hit count ignore must be an integer from 0 to 1000000")
            return
        }
        if (hitCountNumber.equals("")) { return }
        enqueue(format("-break-after {} {}", hitCountNumber, text), "break", "")
        requestBreakpoints()
        hitCountWindow.setVisible(false)
    }

void Cdbg.closeBreakpointCondition() { conditionWindow.setVisible(false) }
bool Cdbg.conditionCloseRequested() { closeBreakpointCondition()
        return(true) }
void Cdbg.closeBreakpointHitCount() { hitCountWindow.setVisible(false) }
bool Cdbg.hitCountCloseRequested() { closeBreakpointHitCount()
        return(true) }

// Lists enabled breakpoints whose hit count did not change during the run.
int64 Cdbg.reportUnreached() {
        int64 count = 0
        int64 i = 0
        while (i < breakpointEntries.length) {
            MiValue entry = breakpointEntries[i] as MiValue
            String number = entry.field("number").text
            String key = format("{}={}", number, entry.field("times").text)
            bool same = false
            int64 j = 0
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
        return(count)
    }
