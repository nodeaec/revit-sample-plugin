---
name: licensing-integrate
description: >-
  Add Node.aec licensing to an Autodesk Revit add-in (Revit 2023-2027): start a
  new plugin from the dotnet new nodeaec-revit-plugin template, migrate an
  existing plugin to the NodeAec.Licensing.Lite gate, or learn the pattern from
  the Sample Plugin. Covers the product slug, gating every IExternalCommand with
  Gate.Validate(slug) (fail-closed, never throws), the blocked dialog, the shared
  Node.aec ribbon tab, the .bundle installer and the manual Revit checks. Use when
  a task mentions Node.aec, nodeaec, Gate/Snapshot/GateReason, a product slug,
  entitlement or license gating of a Revit command, or scaffolding a licensed
  Revit plugin. Not for editing the Node.aec Connector itself or calling Node.aec
  cloud APIs.
---

# Licensing integrate (Node.aec)

The canonical copy of this skill lives in
[revit-sample-plugin `.agents/skills/licensing-integrate/`](https://github.com/nodeaec/revit-sample-plugin/tree/main/.agents/skills/licensing-integrate).
Projects made from the `nodeaec-revit-plugin` template carry a copy; refresh it from there
when it looks outdated (§9 says how to tell).

Worked example for every step: the Sample Plugin
([`HelloCommand.cs`](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/Commands/HelloCommand.cs),
[`App.cs`](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs)).
Its comments explain why each piece is the way it is. Deep detail is in
[`references/`](references/): read a file when a step points to it.

## 0. Invariants (never ask the user about these)

1. **The Connector does the licensing work.** Sign-in, key activation, seats, lease sync and
   the account window belong to the Node.aec Connector, a separate add-in the end user
   installs once. The plugin implements no HTTP client, no login UI and no key handling.
2. **The plugin only asks, offline.** `Gate.Validate(slug)` from the `NodeAec.Licensing.Lite`
   NuGet package reads the signed lease the Connector wrote and decides locally. Never
   reference, copy or ship `NodeAec.Connector.dll`, never copy gate source code, and never
   make network calls in `OnStartup` or a command.
3. **Fail closed.** No code path runs the paid feature without `IsLicensed == true`.
4. **One shared Ribbon tab.** Every Node.aec plugin puts its own panel in the `Node.aec` tab
   and never creates a tab of its own.

## 1. Pick the path

| The user has… | Path | Do |
|---|---|---|
| No project yet | **A. New plugin** | §3, starting from the template |
| A plugin that already ships | **B. Existing plugin** | [`references/migration.md`](references/migration.md) |
| Only the Sample Plugin, to learn | **C. Learn from the sample** | §4 |

## 2. Ask before writing code

Ask these, each with the recommended answer, and wait for the user. Skip a question the
user or the code already answers.

1. **Product slug** registered on Node.aec (`https://nodeaec.com.br/products/<slug>`).
   It must match exactly (case-insensitive); a typo blocks every user with "product not
   found". If none is registered yet, agree on a kebab-case slug and say it must be
   registered before release.
2. **Revit years.** Recommended: 2023-2027, the template's matrix. An existing plugin keeps
   the years it ships today unless the user wants more.
3. **Panel name** inside the `Node.aec` tab, unique to the product (e.g. the product name).
   Not `Conector` (the Connector's) and not `License`/`Licensing` (the Connector removes
   those as legacy).
4. **Which commands are paid.** Recommended: every user-facing command. The only usual
   exception is a command whose sole job is license recovery (opening the Connector).
5. **Test machine.** Is the Connector installed with a signed-in, entitled account? Needed
   only for the licensed run; building and the blocked cases work without it.

## 3. Path A: new plugin from the template

1. **Scaffold** (never hand-wire licensing into an empty project):

   ```powershell
   dotnet new install NodeAec.Templates.RevitPlugin      # once per machine; --force to update
   dotnet new nodeaec-revit-plugin -n MyPlugin --ProductSlug my-plugin
   ```

   The project has `App.cs` (Ribbon, no licensing calls), `Commands/HelloCommand.cs` (the
   gate, holds `ProductSlug`), `MyPlugin.addin` (fresh `AddInId`), `MyPlugin.csproj`
   (Revit-year matrix + the Lite `PackageReference`), `scripts/release.ps1` +
   `installer.iss` (fresh `AppId`, `ProductCode`, `UpgradeCode`), `AGENTS.md` and this skill.
2. **Check the slug** in `HelloCommand.ProductSlug`. With several commands, move it to one
   shared static class.
3. **Name the panel**: `PanelName` in `App.cs` (`-n` gave it the project name).
4. **Add the real commands.** Copy `HelloCommand`'s first lines into each one and replace
   its body with the feature. Add one Ribbon button per command in `App.cs`
   (`AddButtonIfMissing`, a unique internal button name each). Gate rules: §5.
5. **Build** the years the user ships (§7), then **package** (§6) and **validate** (§7).

## 4. Path C: learn from the sample

1. Clone `https://github.com/nodeaec/revit-sample-plugin` and build it:
   `dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=<year>`.
2. Read the source in the README's order ("Reading the source"): `HelloCommand.cs`,
   `App.cs`, `SamplePlugin.addin`, `SamplePlugin.csproj`, then the scripts. Explain to the
   user what each part does and why, from the comments; do not invent reasons.
3. To run it: `scripts/release.ps1 -Version <csproj Version> -Install` (Revit closed), open
   Revit, click **Node.aec > Sample Plugin > Hello World**. Without a license for
   `revit-sample-plugin` the blocked dialog is the expected result, and the point of the demo.
4. To turn it into a real plugin, prefer Path A (fresh identity GUIDs). Copying the
   sample means renaming everything in the §8 mapping table by hand.

## 5. The gate in every paid command

Detail and the full code: [`references/licensing-gate.md`](references/licensing-gate.md).

- First statement of `Execute`: `Snapshot gate = Gate.Validate(ProductSlug);`. Nothing
  before it: no dialog, no transaction, no model access.
- Branch **only** on `gate.IsLicensed`. `gate.Reason` (`GateReason`) is for logs or a
  tailored UI, never for deciding whether to run. Never match message text.
- No `try/catch` around it: it never throws. A catch that let the command run is a free pass.
- Not licensed: show `gate.GetMessage(language)` as the whole dialog content, `language`
  from Revit's UI language, plus an `Open Node.aec Connector...` link that calls
  `Gate.OpenConnector()` on click, then `return Result.Cancelled;`. Never add a list of
  possible causes; the message already names the one reason and the next step.
- Once per execution. Never in `IExternalCommandAvailability`, a per-element loop or a
  `DynamicUpdater`: each call reads and verifies the lease file.
- `gate.LicenseKey` is the end user's secret: never show, log or send it.
- `ExpiresAt == null` means no end date, never "expired".

## 6. Ribbon and packaging

- **Ribbon** (as in `App.cs`): `CreateRibbonTab("Node.aec")` in a `try` that catches only
  the "already exists" `ArgumentException`; get-or-create the panel; add a button only when
  its internal name is missing; AdWindows dedup hooks with `-=` before `+=`. No licensing
  call in `App`.
- **csproj**: `<CopyLocalLockFileAssemblies>true</CopyLocalLockFileAssemblies>` so Lite and
  its dependencies sit next to the plugin DLL; `<UseWPF>true</UseWPF>`; Revit API packages
  with `PrivateAssets="all" ExcludeAssets="runtime"` (never copied).
- **Payload**: Lite + `BouncyCastle.Cryptography` always; `System.Text.Json` and
  `System.Security.Cryptography.ProtectedData` only in the net48 build. Never
  `RevitAPI*.dll`, `AdWindows.dll`, `UIFramework*` or `NodeAec.Connector.dll`.
- **Installer**: `scripts/release.ps1 -Version <x.y.z>` builds one `.bundle` for Revit
  2023-2027 and one Setup.exe with a checkbox per Revit year (needs Inno Setup 6). The
  version must equal the csproj `<Version>`. Keep `ProductCode`/`UpgradeCode` identical in
  `release.ps1` and `installer.iss` and never change them, or the `AppId`, between versions.
  An existing plugin can keep its own installer (see `references/migration.md`).

## 7. Build and validate

Build each compatibility group with its oldest year, the way `release.ps1` does:

```powershell
dotnet build -p:RevitYear=2023   # net48            (Revit 2023-2024)
dotnet build -p:RevitYear=2025   # net8.0-windows   (Revit 2025-2026)
dotnet build -p:RevitYear=2027   # net10.0-windows  (Revit 2027)
```

0 errors is required. Then run the manual Revit checks in
[`references/validation.md`](references/validation.md) (licensed, blocked, Connector absent,
reload twice). They cannot be automated: the lease storage (DPAPI) needs an interactive
Windows session. Report the cases the user still has to run instead of claiming them.

## 8. Mapping: sample names → your plugin

| Sample | Your plugin |
|---|---|
| `ProductSlug = "revit-sample-plugin"` | Your registered slug |
| Namespace and assembly `SamplePlugin` | Your project name |
| Panel `Sample Plugin` | Your panel name |
| Button `Hello World`, id `SamplePlugin_HelloWorld` | Your button text and a unique id |
| `SamplePlugin.Commands.HelloCommand` | Your gated command classes (all of them) |
| `<AddInId>` in `SamplePlugin.addin` | A fresh GUID; never reuse another add-in's |
| `AppId`, `ProductCode`, `UpgradeCode` in `scripts/` | Fresh GUIDs for your product |

## 9. Facts that go stale, and where to check them

Do not trust version numbers written in docs, this file included. Check the source:

| Fact | Source of truth |
|---|---|
| Latest Lite version | <https://www.nuget.org/packages/NodeAec.Licensing.Lite> |
| Lite version to build against | The one the current Connector ships, or older (Revit 2025+ loads one copy per session, the first): `PackageReference` in [revit-connector `src/NodeAec.Connector/NodeAec.Connector.csproj`](https://github.com/nodeaec/revit-connector/blob/main/src/NodeAec.Connector/NodeAec.Connector.csproj) |
| `Snapshot` members, `GateReason` values and messages | [licensing-lite README](https://github.com/nodeaec/licensing-lite#readme) and `src/NodeAec.Licensing.Lite/GateReason.cs` there |
| Latest template version | <https://www.nuget.org/packages/NodeAec.Templates.RevitPlugin> |
| Revit year → target framework, Revit API package versions | `RevitApiPkgVersion` / `TargetFramework` in the plugin csproj (the sample's is the reference) |
| Connector download | <https://nodeaec.com.br/products/nodeaec-connector> |

When a project's version changes, find every doc that repeats it before finishing:
`grep -rn "<old version>" --include=*.md .`
