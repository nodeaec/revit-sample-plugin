# User Manual — Sample Plugin

> **Applies to:** Sample Plugin 0.3.0 · **Updated:** October 2026
> **Platform:** Windows 10/11 (64-bit) · Autodesk Revit 2023–2027 (one installer for every version)
> **Product page:** <https://nodeaec.com.br/products/revit-sample-plugin>

This manual is for the people who **use** the Sample Plugin in Revit. It also shows what
the end users of any plugin sold through Node.aec experience. If you are a developer
building your own plugin, see [For plugin developers](#9-for-plugin-developers) at the end.

---

## Contents

1. [What the Sample Plugin does](#1-what-the-sample-plugin-does)
2. [What you need](#2-what-you-need)
3. [Installation](#3-installation)
4. [Using it](#4-using-it)
5. [When the license is missing](#5-when-the-license-is-missing)
6. [Working offline](#6-working-offline)
7. [Updating, changing Revit versions, uninstalling](#7-updating-changing-revit-versions-uninstalling)
8. [Troubleshooting](#8-troubleshooting)
9. [For plugin developers](#9-for-plugin-developers)

---

## 1. What the Sample Plugin does

The Sample Plugin adds one button, **Hello World**, to the **Node.aec** tab of the Revit
Ribbon. Clicking it checks that your computer has a license for the product, then greets
you and shows the license details. Without a license it explains why and offers to open
the Node.aec Connector, where you fix it.

It exists to demonstrate how Node.aec licensing works; it does not change your models.

---

## 2. What you need

| You need | Why |
|---|---|
| Windows 10 or 11 (64-bit) and Autodesk Revit 2023–2027 | The versions the plugin supports. |
| The **[Node.aec Connector](https://nodeaec.com.br/products/nodeaec-connector)** | The free Node.aec add-in where you sign in and activate licenses. The plugin reads the license the Connector saves; it never asks for a password itself. |
| A Node.aec account with a license for **Sample Plugin** | Without it, the button explains that the product is not licensed. |
| Administrator rights, once | The installer writes to `C:\ProgramData`. Using the plugin needs no special rights. |

Internet is needed only to sign in and to refresh licenses in the Connector. The plugin
itself never connects to the internet.

---

## 3. Installation

1. **Close Autodesk Revit.** The installer refuses to continue while Revit is open
   (*"Close Autodesk Revit before continuing."*), because it has to replace files Revit keeps in use.
2. Run `SamplePlugin-0.3.0-Setup.exe`.
3. On the **Autodesk Revit versions** page, check the Revit versions that should load the
   plugin. Versions installed on this computer are already checked and marked *installed*.
   You can also check a version you will install later. At least one must be checked.
4. Finish the wizard and open Revit.

The plugin is installed in `C:\ProgramData\Autodesk\ApplicationPlugins\SamplePlugin.bundle\`,
and Windows **Settings → Apps** shows one entry, **Sample Plugin**.

If an older Sample Plugin (0.2.0 or earlier) is installed, the installer removes it first
and tells you so on the versions page.

**For IT teams:**

- Silent install for chosen versions: `SamplePlugin-0.3.0-Setup.exe /VERYSILENT /RevitYears=2025,2026`.
  Without `/RevitYears` it keeps the previous choice, or every installed Revit version on a
  first install.
- Without the installer: extract `SamplePlugin-0.3.0.bundle.zip` into
  `C:\ProgramData\Autodesk\ApplicationPlugins\` (enables every Revit version).
- Each file ships with a `.sha256` checksum.

---

## 4. Using it

1. Open Revit and click the **Node.aec** tab.
2. In the **Sample Plugin** panel, click **Hello World**.

With a valid license you see:

```
Hello, <your Windows user name>!

Sample Plugin verified your Node.aec license locally (no network call) and is ready to run.

License (as reported by Node.aec):
  Product     : <product name>
  Type        : <license type>
  Valid until : <yyyy-mm-dd, or "no end date (perpetual)">
```

Your license key is never shown: it is your secret.

The **Node.aec** tab is shared by every Node.aec product, so you may also see the Connector's
**Conector** panel and the panels of other plugins you own.

---

## 5. When the license is missing

If the license cannot be confirmed, the command does not run. A dialog titled
**Sample Plugin — License Required** shows one sentence that names the exact reason and
what to do, in Revit's language (Portuguese or English), and an **Open Node.aec Connector...**
link that opens the Connector's **Minha Conta** window.

| The dialog says (English) | What to do |
|---|---|
| *No Node.aec credentials were found on this computer. Open the Node.aec Connector on the Ribbon to sign in or activate your license.* | Click the link and sign in, or activate your key. If nothing opens, the Connector is not installed: install it first. |
| *The product 'revit-sample-plugin' is not among this account's active licenses. Buy or activate it in the Node.aec catalog.* | Get the product in the [catalog](https://nodeaec.com.br/products), then click **Atualizar minhas licenças** in the Connector. |
| *The license or trial of '…' expired on ….* | Renew it, then refresh licenses in the Connector. |
| *All computers allowed for '…' are already in use.* | Free a computer on the Node.aec web portal. |
| *The offline grace period expired on …. Connect to the internet to synchronize.* | Connect and click **Atualizar minhas licenças** in the Connector. |
| *The licenses were issued for another computer (Hardware ID mismatch).* | Sign in with the Connector on this computer. |
| *The local license date is invalid. Check this computer's date and time and try again.* | Fix the Windows date and time. |

Other messages follow the same pattern: they say what is wrong and what to do. After fixing
it, click **Hello World** again; there is no need to restart Revit.

---

## 6. Working offline

The plugin checks the license on your computer, without internet, every time you click the
button. The license the Connector saves stays valid for **30 days** without a connection.
After that the dialog asks you to connect and synchronize.

---

## 7. Updating, changing Revit versions, uninstalling

- **Update:** close Revit and run the newer installer. It starts with the versions you chose last time.
- **Add or remove a Revit version:** run the installer again and change the checkboxes.
- **Uninstall:** close Revit, then **Settings → Apps → Sample Plugin → Uninstall**. This
  removes it from every Revit version. Your Node.aec account and licenses are not affected.

---

## 8. Troubleshooting

| Problem | What to do |
|---|---|
| The **Hello World** button does not appear | Run the installer again and check that your Revit version is checked. Make sure Revit was closed while installing. |
| The installer stops with *"Close Autodesk Revit before continuing."* | Close every Revit window (check the Task Manager for `Revit.exe`), then run it again. |
| The installer says *"Setup did not finish"* | Run it again with Revit closed. |
| **Open Node.aec Connector...** does nothing | The Connector is not installed. Install it from its [product page](https://nodeaec.com.br/products/nodeaec-connector). |
| The dialog keeps saying the product is not licensed after you bought it | In the Connector, click **Atualizar minhas licenças**, then try again. |
| Two **Node.aec** tabs appear | Restart Revit; the plugins merge the tabs on startup. |

Support: <https://nodeaec.com.br>.

---

## 9. For plugin developers

This manual doubles as a starting point for your own plugin's user manual. Copy it and
change:

- the product name, button, panel and product page;
- the installer file names and install folder (`<YourPlugin>-<version>-Setup.exe`,
  `<YourPlugin>.bundle`);
- the success dialog in §4 (what your command does);
- the product slug in the §5 table.

Keep §2 (the Connector is required), §5 (the license messages come from Node.aec; the
full list is in the [licensing-lite README](https://github.com/nodeaec/licensing-lite#reasons-and-messages)),
§6 and the installer behavior in §3 and §7, which are the same for every plugin built from
the template.

How the plugin itself is built: [README.md](../README.md) and [API.md](../API.md).
