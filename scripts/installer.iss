; Sample Plugin - Inno Setup installer script (requires Inno Setup 6).
;
; ONE Setup.exe for every supported Revit year (2023-2027). Compiled by
; scripts/release.ps1:
;   ISCC.exe /DAppVersion=0.4.0 /DAppVersionNum=0.4.0
;            /DPayloadStage=<abs path>\release\stage\SamplePlugin.bundle
;            /O<abs path>\release scripts\installer.iss
;
; Result: SamplePlugin-<version>-Setup.exe. It installs an Autodesk bundle:
;
;   %ProgramData%\Autodesk\ApplicationPlugins\SamplePlugin.bundle\
;     PackageContents.xml        written by this script: one component per checked year
;     Contents\2023-2024\        net48 build      (only when 2023 or 2024 is checked)
;     Contents\2025-2026\        net8 build       (only when 2025 or 2026 is checked)
;     Contents\2027\             net10 build      (only when 2027 is checked)
;
; Revit loads only the component whose SeriesMin/SeriesMax matches its version,
; so an unchecked year simply has no component. The wizard shows one checkbox per
; year; installed Revit years start checked, and a re-run starts from the previous
; choice. Re-running Setup is how the user adds or removes years. Uninstall removes
; the whole bundle.
;
; Silent installs: /RevitYears=2023,2026 picks the years; without it, the previous
; choice is kept, or every installed Revit year on a first install.
;
; /WaitForRevit: when Revit is open, wait for it to close instead of refusing. The
; Node.aec Connector starts installs and updates with /SILENT /WaitForRevit from inside
; Revit. NodeAec.product.json (written by release.ps1) tells the Connector which
; Node.aec product and version this bundle is.
;
; Migration: installs made by the older per-group installers (Windows Settings >
; Apps entries named "Sample Plugin - Revit <group>", payload in
; %ProgramData%\Autodesk\Revit\Addins\<year>\) are uninstalled before the bundle is
; written, so Revit never loads the plugin twice.
;
; How Inno Setup runs the [Code] section below (event functions, in order):
;   InitializeSetup      Setup starts, before any window.
;   InitializeWizard     wizard pages are built (also runs in silent installs, so the
;                        year selection is resolved here).
;   NextButtonClick      each Next click; the year page reads its checkboxes here.
;   PrepareToInstall     last step before files are copied: the place to refuse
;                        (Revit open, bad /RevitYears) and to remove old installs.
;   [Files] copy         each entry's Check: function decides whether it is copied.
;   CurStepChanged       ssPostInstall: files are in place; PackageContents.xml is
;                        written here, because it depends on the checked years.
;   RegisterPreviousData saves the checked years in the uninstall entry, read back by
;                        GetPreviousData on the next run.
;   InitializeUninstall  the uninstaller starts.
;
; Why the uninstaller lives in %ProgramFiles%\Sample Plugin\Uninstall and not in the
; bundle: the bundle folder then holds only the bundle's own files, the same ones as the
; .bundle.zip, so IT can replace it by extracting a newer zip without breaking uninstall.
;
; NOTE: this file must stay plain ASCII (ISCC reads scripts as ANSI/UTF-8-BOM).

#ifndef AppVersion
  #error AppVersion is required: compile with /DAppVersion=0.4.0 (same as <Version> in the plugin csproj; release.ps1 passes it).
#endif
#ifndef AppVersionNum
  #error AppVersionNum is required: compile with /DAppVersionNum=0.4.0 (numeric x.y.z form of AppVersion).
#endif
#ifndef PayloadStage
  #define PayloadStage "..\release\stage\SamplePlugin.bundle"
#endif

; Plugin identity. AppId names the single Windows Settings > Apps entry (the same
; value the per-group installers used, so the entry is taken over in place).
; ProductCode/UpgradeCode identify the bundle to Autodesk's loader: keep them in
; sync with release.ps1.
#define PluginName "SamplePlugin"
#define DisplayName "Sample Plugin"
#define AppIdGuid "a61b450f-4226-4edc-ad8d-42613b1555a5"
#define ProductCode "{E6D697B0-157B-44DD-B09B-48B0C0DAE14C}"
#define UpgradeCode "{979CC8B7-666B-446F-8CA1-DC5E9AAED38E}"
; Node.aec product slug: the same value as ProductSlug in Commands\HelloCommand.cs.
#define ProductSlug "revit-sample-plugin"
#define ProductUrl "https://nodeaec.com.br/products/" + ProductSlug

[Setup]
; Inno's constant parser needs the literal "{" escaped as "{{".
AppId={{{#AppIdGuid}}
AppName={#DisplayName}
AppVersion={#AppVersion}
AppVerName={#DisplayName} {#AppVersion}
AppPublisher=Node.aec
AppPublisherURL=https://nodeaec.com.br
AppSupportURL=https://nodeaec.com.br
AppUpdatesURL={#ProductUrl}
VersionInfoVersion={#AppVersionNum}
VersionInfoProductVersion={#AppVersion}
VersionInfoProductName={#DisplayName}
VersionInfoDescription={#DisplayName} add-in installer for Autodesk Revit 2023-2027
DefaultDirName={commonappdata}\Autodesk\ApplicationPlugins\{#PluginName}.bundle
DisableDirPage=yes
UsePreviousAppDir=no
DisableProgramGroupPage=yes
; Keep the uninstaller out of the bundle folder Revit scans.
UninstallFilesDir={commonpf}\{#DisplayName}\Uninstall
UninstallDisplayName={#DisplayName}
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputBaseFilename={#PluginName}-{#AppVersion}-Setup
InfoAfterFile=installer-after.txt

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

; All user-facing custom strings. Code reads them with CustomMessage('Name'),
; which follows the wizard language.
[CustomMessages]
brazilianportuguese.YearPageCaption=Versoes do Autodesk Revit
english.YearPageCaption=Autodesk Revit versions
brazilianportuguese.YearPageDesc=Marque as versoes do Revit em que o {#DisplayName} deve ser carregado.
english.YearPageDesc=Check the Revit versions that should load {#DisplayName}.
brazilianportuguese.YearPageHint=Para mudar depois, execute este instalador de novo. Versoes nao instaladas podem ser marcadas para quando o Revit for instalado.
english.YearPageHint=To change this later, run this installer again. Versions that are not installed can be checked for when Revit is installed later.
brazilianportuguese.YearInstalled=instalado
english.YearInstalled=installed
brazilianportuguese.YearNotInstalled=nao instalado
english.YearNotInstalled=not installed
brazilianportuguese.YearNoneChecked=Marque pelo menos uma versao do Revit.
english.YearNoneChecked=Check at least one Revit version.
brazilianportuguese.LegacyFound=A instalacao anterior do {#DisplayName} (por versao do Revit) sera removida e substituida por esta.
english.LegacyFound=The previous {#DisplayName} install (per Revit version) will be removed and replaced by this one.
brazilianportuguese.SilentNoYears=Nenhuma versao do Revit foi informada nem encontrada neste computador. Use /RevitYears=2025,2026.
english.SilentNoYears=No Revit version was given or found on this computer. Use /RevitYears=2025,2026.
brazilianportuguese.SilentBadYears=Versoes do Revit invalidas em /RevitYears: %1. Use anos entre 2023 e 2027, separados por virgula.
english.SilentBadYears=Invalid Revit versions in /RevitYears: %1. Use years from 2023 to 2027, separated by commas.
brazilianportuguese.RevitMustClose=Feche o Autodesk Revit antes de continuar.%nO instalador precisa substituir os arquivos do add-in, que estao em uso.
english.RevitMustClose=Close Autodesk Revit before continuing.%nSetup needs to replace the add-in files, which are in use.
brazilianportuguese.RevitMustCloseUninstall=Feche o Autodesk Revit antes de desinstalar.%nO desinstalador precisa remover os arquivos do add-in, que estao em uso.
english.RevitMustCloseUninstall=Close Autodesk Revit before uninstalling.%nThe uninstaller needs to remove the add-in files, which are in use.
brazilianportuguese.LegacyRemoveFailed=Nao foi possivel remover a instalacao anterior do {#DisplayName} em %1.%nFeche o Autodesk Revit e execute o instalador novamente.
english.LegacyRemoveFailed=Could not remove the previous {#DisplayName} install in %1.%nClose Autodesk Revit and run Setup again.
brazilianportuguese.WriteFailed=Nao foi possivel gravar o arquivo PackageContents.xml do add-in. Execute o instalador novamente.
english.WriteFailed=Could not write the add-in's PackageContents.xml. Run Setup again.
brazilianportuguese.WaitForRevitPrompt=Feche o Revit para continuar a instalacao.
english.WaitForRevitPrompt=Close Revit to continue installation.
brazilianportuguese.FinishFailedHeading=A instalacao nao foi concluida
english.FinishFailedHeading=Setup did not finish
brazilianportuguese.FinishFailedText=O add-in nao foi configurado para o Revit. Execute o instalador novamente.
english.FinishFailedText=The add-in was not set up for Revit. Run Setup again.
brazilianportuguese.AfterText=Instalacao concluida!%n%nAbra o Autodesk Revit, clique na aba "Node.aec" e depois no botao "Hello World" do painel "{#DisplayName}".%n%nO comando verifica sua licenca localmente (sem rede) antes de executar.
english.AfterText=Installation finished!%n%nOpen Autodesk Revit, click the "Node.aec" tab and then the "Hello World" button in the "{#DisplayName}" panel.%n%nThe command verifies your license locally (no network call) before running.

; One payload per compatibility group, installed only when one of its years is
; checked. PackageContents.xml is not copied: [Code] writes it for the checked years.
[Files]
Source: "{#PayloadStage}\Contents\2023-2024\*"; DestDir: "{app}\Contents\2023-2024"; Flags: recursesubdirs createallsubdirs ignoreversion; Check: GroupSelected('2023-2024')
Source: "{#PayloadStage}\Contents\2025-2026\*"; DestDir: "{app}\Contents\2025-2026"; Flags: recursesubdirs createallsubdirs ignoreversion; Check: GroupSelected('2025-2026')
Source: "{#PayloadStage}\Contents\2027\*"; DestDir: "{app}\Contents\2027"; Flags: recursesubdirs createallsubdirs ignoreversion; Check: GroupSelected('2027')
Source: "{#PayloadStage}\README.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#PayloadStage}\NodeAec.product.json"; DestDir: "{app}"; Flags: ignoreversion
; Post-install notes per language (embedded; the InfoAfter page loads the one
; matching the wizard language).
Source: "installer-after.txt"; Flags: dontcopy
Source: "installer-after-en.txt"; Flags: dontcopy

[UninstallDelete]
Type: files; Name: "{app}\PackageContents.xml"
Type: filesandordirs; Name: "{app}\Contents"
Type: dirifempty; Name: "{app}"

[Code]
const
  FirstYear = 2023;
  LastYear = 2027;
  // Revit installation root. Revit's default layout is
  // "C:\Program Files\Autodesk\Revit <year>"; some deployments use
  // "C:\Program Files\Autodesk\Revit\<year>". Both are accepted.
  AutodeskRoot = 'C:\Program Files\Autodesk';
  UninstallRoot = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  LegacyNamePrefix = '{#DisplayName} - Revit';

var
  InstallFailed: Boolean;
  YearPage: TWizardPage;
  YearList: TNewCheckListBox;
  // Checked state per year, index 0 = FirstYear. Filled from the wizard page,
  // or from /RevitYears / the previous choice in silent installs.
  Selected: array of Boolean;
  // Set in InitializeWizard when a silent run has no usable year selection;
  // PrepareToInstall returns it so Setup aborts before touching any file.
  SilentError: string;

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
    Piece := Trim(Piece);
    if Piece <> '' then
    begin
      N := GetArrayLength(Items);
      SetArrayLength(Items, N + 1);
      Items[N] := Piece;
    end;
  end;
end;

function YearCount(): Integer;
begin
  Result := LastYear - FirstYear + 1;
end;

function YearText(Index: Integer): string;
begin
  Result := IntToStr(FirstYear + Index);
end;

// Compatibility group whose build loads in the given Revit year.
function GroupOfYear(Index: Integer): string;
var
  Year: Integer;
begin
  Year := FirstYear + Index;
  if Year <= 2024 then
    Result := '2023-2024'
  else if Year <= 2026 then
    Result := '2025-2026'
  else
    Result := '2027';
end;

// True when Revit of the given year is installed: default folders or the
// Autodesk registry keys (so a non-default install folder is still found).
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

// Fills Selected from a comma-separated year list. Returns '' or the invalid entries.
function SelectFromCsv(const Csv: string): string;
var
  Items: TArrayOfString;
  I, Year: Integer;
begin
  Result := '';
  for I := 0 to YearCount() - 1 do
    Selected[I] := False;
  SplitText(Csv, ',', Items);
  for I := 0 to GetArrayLength(Items) - 1 do
  begin
    Year := StrToIntDef(Items[I], 0);
    if (Year >= FirstYear) and (Year <= LastYear) then
      Selected[Year - FirstYear] := True
    else
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Items[I];
    end;
  end;
end;

// Default choice: the years saved by the previous install, or every installed year.
procedure SelectDefaults();
var
  Previous: string;
  I: Integer;
begin
  Previous := GetPreviousData('RevitYears', '');
  if Previous <> '' then
    SelectFromCsv(Previous)
  else
    for I := 0 to YearCount() - 1 do
      Selected[I] := IsRevitYearInstalled(YearText(I));
end;

function AnySelected(): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to YearCount() - 1 do
    if Selected[I] then
      Result := True;
end;

function SelectedCsv(): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to YearCount() - 1 do
    if Selected[I] then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + YearText(I);
    end;
end;

// [Files] Check: copy a group's build only when one of its years is checked.
function GroupSelected(const Group: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to YearCount() - 1 do
    if Selected[I] and (GroupOfYear(I) = Group) then
      Result := True;
end;

// Uninstall entries left by the per-group installers.
procedure LegacyUninstallKeys(const RootKey: Integer; var Keys: TArrayOfString);
var
  Names: TArrayOfString;
  DisplayName: string;
  I, N: Integer;
begin
  SetArrayLength(Keys, 0);
  if not RegGetSubkeyNames(RootKey, UninstallRoot, Names) then
    Exit;
  for I := 0 to GetArrayLength(Names) - 1 do
    if RegQueryStringValue(RootKey, UninstallRoot + '\' + Names[I], 'DisplayName', DisplayName) and
       (Pos(LegacyNamePrefix, DisplayName) = 1) then
    begin
      N := GetArrayLength(Keys);
      SetArrayLength(Keys, N + 1);
      Keys[N] := UninstallRoot + '\' + Names[I];
    end;
end;

function LegacyAddinExists(): Boolean;
var
  I: Integer;
  Base: string;
begin
  Result := False;
  for I := 0 to YearCount() - 1 do
  begin
    Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\') + YearText(I);
    if FileExists(Base + '\{#PluginName}.addin') or DirExists(Base + '\{#PluginName}') then
      Result := True;
  end;
end;

function LegacyInstallExists(): Boolean;
var
  Keys64, Keys32: TArrayOfString;
begin
  LegacyUninstallKeys(HKLM64, Keys64);
  LegacyUninstallKeys(HKLM32, Keys32);
  Result := (GetArrayLength(Keys64) > 0) or (GetArrayLength(Keys32) > 0) or LegacyAddinExists();
end;

// Runs each legacy uninstaller silently. Inno uninstallers relaunch themselves
// from a temp copy and return at once, so wait until the entry disappears.
procedure RunLegacyUninstallers(const RootKey: Integer);
var
  Keys: TArrayOfString;
  Command: string;
  I, Waited, ExecCode: Integer;
begin
  LegacyUninstallKeys(RootKey, Keys);
  for I := 0 to GetArrayLength(Keys) - 1 do
    if RegQueryStringValue(RootKey, Keys[I], 'UninstallString', Command) then
    begin
      Command := RemoveQuotes(Trim(Command));
      // An entry whose uninstaller is gone can only fail when clicked in Apps.
      if not FileExists(Command) then
      begin
        Log('Deleting orphan legacy entry (uninstaller missing): ' + Keys[I]);
        RegDeleteKeyIncludingSubkeys(RootKey, Keys[I]);
        Continue;
      end;
      Log('Removing legacy install: ' + Keys[I]);
      if Exec(Command, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ExecCode) then
      begin
        Waited := 0;
        while RegKeyExists(RootKey, Keys[I]) and (Waited < 60000) do
        begin
          Sleep(500);
          Waited := Waited + 500;
        end;
      end;
    end;
end;

// Removes everything the per-group installers left: their uninstall entries and,
// as a safety net, the per-year payloads. Returns '' or the folder that failed.
function RemoveLegacyInstalls(): string;
var
  I: Integer;
  Base: string;
begin
  Result := '';
  RunLegacyUninstallers(HKLM64);
  RunLegacyUninstallers(HKLM32);
  for I := 0 to YearCount() - 1 do
  begin
    Base := ExpandConstant('{commonappdata}\Autodesk\Revit\Addins\') + YearText(I);
    if DirExists(Base + '\{#PluginName}') then
      DelTree(Base + '\{#PluginName}', True, True, True);
    if FileExists(Base + '\{#PluginName}.addin') then
      DeleteFile(Base + '\{#PluginName}.addin');
    if FileExists(Base + '\{#PluginName}.addin') or DirExists(Base + '\{#PluginName}') then
      Result := Base;
  end;
end;

// True when a process with the given image name is running (WMI lookup).
// A lookup failure counts as "not running"; a locked file still fails the copy.
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

// PackageContents.xml for the checked years: one component per year, pointing
// at the build of that year's compatibility group.
function PackageContentsXml(): string;
var
  I: Integer;
  Year, Group: string;
begin
  Result :=
    '<?xml version="1.0" encoding="utf-8"?>' + #13#10 +
    '<ApplicationPackage SchemaVersion="1.0" AutodeskProduct="Revit" ProductType="Application" Name="{#DisplayName}" AppVersion="{#AppVersion}" Description="{#DisplayName} for Autodesk Revit" Author="Node.aec" ProductCode="{#ProductCode}" UpgradeCodes="{#UpgradeCode}" OnlineDocumentation="https://nodeaec.com.br">' + #13#10 +
    '  <CompanyDetails Name="Node.aec" Url="https://nodeaec.com.br" />' + #13#10;
  for I := 0 to YearCount() - 1 do
    if Selected[I] then
    begin
      Year := YearText(I);
      Group := GroupOfYear(I);
      Result := Result +
        '  <Components Description="Revit ' + Year + '">' + #13#10 +
        '    <RuntimeRequirements OS="Win64" Platform="Revit" SeriesMin="R' + Year + '" SeriesMax="R' + Year + '" />' + #13#10 +
        '    <ComponentEntry AppName="{#DisplayName}" Version="{#AppVersion}" ModuleName="./Contents/' + Group + '/{#PluginName}.addin" AppDescription="{#DisplayName} for Revit ' + Year + '" />' + #13#10 +
        '  </Components>' + #13#10;
    end;
  Result := Result + '</ApplicationPackage>' + #13#10;
end;

// Resolves the year selection (previous choice, installed years, /RevitYears)
// and adds the year page: one checkbox per Revit year, installed ones marked.
// Runs in silent installs too, so the selection logic lives here.
procedure InitializeWizard();
var
  I: Integer;
  State, Bad: string;
  Hint: TNewStaticText;
begin
  SetArrayLength(Selected, YearCount());
  SelectDefaults();
  SilentError := '';
  if WizardSilent() then
  begin
    if ExpandConstant('{param:RevitYears|}') <> '' then
    begin
      Bad := SelectFromCsv(ExpandConstant('{param:RevitYears|}'));
      if Bad <> '' then
        SilentError := FmtMessage(CustomMessage('SilentBadYears'), [Bad]);
    end;
    if (SilentError = '') and not AnySelected() then
      SilentError := CustomMessage('SilentNoYears');
  end;

  YearPage := CreateCustomPage(wpSelectTasks, CustomMessage('YearPageCaption'), CustomMessage('YearPageDesc'));

  YearList := TNewCheckListBox.Create(YearPage);
  YearList.Parent := YearPage.Surface;
  YearList.Left := 0;
  YearList.Top := 0;
  YearList.Width := YearPage.SurfaceWidth;
  YearList.Height := ScaleY(130);
  for I := 0 to YearCount() - 1 do
  begin
    if IsRevitYearInstalled(YearText(I)) then
      State := CustomMessage('YearInstalled')
    else
      State := CustomMessage('YearNotInstalled');
    YearList.AddCheckBox('Autodesk Revit ' + YearText(I), State, 0, Selected[I], True, False, False, nil);
  end;

  Hint := TNewStaticText.Create(YearPage);
  Hint.Parent := YearPage.Surface;
  Hint.Left := 0;
  Hint.Top := YearList.Top + YearList.Height + ScaleY(8);
  Hint.Width := YearPage.SurfaceWidth;
  Hint.AutoSize := False;
  Hint.WordWrap := True;
  Hint.Height := ScaleY(60);
  Hint.Caption := CustomMessage('YearPageHint');
  if LegacyInstallExists() then
    Hint.Caption := Hint.Caption + #13#10#13#10 + CustomMessage('LegacyFound');
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  InstallFailed := False;
end;

// Reads the checkboxes and refuses to leave the page with nothing checked.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if (YearPage = nil) or (CurPageID <> YearPage.ID) then
    Exit;
  for I := 0 to YearCount() - 1 do
    Selected[I] := YearList.Checked[I];
  // Silent runs also "click" Next; their selection was validated in
  // InitializeWizard, and a message box would block with no user.
  if (not AnySelected()) and (not WizardSilent()) then
  begin
    MsgBox(CustomMessage('YearNoneChecked'), mbError, MB_OK);
    Result := False;
  end;
end;

var
  WaitingForRevit: Boolean;
  WaitForRevitCancelled: Boolean;

// While Setup waits for Revit, Cancel stops the wait (PrepareToInstall then reports that
// Revit must close) instead of asking to exit Setup. Elsewhere Cancel behaves as usual.
procedure CancelButtonClick(CurPageID: Integer; var Cancel, Confirm: Boolean);
begin
  if WaitingForRevit then
  begin
    WaitForRevitCancelled := True;
    Cancel := False;
    Confirm := False;
  end;
end;

// True when a switch with Name (e.g. 'WaitForRevit' for /WaitForRevit or -WaitForRevit) is passed.
function HasParam(const Name: string): Boolean;
var
  I: Integer;
  Param: string;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    Param := ParamStr(I);
    if (CompareText(Param, '/' + Name) = 0) or
       (CompareText(Param, '-' + Name) = 0) or
       (Pos(Uppercase('/' + Name + '='), Uppercase(Param)) = 1) or
       (Pos(Uppercase('-' + Name + '='), Uppercase(Param)) = 1) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

// Waits until Revit.exe exits (the Node.aec Connector starts updates with
// /SILENT /WaitForRevit while Revit is still open). /VERYSILENT waits with no UI;
// otherwise a progress page shows the wait prompt. False when the user cancels.
function WaitForRevitToClose(): Boolean;
var
  ProgressPage: TOutputMarqueeProgressWizardPage;
  I: Integer;
begin
  Result := True;
  WaitForRevitCancelled := False;

  if HasParam('VERYSILENT') then
  begin
    while IsProcessRunning('Revit.exe') do
      Sleep(1000);
    Exit;
  end;

  ProgressPage := CreateOutputMarqueeProgressPage(SetupMessage(msgSetupAppTitle), CustomMessage('WaitForRevitPrompt'));
  ProgressPage.SetText(CustomMessage('WaitForRevitPrompt'), '');
  ProgressPage.Show();
  WaitingForRevit := True;
  WizardForm.CancelButton.Enabled := True;
  try
    while IsProcessRunning('Revit.exe') do
    begin
      ProgressPage.Animate();
      for I := 1 to 10 do
      begin
        if WaitForRevitCancelled then
        begin
          Result := False;
          Exit;
        end;
        Sleep(100);
        ProgressPage.Animate();
      end;
    end;
  finally
    WaitingForRevit := False;
    ProgressPage.Hide();
  end;
end;

// Runs before any file is copied: Revit must be closed, and the legacy
// per-group installs are removed so Revit never loads the plugin twice.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Failed: string;
begin
  NeedsRestart := False;
  Result := SilentError;
  if Result <> '' then
    Exit;
  if IsProcessRunning('Revit.exe') then
  begin
    if (not HasParam('WaitForRevit')) or (not WaitForRevitToClose()) then
    begin
      Result := CustomMessage('RevitMustClose');
      Exit;
    end;
  end;
  Failed := RemoveLegacyInstalls();
  if Failed <> '' then
    Result := FmtMessage(CustomMessage('LegacyRemoveFailed'), [Failed]);
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(PreviousDataKey, 'RevitYears', SelectedCsv());
end;

// Silent runs must not read a failed setup as success.
function GetCustomSetupExitCode: Integer;
begin
  if InstallFailed then
    Result := 1
  else
    Result := 0;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpInfoAfter) and InstallFailed;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  App: string;
begin
  if CurStep <> ssPostInstall then
    Exit;
  App := ExpandConstant('{app}');
  // A re-run can uncheck every year of a group: drop that group's build.
  if not GroupSelected('2023-2024') then
    DelTree(App + '\Contents\2023-2024', True, True, True);
  if not GroupSelected('2025-2026') then
    DelTree(App + '\Contents\2025-2026', True, True, True);
  if not GroupSelected('2027') then
    DelTree(App + '\Contents\2027', True, True, True);
  if not SaveStringToFile(App + '\PackageContents.xml', PackageContentsXml(), False) then
  begin
    // No RaiseException: it would not roll back and Setup would still show the
    // success page. Flag the failure; the Finished page reports it.
    InstallFailed := True;
    if WizardSilent() then
      Log('Could not write PackageContents.xml.')
    else
      MsgBox(CustomMessage('WriteFailed'), mbError, MB_OK);
  end;
end;

// The Finished page reports a failure; the InfoAfter page shows the note in the
// wizard language.
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

// Refuses to uninstall while Revit holds the add-in DLLs. Silent runs have no
// user, so they only fail (exit code) instead of showing a message.
function InitializeUninstall(): Boolean;
begin
  Result := not IsProcessRunning('Revit.exe');
  if (not Result) and (not UninstallSilent()) then
    MsgBox(CustomMessage('RevitMustCloseUninstall'), mbError, MB_OK);
end;
