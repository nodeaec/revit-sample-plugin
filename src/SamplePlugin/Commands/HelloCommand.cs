using System;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using SamplePlugin.Licensing;

namespace SamplePlugin.Commands;

/// <summary>
/// Sample commercial command: the license gate runs FIRST at command entry and the
/// command is <b>never</b> executed unlicensed (fail closed).
/// <para>Licensed → greets the user and shows the real license fields verified locally.
/// Not licensed / unknown state / any exception → the failure
/// <c>Message</c> verbatim plus short guidance and a link that opens the
/// Node.aec Connector, then <see cref="Result.Cancelled"/>.
/// </para>
/// </summary>
[Transaction(TransactionMode.Manual)]
public class HelloCommand : IExternalCommand
{
    /// <summary>Title of the success dialog (required by the sample spec).</summary>
    private const string Title = "Hello World";

    /// <summary>Title of the fail-closed dialog shown when no valid license exists.</summary>
    private const string BlockedTitle = "Sample Plugin — License Required";

    /// <summary>
    /// Executes the command. The very first action is the local license gate; every
    /// non-licensed or unknown outcome shows a dialog and returns
    /// <see cref="Result.Cancelled"/> — there is no code path past the gate without a license.
    /// </summary>
    /// <param name="commandData">Revit context for this execution.</param>
    /// <param name="message">Optional failure message (unused: failures return Cancelled with a dialog).</param>
    /// <param name="elements">Elements the command may want to select on failure (unused).</param>
    /// <returns><see cref="Result.Succeeded"/> only after a licensed greeting; otherwise <see cref="Result.Cancelled"/>.</returns>
    public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
    {
        // 1) License gate — first statement of the command. The seam never throws;
        //    belt-and-braces catch keeps any unexpected state fail-closed.
        GateSnapshot gate;
        try
        {
            gate = NodeAecLicenseGate.Validate();
        }
        catch (Exception)
        {
            return ShowFailClosed();
        }

        try
        {
            // Unknown state (seam contract violated / nothing to branch on) → fail closed.
            if (gate is null)
            {
                return ShowFailClosed();
            }

            // 2) Not licensed → reason verbatim + guidance + action, then stop.
            if (!gate.IsLicensed)
            {
                ShowBlockedDialog(gate);
                return Result.Cancelled;
            }

            // 3) Licensed → greet the user with the real license block.
            string content =
                $"Hello, {Environment.UserName}!\n\n" +
                "Sample Plugin verified your Node.aec license locally (no network call) " +
                "and is ready to run.\n\n" +
                NodeAecLicenseGate.BuildLicenseBlock(gate);

            TaskDialog.Show(Title, content);
            return Result.Succeeded;
        }
        catch (Exception)
        {
            // Any unexpected failure while talking to the UI → fail closed.
            return ShowFailClosed();
        }
    }

    /// <summary>
    /// Fail-closed dialog for unknown states and exceptions: no license, no work —
    /// the command never proceeds unlicensed.
    /// </summary>
    private static Result ShowFailClosed()
    {
        try
        {
            TaskDialog.Show(
                BlockedTitle,
                "Sample Plugin could not verify its license, so it will not run (fail closed).\n\n" +
                "Restart Revit and try again. If the problem persists, open the Node.aec " +
                "Connector from the Node.aec tab and synchronize your licenses.");
        }
        catch (Exception)
        {
            // A missing dialog must not surface as a crash; the command still returns Cancelled.
        }

        return Result.Cancelled;
    }

    /// <summary>
    /// Builds and shows the "not licensed" dialog: the failure
    /// <c>Message</c> verbatim as the reason, short guidance covering the
    /// known situations, and a command link that opens the connector UI
    /// (<c>NodeAecLicenseGate.OpenConnector()</c>).
    /// </summary>
    private static void ShowBlockedDialog(GateSnapshot gate)
    {
        var dialog = new TaskDialog(BlockedTitle)
        {
            MainInstruction = "Sample Plugin requires an active Node.aec license.",
            MainContent =
                $"Reason reported by Node.aec:\n{gate.Message}\n\n" +
                "What the situation usually means:\n" +
                "- Sign in: open the Node.aec Connector and sign in (or activate your license key).\n" +
                "- License expired: renew it from your Node.aec account.\n" +
                $"- No license for this plugin: buy or activate '{NodeAecLicenseGate.ProductSlug}' in the Node.aec catalog.\n" +
                "- Connector not installed or not reachable: install/open the Node.aec Connector and retry.\n" +
                "- Seat limit reached: free a seat for this product in your Node.aec account.\n" +
                "- Offline grace period over: go online and let the connector synchronize.\n\n" +
                "This command stays closed until a valid license is verified (fail closed).",
            CommonButtons = TaskDialogCommonButtons.Close
        };

        dialog.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "Open Node.aec Connector...");

        if (dialog.Show() == TaskDialogResult.CommandLink1)
        {
            NodeAecLicenseGate.OpenConnector();
        }
    }
}
