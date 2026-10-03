# API.md — Node.aec Connector Integration API

Reference for plugin authors **and their coding agents**: everything the Node.aec
license package (`NodeAec.Licensing.Lite`) exposes to a partner plugin, how to reference it, how to branch on
its license gate, and the Ribbon/threading/build rules that go with it.

**Who this is for:** Revit add-in authors integrating Node.aec licensing.
`Gate.Validate(productSlug)` takes one product slug string and returns one
`Snapshot`. It reads the signed lease file from disk, verifies the Ed25519
signature offline against the compiled `TrustedAnchors[]`, and performs no
network call. The result carries one boolean (`IsLicensed` — the sole branch
point) and one human-readable message (`Message`, PT-BR verbatim, shown to the
user as-is). The rest of
this document is the contract for that call, its failure messages, and the
packaging rules around it.

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
13. [Migrating an existing plugin to Lite](#13-migrating-an-existing-plugin-to-lite)
14. [Agent / CI verification track](#14-agent--ci-verification-track)

---

## 1. Overview & responsibility split

The **Node.aec Connector** is the desktop governance hub: it performs SSO via RFC 8252
loopback, syncs the signed **master entitlements lease** to
`%APPDATA%\NodeAec\entitlements.lease` (DPAPI `CurrentUser`), verifies it offline with
Ed25519, and hosts the canonical **`Node.aec`** Ribbon tab. A **partner plugin** (this
sample) never talks to the network and never stores credentials — it only *asks the gate*.

The connector owns authentication, storage, verification, and UI; the plugin
calls only the local gate. There is no API key to manage and no HTTP client to
build. You pass a product slug, you receive a `Snapshot`, and you branch on
`IsLicensed`.

| The connector owns… | The plugin must do… |
|---|---|
| SSO login, license-key activation, lease sync/heartbeat (6 h background timer) | Declare the `NodeAec.Licensing.Lite` package (§3) — it compiles into your plugin |
| DPAPI storage of the lease (Hub writes it) + Ed25519 signature verification (Lite reads it) | Declare **one** product slug constant ([`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)) — the one thing to change when adapting this sample |
| The gate: `Gate.Validate(slug)` / `OpenConnector()` (both Lite, offline) | Call the plugin-local seam `NodeAecLicenseGate.Validate()` at command entry and branch **only** on `IsLicensed` (§2, §9) |
| Canonical Ribbon tab `Node.aec`, its `Conector` panel, tab deduplication | Add its own **panel** (`Sample Plugin`) and button (`Hello World`) inside that shared tab — never a plugin-owned tab (§6) |
| The connector UI (account, plugins, catalog windows) | Show the returned `Message` verbatim on failure and offer to open the connector |
| Its log file `%APPDATA%\NodeAec\connector.log` | Fail closed: any inability to reach the gate ⇒ deny the feature (§9) |

**Non-goals for a plugin** (by connector design): no HTTP client, no cloud auth, no license
manager UI, no re-implementation of the gate. `NodeAec.Connector.Client.ConnectorApiClient`
is Hub-internal even though it is `public`.

---

## 2. Quickstart (happy path)

If you only read one section, make it this one. The whole integration is two calls:
ask the gate, honor the answer. (`SamplePlugin.Commands.HelloCommand`
in `src/SamplePlugin/Commands/HelloCommand.cs`, calling the seam
`NodeAecLicenseGate.Validate()` returning a plugin-local `GateSnapshot` — §9.)

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
Source: [HelloCommand.cs:L36-L63](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L36-L63) (simplified; the shipped command adds the dialog detail shown in §5).

(The shipping `HelloCommand` adds a defensive `try/catch`, a null-state guard and the
`Open Node.aec Connector...` command link — see §5 for the exact dialog shape.)

Setup behind those two calls (details in §3): a `PackageReference` to
`NodeAec.Licensing.Lite` plus the constant
`public const string ProductSlug = "revit-sample-plugin";`.

---

## 3. The integration path (authoritative)

How the dependency works, in one paragraph: your project declares the license
package from NuGet via `PackageReference`, the verification
code compiles *into* your DLL, and your
installer drops your own manifest + DLL per Revit year. The subsections below
are the exact MSBuild, the one integration path, and the folder layout.

### 3.1 The contract (declare exactly)

```xml
<ItemGroup>
  <!-- Offline license verification, compiled INTO this plugin.
       Resolved from NuGet via PackageReference — nothing loose to deploy. -->
  <PackageReference Include="NodeAec.Licensing.Lite" Version="1.0.0-preview.1" />
</ItemGroup>
```
Source: [SamplePlugin.csproj:L98](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj#L98) (pre-release feed: local folder `NuGet.config` → Lite `1.0.0-preview.1`; NuGet.org at release — §8.2).

- **The licensing decision compiles into your assembly.** A loose DLL with the right
  name and class could stand in for the decision (attack A in the plan), so the
  decision lives inside your plugin and ships with it.
- **Not a `ProjectReference`** — Lite is a versioned public package with its own
  release cadence (`1.0.0-preview.1` at the time of writing), not a sibling repo.
- **Never copy `NodeAec.Connector.dll` next to the plugin** (never into your add-in
  folder, `release/` or `stage/`). The only license assembly is Lite, and it travels
  *inside* your payload via `CopyLocalLockFileAssemblies=true` — same rule family as
  "never copy `RevitAPI*.dll`", inverted: Revit assemblies stay out, Lite goes in.
- **No extra MSBuild properties to set.** A machine
  without the Hub builds identically — `dotnet build` restores the Lite package
  (pre-release: local folder feed via `NuGet.config`; at release: NuGet.org —
  §8.2); the only build-time requirement is that the feed resolve. If restore
  fails (`NU1101`, package not found), the feed/version is the problem,
  never a missing Hub.
- **Runtime resolution is trivial**: Lite is already inside your DLL's folder, so
  there is nothing to bind, no `AssemblyResolve` hook to register, no per-year folder
  to match. The connector Hub may or may not be installed for that Revit year — the
  plugin loads and validates either way.
- **When the connector Hub is absent**: fail closed at the **gate**, not at load.
  `Gate.Validate` always runs (Lite is compiled in) and reads the lease file; with no
  credentials on the machine it returns the ordinary failure #2 (`Nenhuma
  credencial…`, §5) — the same message as "never signed in". There is no separate
  "assembly missing" state: a machine with no Hub simply has no lease.
  `Gate.OpenConnector()`
  degrades to a silent no-op when the Hub UI is unreachable (§4.3, §9).

### 3.2 Exactly one integration path

Authoritative for this repository: declare the `PackageReference` to
`NodeAec.Licensing.Lite` of §3.1 — that is the whole dependency. Nothing else
supplies the gate: no assembly reference to an installed DLL, no `ProjectReference`,
no vendored copy of gate source (the real transitive closure of a source copy also
needs `Config/ConnectorConfig.cs`, `Diagnostics/ConnectorLog.cs`,
`Storage/SigningKeyStore.cs`, `Models/UserSessionClaims.cs` plus
`BouncyCastle.Cryptography 2.7.0` and net48 `System.Text.Json`/`System.Net.Http`,
and hand-copied crypto diverges from the audited package), and no shipped copy of
`NodeAec.Connector.dll`. Everything else in this document follows from that choice.

### 3.3 Packaging contract (manifest + payload layout) — verified

Proven against the connector's own packaging — `src/NodeAec.Connector/NodeAec.Connector.addin`
and `scripts/release.ps1`:

- `release.ps1:157-163` sets `$installDir = "C:\ProgramData\Autodesk\Revit\Addins\$BuildYear\NodeAec.Connector"`
  and rewrites the template manifest's `<Assembly>` to `"$installDir\$DllName"` (absolute);
  `release.ps1:226-254` copies the DLLs into `Addins\<year>\NodeAec.Connector\` for every installed year of the group and the
  `.addin` into each `Addins\<year>\` **root** (`installer.iss:315-323` + `453-464` write the same layout).
- **Canonical layout: manifest at the `Addins\<year>\` root, the add-in's DLLs in a
  dedicated subfolder beside it.** The connector's `<Assembly>` ships absolute (rewritten by
  `release.ps1`); the template's original value is relative to the manifest.

The sample mirrors that layout exactly — this is the packaging contract for the plugin:

| Piece | Sample | Connector (proof) |
|---|---|---|
| Manifest location | `%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin` | `Addins\<year>\NodeAec.Connector.addin` (`release.ps1:163`) |
| `<Assembly>` value | `SamplePlugin\SamplePlugin.dll` (relative to the manifest) → `Addins\<year>\SamplePlugin\SamplePlugin.dll` | absolute `Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll` (`release.ps1:157-163`) |
| `<AddInId>` | own GUID, unique per add-in (never reuse the connector's) | fixed GUID `4B8E1A2C-…` across years |
| `<FullClassName>` | `SamplePlugin.App` (`IExternalApplication`) | `NodeAec.Connector.App` |

*Narrow caveat:* the connector repo only ever demonstrates the **absolute** `<Assembly>`
form; the sample's relative form resolves against the manifest's own directory to the
identical layout. If your packaging script rewrites `<Assembly>` to absolute (as
`release.ps1` does), keep the target the same file: `Addins\<year>\SamplePlugin\SamplePlugin.dll`.

Checklist:

1. Plugin `.addin` manifest at `%ProgramData%\Autodesk\Revit\Addins\<year>\` (root), plugin DLLs in the `SamplePlugin\` subfolder (table above) — **including** the Lite licensing assembly, which arrives there automatically via `CopyLocalLockFileAssemblies=true`.
2. Build the plugin with `RevitYear` = that year so the Revit API packages resolve (no connector install needed — §8.1).
3. `release/`/`stage/` of your plugin contains **neither** `RevitAPI*.dll` **nor** `NodeAec.Connector.dll` (the Hub is never a payload); `System.Security.Cryptography.ProtectedData.dll` appears **only** in `net48` payloads (§8.1).

---

## 4. Public integration surface

The integration surface. §4.1 is the validation entry point (one method, one string parameter),
§4.2 is the `Snapshot` contract (six members, branch only on `IsLicensed`), §4.3 is the
`OpenConnector()` courtesy call, §4.4–§4.5 are extras most plugins never need.
All of it ships **inside your plugin** via the Lite package (§3.1) — namespace
`NodeAec.Licensing`, no connector DLL involved.

### 4.1 `Gate.Validate(string productSlug)`

```csharp
namespace NodeAec.Licensing;

public static class Gate
{
    public static Snapshot Validate(string productSlug);   // Lite Gate.cs
    public static void OpenConnector();                    // Lite Gate.cs
    internal static bool HasPlatformAudience(JsonElement? aud); // internal — NOT for plugins
    public sealed class Snapshot { … }                     // same file, six members
}
```
Source: package `NodeAec.Licensing.Lite 1.0.0-preview.1` (`src/NodeAec.Licensing.Lite/Gate.cs`, frozen contract — plan §3).

| Aspect | Contract |
|---|---|
| **Parameter** | `productSlug` — your product's catalog slug. Matched against the entitlement claim `slug` with `Trim()` + `OrdinalIgnoreCase`. `null`/whitespace ⇒ immediate failure (`Slug do produto não informado…`). This sample uses [`"revit-sample-plugin"`](https://nodeaec.com.br/products/revit-sample-plugin). |
| **Returns** | `NodeAec.Licensing.Snapshot` — **no enum, no status code, no out-params**. The only boolean is `IsLicensed`; the only human string is `Message`. |
| **Never throws** | Guaranteed: everything after the initial lease read is wrapped in a top-level `catch` that returns `Snapshot.Failure("Não foi possível verificar a licença local. Abra o Node.aec Connector para ressincronizar.")`. The pre-try part's only I/O call, `LeaseStorage.LoadMasterLease()`, swallows its own exceptions and returns `null`. (Bounded, as always, by catastrophic CLR failures. There is no assembly-missing case: Lite is compiled into your plugin, so `Gate.Validate` always runs — §3.1.) |
| **Network** | **Zero network calls.** Every call does local disk I/O (`entitlements.lease` read + DPAPI unprotect), base64/JWT parse, Ed25519 verify against the compiled `TrustedAnchors[]` and an in-memory entitlement scan. Treat each call as inexpensive disk I/O, and call it **once per command**, not in per-element loops. |
| **Revit API** | None — no `Document`, no `UIApplication`. Filesystem/DPAPI/crypto only. |
| **Environment overrides** | **None — by design.** Unlike the Hub, Lite ignores `NODEAEC_LICENSE_PUBLIC_KEY_SPKI`: the only accepted keys are the compiled `TrustedAnchors[]` (current + next, supporting N/N+1 rotation). No env var, config file, or registry key can change the trust anchor. |
| **Verification order** | Ed25519 signature → `iss` (`"node-aec"`) → `scope` (`"master-lease"`) → `aud` (`node-aec-desktop`/`node-aec-plugin`) → `iat` (≤ now+300 s) → machine id (`mid`) → offline `exp` → entitlement `slug` → entitlement activity. |

### 4.2 `Snapshot` — every member

The `Snapshot` contract. It is an immutable result with six members: one boolean
(`IsLicensed`), four payload fields populated only on success, and one human message
always populated. Constructed only by the public factories, no setter mutates it afterwards.

| Member | C# type | Semantics | When set |
|---|---|---|---|
| `IsLicensed` | `bool` | **The only branch point.** `true` if and only if the slug has an active, verified entitlement on this machine. | `true` only via `Success(...)`; every `Failure` sets `false` |
| `LicenseType` | `string?` | Entitlement `type` claim — a **free string**, not an enum (`"perpetual"` is the model default; vocabulary is not documented). | `Success` only; `null` on failure |
| `LicenseKey` | `string?` | Entitlement `licenseKey` claim, e.g. `NAEC-XXXX-XXXX-XXXX-XXXX`. | `Success` only; `null` on failure |
| `ProductName` | `string?` | Display name of the entitlement (`name` claim). | `Success` only; `null` on failure |
| `ExpiresAt` | `DateTimeOffset?` | Entitlement expiry (UTC, invariant parse, `AssumeUniversal`). `null` = no expiry claim (perpetual-style). | `Success` only; `null` on failure **and** when the claim is absent/invalid |
| `Message` | `string` | Human-readable, user-ready **Portuguese** sentence. Default on success: `Licença ativa e verificada.` On failure: one of the 17 texts of §5. | Always |

Factories (the only way to build one — constructor is `private`):

```csharp
public static Snapshot Success(string type, string? key, string? name, DateTimeOffset? expiresAt,
                               string message = "Licença ativa e verificada.");
public static Snapshot Failure(string message);   // payload members all null
```

**Not exposed — do not invent them:** licensee/account, plan, seat counts
(`maxActivations`/`activeActivations` exist on the internal model but never surface here),
machine id, entitlement `slug`, `status`, `granted`, trial flag, offline-grace days, lease
`exp`, correlation id, any enum/status code, and any Hub-availability flag. If you need
machine-readable reasons: no such
public API exists.

### 4.3 `Gate.OpenConnector()` and deep links

```csharp
public static void OpenConnector();   // Lite Gate.cs
```

- Reflects `Type.GetType("NodeAec.Connector.UI.ConnectorWindow, NodeAec.Connector")` and
  invokes its `public static void Open()` (singleton WPF window, `Show()` + `Activate()`).
  Reflection — not a reference — so calling it never loads the Hub and never fails the build when the Hub is absent.
- **Silent no-op contract:** the whole body is wrapped in `catch { /* Silencioso se o
  add-in do connector não estiver no mesmo processo */ }`. If the Hub UI type cannot
  be resolved (Hub not installed for this Revit year) or the open fails, **nothing
  happens** — no exception, no dialog. Your plugin must therefore never *depend* on
  the window appearing (call it as a courtesy after you have already shown your own dialog).
- **No slug-parameterized deep link exists** — no `OpenConnector(string)` overload, no
  navigation to a specific product card. For a catalog URL, link `https://nodeaec.com.br/products/{slug}` directly.
- The plugin-side seam (§9) calls this behind its own `try`, so it is a genuine no-op
  in every failure case.

### 4.4 Diagnostics / logging (public)

Lite itself is silent: it exposes **no logging API** and writes no log lines — a
plugin correlates a blocked dialog with the failure simply by showing `Message`
verbatim (§5). When the Hub is installed, its log remains available for
Hub-side issues (sync, sign-in):

| Member | Signature / value | Notes |
|---|---|---|
| Hub log file | `%APPDATA%\NodeAec\connector.log` | Written by the Hub only; absent when the Hub is not installed |

- Usage rule (Hub contract): log lines **must never** contain JWT
  tokens, license keys, e-mails or hardware ids — only error type + display-ready text.

### 4.5 Supporting public types (available, but secondary)

Use only if you truly need them; the happy path needs none of them. All live in
the Lite package (`NodeAec.Licensing.*`) and travel with your plugin.

| Type | Useful members | Caution |
|---|---|---|
| `NodeAec.Licensing.Models.MasterLeasePayload` | claims `Iss`, `Sub`, `Mid`, `Scope`, `Aud`, `Iat`, `Exp`, `Entitlements`, derived `ExpiresAt`/`IssuedAt`/`IsExpired` | Read-only display material; never a license decision |
| `NodeAec.Licensing.Models.EntitlementItem` | `Slug`, `Name`, `LicenseKey`, `Type`, `Status`, `Granted`, `ExpiresAt`, `MaxActivations`, `ActiveActivations`, `bool IsActive()` | `IsActive()` = `Granted && Status=="active" && (no expiry or not past)`; seat fields never reach `Snapshot` |
| `NodeAec.Licensing.Storage.LeaseStorage` | `LoadMasterLease()`, `GetLeaseFilePath()`, `GetBaseDirectory()`, `SetCustomBasePath()` (test hook) | `ParseJwtPayload(string)` is explicitly **display-only, signature NOT verified** — license decisions go through `Gate.Validate`, always |
| `NodeAec.Licensing.Hardware.HardwareId` | `static bool TryGetMachineId(out string machineId, out string? reason)` | Machine fingerprint; treat as sensitive |
| `NodeAec.Licensing.Cryptography.LeaseSignatureVerifier` | `TryVerify(string?, out string? reason)`, `TrustedAnchors[]`, `AcceptedAlgorithm = "EdDSA"` | Anchor-only mode: no env override accepted; redundant if you call `Validate` |

---

## 5. Status / reason taxonomy

There is **no status enum**. Every distinct state is a distinct Portuguese sentence from
`Validate`. Branch **only** on `IsLicensed`; on failure show `Message` verbatim (it is
already written as user guidance) — **never** string-match it to decide behavior, and never
translate it inside code. Rows marked ⟶ are the cases the brief calls out explicitly.

Each failure is a distinct `Message` with no machine-readable code — never parse
or match the text to decide behavior.
Read the table to learn what users will see and what guidance to attach, not to
build branches: your code has exactly one `if` on `IsLicensed`.

**How `HelloCommand` really handles this table — one path for every row.** It does *not*
branch per row: any non-licensed outcome (a machine with no credentials looks exactly
like a signed-out one — message #2 below) renders the **same** fail-closed `TaskDialog` (`BlockedTitle` = `Sample Plugin — License
Required`) whose `MainInstruction` is `Sample Plugin requires an active Node.aec license.`,
whose `MainContent` starts `Reason reported by Node.aec:\n{Message}` followed by fixed
generic guidance bullets (sign in / renew / buy `'revit-sample-plugin'` / connector missing / seat
limit / offline grace), with an `Open Node.aec Connector...` command link (→
`NodeAecLicenseGate.OpenConnector()` only on click) and `CommonButtons = Close`; the command
then returns `Result.Cancelled`. The column below is therefore *message-implied* guidance —
detail your own UI may surface — not a set of code branches.

| # | Verbatim `Message` | Situation ⟶ category | Handling & user guidance (sample: same blocked dialog + `Result.Cancelled` for every row) |
|---|---|---|---|
| 1 | `Slug do produto não informado para validação.` | Caller passed null/whitespace slug — **programming error** | Fix the caller (your `ProductSlug` constant); cannot occur in normal operation (if it does, the sample still shows it verbatim in the blocked dialog + `Result.Cancelled`) |
| 2 | `Nenhuma credencial do Node.aec encontrada nesta estação. Abra o Node.aec Connector na Ribbon para entrar com sua conta ou ativar sua licença.` | ⟶ **Not authenticated** (never logged in, logged out, lease file cleared) **AND ALSO the "Hub not installed / lease never written" case** — the gate only reads the file; it cannot distinguish "Hub absent" from "never authenticated", and there is no separate state for it (§3.1, §9) | Show `Message` in the blocked dialog; offer `Open Node.aec Connector...` → `OpenConnector()`; `Result.Cancelled` |
| 3 | `Concessão corrompida ou estrutura inválida. Abra o Node.aec Connector para ressincronizar.` | JWT payload unparsable | Cancel + show + offer `OpenConnector()` (resync) |
| 4 | `A licença local não passou na verificação de segurança. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | Ed25519 signature verification failed (tampered/forged/wrong key); gate logs `WARN` | Cancel; tell user to go online and update in the connector |
| 5 | `Origem da licença local desconhecida. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `iss` ≠ `"node-aec"` | Cancel; go online → update |
| 6 | `A licença local está em formato não suportado. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `scope` ≠ `"master-lease"` (foreign/single-product lease) | Cancel; go online → update |
| 7 | `A licença local não foi emitida para este add-in. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `aud` missing or not a platform audience | Cancel; go online → update |
| 8 | `A data da licença local é inválida. Confira a data e hora deste computador e tente novamente.` | `iat` more than 300 s in the future (clock skew/tampering) | Cancel; ask user to fix the system clock |
| 9 | `Não foi possível identificar esta máquina (MachineGuid do Windows indisponível). Contate o suporte Node.aec.` | Windows machine id unavailable; gate logs `WARN` | Cancel; contact support |
| 10 | ⟶ `A concessão de licenças foi emitida para outra estação de trabalho (Hardware ID divergente).` | **Machine mismatch** — lease bound to another PC | Cancel; user must activate/log in on this machine |
| 11 | ⟶ `O prazo de tolerância offline expirou em {dd/MM/yyyy}. Conecte-se à internet para sincronizar.` | **Offline grace** (offline tolerance window, default 30 days) expired — `exp` in the past | Cancel; tell user to connect and sync (connector "Atualizar") |
| 12 | `O prazo da licença local não pôde ser lido. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `exp` unreadable/out of plausible range | Cancel; go online → update |
| 13 | ⟶ `O produto '{productSlug}' não consta nas licenças ativas desta conta. Adquira ou ative no catálogo Node.aec.` | **Missing entitlement** — account has no lease entry for this slug (wrong product, not purchased, or slug mismatch) | Blocked dialog + `Result.Cancelled`; the sample's guidance bullet calls out `'revit-sample-plugin'` — optionally add a catalog link via `ProductLinks.BuildProductUrl(slug)` |
| 14 | ⟶ `O limite de computadores simultâneos para '{Name}' foi atingido.` | **Seat limit** — entitlement `status == "seat_limit_reached"` | Cancel; user frees a seat in the web portal, then revalidates |
| 15 | ⟶ `A licença ou período de teste de '{Name}' expirou em {dd/MM/yyyy}.` | **Expired license or trial** — `expiresAt` in the past. Note: there is **no trial claim** anywhere; "período de teste" is wording only — a trial is just an entitlement that expires | Cancel; user renews in the portal |
| 16 | `A licença de '{Name}' está com status '{Status}'.` | Any other inactive status, or `granted:false`. **Quirk (verified):** if `granted` is `false` while `status` stays `"active"` and unexpired, the text reads `… está com status 'active'.` — confusing but verbatim | Show as-is in the blocked dialog (the status string is echoed verbatim); surface it to support if needed |
| 17 | `Não foi possível verificar a licença local. Abra o Node.aec Connector para ressincronizar.` | Unexpected exception inside the gate (logged `ERROR`) | Cancel; offer `OpenConnector()` (resync) |
| ✔ | `Licença ativa e verificada.` | Success (default text) | Proceed: `HelloCommand` greets the user and renders `NodeAecLicenseGate.BuildLicenseBlock(gate)` (Product / Type / key / expiry / status from `Snapshot`), then returns `Result.Succeeded` |

Notes:

- **Not authenticated vs Hub-not-installed share message #2** (see row 2) — the gate
  reads only the lease file, so a machine without the Hub looks identical to a machine
  where nobody ever logged in. There is deliberately no separate state to distinguish
  them (§3.1, §9).
- **Offline is not a failure**: `Validate` never touches the network, so being offline looks
  exactly like being online; validity is bounded only by the lease's `exp` (row 11).
- Hub-side API error codes (`LICENSE_EXPIRED`, `MACHINE_MISMATCH`, `ACTIVATION_LIMIT_REACHED`,
  …) belong to the connector's internal HTTP client and are **not reachable through the
  gate** — ignore them for plugin design.

---

## 6. Ribbon integration conventions

Where your button lives. One shared tab owned by the connector; your plugin rents
a panel inside it. The rules below keep that tab from duplicating when Revit
reloads add-ins.

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
bodies in `catch { }`. You **may** call them rather than replicate — convenience (always
the connector's exact algorithm, ~40 fewer lines) **vs** forcing the `NodeAec.Connector`
assembly to load and JIT in your process the first time your handler runs, i.e. your Ribbon
layer hard-depends on the connector being installed — the dependency the sample's `App.cs`
deliberately avoids. They are also *public but not documented as partner API*
(**[Uncertain]** support). Recommendation: replicate locally; treat the helpers as a
defensive fallback if you already accept the load dependency.

### MUST / MUST-NOT rules

| Rule | Mechanics |
|---|---|
| **MUST** use the single shared tab `Node.aec` | Connector creates it in `Initialize` via `application.CreateRibbonTab(TabName)`; you create it only defensively (below) |
| **MUST NOT** create a plugin-owned tab | No second tab per plugin — ever. Panel thematically inside `Node.aec` instead |
| **MUST** catch tab-creation failure with a **filtered** exception | `catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException \|\| ex is ArgumentException)` — "tab already exists" is the *only* expected failure; a bare `catch {}` masks real errors (the connector itself explicitly rejects bare catches) |
| **MUST** insert panel/button **idempotently** | Panel: `GetRibbonPanels(tab).FirstOrDefault(p => p.Name == panelName OrdinalIgnoreCase) ?? CreateRibbonPanel(tab, panelName)`. Button: scan `panel.GetItems()` by `Name` before `AddItem`. Revit add-in reloads (Add-In Manager) otherwise throw `ArgumentException` or duplicate buttons. The connector's helpers doing this are **`private`** (`GetOrCreatePanel`, `AddButtonIfMissing`, `AddStackedButtonsIfMissing`) and `RibbonDecisions` is **`internal`** — **you must replicate the logic**, you cannot call them |
| **MUST** register AdWindows dedup hooks | `ControlledApplication.ApplicationInitialized` and `ComponentManager.UIElementActivated`, each with `-=` **before** `+=` on the named static handler so reloaded add-ins don't stack delegates. Handlers re-run **your local** dedup (replicated algorithm below): merge ghost/duplicate `Node.aec` tabs (keep first, move missing panels, set `duplicateTab.IsVisible = false` and remove it) — connector-free, per the recommended pattern. Stripping rogue `License`/`Licensing` tabs is the connector's `CleanRogueRibbonElements()` job: its own hooks already do it, replicating/calling it is optional (next row) |
| **MAY** (OPTIONAL) call the connector's public dedup helpers | `NodeAec.Connector.App.DeduplicateRibbonTabs(string targetTitle)` / `NodeAec.Connector.App.CleanRogueRibbonElements()` are `public static` and swallow their own errors, **but calling them loads `NodeAec.Connector` into your process at Ribbon time** (JIT) — convenience vs connector-free startup, see the tradeoff above. **[Uncertain]** public-but-undocumented partner API; the sample's `App.cs` does **not** call them |
| **MUST NOT** rely on `RibbonDecisions` / private helpers | `internal`/`private` — invisible outside the connector assembly |
| **MUST** load icons with `BitmapCacheOption.OnLoad` + `Freeze()` | Otherwise Revit keeps the PNG file locked; mirror `App.LoadButtonIcons` (`UriKind.Absolute`, `CacheOption = OnLoad`, `Freeze()`) |
| **MUST** keep `OnStartup` non-blocking | No network, no heavy I/O on the Ribbon thread; wrap everything in a top guard returning `Result.Failed` rather than letting exceptions escape half-built |
| **MUST NOT** produce ghost tabs/panels | Duplicate tabs come from add-in reloads; the hooks above are the supported fix, not manual `Tabs.Remove` calls outside `try/catch` |

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
Source: [App.cs](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs) — constants [L29-L38](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L29-L38), startup [L47](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L47), tab [L100](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L100), panel [L118-L130](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L118-L130), hooks [L175-L179](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L175-L179), dedup [L200](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/App.cs#L200).

Optional alternative to `DeduplicateTab()`, **only if you accept the load dependency**:
`NodeAec.Connector.App.DeduplicateRibbonTabs(TabName); NodeAec.Connector.App.CleanRogueRibbonElements();`
— same semantics, but the connector assembly must load in your process (tradeoff above).

---

## 7. Threading & Revit API-context rules

When and where to call. Short version: call `Validate` once, at the top of each
command, on Revit's own thread — and keep everything else (network, heavy I/O,
Revit objects) where it belongs.

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
- **No plugin-side logging API exists**: Lite is silent by design (§4.4). Correlate a
  blocked dialog with `Message` verbatim; Hub-side issues live in the Hub's own log
  when it is installed.

---

## 8. Versioning & compatibility matrix

Which framework each Revit year builds against, and how the connector reference
resolves per year. Find your year in the table, build with that `RevitYear`, done.

### 8.1 Revit year → target framework

Build with `dotnet build -p:RevitYear=<2023..2027>` (default `2026`); the year defines the
`REVIT2023`…`REVIT2027` compilation constant and isolates `obj\<year>\`/`bin\<year>\`.
The license package resolves for every year alike. Pre-release it
restores from the local folder feed (`NuGet.config` → Lite `bin/Release`); at
release it restores from NuGet.org with no csproj change (§8.2).

| `RevitYear` | Target framework | Nice3point Revit API pkg | DPAPI package (`DpapiPkgVersion`) | `System.Security.Cryptography.ProtectedData.dll` in payload? |
|---|---|---|---|---|
| 2023 | `net48` | `2023.1.90` | `4.7.0` | **Yes** — only the NuGet package provides it on net48 |
| 2024 | `net48` | `2024.3.60` | `4.7.0` | **Yes** |
| 2025 | `net8.0-windows` | `2025.4.60` | `8.0.0` | **No** — ships inside `Microsoft.WindowsDesktop.App`; do not copy it to the add-in folder (must not appear in `release/`/`stage/`) |
| 2026 | `net8.0-windows` | `2026.4.10` | `8.0.0` | **No** |
| 2027 | `net10.0-windows` | `2027.2.0` | *(unset — package not referenced, NuGet prunes it / NU1510)* | **No** |

License-package pins (all years, via `NodeAec.Licensing.Lite 1.0.0-preview.1`):

| Package | Version | Scope |
|---|---|---|
| `BouncyCastle.Cryptography` (Ed25519 verify) | `2.7.0` | all TFMs (`net48`, `net8.0-windows`, `net10.0-windows`) |
| `System.Text.Json` | `8.0.5` | `net48` only (inbox on net8/net10 — never add it there) |

Notes:

- **2026 deliberately stays `net8.0-windows`** even though Revit 2026.5 runs on .NET 10:
  no net10 reference package exists for 2026, and compatibility only flows one way (a net8
  add-in loads in the net10 host; the reverse fails).
- Revit API references must always be non-copying (`PrivateAssets="all"`
  `ExcludeAssets="runtime"`, or `<Private>False</Private>`) — **never** ship
  `RevitAPI*.dll`/`AdWindows.dll`/`UIFramework*`.
- The `ProtectedData.dll` rule above is about *your plugin's payload*, which now
  includes Lite's dependencies: on `net48` the DLL travels with your add-in (correct);
  on net8/net10 its presence in `release/`/`stage/` is a packaging bug.
- Your `.addin` manifests deploy per year under `%ProgramData%\Autodesk\Revit\Addins\<year>\`;
  the Hub (if installed) lives in its own per-year folder and is never referenced (§3.1).

### 8.2 Assembly versioning

- License package: `NodeAec.Licensing.Lite`, `<Version>1.0.0-preview.1</Version>`
  (⇒ assembly version `1.0.0.0` under SDK defaults), `RootNamespace NodeAec.Licensing`,
  TFMs `net48;net8.0-windows;net10.0-windows`, release-signed (strong-name key via
  secrets, never in the repo — local pre-release builds are unsigned) + Authenticode
  at publish.
  Pre-release it restores from the local folder feed (`NuGet.config` at the repo root
  → `../revit-licensing-lite/.../bin/Release`); at release (Wave 4) the local source
  is removed and the same `PackageReference` restores from NuGet.org (prefix
  `NodeAec.*` reserved) with `.nupkg` + `.sha256` per Release.
- Because Lite compiles *into* your plugin, version skew between Hub and plugin is
  impossible by construction: whatever Revit loaded for the Hub is irrelevant to your
  gate. Practical rules: pin the Lite version you tested with; rebuild/re-test when you
  bump it; don't hard-code it in plugin code; treat all surface documented in §4 as
  "latest verified" (verified against `1.0.0-preview.1`) rather than frozen.
- Key rotation between Lite releases is additive: `TrustedAnchors[]` carries the
  current key plus the next one (N/N+1), so a new package keeps validating leases
  signed before the rotation.

---

## 9. Fail-closed recipe (`NodeAecLicenseGate.cs`)

The copy-paste seam. One file sits between your commands and the Lite package so
every gate outcome — including any surprise — becomes a clean denial, not a
crash. Port it verbatim, change the slug, keep licensing types inside it.

Consistent with the template's `Licensing/NodeAecLicenseGate.cs` (the shape this
sample's `src/` uses): **one product slug constant** (the one thing
to change when adapting) and a seam that *cannot* crash the command —
`Validate()` returns a plugin-local `GateSnapshot` and never throws. Lite is
compiled in, so "Hub missing" and "never signed in" are the same ordinary failure #2
(`Nenhuma credencial…`, §5).

```csharp
using NodeAec.Licensing;

namespace SamplePlugin.Licensing;

/// <summary>Fail-closed seam over the Node.aec gate for this plugin.</summary>
public static class NodeAecLicenseGate
{
    /// <summary>THE one constant to change when adapting this sample.</summary>
    public const string ProductSlug = "revit-sample-plugin";

    /// <summary>Validates ProductSlug. Never throws — any failure becomes not-licensed.</summary>
    public static GateSnapshot Validate()
    {
        try
        {
            return RunValidation();
        }
        catch (Exception)
        {
            // Unreachable in practice (Lite is compiled in and Gate never throws):
            // last-resort fail-closed snapshot, never licensed.
            return new GateSnapshot(
                isLicensed: false,
                message: "Node.aec could not verify this plugin's license on this machine, " +
                    "so it will not run. Open the Node.aec Connector, synchronize your " +
                    "licenses, and try again.",
                productName: null,
                licenseType: null,
                licenseKey: null,
                expiresAt: null);
        }
    }

    /// <summary>The single place where the Lite Snapshot is read (6 members only).</summary>
    private static GateSnapshot RunValidation()
    {
        Snapshot snapshot = Gate.Validate(ProductSlug);

        return new GateSnapshot(
            isLicensed: snapshot.IsLicensed,
            message: snapshot.Message,
            productName: snapshot.ProductName,
            licenseType: snapshot.LicenseType,
            licenseKey: snapshot.LicenseKey,
            expiresAt: snapshot.ExpiresAt);
    }

    /// <summary>Courtesy deep link; genuine silent no-op when the Hub is absent.</summary>
    public static void OpenConnector()
    {
        try { Gate.OpenConnector(); }
        catch (Exception) { /* nothing to open */ }
    }

    // Also in the real file: public static string BuildLicenseBlock(GateSnapshot) and
    // private static string FormatExpiry(DateTimeOffset?) — they render the licensed
    // dialog from the snapshot (no catch needed).
}
```
Source: [NodeAecLicenseGate.cs:L47-L65](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L47-L65) (`Validate`), [L74-L85](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L74-L85) (`RunValidation`) and [L139-L185](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Licensing/NodeAecLicenseGate.cs#L139-L185) (`GateSnapshot`).

```csharp
/// <summary>Plain, licensing-free view of one gate outcome: strings and dates only.</summary>
public sealed class GateSnapshot
{
    public GateSnapshot(bool isLicensed, string message,
                        string? productName, string? licenseType, string? licenseKey,
                        DateTimeOffset? expiresAt)
    {
        IsLicensed = isLicensed; Message = message; ProductName = productName;
        LicenseType = licenseType; LicenseKey = licenseKey; ExpiresAt = expiresAt;
    }

    public bool IsLicensed { get; }             // the ONLY branch point
    public string Message { get; }              // gate text, verbatim
    public string? ProductName { get; }         // null on failure
    public string? LicenseType { get; }         // null on failure
    public string? LicenseKey { get; }          // null on failure
    public DateTimeOffset? ExpiresAt { get; }   // null on failure and when the claim is absent
}
```

Why the seam is this thin: Lite compiles *into* the plugin assembly, so there is
no external assembly whose load can fail at JIT time.
`Validate()`'s `try` stays as a last-resort
fail-closed guard, and commands keep their defensive `try/catch` + null guard
around the call. When no lease exists, `Gate.Validate` runs normally and returns
failure #2; `OpenConnector()` either opens the Hub window or silently no-ops.

Command usage (only plugin-local types — see §2 for the full happy path; the shipping
`SamplePlugin.Commands.HelloCommand` adds the defensive `try/catch`, the null guard
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
Source: [HelloCommand.cs:L40-L63](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L40-L63) (full dialog at [L110-L134](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L110-L134)).

---

## 10. Troubleshooting / FAQ

Symptoms first, fixes second. If your command blocks unexpectedly, find the shape
of your failure below before re-reading the earlier sections.

**Q: My plugin fails to restore right after scaffolding (`NU1101`).**
The `PackageReference` to `NodeAec.Licensing.Lite` resolves from NuGet.org (§3.1, §8) —
check feed access and the pinned version. Never "fix" it with a DLL reference: the build
stays package-only.

**Q: Nothing happens when the user clicks my "open connector" link.**
By contract `OpenConnector()` is a silent no-op when the connector UI cannot be reached
(assembly absent, window open failure). Your own dialog must already carry the guidance —
never rely on the window appearing.

**Q: The user says "I have a license" but the command cancels with
`Nenhuma credencial do Node.aec encontrada nesta estação…`.**
This single message covers **not authenticated and connector-not-installed** (§5 row 2).
Check that the connector is installed for this Revit year, then have the user log in /
activate a key in the connector and re-run.

**Q: `O produto 'revit-sample-plugin' não consta nas licenças ativas desta conta…`.**
Entitlement missing for the slug — either not purchased/activated, or your `ProductSlug`
does not match the catalog slug (matching is `Trim()` + case-insensitive). Point the user at
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
No — it is a documentation claim. `Validate` does disk I/O (lease read + DPAPI + key read)
on **every** call. Zero network, yes; "pure CPU", no. Call it once per command.

**Q: DPAPI fails (`Access denied`, win32 5) in CI/SSH/headless contexts.**
Expected: `ProtectedData … CurrentUser` needs a real interactive logon session (Session ≥ 1;
fail-closed by design otherwise). Validate license persistence manually inside a real Revit
session; do not weaken storage or skip tests to work around it.

**Q: May I vendor the gate source into my plugin rather than take the package?**
Not in this repository — §3.2 rules out the source-copy path (incomplete dependency closure,
maintenance burden, divergent versions). Exactly one integration path is authoritative here.

**Q: Where do I see what happened when a validation fails?**
`%APPDATA%\NodeAec\connector.log` (`ConnectorLog.GetLogFilePath()`) — the gate logs
`WARN`/`ERROR` lines with exception types only (never tokens, keys or machine ids).

---

## 11. Glossary

| Term | Meaning |
|---|---|
| **Connector / Hub** | `NodeAec.Connector` — Node.aec desktop governance add-in: auth, lease sync, gate parity, canonical Ribbon tab. Installed per Revit year; never referenced or shipped by plugins |
| **Gate** | `NodeAec.Licensing.Gate` — the local, offline, fail-closed validation entry point (Lite, compiled into your plugin) |
| **`Snapshot`** | Immutable result of `Gate.Validate`; 6 members; only `IsLicensed` branches |
| **`GateSnapshot`** | Plugin-local mirror of one gate outcome, returned by `NodeAecLicenseGate.Validate()`; same 6 members, no Hub-state flag |
| **Master lease** | Signed JWT (`scope: master-lease`) stored DPAPI-encrypted at `%APPDATA%\NodeAec\entitlements.lease`; claims `iss/sub/mid/scope/aud/iat/exp/entitlements` |
| **Entitlement** | One product grant inside the lease (`slug`, `name`, `licenseKey`, `type`, `status`, `granted`, `expiresAt`, seat counts) |
| **Slug** | Product identifier matched by `Validate` (here: `revit-sample-plugin`) |
| **Offline grace** | Lease `exp` window (default 30 days) during which validation works without network; expired ⇒ taxonomy #11 |
| **Seat** | One activated computer; `seat_limit_reached` ⇒ taxonomy #14; counts never surface in `Snapshot` |
| **Machine mismatch** | `mid` claim ≠ this machine's SHA-256 `MachineGuid` ⇒ taxonomy #10 |
| **DPAPI** | Windows Data Protection API, `DataProtectionScope.CurrentUser`; protects lease/session files |
| **Ed25519 / SPKI** | Signature algorithm (RFC 8032) verifying the lease; only the compiled **public** key is ever shipped |
| **Fail-closed** | Any doubt ⇒ deny. No lease, bad signature, wrong machine, unreadable data ⇒ failure |
| **Deep link** | Programmatic opening of a connector window (`OpenConnector()`); no slug-parameterized variant exists |
| **Shared tab** | The single `Node.aec` Ribbon tab owned by the connector; plugins add panels only |
| **AdWindows** | `Autodesk.Windows` (AdWindows.dll) — low-level Ribbon API used for tab deduplication |
| **Ghost tab** | Duplicate/rogue Ribbon tab left by add-in reloads; removed by your local dedup (replica of `App.DeduplicateRibbonTabs`) or, optionally, the connector's `DeduplicateRibbonTabs`/`CleanRogueRibbonElements` (§6 tradeoff) |
| **`.addin`** | Revit manifest in `%ProgramData%\Autodesk\Revit\Addins\<year>\` pointing at an assembly |
| **`RevitYear`** | MSBuild property `2023`–`2027` selecting TFM and API packages |
| **TFM** | Target framework: `net48`, `net8.0-windows`, `net10.0-windows` per year |
| **Hub / ConnectorApiClient** | Connector's internal HTTP client + cloud API — out of bounds for plugins |

---

## 12. Verification & related documents

- **Gate surface verified against `NodeAec.Licensing.Lite 1.0.0-preview.1`** — every
  `Gate`/`Snapshot` identifier, signature and verbatim message above was checked
  against the Lite source (frozen contract, plan §3). Scaffold shape verified
  against the `NodeAec.Templates.RevitPlugin` template (`nodeaec-revit-plugin`).
- **Hub behavior verified against revit-connector@7366482** — the Hub-side facts
  retained in this document (SSO/lease-sync ownership, Hub log path, `OpenConnector`
  reflection target, shared-tab ownership) were checked against the connector source
  at that commit.
- Sample-side identifiers (`App`, `HelloCommand`, `NodeAecLicenseGate.Validate()` →
  `GateSnapshot`, `SamplePlugin.addin`) match the template output for
  `-n SamplePlugin -p ProductSlug=revit-sample-plugin` and the shipped `src/`
  code, and `Source:` links above
  point at the authoritative location for each excerpt.
- Related documents in this repository: [`README.md`](README.md) · [`AGENTS.md`](AGENTS.md) ·
  [`.agents/skills/nodeaec-connector-integration/SKILL.md`](.agents/skills/nodeaec-connector-integration/SKILL.md)
- **Remaining uncertainties are flagged inline with [Uncertain]/GUESS**: off-UI-thread
  behavior of `Validate`/`OpenConnector` (§7), partner support for
  `App.DeduplicateRibbonTabs`/`CleanRogueRibbonElements` (§6), and the future of a
  machine-readable failure code (§4.2).

---

## 13. Migrating an existing plugin to Lite

For existing STANDALONE plugins — shipping today with no Node.aec integration
at all — adopting `NodeAec.Licensing.Lite` for the first time. Target API
(frozen, plan §3):

```csharp
// Package: NodeAec.Licensing.Lite, namespace NodeAec.Licensing
public static class Gate {
  public static Snapshot Validate(string productSlug); // never throws, fail-closed
  public static void OpenConnector();                  // reflection, silent no-op when Hub is absent
}
```

`Snapshot` has exactly six members — `IsLicensed` (the only branch point),
`Message` (PT-BR verbatim, same taxonomy as §5), `ProductName`, `LicenseType`,
`LicenseKey`, `ExpiresAt` (`null` = no claim / perpetual). Lite ships compiled in,
so "Hub absent" becomes
"no lease" (`Nenhuma credencial…`, §5 #2), never a load crash. Each
`IExternalCommand.Execute` calls the gate as its first statement
(`NodeAecLicenseGate.Validate()`), fail-closed with `Result.Cancelled`.

**Step 1 — Catalog slug.** Register your product in the Node.aec catalog and take
its slug. It becomes the single product constant in the seam you add in Step 3
(this sample: [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)).
Matching is `Trim()` + case-insensitive.

**Step 2 — Add the package.**

```bash
dotnet add package NodeAec.Licensing.Lite
```

which declares (version pinned per §8.2):

```xml
<PackageReference Include="NodeAec.Licensing.Lite" Version="1.0.*" />
```

The decision compiles into your assembly and restores from NuGet, so a machine
without the Hub builds identically — nothing to copy or wire.

**Step 3 — Wrap each billable `Execute`.** Inventory every
`IExternalCommand.Execute` (and any other entry point that runs licensed work);
the only exception is an entry point whose sole purpose is license recovery (a
button that only opens the connector). A billable command without a gate is a
release blocker, not a TODO. Add the seam file first: copy
`Licensing/NodeAecLicenseGate.cs` into your plugin (§9) and set its
`ProductSlug` to your Step-1 slug — it is the only file allowed to reference
`NodeAec.Licensing` types. Then gate each command as its first statement, one
call per execution (it performs disk I/O; never in a per-element loop or in
`DynamicUpdaters`), branching only on `IsLicensed`, `Message` verbatim +
`OpenConnector()` + `Result.Cancelled`:

Before / after — a standalone command adopting the gate (BEFORE has zero
licensing: no `using NodeAec.*`, no package reference, the feature runs for
everyone; AFTER keeps the same feature behind the first-line gate):

```csharp
// BEFORE — standalone command with no licensing of any kind
public Result Execute(ExternalCommandData c, ref string msg, ElementSet set)
{
    ShowMyFeature(c);                 // runs unconditionally today
    return Result.Succeeded;
}
```

```csharp
// AFTER — same command, Lite gate first
public Result Execute(ExternalCommandData c, ref string msg, ElementSet set)
{
    var gate = NodeAecLicenseGate.Validate();   // 1st line — nothing before (no dialog, no Transaction)
    if (!gate.IsLicensed)
    {
        ShowBlockedDialog(gate);                // Message verbatim + guidance + link OpenConnector
        return Result.Cancelled;
    }
    ShowMyFeature(c);
    return Result.Succeeded;
}
```

Keep `BuildLicenseBlock`/`FormatExpiry` for the licensed dialog (§9).

**Step 4 — Ribbon: move your own tab into a panel under shared `Node.aec`.**
Never create a plugin tab: defensive creation (`CreateRibbonTab("Node.aec")` with a filtered
`catch` for "already exists" only), idempotent panel/button (get-or-create + scan by `Name`
before `AddItem`), AdWindows hooks with `-=` before `+=`
(`ApplicationInitialized`, `UIElementActivated`), and `App.cs` stays
connector-free (own types only; zero licensing calls at startup).

**Step 5 — Build matrix.** Same command; restore comes from
NuGet (a restore failure reads `NU1101` — feed or version):

```bash
dotnet build -p:RevitYear=2023   # net48
dotnet build -p:RevitYear=2026   # net8.0-windows (default)
dotnet build -p:RevitYear=2027   # net10.0-windows
```

**Step 6 — Packaging checklist.** `release/`/`stage/` with **no**
`RevitAPI*.dll`, no `AdWindows.dll`/`UIFramework*`, no `NodeAec.Connector.dll`;
Lite (and `BouncyCastle.Cryptography`, `System.Text.Json`/`ProtectedData` on
net48) **ships together** via `CopyLocalLockFileAssemblies=true`. Manifest at the year
root (`Addins\<year>\YourPlugin.addin`), relative `<Assembly>`
(`YourPlugin\YourPlugin.dll`).

**Step 7 — Manual protocol** (real Revit session; DPAPI requires interactive logon):

| # | Case | Expected |
|---|---|---|
| 1 | Licensed (Hub installed, entitled session) | Greeting + `BuildLicenseBlock` block, `Result.Succeeded` |
| 2 | Blocked (no session / wrong slug / expired / seat) | `Message` verbatim + guidance + link, `Result.Cancelled` |
| 3 | No Hub (connector uninstalled/folder renamed) | Same blocked state (`Nenhuma credencial…`), silent no-op on the link, no crash, `Result.Cancelled` |
| 4 | Reload 2× via Add-In Manager | One `Node.aec` tab, one button (no ghost tab) |

Being offline is not a failure (§5): only `exp` bounds validity. Cross-check with
`%APPDATA%\NodeAec\connector.log` in cases 2–3 (`WARN`/`ERROR`, never secrets).

---

## 14. Agent / CI verification track

Executable checklist (human or agent, same order):

- [ ] `grep -rn 'using NodeAec.Connector' --include='*.cs' src/` empty (standalone
  plugins never reference Hub types; `NodeAec.Licensing` appears only in
  `Licensing/NodeAecLicenseGate.cs`)
- [ ] `grep -rn 'HintPath.*NodeAec' --include='*.csproj' src/` empty and no
  `ProjectReference.*Connector` (no DLL reference of any kind — Lite arrives via
  `PackageReference`)
- [ ] `2023..2027` matrix compiles with 0 errors (restore
  failures read `NU1101`)
- [ ] payload with no `RevitAPI*.dll`, `AdWindows.dll`, `NodeAec.Connector.dll`;
  Lite + deps ship together (`ProtectedData.dll` only on net48)
- [ ] manifest at the year root, relative `<Assembly>`
- [ ] manual protocol §13 Step 7 completed (licensed / blocked / no-lease /
  reload with no ghost tab)
- [ ] `Source:` links re-anchored (any moved `src/` → verify each link)

**`nodeaec-verify` (concept — future SHALL).** No verification script exists
in this repo today (confirmed by grepping `scripts/`); CI SHALL gain a
`nodeaec-verify` that blocks: `RevitAPI*`/`AdWindows`/`Connector.dll` in a plugin
payload, a manifest outside the year root, a `HintPath` to a connector DLL, and
`ProtectedData.dll` outside net48. Until it exists, the checklist above is the verification
— do not invent an existing file.
