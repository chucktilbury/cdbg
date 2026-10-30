"""Focused numeric-v2 inspection and real debugger source-stepping coverage."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from gtk_support import headless
from program_runner import environment, invoke
from test_cdbg import DRIVER, MI_TRACE, STEPPING_FIXTURE, VALUES_FIXTURE, compile_program


NUMERIC = r'''
start {
    int8 s8 = -128
    uint8 u8 = 255u
    int16 s16 = -32768
    uint16 u16 = 65535u
    int32 s32 = -2147483648
    uint32 u32 = 4294967295u
    int64 s64 = -9223372036854775808
    uint64 u64 = 18446744073709551615u
    fp32 f32 = 0.1
    fp64 f64 = 0.1f64
    int nativeInt = 21
    uint nativeUint = 42u
    float nativeFloat = 0.25
    list small = [s8, u8, s16, u16, s32, u32, f32, nativeInt, nativeUint, nativeFloat]
    list wide = [s64, u64, f64]
    dict smallMap = ["s8": s8, "u8": u8, "s16": s16, "u16": u16, "s32": s32, "u32": u32, "f32": f32, "nativeInt": nativeInt, "nativeUint": nativeUint, "nativeFloat": nativeFloat]
    dict wideMap = ["s64": s64, "u64": u64, "f64": f64]
    fp32 negativeZero = -0.0
    fp32 infinity = fp32(1.0) / fp32(0.0)
    fp32 nanValue = fp32(0.0) / fp32(0.0)
    fp32 subnormal = 1e-45
    list special = [negativeZero, infinity, nanValue, subnormal]
    range<int8> narrow = int8(-128)..int8(127)
    range<int64> signedBounds = int64(-9223372036854775808)..int64(9223372036854775807)
    range<uint64> unsignedBounds = uint64(0u)..uint64(18446744073709551615u)
    range<int64> descending = int64(3)..int64(1)
    range<int64> missingRange = null
    list boxedRanges = [narrow, signedBounds, unsignedBounds, descending, missingRange]
    dict rangeMap = ["signed": signedBounds, "unsigned": unsignedBounds, "descending": descending, "missing": missingRange]
    for (iterator in descending) {
        bool iteratorMarker = iterator == 3
    }
    bool exact = (small[0] is int8 && !(small[0] is int64) &&
        small[6] is fp32 && !(small[6] is fp64) && wide[2] is fp64)
    int64 extracted = int64(small[0] as int8)
    if (!exact || extracted != -128) { System.Process().exit(1) }
    bool rejected = false
    try { int64 wrong = small[0] as int64 }
    except(Exception) { rejected = true }
    if (!rejected) { System.Process().exit(2) }
    s64 = s64 + 1
    print("NUMERIC_RUNTIME_PASS")
}
'''

CHECKS = r'''
import gdb, math
scope = {}
exec(open(SCRIPT, encoding="utf-8").read(), scope)
friendly, dynamic = scope["friendly"], scope["dynamic"]
expected = {
    "s8": ("int8", "-128"), "u8": ("uint8", "255"),
    "s16": ("int16", "-32768"), "u16": ("uint16", "65535"),
    "s32": ("int32", "-2147483648"), "u32": ("uint32", "4294967295"),
    "s64": ("int64", "-9223372036854775808"),
    "u64": ("uint64", "18446744073709551615"),
    "f32": ("fp32", "0.10000000149011612"), "f64": ("fp64", "0.1"),
    "nativeInt": ("int32", "21"), "nativeUint": ("uint32", "42"),
    "nativeFloat": ("fp32", "0.25"),
}
rows = {row["name"]: row for row in scope["Inspector"]().invoke(["locals"])["variables"]}
box = gdb.lookup_type("CwhipArrayValue")
assert box.sizeof == 32 and [field.name for field in box.fields()] == [
    "tag", "integer", "pointer", "length"]
for name, (typ, text) in expected.items():
    value = gdb.parse_and_eval(name)
    assert str(value.type) == typ, (name, str(value.type))
    assert rows[name]["friendly"] == friendly(value, True), rows[name]
    watched = scope["Inspector"]().invoke(["watch", name])
    assert watched == rows[name], (watched, rows[name])
    if typ.startswith("fp"):
        assert float(friendly(value, True)) == float(text), (name, friendly(value, True))
    else:
        assert friendly(value, True) == text, (name, friendly(value, True))
groups = [("small", "smallMap", ["s8", "u8", "s16", "u16", "s32", "u32", "f32",
                                  "nativeInt", "nativeUint", "nativeFloat"],
           [12, 13, 14, 15, 16, 17, 18, 16, 17, 18]),
          ("wide", "wideMap", ["s64", "u64", "f64"], [1, 8, 7])]
for array, mapping, names, tags in groups:
    values = scope["runtime_object"](gdb.parse_and_eval(array), "CwhipArray")["values"]
    entries = scope["runtime_object"](gdb.parse_and_eval(mapping), "CwhipMap")["entries"]
    shown_list = friendly(gdb.parse_and_eval(array), True)
    shown_map = friendly(gdb.parse_and_eval(mapping), True)
    for index, (name, tag) in enumerate(zip(names, tags)):
        text = expected[name][1]
        assert int(values[index]["tag"]) == tag, (name, values[index])
        assert dynamic(values[index], 0) == text, (name, dynamic(values[index], 0))
        assert int(entries[index]["value"]["tag"]) == tag, (name, entries[index])
        assert dynamic(entries[index]["value"], 0) == text, name
        if index < 8:
            assert text in shown_list and ('"' + name + '": ' + text) in shown_map
special = scope["runtime_object"](gdb.parse_and_eval("special"), "CwhipArray")["values"]
assert dynamic(special[0], 0) == "-0.0"
assert dynamic(special[1], 0) == "inf"
assert math.isnan(float(dynamic(special[2], 0)))
assert float(dynamic(special[3], 0)) == 2**-149
range_expected = {
    "narrow": "range<int8>(-128..127)",
    "signedBounds": "range<int64>(-9223372036854775808..9223372036854775807)",
    "unsignedBounds": "range<uint64>(0..18446744073709551615)",
    "descending": "range<int64>(3..1)",
    "missingRange": "null",
}
for name, text in range_expected.items():
    value = gdb.parse_and_eval(name)
    assert friendly(value, True) == text, (name, friendly(value, True))
    assert scope["Inspector"]().invoke(["watch", name])["friendly"] == text
boxed = scope["runtime_object"](gdb.parse_and_eval("boxedRanges"), "CwhipArray")["values"]
assert [int(boxed[i]["tag"]) for i in range(5)] == [19, 19, 19, 19, 3], [
    int(boxed[i]["tag"]) for i in range(5)]
assert [dynamic(boxed[i], 0) for i in range(5)] == list(range_expected.values()), [
    dynamic(boxed[i], 0) for i in range(5)]
mapping = scope["runtime_object"](gdb.parse_and_eval("rangeMap"), "CwhipMap")["entries"]
assert [dynamic(mapping[i]["value"], 0) for i in range(4)] == [
    range_expected["signedBounds"], range_expected["unsignedBounds"],
    range_expected["descending"], range_expected["missingRange"]], [
        dynamic(mapping[i]["value"], 0) for i in range(4)]
iterator = gdb.parse_and_eval("iterator")
assert friendly(iterator, True) == "3", friendly(iterator, True)
assert rows["iterator"]["friendly"] == "3", rows.get("iterator")
iterator_watch = scope["Inspector"]().invoke(["watch", "iterator"])
assert iterator_watch["friendly"] == "3", iterator_watch
for expression in ("boxedRanges", "rangeMap"):
    watched = scope["Inspector"]().invoke(["watch", expression])["friendly"]
    expected_values = range_expected.values() if expression == "boxedRanges" else [
        range_expected[name] for name in (
            "signedBounds", "unsignedBounds", "descending", "missingRange")]
    assert all(text in watched for text in expected_values), watched
# Decode the low bits, even if higher payload bits contain unrelated data.
for tag, bits, text in [(12, 255, "-1"), (13, -1, "255"),
                        (14, 65535, "-1"), (15, -1, "65535"),
                        (16, 4294967295, "-1"), (17, -1, "4294967295"),
                        (18, 0x123456783fc00000, "1.5")]:
    assert dynamic({"tag": tag, "integer": bits}, 0) == text
gdb.execute("disable 1")
gdb.execute("continue")
assert gdb.selected_frame().find_sal().symtab.filename.endswith("numeric.cw")
gdb.execute("next")
assert int(gdb.parse_and_eval("s64")) == -9223372036854775807
assert scope["Inspector"]().invoke(["watch", "s64"])["friendly"] == "-9223372036854775807"
print("NUMERIC_GDB_PASS")
'''


def main():
    parser = argparse.ArgumentParser()
    for name in ("compiler", "source", "include", "work", "executable"):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in ("gdb", "clang", "xvfb"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--sourceview-languages", type=Path, required=True)
    parser.add_argument("--group")
    parser.add_argument("--runtime-source")
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.work.resolve(), prefix="numeric-") as directory:
        work = Path(directory)
        env = environment(work)
        env["CDBG_SOURCEVIEW_LANGUAGES"] = str(args.sourceview_languages.resolve())
        numeric = work / "numeric.cw"
        numeric.write_text("import system\n" + NUMERIC)
        executable = work / "numeric"
        result = invoke([str(args.compiler), str(numeric), "-g", "-o", str(executable)], work, env)
        assert result.returncode == 0, result
        checks = work / "numeric_checks.py"
        checks.write_text("SCRIPT = " + repr(str(args.source.parent.resolve() / "values.py")) +
                          "\n" + CHECKS)
        line = next(i for i, text in enumerate(numeric.read_text().splitlines(), 1)
                    if text.strip() == "s64 = s64 + 1")
        range_line = next(i for i, text in enumerate(numeric.read_text().splitlines(), 1)
                          if text.strip() == "bool iteratorMarker = iterator == 3")
        result = invoke([args.gdb, "-q", "-nx", "--batch", str(executable),
                         "-ex", "set pagination off", "-ex", f"break {numeric}:{range_line}",
                         "-ex", f"break {numeric}:{line}",
                         "-ex", "run", "-ex", f"source {checks}", "-ex", "continue"], work, env)
        assert result.returncode == 0 and "NUMERIC_GDB_PASS" in result.stdout, result
        assert "NUMERIC_RUNTIME_PASS" in result.stdout, result
        assert not result.stderr or all(
            "Error disabling address space randomization" in text
            for text in result.stderr.splitlines()), result.stderr
        print("All ten numeric types: GDB locals/watches, boxed tags and runtime extraction passed",
              flush=True)

        for extra in args.source.parent.glob("*.cw"):
            if extra.name != args.source.name:
                shutil.copy(extra, work / extra.name)
        driver_source = work / "checks.cw"
        driver_source.write_text(args.source.read_text().split("\nstart {")[0] + DRIVER)
        driver = work / "checks"
        fixture, terminal = work / "ui.o", work / "terminal.o"
        flags = subprocess.check_output(
            ["pkg-config", "--cflags", "gtk4", "gtksourceview-5"], text=True).split()
        subprocess.run([args.clang, "-g", "-c",
                        str(args.source.parent.parent / "tests/cdbg_ui_fixture.c"),
                        "-I", str(args.include), *flags, "-o", str(fixture)], check=True)
        subprocess.run([sys.executable, str(args.source.parent / "embed_values.py"),
                        str(args.source.parent / "values.py"), str(work / "values.h")], check=True)
        subprocess.run([args.clang, "-c", str(args.source.parent / "terminal.c"),
                        "-I", str(args.include), "-I", str(work), "-o", str(terminal)], check=True)
        compile_program(args.compiler, driver_source, driver, work, env, [fixture, terminal])
        proxy = work / "trace-gdb"
        proxy.write_text(f"#!{sys.executable}\n" + MI_TRACE)
        proxy.chmod(0o700)
        for mode, contents in (("values", VALUES_FIXTURE), ("stepping", STEPPING_FIXTURE)):
            case = work / mode
            case.mkdir()
            source = case / ("stepping.cw" if mode == "stepping" else "values.cw")
            source.write_text(contents)
            trace = args.work.resolve() / f"numeric-{mode}.mi"
            with headless(args.xvfb, case, env) as gtk_env:
                test_line = next(
                    (index for index, text in enumerate(contents.splitlines(), 1)
                     if text.strip() == "counter = counter + 1"), "")
                gtk_env.update(CDBG_TEST_MODE=mode, CDBG_TEST_TARGET=str(source),
                               CDBG_TEST_SOURCE=str(source), CDBG_TEST_WORK=str(case),
                               CDBG_TEST_LINE=str(test_line),
                               CDBG_COMPILER=str(args.compiler), CDBG_GDB=str(proxy),
                               CDBG_REAL_GDB=args.gdb, CDBG_MI_TRACE=str(trace),
                               CDBG_RUNTIME_TEST="0")
                result = invoke([str(driver)], case, gtk_env, timeout=60)
                assert result.returncode == 0 and result.stdout == "true" and not result.stderr, (
                    result, trace.read_text() if trace.exists() else "no MI trace")
            transcript = trace.read_text()
            assert '-break-insert' in transcript and '-cdbg-inspect locals' in transcript
            assert '-cdbg-inspect watch' in transcript and '-exec-next' in transcript
            if mode == "stepping":
                assert '-exec-step' in transcript and '-exec-finish' in transcript
        print("Numeric-v2: all ten scalar/boxed types, locals, watches, breakpoints and stepping passed")


if __name__ == "__main__":
    main()
