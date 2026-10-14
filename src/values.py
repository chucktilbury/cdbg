"""Read-only, bounded GDB/MI inspection for Cwhip and native frames."""
import json
import re
import struct
import gdb

LIMIT = 256
CHILDREN = 8
DEPTH = 2


def quoted(data):
    return json.dumps(data.decode("utf-8", errors="backslashreplace"), ensure_ascii=False)


def read_bytes(address, size):
    if size < 0:
        raise gdb.GdbError("Invalid negative byte count")
    return bytes(gdb.selected_inferior().read_memory(address, min(size, LIMIT)))


def runtime_object(value, name):
    # Named runtime structs come from DWARF, never inferred address offsets.
    return value.cast(gdb.lookup_type(name).pointer()).dereference()


def raw(value):
    return value.format_string(raw=True, max_elements=CHILDREN, max_depth=DEPTH)


def metadata(value):
    return runtime_object(value, "CwhipStringObject")["metadata"].dereference()


def object_name(value):
    meta = metadata(value)
    length = int(meta["name_length"])
    name = read_bytes(meta["name"], length).decode("utf-8", errors="backslashreplace")
    return name + (" <truncated type name>" if length > LIMIT else "")


def object_summary(value, name):
    meta = metadata(value)
    actual = object_name(value)
    if actual != name:
        return "<{} reference; runtime type {}; members unavailable>".format(name, actual)
    return "{} <{} fields; members unavailable; {}>".format(
        name, int(meta["field_count"]), raw(value))


def dynamic(value, depth):
    tag = int(value["tag"])
    integer = int(value["integer"])
    if tag == 1:
        return str(integer)
    if tag == 8:
        return str(integer & ((1 << 64) - 1))
    if tag == 6:
        return "true" if integer else "false"
    if tag == 7:
        return str(struct.unpack("=d", struct.pack("=Q", integer & ((1 << 64) - 1)))[0])
    if tag == 2:
        return string(value["pointer"])
    if tag == 3:
        pointer = value["pointer"]
        if int(pointer) == 0:
            return "null"
        name = object_name(pointer)
        if name == "String":
            return string(pointer)
        if name in ("list", "dict", "buffer"):
            return container(pointer, name, depth)
        return object_summary(pointer, name)
    if tag in (4, 5, 9):
        name = {4: "dict", 5: "list", 9: "buffer"}[tag]
        return container(value["pointer"], name, depth)
    return "<runtime tag {}: {}>".format(tag, raw(value["pointer"]))


def string(value):
    if int(value) == 0:
        return "null"
    if object_name(value) != "String":
        return "<invalid String runtime type>"
    obj = runtime_object(value, "CwhipStringObject")
    buf = runtime_object(obj["bytes"], "CwhipBuffer")
    length = int(buf["length"])
    if length < 0 or length > int(buf["capacity"]):
        return "<invalid String buffer>"
    result = quoted(read_bytes(buf["data"], length))
    return result + (" … <truncated; {} bytes>".format(length) if length > LIMIT else "")


def container(value, name, depth):
    if int(value) == 0:
        return "null"
    obj = runtime_object(value, {"list": "CwhipArray", "dict": "CwhipMap",
                                "buffer": "CwhipBuffer"}[name])
    length = int(obj["length"])
    if length < 0 or length > int(obj["capacity"]):
        return "<invalid {} length>".format(name)
    if depth >= DEPTH:
        return "{}[{}] <depth limit>".format(name, length)
    if name == "buffer":
        result = read_bytes(obj["data"], length).hex(" ")
    else:
        parts = []
        for i in range(min(length, CHILDREN)):
            entry = obj["values" if name == "list" else "entries"][i]
            if name == "list":
                parts.append(dynamic(entry, depth + 1))
            else:
                key_length = int(entry["key_length"])
                key = quoted(read_bytes(entry["key"], key_length))
                if key_length > LIMIT:
                    key += " <truncated>"
                parts.append(key + ": " + dynamic(entry["value"], depth + 1))
        result = ", ".join(parts)
    limit = LIMIT if name == "buffer" else CHILDREN
    return "{}[{}] {{{}}}{}".format(name, length, result,
                                   " … <truncated>" if length > limit else "")


def friendly(value, cwhip, depth=0):
    if value.is_optimized_out:
        return "<optimized out>"
    if getattr(value, "is_unavailable", False):
        return "<unavailable>"
    typ = value.type.strip_typedefs()
    if not cwhip:
        return raw(value)
    if typ.code == gdb.TYPE_CODE_BOOL:
        return "true" if bool(value) else "false"
    if typ.code in (gdb.TYPE_CODE_INT, gdb.TYPE_CODE_FLT, gdb.TYPE_CODE_CHAR):
        return raw(value)
    if typ.code != gdb.TYPE_CODE_PTR:
        return raw(value) + " <structure not decoded>"
    name = typ.target().name or str(typ.target())
    if int(value) == 0:
        return "null"
    if name == "String":
        return string(value)
    if name in ("list", "dict", "buffer"):
        return container(value, name, depth)
    # Opaque class debug types lack members. Say so instead of guessing fields.
    if typ.target().code == gdb.TYPE_CODE_STRUCT:
        if name in ("handle", "callback"):
            return raw(value) + " <opaque handle>"
        return object_summary(value, name)
    return raw(value)


def inspect(name, value, cwhip):
    result = {"name": name, "type": str(value.type)}
    try:
        original = raw(value)
        result["raw"] = original[:4096]
        if len(original) > 4096:
            result["raw"] += " <truncated>"
        result["friendly"] = friendly(value, cwhip)
    except (gdb.error, gdb.GdbError, ValueError, OverflowError) as error:
        result["friendly"] = "<unreadable: {}>".format(error)
        result.setdefault("raw", "<unreadable: {}>".format(error))
    return result


def safe_expression(expression):
    # Permit read-only arithmetic and member/index access, not calls, pointer casts,
    # assignments, increment/decrement, string literals or GDB commands.
    if len(expression) > 1024 or not re.fullmatch(r"[\w\s.+*/%<>&|^!~()\[\]-]+", expression):
        raise gdb.GdbError("Watch supports read-only identifiers, members, indexing and arithmetic")
    if re.search(r"\+\+|--|\w\s*\(|[)\]]\s*\(|\(\s*\w+\s*\*+\s*\)", expression) or "=" in expression:
        raise gdb.GdbError("Watch calls, pointer casts and mutations are not supported")


class Inspector(gdb.MICommand):
    def __init__(self):
        super().__init__("-cdbg-inspect")

    def invoke(self, argv):
        frame = gdb.selected_frame()
        sal = frame.find_sal()
        cwhip = bool(sal.symtab and sal.symtab.filename.endswith(".cw"))
        if len(argv) == 2 and argv[0] == "watch":
            safe_expression(argv[1])
            return inspect(argv[1], gdb.parse_and_eval(argv[1]), cwhip)
        if argv != ["locals"]:
            raise gdb.GdbError("Expected locals or watch EXPRESSION")
        rows, names = [], set()
        block = frame.block()
        while block:
            for symbol in block:
                if not (symbol.is_argument or symbol.is_variable) or symbol.name in names:
                    continue
                names.add(symbol.name)
                if len(rows) >= 64:
                    return {"variables": rows, "truncated": "true"}
                try:
                    rows.append(inspect(symbol.name, frame.read_var(symbol), cwhip))
                except gdb.error as error:
                    rows.append({"name": symbol.name, "type": "", "raw": str(error),
                                 "friendly": "<unavailable: {}>".format(error)})
            if block.function:
                break
            block = block.superblock
        return {"variables": rows}


Inspector()
