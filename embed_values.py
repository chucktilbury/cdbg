"""Embed the GDB inspector in cdbg, without runtime script-path dependencies."""
import json
import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
output.write_text("static const char cdbg_values_script[] =\n" +
                  "\n".join(json.dumps(line, ensure_ascii=True)
                            for line in source.read_text().splitlines(keepends=True)) +
                  ";\n")
