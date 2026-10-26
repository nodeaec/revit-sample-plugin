# Path B: add Node.aec licensing to an existing plugin

Detail for SKILL.md §1, path B. The plugin already builds and ships; the goal is to gate
its paid commands with `NodeAec.Licensing.Lite` and change nothing else that works.
Ask the SKILL.md §2 questions first.

## 1. Inventory (read the code, report it, then ask)

Find and list for the user:

- **Projects and target frameworks.** Every `.csproj` that builds an add-in, its
  `TargetFramework(s)`, and which Revit years it ships for. Lite supports `net48`
  (Revit 2023/2024), `net8.0-windows` (2025/2026) and `net10.0-windows` (2027); NuGet picks
  the matching one, so a single-target project stays single-target.
- **Project format.** SDK-style (`<Project Sdk=...>`) or old-style with `packages.config`.
  Old-style: add the package through `packages.config` as usual (NuGet copies the DLLs to
  the output) or, if the user agrees, migrate to `PackageReference` first. Do not convert
  the project format without asking.
- **Commands.** Every `IExternalCommand` (and any other entry point that runs paid work:
  `IExternalEventHandler`, a modeless window's buttons, an `IUpdater`). Mark which are paid.
- **Ribbon.** Where tabs, panels and buttons are created (`IExternalApplication.OnStartup`).
- **Existing license check**, if any (a key prompt, a web call, a date check). Ask the user
  whether the Node.aec gate replaces it. Never leave two checks, and never let the old one
  allow what the gate denies.
- **Installer.** How the plugin ships today (`.addin` per year, a `.bundle`, an MSI, an Inno
  or WiX script, a zip) and whether it lists files one by one.

## 2. Add the package

```powershell
dotnet add <Project>.csproj package NodeAec.Licensing.Lite
```

Use the Lite version the current Connector ships, or an older one (SKILL.md §9 says where
to look). In SDK-style projects also set, in the add-in project:

```xml
<CopyLocalLockFileAssemblies>true</CopyLocalLockFileAssemblies>  <!-- Lite + deps next to the DLL -->
<UseWPF>true</UseWPF>  <!-- most add-ins have it; keeps ProtectedData.dll out of net8/net10 output -->
```

Build every target once and check the output folder has `NodeAec.Licensing.Lite.dll` and
`BouncyCastle.Cryptography.dll` (net48 also `System.Text.Json.dll` and
`System.Security.Cryptography.ProtectedData.dll`).

## 3. The slug and the gate

Add one constant the commands share:

```csharp
namespace MyPlugin;

internal static class Licensing
{
    /// <summary>Product slug registered on Node.aec; the gate looks for it in the lease.</summary>
    public const string ProductSlug = "my-plugin";
}
```

Gate each paid command. The feature code moves below the gate unchanged:

```csharp
// BEFORE
public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
{
    RunFeature(commandData);
    return Result.Succeeded;
}

// AFTER
public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
{
    Snapshot gate = Gate.Validate(Licensing.ProductSlug); // first statement, never throws
    if (!gate.IsLicensed)
    {
        ShowBlockedDialog(gate.GetMessage(UserLanguage(commandData)));
        return Result.Cancelled;
    }

    RunFeature(commandData);
    return Result.Succeeded;
}
```

Copy `UserLanguage` and `ShowBlockedDialog` from the sample's
[`HelloCommand.cs`](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/Commands/HelloCommand.cs)
into one shared helper class (adapt the titles and the product name). Rules: SKILL.md §5.

Entry points that are not commands (a modeless window, an `ExternalEvent` handler) call the
gate at the point where paid work starts, on Revit's UI thread, with the same dialog.
`Gate.OpenConnector()` opens a WPF window, so it also needs the UI thread.

## 4. Ribbon: move into the `Node.aec` tab

- Replace `CreateRibbonTab("<OldTab>")` with the shared-tab code from the sample's
  [`App.cs`](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs)
  (`EnsureTab`, `GetOrCreatePanel`, `AddButtonIfMissing`, the dedup hooks).
- Keep the existing buttons; they move into the `Node.aec` tab, in one panel per plugin
  (internal name unique to the product) titled with the company name, so all of the
  company's plugins share one group. Rename button internal names to `<Plugin>_<Command>`. Tell the user their users will find the buttons in the new
  tab (worth a line in the release notes).
- `App` gets no licensing call. Buttons stay enabled; the gate runs on click.

## 5. Packaging

Two options; ask which one:

- **Keep the current installer.** The gate works from any install location. Add the new
  DLLs from step 2 to the payload if the installer lists files one by one, and check no
  `RevitAPI*.dll` or `NodeAec.Connector.dll` ships.
- **Switch to the Node.aec bundle installer.** Copy `scripts/release.ps1`, `installer.iss`
  and `installer-after*.txt` from the sample, rename (`PluginName`, `DisplayName`,
  description, product URL) and give it fresh `ProductCode`/`UpgradeCode` GUIDs. Keep the
  plugin's existing installer `AppId` if it already has one, so the new Setup takes over
  the old Windows Apps entry; the old per-year files must then be removed by the new
  Setup (the sample's `RemoveLegacyInstalls` shows how) or Revit loads the plugin twice.

End users also need the Node.aec Connector: say so in the release notes and the product
page. The plugin's installer does not have to include it.

## 6. Validate

- Build every target the plugin ships with 0 errors.
- Check the payload (step 2 and 5).
- Run the manual checks in [`validation.md`](validation.md) on every paid command, not only one.
- Report to the user: files changed, commands gated (and any left ungated on purpose, with
  the reason), and the manual checks they still have to run in Revit.
