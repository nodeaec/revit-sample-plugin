using System;
using System.Globalization;
using System.Text;
using NodeAec.Licensing;

namespace SamplePlugin.Licensing;

/// <summary>
/// THE integration seam of this sample: everything the plugin knows about Node.aec
/// licensing lives in this file. Port it to your own plugin, change
/// <see cref="ProductSlug"/>, and keep the rest of your code licensing-free.
/// <para>
/// Backed by the embedded Lite gate: <c>Gate.Validate(productSlug)</c> (local, offline,
/// Ed25519-verified, never throws) and <c>Gate.OpenConnector()</c> (opens the connector
/// UI; silently no-ops when the connector is not in the process).
/// </para>
/// <para>
/// WHY A PACKAGE REFERENCE (not a loose DLL): the Lite assembly travels WITH this
/// plugin via <c>PackageReference Include="NodeAec.Licensing.Lite"</c>, so there is no
/// external DLL an attacker can swap — the decision runs inside this plugin. That is
/// why the whole seam body is a single <c>Gate.Validate(ProductSlug)</c> call plus a
/// six-member mapping; no <c>HintPath</c>, no <c>Private=False</c>, no "connector
/// missing" branch (the Lite code is always present; a machine without credentials
/// simply validates as not-licensed with the Lite's <c>Nenhuma credencial...</c> message).
/// </para>
/// <para>
/// The Lite <c>Snapshot</c> never crosses into command code: this adapter maps it
/// to a plain <see cref="GateSnapshot"/> of strings. Commands branch only on
/// <see cref="GateSnapshot.IsLicensed"/> and render <see cref="GateSnapshot.Message"/>
/// verbatim.
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
    /// Validates <see cref="ProductSlug"/> on this machine. Never throws: any failure
    /// becomes a not-licensed snapshot, so callers can always fail closed on
    /// <see cref="GateSnapshot.IsLicensed"/>.
    /// </summary>
    /// <returns>An immutable snapshot of the gate outcome (never <c>null</c>).</returns>
    public static GateSnapshot Validate()
    {
        try
        {
            return RunValidation();
        }
        catch (Exception)
        {
            // Unreachable in practice (Lite travels with the plugin and Gate never throws):
            // last-resort fail-closed snapshot, never licensed.
            return new GateSnapshot(
                isLicensed: false,
                message: "Node.aec could not verify this plugin's license on this machine, so it will not run. Open the Node.aec Connector, synchronize your licenses, and try again.",
                productName: null,
                licenseType: null,
                licenseKey: null,
                expiresAt: null);
        }
    }

    /// <summary>
    /// The single place where the Lite <c>Snapshot</c> is read. Only the six
    /// members of the frozen contract are mapped: <c>IsLicensed</c>, <c>Message</c>,
    /// <c>ProductName</c>, <c>LicenseType</c>, <c>LicenseKey</c>, <c>ExpiresAt</c>.
    /// Licensee, plan, seats, machine binding and entitlement slug/status are NOT
    /// exposed by the gate — do not invent them.
    /// </summary>
    private static GateSnapshot RunValidation()
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

    /// <summary>
    /// Opens the Node.aec Connector UI (sign-in, key activation, renewal, seat
    /// management). A missing connector degrades to a silent no-op — exactly the
    /// Lite contract.
    /// </summary>
    public static void OpenConnector()
    {
        try
        {
            Gate.OpenConnector();
        }
        catch (Exception)
        {
            // Connector not installed / not in this process: nothing to open.
        }
    }

    /// <summary>
    /// Formats the informative license block of the "licensed" dialog from the real
    /// fields the gate exposes (via <see cref="GateSnapshot"/>).
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
/// Plain, Lite-free view of one gate outcome: strings and dates only, so
/// Revit commands can fail closed on <see cref="IsLicensed"/> without touching
/// licensing types. Immutable by construction.
/// </summary>
public sealed class GateSnapshot
{
    /// <summary>
    /// Builds a snapshot. Only values that come from the Lite
    /// <c>Snapshot</c> are accepted — see the mapping in
    /// <see cref="NodeAecLicenseGate"/>.
    /// </summary>
    /// <param name="isLicensed">The gate's only branch point: <c>true</c> only on verified success.</param>
    /// <param name="message">Human reason verbatim from the gate.</param>
    /// <param name="productName">Entitlement display name.</param>
    /// <param name="licenseType">Entitlement type, e.g. <c>perpetual</c>.</param>
    /// <param name="licenseKey">License key.</param>
    /// <param name="expiresAt">Validity/expiry (<c>null</c> = no expiry claim).</param>
    public GateSnapshot(
        bool isLicensed,
        string message,
        string? productName,
        string? licenseType,
        string? licenseKey,
        DateTimeOffset? expiresAt)
    {
        IsLicensed = isLicensed;
        Message = message;
        ProductName = productName;
        LicenseType = licenseType;
        LicenseKey = licenseKey;
        ExpiresAt = expiresAt;
    }

    /// <summary>The ONLY branch point a plugin may use to decide licensed vs not licensed.</summary>
    public bool IsLicensed { get; }

    /// <summary>Gate message, verbatim — the entire failure taxonomy.</summary>
    public string Message { get; }

    /// <summary>Entitlement display name, or <c>null</c> (always <c>null</c> on failure).</summary>
    public string? ProductName { get; }

    /// <summary>Entitlement type (free string, default <c>perpetual</c>), or <c>null</c>.</summary>
    public string? LicenseType { get; }

    /// <summary>License key, or <c>null</c>.</summary>
    public string? LicenseKey { get; }

    /// <summary>Validity/expiry instant, or <c>null</c> when the claim is absent or unreadable.</summary>
    public DateTimeOffset? ExpiresAt { get; }
}
