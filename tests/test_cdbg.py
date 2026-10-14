"""Real Cwhip GTK debugger, MI grammar, local GDB sessions and failure teardown."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from gtk_support import headless
from program_runner import environment, invoke
from test_cedit_shortcuts import Display


PARSER = r'''
include "mi.cw"
class Check {
    void require(bool condition, String name) {
        if (!condition) { print(format("FAIL {}", name))
            System.Process().exit(1) }
    }
}
start {
    Check test = Check()
    MiParser parser = MiParser()
    parser.parse("12^done,stack=[frame={level=\"0\",func=\"main\",fullname=\"a,b.cw\",line=\"10\"}]")
    test.require(parser.valid && parser.token.equals("12") && parser.kind.equals("^") &&
        parser.result.equals("done"), "result record")
    MiValue frame = parser.data.field("stack").values[0] as MiValue
    test.require(frame.field("fullname").text.equals("a,b.cw") &&
        frame.field("line").text.equals("10"), "nested tuple/list")
    parser.parse("*stopped,reason=\"breakpoint-hit\",frame={func=\"foo\",args=[{name=\"x\",value=\"21\"}]}")
    test.require(parser.valid &&
        (parser.data.field("frame").field("args").values[0] as MiValue).field("value").text.equals("21"),
        "value list")
    parser.parse("~\"tab\\tquote\\\"backslash\\\\newline\\n\\303\\251\"")
    test.require(parser.valid && parser.data.text.contains("tab\tquote\"backslash\\newline\n"),
        "C string escapes")
    parser.parse("13^error,msg=\"No symbol \\\"missing\\\" in current context.\"")
    test.require(parser.valid && parser.data.field("msg").text.contains("\"missing\""), "error")
    String input = "path \"with quotes\"\\and\nnewlines\t"
    parser.parse(format("~{}", parser.quote(input)))
    test.require(parser.valid && parser.data.text.equals(input), "quoting roundtrip")
    parser.parse("1^done,values=[]")
    test.require(parser.valid && parser.data.field("values").values.length == 0, "empty list")
    parser.parse("1^done,bkpt={number=\"3\",addr=\"<MULTIPLE>\"},{number=\"3.1\",line=\"7\"},{number=\"3.2\",line=\"9\"}")
    test.require(parser.valid && parser.data.field("bkpt").field("locations").values.length == 2 &&
        (parser.data.field("bkpt").field("locations").values[1] as MiValue).field("line").text.equals("9"),
        "legacy GDB unlabelled multiple breakpoint locations")
    parser.parse("=breakpoint-modified,bkpt={number=\"3\",locations=[{number=\"3.1\",line=\"7\"}]}")
    test.require(parser.valid && parser.data.field("bkpt").field("locations").values.length == 1,
        "nested multiple breakpoint locations")
    parser.parse("1^done,bkpt={number=\"3\"},{number=\"4.1\"}")
    test.require(!parser.valid, "unrelated unlabelled tuple rejected")
    parser.parse("1^done,other={number=\"3\"},{number=\"3.1\"}")
    test.require(!parser.valid, "unlabelled tuple outside bkpt rejected")
    parser.parse("1^done,values=[{name=\"x\"},]")
    test.require(!parser.valid, "trailing comma rejected")
    parser.parse("1^done,msg=\"unfinished")
    test.require(!parser.valid, "unterminated string rejected")
    parser.parse("1^done,msg=\"bad\\q\"")
    test.require(!parser.valid, "unknown escape rejected")
    parser.parse("1^done,msg=\"\\777\"")
    test.require(!parser.valid, "invalid byte escape rejected")
    String deep = "1^done,x="
    int i = 0
    while (i < 40) { deep.append("[")
        i = i + 1 }
    deep.append("\"x\"")
    i = 0
    while (i < 40) { deep.append("]")
        i = i + 1 }
    parser.parse(deep)
    test.require(!parser.valid, "depth bounded")
    ArgumentList args = ArgumentList()
    test.require(args.parse("one  \"two words\" '' \"\" it\\'s 'a \"q\"' \"x\\\"y\\\\z\" caf\\é"),
        "shell-like arguments parse")
    test.require(args.values.length == 8 && (args.values[0] as String).equals("one") &&
        (args.values[1] as String).equals("two words") && (args.values[2] as String).equals("") &&
        (args.values[3] as String).equals("") && (args.values[4] as String).equals("it's") &&
        (args.values[5] as String).equals("a \"q\"") && (args.values[6] as String).equals("x\"y\\z") &&
        (args.values[7] as String).equals("café"), "argument values, quotes and empty strings")
    String shown = args.display(args.values)
    ArgumentList again = ArgumentList()
    test.require(again.parse(shown) && again.display(again.values).equals(shown) &&
        again.values.length == 8 && (again.values[4] as String).equals("it's"), "display round-trips")
    test.require(!args.parse("ok \"unterminated") && args.error.equals("unterminated quote") &&
        args.values.length == 0, "unterminated quote rejected")
    test.require(!args.parse("ok trailing\\") && args.error.equals("trailing backslash"),
        "trailing backslash rejected")
    test.require(args.parse("  ") && args.values.length == 0, "blank arguments")
    test.require(parser.quote("a \"b\"\\").equals("\"a \\\"b\\\"\\\\\""), "MI argument quoting")
    print("true")
}
'''

DRIVER = r'''
import time
class DebugUiFixture {
    bool alert()
    bool panes()
    bool noEmoji()
    bool centered()
    void track()
    int changes()
    bool bordered()
    int closeButtons()
    bool closeTab(String name)
    bool sourceVisible()
    bool findVisible()
    bool findClick(String name)
    bool shortcut(String trigger)
    void choose(String path)
    bool compact()
    bool lineClick(String pane, int line, String action)
    int marks(String file, int line)
    bool watchDialog(String expression, bool accept)
    bool noBreakMenus()
    bool disabled(int line)
    bool setup(int startState, String arguments, String action)
    bool clipboard(String expected)
    bool step(String name, bool keyboard)
}
bool DebugUiFixture.alert() from "cdbg_fixture_alert"
bool DebugUiFixture.panes() from "cdbg_fixture_panes"
bool DebugUiFixture.noEmoji() from "cdbg_fixture_no_emoji"
bool DebugUiFixture.centered() from "cdbg_fixture_centered"
void DebugUiFixture.track() from "cdbg_fixture_track"
int DebugUiFixture.changes() from "cdbg_fixture_changes"
bool DebugUiFixture.bordered() from "cdbg_fixture_bordered"
int DebugUiFixture.closeButtons() from "cdbg_fixture_close_buttons"
bool DebugUiFixture.closeTab(String name) from "cdbg_fixture_close_tab"
bool DebugUiFixture.sourceVisible() from "cdbg_fixture_source_visible"
bool DebugUiFixture.findVisible() from "cdbg_fixture_find_visible"
bool DebugUiFixture.findClick(String name) from "cdbg_fixture_find_click"
bool DebugUiFixture.shortcut(String trigger) from "cdbg_fixture_shortcut"
void DebugUiFixture.choose(String path) from "cdbg_fixture_choose"
bool DebugUiFixture.compact() from "cdbg_fixture_compact"
bool DebugUiFixture.lineClick(String pane, int line, String action) from "cdbg_fixture_line_click"
int DebugUiFixture.marks(String file, int line) from "cdbg_fixture_marks"
bool DebugUiFixture.watchDialog(String expression, bool accept) from "cdbg_fixture_watch"
bool DebugUiFixture.noBreakMenus() from "cdbg_fixture_no_break_menus"
bool DebugUiFixture.disabled(int line) from "cdbg_fixture_disabled"
bool DebugUiFixture.setup(int startState, String arguments, String action) from "cdbg_fixture_setup"
bool DebugUiFixture.clipboard(String expected) from "cdbg_fixture_clipboard"
bool DebugUiFixture.step(String name, bool keyboard) from "cdbg_fixture_step"

class DebugChecks {
    Cdbg ui
    int stage
    int stops
    unsigned deadline
    String mode
    String oldPid
    String previousPc
    void singleStep(String name, bool keyboard) {
        stops = ui.stopCount
        require(DebugUiFixture().step(name, keyboard), format("{} control ready", name))
    }
    void stepped(String file, int line) {
        require(ui.stopCount == stops + 1, "one activation produces exactly one stop")
        require(ui.location.contains(file) && ui.source.line() == line,
            format("single step reaches {}:{}, got {}", file, line, ui.location))
        require(ui.status.text().contains("PC 0x"), "stop displays actual program counter")
    }
    bool steppingTick() {
        if (stage == 0 && ui.loaded && idle()) {
            ui.addWatch("counter")
            stage = 1
        }
        if (stage == 1 && idle()) {
            ui.resume()
            stage = 2
        }
        if (stage == 2 && ui.stopCount == 1 && !ui.running && idle()) {
            require(ui.atStart && ui.source.line() == 7, "Break at start stop")
            singleStep("Step Over", false)
            stage = 3
        }
        if (stage >= 3 && stage <= 23 && ui.stopCount > stops && !ui.running && idle()) {
            if (stage == 3) {
                stepped("stepping.cw", 8)
                singleStep("Step Over", true)
            }
            if (stage == 4) {
                stepped("stepping.cw", 9)
                singleStep("Step Over", false)
            }
            if (stage == 5) {
                stepped("stepping.cw", 10)
                singleStep("Step Into", false)
            }
            if (stage == 6) {
                stepped("RuntimeGc.c", System.Process().getEnv("CDBG_RUNTIME_ENTRY").toInt())
                require(ui.location.contains("cwhip_gc_require_alive"), "step enters real runtime")
                require(ui.watches.text().contains("counter = <") &&
                    !ui.locals.text().contains("fields; members unavailable"),
                    "native frame keeps native values and reports out-of-scope Cwhip watches")
                previousPc = ui.stopAddress
                stops = ui.stopCount
                ui.execute("-exec-step-instruction", "Step Instruction")
                stage = 60
                return true
            }
            if (stage == 7) {
                stepped("RuntimeGc.c", System.Process().getEnv("CDBG_RUNTIME_CALL").toInt())
                ui.inspection.setCurrentPage(1)
                stage = 30
                return true
            }
            if (stage == 8) {
                stepped("RuntimeGc.c", System.Process().getEnv("CDBG_RUNTIME_CALL").toInt() + 1)
                singleStep("Step Out", true)
            }
            if (stage == 9) {
                stepped("stepping.cw", 10)
                require(ui.status.text().contains("function-finished"), "return reason is visible")
                singleStep("Step Into", true)
            }
            if (stage == 10) {
                stepped("stepping.cw", 2)
                singleStep("Step Over", false)
            }
            if (stage == 11) {
                stepped("stepping.cw", 3)
                singleStep("Step Over", true)
            }
            if (stage == 12) {
                stepped("stepping.cw", 4)
                singleStep("Step Over", false)
            }
            if (stage == 13) {
                stepped("stepping.cw", 11)
                require(!ui.stack.text().contains("thunk") && !ui.location.contains("??"),
                    "method return never stops in anonymous dispatch thunk")
                singleStep("Step Over", true)
            }
            if (stage == 14) {
                stepped("stepping.cw", 12)
                singleStep("Step Over", false)
            }
            if (stage == 15) {
                stepped("stepping.cw", 13)
                ui.breakAtStart = false
                ui.addBreakpoint(format("{}:3", System.Process().getEnv("CDBG_TEST_SOURCE")))
                stage = 150
                return true
            }
            if (stage == 16) {
                stepped("stepping.cw", 3)
                singleStep("Step Out", false)
            }
            if (stage == 17) {
                stepped("stepping.cw", 10)
                singleStep("Step Over", true)
            }
            if (stage == 18) {
                stepped("stepping.cw", 11)
                stops = ui.stopCount
                ui.restart()
            }
            if (stage == 19) {
                stepped("stepping.cw", 3)
                ui.inspection.setCurrentPage(1)
                stage = 190
                return true
            }
            if (stage == 20) {
                stepped("stepping.cw", 4)
                // Browse the caller and press Step Out while that frame
                // selection is still in flight; execution must use frame 0.
                stage = 200
                return true
            }
            if (stage == 21) {
                stepped("stepping.cw", 10)
                singleStep("Step Over", false)
            }
            if (stage == 22) {
                stepped("stepping.cw", 11)
                singleStep("Step Over", false)
                stage = 230
                return true
            }
            if (stage == 23) {
                stepped("stepping.cw", 13)
                ui.quit()
                require(ui.closed && ui.process == null, "stepping test shutdown")
                print("true")
                return false
            }
            stage = stage + 1
        }
        if (stage == 30) {
            if (DebugUiFixture().lineClick("Stack", 2, "")) { stage = 31 }
        }
        if (stage == 31 && idle()) {
            require(ui.selectedFrame == 1 && ui.location.contains("stepping.cw:10"),
                "stack click browses caller")
            require(ui.locals.text().contains("counter = 21") && ui.watches.text().contains("counter = 21") &&
                ui.runtimeValues.text().contains("counter : int = 21"),
                "caller selection refreshes friendly and runtime values together")
            singleStep("Step Over", false)
            stage = 8
        }
        if (stage == 150 && idle()) {
            stops = ui.stopCount
            ui.restart()
            stage = 16
        }
        if (stage == 60 && ui.stopCount > stops && !ui.running && idle()) {
            stepped("RuntimeGc.c", System.Process().getEnv("CDBG_RUNTIME_ENTRY").toInt())
            require(!ui.stopAddress.equals(previousPc) &&
                ui.status.text().contains("same source line (previous PC"),
                "real same-line runtime stop displays changed PC, without an automatic extra step")
            singleStep("Step Over", true)
            stage = 7
        }
        // Press immediately after the stop, before the post-stop refresh has
        // completed (it is restarted here if GDB already answered it).
        if (stage == 230 && ui.stopCount > stops && !ui.running) {
            stepped("stepping.cw", 12)
            if (idle()) { ui.refresh() }
            require(!idle(), "refresh is pending at the press")
            singleStep("Step Over", false)
            require(DebugUiFixture().step("Step Over", false), "second press reaches the control")
            require(ui.status.text().contains("Step Over ignored: the previous execution command is still pending"),
                "extra press before *running is reported, not sent")
            stage = 23
        }
        if (stage == 200 && DebugUiFixture().lineClick("Stack", 2, "")) {
            require(!idle(), "frame selection is pending at the press")
            singleStep("Step Out", true)
            stage = 21
        }
        if (stage == 190) {
            if (DebugUiFixture().lineClick("Stack", 2, "")) { stage = 191 }
        }
        if (stage == 191 && idle()) {
            require(ui.selectedFrame == 1 && ui.location.contains("stepping.cw:10"),
                "browse caller after method breakpoint")
            singleStep("Step Into", true)
            stage = 20
        }
        return true
    }
    bool valuesTick() {
        if (stage == 0 && ui.loaded && idle()) {
            require(ui.valueInspector && ui.inspection.pageCount() == 7, "value inspector and Runtime Values tab")
            ui.addBreakpoint(format("{}:19", System.Process().getEnv("CDBG_TEST_SOURCE")))
            list names = ["counter", "positive", "truth", "fraction", "message", "missing",
                "worker", "items", "mapping", "bytes", "longText", "not_in_scope",
                "counter = 0", "print(counter)"]
            int i = 0
            while (i < names.length) {
                ui.addWatch(names[i] as String)
                i = i + 1
            }
            stage = 1
        }
        if (stage == 1 && idle()) { ui.resume()
            stage = 2 }
        if (stage == 2 && ui.stopCount > 0 && !ui.running && idle()) {
            String text = ui.locals.text()
            require(text.contains("counter = 21") && text.contains("positive = 42") &&
                text.contains("truth = true") && text.contains("fraction = 1.5"),
                format("Cwhip primitive values: {}", text))
            require(text.contains("message = \"") && text.contains("café") &&
                text.contains("\\n") && text.contains("\\\""), format("escaped Unicode String: {}", text))
            require(text.contains("missing = null") && text.contains("members unavailable"),
                format("null and honest class summary: {}", text))
            require(text.contains("items = list[9] {21, true, \"hello\", list[2] {1, list[2] <depth limit>}") &&
                text.contains("7} … <truncated>") &&
                text.contains("mapping = dict[1] {\"key\": 42}") &&
                text.contains("bytes = buffer[3] {01 02 ff}") &&
                text.contains("<truncated; 300 bytes>"), format("bounded containers/String: {}", text))
            list rows = text.split("\n")
            int i = 0
            while (i < rows.length) {
                String row = rows[i] as String
                if (!row.equals("")) { require(ui.watches.text().contains(row), format("same local/watch formatter: {}", row)) }
                i = i + 1
            }
            require(ui.watches.text().contains("not_in_scope = <") &&
                ui.runtimeValues.text().contains("message : struct String * = 0x") &&
                ui.runtimeValues.text().contains("Watches (GDB types and raw values)") &&
                ui.runtimeValues.text().contains("not_in_scope = <"), "raw types/values and watch error retained")
            require(ui.watches.text().contains("counter = 0 = <") &&
                ui.watches.text().contains("print(counter) = <"), "mutating/calling watches refused without changing counter")
            singleStep("Step Over", false)
            stage = 3
        }
        if (stage == 3 && ui.stopCount > stops && !ui.running && idle()) {
            require(ui.locals.text().contains("counter = 22") && ui.watches.text().contains("counter = 22") &&
                ui.runtimeValues.text().contains("counter : int = 22"), "all representations update after step")
            ui.selectFrame("0")
            stage = 4
        }
        if (stage == 4 && idle()) {
            require(ui.locals.text().contains("counter = 22") && ui.watches.text().contains("counter = 22"),
                "frame selection preserves shared values")
            ui.quit()
            print("true")
            return false
        }
        return true
    }
    void require(bool condition, String label) {
        if (!condition) {
            System.StandardIO().writeErrorLine(format("FAIL {} stage {}: {} ({})",
                mode, stage, label, ui.status.text()))
            ui.endSession()
            System.Process().exit(1)
        }
    }
    void activate() {
        mode = System.Process().getEnv("CDBG_TEST_MODE")
        ui = Cdbg()
        ui.activate()
        String previousConsole = ui.console.text()
        ui.consume("~\"fragment")
        require(ui.console.text().equals(previousConsole), "incomplete record buffered")
        ui.consume("ed\\n\"\n")
        require(ui.console.text().equals(format("{}fragmented\n", previousConsole)), "fragmented record reassembled")
        deadline = Time.Clock().monotonicMilliseconds() + 20000u
        if (mode.equals("ui") || mode.equals("context")) {
            require(ui.sourceTabs.pageCount() == 1 && ui.source.text().startsWith("No source"),
                "source area starts with a placeholder page")
        }
        if (mode.equals("context")) {
            require(DebugUiFixture().shortcut("F9") && ui.status.text().contains("Load a target"),
                "unloaded shortcut gives clear status without manipulating breakpoints")
        }
        ui.loadTarget(System.Process().getEnv("CDBG_TEST_TARGET"))
        Gtk.Application().post(_self().tick)
    }
    int pages
    // Open Source Code rejection: wait for the parented dialog, then require
    // the source notebook to be visible with its tabs unchanged.
    bool rejected(String label) {
        if (!DebugUiFixture().alert()) { return false }
        require(!ui.failure.equals(""), label)
        require(ui.sourceTabs.pageCount() == pages && DebugUiFixture().sourceVisible() &&
            DebugUiFixture().closeButtons() == pages && ui.source.text().contains("counter"),
            format("{}: failed open leaves source tabs visible and unchanged", label))
        ui.failure = ""
        return true
    }
    void found(String button, String expected) {
        require(DebugUiFixture().findClick(button), format("Find dialog {} button", button))
        require(ui.findStatus.text().equals(expected),
            format("{} reported '{}' expecting '{}'", button, ui.findStatus.text(), expected))
    }
    bool uiTick() {
        String work = System.Process().getEnv("CDBG_TEST_WORK")
        String notes = format("{}/notes.txt", work)
        if (stage == 0 && ui.loaded && idle()) {
            require(ui.failure.equals(""), ui.failure)
            require(DebugUiFixture().bordered(), "source and inspector tabs are bordered")
            pages = ui.sourceTabs.pageCount()
            require(pages == 2 && DebugUiFixture().closeButtons() == 2 &&
                DebugUiFixture().sourceVisible(), "each DWARF source tab has a close icon")
            require(!ui.openSource(format("{}/missing.txt", work)), "missing source rejected")
            stage = 1
        }
        if (stage == 1 && rejected("missing source")) {
            require(!ui.openSource(format("{}/binary.cw", work)), "binary source rejected")
            stage = 2
        }
        if (stage == 2 && rejected("binary source")) {
            require(!ui.openSource(System.Process().getEnv("CDBG_TEST_TARGET")),
                "executable rejected by Open Source Code")
            stage = 3
        }
        if (stage == 3 && rejected("executable as source")) {
            require(!ui.openSource(format("{}/invalid-utf8.cw", work)), "invalid UTF-8 rejected")
            stage = 4
        }
        if (stage == 4 && rejected("invalid UTF-8 source")) {
            require(ui.loaded && !ui.hasRun, "rejections leave the debug session alone")
            require(ui.openSource(notes) && ui.sourceTabs.pageCount() == 3 &&
                DebugUiFixture().closeButtons() == 3 && ui.source.text().contains("needle"),
                "text source opens in a closable tab without compiling")
            require(ui.openSource(notes) && ui.sourceTabs.pageCount() == 3, "reopen reuses tab")
            require(ui.failure.equals("") && ui.loaded && !ui.hasRun, "Open Source keeps session")
            require(DebugUiFixture().shortcut("<Control>f") && DebugUiFixture().findVisible(),
                "Ctrl+F shows Find dialog")
            ui.source.centerCursor(1, 1)
            ui.findEntry.setText("needle")
            found("Find Next", "Found: needle at line 2")
            found("Find Next", "Found: needle at line 4")
            found("Find Next", "Wrapped: needle at line 2")
            found("Find Previous", "Wrapped: needle at line 4")
            found("Find Previous", "Found: needle at line 2")
            ui.findEntry.setText("absent")
            found("Find Next", "Not found: absent")
            found("Close", "Not found: absent")
            require(!DebugUiFixture().findVisible(), "Close hides Find dialog")
            require(DebugUiFixture().closeTab("helper.c") && DebugUiFixture().closeTab("notes.txt") &&
                ui.sourceTabs.pageCount() == 1 && DebugUiFixture().closeButtons() == 1,
                "close icons remove tabs")
            require(ui.loaded && ui.process != null, "closing tabs keeps the debug session")
            ui.addBreakpoint(format("{}:{}", System.Process().getEnv("CDBG_TEST_SOURCE"),
                System.Process().getEnv("CDBG_TEST_LINE")))
            stage = 5
        }
        if (stage == 5 && idle()) { ui.resume()
            stage = 6 }
        if (stage == 6 && ui.stopCount > 0 && !ui.running && idle()) {
            require(ui.sourceTabs.pageCount() == 1, "stop in open file adds no tab")
            stops = ui.stopCount
            ui.stepInto()
            stage = 7
        }
        if (stage == 7 && ui.stopCount > stops && !ui.running && idle()) {
            require(ui.source.text().contains("doubled") && ui.sourceTabs.pageCount() == 2 &&
                DebugUiFixture().closeButtons() == 2, "stop reopens closed file once")
            stops = ui.stopCount
            ui.stepOver()
            stage = 8
        }
        if (stage == 8 && ui.stopCount > stops && !ui.running && idle()) {
            require(ui.sourceTabs.pageCount() == 2, "stepping in reopened file adds no duplicate")
            require(DebugUiFixture().closeTab("helper.c") &&
                DebugUiFixture().closeTab(System.FileSystem().basename(
                    System.Process().getEnv("CDBG_TEST_SOURCE"))),
                "close every file tab")
            require(ui.sourceTabs.pageCount() == 1 && DebugUiFixture().closeButtons() == 0 &&
                DebugUiFixture().sourceVisible() && ui.source.text().startsWith("No source"),
                "closing the last tab leaves a visible placeholder")
            DebugUiFixture().choose(System.Process().getEnv("CDBG_TEST_TARGET"))
            ui.menu.activateItem(ui.loadItem)
            stage = 9
        }
        if (stage == 9 && ui.loaded && !ui.hasRun && idle() && ui.sourceTabs.pageCount() == 2) {
            require(ui.breaks.text().contains("#1") && ui.failure.equals("") &&
                DebugUiFixture().closeButtons() == 2 && ui.source.text().contains("counter"),
                "File > Load Executable starts a fresh session with saved breakpoints and DWARF tabs")
            DebugUiFixture().choose(notes)
            ui.menu.activateItem(ui.openItem)
            stage = 10
        }
        if (stage == 10 && ui.sourceTabs.pageCount() == 3) {
            require(ui.source.text().contains("needle") && ui.loaded && !ui.hasRun &&
                ui.failure.equals(""), "File > Open Source Code opens text without loading it")
            require(ui.window.hasShortcut("<Control>q") && ui.window.hasShortcut("<Control>f"),
                "Quit and Find shortcuts bound on the window")
            ui.menu.activateItem(ui.quitItem)
            require(ui.closed && ui.process == null, "Quit closes the debugger and GDB")
            print("true")
            return false
        }
        return true
    }
    DebugChecks _self()
    bool idle() { return ui.active == null && ui.requests.length == 0 }
    bool persistenceTick() {
        if (!ui.loaded || !idle()) { return true }
        String path = System.Process().getEnv("CDBG_TEST_SOURCE")
        int line = System.Process().getEnv("CDBG_TEST_LINE").toInt()
        if (mode.equals("state-save")) {
            if (stage == 0) {
                require(ui.showSource(path, format("{}", line)), "source for saved breakpoint")
                ui.menu.activateItem(ui.toggleBreakItem)
                stage = 1
                return true
            }
            if (stage == 1) {
                require(ui.breakpointLocations.length == 1, "saved breakpoint resolves")
                ui.menu.activateItem(ui.toggleEnableItem)
                stage = 2
                return true
            }
            require(DebugUiFixture().disabled(line), "saving disabled breakpoint")
            if (stage == 2) {
                ui.window.setDefaultSize(980, 680)
                ui.body.setPosition(420)
                ui.inspection.setCurrentPage(4)
                if (System.Process().getEnv("CDBG_TEST_MAXIMIZE").equals("true")) {
                    ui.window.setMaximized(true)
                }
                stage = 3
                return true
            }
            if (System.Process().getEnv("CDBG_TEST_MAXIMIZE").equals("true") && !ui.window.maximized()) {
                return true
            }
            ui.body.setPosition(420)
        } else {
            require(ui.failure.equals(""), "restore failure does not fail session")
            if (mode.equals("state-restore")) {
                if (System.Process().getEnv("CDBG_TEST_MAXIMIZE").equals("true") &&
                    !ui.window.maximized()) { return true }
                require(ui.breakpointLocations.length == 1, "breakpoint restored after real relaunch")
                require(ui.showSource(path, format("{}", line)) && DebugUiFixture().disabled(line),
                    "restored disabled breakpoint has gray mark")
                require(ui.window.defaultWidth() == 980 && ui.window.defaultHeight() == 680 &&
                    ui.body.position() == 420 && ui.inspection.currentPage() == 4,
                    format("window geometry and layout restored: {}x{} pane {} tab {}, state {}",
                        ui.window.defaultWidth(), ui.window.defaultHeight(), ui.body.position(),
                        ui.inspection.currentPage(), ui.stateText))
                require(Gtk.Config().value(ui.stateText, "", "maximized").equals(
                    format("b{}", System.Process().getEnv("CDBG_TEST_MAXIMIZE"))),
                    "maximized state saved and restored")
                require(ui.stateTarget.equals(System.FileSystem().absolutePath(
                    System.Process().getEnv("CDBG_TEST_TARGET"))), "canonical target persistence key")
            } else {
                if (mode.equals("state-stale")) {
                    require(ui.breakpointLocations.length == 1 && !DebugUiFixture().disabled(line) &&
                        ui.console.text().contains("Stale breakpoint") &&
                        ui.console.text().contains("Could not restore"),
                        "stale and unresolvable locations skipped; valid breakpoint restored")
                } else { if (mode.equals("state-conflict")) {
                    System.File changed = System.File(ui.statePath, "w")
                    String external = "version = 1\nexternal = true\n"
                    require(changed.write(external) == external.length, "external state edit written")
                    changed.close()
                } else { if (mode.equals("state-global")) {
                    require(ui.breakpointLocations.length == 0 && ui.stateWritable &&
                        ui.console.text().contains("is ignored; settings now live in") &&
                        ui.statePath.endsWith("/.cdbg.toml"), "global state ignored, not imported")
                } else { if (mode.equals("state-unwritable")) {
                    if (stage == 0) {
                        require(ui.showSource(path, format("{}", line)), "source for unwritable test")
                        ui.menu.activateItem(ui.toggleBreakItem)
                        stage = 1
                        return true
                    }
                    if (stage == 1) {
                        require(ui.breakpointLocations.length == 1 &&
                            ui.console.text().contains("Settings not saved to") &&
                            ui.status.text().contains("Settings not saved"),
                            "unwritable directory reported; breakpoint still installed")
                        stops = ui.stopCount
                        ui.resume()
                        stage = 2
                        return true
                    }
                    if (ui.stopCount == stops || ui.running) { return true }
                    if (ui.status.text().startsWith("Stopped at start:")) {
                        stops = ui.stopCount
                        ui.resume()
                        return true
                    }
                    require(ui.location.contains(format(":{} (", line)) &&
                        ui.console.text().split("Settings not saved to").length == 2,
                        "debugging continues; diagnostic reported once")
                } else { if (mode.equals("state-clamped")) {
                    require(ui.stateNumber("width", 1100, 640, 3840) == 3840 &&
                        ui.window.defaultWidth() >= 640 && ui.window.defaultWidth() <= 3840 &&
                        ui.window.defaultHeight() == 400 &&
                        ui.body.position() >= 100 && ui.body.position() <= 3740 &&
                        ui.inspection.currentPage() == 6, "out-of-range layout values clamped")
                } else {
                    require(ui.breakpointLocations.length == 0 &&
                        ui.window.defaultWidth() >= 640 && ui.window.defaultWidth() <= 1100 &&
                        ui.window.defaultHeight() == 760 &&
                        ui.inspection.currentPage() == 0 && !ui.stateWritable,
                        format("corrupt defaults: {}x{} tab {} writable {} locations {}",
                            ui.window.defaultWidth(), ui.window.defaultHeight(), ui.inspection.currentPage(),
                            ui.stateWritable, ui.breakpointLocations.length))
                } } } } }
            }
        }
        ui.window.close()
        require(ui.closed && ui.process == null, "persistent session quit cleans GDB")
        print("true")
        return false
    }
    bool contextTick() {
        String path = System.Process().getEnv("CDBG_TEST_SOURCE")
        String helper = System.FileSystem().join(System.FileSystem().dirname(path), "context_helper.c")
        if (stage == 0 && ui.loaded && idle()) {
            require(DebugUiFixture().compact(), "main window has no breakpoint/watch/frame rows or End Session")
            ui.showSource(path, "")
            if (!DebugUiFixture().lineClick("", 7, "")) { return true }
            ui.menu.activateItem(ui.toggleBreakItem)
            require(ui.source.line() == 7, format("source context click positions cursor at line 7, got {}",
                ui.source.line()))
            stage = 1
        }
        if (stage == 1 && idle()) {
            require(ui.breaks.text().contains("#1") && DebugUiFixture().marks("context.c", 7) == 1,
                "resolved file:line breakpoint has a colored mark and icon")
            require(ui.source.line() == 7, "adding marks retains source cursor")
            require(DebugUiFixture().shortcut("F9"), "F9 clears clicked breakpoint")
            stage = 2
        }
        if (stage == 2 && idle()) {
            require(ui.breaks.text().equals("") && DebugUiFixture().marks("context.c", 7) == 0,
                "source context delete removes breakpoint and marker")
            require(DebugUiFixture().shortcut("<Control>F9") &&
                ui.status.text().equals("No breakpoint at the current source line"),
                "enable/disable without a breakpoint reports clear status")
            require(DebugUiFixture().shortcut("F9"), "F9 sets clicked breakpoint")
            stage = 3
        }
        if (stage == 3 && idle()) {
            require(ui.breaks.text().contains("#2") && DebugUiFixture().marks("context.c", 7) == 1,
                "source breakpoint restored")
            ui.addBreakpoint("shared_point")
            stage = 4
        }
        if (stage == 4 && idle()) {
            require(ui.breaks.text().contains("#3") && DebugUiFixture().marks("context.c", 3) == 1 &&
                DebugUiFixture().marks("context_helper.c", 2) == 1,
                "multiple GDB breakpoint locations marked in all source tabs")
            ui.showSource(path, "3")
            if (!DebugUiFixture().lineClick("", 3, "")) { return true }
            ui.menu.activateItem(ui.toggleEnableItem)
            stage = 5
        }
        if (stage == 5 && idle()) {
            require(DebugUiFixture().disabled(3), format("multiple breakpoint disabled with gray mark: {}",
                ui.breaks.text()))
            require(ui.showSource(helper, "2") && DebugUiFixture().disabled(2),
                "disabling parent updates every multiple location")
            if (!DebugUiFixture().lineClick("", 2, "")) { return true }
            require(DebugUiFixture().shortcut("<Control>F9"), "Ctrl+F9 enables multi-location breakpoint")
            stage = 50
        }
        if (stage == 50 && idle()) {
            require(!DebugUiFixture().disabled(2), "Ctrl+F9 restores enabled-state mark")
            require(DebugUiFixture().shortcut("F9"), "F9 clears entire multi-location breakpoint")
            stage = 51
        }
        if (stage == 51 && idle()) {
            require(!ui.breaks.text().contains("#3") && ui.breaks.text().contains("#2") &&
                DebugUiFixture().marks("context.c", 3) == 0 &&
                DebugUiFixture().marks("context_helper.c", 2) == 0 &&
                DebugUiFixture().marks("context.c", 7) == 1,
                "selected breakpoint deletion clears every child marker, not other breakpoints")
            ui.showSource(path, "")
            require(DebugUiFixture().closeTab("context.c"), "close marked source tab")
            require(ui.showSource(path, "") && DebugUiFixture().marks("context.c", 7) == 1,
                "reopened tab inherits breakpoint marks")
            require(DebugUiFixture().noBreakMenus(), "obsolete source and Breakpoints context menus absent")
            if (!DebugUiFixture().lineClick("Watches (Cwhip / Native)", 1, "Add Watch...")) { return true }
            require(DebugUiFixture().watchDialog("ignored", false) && ui.expressions.length == 0,
                "parented watch dialog Cancel adds nothing")
            stage = 6
        }
        if (stage == 6) {
            if (!DebugUiFixture().lineClick("Watches (Cwhip / Native)", 1, "Add Watch...")) { return true }
            require(DebugUiFixture().watchDialog("counter", true), "watch dialog Add accepts expression")
            stage = 7
        }
        if (stage == 7) {
            if (!DebugUiFixture().lineClick("Watches (Cwhip / Native)", 1, "Add Watch...")) { return true }
            require(DebugUiFixture().watchDialog("not_in_scope", true), "watch dialog accepts unknown expression")
            require(ui.expressions.length == 2, "watch expressions retained")
            ui.resume()
            stage = 8
        }
        if (stage == 8 && ui.stopCount > 0 && !ui.running && idle()) {
            require(ui.source.line() == 7 && ui.source.text().contains("int main") &&
                ui.watches.text().contains("counter = 21") &&
                ui.watches.text().contains("not_in_scope = <"),
                "dialog watches evaluate at stop, including out-of-scope errors")
            require(DebugUiFixture().marks("context.c", 7) == 1, "stop retains distinct breakpoint marking")
            stops = ui.stopCount
            ui.restart()
            stage = 9
        }
        if (stage == 9 && ui.stopCount > stops && !ui.running && idle()) {
            require(DebugUiFixture().marks("context.c", 7) == 1 && ui.breaks.text().contains("#2"),
                "Restart retains breakpoint state and marks")
            stops = ui.stopCount
            ui.stepInto()
            stage = 10
        }
        if (stage == 10 && ui.stopCount > stops && !ui.running && idle()) {
            require(ui.source.text().contains("int doubled") && ui.source.line() == 5,
                "execution stops inside helper")
            stops = ui.stopCount
            if (!DebugUiFixture().lineClick("Stack", 2, "")) { return true }
            stage = 11
        }
        if (stage == 11 && idle()) {
            require(ui.selectedFrame == 1 && ui.source.text().contains("int main") &&
                ui.source.line() == 7 && ui.locals.text().contains("counter = 21") &&
                ui.watches.text().contains("counter = 21") && ui.stopCount == stops,
                "single stack click navigates caller and refreshes inspection without execution")
            ui.stepOver()
            stage = 12
        }
        if (stage == 12 && ui.stopCount > stops && !ui.running && idle()) {
            require(ui.selectedFrame == 0 && ui.source.text().contains("int doubled") &&
                ui.source.line() == 6 && ui.locals.text().contains("doubled = 42"),
                "Step Over restores actual execution frame and returns to helper's next line")
            require(ui.showSource(path, "") && DebugUiFixture().marks("context.c", 7) == 1,
                "switching files keeps markers")
            ui.loadTarget(System.Process().getEnv("CDBG_TEST_TARGET"))
            stage = 13
        }
        if (stage == 13 && ui.loaded && idle()) {
            require(ui.breaks.text().contains("#1") && DebugUiFixture().marks("context.c", 7) == 1 &&
                DebugUiFixture().marks("context_helper.c", 2) == 0 && !ui.hasRun,
                "fresh load restores saved breakpoint markers")
            ui.showSource(path, "5")
            ui.menu.activateItem(ui.toggleBreakItem)
            stage = 14
            return true
        }
        if (stage == 14 && idle()) {
            require(DebugUiFixture().marks("context.c", 6) == 1 && ui.source.line() == 5,
                "non-executable line resolves to nearby code without moving cursor")
            require(DebugUiFixture().shortcut("F9"), "F9 clears breakpoint from its original requested line")
            stage = 15
        }
        if (stage == 15 && idle()) {
            require(DebugUiFixture().marks("context.c", 6) == 0 && ui.breakpointLocations.length == 1,
                "relocated breakpoint toggle clears instead of creating duplicates")
            require(ui.failure.equals(""), ui.failure)
            ui.window.close()
            require(ui.closed && ui.process == null && ui.terminal == null && ui.pollToken == 0 &&
                ui.watchWindow.disposed(), "Quit cleans GDB, output transport, watch dialog and polling")
            print("true")
            return false
        }
        return true
    }
    bool stoppedAt(String line) {
        return ui.stopCount > stops && !ui.running && idle() && ui.location.contains(format(":{} (", line))
    }
    // Real Cwhip -g line breakpoints set via F9/menu must stop the inferior,
    // not merely paint a mark; Break at start, Setup, arguments and the
    // Program Output menu are exercised on the same live session.
    bool breaksTick() {
        String path = System.Process().getEnv("CDBG_TEST_SOURCE")
        String args = "one \"two words\" '' \"it's\""
        String output = "arg[1]=<one>\narg[2]=<two words>\narg[3]=<>\narg[4]=<it's>\ncwhip-output:42\n"
        if (stage == 0 && ui.loaded && idle()) {
            require(ui.failure.equals(""), ui.failure)
            if (mode.equals("breaks")) {
                require(ui.breakAtStart && ui.arguments.length == 0 && ui.breakpointLocations.length == 0,
                    "fresh local configuration breaks at start with no arguments")
                ui.menu.activateItem(ui.setupItem)
                require(!DebugUiFixture().setup(-1, "bad \"quote", "Apply") &&
                    ui.setupStatus.text().contains("Invalid arguments: unterminated quote") &&
                    ui.arguments.length == 0, "invalid arguments rejected; dialog stays open")
                require(DebugUiFixture().setup(1, args, "Apply"), "valid Setup applies and closes")
                require(ui.arguments.length == 4 && (ui.arguments[1] as String).equals("two words") &&
                    (ui.arguments[2] as String).equals("") && (ui.arguments[3] as String).equals("it's") &&
                    ui.status.text().contains("next Run"), "arguments parsed with shell quoting")
                ui.menu.activateItem(ui.setupItem)
                require(DebugUiFixture().setup(0, "changed", "Cancel") && ui.breakAtStart &&
                    ui.arguments.length == 4, "Cancel changes nothing")
                ui.showSource(path, "")
                stage = 100
            } else {
                require(ui.breakpointLocations.length == 3 && ui.arguments.length == 4 && ui.breakAtStart,
                    "breakpoints, arguments and Break at start restored from .cdbg.toml")
                ui.menu.activateItem(ui.setupItem)
                require(DebugUiFixture().setup(0, args, "Apply") && !ui.breakAtStart, "Break at start off")
                ui.resume()
                stage = 20
            }
            return true
        }
        if (stage == 100 && DebugUiFixture().lineClick("", 4, "")) {
            require(DebugUiFixture().shortcut("F9"), "F9 line 4")
            stage = 1
        }
        if (stage == 1 && idle()) {
            require(DebugUiFixture().lineClick("", 19, ""), "click line 19")
            ui.menu.activateItem(ui.toggleBreakItem)
            stage = 2
        }
        if (stage == 2 && idle()) {
            require(DebugUiFixture().lineClick("", 8, "") && DebugUiFixture().shortcut("F9"), "F9 line 8")
            stage = 3
        }
        if (stage == 3 && idle()) {
            require(ui.breakpointLocations.length == 3 && ui.breaks.text().contains("enabled installed") &&
                ui.breaks.text().contains("hits 0") && ui.breaks.text().contains("in cwhip.Counter.unused"),
                format("three installed line breakpoints listed: {}", ui.breaks.text()))
            stops = ui.stopCount
            ui.resume()
            stage = 4
        }
        if (stage == 4 && stoppedAt("11")) {
            require(ui.status.text().startsWith("Stopped at start:") && !ui.breaks.text().contains("temporary") &&
                ui.console.text().contains("Break at start: temporary breakpoint at breaks.cw:11 (main)"),
                "Break at start stops on the start line and its temporary breakpoint is consumed")
            stops = ui.stopCount
            ui.resume()
            stage = 5
        }
        if (stage == 5 && stoppedAt("4")) {
            require(!ui.breaks.text().contains("temporary") && ui.breaks.text().contains("hits 1"),
                "F9 breakpoint in a method stops the program")
            stops = ui.stopCount
            ui.resume()
            stage = 6
        }
        if (stage == 6 && stoppedAt("19")) {
            stops = ui.stopCount
            ui.resume()
            stage = 7
        }
        if (stage == 7 && !ui.hasRun && !ui.running && idle() && ui.programOutput.text().equals(output)) {
            require(ui.console.text().contains("Not reached during this run: #") &&
                ui.console.text().contains(":8 in cwhip.Counter.unused") &&
                ui.console.text().contains("(that code did not execute)") &&
                ui.console.text().split("Not reached during this run").length == 2 &&
                ui.status.text().contains("1 breakpoint(s) not reached"), "uncalled breakpoint reported")
            require(DebugUiFixture().lineClick("Program Output", 1, "Copy All") &&
                DebugUiFixture().clipboard(output) && !ui.programOutput.hasSelection(), "Copy All")
            require(ui.programOutput.findWith("arg[2]=<two words>", 0) && ui.programOutput.hasSelection(),
                "select output text")
            stage = 70
            return true
        }
        // Let the text layout settle before clicking at a line position.
        if (stage == 70) {
            if (!DebugUiFixture().lineClick("Program Output", 2, "Copy")) { return true }
            require(ui.programOutput.hasSelection(), "right-click inside the selection keeps it for Copy")
            require(DebugUiFixture().clipboard("arg[2]=<two words>"), "Copy copies only the selection")
            require(DebugUiFixture().lineClick("Program Output", 1, "Clear") &&
                ui.programOutput.text().equals("") && ui.loaded, "Clear empties only the displayed output")
            stops = ui.stopCount
            ui.restart()
            stage = 8
        }
        if (stage == 8 && stoppedAt("11")) {
            stops = ui.stopCount
            ui.restart()
            stage = 9
        }
        if (stage == 9 && stoppedAt("11")) {
            require(ui.console.text().split("Break at start: temporary").length == 4 &&
                !ui.breaks.text().contains("temporary") && ui.breakpointLocations.length == 3,
                format("one start breakpoint per run, none left over: {}", ui.breaks.text()))
            stops = ui.stopCount
            ui.resume()
            stage = 10
        }
        if (stage == 10 && stoppedAt("4")) { stops = ui.stopCount
            ui.resume()
            stage = 11 }
        if (stage == 11 && stoppedAt("19")) { stops = ui.stopCount
            ui.resume()
            stage = 12 }
        if (stage == 12 && !ui.hasRun && !ui.running && idle() && ui.programOutput.text().equals(output)) {
            ui.menu.activateItem(ui.quitItem)
            require(ui.closed && ui.process == null, "Quit cleans GDB")
            print("true")
            return false
        }
        if (stage == 20 && stoppedAt("4")) {
            require(!ui.status.text().contains("start"), "Break at start disabled: first stop is line 4")
            stops = ui.stopCount
            ui.menu.activateItem(ui.setupItem)
            require(DebugUiFixture().setup(1, "only", "Apply") && ui.hasRun && !ui.running &&
                ui.stopCount == stops && ui.location.contains(":4 ("), "Apply does not restart the program")
            ui.menu.activateItem(ui.setupItem)
            require(DebugUiFixture().setup(0, args, "Apply"), "restore setup")
            ui.restart()
            stage = 21
        }
        if (stage == 21 && stoppedAt("4")) {
            require(!ui.breaks.text().contains("temporary"), "restart with start off adds no start breakpoint")
            stops = ui.stopCount
            ui.resume()
            stage = 22
        }
        if (stage == 22 && stoppedAt("19")) { stops = ui.stopCount
            ui.resume()
            stage = 23 }
        if (stage == 23 && !ui.hasRun && !ui.running && idle() && ui.programOutput.text().endsWith(output)) {
            ui.window.close()
            require(ui.closed && ui.process == null, "close cleans GDB")
            print("true")
            return false
        }
        return true
    }
    void tick() {
        require(Time.Clock().monotonicMilliseconds() < deadline, "session deadline")
        if (mode.equals("values")) {
            if (valuesTick()) { Gtk.Application().post(_self().tick) }
            return
        }
        if (mode.equals("stepping")) {
            if (steppingTick()) { Gtk.Application().post(_self().tick) }
            return
        }
        if (mode.startsWith("breaks")) {
            if (breaksTick()) { Gtk.Application().post(_self().tick) }
            return
        }
        if (mode.startsWith("state-")) {
            if (persistenceTick()) { Gtk.Application().post(_self().tick) }
            return
        }
        if (mode.equals("ui")) {
            if (uiTick()) { Gtk.Application().post(_self().tick) }
            return
        }
        if (mode.equals("context")) {
            if (contextTick()) { Gtk.Application().post(_self().tick) }
            return
        }
        if (mode.equals("missing") || mode.equals("compile-error") || mode.equals("invalid-target") ||
            mode.equals("missing-file") || mode.equals("binary-source") || mode.equals("invalid-utf8") ||
            mode.equals("missing-source")) {
            if (!ui.failure.equals("")) {
                if (!mode.equals("missing-source")) {
                    require(!ui.loaded && !ui.running, "failed startup not success-shaped")
                }
                if (!mode.equals("missing")) {
                    if (!DebugUiFixture().alert()) { Gtk.Application().post(_self().tick)
                        return }
                }
                ui.endSession()
                ui.window.close()
                print("true")
                return
            }
        } else {
            require(ui.failure.equals(""), ui.failure)
            require(DebugUiFixture().panes(), "all text panes read-only without Emoji hint")
            if (mode.equals("scroll")) {
                if (stage == 0 && ui.loaded && idle()) {
                    ui.addBreakpoint(format("{}:{}", System.Process().getEnv("CDBG_TEST_SOURCE"),
                        System.Process().getEnv("CDBG_TEST_LINE")))
                    stage = 1
                }
                if (stage == 1 && idle()) { ui.resume()
                    stage = 2 }
                if (stage == 2 && ui.stopCount > 0 && !ui.running && idle() &&
                    DebugUiFixture().centered()) {
                    require(DebugUiFixture().noEmoji(), "actual context menu omits Insert Emoji")
                    DebugUiFixture().track()
                    stops = ui.stopCount
                    ui.stepOver()
                    stage = 3
                }
                if (stage == 3 && ui.stopCount > stops && !ui.running && idle() &&
                    DebugUiFixture().centered()) {
                    require(DebugUiFixture().changes() == 0, "step retains source buffer text")
                    require(ui.sourceTabs.pageCount() == 1, "steps reuse existing file tab")
                    ui.window.close()
                    print("true")
                    return
                }
                Gtk.Application().post(_self().tick)
                return
            }
            if (mode.equals("no-source") && ui.loaded && idle()) {
                require(ui.source.text().startsWith("Source unavailable:"),
                    "missing debug source explicitly reported")
                require(DebugUiFixture().shortcut("<Control>q") && ui.closed && ui.process == null,
                    "Ctrl+Q quits through the window shortcut")
                print("true")
                return
            }
            if (mode.equals("no-source")) {
                Gtk.Application().post(_self().tick)
                return
            }
            if (mode.equals("cancel")) {
                if (stage == 0 && ui.loaded && idle()) { ui.resume()
                    stage = 1 }
                if (stage == 1 && ui.running && idle() && ui.programOutput.text().contains("ready")) {
                    ui.interrupt()
                    stage = 2 }
                if (stage == 2 && !ui.running && ui.stopCount > 0 && idle()) {
                    require(!ui.inferiorPid.equals(""), "inferior PID received")
                    ui.resume()
                    stage = 3
                }
                if (stage == 3 && ui.running && idle()) {
                    oldPid = ui.inferiorPid
                    ui.restart()
                    stage = 4
                }
                if (stage == 4 && ui.running && idle() && !ui.restarting &&
                    !ui.inferiorPid.equals(oldPid)) {
                    String pid = ui.inferiorPid
                    ui.window.close()
                    require(ui.closed && ui.process == null && ui.pollToken == 0,
                        "close running session cleans up")
                    print(format("true:{}:{}", oldPid, pid))
                    return
                }
                Gtk.Application().post(_self().tick)
                return
            }
            if (stage == 0 && ui.loaded && idle()) {
                require(ui.source.text().contains("counter"), "source visible immediately after Load")
                require(DebugUiFixture().noEmoji(), "source context menu excludes Emoji")
                if (mode.equals("native")) {
                    require(ui.sourceTabs.pageCount() == 2, "multiple source files have tabs")
                }
                ui.addBreakpoint(format("{}:{}", System.Process().getEnv("CDBG_TEST_SOURCE"),
                    System.Process().getEnv("CDBG_TEST_LINE")))
                stage = 1
            }
            if (stage == 1 && idle()) {
                require(ui.breaks.text().contains("#1"), "breakpoint listed")
                ui.addWatch("counter")
                ui.addWatch("not_in_scope")
                ui.resume()
                stage = 2
            }
            if (stage == 2 && ui.stopCount >= 1 && !ui.running && idle()) {
                require(ui.location.contains(System.Process().getEnv("CDBG_TEST_SOURCE")), "source stop")
                require(ui.source.text().contains("counter"), "source displayed")
                require(ui.source.line() == System.Process().getEnv("CDBG_TEST_LINE").toInt(),
                    "current source line highlighted")
                require(ui.locals.text().contains("counter = 21"), "DWARF scalar local")
                require(ui.watches.text().contains("counter = 21") &&
                    ui.watches.text().contains("not_in_scope = <"), format("watches and evaluation failure: {} / {}",
                        ui.watches.text(), ui.console.text()))
                require(ui.stack.text().contains("#0"), "stack")
                ui.addWatch("counter + 1")
                ui.selectFrame("0")
                stage = 3
            }
            if (stage == 3 && idle()) {
                require(ui.watches.text().contains("counter + 1 = 22") &&
                    ui.watches.text().split("counter = 21").length == 2,
                    "new watches and frame refresh replace stale inspection")
                stops = ui.stopCount
                oldPid = ui.inferiorPid
                ui.restart()
                stage = 30
            }
            if (stage == 30 && ui.stopCount > stops && !ui.running && idle()) {
                require(!ui.inferiorPid.equals(oldPid), "Restart replaces stopped inferior")
                require(ui.breaks.text().contains("#1") &&
                    ui.watches.text().contains("counter + 1 = 22"),
                    "Restart preserves breakpoints and watches")
                stops = ui.stopCount
                ui.stepInto()
                stage = 4
            }
            if (stage == 4 && ui.stopCount > stops && !ui.running && idle()) {
                if (mode.equals("native")) {
                    require(ui.source.text().contains("doubled") && ui.sourceTabs.pageCount() == 2,
                        "stop switches to helper file without a duplicate tab")
                }
                stops = ui.stopCount
                ui.stepOver()
                stage = 5
            }
            if (stage == 5 && ui.stopCount > stops && !ui.running && idle()) {
                stops = ui.stopCount
                ui.stepOut()
                stage = 6
            }
            if (stage == 6 && ui.stopCount > stops && !ui.running && idle()) {
                ui.deleteBreakpoint("1")
                stage = 7
            }
            if (stage == 7 && idle()) {
                require(!ui.breaks.text().contains("#1"), "breakpoint deleted")
                ui.resume()
                stage = 8
            }
            if (stage == 8 && !ui.hasRun && !ui.running && idle()) {
                require(ui.status.text().contains("exited"), "normal inferior exit")
                if (mode.equals("native")) {
                    if (!ui.programOutput.text().contains("stderr-only")) {
                        Gtk.Application().post(_self().tick)
                        return
                    }
                    require(ui.programOutput.text().contains("stdout-only") &&
                        ui.programOutput.text().contains("^9999^done") &&
                        ui.programOutput.text().contains("\\0") &&
                        ui.programOutput.text().length <= 65536 &&
                        !ui.console.text().contains("stdout-only") &&
                        !ui.console.text().contains("stderr-only"),
                        "stdout/stderr and MI-like inferior output isolated from GDB")
                } else {
                    if (!ui.programOutput.text().contains("cwhip-output:42")) {
                        Gtk.Application().post(_self().tick)
                        return
                    }
                    require(!ui.console.text().contains("cwhip-output:42"),
                        "Cwhip output uses Program Output")
                }
                ui.restart()
                stage = 9
            }
            if (stage == 9 && !ui.hasRun && !ui.running && idle() && !ui.restarting) {
                require(ui.status.text().contains("exited"), "Restart after exit runs target again")
                ui.loadTarget(System.Process().getEnv("CDBG_TEST_TARGET"))
                stage = 10
            }
            if (stage == 10 && ui.loaded && idle()) {
                require(!ui.hasRun && !ui.running && ui.breaks.text().equals("") &&
                    ui.source.text().contains("counter"), "Load reloads source without running")
                ui.endSession()
                require(ui.process == null && !ui.loaded && ui.pollToken == 0 &&
                    ui.temporary.equals(""), "owned process and temporary cleanup")
                ui.window.close()
                print("true")
                return
            }
        }
        Gtk.Application().post(_self().tick)
    }
}
DebugChecks DebugChecks._self() from "cwhip_gtk_self"
start {
    Gtk.Application app = Gtk.Application("org.cwhip.CdbgTests")
    DebugChecks checks = DebugChecks()
    app.onActivate(checks.activate)
    app.run()
}
'''

C_FIXTURE = """\
#include "helper.c"
#include <stdio.h>
/* fixture */
/* fixture */
int main(void) {
    int counter = 21;
    counter = helper(counter);
    for (int index = 0; index < 23000; ++index) fputs("\\xe2\\x82\\xac", stdout);
    puts("stdout-only");
    fputs("stderr-only\\n", stderr);
    puts("^9999^done");
    const unsigned char binary[] = {0, 255, '\\n'};
    fwrite(binary, 1, sizeof binary, stdout);
    return counter == 42 ? 0 : 1;
}
"""

BREAKS_FIXTURE = """\
import system
class Counter {
    int double(int value) {
        int doubled = value * 2
        return doubled
    }
    int unused(int value) {
        return value + 1
    }
}
start {
    Counter worker = Counter()
    int counter = worker.double(21)
    int i = 1
    while (i < System.Process().argc()) {
        print(format("arg[{}]=<{}>\\n", i, System.Process().arg(i)))
        i = i + 1
    }
    print(format("cwhip-output:{}\\n", counter))
}
"""

CW_FIXTURE = """\
class Counter {
    int double(int value) {
        int doubled = value * 2
        return doubled
    }
}
start {
    Counter worker = Counter()
    int counter = 21
    counter = worker.double(counter)
    print(format("cwhip-output:{}", counter))
}
"""

STEPPING_FIXTURE = """\
class Counter {
    int double(int value) {
        int doubled = value * 2
        return doubled
    }
}
start {
    Counter worker = Counter()
    int counter = 21
    counter = worker.double(counter)
    counter = counter + 1
    counter = counter + 2
    print(format("result:{}", counter))
}
"""

VALUES_FIXTURE = r'''class Counter {
    int value
}
start {
    int counter = 21
    unsigned positive = 42u
    bool truth = true
    float fraction = 1.5
    String message = "café\n\"quoted\"\\path"
    String missing = null
    Counter worker = Counter()
    list items = [21, true, "hello", [1, [2, [3]]], 4, 5, 6, 7, 8]
    dict mapping = {"key": 42}
    buffer bytes = buffer[1, 2, 255]
    String longText = ""
    while (longText.length < 300) {
        longText.append("a")
    }
    counter = counter + 1
    print(counter)
}
'''

VALUE_CHECKS = r'''
import gdb
scope = {}
exec(open(SCRIPT, encoding="utf-8").read(), scope)
friendly, inspect = scope["friendly"], scope["inspect"]
value = gdb.parse_and_eval("message")
assert friendly(value, True) == '"café\\n\\"quoted\\"\\\\path"'
assert friendly(value, False) == scope["raw"](value)  # native frames never decode Cwhip pointers
assert friendly(gdb.parse_and_eval("missing"), True) == "null"
bad = gdb.Value(1).cast(value.type)
assert "<unreadable:" in inspect("bad", bad, True)["friendly"]
assert "<members unavailable" not in friendly(value, True)
for expression in ["counter = 1", "counter++", "fn()", "(*fn)()", "p[0]()", "counter;continue", "(String *)1"]:
    try:
        scope["safe_expression"](expression)
    except (gdb.error, gdb.GdbError):
        pass
    else:
        raise AssertionError(expression)
for expression in ["counter + 1", "counter", "(counter + 1) * 2", "items[0]", "p->field"]:
    scope["safe_expression"](expression)
assert scope["quoted"](b'a\x00"\n\\\xff') == '"a\\u0000\\"\\n\\\\\\\\xff"'
# Exercise explicit optimized/unavailable branches independently of GDB's
# platform-dependent ability to rematerialize optimized native locals.
class Optimized:
    is_optimized_out = True
assert friendly(Optimized(), True) == "<optimized out>"
class Unavailable:
    is_optimized_out = False
    is_unavailable = True
assert friendly(Unavailable(), True) == "<unavailable>"
assert friendly(gdb.parse_and_eval("worker"), True).startswith("Counter <1 fields; members unavailable")
assert scope["dynamic"](gdb.parse_and_eval("(CwhipArrayValue){10,0,0,0}"), 0).startswith("<runtime tag 10:")
print("VALUE_CHECKS_PASS")
'''

# Record the real process boundary, not a simulated MI transport. Only GDB's
# stdin/stdout are proxied; the inferior still uses cdbg's separate PTY.
MI_TRACE = r'''
import os
import subprocess
import sys
import threading
p = subprocess.Popen([os.environ["CDBG_REAL_GDB"], *sys.argv[1:]],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE)
with open(os.environ["CDBG_MI_TRACE"], "wb", buffering=0) as trace:
    def forward():
        for line in sys.stdin.buffer:
            trace.write(b"> " + line)
            try:
                p.stdin.write(line)
                p.stdin.flush()
            except BrokenPipeError:
                break
    threading.Thread(target=forward, daemon=True).start()
    for line in p.stdout:
        trace.write(b"< " + line)
        sys.stdout.buffer.write(line)
        sys.stdout.buffer.flush()
sys.exit(p.wait())
'''


def compile_program(compiler: Path, source: Path, output: Path, work: Path,
                    env: dict[str, str], objects: list[Path] | None = None) -> None:
    result = invoke([str(compiler), str(source), "-o", str(output)] +
                    [str(obj) for obj in objects or []], work, env)
    assert result.returncode == 0, result.stderr


def binary_smoke(executable: Path, target: Path, compiler: Path, gdb: str,
                 xvfb: str, work: Path, env: dict[str, str]) -> None:
    with headless(xvfb, work, env) as gtk_env:
        gtk_env.update(CDBG_COMPILER=str(compiler), CDBG_GDB=gdb)
        process = subprocess.Popen([str(executable), str(target)], cwd=work, env=gtk_env,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        display = Display(gtk_env["DISPLAY"])
        gdb_pid = None
        try:
            window = display.focus_editor()
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and process.poll() is None:
                children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text()
                for child in children.split():
                    try:
                        if Path(f"/proc/{child}/exe").resolve().name == Path(gdb).name:
                            gdb_pid = int(child)
                    except FileNotFoundError:
                        pass
                if gdb_pid is not None:
                    break
                time.sleep(0.05)
            assert gdb_pid is not None, "actual cdbg did not compile and start GDB"
            display.settle(0.5)
            display.delete_window(window)
            output = process.communicate(timeout=10)[0]
            assert process.returncode == 0, output
            assert not output, output
            assert not Path(f"/proc/{gdb_pid}").exists(), "actual cdbg leaked GDB on close"
        finally:
            display.close()
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=10)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--executable", type=Path)
    parser.add_argument("--build", type=Path)
    parser.add_argument("--cmake")
    parser.add_argument("--gdb")
    parser.add_argument("--clang")
    parser.add_argument("--xvfb")
    parser.add_argument("--group", choices=("parser", "session", "build"), required=True)
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.work.mkdir(parents=True, exist_ok=True)
    if args.group == "build":
        command = [args.cmake, "--build", str(args.build), "--target", "cdbg"]
        subprocess.run(command, check=True, timeout=120)
        outputs = [args.executable, args.compiler]
        before = [path.stat().st_mtime_ns for path in outputs]
        subprocess.run(command, check=True, timeout=120)
        assert before == [path.stat().st_mtime_ns for path in outputs], "No-op cdbg rebuild"
        result = subprocess.run([str(args.executable), "--help"], capture_output=True, text=True,
                                timeout=10)
        assert result.returncode == 0 and "Usage: cdbg" in result.stdout, result
        assert not result.stderr, result.stderr
        return
    with tempfile.TemporaryDirectory(dir=args.work.resolve(), prefix="cdbg-") as directory:
        work = Path(directory)
        env = environment(work)
        shutil.copy(args.source.parent / "mi.cw", work / "mi.cw")
        shutil.copy(args.source.parent / "terminal.cw", work / "terminal.cw")
        source = work / "checks.cw"
        binary = work / "checks"
        if args.group == "parser":
            source.write_text('import system\n' + PARSER)
            compile_program(args.compiler, source, binary, work, env)
            result = invoke([str(binary)], work, env)
            assert result.returncode == 0 and result.stdout == "true", result
            assert not result.stderr, result.stderr
            return
        source.write_text(args.source.read_text().split("\nstart {")[0] + DRIVER)
        root = args.source.resolve().parents[2]
        fixture = work / "ui.o"
        terminal = work / "terminal.o"
        gtk_flags = subprocess.check_output(
            ["pkg-config", "--cflags", "gtk4", "gtksourceview-5"], text=True).split()
        subprocess.run([args.clang, "-g", "-c", str(root / "tests/cdbg_ui_fixture.c"),
                        "-I", str(root / "include"), *gtk_flags, "-o", str(fixture)], check=True)
        subprocess.run([sys.executable, str(args.source.parent / "embed_values.py"),
                        str(args.source.parent / "values.py"), str(work / "values.h")], check=True)
        subprocess.run([args.clang, "-c", str(args.source.parent / "terminal.c"),
                        "-I", str(root / "include"), "-I", str(work), "-o", str(terminal)], check=True)
        compile_program(args.compiler, source, binary, work, env, [fixture, terminal])
        (work / "helper.c").write_text(
            "int helper(int value) {\n    int doubled = value * 2;\n    return doubled;\n}\n")
        c_source = work / 'target with "quotes".c'
        c_source.write_text(C_FIXTURE)
        c_binary = work / "native target"
        subprocess.run([args.clang, "-g", "-O0", str(c_source), "-o", str(c_binary)], check=True)
        context_source = work / "context.c"
        context_source.write_text(
            "int helper(int value);\nstatic int shared_point(int value) {\n return value + 1;\n}\n"
            "int main(void) {\n int counter = 21;\n counter = helper(counter);\n"
            " return counter == shared_point(41) ? 0 : 1;\n}\n")
        context_helper = work / "context_helper.c"
        context_helper.write_text(
            "static int shared_point(int value) {\n return value + 1;\n}\n"
            "int helper(int value) {\n int doubled = value * 2;\n"
            " return doubled + shared_point(0) - 1;\n}\n")
        context_binary = work / "context target"
        subprocess.run([args.clang, "-g", "-O0", str(context_source), str(context_helper),
                        "-o", str(context_binary)], check=True)
        stripped_binary = work / "no debug info"
        subprocess.run([args.clang, str(c_source), "-o", str(stripped_binary)], check=True)
        (work / "notes.txt").write_text("alpha\nneedle one\nbeta\nneedle two\n")
        vanished_source = work / "vanished.c"
        vanished_source.write_text("int main(void) { return 0; }\n")
        vanished_binary = work / "vanished"
        subprocess.run([args.clang, "-g", str(vanished_source), "-o", str(vanished_binary)], check=True)
        vanished_source.unlink()
        loop_source = work / "loop.c"
        loop_source.write_text('#include <stdio.h>\nint main(void) { volatile unsigned counter = 0; '
                               'puts("ready"); fflush(stdout); while (1) { counter++; } }\n')
        loop_binary = work / "loop"
        subprocess.run([args.clang, "-g", "-O0", str(loop_source), "-o", str(loop_binary)], check=True)
        cw_source = work / "target with spaces.cw"
        cw_source.write_text(CW_FIXTURE)
        values_source = work / "values.cw"
        values_source.write_text(VALUES_FIXTURE)
        values_binary = work / "values"
        result = invoke([str(args.compiler), str(values_source), "-g", "-o", str(values_binary)], work, env)
        assert result.returncode == 0, result.stderr
        value_checks = work / "value-checks.py"
        value_checks.write_text("SCRIPT = " + repr(str(args.source.parent.resolve() / "values.py")) +
                                "\n" + VALUE_CHECKS)
        value_result = invoke([args.gdb, "-q", "-nx", "--batch", str(values_binary),
                               "-ex", "set host-charset UTF-8",
                               "-ex", f"break {values_source}:19", "-ex", "run",
                               "-ex", f"source {value_checks}"], work, env)
        assert value_result.returncode == 0 and "VALUE_CHECKS_PASS" in value_result.stdout, value_result
        optimized_source = work / "optimized.c"
        optimized_source.write_text(
            "extern int puts(const char *); volatile int input = 42;\n"
            "__attribute__((noinline)) void snapshot(void) {\n"
            " int removed = input;\n"
            " volatile int marker = 0; puts(\"checkpoint\");\n"
            " marker++;\n"
            " marker++;\n"
            "}\nint main(void) { snapshot(); return 0; }\n")
        optimized_binary = work / "optimized"
        subprocess.run([args.clang, "-g", "-O2", str(optimized_source), "-o", str(optimized_binary)], check=True)
        optimized_checks = work / "optimized-checks.py"
        optimized_checks.write_text(
            "import gdb\nscope = {}\nexec(open(" +
            repr(str(args.source.parent.resolve() / "values.py")) + ").read(), scope)\n"
            "value = gdb.selected_frame().read_var('removed')\n"
            "assert value.is_optimized_out, str(value)\n"
            "assert scope['inspect']('removed', value, False)['friendly'] == '<optimized out>'\n"
            "print('OPTIMIZED_CHECK_PASS')\n")
        optimized_result = invoke([args.gdb, "-q", "-nx", "--batch", str(optimized_binary),
                                   "-ex", f"break {optimized_source}:6", "-ex", "run",
                                   "-ex", f"source {optimized_checks}"], work, env)
        assert optimized_result.returncode == 0 and "OPTIMIZED_CHECK_PASS" in optimized_result.stdout, optimized_result
        bad_source = work / "bad.cw"
        bad_source.write_text("start { missing_symbol() }\n")
        binary_source = work / "binary.cw"
        binary_source.write_bytes(b"\x00not source")
        invalid_utf8 = work / "invalid-utf8.cw"
        invalid_utf8.write_bytes(b"\xffnot source")
        invalid_target = work / "invalid-target"
        invalid_target.write_text("This is not an executable\n")
        scroll_source = work / "scroll.c"
        scroll_source.write_text("\n" * 120 +
            "int main(void) {\n volatile int counter = 21;\n counter++;\n counter++;\n return 0;\n}\n" +
            "\n" * 150)
        scroll_binary = work / "scroll"
        subprocess.run([args.clang, "-g", "-O0", str(scroll_source), "-o", str(scroll_binary)], check=True)
        # Legacy modes share one local settings file, without Break at start.
        (work / ".cdbg.toml").write_text("version = 1\nbreak_at_start = false\n")
        for mode, target, debug_source, line in (
            ("values", values_source, values_source, "19"),
            ("native", c_binary, c_source, "7"),
            ("cwhip", cw_source, cw_source, "10"),
            ("relative-cwhip", Path(cw_source.name), cw_source, "10"),
            ("no-source", stripped_binary, c_source, "7"),
            ("missing", c_binary, c_source, "7"),
            ("compile-error", bad_source, bad_source, "1"),
            ("invalid-target", invalid_target, invalid_target, "1"),
            ("missing-file", work / "missing.cw", work / "missing.cw", "1"),
            ("binary-source", binary_source, binary_source, "1"),
            ("invalid-utf8", invalid_utf8, invalid_utf8, "1"),
            ("missing-source", vanished_binary, vanished_source, "1"),
            ("scroll", scroll_binary, scroll_source, "123"),
            ("cancel", loop_binary, loop_source, "1"),
            ("ui", c_binary, c_source, "7"),
            ("context", context_binary, context_source, "7"),
        ):
            with headless(args.xvfb, work, env) as gtk_env:
                gtk_env.update(CDBG_TEST_MODE=mode, CDBG_TEST_TARGET=str(target),
                               CDBG_TEST_WORK=str(work),
                               CDBG_TEST_SOURCE=str(debug_source), CDBG_TEST_LINE=line,
                               CDBG_COMPILER=str(args.compiler),
                               CDBG_GDB=args.gdb if mode != "missing" else str(work / "no-gdb"))
                result = invoke([str(binary)], work, gtk_env, timeout=45)
                expected_output = result.stdout == "true"
                if mode == "cancel":
                    expected_output = result.stdout.startswith("true:")
                    for value in result.stdout.split(":")[1:]:
                        pid = int(value)
                        deadline = time.monotonic() + 5
                        while Path(f"/proc/{pid}").exists() and time.monotonic() < deadline:
                            time.sleep(0.05)
                        assert not Path(f"/proc/{pid}").exists(), f"orphan inferior {pid}"
                assert result.returncode == 0 and expected_output, (
                    mode, result.returncode, result.stdout, result.stderr)
                if mode == "ui":
                    lines = [line for line in result.stderr.splitlines() if line]
                    assert len(lines) == 4 and all(line.startswith("cdbg: ") for line in lines), (
                        result.stderr)
                elif mode in ("values", "native", "cwhip", "relative-cwhip", "no-source", "cancel", "scroll", "context"):
                    assert not result.stderr, result.stderr
                else:
                    assert "cdbg:" in result.stderr, result.stderr
        binary_smoke(args.executable.resolve(), cw_source, args.compiler, args.gdb,
                     args.xvfb, work, env)

        stepping_work = work / "stepping-work"
        stepping_work.mkdir()
        stepping_source = stepping_work / "stepping.cw"
        stepping_source.write_text(STEPPING_FIXTURE)
        proxy = work / "trace-gdb"
        proxy.write_text(f"#!{sys.executable}\n" + MI_TRACE)
        proxy.chmod(0o700)
        trace = work / "stepping.mi"
        runtime_lines = (root / "src/RuntimeGc.c").read_text().splitlines()
        entry = next(i for i, line in enumerate(runtime_lines, 1)
                     if line.startswith("void cwhip_gc_require_alive("))
        runtime_entry = next(i for i in range(entry, entry + 8)
                             if "if (object == NULL)" in runtime_lines[i - 1])
        runtime_call = next(i for i in range(entry, entry + 12)
                            if "HeapNode *node = find_containing_object" in runtime_lines[i - 1])
        with headless(args.xvfb, work, env) as gtk_env:
            gtk_env.update(CDBG_TEST_MODE="stepping", CDBG_TEST_TARGET=str(stepping_source),
                           CDBG_TEST_SOURCE=str(stepping_source), CDBG_COMPILER=str(args.compiler),
                           CDBG_GDB=str(proxy), CDBG_REAL_GDB=args.gdb, CDBG_MI_TRACE=str(trace),
                           CDBG_RUNTIME_ENTRY=str(runtime_entry), CDBG_RUNTIME_CALL=str(runtime_call))
            result = invoke([str(binary)], stepping_work, gtk_env, timeout=45)
            transcript = trace.read_text() if trace.exists() else "(no MI trace)"
            # Keep the last live transcript available even when the temp test
            # directory is removed, including on assertion failure.
            (args.work / "stepping.mi").write_text(transcript)
            assert result.returncode == 0 and result.stdout == "true" and not result.stderr, (
                result, transcript)
            commands = [line.split(" ", 1)[1] for line in transcript.splitlines()
                        if line.startswith("> ")]
            steps = [line for line in commands
                     if any(command in line for command in ("-exec-next", "-exec-step", "-exec-finish"))]
            assert len(steps) == 21, (steps, transcript)
            browse = max(i for i, line in enumerate(commands) if line.endswith("-stack-select-frame 1"))
            after = [line.lstrip("0123456789") for line in commands[browse + 1:]]
            finish = after.index("-exec-finish")
            assert "-stack-select-frame 0" in after[:finish] and not any(
                line.startswith("-exec-") for line in after[:finish]), commands[browse:]
            assert "-stack-select-frame 0" in transcript, transcript
            assert transcript.count('reason="function-finished"') == 3, transcript

        def state_run(mode: str, target: Path, debug_source: Path, line: int,
                      state_env: dict[str, str], cwd: Path) -> None:
            cwd.mkdir(exist_ok=True)
            with headless(args.xvfb, work, state_env) as gtk_env:
                gtk_env.update(CDBG_TEST_MODE=mode, CDBG_TEST_TARGET=str(target),
                               CDBG_TEST_SOURCE=str(debug_source), CDBG_TEST_LINE=str(line),
                               CDBG_COMPILER=str(args.compiler), CDBG_GDB=args.gdb,
                               CDBG_TEST_MAXIMIZE="false")
                # Exercise real maximize/restore when a test WM is available.
                wm = shutil.which("xfwm4")
                manager = None
                with (work / "wm.log").open("w") as log:
                    try:
                        if wm and mode in ("state-save", "state-restore"):
                            manager_env = dict(gtk_env)
                            manager_env.pop("SESSION_MANAGER", None)
                            manager = subprocess.Popen(
                                [wm, "--sm-client-disable", "--replace", "--compositor=off"], env=manager_env,
                                                       stdout=log, stderr=log)
                            time.sleep(0.4)
                            assert manager.poll() is None, (work / "wm.log").read_text()
                            gtk_env["CDBG_TEST_MAXIMIZE"] = "true"
                        result = invoke([str(binary)], cwd, gtk_env, timeout=45)
                        assert result.returncode == 0 and result.stdout == "true", (
                            mode, result.returncode, result.stdout, result.stderr)
                        if mode in ("state-save", "state-restore", "state-clamped", "state-global",
                                    "breaks", "breaks-restore"):
                            assert not result.stderr, result.stderr
                        else:
                            assert "cdbg state:" in result.stderr, result.stderr
                            assert "CRITICAL" not in result.stderr, result.stderr
                    finally:
                        if manager:
                            manager.terminate()
                            manager.wait(timeout=10)

        import json
        import tomllib
        native_alias = work / "native symlink"
        native_alias.symlink_to(c_binary)
        for name, target, debug_source, line in (
            ("native", native_alias, c_source, 7), ("cwhip", cw_source, cw_source, 10)
        ):
            state_env = environment(work / ("state-" + name))
            local = work / ("local-" + name)
            state_run("state-save", target, debug_source, line, state_env, local)
            state_file = local / ".cdbg.toml"
            assert state_file.is_file()
            saved = tomllib.loads(state_file.read_text())
            assert str(target.resolve()) in saved, saved
            assert saved[str(target.resolve())]["points"][0]["enabled"] is False
            assert "target" not in saved, "Temporary compiled executable must not be a state key"
            state_run("state-restore", target, debug_source, line, state_env, local)
            assert not (Path(state_env["XDG_CONFIG_HOME"]) / "cdbg").exists(), "No global state written"
            assert not (Path(state_env["HOME"]) / ".config/cdbg").exists(), "No HOME state written"

        stale_env = environment(work / "state-stale")
        stale_dir = work / "local-stale"
        stale_dir.mkdir()
        (stale_dir / ".cdbg.toml").write_text("version = 1\n[" + json.dumps(str(c_binary.resolve())) +
            "]\npoints = [\n{ file = " + json.dumps(str(c_source)) +
            ', line = 7, enabled = true },\n{ file = ' + json.dumps(str(work / "vanished.c")) +
            ', line = 1, enabled = false },\n{ file = ' + json.dumps(str(work / "notes.txt")) +
            ", line = 999, enabled = true },\n]\n")
        state_run("state-stale", c_binary, c_source, 7, stale_env, stale_dir)
        corrupt_env = environment(work / "state-corrupt")
        corrupt_dir = work / "local-corrupt"
        corrupt_dir.mkdir()
        corrupt_file = corrupt_dir / ".cdbg.toml"
        corrupt_file.write_text("invalid [ TOML")
        state_run("state-corrupt", c_binary, c_source, 7, corrupt_env, corrupt_dir)
        assert corrupt_file.read_text() == "invalid [ TOML", "Corrupt state should not be overwritten"
        conflict_env = environment(work / "state-conflict")
        conflict_dir = work / "local-conflict"
        state_run("state-conflict", c_binary, c_source, 7, conflict_env, conflict_dir)
        assert (conflict_dir / ".cdbg.toml").read_text() == "version = 1\nexternal = true\n", (
            "Atomic save must not overwrite another writer")
        clamped_env = environment(work / "state-clamped")
        clamped_dir = work / "local-clamped"
        clamped_dir.mkdir()
        (clamped_dir / ".cdbg.toml").write_text(
            "version = 1\nwidth = 99999\nheight = 0\npane = 9999\ninspector = 99\nmaximized = false\n")
        state_run("state-clamped", c_binary, c_source, 7, clamped_env, clamped_dir)
        # An old global XDG file is reported but never imported or modified.
        global_env = environment(work / "state-global")
        global_file = Path(global_env["XDG_CONFIG_HOME"]) / "cdbg/state.toml"
        global_file.parent.mkdir()
        global_text = ("version = 1\n[" + json.dumps(str(c_binary.resolve())) + "]\npoints = [\n{ file = " +
                       json.dumps(str(c_source)) + ", line = 7, enabled = true },\n]\n")
        global_file.write_text(global_text)
        global_dir = work / "local-global"
        state_run("state-global", c_binary, c_source, 7, global_env, global_dir)
        assert global_file.read_text() == global_text, "global state must stay unchanged"
        local_global = tomllib.loads((global_dir / ".cdbg.toml").read_text())
        assert not local_global.get(str(c_binary.resolve()), {}).get("points"), local_global
        # An unwritable working directory: debugging continues, nothing is saved.
        unwritable_env = environment(work / "state-unwritable")
        unwritable_dir = work / "local-unwritable"
        unwritable_dir.mkdir()
        unwritable_dir.chmod(0o555)
        try:
            if not os.access(unwritable_dir, os.W_OK):
                state_run("state-unwritable", c_binary, c_source, 7, unwritable_env, unwritable_dir)
                assert not list(unwritable_dir.iterdir()), "no settings file in unwritable directory"
        finally:
            unwritable_dir.chmod(0o755)
        # Real Cwhip -g line breakpoints from F9/menu stop the program; Setup,
        # arguments and Break at start persist across a real quit and relaunch.
        breaks_source = work / "breaks.cw"
        breaks_source.write_text(BREAKS_FIXTURE)
        breaks_env = environment(work / "state-breaks")
        breaks_dir = work / "local-breaks"
        state_run("breaks", breaks_source, breaks_source, 4, breaks_env, breaks_dir)
        saved = tomllib.loads((breaks_dir / ".cdbg.toml").read_text())
        entry = saved[str(breaks_source.resolve())]
        assert entry["break_at_start"] is True and entry["arguments"] == "one 'two words' '' 'it'\\''s'", entry
        assert sorted(point["line"] for point in entry["points"]) == [4, 8, 19], entry
        assert all(point["enabled"] for point in entry["points"]), entry
        state_run("breaks-restore", breaks_source, breaks_source, 4, breaks_env, breaks_dir)
        entry = tomllib.loads((breaks_dir / ".cdbg.toml").read_text())[str(breaks_source.resolve())]
        assert entry["break_at_start"] is False and len(entry["points"]) == 3, entry
        assert not (Path(breaks_env["XDG_CONFIG_HOME"]) / "cdbg").exists(), "No global state written"

if __name__ == "__main__":
    main()
