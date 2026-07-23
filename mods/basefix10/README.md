# 10 Bases Per Guild

Raises the guild base-camp limit to **10** at every base level. Worker limits stay
100% vanilla — this only touches the base cap, nothing else.

| | |
|---|---|
| **ID** | `basefix10` |
| **Version** | 1.0.0 |
| **Category** | server-rule |
| **Needs server + client** | Yes (both must run it) |
| **Verified on** | Palworld v1.0.1.100619 (2026-07-23) |
| **Author** | Luibot & AyeGuild |

## What it changes

One field in one DataTable: `BaseCampMaxNumInGuild` in `DT_BaseCampLevelData`, set to
`10` on all 35 rows. `WorkerMaxNum` is left exactly as vanilla. Diff-verified against the
unmodified game pak — see [Test-Mod](https://github.com/luibots/pal-command).

## Why it needs both sides

The **server** reads this table to decide whether a guild may place another base. The
**client** reads the same table to draw the Palbox UI and run its own pre-check. If only
one side has it, the Palbox shows the wrong number or blocks placement. Everyone runs it.

## How it was built

`src/DT_BaseCampLevelData.mod.json` is the edited DataTable in JSON form — the recipe.
To rebuild the pak after a game update:

1. Extract the current `DT_BaseCampLevelData` from the game pak (repak)
2. Re-apply the edit (set `BaseCampMaxNumInGuild = 10` on every row)
3. Repack with repak, matching the game pak's version + path-hash seed

## Install

Open the [Palworld Mod Manager](https://github.com/luibots/palworld-mods/releases/latest/download/Palworld.Mod.Manager.bat),
tick it, Apply. The server must also be running it — ask the admin if your Palbox still
shows the old cap.
