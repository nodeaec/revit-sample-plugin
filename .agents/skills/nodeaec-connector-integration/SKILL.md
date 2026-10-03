---
name: nodeaec-connector-integration
description: >-
  Implement Node.aec licensing in a new Revit plugin: scaffold with
  dotnet new nodeaec-revit-plugin, keep the NodeAec.Licensing.Lite
  PackageReference, set the product slug, gate every IExternalCommand through
  NodeAecLicenseGate.Validate() (fail-closed seam over Lite Gate), and package
  with the .addin layout on the shared Node.aec ribbon tab. Use when a task
  mentions Node.aec, nodeaec, NodeAecLicenseGate, Gate/Snapshot, product slug
  or entitlement gating, partner-plugin licensing, "license-gate this Revit
  command", or scaffolding a licensed Revit plugin. Not for editing the
  connector Hub itself or for cloud/HTTP license APIs.
---

# Node.aec connector integration

New-plugin path: scaffold from the template, set the slug, gate every command.
Worked example: this repository's `src/SamplePlugin/` (canonical names:
`SamplePlugin.Commands.HelloCommand`, `NodeAecLicenseGate`) — the template's
output for `-n SamplePlugin -p ProductSlug=revit-sample-plugin`. Deep detail
lives in [`references/`](references/) — read them when a step says so.

## 1. When to use

Any task that makes a Revit add-in depend on a Node.aec entitlement: scaffolding
a new licensed plugin, adding one more gated command, or porting the sample's
seam into another plugin. Skip it only for plugins that ship no licensed
functionality.

Migrating an existing STANDALONE plugin (no Node.aec integration yet) to Lite
for the first time follows this same workflow, except Step 1 becomes
"inventory every billable `IExternalCommand.Execute`" instead of scaffolding —
full trail in API.md §13 *Migrating an existing plugin to Lite*.

## 2. Prerequisites

- **.NET 8 SDK** (minimum) — builds every Revit year from the same machine.
  No Hub install is needed to compile: the Lite package restores from its feed
  (pre-release: the local folder in `NuGet.config`; at release: NuGet.org).
- **Product slug registered and entitled** on the platform (this sample: the
  constant `ProductSlug = "revit-sample-plugin"` — [product page](https://nodeaec.com.br/products/revit-sample-plugin) — the single constant you change; set it at scaffold time).
- **Supported Revit years**: 2023–2027 via `-p:RevitYear=<year>` (default 2026)
  → `net48` / `net8.0-windows` / `net10.0-windows`.
- **Node.aec Connector Hub installed and signed in** (or a license key
  activated) on the test machine — needed only for the *licensed* test run.
  The gate reads the local lease the Hub syncs; it never logs in for you.

## 3. Integration workflow

1. **Scaffold from the template.** One command produces a working project
   with no manual wiring:

   ```bash
   dotnet new install NodeAec.Templates.RevitPlugin   # once per machine
   dotnet new nodeaec-revit-plugin -n MyPlugin -p ProductSlug=my-plugin
   ```

   You get `App.cs` (shared-tab ribbon, zero licensing calls),
   `Commands/HelloCommand.cs` (gate-first command), `Licensing/NodeAecLicenseGate.cs`
   (the seam), a relative-`<Assembly>` `.addin` manifest, a `RevitYear`-matrix
   csproj with the Lite `PackageReference`, and `scripts/release.ps1` per group.
   *Decision point:* never start from an empty csproj and hand-wire licensing.

2. **Confirm the slug.** It was set at scaffold time; verify
   `NodeAecLicenseGate.ProductSlug` matches your catalog slug exactly
   (matching is trim + case-insensitive). This is the **one** constant you change.
   Code details: [`references/licensing-seam.md`](references/licensing-seam.md).

3. **Keep the package reference, never a DLL reference** (API.md §3 *The
   integration path (authoritative)*). The scaffold already declares exactly one
   `<PackageReference Include="NodeAec.Licensing.Lite" Version="1.0.0-preview.1">`
   — resolved from NuGet, compiled into your plugin. Never add a `Reference` +
   `HintPath` to an installed connector DLL, never a `ProjectReference`,
   **never copy a connector DLL next to your plugin**. Ship your `.addin` at the
   `Addins\<year>` **root** with relative `<Assembly>MyPlugin\MyPlugin.dll</Assembly>`
   pointing into your payload subfolder (the Lite assembly travels inside it).

4. **Inventory every command that must be gated.** List all `IExternalCommand`
   classes (and any other entry point that runs licensed work).
   *Decision point:* gate every user-facing command; the only
   exception is an entry point whose sole job is license recovery (for example, a button that
   only opens the connector). Ungated commands are a release blocker, not a TODO.

5. **Call the gate at entry of EVERY command, fail-closed.** First statement of
   `Execute`: `var gate = NodeAecLicenseGate.Validate();` then branch **only**
   on `gate.IsLicensed`. No work, no dialog, no transaction before the gate;
   any exception or null state ⇒ fail closed. Call it once per execution, never
   inside per-element loops (API.md §7 *Threading & Revit API-context rules*).
   Build the licensed UX from the real fields: `Snapshot` exposes exactly
   `IsLicensed`, `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`,
   `Message` — payload fields are `null` on failure. Render them with
   `NodeAecLicenseGate.BuildLicenseBlock(gate)` (treat `ExpiresAt == null` as
   "no expiry recorded (perpetual)", never as expired). Failure UX: show the
   gate's `Message` **verbatim** + short English guidance bullets (sign in /
   renew / buy your slug / no credentials / seat limit / offline grace) + an
   `Open Node.aec Connector...` command link calling
   `NodeAecLicenseGate.OpenConnector()` on click, then `Result.Cancelled`.
   Never translate, string-match, or branch on `Message` — `IsLicensed` is the
   only branch point (API.md §5 *Status / reason taxonomy*).

6. **Ribbon placement under the shared `Node.aec` tab** (API.md §6 *Ribbon
   integration conventions*): the scaffold already adds your own panel with your
   button inside the shared `Node.aec` tab — never create a plugin-owned tab.
   Recommended pattern = local idempotent dedup replica +
   AdWindows hooks (`ApplicationInitialized`, `UIElementActivated`, `-=` before
   `+=`), exactly as `App.cs`. The Hub's public
   `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` are OPTIONAL helpers with
   a runtime tradeoff (they load the Hub assembly into your process at
   ribbon time).

7. **Build the matrix, then deploy per year.** No Hub install needed to compile:

   ```bash
   dotnet build -p:RevitYear=2023   # net48
   dotnet build -p:RevitYear=2026   # net8.0-windows (default)
   dotnet build -p:RevitYear=2027   # net10.0-windows
   ```

   Deploy the `.addin` + payload subfolder to
   `%ProgramData%\Autodesk\Revit\Addins\<year>\`, or ship the per-group
   installer from `scripts/release.ps1`.

8. **Validation checklist.** No automated suite exists (Revit + DPAPI need a real
   session), so build the matrix above, then run in a real Revit session:
    - [ ] Valid license (Hub installed, signed in, entitled) → licensed greeting with `BuildLicenseBlock` fields, `Result.Succeeded`
    - [ ] No credentials / Hub absent → blocked dialog with the gate `Message` verbatim (`Nenhuma credencial…`), no crash, `Result.Cancelled` (no separate "Hub missing" state — Lite always runs)
    - [ ] Not signed in / no entitlement / expired → blocked dialog, gate `Message` verbatim, `Result.Cancelled`
    - [ ] Add-in reloaded twice → still one `Node.aec` tab, one button
    - [ ] `release`/`stage` contain neither `RevitAPI*.dll` nor `NodeAec.Connector.dll` (`ProtectedData.dll` only in `net48` payloads)
    - [ ] Docs still accurate: every `Source:` file/line link points at the intended
      lines (re-anchor any link whose target moved)

    Setups and expected texts per case: [`references/validation.md`](references/validation.md).

## 4. Common pitfalls

| Pitfall | Why it hurts | Do this instead |
|---|---|---|
| Hand-wiring licensing into an empty project | Missed seam rules, wrong reference, divergent crypto | Scaffold step 1; the template did the wiring |
| Referencing an installed connector DLL (`Reference` + `HintPath`) | Swappable external DLL, build needs the Hub — a retired historical path, never the migration source | Keep the Lite `PackageReference`; it compiles into your plugin |
| Copying any connector DLL next to your plugin | Version skew, stale copies, fights the `never copy` rule family | Nothing to copy: Lite travels inside your payload automatically |
| Creating your own ribbon tab | Two tabs fragment the ecosystem; the shared tab is canonical | Your panel inside the shared `Node.aec` tab |
| Gating only some commands | Ungated path = free feature; fails review | Step 4 inventory; gate every command at entry |
| Swallowing exceptions into "licensed" | Turns any error into a free pass — fail-open | Catch → not-licensed snapshot → `Result.Cancelled` |
| Inventing `Snapshot` fields (seats, plan, licensee, slug, status, Hub-available flag) | They do not exist; the code will not compile | Only the six real members; `IsLicensed` branches |
| Calling Node.aec HTTP APIs directly | Hub-internal, breaks the responsibility split | Only `NodeAecLicenseGate.Validate()` / `OpenConnector()` |

## 5. Adapt-to-your-plugin mapping

| Sample (this repo) | Your plugin |
|---|---|
| `ProductSlug = "revit-sample-plugin"` | Your registered catalog slug — the **one** constant to change (set via `-p ProductSlug=` at scaffold) |
| Namespace `SamplePlugin.*` / assembly `SamplePlugin` | Your `-n` name (root namespace / assembly name) |
| Panel `Sample Plugin` | Your panel name inside the shared `Node.aec` tab |
| Button `Hello World`, id `SamplePlugin_HelloWorld` | Your button text and unique id |
| Command `SamplePlugin.Commands.HelloCommand` | Your gated command classes (all of them) |
| Manifest `SamplePlugin.addin`, `<AddInId>` GUID | Your manifest name and fresh GUID (scaffold generates one; never reuse another add-in's) |
| `App` (`SamplePlugin.App`) | Your `IExternalApplication` full class name |

## 6. Where to go next

- [`API.md`](../../../API.md) — §2 *Quickstart (happy path)*, §3 *The
  integration path (authoritative)*, §5 *Status / reason taxonomy*, §6 *Ribbon
  integration conventions*, §7 *Threading & Revit API-context rules*, §9
  *Fail-closed recipe (`NodeAecLicenseGate.cs`)*, §10 *Troubleshooting / FAQ*.
- [`README.md`](../../../README.md) · [`AGENTS.md`](../../../AGENTS.md) — repo
  orientation and agent rules for this sample.
- Worked source: <https://github.com/nodeaec/revit-sample-plugin> —
  `src/SamplePlugin/Licensing/NodeAecLicenseGate.cs`,
  `src/SamplePlugin/Commands/HelloCommand.cs`, `src/SamplePlugin/App.cs`,
  `src/SamplePlugin/SamplePlugin.csproj`, `src/SamplePlugin/SamplePlugin.addin`.
- Upstream connector (read-only, background only):
  <https://github.com/nodeaec/revit-connector> — owns the Hub (sign-in, lease
  sync, shared tab) and its own skills (`licensing-integrate`, `ribbon-guard`,
  `revit-build-validate`). Never edit it from this integration; this repo's
  `API.md` governs here.
