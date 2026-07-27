# AyeGuild MiniMap

Client-only UE4SS Lua mod for Palworld 1.0.

- Displays a compact 220px high-zoom local view in the upper-right HUD.
- Uses Palworld's native player marker and rotates it with player heading.
- Keeps the player centered while the clipped local map moves underneath.
- Shows coordinates in a restrained 13px translucent strip.
- Press `F6` to hide or show the minimap.
- Samples movement ten times per second but skips unchanged layout and text work.
- Does not use a scene-capture camera, network request, or per-frame object creation.

The mod reads only the local player pawn. It does not contact or modify the dedicated
server and does not write to save data.
