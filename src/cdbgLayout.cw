void Cdbg.buildInspectionLayout(Gtk.Paned host) {
        rightColumn = Gtk.Box(Gtk.Box.VERTICAL, 4)
        rightColumn.setHExpand(true)
        rightColumn.setVExpand(true)
        host.append(rightColumn)
        topInspection = Gtk.Notebook()
        topInspection.setBorderedTabs()
        topInspection.setScrollable(true)
        topInspection.setHExpand(true)
        topInspection.setVExpand(true)
        midInspection = Gtk.Notebook()
        midInspection.setBorderedTabs()
        midInspection.setScrollable(true)
        midInspection.setHExpand(true)
        midInspection.setVExpand(true)
        bottomRow = Gtk.Paned()
        bottomRow.setHExpand(true)
        bottomRow.setVExpand(true)
        bottomRow.setPosition(400)
        rightColumn.append(topInspection)
        rightColumn.append(midInspection)
        rightColumn.append(bottomRow)
        locals = pane()
        watches = pane()
        runtimeValues = pane()
        stack = pane()
        breaks = pane()
        console = pane()
        programOutput = pane()
        localsScroll = scroll(locals)
        watchesScroll = scroll(watches)
        runtimeScroll = scroll(runtimeValues)
        stackScroll = scroll(stack)
        breaksScroll = scroll(breaks)
        outputNotebook = Gtk.Notebook()
        outputNotebook.setBorderedTabs()
        outputNotebook.setScrollable(true)
        outputNotebook.setHExpand(true)
        outputNotebook.setVExpand(true)
        consoleNotebook = Gtk.Notebook()
        consoleNotebook.setBorderedTabs()
        consoleNotebook.setScrollable(true)
        consoleNotebook.setHExpand(true)
        consoleNotebook.setVExpand(true)
        outputScroll = scroll(programOutput)
        consoleScroll = scroll(console)
        bottomRow.append(outputNotebook)
        bottomRow.append(consoleNotebook)
        stack.setLineSelection(true)
        stack.onLineActivated(_self().stackClicked)
        breaks.setLineSelection(true)
        breaks.onLineActivated(_self().breakpointClicked)
        breakMenu = Gtk.ContextMenu(breaks.widget())
        disableBreakItem = breakMenu.addItem("Disable Breakpoint", _self().disableSelectedBreakpoint)
        enableBreakItem = breakMenu.addItem("Enable Breakpoint", _self().enableSelectedBreakpoint)
        breakMenu.addItem("Edit Condition...", _self().showBreakpointCondition)
        breakMenu.addItem("Hit Count...", _self().showBreakpointHitCount)
        deleteBreakItem = breakMenu.addItem("Delete Breakpoint", _self().deleteSelectedBreakpoint)
        watches.setLineSelection(true)
        watches.onLineActivated(_self().watchClicked)
        watchMenu = Gtk.ContextMenu(watches.widget())
        watchMenu.addItem("Add Watch...", _self().showWatch)
        deleteWatchItem = watchMenu.addItem("Delete Watch", _self().deleteSelectedWatch)
        outputMenu = Gtk.ContextMenu(programOutput.widget())
        outputMenu.addItem("Clear", _self().clearOutput)
        outputMenu.addItem("Copy", _self().copyOutput)
        outputMenu.addItem("Copy All", _self().copyAllOutput)
        showLocals = true
        showWatches = true
        showStack = true
        showBreaks = true
        showOutput = true
        showConsole = true
        showRuntime = false
        localsAttached = false
        watchesAttached = false
        runtimeAttached = false
        stackAttached = false
        breaksAttached = false
        outputAttached = false
        consoleAttached = false
        syncInspectionPages()
    }

void Cdbg.addViewMenu() {
        int64 viewMenu = menu.addMenu("View")
        viewLocalsItem = menu.addCheckItem(viewMenu, "Locals / Arguments", showLocals, _self().viewLocalsChecked)
        viewWatchesItem = menu.addCheckItem(viewMenu, "Watches", showWatches, _self().viewWatchesChecked)
        viewStackItem = menu.addCheckItem(viewMenu, "Stack", showStack, _self().viewStackChecked)
        viewBreaksItem = menu.addCheckItem(viewMenu, "Breakpoints", showBreaks, _self().viewBreaksChecked)
        viewOutputItem = menu.addCheckItem(viewMenu, "Program Output", showOutput, _self().viewOutputChecked)
        viewConsoleItem = menu.addCheckItem(viewMenu, "Debugger Console", showConsole, _self().viewConsoleChecked)
        viewRuntimeItem = menu.addCheckItem(viewMenu, "Runtime Values", showRuntime, _self().viewRuntimeChecked)
    }

void Cdbg.viewLocalsChecked(bool active) { setPanelVisible("locals", active) }
void Cdbg.viewWatchesChecked(bool active) { setPanelVisible("watches", active) }
void Cdbg.viewStackChecked(bool active) { setPanelVisible("stack", active) }
void Cdbg.viewBreaksChecked(bool active) { setPanelVisible("breaks", active) }
void Cdbg.viewOutputChecked(bool active) { setPanelVisible("output", active) }
void Cdbg.viewConsoleChecked(bool active) { setPanelVisible("console", active) }
void Cdbg.viewRuntimeChecked(bool active) { setPanelVisible("runtime", active) }

void Cdbg.setPanelVisible(String name, bool active) {
        if (name.equals("locals")) { showLocals = active }
        if (name.equals("watches")) { showWatches = active }
        if (name.equals("stack")) { showStack = active }
        if (name.equals("breaks")) { showBreaks = active }
        if (name.equals("output")) { showOutput = active }
        if (name.equals("console")) { showConsole = active }
        if (name.equals("runtime")) { showRuntime = active }
        syncInspectionPages()
        syncViewMenuChecks()
    }

void Cdbg.togglePanel(String name) {
        if (name.equals("locals")) { setPanelVisible(name, !showLocals) }
        if (name.equals("watches")) { setPanelVisible(name, !showWatches) }
        if (name.equals("stack")) { setPanelVisible(name, !showStack) }
        if (name.equals("breaks")) { setPanelVisible(name, !showBreaks) }
        if (name.equals("output")) { setPanelVisible(name, !showOutput) }
        if (name.equals("console")) { setPanelVisible(name, !showConsole) }
        if (name.equals("runtime")) { setPanelVisible(name, !showRuntime) }
    }

void Cdbg.syncViewMenuChecks() {
        if (menu == null) { return }
        menu.setItemChecked(viewLocalsItem, showLocals)
        menu.setItemChecked(viewWatchesItem, showWatches)
        menu.setItemChecked(viewStackItem, showStack)
        menu.setItemChecked(viewBreaksItem, showBreaks)
        menu.setItemChecked(viewOutputItem, showOutput)
        menu.setItemChecked(viewConsoleItem, showConsole)
        menu.setItemChecked(viewRuntimeItem, showRuntime)
    }

void Cdbg.syncPage(Gtk.Notebook notebook, Gtk.ScrolledWindow item, String title, bool want,
                   bool attached) {
        // Caller updates the attached flag after this returns via syncInspectionPages.
        if (want && !attached) { notebook.appendPage(item, title) }
        if (!want && attached) { notebook.remove(item) }
    }

void Cdbg.syncInspectionPages() {
        if (showLocals != localsAttached) {
            syncPage(topInspection, localsScroll, "Locals / Arguments (Cwhip / Native)",
                showLocals, localsAttached)
            localsAttached = showLocals
        }
        if (showWatches != watchesAttached) {
            syncPage(topInspection, watchesScroll, "Watches (Cwhip / Native)",
                showWatches, watchesAttached)
            watchesAttached = showWatches
        }
        if (showRuntime != runtimeAttached) {
            syncPage(topInspection, runtimeScroll, "Runtime Values", showRuntime, runtimeAttached)
            runtimeAttached = showRuntime
        }
        if (showStack != stackAttached) {
            syncPage(midInspection, stackScroll, "Stack", showStack, stackAttached)
            stackAttached = showStack
        }
        if (showBreaks != breaksAttached) {
            syncPage(midInspection, breaksScroll, "Breakpoints", showBreaks, breaksAttached)
            breaksAttached = showBreaks
        }
        if (showOutput != outputAttached) {
            syncPage(outputNotebook, outputScroll, "Program Output", showOutput, outputAttached)
            outputAttached = showOutput
        }
        if (showConsole != consoleAttached) {
            syncPage(consoleNotebook, consoleScroll, "Debugger Console", showConsole, consoleAttached)
            consoleAttached = showConsole
        }
        topInspection.setVisible(topInspection.pageCount() > 0)
        midInspection.setVisible(midInspection.pageCount() > 0)
        outputNotebook.setVisible(showOutput)
        consoleNotebook.setVisible(showConsole)
        bottomRow.setVisible(showOutput || showConsole)
        rightColumn.setVisible(topInspection.visible() || midInspection.visible() || bottomRow.visible())
    }
