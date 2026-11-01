"""Find a byte pattern in default.xbe's sections: xfind.py <hex bytes, '??' = any> [xbe]

Prints the guest VA (and section) of every match. Used to re-locate MM3/RSC2
functions by their first bytes (bringup-playbook section 4).
"""
import re
import sys

from xdis import sections


def main():
    pat = sys.argv[1].replace(" ", "")
    path = sys.argv[2] if len(sys.argv) > 2 else "game_files/default.xbe"
    rx = re.compile(b"".join(b"." if pat[i:i + 2] == "??" else re.escape(bytes.fromhex(pat[i:i + 2]))
                             for i in range(0, len(pat), 2)), re.S)
    xbe = open(path, "rb").read()
    for name, va, _vsize, raw, rsize in sections(xbe):
        for m in rx.finditer(xbe, raw, raw + rsize):
            print(f"0x{va + m.start() - raw:08X}  {name}")


if __name__ == "__main__":
    main()
