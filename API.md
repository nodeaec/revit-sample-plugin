# API.md — Node.aec Connector Integration API

Reference for plugin authors **and their coding agents**: everything the Node.aec Connector
(`NodeAec.Connector.dll`) exposes to a partner plugin, how to reference it, how to branch on
its license gate, and the Ribbon/threading/build rules that go with it.

All identifiers below were spot-checked against the connector source. Verbatim connector
strings (Portuguese) are quoted exactly — never translate or re-word them in code branches.

**Contents**

1. [Overview & responsibility split](#1-overview--responsibility-split)
2. [Quickstart (happy path)](#2-quickstart-happy-path)
3. [The integration path (authoritative)](#3-the-integration-path-authoritative)
4. [Public integration surface](#4-public-integration-surface)
5. [Status / reason taxonomy](#5-status--reason-taxonomy)
6. [Ribbon integration conventions](#6-ribbon-integration-conventions)
7. [Threading & Revit API-context rules](#7-threading--revit-api-context-rules)
8. [Versioning & compatibility matrix](#8-versioning--compatibility-matrix)
9. [Fail-closed recipe (`NodeAecLicenseGate.cs`)](#9-fail-closed-recipe-nodeaeclicensegatecs)
10. [Troubleshooting / FAQ](#10-troubleshooting--faq)
11. [Glossary](#11-glossary)
12. [Verification & related documents](#12-verification--related-documents)

---

## 1. Overview & responsibility split

The **Node.aec Connector** is the desktop governance hub: it does browser SSO (RFC 8252
loopback), syncs the signed **master entitlements lease** to
`%APPDATA%\NodeAec\entitlements.lease` (DPAPI `CurrentUser`), verifies it offline with
Ed25519, and hosts the canonical **`Node.aec`** Ribbon tab. A **partner plugin** (this
sample) never talks to the network and never stores credentials — it only *asks the gate*.

| The connector owns… | The plugin must do… |
|---|---|
| SSO login, license-key activation, lease sync/heartbeat (6 h background timer) | Reference `NodeAec.Connector.dll` at build time (§3) — never copy it |
| DPAPI storage of the lease + Ed25519 signature verification | Declare **one** product slug constant (`sample-plugin`) — the one thing to change when adapting this sample |
| The gate: `NodeAecGate.Validate(slug)` / `OpenConnector()` | Call the plugin-local seam `NodeAecLicenseGate.Validate()` at command entry and branch **only** on `IsLicensed` (§2, §9) |
| Canonical Ribbon tab `Node.aec`, its `Conector` panel, tab deduplication | Add its own **panel** (`Sample Plugin`) and button (`Hello World`) inside that shared tab — never a plugin-owned tab (§6) |
| The connector UI (account, plugins, catalog windows) | Show the returned `Message` verbatim on failure and offer to open the connector |
| Its log file `%APPDATA%\NodeAec\connector.log` | Fail closed: any inability to reach the gate ⇒ deny the feature (§9) |

**Non-goals for a plugin** (by connector design): no HTTP client, no cloud auth, no license
manager UI, no re-implementation of the gate. `NodeAec.Connector.Client.ConnectorApiClient`
is Hub-internal even though it is `public`.

---

## 2. Quickstart (happy path)

The real command is `SamplePlugin.Commands.HelloCommand`
(`src/SamplePlugin/Commands/HelloCommand.cs`); the seam it calls is
`NodeAecLicenseGate.Validate()` returning a plugin-local `GateSnapshot` (§9):

```csharp
namespace SamplePlugin.Commands;

[Transaction(TransactionMode.Manual)]
public class HelloCommand : IExternalCommand          // real class: SamplePlugin.Commands.HelloCommand
{
    public Result Execute(ExternalCommandData c, ref string msg, ElementSet set)
    {
        var gate = NodeAecLicenseGate.Validate();     // fail-closed seam → GateSnapshot (§9)
        if (!gate.IsLicensed)                         // ONLY branch point
        {
            TaskDialog.Show("Sample Plugin — License Required",
                $"Reason reported by Node.aec:\n{gate.Message}");  // verbatim connector text
            NodeAecLicenseGate.OpenConnector();       // silent no-op if absent
            return Result.Cancelled;
        }
        // … licensed feature code here …
        return Result.Succeeded;
    }
}
```

(The shipping `HelloCommand` adds a belt-and-braces `try/catch`, a null-state guard and the
`Open Node.aec Connector...` command link — see §5 for the exact dialog shape.)

Setup behind those two calls (details in §3): a build-time `<Reference>` with `HintPath` to
`$(ProgramData)\Autodesk\Revit\Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll` and
`<Private>False</Private>`, plus the constant
`public const string ProductSlug = "sample-plugin";`.

---

## 3. The integration path (authoritative)

### 3.1 The contract (bind exactly)

```xml
<ItemGroup>
  <!-- Build-time reference to the INSTALLED connector. One <year> per build (2023…2027). -->
  <Reference Include="NodeAec.Connector">
    <HintPath>$(ProgramData)\Autodesk\Revit\Addins\$(RevitYear)\NodeAec.Connector\NodeAec.Connector.dll</HintPath>
    <Private>False</Private>
  </Reference>
</ItemGroup>
```

- **NOT NuGet** — the connector repository contains no `.nuspec`/`.nupkg`; no package exists.
- **NOT a `ProjectReference`** — the connector is a separate repo/product with its own
  release cadence (`0.1.2` at the time of writing).
- **Never copy `NodeAec.Connector.dll` next to the plugin** (never into your add-in folder,
  `release/` or `stage/`). `<Private>False</Private>` is the MSBuild-level enforcement —
  same rule family as "never copy `RevitAPI*.dll`".
- `<year>` is the Revit year you build for (`RevitYear` property, default `2026`); the
  connector installs **one folder per year**, so the HintPath must match the target year (§8).
- **The sample routes the HintPath through one MSBuild property**, `NodeAecConnectorDll`,
  whose default is the canonical path above:

  ```xml
  <NodeAecConnectorDll Condition="'$(NodeAecConnectorDll)' == ''">$(ProgramData)\Autodesk\Revit\Addins\$(RevitYear)\NodeAec.Connector\NodeAec.Connector.dll</NodeAecConnectorDll>
  …
  <Reference Include="NodeAec.Connector">
    <HintPath>$(NodeAecConnectorDll)</HintPath>
    <Private>False</Private>
  </Reference>
  ```

  Override it **only** to validate compilation on a machine where the connector is not
  installed: `dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026
  -p:NodeAecConnectorDll=<path>\NodeAec.Connector.dll` (§8.1). The target must still be
  the **same year's** `NodeAec.Connector.dll`; the override is a compile-only escape
  hatch, never a license to ship a copy of the DLL.
- **Runtime resolution is automatic**: Revit loads the connector add-in at startup, so the
  plugin's reference binds to the already-loaded `NodeAec.Connector` assembly. The
  connector's own static constructor additionally registers
  `AppDomain.CurrentDomain.AssemblyResolve` (net48) and
  `AssemblyLoadContext.Default.Resolving` (.NET 8/10) hooks that probe **the connector's own
  folder** for missing dependencies (`App.cs` static ctor) — so types you touch from the
  connector (e.g. `ConnectorLog`) find `BouncyCastle.Cryptography`, `System.Text.Json`, etc.
  beside the connector DLL, not beside yours.
- **When the connector is absent**: fail closed at the **seam**, not inside the gate.
  With the DLL missing, `NodeAecGate.Validate` never runs at all — the JIT load failure
  surfaces when the first method touching a connector type executes, and
  `NodeAecLicenseGate` catches it (below) and returns a fail-closed `GateSnapshot`
  (`ConnectorAvailable == false`, text `ConnectorUnavailableMessage`).
  `NodeAecLicenseGate.OpenConnector()` degrades the same way to a silent no-op.

> **JIT nuance (code-checked against `Licensing/NodeAecLicenseGate.cs`):** with a
> *compile-time reference* and `NodeAec.Connector.dll` missing at runtime, the load failure
> does **not** occur when the plugin assembly loads — it surfaces when a method whose body
> mentions a connector type is first JIT-compiled, i.e. when `RunValidation()` (or
> `OpenConnectorCore()`) first runs. The CLR resolves `NodeAecGate` while compiling *that*
> method, so its own frame throws before executing; the exception propagates to the caller's
> `try`. `NodeAecLicenseGate` therefore isolates **every** connector-type reference behind
> wrapper methods: `Validate()` invokes `RunValidation()` *inside* its `try`, so the load
> failure lands in `Validate()`'s `catch` and becomes a normal fail-closed `GateSnapshot`
> instead of a crashing command; `OpenConnector()` wraps `OpenConnectorCore()` identically.
> When the connector **is** present but holds no lease, `NodeAecGate.Validate` runs normally
> and returns an ordinary failure `GateResult` with message #2 (`Nenhuma credencial…`, §5) —
> "assembly missing" (caught seam-side, English `ConnectorUnavailableMessage`,
> `ConnectorAvailable=false`) and "lease missing" (connector-produced Portuguese `Message`)
> are different states with different texts. What Revit itself logs/shows for the
> missing-assembly case beyond this remains **[Uncertain]** — no code in either repo
> demonstrates that UX.

### 3.2 README-vs-skill conflict — this document resolves it

The connector repository documents **two contradictory** integration strategies:

| Source | Strategy | Status |
|---|---|---|
| connector `README.md`, section *Como Integrar Plugins Parceiros com o `NodeAecGate`* | Assembly reference: `using NodeAec.Connector.Gate;` + `NodeAecGate.Validate(...)` — but it never explains **how** to obtain the reference (no HintPath recipe, no NuGet, no copy step) | Implied, incomplete |
| connector skill `.agents/skills/licensing-integrate` Recipe 2 | **Copy** `Gate/NodeAecGate.cs`, `Hardware/HardwareId.cs` and "`Cryptography/`, `Storage/`, `Models/`" into the plugin | Incomplete: the real transitive closure also needs `Config/ConnectorConfig.cs`, `Diagnostics/ConnectorLog.cs`, `Storage/SigningKeyStore.cs`, `Models/UserSessionClaims.cs` plus `BouncyCastle.Cryptography 2.7.0` and net48 `System.Text.Json`/`System.Net.Http` — as written it does not compile |

**Resolution (authoritative for this repository): use the build-time `Reference` +
`HintPath` + `<Private>False</Private>` of §3.1.** No NuGet, no project reference, no source
copy, no shipped copy of the DLL. Everything else in this document follows from that choice.

### 3.3 Packaging contract (manifest + payload layout) — verified

Proven against the connector's own packaging — `src/NodeAec.Connector/NodeAec.Connector.addin`
and `scripts/release.ps1`:

- `release.ps1:121-124` sets `$installDir = "C:\ProgramData\Autodesk\Revit\Addins\$RevitYear\NodeAec.Connector"`
  and rewrites the template manifest's `<Assembly>` to `"$installDir\$DllName"` (absolute);
  `release.ps1:166-176` copies the DLLs into `Addins\<year>\NodeAec.Connector\` and the
  `.addin` into the `Addins\<year>\` **root** (`installer.iss:211-213` writes the same layout).
- **Canonical layout: manifest at the `Addins\<year>\` root, the add-in's DLLs in a
  dedicated subfolder beside it.** The connector's `<Assembly>` ships absolute (rewritten by
  `release.ps1`); the template's original value is relative to the manifest.

The sample mirrors that layout exactly — this is the packaging contract for the plugin:

| Piece | Sample | Connector (proof) |
|---|---|---|
| Manifest location | `%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin` | `Addins\<year>\NodeAec.Connector.addin` (`release.ps1:176`) |
| `<Assembly>` value | `SamplePlugin\SamplePlugin.dll` (relative to the manifest) → `Addins\<year>\SamplePlugin\SamplePlugin.dll` | absolute `Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll` (`release.ps1:121-124`) |
| `<AddInId>` | own GUID, unique per add-in (never reuse the connector's) | fixed GUID `4B8E1A2C-…` across years |
| `<FullClassName>` | `SamplePlugin.App` (`IExternalApplication`) | `NodeAec.Connector.App` |

*Narrow caveat:* the connector repo only ever demonstrates the **absolute** `<Assembly>`
form; the sample's relative form resolves against the manifest's own directory to the
identical layout. If your packaging script rewrites `<Assembly>` to absolute (as
`release.ps1` does), keep the target the same file: `Addins\<year>\SamplePlugin\SamplePlugin.dll`.

Checklist:

1. Connector installed for the target year → `%ProgramData%\Autodesk\Revit\Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll` (written by the connector's `scripts/release.ps1` / installer).
2. Plugin `.addin` manifest at `%ProgramData%\Autodesk\Revit\Addins\<year>\` (root), plugin DLLs in the `SamplePlugin\` subfolder (table above).
3. Build the plugin with `RevitYear` = that year so the HintPath resolves.
4. `release/`/`stage/` of your plugin contains **neither** `RevitAPI*.dll` **nor** `NodeAec.Connector.dll`.

---

## 4. Public integration surface

### 4.1 `NodeAecGate.Validate(string productSlug)`

```csharp
namespace NodeAec.Connector.Gate;

public static class NodeAecGate
{
    public static GateResult Validate(string productSlug);   // NodeAecGate.cs:65
    public static void OpenConnector();                      // NodeAecGate.cs:218
    internal static bool HasPlatformAudience(JsonElement? aud); // internal — NOT for plugins
    public class GateResult { … }                            // nested class
}
```

| Aspect | Contract |
|---|---|
| **Parameter** | `productSlug` — your product's catalog slug. Matched against the entitlement claim `slug` with `Trim()` + `OrdinalIgnoreCase`. `null`/whitespace ⇒ immediate failure (`Slug do produto não informado…`). This sample uses `"sample-plugin"`. |
| **Returns** | `NodeAecGate.GateResult` (nested class) — **no enum, no status code, no out-params**. The only boolean is `IsLicensed`; the only human string is `Message`. |
| **Never throws** | Guaranteed: everything after the initial lease read is wrapped in a top-level `catch (Exception)` that logs `ERROR … Erro inesperado na validação do gate: {ExceptionType}.` and returns `GateResult.Failure("Não foi possível verificar a licença local. Abra o Node.aec Connector para ressincronizar.")`. The pre-try part's only I/O call, `LeaseStorage.LoadMasterLease()`, swallows its own exceptions and returns `null`. (Bounded, as always, by catastrophic CLR failures — and by the assembly-load nuance of §3.1, which keeps `NodeAecGate.Validate` from ever running when the DLL is missing; the plugin-side seam turns that into a fail-closed `GateSnapshot`.) |
| **Network** | **Zero network calls.** Every call does local disk I/O (`entitlements.lease` read + DPAPI unprotect + verification-keys read), base64/JWT parse, Ed25519 verify and an in-memory entitlement scan. The `< 1ms` figure in connector docs is a documentation claim, not a measured guarantee — treat it as "cheap", and call it **once per command**, not in per-element loops. |
| **Revit API** | None — no `Document`, no `UIApplication`. Filesystem/DPAPI/crypto only. |
| **Verification order** | Ed25519 signature → `iss` (`"node-aec"`) → `scope` (`"master-lease"`) → `aud` (`node-aec-desktop`/`node-aec-plugin`) → `iat` (≤ now+300 s) → machine id (`mid`) → offline `exp` → entitlement `slug` → entitlement activity. |

### 4.2 `NodeAecGate.GateResult` — every member

Immutable; constructed only by the public factories, no setter mutates it afterwards.

| Member | C# type | Semantics | When set |
|---|---|---|---|
| `IsLicensed` | `bool` | **The only branch point.** `true` iff the slug has an active, verified entitlement on this machine. | `true` only via `Success(...)`; every `Failure` sets `false` |
| `LicenseType` | `string?` | Entitlement `type` claim — a **free string**, not an enum (`"perpetual"` is the model default; vocabulary is not documented). | `Success` only; `null` on failure |
| `LicenseKey` | `string?` | Entitlement `licenseKey` claim, e.g. `NAEC-XXXX-XXXX-XXXX-XXXX`. | `Success` only; `null` on failure |
| `ProductName` | `string?` | Display name of the entitlement (`name` claim). | `Success` only; `null` on failure |
| `ExpiresAt` | `DateTimeOffset?` | Entitlement expiry (UTC, invariant parse, `AssumeUniversal`). `null` = no expiry claim (perpetual-style). | `Success` only; `null` on failure **and** when the claim is absent/invalid |
| `Message` | `string` | Human-readable, user-ready **Portuguese** sentence. Default on success: `Licença ativa e verificada.` On failure: one of the 17 texts of §5. | Always |

Factories (the only way to build one — constructor is `private`):

```csharp
public static GateResult Success(string type, string? key, string? name, DateTimeOffset? expiresAt,
                                 string message = "Licença ativa e verificada.");
public static GateResult Failure(string message);   // payload members all null
```

**Not exposed — do not invent them:** licensee/account, plan, seat counts
(`maxActivations`/`activeActivations` exist on the internal model but never surface here),
machine id, entitlement `slug`, `status`, `granted`, trial flag, offline-grace days, lease
`exp`, correlation id, any enum/status code. If you need machine-readable reasons: no such
public API exists (open question in the connector — **uncertain** whether one will come).

### 4.3 `NodeAecGate.OpenConnector()` and deep links

```csharp
public static void OpenConnector();   // NodeAecGate.cs:218
```

- Reflects `Type.GetType("NodeAec.Connector.UI.ConnectorWindow, NodeAec.Connector")` and
  invokes its `public static void Open()` (singleton WPF window, `Show()` + `Activate()`).
- **Silent no-op contract:** the whole body is wrapped in `catch { /* Silencioso se o
  add-in do connector não estiver no mesmo processo */ }`. If the connector UI type cannot
  be resolved or the open fails, **nothing happens** — no exception, no dialog. Your plugin
  must therefore never *depend* on the window appearing (call it as a courtesy after you
  have already shown your own dialog).
- **No slug-parameterized deep link exists** — no `OpenConnector(string)`, no route to a
  specific product card. For a catalog URL use the public helper
  `NodeAec.Connector.Client.ProductLinks.BuildProductUrl(string? slug)` →
  `https://nodeaec.com.br/products/{slug}`.
- When the connector *assembly itself* is missing, calling this method hits the same
  pre-execution load nuance as `Validate` (§3.1) — route the call through the seam (§9),
  which makes it a genuine no-op in that case.

### 4.4 Diagnostics / logging (public)

`NodeAec.Connector.Diagnostics.ConnectorLog` is `public static`:

| Member | Signature / value | Notes |
|---|---|---|
| `LogFileName` | `public const string LogFileName = "connector.log";` | |
| `GetLogFilePath()` | `public static string GetLogFilePath()` | → `%APPDATA%\NodeAec\connector.log` |
| `Write(level, message)` | `public static void Write(string level, string message)` | `level` = `INFO` \| `WARN` \| `ERROR`; line format `yyyy-MM-dd'T'HH:mm:sszzz [LEVEL] message`; rotates to `connector.log.1` at 512 KB; **never throws**; `FileShare.ReadWrite\|Delete` so multiple Revit instances append safely |

- Usage rule from the connector's own class contract: log lines **must never** contain JWT
  tokens, license keys, e-mails or hardware ids — only error type + display-ready text.
- The gate already writes its own lines (`WARN Lease local rejeitado: …`,
  `WARN Machine ID indisponível: …`, `ERROR Erro inesperado na validação do gate: …`), so a
  plugin can correlate its dialog with the connector log without logging the gate itself.
- `NodeAec.Connector.Diagnostics.HeartbeatLog` is **`internal`** — not available to plugins.

### 4.5 Supporting public types (available, but secondary)

Use only if you truly need them; the happy path needs none of them.

| Type | Useful members | Caution |
|---|---|---|
| `NodeAec.Connector.Models.MasterLeasePayload` | claims `Iss`, `Sub`, `Mid`, `Scope`, `Aud`, `Iat`, `Exp`, `Entitlements`, derived `ExpiresAt`/`IssuedAt`/`IsExpired` | Read-only display material; never a license decision |
| `NodeAec.Connector.Models.EntitlementItem` | `Slug`, `Name`, `LicenseKey`, `Type`, `Status`, `Granted`, `ExpiresAt`, `MaxActivations`, `ActiveActivations`, `bool IsActive()` | `IsActive()` = `Granted && Status=="active" && (no expiry or not past)`; seat fields never reach `GateResult` |
| `NodeAec.Connector.Storage.LeaseStorage` | `LoadMasterLease()`, `GetLeaseFilePath()`, `GetBaseDirectory()`, `ClearMasterLease()`, `LoadSession()`, `ClearAll()` | `ParseJwtPayload(string)` is explicitly documented **display-only, signature NOT verified** — license decisions go through `NodeAecGate`, always |
| `NodeAec.Connector.Hardware.HardwareId` | `static bool TryGetMachineId(out string machineId, out string? reason)` | Machine fingerprint; treat as sensitive |
| `NodeAec.Connector.Cryptography.LeaseSignatureVerifier` | `TryVerify(string?, out string? reason)`, `Evaluate(…)`, `enum VerificationOutcome { Verified, NoKeysAvailable, Rejected }`, `AcceptedAlgorithm = "EdDSA"` | Redundant if you call `Validate` |
| `NodeAec.Connector.Config.ConnectorConfig` | `Version` (`"0.1.2"`), `ApiBaseUrl`, public-key SPKI fields | Read-only; never embed private keys |
| `NodeAec.Connector.Auth.LoginRequirement` | `static bool IsLoggedIn()` | Local DPAPI session read, no network |
| `NodeAec.Connector.Commands.RequiresLoginAvailability` | `IExternalCommandAvailability` → `IsCommandAvailable(…)` | Lets you grey out a Ribbon button until login |
| `NodeAec.Connector.Client.ProductLinks` | `static string BuildProductUrl(string? slug)` | Catalog deep URL |
| `NodeAec.Connector.Client.ConnectorApiClient` | sync/activate/heartbeat/deactivate | **Hub-internal — plugins must not implement or call HTTP flows** |
| `NodeAec.Connector.App` | `TabName`, `PanelName`, `DeduplicateRibbonTabs(string)`, `CleanRogueRibbonElements()` | Ribbon section §6; `GetOrCreatePanel`/`AddButtonIfMissing`/`AddStackedButtonsIfMissing` are **`private`**, `RibbonDecisions` is **`internal`** — you must replicate the logic. The two public dedup helpers are **OPTIONAL** and have a price: calling them makes your Ribbon code JIT-load `NodeAec.Connector` at startup (§6 tradeoff) — the sample's `App.cs` deliberately does **not** call them |

---

## 5. Status / reason taxonomy

There is **no status enum**. Every distinct state is a distinct Portuguese sentence from
`Validate`. Branch **only** on `IsLicensed`; on failure show `Message` verbatim (it is
already written as user guidance) — **never** string-match it to decide behavior, and never
translate it inside code. Rows marked ⟶ are the cases the brief calls out explicitly.

**How `HelloCommand` really handles this table — one path for every row.** It does *not*
branch per row: any non-licensed outcome (including the seam's own
`ConnectorUnavailableMessage`, shown when the connector assembly cannot be loaded at all)
renders the **same** fail-closed `TaskDialog` (`BlockedTitle` = `Sample Plugin — License
Required`) whose `MainInstruction` is `Sample Plugin requires an active Node.aec license.`,
whose `MainContent` starts `Reason reported by Node.aec:\n{Message}` followed by fixed
generic guidance bullets (sign in / renew / buy `'sample-plugin'` / connector missing / seat
limit / offline grace), with an `Open Node.aec Connector...` command link (→
`NodeAecLicenseGate.OpenConnector()` only on click) and `CommonButtons = Close`; the command
then returns `Result.Cancelled`. The column below is therefore *message-implied* guidance —
detail your own UI may surface — not a set of code branches.

| # | Verbatim `Message` | Situation ⟶ category | Handling & user guidance (sample: same blocked dialog + `Result.Cancelled` for every row) |
|---|---|---|---|
| 1 | `Slug do produto não informado para validação.` | Caller passed null/whitespace slug — **programming error** | Fix the caller (your `ProductSlug` constant); cannot occur in normal operation (if it does, the sample still shows it verbatim in the blocked dialog + `Result.Cancelled`) |
| 2 | `Nenhuma credencial do Node.aec encontrada nesta estação. Abra o Node.aec Connector na Ribbon para entrar com sua conta ou ativar sua licença.` | ⟶ **Not authenticated** (never logged in, logged out, lease file cleared) **AND ALSO the "connector not installed / lease never written" case** — the gate only reads the file; it cannot distinguish "connector absent" from "never authenticated". **SAY SO to users only as the message itself does**; if you must distinguish, the §9 seam reports `ConnectorAvailable = false` with its own `ConnectorUnavailableMessage` when the assembly itself is missing | Show `Message` in the blocked dialog; offer `Open Node.aec Connector...` → `OpenConnector()`; `Result.Cancelled` |
| 3 | `Concessão corrompida ou estrutura inválida. Abra o Node.aec Connector para ressincronizar.` | JWT payload unparsable | Cancel + show + offer `OpenConnector()` (resync) |
| 4 | `A licença local não passou na verificação de segurança. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | Ed25519 signature verification failed (tampered/forged/wrong key); gate logs `WARN` | Cancel; tell user to go online and update in the connector |
| 5 | `Origem da licença local desconhecida. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `iss` ≠ `"node-aec"` | Cancel; go online → update |
| 6 | `A licença local está em formato não suportado. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `scope` ≠ `"master-lease"` (foreign/single-product lease) | Cancel; go online → update |
| 7 | `A licença local não foi emitida para este add-in. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `aud` missing or not a platform audience | Cancel; go online → update |
| 8 | `A data da licença local é inválida. Confira a data e hora deste computador e tente novamente.` | `iat` more than 300 s in the future (clock skew/tampering) | Cancel; ask user to fix the system clock |
| 9 | `Não foi possível identificar esta máquina (MachineGuid do Windows indisponível). Contate o suporte Node.aec.` | Windows machine id unavailable; gate logs `WARN` | Cancel; contact support |
| 10 | ⟶ `A concessão de licenças foi emitida para outra estação de trabalho (Hardware ID divergente).` | **Machine mismatch** — lease bound to another PC | Cancel; user must activate/log in on this machine |
| 11 | ⟶ `O prazo de tolerância offline expirou em {dd/MM/yyyy}. Conecte-se à internet para sincronizar.` | **Offline grace** (tolerância offline, default 30 days) expired — `exp` in the past | Cancel; tell user to connect and sync (connector "Atualizar") |
| 12 | `O prazo da licença local não pôde ser lido. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `exp` unreadable/out of plausible range | Cancel; go online → update |
| 13 | ⟶ `O produto '{productSlug}' não consta nas licenças ativas desta conta. Adquira ou ative no catálogo Node.aec.` | **Missing entitlement** — account has no lease entry for this slug (wrong product, not purchased, or slug mismatch) | Blocked dialog + `Result.Cancelled`; the sample's guidance bullet calls out `'revit-sample-plugin'` — optionally add a catalog link via `ProductLinks.BuildProductUrl(slug)` |
| 14 | ⟶ `O limite de computadores simultâneos para '{Name}' foi atingido.` | **Seat limit** — entitlement `status == "seat_limit_reached"` | Cancel; user frees a seat in the web portal, then revalidates |
| 15 | ⟶ `A licença ou período de teste de '{Name}' expirou em {dd/MM/yyyy}.` | **Expired license or trial** — `expiresAt` in the past. Note: there is **no trial claim** anywhere; "período de teste" is wording only — a trial is just an entitlement that expires | Cancel; user renews in the portal |
| 16 | `A licença de '{Name}' está com status '{Status}'.` | Any other inactive status, or `granted:false`. **Quirk (verified):** if `granted` is `false` while `status` stays `"active"` and unexpired, the text reads `… está com status 'active'.` — confusing but verbatim | Show as-is in the blocked dialog (the status string is echoed verbatim); surface it to support if needed |
| 17 | `Não foi possível verificar a licença local. Abra o Node.aec Connector para ressincronizar.` | Unexpected exception inside the gate (logged `ERROR`) | Cancel; offer `OpenConnector()` (resync) |
| ✔ | `Licença ativa e verificada.` | Success (default text) | Proceed: `HelloCommand` greets the user and renders `NodeAecLicenseGate.BuildLicenseBlock(gate)` (Product / Type / key / expiry / status from `GateResult`), then returns `Result.Succeeded` |

Notes:

- **Not authenticated vs connector-not-installed share message #2** (see row 2) — the gate
  reads only the lease file, so a machine without the connector looks identical to a machine
  where nobody ever logged in. Distinguish only if you need to (the §9 seam returns its
  own `ConnectorUnavailableMessage` with `ConnectorAvailable = false` when the assembly
  itself is missing — `NodeAecLicenseGate.Validate` never reaches `NodeAecGate` in that
  case).
- **Offline is not a failure**: `Validate` never touches the network, so being offline looks
  exactly like being online; validity is bounded only by the lease's `exp` (row 11).
- Hub-side API error codes (`LICENSE_EXPIRED`, `MACHINE_MISMATCH`, `ACTIVATION_LIMIT_REACHED`,
  …) belong to the connector's internal HTTP client and are **not reachable through the
  gate** — ignore them for plugin design.

---

## 6. Ribbon integration conventions

Canonical constants (connector `App.cs`): `App.TabName = "Node.aec"`, `App.PanelName =
"Conector"`. The sample adds panel **`Sample Plugin`** with button **`Hello World`** inside
the shared tab.

**RECOMMENDED partner pattern (exactly what `src/SamplePlugin/App.cs` does):** keep your
`IExternalApplication` **free of every Node.aec Connector API call**. Build the shared tab
locally (filtered `ArgumentException` catch), replicate the idempotent panel/button
insertion, replicate the tab-dedup algorithm, and register the two AdWindows hooks against
your own static handler. Reasons, all code-visible in `App.cs`: (a) the Ribbon must come up
even when the connector is missing, so startup must not JIT-load `NodeAec.Connector`;
(b) the connector's idempotency helpers are `private`/`internal` anyway, so you are already
replicating that half; (c) the only connector surface of the sample stays in the licensing
seam (§9).

**OPTIONAL helpers, explicit tradeoff:** `NodeAec.Connector.App.DeduplicateRibbonTabs(string)`
and `NodeAec.Connector.App.CleanRogueRibbonElements()` *are* `public static` and wrap their
bodies in `catch { }`. You **may** call them instead of replicating — convenience (always
the connector's exact algorithm, ~40 fewer lines) **vs** forcing the `NodeAec.Connector`
assembly to load and JIT in your process the first time your handler runs, i.e. your Ribbon
layer hard-depends on the connector being installed — the dependency the sample's `App.cs`
deliberately avoids. They are also *public but not documented as partner API*
(**[Uncertain]** support). Recommendation: replicate locally; treat the helpers as a
belt-and-braces fallback if you already accept the load dependency.

### MUST / MUST-NOT rules

| Rule | Mechanics |
|---|---|
| **MUST** use the single shared tab `Node.aec` | Connector creates it in `Initialize` via `application.CreateRibbonTab(TabName)`; you create it only defensively (below) |
| **MUST NOT** create a plugin-owned tab | No second tab per plugin — ever. Panel thematically inside `Node.aec` instead |
| **MUST** catch tab-creation failure with a **filtered** exception | `catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException \|\| ex is ArgumentException)` — "tab already exists" is the *only* expected failure; a bare `catch {}` masks real errors (the connector itself explicitly rejects bare catches) |
| **MUST** insert panel/button **idempotently** | Panel: `GetRibbonPanels(tab).FirstOrDefault(p => p.Name == panelName OrdinalIgnoreCase) ?? CreateRibbonPanel(tab, panelName)`. Button: scan `panel.GetItems()` by `Name` before `AddItem`. Revit add-in reloads (Add-In Manager) otherwise throw `ArgumentException` or duplicate buttons. The connector's helpers doing this are **`private`** (`GetOrCreatePanel`, `AddButtonIfMissing`, `AddStackedButtonsIfMissing`) and `RibbonDecisions` is **`internal`** — **you must replicate the logic**, you cannot call them |
| **MUST** register AdWindows dedup hooks | `ControlledApplication.ApplicationInitialized` and `ComponentManager.UIElementActivated`, each with `-=` **before** `+=` on the named static handler so reloaded add-ins don't stack delegates. Handlers re-run **your local** dedup (replicated algorithm below): merge ghost/duplicate `Node.aec` tabs (keep first, move missing panels, set `duplicateTab.IsVisible = false` and remove it) — connector-free, per the recommended pattern. Stripping legacy `License`/`Licensing` rogue tabs is the connector's `CleanRogueRibbonElements()` job: its own hooks already do it, replicating/calling it is optional (next row) |
| **MAY** (OPTIONAL) call the connector's public dedup helpers | `NodeAec.Connector.App.DeduplicateRibbonTabs(string targetTitle)` / `NodeAec.Connector.App.CleanRogueRibbonElements()` are `public static` and swallow their own errors, **but calling them loads `NodeAec.Connector` into your process at Ribbon time** (JIT) — convenience vs connector-free startup, see the tradeoff above. **[Uncertain]** public-but-undocumented partner API; the sample's `App.cs` does **not** call them |
| **MUST NOT** rely on `RibbonDecisions` / private helpers | `internal`/`private` — invisible outside the connector assembly |
| **MUST** load icons with `BitmapCacheOption.OnLoad` + `Freeze()` | Otherwise Revit keeps the PNG file locked; mirror `App.LoadButtonIcons` (`UriKind.Absolute`, `CacheOption = OnLoad`, `Freeze()`) |
| **MUST** keep `OnStartup` non-blocking | No network, no heavy I/O on the Ribbon thread; wrap everything in a top guard returning `Result.Failed` rather than letting exceptions escape half-built |
| **MUST NOT** produce ghost tabs/panels | Duplicate tabs come from add-in reloads; the hooks above are the sanctioned fix, not manual `Tabs.Remove` calls outside `try/catch` |

### Minimal sketch (panel `Sample Plugin`, button `Hello World`) — mirrors `src/SamplePlugin/App.cs`

```csharp
// Requires: using Autodesk.Windows;   (AdWindows — ComponentManager)
// RECOMMENDED pattern: NO Node.aec Connector API calls anywhere in this class, so the
// Ribbon comes up even when the connector is missing and startup never JIT-loads it.
// The only connector surface of the sample is the licensing seam (§9).
public class App : IExternalApplication
{
    // Shared canonical tab — THE tab. Never a plugin-owned one.
    public const string TabName = "Node.aec";   // string copy of the convention; no type use
    public const string PanelName = "Sample Plugin";
    public const string ButtonId = "SamplePlugin_HelloWorld";
    public const string ButtonText = "Hello World";

    public Result OnStartup(UIControlledApplication application)
    {
        try
        {
            // 1. Create the shared tab; "already exists" is the only expected failure.
            try { application.CreateRibbonTab(TabName); }
            catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException
                                    || ex is ArgumentException)
            { /* connector already created it — normal */ }

            DeduplicateTab();   // App.cs runs the local dedup right after EnsureTab, too

            // 2. Idempotent panel acquisition (connector's GetOrCreatePanel is private).
            var panel = application.GetRibbonPanels(TabName)
                .FirstOrDefault(p => string.Equals(p.Name, PanelName, StringComparison.OrdinalIgnoreCase))
                ?? application.CreateRibbonPanel(TabName, PanelName);

            // 3. Idempotent button insertion (connector's AddButtonIfMissing is private).
            if (!panel.GetItems().Any(i => string.Equals(i.Name, ButtonId, StringComparison.OrdinalIgnoreCase)))
            {
                var btn = new PushButtonData(ButtonId, ButtonText,
                        typeof(App).Assembly.Location,
                        "SamplePlugin.Commands.HelloCommand")     // real command class name
                { ToolTip = "Sample Plugin: greets the user and shows the Node.aec license backing this command." };
                panel.AddItem(btn);   // icons: BitmapCacheOption.OnLoad + Freeze()
            }

            // 4. AdWindows dedup hooks — "-=" before "+=" so reloads don't stack delegates.
            application.ControlledApplication.ApplicationInitialized -= OnApplicationInitialized;
            application.ControlledApplication.ApplicationInitialized += OnApplicationInitialized;
            ComponentManager.UIElementActivated -= OnUiElementActivated;
            ComponentManager.UIElementActivated += OnUiElementActivated;

            return Result.Succeeded;
        }
        catch (Exception) { return Result.Failed; }   // never leave a half-built ribbon
    }

    private static void OnApplicationInitialized(object? s, EventArgs e) => DeduplicateTab();
    private static void OnUiElementActivated(object? s, EventArgs e) => DeduplicateTab();

    // Local replica of the connector's App.DeduplicateRibbonTabs("Node.aec") — NOT a call
    // to it (calling the connector helper would load NodeAec.Connector here; tradeoff above).
    // Same algorithm as src/SamplePlugin/App.cs DeduplicateTab():
    private static void DeduplicateTab()
    {
        try
        {
            var ribbon = ComponentManager.Ribbon;
            var matches = ribbon?.Tabs
                .Where(t => string.Equals(t.Title, TabName, StringComparison.OrdinalIgnoreCase)
                         || string.Equals(t.Id, TabName, StringComparison.OrdinalIgnoreCase))
                .ToList();
            if (matches is null || matches.Count <= 1) return;      // one tab — nothing to do

            var primary = matches[0];
            for (int i = 1; i < matches.Count; i++)
            {
                var dup = matches[i];
                foreach (var p in dup.Panels.ToList())
                {
                    dup.Panels.Remove(p);
                    bool already = primary.Panels.Any(q =>
                        string.Equals(q.Source?.Title, p.Source?.Title, StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(q.Source?.Id, p.Source?.Id, StringComparison.OrdinalIgnoreCase));
                    if (!already) primary.Panels.Add(p);            // move, don't drop panels
                }
                dup.IsVisible = false;
                ribbon.Tabs.Remove(dup);
            }
        }
        catch (Exception) { /* dedup must never throw into Revit's event pipeline */ }
    }

    public Result OnShutdown(UIControlledApplication application)
    {
        // Unhook both delegates ("-=") so a reload never stacks handlers; always succeeds.
        application.ControlledApplication.ApplicationInitialized -= OnApplicationInitialized;
        ComponentManager.UIElementActivated -= OnUiElementActivated;
        return Result.Succeeded;
    }
}
```

Optional alternative to `DeduplicateTab()`, **only if you accept the load dependency**:
`NodeAec.Connector.App.DeduplicateRibbonTabs(TabName); NodeAec.Connector.App.CleanRogueRibbonElements();`
— same semantics, but the connector assembly must load in your process (tradeoff above).

---

## 7. Threading & Revit API-context rules

- **Call `Validate` from `IExternalCommand.Execute`** (the external-command context). The
  gate touches only filesystem, DPAPI, JSON and crypto — **no Revit API**, no network — so
  it is legal there and needs no `Transaction`.
- **Call it once per command execution**, at entry (first statement). It performs disk I/O
  on every call; caching the snapshot for the duration of one command is fine. Never
  call it inside per-element loops or `DynamicUpdaters`.
- **Never block the Revit UI thread with network or heavy I/O** (connector `AGENTS.md`
  rule). `Validate` itself is network-free; anything *you* add (HTTP, big file scans) must
  go to a background task — and never call the Revit API off the UI thread.
- **No HTTP in commands or add-in startup** (skill invariant): plugins do not talk to the
  Node.aec API at all — the connector's 6-hour background heartbeat owns that.
- **`OpenConnector()` → run on the UI thread**, i.e. inside `Execute` right after your
  dialog. It opens a WPF window (`Show()`/`Activate()`). Calling it from a background thread
  is **[Uncertain/GUESS]** — the connector has no guard and never tests it.
- **Off-UI-thread `Validate`**: **[Uncertain/GUESS]** — DPAPI/file reads look thread-safe
  (writes are `WriteLock`-serialized, hardware id is cached), but nothing in the connector
  asserts or tests concurrent use. Stick to the command context.
- **Ribbon construction only in `OnStartup`** (§6); `IExternalCommandAvailability`
  callbacks (`RequiresLoginAvailability` pattern) must stay local-only — reading the DPAPI
  session file is explicitly documented as safe for frequent Ribbon calls.
- **`ConnectorLog.Write`** is lock-protected and never throws — safe from any thread.

---

## 8. Versioning & compatibility matrix

### 8.1 Revit year → target framework

Build with `dotnet build -p:RevitYear=<2023..2027>` (default `2026`); the year defines the
`REVIT2023`…`REVIT2027` compilation constant and isolates `obj\<year>\`/`bin\<year>\`.
The connector reference resolves through the `NodeAecConnectorDll` property (§3.1):
default `%ProgramData%\Autodesk\Revit\Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll`,
overridable per build with `-p:NodeAecConnectorDll=<path>` on machines where the
connector is not installed.

| `RevitYear` | Target framework | Nice3point Revit API pkg | DPAPI package (`DpapiPkgVersion`) | `System.Security.Cryptography.ProtectedData.dll` in payload? |
|---|---|---|---|---|
| 2023 | `net48` | `2023.1.90` | `4.7.0` | **Yes** — only the NuGet package provides it on net48 |
| 2024 | `net48` | `2024.3.60` | `4.7.0` | **Yes** |
| 2025 | `net8.0-windows` | `2025.4.60` | `8.0.0` | **No** — ships inside `Microsoft.WindowsDesktop.App`; do not copy it to the add-in folder (must not appear in `release/`/`stage/`) |
| 2026 | `net8.0-windows` | `2026.4.10` | `8.0.0` | **No** |
| 2027 | `net10.0-windows` | `2027.2.0` | *(unset — package not referenced, NuGet prunes it / NU1510)* | **No** |

Notes:

- **2026 deliberately stays `net8.0-windows`** even though Revit 2026.5 runs on .NET 10:
  no net10 reference package exists for 2026, and compatibility only flows one way (a net8
  add-in loads in the net10 host; the reverse fails).
- Revit API references must always be non-copying (`PrivateAssets="all"`
  `ExcludeAssets="runtime"`, or `<Private>False</Private>`) — **never** ship
  `RevitAPI*.dll`/`AdWindows.dll`/`UIFramework*`.
- net48-only extras if you build anything resembling the connector: `System.Text.Json
  8.0.5` + explicit `<Reference Include="System.Net.Http" />`.
- Your `HintPath` must point at the **same year's** connector folder (§3.1), and your
  `.addin` manifests deploy per year under `%ProgramData%\Autodesk\Revit\Addins\<year>\`.

### 8.2 Assembly versioning

- Connector assembly: `NodeAec.Connector`, `<Version>0.1.2</Version>` (⇒ assembly version
  `0.1.2.0` under SDK defaults), `RootNamespace NodeAec.Connector`.
- **[Uncertain — open question in the connector]** There is **no documented API-stability
  policy, no SemVer guarantee and no binding-redirect guidance** for consumers. Practical
  rules: compile against the connector version you target; rebuild your plugin when the
  connector updates; don't hard-code `0.1.2`; treat all surface documented in §4 as
  "latest verified" (verified against `7366482`) rather than frozen. Binding redirects on
  `net48` (Revit 2023/2024) if versions diverge: **[Uncertain]** not demonstrated anywhere
  in the connector repo.
- Because you never copy the DLL (§3), version skew manifests as the runtime resolving to
  whatever Revit already loaded — another reason to keep to the documented surface.

---

## 9. Fail-closed recipe (`NodeAecLicenseGate.cs`)

Consistent with the sample's `src/SamplePlugin/Licensing/NodeAecLicenseGate.cs`: **one
product slug constant** (the one thing to change when adapting this sample) and a seam that
*cannot* crash the command — `Validate()` returns a plugin-local `GateSnapshot` and never
throws, including on a machine where the connector isn't installed.

```csharp
using NodeAec.Connector.Gate;

namespace SamplePlugin.Licensing;

/// <summary>Fail-closed seam over the Node.aec gate for this plugin.</summary>
public static class NodeAecLicenseGate
{
    /// <summary>THE one constant to change when adapting this sample.</summary>
    public const string ProductSlug = "revit-sample-plugin";

    /// <summary>Reason when the connector assembly cannot be reached at all (§3.1).</summary>
    public const string ConnectorUnavailableMessage =
        "The Node.aec Connector could not be loaded on this station. " +
        "Install or repair the Node.aec Connector, then open it and try again.";

    /// <summary>Validates ProductSlug. Never throws — missing connector included.</summary>
    public static GateSnapshot Validate()
    {
        try
        {
            // Isolated helper: a JIT-time load failure of NodeAec.Connector surfaces
            // HERE, inside this try, instead of before any of this code runs (§3.1).
            return RunValidation();
        }
        catch (Exception)
        {
            return new GateSnapshot(
                isLicensed: false,
                message: ConnectorUnavailableMessage,
                productName: null,
                licenseType: null,
                licenseKey: null,
                expiresAt: null,
                connectorAvailable: false);
        }
    }

    /// <summary>The single place where the connector's GateResult is read (6 members only).</summary>
    private static GateSnapshot RunValidation()
    {
        NodeAecGate.GateResult result = NodeAecGate.Validate(ProductSlug);

        return new GateSnapshot(
            isLicensed: result.IsLicensed,
            message: result.Message,
            productName: result.ProductName,
            licenseType: result.LicenseType,
            licenseKey: result.LicenseKey,
            expiresAt: result.ExpiresAt,
            connectorAvailable: true);
    }

    /// <summary>Courtesy deep link; genuine silent no-op when the connector is absent.</summary>
    public static void OpenConnector()
    {
        try { OpenConnectorCore(); }
        catch (Exception) { /* nothing to open */ }
    }

    /// <summary>Isolated call target so the load failure of the connector stays catchable.</summary>
    private static void OpenConnectorCore() => NodeAecGate.OpenConnector();

    // Also in the real file: public static string BuildLicenseBlock(GateSnapshot) and
    // private static string FormatExpiry(DateTimeOffset?) — they render the licensed
    // dialog from the snapshot (connector-free, no catch needed).
}

/// <summary>Plain, connector-free view of one gate outcome: strings and dates only.</summary>
public sealed class GateSnapshot
{
    public GateSnapshot(bool isLicensed, string message,
                        string? productName, string? licenseType, string? licenseKey,
                        DateTimeOffset? expiresAt, bool connectorAvailable)
    {
        IsLicensed = isLicensed; Message = message; ProductName = productName;
        LicenseType = licenseType; LicenseKey = licenseKey; ExpiresAt = expiresAt;
        ConnectorAvailable = connectorAvailable;
    }

    public bool IsLicensed { get; }             // the ONLY branch point
    public string Message { get; }              // connector text, verbatim (or the seam's own English text)
    public string? ProductName { get; }         // null on failure
    public string? LicenseType { get; }         // null on failure
    public string? LicenseKey { get; }          // null on failure
    public DateTimeOffset? ExpiresAt { get; }   // null on failure and when the claim is absent
    public bool ConnectorAvailable { get; }     // false ⇒ assembly missing (fail-closed state)
}
```

Why the isolation boundary: the CLR JIT resolves `NodeAecGate` while compiling a method
that mentions it — if the DLL is missing, that resolution fails when the method first
runs, and the throw lands **at its call site**, i.e. inside `Validate()`'s (or
`OpenConnector()`'s) `try`; `RunValidation()`'s own frame cannot catch it (and a
`GateResult` in a plugin signature would poison the caller too). So every method touching
connector types (`RunValidation`, `OpenConnectorCore`) sits behind the boundary where
`Validate()`/`OpenConnector()` invoke it *inside* their `try` — the load failure then
lands in the catch and becomes a normal fail-closed `GateSnapshot`
(`ConnectorAvailable = false`, `ConnectorUnavailableMessage`) / silent no-op. When the
connector **is** installed (the normal case), `NodeAecGate.Validate`'s own never-throws
guarantee applies and returns one of the §5 messages (no lease → message #2);
`OpenConnector()` then either opens the window or silently no-ops.

Command usage (only plugin-local types — see §2 for the full happy path; the shipping
`SamplePlugin.Commands.HelloCommand` adds the belt-and-braces `try/catch`, the null guard
and the `Open Node.aec Connector...` command link that calls `OpenConnector()` on click):

```csharp
var gate = NodeAecLicenseGate.Validate();      // GateSnapshot — plugin-local, never throws
if (!gate.IsLicensed)
{
    TaskDialog.Show("Sample Plugin — License Required",
        $"Reason reported by Node.aec:\n{gate.Message}");
    NodeAecLicenseGate.OpenConnector();
    return Result.Cancelled;
}
```

---

## 10. Troubleshooting / FAQ

**Q: My plugin fails to load right after adding the reference.**
HintPath year mismatch or connector not installed for that year. Verify
`%ProgramData%\Autodesk\Revit\Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll`
exists and that you build with the same `-p:RevitYear`. Remember: you must **not** copy the
DLL into your add-in folder as a "fix" — install the connector instead.

**Q: Nothing happens when the user clicks my "open connector" link.**
By contract `OpenConnector()` is a silent no-op when the connector UI can't be reached
(assembly absent, window open failure). Your own dialog must already carry the guidance —
never rely on the window appearing.

**Q: The user says "I have a license" but the command cancels with
`Nenhuma credencial do Node.aec encontrada nesta estação…`.**
This single message covers **not authenticated and connector-not-installed** (§5 row 2).
Check that the connector is installed for this Revit year, then have the user log in /
activate a key in the connector and re-run.

**Q: `O produto 'sample-plugin' não consta nas licenças ativas desta conta…`.**
Entitlement missing for the slug — either not purchased/activated, or your `ProductSlug`
doesn't match the catalog slug (matching is `Trim()` + case-insensitive). Point the user at
the catalog: `ProductLinks.BuildProductUrl(slug)`.

**Q: Can I branch on the message text (e.g. `Contains("expirou")`)?**
No. Messages are free-form Portuguese that may change between connector versions. The only
stable branch point is `IsLicensed`; show `Message` verbatim.

**Q: Two `Node.aec` tabs after reloading my add-in (Add-In Manager).**
Ghost/duplicate tabs — your insertion wasn't idempotent or your AdWindows hooks are
missing/mis-registered. Re-read §6: filtered `ArgumentException` catch, acquire-or-create
panel, `ContainsName`-style button check, `-=` before `+=` on `ApplicationInitialized` and
`ComponentManager.UIElementActivated`, and a local (connector-free) `DeduplicateTab()`
handler as in `src/SamplePlugin/App.cs`.

**Q: Is `< 1ms` a guarantee?**
No — it's a documentation claim. `Validate` does disk I/O (lease read + DPAPI + key read)
on **every** call. Zero network, yes; "pure CPU", no. Call it once per command.

**Q: DPAPI fails (`Access denied`, win32 5) in CI/SSH/headless contexts.**
Expected: `ProtectedData … CurrentUser` needs a real interactive logon session (Session ≥ 1;
fail-closed by design otherwise). Validate license persistence manually inside a real Revit
session; don't weaken storage or skip tests to work around it.

**Q: May I ship `NodeAecGate` source in my plugin instead of referencing the DLL?**
Not in this repository — §3.2 rejects the source-copy path (incomplete dependency closure,
maintenance burden, divergent versions). Exactly one integration path is authoritative here.

**Q: Where do I see what happened when a validation fails?**
`%APPDATA%\NodeAec\connector.log` (`ConnectorLog.GetLogFilePath()`) — the gate logs
`WARN`/`ERROR` lines with exception types only (never tokens, keys or machine ids).

---

## 11. Glossary

| Term | Meaning |
|---|---|
| **Connector** | `NodeAec.Connector` — Node.aec desktop governance add-in: auth, lease sync, gate, canonical Ribbon tab |
| **Gate** | `NodeAecGate` — the local, offline, fail-closed validation entry point |
| **`GateResult`** | Immutable result of `Validate`; 6 members; only `IsLicensed` branches |
| **`GateSnapshot`** | Plugin-local, connector-free mirror of one gate outcome, returned by `NodeAecLicenseGate.Validate()`; 6 `GateResult` members + `ConnectorAvailable` (`false` = connector assembly missing) |
| **Master lease** | Signed JWT (`scope: master-lease`) stored DPAPI-encrypted at `%APPDATA%\NodeAec\entitlements.lease`; claims `iss/sub/mid/scope/aud/iat/exp/entitlements` |
| **Entitlement** | One product grant inside the lease (`slug`, `name`, `licenseKey`, `type`, `status`, `granted`, `expiresAt`, seat counts) |
| **Slug** | Product identifier matched by `Validate` (here: `revit-sample-plugin`) |
| **Offline grace (tolerância offline)** | Lease `exp` window (default 30 days) during which validation works without network; expired ⇒ taxonomy #11 |
| **Seat (posto)** | One activated computer; `seat_limit_reached` ⇒ taxonomy #14; counts never surface in `GateResult` |
| **Machine mismatch** | `mid` claim ≠ this machine's SHA-256 `MachineGuid` ⇒ taxonomy #10 |
| **DPAPI** | Windows Data Protection API, `DataProtectionScope.CurrentUser`; protects lease/session files |
| **Ed25519 / SPKI** | Signature algorithm (RFC 8032) verifying the lease; only the compiled **public** key is ever shipped |
| **Fail-closed** | Any doubt ⇒ deny. No lease, bad signature, wrong machine, unreadable data ⇒ failure |
| **Deep link** | Programmatic opening of a connector window (`OpenConnector()`); no slug-parameterized variant exists |
| **Shared tab** | The single `Node.aec` Ribbon tab owned by the connector; plugins add panels only |
| **AdWindows** | `Autodesk.Windows` (AdWindows.dll) — low-level Ribbon API used for tab deduplication |
| **Ghost tab** | Duplicate/rogue Ribbon tab left by add-in reloads; removed by your local dedup (replica of `App.DeduplicateRibbonTabs`) or, optionally, the connector's `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` (§6 tradeoff) |
| **`.addin`** | Revit manifest in `%ProgramData%\Autodesk\Revit\Addins\<year>\` pointing at an assembly |
| **`RevitYear`** | MSBuild property `2023`–`2027` selecting TFM, API packages and connector folder |
| **TFM** | Target framework: `net48`, `net8.0-windows`, `net10.0-windows` per year |
| **Hub / ConnectorApiClient** | Connector's internal HTTP client + cloud API — out of bounds for plugins |

---

## 12. Verification & related documents

- **Verified against revit-connector@7366482** — every connector identifier, signature and
  verbatim message above was checked against the connector source at that commit.
- Sample-side identifiers (`App`, `HelloCommand`, `NodeAecLicenseGate.Validate()` →
  `GateSnapshot`, `SamplePlugin.addin`) are aligned with the canonical, built & validated
  contract in `src/SamplePlugin/`.
- Related documents in this repository: [`README.md`](README.md) · [`AGENTS.md`](AGENTS.md) ·
  [`.agents/skills/nodeaec-connector-integration/SKILL.md`](.agents/skills/nodeaec-connector-integration/SKILL.md)
- **Remaining uncertainties are flagged inline with [Uncertain]/GUESS**: Revit-level UX/log
  output when the connector DLL is absent (the plugin-side seam behavior itself is
  code-checked, §3.1), off-UI-thread behavior of `Validate`/`OpenConnector`
  (§7), partner support for `App.DeduplicateRibbonTabs`/`CleanRogueRibbonElements` (§6),
  assembly-version compatibility/binding-redirect policy (§8.2), and the future of a
  machine-readable failure code (§4.2).
