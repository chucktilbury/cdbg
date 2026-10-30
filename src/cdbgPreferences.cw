void Cdbg.createPreferences() {
        preferencesWindow = Gtk.TransientWindow("cdbg Preferences")
        preferencesWindow.setTransientFor(window)
        preferencesWindow.setDefaultSize(850, 600)
        Gtk.Box root = Gtk.Box(Gtk.Box.VERTICAL, 8)
        Gtk.Box content = Gtk.Box(Gtk.Box.HORIZONTAL, 12)
        Gtk.Box categories = Gtk.Box(Gtk.Box.VERTICAL, 6)
        Gtk.Button sessionCategory = Gtk.Button("Session")
        Gtk.Button appearanceCategory = Gtk.Button("Appearance")
        Gtk.Button keyboardCategory = Gtk.Button("Keyboard")
        categories.append(sessionCategory)
        categories.append(appearanceCategory)
        categories.append(keyboardCategory)
        sessionCategory.onClicked(_self().showSessionPreferences)
        appearanceCategory.onClicked(_self().showAppearancePreferences)
        keyboardCategory.onClicked(_self().showKeyboardPreferences)
        content.append(categories)
        Gtk.Box pages = Gtk.Box(Gtk.Box.VERTICAL, 8)
        pages.setHExpand(true)
        pages.setVExpand(true)
        content.append(pages)
        sessionPreferences = Gtk.Box(Gtk.Box.VERTICAL, 6)
        sessionPreferences.append(Gtk.Label("Session"))
        setupStart = Gtk.CheckButton("Break at start")
        sessionPreferences.append(setupStart)
        sessionPreferences.append(Gtk.Label("Program arguments (shell-style quoting; no shell is run)"))
        setupArguments = Gtk.Entry("")
        setupArguments.setHExpand(true)
        sessionPreferences.append(setupArguments)
        setupStatus = Gtk.Label("")
        sessionPreferences.append(setupStatus)
        Gtk.Box sessionButtons = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        sessionPreferences.append(sessionButtons)
        button(sessionButtons, "Apply", _self().applySetup)
        button(sessionButtons, "Cancel", _self().closeSetup)
        pages.append(sessionPreferences)
        appearancePreferences = Gtk.Box(Gtk.Box.VERTICAL, 6)
        appearancePreferences.append(Gtk.Label("Appearance"))
        fontEntry = preferenceEntry(appearancePreferences, "Monospace font family", settings.fontFamily)
        sizeEntry = preferenceEntry(appearancePreferences, "Font size (6-72 pt)", format("{}", settings.fontSize))
        tabsEntry = preferenceEntry(appearancePreferences, "Tab width (1-16 columns)", format("{}", settings.tabWidth))
        numbersCheck = Gtk.CheckButton("Show line numbers in source panes")
        numbersCheck.setActive(settings.lineNumbers)
        numbersCheck.onToggled(_self().appearanceCheckChanged)
        appearancePreferences.append(numbersCheck)
        fontEntry.onChanged(_self().appearanceSettingChanged)
        sizeEntry.onChanged(_self().appearanceSettingChanged)
        tabsEntry.onChanged(_self().appearanceSettingChanged)
        Gtk.Button appearanceReset = Gtk.Button("Reset Appearance to Defaults")
        appearanceReset.onClicked(_self().resetAppearancePreferences)
        appearancePreferences.append(appearanceReset)
        pages.append(appearancePreferences)
        appearancePreferences.setVisible(false)
        keyboardPreferences = Gtk.Box(Gtk.Box.VERTICAL, 6)
        commandSearch = Gtk.Entry("")
        keyboardPreferences.append(Gtk.Label("Search commands; empty binding disables a command"))
        keyboardPreferences.append(commandSearch)
        commandSearch.onChanged(_self().commandSearchChanged)
        Gtk.ScrolledWindow scroll = Gtk.ScrolledWindow()
        scroll.setVExpand(true)
        keyboardRowsBox = Gtk.Grid(6)
        scroll.setChild(keyboardRowsBox)
        keyboardRows = []
        keyboardPreferences.append(scroll)
        Gtk.Button keyboardReset = Gtk.Button("Reset Keyboard to Defaults")
        keyboardReset.onClicked(_self().resetKeyboardPreferences)
        keyboardPreferences.append(keyboardReset)
        pages.append(keyboardPreferences)
        keyboardPreferences.setVisible(false)
        root.append(content)
        String settingsError = ""
        if (!settings.errors.equals("")) {
            settingsError = DebugDiagnostic().header("error", "CDBG2002",
                format("{}: {}", settings.path, settings.errors))
        }
        preferencesMessage = Gtk.Label(settingsError)
        root.append(preferencesMessage)
        settingsPathLabel = Gtk.Label(format("Appearance and keyboard automatically saved to {}", settings.path))
        root.append(settingsPathLabel)
        resetChoices = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        resetChoices.append(Gtk.Label("Reset this section?"))
        confirmResetButton = Gtk.Button("Confirm Reset")
        cancelResetButton = Gtk.Button("Cancel")
        confirmResetButton.onClicked(_self().confirmPreferencesReset)
        cancelResetButton.onClicked(_self().cancelPreferencesReset)
        resetChoices.append(confirmResetButton)
        resetChoices.append(cancelResetButton)
        root.append(resetChoices)
        resetChoices.setVisible(false)
        preferencesWindow.setChild(root)
        preferencesWindow.onCloseRequest(_self().hidePreferences)
        preferencesWindow.setVisible(false)
    }

Gtk.Entry Cdbg.preferenceEntry(Gtk.Box page, String label, String text) {
        Gtk.Box row = Gtk.Box(Gtk.Box.HORIZONTAL, 6)
        row.append(Gtk.Label(label))
        Gtk.Entry entry = Gtk.Entry(text)
        entry.setHExpand(true)
        row.append(entry)
        page.append(row)
        return(entry)
    }

void Cdbg.showPreferences() {
        if (preferencesWindow == null) { createPreferences() }
        showSessionPreferences()
        preferencesWindow.present()
    }

// Keep showSetup as an alias so existing menu/test call sites open Session.
void Cdbg.showSetup() {
        showPreferences()
        setupStart.setActive(breakAtStart)
        setupArguments.setText(ArgumentList().display(arguments))
        if (stateTarget.equals("")) {
            setupStatus.setText("No target loaded: Break at start becomes this directory's default")
        } else { setupStatus.setText(format("Settings for {}", stateTarget)) }
        setupArguments.focus()
    }

void Cdbg.closeSetup() {
        if (preferencesWindow != null && !preferencesWindow.disposed()) {
            preferencesWindow.setVisible(false)
        }
    }

bool Cdbg.setupCloseRequested() { closeSetup()
        return(true) }

bool Cdbg.hidePreferences() {
        prepareShortcutRecord()
        if (preferencesWindow != null && !preferencesWindow.disposed()) {
            preferencesWindow.setVisible(false)
        }
        return(true)
    }

void Cdbg.showSessionPreferences() {
        if (preferencesWindow == null) { createPreferences() }
        prepareShortcutRecord()
        sessionPreferences.setVisible(true)
        appearancePreferences.setVisible(false)
        keyboardPreferences.setVisible(false)
        resetChoices.setVisible(false)
        setupStart.setActive(breakAtStart)
        setupArguments.setText(ArgumentList().display(arguments))
        if (stateTarget.equals("")) {
            setupStatus.setText("No target loaded: Break at start becomes this directory's default")
        } else { setupStatus.setText(format("Settings for {}", stateTarget)) }
        preferencesWindow.setVisible(true)
        preferencesWindow.present()
    }

void Cdbg.showAppearancePreferences() {
        if (preferencesWindow == null) { createPreferences() }
        prepareShortcutRecord()
        sessionPreferences.setVisible(false)
        appearancePreferences.setVisible(true)
        keyboardPreferences.setVisible(false)
        resetChoices.setVisible(false)
        refreshingPreferences = true
        fontEntry.setText(settings.fontFamily)
        sizeEntry.setText(format("{}", settings.fontSize))
        tabsEntry.setText(format("{}", settings.tabWidth))
        numbersCheck.setActive(settings.lineNumbers)
        refreshingPreferences = false
        preferencesWindow.setVisible(true)
        preferencesWindow.present()
    }

void Cdbg.showKeyboardPreferences() {
        if (preferencesWindow == null) { createPreferences() }
        sessionPreferences.setVisible(false)
        appearancePreferences.setVisible(false)
        keyboardPreferences.setVisible(true)
        resetChoices.setVisible(false)
        if (keyboardRows.length == 0) {
            int64 i = 0
            while (i < settings.commands.length) {
                keyboardRows.append(KeyboardPreference(settings, settings.commands[i] as CommandBinding,
                    _self().keyboardChanged, _self().prepareShortcutRecord, keyboardRowsBox, i))
                i = i + 1
            }
        }
        filterCommands("")
        preferencesWindow.setVisible(true)
        preferencesWindow.present()
    }

void Cdbg.appearanceSettingChanged(String text) {
        appearanceChanged()
    }

void Cdbg.appearanceChanged() {
        if (refreshingPreferences) { return }
        String font = fontEntry.text().trim()
        String problem = settings.fontError(font)
        int64 size = sizeEntry.text().toInt64()
        int64 tabs = tabsEntry.text().toInt64()
        if (!problem.equals("")) {
            preferencesMessage.setText(problem)
            return
        }
        if (size < 6 || size > 72) {
            preferencesMessage.setText("Font size must be between 6 and 72")
            return
        }
        if (tabs < 1 || tabs > 16) {
            preferencesMessage.setText("Tab width must be between 1 and 16")
            return
        }
        settings.fontFamily = font
        settings.fontSize = size
        settings.tabWidth = tabs
        preferencesMessage.setText("")
        applyAppearance()
        saveSettings()
    }

void Cdbg.appearanceCheckChanged(bool active) {
        if (refreshingPreferences) { return }
        settings.lineNumbers = active
        applyAppearance()
        saveSettings()
    }

void Cdbg.commandSearchChanged(String text) { filterCommands(text) }

void Cdbg.filterCommands(String text) {
        String query = text.trim().toLower()
        if (query.equals("") && commandSearch != null) {
            query = commandSearch.text().trim().toLower()
        }
        int64 i = 0
        while (i < keyboardRows.length) {
            KeyboardPreference row = keyboardRows[i] as KeyboardPreference
            bool match = query.equals("") || row.binding.name.toLower().contains(query) || row.binding.id.toLower().contains(query)
            row.setVisible(match)
            i = i + 1
        }
    }

void Cdbg.prepareShortcutRecord() {
        int64 i = 0
        while (i < keyboardRows.length) {
            (keyboardRows[i] as KeyboardPreference).cancelRecording()
            i = i + 1
        }
    }

void Cdbg.keyboardChanged() {
        settings.shortcutRevision = settings.shortcutRevision + 1
        rebindShortcuts()
        saveSettings()
    }

void Cdbg.resetAppearancePreferences() {
        resetSection = "appearance"
        resetChoices.setVisible(true)
    }

void Cdbg.resetKeyboardPreferences() {
        resetSection = "keyboard"
        resetChoices.setVisible(true)
    }

void Cdbg.confirmPreferencesReset() {
        if (resetSection.equals("appearance")) {
            settings.resetAppearance()
            refreshingPreferences = true
            fontEntry.setText(settings.fontFamily)
            sizeEntry.setText(format("{}", settings.fontSize))
            tabsEntry.setText(format("{}", settings.tabWidth))
            numbersCheck.setActive(settings.lineNumbers)
            refreshingPreferences = false
            applyAppearance()
            saveSettings()
        }
        if (resetSection.equals("keyboard")) {
            settings.resetKeyboard()
            int64 i = 0
            while (i < keyboardRows.length) {
                (keyboardRows[i] as KeyboardPreference).refresh()
                i = i + 1
            }
            keyboardChanged()
        }
        resetSection = ""
        resetChoices.setVisible(false)
    }

void Cdbg.cancelPreferencesReset() {
        resetSection = ""
        resetChoices.setVisible(false)
    }

void Cdbg.saveSettings() {
        if (!settings.writable) {
            preferencesMessage.setText(format("Settings not saved to {}: {}", settings.path, settings.errors))
            return
        }
        String text = settings.serialize()
        if (text.equals("") || text.length > 65536) {
            preferencesMessage.setText("Settings snapshot exceeds its limit or cannot be serialized")
            return
        }
        String error = Gtk.Config().saveNow(settings.path, text, settings.original)
        if (!error.equals("")) {
            preferencesMessage.setText(format("Settings not saved to {}: {}", settings.path, error))
            return
        }
        settings.original = text
        preferencesMessage.setText("")
        settingsPathLabel.setText(format("Appearance and keyboard automatically saved to {}", settings.path))
    }

void Cdbg.applyAppearance() {
        list views = [source, locals, stack, watches, breaks, console, programOutput, runtimeValues]
        int64 i = 0
        while (i < sourceFiles.length) {
            views.append((sourceFiles[i] as DebugSource).view)
            i = i + 1
        }
        i = 0
        while (i < views.length) {
            GtkSource.View view = views[i] as GtkSource.View
            if (view != null) {
                bool numbers = settings.lineNumbers
                if (view == locals || view == stack || view == watches || view == breaks ||
                    view == console || view == programOutput || view == runtimeValues) {
                    numbers = false
                }
                view.configure(settings.fontFamily, settings.fontSize, settings.tabWidth, true,
                    numbers, false, true)
            }
            i = i + 1
        }
    }

void Cdbg.settingsChanged() {
        applyAppearance()
        rebindShortcuts()
        saveSettings()
    }
