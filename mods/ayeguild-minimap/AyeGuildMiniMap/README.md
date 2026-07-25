# AyeGuild MiniMap

Client-only UE4SS Lua mod for Palworld 1.0.

- Displays Palworld's own world-map texture in the top-right corner.
- Tracks the local player's current map position.
- Shows the current numeric map coordinates.
- Press `F6` to hide or show the minimap.
- Updates twice per second and does not use a scene-capture camera.

The mod reads only the local player pawn. It does not contact or modify the dedicated
server and does not write to save data.
