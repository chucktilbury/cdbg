void Cdbg.showFind() {
        if (findWindow == null || findWindow.disposed()) { return }
        findStatus.setText("")
        if (source != null && source.hasSelection()) {
            String selected = source.selectedText()
            if (!selected.contains("\n")) { findEntry.setText(selected) }
        }
        findWindow.setVisible(true)
        findWindow.present()
        findEntry.focus()
    }

void Cdbg.closeFind() {
        if (findWindow != null && !findWindow.disposed()) { findWindow.setVisible(false) }
    }

bool Cdbg.findCloseRequested() {
        findWindow.setVisible(false)
        return(true)
    }
void Cdbg.findNext() { find(false) }
void Cdbg.findPrevious() { find(true) }

void Cdbg.find(bool backward) {
        String query = findEntry.text()
        if (query.equals("")) { findStatus.setText("Enter text to find")
            return }
        if (source == null || currentSource() == null) {
            findStatus.setText("No source file is open")
            return
        }
        int64 before = source.line()
        int64 options = 0
        if (backward) { options = GtkSource.View.BACKWARD }
        if (!source.findWith(query, options)) {
            findStatus.setText(format("Not found: {}", query))
            return
        }
        int64 after = source.line()
        if ((!backward && after < before) || (backward && after > before)) {
            findStatus.setText(format("Wrapped: {} at line {}", query, after))
        } else { findStatus.setText(format("Found: {} at line {}", query, after)) }
    }
