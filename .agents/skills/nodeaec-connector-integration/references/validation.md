# Validation — build matrix + manual Revit test script

Deep detail for step 8 of SKILL.md.

## 1. Build matrix

SDK-style csproj; the year selects the TFM and the connector HintPath folder:

```bash
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2023   # net48
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2024   # net48
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2025   # net8.0-windows
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026   # net8.0-windows (default)
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2027   # net10.0-windows
```

Machine without the connector installed (CI compile-only):

```bash
dotnet build src/SamplePlugin/SamplePlugin.csproj -p:RevitYear=2026 \
  -p:NodeAecConnectorDll=/path/to/NodeAec.Connector.dll
```

Payload hygiene — the `release/`/`stage/` output must contain **neither**
`RevitAPI*.dll` **nor** `NodeAec.Connector.dll`. Manifest layout:

```
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin.addin          (root)
%ProgramData%\Autodesk\Revit\Addins\<year>\SamplePlugin\SamplePlugin.dll
```

## 2. Manual Revit test script

Run all five cases on a real Revit session per supported year (DPAPI needs an
interactive logon — CI/headless cannot cover this). Record: dialog shown,
`Message` text, button behavior, and the command's return.

| # | Case | Setup | Expected |
|---|---|---|---|
| 1 | **No connector** | Uninstall the Node.aec Connector for that year (or rename its `Addins\<year>\NodeAec.Connector\` folder), restart Revit | Command still loads; gate fails at the seam; blocked dialog with `ConnectorUnavailableMessage`; `Open Node.aec Connector...` click is a silent no-op; `Result.Cancelled`; no crash |
| 2 | **Not signed in** | Connector installed; clear the session / sign out (lease absent) | Blocked dialog showing connector `Message` verbatim (`Nenhuma credencial do Node.aec encontrada nesta estação…`); command link opens the connector UI; `Result.Cancelled` |
| 3 | **No entitlement** | Signed in with an account that lacks slug `sample-plugin` (or a typo'd `ProductSlug`) | Blocked dialog with `O produto 'sample-plugin' não consta nas licenças ativas desta conta…` verbatim; `Result.Cancelled` |
| 4 | **Expired** | Entitlement past `ExpiresAt` (test account, or wait out offline grace) | Blocked dialog with `A licença ou período de teste de '…' expirou em {dd/MM/yyyy}.` verbatim; `Result.Cancelled` |
| 5 | **Valid** | Connector installed, signed in, entitled for `sample-plugin` | Licensed greeting; license block shows Product / Type / License key / Valid until / Status from the real fields; `Result.Succeeded` |

Cross-checks after the run:

- Ribbon: shared `Node.aec` tab with panel `Sample Plugin` and button
  `Hello World`; reload the add-in (Add-In Manager) twice — still one tab, one
  button (idempotency + AdWindows dedup hooks).
- `%APPDATA%\NodeAec\connector.log` for cases 2–4 (`WARN`/`ERROR` lines, never
  tokens or keys).
- Negative network test: run cases 2–5 with the machine offline — offline is
  not a failure (API.md §5); only lease expiry (case 4) differs.
