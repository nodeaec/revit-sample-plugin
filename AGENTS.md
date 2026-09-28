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
Node.aec Connector's public gate (`NodeAecGate`). It exists to be read by humans **and
by coding agents**, then copied/adapted into real commercial plugins.

**The invariant that outranks everything else: licensing is FAIL-CLOSED.**

- `SamplePlugin.Commands.HelloCommand` calls `SamplePlugin.Licensing.NodeAecLicenseGate.Validate()`
  as its **first statement**; nothing in a command executes without a verified license.
- Every non-licensed, unknown, or exceptional outcome ends in the blocked dialog and
  `Result.Cancelled`. There is no code path past the gate without a license.
- "Cannot reach the gate" (connector missing, assembly unloadable, exception anywhere)
  is **denied**, never allowed. A machine where the connector is absent must behave
  exactly like an unlicensed machine: fail-closed `GateSnapshot`, plugin-owned dialog,
  `Result.Cancelled`.

Any change that lets a command run unlicensed — silently, by catching an error into the
licensed branch, or by branching on something other than `IsLicensed` — is a defect,
regardless of how convenient it looks. Treat this as the repo's equivalent of a
security boundary.

---

## 2. Repo map

| Path | Role |
|---|---|
| `src/SamplePlugin/SamplePlugin.csproj` | SDK-style project: Revit-year matrix, the single `NodeAec.Connector` reference, `NodeAecConnectorDll` override, per-year `bin\`/`obj\` isolation. Header comment documents the build commands — keep it in sync with reality. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj)) |
| `src/SamplePlugin/App.cs` | `IExternalApplication`. Builds the shared ribbon: `Node.aec` tab (defensive create), panel `Sample Plugin`, button `Hello World`, local tab-dedup replica + AdWindows hooks. **Contains zero Node.aec Connector API calls** — by design. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs)) |
| `src/SamplePlugin/Commands/HelloCommand.cs` | `SamplePlugin.Commands.HelloCommand`. The canonical command shape: gate first, fail-closed dialog + `Result.Cancelled`, licensed greeting with `NodeAecLicenseGate.BuildLicenseBlock(gate)`. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs)) |
| `src/SamplePlugin/Licensing/NodeAecLicenseGate.cs` | **The integration seam.** `NodeAecLicenseGate.Validate()` → `GateSnapshot`, `NodeAecLicenseGate.OpenConnector()`, `NodeAecLicenseGate.BuildLicenseBlock(GateSnapshot)`, the `ProductSlug` constant, and the `GateSnapshot` type. The ONLY file in this repo allowed to reference `NodeAec.Connector` types. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs)) |
| `src/SamplePlugin/SamplePlugin.addin` | Revit manifest. Deployed to `%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin` with `<Assembly>SamplePlugin\SamplePlugin.dll`. ([source](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.addin)) |
| `src/SamplePlugin/bin/`, `src/SamplePlugin/obj/` | Per-year build output (`bin\<year>\…`). Git-ignored; never edit, never commit. |
| `API.md` | The integration contract: connector surface, message taxonomy, ribbon/threading/build rules. Verified against revit-connector@7366482. Section titles are stable — cross-reference them by title. |
| `README.md` | Human-facing overview and onboarding guide. |
| `LICENSE` | MIT. |
| `.agents/skills/nodeaec-connector-integration/SKILL.md` | This project's skill: the actionable adaptation workflow (see §11). Progressive disclosure: `SKILL.md` stays concise, depth lives in `references/licensing-seam.md` (seam walkthrough) and `references/validation.md` (build + manual test script). |
| `../revit-connector/` | **Outside the repo, READ-ONLY upstream** (see §10). |

---

## 3. Golden rules

| # | Rule | Why / mechanics |
|---|---|---|
| G1 | **Validate at the entry of EVERY command.** | `NodeAecLicenseGate.Validate()` is the first statement of each `IExternalCommand.Execute`. One call per execution — it does disk I/O; never in per-element loops or `DynamicUpdaters` (`API.md` §7 "Threading & Revit API-context rules"). |
| G2 | **Branch ONLY on the license boolean** (`GateSnapshot.IsLicensed`, backed by `GateResult.IsLicensed`). | Never string-match `Message`, never switch on a status — no enum/status code exists (`API.md` §5 "Status / reason taxonomy"). `LicenseType`/`LicenseKey`/`ProductName`/`ExpiresAt` are display-only and `null` on failure. |
| G3 | **Never copy `NodeAec.Connector.dll`.** | Not into the add-in folder, `release/`, or `stage/`. `<Private>False</Private>` is the MSBuild-level enforcement; same rule family as never shipping `RevitAPI*.dll`. Install the connector instead (`API.md` §3 "The integration path (authoritative)"). |
| G4 | **Never create a plugin-owned ribbon tab.** | One shared `Node.aec` tab; a plugin adds its own panel (`Sample Plugin`) and button (`Hello World`) inside it (`API.md` §6 "Ribbon integration conventions"). |
| G5 | **Never call Node.aec HTTP APIs and never build login/license-manager UI.** | A plugin does local, offline validation only; the connector owns SSO, sync, heartbeat, and its UI. `ConnectorApiClient` is Hub-internal (`API.md` §1 "Overview & responsibility split", §4 "Public integration surface"). |
| G6 | **The upstream connector repo is READ-ONLY.** | `../revit-connector` (github.com/nodeaec/revit-connector): never write, never "fix" it from this repo's sessions (§10). |
| G7 | **Code wins over docs — and code changes update docs in the SAME change.** | Any change to `src/SamplePlugin/*` updates `API.md` **and** `.agents/skills/nodeaec-connector-integration/SKILL.md` **and** `README.md` together (table in §9). Never land a code-only or doc-only behavioral change. |
| G8 | **Never swallow an exception into "licensed".** | Catches may fail closed (blocked dialog + `Result.Cancelled`) or degrade (`OpenConnector()` → silent no-op). A `catch` that proceeds with the feature, or that returns `Result.Succeeded` on an unknown state, is forbidden. |
| G9 | **Connector Portuguese strings are verbatim.** | Show `GateResult.Message` as-is; never translate, re-word, or trim it in code branches. English guidance is *added* around it, not substituted for it (`API.md` §5). |

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
| Packaging | `SamplePlugin.addin` at the `Addins\<year>\` **root**, relative `<Assembly>` `SamplePlugin\SamplePlugin.dll` → `Addins\<year>\SamplePlugin\SamplePlugin.dll` |
| Build | SDK-style csproj; `-p:RevitYear=2023..2027` → `net48` / `net8.0-windows` / `net10.0-windows` (default `2026`); `-p:NodeAecConnectorDll=<path>` for machines without the connector |
| `GateResult` members (exactly six) | `IsLicensed`, `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`, `Message` — payload fields `null` on failure; **only** branch point is `IsLicensed` |
| Failure UX | Connector `Message` verbatim + short guidance + `NodeAecLicenseGate.OpenConnector()` action + `Result.Cancelled` (fail-closed, never proceed unlicensed) |
| Command class | `SamplePlugin.Commands.HelloCommand` |
| Seam | `SamplePlugin.Licensing.NodeAecLicenseGate.Validate()` → `GateSnapshot`; `NodeAecLicenseGate.OpenConnector()`; `NodeAecLicenseGate.BuildLicenseBlock(GateSnapshot)` |

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
Source: canonical forms documented in [SamplePlugin.csproj:L16-L18](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj#L16-L18).

Year → TFM: `2023|2024` → `net48`, `2025|2026` → `net8.0-windows`, `2027` →
`net10.0-windows`. 2026 deliberately stays on `net8.0-windows` (rationale in the csproj
header and `API.md` §8.1). Outputs are isolated per year under `bin\<year>\` /
`obj\<year>\`.

**Connector-less machines (this one included — the connector is not installed under
`%ProgramData%\Autodesk\Revit\Addins\<year>\NodeAec.Connector\`):** the default
`HintPath` cannot resolve, so pass an explicit DLL path:

```bash
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026 -p:NodeAecConnectorDll=<path>\NodeAec.Connector.dll
```

Use this **only** to validate compilation (the csproj comment: "ONLY on CI machines that
validate compilation without the connector installed"). Expected failure modes without
it, in order:

| Symptom | Meaning | Fix |
|---|---|---|
| `MSB3245` — could not resolve reference `NodeAec.Connector` | `HintPath` target missing | Install the connector for that year, **or** pass `-p:NodeAecConnectorDll=` |
| `CS0246` (`CS0234` alongside) — type/namespace `NodeAec`/`NodeAec.Connector` not found | downstream of MSB3245, in `Licensing/NodeAecLicenseGate.cs` | same — never "fix" it by copying the DLL or by stubbing the gate |

**There is NO automated test suite.** Revit cannot be instantiated in this environment
and DPAPI (`ProtectedData`/`CurrentUser`) requires a real interactive logon session
(`API.md` §10 "Troubleshooting / FAQ"). Validation therefore = the build matrix above +
the **manual test protocol**, whose home is `API.md` (§3.3 packaging checklist, §10
"Troubleshooting / FAQ"), restated as an actionable checklist in
[`.agents/skills/nodeaec-connector-integration/SKILL.md`](.agents/skills/nodeaec-connector-integration/SKILL.md)
and in [`README.md`](README.md) (validate step).
Do not invent a unit-test harness that mocks the gate — the seam's contract is
"never throws, fail closed", and it is proven by build + manual run in a real Revit
session:

1. Install the connector for the target year; deploy `SamplePlugin.addin` +
   `SamplePlugin\SamplePlugin.dll` to `Addins\<year>\`.
2. Licensed run → greeting dialog with the `BuildLicenseBlock` fields, `Result.Succeeded`.
3. Unlicensed runs (no lease / wrong slug / cleared lease) → blocked dialog showing the
   connector `Message` verbatim, `Open Node.aec Connector...` link, `Result.Cancelled`.
4. Connector **not installed** → same blocked dialog with the seam's own English
   `ConnectorUnavailableMessage`, no crash.
5. Reload the add-in twice (Add-In Manager) → no duplicate `Node.aec` tabs/buttons.
6. Confirm `release/`/`stage/` contain neither `RevitAPI*.dll` nor `NodeAec.Connector.dll`.

---

## 6. Coding conventions (derived from `src/SamplePlugin/*`)

**Project / language**
- `LangVersion latest`, `Nullable enable`, `ImplicitUsings enable`; still write explicit
  `using` directives at the top of each file (the sources do).
- The csproj uses the explicit `Sdk.props` / `Sdk.targets` import form so the
  Revit-year matrix evaluates before the SDK import. **Keep those imports** if you edit
  the csproj; `BaseIntermediateOutputPath` must stay that early.
- File-scoped namespaces (`namespace SamplePlugin.Licensing;`). One type per file, except
  `NodeAecLicenseGate.cs` where `GateSnapshot` lives beside its producer — do not split
  them.
- Revit API references stay reference-only (`PrivateAssets="all" ExcludeAssets="runtime"`);
  dependency DLLs travel with the add-in (`CopyLocalLockFileAssemblies=true`).

**Naming & layout**
- PascalCase for types, members, and `const`s (`TabName`, `PanelName`, `ButtonId`,
  `ProductSlug`, `BlockedTitle`, `ConnectorUnavailableMessage`); camelCase for locals
  and parameters; no instance fields in these files (all logic is `static`).
- UI strings live in named `const string`s, never inline literals repeated across methods.
- Disambiguate colliding Autodesk types with a using alias when needed
  (`using RevitRibbonPanel = Autodesk.Revit.UI.RibbonPanel;` in `App.cs`).

**Documentation & comments**
- XML doc comments (`/// <summary>`) on **every public type and member** and on private
  helpers too; use `<see cref="…">`, `<param>`, `<returns>`. The public seam
  (`NodeAecLicenseGate`, `GateSnapshot`) is the documented API of this sample — its docs
  must stay accurate.
- Comments explain *why*, not *what*: JIT-isolation rationale in the seam, reload-safety
  in the ribbon hooks, "never depend on the connector at JIT time" in `App.cs`. Empty
  `catch` blocks always carry a one-line justification. Step-numbered comments
  (`// 1)`, `// 2)`, …) mark the command's control flow.
- Do not add banner comments, restated code, or changelog narration in source.

**Error handling shape**
- Command boundary: defensive `try/catch` around the gate call and around the UI
  block; every catch returns `ShowFailClosed()` → `Result.Cancelled`.
- Expected exceptions are filtered: `catch (Exception ex) when (ex is
  Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)` — never a bare
  `catch` where a real error could hide.
- Ribbon helpers degrade locally (return `Result.Failed`, or skip the nicety) instead of
  throwing out of `OnStartup`; `OnStartup` has a top guard.

**Connector isolation**
- `NodeAec.Connector` types appear **only** inside `Licensing/NodeAecLicenseGate.cs`,
  and only inside the isolated helpers (`RunValidation`, `OpenConnectorCore`) so a
  JIT-time load failure lands inside the wrapping `try`. Never let a `GateResult` (or any
  connector type) cross into a command signature, field, or expression — that would move
  the load failure outside the seam (`API.md` §9 "Fail-closed recipe (`NodeAecLicenseGate.cs`)").
- `App.cs` stays connector-free entirely (string copies of ribbon constants, no type use).

---

## 7. The integration contract — summary + pointers into API.md

Cross-reference `API.md` **by these section titles** (they are stable):

| Topic | API.md section title |
|---|---|
| Who owns what: connector = SSO/sync/gate/shared tab; plugin = reference + one slug + gate call | §1 *Overview & responsibility split* |
| Happy-path command code (`HelloCommand` shape, two-call setup) | §2 *Quickstart (happy path)* |
| The ONLY reference recipe (`Reference` + `HintPath` + `<Private>False</Private>`), JIT-load isolation, packaging/manifest layout | §3 *The integration path (authoritative)* |
| `NodeAecGate.Validate`, every `GateResult` member, `OpenConnector()`, `ConnectorLog`, secondary types, ribbon helper visibility | §4 *Public integration surface* |
| The 17 verbatim failure messages → situation → handling; "one path for every row" | §5 *Status / reason taxonomy* |
| Ribbon MUST / MUST-NOT table, recommended local-replica pattern, OPTIONAL helper tradeoff | §6 *Ribbon integration conventions* |
| Call `Validate` once per command, UI-thread rules, no HTTP, no blocking I/O | §7 *Threading & Revit API-context rules* |
| `RevitYear` → TFM matrix, package pins, assembly-versioning uncertainty | §8 *Versioning & compatibility matrix* |
| The seam source (`NodeAecLicenseGate` + `GateSnapshot`) and why the isolation boundary exists | §9 *Fail-closed recipe (`NodeAecLicenseGate.cs`)* |
| Build/install failure Q&As, log location, DPAPI-in-CI caveat | §10 *Troubleshooting / FAQ* |
| Term definitions (fail-closed, master lease, ghost tab, AdWindows, …) | §11 *Glossary* |
| Verification provenance (revit-connector@7366482) and flagged uncertainties | §12 *Verification & related documents* |

Contract in one paragraph: reference the installed connector DLL at build time (never
copy it), put the single slug constant in `NodeAecLicenseGate`, call `Validate()` at the
entry of every command, branch only on `IsLicensed`, render `Message` verbatim with
guidance + `OpenConnector()` + `Result.Cancelled` on failure, add panel `Sample Plugin`
with button `Hello World` to the shared `Node.aec` tab using the local idempotent
replica + AdWindows hooks, ship the manifest at `Addins\<year>\` root with a relative
`Assembly`, and build the `RevitYear` matrix.

---

## 8. Adapting the sample to a real plugin

**Step 0 — read the skill first:**
[`.agents/skills/nodeaec-connector-integration/SKILL.md`](.agents/skills/nodeaec-connector-integration/SKILL.md).
It is the authoritative workflow for this repo; this section is its summary.

Checklist (order matters):

1. **Copy the shape, not the names you must change.** Keep `App.cs`, `HelloCommand.cs`,
   `NodeAecLicenseGate.cs`, the `.addin`.
2. **Change the one constant:** `NodeAecLicenseGate.ProductSlug` → your catalog slug.
   Everything else about licensing stays identical.
3. **Rename identity:** assembly/root namespace, `Name` in the `.addin`, a **fresh
   `AddInId` GUID** (never reuse the sample's or the connector's), `FullClassName` → your
   `IExternalApplication`, ribbon `PanelName`/`ButtonId`/`ButtonText` (keep the shared
   `Node.aec` tab), tooltips and dialog titles.
4. **Gate every command:** `NodeAecLicenseGate.Validate()` first statement; branch only
   on `IsLicensed`; failure UX = `Message` verbatim + guidance + `OpenConnector()` +
   `Result.Cancelled`. No exceptions swallowed into the licensed path.
5. **Ribbon:** keep the local idempotent replica + AdWindows hooks pattern; treat the
   connector's `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` as OPTIONAL (JIT-load
   tradeoff, `API.md` §6 *Ribbon integration conventions*). Filtered `ArgumentException`
   catch on `CreateRibbonTab`; `-=` before `+=` on hooks; icons via
   `BitmapCacheOption.OnLoad` + `Freeze()`.
6. **Build/packaging:** keep the `RevitYear` matrix and `<Private>False</Private>`;
   manifest at `Addins\<year>\` root, DLL in your subfolder; nothing in
   `release/`/`stage/` except your payload.
7. **Validate:** build the matrix (§5), then run the manual protocol (§5) in a real Revit
   session — including the connector-absent and add-in-reload cases.
8. **Docs:** update `API.md` + skill + `README.md` in the same change if your adaptation
   reveals a contract gap (§9).

---

## 9. Docs-sync obligations

A change to column X **must** update column Y in the same commit (rule G7):

| If you change… | Update in the SAME change |
|---|---|
| Seam signatures/behavior (`Validate`, `OpenConnector`, `BuildLicenseBlock`, `GateSnapshot` members) | `API.md` §9 *Fail-closed recipe (`NodeAecLicenseGate.cs`)* + `.agents/skills/nodeaec-connector-integration/SKILL.md` + `README.md` + XML docs in the source file |
| Command control flow / failure UX (dialog shape, `Result` codes) | `API.md` §2 *Quickstart (happy path)* and §5 *Status / reason taxonomy* + skill + `README.md` |
| Ribbon pattern, panel/button names, hooks | `API.md` §6 *Ribbon integration conventions* + skill + `README.md` + constants' XML docs |
| Build matrix, TFM pins, `RevitYear`/`NodeAecConnectorDll` properties | `API.md` §8 *Versioning & compatibility matrix* + csproj header comment + `README.md` + skill |
| Packaging layout / `.addin` contents | `API.md` §3 *The integration path (authoritative)* (§3.3) + `README.md` + the `.addin` header comment |
| Canonical vocabulary (§4) | every doc that mentions it: `README.md`, `API.md`, skill, source constants/dialog text |
| Connector-verified identifiers or verbatim messages | `API.md` (and bump its revit-connector commit note in §12 *Verification & related documents*) — never edit upstream |
| Manual test protocol steps | `API.md` §10 *Troubleshooting / FAQ* + skill checklist + `README.md` validate step |
| Related-document list / file renames | `API.md` §12 *Verification & related documents* (it links `README.md`, `AGENTS.md`, the skill) |

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
  - **`licensing-integrate`** — the upstream end-to-end licensing integration recipes
    (Hub & Micro-Gate). **Known divergence:** its source-copy recipe is an incomplete
    dependency closure, and its TFM framing predates the 2023–2027 matrix; `API.md`
    §3 *The integration path (authoritative)* explicitly resolves README-vs-skill
    conflicts in favor of the build-time reference. Follow `API.md` here.
  - **`ribbon-guard`** — upstream ribbon/panel/tab conventions and ghost-tab cleanup.
    Background for §6 rules; note it references helpers that do not exist in connector
    source (see `API.md` §12) — the sample's `App.cs` code is what to
    imitate.
  - **`revit-build-validate`** — upstream build/dependency-pollution rules (never ship
    Revit binaries, clean compilation). Directly applicable when validating this repo's
    matrix.
- Upstream docs (README, `docs/licensing-api.md`, `docs/USER_MANUAL.md`) contain
  verified code-vs-doc discrepancies; `API.md` §12 records the verification commit
  (`7366482`) and the flagged uncertainties.
- Connector version referenced today: `0.1.2`; do not hard-code it in plugin code.

---

## 11. This repo's skill and how to use it

**`.agents/skills/nodeaec-connector-integration/SKILL.md`** is this project's skill.

- **Load it before any task** that touches licensing, ribbon, packaging, build, or
  adaptation of this sample. It encodes the workflow this `AGENTS.md` summarizes; where
  it and `API.md` overlap, they must agree — if you find a mismatch, fix both in the same
  change (§9).
- Use it as the checklist when asked to "add Node.aec licensing", "protect a Revit
  command", "adapt the sample", or "package the add-in".
- The upstream skills (`licensing-integrate`, `ribbon-guard`, `revit-build-validate`)
  are **background only** here; this repo's skill + `API.md` + `AGENTS.md` govern.
- Do not create additional skills or move the skill; reference it by its exact path:
  `.agents/skills/nodeaec-connector-integration/SKILL.md`.

---

## 12. What NOT to do

- ❌ Do not let any command run without a successful gate (breaks fail-closed — §1, G1/G8).
- ❌ Do not branch on `Message` text, `LicenseType`, or any invented status/code — only
  on `IsLicensed` (G2). Do not invent `GateResult` members that do not exist (licensee,
  plan, seats, machine id, trial flag).
- ❌ Do not copy, bundle, or side-load `NodeAec.Connector.dll`; do not add a NuGet
  package or `ProjectReference` for it; do not ship `RevitAPI*.dll`/`AdWindows.dll`/
  `UIFramework*` (G3).
- ❌ Do not create a second ribbon tab, a bare `catch` around `CreateRibbonTab`,
  non-idempotent panel/button insertion, or hook registration without `-=` first (G4).
- ❌ Do not add HTTP calls, cloud auth, login/license-manager UI, or blocking I/O on the
  Revit UI thread — in commands or `OnStartup` (G5).
- ❌ Do not write to `../revit-connector`, or to anything outside this repo root (G6).
- ❌ Do not land a code change without updating `API.md` + skill + `README.md` where §9
  requires it, and vice versa (G7).
- ❌ Do not translate, trim, or re-word connector `Message` strings; do not show them as
  the *only* content — add the short guidance, the `OpenConnector()` action, and return
  `Result.Cancelled` (G9, §4).
- ❌ Do not call `NodeAecLicenseGate.OpenConnector()` and depend on the window appearing
  (silent no-op by contract) — your dialog must already carry the guidance.
- ❌ Do not put `NodeAec.Connector` types in command signatures, fields, or expressions
  outside `Licensing/NodeAecLicenseGate.cs` (JIT isolation, §6).
- ❌ Do not "fix" `MSB3245`/`CS0246` by copying the DLL or stubbing the gate (§5).
- ❌ Do not rename canonical vocabulary (§4), reuse another add-in's `AddInId`, or rename
  `API.md`/`README.md`/`AGENTS.md`/the skill path in cross-references.
- ❌ Do not fabricate tests or claim runtime validation that requires Revit/DPAPI — say
  what was actually built and what still needs the manual run (§5).
