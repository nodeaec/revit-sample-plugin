# Validation — build matrix + manual Revit test script

Deep detail for step 8 of SKILL.md.

## 1. Build matrix

SDK-style csproj; the year selects the TFM and the Lite package restores from
NuGet (no DLL override, no `HintPath` — API.md §13):

```bash
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2023   # net48
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2024   # net48
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2025   # net8.0-windows
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026   # net8.0-windows (default)
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2027   # net10.0-windows
```
Source: canonical forms documented in [SamplePlugin.csproj:L16-L18](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.csproj#L16-L18).

Restore failure now reads `NU1101` (package not found — check the feed/version),
not the legacy `MSB3245` (pre-Lite `HintPath` miss, kept as history in AGENTS.md
§5). No `-p:NodeAecConnectorDll` anymore: nothing points at a loose DLL.

Payload hygiene — the `release/`/`stage/` output must contain **neither**
`RevitAPI*.dll`/`AdWindows.dll` **nor** `NodeAec.Connector.dll`, while Lite and
its deps **travel together** (`NodeAec.Licensing.Lite.dll`,
`BouncyCastle.Cryptography.dll`, plus `System.Text.Json.dll` /
`System.Security.Cryptography.ProtectedData.dll` on net48 only). Manifest layout:

```
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin          (root)
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin\SamplePlugin.dll
```
Source: [SamplePlugin.addin](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/SamplePlugin.addin).

## 2. Manual Revit test script

Run all six cases on a real Revit session per supported year (DPAPI needs an
interactive logon — CI/headless cannot cover this). Record: dialog shown,
`Message` text, button behavior, and the command's return.

| # | Case | Setup | Expected |
|---|---|---|---|
| 1 | **Licensed (valid)** | Connector installed, signed in, entitled for `revit-sample-plugin` | Licensed greeting; license block shows Product / Type / License key / Valid until / Status from the real fields; `Result.Succeeded` |
| 2 | **Blocked — not signed in** | Connector installed; clear the session / sign out (lease absent) | Blocked dialog showing gate `Message` verbatim (`Nenhuma credencial do Node.aec encontrada nesta estação…`); command link opens the connector UI; `Result.Cancelled` |
| 3 | **Blocked — no entitlement** | Signed in with an account that lacks slug `revit-sample-plugin` (or a typo'd `ProductSlug`) | Blocked dialog with `O produto 'revit-sample-plugin' não consta nas licenças ativas desta conta…` verbatim; `Result.Cancelled` |
| 4 | **Blocked — expired** | Entitlement past `ExpiresAt` (test account, or wait out offline grace) | Blocked dialog with `A licença ou período de teste de '…' expirou em {dd/MM/yyyy}.` verbatim; `Result.Cancelled` |
| 5 | **No lease (Hub absent)** | Uninstall the Node.aec Connector for that year (or rename its `Addins\<year>\NodeAec.Connector\` folder), restart Revit | Command still loads; gate reads no lease; blocked dialog with `Nenhuma credencial…` verbatim; `Open Node.aec Connector...` click is a silent no-op; `Result.Cancelled`; no crash |
| 6 | **Reload (no ghost tab)** | Add-In Manager → reload the add-in twice | Still one `Node.aec` tab, one button (idempotency + AdWindows dedup hooks) |

## 3. `nodeaec-verify` (concept — future SHALL, no real script today)

Confirmed: `scripts/` contains only `release.ps1`/`installer.iss` (+afters). CI
SHALL gain a `nodeaec-verify` that fails when: the payload contains
`RevitAPI*`/`AdWindows`/`UIFramework*`/`NodeAec.Connector.dll`; the manifest is outside the
year root or `<Assembly>` is not relative; a `HintPath.*NodeAec.Connector` or
`ProjectReference.*Connector` remains in the csproj; `ProtectedData.dll` is outside the
net48 payload. Until it exists, the checklist grep (API.md §14) applies — do not quote
a script path as if it existed.

Cross-checks after the run:

- `%APPDATA%\NodeAec\connector.log` for cases 2–4 (`WARN`/`ERROR` lines, never
  tokens or keys).
- Negative network test: run cases 1–5 with the machine offline — offline is
  not a failure (API.md §5); only lease expiry (case 4) differs.
