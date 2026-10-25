# revit-sample-plugin

One Revit button that demonstrates how to sell through the Node.aec platform: without a valid license, the feature does not run.

This README takes about five minutes. It explains what the sample does, how to run it, and how to apply the same pattern to your own plugin. The license check is a fail-closed gate — `Gate.Validate(ProductSlug)` is the first statement of `IExternalCommand.Execute` — and the license package is a NuGet `PackageReference` to `NodeAec.Licensing.Lite`.

> **Status:** the `src/` code uses `NodeAec.Licensing.Lite` 0.3.0 from NuGet.org, and
> `dotnet new nodeaec-revit-plugin` (template 0.3.0 or later) generates the same shape, bundle installer included.
> Template 0.1.0 generated an older wrapper class and a manifest with invalid XML: update
> with `dotnet new install NodeAec.Templates.RevitPlugin --force`.

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

With a valid, active license, the command shows a greeting together with a license card: product name, license type, and expiry date. The license key is never shown: it is the user's secret.

In any other case — not signed in, no entitlement for this product, expired license, seat limit reached, offline grace expired, or no credentials on this machine — the command stops and explains why, with an action that opens the connector so the issue can be resolved. It never runs without a license.

## How it works

Every command calls `Gate.Validate(ProductSlug)` as the first statement of `IExternalCommand.Execute` and honors the answer.

```
Click Hello World
  -> SamplePlugin.Commands.HelloCommand runs Gate.Validate(ProductSlug)
       -> reads the local lease file, verifies the Ed25519 signature
          offline against the anchors compiled into the package, no network
            -> licensed:     greeting + license card, Result.Succeeded
            -> not licensed: the reason, in Revit's UI language
                             + open-connector link, Result.Cancelled
```

The gate returns a `Snapshot`. Commands decide only on `IsLicensed` and show `GetMessage(language)` as-is (Portuguese or English). `Reason` names the case for logs; `ProductName`, `LicenseType` and `ExpiresAt` are display-only (`null` on failure); `LicenseKey` is the user's secret and is never shown or logged.

Two pieces work together:

- **Your plugin (+ `NodeAec.Licensing.Lite` NuGet package)** verifies offline. The verification code compiles *inside* your DLL, so no connector install is needed at build time.
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

**2. Scaffold your plugin.** One command produces a working project with no manual wiring. `-n` is the plugin/assembly name; `--ProductSlug` is your catalog slug (the template's `--ProductSlug` parameter):

```bash
dotnet new nodeaec-revit-plugin -n MyPlugin --ProductSlug my-plugin
cd MyPlugin
```

(This repo is the template's output for `-n SamplePlugin --ProductSlug revit-sample-plugin`, plus the sample's demo content.)

**3. Build.** No connector install needed — the license package restores from NuGet.org. `RevitYear` is an MSBuild property selecting the Revit year; each year maps to a target framework (TFM):

```bash
dotnet build -p:RevitYear=2023   # net48 (old .NET Framework in Revit 2023–2024)
dotnet build -p:RevitYear=2026   # net8.0-windows (default)
dotnet build -p:RevitYear=2027   # net10.0-windows
```

| Revit year | 2023–2024 | 2025–2026 | 2027 |
|---|---|---|---|
| Target framework | `net48` | `net8.0-windows` | `net10.0-windows` |

Details: [API.md §8 — Versioning & compatibility matrix](API.md#8-versioning--compatibility-matrix).

**4. Deploy.** Run `scripts/release.ps1 -Version 0.1.0`. It builds the three Revit groups into one Autodesk bundle (layout in [API.md §3.3](API.md#33-packaging-contract-bundle-layout--verified)) and produces:

- `release/MyPlugin-0.1.0-Setup.exe`: one installer for Revit 2023–2027. The user checks the Revit versions that should load the plugin; installed versions start checked.
- `release/MyPlugin-0.1.0.bundle.zip`: the same bundle for IT deployment; extract it into `%ProgramData%\Autodesk\ApplicationPlugins\`.

Add `-Install` to copy the bundle into this machine's `ApplicationPlugins` folder (close Revit first).

The license assembly travels *inside* your payload automatically — nothing extra to deploy. Do not ship `RevitAPI*.dll` alongside your plugin.

**5. Run.** Open Revit, open the **Node.aec** tab, and select your button. A licensed session (connector installed, signed in, entitled to your slug) shows the greeting; any other state shows the blocked dialog with the reason.

## Make it yours

The template already did the wiring — what remains is your product identity and your commands. Each step below shows the change and the API.md section with full details and edge cases.

**1. Understand the responsibility split.** The connector hub handles sign-in, lease synchronization, and its UI. Your plugin declares a product slug and verifies offline with the license package compiled in — no licensing logic of your own, no network calls. Details: [API.md §1 — Overview & responsibility split](API.md#1-overview--responsibility-split)

```csharp
// Licensing in this sample is the first lines of src/SamplePlugin/Commands/HelloCommand.cs.
// App.cs (the Ribbon) has no licensing calls.
```

**2. Confirm your product slug.** The scaffold sets it (`--ProductSlug`); it becomes the `ProductSlug` constant in `HelloCommand` (the sample uses [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)). Matching is trim + case-insensitive. Details: [API.md §4 — Public integration surface](API.md#4-public-integration-surface)

```csharp
public const string ProductSlug = "revit-sample-plugin"; // replace with your slug
```

**3. Keep the package reference (nothing to wire).** The scaffold already declares the license package — a NuGet `PackageReference` resolved from the configured feed. The verification code compiles *into* your plugin, so the licensing decision lives inside your own DLL. Details: [API.md §3 — The integration path (authoritative)](API.md#3-the-integration-path-authoritative)

```xml
<PackageReference Include="NodeAec.Licensing.Lite" Version="0.3.0" />
```

**4. Call the gate directly.** `Gate.Validate` never throws and never returns `null`: every failure comes back as `IsLicensed = false`. You need no wrapper class and no `try/catch`. Details: [API.md §9 — Command recipe](API.md#9-command-recipe-hellocommandcs)

```csharp
Snapshot gate = Gate.Validate(ProductSlug);
if (!gate.IsLicensed) { /* blocked dialog + Result.Cancelled */ }
```

**5. Gate every command.** Call `Validate()` as the first statement of each command, once per execution, and branch only on `IsLicensed`. Place nothing — no dialogs, no transactions — before the gate, and avoid calling it inside per-element loops since each call performs disk I/O (reads + decrypts the lease file). Treat any exception or unknown state as not licensed: an error must never become a pass. Details: [API.md §2 — Quickstart](API.md#2-quickstart-happy-path) and [§7 — Threading rules](API.md#7-threading--revit-api-context-rules)

```csharp
Snapshot gate = Gate.Validate(ProductSlug);
if (!gate.IsLicensed) { ShowBlockedDialog(gate.GetMessage(UserLanguage(commandData))); return Result.Cancelled; }
```

**6. Place your UI under the shared tab.** Add your own panel and button inside the shared `Node.aec` tab; do not create a plugin-owned tab. Tab creation is defensive: the "already exists" case is expected when the connector created the tab first. Details: [API.md §6 — Ribbon integration conventions](API.md#6-ribbon-integration-conventions)

```csharp
try { application.CreateRibbonTab("Node.aec"); }
catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)
{ /* already exists — normal */ }
```

**7. Show the reason, then offer the Connector.** Display the gate message as-is, in the user's language: `gate.GetMessage(MessageLanguage.English)` or `MessageLanguage.Portuguese` (the sample follows Revit's UI language). Never translate or rewrite it in code. It already says what went wrong and what to do, so don't add a list of possible causes around it. Offer a link that opens the connector; `OpenConnector()` is a silent no-op when the connector is not installed, so always show the dialog first. Details: [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy)

```csharp
dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");
if (dialog.Show() == TaskDialogResult.CommandLink1) Gate.OpenConnector();
```

**8. Validate manually in Revit.** Exercise the failure states in a real Revit session: signed out, expired, wrong slug, and no credentials on the machine. Each must block the command; only a healthy license may reach the feature. This step is manual because the underlying storage (DPAPI — Windows' per-user vault that encrypts the lease file) requires an interactive login session. Details: [API.md §10 — Troubleshooting / FAQ](API.md#10-troubleshooting--faq)

```csharp
TaskDialog.Show(Title, $"Hello, {Environment.UserName}!\n\n" + BuildLicenseBlock(gate));
return Result.Succeeded; // reachable only when licensed
```

## Migrating an existing plugin to Lite

Shipping a standalone plugin with no Node.aec integration yet? Adopting Lite is
seven steps — full trail with before/after
in [API.md §13](API.md#13-migrating-an-existing-plugin-to-lite), CI checklist in
[API.md §14](API.md#14-agent--ci-verification-track):

1. **Catalog slug** — register your product and take its slug (one `ProductSlug` constant).
2. `dotnet add package NodeAec.Licensing.Lite` — one package reference, nothing to copy or wire.
3. Wrap each billable `Execute`: gate as the first line, branch only on `IsLicensed`, the gate's message as-is + `OpenConnector()` + `Result.Cancelled`.
4. Move your own tab into a panel under shared `Node.aec` (defensive create, idempotent inserts, `-=` before `+=` hooks; `App.cs` stays licensing-free).
5. Build the matrix (`2023`/`2026`/`2027`), confirm the payload holds no `RevitAPI*`/`AdWindows`/Hub DLL while Lite travels together.
6. Packaging: your DLL + Lite travel together via `CopyLocalLockFileAssemblies`; never ship `RevitAPI*`.
7. Manual protocol in Revit: licensed → greet; blocked → message as-is + `Cancelled`; no lease (Hub absent) → same blocked, no crash; reload twice → no ghost tab.

## Let your agent do it

Every path below has the same agent material: the skill
[`.agents/skills/licensing-integrate/`](.agents/skills/licensing-integrate/SKILL.md) (detailed
steps, rules and checks) and a prompt to paste into your coding agent. To install the skill,
copy the `.agents/skills/licensing-integrate/` folder into your repo's `.agents/skills/` folder
(or your agent's global skills folder). Projects made from the template already have it.

<details>
<summary>Prompt: start a new plugin from the template</summary>

```text
Create a new Autodesk Revit plugin licensed through Node.aec.

Follow the skill at https://github.com/nodeaec/revit-sample-plugin/tree/main/.agents/skills/licensing-integrate
(SKILL.md, path A). The Sample Plugin in that repo is the worked example.

Before writing code, ask me the questions in the skill's section 2 (product slug, Revit
years, panel name, which commands are paid, test machine) and wait for my answers.

Then: install the template (dotnet new install NodeAec.Templates.RevitPlugin), scaffold with
dotnet new nodeaec-revit-plugin, add my commands with the gate as their first statement,
build every compatibility group with 0 errors, and package with scripts/release.ps1.

Finish with: the files you created or changed, and the manual Revit checks from the
skill's references/validation.md that I still have to run.
```

</details>

<details>
<summary>Prompt: add licensing to an existing plugin</summary>

```text
Add Node.aec licensing to my existing Autodesk Revit plugin in this repository.

Follow the skill at https://github.com/nodeaec/revit-sample-plugin/tree/main/.agents/skills/licensing-integrate
(SKILL.md, path B, and references/migration.md). The Sample Plugin in that repo is the
worked example.

First read my code and report the inventory from references/migration.md section 1
(projects and frameworks, commands, Ribbon, any existing license check, installer). Then
ask me the questions in SKILL.md section 2 and wait for my answers.

Then: add the NodeAec.Licensing.Lite package, gate every paid command with Gate.Validate
as its first statement, move my panels into the shared Node.aec tab, and keep my installer
working (or switch to the bundle installer if I choose that). Change nothing else.

Finish with: the files you changed, the commands you gated (and any you left ungated, with
the reason), and the manual Revit checks I still have to run.
```

</details>

<details>
<summary>Prompt: learn from the Sample Plugin</summary>

```text
Teach me how Node.aec licensing works in an Autodesk Revit plugin, using the Sample Plugin.

Clone https://github.com/nodeaec/revit-sample-plugin and follow its skill
(.agents/skills/licensing-integrate/SKILL.md, path C).

Build it, then walk me through the source in the order of the README's "Reading the
source" section. For each file, explain what it does and why, using the comments in the
code; do not invent reasons. Tell me how to install and run it in Revit, and what I should
see with and without a license.

Do not change any file.
```

</details>

## Troubleshooting

Plain-English symptoms; fixes grounded in [API.md §5](API.md#5-status--reason-taxonomy) and [§10](API.md#10-troubleshooting--faq). Gate messages come in Portuguese and English — shown as-is in the dialog, never rewritten in code.

| Symptom | Fix |
|---|---|
| Package restore fails (`NU1101`, `NodeAec.Licensing.Lite` not found) | The template's `PackageReference` resolves from its configured feed — that is NuGet.org; check the pinned version in [API.md §8](API.md#8-versioning--compatibility-matrix) |
| Not signed in (no credentials on this machine) | Open the connector, sign in or activate a key, re-run |
| Product not in this account's entitlements (often a wrong slug) | Buy/activate it, or fix your `ProductSlug` constant |
| License or trial expired | Renew in the Node.aec portal, let the connector sync |
| Seat limit reached | Free a seat in the web portal, then re-run |
| Offline grace expired | Go online, click sync in the connector, re-run |
| No credentials and no connector for this Revit year | Get it from the [product page](https://nodeaec.com.br/products/nodeaec-connector) ([source](https://github.com/nodeaec/revit-connector)) and install it; if it is installed already, run its Setup again and check this Revit version. Sign in, then re-run (no rebuild needed: compiling does not require the connector) |
| Two `Node.aec` tabs after reload | Re-read [API.md §6](API.md#6-ribbon-integration-conventions): idempotent panel/button inserts plus the AdWindows hooks |
| Open-connector button seems to do nothing | Expected when the connector UI is unreachable — `OpenConnector()` is a silent no-op by contract, so the dialog already carries the guidance |

## Project layout

```
revit-sample-plugin/
├── API.md                  full integration reference (start at §1)
├── AGENTS.md               brief for coding agents working in this repo
├── README.md               you are here
├── docs/USER_MANUAL.md     end-user manual (install, dialogs, troubleshooting)
├── LICENSE
├── .agents/skills/licensing-integrate/
│   ├── SKILL.md            installable agent skill
│   └── references/         gate walkthrough + manual test script
├── scripts/
│   ├── release.ps1         builds the 3 Revit groups into SamplePlugin.bundle + zip + Setup.exe
│   └── installer.iss       Inno Setup: one Setup, a checkbox per Revit year
└── src/SamplePlugin/
    ├── SamplePlugin.csproj RevitYear matrix + PackageReference NodeAec.Licensing.Lite
    ├── SamplePlugin.addin  manifest (Assembly = SamplePlugin.dll, copied into each bundle group)
    ├── App.cs              shared Node.aec tab, panel, button, dedup hooks
    └── Commands/HelloCommand.cs   ProductSlug, Gate.Validate first, blocked dialog, greeting
```

### Reading the source

The comments in the source explain why each piece is the way it is, not only what it
does. To learn the integration, read the files in this order:

1. `src/SamplePlugin/Commands/HelloCommand.cs`: the whole licensing integration. How the
   Connector, the lease and `Gate.Validate` fit together, why the gate runs on every click,
   why there is no `try/catch`, why the command returns `Cancelled`, why the license key is
   never shown.
2. `src/SamplePlugin/App.cs`: how Revit finds and starts an add-in, why the plugin shares
   the `Node.aec` tab, why there are no licensing calls at startup, and why tab
   deduplication goes through AdWindows.
3. `src/SamplePlugin/SamplePlugin.addin`: what each manifest element is for.
4. `src/SamplePlugin/SamplePlugin.csproj`: why one build per group of Revit years, why
   the Revit API is never copied while NuGet dependencies always are, and which Lite
   version to build against.
5. `scripts/release.ps1` and `scripts/installer.iss`: why a bundle instead of a `.addin`
   per year, and the order in which Inno Setup runs the installer code.

Scaffold source (what generated this shape): `dotnet new nodeaec-revit-plugin`
(template package `NodeAec.Templates.RevitPlugin`); license package
`NodeAec.Licensing.Lite 0.3.0` on NuGet.org. Provenance:
[API.md §12](API.md#12-verification--related-documents).

## What we validated

- **Build matrix green** for Revit years 2023–2027 with **no connector installed** — the license package restores from NuGet, so compiling never needs the hub.
- **Behavior in Revit only via the manual protocol** — signed-out, expired, wrong slug, seat limit, offline grace, no credentials. Each must block; only a healthy license greets. This is not scripted; the underlying storage requires an interactive session, so run it on the target machine.
- **Gate surface verified** against `NodeAec.Licensing.Lite 0.3.0` (`Gate.Validate` / `Snapshot` with `Reason` and `GetMessage`).

## Links

- [docs/USER_MANUAL.md](docs/USER_MANUAL.md) — for the people who use the plugin in Revit: install, the licensed and blocked dialogs, troubleshooting (also a starting point for your own plugin's manual)
- [API.md](API.md) — the full integration reference
- [AGENTS.md](AGENTS.md) — brief for coding agents in this repo
- [.agents/skills/licensing-integrate/SKILL.md](.agents/skills/licensing-integrate/SKILL.md) — the installable skill
- [Sample Plugin product page](https://nodeaec.com.br/products/revit-sample-plugin) — the catalog entry for this sample's `revit-sample-plugin` slug (the entitlement your connector session needs for the demo)
- [Node.aec Connector product page](https://nodeaec.com.br/products/nodeaec-connector) — download and install the connector (needed only for the licensed run, never for the build)
- [github.com/nodeaec/revit-connector](https://github.com/nodeaec/revit-connector) — the **Node.aec Connector source**: the desktop hub this sample plugs into. It owns sign-in, license sync, and the shared `Node.aec` ribbon tab. Read-only upstream — install it, never copy code out of it by hand.
- [Node.aec platform](https://nodeaec.com.br) — accounts, entitlements, catalog

## License

MIT — Copyright (c) 2026 Node.aec. See [LICENSE](LICENSE).
