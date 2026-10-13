import process

class MiValue {
    String text
    list keys
    list values

    MiValue() {
        text = ""
        keys = []
        values = []
    }
    MiValue field(String key) {
        int i = 0
        while (i < keys.length) {
            if ((keys[i] as String).equals(key)) { return values[i] as MiValue }
            i = i + 1
        }
        return MiValue()
    }
}

class MiParser {
    String input
    int offset
    bool valid
    String token
    String kind
    String result
    MiValue data

    String character() {
        if (offset >= input.length) { return "" }
        return input.slice(offset, offset + 1)
    }
    bool take(String expected) {
        if (!character().equals(expected)) { valid = false
            return false }
        offset = offset + 1
        return true
    }
    bool digit(String value) {
        return value.length == 1 && int(value.byteAt(0)) >= 48 && int(value.byteAt(0)) <= 57
    }
    String word() {
        int first = offset
        while (offset < input.length && !character().equals("=") &&
               !character().equals(",") && !character().equals("}") &&
               !character().equals("]")) { offset = offset + 1 }
        if (first == offset) { valid = false }
        return input.slice(first, offset)
    }
    String quoted() {
        buffer bytes = buffer[]
        if (!take("\"")) { return "" }
        while (offset < input.length && !character().equals("\"") && valid) {
            int byte = int(input.byteAt(offset))
            offset = offset + 1
            if (byte == 92) {
                if (offset >= input.length) { valid = false
                    return "" }
                byte = int(input.byteAt(offset))
                offset = offset + 1
                if (byte >= 48 && byte <= 55) {
                    int number = byte - 48
                    int count = 1
                    while (count < 3 && offset < input.length &&
                           int(input.byteAt(offset)) >= 48 && int(input.byteAt(offset)) <= 55) {
                        number = number * 8 + int(input.byteAt(offset)) - 48
                        offset = offset + 1
                        count = count + 1
                    }
                    if (number > 255) { valid = false
                        return "" }
                    byte = number
                } else {
                    String escapes = "nrtbfv\\\"'"
                    list replacements = [10, 13, 9, 8, 12, 11, 92, 34, 39]
                    int index = escapes.find(input.slice(offset - 1, offset))
                    if (index < 0) { valid = false
                        return "" }
                    byte = replacements[index] as int
                }
            }
            bytes.append(unsigned(byte))
        }
        take("\"")
        Process.OutputDecoder decoder = Process.OutputDecoder()
        String text = decoder.decode(bytes)
        text.append(decoder.finish())
        return text
    }
    MiValue value(int depth) {
        MiValue node = MiValue()
        if (depth > 32) { valid = false
            return node }
        if (character().equals("\"")) { node.text = quoted()
            return node }
        String open = character()
        if (!open.equals("{") && !open.equals("[")) { valid = false
            return node }
        offset = offset + 1
        String close = "}"
        if (open.equals("[")) { close = "]" }
        while (valid && offset < input.length && !character().equals(close)) {
            String key = ""
            if (!character().equals("\"") && !character().equals("{") &&
                !character().equals("[")) {
                key = word()
                take("=")
            } else { if (open.equals("{")) { valid = false } }
            node.keys.append(key)
            node.values.append(value(depth + 1))
            if (!character().equals(close)) {
                take(",")
                if (character().equals(close)) { valid = false }
            }
        }
        take(close)
        return node
    }
    void parse(String line) {
        input = line
        offset = 0
        valid = true
        token = ""
        kind = ""
        result = ""
        data = MiValue()
        while (digit(character())) {
            token.append(character())
            offset = offset + 1
        }
        kind = character()
        offset = offset + 1
        if (kind.equals("~") || kind.equals("@") || kind.equals("&")) {
            data.text = quoted()
        } else {
            if (kind.equals("^") || kind.equals("*") || kind.equals("=") ||
                kind.equals("+")) {
                result = word()
                while (valid && offset < input.length) {
                    take(",")
                    String key = word()
                    take("=")
                    data.keys.append(key)
                    data.values.append(value(0))
                }
            } else { valid = false }
        }
        if (offset != input.length) { valid = false }
    }
    String quote(String text) {
        return format("\"{}\"", text.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t"))
    }
}
