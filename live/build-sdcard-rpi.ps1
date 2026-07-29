# Build the LingOS Raspberry Pi kernel natively on Windows, then assemble
# the FAT32 boot image via WSL (mtools only exists there).
$ErrorActionPreference = "Stop"

$LingOSRoot = Split-Path -Parent $PSScriptRoot
$LingRoot = Join-Path (Split-Path -Parent $LingOSRoot) "ling"
$LingExe = Join-Path $LingRoot "target\release\ling.exe"
$Dist = Join-Path $LingOSRoot "dist"

if (-not (Test-Path $LingExe)) {
    Write-Error "ling.exe not found at $LingExe`nBuild it first: cd '$LingRoot'; cargo build --release --bin ling"
}

Write-Host "==> compiling LingOS Raspberry Pi kernel"
& $LingExe build (Join-Path $LingOSRoot "kernel\rpi") --platform rpi --out $Dist

Write-Host "==> packaging FAT32 boot image (WSL)"
$wslLingOS = (wsl.exe wslpath -a "$LingOSRoot").Trim()
wsl.exe bash "$wslLingOS/live/build-sdcard-rpi.sh"
