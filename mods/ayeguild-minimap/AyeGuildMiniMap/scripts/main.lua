local UEHelpers = require("UEHelpers")

local MOD_NAME = "AyeGuildMiniMap"
local MAP_PACKAGE = "/Game/Pal/Texture/UI/Map/T_WorldMap"
local MAP_ASSET = "/Game/Pal/Texture/UI/Map/T_WorldMap.T_WorldMap"
local VIEW_SIZE = 260.0
local MAP_SCALE = 6.0
local MAP_RENDER_SIZE = VIEW_SIZE * MAP_SCALE
local MAP_MARGIN = 24.0
local MARKER_OUTER_SIZE = 18.0
local MARKER_INNER_SIZE = 10.0
local MAP_MIN = -1000.0
local MAP_MAX = 1000.0

local root_widget = nil
local map_slot = nil
local coordinate_text = nil
local visible = true
local update_queued = false
local retry_after = 0
local sample_count = 0

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, message))
end

local function valid(object)
    return object and object:IsValid()
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function find_class(path)
    local class = StaticFindObject(path)
    if not valid(class) then
        error("Missing Unreal class: " .. path)
    end
    return class
end

local function create_object(class_path, outer)
    local class = find_class(class_path)
    local object = StaticConstructObject(
        class,
        outer,
        0,
        0,
        0,
        nil,
        false,
        false,
        nil
    )
    if not valid(object) then
        error("Could not construct: " .. class_path)
    end
    return object
end

local function load_map_texture()
    LoadAsset(MAP_PACKAGE)
    local texture = StaticFindObject(MAP_ASSET)
    if not valid(texture) then
        error("Could not load Palworld world-map texture")
    end
    return texture
end

local function add_fixed_widget(canvas, widget, left, top, width, height)
    local slot = canvas:AddChildToCanvas(widget)
    slot:SetAnchors({
        Minimum = {X = 1.0, Y = 0.0},
        Maximum = {X = 1.0, Y = 0.0}
    })
    slot:SetAlignment({X = 1.0, Y = 0.0})
    slot:SetOffsets({
        Left = left,
        Top = top,
        Right = width,
        Bottom = height
    })
    return slot
end

local function add_centered_widget(canvas, widget, width, height)
    local center_x = -MAP_MARGIN - (VIEW_SIZE / 2.0)
    local center_y = MAP_MARGIN + (VIEW_SIZE / 2.0)
    local slot = add_fixed_widget(canvas, widget, center_x, center_y, width, height)
    slot:SetAlignment({X = 0.5, Y = 0.5})
    return slot
end

local function build_minimap()
    local controller = UEHelpers:GetPlayerController()
    if not valid(controller) then
        error("PlayerController is not ready")
    end

    -- Keep construction local until every required widget is ready. This prevents
    -- the update loop from observing a half-built minimap while assets stream in.
    local next_root = create_object("/Script/UMG.UserWidget", controller)
    local widget_tree = create_object("/Script/UMG.WidgetTree", next_root)
    local root_canvas = create_object("/Script/UMG.CanvasPanel", widget_tree)
    local viewport = create_object("/Script/UMG.Border", widget_tree)
    local map_canvas = create_object("/Script/UMG.CanvasPanel", widget_tree)
    local map_image = create_object("/Script/UMG.Image", widget_tree)
    local marker_outer = create_object("/Script/UMG.Border", widget_tree)
    local marker_inner = create_object("/Script/UMG.Border", widget_tree)
    local next_coordinate_text = create_object("/Script/UMG.TextBlock", widget_tree)

    next_root.WidgetTree = widget_tree
    widget_tree.RootWidget = root_canvas

    viewport:SetBrushColor({R = 0.025, G = 0.035, B = 0.05, A = 0.94})
    viewport:SetClipping(1)
    viewport:AddChild(map_canvas)
    add_fixed_widget(
        root_canvas,
        viewport,
        -MAP_MARGIN,
        MAP_MARGIN,
        VIEW_SIZE,
        VIEW_SIZE
    )

    map_image:SetBrushFromTexture(load_map_texture(), false)
    map_image:SetRenderOpacity(0.96)
    local next_map_slot = map_canvas:AddChildToCanvas(map_image)
    next_map_slot:SetAnchors({
        Minimum = {X = 0.0, Y = 0.0},
        Maximum = {X = 0.0, Y = 0.0}
    })
    next_map_slot:SetOffsets({
        Left = 0.0,
        Top = 0.0,
        Right = MAP_RENDER_SIZE,
        Bottom = MAP_RENDER_SIZE
    })

    marker_outer:SetBrushColor({R = 0.02, G = 0.025, B = 0.03, A = 1.0})
    add_centered_widget(root_canvas, marker_outer, MARKER_OUTER_SIZE, MARKER_OUTER_SIZE)
    marker_inner:SetBrushColor({R = 1.0, G = 0.72, B = 0.08, A = 1.0})
    add_centered_widget(root_canvas, marker_inner, MARKER_INNER_SIZE, MARKER_INNER_SIZE)

    next_coordinate_text:SetText(FText("POSITION  X 0  Y 0"))
    next_coordinate_text:SetShadowOffset({X = 1.5, Y = 1.5})
    next_coordinate_text:SetShadowColorAndOpacity({R = 0.0, G = 0.0, B = 0.0, A = 1.0})
    add_fixed_widget(
        root_canvas,
        next_coordinate_text,
        -MAP_MARGIN,
        MAP_MARGIN + VIEW_SIZE + 6.0,
        VIEW_SIZE,
        30.0
    )

    next_root:AddToViewport(100)
    next_root:SetVisibility(visible and 0 or 1)

    root_widget = next_root
    map_slot = next_map_slot
    coordinate_text = next_coordinate_text
    log("Tracking minimap created. The player marker remains centered while the map moves.")
end

local function get_player_location()
    local controller = UEHelpers:GetPlayerController()
    if not valid(controller) then
        return nil
    end
    local pawn = controller.Pawn
    if not valid(pawn) then
        local ok, result = pcall(function()
            return controller:GetPawn()
        end)
        if ok then
            pawn = result
        end
    end
    if not valid(pawn) then
        return nil
    end
    local ok, location = pcall(function()
        return pawn:K2_GetActorLocation()
    end)
    if not ok then
        return nil
    end
    return location
end

local function world_to_map(location)
    local map_x = (location.Y - 158000.0) / 460.0
    local map_y = (location.X + 123000.0) / 460.0
    return map_x, map_y
end

local function update_minimap()
    if not valid(root_widget) or not valid(map_slot) or not valid(coordinate_text) then
        root_widget = nil
        map_slot = nil
        coordinate_text = nil
        build_minimap()
    end

    local location = get_player_location()
    if not location then
        return
    end

    local map_x, map_y = world_to_map(location)
    local span = MAP_MAX - MAP_MIN
    local normalized_x = clamp((map_x - MAP_MIN) / span, 0.0, 1.0)
    local normalized_y = clamp((map_y - MAP_MIN) / span, 0.0, 1.0)
    local texture_x = normalized_x * MAP_RENDER_SIZE
    local texture_y = (1.0 - normalized_y) * MAP_RENDER_SIZE

    map_slot:SetOffsets({
        Left = (VIEW_SIZE / 2.0) - texture_x,
        Top = (VIEW_SIZE / 2.0) - texture_y,
        Right = MAP_RENDER_SIZE,
        Bottom = MAP_RENDER_SIZE
    })
    coordinate_text:SetText(FText(string.format(
        "POSITION  X %d  Y %d",
        math.floor(map_x + 0.5),
        math.floor(map_y + 0.5)
    )))

    sample_count = sample_count + 1
    if sample_count >= 20 then
        sample_count = 0
        log(string.format("Tracking position X %.1f Y %.1f", map_x, map_y))
    end
end

local function toggle_minimap()
    ExecuteInGameThread(function()
        visible = not visible
        if valid(root_widget) then
            root_widget:SetVisibility(visible and 0 or 1)
        end
        log(visible and "Minimap shown" or "Minimap hidden")
    end)
end

RegisterKeyBind(Key.F6, toggle_minimap)

LoopAsync(250, function()
    if update_queued then
        return false
    end
    local now = os.time()
    if now < retry_after then
        return false
    end
    update_queued = true
    ExecuteInGameThread(function()
        local ok, message = pcall(update_minimap)
        if not ok then
            retry_after = os.time() + 5
            log("Update paused for 5 seconds: " .. tostring(message))
        end
        update_queued = false
    end)
    return false
end)

log("Loaded. The minimap will appear after entering a world.")
