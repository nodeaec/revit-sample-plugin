# Sample Plugin

A tiny Revit plugin — one button, one command — that shows how to license-gate a command with the **Node.aec Connector**. Change exactly one constant (`sample-plugin`) and the pattern becomes yours.

---

## What is this

**Sample Plugin** is the reference add-in for partner plugins on the Node.aec platform. It adds a single **Hello World** button to the shared **Node.aec** Ribbon tab (panel **Sample Plugin**) and does one interesting thing: it asks the local license gate before running anything.

The demo behavior:

- **License valid and active** → you get `Hello, <user>!` plus an informative license card built from the real `GateResult` fields: **Product**, **Type**, **License key**, **Valid until** and **Status** (`NodeAecLicenseGate.BuildLicenseBlock`).
- **Anything else** → a precise, fail-closed error. Not signed in, license expired, the product isn't in this account's entitlements, seat limit reached, offline grace over, or the connector isn't installed at all — the connector's own `Message` is shown verbatim, plus short guidance and an **Open Node.aec Connector...** action.

There is no path past the gate. Every non-licensed outcome ends in `Result.Cancelled` — the command never runs unlicensed.

## How it works

```
Hello World click
  └─ SamplePlugin.Commands.HelloCommand.Execute (first statement)
       └─ NodeAecLicenseGate.Validate()            → GateSnapshot (never throws)
            └─ NodeAecGate.Validate("sample-plugin")  local disk + DPAPI + Ed25519, zero network
                 ├─ IsLicensed == true  → greeting + license card → Result.Succeeded
                 └─ IsLicensed == false → blocked dialog (Message verbatim + action) → Result.Cancelled
```

`GateSnapshot` is a plugin-local, connector-free mirror of the gate outcome, so a machine *without* the connector still fails closed with this plugin's own dialog instead of a load crash.

| Gate outcome | What the user sees |
|---|---|
| `IsLicensed == true` | `Hello World` dialog + license card: Product / Type / License key / Valid until / Status |
| Not signed in (or never authenticated) | `Nenhuma credencial do Node.aec encontrada nesta estação…` + guidance + **Open Node.aec Connector...** → `Result.Cancelled` |
| License or trial expired | `A licença ou período de teste de '{Name}' expirou em {dd/MM/yyyy}.` → `Result.Cancelled` |
| Product not entitled / wrong slug | `O produto 'sample-plugin' não consta nas licenças ativas desta conta…` → `Result.Cancelled` |
| Seat limit reached | `O limite de computadores simultâneos para '{Name}' foi atingido.` → `Result.Cancelled` |
| Offline grace expired | `O prazo de tolerância offline expirou em {dd/MM/yyyy}…` → `Result.Cancelled` |
| Connector not installed / not loadable | Seam's own `ConnectorUnavailableMessage` (English, `ConnectorAvailable = false`) → same blocked dialog → `Result.Cancelled` |

Full taxonomy of the 17 failure texts plus the success text: [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy).

## Try it

**Prerequisites**

1. **Revit 2023–2027** (this sample builds for all five years).
2. **Node.aec Connector installed** for that Revit year — it owns sign-in, entitlements and the gate.
3. **Signed in** in the connector and **entitled** to the `sample-plugin` product.

**Build** ([API.md §8 — Versioning & compatibility matrix](API.md#8-versioning--compatibility-matrix)):

```bash
# The matrix, verbatim from API.md §8.1 — default is 2026
dotnet build -p:RevitYear=<2023..2027>

# Machine without the connector installed: point the reference at any NodeAec.Connector.dll
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026 -p:NodeAecConnectorDll=<path-to-NodeAec.Connector.dll>
```

| `RevitYear` | 2023 | 2024 | 2025 | 2026 | 2027 |
|---|---|---|---|---|---|
| Target framework | `net48` | `net48` | `net8.0-windows` | `net8.0-windows` | `net10.0-windows` |

**Install** — the packaging contract from [API.md §3.3 — Packaging contract (manifest + payload layout)](API.md#33-packaging-contract-manifest--payload-layout--verified):

```
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin            ← from bin\<year>\...\ (root)
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin\SamplePlugin.dll ← payload subfolder
```

`<Assembly>` in the manifest is `SamplePlugin\SamplePlugin.dll`, relative to the manifest — that layout is what the relative path assumes. Never ship `NodeAec.Connector.dll` or `RevitAPI*.dll` beside your plugin.

**Launch** Revit, open the **Node.aec** tab, click **Hello World** in the **Sample Plugin** panel. Licensed → greeting + card; not licensed → the blocked dialog with an open-connector action.

## Integrate your own plugin with Node.aec

Eight steps. Each one is a change you can lift straight out of this repo, with the matching [API.md](API.md) section for the details and the edge cases.

**1. Understand the split.** The platform/connector owns accounts, lease sync and validation; your plugin only calls the gate at command entry. Nothing else in your codebase should ever touch licensing decisions — or the network.

```csharp
/// THE integration seam of this sample: everything the plugin knows about Node.aec
/// licensing lives in this file. Port it to your own plugin, change
/// <see cref="ProductSlug"/>, and keep the rest of your code connector-free.
```
→ [API.md §1 — Overview & responsibility split](API.md#1-overview--responsibility-split)

**2. Register your product slug.** Your product gets a slug in the Node.aec catalog; it is the single constant this sample changes. Match is `Trim()` + case-insensitive against the entitlement claim `slug`.

```csharp
public static class NodeAecLicenseGate
{
    /// THE one constant to change when adapting this sample to another product:
    /// the product slug as registered in the Node.aec catalog / entitlement claims.
    public const string ProductSlug = "sample-plugin";
```
→ [API.md §4 — Public integration surface](API.md#4-public-integration-surface)

**3. Add the reference.** Build-time `Reference` + `HintPath` + `<Private>False</Private>` against the *installed* connector — not NuGet, not a project reference, never a copied DLL.

```xml
<NodeAecConnectorDll Condition="'$(NodeAecConnectorDll)' == ''">$(ProgramData)\Autodesk\Revit\Addins\$(RevitYear)\NodeAec.Connector\NodeAec.Connector.dll</NodeAecConnectorDll>
...
<Reference Include="NodeAec.Connector">
  <HintPath>$(NodeAecConnectorDll)</HintPath>
  <Private>False</Private>
</Reference>
```
→ [API.md §3 — The integration path (authoritative)](API.md#3-the-integration-path-authoritative)

**4. Port the licensing seam.** Copy `NodeAecLicenseGate.cs` verbatim, change `ProductSlug`. It maps `GateResult`'s six members into a plain `GateSnapshot` and isolates every connector-type reference so a missing DLL becomes a fail-closed snapshot, not a crash.

```csharp
public static GateSnapshot Validate()
{
    try { return RunValidation(); }   // a JIT load failure of NodeAec.Connector lands HERE
    catch (Exception) { return new GateSnapshot(isLicensed: false, message: ConnectorUnavailableMessage,
        productName: null, licenseType: null, licenseKey: null, expiresAt: null, connectorAvailable: false); }
}
```
→ [API.md §9 — Fail-closed recipe (`NodeAecLicenseGate.cs`)](API.md#9-fail-closed-recipe-nodeaeclicensegatecs)

**5. Gate every command.** First statement of `Execute`, once per execution — never inside per-element loops. Branch on `IsLicensed` only; anything unknown or null fails closed.

```csharp
gate = NodeAecLicenseGate.Validate();          // first statement of the command
...
if (!gate.IsLicensed)
{
    ShowBlockedDialog(gate);                   // Message verbatim + guidance + action
    return Result.Cancelled;                   // no code path past the gate
}
```
→ [API.md §2 — Quickstart (happy path)](API.md#2-quickstart-happy-path) and [§7 — Threading & Revit API-context rules](API.md#7-threading--revit-api-context-rules)

**6. Place your ribbon under the shared tab.** One shared `Node.aec` tab, your own panel and button inside it — never a plugin-owned tab. Tab creation tolerates only the "already exists" `ArgumentException`, panel/button insertion is idempotent, and two AdWindows hooks re-run a local, connector-free dedup.

```csharp
try { application.CreateRibbonTab(TabName); }
catch (Exception ex) when (ex is Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)
{ /* the connector already created it — normal */ }

var found = existing.FirstOrDefault(p => string.Equals(p.Name, panelName, StringComparison.OrdinalIgnoreCase));
if (found != null) return found;               // idempotent: reuse instead of duplicating
```
→ [API.md §6 — Ribbon integration conventions](API.md#6-ribbon-integration-conventions)

**7. Handle failures with actionable messages + `OpenConnector()`.** Show the connector's `Message` verbatim (never string-match or translate it), add short guidance, offer an action link, then `Result.Cancelled`. `OpenConnector()` is a silent no-op when the connector is absent — your dialog must carry the guidance on its own.

```csharp
var dialog = new TaskDialog(BlockedTitle)
{
    MainInstruction = "Sample Plugin requires an active Node.aec license.",
    MainContent = $"Reason reported by Node.aec:\n{gate.Message}\n\n" + /* short guidance bullets */,
    CommonButtons = TaskDialogCommonButtons.Close
};
dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");
if (dialog.Show() == TaskDialogResult.CommandLink1) NodeAecLicenseGate.OpenConnector();
```
→ [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy)

**8. Validate with the manual test protocol.** Walk the taxonomy in a real Revit session: signed out, expired, wrong slug, seat limit, offline grace, connector uninstalled — each must produce the blocked dialog + `Result.Cancelled`, and only a healthy license may reach the greeting. DPAPI needs an interactive logon session, so headless CI cannot prove this part.

```csharp
string content =
    $"Hello, {Environment.UserName}!\n\n" +
    "Sample Plugin verified your Node.aec license locally (no network call) and is ready to run.\n\n" +
    NodeAecLicenseGate.BuildLicenseBlock(gate);
TaskDialog.Show(Title, content);
return Result.Succeeded;                       // only reachable with IsLicensed == true
```
→ [API.md §10 — Troubleshooting / FAQ](API.md#10-troubleshooting--faq) and [§12 — Verification & related documents](API.md#12-verification--related-documents)

## Let your agent do it for you

Copy-paste this into your coding agent, from inside your own plugin repo:

```AGENT PROMPT
You are integrating the Node.aec Connector license gate into my Revit plugin.

Repo to learn from: https://github.com/nodeaec/revit-sample-plugin
Read, in this order, before writing any code:
  1. AGENTS.md
  2. .agents/skills/nodeaec-connector-integration/SKILL.md
  3. API.md  (the authoritative reference — follow its section titles; do not invent API)

Target repo (mine): <your-plugin-repo>

Confirm this prerequisite checklist FIRST — stop and ask me if any item is unresolved:
  [ ] Target Revit year chosen (2023, 2024, 2025, 2026 or 2027) and its TFM known
      (2023/2024 = net48, 2025/2026 = net8.0-windows, 2027 = net10.0-windows)
  [ ] Node.aec Connector installed for that year at
      %ProgramData%\Autodesk\Revit\Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll
  [ ] My product slug, registered in the Node.aec catalog: <your-product-slug>
  [ ] A signed-in connector session entitled to that slug, for manual verification
  [ ] My plugin's commands are reachable from Ribbon buttons I control

Then perform the integration in <your-plugin-repo>:
  1. Add the build-time Reference + HintPath + <Private>False</Private> for NodeAec.Connector
     (API.md §3). NOT NuGet, NOT a ProjectReference, NEVER copy the DLL.
  2. Port src/SamplePlugin/Licensing/NodeAecLicenseGate.cs unchanged except
     ProductSlug = "<your-product-slug>" (API.md §9).
  3. In EVERY IExternalCommand, call NodeAecLicenseGate.Validate() as the first statement,
     branch only on snapshot.IsLicensed, show Message verbatim + guidance +
     NodeAecLicenseGate.OpenConnector() on failure, and return Result.Cancelled (API.md §2, §7).
  4. On success, keep feature code behind the gate; use BuildLicenseBlock-style display
     only from the snapshot's six fields — never invent fields the connector does not expose.
  5. Put my button in the shared Node.aec tab as my own panel: idempotent tab/panel/button
     insertion, filtered ArgumentException catch, "-=" before "+=" AdWindows hooks, local
     connector-free dedup (API.md §6). No plugin-owned tab.
  6. Keep my add-in startup connector-free (no Node.aec types in IExternalApplication).
  7. Build with -p:RevitYear=<year> for every year I support (API.md §8); on machines
     without the connector use -p:NodeAecConnectorDll=<path>.
  8. Report exactly what you changed, file by file, and list the manual test protocol cases
     I still have to run in Revit (API.md §10) — do not claim runtime verification you
     cannot perform.

Rules: never weaken the gate, never cache a licensed result across commands, never
string-match Message, never translate it in code, never add HTTP calls.
```

**Installing the skill:** this repo ships `.agents/skills/nodeaec-connector-integration/SKILL.md`. Copy that folder into your repo's `.agents/skills/` directory (so every clone of your repo gets it) or into your agent's global skills directory, and it will load automatically when your agent works on Node.aec integration tasks. [AGENTS.md](AGENTS.md) is the always-on companion brief for agents in this repo.

## Troubleshooting

Grounded in [API.md §5 — Status / reason taxonomy](API.md#5-status--reason-taxonomy) and [§10 — Troubleshooting / FAQ](API.md#10-troubleshooting--faq).

| Symptom (verbatim message or seam text) | Cause | Fix |
|---|---|---|
| `The Node.aec Connector could not be loaded on this station.` | Connector not installed for this Revit year, or not loadable — the seam never reaches the gate (`ConnectorAvailable = false`) | Install/repair the connector for that year; verify `Addins\<year>\NodeAec.Connector\NodeAec.Connector.dll` exists. Do **not** copy the DLL into your add-in folder |
| `Nenhuma credencial do Node.aec encontrada nesta estação…` | Not signed in — never logged in, logged out, or lease file cleared (this same text also appears when the connector was never installed) | Open the Node.aec Connector and sign in / activate a license key, then re-run the command |
| `O produto '{productSlug}' não consta nas licenças ativas desta conta.` | No entitlement for the slug — not purchased/activated, or `ProductSlug` doesn't match the catalog (match is `Trim()` + case-insensitive) | Buy/activate the product in the Node.aec catalog, or fix your `ProductSlug` constant |
| `A licença ou período de teste de '{Name}' expirou em {dd/MM/yyyy}.` | Entitlement `expiresAt` is in the past | Renew in the Node.aec portal, then let the connector synchronize |
| `O limite de computadores simultâneos para '{Name}' foi atingido.` | Seat limit — entitlement `status == "seat_limit_reached"` | Free a seat for this product in the web portal, then revalidate |
| `O prazo de tolerância offline expirou em {dd/MM/yyyy}. Conecte-se à internet para sincronizar.` | Offline grace (default 30 days) expired — lease `exp` is past | Go online and click **Atualizar** in the connector to resync the lease |
| `O produto 'sample-plugin' não consta…` while you expected a license | Wrong slug — your constant doesn't equal the catalog slug | Fix `ProductSlug`; catalog link helper: `ProductLinks.BuildProductUrl(slug)` |
| `A licença local não passou na verificação de segurança…` / `Origem da licença local desconhecida…` | Lease failed Ed25519/`iss`/`scope`/`aud` verification — tampered, foreign or stale lease | Go online and click **Atualizar** in the connector to resync |
| `Não foi possível verificar a licença local.` | Unexpected exception inside the gate (logged `ERROR`) | Open `%APPDATA%\NodeAec\connector.log`, then resync in the connector |
| Two `Node.aec` tabs after an add-in reload | Non-idempotent insertion or missing AdWindows hooks | Re-read [API.md §6](API.md#6-ribbon-integration-conventions): filtered `ArgumentException`, acquire-or-create panel, `-=` before `+=`, local `DeduplicateTab()` |
| Nothing happens when the user clicks "Open Node.aec Connector..." | By contract `OpenConnector()` silently no-ops when the connector UI can't be reached | Expected — your dialog must already carry the guidance |

## Project layout

```
revit-sample-plugin/
├── API.md                                     ← authoritative integration reference
├── AGENTS.md                                  ← brief for coding agents working this repo
├── README.md                                  ← you are here
├── LICENSE
├── .agents/skills/nodeaec-connector-integration/
│   ├── SKILL.md                                ← installable skill for agent-assisted integration
│   └── references/                             ← depth behind the skill (seam walkthrough, test script)
└── src/SamplePlugin/
    ├── SamplePlugin.csproj                    ← RevitYear matrix, the one connector Reference
    ├── SamplePlugin.addin                     ← manifest (Assembly = SamplePlugin\SamplePlugin.dll)
    ├── App.cs                                 ← Ribbon: shared Node.aec tab, panel, button, dedup hooks
    ├── Commands/
    │   └── HelloCommand.cs                    ← gate first, then greet — the whole demo
    └── Licensing/
        └── NodeAecLicenseGate.cs              ← THE seam: Validate(), OpenConnector(), BuildLicenseBlock()
```

## What we validated

- **Build matrix** — green for `RevitYear` 2023–2027 using the `-p:NodeAecConnectorDll=<path>` override on machines without the connector installed. Release outputs are on disk for 2023 (`net48`), 2026 (`net8.0-windows`, default) and 2027 (`net10.0-windows`); 2024 and 2025 share those two TFMs.
- **Behavior in Revit** — verified **only** against the manual protocol (sign out, expired, wrong slug, seat limit, offline grace, connector missing → blocked dialog + `Result.Cancelled`; healthy license → greeting + card). We have not scripted it; DPAPI needs an interactive session, so run the protocol yourself on your target machine.
- **Connector surface** — every identifier and every verbatim message quoted here was checked against revit-connector@`7366482`. Things that remain uncertain are flagged **[Uncertain]/GUESS** inline in [API.md](API.md); treat them as such.

## Links

- [API.md](API.md) — the full integration reference (start at §1, the responsibility split)
- [AGENTS.md](AGENTS.md) — the brief for coding agents in this repo
- [.agents/skills/nodeaec-connector-integration/SKILL.md](.agents/skills/nodeaec-connector-integration/SKILL.md) — the installable agent skill
- [github.com/nodeaec/revit-connector](https://github.com/nodeaec/revit-connector) — the Node.aec Connector itself (read-only upstream)
- [Node.aec platform](https://nodeaec.com.br) — accounts, entitlements, catalog

## License

MIT — Copyright (c) 2026 Node.aec. See [LICENSE](LICENSE).
