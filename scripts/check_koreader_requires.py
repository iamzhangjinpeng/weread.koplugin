#!/usr/bin/env python3
"""Verify every KOReader module this plugin requires actually exists.

The plugin reaches into KOReader's own UI toolkit, and a single mistyped
directory in a require path is invisible to the Lua specs: those specs stub
`weread.ui.*` and the widgets wholesale, so the real file is never loaded.
Such a typo only surfaces on a device, as a crash when the page is opened.

This check parses every require() in the plugin and resolves it against a
KOReader checkout, so a wrong path fails the build instead.

Usage:
    python3 scripts/check_koreader_requires.py /path/to/koreader
"""

import os
import re
import sys

# Required by the plugin but not resolvable as a .lua file inside the
# checkout: compiled libraries loaded through package.cpath, LuaSocket, and
# modules KOReader ships inside frontend/ffi or the repository root.
C_MODULES = {
    "bit",
    "rapidjson",
    "ltn12",
    "socket",
    "socket.http",
    "socket.url",
    "socket.headers",
    "mime",
    "mime.core",
}

# Namespaces owned by the plugin itself.
OWN_PREFIXES = ("weread.", "weread/", "integrations.")

REQUIRE_RE = re.compile(r'require\s*\(\s*"([^"]+)"\s*\)')

SCAN_ORDERS = ("main.lua", "_meta.lua")
SCAN_ROOTS = ("weread", "integrations")


def lua_files(repo_root):
    for name in SCAN_ORDERS:
        path = os.path.join(repo_root, name)
        if os.path.isfile(path):
            yield path
    for sub in SCAN_ROOTS:
        base = os.path.join(repo_root, sub)
        for dirpath, _dirnames, filenames in os.walk(base):
            for filename in sorted(filenames):
                if filename.endswith(".lua"):
                    yield os.path.join(dirpath, filename)


def module_exists(koreader_root, module):
    if module.startswith("libs/"):
        return True
    if module in C_MODULES:
        return True
    relative = module.replace(".", "/")
    search_roots = (
        os.path.join(koreader_root, "frontend"),
        os.path.join(koreader_root, "ffi"),
        os.path.join(koreader_root, "common"),
        koreader_root,
    )
    for root in search_roots:
        if os.path.isfile(os.path.join(root, relative + ".lua")):
            return True
        if os.path.isfile(os.path.join(root, relative, "init.lua")):
            return True
    return False


def main(argv):
    if len(argv) != 2:
        print("usage: check_koreader_requires.py <koreader_root>", file=sys.stderr)
        return 2
    koreader_root = os.path.abspath(argv[1])
    if not os.path.isdir(os.path.join(koreader_root, "frontend")):
        print(
            "error: %s does not look like a KOReader checkout (no frontend/)"
            % koreader_root,
            file=sys.stderr,
        )
        return 2

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    checked = 0
    missing = []
    for path in lua_files(repo_root):
        with open(path, encoding="utf-8", errors="replace") as handle:
            source = handle.read()
        for match in REQUIRE_RE.finditer(source):
            module = match.group(1)
            if module.startswith(OWN_PREFIXES):
                continue
            checked += 1
            if not module_exists(koreader_root, module):
                line = source.count("\n", 0, match.start()) + 1
                missing.append(
                    (os.path.relpath(path, repo_root), line, module)
                )

    if missing:
        for path, line, module in missing:
            print(
                "error: %s:%d requires '%s', which is absent from KOReader"
                % (path, line, module),
                file=sys.stderr,
            )
        print(
            "%d require(s) checked, %d missing" % (checked, len(missing)),
            file=sys.stderr,
        )
        return 1

    print("%d KOReader require(s) resolved" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
