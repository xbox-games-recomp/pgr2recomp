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

## Next

1. Press Start (`RECOMP_PAD_PRESS=0x10` / `scripts\dev\press.ps1`) and follow the front end; XOnline sign-in
   prompts are likely (stub XNet/XOnline to "no network" as in MM3 if it waits).
2. A race, then audio (`RECOMP_AUDIO_WAV`), then the user's eyes on the window.
3. The toolkit fixes in 7 are game-agnostic: carry them to rsc2recomp/mm3recomp's patch when convenient.
