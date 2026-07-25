# AyeGuild MiniMap Blueprint Rebuild

> Status: architecture approved; Blueprint implementation and runtime validation
> are pending. The retired UE4SS Lua prototype is not the release design.

The replacement is a client-only Palworld LogicMod. It renders a real local
terrain view, keeps the player visibly centered, and treats smooth frame time as
a release requirement rather than an optional optimization.

## Product Contract

- Circular 256 px local terrain view with no title or permanent label.
- Player arrow stays centered and rotates with heading.
- North-up and heading-up modes.
- Three icon-only zoom levels.
- Nearby guild members use Palworld's native member icon.
- Coordinates are optional and disabled by default.
- Full-screen menus hide the minimap; aiming can hide it by preference.
- No server package, RPC, polling, save-file access, or inventory access.

## C4 Context

```mermaid
%%{init: {"theme": "dark"}}%%
C4Context
    title AyeGuild MiniMap - System Context

    Person(player, "Player", "Uses the live minimap")
    System(minimap, "AyeGuild MiniMap", "Client-only LogicMod")
    System_Ext(game, "Palworld Client", "World, pawn, HUD, and nearby players")
    System_Ext(server, "Dedicated Server", "Unmodified shared world")

    Rel(player, minimap, "Uses")
    Rel(minimap, game, "Reads and renders")

    UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")
```

## C4 Containers

```mermaid
%%{init: {"theme": "dark"}}%%
C4Container
    title AyeGuild MiniMap - Runtime Containers

    Person(player, "Player")

    Container(palworld, "Palworld Runtime", "Unreal Engine", "Client process: world, pawn, HUD, and actors")
    Container(logicmod, "MiniMap LogicMod", "Blueprint", "Client process: scheduling and marker state")
    Container(capture, "Terrain Capture", "SceneCaptureComponent2D", "Client process: throttled top-down capture")
    Container(renderTarget, "Render Target", "TextureRenderTarget2D", "Client process: persistent 256x256 texture")
    Container(widget, "MiniMap HUD", "UMG", "Client process: circular map and markers")

    System_Ext(server, "Dedicated Server", "Unmodified")

    Rel(player, widget, "")
    Rel(logicmod, palworld, "")
    Rel(logicmod, capture, "")
    Rel(capture, renderTarget, "")
    Rel(renderTarget, widget, "")
    Rel(logicmod, widget, "")

    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

## C4 Components

```mermaid
%%{init: {"theme": "dark"}}%%
C4Component
    title AyeGuild MiniMap - LogicMod Components

    Component(lifecycle, "Lifecycle", "Blueprint", "Owns world-scoped resources")
    Component(scheduler, "Scheduler", "Blueprint", "Bounds update rates")
    Component(registry, "Marker Registry", "Blueprint", "Pools guild markers")
    Container_Ext(world, "Palworld World", "Actors and local pawn")
    Component(viewModel, "HUD View Model", "Blueprint", "Publishes HUD state")
    Component(captureController, "Capture Controller", "Blueprint", "Triggers terrain capture")
    Container_Ext(hud, "UMG MiniMap Widget", "HUD overlay")
    Container_Ext(rt, "Persistent Render Target", "256x256 texture")

    Rel(lifecycle, scheduler, "")
    Rel(scheduler, captureController, "")
    Rel(scheduler, world, "")
    Rel(registry, world, "")
    Rel(captureController, rt, "")
    Rel(registry, viewModel, "")
    Rel(viewModel, hud, "")
    Rel(rt, hud, "")

    UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")
```

## Runtime Flow

```mermaid
%%{init: {"theme": "dark", "flowchart": {"curve": "basis", "nodeSpacing": 35, "rankSpacing": 45}}}%%
flowchart TD
    A["World becomes ready"] --> B["Create one ModActor"]
    B --> C["Allocate one 256x256 render target"]
    C --> D["Create one dynamic map material"]
    D --> E["Create HUD and fixed marker pool"]
    E --> F{"Minimap visible?"}

    F -- "No" --> G["Pause capture and marker updates"]
    G --> F

    F -- "Yes" --> H["Read pawn position and heading"]
    H --> I{"Player moving?"}
    I -- "Yes" --> J["Capture terrain at up to 5 Hz"]
    I -- "No" --> K["Capture terrain at up to 2 Hz"]
    J --> L["Update player and marker transforms at up to 10 Hz"]
    K --> L
    L --> M{"World unloading?"}
    M -- "No" --> F
    M -- "Yes" --> N["Release references and pooled widgets"]
```

## Frame Scheduling

```mermaid
%%{init: {"theme": "dark"}}%%
stateDiagram-v2
    [*] --> WaitingForWorld
    WaitingForWorld --> ActiveMoving: local pawn valid
    ActiveMoving --> ActiveIdle: speed below threshold
    ActiveIdle --> ActiveMoving: movement detected
    ActiveMoving --> Suspended: hidden or full-screen menu
    ActiveIdle --> Suspended: hidden or full-screen menu
    Suspended --> ActiveMoving: shown and moving
    Suspended --> ActiveIdle: shown and idle
    ActiveMoving --> Degraded: frame-time budget exceeded
    ActiveIdle --> Degraded: frame-time budget exceeded
    Degraded --> ActiveMoving: budget healthy for 10 seconds
    Degraded --> ActiveIdle: budget healthy for 10 seconds
    WaitingForWorld --> [*]: mod removed
    ActiveMoving --> [*]: world unload
    ActiveIdle --> [*]: world unload
    Suspended --> [*]: world unload
    Degraded --> [*]: world unload
```

| State | Terrain capture | Marker transforms | Notes |
|---|---:|---:|---|
| Moving | 5 Hz maximum | 10 Hz maximum | Normal exploration |
| Idle | 2 Hz maximum | 4 Hz maximum | Avoids unnecessary GPU work |
| Suspended | 0 Hz | 0 Hz | Menus, hidden map, or world transition |
| Degraded | 2 Hz maximum | 4 Hz maximum | Entered automatically after budget violations |

## Memory Ownership

```mermaid
%%{init: {"theme": "dark", "flowchart": {"curve": "linear", "nodeSpacing": 30, "rankSpacing": 45}}}%%
flowchart LR
    A["Lifecycle Controller"] -->|"owns one"| B["Scene Capture"]
    A -->|"owns one"| C["Render Target"]
    A -->|"owns one"| D["Dynamic Material"]
    A -->|"owns one"| E["HUD Widget"]
    A -->|"owns bounded pool"| F["Guild Marker Widgets"]
    E -->|"references"| D
    D -->|"samples"| C
    F -->|"reused, never recreated on Tick"| E
    G["World actors"] -->|"weak references only"| F
```

### Allocation Rules

- Allocate the capture, render target, material, HUD, and marker pool once after
  the local world is ready.
- Nominal render-target storage is 0.25 MiB for one 256x256 RGBA8 surface;
  actual GPU allocation may be higher because of driver alignment.
- Disable mip generation and avoid depth storage unless testing proves it is
  required.
- Never create UObjects, widgets, arrays, materials, or textures on Tick.
- Reuse a fixed marker pool capped at 32 nearby guild members.
- Store weak actor references and remove invalid entries during bounded
  reconciliation.
- Clear strong world references before travel, disconnect, or world teardown.
- Avoid per-frame string formatting; coordinates update only when enabled and
  only when the rounded value changes.

## How Stutter Is Controlled

| Risk | Control | Verification |
|---|---|---|
| Scene capture runs every rendered frame | `bCaptureEveryFrame=false`; explicit adaptive scheduler | UE Insights capture-call count |
| Large render target saturates GPU bandwidth | Fixed 256x256 RGBA8 target; no supersampling | GPU frame-time comparison |
| Actor scans cause CPU spikes | Event-driven registry plus one bounded reconciliation every 2 seconds | Game-thread trace |
| Widgets create garbage | Fixed pool; transform and visibility updates only | UObject count before/after 30 minutes |
| Menus render hidden work | Capture and marker timers pause at zero | Capture-call count while menu is open |
| Teleports create invalid references | World lifecycle hooks clear all cached actors | Repeated travel/disconnect test |
| Too many nearby actors | Guild-only filter and hard cap of 32 markers | Crowded-base stress test |
| Capture cost rises in dense scenes | Minimal show flags; no motion blur, bloom, AO, or post-processing | Dense-base GPU trace |
| Slow hardware misses budget | Automatic degraded state at 2 Hz | Forced low-FPS test |

## Render Pipeline

```mermaid
%%{init: {"theme": "dark"}}%%
sequenceDiagram
    autonumber
    participant S as Adaptive Scheduler
    participant P as Local Pawn Tracker
    participant C as Scene Capture
    participant R as Persistent Render Target
    participant V as HUD View Model
    participant U as UMG MiniMap

    S->>P: Sample movement and visibility
    P-->>S: Position, heading, speed, menu state
    alt Visible and capture interval elapsed
        S->>C: Move above pawn and CaptureScene
        C->>R: Render local terrain once
    else Hidden, idle interval pending, or over budget
        S-->>C: Skip capture
    end
    S->>V: Update player and pooled marker transforms
    V->>U: Apply transforms without rebuilding widgets
    R-->>U: Existing material samples latest terrain frame
```

## Failure and Degradation

```mermaid
%%{init: {"theme": "dark", "flowchart": {"curve": "basis"}}}%%
flowchart TD
    A{"Runtime check"} -->|"Render target unavailable"| B["Hide terrain layer"]
    A -->|"Local pawn unavailable"| C["Suspend all updates"]
    A -->|"Frame budget exceeded"| D["Enter 2 Hz degraded mode"]
    A -->|"Marker actor invalid"| E["Return marker to pool"]
    A -->|"Healthy"| F["Continue normal schedule"]
    B --> G["Keep game playable and log once"]
    C --> H["Retry only after world-ready signal"]
    D --> I["Recover after 10 healthy seconds"]
    E --> F
```

The minimap must fail closed: it may hide itself, but it must never block input,
hold stale world references, modify save data, or affect the server.

## Performance Gates

- Less than 3% median FPS loss on the local RTX 3080 test machine.
- Less than 0.5 ms added median game-thread time.
- No recurring frame-time spike above 2 ms attributable to the mod.
- No upward UObject or GPU-memory trend during a 30-minute traversal.
- No capture calls while hidden or while a full-screen menu is open.
- No unbounded actor scan on Tick.
- No server-side files or network calls.

## Visual Gates

- Player movement is obvious within two seconds of walking.
- Terrain beneath the player is recognizable at every zoom level.
- No permanent text in the default configuration.
- Optional coordinate text is at most 13 px.
- No overlap with quests, base status, party list, or weapon controls at
  1920x1080, 2560x1440, and 3840x1440.
- UI scale tests cover 80%, 100%, 120%, and 150%.
- Screenshot verification is required before release.

## Validation Matrix

| Scenario | Required result |
|---|---|
| Walk, sprint, mount, and fly | Terrain follows smoothly; arrow heading is correct |
| Stand idle for five minutes | Capture drops to 2 Hz with no visual jitter |
| Open inventory, map, build menu, and settings | Capture pauses and HUD does not overlap |
| Teleport repeatedly | No duplicate widget, stale marker, or memory growth |
| Join and leave multiplayer | Local-only initialization remains single-instance |
| Gather near 10+ guild members | Marker pool remains bounded and responsive |
| Enter a dense base | Frame-time gates still pass or degraded mode activates |
| Hide minimap for ten minutes | Zero capture and marker update work |
| Remove mod | No save change and no server-side cleanup required |

## Authoring and Release

The current community LogicMod workflow requires:

- Unreal Engine 5.1
- Palworld Modding Kit
- .NET 6
- Visual Studio 2022 with MSVC v143 14.38
- Wwise 2021.1.11

The cooked `.pak`/`.ucas`/`.utoc` output installs through UE4SS LogicMods. The
installer must verify hashes and treat the mod as a private beta until every
performance and visual gate passes.

The architecture was informed by SvenBrnn's MIT-licensed
`pal-yet-another-minimap-mod`. Any reused source assets or Blueprint graphs must
retain its copyright notice and MIT license.
