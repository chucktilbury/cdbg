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
        int64 i = 0
        while (i < keys.length) {
            if ((keys[i] as String).equals(key)) { return values[i] as MiValue }
            i = i + 1
        }
        return MiValue()
    }
}

class MiParser {
    String input
    int64 offset
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
        return value.length == 1 && int64(value.byteAt(0)) >= 48 && int64(value.byteAt(0)) <= 57
    }
    String word() {
        int64 first = offset
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
            int64 byte = int64(input.byteAt(offset))
            offset = offset + 1
            if (byte == 92) {
                if (offset >= input.length) { valid = false
                    return "" }
                byte = int64(input.byteAt(offset))
                offset = offset + 1
                if (byte >= 48 && byte <= 55) {
                    int64 number = byte - 48
                    int64 count = 1
                    while (count < 3 && offset < input.length &&
                           int64(input.byteAt(offset)) >= 48 && int64(input.byteAt(offset)) <= 55) {
                        number = number * 8 + int64(input.byteAt(offset)) - 48
                        offset = offset + 1
                        count = count + 1
                    }
                    if (number > 255) { valid = false
                        return "" }
                    byte = number
                } else {
                    String escapes = "nrtbfv\\\"'"
                    list replacements = [10, 13, 9, 8, 12, 11, 92, 34, 39]
                    int64 index = escapes.find(input.slice(offset - 1, offset))
                    if (index < 0) { valid = false
                        return "" }
                    byte = int64(replacements[index] as int8)
                }
            }
            bytes.append(uint64(byte))
        }
        take("\"")
        Process.OutputDecoder decoder = Process.OutputDecoder()
        String text = decoder.decode(bytes)
        text.append(decoder.finish())
        return text
    }
    MiValue value(int64 depth) {
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
                    // Older GDB versions append unlabelled child locations
                    // after a multi-location bkpt result/notification.
                    if (character().equals("{") && data.keys.length > 0 &&
                        (data.keys[data.keys.length - 1] as String).equals("bkpt")) {
                        MiValue parent = data.values[data.values.length - 1] as MiValue
                        MiValue child = value(0)
                        if (!child.field("number").text.startsWith(
                            format("{}.", parent.field("number").text))) { valid = false }
                        MiValue locations = parent.field("locations")
                        if (locations.values.length == 0) {
                            parent.keys.append("locations")
                            parent.values.append(locations)
                        }
                        locations.keys.append("")
                        locations.values.append(child)
                    } else {
                        String key = word()
                        take("=")
                        data.keys.append(key)
                        data.values.append(value(0))
                    }
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

// Shell-like inferior argument parsing without invoking a shell: blanks
// separate words; '...' is literal; "..." honours \" \\ \$ \` escapes; an
// unquoted backslash escapes the next character; '' and "" give empty words.
class ArgumentList {
    list values
    String error

    ArgumentList() {
        values = []
        error = ""
    }
    String word(buffer bytes) {
        Process.OutputDecoder decoder = Process.OutputDecoder()
        String text = decoder.decode(bytes)
        text.append(decoder.finish())
        return text
    }
    bool parse(String text) {
        values = []
        error = ""
        buffer current = buffer[]
        bool started = false
        int64 quote = 0
        int64 i = 0
        while (i < text.length) {
            int64 c = int64(text.byteAt(i))
            i = i + 1
            if (quote == 39) {
                if (c == 39) { quote = 0 } else { current.append(uint64(c)) }
            } else { if (quote == 34) {
                if (c == 34) { quote = 0 } else {
                    if (c == 92 && i < text.length && (int64(text.byteAt(i)) == 34 ||
                        int64(text.byteAt(i)) == 92 || int64(text.byteAt(i)) == 36 ||
                        int64(text.byteAt(i)) == 96)) {
                        current.append(text.byteAt(i))
                        i = i + 1
                    } else { current.append(uint64(c)) }
                }
            } else {
                if (c == 32 || c == 9 || c == 10 || c == 13) {
                    if (started) { values.append(word(current))
                        current = buffer[]
                        started = false }
                } else {
                    started = true
                    if (c == 39 || c == 34) { quote = c } else { if (c == 92) {
                        if (i >= text.length) {
                            error = "trailing backslash"
                            values = []
                            return false
                        }
                        current.append(text.byteAt(i))
                        i = i + 1
                    } else { current.append(uint64(c)) } }
                }
            } }
        }
        if (quote != 0) {
            error = "unterminated quote"
            values = []
            return false
        }
        if (started) { values.append(word(current)) }
        return true
    }
    String display(list items) {
        String text = ""
        int64 i = 0
        while (i < items.length) {
            String item = items[i] as String
            if (i > 0) { text.append(" ") }
            if (item.equals("") || item.contains(" ") || item.contains("\t") || item.contains("\n") ||
                item.contains("\r") || item.contains("'") || item.contains("\"") || item.contains("\\")) {
                text.append(format("'{}'", item.replace("'", "'\\''")))
            } else { text.append(item) }
            i = i + 1
        }
        return text
    }
}
