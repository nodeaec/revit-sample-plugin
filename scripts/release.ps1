<#
.SYNOPSIS
  Builds every Revit compatibility group, stages ONE Autodesk bundle
  (SamplePlugin.bundle), zips it, optionally compiles the single Inno Setup
  installer (.exe), and optionally installs the bundle on this machine. Same
  pipeline as the Node.aec Connector's scripts/release.ps1.

.DESCRIPTION
  The bundle holds one payload per compatibility group, each compiled with the
  group's floor year (the oldest API of the group, so one DLL loads on every
  year of it):

    SamplePlugin.bundle\
      PackageContents.xml              one component per Revit year (2023..2027)
      Contents\2023-2024\              net48            (Revit 2023, 2024)
      Contents\2025-2026\              net8.0-windows   (Revit 2025, 2026)
      Contents\2027\                   net10.0-windows  (Revit 2027)

  Each Contents folder has its own SamplePlugin.addin with a relative Assembly
  path. Revit reads PackageContents.xml from
  %ProgramData%\Autodesk\ApplicationPlugins\ and loads only the component whose
  SeriesMin/SeriesMax matches its own version.

  Why a bundle instead of a .addin per Revit year: a .addin in
  %ProgramData%\Autodesk\Revit\Addins\<year>\ serves one year, so supporting five years
  means five copies to install, update and remove. A bundle is one folder that Revit
  itself maps to the right build for its version, so one installer, one update and one
  uninstall cover every year.

  Why every group is built here: a Revit year can only load a DLL built for its .NET
  runtime (see the matrix in SamplePlugin.csproj), so the bundle carries one build per
  group, each compiled against the group's oldest Revit API.

  Artifacts in release\:
    SamplePlugin-<version>.bundle.zip   the bundle, every year enabled
    SamplePlugin-<version>-Setup.exe    the installer (needs Inno Setup 6);
                                        the user picks the Revit years

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.3.0
  powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.3.0 -Install

  -Version has no default and must equal <Version> in SamplePlugin.csproj, so the
  DLL, the zip and the installer always carry the same version.
#>
param(
  [string]$Version,
  [string]$Configuration = "Release",
  [switch]$Install,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

# -File does not bind "-Param=value": the token would land in $args and the script
# would continue with defaults. Fail loudly on any leftover.
if ($args.Count -gt 0) {
  throw "Unrecognized arguments: $($args -join ' '). Usage: -Version <x.y.z> [-Install] [-SkipBuild]."
}
if ([string]::IsNullOrWhiteSpace($Version)) {
  throw "-Version is required (e.g. -Version 0.3.0). Use the same value as <Version> in src\SamplePlugin\SamplePlugin.csproj."
}
if ($Version -notmatch '^\d+\.\d+(\.\d+){0,2}([.-][0-9A-Za-z]+)*$') {
  throw "Invalid version: '$Version'. Use SemVer (e.g. 0.3.0 or 0.3.0-rc1)."
}

# Compatibility group -> Revit years. The first year of each group is the build year.
$RevitYearGroups = [ordered]@{
  "2023-2024" = @("2023","2024")
  "2025-2026" = @("2025","2026")
  "2027"      = @("2027")
}

# Plugin identity. ProductCode/UpgradeCodes identify the bundle to Autodesk's
# loader; they never change between versions. Keep them in sync with installer.iss.
$PluginName = "SamplePlugin"
$DisplayName = "Sample Plugin"
$Description = "Node.aec Sample Plugin: licensed Hello World for Autodesk Revit"
$ProductCode = "{E6D697B0-157B-44DD-B09B-48B0C0DAE14C}"
$UpgradeCode = "{979CC8B7-666B-446F-8CA1-DC5E9AAED38E}"

# The script lives in <repo>\scripts: the repo root holds src/.
$RepoRoot = Split-Path $PSScriptRoot -Parent
$Project = Join-Path $RepoRoot "src\$PluginName\$PluginName.csproj"
$ProjectDir = Split-Path $Project -Parent
$DllName = "$PluginName.dll"
$AddinTemplate = Join-Path $ProjectDir "$PluginName.addin"
$BundleName = "$PluginName.bundle"
$ReleaseDir = Join-Path $RepoRoot "release"
$StageRoot = Join-Path $ReleaseDir "stage"
$BundleStage = Join-Path $StageRoot $BundleName
$ZipPath = Join-Path $ReleaseDir "$PluginName-$Version.bundle.zip"

$ProjectVersion = (& dotnet msbuild $Project -getProperty:Version -nologo -v:quiet |
  Select-Object -Last 1).ToString().Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ProjectVersion)) {
  throw "Could not read <Version> from $Project (exit $LASTEXITCODE)."
}
if ($Version -ne $ProjectVersion) {
  throw "-Version $Version differs from <Version>$ProjectVersion</Version> in $PluginName.csproj. Update the csproj or pass -Version $ProjectVersion."
}

# Writes PackageContents.xml with one component per year in $Years. The installer
# generates the same document in [Code] for the years the user checks.
function Write-PackageContents([string]$Path, [string[]]$Years) {
  $components = foreach ($year in $Years) {
    $group = ($RevitYearGroups.Keys | Where-Object { $RevitYearGroups[$_] -contains $year })
@"
  <Components Description="Revit $year">
    <RuntimeRequirements OS="Win64" Platform="Revit" SeriesMin="R$year" SeriesMax="R$year" />
    <ComponentEntry AppName="$DisplayName" Version="$Version" ModuleName="./Contents/$group/$PluginName.addin" AppDescription="$DisplayName for Revit $year" />
  </Components>
"@
  }
  $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<ApplicationPackage SchemaVersion="1.0" AutodeskProduct="Revit" ProductType="Application" Name="$DisplayName" AppVersion="$Version" Description="$Description" Author="Node.aec" ProductCode="$ProductCode" UpgradeCodes="$UpgradeCode" OnlineDocumentation="https://nodeaec.com.br">
  <CompanyDetails Name="Node.aec" Url="https://nodeaec.com.br" />
$($components -join "`r`n")
</ApplicationPackage>
"@
  [IO.File]::WriteAllText($Path, $xml, (New-Object Text.UTF8Encoding($false)))
}

if (Test-Path $StageRoot) { Remove-Item $StageRoot -Recurse -Force }
New-Item $BundleStage -ItemType Directory -Force | Out-Null

foreach ($group in $RevitYearGroups.Keys) {
  $buildYear = $RevitYearGroups[$group][0]

  # Resolve the TFM from the project instead of repeating the matrix here.
  $tfm = (& dotnet msbuild $Project -getProperty:TargetFramework -p:RevitYear=$buildYear -nologo -v:quiet |
    Select-Object -Last 1).ToString().Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tfm)) {
    throw "Could not resolve TargetFramework for RevitYear=$buildYear (exit $LASTEXITCODE)."
  }
  $outDir = Join-Path $ProjectDir "bin\$buildYear\$Configuration\$tfm"

  if (-not $SkipBuild) {
    Write-Host "==> dotnet build -c $Configuration -p:RevitYear=$buildYear ($tfm, group $group)"
    & dotnet build $Project -c $Configuration -p:RevitYear=$buildYear --nologo -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed for RevitYear=$buildYear ($LASTEXITCODE)" }
  }
  if (-not (Test-Path (Join-Path $outDir $DllName))) { throw "Build output not found: $outDir\$DllName" }

  # Payload: plugin DLL + NodeAec.Licensing.Lite and its dependencies + deps file.
  # RevitAPI/AdWindows stay out: Revit provides them at runtime.
  $contents = Join-Path $BundleStage "Contents\$group"
  New-Item $contents -ItemType Directory -Force | Out-Null
  Get-ChildItem $outDir -Filter *.dll |
    Where-Object { $_.Name -notlike "RevitAPI*" -and $_.Name -ne "AdWindows.dll" -and $_.Name -notlike "UIFramework*" } |
    Copy-Item -Destination $contents -Force
  Get-ChildItem $outDir -Filter *.deps.json -ErrorAction SilentlyContinue |
    Copy-Item -Destination $contents -Force
  if (Test-Path (Join-Path $outDir "Resources")) {
    Copy-Item (Join-Path $outDir "Resources") $contents -Recurse -Force
  }

  # Without the license package the plugin loads, but every command fails with a
  # FileNotFoundException instead of the license dialog.
  foreach ($required in @("NodeAec.Licensing.Lite.dll", "BouncyCastle.Cryptography.dll")) {
    if (-not (Test-Path (Join-Path $contents $required))) {
      throw "Missing licensing dependency for $group`: $required was not copied to $outDir."
    }
  }

  # The manifest's Assembly path is relative to the manifest itself, so the same
  # file works wherever the bundle is installed.
  Copy-Item $AddinTemplate (Join-Path $contents "$PluginName.addin") -Force
}

$allYears = @($RevitYearGroups.Values | ForEach-Object { $_ })
Write-PackageContents (Join-Path $BundleStage "PackageContents.xml") $allYears
if (Test-Path (Join-Path $RepoRoot "README.md")) {
  Copy-Item (Join-Path $RepoRoot "README.md") (Join-Path $BundleStage "README.md") -Force
}

# Zip + checksum (the zip holds the .bundle folder itself).
New-Item $ReleaseDir -ItemType Directory -Force | Out-Null
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path $BundleStage -DestinationPath $ZipPath -Force
$hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $(Split-Path $ZipPath -Leaf)" | Out-File "$ZipPath.sha256" -Encoding ascii
Write-Host "==> release: $ZipPath"
Write-Host "    sha256: $hash"

# Optional: the single Inno Setup installer. Requires Inno Setup 6
# (https://jrsoftware.org/isdl.php); without ISCC.exe the .zip is the only artifact.
$setupName = "$PluginName-$Version-Setup.exe"
$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($iscc) {
  $versionNum = if ($Version -match '^\d+\.\d+$') { "$Version.0" } else { ($Version -split '[-+]')[0] }
  $iss = Join-Path $PSScriptRoot "installer.iss"
  Write-Host "==> ISCC $iss"
  & $iscc "/DAppVersion=$Version" "/DAppVersionNum=$versionNum" "/DPayloadStage=$BundleStage" "/O$ReleaseDir" $iss
  if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }

  $setupPath = Join-Path $ReleaseDir $setupName
  if (-not (Test-Path $setupPath)) { throw "Setup output not found: $setupPath" }
  $setupHash = (Get-FileHash $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
  "$setupHash  $setupName" | Out-File "$setupPath.sha256" -Encoding ascii
  Write-Host "==> setup: $setupPath"
  Write-Host "    sha256: $setupHash"
}
else {
  Write-Warning "Inno Setup 6 (ISCC.exe) not found - only the .zip was generated. Install from https://jrsoftware.org/isdl.php to also build $setupName."
}

if ($Install) {
  # Developer install: the whole bundle, every year enabled. Removes the legacy
  # per-year .addin installs first, or Revit would load the plugin twice.
  if (Get-Process Revit -ErrorAction SilentlyContinue) { throw "Close Autodesk Revit before installing." }
  foreach ($year in $allYears) {
    $legacy = "$env:ProgramData\Autodesk\Revit\Addins\$year"
    if ((Test-Path "$legacy\$PluginName.addin") -or (Test-Path "$legacy\$PluginName")) {
      Write-Host "==> removing legacy install from $legacy"
      Remove-Item "$legacy\$PluginName.addin" -Force -ErrorAction SilentlyContinue
      Remove-Item "$legacy\$PluginName" -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  $target = "$env:ProgramData\Autodesk\ApplicationPlugins\$BundleName"
  if (Test-Path $target) { Remove-Item $target -Recurse -Force }
  New-Item (Split-Path $target -Parent) -ItemType Directory -Force | Out-Null
  Copy-Item $BundleStage $target -Recurse -Force
  Write-Host "==> installed $target (Revit $($allYears -join ', ')). Restart Revit."
  $entries = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*_is1" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "$DisplayName - Revit*" }
  if ($entries) {
    Write-Warning "Old installer entries remain in Windows Settings > Apps ($(@($entries).Count)). Uninstall them or run the new Setup, which removes them."
  }
}
