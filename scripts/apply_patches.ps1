# Applies this port's changes to the xboxrecomp submodule (patches\xboxrecomp.patch).
# Safe to run any number of times: does nothing if the patch is already in.
# regen.ps1 runs it first; run it yourself once before a code-only build of a fresh clone.
#
# To update the patch after editing toolkit files:
#   git -C xboxrecomp diff > patches\xboxrecomp.patch
# Not "Stop": Windows PowerShell treats any git stderr as fatal then, and the probe below is meant to fail.
$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
$tk = Join-Path $root "xboxrecomp"
$patch = Join-Path $root "patches\xboxrecomp.patch"

if (-not (Test-Path (Join-Path $tk "CMakeLists.txt"))) {
    throw "xboxrecomp submodule is empty. Run: git submodule update --init"
}

# Run from the project root with --directory, not inside xboxrecomp: a release zip has no git metadata, and a
# leftover xboxrecomp\.git link file pointing at a missing ..\.git\modules folder makes git -C xboxrecomp fail.
$apply = @("-C", $root, "apply", "--directory=xboxrecomp")
git @apply --reverse --check $patch 2>$null
if ($LASTEXITCODE -eq 0) { "xboxrecomp patch already applied"; return }

git @apply --check $patch
if ($LASTEXITCODE -ne 0) {
    throw "xboxrecomp patch does not apply (git's error is above). Is the submodule at the pinned commit? (git submodule update)"
}
git @apply $patch
"xboxrecomp patch applied"
