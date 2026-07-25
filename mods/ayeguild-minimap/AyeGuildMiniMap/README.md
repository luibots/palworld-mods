# AyeGuild MiniMap

Client-only UE4SS Lua mod for Palworld 1.0.

- Displays a high-zoom local view using Palworld's own world-map texture.
- Uses Palworld's native player marker and rotates it with player heading.
- Lets the marker visibly move while the map follows and recenters.
- Shows the current numeric map coordinates.
- Press `F6` to hide or show the minimap.
- Updates four times per second and does not use a scene-capture camera.

The mod reads only the local player pawn. It does not contact or modify the dedicated
server and does not write to save data.
