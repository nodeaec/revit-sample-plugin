using System;
using System.Linq;
using Autodesk.Revit.UI;
using Autodesk.Windows;
using SamplePlugin.Commands;
using RevitRibbonPanel = Autodesk.Revit.UI.RibbonPanel;

namespace SamplePlugin;

/// <summary>
/// Sample Plugin entry point (<see cref="IExternalApplication"/>).
/// <para>
/// How Revit finds this class: at startup Revit reads the bundle's <c>PackageContents.xml</c>,
/// picks the component for its own version, opens that folder's <c>SamplePlugin.addin</c>,
/// loads <c>SamplePlugin.dll</c> and creates the class named in <c>FullClassName</c> (this one).
/// It then calls <see cref="OnStartup"/> once per session and <see cref="OnShutdown"/> when
/// Revit closes. Commands (<see cref="IExternalCommand"/>) need no manifest entry of their
/// own: the Ribbon button below names the command class, and Revit creates it on each click.
/// </para>
/// <para>
/// Ribbon rules (same conventions as the Node.aec Connector):
/// the button lives in the SHARED canonical <c>Node.aec</c> tab — this add-in never
/// owns a tab of its own — inside its own <c>SamplePlugin</c> panel, titled with the company
/// name (<see cref="CompanyName"/>) so the Connector shows it in the company's group, with a
/// single push button named after the plugin. One tab for every Node.aec plugin keeps the user's
/// Ribbon short and puts every product they bought in one place. Tab creation tolerates
/// only the "already exists" ArgumentException, panel/button insertion is idempotent,
/// and AdWindows lifecycle hooks keep the tab deduplicated across add-in reloads.
/// </para>
/// <para>
/// Deliberately contains no licensing calls: the Ribbon must come up even when the
/// connector is missing, so the user can see the button and get the "why not" message
/// on click. There is a .NET reason too: the runtime loads a referenced assembly when it
/// first compiles a method that uses it, so a <c>Gate</c> call here would make a missing
/// or broken licensing DLL fail the whole add-in at startup. The license check lives at
/// the top of <see cref="Commands.HelloCommand.Execute"/>.
/// </para>
/// </summary>
public class App : IExternalApplication
{
    /// <summary>Shared canonical tab. Owned by the Node.aec ecosystem — never re-created as a plugin tab.</summary>
    public const string TabName = "Node.aec";

    /// <summary>
    /// Title of the group this plugin's buttons appear in: the company name, spelled exactly the
    /// same in every plugin the company publishes (one group per company on the tab). The sample
    /// is a Node.aec product, so it joins the Connector's <c>Node.aec</c> group; use your own
    /// company name.
    /// </summary>
    public const string CompanyName = "Node.aec";

    /// <summary>
    /// Internal name of this plugin's panel, unique to the plugin. Never the company name:
    /// Revit refuses a panel name another add-in already created.
    /// </summary>
    public const string PanelName = "SamplePlugin";

    /// <summary>
    /// Internal (non-localized) id of the push button; used for idempotent insertion. It starts
    /// with the plugin name and <c>_</c> so the Connector keeps this plugin's buttons together.
    /// </summary>
    public const string ButtonId = "SamplePlugin_HelloWorld";

    /// <summary>Display text of the push button: the plugin's name.</summary>
    public const string ButtonText = "Sample\nPlugin";

    /// <summary>
    /// Builds the Ribbon (tab → panel → button) and registers the dedup hooks.
    /// Any exception becomes a clean <see cref="Result.Failed"/> instead of a
    /// half-built Ribbon with no cause recorded.
    /// <para>
    /// Revit runs <c>OnStartup</c> on its UI thread while the splash screen is up, and waits
    /// for every add-in before it shows the window. Keep it to Ribbon work only: no network
    /// calls and no heavy file reads, or every Revit start gets slower for the user.
    /// </para>
    /// </summary>
    /// <param name="application">Revit-provided handle to the Ribbon of this session.</param>
    /// <returns><see cref="Result.Succeeded"/> when the Ribbon is ready, otherwise <see cref="Result.Failed"/>.</returns>
    public Result OnStartup(UIControlledApplication application)
    {
        try
        {
            EnsureTab(application);
            DeduplicateTab();

            RevitRibbonPanel panel = GetOrCreatePanel(application, TabName, PanelName);
            SetGroupTitle(panel);
            AddButtonIfMissing(panel, BuildHelloButtonData());

            RegisterRibbonHooks(application);
            return Result.Succeeded;
        }
        catch (Exception)
        {
            // Revit reports the add-in failure. No licensing calls here on purpose:
            // this class must not depend on NodeAec.Licensing at JIT time.
            return Result.Failed;
        }
    }

    /// <summary>
    /// Clean shutdown: unhooks the AdWindows/lifecycle delegates so a reload of the
    /// add-in in the same process never stacks handlers (the hooks are detached with
    /// "-=" before being attached with "+=" for the same reason).
    /// </summary>
    /// <param name="application">Revit-provided handle to the Ribbon of this session.</param>
    /// <returns>Always <see cref="Result.Succeeded"/>; shutdown has nothing that can fail.</returns>
    public Result OnShutdown(UIControlledApplication application)
    {
        try
        {
            application.ControlledApplication.ApplicationInitialized -= OnApplicationInitialized;
            ComponentManager.UIElementActivated -= OnUiElementActivated;
        }
        catch (Exception)
        {
            // Best-effort detachment; the delegates are static and idempotent anyway.
        }

        return Result.Succeeded;
    }

    /// <summary>
    /// Creates the shared <c>Node.aec</c> tab when it is not there yet (the connector
    /// usually creates it first). Only the "name already in use / rejected" exception
    /// is treated as the expected add-in-reload state; every other failure propagates
    /// to the top guard of <see cref="OnStartup"/> — a bare catch would mask real errors.
    /// <para>
    /// The Revit API has no "does this tab exist?" query, so trying to create it and
    /// accepting the "already exists" error is the standard way to share a tab. Add-ins
    /// start in an order Revit does not guarantee, so every Node.aec add-in runs this.
    /// </para>
    /// </summary>
    private static void EnsureTab(UIControlledApplication application)
    {
        try
        {
            application.CreateRibbonTab(TabName);
        }
        catch (Exception ex) when (
            ex is Autodesk.Revit.Exceptions.ArgumentException || ex is ArgumentException)
        {
            // Expected: the tab already exists (connector or another plugin created it).
        }
    }

    /// <summary>
    /// Shows the panel under the company's group title (<see cref="CompanyName"/>). The
    /// Connector merges every panel with the same title into one group, so all of a company's
    /// plugins sit together. Best effort: if Revit refuses the title, the panel keeps its name.
    /// </summary>
    private static void SetGroupTitle(RevitRibbonPanel panel)
    {
        try
        {
            panel.Title = CompanyName;
        }
        catch (Exception)
        {
            // The panel stays visible under its own name.
        }
    }

    /// <summary>
    /// Creates or reuses the <see cref="PanelName"/> panel inside the shared tab —
    /// the idempotent GetOrCreatePanel pattern (the connector's helper is private to
    /// its own assembly, so the sample replicates the logic).
    /// </summary>
    private static RevitRibbonPanel GetOrCreatePanel(UIControlledApplication application, string tabName, string panelName)
    {
        try
        {
            var existing = application.GetRibbonPanels(tabName);
            var found = existing.FirstOrDefault(p => string.Equals(p.Name, panelName, StringComparison.OrdinalIgnoreCase));
            if (found != null)
            {
                return found;
            }
        }
        catch (Exception)
        {
            // Lookup failure falls through to CreateRibbonPanel, which reports real problems.
        }

        return application.CreateRibbonPanel(tabName, panelName);
    }

    /// <summary>
    /// Creates the plugin's push button descriptor bound to <see cref="HelloCommand"/>.
    /// Revit stores the DLL path and the class name, and creates the command from them on
    /// each click. <c>Assembly.Location</c> is the path this DLL was actually loaded from
    /// (the bundle's <c>Contents\&lt;group&gt;\</c> folder), so it is right wherever the
    /// plugin is installed; never hard-code it.
    /// </summary>
    private static PushButtonData BuildHelloButtonData()
    {
        return new PushButtonData(
            ButtonId,
            ButtonText,
            typeof(App).Assembly.Location,
            typeof(HelloCommand).FullName ?? string.Empty)
        {
            ToolTip = "Sample Plugin: greets the user and shows the Node.aec license backing this command."
        };
    }

    /// <summary>
    /// Adds the button only when its internal name is not already present — safe on
    /// add-in reloads and when another instance of the panel already holds it.
    /// </summary>
    private static void AddButtonIfMissing(RevitRibbonPanel panel, PushButtonData buttonData)
    {
        try
        {
            var items = panel.GetItems().ToList();
            bool present = items.Any(i => string.Equals(i.Name, buttonData.Name, StringComparison.OrdinalIgnoreCase));
            if (!present)
            {
                panel.AddItem(buttonData);
            }
        }
        catch (Exception)
        {
            // Never let a Ribbon hiccup take the whole add-in down.
        }
    }

    /// <summary>
    /// Registers the AdWindows/Revit lifecycle hooks that keep the shared tab unique.
    /// Named static handlers with "-=" before "+=" so reloads don't stack delegates.
    /// <para>
    /// AdWindows (<c>Autodesk.Windows</c>) is the WPF library that draws Revit's Ribbon.
    /// The Revit API can create tabs but cannot list or remove them; AdWindows can, which
    /// is why deduplication goes through it. Removing a handler that was never added is a
    /// no-op, so "-=" then "+=" always leaves exactly one subscription.
    /// </para>
    /// </summary>
    private static void RegisterRibbonHooks(UIControlledApplication application)
    {
        try
        {
            application.ControlledApplication.ApplicationInitialized -= OnApplicationInitialized;
            application.ControlledApplication.ApplicationInitialized += OnApplicationInitialized;

            ComponentManager.UIElementActivated -= OnUiElementActivated;
            ComponentManager.UIElementActivated += OnUiElementActivated;
        }
        catch (Exception)
        {
            // AdWindows unavailable in this host: dedup stays best-effort, Ribbon still loads.
        }
    }

    /// <summary>Re-runs deduplication once the Ribbon is fully initialized.</summary>
    private static void OnApplicationInitialized(object? sender, EventArgs e) => DeduplicateTab();

    /// <summary>Re-runs deduplication on every Ribbon interaction (cheap no-op when there is one tab).</summary>
    private static void OnUiElementActivated(object? sender, EventArgs e) => DeduplicateTab();

    /// <summary>
    /// Removes duplicate <c>Node.aec</c> tabs (add-in reloads, mixed connector/plugin
    /// startup orders): keeps the first match, moves panels that are not present in it,
    /// then hides and removes the duplicate. Same algorithm as the connector's
    /// <c>App.DeduplicateRibbonTabs</c>; replicated here because that helper, although
    /// public, is not documented as partner API — this sample only consumes the gate.
    /// </summary>
    private static void DeduplicateTab()
    {
        try
        {
            var ribbon = ComponentManager.Ribbon;
            if (ribbon is null)
            {
                return;
            }

            var matchingTabs = ribbon.Tabs
                .Where(t => string.Equals(t.Title, TabName, StringComparison.OrdinalIgnoreCase)
                         || string.Equals(t.Id, TabName, StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (matchingTabs.Count <= 1)
            {
                return;
            }

            var primaryTab = matchingTabs[0];
            for (int i = 1; i < matchingTabs.Count; i++)
            {
                var duplicateTab = matchingTabs[i];

                foreach (var panel in duplicateTab.Panels.ToList())
                {
                    duplicateTab.Panels.Remove(panel);

                    // Only the same panel id is a leftover copy. A panel that merely shares the
                    // title is another plugin of the same company: keep it (the Connector merges
                    // same-title panels into one group).
                    bool alreadyInPrimary = primaryTab.Panels.Any(p =>
                        string.Equals(p.Source?.Id, panel.Source?.Id, StringComparison.OrdinalIgnoreCase));

                    if (!alreadyInPrimary)
                    {
                        primaryTab.Panels.Add(panel);
                    }
                }

                duplicateTab.IsVisible = false;
                ribbon.Tabs.Remove(duplicateTab);
            }
        }
        catch (Exception)
        {
            // Deduplication must never throw into Revit's event pipeline.
        }
    }
}
