; Sample Plugin - Inno Setup installer script (requires Inno Setup 6).
;
; ONE Setup.exe == ONE Revit year. Compiled automatically by scripts/release.ps1:
;   ISCC.exe /DAppVersion=1.0.0 /DAppVersionNum=1.0.0 /DRevitYear=2026
;            /DAppId={a61b450f-4226-4edc-ad8d-42613b1555a5}
;            /DPayloadStage=<abs path>\release\stage\SamplePlugin
;            /O<abs path>\release scripts\installer.iss
;
; Result: SamplePlugin-<version>-R<RevitYear>-Setup.exe - double-click
; installer for non-technical users. It installs the payload ONLY into
; %ProgramData%\Autodesk\Revit\Addins\<RevitYear>\SamplePlugin\ and writes
; the .addin manifest with the absolute Assembly path for that year. When the
; target Revit year is not installed, Setup aborts before touching any file.
;
; AppId note: unlike the connector (one AppId per year), this sample ships a
; single user-supplied AppId shared by all years, so Windows Settings > Apps
; shows ONE entry ("Sample Plugin") and each year's Setup upgrades it in
; place. /DRevitYear defaults to 2026 and one Setup handles exactly that year
; (2023..2027).
;
; Rerun behavior: re-running Setup detects the previous install. Yes =
; uninstall it and close (run Setup again to install). No = upgrade in
; place. Uninstall is also available in Windows Settings > Apps and in
; {app}\unins000.exe.
;
; NOTE: this file must stay plain ASCII (ISCC reads scripts as ANSI/UTF-8-BOM).

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef AppVersionNum
  #define AppVersionNum "1.0.0"
#endif
#ifndef RevitYear
  #define RevitYear "2026"
#endif
#ifndef AppId
  #error AppId is required: compile with /DAppId={GUID} (release.ps1 always passes it).
#endif
#ifndef PayloadStage
  #define PayloadStage "..\release\stage\SamplePlugin"
#endif

; Guard rail: one Setup installs exactly one supported Revit year.
#if (RevitYear != "2023") && (RevitYear != "2024") && (RevitYear != "2025") && (RevitYear != "2026") && (RevitYear != "2027")
  #error RevitYear must be one of 2023, 2024, 2025, 2026 or 2027.
#endif

[Setup]
; Shared AppId (release.ps1 passes a bare {GUID} via /DAppId); Inno's constant
; parser needs the literal "{" escaped as "{{".
AppId={#StringChange(AppId, "{", "{{")}
AppName=Sample Plugin - Revit {#RevitYear}
AppVersion={#AppVersion}
AppPublisher=Node.aec
AppPublisherURL=https://nodeaec.com.br
AppSupportURL=https://nodeaec.com.br
AppUpdatesURL=https://nodeaec.com.br/products/revit-sample-plugin
VersionInfoVersion={#AppVersionNum}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductName=Sample Plugin - Revit {#RevitYear}
VersionInfoDescription=Sample Plugin Revit {#RevitYear} add-in installer
DefaultDirName={autopf}\Sample Plugin\Revit {#RevitYear}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputBaseFilename=SamplePlugin-{#AppVersion}-R{#RevitYear}-Setup
InfoAfterFile=installer-after.txt

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

; All user-facing custom strings, localized and scoped to this Revit year.
; Code reads them with CustomMessage('Name'), which follows the wizard language.
[CustomMessages]
brazilianportuguese.PreviousFound=Uma instalacao anterior do Sample Plugin para o Revit {#RevitYear} foi encontrada.%n%nSim = desinstalar a versao anterior e fechar o instalador.%n(Depois, execute o instalador novamente para instalar.)%nNao = atualizar por cima, sem desinstalar.%nCancelar = sair sem alterar nada.
english.PreviousFound=A previous Sample Plugin install for Revit {#RevitYear} was found.%n%nYes = uninstall the previous version and close Setup.%n(Then run Setup again to install.)%nNo = upgrade in place without uninstalling.%nCancel = exit without changing anything.
brazilianportuguese.UninstalledDone=A versao anterior foi desinstalada. Execute o instalador novamente para instalar a nova versao.
english.UninstalledDone=The previous version was uninstalled. Run Setup again to install the new version.
brazilianportuguese.RevitMustClose=Feche o Autodesk Revit antes de continuar.%nO instalador precisa substituir os arquivos do add-in, que estao em uso.
english.RevitMustClose=Close Autodesk Revit before continuing.%nSetup needs to replace the add-in files, which are in use.
brazilianportuguese.RevitMustCloseUninstall=Feche o Autodesk Revit antes de desinstalar.%nO desinstalador precisa remover os arquivos do add-in, que estao em uso.
english.RevitMustCloseUninstall=Close Autodesk Revit before uninstalling.%nThe uninstaller needs to remove the add-in files, which are in use.
brazilianportuguese.RevitYearMissing=O Autodesk Revit {#RevitYear} nao foi encontrado em C:\Program Files\Autodesk\Revit {#RevitYear}.%n%nInstale o Autodesk Revit {#RevitYear} ou execute o instalador correspondente a outra versao do Revit.%nNenhum arquivo foi alterado.
english.RevitYearMissing=Autodesk Revit {#RevitYear} was not found at C:\Program Files\Autodesk\Revit {#RevitYear}.%n%nInstall Autodesk Revit {#RevitYear} or run the installer that matches another Revit version.%nNo files were changed.
brazilianportuguese.CopyFailed=Nao foi possivel substituir os arquivos do add-in. Feche o Autodesk Revit e execute o instalador novamente.
english.CopyFailed=Could not replace the add-in files. Close Autodesk Revit and run Setup again.
brazilianportuguese.FinishFailedHeading=A instalacao nao foi concluida
english.FinishFailedHeading=Setup did not finish
brazilianportuguese.FinishFailedText=Alguns arquivos nao puderam ser atualizados (talvez o Revit estivesse aberto).%nFeche o Autodesk Revit e execute o instalador novamente.
english.FinishFailedText=Some files could not be updated (Revit may have been open).%nClose Autodesk Revit and run Setup again.
brazilianportuguese.AfterText=Instalacao concluida!%n%nAbra o Autodesk Revit, clique na aba "Node.aec" e depois no botao "Hello World" do painel "Sample Plugin".%n%nO comando verifica sua licenca no Node.aec Connector antes de executar.
english.AfterText=Installation finished!%n%nOpen Autodesk Revit, click the "Node.aec" tab and then the "Hello World" button in the "Sample Plugin" panel.%n%nThe command checks your license with the Node.aec Connector before running.

; Payload staged by release.ps1 (plugin DLL, .deps.json, README).
; The staged .addin is excluded: the per-year manifest is generated in [Code].
[Files]
Source: "{#PayloadStage}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion; Excludes: "*.addin"

; Post-install notes per language (embedded; ssDone loads the one
; matching the wizard language into the InfoAfter page).
Source: "installer-after.txt"; Flags: dontcopy
Source: "installer-after-en.txt"; Flags: dontcopy

[Code]
const
  // Revit add-in identity of the Sample Plugin (matches
  // src/SamplePlugin/SamplePlugin.addin; never reuse another add-in's GUID).
  SampleAddInId = 'B6BD6575-DBB6-412A-A5EA-0843ABE8D9B6';
  // Single target Revit year, fixed at compile time by /DRevitYear=<year>.
  TargetRevitYear = '{#RevitYear}';
  // Revit installation root. Revit's default layout is
  // "C:\Program Files\Autodesk\Revit <year>" (space); some deployments use
  // "C:\Program Files\Autodesk\Revit\<year>". Both layouts are accepted.
  AutodeskRoot = 'C:\Program Files\Autodesk';
  // This install's uninstall key. release.ps1 passes the shared AppId
  // via /DAppId; Inno writes the uninstall entry under "{GUID}_is1".
  UninstallKey = '{#AppId}_is1';
  AddInTemplate =
    '<?xml version="1.0" encoding="utf-8"?>' + #13#10 +
    '<RevitAddIns>' + #13#10 +
    '  <AddIn Type="Application">' + #13#10 +
    '    <Name>Sample Plugin</Name>' + #13#10 +
    '    <Assembly>%s</Assembly>' + #13#10 +
    '    <AddInId>' + SampleAddInId + '</AddInId>' + #13#10 +
    '    <FullClassName>SamplePlugin.App</FullClassName>' + #13#10 +
    '    <VendorId>NODEAEC</VendorId>' + #13#10 +
    '    <VendorDescription>Node.aec - https://nodeaec.com.br</VendorDescription>' + #13#10 +
    '  </AddIn>' + #13#10 +
    '</RevitAddIns>' + #13#10;

var
  InstallFailed: Boolean;

// True when this Setup's Revit year is installed. Accepts the default install
// folders ("Revit <year>" and "Revit\<year>") and the Autodesk registry signal
// ("SOFTWARE\Autodesk\Revit\<year>"), so a non-default install folder does not
// cause a false abort.
function IsTargetRevitInstalled(): Boolean;
var
  InstallLocation: string;
begin
  Result :=
    DirExists(AutodeskRoot + '\Revit ' + TargetRevitYear) or
    DirExists(AutodeskRoot + '\Revit\' + TargetRevitYear) or
    RegKeyExists(HKLM64, 'SOFTWARE\Autodesk\Revit\' + TargetRevitYear) or
    RegKeyExists(HKLM32, 'SOFTWARE\Autodesk\Revit\' + TargetRevitYear) or
    RegQueryStringValue(HKLM64, 'SOFTWARE\Autodesk\Revit\Autodesk Revit ' + TargetRevitYear, 'InstallLocation', InstallLocation);
end;

// Recursively copies SrcDir into DstDir. Returns the number of copy failures
// (locked files, e.g. Revit running with the DLL loaded).
function CopyDirTree(const SrcDir, DstDir: string): Integer;
var
  FindRec: TFindRec;
  Src, Dst: string;
begin
  Result := 0;
  ForceDirectories(DstDir);
  if FindFirst(SrcDir + '\*', FindRec) then
  try
    repeat
      if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
      begin
        Src := SrcDir + '\' + FindRec.Name;
        Dst := DstDir + '\' + FindRec.Name;
        if DirExists(Src) then
          Result := Result + CopyDirTree(Src, Dst)
        // The Setup uninstaller lives in {app} too (unins000.*, unins001.*,
        // ...); never propagate it into the Revit add-in folders.
        // FailIfExists=False overwrites the destination, which upgrades
        // and reinstalls require.
        else if CompareText(Copy(FindRec.Name, 1, 5), 'unins') <> 0 then
          if not CopyFile(Src, Dst, False) then
            Result := Result + 1;
      end;
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

// Deletes stray Setup uninstaller files (unins*.*) from a directory.
// Harmless when none exist.
procedure DeleteUninstallerStrays(const Dir: string);
var
  FindRec: TFindRec;
  Path: string;
begin
  if FindFirst(Dir + '\unins*', FindRec) then
  try
    repeat
      Path := Dir + '\' + FindRec.Name;
      if (FindRec.Name <> '.') and (FindRec.Name <> '..') and not DirExists(Path) then
        DeleteFile(Path);
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

// Writes the per-year .addin manifest with the absolute Assembly path.
function WriteAddInManifest(const AddinsDir: string): Boolean;
var
  AssemblyPath, Xml: string;
begin
  AssemblyPath := AddinsDir + '\SamplePlugin\SamplePlugin.dll';
  Xml := Format(AddInTemplate, [AssemblyPath]);
  Result := SaveStringToFile(AddinsDir + '\SamplePlugin.addin', Xml, False);
end;

// True when a process with the given image name is running (WMI lookup).
// Any lookup failure is treated as "not running" (fail-open for detection;
// the copy step still reports locked files honestly).
function IsProcessRunning(const ProcessName: string): Boolean;
var
  Locator, Service, Procs: Variant;
begin
  Result := False;
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Procs := Service.ExecQuery('SELECT ProcessId FROM Win32_Process WHERE Name="' + ProcessName + '"');
    Result := (not VarIsNull(Procs)) and (Procs.Count > 0);
  except
    Result := False;
  end;
end;

// Finds the previous install (same AppId) uninstall command.
// Returns True when found.
function GetPreviousUninstallString(var UninstallString: string): Boolean;
begin
  Result := True;
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + UninstallKey, 'UninstallString', UninstallString) then Exit;
  if RegQueryStringValue(HKLM32, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + UninstallKey, 'UninstallString', UninstallString) then Exit;
  Result := False;
end;

// Offers uninstall-first when re-running over a previous install.
// Yes = uninstall the previous version and close (does NOT continue
// installing; run Setup again to install). No = upgrade in place.
// Silent installs skip the prompt and upgrade in place.
// All prompts follow the wizard language via [CustomMessages].
function InitializeSetup(): Boolean;
var
  UninstallString, Clean: string;
  Choice, ExecCode: Integer;
begin
  Result := True;
  InstallFailed := False;
  if WizardSilent() then
    Exit;
  if not GetPreviousUninstallString(UninstallString) then
    Exit;
  Choice := MsgBox(CustomMessage('PreviousFound'), mbConfirmation, MB_YESNOCANCEL);
  if Choice <> IDYES then
  begin
    Result := Choice = IDNO;
    Exit;
  end;
  Clean := RemoveQuotes(Trim(UninstallString));
  Exec(Clean, '/SILENT /SUPPRESSMSGBOXES', '', SW_SHOW, ewWaitUntilTerminated, ExecCode);
  MsgBox(CustomMessage('UninstalledDone'), mbInformation, MB_OK);
  Result := False;
end;

// Clean pre-flight abort (no files touched, no success page): the target
// Revit year must be installed and Revit must be closed before any copy.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  NeedsRestart := False;
  Result := '';
  if not IsTargetRevitInstalled() then
    Result := CustomMessage('RevitYearMissing')
  else if IsProcessRunning('Revit.exe') then
    Result := CustomMessage('RevitMustClose');
end;

// The InfoAfter "success" page must not show when the copy step failed.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpInfoAfter) and InstallFailed;
end;

// Silent/automation runs must not read a failed copy as success: any non-zero
// code fails the build pipeline, while 0 keeps Inno's normal exit code.
function GetCustomSetupExitCode: Integer;
begin
  if InstallFailed then
    Result := 1
  else
    Result := 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Base: string;
  Failures: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\' + TargetRevitYear);
    ForceDirectories(Base);
    Failures := CopyDirTree(ExpandConstant('{app}'), Base + '\SamplePlugin');
    if not WriteAddInManifest(Base) then
      Failures := Failures + 1;
    // Repair: older installers may have copied the Setup uninstaller
    // (unins*.*) into the Revit folders; remove those strays.
    DeleteUninstallerStrays(Base + '\SamplePlugin');
    // NOTE: no RaiseException here on purpose. A raised exception inside
    // ssPostInstall does not roll back and Setup still reaches ssDone,
    // which would show the InfoAfter success page. Flag the failure
    // instead: the success page is skipped and the Finished page reports it.
    if Failures > 0 then
    begin
      InstallFailed := True;
      // /SUPPRESSMSGBOXES does not cover [Code] MsgBox calls: in a silent run
      // (no user) the box would block forever. Silent runs are told about the
      // failure by the log and by GetCustomSetupExitCode instead.
      if WizardSilent() then
        Log('Copy failed: some add-in files could not be replaced (locked?).')
      else
        MsgBox(CustomMessage('CopyFailed'), mbError, MB_OK);
    end;
  end;
end;

// Runs when a wizard page is shown. The Finished page is where a failed copy
// must surface: ssDone fires after the wizard is hidden, so setting the
// captions there has no visible effect.
procedure CurPageChanged(CurPageID: Integer);
var
  AfterFile, AfterText: string;
  Note: AnsiString;
begin
  if (CurPageID = wpFinished) and InstallFailed then
  begin
    WizardForm.FinishedHeadingLabel.Caption := CustomMessage('FinishFailedHeading');
    WizardForm.FinishedLabel.Caption := CustomMessage('FinishFailedText');
  end;
  if (CurPageID <> wpInfoAfter) or InstallFailed then
    Exit;
  // InfoAfterFile is a single static file; load the note matching the
  // wizard language (CustomMessage AfterText stays as fallback).
  if CompareText(ActiveLanguage(), 'english') = 0 then
    AfterFile := 'installer-after-en.txt'
  else
    AfterFile := 'installer-after.txt';
  ExtractTemporaryFile(AfterFile);
  if LoadStringFromFile(ExpandConstant('{tmp}\' + AfterFile), Note) then
    WizardForm.InfoAfterMemo.Text := Note
  else
  begin
    AfterText := CustomMessage('AfterText');
    StringChange(AfterText, '%n', #13#10);
    WizardForm.InfoAfterMemo.Text := AfterText;
  end;
end;

// Refuses to uninstall while Revit holds the add-in DLLs locked, mirroring the
// install pre-flight. Returning False aborts the uninstall before any file is
// touched; silent runs have no user, so the abort is reported by the exit code
// and by the untouched files instead of a blocking message box.
function InitializeUninstall(): Boolean;
begin
  Result := not IsProcessRunning('Revit.exe');
  if (not Result) and (not UninstallSilent()) then
    MsgBox(CustomMessage('RevitMustCloseUninstall'), mbError, MB_OK);
end;

// Removes ONLY this year's add-in folder and .addin manifest. Other Revit
// years keep their own payload folders (each year's Setup wrote its own);
// they share this installer's AppId, so one Apps entry covers all years and
// uninstalling removes this year's payload with it.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Base: string;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\' + TargetRevitYear);
  DelTree(Base + '\SamplePlugin', True, True, True);
  DeleteFile(Base + '\SamplePlugin.addin');
end;
