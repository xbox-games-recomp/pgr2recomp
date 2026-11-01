"""Re-locate functions from another XBE by their first bytes:
xmatch.py <other.xbe> <va>[=name] ... [--len N] [--xbe this.xbe]

For each VA, takes the first N bytes (default 24) of that function in <other.xbe>,
masks 4-byte absolute operands that point into the image (so globals and call
targets do not have to match), and searches this XBE's sections. Prints the
matches; shrinks the pattern to 16 then 12 bytes when nothing matches.
"""
import re
import struct
import sys

import capstone

from xdis import sections


def code_at(xbe, va, n):
    for _name, sva, _vs, raw, rsize in sections(xbe):
        if sva <= va < sva + rsize:
            return xbe[raw + va - sva: raw + va - sva + n]
    return b""


def pattern(code, va):
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    mask = [False] * len(code)
    for ins in md.disasm(code, va):
        off = ins.address - va
        b = ins.bytes
        # rel32 call/jmp: mask the displacement
        if b[0] in (0xE8, 0xE9) and len(b) == 5:
            for i in range(1, 5):
                mask[off + i] = True
        if b[0] == 0x0F and len(b) == 6 and 0x80 <= b[1] <= 0x8F:
            for i in range(2, 6):
                mask[off + i] = True
        # any 4-byte little-endian value inside the image window: mask it
        for i in range(len(b) - 3):
            v, = struct.unpack_from("<I", b, i)
            if 0x00010000 <= v < 0x00800000 and off + i + 4 <= len(code):
                for k in range(4):
                    mask[off + i + k] = True
    return re.compile(b"".join(b"." if m else re.escape(code[i:i + 1]) for i, m in enumerate(mask)), re.S)


def main():
    args = sys.argv[1:]
    n = 24
    this = "game_files/default.xbe"
    if "--len" in args:
        i = args.index("--len"); n = int(args[i + 1]); del args[i:i + 2]
    if "--xbe" in args:
        i = args.index("--xbe"); this = args[i + 1]; del args[i:i + 2]
    other = open(args[0], "rb").read()
    xbe = open(this, "rb").read()
    secs = sections(xbe)
    for spec in args[1:]:
        va_s, _, name = spec.partition("=")
        va = int(va_s, 16)
        hits = []
        for ln in (n, 16, 12):
            code = code_at(other, va, ln)
            if not code:
                break
            rx = pattern(code, va)
            hits = [(sva + m.start() - raw, sname) for sname, sva, _vs, raw, rsize in secs
                    for m in rx.finditer(xbe, raw, raw + rsize)]
            if hits:
                break
        desc = ", ".join(f"0x{h:08X} {s}" for h, s in hits[:6]) or "no match"
        more = f" (+{len(hits) - 6} more)" if len(hits) > 6 else ""
        print(f"0x{va:08X} {name:28s} [{ln}B] -> {desc}{more}")


if __name__ == "__main__":
    main()
