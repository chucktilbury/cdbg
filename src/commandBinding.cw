class CommandBinding {
    String id
    String name
    String defaultTrigger
    String trigger
    String normalized
    bool valid
    void<> action
    CommandBinding(String command, String label, String shortcut) {
        id = command
        name = label
        defaultTrigger = shortcut
        setTrigger(shortcut)
    }
    void setTrigger(String shortcut) {
        trigger = shortcut
        normalized = ""
        if (!shortcut.equals("")) { normalized = Gtk.Keyboard().normalize(shortcut) }
        valid = shortcut.equals("") || normalized.length > 0
    }
}
