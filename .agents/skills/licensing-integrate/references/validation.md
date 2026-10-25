# Validation: build + manual Revit test script

Detail for SKILL.md §7.

## 1. Build

Build each compatibility group with its oldest Revit year (the same builds `release.ps1`
makes); every build must end with 0 errors:

```powershell
dotnet build -p:RevitYear=2023   # net48            (Revit 2023-2024)
dotnet build -p:RevitYear=2025   # net8.0-windows   (Revit 2025-2026)
dotnet build -p:RevitYear=2027   # net10.0-windows  (Revit 2027)
```

A restore failure reading `NU1101` means the package was not found: check the feed and the
version (SKILL.md §9).

Payload hygiene — the `release/`/`stage/` output must contain **neither**
`RevitAPI*.dll`/`AdWindows.dll` **nor** `NodeAec.Connector.dll`, while Lite and
its deps **travel together** (`NodeAec.Licensing.Lite.dll`,
`BouncyCastle.Cryptography.dll`, plus `System.Text.Json.dll` /
`System.Security.Cryptography.ProtectedData.dll` on net48 only). Bundle layout:

```
%ProgramData%\Autodesk\ApplicationPlugins\SamplePlugin.bundle\
  PackageContents.xml                        one component per Revit year
  Contents\<group>\SamplePlugin.addin        Assembly = SamplePlugin.dll (relative)
  Contents\<group>\SamplePlugin.dll          + Lite and its dependencies
```
Example: the Sample Plugin's [`SamplePlugin.addin`](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/SamplePlugin.addin). A plugin that keeps its own installer can use any layout; the payload rules still apply.

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
| 5 | **No lease (Hub absent)** | Uninstall the Node.aec Connector (or rerun its Setup with that year unchecked), restart Revit | Command still loads; gate reads no lease; blocked dialog with `Nenhuma credencial…` verbatim; `Open Node.aec Connector...` click is a silent no-op; `Result.Cancelled`; no crash |
| 6 | **Reload (no ghost tab)** | Add-In Manager → reload the add-in twice | Still one `Node.aec` tab, one button (idempotency + AdWindows dedup hooks) |

## 3. `nodeaec-verify` (concept — future SHALL, no real script today)

Payload check after `release.ps1` (PowerShell, from the project folder); both must print nothing:

```powershell
Get-ChildItem release\stage -Recurse -Include RevitAPI*.dll,AdWindows.dll,UIFramework*.dll,NodeAec.Connector.dll
Get-ChildItem release\stage -Recurse -Filter System.Security.Cryptography.ProtectedData.dll | Where-Object { $_.DirectoryName -notlike "*2023-2024*" }
```

Cross-checks after the run:

- `%APPDATA%\NodeAec\connector.log` for cases 2–4 (`WARN`/`ERROR` lines, never
  tokens or keys).
- Negative network test: run cases 1–5 with the machine offline — offline is
  not a failure ([API.md §5](https://github.com/nodeaec/revit-sample-plugin/blob/main/API.md#5-status--reason-taxonomy)); only lease expiry (case 4) differs.
