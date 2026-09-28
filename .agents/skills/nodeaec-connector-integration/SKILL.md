---
name: nodeaec-connector-integration
description: >-
  Implement the Node.aec (nodeaec) Connector licensing integration in a Revit
  plugin: gate every IExternalCommand through NodeAecLicenseGate.Validate()
  (fail-closed seam over NodeAecGate), add the NodeAec.Connector build reference
  and .addin packaging, and place buttons on the shared Node.aec ribbon tab.
  Use when a task mentions Node.aec, nodeaec, NodeAec.Connector, NodeAecGate,
  NodeAecLicenseGate, GateResult/GateSnapshot, product slug or entitlement
  gating, partner-plugin licensing, "license-gate this Revit command", or
  integrating a third-party plugin with the Node.aec platform. Not for editing
  the connector itself or for cloud/HTTP license APIs.
---

# Node.aec connector integration

Worked example: this repository's `src/SamplePlugin/` (canonical names:
`SamplePlugin.Commands.HelloCommand`, `NodeAecLicenseGate`). Deep detail lives in
[`references/`](references/) — read them when a step says so.

## 1. When to use

Any task that makes a Revit add-in depend on a Node.aec entitlement: first-time
integration, adding one more gated command, or porting the sample's seam into
another plugin. Skip it only for plugins that ship no licensed functionality.

## 2. Prerequisites

- **Node.aec Connector installed** for the target Revit year and **signed in**
  (or a license key activated) on the test machine — the gate reads the local
  lease the connector syncs; it never logs in for you.
- **Product slug registered and entitled** on the platform (this sample: the
  constant `ProductSlug = "revit-sample-plugin"` — [product page](https://nodeaec.com.br/products/revit-sample-plugin) — the single constant you change).
- **Supported Revit years**: 2023–2027 via `-p:RevitYear=<year>` (default 2026)
  → `net48` / `net8.0-windows` / `net10.0-windows`. Connector DLL expected at
  `%ProgramData%\Autodesk\Revit\Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll`.

## 3. Integration workflow

1. **Inventory every command that must be gated.** List all `IExternalCommand`
   classes (and any other entry point that runs licensed work).
   *Decision point:* gate every user-facing command; the only defensible
   exception is plumbing whose sole job is license recovery (e.g. a button that
   only opens the connector). Ungated commands are a release blocker, not a
   TODO.

2. **Add the build reference per the packaging contract** (API.md §3 *The
   integration path (authoritative)*). Exactly one `<Reference
   Include="NodeAec.Connector">` with `HintPath`
   `$(ProgramData)\Autodesk\Revit\Addins\$(RevitYear)\NodeAec.Connector\NodeAec.Connector.dll`
   and `<Private>False</Private>` — never NuGet, never a `ProjectReference`,
   **never copy `NodeAec.Connector.dll` next to your plugin**. Ship
   `SamplePlugin.addin` at the `Addins\<year>` **root** with relative
   `<Assembly>SamplePlugin\SamplePlugin.dll</Assembly>` pointing into your
   payload subfolder. *Decision point:* build machine without the connector →
   pass `-p:NodeAecConnectorDll=<path>` to the DLL; do not vendor a copy.

3. **Create the licensing seam** by porting
   `src/SamplePlugin/Licensing/NodeAecLicenseGate.cs`: `Validate()` returning a
   plugin-local `GateSnapshot` (never throws), a JIT-isolation wrapper
   (`RunValidation()`) so a missing connector becomes a fail-closed snapshot,
   `OpenConnector()` behind its own wrapper, and `BuildLicenseBlock(GateSnapshot)`.
   Change `ProductSlug` to your registered slug; keep every `NodeAec.Connector`
   type inside this one file. *Decision point:* no connector type may appear in
   a command signature — that would crash JIT when the connector is absent.
   Code details: [`references/licensing-seam.md`](references/licensing-seam.md).

4. **Call the gate at entry of EVERY command, fail-closed.** First statement of
   `Execute`: `var gate = NodeAecLicenseGate.Validate();` then branch **only**
   on `gate.IsLicensed`. No work, no dialog, no transaction before the gate;
   any exception or null state ⇒ fail closed. Call it once per execution, never
   inside per-element loops (API.md §7 *Threading & Revit API-context rules*).

5. **Build the licensed UX from the real fields.** `GateResult` exposes exactly
   `IsLicensed`, `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`,
   `Message` — payload fields are `null` on failure. Render them with
   `NodeAecLicenseGate.BuildLicenseBlock(gate)` (treat `ExpiresAt == null` as
   "no expiry recorded (perpetual)", never as expired).

6. **Failure UX, verbatim and fail-closed.** Show the connector's `Message`
   **verbatim** + short English guidance bullets (sign in / renew / buy your
   slug / connector missing / seat limit / offline grace) + an
   `Open Node.aec Connector...` command link calling
   `NodeAecLicenseGate.OpenConnector()` on click, then `Result.Cancelled`.
   Never translate, string-match, or branch on `Message` — `IsLicensed` is the
   only branch point (API.md §5 *Status / reason taxonomy*).

7. **Ribbon placement under the shared `Node.aec` tab** (API.md §6 *Ribbon
   integration conventions*): add your own panel (`Sample Plugin`) with your
   button (`Hello World`) inside the shared `Node.aec` tab — never create a
   plugin-owned tab. Recommended pattern = local idempotent dedup replica +
   AdWindows hooks (`ApplicationInitialized`, `UIElementActivated`, `-=` before
   `+=`), exactly as `src/SamplePlugin/App.cs`. The connector's public
   `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` are OPTIONAL helpers with
   a JIT-load tradeoff (they pull `NodeAec.Connector` into your process at
   ribbon time).

8. **Validation checklist.** No automated suite exists (Revit + DPAPI need a real
   session), so build the matrix (`-p:RevitYear=2023` … `2027`, default 2026),
   then run in a real Revit session:
   - [ ] Valid license → licensed greeting with `BuildLicenseBlock` fields, `Result.Succeeded`
   - [ ] No connector → blocked dialog + `ConnectorUnavailableMessage`, no crash, `Result.Cancelled`
   - [ ] Not signed in / no entitlement / expired → blocked dialog, connector `Message` verbatim, `Result.Cancelled`
   - [ ] Add-in reloaded twice → still one `Node.aec` tab, one `Hello World` button
   - [ ] `release`/`stage` contain neither `RevitAPI*.dll` nor `NodeAec.Connector.dll`

   Setups and expected texts per case: [`references/validation.md`](references/validation.md).

## 4. Common pitfalls

| Pitfall | Why it hurts | Do this instead |
|---|---|---|
| Copying `NodeAec.Connector.dll` next to your plugin | Version skew, stale copies, fights the `never copy` rule family | `<Private>False</Private>`; let Revit load the connector from its own folder |
| Creating your own ribbon tab | Two tabs fragment the ecosystem; the shared tab is canonical | Panel `Sample Plugin` inside the shared `Node.aec` tab |
| Gating only some commands | Ungated path = free feature; fails review | Step 1 inventory; gate every command at entry |
| Swallowing exceptions into "licensed" | Turns any error into a free pass — fail-open | Catch → not-licensed snapshot → `Result.Cancelled` |
| Inventing `GateResult` fields (seats, plan, licensee, slug, status) | They do not exist; code won't compile | Only the six real members; `IsLicensed` branches |
| Calling Node.aec HTTP APIs directly | Hub-internal, breaks the responsibility split | Only `NodeAecLicenseGate.Validate()` / `OpenConnector()` |

## 5. Adapt-to-your-plugin mapping

| Sample (this repo) | Your plugin |
|---|---|
| `ProductSlug = "sample-plugin"` | Your registered catalog slug — the **one** constant to change |
| Namespace `SamplePlugin.*` / assembly `SamplePlugin` | Your root namespace / assembly name |
| Panel `Sample Plugin` | Your panel name inside the shared `Node.aec` tab |
| Button `Hello World`, id `SamplePlugin_HelloWorld` | Your button text and unique id |
| Command `SamplePlugin.Commands.HelloCommand` | Your gated command classes (all of them) |
| Manifest `SamplePlugin.addin`, `<AddInId>` GUID | Your manifest name and fresh GUID (never reuse another add-in's) |
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
  <https://github.com/nodeaec/revit-connector> — owns `NodeAecGate`,
  the shared tab, and its own skills (`licensing-integrate`, `ribbon-guard`,
  `revit-build-validate`). Never edit it from this integration; this repo's
  `API.md` governs here.
