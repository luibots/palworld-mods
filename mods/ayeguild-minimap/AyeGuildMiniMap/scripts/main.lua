local UEHelpers = require("UEHelpers")

local MOD_NAME = "AyeGuildMiniMap"
local MAP_PACKAGE = "/Game/Pal/Texture/UI/Map/T_WorldMap"
local MAP_ASSET = "/Game/Pal/Texture/UI/Map/T_WorldMap.T_WorldMap"
local MAP_SIZE = 272.0
local MAP_MARGIN = 24.0
local MARKER_SIZE = 12.0
local MAP_MIN = -1000.0
local MAP_MAX = 1000.0

local root_widget = nil
local marker_slot = nil
local coordinate_text = nil
local visible = true
local update_queued = false
local retry_after = 0

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

local function build_minimap()
    local controller = UEHelpers:GetPlayerController()
    if not valid(controller) then
        error("PlayerController is not ready")
    end

    root_widget = create_object("/Script/UMG.UserWidget", controller)
    local widget_tree = create_object("/Script/UMG.WidgetTree", root_widget)
    local canvas = create_object("/Script/UMG.CanvasPanel", widget_tree)
    local map_image = create_object("/Script/UMG.Image", widget_tree)
    local marker = create_object("/Script/UMG.Border", widget_tree)
    coordinate_text = create_object("/Script/UMG.TextBlock", widget_tree)

    root_widget.WidgetTree = widget_tree
    widget_tree.RootWidget = canvas

    map_image:SetBrushFromTexture(load_map_texture(), false)
    map_image:SetRenderOpacity(0.88)
    add_fixed_widget(
        canvas,
        map_image,
        -MAP_MARGIN,
        MAP_MARGIN,
        MAP_SIZE,
        MAP_SIZE
    )

    marker:SetBrushColor({R = 1.0, G = 0.72, B = 0.08, A = 1.0})
    marker_slot = add_fixed_widget(
        canvas,
        marker,
        -MAP_MARGIN - (MAP_SIZE / 2.0),
        MAP_MARGIN + (MAP_SIZE / 2.0),
        MARKER_SIZE,
        MARKER_SIZE
    )
    marker_slot:SetAlignment({X = 0.5, Y = 0.5})

    coordinate_text:SetText(FText("X 0  Y 0"))
    add_fixed_widget(
        canvas,
        coordinate_text,
        -MAP_MARGIN,
        MAP_MARGIN + MAP_SIZE + 5.0,
        MAP_SIZE,
        28.0
    )

    root_widget:AddToViewport(100)
    root_widget:SetVisibility(visible and 0 or 1)
    log("Minimap created. Press F6 to hide or show it.")
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
    if not valid(root_widget) then
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
    local marker_x = -MAP_MARGIN - MAP_SIZE + (normalized_x * MAP_SIZE)
    local marker_y = MAP_MARGIN + MAP_SIZE - (normalized_y * MAP_SIZE)

    marker_slot:SetOffsets({
        Left = marker_x,
        Top = marker_y,
        Right = MARKER_SIZE,
        Bottom = MARKER_SIZE
    })
    coordinate_text:SetText(FText(string.format(
        "X %d  Y %d",
        math.floor(map_x + 0.5),
        math.floor(map_y + 0.5)
    )))
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

LoopAsync(500, function()
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
