String Cdbg.initialPath() {
        if (!targetPath.equals("")) { return(System.FileSystem().absolutePath(targetPath)) }
        if (source != null) {
            int64 i = 0
            while (i < sourceFiles.length) {
                DebugSource file = sourceFiles[i] as DebugSource
                if (file.view == source && !file.path.equals("")) { return(file.path) }
                i = i + 1
            }
        }
        return("")
    }

void Cdbg.chooseExecutable() {
        if (fileDialog != null && fileDialog.pending()) { return }
        fileDialog = Gtk.FileDialog(window, false, initialPath(), _self().executableChosen)
    }

void Cdbg.chooseSource() {
        if (fileDialog != null && fileDialog.pending()) { return }
        fileDialog = Gtk.FileDialog(window, false, initialPath(), _self().sourceChosen)
    }

void Cdbg.executableChosen(String path) {
        fileDialog = null
        if (!path.equals("")) { loadTarget(path) }
    }

void Cdbg.sourceChosen(String path) {
        fileDialog = null
        if (!path.equals("")) { openSource(path) }
    }

void Cdbg.quit() {
        if (window != null && !window.disposed()) { window.close() }
    }

// Load Executable: a fresh GDB session with breakpoints cleared, prepared
// but not run. A .cw path (command line) is compiled with -g first. A path
// that is not a regular file is rejected before the current session or
// source tabs are touched.
void Cdbg.loadTarget(String path) {
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
bool Cdbg.openSource(String path) {
        String absolute = System.FileSystem().absolutePath(path)
        if (absolute.equals("")) { absolute = path }
        if (!System.FileSystem().isFile(absolute)) {
            loadFailure(format("Source is not a local file: {}", absolute))
            return(false)
        }
        if (executableImage(absolute)) {
            loadFailure(format("{} is an executable, not source code; use File > Load Executable...",
                absolute))
            return(false)
        }
        return(showSource(absolute, ""))
    }

bool Cdbg.executableImage(String path) {
        System.File file = null
        try {
            file = System.File(path, "rb")
            String magic = file.read(4)
            file.close()
            return (magic.length == 4 && magic[0] == 127u && magic[1] == 69u &&
                magic[2] == 76u && magic[3] == 70u)
        } except(Exception) {
            if (file != null && file.isOpen()) { file.close() }
        }
        return(false)
    }
