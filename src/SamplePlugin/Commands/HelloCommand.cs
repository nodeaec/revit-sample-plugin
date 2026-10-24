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
