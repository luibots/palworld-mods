# AyeGuild MiniMap

Client-only UE4SS Lua mod for Palworld 1.0.

- Displays a compact 220px high-zoom local view in the upper-left HUD.
- Uses Palworld's native player marker and rotates it with player heading.
- Lets the marker visibly move while the map follows and recenters.
- Shows coordinates in a restrained 13px translucent strip.
- Press `F6` to hide or show the minimap.
- Updates four times per second and does not use a scene-capture camera.

The mod reads only the local player pawn. It does not contact or modify the dedicated
server and does not write to save data.
