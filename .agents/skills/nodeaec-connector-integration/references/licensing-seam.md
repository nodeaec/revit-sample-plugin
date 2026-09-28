# The licensing seam — full walkthrough

Deep detail for step 3 of SKILL.md. Canonical source:
`src/SamplePlugin/Licensing/NodeAecLicenseGate.cs` (see also API.md §9
*Fail-closed recipe (`NodeAecLicenseGate.cs`)*).

## Design rules

1. **One file knows Node.aec.** Every `NodeAec.Connector` type used by the
   plugin lives in `NodeAecLicenseGate.cs`. Commands and ribbon code speak only
   plugin-local types (`GateSnapshot`).
2. **`Validate()` never throws.** Missing connector assembly, corrupt lease,
   unexpected CLR noise — everything becomes a not-licensed `GateSnapshot`, so
   callers can always branch on `IsLicensed`.
3. **JIT isolation.** The CLR resolves `NodeAecGate` while *compiling* a method
   whose body mentions it. With `<Private>False</Private>` and the connector
   absent, that resolution fails when the method first runs — so a connector
   type must never appear in `Validate()`'s own body. The pattern:

   ```csharp
   public static GateSnapshot Validate()
   {
       try { return RunValidation(); }          // called INSIDE the try
       catch (Exception)
       {
           return new GateSnapshot(isLicensed: false,
               message: ConnectorUnavailableMessage,
               productName: null, licenseType: null, licenseKey: null,
               expiresAt: null, connectorAvailable: false);
       }
   }

   private static GateSnapshot RunValidation()  // the ONLY method touching NodeAecGate
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
   ```

   The load failure lands at `RunValidation()`'s call site, inside
   `Validate()`'s `catch`, and surfaces as a normal fail-closed snapshot.
   `OpenConnector()` wraps `OpenConnectorCore()` identically (a missing
   connector degrades to the connector's own silent no-op contract).

4. **Map only the six real members.** `GateResult` = `IsLicensed`,
   `LicenseType`, `LicenseKey`, `ProductName`, `ExpiresAt`, `Message`. Payload
   fields are `null` on failure. No licensee, plan, seat counts, machine id,
   entitlement slug/status, trial flag, or status enum exists (API.md §4.2
   *`NodeAecGate.GateResult` — every member*).
5. **`IsLicensed` is the only branch point.** `Message` is display text —
   Portuguese, free-form, may change between connector versions. Show it
   verbatim; never translate it and never string-match it to decide behavior.

## What each member of the seam does

| Member | Role |
|---|---|
| `public const string ProductSlug = "revit-sample-plugin";` | The one constant to change when adapting |
| `public const string ConnectorUnavailableMessage` | English fail-closed text used when the assembly cannot be loaded at all (`ConnectorAvailable == false`) — distinct from the connector's own Portuguese messages |
| `public static GateSnapshot Validate()` | Entry point; never throws; returns a snapshot (never `null`) |
| `private static GateSnapshot RunValidation()` | Single place `NodeAecGate.Validate(ProductSlug)` is read |
| `public static void OpenConnector()` | Courtesy deep link; wrapper so absence = silent no-op |
| `public static string BuildLicenseBlock(GateSnapshot)` | Licensed-dialog content: Product / Type / License key / Valid until / Status; `ExpiresAt == null` renders `no expiry recorded (perpetual)` |

## Command-side shape (`SamplePlugin.Commands.HelloCommand`)

```csharp
public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
{
    GateSnapshot gate;
    try { gate = NodeAecLicenseGate.Validate(); }
    catch (Exception) { return ShowFailClosed(); }   // belt-and-braces: never proceed

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

`ShowBlockedDialog` builds a `TaskDialog` whose `MainContent` starts with
`Reason reported by Node.aec:\n{gate.Message}`, adds fixed guidance bullets
(sign in / renew / buy `'sample-plugin'` / connector missing / seat limit /
offline grace), adds `AddCommandLink(... "Open Node.aec Connector...")` calling
`NodeAecLicenseGate.OpenConnector()` only on click, and the command then
returns `Result.Cancelled`. There is no code path past the gate without a
license.

## Threading reminder (API.md §7)

Call `Validate()` once per `Execute`, at entry. It does disk I/O (lease read +
DPAPI + key read) on every call but zero network and no Revit API — never put
it in a per-element loop or a `DynamicUpdater`, and call `OpenConnector()` on
the UI thread right after your dialog.
