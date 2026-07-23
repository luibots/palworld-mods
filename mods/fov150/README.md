# AyeGuild FOV 150 Slider

Expands Palworld's in-game FOV slider maximum from **90** to **150**.
It does not force a camera value. Every player chooses their own FOV in the
normal game settings.

| | |
|---|---|
| **ID** | `fov150` |
| **Version** | 1.0.0 |
| **Category** | client-tweak |
| **Server install** | No |
| **Verified on** | Palworld v1.0.1.100619 (2026-07-23) |
| **Authors** | Luibot and AyeGuild |

## What It Changes

One scalar in one current-game Blueprint asset:

```text
Pal/Content/Pal/Blueprint/System/BP_PalOptionSubsystem
OptionLocalStaticSettings.FOV.Max: 90.0 -> 150.0
```

The minimum, default, all other graphics settings, game rules, server data, and
save files remain unchanged.

## Install

Run the AyeGuild Mod Manager, tick **FOV Slider: Up To 150**, and select
**Apply Changes**. Start Palworld and choose your preferred value under the
normal camera settings.

## Remove

Close Palworld, untick the mod in the manager, and apply changes. Palworld stores
the selected FOV locally, so removing the unlocker does not necessarily reset an
already selected value until the player changes that setting again.

## Compatibility

This asset conflicts with other mods that replace `BP_PalOptionSubsystem`,
including some world-setting unlockers. The manager should not install two mods
that replace that asset at the same time.

## Validation

`src/Test-FOV150.ps1` compares this pak against the vanilla game pak. It requires:

- exactly the expected two serialized byte positions to differ;
- the complete four-byte scalar at that position to read `90.0 -> 150.0`;
- no `.uasset` bytes and no other `.uexp` bytes to change.

