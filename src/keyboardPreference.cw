class KeyboardPreference {
    KeyboardPreference _self()
    CommandBinding binding
    CdbgSettings settings
    Gtk.Label name
    Gtk.Entry entry
    Gtk.Button recordButton
    Gtk.Button resetButton
    Gtk.Button disableButton
    Gtk.Label errorLabel
    void<> applied
    void<> prepareRecord
    int64 recording
    bool refreshing

    KeyboardPreference(CdbgSettings model, CommandBinding command, void<> changed,
                       void<> prepare, Gtk.Grid grid, int64 index) {
        settings = model
        binding = command
        applied = changed
        prepareRecord = prepare
        name = Gtk.Label(binding.name)
        entry = Gtk.Entry(binding.trigger)
        entry.setEditable(false)
        entry.setHExpand(true)
        recordButton = Gtk.Button("Record")
        resetButton = Gtk.Button("Reset")
        disableButton = Gtk.Button("Disable")
        errorLabel = Gtk.Label("")
        grid.attach(name, 0, index * 2, 1, 1)
        grid.attach(entry, 1, index * 2, 1, 1)
        grid.attach(recordButton, 2, index * 2, 1, 1)
        grid.attach(resetButton, 3, index * 2, 1, 1)
        grid.attach(disableButton, 4, index * 2, 1, 1)
        grid.attach(errorLabel, 0, index * 2 + 1, 5, 1)
        entry.onChanged(_self().changedTrigger)
        recordButton.onClicked(_self().record)
        resetButton.onClicked(_self().reset)
        disableButton.onClicked(_self().disable)
    }

    void changedTrigger(String text) {
        if (refreshing) { return }
        if (text.equals("")) {
            errorLabel.setText("Use Disable to remove this binding")
            return
        }
        String problem = settings.bindingError(binding, text)
        errorLabel.setText(problem)
        if (!problem.equals("")) { return }
        binding.setTrigger(text)
        applied()
    }
    void record() {
        prepareRecord()
        errorLabel.setText("Press shortcut; Escape cancels")
        recording = Gtk.Keyboard().record(entry, _self().recorded)
    }
    void recorded(String trigger) {
        cancelRecording()
        if (!trigger.equals("")) { setTrigger(trigger) }
    }
    void cancelRecording() {
        if (recording != 0) {
            Gtk.Keyboard().cancel(recording)
            recording = 0
            errorLabel.setText("")
        }
    }
    void reset() {
        cancelRecording()
        setTrigger(binding.defaultTrigger)
    }
    void disable() {
        cancelRecording()
        refreshing = true
        entry.setText("")
        refreshing = false
        binding.setTrigger("")
        errorLabel.setText("")
        applied()
    }
    void setTrigger(String trigger) {
        refreshing = true
        entry.setText(trigger)
        refreshing = false
        changedTrigger(trigger)
    }
    void refresh() {
        refreshing = true
        cancelRecording()
        entry.setText(binding.trigger)
        errorLabel.setText("")
        refreshing = false
    }
    void setVisible(bool visible) {
        name.setVisible(visible)
        entry.setVisible(visible)
        recordButton.setVisible(visible)
        resetButton.setVisible(visible)
        disableButton.setVisible(visible)
        errorLabel.setVisible(visible)
    }
}

KeyboardPreference KeyboardPreference._self() from "cwhip_gtk_self"
