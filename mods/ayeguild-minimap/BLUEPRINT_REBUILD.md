# AyeGuild MiniMap Blueprint Rebuild

The UE4SS Lua prototype is retired. It pans a static world texture and cannot
provide the local terrain view expected from a real minimap.

## Experience Contract

- Circular 256 px local terrain view with no title or permanent label.
- Player arrow remains centered and rotates with heading.
- Map can be north-up or heading-up.
- Nearby guild members use Palworld's native member icon.
- Coordinates are optional and off by default.
- Hide while a full-screen menu is open and optionally while aiming.
- Three zoom levels with a compact icon-only control.

## Runtime Architecture

1. A client-only LogicMod spawns one `ModActor` after the local player enters a
   world.
2. A `SceneCaptureComponent2D` follows the player from above and renders to a
   256x256 `TextureRenderTarget2D`.
3. A UMG widget displays the render target through a circular mask material.
4. Player and guild icons render on a separate overlay so terrain capture does
   not need to run every frame.
5. The capture refreshes at 5 Hz while moving, 2 Hz while idle, and pauses when
   hidden. It must not use `bCaptureEveryFrame`.

## Performance Gates

- Less than 3% median FPS loss on the local RTX 3080 test machine.
- No server package, RPC, polling, or save-file access.
- No unbounded actor scan on Tick.
- Player/member icon updates capped at 10 Hz.
- Capture pauses in menus and when the minimap is hidden.

## Visual Gates

- Player movement is obvious within two seconds of walking.
- Terrain beneath the player is recognizable at every zoom level.
- No text larger than 13 px inside the minimap.
- No overlap with quests, base status, party list, or weapon controls at
  1920x1080 and 3840x1440.
- Screenshot verification is required before release.

## Authoring Toolchain

The current Palworld community LogicMod workflow requires Unreal Engine 5.1,
the Palworld Modding Kit, .NET 6, Visual Studio 2022 with MSVC v143 14.38, and
Wwise 2021.1.11. Cooked `.pak`/`.ucas`/`.utoc` output is installed through
UE4SS LogicMods.

The architecture was informed by SvenBrnn's MIT-licensed
`pal-yet-another-minimap-mod`. Any reused source assets or Blueprint graphs must
retain its copyright notice and MIT license.
