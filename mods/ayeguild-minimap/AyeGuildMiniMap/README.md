# AyeGuild MiniMap

Client-only UE4SS Lua mod for Palworld 1.0.

- Displays a cropped, zoomed view of Palworld's own world-map texture.
- Keeps the local player centered while the map scrolls with movement.
- Shows the current numeric map coordinates.
- Press `F6` to hide or show the minimap.
- Updates four times per second and does not use a scene-capture camera.

The mod reads only the local player pawn. It does not contact or modify the dedicated
server and does not write to save data.
