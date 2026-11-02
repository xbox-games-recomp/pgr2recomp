# Project Gotham Racing 2 static recompilation -- engineering notes

Scaffolded 2026-10-31 from rsc2recomp (RalliSport Challenge 2), itself scaffolded from
[mm3recomp](https://github.com/xbox-games-recomp/mm3recomp). "MM3 #n" / "RSC2 #n" refer to those repos' NOTES.md.

Layout: toolkit = submodule `xboxrecomp\` pinned to v0.15.0 (6376eb8) with rsc2recomp's
`patches\xboxrecomp.patch` (game-agnostic fixes: D3D11 hooks, P8 palettes, zpass queries, fibers, ...) applied by
`scripts\apply_patches.ps1`. Launcher = submodule `launcher\` (xbox-recomp-launcher 6c9786e). Game files:
`D:\Documents\Xbox Recompilation\pgr2_files`, junctioned in as `game_files\` (ignored, never committed).

## 1. XBE fingerprint

| | |
|---|---|
| Title | Project Gotham Racing 2, retail, title ID `0x4D53004B` (Bizarre Creations) |
| Build | 2003-10-14 23:08:57 UTC (cert 2003-10-16), region NA/JP, DVD_X2, version 5 |
| XDK | **5659** for every library (MM3 5233, RSC2 5849: neither's byte patterns match 1:1) |
| Debug path | `c:\projects\Gotham2\2003.10.08.B\release2master\Gotham2.exe` |
| SHA-1 | `702b79fd3bc844a413cbc26404718b1bf7e44e87` (`default.xbe`, 2,707,456 bytes) |
| Base / size | `0x00010000` / `0x004A43A0` |
| Entry | `0x00192437` (set in `src/main.c`) |
| Kernel thunks | `0x00275600`, 158 imports |
| TLS | index at `0x004A2110`, 144 bytes zero fill, no data template |
| Libraries | XAPILIB, D3D8, D3DX8, XGRAPHC, DSOUND, XBOXKRNL, XMV, XONLINES, XVOICE, LIBCMT, LIBCPMT |

Sections (18):

| Section | VA | Size | Notes |
|---|---|---|---|
| .text | 0x00011000 | 0x1AE7FC | game + CRT (D3D8 is not LTCG here: it has its own section) |
| D3D | 0x001BF800 | 0x136DC | |
| D3DX | 0x001D2EE0 | 0xD4F8 | (absent in RSC2) |
| XGRPH | 0x001E03E0 | 0xB1A0 | full XGraphics lib (RSC2: 0x214). MM3 #28: shader assembler / swizzlers live here |
| DSOUND | 0x001EB580 | 0xC274 | |
| WMADEC | 0x001F7800 | 0x19274 | radio/music `.wma` |
| XMV | 0x00210A80 | 0x27DCC | XMV movie player (WMV) -- new compared with MM3/RSC2 (both Bink) |
| XONLINE / XNET | 0x00238860 / 0x0025A1A0 | 0x21924 / 0x125A0 | Xbox Live (PGR2 was a Live title) |
| XPP | 0x0026C740 | 0x8EA8 | USB/XAPI input -> override at API level |
| .rdata / .data | 0x00275600 / 0x002886C0 | 0x130A4 / 0x21EB9C | |
| DOLBY, XON_RD, .data1 | | | data |
| $$XTIMAGE, $$XSIMAGE, .XTLID | | | insertable (not loaded at boot) |

No XACTENG (sound banks are `.xwb` wave banks driven by the game's own code), no Bink.

## 2. `--extra-sections` (initial choice)

`D3D,D3DX,XGRPH,DSOUND,WMADEC,XMV,XONLINE,XNET,XPP` (in `scripts\regen.ps1`): every XDK library section.
Rationale: rule 1 of the skill (MM3 #19, #28; RSC2 #5 -- a half-lifted XNET spin lock hung RSC2's first boot).
RSC2 ended up sweeping all of its library sections too, and it built and ran fine.

## 3. Disc and data formats

- Plain XDVDFS at offset 0, 4.23 GB; extracted with `scripts\xiso_extract.py <iso> <outdir>` (10,685 files).
- Root: `default.xbe`, `dashupdate.xbe`, `update.xbe`, `downloader.xbe`, `XDemos\cdx.xbe` (demo disc launcher,
  `D:\xdemos\cdx.xbe`), `buffer0`/`buffer1` (2 x 100 MB, zero-filled? -- probably disc-layout padding).
- `Cache\` (211 MB: `Ambience`, `Cars`, `Objects`, `Resource`) is copied to the **Z: utility drive** at boot
  (`Z:\Cars.Ind`, `Z:\Frontend\Intro1.Xmv`, ...). Same pattern as RSC2's HDD cache: expect the Z: partition
  format/copy path to matter on the first boot.
- `Game\Areas\<City>.pak_common/_day/_night/_overcast/_stream` + `.pvs_<weather>` (visibility sets) per city;
  `<City> Frontend Maps.dat`. Cars: `.pak_cth/_hrd/_opn/_sft` (cloth/hard top/open/soft top variants).
- `Frontend\*.ini` (plain-text game config: Cars, Cities, Races, Rewards, per-language strings).
- `media\*.xpr` (XPR packed resources: fonts and UI per language), `Fonts.fpr`, `Sound.xsb`/`Wave.xwb`.
- `data\audio\`: 636 files, per-car engine banks (`<car>.xwb`, `_AI.xwb`, `_PCM.dat`), 8,490 `.wav` and 279
  `.wma` (radio stations, `D:\data\audio\Radio\`).
- `data\Movies\*.xmv` (19 class/level movies) and the intros `Intro1-3.Xmv` from the cache: **XMV**, not Bink.
  XMV decodes to YUY2 surfaces shown through the PVIDEO overlay (MM3 #29 overlay path is the likely route).
- No `.psh`/`.vsh` strings in the XBE: shaders are probably compiled into the code or the paks. XGRPH is still
  fully linked (swizzle/XPR helpers at least), and it is swept.

## 4. Overrides to re-locate

`src/recomp_manual.c` keeps RSC2's overrides (XDK 5849 addresses) and MM3's (5233) inside `#if 0` reference
blocks. Each needs its PGR2 (5659) address:

- [ ] D3D_BlockOnTime (GPU fence; check whether 5659 takes the fence in EAX like 5849 or on the stack like 5233)
      + device-pointer global
- [ ] D3D overlay stop (PVIDEO, needed for XMV)
- [ ] XAPI fibers (RSC2 #8: SwitchToFiber override), if PGR2 uses fibers
- [ ] XGetDevices / XGetDeviceChanges / XInputOpen / XInputClose / XInputGetState / XInputGetCapabilities /
      XInputSetState (+ XDEVICE_TYPE_GAMEPAD struct)
- [ ] XNet "no network" (PGR2 is a Live title: expect Live sign-in prompts / waits)

## 5. GPU fence wait (D3D_BlockOnTime) re-located before the first boot

MM3's fence-check bytes `8b4630 8b08 8b462c 8bd0 2bd1` occur once in PGR2, at `0x001C5E97` (D3D section):

- `sub_001C5E90` = BlockOnTime, **stdcall(fence, flags), ret 8** -- the 5233 (MM3) shape, not 5849's
  fence-in-EAX (RSC2 #6).
- Device pointer global `0x001D09D8`; the newest-fence kick is `sub_001C5DE0(0)` (ret 4), called from
  `0x001C5EBA` (return address `0x001C5EBF`).
- Override in `src/recomp_manual.c` = MM3's body with these addresses (honest wait with RECOMP_PB_EXEC,
  `RECOMP_D3D_FENCE_FAKE=1` reverts).

MM3's overlay-stop sequence (`[dev+0x4F8]` + `0x8700/0x8704` writes) does not occur in PGR2's code; no
`0x8700` immediates in any code section. XMV may not stop the overlay this way -- look again when movies play.

## 6. First regens, first boots, gamepad overrides

Regen 1 (all library sections swept, NOTES 2): 8,046 functions, **6 unresolved stubs**, builds (~10 min). Boot 1
ran 60 s without a crash: threads, D3D init, honest fence (NOTES 5), title/user data dirs, the Z: cache mount
attempt -- then a frame loop of black clears (~2,400 flips/s with vsync off). One ICALL failure: `0x0026C9C0`, an
XPP init routine reached only through a pointer table (it allocates with tag `MU__`) -> seeded
(`config/seed_functions.json`).

XAPI input answered at the API level as in MM3 #13/14 and RSC2 #12. `scripts/xmatch.py <other.xbe> <va>...`
takes each function's first bytes from another XBE (masking absolute operands and rel32 targets) and finds them
here; MM3's (5233) and RSC2's (5849) copies agree on every address:

| XAPI | PGR2 | game call sites |
|---|---|---|
| XGetDevices(type), ret 4 | `0026E033` | `001384FB..00138521` (gamepad, `0x26C778`, `0x26C950`, `0x26C95C`) |
| XGetDeviceChanges, ret 12 | `0026E055` | `001375FC..00137632`, polled every frame |
| XGetDeviceEnumerationStatus | `0026E3D2` | `00154B73` (spins while BUSY, then calls XOnline) |
| XInputOpen / Close / GetCapabilities / GetState / SetState | `0026D880` / `0026D8D6` / `0026D8E2` / `0026DABA` / `0026DB2D` | |
| XInitDevices wrapper | `0026E02E` (-> `0026D108`) | not overridden |
| XNet status / receive callback (MM3 pair) | `0025A6CD` / `002620C3` | not overridden yet: no network wait seen |

Gamepad device type `0x0026C7F8` (XInputOpen's argument). PGR2 links XGetDevices (RSC2 did not), so MM3's
override is back; it shares the "reported" flag with XGetDeviceChanges so the pad is inserted once.
Fibers: RSC2's SwitchToFiber/CreateFiber bytes do not occur -- PGR2 does not use XAPI fibers.

## 7. Z: utility drive: two toolkit fixes (black screen = the title's fatal-error path)

The black frames were the title's own error screen: `sub_0013DCE0` calls XMountUtilityDrive (`sub_00190BE0`)
and on failure `sub_001388F0("InitialiseFileCache - !XMountUtilityDrive")` (77 callers: the generic fatal-error
routine; `sub_00138780(n)` draws message n from data at `0x28F9C8`). Found from the watchdog's guest stack.
`RECOMP_KERNEL_LOG_BUDGET=100000` logs every kernel call -- that is what showed the steps below.

1. **Cluster size.** After formatting Partition5, XAPI 5659's mount (`sub_00193128`) opens
   `\Device\Harddisk0\Partition5\` and asks NtQueryVolumeInformationFile(FileFsSizeInformation); it requires
   SectorsPerAllocationUnit x BytesPerSector == the utility-drive cluster size from the XBE InitFlags
   (`[0x10124] >> 30`: 16/32/64/128 KB; PGR2's flags `0x80000004` = **64 KB**), else
   STATUS_UNRECOGNIZED_VOLUME. The toolkit always said 16 KB. RSC2 has the same flags, but 5849's XAPI does not
   check. Fix: a cache partition opened as a directory now lands in `<save_dir>\Cache` (kernel_file.c; it was the
   save dir itself), and the bridge answers FileFsSizeInformation on Partition3..5 / `\Cache` with the requested
   cluster size (`bridge_is_cache_partition`, kernel_bridge.c). `RECOMP_VOLINFO_LOG=1` logs every volume query.
2. **Symbolic link target.** On a fresh drive (`Z:\Version.12` absent) the title calls XFormatUtilityDrive
   (`sub_00190CE5`, error string "InitialiseFileCache - !XFormatUtilityDrive"): NtOpenSymbolicLinkObject("\??\Z:"),
   NtQuerySymbolicLinkObject, then format the device it names. The toolkit ignored the name and always answered
   `\Device\CdRom0` -> it "formatted" the DVD (zeroed geometry) and failed. Fix: the open looks the name up in the
   IoCreateSymbolicLink table (xbox_LookupSymbolicLink) and the query returns that target; unknown links keep the
   CdRom0 answer.

With both, the title formats Z:, copies `D:\Cache\` (Ambient, Cars, Frontend, Textures, Resource, `.Ind` index
files, intro `.xmv`s) onto it on a third thread (`0x0013D900`) and writes `Z:\Version.12` last.

## 8. XMV movies need vblank interrupts (`RECOMP_VBLANK=paced`)

Next stop: main thread in `sub_0013C810` (play movie, `Z:\Frontend\Intro1.xmv`) looping on XMV's GetNextFrame
(`sub_002113E8`, status 0 = no frame -> Sleep(0) and retry; 1 new frame, 2 end, 3 fail). Found with cdb host stacks
(`cdb -pv -p <pid> -y build\Release -c ".reload /f pgr2_recomp.exe; ~*k 14; q"`). XMV times frames by
D3D's display-field count (`sub_001C4350` = GetDisplayFieldStatus, `[dev + 0x1DD8]`), which only D3D's vblank ISR
(vector 3, `0x001CA410`) advances. The toolkit delivers vblanks only with `RECOMP_VBLANK` set; MM3 and RSC2 never
needed it (Bink paces itself). `RECOMP_VBLANK=paced` (60 Hz schedule) is now in `launcher.ini` and the dev scripts.

## 9. Milestone: title screen (2026-10-31)

`frames\gpu6_sheet.png` (vsync on, dumps every 5 s), verified in frame dumps: Bizarre Creations intro movie, warning
text, Microsoft Game Studios / Bizarre logos, the Enzo intro with the city names, **"PRESS START" title screen with
correct colours**; XMV video arrives as 480x320 format-24 textures re-decoded per frame (no PVIDEO overlay, so
MM3's overlay-stop override is not needed). Pad polled every frame (XGetDeviceChanges + XInputGetState). No crash
in 120 s. Not checked: audio, input past the title screen, anything in game.

Open from this run: NtQueryVolumeInformationFile class 1 (FileFsVolumeInformation) on `UDATA\4d53004b\` returns
STATUS_NOT_IMPLEMENTED (save-game code; watch for save problems).

## 10. Stuck at car selection: functions reached only through immediates (seeds)

Symptom (user's `run.log`): after picking an event, car selection kept rendering but A did nothing. The log had a
single `[ICALL] Failed to resolve VA 0x00052F70`. `sub_000AA000` / `sub_000AA230` map the game mode (13 cases) to
a callback with `mov eax, imm32; ret 4`, and the caller stores it in `[0x34E938]`; mode 5's callback `0x00052F70`
was never found by the disassembler (no direct call, no data pointer), so the call returned 0 and the mode never
started. Seeded (`config\seed_functions.json`).

Same class, found by scanning every `.text` instruction operand and every aligned `.data`/`.rdata` dword for
values that land on a plausible, unknown function start: `0x0005A9C0`, `0x0009C040`, `0x001774D0` (pushed or
stored as callbacks) and two atexit thunks. **Only seed addresses that follow int3 padding** (or are observed):
`0x001510F0` follows a `ret` but is a block of `sub_00150A00` that the title only *compares* against; seeding it
split that function, its jump table landed in the new piece (`[ICALL] 0x00151CA2`) and the game ran into null
pointers within seconds. `0x00081B40` / `0x0008F350` were dropped for the same reason.

The race needs more of the same in the CRT's x87 maths (`exp`/`sinh`/`cosh`/`tanh`, pow-style helpers): the CRT
dispatches through byte-packed tables (name, flags, four handler addresses -- **unaligned**, at `0x002966FA..`)
and an aligned table at `0x00296130`, and the handlers tail-jump into each other. Seeded every missing table
entry (`0x001B5BC8 .. 0x001B9EB5`, `0x001B5BD0`, `0x001B5C72`) and the stub target `0x001B5C74`. Symptoms before:
`[ICALL] Failed 0x001B9E14` every frame once an attract-mode car's audio set loaded, `0x001B5BD0` in the race.
Stubs after the final regen: see 12.

## 11. Streamer deadlock: file I/O completions must be deferred (`RECOMP_DEFER_IO_APC`)

Symptom: pressing Start in the attract demo (or any front end <-> game switch) froze the picture; no more flips.
cdb host stacks: main thread in `sub_00100AC0` -> WaitForSingleObject(streamer thread, INFINITE); the streamer
thread (`sub_001009E0`) had seen its quit event and sat in `sub_00136070`, an alertable WaitAll loop that runs
while the pending-read mask `[esi+0x5C]` is non-zero. `sub_00136360` issues `ReadFileEx(..., 0x001362F0)` and
**then** ORs the request's bit into the mask; the completion routine clears it. The toolkit ran file APCs inline
inside NtReadFile, so the completion ran before the bit was set and the bit never cleared (the toolkit comment cites
Fallout: BoS doing the same). The toolkit already has hardware-style deferral (APC queued per thread, run at the
next alertable user-mode wait): `src\main.c` now calls `xbox_SetDeferredIoApc(1)`. `RECOMP_DEFER_IO_APC=0`
reverts. With it, attract -> title -> front end -> race all switch cleanly; A/B with `=0` (run `ab0`): Start in
the attract demo freezes again (flips stop).

## 12. Milestone: front end and a race (2026-11-01)

`scripts\dev\to_carselect.ps1 <tag> [-race]` (fresh profile in `saveroot\UDATA`, Z: cache kept): Start at the
title before the attract demo starts (A at the title starts the attract demo), plate / plate text / helmet,
Single Player -> Kudos World Series -> Compact Sports Series -> Street Race (Florence) -> **car selection ->
transmission -> difficulty -> pre-race -> race**. Verified in frame dumps (`frames\race1`, `frames\race2`): every
menu, the Florence street race with HUD, AI cars, and scripted throttle (`rt:6000` in the live pad file) driving
the car to 40-50 mph in 2nd. The attract demo renders Hong Kong / other cities with cars driving. No XOnline wait
anywhere ("Not signed in to Xbox Live" on the scoreboard).

Open: the player's car (dark green MINI) renders almost black in the race (not checked against xemu); audio not
checked; driving feel / window needs the user. One of four scripted runs (`race2`) crashed during the race load in
DirectSound on the APU interrupt path (`[CRASH]` AV in `sub_001F25D7`, `edi=0xFFFFFFB4`); `race1`/`race3`/`r5`
on the same seeds minus three CRT entries / the same build did not. Intermittent, not investigated (MM3 #11/#31
are the DSOUND precedents).
Stubs after the final regen: 6 (`0x00128B89`, `0x00177C76/7E`, `0x001D78E7/EB`, `0x00275626`), none hit in race3.

## 13. Races ran at double speed: flip pacing (`RECOMP_FLIP_PACING=1`)

Symptom (user, driving): everything in the race moved twice as fast. Measured from frame dumps: the in-game lap
clock advanced exactly flips/30 (266 flips -> 8.85 s, 228 -> 7.6 s, whatever the wall time), so PGR2 steps a fixed
1/30 s per frame and relies on its swaps' presentation interval 2 to hold it at 30 fps. The toolkit completed every
FLIP_STALL at once, so the race flipped at the host's 60 Hz (or faster with vsync off). The toolkit's flip hold
(`nv2a_flip_hold.h`: holds the GPU after a FLIP_STALL until the guest vblank count reaches last flip + the
interval from D3D's swap NOP) is opt-in; `RECOMP_FLIP_PACING=1` is now in `launcher.ini` and `scripts\dev\live.ps1`.
Run `pace1` (vsync off, so nothing else caps the rate): the race at exactly 30 flips/s (600 in 20 s) and the lap
clock 15.000 s over 15 s of wall time; menus and movies keep 60 (they ask for interval 1). Unset or `=0` reverts.
It needs `RECOMP_VBLANK` (the guest vblank clock). A machine that cannot hold 30 fps still runs slow (headless
runs without it reached ~23 fps in races).

Probes added to `src\d3d11_backend.c` while looking at the user's alpha-masked buildings: the batch log
(`RECOMP_D3D11_LOGFRAME` / `_LOGFILE`) prints `aref` (alpha reference), and `RECOMP_D3D11_NOATEST=1` ignores the
alpha test. On the Florence grid the alpha-tested draws are the overhead cables (refs 0/1/45/128) and work; the
far bank of the river (user's screenshot at ~38 s into lap 1: flat water to the horizon, bare poles) is not
reproduced yet.

## 14. Streets of buildings that vanish: the lifter's 8-bit `imul` (fixed in the toolkit)

User recording `flicker61101_123328`, frames 119-232: the start straight of Florence shows no buildings on
either side (sky and a flat "river" to the horizon) until frame 232, when the whole street appears from one frame
to the next at the same position. The "river" of the earlier screenshot is this, and the alpha-masked buildings
of 13 too.

**Cause.** `sub_001194E0` (track load) gives every draw item of a city chunk its sort key:
`mov bl, 5; imul bl; add al, [esi+5]; mov [edx+2], al` at 0x0011956A (key = class * 5 + the material's byte 5).
The lifter emitted every one-operand `imul`/`mul`/`div`/`idiv` as the dword form (EDX:EAX), so `imul bl` zeroed
EDX, the item pointer, and the key went to guest address 2. Every item kept its file's placeholder key 6. The
draws of visible chunks go through a counting sort on that key (`sub_0011B1B0` add, `sub_0011B210` sort,
`sub_0011B410` draws keys <= 79, then the rest after restoring depth writes and the z bias). With one key, the
list stays in chunk order. Its multiply decals (material type 16) and alpha overlays (type 18), which set
DEPTH_MASK = 0 and a z bias through the game's own state cache (`0x486149`, `sub_00118D90`), land in the middle
of it. Every opaque item after the first decal is then drawn without depth writes, and the sky dome (`46B9DE93`,
LEQUAL, drawn last) paints over it. Whether a decal chunk comes early depends on where the camera is: hence
streets that vanish at one spot and come back at another.

Fix: `tools/recomp/lifter.py` `_narrow_muldiv` lifts the 8-bit forms on AX (AL * r/m8 into AX; AX / r/m8 into
AL, AH) and the 16-bit forms on DX:AX, leaving the rest of EAX/EDX alone (toolkit patch). Game-agnostic: every
`mul`/`imul`/`div`/`idiv r/m8|r/m16` in any port was wrong before.

How it was found (the method generalises to "wrong draw state"): two F12 captures from the user (street missing
at f1208 / present at f1268, both with the batch log). The same draws were in both frames, but in the bad one a
decal ran at b753 and the next ~470 buildings had `dw0`. A temporary probe recorded the guest stack at every
DEPTH_MASK write in the game's one-method helper `sub_001C0E00`, keyed by pushbuffer address. The executor
carried the address into each batch, so the log showed the call chain behind each `dw` switch. A dump of the
sorted list then showed all keys = 6 and the decal in mid-list.

Kept from the investigation (harmless, correct):
- `depth_scale()` normalised depth by each draw's clip maximum. xemu (master, `pgraph/glsl/psh.c` + `common.c`)
  stores w (w-buffer) or screen z at the depth buffer's full scale (16777215 / 65535) and uses the clip range only
  to discard/clamp. Changed to that (`Nv2aRenderState.zeta_format`, new; toolkit patch);
  `RECOMP_D3D11_ZSCALE_CLIP=1` reverts.
- `RECOMP_ZPASS_FORCE=<pixels>` (toolkit probe) answers every visibility test with that count; forcing them all
  visible floods the screen with sun glare (the game tests the sun).
- F12 also logs every batch of the next flip to stderr (`[D3D11] F12: logging flip N`, then `f<N> b...`).

## 15. Shadows that build up on sunlit road (NOT fixed); the car shadow map was never cleared (fixed)

User recording `flicker\20261101_170538` (from #217): hard-edged shadow darkens more and more on the road as the
car drives on, only where the sun falls. **Still there after the fix below (user, same evening).** Looked at
closer (crops of #214-230, plaza ~29 s into lap 2): large straight-edged dark polygons over the cobbles that
layer (a medium band, darker where two overlap) and move with the view -- not the car shadow map, whose casters
and receivers are both car draws (`5952997B` / `420C5AC3`). Ruled out: stencil (no draw in a race enables it;
the batch log now prints `stencil ...` when one does), draw counts (`stats.txt` shows no shader's batches
growing from #217). The road's baked shadows are the world shader's second stage (`27E59953`, lightmap); the
multiply decals `217F6A8C` (b1407-1413 of a race flip) are textured dirt/skid marks. Open candidates: overlapping
multiply shadow decals that the original keeps to one layer (depth writes / z bias), or stale streamed lightmap
texels (the texture cache hashes only mip level 0, `get_texture`). Needs an F12 capture at the spot with its
batch log (it is in `run.log`, which every launch overwrites; the user's first one was lost that way).

**Second capture** (`flicker\20261101_195639`, #182-219, batch logs of flips 1242/1280 kept as
`run_user_195639.log`): Florence Duomo 1 (One on One), ~3 s after the start line -- reachable by script
(`one_on_one.ps1` in the session scratchpad: `to_carselect` without `-race`, then B, Up, A x5; `rt:5200`
from the grid). Stepping the frame (`RECOMP_D3D11_LOGFILE` with `"<a>-<b>/<stride>"`, new: a stride) shows
the dark, sharp-edged area appear with the `1E311CB8` road pieces (b1436-1610); the road drawn with
`27E59953` stays bright. Not time-dependent: with the car parked the picture does not change (25 frames),
so "builds up" is which road pieces are in view.
- `27E59953` (far/other road): `out = fog.a * 1.5*T0*v3 + (1-fog.a)*fog` (rc0 v3*f0 0.5, rc1 T0*R0+T0*v3).
- `1E311CB8` (near road): `out = fog.a*(T0*v3*c147) + (1-fog.a)*fog + fog.a*(T3*T0.a*spec.a)`, c147 = 1,
  v3 = 0.2-0.49 on the dark pieces. T3 = `807D8000` (256x256, read as linear Y8) at a screen-space
  projection of the view position (`c167..170`: s/q = 181*x/z + 128, t/q = -241*y/z + 128).
- `807D8000` is rebuilt every frame: b612 fills it through fog (linear 0..75, distance 1/rhw = 1 -> fog
  factor 0.987, colour (0.85,0.90,1.0)), i.e. 3/255; b613/b614 add 2x a soft round glow (`8082FB80`,
  128x128 Y8) on a quad at x -187..102, y -37..398 (identical bytes in the user's run and ours: static).
  Result mean 3-8/255: so the near road gets almost no T3 term and is ~1.5x darker than the far road.
  Checked and right as far as the hardware formulas go: the VS (`oPos = v0*c0 + c1`, c0 = 1, c1 = 0.53),
  fog (same formula as xemu), the projective divide, linear-texture scaling, combiner mapping 6.
  `RECOMP_D3D11_CPUWRITES=0` (the game rewrites `807D8000`'s guest memory every ~11 flips, all zeros when
  dumped) did not change it. What the original shows here is unknown: a reference (xemu or console) of
  this spot decides whether the T3 mask should be brighter (then the fill quad or its fog input is wrong).
- The batch log now also prints `fog en/mode/param/colour` per draw.
- **xemu reference** (user's screenshot, same spot): the near road is evenly sunlit and the car casts a
  car-shaped shadow. So the sun mask must be bright (sun) everywhere except the car's shadow, and our
  near-black mask is the bug. `RECOMP_D3D11_SKIPPROG=1E311CB8` leaves a hole: those pieces are the only road
  there, so their light has to come from T3.
- **Experiment** `RECOMP_D3D11_FOGW=<vsh hash>` (backend, diagnostic): that programme's fog distance from
  |oPos.w| instead of oFog. With `=C8AF571F` the fill quad fogs to the fog colour, the mask turns bright and
  the near road is sunlit like xemu -- except a dark rectangle where b613/b614 (the glow quads, fog off,
  `fog.a*2*V0*T0 + (1-fog.a)`) overwrite the mask with the glow over black. For xemu's picture the glow quads
  must not darken either. Not the fix: oFog is what the hardware (and xemu) uses for vertex programs, and the
  fill's oFog = 1/rhw = 1 really gives fog factor 0.987.
- xemu's own state for these draws (its shader cache, `%APPDATA%\xemu\xemu\shaders`, parsed with the layouts
  of `pgraph/glsl/vsh.h` + `psh.h` at xemu master; program tokens at byte 255 of an entry, `fog_enable` at
  57, `fog_mode` at 59): fill quad fog on (mode LINEAR or EXP in different entries), glow quads fog off,
  road `1E311CB8` stage 3 `rect_tex` with no compare/shadow/snorm flags, same combiner words as ours. So the
  difference is in per-draw values (vertex data, constants, fog params), not in state.
- Immediate-mode check (`RECOMP_PB_ATTRDUMP=<vsh hash>`, new: each attribute's format and the first vertex's
  raw dwords): the fill is a SET_VERTEX* immediate quad, diffuse really 0; unhandled immediate methods in
  0x1500-0x17FF are now logged once each (`[GPU] unhandled vertex method`): only 0x16BC, 0x17BC, 0x17C4.
  The glow quads move between runs (x 43..., -187...), so they are computed per frame (probably the car's
  shadow/light footprint in screen space).
- More facts: `807D8000` is a **B8** colour surface (format `0x119`). All `C8AF571F` draws have fog gen
  PLANAR (2); HUD/minimap draws with it are fogged too (EXP). xemu master renders B8 as GL_R8 (keeps red,
  "FIXME: Map channel color"), colour mask straight from CONTROL_0, B8 surfaces always take the slow
  download/upload path to become textures -- so by its formulas xemu's mask would be as dark as ours.
  Experiment `RECOMP_D3D11_FOGSPEC=<vsh hash>` (fog factor = specular alpha, 0 in all three quads) makes
  the whole road sunlit with no dark rectangle, but also turns the minimap white and shows no car shadow:
  not a rule either. The user's xemu screenshot is Duomo 2 at 0:23 (4 cars), not the Duomo 1 spot used
  here, so an xemu capture of the same spot is the next thing to compare against.
- Next: find what makes the mask white on hardware. Leads: the glow quads' role (light pools vs shadow:
  the car shadow in xemu suggests the mask = white minus car footprint, i.e. these quads should darken or
  be inverted -- check their colour mask 0x00010101 against a B8/Y8 surface: which channel the NV2A stores
  for an 8-bit colour surface, and what the combiner's alpha/blue carries), the 807D8000 surface format, and
  the CPU writes to it every ~11 flips.
- **Same-spot xemu captures** (Duomo 1, 0:03.4 and 0:06.8; the user's images): near road evenly sunlit with a
  whitish sheen (strongest on the left, where our glow quad sits), a soft car-shaped shadow to the right of the
  car, and a *darker* band further out. Ours is the reverse: the near road dark, the far band bright.
- Glow quad position (CPU, `sub_00041DC0`): the sun vector at `0x49EE8C` (= -0.573, -0.414, -0.707 in our run,
  written once by `0x1808C0`) is projected onto the plane of the normal at `obj+0xBEF4`, scaled by
  `obj+0x18 - [0x275B98]` (plane -10000 by default, from `0x1848D0`), subtracted from `obj+0xE0` and projected with
  `sub_00015D70` (camera block `[0x3CD804]`). Radius = viewport width x `[cam+0x130]` x 0.4. So the glow is the
  sun's direction on screen; at this spot it lands at mask x -75 (left edge), which fits xemu's left-side sheen.
- Road VS `1E311CB8`: spec = `c150` (1,1,1), spec.a = `c97.x - |(v0 - c161).c162| * c97.y` with c162 = (0,1,0),
  so a height falloff above the car (c161), about constant on the road; T3 coordinates = `R10 . c167..170`.
- xemu `vsh.c` (master) fog read again: `oFog = vshCarryFog` before the program, fog disabled -> `oFog = 1`,
  LINEAR `p0 + d*p1 - 1`, `fogDistance = oFog.x` for programs. Same as ours, so by xemu's own formulas the fill
  is 0.987 fog = 3/255 too. The road being lit in xemu therefore comes from something these formulas don't show.
- More experiments, all diagnostic only, none a rule:
  - `RECOMP_D3D11_SKIPMASKFILL=1`: drop the fill quad (C8AF571F into a 1-byte RT, front-face cull). Near road
    lit, because the mask then keeps old contents. Not a rule: the fill is CW on screen, so cull FRONT with
    front = CCW does not cull it (`RECOMP_D3D11_CULLFLIP=1` turns the whole world inside out, so our
    winding convention is right).
  - `RECOMP_D3D11_FOGSPEC=C8AF571F` again at the same spot: the 1E311CB8 band further out turns whitish and the
    near road stays dark. That is the opposite of xemu, so "mask white everywhere" is not the answer either.
  - `RECOMP_D3D11_Y8INV=1` (invert Y8 texture samples, in case the glow blob is meant to be a shadow): knob
    exists, result not written down. Re-check it before ruling it out.
- Also fixed on the way: `rt_take_cpu_writes` hashed the whole mip chain of a 1-byte RT, so it saw "CPU writes"
  that were not there and overwrote `807D8000` with guest memory. It now hashes level 0 only
  (`RT.guest_sig_bytes`, re-baselined when the footprint changes).
- **The mask is a road reflection.** During `sub_00041DC0` the camera block is mode 3 (reflection camera):
  viewport 256, near 0.1, far 75 (= the fog end), position y -0.38 (mirrored below the road), plane normal
  (0,1,0). So the fill is the reflected sky and the glow is the sun at the horizon (P = E - 74 * sun
  projected onto the plane). The road reads it with clamp-to-edge (`addr 3/3`; the stage line now prints
  `addr` and `border`), so the near road reflects the edge row (sky) and the far road the horizon rows.
  With that reading, xemu's look (near road sky-bright, far band dark, soft extra brightness on the left where
  the glow sits) needs a sky-coloured fill, i.e. a fill fully fogged. `RECOMP_D3D11_FOGW=C8AF571F` gives that
  (fill fog distance = oPos.w = 559250, because `c0.w` = 559250 is the w-buffer scale; oFog = 1/rhw = 1).
  But it still differs from xemu: the glow quads overwrite their rectangle (x -220..70) with the glow over black,
  which leaves a hard-edged dark block on the left where xemu is brighter, and our far band stays bright
  where xemu's is dark. Both point at the glow quads' composite (xemu acts as if they add, e.g. the
  screen blend `ONE_MINUS_DST_COLOR, ONE` that is set but disabled) and at something dark along the horizon
  rows in xemu. Not settled.
- **Experiment `RECOMP_D3D11_FOGW=C8AF571F` + `RECOMP_D3D11_MASKBLEND=1`** (new knob: turn on the screen blend
  the glow quads set but leave disabled). The mask after the three draws is the sky colour everywhere
  (dumped with the `"a-b"` trigger: 216,229,255). The road reads that render target (new log line
  `stage3 reads RT 256x256`). At 0:05.1 the frame looks like the xemu shots at 0:06.8/0:07.4: sky sheen on
  the near road, darker band further out. At 0:08.2 (reversing) a darker wedge left of a diagonal seam is
  still there, and the far band is bright where xemu's is dark. The wedge can't be the glow quads (the
  blend can only brighten), so it is road pieces or their per-vertex data. Why the hardware fogs the fill
  (oFog = 1/rhw = 1, while xemu's code uses oFog too) and whether the glow blend is really on is still
  unexplained, so neither knob is on by default. An earlier frame with a hard dark block on the left was the
  bumper camera (the script's key timing), not this effect.
- Open: in the xemu shots the near pieces are the bright ones. Either xemu picks different pieces for
  `1E311CB8` and `27E59953` (a CPU choice) or the T3 mask is flipped vertically relative to ours. Next: log
  which programme draws each near piece in xemu (its shader cache only stores state, not draw order), or get
  a console capture of the same spot.
- **The sun term is switched per road piece by the track data** (runs w2-w5, 2026-11-02). Decoded again from the
  combiners: `1E311CB8` is `out = fog.a*(T0*v0 + spec.a*T3*T0.a*spec.b) + (1-fog.a)*fog` (rc0 writes
  `spec.a*T3 + (1-spec.a)*c0` back into T3 with c0 = 0, and `T0.a*spec.b` into T0.a). The VS sets
  `oD1.rgb = c150` and `oD1.a = c97.x - c97.y*|y - c161.y|` (c97 = 1, 0.5; c161 = the car position, y 1.59 at the
  grid, -10000 when there is no reflection plane), so spec.a is ~1 on flat road near the car and the term is gated
  by `c150`. `RECOMP_D3D11_LOGCONST=<a>-<b>` now prints constants for held geometry too (it used to skip every
  cached road piece). In one flip at the Duomo 1 grid `c150` is (1,1,1,0) for some `1E311CB8` draws and 0 for
  the rest. Stepping the flip: b1413 (c150 = 0, 518k pixels, mean 33) is the whole near road, b1412 (c150 = 1)
  the bright far band. Where `c150` comes from: `sub_00118B90` (material command interpreter) loads
  `c150 = palette[idx]` (`0x3FE8C0 + 16*idx`, cached in `[0x28F6E1]`), and `sub_001186C0` recomputes the palette
  each frame by entry type (bytes at `0x3FE8C0+0x8E30`, 40 entries, count at `+0xC196`) from a source colour per
  entry (`0x3FEF00 + 4*idx`). Types and sources are read from the track file (`sub_0016C4..`, stream reads into
  both arrays). Tagging the sources in the live process (cdb `ed`) showed the near piece uses entry 6 (type 8,
  source 0x00000000) and the far band entry 9 (type 8, source 0x00FFFFFF). So the near road at the grid has no
  sun/sky term by data, in xemu as here; its look is just `T0*v0`, and hard-edged dark areas next to bright ones
  are material boundaries (entry 6 vs 9), not a rendering fault. That is the likely "wedge" too (not reproduced
  in run w1, where the car pins itself on the barrier). The large curved dark area in the user's xemu shot at
  0:17 fits the same thing (the Piazza's paving) better than a car shadow.
- With `FOGW=C8AF571F` + `MASKBLEND=1`, run w1 at 0:03.8 next to the user's xemu shot at 0:03.4 (same lap, same
  view): near road with the sky sheen, darker band further out, close to identical. Without the knobs that
  sheen is missing, because the c150 = 1 pieces read a near-black mask. So the knobs are the right direction.
  What is still missing is the hardware reason for a fully fogged fill (oFog = 1/rhw = 1 by the passthrough
  programme, `o5 = rcp(v0.w)`) and for the glow quads' blend. Next: the user's RenderDoc capture of xemu at the
  plaza, to see xemu's `807D8000` after b612-b614 and what a near-road pixel samples from it.
- Hangs seen while doing this (runs sh3, sh5, earlier ir1): the DISPATCH gate holder in a guest loop with
  no kernel calls, twice right at the grid; one with "383 refused" (holder inside an ISR). The IRQL/TIB
  probe added in 17 was in all three builds and is removed again (it never fired; ruling out a timing
  effect).

What was fixed on the way, a real bug but not this symptom: the batch log of the flip after the user's
recording (flip 4437): the
scene draws its sun shadow map at b894-934, depth only, into a 1024x1024 zeta `80A11000` with colour offset 0
(`rt 80000000`, colour writes off), then samples it in the lit pass (b935-970, `vsh 420C5AC3`). Every other
target got a `CLEAR` that flip; the shadow map did not. The executor's `clear_surface` returned early whenever
the colour offset was 0, so the game's depth clear of a depth-only surface was dropped and each frame's casters
were depth-tested against all earlier frames'.

Fix (`nv2a_pb_exec.c` `clear_surface`, toolkit patch): with colour offset 0, a clear that asks for Z/stencil on
a set zeta still goes to the back end. Verified in run `fz4`'s batch log (`RECOMP_D3D11_LOGFILE`):
`CLEAR after b1406 rt 80000000 1024x1024 flags 3 zst 0000FFFF zeta 80A11000` before the first caster, every
flip. `RECOMP_ZONLY_CLEAR=0` drops such clears again. (A first version that also let through clears with a
colour offset but no pitch/format cleared the whole 1280x480 depth buffer from a 500x200 car-select pass; the
fix is limited to colour offset 0.)

## 16. Race audio: effect sends were mixed into the left channel (fixed in the toolkit)

Evidence (`RECOMP_AUDIO_WAV`, `RECOMP_APU_VOICES=1`, run `fz3`): the output was there and continuous, but the
front end was 13 dB quieter on the right (R = 0.22 x L, correlation 0.98) and a race almost entirely on the
left (R/L 0.04-0.06, uncorrelated). Per-voice volumes were balanced. `RECOMP_APU_VOICES=2` (new: every one of a
voice's eight bin:volume pairs, `[APU-VPAIRS]`) showed why: the music voice sends to the front pair (bins 0/1)
and also, louder, both channels to bin 24; in car selection its front pair is muted and it plays through bin 24
alone; in a race every engine/effect voice goes to the front pair at its pan and to bins 12-14 6-10 dB louder,
plus a little to bin 10. Those are DirectSound effect sends (XDK mixbins: 0-5 speakers, 6-9 crosstalk, 10
I3DL2 reverb, 11-30 FXSEND_0..19), inputs of the effect chains in the title's GP image (the front end loads
`Compressor.dat` / `Listener.dat`), which mix to the speakers. The GP is a stub, and its stand-in summed every
bin by parity (even = left), so bins 12, 14 and 24 all landed on the left.

Fix (`apu_dsp.c`, toolkit patch): the default mixdown now takes the speaker bins as speakers (centre/LFE to both),
the crosstalk bins 6-9 by side, each effect send as a centred mono return and the reverb send at half that.
Run `au2` against `fz3`: front end R/L 0.99-1.01, race 0.95-1.00, no clipping. `RECOMP_APU_MIXDOWN_ALL=1` is the
parity sum, `=0` the two-bin read. The effect chains themselves (EQ, compression) are not emulated; a race is
therefore close to mono. Checked from the dumps only, not by ear. Also logged now: `[APU] submix N headroom`
(PGR2 sets 1 on every bin, so headroom is not part of it) and `[APU] HRTF submixes`.

**User, same evening: race audio still broken** (what it sounds like not yet known). The effects' real return
path: voices 243-246 (`fmt E20000CA`, 24-bit in 32, looping, rate 1.0) play buffers in the GP scratch page
(`0x00744004..`) into the speaker bins at their own volumes -- the GP program's output. With the GP a stub those
buffers stay silent, and the mixdown above is a stand-in for them. The principled fix is the GP itself: xemu's
DSP56300 core (`hw/xbox/mcpx/dsp/`, ~2,400 lines plus `dsp_emu.inl`; a copy in
`D:\Documents\Visual Studio 2019\Projects\xemu-master`) running the title's GP image.

## 17. Freeze going back to the menus after a race: a suspended lock waiter (fixed); DirectSound's event lists (open); APU trap crashes (fixed)

The user's `run.log`: after the finish jingle (`UI_RaceFinishSuccess.wma`), the profile save and the loader thread
(`0x1589E0`), the front end loaded `English_frontend/uifont_Resource.xpr` and then stopped; normally the next
thing is the front end's audio banks (`Listener.dat`, `UI_Hi.xwb`). From there the main thread (esp
`0x00F7F1A4`) called KeQuerySystemTime and nothing else, 5 million times a second, and the race's streamer
(`0x1009E0`) never exited.

Reproduced what a finish does, not the freeze: `[0x39B320]` is the player's race state (`+0x10` laps, `+0x14` lap
index, -1 before the line, `+0x18` sector, `+0x40` lap timer in ms). With the car behind the start line, poke
`+0x14 = 1` and `+0x18 = 2` (cdb, host address = guest + 0x10000: `ed 0x3ab334 1; ed 0x3ab338 2`) and cross it:
RACE FINISHED, 1st place if the AI have not finished. Five finishes (fail and 1st place, results, replay, kudos,
back to event select) and a pause-menu quit all came back. No freeze.

What the code says. DSOUND's KeQuerySystemTime callers: `sub_001F028F` is the timer queue's KTIMER DPC body
(`0x1F06A6`, `ret 0x10`): it walks the sorted list at `core+0x4A8`, fires each expired node (`RemoveEntryList`
`0x1EB580`, callback vtable+0x24) and re-arms the KTIMER for the first one not due; its insert (`0x1F0883`) never
queues a node already due. So that walk can only spin if the list is corrupt: a node the head points to but which
links to itself (what inserting a node twice leaves), which `RemoveEntryList` takes for "already removed". The
loop then fires the same node forever, calling KeQuerySystemTime each time -- the user's signature (DPCs drain on
the thread that lowers IRQL, here the main thread).

The same corruption reproduced once, elsewhere: run `ir1` hung in the front end (XMV `pbg.xmv` background) with
the gate holder in a guest loop and no kernel calls (`[IRQ] wait: ... a guest loop here makes no kernel call`).
cdb: main thread in `sub_001F0311` (DSOUND's immediate-event drain, list `core+0x4B0`, from `sub_001EBBE7` under
XMV), looping on `while (head->Flink != head) MoveToTail(local, head->Flink)` (`sub_001EFE1F`), which never ends
for a self-linked first node. Both lists guard insertion with flag bit 2 of the node under DSOUND's IRQL lock
("fs:[0x24] >= 2, or raise"), so a double insert means two threads in DSOUND at DISPATCH at once, or a node
re-initialised while still queued. Probes added to the toolkit, all silent so far: `[IRQL] thread N at IRQL 2
without the DISPATCH gate` and `[IRQL] ... publishes IRQL into TIB ..., which thread M also uses` (kernel_hal.c;
neither fired in a run to the race; removed again, see 15), and a spin detector in the kernel dispatcher: `[KERNEL] thread N: ordinal X
called 20000000 times in a row ... image addresses on its stack: ...` -- the next freeze names its loop. Also
`[KERNEL] deferred I/O APC queue full` (the streamer's mask is 3 bits per file object; a backlog never passed 7,
so the 16-deep queue is not it). NOTES 12's intermittent crash at race load (`sub_001F25D7`, a DSOUND list link
of 0) looks like the same family.

**Reproduced the crash, and one cause fixed (toolkit, 2026-11-02).** Run w2 sat at the Duomo 1 grid and crashed
right after a slow logged flip (thousands of log lines plus step dumps): read at `0xFFFFFFBE` in `sub_001F25D7`,
guest stack `0x1F0205 <- 0x1F07CE <- 0x1F086B <- 0x1F0981 <- 0x1F09FE <- 0x1F7670`. That is DSOUND's APU
service routine (`sub_001F0959`: ISTS bit 4, FETINTSTS) -> `sub_001F083C` (FECTL trap reason REQUESTED ->
FEDECMETH 0x8000 = SE2FE_IDLE_VOICE, FEDECPARAM = voice) -> `sub_001F01B8`, which takes
`voices[idx]` (`[this+0x88+4*idx]`) without a null check and calls `sub_001F25D7` on it (unlink from the mixbin
list) with this = 0. How the slot gets nulled: Stop (`sub_001F27B3`) calls `sub_001F5E19(1)` to halt the front
end, which does nothing when FECTL is already trapped; then, with the voice still marked playing, it unlinks it
itself (`sub_001F25D7(0)`, no notification), and the release (`sub_001F2154` -> `sub_001EFFD5`) zeroes the
hardware voice and nulls the slot. On the console the service routine runs at DIRQL microseconds after the trap,
ahead of the title's DISPATCH-level code, so the slot is still there. Here the APU interrupt is posted to the
gate holder and runs at its next safe point, which can be after the whole Stop + release region.
`sub_001F01B8` does skip a voice whose list entry is self-linked, so DirectSound expects late traps for voices
it has unlinked, but not for freed ones; and a slot already reused for a new voice would have that voice
"completed" instead -- a candidate for the event-list corruption above.

Fix (`apu_vp.c` `mcpx_apu_vp_retract_stale_idle_trap`, called from `apu_core.c` `apu_call_isr` under the APU
lock just before the routine runs): if the pending trap is SE2FE_IDLE_VOICE and its voice is no longer in any
of the three voice lists, or is active again, retract it (FE back to free running, FETINTSTS down, line
re-derived). That is the state the console's order leaves: the voice off the list, the FE running.
`RECOMP_APU_STALE_TRAP=0` delivers such traps as before. Run w5: `[APU] stale idle-voice trap retracted: voice
115 no longer in a list` and 7 more within a minute at the grid, so this happens all the time.

The crash w5 still had (same signature, after two cdb attaches) was a different case: an idle trap for **voice
0**, which DirectSound never allocates (slots 0-63 were all null at the grid). With a null slot `sub_001F01B8`
compares the trap's voice against `word [0x0A]` of guest page 0, which is all zero here (unmapped on the
console), so only voice 0 passes; `sub_001F25D7` with this = 0 then gives exactly the crash registers
(`eax=0 ecx=0x488 edi=0xFFFFFFB4`, `ebx` is unrelated). How the walk gets to voice 0: the release
(`sub_001F2154`) zeroes the voice block with `rep stosd` before it writes the self-link that DirectSound uses for
"unlinked" (the loop at `001F26B4` uses the same convention), so for a moment the link reads 0. A voice-list
walk -- the VP's, or this check's own -- that reads the link then follows it to voice 0's blank block, inactive
and "linked". Fix: a **blank voice** (whole 128-byte block zero apart from the link, `voice_is_blank`) ends the
VP walk for that frame instead of trapping (`[APU] list L reached blank voice N: walk ends this frame`), and a
pending trap for one is retracted (`... retracted: voice N blank`). Same knob, `RECOMP_APU_STALE_TRAP=0`.
Verified by forcing it: at the grid, cdb `ew 0x807220FC 0` (voice 0x41's link, voice blocks at guest
0x80720000 = `[0x1F7720]`) for 3 s. With the knob off (run t3) that is the w5 crash exactly; with it on (t2) the
walk logs the blank voice each frame, the game carries on, and restoring the link (`ew 0x807220FC 0x40`) brings
the list back. Unforced runs (t1: 40 cdb freezes at the grid, t2: 30 s of driving + 30 freezes) never hit
either case, so the natural rate is low. `RECOMP_APU_TRAPLOG=1` now also names the predecessor
(`voice N in list L after P, next M`) and logs every retraction. The trap log shows DirectSound routinely
leaves idle, still-linked voices that trap every frame (it ignores traps for any voice but the last of a buffer).

**A race-end freeze reproduced and fixed (toolkit, 2026-11-02): a suspended lock waiter.** New
`scripts\dev\finish_cycles.ps1 <tag> -n N` (after `to_carselect.ps1 <tag> -race -drive 0`) finishes the race N
times with the lap poke above and presses A through results, kudos and event select into the next race. Run f1
froze on its fourth race end, at the kudos screen's Continue: the loader thread (`0x1589E0`) was spawned, then no
more flips. Not the KeQuerySystemTime spin -- ordinal 128's count stood still. cdb `~*kc`: the main thread in
`sub_0012D720` (race teardown) -> ... -> `sub_001234A0` -> DSOUND `sub_001EB875` -> `sub_001EB7BE`, blocked in
RtlEnterCriticalSection on DirectSound's API lock `0x1F6FA4`; so was the audio meter thread (`sub_001298E0` ->
`sub_001ECBA0` -> `sub_001EBADC` -> `sub_001EB7BE`), with a suspend count one above every other thread's. The
lock's shadow CRITICAL_SECTION: LockCount 0xFFFFFFF9 (free, one waiter, "a waiter has been woken"),
OwningThread 0. What happened: `sub_0012D720` takes the game lock at `this+0xEFC`, then (once, flag
`[0x28F77C]`) suspends the meter thread (`this+0x2B4`, XAPI SuspendThread `0x18F419` from `0x12D799`; resumed at
the next race start, `0x12AA86`) and tears down audio through DirectSound. The meter thread never takes the
game lock: it loops reading DirectSound levels (`sub_001ECBA0`) and sleeping 2 ms. It was suspended while
waiting on DirectSound's lock, as the waiter that the last release had woken. Windows' critical section wakes
no other waiter until the woken one retries, so the lock stayed free and untakeable. On the console the caller
has the one CPU and the meter thread is nearly always in its sleep when suspended; here it runs beside the
teardown and contends for DirectSound's lock with it.

Fix (`kernel_thread.c` `xbox_SuspendGuestThread`, used by NtSuspendThread and KeSuspendThread): every thread
counts the guest locks it holds or is acquiring (`xbox_ThreadLockDepthAdd` in RtlEnter/LeaveCriticalSection and
the DISPATCH gate's enter/try/leave); a suspend of another thread that finds that count non-zero (after
GetThreadContext, so the target has really stopped) resumes it, yields and tries again, for up to
`RECOMP_SAFE_SUSPEND_MS` (default 500), then suspends it where it is
(`[THREAD] NtSuspendThread: thread N still inside a guest lock after ...`). A deferred one logs `[THREAD]
NtSuspendThread: thread N was inside a guest lock; suspended after it left (T tries, M ms)`.
`RECOMP_SAFE_SUSPEND=0` suspends at once, as before. Windows only (POSIX SuspendThread only counts).
Verified on demand with a test knob (game side, `recomp_manual.c` wrapping `sub_0018F419`):
`RECOMP_TEST_SUSPEND_RACE_MS=N` has a host helper thread hold DirectSound's lock for N ms at the teardown's
suspend, so the meter thread is queued on it when suspended. With `RECOMP_SAFE_SUSPEND=0` and N = 200 (run h3) the
first race end froze in f1's state exactly (main in `sub_0012D720` and the meter, suspend count 2, both in
`sub_001EB7BE`). With the fix (h4) three race ends in a row came back, each suspend logged `suspended after it left
(~100 tries, ~190 ms)`. Unforced the freeze is rare: f1 froze on its 4th race end, but 12 race ends with the
fix (f2) and 11 without it (f3) all came back. Holding the lock in the meter thread itself, or in the teardown
before the suspend, did not reproduce it (h0-h2): the meter is then the holder, or takes the released lock
within microseconds, before the suspend lands.

Also new, game side (`recomp_manual.c`, wired by `patch_gen.py` renaming the generated functions to `*_gen`):
`RECOMP_DS_LISTCHECK` wraps DirectSound's two list inserts (`sub_001F0208` immediate, `sub_001F0883` timer) and
drains (`sub_001F028F`, `sub_001F0311`). An insert of a node that is still on either list logs `[DSLIST] ... insert
of a queued node` with the node, its owner and the guest stack, and (1, default) unlinks it first so the list
stays a list; 2 logs only; 0 is off. A drain that finds a broken link logs `[DSLIST] ... broken at entry N`.
Silent so far: the user's KeQuerySystemTime spin (the self-linked node) has not recurred, so its cause is still
open; the next one names its inserter.

## Next

0. Sunlit road (15): the hardware rule behind `FOGW` + `MASKBLEND` -- needs the user's xemu RenderDoc capture of
   the plaza (`807D8000` after b612-b614, a near-road pixel's T3 sample).
1. The DirectSound list corruption of 17 (the user's KeQuerySystemTime spin): not seen since; `RECOMP_DS_LISTCHECK`
   logs the inserter of a queued node and repairs it. Port `xbox_SuspendGuestThread` (17) to rsc2/mm3's patch.
2. The user drives a full race (window, input feel, audio); the black player car (xemu shader cache comparison).
3. More CRT x87 entries may surface as `[ICALL] Failed 0x001B5xxx/0x001B9xxx`: seed the table entry / stub
   target (10). SEH handlers referenced from `.rdata` (`0x001B2F48`, `0x001B85D9`, ...) are not seeded.
4. The toolkit fixes in 7 and 14 (narrow mul/div) are game-agnostic: carry them to rsc2recomp/mm3recomp's patch
   when convenient (14 especially: any `imul r/m8` there is mis-lifted too).
