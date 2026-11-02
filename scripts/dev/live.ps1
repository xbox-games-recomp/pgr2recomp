# live.ps1 <tag> [-exe <path>] [-extraEnv "K=V;K=V"]: start the game headless with the launcher.ini env,
# RECOMP_SAVE_ROOT=saveroot, frame dumps every second in frames\<tag> and the live pad file pad_live.txt
# (drive it with press.ps1 <tag> <button>...). Leaves the game running; log in <tag>.err.
param([string]$tag, [string]$exe = "build\Release\pgr2_recomp.exe", [string]$extraEnv = "")
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $repo
Get-Process pgr2_recomp -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
New-Item -ItemType Directory -Force "frames\$tag" | Out-Null
"" | Out-File pad_live.txt -Encoding ascii
$env:RECOMP_SAVE_ROOT = "$repo\saveroot"; $env:RECOMP_WATCHDOG_SECS = "120"; $env:RECOMP_STUB_LOG = "1"
$env:RECOMP_AC97_READY = "1"; $env:RECOMP_HEAP_RECLAIM = "1"; $env:RECOMP_DISPATCH_GATE = "1"; $env:RECOMP_PB_EXEC = "1"
$env:RECOMP_D3D11 = "1"; $env:RECOMP_VBLANK = "paced"; $env:RECOMP_D3D11_VSYNC = "1"; $env:RECOMP_FLIP_PACING = "1"
$env:RECOMP_PAD_LIVE = "$repo\pad_live.txt"; $env:RECOMP_D3D11_DUMP = "frames\$tag\f"; $env:RECOMP_D3D11_DUMP_MS = "1000"
foreach ($kv in ($extraEnv -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item "env:$k" $v } }
$p = Start-Process $exe -RedirectStandardError "$tag.err" -RedirectStandardOutput "$tag.out" -PassThru -WindowStyle Hidden
"pid $($p.Id)"
