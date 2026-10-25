# AGENTS.md — operating instructions for coding agents

Instructions for any agent working **in this repository**, and for agents adapting this
sample into a real Autodesk Revit plugin. Read this file before touching anything.
Human-facing overview lives in [`README.md`](README.md); the full integration reference
lives in [`API.md`](API.md). Where this file and `API.md` differ on a connector
identifier or contract, **`API.md` wins** (see rule G7).

---

## 1. What this repo is — and the one thing you must never break

This repo is the **Sample Plugin**: a minimal, complete, working reference add-in that
shows how a third-party Revit plugin integrates Node.aec licensing through the
embedded Lite gate (`NodeAec.Licensing.Gate.Validate`, package
`NodeAec.Licensing.Lite`). It exists to be read by humans **and
by coding agents**, then copied/adapted into real commercial plugins.

> **Migration track:** migration means existing STANDALONE plugins with no
> Node.aec integration adopting `NodeAec.Licensing.Lite` for the first time
> (`API.md` §13).

**The invariant that outranks everything else: licensing is FAIL-CLOSED.**

- `SamplePlugin.Commands.HelloCommand` calls `Gate.Validate(ProductSlug)` (`NodeAec.Licensing`)
  as its **first statement**; nothing in a command executes without a verified license.
- Every non-licensed, unknown, or exceptional outcome ends in the blocked dialog and
  `Result.Cancelled`. There is no code path past the gate without a license.
- "Cannot reach the gate" (no lease, Hub absent, exception anywhere)
  is **denied**, never allowed. A machine without credentials must behave
  exactly like an unlicensed machine: a denied `Snapshot`, plugin-owned dialog,
  `Result.Cancelled`. A machine without the Hub simply has no lease — the same
  ordinary failure.

Any change that lets a command run unlicensed — silently, by catching an error into the
licensed branch, or by branching on something other than `IsLicensed` — is a defect,
regardless of how convenient it looks. Treat this as the repo's equivalent of a
security boundary.

---

## 2. Repo map

| Path | Role |
|---|---|
| `src/SamplePlugin/SamplePlugin.csproj` | SDK-style project: Revit-year matrix, the `NodeAec.Licensing.Lite` `PackageReference`, per-year `bin\`/`obj\` isolation. Header comment documents the build commands — keep it in sync with reality. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/SamplePlugin.csproj)) |
| `src/SamplePlugin/App.cs` | `IExternalApplication`. Builds the shared ribbon: `Node.aec` tab (defensive create), panel `Sample Plugin`, button `Hello World`, local tab-dedup replica + AdWindows hooks. **Contains zero Node.aec Connector API calls** — by design. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs)) |
| `src/SamplePlugin/Commands/HelloCommand.cs` | `SamplePlugin.Commands.HelloCommand`. **The whole integration**: the `ProductSlug` constant, `Gate.Validate(ProductSlug)` as the first statement, the blocked dialog (`gate.GetMessage(language)` + `Gate.OpenConnector()` link + `Result.Cancelled`), and the licensed greeting. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/Commands/HelloCommand.cs)) |
| `src/SamplePlugin/SamplePlugin.addin` | Revit manifest with relative `<Assembly>SamplePlugin.dll</Assembly>`. Packaging copies it next to the DLL in each `Contents\<group>\` folder of `SamplePlugin.bundle`. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/SamplePlugin.addin)) |
| `scripts/release.ps1` | Release pipeline (mirrors the connector's): builds the three compatibility groups (floor years 2023 / 2025 / 2027), stages one `SamplePlugin.bundle` (`PackageContents.xml` + `Contents\<group>\`), zips it with a sha256, and compiles the single Setup.exe via `installer.iss` when ISCC.exe is present. `powershell -ExecutionPolicy Bypass -File scripts/release.ps1 -Version 0.3.0 [-Install]` (`-Version` is required and must match the csproj; `-Install` copies the bundle to `%ProgramData%\Autodesk\ApplicationPlugins\`). |
| `scripts/installer.iss` (+ `installer-after*.txt`) | Inno Setup 6 script: one Setup.exe for Revit 2023–2027, one Apps entry (`AppId` kept from the per-group installers). One checkbox per Revit year (installed years start checked, a re-run starts from the previous choice; silent: `/RevitYears=2025,2026`); copies only the checked groups' builds and writes `PackageContents.xml` in `[Code]`. Removes the old per-group installs (`Addins\<year>\SamplePlugin*`) first. Must stay plain ASCII. |
| `src/SamplePlugin/bin/`, `src/SamplePlugin/obj/` | Per-year build output (`bin\<year>\…`). Git-ignored; never edit, never commit. |
| `API.md` | The integration contract: connector surface, message taxonomy, ribbon/threading/build rules. Verified against revit-connector@7366482. Section titles are stable — cross-reference them by title. |
| `README.md` | Human-facing overview and onboarding guide. |
| `LICENSE` | MIT. |
| `.agents/skills/licensing-integrate/SKILL.md` | The canonical Node.aec licensing skill for partner plugins (see §11): new plugin from the template, existing plugin, learning from this sample. `SKILL.md` stays concise; depth lives in `references/licensing-gate.md` (gate walkthrough), `references/migration.md` (existing plugin) and `references/validation.md` (build + manual test script). |
| `../revit-connector/` | **Outside the repo, READ-ONLY upstream** (see §10). |

---

## 3. Golden rules

| # | Rule | Why / mechanics |
|---|---|---|
| G1 | **Validate at the entry of EVERY command.** | `Gate.Validate(ProductSlug)` is the first statement of each `IExternalCommand.Execute`. One call per execution — it does disk I/O; never in per-element loops or `DynamicUpdaters` (`API.md` §7 "Threading & Revit API-context rules"). |
| G2 | **Decide ONLY on the license boolean** (`Snapshot.IsLicensed`). | Never string-match the message. `Snapshot.Reason` (`GateReason`) may drive logs or UI tweaks, never whether the command runs (`API.md` §5 "Status / reason taxonomy"). `LicenseType`/`ProductName`/`ExpiresAt` are display-only and `null` on failure; `LicenseKey` is the user's secret — never show or log it. |
| G3 | **Never copy `NodeAec.Connector.dll` — Lite travels together.** | The Hub DLL never enters the add-in folder, `release/`, or `stage/` — the project carries no reference to it at all. The Lite assembly + its deps (`BouncyCastle.Cryptography`, net48 `System.Text.Json`/`ProtectedData`) DO ship with the plugin via `CopyLocalLockFileAssemblies=true`. Same rule family as never shipping `RevitAPI*.dll` (`API.md` §13 "Migrating an existing plugin to Lite", §14). |
| G4 | **Never create a plugin-owned ribbon tab.** | One shared `Node.aec` tab; a plugin adds its own panel (`Sample Plugin`) and button (`Hello World`) inside it (`API.md` §6 "Ribbon integration conventions"). |
| G5 | **Never call Node.aec HTTP APIs and never build login/license-manager UI.** | A plugin does local, offline validation only; the connector owns SSO, sync, heartbeat, and its UI. `ConnectorApiClient` is Hub-internal (`API.md` §1 "Overview & responsibility split", §4 "Public integration surface"). |
| G6 | **The upstream connector repo is READ-ONLY.** | `../revit-connector` (github.com/nodeaec/revit-connector): never write, never "fix" it from this repo's sessions (§10). |
| G7 | **Code wins over docs — and code changes update docs in the SAME change.** | Any change to `src/SamplePlugin/*` updates `API.md` **and** `.agents/skills/licensing-integrate/SKILL.md` **and** `README.md` together (table in §9, migration docs in `API.md` §§13–14 included). Never land a code-only or doc-only behavioral change. |
| G8 | **Never swallow an exception into "licensed".** | Catches may fail closed (blocked dialog + `Result.Cancelled`) or degrade (`OpenConnector()` → silent no-op). A `catch` that proceeds with the feature, or that returns `Result.Succeeded` on an unknown state, is forbidden. |
| G9 | **The gate's message is verbatim — and it is the whole message.** | Show `gate.GetMessage(language)` as-is (Portuguese or English, following Revit's UI language); never translate, re-word, or trim it. It already names the one specific reason and the next step, so it is the dialog's content: never surround it with a generic list of possible causes (the user cannot tell which applies and the real reason gets buried) (`API.md` §5). |

---

## 4. Canonical vocabulary

Use these exact values and names everywhere — docs, code, dialogs, commits. Never vary.

| Concept | Canonical value |
|---|---|
| Product slug (the ONE constant a plugin changes when adapting) | [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin) |
| Plugin display name | `Sample Plugin` |
| Ribbon tab (shared, owned by the connector) | `Node.aec` |
| Ribbon panel (this plugin's) | `Sample Plugin` |
| Ribbon button | `Hello World` |
| Recommended ribbon pattern | Local idempotent dedup replica + AdWindows hooks (`ApplicationInitialized`, `UIElementActivated`, `-=` before `+=`). The connector's public `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` are documented **OPTIONAL helpers** with a JIT-load tradeoff — calling them pulls `NodeAec.Connector` into your process at ribbon time. |
| Packaging | One bundle `%ProgramData%\Autodesk\ApplicationPlugins\SamplePlugin.bundle\`: `PackageContents.xml` (one component per Revit year) + `Contents\<group>\SamplePlugin.addin` with relative `<Assembly>SamplePlugin.dll</Assembly>` |
| Build | SDK-style csproj; `-p:RevitYear=2023..2027` → `net48` / `net8.0-windows` / `net10.0-windows` (default `2026`); `NodeAec.Licensing.Lite` via NuGet restore |
| `Snapshot` members | `IsLicensed`, `Reason`, `GetMessage(MessageLanguage)`, `Message` (Portuguese), `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt` — payload fields `null` on failure; **only** branch point is `IsLicensed` |
| Failure UX | `gate.GetMessage(language)` verbatim as the dialog content + `Gate.OpenConnector()` command link + `Result.Cancelled` (fail-closed, never proceed unlicensed) |
| Command class | `SamplePlugin.Commands.HelloCommand` |
| Gate call | `NodeAec.Licensing.Gate.Validate(ProductSlug)` → `Snapshot`, called directly in each command; no wrapper class (`API.md` §9, §§13–14) |

---

## 5. Build & validation commands

Reproduce these **exactly** (verbatim from `API.md` §8.1 "Versioning & compatibility
matrix" and the `SamplePlugin.csproj` header comment):

```bash
# API.md §8.1 — the canonical form (default 2026):
dotnet build -p:RevitYear=<2023..2027>

# csproj header — explicit project path, the forms the project itself documents:
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026   # default
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2023   # net48
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2027   # net10
```
Source: canonical forms documented in [SamplePlugin.csproj:L16-L18](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/SamplePlugin.csproj#L16-L18).

Year → TFM: `2023|2024` → `net48`, `2025|2026` → `net8.0-windows`, `2027` →
`net10.0-windows`. 2026 deliberately stays on `net8.0-windows` (rationale in the csproj
header and `API.md` §8.1). Outputs are isolated per year under `bin\<year>\` /
`obj\<year>\`.

**Machines without the Hub (this one included):** Lite restores from NuGet, so no
DLL path is needed — plain `dotnet build` works everywhere. A restore failure
reads `NU1101` (package/feed): the feed or the pinned version is wrong, never a
missing Hub.

**There is NO automated test suite.** Revit cannot be instantiated in this environment
and DPAPI (`ProtectedData`/`CurrentUser`) requires a real interactive logon session
(`API.md` §10 "Troubleshooting / FAQ"). Validation therefore = the build matrix above +
the **manual test protocol**, whose home is `API.md` (§3.3 packaging checklist, §10
"Troubleshooting / FAQ"), restated as an actionable checklist in
[`.agents/skills/licensing-integrate/SKILL.md`](.agents/skills/licensing-integrate/SKILL.md)
and in [`README.md`](README.md) (validate step).
Do not invent a unit-test harness that mocks the gate — its contract is
"never throws, fail closed" (tested in the Lite repository), and it is proven by build + manual run in a real Revit
session:

1. Install the connector for the target year; install the sample with its Setup.exe
   (or `scripts/release.ps1 -Version <x.y.z> -Install`).
2. Licensed run → greeting dialog with product, type and expiry (no license key), `Result.Succeeded`.
3. Unlicensed runs (no lease / wrong slug / cleared lease) → blocked dialog showing the
   gate message verbatim, in Revit's UI language, `Open Node.aec Connector...` link, `Result.Cancelled`.
4. Hub **not installed** → same blocked dialog (`NoLease`: *No Node.aec credentials…* / *Nenhuma credencial…*), link is a
   silent no-op, no crash.
5. Reload the add-in twice (Add-In Manager) → no duplicate `Node.aec` tabs/buttons (no ghost tab).
6. Confirm `release/`/`stage/` contain neither `RevitAPI*.dll`/`AdWindows.dll` nor `NodeAec.Connector.dll` — while Lite + deps travel together (`ProtectedData.dll` only on net48).

---

## 6. Coding conventions (derived from `src/SamplePlugin/*`)

**Project / language**
- `LangVersion latest`, `Nullable enable`, `ImplicitUsings enable`; still write explicit
  `using` directives at the top of each file (the sources do).
- The csproj uses the explicit `Sdk.props` / `Sdk.targets` import form so the
  Revit-year matrix evaluates before the SDK import. **Keep those imports** if you edit
  the csproj; `BaseIntermediateOutputPath` must stay that early.
- File-scoped namespaces (`namespace SamplePlugin.Commands;`). One type per file.
- Revit API references stay reference-only (`PrivateAssets="all" ExcludeAssets="runtime"`);
  dependency DLLs travel with the add-in (`CopyLocalLockFileAssemblies=true`).

**Naming & layout**
- PascalCase for types, members, and `const`s (`TabName`, `PanelName`, `ButtonId`,
  `ProductSlug`, `BlockedTitle`); camelCase for locals
  and parameters; no instance fields in these files (all logic is `static`).
- UI strings live in named `const string`s, never inline literals repeated across methods.
- Disambiguate colliding Autodesk types with a using alias when needed
  (`using RevitRibbonPanel = Autodesk.Revit.UI.RibbonPanel;` in `App.cs`).

**Documentation & comments**
- XML doc comments (`/// <summary>`) on **every public type and member** and on private
  helpers too; use `<see cref="…">`, `<param>`, `<returns>`.
- Comments explain *why*, not *what*: why the dialog shows the message alone, reload-safety
  in the ribbon hooks, "never depend on the connector at JIT time" in `App.cs`. Empty
  `catch` blocks always carry a one-line justification.
- Do not add banner comments, restated code, or changelog narration in source.

**Error handling shape**
- Command boundary: no `try/catch` around `Gate.Validate` — it never throws, and a
  catch would only add a path to get wrong. Never catch an exception into the licensed branch (G8).
- Expected exceptions are filtered: `catch (Exception ex) when (ex is
  Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)` — never a bare
  `catch` where a real error could hide.
- Ribbon helpers degrade locally (return `Result.Failed`, or skip the nicety) rather than
  throwing out of `OnStartup`; `OnStartup` has a top guard.

**Connector isolation**
- Commands use `NodeAec.Licensing` (`Gate`, `Snapshot`, `MessageLanguage`) directly; there is
  no wrapper class (`API.md` §9 "Command recipe (`HelloCommand.cs`)", §13).
- `App.cs` stays connector-free entirely (string copies of ribbon constants, no type use, zero licensing calls at startup).

---

## 7. The integration contract — summary + pointers into API.md

Cross-reference `API.md` **by these section titles** (they are stable):

| Topic | API.md section title |
|---|---|
| Who owns what: connector = SSO/sync/lease/shared tab; plugin = Lite package + one slug + gate call | §1 *Overview & responsibility split* |
| Happy-path command code (`HelloCommand` shape, two-call setup) | §2 *Quickstart (happy path)* |
| First-time Lite adoption for standalone plugins (no prior Node.aec integration): `PackageReference` Lite, gate-first commands, shared-tab ribbon, Lite traveling with the payload | §13 *Migrating an existing plugin to Lite* |
| Executable agent/CI checklist + `nodeaec-verify` SHALL | §14 *Agent / CI verification track* |
| Authoritative dependency + packaging/manifest layout | §3 *The integration path (authoritative)* |
| `Gate.Validate`, every `Snapshot` member, `GateReason`, `MessageLanguage`, `OpenConnector()`, ribbon helper visibility | §4 *Public integration surface* |
| Every `GateReason` → situation → message → handling; "one path for every row" | §5 *Status / reason taxonomy* |
| Ribbon MUST / MUST-NOT table, recommended local-replica pattern, OPTIONAL helper tradeoff | §6 *Ribbon integration conventions* |
| Call `Validate` once per command, UI-thread rules, no HTTP, no blocking I/O | §7 *Threading & Revit API-context rules* |
| `RevitYear` → TFM matrix, package pins, assembly-versioning uncertainty | §8 *Versioning & compatibility matrix* |
| The full command source and why it needs no wrapper or `try/catch` | §9 *Command recipe (`HelloCommand.cs`)* |
| Build/install failure Q&As, log location, DPAPI-in-CI caveat | §10 *Troubleshooting / FAQ* |
| Term definitions (fail-closed, master lease, ghost tab, AdWindows, …) | §11 *Glossary* |
| Verification provenance (revit-connector@7366482) and flagged uncertainties | §12 *Verification & related documents* |

Contract in one paragraph: add the `NodeAec.Licensing.Lite` package (never
copy the Hub DLL — Lite compiles in and travels with your payload), declare one `ProductSlug` constant, call `Gate.Validate(ProductSlug)` at the
entry of every command, branch only on `IsLicensed`, render `gate.GetMessage(language)` verbatim with
an `OpenConnector()` link + `Result.Cancelled` on failure, add panel `Sample Plugin`
with button `Hello World` to the shared `Node.aec` tab using the local idempotent
replica + AdWindows hooks, ship one `.bundle` whose `Contents\<group>\` manifests use a
relative `Assembly`, and build the `RevitYear` matrix.

---

## 8. Adapting the sample to a real plugin

**Step 0 — read the skill first:**
[`.agents/skills/licensing-integrate/SKILL.md`](.agents/skills/licensing-integrate/SKILL.md).
It is the authoritative workflow for this repo; this section is its summary.

Checklist (order matters):

1. **Copy the shape, not the names you must change.** Keep `App.cs`, `HelloCommand.cs`,
   the `.addin`.
2. **Change the one constant:** `HelloCommand.ProductSlug` → your catalog slug.
   Everything else about licensing stays identical.
3. **Rename identity:** assembly/root namespace, `Name` in the `.addin`, a **fresh
   `AddInId` GUID** (never reuse the sample's or the connector's), `FullClassName` → your
   `IExternalApplication`, ribbon `PanelName`/`ButtonId`/`ButtonText` (keep the shared
   `Node.aec` tab), tooltips and dialog titles.
4. **Gate every command:** `Gate.Validate(ProductSlug)` first statement; branch only
   on `IsLicensed`; failure UX = `gate.GetMessage(language)` verbatim + `Gate.OpenConnector()` link +
   `Result.Cancelled`. No exceptions swallowed into the licensed path.
5. **Ribbon:** keep the local idempotent replica + AdWindows hooks pattern; treat the
   connector's `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` as OPTIONAL (JIT-load
   tradeoff, `API.md` §6 *Ribbon integration conventions*). Filtered `ArgumentException`
   catch on `CreateRibbonTab`; `-=` before `+=` on hooks; icons via
   `BitmapCacheOption.OnLoad` + `Freeze()`.
6. **Build/packaging:** keep the `RevitYear` matrix; the Lite `PackageReference` is the
   whole dependency (nothing else to reference, copy, or wire);
   one bundle with a `Contents\<group>\` folder per group; give the scripts your own
   `PluginName`, `AppId`, `ProductCode` and `UpgradeCode` (fresh GUIDs); `release/`/`stage/`
   hold your payload + Lite, never `RevitAPI*`/`AdWindows`/Hub DLL.
7. **Validate:** build the matrix (§5), then run the manual protocol (§5) in a real Revit
   session — including the Hub-absent and add-in-reload (no ghost tab) cases.
8. **Docs:** update `API.md` + skill + `README.md` in the same change if your adaptation
   reveals a contract gap (§9).

---

## 9. Docs-sync obligations

A change to column X **must** update column Y in the same commit (rule G7):

| If you change… | Update in the SAME change |
|---|---|
| Gate usage in commands (`Gate.Validate`, message language, `OpenConnector`, license block) | `API.md` §9 *Command recipe (`HelloCommand.cs`)* + `.agents/skills/licensing-integrate/SKILL.md` + `README.md` + XML docs in the source file |
| Command control flow / failure UX (dialog shape, `Result` codes) | `API.md` §2 *Quickstart (happy path)* and §5 *Status / reason taxonomy* + skill + `README.md` |
| Ribbon pattern, panel/button names, hooks | `API.md` §6 *Ribbon integration conventions* + skill + `README.md` + constants' XML docs |
| Build matrix, TFM pins, `RevitYear` properties | `API.md` §8 *Versioning & compatibility matrix* + csproj header comment + `README.md` + skill |
| Standalone-adoption change (slug, package add, command gating, ribbon move, payload rules) | `API.md` §13 *Migrating an existing plugin to Lite* + §14 checklist + skill + `README.md` migration section |
| Packaging layout / `.addin` contents | `API.md` §3 *The integration path (authoritative)* (§3.3) + `README.md` + the `.addin` header comment |
| Canonical vocabulary (§4) | every doc that mentions it: `README.md`, `API.md`, skill, source constants/dialog text |
| Connector-verified identifiers or verbatim messages | `API.md` (and bump its revit-connector commit note in §12 *Verification & related documents*) — never edit upstream |
| Manual test protocol steps | `API.md` §10 *Troubleshooting / FAQ* + skill checklist + `README.md` validate step |
| Related-document list / file renames | `API.md` §12 *Verification & related documents* (it links `README.md`, `AGENTS.md`, the skill) |
| Source lines move (any edit that shifts line numbers in `src/…`) | every `Source:` file/line link in `README.md`, `API.md`, skill + references that points at the moved lines — re-anchor each one the same way they were created (verify the target line still holds the quoted code) |

Never let a doc describe behavior the code does not have; when docs and code disagree,
**code wins and the docs are fixed in the same change**.

---

## 10. Working with the upstream repo (read-only)

Upstream: **https://github.com/nodeaec/revit-connector**, local read-only checkout at
`../revit-connector`.

- **This repo never writes there.** Treat it as a source of truth to read and quote;
  if you find an upstream bug, report it — do not patch it from a session rooted here.
- The upstream repo has its **own** `AGENTS.md` and skills; they govern work done
  *there*, and they are useful background here:
  - **`licensing-integrate`** there is a short pointer to **this** repo's skill, which is
    the canonical one.
  - **`ribbon-guard`** — upstream ribbon/panel/tab conventions and ghost-tab cleanup.
    Background for §6 rules; the sample's `App.cs` code is what to imitate.
  - **`revit-build-validate`** — upstream build/dependency-pollution rules (never ship
    Revit binaries, clean compilation). Directly applicable when validating this repo's
    matrix.
- `API.md` §12 records the upstream commit its Hub facts were verified against.
- Never hard-code the Connector's version in plugin code; §13 says where to look it up.

---

## 11. This repo's skill and how to use it

**`.agents/skills/licensing-integrate/SKILL.md`** is the canonical Node.aec licensing skill
for partner plugins. Partners copy it into their own repos, and two other copies exist:

| Copy | What it is |
|---|---|
| `templates-revit` `content/__PluginName__/.agents/skills/licensing-integrate/` | Byte-for-byte copy that every `dotnet new nodeaec-revit-plugin` project receives |
| `revit-connector` `.agents/skills/licensing-integrate/SKILL.md` | A short pointer to this one, for agents working in the Connector |

- **Load it before any task** that touches licensing, ribbon, packaging, build, or
  adaptation of this sample. Where it and `API.md` overlap, they must agree — if you find
  a mismatch, fix both in the same change (§9).
- The skill is copied into other repos, so it must not depend on this repo's layout: link
  to this repo's files with full `https://github.com/nodeaec/revit-sample-plugin/blob/main/...`
  URLs, never relative paths outside the skill folder.
- **After changing the skill**, the template's copy must get the same change. Tell the user
  (or, when asked to, copy the folder into a `templates-revit` checkout and commit there).
- Do not create additional skills or move the skill; reference it by its exact path:
  `.agents/skills/licensing-integrate/SKILL.md`.

---

## 12. What NOT to do

- ❌ Do not let any command run without a successful gate (breaks fail-closed — §1, G1/G8).
- ❌ Do not branch on `Message` text, `LicenseType`, or any invented status/code — only
  on `IsLicensed` (G2). Do not invent `Snapshot` members that do not exist (licensee,
  plan, seats, machine id, trial flag).
- ❌ Do not copy, bundle, or side-load `NodeAec.Connector.dll`, and do not reference it
  from the project — Lite arrives via `PackageReference` and
  travels with your payload (G3). Do not ship `RevitAPI*.dll`/`AdWindows.dll`/
  `UIFramework*`.
- ❌ Do not create a second ribbon tab, a bare `catch` around `CreateRibbonTab`,
  non-idempotent panel/button insertion, or hook registration without `-=` first (G4).
- ❌ Do not add HTTP calls, cloud auth, login/license-manager UI, or blocking I/O on the
  Revit UI thread — in commands or `OnStartup` (G5).
- ❌ Do not write to `../revit-connector`, or to anything outside this repo root (G6).
- ❌ Do not land a code change without updating `API.md` + skill + `README.md` where §9
  requires it, and vice versa (G7).
- ❌ Do not translate, trim, or re-word the gate's messages, and do not wrap them
  in a generic list of possible causes — show the message, offer the `OpenConnector()`
  link, and return `Result.Cancelled` (G9, §4).
- ❌ Do not call `Gate.OpenConnector()` and depend on the window appearing
  (silent no-op by contract) — show the dialog with the message first.
- ❌ Do not show or log `Snapshot.LicenseKey`: it is the end user's secret.
- ❌ Do not treat a restore failure (`NU1101`) as a missing Hub and "fix" it with a
  loose DLL or a DLL reference — the Lite package comes from the feed (§5).
- ❌ Do not rename canonical vocabulary (§4), reuse another add-in's `AddInId`, or rename
  `API.md`/`README.md`/`AGENTS.md`/the skill path in cross-references.
- ❌ Do not leave stale `Source:` file/line links — after any `src/` edit, re-verify every
  anchor still points at the intended lines (§9).
- ❌ Do not fabricate tests or claim runtime validation that requires Revit/DPAPI — say
  what was actually built and what still needs the manual run (§5).

---

## 13. Facts that go stale, and where to check them

Versions and pins are repeated across the docs. Before you trust one, or after you change
one, check its source of truth, then find every doc that repeats it:
`grep -rn "<old value>" --include=*.md .` (and the source comments).

| Fact | Source of truth | Repeated in |
|---|---|---|
| This sample's version | `<Version>` in `src/SamplePlugin/SamplePlugin.csproj` | `README.md` and `AGENTS.md` release commands, `API.md` |
| Lite version the sample builds against | `PackageReference` in `src/SamplePlugin/SamplePlugin.csproj`; must not be newer than the Connector's ([`src/NodeAec.Connector/NodeAec.Connector.csproj`](https://github.com/nodeaec/revit-connector/blob/main/src/NodeAec.Connector/NodeAec.Connector.csproj)) | `README.md`, `API.md` §8.2 and §13, the skill, `references/licensing-gate.md` |
| Latest Lite on NuGet | <https://www.nuget.org/packages/NodeAec.Licensing.Lite> | `README.md` status note |
| `Snapshot` members, `GateReason` values and messages | [licensing-lite](https://github.com/nodeaec/licensing-lite) `src/NodeAec.Licensing.Lite/Gate.cs`, `GateReason.cs`, `GateMessages.cs` | `API.md` §4–§5, `references/licensing-gate.md` |
| Template version (and what it generates) | <https://www.nuget.org/packages/NodeAec.Templates.RevitPlugin>; `<Version>` in templates-revit `NodeAec.Templates.RevitPlugin.csproj` | `README.md` status note, `API.md` §12, the skill |
| Revit year → TFM, Revit API package pins | `TargetFramework` / `RevitApiPkgVersion` in `src/SamplePlugin/SamplePlugin.csproj` | csproj header, `API.md` §8, `README.md` |
| Hub facts quoted in `API.md` | revit-connector at the commit named in `API.md` §12 | `API.md` |
| Bundle identity (`AppId`, `ProductCode`, `UpgradeCode`) | `scripts/installer.iss` and `scripts/release.ps1` (must match; never change between versions) | `API.md` §3.3 |

