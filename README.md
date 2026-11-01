# Project Gotham Racing 2 — Static Recompilation

A native Windows (x64) port of the original-Xbox *Project Gotham Racing 2* (Bizarre Creations / Microsoft, 2003).
Every x86 function in the retail `default.xbe` is translated to C, compiled with MSVC and linked against a
replacement Xbox kernel, audio, input and GPU runtime; the NV2A command stream is rendered with Direct3D 11.
No emulator, interpreter or JIT.

Built on [xboxrecomp](https://github.com/sp00nznet/xboxrecomp) v0.15.0 (MIT, git submodule) plus
`patches/xboxrecomp.patch`, scaffolded from rsc2recomp and [mm3recomp](https://github.com/xbox-games-recomp/mm3recomp).

> **No game content is in this repository.** You need your own copy of the game. Everything derived from it
> (generated C, builds, dumps) is git-ignored.

**Status: bring-up.** Not playable yet; see `NOTES.md`.

## Game version

The overrides name guest addresses, so only this executable works:

| | |
|---|---|
| Title ID | `0x4D53004B` (XBE 2003-10-14, XDK 5659) |
| `default.xbe` SHA-1 | `702b79fd3bc844a413cbc26404718b1bf7e44e87` |

Extract the whole disc into `game_files\`, e.g. `python scripts\xiso_extract.py "Project Gotham Racing 2.iso" game_files`
(`extract-xiso -x` works too). The image is a plain XDVDFS partition.

## Building from source

Needs Windows 10/11, Visual Studio 2022 (C++ workload), CMake 3.20+, Python 3.10+ with `pip install capstone`,
and a Direct3D 11 GPU.

```powershell
& .\scripts\regen_once.ps1             # patch toolkit, lift x86 to C, build (15–20 min, prints BUILD_EXIT=0)
cmake --build build --config Release   # code-only rebuild (~1 min)
```

The output is `build\Release\pgr2_recomp.exe`; `pgr2_launcher.exe` is copied to the repository root.
The required environment variables are in `launcher.ini`.

## How it works

```
default.xbe ─► disasm ─► func_id ─► abi_analysis ─► recomp ─► patch_gen.py ─► MSVC ─► pgr2_recomp.exe
               (capstone + seeds in config/seed_functions.json)      (x86 → C)         + xboxrecomp runtime
```

- **xboxrecomp** supplies the Xbox kernel, an emulated MCPX APU (→ XAudio2), XInput and the NV2A pushbuffer
  executor.
- **`src/recomp_manual.c`** replaces guest functions that depend on hardware or the XDK.
- **`scripts/patch_gen.py`** applies anchored fixes to the generated C.
- **`src/d3d11_backend.c`** translates NV2A vertex programs to HLSL and runs the register combiners in one
  data-driven pixel shader.

`NOTES.md` is the engineering log.

## Legal

An independent, non-commercial preservation project, not affiliated with Microsoft, Xbox Game Studios or
Bizarre Creations. *Project Gotham Racing* is the property of its owners. Do not open issues or pull
requests containing game files or generated code. The toolkit in `xboxrecomp/` is MIT-licensed.
