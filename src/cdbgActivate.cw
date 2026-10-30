Gtk.Button Cdbg.button(Gtk.Box row, String title, void<> action) {
        Gtk.Button item = Gtk.Button(title)
        item.onClicked(action)
        row.append(item)
        return(item)
    }

Gtk.Button Cdbg.toolbarButton(Gtk.Box row, String title, void<> action) {
        Gtk.Button item = Gtk.Button(title)
        // Keep focus in the source pane; a focusable toolbar button makes the
        // first mouse press only focus the control instead of stepping.
        item.setCanFocus(false)
        item.setFocusOnClick(false)
        item.onClicked(action)
        row.append(item)
        return(item)
    }

GtkSource.View Cdbg.pane() {
        GtkSource.View view = GtkSource.View()
        view.configure(settings.fontFamily, settings.fontSize, settings.tabWidth, true,
            settings.lineNumbers, false, true)
        view.setEmojiMenu(false)
        view.setEditable(false)
        view.widget().setHExpand(true)
        view.widget().setVExpand(true)
        return(view)
    }

Gtk.ScrolledWindow Cdbg.scroll(GtkSource.View view) {
        Gtk.ScrolledWindow item = Gtk.ScrolledWindow()
        item.setChild(view.widget())
        item.setHExpand(true)
        item.setVExpand(true)
        return(item)
    }

void Cdbg.activate() {
        if (window != null && !window.disposed()) { window.present()
            return }
        window = Gtk.Window("cdbg - local GDB prototype")
        window.setDefaultSize(1100, 760)
        // Menu lives in the content box, not the application menubar; keep F10
        // for Step Over instead of GTK's default menubar accelerator.
        window.setMenubarAccel(false)
        window.onCloseRequest(_self().closeRequested)
        Gtk.Box layout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        window.setChild(layout)
        menu = Gtk.MenuBar()
        layout.append(menu)
        int64 fileMenu = menu.addMenu("File")
        loadItem = menu.addItem(fileMenu, "Load Executable...", _self().chooseExecutable)
        openItem = menu.addItem(fileMenu, "Open Source Code...", _self().chooseSource)
        menu.addSeparator(fileMenu)
        quitItem = menu.addItem(fileMenu, "Quit", _self().quit)
        int64 editMenu = menu.addMenu("Edit")
        preferencesItem = menu.addItem(editMenu, "Preferences...", _self().showPreferences)
        setupItem = preferencesItem
        int64 searchMenu = menu.addMenu("Search")
        findItem = menu.addItem(searchMenu, "Find...", _self().showFind)
        addViewMenu()
        int64 breakpointMenu = menu.addMenu("Breakpoint")
        toggleBreakItem = menu.addItem(breakpointMenu, "Set/Clear Breakpoint", _self().toggleBreakpoint)
        toggleEnableItem = menu.addItem(breakpointMenu, "Enable/Disable Breakpoint", _self().toggleEnabled)
        bindCommands()
        rebindShortcuts()
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
        runButton = toolbarButton(control, "Run / Continue", _self().resume)
        restartButton = toolbarButton(control, "Restart", _self().restart)
        stepButton = toolbarButton(control, "Step Into", _self().stepInto)
        nextButton = toolbarButton(control, "Step Over", _self().stepOver)
        finishButton = toolbarButton(control, "Step Out", _self().stepOut)
        interruptButton = toolbarButton(control, "Pause", _self().interrupt)
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
        buildInspectionLayout(body)
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
        conditionWindow = Gtk.TransientWindow("Breakpoint Condition")
        conditionWindow.setTransientFor(window)
        conditionWindow.setDefaultSize(420, 100)
        conditionWindow.setVisible(false)
        conditionWindow.onCloseRequest(_self().conditionCloseRequested)
        Gtk.Box conditionLayout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        conditionWindow.setChild(conditionLayout)
        conditionLayout.append(Gtk.Label("Stop only when this expression is true (empty clears)"))
        conditionEntry = Gtk.Entry("")
        conditionLayout.append(conditionEntry)
        conditionStatus = Gtk.Label("")
        conditionLayout.append(conditionStatus)
        Gtk.Box conditionButtons = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        conditionLayout.append(conditionButtons)
        button(conditionButtons, "Apply", _self().acceptBreakpointCondition)
        button(conditionButtons, "Cancel", _self().closeBreakpointCondition)
        hitCountWindow = Gtk.TransientWindow("Breakpoint Hit Count")
        hitCountWindow.setTransientFor(window)
        hitCountWindow.setDefaultSize(420, 100)
        hitCountWindow.setVisible(false)
        hitCountWindow.onCloseRequest(_self().hitCountCloseRequested)
        Gtk.Box hitLayout = Gtk.Box(Gtk.Box.VERTICAL, 6)
        hitCountWindow.setChild(hitLayout)
        hitLayout.append(Gtk.Label("Ignore this many hits before stopping (0 = every time)"))
        hitCountEntry = Gtk.Entry("0")
        hitLayout.append(hitCountEntry)
        hitCountStatus = Gtk.Label("")
        hitLayout.append(hitCountStatus)
        Gtk.Box hitButtons = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        hitLayout.append(hitButtons)
        button(hitButtons, "Apply", _self().acceptBreakpointHitCount)
        button(hitButtons, "Cancel", _self().closeBreakpointHitCount)
        conditionNumber = ""
        hitCountNumber = ""
        status = Gtk.Label("Load a local target. GDB only; no attach/remote or LLDB yet.")
        layout.append(status)
        readState()
        applyAppearance()
        controls()
        window.present()
        if (System.Process().argc() > 1) {
            int64 i = 2
            if (System.Process().arg(i).equals("--")) { i = i + 1 }
            while (i < System.Process().argc()) {
                cliArguments.append(System.Process().arg(i))
                i = i + 1
            }
            cliPending = cliArguments.length > 0
            loadTarget(System.Process().arg(1))
        }
    }

void Cdbg.bindCommands() {
        settings.command("quit").action = _self().quit
        settings.command("load").action = _self().chooseExecutable
        settings.command("open-source").action = _self().chooseSource
        settings.command("find").action = _self().showFind
        settings.command("preferences").action = _self().showPreferences
        settings.command("resume").action = _self().resume
        settings.command("restart").action = _self().restart
        settings.command("interrupt").action = _self().interrupt
        settings.command("step-into").action = _self().stepInto
        settings.command("step-over").action = _self().stepOver
        settings.command("step-out").action = _self().stepOut
        settings.command("toggle-breakpoint").action = _self().toggleBreakpoint
        settings.command("toggle-enable").action = _self().toggleEnabled
        settings.command("view-locals").action = _self().toggleLocalsPanel
        settings.command("view-watches").action = _self().toggleWatchesPanel
        settings.command("view-stack").action = _self().toggleStackPanel
        settings.command("view-breaks").action = _self().toggleBreaksPanel
        settings.command("view-output").action = _self().toggleOutputPanel
        settings.command("view-console").action = _self().toggleConsolePanel
        settings.command("view-runtime").action = _self().toggleRuntimePanel
    }

void Cdbg.toggleLocalsPanel() { togglePanel("locals") }
void Cdbg.toggleWatchesPanel() { togglePanel("watches") }
void Cdbg.toggleStackPanel() { togglePanel("stack") }
void Cdbg.toggleBreaksPanel() { togglePanel("breaks") }
void Cdbg.toggleOutputPanel() { togglePanel("output") }
void Cdbg.toggleConsolePanel() { togglePanel("console") }
void Cdbg.toggleRuntimePanel() { togglePanel("runtime") }

void Cdbg.rebindShortcuts() {
        if (window == null || window.disposed()) { return }
        window.clearShortcuts()
        int64 i = 0
        while (i < settings.commands.length) {
            CommandBinding binding = settings.commands[i] as CommandBinding
            if (!binding.trigger.equals("") && binding.valid && binding.action != null) {
                window.bindShortcut(binding.trigger, binding.action)
            }
            i = i + 1
        }
    }
