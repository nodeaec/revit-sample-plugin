using System;
using System.Globalization;
using System.Text;
using NodeAec.Connector.Gate;

namespace SamplePlugin.Licensing;

/// <summary>
/// THE integration seam of this sample: everything the plugin knows about Node.aec
/// licensing lives in this file. Port it to your own plugin, change
/// <see cref="ProductSlug"/>, and keep the rest of your code connector-free.
/// <para>
/// Backed by the connector's public gate: <c>NodeAecGate.Validate(productSlug)</c>
/// (local, offline, Ed25519-verified, never throws) and <c>NodeAecGate.OpenConnector()</c>
/// (opens the connector UI; silently no-ops when the connector is not in the process).
/// </para>
/// <para>
/// The gate's <c>GateResult</c> never crosses into command code: this adapter maps it
/// to a plain <see cref="GateSnapshot"/> of strings. That keeps the connector assembly
/// out of the commands' JIT surface, so a machine without the connector fails closed
/// with this plugin's own dialog instead of an unhandled load failure.
/// </para>
/// </summary>
public static class NodeAecLicenseGate
{
    /// <summary>
    /// THE one constant to change when adapting this sample to another product:
    /// the product slug as registered in the Node.aec catalog / entitlement claims.
    /// </summary>
    public const string ProductSlug = "revit-sample-plugin";

    /// <summary>
    /// Reason shown when the connector assembly cannot be reached at all (not
    /// installed / not loadable). Fail-closed: this is treated as "not licensed".
    /// </summary>
    public const string ConnectorUnavailableMessage =
        "The Node.aec Connector could not be loaded on this station. " +
        "Install or repair the Node.aec Connector, then open it and try again.";

    /// <summary>
    /// Validates <see cref="ProductSlug"/> on this machine. Never throws: any failure
    /// — including the connector assembly being absent — becomes a not-licensed
    /// snapshot, so callers can always fail closed on <see cref="GateSnapshot.IsLicensed"/>.
    /// </summary>
    /// <returns>An immutable snapshot of the gate outcome (never <c>null</c>).</returns>
    public static GateSnapshot Validate()
    {
        try
        {
            // Isolated helper so a JIT-time load failure of NodeAec.Connector surfaces
            // HERE, inside the try, instead of before any of this code runs.
            return RunValidation();
        }
        catch (Exception)
        {
            return new GateSnapshot(
                isLicensed: false,
                message: ConnectorUnavailableMessage,
                productName: null,
                licenseType: null,
                licenseKey: null,
                expiresAt: null,
                connectorAvailable: false);
        }
    }

    /// <summary>
    /// The single place where the connector's <c>GateResult</c> is read. Only the six
    /// members that really exist are mapped: <c>IsLicensed</c>, <c>Message</c>,
    /// <c>ProductName</c>, <c>LicenseType</c>, <c>LicenseKey</c>, <c>ExpiresAt</c>.
    /// Licensee, plan, seats, machine binding and entitlement slug/status are NOT
    /// exposed by the connector — do not invent them.
    /// </summary>
    private static GateSnapshot RunValidation()
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

    /// <summary>
    /// Opens the Node.aec Connector UI (sign-in, key activation, renewal, seat
    /// management). Wrapper around the real API so a missing connector degrades to a
    /// silent no-op — exactly the connector's contract.
    /// </summary>
    public static void OpenConnector()
    {
        try
        {
            OpenConnectorCore();
        }
        catch (Exception)
        {
            // Connector not installed / not in this process: nothing to open.
        }
    }

    /// <summary>Isolated call target so the load failure of the connector stays catchable.</summary>
    private static void OpenConnectorCore() => NodeAecGate.OpenConnector();

    /// <summary>
    /// Formats the informative license block of the "licensed" dialog from the real
    /// fields the connector exposes on <c>GateResult</c> (via <see cref="GateSnapshot"/>).
    /// </summary>
    /// <param name="snapshot">Snapshot of a licensed gate outcome.</param>
    /// <returns>Multi-line, human-readable license block.</returns>
    public static string BuildLicenseBlock(GateSnapshot snapshot)
    {
        var block = new StringBuilder();
        block.AppendLine("License (as reported by Node.aec):");
        block.Append("  Product        : ").AppendLine(snapshot.ProductName ?? "(not reported)");
        block.Append("  Type           : ").AppendLine(snapshot.LicenseType ?? "(not reported)");
        block.Append("  License key    : ").AppendLine(snapshot.LicenseKey ?? "(not reported)");
        block.Append("  Valid until    : ").AppendLine(FormatExpiry(snapshot.ExpiresAt));
        block.Append("  Status         : ").AppendLine(snapshot.Message);
        return block.ToString();
    }

    /// <summary>
    /// Renders the entitlement expiry. <c>null</c> means the claim carries no expiry
    /// (e.g. a perpetual license), never "already expired".
    /// </summary>
    private static string FormatExpiry(DateTimeOffset? expiresAt)
    {
        return expiresAt is { } expiry
            ? expiry.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture)
            : "no expiry recorded (perpetual)";
    }
}

/// <summary>
/// Plain, connector-free view of one gate outcome: strings and dates only, so
/// Revit commands can be JIT-compiled and fail closed even when the Node.aec
/// Connector assembly is absent. Immutable by construction.
/// </summary>
public sealed class GateSnapshot
{
    /// <summary>
    /// Builds a snapshot. Only values that come from the connector's
    /// <c>NodeAecGate.GateResult</c> are accepted — see the mapping in
    /// <see cref="NodeAecLicenseGate"/>.
    /// </summary>
    /// <param name="isLicensed">The gate's only branch point: <c>true</c> only on verified success.</param>
    /// <param name="message">Human reason verbatim from the connector (default success text on success).</param>
    /// <param name="productName">Entitlement display name (<c>GateResult.ProductName</c>).</param>
    /// <param name="licenseType">Entitlement type, e.g. <c>perpetual</c> (<c>GateResult.LicenseType</c>).</param>
    /// <param name="licenseKey">License key (<c>GateResult.LicenseKey</c>).</param>
    /// <param name="expiresAt">Validity/expiry (<c>GateResult.ExpiresAt</c>); <c>null</c> = no expiry claim.</param>
    /// <param name="connectorAvailable"><c>false</c> when the connector could not be loaded at all.</param>
    public GateSnapshot(
        bool isLicensed,
        string message,
        string? productName,
        string? licenseType,
        string? licenseKey,
        DateTimeOffset? expiresAt,
        bool connectorAvailable)
    {
        IsLicensed = isLicensed;
        Message = message;
        ProductName = productName;
        LicenseType = licenseType;
        LicenseKey = licenseKey;
        ExpiresAt = expiresAt;
        ConnectorAvailable = connectorAvailable;
    }

    /// <summary>The ONLY branch point a plugin may use to decide licensed vs not licensed.</summary>
    public bool IsLicensed { get; }

    /// <summary>Connector message, verbatim — the entire failure taxonomy.</summary>
    public string Message { get; }

    /// <summary>Entitlement display name, or <c>null</c> (always <c>null</c> on failure).</summary>
    public string? ProductName { get; }

    /// <summary>Entitlement type (free string, default <c>perpetual</c>), or <c>null</c>.</summary>
    public string? LicenseType { get; }

    /// <summary>License key, or <c>null</c>.</summary>
    public string? LicenseKey { get; }

    /// <summary>Validity/expiry instant, or <c>null</c> when the claim is absent or unreadable.</summary>
    public DateTimeOffset? ExpiresAt { get; }

    /// <summary><c>false</c> when the connector assembly could not be reached (fail-closed state).</summary>
    public bool ConnectorAvailable { get; }
}
