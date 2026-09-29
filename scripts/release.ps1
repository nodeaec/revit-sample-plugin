<#
.SYNOPSIS
  Builds, stages and zips the Sample Plugin for ONE Revit year, and optionally
  compiles the Inno Setup installer (.exe) — same pipeline as the connector's
  scripts/release.ps1, adapted to this repo.

.DESCRIPTION
  One year per invocation (-RevitYear; supported 2023..2027). Produces
  release/SamplePlugin-<version>-R<year>.zip plus a .sha256 checksum.
  With Inno Setup 6 installed it also produces
  SamplePlugin-<version>-R<year>-Setup.exe via scripts/installer.iss.
  The installer AppId (-AppId, default below) is shared by all years: one
  entry in Windows Settings > Apps ("Sample Plugin"), upgraded in place.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.1 -RevitYear 2026
  powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.1 -RevitYear 2023 -Install
#>
param(
  [string]$Version = "0.1",
  [string]$RevitYear = "2026",
  [string]$Configuration = "Release",
  # Inno Setup AppId shared by every year (user-supplied identity).
  [string]$AppId = "a61b450f-4226-4edc-ad8d-42613b1555a5",
  # Compile-only escape hatch for machines without the connector installed:
  # forwarded to the build as -p:NodeAecConnectorDll=<path>.
  [string]$NodeAecConnectorDll = "",
  [switch]$Install,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

if ($args.Count -gt 0) {
  throw "Unrecognized arguments: $($args -join ' '). Use -RevitYear <year> (e.g. -RevitYear 2023)."
}
if ($Version -notmatch '^\d+\.\d+(\.\d+){0,2}([.-][0-9A-Za-z]+)*$') {
  throw "Invalid version: '$Version'. Use SemVer (e.g. 0.1) and pass the year with -RevitYear <year>."
}
if ($RevitYear -notin @("2023","2024","2025","2026","2027")) {
  throw "Unsupported RevitYear '$RevitYear': use 2023, 2024, 2025, 2026 or 2027."
}
if ($AppId -notmatch '^\{[0-9A-Fa-f-]{36}\}$|^[0-9A-Fa-f-]{36}$') {
  throw "Invalid AppId '$AppId': expected a GUID, with or without braces."
}
if ($AppId -notmatch '^\{') { $AppId = "{$AppId}" }

# This script lives in <repo>\scripts: the repo root holds src/.
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $RepoRoot "src\SamplePlugin\SamplePlugin.csproj"
$DllName = "SamplePlugin.dll"
$AddinTemplate = Join-Path $RepoRoot "src\SamplePlugin\SamplePlugin.addin"
$ReleaseDir = Join-Path $RepoRoot "release"
$StageDir = Join-Path $ReleaseDir "stage\SamplePlugin"
$ZipPath = Join-Path $ReleaseDir "SamplePlugin-$Version-R$RevitYear.zip"

# Resolve the TFM from the project (single source of truth, per RevitYear).
$TargetFramework = (& dotnet msbuild $Project -getProperty:TargetFramework -p:RevitYear=$RevitYear -nologo -v:quiet |
  Select-Object -Last 1).ToString().Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($TargetFramework)) {
  throw "Could not resolve TargetFramework for RevitYear=$RevitYear (exit $LASTEXITCODE)."
}
$OutDir = Join-Path $RepoRoot "src\SamplePlugin\bin\$RevitYear\$Configuration\$TargetFramework"

if (-not $SkipBuild) {
  $buildArgs = @("build", $Project, "-c", $Configuration, "-p:RevitYear=$RevitYear")
  if ($NodeAecConnectorDll -ne "") { $buildArgs += "-p:NodeAecConnectorDll=$NodeAecConnectorDll" }
  Write-Host "==> dotnet $($buildArgs -join ' ') ($TargetFramework)"
  & dotnet $buildArgs
  if ($LASTEXITCODE -ne 0) { throw "dotnet build failed ($LASTEXITCODE)" }
}

$dll = Join-Path $OutDir $DllName
if (-not (Test-Path $dll)) { throw "Build output not found: $dll" }

# Stage: clean + copy runtime payload (plugin DLL + deps file; never the
# connector DLL, never RevitAPI/AdWindows — same rule family as the build).
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item $StageDir -ItemType Directory -Force | Out-Null
Get-ChildItem $OutDir -Filter *.dll |
  Where-Object { $_.Name -notlike "RevitAPI*" -and $_.Name -ne "AdWindows.dll" -and $_.Name -notlike "UIFramework*" -and $_.Name -ne "NodeAec.Connector.dll" } |
  Copy-Item -Destination $StageDir -Force
Get-ChildItem $OutDir -Filter *.deps.json -ErrorAction SilentlyContinue |
  Copy-Item -Destination $StageDir -Force
if (Test-Path (Join-Path $RepoRoot "README.md")) {
  Copy-Item (Join-Path $RepoRoot "README.md") (Join-Path $StageDir "README.md") -Force
}

# Stage the .addin with the absolute Assembly path for THIS year
# (mirrors the connector's release.ps1; AddInId stays the sample's own).
$installDir = "C:\ProgramData\Autodesk\Revit\Addins\$RevitYear\SamplePlugin"
[xml]$addin = Get-Content $AddinTemplate
$addin.RevitAddIns.AddIn.Assembly = "$installDir\$DllName"
$addin.Save((Join-Path $StageDir "SamplePlugin.addin"))

# Zip + checksum
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
New-Item $ReleaseDir -ItemType Directory -Force | Out-Null
Compress-Archive -Path "$StageDir\*" -DestinationPath $ZipPath -Force
$hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $ZipPath -Leaf)" | Out-File "$ZipPath.sha256" -Encoding ascii
Write-Host "==> release: $ZipPath"
Write-Host "    sha256: $hash"

# Optional: Inno Setup .exe installer for THIS Revit year. Requires Inno
# Setup 6 (https://jrsoftware.org/isdl.php). Without ISCC.exe the .zip above
# remains the only artifact - no failure.
$setupName = "SamplePlugin-$Version-R$RevitYear-Setup.exe"
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($iscc) {
  $versionNum = if ($Version -match '^\d+\.\d+$') { "$Version.0" } else { $Version }
  $iss = Join-Path $PSScriptRoot "installer.iss"
  Write-Host "==> ISCC $iss (Revit $RevitYear, AppId $AppId)"
  & $iscc "/DAppVersion=$Version" "/DAppVersionNum=$versionNum" "/DRevitYear=$RevitYear" "/DAppId=$AppId" "/DPayloadStage=$StageDir" "/O$ReleaseDir" $iss
  if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

  $setupPath = Join-Path $ReleaseDir $setupName
  if (-not (Test-Path $setupPath)) { throw "Setup output not found: $setupPath" }
  $setupHash = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
  "$setupHash  $setupName" | Out-File "$setupPath.sha256" -Encoding ascii
  Write-Host "==> setup: $setupPath"
  Write-Host "    sha256: $setupHash"

  # Bundle the installer with its checksum: one zip per Setup.exe.
  $setupZip = Join-Path $ReleaseDir ($setupName -replace '\.exe$','.zip')
  if (Test-Path $setupZip) { Remove-Item $setupZip -Force }
  Compress-Archive -Path $setupPath, "$setupPath.sha256" -DestinationPath $setupZip -Force
  $setupZipHash = (Get-FileHash $setupZip -Algorithm SHA256).Hash.ToLowerInvariant()
  "$setupZipHash  $(Split-Path $setupZip -Leaf)" | Out-File "$setupZip.sha256" -Encoding ascii
  Write-Host "==> setup zip: $setupZip"
  Write-Host "    sha256: $setupZipHash"
}
else {
  Write-Warning "Inno Setup 6 (ISCC.exe) not found - only the .zip was generated. Install from https://jrsoftware.org/isdl.php to also build $setupName."
}

if ($Install) {
  $addinsDir = "$env:ProgramData\Autodesk\Revit\Addins\$RevitYear"
  $targetDir = Join-Path $addinsDir "SamplePlugin"
  Write-Host "==> install to $targetDir"
  New-Item $targetDir -ItemType Directory -Force | Out-Null
  Copy-Item "$StageDir\*.dll" $targetDir -Force
  Copy-Item (Join-Path $StageDir "SamplePlugin.addin") $addinsDir -Force
  Write-Host "==> installed Sample Plugin. Restart Revit $RevitYear."
}
