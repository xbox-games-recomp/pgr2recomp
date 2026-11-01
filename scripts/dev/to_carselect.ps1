# to_carselect.ps1 <tag> [-exe <path>] [-race]: fresh profile in saveroot, boot (live.ps1), Start at the title,
# create the profile (plate, plate text, helmet), Single Player -> Kudos World Series -> Compact Sports Series ->
# Street Race (Florence) -> car selection. -race carries on: MINI Cooper S, Auto, Novice, Start Race, then 6 s of
# throttle. Leaves the game running; frames in frames\<tag>, log in <tag>.err, the screen after each step in
# frames\<tag>_now.png.
param([string]$tag, [string]$exe = "build\Release\pgr2_recomp.exe", [switch]$race, [string]$extraEnv = "")
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$press = "$PSScriptRoot\press.ps1"
Set-Location $repo
Get-Process pgr2_recomp -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
# Profiles live in UDATA; the Z: cache (partition images) stays, so the boot skips the cache copy.
Remove-Item "$repo\saveroot\UDATA" -Recurse -Force -ErrorAction SilentlyContinue
& "$PSScriptRoot\live.ps1" $tag -exe $exe -extraEnv "RECOMP_WATCHDOG_SECS=1800;$extraEnv"
Start-Sleep 48                                   # intro movies -> title
foreach ($i in 1..4) { & $press $tag -wait 3 start }   # title -> new profile (Start before the attract demo begins)
& $press $tag -wait 5 a     # plate style
& $press $tag -wait 6 a     # plate text: DONE
& $press $tag -wait 6 a     # helmet -> main menu
& $press $tag -wait 6 a     # Single Player
& $press $tag -wait 8 a     # Kudos World Series
& $press $tag -wait 8 a     # Compact Sports Series
& $press $tag -wait 10 a    # Street Race, Florence -> car selection
if (-not $race) { return }
& $press $tag -wait 10 a    # MINI Cooper S
& $press $tag -wait 25 a    # Auto transmission -> difficulty
& $press $tag -wait 40 a    # Novice -> pre-race
& $press $tag -wait 60 a    # Start Race -> grid
"rt:6000" | Out-File "$repo\pad_live.txt" -Append -Encoding ascii
& $press $tag -wait 7
