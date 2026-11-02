# finish_cycles.ps1 <tag> [-n <cycles>]: with the game at a race grid (to_carselect.ps1 <tag> -race -drive 0),
# finish the race n times: poke the player's lap index and sector (NOTES 17: [0x39B320]+0x14/+0x18, host =
# guest + 0x10000), hold the throttle across the line, then A through results, kudos and event select into the
# next race. Prints whether frame dumps still advance after each cycle (a race-end freeze stops them).
param([string]$tag, [int]$n = 5)
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $repo
$cdb = "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe"
foreach ($c in 1..$n) {
    $p = Get-Process pgr2_recomp -ErrorAction SilentlyContinue
    if (-not $p) { "cycle ${c}: process gone"; break }
    & $cdb -pv -p $p.Id -c "ed 0x3ab334 1; ed 0x3ab338 2; q" | Out-Null
    "rt:8000" | Out-File "$repo\pad_live.txt" -Append -Encoding ascii
    Start-Sleep 14
    foreach ($i in 1..8) { & "$PSScriptRoot\press.ps1" $tag -wait 8 a | Out-Null }
    $before = (Get-ChildItem "frames\$tag" | Sort-Object LastWriteTime | Select-Object -Last 1).Name
    Start-Sleep 5
    $after = (Get-ChildItem "frames\$tag" | Sort-Object LastWriteTime | Select-Object -Last 1).Name
    Copy-Item "frames\${tag}_now.png" "frames\${tag}_c$c.png"
    if ($before -eq $after) { "cycle ${c}: frames stopped at $after (freeze)"; break }
    "cycle ${c}: ok ($after)"
}
