#!/usr/bin/env python3
"""Steam helpers for gta2-deck: non-Steam shortcuts and compat tool mapping.

Standard library only (SteamOS ships python3 but no extra modules).
Steam must not be running while shortcuts.vdf or config.vdf are written:
it keeps both in memory and overwrites them on exit.
"""

import argparse
import os
import re
import shutil
import struct
import sys
import time
import zlib

# --- Steam locations ----------------------------------------------------------


def steam_root():
    for candidate in ("~/.local/share/Steam", "~/.steam/steam"):
        path = os.path.realpath(os.path.expanduser(candidate))
        if os.path.isdir(os.path.join(path, "steamapps")):
            return path
    sys.exit("error: Steam installation not found")


def library_paths(root):
    """Return every Steam library folder (internal storage, SD card...)."""
    paths = [root]
    vdf = os.path.join(root, "steamapps", "libraryfolders.vdf")
    if os.path.isfile(vdf):
        with open(vdf, encoding="utf-8", errors="replace") as fh:
            for path in re.findall(r'"path"\s+"([^"]+)"', fh.read()):
                path = path.replace("\\\\", "\\")
                if os.path.realpath(path) not in map(os.path.realpath, paths):
                    paths.append(path)
    return paths


def active_account_id(root):
    """Account ID (userdata folder name) of the most recently logged-in user."""
    auto_login = None
    registry = os.path.expanduser("~/.steam/registry.vdf")
    if os.path.isfile(registry):
        tree = parse_text_vdf(open(registry, encoding="utf-8", errors="replace").read())
        auto_login = get(tree, "Registry", "HKCU", "Software", "Valve", "Steam", "AutoLoginUser")
    vdf = os.path.join(root, "config", "loginusers.vdf")
    users = []
    if os.path.isfile(vdf):
        tree = parse_text_vdf(open(vdf, encoding="utf-8", errors="replace").read())
        for steamid, data in get(tree, "users", default=[]):
            if not isinstance(data, list):
                continue
            fields = dict((k.lower(), v) for k, v in data if isinstance(v, str))
            account_id = int(steamid) - 76561197960265728
            users.append((fields.get("accountname") == auto_login,
                          fields.get("mostrecent") == "1",
                          int(fields.get("timestamp", "0") or 0), account_id))
    users = [u for u in users if os.path.isdir(os.path.join(root, "userdata", str(u[-1])))]
    if not users:
        dirs = [d for d in os.listdir(os.path.join(root, "userdata")) if d.isdigit() and d != "0"]
        if len(dirs) == 1:
            return int(dirs[0])
        sys.exit("error: cannot determine the Steam user, pass --account-id")
    users.sort(reverse=True)
    return users[0][-1]


# --- text VDF (config.vdf, loginusers.vdf) ------------------------------------
# Trees are lists of (key, value) pairs; value is a str or a nested list.
# Lists keep key order and duplicate keys, so a rewrite only changes what we touch.

_TOKEN = re.compile(r'\s+|//[^\n]*|"((?:[^"\\]|\\.)*)"|([{}])|([^\s{}"]+)', re.S)


def _unescape(s):
    # Steam only escapes quotes and backslashes; newlines are stored raw.
    return re.sub(r'\\(["\\])', r"\1", s)


def _escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def parse_text_vdf(text):
    tokens = []
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError("invalid VDF near offset %d" % pos)
        pos = m.end()
        if m.group(1) is not None:
            tokens.append(("str", _unescape(m.group(1))))
        elif m.group(2):
            tokens.append((m.group(2), None))
        elif m.group(3):
            tokens.append(("str", m.group(3)))
    stack = [[]]
    key = None
    for kind, value in tokens:
        if kind == "str":
            if key is None:
                key = value
            else:
                stack[-1].append((key, value))
                key = None
        elif kind == "{":
            node = []
            stack[-1].append((key, node))
            stack.append(node)
            key = None
        elif kind == "}":
            stack.pop()
    return stack[0]


def dump_text_vdf(tree, depth=0):
    out = []
    pad = "\t" * depth
    for key, value in tree:
        if isinstance(value, list):
            out.append('%s"%s"\n%s{\n' % (pad, _escape(key), pad))
            out.append(dump_text_vdf(value, depth + 1))
            out.append("%s}\n" % pad)
        else:
            out.append('%s"%s"\t\t"%s"\n' % (pad, _escape(key), _escape(value)))
    return "".join(out)


def get(tree, *path, default=None):
    """Case-insensitive lookup of a nested key path."""
    node = tree
    for name in path:
        for key, value in node:
            if key.lower() == name.lower():
                node = value
                break
        else:
            return default
    return node


def ensure(tree, *path):
    """Return the nested list at path, creating missing levels."""
    node = tree
    for name in path:
        child = get(node, name)
        if not isinstance(child, list):
            child = []
            node.append((name, child))
        node = child
    return node


def remove_key(tree, name):
    tree[:] = [(k, v) for k, v in tree if k.lower() != name.lower()]


# --- binary VDF (shortcuts.vdf) -----------------------------------------------
# Same list-of-pairs model; values are str, int (0x02, uint32), bytes (other
# scalar types kept verbatim) or nested lists.


def parse_binary_vdf(data):
    pos = 0

    def cstring():
        nonlocal pos
        end = data.index(b"\0", pos)
        s = data[pos:end].decode("utf-8", "surrogateescape")
        pos = end + 1
        return s

    def node():
        nonlocal pos
        items = []
        while True:
            kind = data[pos]
            pos += 1
            if kind == 0x08:
                return items
            key = cstring()
            if kind == 0x00:
                items.append((key, node()))
            elif kind == 0x01:
                items.append((key, cstring()))
            elif kind == 0x02:
                items.append((key, struct.unpack_from("<I", data, pos)[0]))
                pos += 4
            elif kind in (0x03, 0x04, 0x06):
                items.append((key, (kind, data[pos:pos + 4])))
                pos += 4
            elif kind == 0x07:
                items.append((key, (kind, data[pos:pos + 8])))
                pos += 8
            else:
                raise ValueError("unsupported binary VDF type 0x%02x" % kind)

    tree = node() if data else []
    return tree


def dump_binary_vdf(tree):
    out = bytearray()

    def cstring(s):
        out.extend(s.encode("utf-8", "surrogateescape") + b"\0")

    def node(items):
        for key, value in items:
            if isinstance(value, list):
                out.append(0x00)
                cstring(key)
                node(value)
            elif isinstance(value, str):
                out.append(0x01)
                cstring(key)
                cstring(value)
            elif isinstance(value, int):
                out.append(0x02)
                cstring(key)
                out.extend(struct.pack("<I", value & 0xFFFFFFFF))
            else:
                kind, raw = value
                out.append(kind)
                cstring(key)
                out.extend(raw)
        out.append(0x08)

    node(tree)
    return bytes(out)


# --- file helpers --------------------------------------------------------------


BACKUPS_KEPT = 3


def backup(path):
    """Copy path to a timestamped .bak next to it, keeping the newest few."""
    if not os.path.isfile(path):
        return
    dest = "%s.gta2-deck-%s.bak" % (path, time.strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(path, dest)
    # Timestamps sort lexically; every run would otherwise add one more copy.
    prefix = os.path.basename(path) + ".gta2-deck-"
    folder = os.path.dirname(path)
    old = sorted(f for f in os.listdir(folder) if f.startswith(prefix) and f.endswith(".bak"))
    for name in old[:-BACKUPS_KEPT]:
        os.remove(os.path.join(folder, name))


def atomic_write(path, data):
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)


def shortcuts_path(root, account_id):
    return os.path.join(root, "userdata", str(account_id), "config", "shortcuts.vdf")


def load_shortcuts(path):
    tree = parse_binary_vdf(open(path, "rb").read()) if os.path.isfile(path) else []
    return tree, ensure(tree, "shortcuts")


def shortcut_appid(exe, name):
    # Same scheme as Steam ROM Manager; the value only has to be stable and unique.
    return (zlib.crc32((exe + name).encode("utf-8")) & 0xFFFFFFFF) | 0x80000000


def find_shortcut(entries, exe):
    for index, (_, entry) in enumerate(entries):
        if isinstance(entry, list) and get(entry, "Exe") == exe:
            return index
    return None


# --- commands ------------------------------------------------------------------


def cmd_info(args):
    root = steam_root()
    print("root=%s" % root)
    print("account_id=%s" % (args.account_id or active_account_id(root)))
    for lib in library_paths(root):
        print("library=%s" % lib)


def valve_tool_name(folder):
    """Internal compat tool name of an official Proton build, from its folder name.

    Steam names them proton_<major> since 7.0 ("Proton 10.0" -> proton_10,
    "Proton 9.0 (Beta)" -> proton_9), plus proton_experimental and proton_hotfix.
    """
    if folder == "Proton - Experimental":
        return "proton_experimental"
    if folder == "Proton Hotfix":
        return "proton_hotfix"
    m = re.match(r"Proton (\d+)\.\d+", folder)
    if m and int(m.group(1)) >= 7:
        return "proton_%s" % m.group(1)
    return None


def proton_tools(root):
    """Installed Proton-like tools as (internal_name, display_name, path)."""
    tools = []
    for lib in library_paths(root):
        common = os.path.join(lib, "steamapps", "common")
        for folder in sorted(os.listdir(common)) if os.path.isdir(common) else []:
            path = os.path.join(common, folder)
            name = valve_tool_name(folder)
            if name and os.path.isfile(os.path.join(path, "proton")):
                tools.append((name, folder, path))
    # Custom tools (GE-Proton, ...) declare their internal name themselves.
    for base in (os.path.join(root, "compatibilitytools.d"), "/usr/share/steam/compatibilitytools.d"):
        for folder in sorted(os.listdir(base)) if os.path.isdir(base) else []:
            path = os.path.join(base, folder)
            vdf = os.path.join(path, "compatibilitytool.vdf")
            if not os.path.isfile(vdf):
                continue
            tree = parse_text_vdf(open(vdf, encoding="utf-8", errors="replace").read())
            for name, data in get(tree, "compatibilitytools", "compat_tools", default=[]):
                if not isinstance(data, list):
                    continue
                install = os.path.normpath(os.path.join(path, get(data, "install_path", default=".")))
                if os.path.isfile(os.path.join(install, "proton")):
                    tools.append((name, get(data, "display_name", default=name), install))
    # The same tool can be installed in several libraries: keep the first one.
    seen = set()
    return [t for t in tools if not (t[0] in seen or seen.add(t[0]))]


def cmd_list_tools(args):
    for name, display, path in proton_tools(steam_root()):
        print("%s\t%s\t%s" % (name, display, path))


def cmd_find_tool(args):
    """Resolve a tool by internal name, display name or folder name."""
    wanted = args.name.lower()
    for name, display, path in proton_tools(steam_root()):
        if wanted in (name.lower(), display.lower(), os.path.basename(path).lower()):
            print("%s\t%s\t%s" % (name, display, path))
            return
    sys.exit(1)


def cmd_add_shortcut(args):
    root = steam_root()
    account_id = args.account_id or active_account_id(root)
    path = shortcuts_path(root, account_id)
    tree, entries = load_shortcuts(path)
    exe = '"%s"' % args.exe
    index = find_shortcut(entries, exe)
    if index is None:
        appid = shortcut_appid(exe, args.name)
        entry = []
        entries.append((str(len(entries)), entry))
    else:
        entry = entries[index][1]
        appid = get(entry, "appid") or shortcut_appid(exe, args.name)
    fields = [
        ("appid", appid),
        ("AppName", args.name),
        ("Exe", exe),
        ("StartDir", '"%s/"' % args.start_dir.rstrip("/")),
        ("icon", args.icon or ""),
        ("ShortcutPath", ""),
        ("LaunchOptions", args.launch_options or ""),
        ("IsHidden", 0),
        ("AllowDesktopConfig", 1),
        ("AllowOverlay", 1),
        ("OpenVR", 0),
        ("Devkit", 0),
        ("DevkitGameID", ""),
        ("DevkitOverrideAppID", 0),
        ("LastPlayTime", get(entry, "LastPlayTime") or 0),
        ("FlatpakAppID", ""),
        ("sortas", ""),
        ("tags", get(entry, "tags") or []),
    ]
    entry[:] = fields
    os.makedirs(os.path.dirname(path), exist_ok=True)
    backup(path)
    atomic_write(path, dump_binary_vdf(tree))
    print(appid)


def cmd_remove_shortcut(args):
    root = steam_root()
    path = shortcuts_path(root, args.account_id or active_account_id(root))
    if not os.path.isfile(path):
        return
    tree, entries = load_shortcuts(path)
    index = find_shortcut(entries, '"%s"' % args.exe)
    if index is None:
        return
    appid = get(entries[index][1], "appid")
    del entries[index]
    # Steam expects consecutive indices as keys.
    entries[:] = [(str(i), entry) for i, (_, entry) in enumerate(entries)]
    backup(path)
    atomic_write(path, dump_binary_vdf(tree))
    print(appid)


# Library artwork of a non-Steam shortcut lives in userdata/<id>/config/grid,
# named after the shortcut appid.
ARTWORK_SUFFIXES = {
    "portrait": "p",      # vertical capsule, 600x900
    "landscape": "",      # horizontal capsule, 920x430
    "hero": "_hero",      # library header background, 1920x620
    "logo": "_logo",      # logo drawn over the hero
}


def cmd_set_artwork(args):
    root = steam_root()
    grid = os.path.join(root, "userdata", str(args.account_id or active_account_id(root)), "config", "grid")
    os.makedirs(grid, exist_ok=True)
    for kind, suffix in ARTWORK_SUFFIXES.items():
        source = getattr(args, kind)
        if not source:
            continue
        ext = os.path.splitext(source)[1].lower()
        for old in (".png", ".jpg", ".jpeg", ".webp"):
            stale = os.path.join(grid, "%d%s%s" % (args.appid, suffix, old))
            if os.path.isfile(stale):
                os.remove(stale)
        shutil.copyfile(source, os.path.join(grid, "%d%s%s" % (args.appid, suffix, ext)))


def cmd_unset_artwork(args):
    root = steam_root()
    grid = os.path.join(root, "userdata", str(args.account_id or active_account_id(root)), "config", "grid")
    for suffix in ARTWORK_SUFFIXES.values():
        for ext in (".png", ".jpg", ".jpeg", ".webp"):
            path = os.path.join(grid, "%d%s%s" % (args.appid, suffix, ext))
            if os.path.isfile(path):
                os.remove(path)
    json_path = os.path.join(grid, "%d.json" % args.appid)
    if os.path.isfile(json_path):
        os.remove(json_path)


def config_vdf_path(root):
    return os.path.join(root, "config", "config.vdf")


def cmd_set_compat(args):
    path = config_vdf_path(steam_root())
    tree = parse_text_vdf(open(path, encoding="utf-8", errors="surrogateescape").read())
    mapping = ensure(tree, "InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping")
    remove_key(mapping, str(args.appid))
    mapping.append((str(args.appid), [("name", args.tool), ("config", ""), ("priority", "250")]))
    backup(path)
    atomic_write(path, dump_text_vdf(tree).encode("utf-8", "surrogateescape"))


def cmd_unset_compat(args):
    path = config_vdf_path(steam_root())
    if not os.path.isfile(path):
        return
    tree = parse_text_vdf(open(path, encoding="utf-8", errors="surrogateescape").read())
    mapping = get(tree, "InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping")
    if isinstance(mapping, list) and get(mapping, str(args.appid)) is not None:
        remove_key(mapping, str(args.appid))
        backup(path)
        atomic_write(path, dump_text_vdf(tree).encode("utf-8", "surrogateescape"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--account-id", type=int, help="Steam account ID (userdata folder)")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("info").set_defaults(func=cmd_info)

    sub.add_parser("list-tools").set_defaults(func=cmd_list_tools)

    p = sub.add_parser("find-tool")
    p.add_argument("name", help='internal, display or folder name, e.g. "Proton 10.0"')
    p.set_defaults(func=cmd_find_tool)

    p = sub.add_parser("add-shortcut")
    p.add_argument("--name", required=True)
    p.add_argument("--exe", required=True)
    p.add_argument("--start-dir", required=True)
    p.add_argument("--launch-options", default="")
    p.add_argument("--icon", default="")
    p.set_defaults(func=cmd_add_shortcut)

    p = sub.add_parser("remove-shortcut")
    p.add_argument("--exe", required=True)
    p.set_defaults(func=cmd_remove_shortcut)

    p = sub.add_parser("set-artwork")
    p.add_argument("--appid", type=int, required=True)
    for kind in ARTWORK_SUFFIXES:
        p.add_argument("--" + kind, default="")
    p.set_defaults(func=cmd_set_artwork)

    p = sub.add_parser("unset-artwork")
    p.add_argument("--appid", type=int, required=True)
    p.set_defaults(func=cmd_unset_artwork)

    p = sub.add_parser("set-compat")
    p.add_argument("--appid", type=int, required=True)
    p.add_argument("--tool", required=True, help="internal tool name, e.g. proton_10")
    p.set_defaults(func=cmd_set_compat)

    p = sub.add_parser("unset-compat")
    p.add_argument("--appid", type=int, required=True)
    p.set_defaults(func=cmd_unset_compat)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
