<#
.SYNOPSIS
  Builds, stages and zips the Sample Plugin for ONE Revit compatibility group,
  and optionally compiles the Inno Setup installer (.exe) — same pipeline as
  the connector's scripts/release.ps1, adapted to this repo.

.DESCRIPTION
  One compatibility group per invocation (-RevitYear, default "2025-2026";
  groups 2023-2024 / 2025-2026 / 2027, and a single year 2023..2027 is accepted
  as an alias for its group). Produces
  release/SamplePlugin-<version>-R<group>.zip plus a .sha256 checksum.
  With Inno Setup 6 installed it also produces
  SamplePlugin-<version>-R<group>-Setup.exe via scripts/installer.iss; the
  Setup installs into %ProgramData%\Autodesk\Revit\Addins\<year>\ for EVERY
  year of the group that is installed on the machine.
  The installer AppId (-AppId, default below) is shared by all years: one
  entry in Windows Settings > Apps ("Sample Plugin"), upgraded in place.
  Uninstall removes the payload from every supported Revit year (2023..2027).

  The payload is always compiled with the group's floor year (2023, 2025 or
  2027): compiling against the oldest API of the group is what makes a single
  DLL load on every year of the group. Passing a non-floor year of a group
  resolves to that group and logs a notice.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.1 -RevitYear 2025-2026
  powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.1 -RevitYear 2023-2024 -Install
#>
param(
  [string]$Version = "0.1",
  [string]$RevitYear = "2025-2026",
  [string]$Configuration = "Release",
  # Inno Setup AppId shared by every year (user-supplied identity).
  [string]$AppId = "a61b450f-4226-4edc-ad8d-42613b1555a5",
  [switch]$Install,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

if ($args.Count -gt 0) {
  throw "Unrecognized arguments: $($args -join ' '). Use -RevitYear <group> (e.g. -RevitYear 2023-2024)."
}
if ($Version -notmatch '^\d+\.\d+(\.\d+){0,2}([.-][0-9A-Za-z]+)*$') {
  throw "Invalid version: '$Version'. Use SemVer (e.g. 0.1) and pass the group with -RevitYear <group>."
}

# One installer per Revit compatibility group. The group defines the years the
# Setup covers; the payload is always compiled with the group's floor year (the
# oldest API), which is what lets a single DLL load on every year of the group.
$RevitYearGroups = [ordered]@{
  "2023-2024" = @("2023","2024")
  "2025-2026" = @("2025","2026")
  "2027"      = @("2027")
}
# Single years remain accepted and resolve to their group.
$RevitYearToGroup = @{
  "2023" = "2023-2024"; "2024" = "2023-2024"
  "2025" = "2025-2026"; "2026" = "2025-2026"
  "2027" = "2027"
}
if ($RevitYearGroups.Contains($RevitYear)) {
  $Group = $RevitYear
}
elseif ($RevitYearToGroup.ContainsKey($RevitYear)) {
  $Group = $RevitYearToGroup[$RevitYear]
  Write-Warning "RevitYear '$RevitYear' promotes to group '$Group': building with floor year $($RevitYearGroups[$Group][0]) so one DLL loads on every year of the group."
}
else {
  throw "Unsupported RevitYear '$RevitYear': use a group (2023-2024, 2025-2026, 2027) or a single year (2023..2027)."
}
$RevitYears = $RevitYearGroups[$Group]
$BuildYear = $RevitYears[0]

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
$ZipPath = Join-Path $ReleaseDir "SamplePlugin-$Version-R$Group.zip"

# Resolve the TFM from the project (single source of truth, per build year).
$TargetFramework = (& dotnet msbuild $Project -getProperty:TargetFramework -p:RevitYear=$BuildYear -nologo -v:quiet |
  Select-Object -Last 1).ToString().Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($TargetFramework)) {
  throw "Could not resolve TargetFramework for RevitYear=$BuildYear (exit $LASTEXITCODE)."
}
$OutDir = Join-Path $RepoRoot "src\SamplePlugin\bin\$BuildYear\$Configuration\$TargetFramework"

if (-not $SkipBuild) {
  $buildArgs = @("build", $Project, "-c", $Configuration, "-p:RevitYear=$BuildYear")
  Write-Host "==> dotnet $($buildArgs -join ' ') ($TargetFramework)"
  & dotnet $buildArgs
  if ($LASTEXITCODE -ne 0) { throw "dotnet build failed ($LASTEXITCODE)" }
}

$dll = Join-Path $OutDir $DllName
if (-not (Test-Path $dll)) { throw "Build output not found: $dll" }

# Stage: clean + copy runtime payload (plugin DLL + Lite licensing DLL + deps
# file; never RevitAPI/AdWindows — same rule family as the build).
# Unlike the old connector reference, NodeAec.Licensing.Lite travels WITH the
# plugin (NuGet, CopyLocal): it is the code that verifies the license offline.
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item $StageDir -ItemType Directory -Force | Out-Null
Get-ChildItem $OutDir -Filter *.dll |
  Where-Object { $_.Name -notlike "RevitAPI*" -and $_.Name -ne "AdWindows.dll" -and $_.Name -notlike "UIFramework*" } |
  Copy-Item -Destination $StageDir -Force
Get-ChildItem $OutDir -Filter *.deps.json -ErrorAction SilentlyContinue |
  Copy-Item -Destination $StageDir -Force
if (Test-Path (Join-Path $RepoRoot "README.md")) {
  Copy-Item (Join-Path $RepoRoot "README.md") (Join-Path $StageDir "README.md") -Force
}

# Stage the .addin with the absolute Assembly path for the BUILD year. This
# staged copy only feeds the .zip (the Setup compiles its manifests in [Code],
# one per installed year of the group); keep it aligned with the build year.
# AddInId stays the sample's own.
$installDir = "C:\ProgramData\Autodesk\Revit\Addins\$BuildYear\SamplePlugin"
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

# Optional: Inno Setup .exe installer for THIS Revit group. Requires Inno
# Setup 6 (https://jrsoftware.org/isdl.php). Without ISCC.exe the .zip above
# remains the only artifact - no failure.
$setupName = "SamplePlugin-$Version-R$Group-Setup.exe"
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($iscc) {
  $versionNum = if ($Version -match '^\d+\.\d+$') { "$Version.0" } else { $Version }
  $iss = Join-Path $PSScriptRoot "installer.iss"
  Write-Host "==> ISCC $iss (Revit $Group, AppId $AppId)"
  & $iscc "/DAppVersion=$Version" "/DAppVersionNum=$versionNum" "/DGroupLabel=$Group" "/DRevitYears=$($RevitYears -join ',')" "/DAppId=$AppId" "/DPayloadStage=$StageDir" "/O$ReleaseDir" $iss
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

# True when Revit Year is installed locally (same detection as installer.iss).
function Test-RevitYearInstalled([string]$Year) {
  foreach ($dir in @("C:\Program Files\Autodesk\Revit $Year", "C:\Program Files\Autodesk\Revit\$Year")) {
    if (Test-Path $dir) { return $true }
  }
  foreach ($hive in @('HKLM:\SOFTWARE\Autodesk\Revit', 'HKLM:\SOFTWARE\WOW6432Node\Autodesk\Revit')) {
    if (Test-Path "$hive\$Year") { return $true }
  }
  $loc = (Get-ItemProperty "HKLM:\SOFTWARE\Autodesk\Revit\Autodesk Revit $Year" -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
  return [bool]$loc
}

if ($Install) {
  # Deploy to EVERY year of the group present on this machine, each with its own
  # absolute Assembly path in the .addin manifest (the staged .addin points at
  # the build year and is only used by the .zip).
  $installed = @()
  foreach ($year in $RevitYears) {
    if (-not (Test-RevitYearInstalled $year)) {
      Write-Host "==> Revit $year not found - skipping"
      continue
    }
    $addinsDir = "$env:ProgramData\Autodesk\Revit\Addins\$year"
    $targetDir = Join-Path $addinsDir "SamplePlugin"
    Write-Host "==> install to $targetDir"
    New-Item $targetDir -ItemType Directory -Force | Out-Null
    Copy-Item "$StageDir\*.dll" $targetDir -Force
    Copy-Item "$StageDir\*.deps.json" $targetDir -Force -ErrorAction SilentlyContinue
    [xml]$addin = Get-Content $AddinTemplate
    $addin.RevitAddIns.AddIn.Assembly = "C:\ProgramData\Autodesk\Revit\Addins\$year\SamplePlugin\$DllName"
    $addin.Save((Join-Path $addinsDir "SamplePlugin.addin"))
    $installed += $year
  }
  if ($installed.Count -eq 0) {
    Write-Warning "No Autodesk Revit of group $Group found locally (years: $($RevitYears -join ', ')) - nothing was copied."
  }
  else {
    Write-Host "==> installed Sample Plugin for Revit $($installed -join ', '). Restart Revit."
  }
}
