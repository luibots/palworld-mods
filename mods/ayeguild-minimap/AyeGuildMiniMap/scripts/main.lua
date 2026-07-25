local UEHelpers = require("UEHelpers")

local MOD_NAME = "AyeGuildMiniMap"
local MAP_PACKAGE = "/Game/Pal/Texture/UI/Map/T_WorldMap"
local MAP_ASSET = "/Game/Pal/Texture/UI/Map/T_WorldMap.T_WorldMap"
local PLAYER_ICON_PACKAGE = "/Game/Pal/Texture/UI/InGame/T_icon_map_player"
local PLAYER_ICON_ASSET = "/Game/Pal/Texture/UI/InGame/T_icon_map_player.T_icon_map_player"
local VIEW_SIZE = 220.0
local VISIBLE_MAP_SPAN = 80.0
local MAP_MARGIN = 24.0
local MAP_TOP = 68.0
local MARKER_SIZE = 24.0
local COORDINATE_HEIGHT = 22.0
local MAP_MIN = -1000.0
local MAP_MAX = 1000.0
local MAP_COORDINATE_SPAN = MAP_MAX - MAP_MIN
local MAP_SCALE = MAP_COORDINATE_SPAN / VISIBLE_MAP_SPAN
local MAP_RENDER_SIZE = VIEW_SIZE * MAP_SCALE

local root_widget = nil
local map_slot = nil
local marker_widget = nil
local marker_slot = nil
local coordinate_text = nil
local visible = true
local update_queued = false
local retry_after = 0
local sample_count = 0
local camera_map_x = nil
local camera_map_y = nil

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

local function load_texture(package_path, asset_path)
    LoadAsset(package_path)
    local texture = StaticFindObject(asset_path)
    if not valid(texture) then
        error("Could not load Palworld texture: " .. asset_path)
    end
    return texture
end

local function add_fixed_widget(canvas, widget, left, top, width, height)
    local slot = canvas:AddChildToCanvas(widget)
    slot:SetAnchors({
        Minimum = {X = 0.0, Y = 0.0},
        Maximum = {X = 0.0, Y = 0.0}
    })
    slot:SetAlignment({X = 0.0, Y = 0.0})
    slot:SetOffsets({
        Left = left,
        Top = top,
        Right = width,
        Bottom = height
    })
    return slot
end

local function set_text_size(text_widget, size)
    local font = text_widget.Font
    font.Size = size
    text_widget:SetFont(font)
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
    local next_marker_widget = create_object("/Script/UMG.Image", widget_tree)
    local coordinate_panel = create_object("/Script/UMG.Border", widget_tree)
    local next_coordinate_text = create_object("/Script/UMG.TextBlock", widget_tree)

    next_root.WidgetTree = widget_tree
    widget_tree.RootWidget = root_canvas

    viewport:SetBrushColor({R = 0.025, G = 0.035, B = 0.05, A = 0.94})
    viewport:SetClipping(1)
    viewport:AddChild(map_canvas)
    add_fixed_widget(
        root_canvas,
        viewport,
        MAP_MARGIN,
        MAP_TOP,
        VIEW_SIZE,
        VIEW_SIZE
    )

    map_image:SetBrushFromTexture(load_texture(MAP_PACKAGE, MAP_ASSET), false)
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

    next_marker_widget:SetBrushFromTexture(
        load_texture(PLAYER_ICON_PACKAGE, PLAYER_ICON_ASSET),
        false
    )
    local next_marker_slot = add_fixed_widget(
        root_canvas,
        next_marker_widget,
        MAP_MARGIN + (VIEW_SIZE / 2.0),
        MAP_TOP + (VIEW_SIZE / 2.0),
        MARKER_SIZE,
        MARKER_SIZE
    )
    next_marker_slot:SetAlignment({X = 0.5, Y = 0.5})

    coordinate_panel:SetBrushColor({R = 0.02, G = 0.025, B = 0.035, A = 0.82})
    next_coordinate_text:SetText(FText("0, 0"))
    set_text_size(next_coordinate_text, 13)
    next_coordinate_text:SetJustification(1)
    next_coordinate_text:SetShadowOffset({X = 1.0, Y = 1.0})
    next_coordinate_text:SetShadowColorAndOpacity({R = 0.0, G = 0.0, B = 0.0, A = 1.0})
    coordinate_panel:AddChild(next_coordinate_text)
    add_fixed_widget(
        root_canvas,
        coordinate_panel,
        MAP_MARGIN + 8.0,
        MAP_TOP + VIEW_SIZE - COORDINATE_HEIGHT - 6.0,
        VIEW_SIZE - 16.0,
        COORDINATE_HEIGHT
    )

    next_root:AddToViewport(100)
    next_root:SetVisibility(visible and 0 or 1)

    root_widget = next_root
    map_slot = next_map_slot
    marker_widget = next_marker_widget
    marker_slot = next_marker_slot
    coordinate_text = next_coordinate_text
    log("GPS minimap created. The player marker moves and the local map follows.")
end

local function get_player_location()
    local controller = UEHelpers:GetPlayerController()
    if not valid(controller) then
        return nil, nil
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
        return nil, nil
    end
    local ok, location = pcall(function()
        return pawn:K2_GetActorLocation()
    end)
    if not ok then
        return nil, nil
    end
    return location, pawn
end

local function world_to_map(location)
    local map_x = (location.Y - 158000.0) / 460.0
    local map_y = (location.X + 123000.0) / 460.0
    return map_x, map_y
end

local function update_minimap()
    if not valid(root_widget)
        or not valid(map_slot)
        or not valid(marker_widget)
        or not valid(marker_slot)
        or not valid(coordinate_text)
    then
        root_widget = nil
        map_slot = nil
        marker_widget = nil
        marker_slot = nil
        coordinate_text = nil
        build_minimap()
    end

    local location, pawn = get_player_location()
    if not location then
        return
    end

    local map_x, map_y = world_to_map(location)
    if not camera_map_x or not camera_map_y then
        camera_map_x = map_x
        camera_map_y = map_y
    end

    local delta_x = map_x - camera_map_x
    local delta_y = map_y - camera_map_y
    local snap_distance = VISIBLE_MAP_SPAN * 0.42
    if math.abs(delta_x) > snap_distance or math.abs(delta_y) > snap_distance then
        camera_map_x = map_x
        camera_map_y = map_y
    else
        camera_map_x = camera_map_x + (delta_x * 0.08)
        camera_map_y = camera_map_y + (delta_y * 0.08)
    end

    local normalized_x = clamp((camera_map_x - MAP_MIN) / MAP_COORDINATE_SPAN, 0.0, 1.0)
    local normalized_y = clamp((camera_map_y - MAP_MIN) / MAP_COORDINATE_SPAN, 0.0, 1.0)
    local texture_x = normalized_x * MAP_RENDER_SIZE
    local texture_y = (1.0 - normalized_y) * MAP_RENDER_SIZE

    map_slot:SetOffsets({
        Left = (VIEW_SIZE / 2.0) - texture_x,
        Top = (VIEW_SIZE / 2.0) - texture_y,
        Right = MAP_RENDER_SIZE,
        Bottom = MAP_RENDER_SIZE
    })

    local pixels_per_map_unit = VIEW_SIZE / VISIBLE_MAP_SPAN
    local marker_x = (VIEW_SIZE / 2.0) + ((map_x - camera_map_x) * pixels_per_map_unit)
    local marker_y = (VIEW_SIZE / 2.0) - ((map_y - camera_map_y) * pixels_per_map_unit)
    marker_slot:SetOffsets({
        Left = MAP_MARGIN + marker_x,
        Top = MAP_TOP + marker_y,
        Right = MARKER_SIZE,
        Bottom = MARKER_SIZE
    })

    local rotation_ok, rotation = pcall(function()
        return pawn:K2_GetActorRotation()
    end)
    if rotation_ok and rotation then
        marker_widget:SetRenderTransformAngle(rotation.Yaw)
    end
    coordinate_text:SetText(FText(string.format(
        "%d, %d",
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
