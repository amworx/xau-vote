"""Locate brace imbalance in a Dart/JS-like source file.

Handles single/double/triple quoted strings and // and /* */ comments so the
count reflects real code structure. Used to find the exact line where a
refactor dropped a closing brace.
"""

import sys


def scan(path: str) -> None:
    src = open(path, encoding="utf-8", errors="replace").read()
    depth = 0
    line = 1
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        # comments
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
        # triple-quoted strings
        if src[i : i + 3] in ("'''", '"""'):
            q = src[i : i + 3]
            i += 3
            while i < n and src[i : i + 3] != q:
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 3
            continue
        # single-line strings
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
            if depth < 0:
                print(f"EXTRA closing brace at line {line}")
                return
        i += 1
    print(f"final depth: {depth}")


if __name__ == "__main__":
    scan(sys.argv[1])