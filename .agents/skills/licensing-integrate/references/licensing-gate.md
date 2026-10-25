# The license gate in a command — full walkthrough

Detail for SKILL.md §5. Canonical source: the Sample Plugin's
[`HelloCommand.cs`](https://github.com/nodeaec/revit-sample-plugin/blob/main/src/SamplePlugin/Commands/HelloCommand.cs) (see also [API.md §9](https://github.com/nodeaec/revit-sample-plugin/blob/main/API.md#9-command-recipe-hellocommandcs)
*Command recipe (`HelloCommand.cs`)*).

## Design rules

1. **Call `Gate.Validate` directly.** There is no wrapper class. The package
   compiles into the plugin's folder, so the call is always there to make.
2. **No `try/catch` around it.** `Gate.Validate` never throws: a missing lease,
   corrupt data, or an unexpected error all come back as `IsLicensed = false`.
   A catch would only add a path to get wrong. (A machine without the Hub
   simply has no lease and validates as not-licensed, `Reason = NoLease`.)
3. **`IsLicensed` is the only branch point.** `Reason` (`GateReason`) names the
   case for logs or UI tweaks, never for deciding whether the command runs.
   Never string-match the message: its wording may change between versions.
4. **Show the message as-is, in the user's language.** `gate.GetMessage(MessageLanguage.English)`
   or `MessageLanguage.Portuguese`; the sample follows Revit's UI language.
   It already names the one reason and the next step, so it is the whole dialog
   content — never add a generic list of causes.
5. **Never show or log `LicenseKey`.** It is the end user's secret.

## The command (`SamplePlugin.Commands.HelloCommand`)

```csharp
public const string ProductSlug = "revit-sample-plugin"; // the one value to change

public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
{
    Snapshot gate = Gate.Validate(ProductSlug);
    if (!gate.IsLicensed)
    {
        ShowBlockedDialog(gate.GetMessage(UserLanguage(commandData)));
        return Result.Cancelled;
    }

    TaskDialog.Show(Title, $"Hello, {Environment.UserName}!\n\n" + ... + BuildLicenseBlock(gate));
    return Result.Succeeded;
}

private static MessageLanguage UserLanguage(ExternalCommandData commandData) =>
    commandData.Application.Application.Language == LanguageType.Brazilian_Portuguese
        ? MessageLanguage.Portuguese
        : MessageLanguage.English;
```

`ShowBlockedDialog` builds a `TaskDialog` whose `MainContent` is the message,
adds `AddCommandLink(... "Open Node.aec Connector...")` calling
`Gate.OpenConnector()` only on click, and the command then returns
`Result.Cancelled`. There is no code path past the gate without a license.

`BuildLicenseBlock` shows `ProductName`, `LicenseType` and `ExpiresAt`
(`null` renders "no end date (perpetual)", never "expired"). It leaves the
license key out on purpose.

## `Snapshot` members

As of Lite 0.3.0; the current list is in the [licensing-lite README](https://github.com/nodeaec/licensing-lite#snapshot).


| Member | Use |
|---|---|
| `IsLicensed` | The only branch point |
| `Reason` | `GateReason` value naming the case; logs and UI tweaks only |
| `GetMessage(MessageLanguage)` | End-user text, Portuguese or English |
| `Message` | Same as `GetMessage(MessageLanguage.Portuguese)` |
| `ProductName`, `LicenseType`, `ExpiresAt` | Display only; `null` on failure |
| `LicenseKey` | The user's secret: never show or log it |

## Threading reminder ([API.md §7](https://github.com/nodeaec/revit-sample-plugin/blob/main/API.md#7-threading--revit-api-context-rules))

Call `Gate.Validate` once per `Execute`, at entry. It does disk I/O (lease read +
DPAPI) on every call but no network and no Revit API — never put it in a
per-element loop or a `DynamicUpdater`. Call `Gate.OpenConnector()` on the UI
thread right after your dialog.
