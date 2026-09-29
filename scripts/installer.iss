; Sample Plugin - Inno Setup installer script (requires Inno Setup 6).
;
; ONE Setup.exe == ONE compatibility group of Revit years. Compiled automatically
; by scripts/release.ps1:
;   ISCC.exe /DAppVersion=0.1 /DAppVersionNum=0.1.0
;            /DGroupLabel=2023-2024 /DRevitYears=2023,2024
;            /DAppId={a61b450f-4226-4edc-ad8d-42613b1555a5}
;            /DPayloadStage=<abs path>\release\stage\SamplePlugin
;            /O<abs path>\release scripts\installer.iss
;
; Result: SamplePlugin-<version>-R<GroupLabel>-Setup.exe - double-click
; installer for non-technical users. During the wizard the user picks the Revit
; version from a dropdown listing the years of the group installed on the
; machine (plus "all installed versions", the default). The payload is copied
; into %ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin\ for the
; selected year(s), each with its own .addin manifest with an absolute Assembly
; path. When no year of the group is installed, Setup aborts before touching
; any file. Silent installs skip the dropdown and install into every installed
; year of the group; pass /RevitYear=<year> to target one year in silence.
;
; AppId note: unlike the connector (one AppId per year), this sample ships a
; single user-supplied AppId shared by ALL groups, so Windows Settings > Apps
; shows ONE entry ("Sample Plugin") and each group's Setup upgrades it in
; place. The uninstaller therefore lists every supported Revit year where the
; add-in is present (2023..2027) and "remove all versions" removes the payload
; from all of them.
;
; Rerun behavior: re-running Setup detects the previous install. Yes =
; uninstall it and close (run Setup again to install). No = upgrade in
; place. Uninstall is also available in Windows Settings > Apps and in
; {app}\unins000.exe.
;
; NOTE: this file must stay plain ASCII (ISCC reads scripts as ANSI/UTF-8-BOM).

#ifndef AppVersion
  #define AppVersion "0.1"
#endif
#ifndef AppVersionNum
  #define AppVersionNum "0.1.0"
#endif
#ifndef RevitYears
  #error RevitYears is required: compile with /DRevitYears=2023,2024 (the compatible Revit years of this build).
#endif
#ifndef GroupLabel
  #error GroupLabel is required: compile with /DGroupLabel=2023-2024 (display label of the Revit year group).
#endif
#ifndef AppId
  #error AppId is required: compile with /DAppId={GUID} (release.ps1 always passes it).
#endif
#ifndef PayloadStage
  #define PayloadStage "..\release\stage\SamplePlugin"
#endif

[Setup]
; Shared AppId (release.ps1 passes a bare {GUID} via /DAppId); Inno's constant
; parser needs the literal "{" escaped as "{{".
AppId={#StringChange(AppId, "{", "{{")}
AppName=Sample Plugin - Revit {#GroupLabel}
AppVersion={#AppVersion}
AppPublisher=Node.aec
AppPublisherURL=https://nodeaec.com.br
AppSupportURL=https://nodeaec.com.br
AppUpdatesURL=https://nodeaec.com.br/products/revit-sample-plugin
VersionInfoVersion={#AppVersionNum}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductName=Sample Plugin - Revit {#GroupLabel}
VersionInfoDescription=Sample Plugin Revit {#GroupLabel} add-in installer
DefaultDirName={autopf}\Sample Plugin\Revit {#GroupLabel}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputBaseFilename=SamplePlugin-{#AppVersion}-R{#GroupLabel}-Setup
InfoAfterFile=installer-after.txt

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

; All user-facing custom strings, localized and scoped to this Revit year group.
; Code reads them with CustomMessage('Name'), which follows the wizard language.
[CustomMessages]
brazilianportuguese.YearPageCaption=Versao do Autodesk Revit
english.YearPageCaption=Autodesk Revit version
brazilianportuguese.YearPageDesc=Escolha para qual versao do Revit o add-in sera instalado. Apenas versoes instaladas neste computador aparecem na lista.
english.YearPageDesc=Choose which Revit version to install the add-in for. Only versions installed on this computer are listed.
brazilianportuguese.YearAllOption=Todas as versoes instaladas (%1)
english.YearAllOption=All installed versions (%1)
brazilianportuguese.YearNotAvailable=A versao %1 do Autodesk Revit nao esta disponivel neste computador.%n%nVersoes disponiveis: %2.%nNenhum arquivo foi alterado.
english.YearNotAvailable=Autodesk Revit %1 is not available on this computer.%n%nAvailable versions: %2.%nNo files were changed.
brazilianportuguese.UninstallYearCaption=Desinstalar o Sample Plugin
english.UninstallYearCaption=Uninstall Sample Plugin
brazilianportuguese.UninstallYearPick=Remover o add-in de qual versao do Revit?
english.UninstallYearPick=Remove the add-in from which Revit version?
brazilianportuguese.UninstallAllOption=Remover de todas as versoes (%1)
english.UninstallAllOption=Remove from all versions (%1)
brazilianportuguese.UninstallYearRemoved=O add-in foi removido do Revit %1.%n%nPara remover das demais versoes, execute o desinstalador novamente e escolha "Remover de todas as versoes".
english.UninstallYearRemoved=The add-in was removed from Revit %1.%n%nTo remove it from the other versions, run the uninstaller again and choose "Remove from all versions".
brazilianportuguese.UninstallOK=OK
english.UninstallOK=OK
brazilianportuguese.UninstallCancel=Cancelar
english.UninstallCancel=Cancel
brazilianportuguese.PreviousFound=Uma instalacao anterior do Sample Plugin (Revit {#GroupLabel}) foi encontrada.%n%nSim = desinstalar a versao anterior e fechar o instalador.%n(Depois, execute o instalador novamente para instalar.)%nNao = atualizar por cima, sem desinstalar.%nCancelar = sair sem alterar nada.
english.PreviousFound=A previous Sample Plugin install (Revit {#GroupLabel}) was found.%n%nYes = uninstall the previous version and close Setup.%n(Then run Setup again to install.)%nNo = upgrade in place without uninstalling.%nCancel = exit without changing anything.
brazilianportuguese.UninstalledDone=A versao anterior foi desinstalada. Execute o instalador novamente para instalar a nova versao.
english.UninstalledDone=The previous version was uninstalled. Run Setup again to install the new version.
brazilianportuguese.RevitMustClose=Feche o Autodesk Revit antes de continuar.%nO instalador precisa substituir os arquivos do add-in, que estao em uso.
english.RevitMustClose=Close Autodesk Revit before continuing.%nSetup needs to replace the add-in files, which are in use.
brazilianportuguese.RevitMustCloseUninstall=Feche o Autodesk Revit antes de desinstalar.%nO desinstalador precisa remover os arquivos do add-in, que estao em uso.
english.RevitMustCloseUninstall=Close Autodesk Revit before uninstalling.%nThe uninstaller needs to remove the add-in files, which are in use.
brazilianportuguese.RevitGroupMissing=Nenhum Autodesk Revit compativel foi encontrado neste computador (versoes: %1).%n%nInstale o Autodesk Revit %1 ou execute o instalador correspondente a outro grupo de versoes.%nNenhum arquivo foi alterado.
english.RevitGroupMissing=No compatible Autodesk Revit installation was found on this computer (versions: %1).%n%nInstall Autodesk Revit %1 or run the installer for another Revit version group.%nNo files were changed.
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
  // Compatible Revit years of this build, fixed at compile time by
  // /DRevitYears=2023,2024 (release.ps1 passes the group's years).
  SupportedYearsCsv = '{#RevitYears}';
  // Every Revit year this project supports. The AppId is shared by every
  // group, so uninstall lists/cleans the payload of all of them.
  AllProjectYearsCsv = '2023,2024,2025,2026,2027';
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
  // Years the post-install copy writes to: the dropdown choice, the
  // /RevitYear switch, or every installed supported year when nothing is
  // chosen (silent installs).
  TargetYears: TArrayOfString;
  // Install-side year chooser: page + dropdown created in InitializeWizard.
  // YearChoices holds the installed supported years; the combo box gets one
  // entry per year plus a trailing "all installed versions" entry.
  YearPage: TWizardPage;
  YearCombo: TNewComboBox;
  YearChoices: TArrayOfString;

// Splits Text on Sep into Items, in order. Empty segments are dropped.
procedure SplitText(const Text, Sep: string; var Items: TArrayOfString);
var
  Rest, Piece: string;
  P, N: Integer;
begin
  SetArrayLength(Items, 0);
  Rest := Text;
  while Rest <> '' do
  begin
    P := Pos(Sep, Rest);
    if P = 0 then
    begin
      Piece := Rest;
      Rest := '';
    end
    else
    begin
      Piece := Copy(Rest, 1, P - 1);
      Delete(Rest, 1, P - 1 + Length(Sep));
    end;
    if Piece <> '' then
    begin
      N := GetArrayLength(Items);
      SetArrayLength(Items, N + 1);
      Items[N] := Piece;
    end;
  end;
end;

// Revit years this Setup supports, in order (2023,2024 / 2025,2026 / 2027).
procedure SupportedYears(var Years: TArrayOfString);
begin
  SplitText(SupportedYearsCsv, ',', Years);
end;

// True when Year is a Revit year this project knows how to target.
function IsKnownRevitYear(const Year: string): Boolean;
begin
  Result :=
    (Year = '2023') or (Year = '2024') or (Year = '2025') or
    (Year = '2026') or (Year = '2027');
end;

// True when Revit Year is installed. Accepts the default install folders
// ("Revit <year>" and "Revit\<year>") and the Autodesk registry signal
// ("SOFTWARE\Autodesk\Revit\<year>"), so a non-default install folder does not
// cause a false negative.
function IsRevitYearInstalled(const Year: string): Boolean;
var
  InstallLocation: string;
begin
  Result :=
    DirExists(AutodeskRoot + '\Revit ' + Year) or
    DirExists(AutodeskRoot + '\Revit\' + Year) or
    RegKeyExists(HKLM64, 'SOFTWARE\Autodesk\Revit\' + Year) or
    RegKeyExists(HKLM32, 'SOFTWARE\Autodesk\Revit\' + Year) or
    RegQueryStringValue(HKLM64, 'SOFTWARE\Autodesk\Revit\Autodesk Revit ' + Year, 'InstallLocation', InstallLocation);
end;

// Supported years of this build that are installed on this machine.
procedure InstalledSupportedYears(var Years: TArrayOfString);
var
  All: TArrayOfString;
  I, N: Integer;
begin
  SetArrayLength(Years, 0);
  SupportedYears(All);
  for I := 0 to GetArrayLength(All) - 1 do
    if IsRevitYearInstalled(All[I]) then
    begin
      N := GetArrayLength(Years);
      SetArrayLength(Years, N + 1);
      Years[N] := All[I];
    end;
end;

// Years joined for display, e.g. '2023 / 2024'.
function YearsDisplayList(var Years: TArrayOfString): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to GetArrayLength(Years) - 1 do
  begin
    if Result <> '' then
      Result := Result + ' / ';
    Result := Result + Years[I];
  end;
end;

// Guard against a Setup compiled with a typo'd /DRevitYears (release.ps1
// validates the group, so this only protects direct ISCC invocations).
function SupportedYearsAreValid(): Boolean;
var
  Years: TArrayOfString;
  I: Integer;
begin
  SupportedYears(Years);
  Result := GetArrayLength(Years) > 0;
  if not Result then
    Exit;
  for I := 0 to GetArrayLength(Years) - 1 do
    if not IsKnownRevitYear(Years[I]) then
    begin
      Result := False;
      Exit;
    end;
end;

// Fills the install-side dropdown: one entry per installed supported year plus
// a trailing "all installed versions" entry (the default). A /RevitYear=<year>
// switch preselects that year when it is available.
procedure BuildYearChooser();
var
  Installed: TArrayOfString;
  ParamYear: string;
  I, N: Integer;
begin
  InstalledSupportedYears(Installed);
  YearChoices := Installed;
  N := GetArrayLength(YearChoices);
  YearCombo.Items.Clear;
  for I := 0 to N - 1 do
    YearCombo.Items.Add(YearChoices[I]);
  YearCombo.Items.Add(FmtMessage(CustomMessage('YearAllOption'), [YearsDisplayList(YearChoices)]));
  YearCombo.ItemIndex := N;
  ParamYear := ExpandConstant('{param:RevitYear|}');
  if ParamYear <> '' then
    for I := 0 to N - 1 do
      if YearChoices[I] = ParamYear then
        YearCombo.ItemIndex := I;
end;

// Resolves the year selection into TargetYears. Returns '' on success or the
// user-facing error message when /RevitYear names a year that is not installed.
// Silent installs default to every installed year of the group.
function ResolveTargetYears(): String;
var
  Installed: TArrayOfString;
  ParamYear: string;
  I: Integer;
  Found: Boolean;
begin
  Result := '';
  InstalledSupportedYears(Installed);
  SetArrayLength(TargetYears, 0);
  if WizardSilent() then
  begin
    ParamYear := ExpandConstant('{param:RevitYear|}');
    if ParamYear = '' then
      TargetYears := Installed
    else
    begin
      Found := False;
      for I := 0 to GetArrayLength(Installed) - 1 do
        if Installed[I] = ParamYear then
          Found := True;
      if not Found then
      begin
        Result := FmtMessage(CustomMessage('YearNotAvailable'), [ParamYear, YearsDisplayList(Installed)]);
        Exit;
      end;
      SetArrayLength(TargetYears, 1);
      TargetYears[0] := ParamYear;
    end;
  end
  else
  begin
    // Index = number of installed years means the trailing "all" entry.
    if (YearCombo.ItemIndex < 0) or (YearCombo.ItemIndex >= GetArrayLength(YearChoices)) then
      TargetYears := Installed
    else
    begin
      SetArrayLength(TargetYears, 1);
      TargetYears[0] := YearChoices[YearCombo.ItemIndex];
    end;
  end;
end;

// Adds the "Revit version" wizard page with its year dropdown. The page is
// skipped (ShouldSkipPage) when there is nothing to choose.
procedure InitializeWizard();
begin
  YearPage := CreateCustomPage(wpSelectTasks, CustomMessage('YearPageCaption'), CustomMessage('YearPageDesc'));
  YearCombo := TNewComboBox.Create(YearPage);
  YearCombo.Parent := YearPage.Surface;
  YearCombo.Left := 0;
  YearCombo.Top := ScaleY(12);
  YearCombo.Width := YearPage.SurfaceWidth;
  YearCombo.Style := csDropDownList;
  BuildYearChooser();
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

// True when the add-in payload folder or .addin manifest exists for Year.
function HasPayload(const Year: string): Boolean;
var
  Base: string;
begin
  Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\' + Year);
  Result := DirExists(Base + '\SamplePlugin') or FileExists(Base + '\SamplePlugin.addin');
end;

// Removes the add-in payload folder and .addin manifest of a single year.
procedure RemoveYearPayload(const Year: string);
var
  Base: string;
begin
  Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\' + Year);
  DelTree(Base + '\SamplePlugin', True, True, True);
  DeleteFile(Base + '\SamplePlugin.addin');
end;

// Every project year where the add-in is actually present. The shared AppId
// covers all groups, so this scans the whole matrix, not only this Setup's
// group.
procedure YearsWithPayload(var Years: TArrayOfString);
var
  All: TArrayOfString;
  I, N: Integer;
begin
  SetArrayLength(Years, 0);
  SplitText(AllProjectYearsCsv, ',', All);
  for I := 0 to GetArrayLength(All) - 1 do
    if HasPayload(All[I]) then
    begin
      N := GetArrayLength(Years);
      SetArrayLength(Years, N + 1);
      Years[N] := All[I];
    end;
end;

// Finds the previous install (same shared AppId) uninstall command.
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
  if not SupportedYearsAreValid() then
  begin
    MsgBox('This Setup was compiled with unsupported Revit years (' + SupportedYearsCsv + '). Rebuild it with scripts/release.ps1.', mbError, MB_OK);
    Result := False;
    Exit;
  end;
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

// Clean pre-flight abort (no files touched, no success page): at least one
// Revit year of the group must be installed, the year selection must resolve
// and Revit must be closed before any copy.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  All: TArrayOfString;
begin
  NeedsRestart := False;
  Result := '';
  InstalledSupportedYears(TargetYears);
  if GetArrayLength(TargetYears) = 0 then
  begin
    SupportedYears(All);
    Result := FmtMessage(CustomMessage('RevitGroupMissing'), [YearsDisplayList(All)]);
    Exit;
  end;
  Result := ResolveTargetYears();
  if Result <> '' then
    Exit;
  if IsProcessRunning('Revit.exe') then
    Result := CustomMessage('RevitMustClose');
end;

// The InfoAfter "success" page must not show when the copy step failed; the
// year chooser is only useful when more than one year can be selected.
function ShouldSkipPage(PageID: Integer): Boolean;
var
  Installed: TArrayOfString;
begin
  Result := (PageID = wpInfoAfter) and InstallFailed;
  if (not Result) and (YearPage <> nil) and (PageID = YearPage.ID) then
  begin
    InstalledSupportedYears(Installed);
    Result := GetArrayLength(Installed) <= 1;
  end;
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
  Failures, I: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    Failures := 0;
    // One payload folder + manifest per selected year.
    for I := 0 to GetArrayLength(TargetYears) - 1 do
    begin
      Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\' + TargetYears[I]);
      ForceDirectories(Base);
      Failures := Failures + CopyDirTree(ExpandConstant('{app}'), Base + '\SamplePlugin');
      if not WriteAddInManifest(Base) then
        Failures := Failures + 1;
      // Repair: older installers may have copied the Setup uninstaller
      // (unins*.*) into the Revit folders; remove those strays.
      DeleteUninstallerStrays(Base + '\SamplePlugin');
    end;
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

// Asks from which year the add-in should be removed. Returns True when the
// complete uninstall should proceed (the user picked "all versions", the only
// year with payload, or there is nothing to choose). Returns False when the
// user cancelled, or after removing a single year: the uninstaller then stops
// before deleting the Apps entry so the remaining years stay manageable.
function AskUninstallYear(): Boolean;
var
  Form: TSetupForm;
  Prompt: TNewStaticText;
  Combo: TNewComboBox;
  OkBtn, CancelBtn: TNewButton;
  Present: TArrayOfString;
  I, AllIndex: Integer;
begin
  Result := False;
  YearsWithPayload(Present);
  if GetArrayLength(Present) = 0 then
  begin
    // No payload found: nothing to choose, run the normal (complete)
    // uninstall so stale entries/files are cleaned up.
    Result := True;
    Exit;
  end;
  Form := CreateCustomForm(ScaleX(360), ScaleY(170), False, False);
  try
    Form.Caption := CustomMessage('UninstallYearCaption');
    Form.Position := poScreenCenter;

    Prompt := TNewStaticText.Create(Form);
    Prompt.Parent := Form;
    Prompt.Left := ScaleX(12);
    Prompt.Top := ScaleY(12);
    Prompt.Caption := CustomMessage('UninstallYearPick');

    Combo := TNewComboBox.Create(Form);
    Combo.Parent := Form;
    Combo.Left := ScaleX(12);
    Combo.Top := ScaleY(36);
    Combo.Width := ScaleX(336);
    Combo.Style := csDropDownList;
    for I := 0 to GetArrayLength(Present) - 1 do
      Combo.Items.Add(Present[I]);
    AllIndex := GetArrayLength(Present);
    Combo.Items.Add(FmtMessage(CustomMessage('UninstallAllOption'), [YearsDisplayList(Present)]));
    Combo.ItemIndex := AllIndex;

    OkBtn := TNewButton.Create(Form);
    OkBtn.Parent := Form;
    OkBtn.Caption := CustomMessage('UninstallOK');
    OkBtn.Width := ScaleX(90);
    OkBtn.Height := ScaleY(23);
    OkBtn.Left := Form.ClientWidth - ScaleX(200);
    OkBtn.Top := Form.ClientHeight - ScaleY(35);
    OkBtn.ModalResult := mrOk;
    OkBtn.Default := True;

    CancelBtn := TNewButton.Create(Form);
    CancelBtn.Parent := Form;
    CancelBtn.Caption := CustomMessage('UninstallCancel');
    CancelBtn.Width := ScaleX(90);
    CancelBtn.Height := ScaleY(23);
    CancelBtn.Left := Form.ClientWidth - ScaleX(100);
    CancelBtn.Top := OkBtn.Top;
    CancelBtn.ModalResult := mrCancel;
    CancelBtn.Cancel := True;

    Form.ActiveControl := Combo;
    if Form.ShowModal() <> mrOk then
      Exit;
    if (Combo.ItemIndex < 0) or (Combo.ItemIndex = AllIndex) then
    begin
      // "All versions" (the default): complete uninstall.
      Result := True;
      Exit;
    end;
    if GetArrayLength(Present) = 1 then
    begin
      // Removing the only year with payload is a complete uninstall.
      Result := True;
      Exit;
    end;
    RemoveYearPayload(Present[Combo.ItemIndex]);
    MsgBox(FmtMessage(CustomMessage('UninstallYearRemoved'), [Present[Combo.ItemIndex]]), mbInformation, MB_OK);
    Result := False;
  finally
    Form.Free;
  end;
end;

// Refuses to uninstall while Revit holds the add-in DLLs locked, mirroring the
// install pre-flight, and then asks which year to remove. Returning False
// aborts the uninstall before any other file is touched; silent runs have no
// user, so they remove the whole product and report problems by the exit code
// and by the untouched files instead of a blocking message box.
function InitializeUninstall(): Boolean;
var
  RevitClosed: Boolean;
begin
  RevitClosed := not IsProcessRunning('Revit.exe');
  if not RevitClosed then
  begin
    if not UninstallSilent() then
      MsgBox(CustomMessage('RevitMustCloseUninstall'), mbError, MB_OK);
    Result := False;
    Exit;
  end;
  if UninstallSilent() then
    Result := True
  else
    Result := AskUninstallYear();
end;

// Removes the add-in from EVERY supported Revit year (2023..2027), not only
// the group this Setup covers: the shared AppId gives Windows a single
// uninstall entry for the whole product, so a partial cleanup would leave the
// plugin loading in years the user just uninstalled. A partial uninstall never
// reaches this step (the year was already removed and the uninstaller
// aborted). Harmless where the year was never installed.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Years: TArrayOfString;
  Base: string;
  I: Integer;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  SplitText(AllProjectYearsCsv, ',', Years);
  for I := 0 to GetArrayLength(Years) - 1 do
  begin
    Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\' + Years[I]);
    DelTree(Base + '\SamplePlugin', True, True, True);
    DeleteFile(Base + '\SamplePlugin.addin');
  end;
end;
