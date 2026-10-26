# API.md — Node.aec Connector Integration API

Reference for plugin authors **and their coding agents**: everything the Node.aec
license package (`NodeAec.Licensing.Lite`) exposes to a partner plugin, how to reference it, how to branch on
its license gate, and the Ribbon/threading/build rules that go with it.

**Who this is for:** Revit add-in authors integrating Node.aec licensing.
`Gate.Validate(productSlug)` takes one product slug string and returns one
`Snapshot`. It reads the signed lease file from disk, verifies the Ed25519
signature offline against the compiled `TrustedAnchors[]`, and performs no
network call. The result carries one boolean (`IsLicensed` — the sole branch
point), a `Reason` (`GateReason`) naming the case, and a human-readable message
(`GetMessage(MessageLanguage.Portuguese | English)`, shown to the user as-is). The rest of
this document is the contract for that call, its failure messages, and the
packaging rules around it.

All identifiers below were checked against `NodeAec.Licensing.Lite` 0.3.0. Gate messages
are quoted exactly — never translate or re-word them, and never branch on their text.

**Contents**

1. [Overview & responsibility split](#1-overview--responsibility-split)
2. [Quickstart (happy path)](#2-quickstart-happy-path)
3. [The integration path (authoritative)](#3-the-integration-path-authoritative)
4. [Public integration surface](#4-public-integration-surface)
5. [Status / reason taxonomy](#5-status--reason-taxonomy)
6. [Ribbon integration conventions](#6-ribbon-integration-conventions)
7. [Threading & Revit API-context rules](#7-threading--revit-api-context-rules)
8. [Versioning & compatibility matrix](#8-versioning--compatibility-matrix)
9. [Command recipe (`HelloCommand.cs`)](#9-command-recipe-hellocommandcs)
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
| The gate: `Gate.Validate(slug)` / `OpenConnector()` (both Lite, offline) | Call `Gate.Validate(ProductSlug)` at command entry and branch **only** on `IsLicensed` (§2, §9) |
| Canonical Ribbon tab `Node.aec`, its `Node.aec` panel, tab deduplication | Add its own **panel** (`SamplePlugin`, titled with the company name: one group per company) and button (`Sample Plugin`) inside that shared tab — never a plugin-owned tab (§6) |
| The connector UI (one window: account, plugins with install/update, catalog) | Show the returned `Message` verbatim on failure and offer to open the connector |
| Its log file `%APPDATA%\NodeAec\connector.log` | Fail closed: any inability to reach the gate ⇒ deny the feature (§9) |

**Non-goals for a plugin** (by connector design): no HTTP client, no cloud auth, no license
manager UI, no re-implementation of the gate. `NodeAec.Connector.Client.ConnectorApiClient`
is Hub-internal even though it is `public`.

---

## 2. Quickstart (happy path)

If you only read one section, make it this one. The whole integration is two calls:
ask the gate, honor the answer (`SamplePlugin.Commands.HelloCommand` in
`src/SamplePlugin/Commands/HelloCommand.cs` — full source in §9).

```csharp
using NodeAec.Licensing;

[Transaction(TransactionMode.Manual)]
public class HelloCommand : IExternalCommand
{
    public const string ProductSlug = "revit-sample-plugin";

    public Result Execute(ExternalCommandData c, ref string msg, ElementSet set)
    {
        Snapshot gate = Gate.Validate(ProductSlug);   // never throws; no try/catch needed
        if (!gate.IsLicensed)                         // ONLY branch point
        {
            TaskDialog.Show("Sample Plugin — License Required",
                gate.GetMessage(MessageLanguage.English)); // verbatim: the reason and the next step
            Gate.OpenConnector();                     // silent no-op if absent
            return Result.Cancelled;
        }
        // … licensed feature code here …
        return Result.Succeeded;
    }
}
```

(The shipping `HelloCommand` picks the language from Revit's UI language and puts the
`Open Node.aec Connector...` link inside the dialog — see §9.)

Setup behind those two calls (details in §3): a `PackageReference` to
`NodeAec.Licensing.Lite` plus the `ProductSlug` constant.

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
  <PackageReference Include="NodeAec.Licensing.Lite" Version="0.3.0" />
</ItemGroup>
```
Source: [SamplePlugin.csproj:L94](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/SamplePlugin.csproj#L94) (restored from NuGet.org — §8.2).

- **The licensing decision compiles into your assembly.** A loose DLL with the right
  name and class could stand in for the decision (attack A in the plan), so the
  decision lives inside your plugin and ships with it.
- **Not a `ProjectReference`** — Lite is a versioned public package with its own
  release cadence (`0.3.0` at the time of writing), not a sibling repo.
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

### 3.3 Packaging contract (bundle layout) — verified

The plugin ships as one Autodesk bundle, the same format the Node.aec Connector uses
(`revit-connector/scripts/release.ps1` and `installer.iss`). `scripts/release.ps1` builds
every compatibility group and stages:

```
%ProgramData%\Autodesk\ApplicationPlugins\SamplePlugin.bundle\
  PackageContents.xml            one <Components> per Revit year (SeriesMin = SeriesMax = R<year>)
  Contents\2023-2024\            net48            SamplePlugin.addin + SamplePlugin.dll + Lite + deps
  Contents\2025-2026\            net8.0-windows   same files
  Contents\2027\                 net10.0-windows  same files
```

Revit scans `ApplicationPlugins\*.bundle\PackageContents.xml` at startup and loads only
the component whose `SeriesMin`/`SeriesMax` matches its own version, so one bundle covers
2023–2027 and a year without a component does not load the plugin.

| Piece | Value |
|---|---|
| Manifest | `Contents\<group>\SamplePlugin.addin` (the same file in every group, copied from `src/SamplePlugin/SamplePlugin.addin`) |
| `<Assembly>` | `SamplePlugin.dll`: relative to the manifest, so it names the DLL in the same folder wherever the bundle is installed |
| `<AddInId>` | own GUID, unique per add-in (never reuse the connector's) |
| `<FullClassName>` | `SamplePlugin.App` (`IExternalApplication`) |
| `ProductCode` / `UpgradeCodes` | fixed per product, identical in `release.ps1` and `installer.iss` |

The installer (`SamplePlugin-<version>-Setup.exe`) shows one checkbox per Revit year
(installed years start checked; a re-run starts from the previous choice), copies only the
builds the checked years need and writes `PackageContents.xml` for them. Silent installs
take `/VERYSILENT /RevitYears=2025,2026`. It also removes installs made by the older
per-group installers (`Addins\<year>\SamplePlugin.addin` + `SamplePlugin\`), so Revit never
loads the plugin twice.

Checklist:

1. One bundle under `%ProgramData%\Autodesk\ApplicationPlugins\`, one `Contents\<group>\` folder per compatibility group, each with the manifest, the plugin DLL and **the Lite licensing assembly** (copied there by `CopyLocalLockFileAssemblies=true`).
2. Build each group with its floor year (`RevitYear` = 2023, 2025, 2027) so one DLL loads on every year of the group (no connector install needed — §8.1).
3. `release/`/`stage/` of your plugin contains **neither** `RevitAPI*.dll` **nor** `NodeAec.Connector.dll` (the Hub is never a payload); `System.Security.Cryptography.ProtectedData.dll` appears **only** in `net48` payloads (§8.1).

A per-year `.addin` under `%ProgramData%\Autodesk\Revit\Addins\<year>\` also works with
the gate (it does not care where the plugin is installed); the bundle is what this sample
and the template ship.

---

## 4. Public integration surface

The integration surface. §4.1 is the validation entry point (one method, one string parameter),
§4.2 is the `Snapshot` contract (branch only on `IsLicensed`), §4.3 is the
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
}

public sealed class Snapshot { … }                         // same file (§4.2)
public enum GateReason { … }                               // GateReason.cs (§5)
public enum MessageLanguage { Portuguese, English }        // GateReason.cs
```
Source: package `NodeAec.Licensing.Lite 0.3.0` (`src/NodeAec.Licensing.Lite/Gate.cs`, `GateReason.cs`).

| Aspect | Contract |
|---|---|
| **Parameter** | `productSlug` — your product's catalog slug. Matched against the entitlement claim `slug` with `Trim()` + `OrdinalIgnoreCase`. `null`/whitespace ⇒ immediate failure (`Slug do produto não informado…`). This sample uses [`"revit-sample-plugin"`](https://nodeaec.com.br/products/revit-sample-plugin). |
| **Returns** | `NodeAec.Licensing.Snapshot`, never `null`. Decide on `IsLicensed`; `Reason` names the case; `GetMessage(language)` is the text for the user. |
| **Never throws** | Guaranteed: everything after the initial lease read is wrapped in a top-level `catch` that returns a denied snapshot with `Reason = VerificationError`. The pre-try part's only I/O call, `LeaseStorage.LoadMasterLease()`, swallows its own exceptions and returns `null`. (Bounded, as always, by catastrophic CLR failures. There is no assembly-missing case: Lite is compiled into your plugin, so `Gate.Validate` always runs — §3.1.) |
| **Network** | **Zero network calls.** Every call does local disk I/O (`entitlements.lease` read + DPAPI unprotect), base64/JWT parse, Ed25519 verify against the compiled `TrustedAnchors[]` and an in-memory entitlement scan. Treat each call as inexpensive disk I/O, and call it **once per command**, not in per-element loops. |
| **Revit API** | None — no `Document`, no `UIApplication`. Filesystem/DPAPI/crypto only. |
| **Environment overrides** | **None — by design.** Lite ignores `NODEAEC_LICENSE_PUBLIC_KEY_SPKI` (production Connector builds ignore it too): the only accepted keys are the compiled `TrustedAnchors[]` (current + next, supporting N/N+1 rotation). No env var, config file, or registry key can change the trust anchor. |
| **Verification order** | Ed25519 signature → `iss` (`"node-aec"`) → `scope` (`"master-lease"`) → `aud` (`node-aec-desktop`/`node-aec-plugin`) → `iat` (≤ now+300 s) → machine id (`mid`) → offline `exp` → entitlement `slug` → entitlement activity. |

### 4.2 `Snapshot` — every member

An immutable result: no property changes after the gate builds it.

| Member | C# type | Semantics | When set |
|---|---|---|---|
| `IsLicensed` | `bool` | **The only branch point.** `true` if and only if the slug has an active, verified entitlement on this machine. | Always |
| `Reason` | `GateReason` | The one case behind the decision: `Licensed`, or a failure (§5). For logs and UI tweaks, never to decide whether to run. Since 0.3.0. | Always |
| `GetMessage(MessageLanguage)` | `string` | User-ready sentence in Portuguese or English. On failure it names the one reason and the next step. Since 0.3.0. | Always |
| `Message` | `string` | Same as `GetMessage(MessageLanguage.Portuguese)`. | Always |
| `LicenseType` | `string?` | Entitlement `type` claim — a **free string**, not an enum (`"perpetual"` is the model default). | Success only; `null` on failure |
| `LicenseKey` | `string?` | Entitlement `licenseKey` claim, e.g. `NAEC-XXXX-XXXX-XXXX-XXXX`. **The end user's secret: never show it, log it, or send it anywhere.** | Success only; `null` on failure |
| `ProductName` | `string?` | Display name of the entitlement (`name` claim). | Success only; `null` on failure |
| `ExpiresAt` | `DateTimeOffset?` | Entitlement expiry (UTC). `null` = no expiry claim (perpetual-style). | Success only; `null` on failure **and** when the claim is absent/invalid |

`Snapshot.Success(...)` and `Snapshot.Failure(string)` still exist for compatibility with
0.1/0.2 but are hidden from IntelliSense: a plugin never needs them.

**Not exposed — do not invent them:** licensee/account, plan, seat counts
(`maxActivations`/`activeActivations` exist on the internal model but never surface here),
machine id, entitlement `slug`, `status`, `granted`, trial flag, offline-grace days, lease
`exp`, correlation id, and any Hub-availability flag.

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
- Call it directly, with no `try/catch`: it already swallows every failure.

### 4.4 Diagnostics / logging (public)

Lite itself is silent: it exposes **no logging API** and writes no log lines — a
plugin that wants its own log line writes `gate.Reason` (never the license key). When the Hub is installed, its log remains available for
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
| `NodeAec.Licensing.Cryptography.LeaseSignatureVerifier` | `TryVerify(string?, out string? reason)`, `AcceptedAlgorithm = "EdDSA"` | Anchor-only mode: no env override accepted; redundant if you call `Validate`. `TrustedAnchors` is private since 0.2.0 (a public array let any add-in replace an anchor). `IsTrustedKey(byte[])` (0.3.0) is read-only and used by the Connector for rotation warnings |

---

## 5. Status / reason taxonomy

Every outcome has one `GateReason` value and one message in each language. Decide **only**
on `IsLicensed`; on failure show `gate.GetMessage(language)` verbatim (it is already written
as user guidance). Use `Reason` for logs or small UI tweaks (for example a "Buy" link on
`ProductNotFound`), never to let a command run, and **never** string-match the message.
The English texts are in the [Lite README](https://github.com/nodeaec/licensing-lite#reasons-and-messages).

Read the table to learn what users will see, not to build branches: your code has
exactly one `if` on `IsLicensed`, and the message is the whole explanation — never add
a generic list of possible causes around it.

**How `HelloCommand` really handles this table — one path for every row.** Any non-licensed
outcome (a machine with no credentials looks exactly like a signed-out one — `NoLease`)
renders the **same** fail-closed `TaskDialog` (`BlockedTitle` = `Sample Plugin — License
Required`) whose `MainInstruction` is `Sample Plugin requires an active Node.aec license.`,
whose `MainContent` is the message in Revit's UI language, with an `Open Node.aec Connector...`
command link (→ `Gate.OpenConnector()` only on click) and `CommonButtons = Close`; the command
then returns `Result.Cancelled`. The column below explains each case for support and
troubleshooting — it is not a set of code branches and not text to add to the dialog.

| # | `GateReason` | Verbatim Portuguese message | Situation ⟶ category | Handling (sample: same blocked dialog + `Result.Cancelled` for every row) |
|---|---|---|---|---|
| 1 | `MissingProductSlug` | `Slug do produto não informado para validação.` | Caller passed null/whitespace slug — **programming error** | Fix the caller (your `ProductSlug` constant); cannot occur in normal operation (if it does, the sample still shows it verbatim in the blocked dialog + `Result.Cancelled`) |
| 2 | `NoLease` | `Nenhuma credencial do Node.aec encontrada nesta estação. Abra o Node.aec Connector na Ribbon para entrar com sua conta ou ativar sua licença.` | ⟶ **Not authenticated** (never logged in, logged out, lease file cleared) **AND ALSO the "Hub not installed / lease never written" case** — the gate only reads the file; it cannot distinguish "Hub absent" from "never authenticated", and there is no separate state for it (§3.1, §9) | Show `Message` in the blocked dialog; offer `Open Node.aec Connector...` → `OpenConnector()`; `Result.Cancelled` |
| 3 | `CorruptLease` | `Concessão corrompida ou estrutura inválida. Abra o Node.aec Connector para ressincronizar.` | JWT payload unparsable | Cancel + show + offer `OpenConnector()` (resync) |
| 4 | `SignatureInvalid` | `A licença local não passou na verificação de segurança. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | Ed25519 signature verification failed (tampered/forged/wrong key) | Cancel; tell user to go online and update in the connector |
| 5 | `UnknownIssuer` | `Origem da licença local desconhecida. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `iss` ≠ `"node-aec"` | Cancel; go online → update |
| 6 | `UnsupportedFormat` | `A licença local está em formato não suportado. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `scope` ≠ `"master-lease"` (foreign/single-product lease) | Cancel; go online → update |
| 7 | `WrongAudience` | `A licença local não foi emitida para este add-in. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `aud` missing or not a platform audience | Cancel; go online → update |
| 8 | `ClockInvalid` | `A data da licença local é inválida. Confira a data e hora deste computador e tente novamente.` | `iat` more than 300 s in the future (clock skew/tampering) | Cancel; ask user to fix the system clock |
| 9 | `MachineIdUnavailable` | `Não foi possível identificar esta máquina (MachineGuid do Windows indisponível). Contate o suporte Node.aec.` | Windows machine id unavailable | Cancel; contact support |
| 10 | `MachineMismatch` | ⟶ `A concessão de licenças foi emitida para outra estação de trabalho (Hardware ID divergente).` | **Machine mismatch** — lease bound to another PC | Cancel; user must activate/log in on this machine |
| 11 | `OfflineGraceExpired` | ⟶ `O prazo de tolerância offline expirou em {dd/MM/yyyy}. Conecte-se à internet para sincronizar.` | **Offline grace** (offline tolerance window, default 30 days) expired — `exp` in the past | Cancel; tell user to connect and sync (connector "Atualizar") |
| 12 | `LeaseExpiryUnreadable` | `O prazo da licença local não pôde ser lido. Conecte-se à internet e clique em atualizar no Node.aec Connector.` | `exp` unreadable/out of plausible range | Cancel; go online → update |
| 13 | `ProductNotFound` | ⟶ `O produto '{productSlug}' não consta nas licenças ativas desta conta. Adquira ou ative no catálogo Node.aec.` | **Missing entitlement** — account has no lease entry for this slug (wrong product, not purchased, or slug mismatch) | Blocked dialog + `Result.Cancelled`; the message already names the slug |
| 14 | `SeatLimitReached` | ⟶ `O limite de computadores simultâneos para '{Name}' foi atingido.` | **Seat limit** — entitlement `status == "seat_limit_reached"` | Cancel; user frees a seat in the web portal, then revalidates |
| 15 | `LicenseExpired` | ⟶ `A licença ou período de teste de '{Name}' expirou em {dd/MM/yyyy}.` | **Expired license or trial** — `expiresAt` in the past. Note: there is **no trial claim** anywhere; "período de teste" is wording only — a trial is just an entitlement that expires | Cancel; user renews in the portal |
| 16 | `LicenseInactive` | `A licença de '{Name}' está com status '{Status}'.` | Any other inactive status, or `granted:false`. **Quirk (verified):** if `granted` is `false` while `status` stays `"active"` and unexpired, the text reads `… está com status 'active'.` — confusing but verbatim | Show as-is in the blocked dialog (the status string is echoed verbatim); surface it to support if needed |
| 17 | `VerificationError` | `Não foi possível verificar a licença local. Abra o Node.aec Connector para ressincronizar.` | Unexpected exception inside the gate | Cancel; offer `OpenConnector()` (resync) |
| ✔ | `Licensed` | `Licença ativa e verificada.` | Success (default text) | Proceed: `HelloCommand` greets the user and renders its license block (product / type / expiry — never the key), then returns `Result.Succeeded` |

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
"Node.aec"`. The sample adds its own panel **`SamplePlugin`**, titled **`Node.aec`** (its company, so it
joins the Connector's group), with button **`Sample Plugin`** inside the shared tab. Each
company has **one group**: every plugin of the company creates its own panel (internal name
unique to the plugin) and sets `panel.Title` to the company name; the Connector (0.4.0+)
merges same-title panels into one group, keeps each plugin's buttons together (internal
names `<Plugin>_<Command>`), and orders groups and plugins alphabetically, its own group
first.

**RECOMMENDED partner pattern (exactly what `src/SamplePlugin/App.cs` does):** keep your
`IExternalApplication` **free of every Node.aec Connector API call**. Build the shared tab
locally (filtered `ArgumentException` catch), replicate the idempotent panel/button
insertion, replicate the tab-dedup algorithm, and register the two AdWindows hooks against
your own static handler. Reasons, all code-visible in `App.cs`: (a) the Ribbon must come up
even when the connector is missing, so startup must not JIT-load `NodeAec.Connector`;
(b) the connector's idempotency helpers are `private`/`internal` anyway, so you are already
replicating that half; (c) licensing stays in the commands (§9), where it is checked
on every run.

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
| **MUST** title the panel with the company name | `panel.Title = CompanyName`, spelled the same in every plugin of the company. Never use the company name as the panel *name*: Revit refuses a name another add-in already created |
| **MUST** insert panel/button **idempotently** | Panel: `GetRibbonPanels(tab).FirstOrDefault(p => p.Name == panelName OrdinalIgnoreCase) ?? CreateRibbonPanel(tab, panelName)`. Button: scan `panel.GetItems()` by `Name` before `AddItem`. Revit add-in reloads (Add-In Manager) otherwise throw `ArgumentException` or duplicate buttons. The connector's helpers doing this are **`private`** (`GetOrCreatePanel`, `AddButtonIfMissing`, `AddStackedButtonsIfMissing`) and `RibbonDecisions` is **`internal`** — **you must replicate the logic**, you cannot call them |
| **MUST** register AdWindows dedup hooks | `ControlledApplication.ApplicationInitialized` and `ComponentManager.UIElementActivated`, each with `-=` **before** `+=` on the named static handler so reloaded add-ins don't stack delegates. Handlers re-run **your local** dedup (replicated algorithm below): merge ghost/duplicate `Node.aec` tabs (keep first, move missing panels, set `duplicateTab.IsVisible = false` and remove it) — connector-free, per the recommended pattern. Stripping rogue `License`/`Licensing` tabs is the connector's `CleanRogueRibbonElements()` job: its own hooks already do it, replicating/calling it is optional (next row) |
| **MAY** (OPTIONAL) call the connector's public dedup helpers | `NodeAec.Connector.App.DeduplicateRibbonTabs(string targetTitle)` / `NodeAec.Connector.App.CleanRogueRibbonElements()` are `public static` and swallow their own errors, **but calling them loads `NodeAec.Connector` into your process at Ribbon time** (JIT) — convenience vs connector-free startup, see the tradeoff above. **[Uncertain]** public-but-undocumented partner API; the sample's `App.cs` does **not** call them |
| **MUST NOT** rely on `RibbonDecisions` / private helpers | `internal`/`private` — invisible outside the connector assembly |
| **MUST** load icons with `BitmapCacheOption.OnLoad` + `Freeze()` | Otherwise Revit keeps the PNG file locked; mirror `App.LoadButtonIcons` (`UriKind.Absolute`, `CacheOption = OnLoad`, `Freeze()`) |
| **MUST** keep `OnStartup` non-blocking | No network, no heavy I/O on the Ribbon thread; wrap everything in a top guard returning `Result.Failed` rather than letting exceptions escape half-built |
| **MUST NOT** produce ghost tabs/panels | Duplicate tabs come from add-in reloads; the hooks above are the supported fix, not manual `Tabs.Remove` calls outside `try/catch` |

### Minimal sketch (group `Node.aec`, button `Sample Plugin`) — mirrors `src/SamplePlugin/App.cs`

```csharp
// Requires: using Autodesk.Windows;   (AdWindows — ComponentManager)
// RECOMMENDED pattern: NO Node.aec Connector API calls anywhere in this class, so the
// Ribbon comes up even when the connector is missing and startup never JIT-loads it.
// Licensing lives in the commands (§9), never here.
public class App : IExternalApplication
{
    // Shared canonical tab — THE tab. Never a plugin-owned one.
    public const string TabName = "Node.aec";   // string copy of the convention; no type use
    public const string CompanyName = "Node.aec";   // group title: your company, same in all your plugins
    public const string PanelName = "SamplePlugin";  // internal, unique to this plugin
    public const string ButtonId = "SamplePlugin_HelloWorld";   // "<Plugin>_" keeps your buttons together
    public const string ButtonText = "Sample\nPlugin";

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
            panel.Title = CompanyName;   // the Connector merges same-title panels into one group

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
                    // Same id = leftover copy. Same title = same company's other plugin: keep it.
                    bool already = primary.Panels.Any(q =>
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
Source: [App.cs](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs) — constants [L29-L38](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs#L29-L38), startup [L47](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs#L47), tab [L100](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs#L100), panel [L118-L130](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs#L118-L130), hooks [L175-L179](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs#L175-L179), dedup [L200](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/App.cs#L200).

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
- **No plugin-side logging API exists**: Lite is silent by design (§4.4). Log `gate.Reason`
  yourself if you need it; Hub-side issues live in the Hub's own log when it is installed.

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

License-package pins (all years, via `NodeAec.Licensing.Lite 0.3.0`):

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
- Your plugin deploys as its own bundle under `%ProgramData%\Autodesk\ApplicationPlugins\`
  (§3.3); the Hub lives in its own `NodeAec.Connector.bundle` and is never referenced (§3.1).

### 8.2 Assembly versioning

- License package: `NodeAec.Licensing.Lite`, `<Version>0.3.0</Version>` (assembly version
  `0.3.0.0`), `RootNamespace NodeAec.Licensing`, TFMs `net48;net8.0-windows;net10.0-windows`,
  strong-named with `PublicKeyToken=b00754dbadfd618b` since 0.2.0; no Authenticode (see
  `revit-licensing-lite/docs/signing.md`). Restored from NuGet.org.
- **Versions meet in one Revit process.** The Connector references the same package, and
  so may other partner plugins. On Revit 2023/2024 (.NET Framework 4.8) different
  strong-named versions load side by side. On Revit 2025+ (.NET 8/10) only one version
  loads, the first one, and a later request for a **higher** version fails with
  `FileLoadException`. The Connector loads Lite at startup and always ships the newest
  release, and Lite is additive-only, so a plugin built against the same or an older Lite
  keeps working. Practical rules: build against the Lite version the current Connector
  ships (or older); rebuild and re-test when you bump it; don't hard-code it in plugin code.
- Key rotation between Lite releases is additive: `TrustedAnchors[]` carries the
  current key plus the next one (N/N+1), so a new package keeps validating leases
  signed before the rotation.

---

## 9. Command recipe (`HelloCommand.cs`)

The whole integration of this sample is one file. There is no wrapper class and no
`try/catch` around the gate:

- `Gate.Validate` never throws and never returns `null`; every failure comes back as
  `IsLicensed = false`, so a catch would only add a path to get wrong.
- Lite ships inside the plugin's folder, so there is no "Hub missing" branch: a machine
  without the Hub has no lease and validates as `NoLease`.
- The message is shown in Revit's UI language, as-is, as the whole dialog content.
- The license key is never shown or logged.

```csharp
using System;
using System.Globalization;
using System.Text;
using Autodesk.Revit.ApplicationServices;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using NodeAec.Licensing;

namespace SamplePlugin.Commands;

/// <summary>
/// Sample commercial command: the license gate runs FIRST and the command never runs
/// unlicensed. Licensed → greets the user with the license details. Not licensed → shows
/// the gate's message, in Revit's UI language, with a link that opens the Node.aec
/// Connector, then returns <see cref="Result.Cancelled"/>.
/// </summary>
[Transaction(TransactionMode.Manual)]
public class HelloCommand : IExternalCommand
{
    /// <summary>
    /// The product slug registered in the Node.aec catalog: the one value to change when you
    /// copy this sample. Share it between your commands if you have several.
    /// </summary>
    public const string ProductSlug = "revit-sample-plugin";

    /// <summary>Title of the success dialog.</summary>
    private const string Title = "Hello World";

    /// <summary>Title of the dialog shown when there is no valid license.</summary>
    private const string BlockedTitle = "Sample Plugin — License Required";

    /// <summary>
    /// Executes the command. The first statement is the local license gate.
    /// </summary>
    /// <param name="commandData">Revit context for this execution.</param>
    /// <param name="message">Unused: failures show a dialog and return Cancelled.</param>
    /// <param name="elements">Unused.</param>
    /// <returns><see cref="Result.Succeeded"/> only when licensed; otherwise <see cref="Result.Cancelled"/>.</returns>
    public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
    {
        // Local check, no network. Gate.Validate never throws: every failure comes back as
        // IsLicensed = false, so no try/catch is needed. Decide on IsLicensed only.
        Snapshot gate = Gate.Validate(ProductSlug);
        if (!gate.IsLicensed)
        {
            ShowBlockedDialog(gate.GetMessage(UserLanguage(commandData)));
            return Result.Cancelled;
        }

        TaskDialog.Show(
            Title,
            $"Hello, {Environment.UserName}!\n\n" +
            "Sample Plugin verified your Node.aec license locally (no network call) " +
            "and is ready to run.\n\n" +
            BuildLicenseBlock(gate));
        return Result.Succeeded;
    }

    /// <summary>
    /// Node.aec messages come in Portuguese and English: follow Revit's UI language.
    /// </summary>
    private static MessageLanguage UserLanguage(ExternalCommandData commandData) =>
        commandData.Application.Application.Language == LanguageType.Brazilian_Portuguese
            ? MessageLanguage.Portuguese
            : MessageLanguage.English;

    /// <summary>
    /// Shows the "not licensed" dialog: the gate's message and a link that opens the Connector.
    /// <para>
    /// The message already names the one specific reason and the next step, so it is the
    /// whole content. Do not add a generic list of possible causes: the user cannot tell
    /// which one applies, and the real reason gets buried.
    /// </para>
    /// </summary>
    /// <param name="reason">The gate's message, in the user's language.</param>
    private static void ShowBlockedDialog(string reason)
    {
        var dialog = new TaskDialog(BlockedTitle)
        {
            MainInstruction = "Sample Plugin requires an active Node.aec license.",
            MainContent = reason,
            CommonButtons = TaskDialogCommonButtons.Close
        };

        dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");

        // OpenConnector does nothing when the Connector is not installed, which is why the
        // dialog always comes first.
        if (dialog.Show() == TaskDialogResult.CommandLink1)
        {
            Gate.OpenConnector();
        }
    }

    /// <summary>
    /// Formats the license details of the success dialog. The license key is left out on
    /// purpose: it is the end user's secret and is never shown or logged.
    /// </summary>
    /// <param name="gate">A licensed gate result.</param>
    /// <returns>Multi-line license block.</returns>
    private static string BuildLicenseBlock(Snapshot gate)
    {
        var block = new StringBuilder();
        block.AppendLine("License (as reported by Node.aec):");
        block.Append("  Product     : ").AppendLine(gate.ProductName ?? "(not reported)");
        block.Append("  Type        : ").AppendLine(gate.LicenseType ?? "(not reported)");
        block.Append("  Valid until : ").AppendLine(
            gate.ExpiresAt is { } expiry
                ? expiry.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                : "no end date (perpetual)");
        return block.ToString();
    }
}
```
Source: [HelloCommand.cs](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/Commands/HelloCommand.cs).

To adapt it: change `ProductSlug`, rename the namespace and titles, and put your feature
where the greeting is. With several commands, move `ProductSlug` and `UserLanguage` to a
small shared static class.

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
(assembly absent, window open failure). Your own dialog must already show the message —
never rely on the window appearing.

**Q: The user says "I have a license" but the command cancels with
`NoLease` (*No Node.aec credentials were found…* / *Nenhuma credencial do Node.aec…*).**
This single reason covers **not authenticated and connector-not-installed** (§5 row 2).
Check that the connector is installed for this Revit year, then have the user log in /
activate a key in the connector and re-run.

**Q: `ProductNotFound` (*The product 'revit-sample-plugin' is not among this account's active licenses…*).**
Entitlement missing for the slug — either not purchased/activated, or your `ProductSlug`
does not match the catalog slug (matching is `Trim()` + case-insensitive). Point the user at
the catalog: `ProductLinks.BuildProductUrl(slug)`.

**Q: Can I branch on the message text (e.g. `Contains("expirou")`)?**
No. Message wording may change between versions. Use `gate.Reason` to tell cases apart
(logs, UI tweaks); decide whether to run only on `IsLicensed`; show the message verbatim.

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
| **Connector / Hub** | `NodeAec.Connector` — Node.aec desktop governance add-in: auth, lease sync (verified with the same Lite package), canonical Ribbon tab. Installed per Revit year; never referenced or shipped by plugins |
| **Gate** | `NodeAec.Licensing.Gate` — the local, offline, fail-closed validation entry point (Lite, compiled into your plugin) |
| **`Snapshot`** | Immutable result of `Gate.Validate`; only `IsLicensed` branches |
| **`GateReason`** | Enum naming the case behind a `Snapshot` (`Licensed`, `NoLease`, `ProductNotFound`, …); numbers never change |
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
| **`.addin`** | Revit manifest pointing at an assembly; in a bundle it sits in `Contents\<group>\` next to the DLL |
| **`.bundle`** | Autodesk package folder under `%ProgramData%\Autodesk\ApplicationPlugins\`; its `PackageContents.xml` maps each Revit year to a `Contents\<group>\` build |
| **`RevitYear`** | MSBuild property `2023`–`2027` selecting TFM and API packages |
| **TFM** | Target framework: `net48`, `net8.0-windows`, `net10.0-windows` per year |
| **Hub / ConnectorApiClient** | Connector's internal HTTP client + cloud API — out of bounds for plugins |

---

## 12. Verification & related documents

- **Gate surface verified against `NodeAec.Licensing.Lite 0.3.0`** — every
  `Gate`/`Snapshot`/`GateReason` identifier, signature and verbatim message above was
  checked against the Lite source. The `NodeAec.Templates.RevitPlugin` template 0.4.0
  generates this same shape, bundle installer included, with `NodeAec.product.json` and
  `/WaitForRevit` (0.3.0 had neither; 0.2.0 generated the same code with
  per-group `.addin` installers; 0.1.0 generated an older wrapper class, pinned a Lite version
  that is not on NuGet.org, and wrote a `.addin` with invalid XML).
- **Hub behavior verified against revit-connector@7366482** — the Hub-side facts
  retained in this document (SSO/lease-sync ownership, Hub log path, `OpenConnector`
  reflection target, shared-tab ownership) were checked against the connector source
  at that commit.
- Sample-side identifiers (`App`, `HelloCommand`, `SamplePlugin.addin`) match the shipped
  `src/` code, and `Source:` links above
  point at the authoritative location for each excerpt.
- Related documents in this repository: [`README.md`](README.md) · [`AGENTS.md`](AGENTS.md) ·
  [`.agents/skills/licensing-integrate/SKILL.md`](.agents/skills/licensing-integrate/SKILL.md)
- **Remaining uncertainties are flagged inline with [Uncertain]/GUESS**: off-UI-thread
  behavior of `Validate`/`OpenConnector` (§7), partner support for
  `App.DeduplicateRibbonTabs`/`CleanRogueRibbonElements` (§6), and the future of a
  machine-readable failure code (§4.2).

---

## 13. Migrating an existing plugin to Lite

The agent version of this section, with the inventory to make first and the packaging
choices, is the skill's
[`references/migration.md`](.agents/skills/licensing-integrate/references/migration.md).

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

`Snapshot` (§4.2): `IsLicensed` (the only branch point), `Reason`, `GetMessage(language)`
/ `Message`, `ProductName`, `LicenseType`, `LicenseKey` (secret), `ExpiresAt`
(`null` = no claim / perpetual). Lite ships compiled in, so "Hub absent" becomes
"no lease" (`NoLease`, §5 #2), never a load crash. Each `IExternalCommand.Execute` calls
`Gate.Validate(ProductSlug)` as its first statement, fail-closed with `Result.Cancelled`.

**Step 1 — Catalog slug.** Register your product in the Node.aec catalog and take
its slug. It becomes the single `ProductSlug` constant you add in Step 3
(this sample: [`revit-sample-plugin`](https://nodeaec.com.br/products/revit-sample-plugin)).
Matching is `Trim()` + case-insensitive.

**Step 2 — Add the package.**

```bash
dotnet add package NodeAec.Licensing.Lite
```

which declares the latest version (pin the one the current Connector ships, or an older
one — §8.2; `AGENTS.md` §13 says where to look it up):

```xml
<PackageReference Include="NodeAec.Licensing.Lite" Version="0.3.0" />
```

The decision compiles into your assembly and restores from NuGet, so a machine
without the Hub builds identically — nothing to copy or wire.

**Step 3 — Wrap each billable `Execute`.** Inventory every
`IExternalCommand.Execute` (and any other entry point that runs licensed work);
the only exception is an entry point whose sole purpose is license recovery (a
button that only opens the connector). A billable command without a gate is a
release blocker, not a TODO. Declare `ProductSlug` with your Step-1 slug, then
gate each command as its first statement, one call per execution (it performs disk
I/O; never in a per-element loop or in `DynamicUpdaters`), branching only on
`IsLicensed`, with the message verbatim + `Gate.OpenConnector()` + `Result.Cancelled`:

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
    Snapshot gate = Gate.Validate(ProductSlug); // 1st line — nothing before (no dialog, no Transaction)
    if (!gate.IsLicensed)
    {
        ShowBlockedDialog(gate.GetMessage(UserLanguage(c))); // verbatim + link Gate.OpenConnector
        return Result.Cancelled;
    }
    ShowMyFeature(c);
    return Result.Succeeded;
}
```

`ShowBlockedDialog`, `UserLanguage` and `BuildLicenseBlock` are in §9.

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
net48) **ships together** via `CopyLocalLockFileAssemblies=true`. One bundle
(`ApplicationPlugins\YourPlugin.bundle\`) with a `Contents\<group>\` folder per
compatibility group, each holding the manifest with relative `<Assembly>YourPlugin.dll</Assembly>`
(§3.3).

**Step 7 — Manual protocol** (real Revit session; DPAPI requires interactive logon):

| # | Case | Expected |
|---|---|---|
| 1 | Licensed (Hub installed, entitled session) | Greeting + license block (no key), `Result.Succeeded` |
| 2 | Blocked (no session / wrong slug / expired / seat) | Message verbatim in Revit's UI language + link, `Result.Cancelled` |
| 3 | No Hub (connector uninstalled/folder renamed) | Same blocked state (`NoLease`), silent no-op on the link, no crash, `Result.Cancelled` |
| 4 | Reload 2× via Add-In Manager | One `Node.aec` tab, one button (no ghost tab) |

Being offline is not a failure (§5): only `exp` bounds validity. Cross-check with
`%APPDATA%\NodeAec\connector.log` in cases 2–3 (`WARN`/`ERROR`, never secrets).

---

## 14. Agent / CI verification track

Executable checklist (human or agent, same order):

- [ ] `grep -rn 'using NodeAec.Connector' --include='*.cs' src/` empty (standalone
  plugins never reference Hub types; only `NodeAec.Licensing` is used)
- [ ] `grep -rn 'HintPath.*NodeAec' --include='*.csproj' src/` empty and no
  `ProjectReference.*Connector` (no DLL reference of any kind — Lite arrives via
  `PackageReference`)
- [ ] `2023..2027` matrix compiles with 0 errors (restore
  failures read `NU1101`)
- [ ] payload with no `RevitAPI*.dll`, `AdWindows.dll`, `NodeAec.Connector.dll`;
  Lite + deps ship together (`ProtectedData.dll` only on net48)
- [ ] each `Contents\<group>\` folder of the bundle holds the manifest with a relative
  `<Assembly>` (or, with the plugin's own installer, the manifest's `<Assembly>` points at
  the installed DLL)
- [ ] manual protocol §13 Step 7 completed (licensed / blocked / no-lease /
  reload with no ghost tab)
- [ ] `Source:` links re-anchored (any moved `src/` → verify each link)

**`nodeaec-verify` (concept — future SHALL).** No verification script exists
in this repo today (confirmed by grepping `scripts/`); CI SHALL gain a
`nodeaec-verify` that blocks: `RevitAPI*`/`AdWindows`/`Connector.dll` in a plugin
payload, a bundle group without its manifest, a `HintPath` to a connector DLL, and
`ProtectedData.dll` outside net48. Until it exists, the checklist above is the verification
— do not invent an existing file.
