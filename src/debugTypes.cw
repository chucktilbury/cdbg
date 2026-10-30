class DebugDiagnostic {
    String header(String severity, String code, String text) {
        return(format("cdbg: {}[{}]: {}", severity, code, text))
    }
    String emit(String severity, String code, String text) {
        String message = header(severity, code, text)
        System.StandardIO().writeErrorLine(message)
        return(message)
    }
}

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
    int64 centeredStop
    void<DebugSource> closeAction
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

