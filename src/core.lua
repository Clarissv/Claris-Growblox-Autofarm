-- Pure configuration and layout helpers; bundled into the runnable script.
local Core = {}
Core.VERSION = 1
Core.REPO = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/"
Core.POINTS = { "pnb", "blockBox", "seedBox", "farmBox", "farmDoor", "breakDoor" }
Core.LIMITS = {
    placeDelay = { 0.15, 2 }, punchDelay = { 0.22, 2 },
    collectDelay = { 0.3, 5 }, actionTimeout = { 5, 30 },
    moveTimeout = { 5, 90 }, seedThreshold = { 1, 200 },
}

function Core.defaults()
    return {
        version = Core.VERSION, blockId = 0, points = {},
        options = { placeDelay = 0.2, punchDelay = 0.24, collectDelay = 0.75,
            actionTimeout = 10, moveTimeout = 30, seedThreshold = 200 },
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

function Core.validate(input)
    assert(type(input) == "table" and input.version == Core.VERSION, "Unsupported or damaged profile.")
    assert(integer(input.blockId, 0, 65535), "Invalid block ID in profile.")
    assert(type(input.points) == "table" and type(input.options) == "table", "Incomplete profile.")
    local out = Core.defaults()
    out.blockId = input.blockId
    for key, limits in pairs(Core.LIMITS) do
        local value = input.options[key]
        assert(finite(value) and value >= limits[1] and value <= limits[2], "Invalid setting: " .. key)
        if key == "seedThreshold" then
            assert(value == math.floor(value), "Seed threshold must be a whole number.")
        end
        out.options[key] = value
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
    return out
end

function Core.grid(anchor)
    local result = {}
    -- Screenshot: five columns, two rows directly above the standing tile.
    for row = 1, 2 do
        for dx = -2, 2 do
            table.insert(result, { x = anchor.x + dx, y = anchor.y - row })
        end
    end
    return result
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

function Core.storageCount(rows, itemId)
    local count = 0
    for _, row in pairs(rows or {}) do
        assert(type(row) == "table" and row[1] == itemId,
            "This storage box contains a different item. Use a box dedicated to the selected item.")
        assert(integer(row[2], 0, 4294967295), "Invalid storage count.")
        count = count + row[2]
    end
    return count
end

function Core.checkSetup(config, mode, items)
    assert(Core.farmable(items[config.blockId]), "Choose a farmable block from your inventory.")
    local keys = mode == "pnb" and { "pnb", "blockBox", "seedBox" }
        or { "farmBox", "farmDoor", "blockBox", "breakDoor" }
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
        assert(p.pnb.x >= 2 and p.pnb.y >= 2, "PNB grid is outside the world.")
    else
        assert(p.farmBox.world == p.farmDoor.world, "Farm storage and farm door must be in the same world.")
        assert(p.blockBox.world == p.breakDoor.world, "Block storage and return door must be in the same world.")
        assert(p.farmBox.world ~= p.blockBox.world, "Farm and breaking worlds must be different.")
    end
    return true
end

return Core
