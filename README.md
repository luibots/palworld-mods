# Palworld Guild Mods

**By Luibot & AyeGuild** · Mods for our Palworld server, plus a one-click manager that installs them for you.

**You do not need to know anything technical. Just follow the two steps below.**

---

## How to install the mods

1. **[Click here to download the Mod Manager](https://github.com/luibots/palworld-mods/releases/latest/download/Palworld.Mod.Manager.bat)**
2. **Double-click the file you just downloaded.**

A window opens, finds your Palworld automatically, and shows the mod list.
Tick the mods you want, press **Apply Changes**, done.

> **Windows may show a blue "Windows protected your PC" box.**
> That is just because the file is new, not because anything is wrong.
> Click **More info**, then **Run anyway**.

### To remove a mod later
Open the manager again, **untick** the mod, press **Apply Changes**.

---

## Important notes

- **Close Palworld before installing.** The manager will tell you if the game is still running.
- **Steam version only.** Palworld from Xbox / Game Pass keeps its files locked down, so mods do not work there. The manager will tell you if it detects that.
- **The server has to run the same mods.** If a mod changes a rule (like base limits) and your game still shows the old number, the server has not been updated yet - ask the admin.

## Having trouble?

- *"It cannot find my Palworld"* - click **Find it myself...** and pick your Palworld folder (the one containing a folder called `Pal`).
- *"Nothing changed in game"* - make sure you fully closed and reopened Palworld, and that you are joining the modded server.
- Still stuck? Ping the admin with a screenshot of the manager window.

---

## Current mods

| Mod | What it does | Server must match |
|---|---|---|
| **10 Bases Per Guild** | Raises the base-camp limit to 10 at every base level. Worker limits stay vanilla. | Yes |

---

## For the admin

Mods live here; the manager reads [`mods.json`](mods.json) to know what is available.

**Publishing a new mod is one command** - it hashes the pak, updates the manifest, commits and pushes:

```powershell
.\Publish-Mod.ps1 -PakPath "C:\built\zzz_xprate_P.pak" `
                  -Name "2x XP" -Description "Doubles XP gain." `
                  -ServerSide -Recommended
```

```powershell
.\Publish-Mod.ps1 -List              # see what's published
.\Publish-Mod.ps1 -Remove xprate     # unpublish
```

Everyone's Mod Manager picks up the change the next time they open it - no re-sending files,
and the Discord bot announces new mods automatically.

Note: the download link above points at the **Release** asset, not the raw file. A raw `.bat`
link opens as text in the browser instead of downloading, which confuses non-technical users.
After changing the manager itself, refresh the release asset:

```powershell
gh release upload v1.0 "Palworld Mod Manager.bat" --repo luibots/palworld-mods --clobber
```

## Credits

Made by **Luibot** and the **AyeGuild** crew.
Built and managed with [PAL·COMMAND](https://github.com/luibots/pal-command).
