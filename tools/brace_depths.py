"""Print the running brace depth at each top-level declaration.

Used to localise an unbalanced brace introduced by a mechanical edit: the last
declaration whose depth is non-zero, or the first one that should return to a
known depth, pinpoints the region that lost a closer.
"""

import sys


def depths(path: str) -> list[tuple[int, int, str]]:
    src = open(path, encoding="utf-8", errors="replace").read()
    lines = src.split("\n")
    out: list[tuple[int, int, str]] = []
    depth = 0
    i = 0
    n = len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            stripped = lines[line - 1].strip()
            if stripped.startswith(("class ", "mixin ", "enum ", "extension ")):
                out.append((line, depth, stripped[:70]))
            i += 1
            continue
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
            continue
        if src.startswith("/*", i):
            i += 2
            while i < n and not src.startswith("*/", i):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2
            continue
        if src[i : i + 3] in ("'''", '"""'):
            q = src[i : i + 3]
            i += 3
            while i < n and src[i : i + 3] != q:
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 3
            continue
        if c in ("'", '"'):
            q = c
            i += 1
            while i < n and src[i] != q:
                if src[i] == "\\":
                    i += 1
                if i < n and src[i] == "\n":
                    line += 1
                i += 1
            i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return out


if __name__ == "__main__":
    for line, d, text in depths(sys.argv[1]):
        flag = "  <-- non-zero" if d != 0 else ""
        print(f"L{line:>5} depth={d}{flag}  {text}")