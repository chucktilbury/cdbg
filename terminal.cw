import process as TerminalProcess

class DebugTerminal {
    private:
    handle _native
    TerminalProcess.OutputDecoder _decoder
    bool _closed
    bool _finished

    handle _nativeOpen()
    String _nativePath(handle terminal)
    buffer _nativeRead(handle terminal)
    void _nativeClose(handle terminal)
    String _nativeError(handle terminal)
    void _nativeDestroy(handle terminal)

    public:
    DebugTerminal() {
        _native = _nativeOpen()
        _decoder = TerminalProcess.OutputDecoder()
        _closed = false
        _finished = false
    }

    String path() {
        return _nativePath(_native)
    }

    String read() {
        if (_native != null && !_closed) {
            return _decoder.decode(_nativeRead(_native))
        }
        if (!_finished) {
            _finished = true
            return _decoder.finish()
        }
        return ""
    }

    void close() {
        if (!_closed) {
            _closed = true
            if (_native != null) {
                _nativeClose(_native)
            }
        }
    }

    String error() {
        return _nativeError(_native)
    }

    destroy {
        if (_native != null) {
            _nativeDestroy(_native)
            _native = null
        }
    }
}

handle DebugTerminal._nativeOpen() from "cwhip_cdbg_terminal_open"
String DebugTerminal._nativePath(handle terminal) from "cwhip_cdbg_terminal_path"
buffer DebugTerminal._nativeRead(handle terminal) from "cwhip_cdbg_terminal_read"
void DebugTerminal._nativeClose(handle terminal) from "cwhip_cdbg_terminal_close"
String DebugTerminal._nativeError(handle terminal) from "cwhip_cdbg_terminal_error"
void DebugTerminal._nativeDestroy(handle terminal) from "cwhip_cdbg_terminal_destroy"
