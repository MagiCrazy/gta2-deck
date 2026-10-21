#!/usr/bin/env python3
"""Extract the Disk1 InstallShield package embedded in GTA2INSTALLER.exe.

The freeware installer is an InstallShield 7 "Setup Launcher": a stub that
unpacks Disk1\\ (setup.exe, data1.hdr, data*.cab...) to %TEMP% and runs it.
Under recent Proton builds (11, Experimental) the stub randomly hangs before
unpacking anything, so we unpack Disk1 ourselves and run Disk1\\setup.exe.

Embedded files follow each other after the stub, each one preceded by a
header "<name>\\0<relative path>\\0<a.b.c.d version>\\0<decimal size>\\0".
Headers are chained (next header = end of header + size) so that look-alike
headers inside a file's data (setup.boot contains some) are never parsed.

Usage: unpack_installer.py GTA2INSTALLER.exe OUTPUT_DIR
"""

import os
import re
import sys

HEADER = re.compile(rb'([\x20-\x7e]{1,128})\0([\x20-\x7e]{1,260})\0(\d+\.\d+\.\d+\.\d+)\0(\d+)\0')
REQUIRED = ("setup.exe", "setup.inx", "data1.hdr", "data1.cab")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-1])
    source, output = sys.argv[1], sys.argv[2]
    data = open(source, "rb").read()

    first = next((m for m in HEADER.finditer(data) if m.group(2).startswith(b"Disk1\\")), None)
    if first is None:
        sys.exit("error: no embedded Disk1 package found in %s" % source)

    extracted = []
    match = first
    while match:
        relpath = match.group(2).decode("ascii")
        size = int(match.group(4))
        start = match.end()
        if start + size > len(data):
            sys.exit("error: truncated entry %s" % relpath)
        if relpath.startswith("Disk1\\"):
            name = relpath[len("Disk1\\"):].replace("\\", "/")
            if not name or name.startswith("/") or ".." in name.split("/"):
                sys.exit("error: unsafe path in installer: %s" % relpath)
            dest = os.path.join(output, name)
            os.makedirs(os.path.dirname(dest) or output, exist_ok=True)
            with open(dest, "wb") as fh:
                fh.write(data[start:start + size])
            extracted.append(name.lower())
        match = HEADER.match(data, start + size)

    missing = [f for f in REQUIRED if f not in extracted]
    if missing:
        sys.exit("error: incomplete package, missing %s" % ", ".join(missing))
    print("\n".join(sorted(extracted)))


if __name__ == "__main__":
    main()
