# The licensing seam — full walkthrough

Deep detail for steps 2 and 5 of SKILL.md. Canonical source:
`src/SamplePlugin/Licensing/NodeAecLicenseGate.cs` (see also API.md §9
*Fail-closed recipe (`NodeAecLicenseGate.cs`)*).

## Design rules

1. **One file knows Node.aec.** Every `NodeAec.Licensing` type used by the
   plugin lives in `NodeAecLicenseGate.cs`. Commands and ribbon code speak only
   plugin-local types (`GateSnapshot`).
2. **`Validate()` never throws.** Missing lease, corrupt data, unexpected CLR
   noise — everything becomes a not-licensed `GateSnapshot`, so callers can
   always branch on `IsLicensed`. (No `ConnectorAvailable` branch: Lite is
   compiled in via `PackageReference`; a Hub-less machine simply has no lease
   and validates as not-licensed.)
3. **No JIT isolation needed.** Lite compiles INTO the plugin assembly, so there
   is no external DLL whose load can fail at JIT time. The seam stays thin by
   design — one `Gate.Validate(ProductSlug)` call plus a six-member mapping:

   ```csharp
   public static GateSnapshot Validate()
   {
       try { return RunValidation(); }          // Lite never throws; catch = last resort
       catch (Exception)
       {
           return new GateSnapshot(isLicensed: false,
               message: "Node.aec could not verify this plugin's license on this machine, ...",
               productName: null, licenseType: null, licenseKey: null,
               expiresAt: null);
       }
   }

   private static GateSnapshot RunValidation()  // the ONLY method touching Lite types
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
   ```

   `OpenConnector()` calls `Gate.OpenConnector()` directly (Hub absent = the
   Lite silent no-op contract).
4. **Map only the six real members.** `Snapshot` = `IsLicensed`,
   `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`, `Message`. Payload
   fields are `null` on failure. No licensee, plan, seat counts, machine id,
   entitlement slug/status, trial flag, or status enum exists (API.md §4.2
   *`Snapshot` — every member*, API.md §13 for the Lite mapping).
5. **`IsLicensed` is the only branch point.** `Message` is display text —
   Portuguese, free-form, may change between connector versions. Show it
   verbatim; never translate it and never string-match it to decide behavior.

## What each member of the seam does

| Member | Role |
|---|---|
| `public const string ProductSlug = "revit-sample-plugin";` | The one constant to change when adapting |
| `public static GateSnapshot Validate()` | Entry point; never throws; returns a snapshot (never `null`) |
| `private static GateSnapshot RunValidation()` | Single place `Gate.Validate(ProductSlug)` (Lite) is read |
| `public static void OpenConnector()` | Courtesy deep link; Hub absent = Lite silent no-op |
| `public static string BuildLicenseBlock(GateSnapshot)` | Licensed-dialog content: Product / Type / License key / Valid until / Status; `ExpiresAt == null` renders `no expiry recorded (perpetual)` |

## Command-side shape (`SamplePlugin.Commands.HelloCommand`)

```csharp
public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
{
    GateSnapshot gate;
    try { gate = NodeAecLicenseGate.Validate(); }
    catch (Exception) { return ShowFailClosed(); }   // defensive: never proceed unlicensed

    try
    {
        if (gate is null) return ShowFailClosed();   // unknown state ⇒ fail closed
        if (!gate.IsLicensed)
        {
            ShowBlockedDialog(gate);                 // Message verbatim + guidance + link
            return Result.Cancelled;
        }

        string content =
            $"Hello, {Environment.UserName}!\n\n" +
            NodeAecLicenseGate.BuildLicenseBlock(gate);
        TaskDialog.Show(Title, content);
        return Result.Succeeded;
    }
    catch (Exception) { return ShowFailClosed(); }
}
```
Source: [HelloCommand.cs:L36-L80](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L36-L80) (blocked dialog at [L110-L134](https://github.com/nodeaec/revit-sample-plugin/blob/master/src/SamplePlugin/Commands/HelloCommand.cs#L110-L134)).

`ShowBlockedDialog` builds a `TaskDialog` whose `MainContent` starts with
`Reason reported by Node.aec:\n{gate.Message}`, adds fixed guidance bullets
(sign in / renew / buy `'revit-sample-plugin'` / Hub missing / seat limit /
offline grace), adds `AddCommandLink(... "Open Node.aec Connector...")` calling
`NodeAecLicenseGate.OpenConnector()` only on click, and the command then
returns `Result.Cancelled`. There is no code path past the gate without a
license. (Historical note: an early Hub-DLL-reference seam carried a
`ConnectorAvailable == false` branch for "assembly missing" — Lite is always
present, so Hub-less now reads as no-lease.)

## Threading reminder (API.md §7)

Call `Validate()` once per `Execute`, at entry. It does disk I/O (lease read +
DPAPI + key read) on every call but zero network and no Revit API — never put
it in a per-element loop or a `DynamicUpdater`, and call `OpenConnector()` on
the UI thread right after your dialog.
