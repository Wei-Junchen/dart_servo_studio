[CmdletBinding()]
param(
    [string]$Flutter = 'flutter',
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundle = Join-Path $root 'build/windows/x64/runner/Release'
$dist = Join-Path $root 'dist'
$versionLine = Select-String -LiteralPath (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([0-9][0-9A-Za-z.+-]*)\s*$' | Select-Object -First 1
if (-not $versionLine) { throw 'Could not determine the version from pubspec.yaml.' }
$name = 'dart_servo_studio-windows-x64-v' + $versionLine.Matches[0].Groups[1].Value

if (-not $NoBuild) {
    if ($env:OS -ne 'Windows_NT') { throw 'Flutter requires a Windows host with Visual Studio to build the Windows release.' }
    Push-Location $root
    try {
        & $Flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "Flutter exited with code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

foreach ($file in @('dart_servo_studio.exe', 'flutter_windows.dll', 'file_selector_windows_plugin.dll', 'data/app.so', 'data/icudtl.dat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $file) -PathType Leaf)) {
        throw "Incomplete Windows x64 release: missing $file in $bundle"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $bundle 'data/flutter_assets') -PathType Container)) {
    throw "Incomplete Windows x64 release: missing data/flutter_assets in $bundle"
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ('dart-servo-studio-' + [Guid]::NewGuid().ToString('N'))
$package = Join-Path $stage $name
New-Item -ItemType Directory -Path $package -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $bundle 'dart_servo_studio.exe') -Destination $package
    Get-ChildItem -LiteralPath $bundle -Filter '*.dll' -File | Copy-Item -Destination $package
    Copy-Item -LiteralPath (Join-Path $bundle 'data') -Destination $package -Recurse

    @'
@echo off
setlocal
pushd "%~dp0" || exit /b 1
if not defined JLINK_DIR set "JLINK_DIR=%CD%\jlink"
if exist "%JLINK_DIR%\JLink.exe" set "PATH=%JLINK_DIR%;%PATH%"
start "" "dart_servo_studio.exe" %*
popd
'@ | Set-Content -LiteralPath (Join-Path $package 'start.cmd') -Encoding Ascii

    @'
# Dart Servo Studio - Windows x64

Extract the entire ZIP and run start.cmd (or dart_servo_studio.exe).
Offline preview does not require Flutter, Dart, or J-Link. If Windows reports
missing Visual C++ runtime DLLs, install Microsoft's x64 redistributable:
https://aka.ms/vs/17/release/vc_redist.x64.exe

To use a physical probe, install the Windows 64-bit J-Link software package:
https://www.segger.com/downloads/jlink/

Keep JLink.exe and JLink_x64.dll (and any other installed DLLs) together.
Select the installed JLink.exe by full path in the app's connection settings,
add its folder to PATH, or set JLINK_DIR to that folder before running start.cmd.
The package does not redistribute J-Link. It does not flash the target board.
'@ | Set-Content -LiteralPath (Join-Path $package 'README.txt') -Encoding Ascii

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tempZip = Join-Path $stage "$name.zip"
    [IO.Compression.ZipFile]::CreateFromDirectory($package, $tempZip, [IO.Compression.CompressionLevel]::Optimal, $true)
    $hash = (Get-FileHash -LiteralPath $tempZip -Algorithm SHA256).Hash.ToLowerInvariant()
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    $zip = Join-Path $dist "$name.zip"
    Copy-Item -LiteralPath $tempZip -Destination $zip -Force
    "$hash  $name.zip" | Set-Content -LiteralPath "$zip.sha256" -Encoding Ascii
    Write-Host "Created $zip and $zip.sha256"
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
