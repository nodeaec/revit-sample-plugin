# revit-sample-plugin

One Revit button that demonstrates how to sell through the Node.aec platform: without a valid license, the feature does not run.

This README takes about five minutes. It explains what the sample does, how to run it, and how to apply the same pattern to your own plugin. The license check is a fail-closed gate — `NodeAecLicenseGate.Validate()` is the first statement of `IExternalCommand.Execute` — and the license package is a NuGet `PackageReference` to `NodeAec.Licensing.Lite`.

> **Status (Wave 3):** this README describes the Lite integration — template
> scaffold + `NodeAec.Licensing.Lite` package (`1.0.0-preview.1`) — and the
> `src/` code migration (S1: `Reference` → `PackageReference`,
> `NodeAec.Connector.Gate` → `NodeAec.Licensing`) has landed in the working
> tree. Pre-release, the package restores from the local folder feed
> (`NuGet.config`); at release it restores from NuGet.org with no project change
> (`API.md` §12 records provenance).

## Contents

- [What this does](#what-this-does)
- [How it works](#how-it-works)
- [Try it in 5 minutes](#try-it-in-5-minutes)
- [Make it yours](#make-it-yours)
- [Migrating an existing plugin to Lite](#migrating-an-existing-plugin-to-lite)
- [Let your agent do it](#let-your-agent-do-it)
- [Troubleshooting](#troubleshooting)
- [Project layout](#project-layout)
- [What we validated](#what-we-validated)
- [Links](#links)
- [License](#license)

## What this does

**Sample Plugin** adds a single **Hello World** button to the shared **Node.aec** ribbon tab (panel **Sample Plugin**). Selecting it asks the license gate **compiled into the plugin itself** whether this machine is entitled to run the [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin) product.

With a valid, active license, the command shows a greeting together with a license card: product name, license type, key, and expiry date.

In any other case — not signed in, no entitlement for this product, expired license, seat limit reached, offline grace expired, or no credentials on this machine — the command stops and explains why, with an action that opens the connector so the issue can be resolved. It never runs without a license.

## How it works

Every command calls `NodeAecLicenseGate.Validate()` as the first statement of `IExternalCommand.Execute` and honors the answer.

```
Click Hello World
  -> SamplePlugin.Commands.HelloCommand runs NodeAecLicenseGate.Validate()
       -> Gate.Validate(slug): reads the local lease file, verifies the
          Ed25519 signature offline against the compiled TrustedAnchors,
          no network
            -> licensed:    greeting + license card, Result.Succeeded
            -> not licensed: reason + guidance + open-connector action, Result.Cancelled
```

The gate returns a snapshot with six members (`IsLicensed`, `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`, `Message`). Commands branch only on `IsLicensed` and show `Message` verbatim (PT-BR, as-is); the remaining members are display-only (`null` on failure).

Two pieces work together:

- **Your plugin (+ `NodeAec.Licensing.Lite` NuGet package)** verifies offline. The verification code compiles *inside* your DLL, so there is no external DLL to swap and no connector install needed at build time.
- **The [Node.aec Connector](https://nodeaec.com.br/products/nodeaec-connector)** ([source](https://github.com/nodeaec/revit-connector)) is the desktop hub: sign-in, license synchronization, and the shared ribbon tab. It writes the signed lease file; your plugin only reads and verifies it. Needed at *runtime* for licensed use, never for compiling.

The full list of license outcomes is documented in [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy). The sample handles every outcome with the same blocked dialog, so there is no need to memorize the list.

## Try it in 5 minutes

Prerequisites (install once):

- **.NET 8 SDK** (minimum) — the compiler toolchain. It builds every Revit year from the same machine, including the old `net48` target (Windows-targeting packs handle that; you do not need ancient .NET installed). Building Revit 2027 (`net10.0-windows`, the per-year framework your DLL targets) needs the matching newer SDK alongside it.
- **Revit 2023–2027** — only to *run* the plugin, not to compile it.
- **A product slug** — yours, from the [Node.aec catalog](https://nodeaec.com.br/products) (the sample uses [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)).
- **The [Node.aec Connector](https://nodeaec.com.br/products/nodeaec-connector) + a signed-in, entitled session** — only for the *licensed* test at the end. Compiling, deploying, and even the blocked-state tests work without it.

**1. Install the template (once per machine).**

```bash
dotnet new install NodeAec.Templates.RevitPlugin
```

**2. Scaffold your plugin.** One command produces a working project with no manual wiring. `-n` is the plugin/assembly name; `-p ProductSlug=` is your catalog slug (the template's `--ProductSlug` parameter):

```bash
dotnet new nodeaec-revit-plugin -n MyPlugin -p ProductSlug=my-plugin
cd MyPlugin
```

(This repo is the template's output for `-n SamplePlugin -p ProductSlug=revit-sample-plugin`, plus the sample's demo content.)

**3. Build.** No connector install needed — the license package restores from its configured feed (pre-release: the local folder in `NuGet.config`; at release: NuGet.org), not from a loose DLL. `RevitYear` is an MSBuild property selecting the Revit year; each year maps to a target framework (TFM):

```bash
dotnet build -p:RevitYear=2023   # net48 (old .NET Framework in Revit 2023–2024)
dotnet build -p:RevitYear=2026   # net8.0-windows (default)
dotnet build -p:RevitYear=2027   # net10.0-windows
```

| Revit year | 2023–2024 | 2025–2026 | 2027 |
|---|---|---|---|
| Target framework | `net48` | `net8.0-windows` | `net10.0-windows` |

Details: [API.md §8 — Versioning & compatibility matrix](API.md#8-versioning--compatibility-matrix).

**4. Deploy.** Copy two files per [API.md §3.3](API.md#33-packaging-contract-manifest--payload-layout--verified) — the `.addin` file is the Revit manifest: a small XML that declares the assembly Revit loads on startup:

```
%ProgramData%\Autodesk\Revit\Addins\<year>\MyPlugin.addin
%ProgramData%\Autodesk\Revit\Addins\<year>\MyPlugin\MyPlugin.dll
```

Or run the group installer (`release/MyPlugin-0.1-R<group>-Setup.exe`, produced by `scripts/release.ps1` — one Setup per Revit compatibility group `2023-2024` / `2025-2026` / `2027`; the wizard lists the group's installed Revit versions).

The license assembly travels *inside* your payload automatically — nothing extra to deploy. Do not ship `RevitAPI*.dll` alongside your plugin.

**5. Run.** Open Revit, open the **Node.aec** tab, and select your button. A licensed session (connector installed, signed in, entitled to your slug) shows the greeting; any other state shows the blocked dialog with the reason.

## Make it yours

The template already did the wiring — what remains is your product identity and your commands. Each step below shows the change and the API.md section with full details and edge cases.

**1. Understand the responsibility split.** The connector hub handles sign-in, lease synchronization, and its UI. Your plugin declares a product slug and verifies offline with the license package compiled in — no licensing logic of your own, no network calls. Details: [API.md §1 — Overview & responsibility split](API.md#1-overview--responsibility-split)

```csharp
// All licensing knowledge in this sample lives in one file:
// src/SamplePlugin/Licensing/NodeAecLicenseGate.cs — keep the rest of your code licensing-free.
```

**2. Confirm your product slug.** It was set at scaffold time (`-p ProductSlug=`); it becomes the single constant in the ported file (the sample uses [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)). Matching is trim + case-insensitive. Details: [API.md §4 — Public integration surface](API.md#4-public-integration-surface)

```csharp
public const string ProductSlug = "revit-sample-plugin"; // replace with your slug
```

**3. Keep the package reference (nothing to wire).** The scaffold already declares the license package — a NuGet `PackageReference` resolved from the configured feed. There is deliberately no `Reference` + `HintPath` + `Private False` to an installed DLL anymore: the verification code compiles *into* your plugin, so there is no external DLL an attacker can swap. Details: [API.md §3 — The integration path (authoritative)](API.md#3-the-integration-path-authoritative)

```xml
<PackageReference Include="NodeAec.Licensing.Lite" Version="1.0.0-preview.1" />
```

**4. Keep the licensing seam.** `NodeAecLicenseGate.cs` maps the package's `Snapshot` to your plugin-local `GateSnapshot` and never throws (fail-closed: any doubt denies the feature). Change the slug, nothing else. Details: [API.md §9 — Fail-closed recipe](API.md#9-fail-closed-recipe-nodeaeclicensegatecs)

```csharp
var gate = NodeAecLicenseGate.Validate();   // GateSnapshot — never throws, never null
if (!gate.IsLicensed) { /* blocked dialog + Result.Cancelled */ }
```

**5. Gate every command.** Call `Validate()` as the first statement of each command, once per execution, and branch only on `IsLicensed`. Place nothing — no dialogs, no transactions — before the gate, and avoid calling it inside per-element loops since each call performs disk I/O (reads + decrypts the lease file). Treat any exception or unknown state as not licensed: an error must never become a pass. Details: [API.md §2 — Quickstart](API.md#2-quickstart-happy-path) and [§7 — Threading rules](API.md#7-threading--revit-api-context-rules)

```csharp
var gate = NodeAecLicenseGate.Validate();
if (!gate.IsLicensed) { ShowBlockedDialog(gate); return Result.Cancelled; }
```

**6. Place your UI under the shared tab.** Add your own panel and button inside the shared `Node.aec` tab; do not create a plugin-owned tab. Tab creation is defensive: the "already exists" case is expected when the connector created the tab first. Details: [API.md §6 — Ribbon integration conventions](API.md#6-ribbon-integration-conventions)

```csharp
try { application.CreateRibbonTab("Node.aec"); }
catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)
{ /* already exists — normal */ }
```

**7. Present failures with guidance.** Display the gate message verbatim (Portuguese, as-is — never translate it in code), add a brief note on what to do next, and offer the action that opens the connector. Note that `OpenConnector()` is a silent no-op when the connector UI is unreachable, so the dialog itself must contain the guidance. Details: [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy)

```csharp
dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");
if (dialog.Show() == TaskDialogResult.CommandLink1) NodeAecLicenseGate.OpenConnector();
```

**8. Validate manually in Revit.** Exercise the failure states in a real Revit session: signed out, expired, wrong slug, and no credentials on the machine. Each must block the command; only a healthy license may reach the feature. This step is manual because the underlying storage (DPAPI — Windows' per-user vault that encrypts the lease file) requires an interactive login session. Details: [API.md §10 — Troubleshooting / FAQ](API.md#10-troubleshooting--faq)

```csharp
TaskDialog.Show(Title, $"Hello, {Environment.UserName}!\n\n" + NodeAecLicenseGate.BuildLicenseBlock(gate));
return Result.Succeeded; // reachable only when licensed
```

## Migrating an existing plugin to Lite

Shipping a standalone plugin with no Node.aec integration yet? Adopting Lite is
seven steps — full trail with before/after
in [API.md §13](API.md#13-migrating-an-existing-plugin-to-lite), CI checklist in
[API.md §14](API.md#14-agent--ci-verification-track):

1. **Catalog slug** — register your product and take its slug (one constant in the seam).
2. `dotnet add package NodeAec.Licensing.Lite` — no DLL reference, no `HintPath`, no copy step.
3. Wrap each billable `Execute`: gate as the first line, branch only on `IsLicensed`, `Message` verbatim + `OpenConnector()` + `Result.Cancelled`.
4. Move your own tab into a panel under shared `Node.aec` (defensive create, idempotent inserts, `-=` before `+=` hooks; `App.cs` stays licensing-free).
5. Build the matrix (`2023`/`2026`/`2027`), confirm the payload holds no `RevitAPI*`/`AdWindows`/Hub DLL while Lite travels together.
6. Packaging: your DLL + Lite travel together via `CopyLocalLockFileAssemblies`; never ship `RevitAPI*`.
7. Manual protocol in Revit: licensed → greet; blocked → verbatim + `Cancelled`; no lease (Hub absent) → same blocked, no crash; reload twice → no ghost tab.

## Let your agent do it

Point your coding agent at this repo. It should read the agent brief, the installable skill, then the reference — in that order.

<details>
<summary>Copy-paste agent prompt (click to expand)</summary>

```text
You are adding Node.aec licensing to my Revit plugin (new plugin path).

Learn from https://github.com/nodeaec/revit-sample-plugin — read first:
  1. AGENTS.md
  2. .agents/skills/nodeaec-connector-integration/SKILL.md
  3. API.md (authoritative; follow its section titles, do not invent API)

My repo: <your-plugin-repo>

Confirm before writing code — stop and ask if anything is unresolved:
  - Target Revit year (2023–2027) and its framework (2023/24 net48, 2025/26 net8.0-windows, 2027 net10.0-windows)
  - My catalog slug: <your-product-slug>
  - Which commands need gating (answer: all of them)
  - Whether the test machine has the connector installed with an entitled session (needed only for the licensed run, never for the build)

Then: scaffold with dotnet new nodeaec-revit-plugin -n <Name> -p ProductSlug=<slug>
(API.md §3); keep NodeAecLicenseGate.cs changing only ProductSlug (API.md §9);
gate every command on IsLicensed with the blocked dialog + OpenConnector +
Cancelled (API.md §2, §5, §7); place my panel under the shared Node.aec tab
with idempotent inserts (API.md §6); build the RevitYear matrix 2023/2026/2027
(API.md §8); report file-by-file changes plus the manual cases I must still
run in Revit.

Rules: never weaken the gate, never invent Snapshot fields, never match on
message text, never add a HintPath/Reference to a connector DLL, never add
HTTP calls or login UI.
```

</details>

To install the skill, copy `.agents/skills/nodeaec-connector-integration/` into your repo's `.agents/skills/` folder (or your agent's global skills directory). `AGENTS.md` is the companion brief for agents working here.

## Troubleshooting

Plain-English symptoms; fixes grounded in [API.md §5](API.md#5-status--reason-taxonomy) and [§10](API.md#10-troubleshooting--faq). Gate messages are Portuguese verbatim — shown as-is in the dialog, never translated in code.

| Symptom | Fix |
|---|---|
| Package restore fails (`NU1101`, `NodeAec.Licensing.Lite` not found) | The template's `PackageReference` resolves from its configured feed — pre-release that is the local folder in `NuGet.config` (build the Lite `Release` first), at release it is NuGet.org; check the pinned version in [API.md §8](API.md#8-versioning--compatibility-matrix) |
| Not signed in (no credentials on this machine) | Open the connector, sign in or activate a key, re-run |
| Product not in this account's entitlements (often a wrong slug) | Buy/activate it, or fix your `ProductSlug` constant |
| License or trial expired | Renew in the Node.aec portal, let the connector sync |
| Seat limit reached | Free a seat in the web portal, then re-run |
| Offline grace expired | Go online, click sync in the connector, re-run |
| No credentials and no connector for this Revit year | Get it from the [product page](https://nodeaec.com.br/products/nodeaec-connector) ([source](https://github.com/nodeaec/revit-connector)), install it for that year, sign in — then re-run (no rebuild needed: the build never depended on it) |
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
    ├── SamplePlugin.csproj RevitYear matrix + PackageReference NodeAec.Licensing.Lite
    ├── SamplePlugin.addin  manifest (Assembly = SamplePlugin\SamplePlugin.dll)
    ├── App.cs              shared Node.aec tab, panel, button, dedup hooks
    ├── Commands/HelloCommand.cs   gate first, then greet
    └── Licensing/NodeAecLicenseGate.cs   Validate(), OpenConnector(), BuildLicenseBlock()
```

Scaffold source (what generated this shape): `dotnet new nodeaec-revit-plugin`
(template package `NodeAec.Templates.RevitPlugin`); license package
`NodeAec.Licensing.Lite 1.0.0-preview.1` on NuGet.org. Provenance:
[API.md §12](API.md#12-verification--related-documents).

## What we validated

- **Build matrix green** for Revit years 2023–2027 with **no connector installed** — the license package restores from NuGet, so compilation no longer depends on the hub.
- **Behavior in Revit only via the manual protocol** — signed-out, expired, wrong slug, seat limit, offline grace, no credentials. Each must block; only a healthy license greets. This is not scripted; the underlying storage requires an interactive session, so run it on the target machine.
- **Gate surface verified** against `NodeAec.Licensing.Lite 1.0.0-preview.1` (frozen contract: `Gate.Validate` / `Snapshot`, six members). Open questions are flagged inline in API.md.

## Links

- [API.md](API.md) — the full integration reference
- [AGENTS.md](AGENTS.md) — brief for coding agents in this repo
- [.agents/skills/nodeaec-connector-integration/SKILL.md](.agents/skills/nodeaec-connector-integration/SKILL.md) — the installable skill
- [Sample Plugin product page](https://nodeaec.com.br/products/revit-sample-plugin) — the catalog entry for this sample's `revit-sample-plugin` slug (the entitlement your connector session needs for the demo)
- [Node.aec Connector product page](https://nodeaec.com.br/products/nodeaec-connector) — download and install the connector (needed only for the licensed run, never for the build)
- [github.com/nodeaec/revit-connector](https://github.com/nodeaec/revit-connector) — the **Node.aec Connector source**: the desktop hub this sample plugs into. It owns sign-in, license sync, and the shared `Node.aec` ribbon tab. Read-only upstream — install it, never copy code out of it by hand.
- [Node.aec platform](https://nodeaec.com.br) — accounts, entitlements, catalog

## License

MIT — Copyright (c) 2026 Node.aec. See [LICENSE](LICENSE).
