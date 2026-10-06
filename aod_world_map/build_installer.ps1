# Builds the release app and packages it as build\installer\Meridian-Setup-<version>.exe.
# Needs Inno Setup 6 (winget install JRSoftware.InnoSetup).
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([\d.]+)').Matches[0].Groups[1].Value

# The installer packs everything in Release, so start it empty: no stale exes or DLLs.
$release = 'build\windows\x64\runner\Release'
if (Test-Path $release) { Remove-Item $release -Recurse -Force }

$buildArgs = @('build', 'windows', '--release')
if (Test-Path google_client.json) {
  $buildArgs += '--dart-define-from-file=google_client.json'
} else {
  Write-Warning 'google_client.json not found; the installer will be built without Google sign-in.'
}
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

& $iscc "/DAppVersion=$version" windows\installer\meridian.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }

Write-Host "Installer: $(Resolve-Path "build\installer\Meridian-Setup-$version.exe")"
