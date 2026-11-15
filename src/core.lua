-- Pure configuration and layout helpers; bundled into the runnable script.
local Core = {}
Core.VERSION = 1
Core.REPO = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/"
Core.POINTS = { "pnb", "blockBox", "seedBox", "farmBox", "moveBox", "farmDoor", "breakDoor", "plantBox" }
Core.BOOL_OPTIONS = { "antiAFK", "autoRejoin", "moveAfterHarvest", "harvestRespawn", "fpsBooster", "fpsGreyMap", "harvestPlanting" }
Core.LIMITS = {
    placeDelay = { 0.15, 2 }, punchDelay = { 0.22, 2 },
    collectDelay = { 0, 5 }, actionTimeout = { 5, 30 },
    moveTimeout = { 5, 90 }, seedThreshold = { 1, 200 },
}

function Core.defaults()
    return {
        version = Core.VERSION, blockId = 0, points = {},
        options = { placeDelay = 0.2, punchDelay = 0.24, collectDelay = 0.1,
            actionTimeout = 10, moveTimeout = 30, seedThreshold = 200, antiAFK = true, autoRejoin = true,
            moveAfterHarvest = false, harvestRespawn = true, fpsBooster = false, fpsGreyMap = false, harvestPlanting = false },
        webhook = { url = "", enabled = false, intervalMinutes = 5, includeBoxes = true,
            discordId = "", failureAlerts = true },
        planting = {seedId = 0, storageWorld = "", worlds = {}},
        harvesting = {method = "fist"},
        moving = {item = "blocks"},
        rotation = {farms = {}},
    }
end

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function integer(n, min, max)
    return finite(n) and n == math.floor(n) and n >= min and n <= max
end

function Core.profileName(value)
    assert(type(value) == "string", "Enter a profile name.")
    local name = value:match("^%s*(.-)%s*$")
    assert(#name > 0 and #name <= 48 and name:match("^[%w _%-]+$"),
        "Use 1-48 letters, numbers, spaces, underscores, or hyphens.")
    return name
end

function Core.webhookURL(value)
    assert(type(value) == "string", "Enter a Discord webhook URL.")
    local url = value:match("^%s*(.-)%s*$")
    if url == "" then return url end
    local host, path = url:match("^https://([^/]+)/api/(.+)$")
    assert(host and (host == "discord.com" or host == "discordapp.com"
        or host == "canary.discord.com" or host == "ptb.discord.com"), "Use an HTTPS Discord webhook URL.")
    path = path:gsub("^v%d+/", ""):gsub("/$", "")
    assert(#url <= 300 and path:match("^webhooks/%d+/[%w_%-]+$"), "Use a valid Discord webhook URL.")
    return url:gsub("/$", "")
end

function Core.validateWebhook(input)
    local out = Core.defaults().webhook
    if input == nil then return out end
    assert(type(input) == "table", "Invalid webhook settings.")
    out.url = Core.webhookURL(input.url)
    assert(type(input.enabled) == "boolean" and type(input.includeBoxes) == "boolean", "Invalid webhook toggles.")
    assert(finite(input.intervalMinutes) and input.intervalMinutes >= 1 and input.intervalMinutes <= 1440,
        "Webhook interval must be between 1 and 1440 minutes.")
    assert(not input.enabled or out.url ~= "", "Set the Discord webhook URL before enabling reports.")
    out.enabled, out.includeBoxes, out.intervalMinutes = input.enabled, input.includeBoxes, input.intervalMinutes
    out.discordId = Core.discordUserId(input.discordId)
    if input.failureAlerts ~= nil then
        assert(type(input.failureAlerts) == "boolean", "Invalid failure alert toggle.")
        out.failureAlerts = input.failureAlerts
    end
    return out
end

function Core.discordUserId(value)
    if value == nil then return "" end
    assert(type(value) == "string", "Enter your Discord user ID as digits.")
    local id = value:match("^%s*(.-)%s*$")
    if id == "" then return id end
    id = id:match("^<@!?(%d+)>$") or id
    assert(#id >= 17 and #id <= 20 and id:match("^[1-9]%d+$"),
        "Use a 17-20 digit Discord user ID. Enable Discord Developer Mode, then Copy User ID.")
    return id
end

function Core.worldName(value)
    assert(type(value) == "string", "Enter a world name.")
    local name = value:match("^%s*(.-)%s*$"):upper()
    assert(#name > 0 and #name <= 48 and name:match("^[%w_%-]+$"), "Use a world name with 1-48 letters, digits, underscores, or hyphens.")
    return name
end

function Core.parseWorlds(value)
    assert(type(value) == "string", "Enter farm worlds separated by commas.")
    local worlds, seen = {}, {}
    for part in value:gmatch("[^,;\r\n]+") do
        if part:match("%S") then
            local name = Core.worldName(part)
            if not seen[name] then table.insert(worlds, name); seen[name] = true end
        end
    end
    assert(#worlds <= 50, "Use at most 50 farm worlds.")
    return worlds
end

function Core.validatePlanting(input)
    if input == nil then return Core.defaults().planting end
    assert(type(input) == "table" and integer(input.seedId, 0, 65535)
        and type(input.storageWorld) == "string" and type(input.worlds) == "table", "Invalid planting settings.")
    local out = {seedId = input.seedId, storageWorld = input.storageWorld == "" and "" or Core.worldName(input.storageWorld), worlds = {}}
    local seen = {}
    for index, value in pairs(input.worlds) do
        assert(integer(index, 1, #input.worlds), "Invalid farm world list.")
        local name = Core.worldName(value)
        assert(not seen[name], "Duplicate farm world: " .. name)
        seen[name], out.worlds[index] = true, name
    end
    assert(#out.worlds <= 50, "Use at most 50 farm worlds.")
    return out
end

function Core.validate(input)
    assert(type(input) == "table" and input.version == Core.VERSION, "Unsupported or damaged profile.")
    assert(integer(input.blockId, 0, 65535), "Invalid block ID in profile.")
    assert(type(input.points) == "table" and type(input.options) == "table", "Incomplete profile.")
    local out = Core.defaults()
    out.webhook = Core.validateWebhook(input.webhook)
    out.planting = Core.validatePlanting(input.planting)
    if input.moving ~= nil then
        assert(type(input.moving) == "table" and (input.moving.item == "blocks" or input.moving.item == "seeds"),
            "Invalid Moving Drops item.")
        out.moving.item = input.moving.item
    end
    if input.harvesting ~= nil then
        assert(type(input.harvesting) == "table" and (input.harvesting.method == "fist" or input.harvesting.method == "tractor"),
            "Invalid harvesting method.")
        out.harvesting.method = input.harvesting.method
    end
    out.blockId = input.blockId
    for key, limits in pairs(Core.LIMITS) do
        local value = input.options[key]
        assert(finite(value) and value >= limits[1] and value <= limits[2], "Invalid setting: " .. key)
        if key == "seedThreshold" then
            assert(value == math.floor(value), "Seed threshold must be a whole number.")
        end
        out.options[key] = value
    end
    for _, key in ipairs(Core.BOOL_OPTIONS) do
        local value = input.options[key]
        if value ~= nil then
            assert(type(value) == "boolean", "Invalid setting: " .. key)
            out.options[key] = value
        end
    end
    for _, key in ipairs(Core.POINTS) do
        local point = input.points[key]
        if point ~= nil then
            assert(type(point) == "table" and type(point.world) == "string" and #point.world > 0,
                "Invalid saved world: " .. key)
            assert(integer(point.x, 0, 65535) and integer(point.y, 0, 65535), "Invalid tile: " .. key)
            local copy = { world = point.world, x = point.x, y = point.y }
            if key ~= "pnb" then
                assert(integer(point.standX, 0, 65535) and integer(point.standY, 0, 65535),
                    "Missing standing position: " .. key)
                copy.standX, copy.standY = point.standX, point.standY
            end
            out.points[key] = copy
        end
    end
    if input.rotation ~= nil then
        assert(type(input.rotation) == "table" and type(input.rotation.farms) == "table", "Invalid rotation farm storage.")
        local total = 0
        for name, point in pairs(input.rotation.farms) do
            local world = Core.worldName(name)
            assert(world == name and type(point) == "table" and point.world == world, "Invalid rotation storage world.")
            local copy = {world = world}
            for _, key in ipairs({"x", "y", "standX", "standY"}) do
                assert(integer(point[key], 0, 65535), "Invalid rotation storage position.")
                copy[key] = point[key]
            end
            out.rotation.farms[world], total = copy, total + 1
        end
        assert(total <= 50, "Use at most 50 saved rotation farms.")
    end
    if out.points.farmBox and not out.rotation.farms[out.points.farmBox.world] then
        out.rotation.farms[out.points.farmBox.world] = out.points.farmBox
    end
    return out
end

function Core.grid(anchor)
    local result = {}
    -- One block directly above the player keeps new drops within pickup reach.
    table.insert(result, { x = anchor.x, y = anchor.y - 1 })
    return result
end

function Core.exportConfig(config, profile, scriptVersion)
    return {format = "ClarisGrowbloxConfig", version = 1, scriptVersion = scriptVersion,
        profile = Core.profileName(profile), config = Core.validate(config)}
end

function Core.importConfig(record, name)
    assert(type(record) == "table", "Paste an exported configuration or saved profile JSON.")
    local config, profile
    if record.format ~= nil then
        assert(record.format == "ClarisGrowbloxConfig" and record.version == 1,
            "Unsupported configuration export. Export again using the current script.")
        config, profile = Core.validate(record.config), Core.profileName(record.profile)
    else
        assert(record.config == nil, "Import a configuration export or profile file; task recovery files cannot be imported.")
        config, profile = Core.validate(record), "Imported Farm"
    end
    if name ~= nil then
        assert(type(name) == "string", "Enter a profile name.")
        if name:match("%S") then profile = Core.profileName(name) end
    end
    return config, profile
end

function Core.seedId(items, blockId)
    local item = items[blockId]
    assert(item, "Selected block is missing from the current game data.")
    local id = item.seedId or blockId + 1
    assert(items[id] and items[id].kind == "seed", "This block has no supported seed type.")
    return id
end

function Core.farmable(item)
    return type(item) == "table" and (item.kind == nil or item.kind == "block") and not item.background
        and not item.lock and not item.area and not item.display and not item.displayOne
        and not item.entrance and not item.door and not item.idOnly and not item.vip
        and type(item.hits) == "number" and item.hits > 0
end

function Core.storageCount(rows, itemId, companionId)
    local count = 0
    for _, row in pairs(rows or {}) do
        assert(type(row) == "table" and (row[1] == itemId or (companionId ~= nil and row[1] == companionId)),
            "This storage box contains a different item. Use a box dedicated to the selected item.")
        assert(integer(row[2], 0, 4294967295), "Invalid storage count.")
        if row[1] == itemId then count = count + row[2] end
    end
    return count
end

-- Reporting can count the selected item in mixed boxes without changing them.
function Core.itemCount(rows, itemId)
    assert(type(rows) == "table", "Display contents are unavailable.")
    local total = 0
    for _, row in pairs(rows) do
        assert(type(row) == "table" and integer(row[1], 0, 65535)
            and integer(row[2], 0, 4294967295), "Invalid display contents.")
        if row[1] == itemId then total = total + row[2] end
    end
    return total
end

function Core.plantingTile(world, items, x, y)
    if x < 0 or x >= world.w or y < 0 or y >= world.h - 1 then return false end
    if not world.fg[y] or world.fg[y][x] ~= 0 then return false end
    local below = items[world.fg[y + 1] and world.fg[y + 1][x] or 0]
    return below ~= nil and (below.solid == true or below.platform == true)
end

function Core.farmRows(world, items)
    local rows = {}
    for y = 0, world.h - 2 do
        local row = {y = y, count = 0}
        for x = 0, world.w - 1 do
            local below = items[world.fg[y + 1] and world.fg[y + 1][x] or 0]
            if below and (below.solid == true or below.platform == true) then
                local tile = items[world.fg[y] and world.fg[y][x] or 0]
                if not tile or not tile.solid or tile.kind == "seed" then
                    row.left, row.right, row.count = row.left or x, x, row.count + 1
                end
            end
        end
        if row.count > 0 then table.insert(rows, row) end
    end
    local wide = {}
    for _, row in ipairs(rows) do if row.count >= 3 then table.insert(wide, row) end end
    -- A farm with long rows can also contain individual boxes or stepping stones.
    -- Those supports do not constitute another farm row or reverse its direction.
    if #wide >= 2 then rows = wide end
    for index, row in ipairs(rows) do row.direction = index % 2 == 1 and 1 or -1 end
    return rows
end

function Core.plantingTiles(world, items, rows)
    local tiles = {}
    for index, row in ipairs(rows or Core.farmRows(world, items)) do
        local direction = index % 2 == 1 and 1 or -1
        local first, last = direction == 1 and row.left or row.right, direction == 1 and row.right or row.left
        for x = first, last, direction do
            if Core.plantingTile(world, items, x, row.y) then table.insert(tiles, {x = x, y = row.y}) end
        end
    end
    return tiles
end

function Core.rowHasPlantingSpace(world, items, row, skipped)
    for x = row.left, row.right do
        if not (skipped and skipped[x .. ":" .. row.y]) and Core.plantingTile(world, items, x, row.y) then return true end
    end
    return false
end

function Core.hasTrees(world, seedId)
    for y = 0, world.h - 1 do
        for x = 0, world.w - 1 do
            if world.fg[y] and world.fg[y][x] == seedId then return true end
        end
    end
    return false
end

-- Check the whole world, including trees outside the detected walking rows.
-- Unknown growth data must never be interpreted as a mature tree.
function Core.treeGrowth(world, seedId, isRipe, timeRemaining, step)
    local growing, ripeCount, remaining, unknownTimer = 0, 0, nil, false
    for y = 0, world.h - 1 do
        for x = 0, world.w - 1 do
            if world.fg[y] and world.fg[y][x] == seedId then
                assert(type(isRipe) == "function", "Tree growth hooks are unavailable.")
                local ripe = isRipe(x, y, seedId)
                assert(type(ripe) == "boolean", "Tree growth data is not ready. Reconnect and copy diagnostics.")
                if ripe then ripeCount = ripeCount + 1
                else
                    growing = growing + 1
                    local left = type(timeRemaining) == "function" and timeRemaining(x, y, seedId) or nil
                    if type(left) == "number" and left == left and left > 0 and left < math.huge then
                        remaining = math.max(remaining or left, left)
                    else unknownTimer = true end
                end
            end
        end
        if step and y % 16 == 15 then step() end
    end
    return growing, ripeCount, unknownTimer and math.min(remaining or 30, 30) or remaining or 30
end

function Core.ripeTrees(world, seedId, row, ripe)
    local result = {}
    local direction = row.direction or 1
    local first, last = direction == 1 and row.left or row.right, direction == 1 and row.right or row.left
    for x = first, last, direction do
        if world.fg[row.y] and world.fg[row.y][x] == seedId then
            local ready = ripe(x, row.y, seedId)
            assert(ready ~= nil, "Tree growth data is not ready at " .. x .. ", " .. row.y .. ". Reconnect after the world loads.")
            if ready then table.insert(result, {x = x, y = row.y}) end
        end
    end
    return result
end

function Core.transferDestination(config)
    return config.points.moveBox or config.points[config.moving and config.moving.item == "seeds" and "seedBox" or "blockBox"]
end

function Core.checkSetup(config, mode, items)
    assert(mode == "pnb" or mode == "transfer" or mode == "harvest" or mode == "plant" or mode == "rotation", "Unknown farming task.")
    if mode == "rotation" then
        Core.checkSetup(config, "plant", items)
        Core.checkSetup(config, "pnb", items)
        assert(config.planting.seedId == Core.seedId(items, config.blockId), "Rotation planting seed must match the selected PNB block.")
        local stock, seeds = config.points.plantBox, config.points.seedBox
        assert(stock.world == seeds.world and stock.x == seeds.x and stock.y == seeds.y,
            "Use the PNB seed box as planting storage for rotation.")
        for _, name in ipairs(config.planting.worlds) do
            assert(config.rotation.farms[name], "Save Farm storage in rotation world: " .. name)
        end
        return true
    end
    if mode == "plant" then
        local p = Core.validatePlanting(config.planting)
        assert(items[p.seedId] and items[p.seedId].kind == "seed", "Choose a seed on the Planting tab.")
        assert(p.storageWorld ~= "" and config.points.plantBox, "Save the planting seed Display Box and storage world first.")
        assert(config.points.plantBox.world:upper() == p.storageWorld, "The saved seed Display Box must be in the entered storage world.")
        assert(#p.worlds > 0, "Enter at least one dirt farm world.")
        for _, name in ipairs(p.worlds) do assert(name ~= p.storageWorld, "Seed storage and dirt farm worlds must be different.") end
        return true
    end
    assert(Core.farmable(items[config.blockId]), "Choose a farmable block from your inventory.")
    local keys = mode == "pnb" and { "pnb", "blockBox", "seedBox" }
        or mode == "harvest" and { "farmBox" }
        or { "farmBox" }
    for _, key in ipairs(keys) do
        assert(config.points[key], "Save this location first: " .. key)
    end
    local p = config.points
    if mode == "pnb" then
        Core.seedId(items, config.blockId)
        assert(p.pnb.world == p.blockBox.world and p.pnb.world == p.seedBox.world,
            "PNB spot and both storage boxes must be in the same world.")
        assert(p.seedBox.x == p.pnb.x - 2 and p.seedBox.y == p.pnb.y
            and p.blockBox.x == p.pnb.x + 2 and p.blockBox.y == p.pnb.y,
            "Layout must be: seed box, empty tile, player, empty tile, block box.")
        assert(p.pnb.x >= 2 and p.pnb.y >= 1, "PNB tile or storage layout is outside the world.")
    elseif mode == "transfer" then
        Core.seedId(items, config.blockId)
        local destination = Core.transferDestination(config)
        assert(destination, "Save the destination Display Box on Moving Drops first.")
        assert(p.farmBox.world ~= destination.world, "Farm and destination worlds must be different.")
    end
    return true
end

return Core
