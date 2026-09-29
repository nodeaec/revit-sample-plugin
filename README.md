# revit-sample-plugin

One Revit button that demonstrates how to sell through the Node.aec platform: without a valid license, the feature does not run.

This README takes about five minutes. It explains what the sample does, how to run it, and how to apply the same pattern to your own plugin.

## Contents

- [What this does](#what-this-does)
- [How it works](#how-it-works)
- [Try it in 5 minutes](#try-it-in-5-minutes)
- [Make it yours](#make-it-yours)
- [Let your agent do it](#let-your-agent-do-it)
- [Troubleshooting](#troubleshooting)
- [Project layout](#project-layout)
- [What we validated](#what-we-validated)
- [Links](#links)
- [License](#license)

## What this does

**Sample Plugin** adds a single **Hello World** button to the shared **Node.aec** ribbon tab (panel **Sample Plugin**). Selecting it asks the Node.aec Connector whether this machine is entitled to run the [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin) product.

With a valid, active license, the command shows a greeting together with a license card: product name, license type, key, and expiry date.

In any other case — not signed in, no entitlement for this product, expired license, seat limit reached, offline grace expired, or connector not installed — the command stops and explains why, with an action that opens the connector so the issue can be resolved. It never runs without a license.

## How it works

Every command asks the gate first and honors the answer.

```
Click Hello World
  -> SamplePlugin.Commands.HelloCommand runs NodeAecLicenseGate.Validate()
       -> local license read, no network
            -> licensed:    greeting + license card, Result.Succeeded
            -> not licensed: reason + guidance + open-connector action, Result.Cancelled
```

The gate returns a snapshot with six fields (`IsLicensed`, `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`, `Message`). Commands branch on `IsLicensed` only; the remaining fields are display text.

The other half of this picture is the [Node.aec Connector](https://nodeaec.com.br/products/nodeaec-connector) ([source](https://github.com/nodeaec/revit-connector)): the installed desktop hub responsible for sign-in, license synchronization, the gate itself, and the shared ribbon tab. This plugin only queries it.

The full list of license outcomes is documented in [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy). The sample handles every outcome with the same blocked dialog, so there is no need to memorize the list.

## Try it in 5 minutes

Prerequisites: Revit 2023–2027, the [Node.aec Connector](https://nodeaec.com.br/products/nodeaec-connector) installed for that Revit year ([source](https://github.com/nodeaec/revit-connector)), and a connector session signed in and entitled to [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin). Without the connector, start from the [product page](https://nodeaec.com.br/products/nodeaec-connector) — the steps below assume it is installed.

**1. Build.** Defaults to Revit 2026 ([API.md §8 — Versioning & compatibility matrix](API.md#8-versioning--compatibility-matrix)):

```bash
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2023   # net48
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2027   # net10
```

On a machine without the connector, point at any same-year copy to verify compilation:

```bash
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026 -p:NodeAecConnectorDll=<path-to-NodeAec.Connector.dll>
```

| Revit year | 2023–2024 | 2025–2026 | 2027 |
|---|---|---|---|
| Target framework | `net48` | `net8.0-windows` | `net10.0-windows` |

**2. Install.** Easiest: run the year-matching installer (`release/SamplePlugin-1.0.0-R<year>-Setup.exe`, produced by `scripts/release.ps1` — one Setup per year). Or copy two files per [API.md §3.3](API.md#33-packaging-contract-manifest--payload-layout--verified):

```
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin\SamplePlugin.dll
```

Do not ship `NodeAec.Connector.dll` or `RevitAPI*.dll` alongside your plugin.

**3. Run.** Open Revit, open the **Node.aec** tab, and select **Hello World** in the **Sample Plugin** panel. A licensed session shows the greeting; any other state shows the blocked dialog.

## Make it yours

The same eight steps apply to any plugin. Each step below shows the change, a short excerpt from this repo, and the API.md section with full details and edge cases.

**1. Understand the responsibility split.** The connector handles sign-in, lease synchronization, and license decisions. Your plugin declares a product slug and queries the gate at command entry. It performs no licensing logic and makes no network calls. Details: [API.md §1 — Overview & responsibility split](API.md#1-overview--responsibility-split)

```csharp
// All licensing knowledge in this sample lives in one file:
// src/SamplePlugin/Licensing/NodeAecLicenseGate.cs — port it and keep the rest connector-free.
```
Source: [NodeAecLicenseGate.cs:L8-L11](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L8-L11)

**2. Register your product slug.** Register your product in the [Node.aec catalog](https://nodeaec.com.br/products) to receive a slug. That slug becomes the single constant you change in the ported file (the sample uses [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)). Details: [API.md §4 — Public integration surface](API.md#4-public-integration-surface)

```csharp
public const string ProductSlug = "revit-sample-plugin"; // replace with your slug
```
Source: [NodeAecLicenseGate.cs:L30](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L30)

**3. Reference the installed connector.** Add a build-time reference to the connector DLL at its installed location. Do not use NuGet or a project reference, and do not copy the DLL into your plugin folder. Details: [API.md §3 — The integration path (authoritative)](API.md#3-the-integration-path-authoritative)

```xml
<Reference Include="NodeAec.Connector">
  <HintPath>$(NodeAecConnectorDll)</HintPath>
  <Private>False</Private>
</Reference>
```
Source: [SamplePlugin.csproj:L105-L107](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj#L105-L107) (path property at [L70](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj#L70))

**4. Port the licensing seam.** Copy `NodeAecLicenseGate.cs` unchanged except for the slug. Its wrapper methods isolate every connector-type reference so that a missing connector produces a clean denial rather than a crash. Details: [API.md §9 — Fail-closed recipe](API.md#9-fail-closed-recipe-nodeaeclicensegatecs)

```csharp
public static GateSnapshot Validate()
{
    try { return RunValidation(); }
    catch (Exception) { return new GateSnapshot(isLicensed: false, message: ConnectorUnavailableMessage, ...); }
}
```
Source: [NodeAecLicenseGate.cs:L46-L65](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L46-L65) (isolation helper at [L74-L86](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L74-L86))

**5. Gate every command.** Call `Validate()` as the first statement of each command, once per execution, and branch only on `IsLicensed`. Place nothing — no dialogs, no transactions — before the gate, and avoid calling it inside per-element loops since each call performs disk I/O. Treat any exception or unknown state as not licensed: an error must never become a pass. Details: [API.md §2 — Quickstart](API.md#2-quickstart-happy-path) and [§7 — Threading rules](API.md#7-threading--revit-api-context-rules)

```csharp
var gate = NodeAecLicenseGate.Validate();
if (!gate.IsLicensed) { ShowBlockedDialog(gate); return Result.Cancelled; }
```
Source: [HelloCommand.cs:L40-L63](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L40-L63)

**6. Place your UI under the shared tab.** Add your own panel and button inside the shared `Node.aec` tab; do not create a plugin-owned tab. Tab creation is defensive: the "already exists" case is expected when the connector created the tab first. Details: [API.md §6 — Ribbon integration conventions](API.md#6-ribbon-integration-conventions)

```csharp
try { application.CreateRibbonTab("Node.aec"); }
catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)
{ /* already exists — normal */ }
```
Source: [App.cs:L100](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L100) (panel at [L118-L130](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L118-L130), hooks at [L175-L179](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L175-L179))

**7. Present failures with guidance.** Display the connector message verbatim, add a brief note on what to do next, and offer the action that opens the connector. Note that `OpenConnector()` is a silent no-op when the connector UI is unreachable, so the dialog itself must contain the guidance. Details: [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy)

```csharp
dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");
if (dialog.Show() == TaskDialogResult.CommandLink1) NodeAecLicenseGate.OpenConnector();
```
Source: [HelloCommand.cs:L128-L133](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L128-L133)

**8. Validate manually in Revit.** Exercise the failure states in a real Revit session: signed out, expired, wrong slug, and connector missing. Each must block the command; only a healthy license may reach the feature. This step is manual because the underlying storage requires an interactive login session. Details: [API.md §10 — Troubleshooting / FAQ](API.md#10-troubleshooting--faq)

```csharp
TaskDialog.Show(Title, $"Hello, {Environment.UserName}!\n\n" + NodeAecLicenseGate.BuildLicenseBlock(gate));
return Result.Succeeded; // reachable only when licensed
```
Source: [HelloCommand.cs:L65-L73](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L65-L73)

## Let your agent do it

Point your coding agent at this repo. It should read the agent brief, the installable skill, then the reference — in that order.

<details>
<summary>Copy-paste agent prompt (click to expand)</summary>

```text
You are integrating the Node.aec Connector license gate into my Revit plugin.

Learn from https://github.com/nodeaec/revit-sample-plugin — read first:
  1. AGENTS.md
  2. .agents/skills/nodeaec-connector-integration/SKILL.md
  3. API.md (authoritative; follow its section titles, do not invent API)

My repo: <your-plugin-repo>

Confirm before writing code — stop and ask if anything is unresolved:
  - Target Revit year (2023–2027) and its framework (2023/24 net48, 2025/26 net8.0-windows, 2027 net10.0-windows)
  - Connector installed for that year, and a signed-in session entitled to my slug
  - My catalog slug: <your-product-slug>
  - Which commands need gating (answer: all of them)

Then: add the Reference + HintPath + Private False (API.md §3); port
NodeAecLicenseGate.cs changing only ProductSlug (API.md §9); gate every
command on IsLicensed with the blocked dialog + OpenConnector + Cancelled
(API.md §2, §5, §7); place my panel under the shared Node.aec tab with
idempotent inserts (API.md §6); build the RevitYear matrix (API.md §8);
report file-by-file changes plus the manual cases I must still run in Revit.

Rules: never weaken the gate, never invent GateResult fields, never match on
message text, never add HTTP calls or login UI.
```

</details>

To install the skill, copy `.agents/skills/nodeaec-connector-integration/` into your repo's `.agents/skills/` folder (or your agent's global skills directory). `AGENTS.md` is the companion brief for agents working here.

## Troubleshooting

Plain-English symptoms; fixes grounded in [API.md §5](API.md#5-status--reason-taxonomy) and [§10](API.md#10-troubleshooting--faq). Connector messages are Portuguese verbatim — shown as-is in the dialog, never translated in code.

| Symptom | Fix |
|---|---|
| Not signed in (no credentials on this machine) | Open the connector, sign in or activate a key, re-run |
| Product not in this account's entitlements (often a wrong slug) | Buy/activate it, or fix your `ProductSlug` constant |
| License or trial expired | Renew in the Node.aec portal, let the connector sync |
| Seat limit reached | Free a seat in the web portal, then re-run |
| Offline grace expired | Go online, click sync in the connector, re-run |
| Connector not installed for this Revit year | Get it from the [product page](https://nodeaec.com.br/products/nodeaec-connector) ([source](https://github.com/nodeaec/revit-connector)), install/repair it for that year; do not copy its DLL into your folder |
| Two `Node.aec` tabs after reload | Re-read [API.md §6](API.md#6-ribbon-integration-conventions): idempotent panel/button inserts plus the AdWindows hooks |
| Open-connector button seems to do nothing | Expected when the connector UI is unreachable — `OpenConnector()` is a silent no-op by contract, so the dialog already carries the guidance |

## Project layout

```
revit-sample-plugin/
├── API.md                  full integration reference (start at §1)
├── AGENTS.md               brief for coding agents working in this repo
├── README.md               you are here
├── LICENSE
├── .agents/skills/nodeaec-connector-integration/
│   ├── SKILL.md            installable agent skill
│   └── references/         seam walkthrough + manual test script
└── src/SamplePlugin/
    ├── [SamplePlugin.csproj](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj) RevitYear matrix + the one connector reference
    ├── [SamplePlugin.addin](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.addin)  manifest (Assembly = SamplePlugin\SamplePlugin.dll)
    ├── [App.cs](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs)              shared Node.aec tab, panel, button, dedup hooks
    ├── Commands/[HelloCommand.cs](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs)   gate first, then greet
    └── Licensing/[NodeAecLicenseGate.cs](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs)   Validate(), OpenConnector(), BuildLicenseBlock()
```

## What we validated

- **Build matrix green** for Revit years 2023–2027 via the `NodeAecConnectorDll` override on machines without the connector installed.
- **Behavior in Revit only via the manual protocol** — signed-out, expired, wrong slug, seat limit, offline grace, connector missing. Each must block; only a healthy license greets. This is not scripted; the underlying storage requires an interactive session, so run it on the target machine.
- **Connector surface verified** against `revit-connector@7366482`. Open questions are flagged inline in API.md.

## Links

- [API.md](API.md) — the full integration reference
- [AGENTS.md](AGENTS.md) — brief for coding agents in this repo
- [.agents/skills/nodeaec-connector-integration/SKILL.md](.agents/skills/nodeaec-connector-integration/SKILL.md) — the installable skill
- [Sample Plugin product page](https://nodeaec.com.br/products/revit-sample-plugin) — the catalog entry for this sample's `revit-sample-plugin` slug (the entitlement your connector session needs for the demo)
- [Node.aec Connector product page](https://nodeaec.com.br/products/nodeaec-connector) — download and install the connector (start here without it)
- [github.com/nodeaec/revit-connector](https://github.com/nodeaec/revit-connector) — the **Node.aec Connector source**: the desktop hub this sample plugs into. It owns sign-in, license sync, the `NodeAecGate` license gate, and the shared `Node.aec` ribbon tab. Read-only upstream — install it, build against it, never copy code out of it by hand.
- [Node.aec platform](https://nodeaec.com.br) — accounts, entitlements, catalog

## License

MIT — Copyright (c) 2026 Node.aec. See [LICENSE](LICENSE).
