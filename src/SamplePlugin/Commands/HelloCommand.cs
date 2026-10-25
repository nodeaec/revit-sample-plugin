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
/// Sample commercial command and the whole Node.aec licensing integration: the license gate
/// runs FIRST and the command never runs unlicensed. Licensed → greets the user with the
/// license details. Not licensed → shows the gate's message, in Revit's UI language, with a
/// link that opens the Node.aec Connector, then returns <see cref="Result.Cancelled"/>.
/// <para>
/// How the pieces fit together. The <b>Node.aec Connector</b> (a separate add-in the user
/// installs once) signs the user in and keeps a signed <i>lease</i> on disk that lists the
/// products the account may use on this computer. This plugin never talks to the network:
/// <see cref="Gate.Validate"/>, from the <c>NodeAec.Licensing.Lite</c> NuGet package, reads
/// that lease and decides locally. That is why a command can be gated with three lines and
/// still work offline (the lease stays valid for 30 days without a sync).
/// </para>
/// <para>
/// Why the gate sits in <c>Execute</c> and not in <see cref="App.OnStartup"/>: the license can
/// change while Revit is open (the user signs in, a trial ends, a seat frees up), and the
/// check costs a file read, so checking on every click gives the right answer every time.
/// Checking once at startup would also mean either hiding the button (the user never
/// learns the plugin exists or why it is off) or blocking Revit's startup.
/// </para>
/// </summary>
/// <remarks>
/// <c>[Transaction(TransactionMode.Manual)]</c> is required on every <see cref="IExternalCommand"/>:
/// it tells Revit not to open a model transaction for us. This command only shows dialogs;
/// a command that edits the model opens its own <see cref="Transaction"/> after the gate.
/// </remarks>
[Transaction(TransactionMode.Manual)]
public class HelloCommand : IExternalCommand
{
    /// <summary>
    /// The product slug registered in the Node.aec catalog: the one value to change when you
    /// copy this sample. The gate looks for this exact slug (case-insensitive) in the lease,
    /// so a typo shows up as "product not found" for every user.
    /// With several commands, move it to one shared static class so they can never disagree.
    /// </summary>
    public const string ProductSlug = "revit-sample-plugin";

    /// <summary>Title of the success dialog.</summary>
    private const string Title = "Hello World";

    /// <summary>Title of the dialog shown when there is no valid license.</summary>
    private const string BlockedTitle = "Sample Plugin — License Required";

    /// <summary>
    /// Executes the command. Revit calls this on every click of the Ribbon button; the first
    /// statement is the local license gate.
    /// </summary>
    /// <param name="commandData">Revit context for this execution (application, documents, UI language).</param>
    /// <param name="message">
    /// Unused. Revit shows this text in its own error dialog only when the command returns
    /// <see cref="Result.Failed"/>; the blocked path shows a better dialog itself instead.
    /// </param>
    /// <param name="elements">Unused (elements Revit highlights on failure).</param>
    /// <returns><see cref="Result.Succeeded"/> only when licensed; otherwise <see cref="Result.Cancelled"/>.</returns>
    public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
    {
        // Gate.Validate checks, in order: a lease exists, its Ed25519 signature verifies
        // against keys compiled into Lite (so an edited or copied file is rejected), it was
        // issued for this computer, its offline period has not ended, and ProductSlug is
        // active in it. No network call is made.
        //
        // It never throws: every failure comes back as IsLicensed = false with a Reason, so
        // no try/catch is needed, and none should be added. A catch that let the command run
        // would turn any error into free access ("fail open"); the gate fails closed.
        Snapshot gate = Gate.Validate(ProductSlug);

        // Decide on IsLicensed only. gate.Reason (GateReason) says why, for logs or a tailored
        // UI, but branching on it would let a new reason added in a later Lite version fall
        // through to the licensed path.
        if (!gate.IsLicensed)
        {
            ShowBlockedDialog(gate.GetMessage(UserLanguage(commandData)));

            // Cancelled, not Failed: the user is told why in our own dialog. Failed would add
            // Revit's generic "external command failed" error on top of it.
            return Result.Cancelled;
        }

        // From here on the command is licensed: this is where a real plugin does its work.
        TaskDialog.Show(
            Title,
            $"Hello, {Environment.UserName}!\n\n" +
            "Sample Plugin verified your Node.aec license locally (no network call) " +
            "and is ready to run.\n\n" +
            BuildLicenseBlock(gate));
        return Result.Succeeded;
    }

    /// <summary>
    /// Node.aec messages come in Portuguese and English: follow Revit's UI language, which is
    /// the language the user already chose for everything else on screen.
    /// </summary>
    private static MessageLanguage UserLanguage(ExternalCommandData commandData) =>
        commandData.Application.Application.Language == LanguageType.Brazilian_Portuguese
            ? MessageLanguage.Portuguese
            : MessageLanguage.English;

    /// <summary>
    /// Shows the "not licensed" dialog: the gate's message and a link that opens the Connector.
    /// <para>
    /// The message already names the one specific reason and the next step (for example
    /// "sign in with the Node.aec Connector" or "the trial ended on 05/03/2026"), so it is the
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

        // Almost every blocked case is fixed in the Connector (sign in, activate a key, sync),
        // so the dialog offers a one-click way there.
        dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");

        // OpenConnector finds the Connector inside this Revit session and opens its window.
        // It does nothing when the Connector is not installed, which is why the dialog always
        // comes first: the message itself then tells the user to install it.
        if (dialog.Show() == TaskDialogResult.CommandLink1)
        {
            Gate.OpenConnector();
        }
    }

    /// <summary>
    /// Formats the license details of the success dialog. The license key
    /// (<see cref="Snapshot.LicenseKey"/>) is left out on purpose: it is the end user's
    /// secret, and anything shown on screen ends up in screenshots and support tickets, so
    /// it is never shown or logged.
    /// </summary>
    /// <param name="gate">A licensed gate result.</param>
    /// <returns>Multi-line license block.</returns>
    private static string BuildLicenseBlock(Snapshot gate)
    {
        var block = new StringBuilder();
        block.AppendLine("License (as reported by Node.aec):");
        block.Append("  Product     : ").AppendLine(gate.ProductName ?? "(not reported)");
        block.Append("  Type        : ").AppendLine(gate.LicenseType ?? "(not reported)");
        // ExpiresAt is null for licenses without an end date. The invariant format keeps the
        // date unambiguous whatever the Windows regional settings are.
        block.Append("  Valid until : ").AppendLine(
            gate.ExpiresAt is { } expiry
                ? expiry.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                : "no end date (perpetual)");
        return block.ToString();
    }
}
