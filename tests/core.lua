-- Runs offline with the actual core module injected by run.ps1.
local Core = (function()
-- CLARIS_CORE_SOURCE
end)()

local passed = 0
local function test(name, fn)
    local ok, message = pcall(fn)
    assert(ok, name .. ": " .. tostring(message))
    passed = passed + 1
end
local function rejects(fn, fragment)
    local ok, message = pcall(fn)
    assert(not ok, "Expected a rejected operation")
    if fragment then assert(tostring(message):find(fragment, 1, true), tostring(message)) end
end
local items = {
    [954] = { name = "Sugar Cane", hits = 2, solid = true },
    [955] = { name = "Sugar Cane Seed", kind = "seed" },
    [628] = { name = "Tangram Variant", hits = 4, seedId = 627 },
    [627] = { name = "Tangram Seed", kind = "seed" },
    [1422] = { name = "Display Box", hits = 6, display = true },
    [18] = { name = "Fist", kind = "tool" },
}
local function box(world, x, y)
    return { world = world, x = x, y = y, standX = x - 1, standY = y }
end
local function setup()
    local config = Core.defaults()
    config.blockId = 954
    config.points = {
        pnb = { world = "BREAK", x = 10, y = 8 },
        seedBox = box("BREAK", 8, 8), blockBox = box("BREAK", 12, 8),
        farmBox = box("FARM", 20, 8), farmDoor = box("FARM", 21, 8),
        breakDoor = box("BREAK", 13, 8),
    }
    return config
end

test("A saved sugar cane setup survives validation without sharing mutable data", function()
    local config = setup()
    local saved = Core.validate(config)
    assert(Core.checkSetup(saved, "pnb", items))
    assert(Core.checkSetup(saved, "transfer", items))
    saved.points.pnb.x = 11
    saved.options.punchDelay = 1
    assert(config.points.pnb.x == 10 and config.options.punchDelay == 0.24)
end)
test("The screenshot grid contains ten unique tiles above the player", function()
    local grid = Core.grid(setup().points.pnb)
    local seen = {}
    assert(#grid == 10)
    for _, tile in ipairs(grid) do
        assert(tile.x >= 8 and tile.x <= 12 and (tile.y == 6 or tile.y == 7))
        local key = tile.x .. ":" .. tile.y
        assert(not seen[key])
        seen[key] = true
    end
    assert(seen["8:6"] and seen["12:7"] and not seen["10:8"])
end)
test("Sugar cane and shared-seed variants select the proper seed", function()
    assert(Core.seedId(items, 954) == 955)
    assert(Core.seedId(items, 628) == 627)
    rejects(function() Core.seedId(items, 100) end, "missing")
    rejects(function() Core.seedId(items, 1422) end, "seed")
end)
test("The item selector excludes tools and storage infrastructure", function()
    assert(Core.farmable(items[954]))
    assert(not Core.farmable(items[18]))
    assert(not Core.farmable(items[1422]))
    assert(not Core.farmable({ hits = 3, background = true }))
    assert(not Core.farmable({ hits = 0 }))
end)
test("Dedicated storage sums multiple stacks and handles empty storage", function()
    assert(Core.storageCount({ {954, 200}, {954, 4306, 0.75} }, 954) == 4506)
    assert(Core.storageCount(nil, 954) == 0)
    assert(Core.storageCount({}, 954) == 0)
end)
test("Mixed storage is rejected before withdrawal can take unrelated items", function()
    rejects(function() Core.storageCount({ {954, 30}, {955, 200} }, 954) end, "different item")
    rejects(function() Core.storageCount({ {954, -1} }, 954) end, "Invalid storage count")
    rejects(function() Core.storageCount({ {954, 0.5} }, 954) end, "Invalid storage count")
end)
test("PNB requires both boxes in the same world and exact left/right layout", function()
    local config = setup()
    config.points.seedBox.world = "FARM"
    rejects(function() Core.checkSetup(config, "pnb", items) end, "same world")
    config = setup()
    config.points.seedBox.x = 9
    rejects(function() Core.checkSetup(config, "pnb", items) end, "Layout")
    config = setup()
    config.points.blockBox.y = 7
    rejects(function() Core.checkSetup(config, "pnb", items) end, "Layout")
end)
test("Transfer requires farm and breaking doors to match their own worlds", function()
    local config = setup()
    config.points.farmDoor.world = "BREAK"
    rejects(function() Core.checkSetup(config, "transfer", items) end, "Farm storage")
    config = setup()
    config.points.breakDoor.world = "FARM"
    rejects(function() Core.checkSetup(config, "transfer", items) end, "Block storage")
    config = setup()
    config.points.farmBox.world, config.points.farmDoor.world = "BREAK", "BREAK"
    rejects(function() Core.checkSetup(config, "transfer", items) end, "different")
end)
test("Incomplete setup and unknown blocks cannot start", function()
    local config = setup()
    config.points.pnb = nil
    rejects(function() Core.checkSetup(config, "pnb", items) end, "Save this location")
    config = setup()
    config.blockId = 18
    rejects(function() Core.checkSetup(config, "pnb", items) end, "farmable")
end)
test("Corrupt version and invalid saved coordinates are rejected", function()
    local config = setup()
    config.version = 99
    rejects(function() Core.validate(config) end, "Unsupported")
    config = setup()
    config.points.pnb.x = -1
    rejects(function() Core.validate(config) end, "Invalid tile")
    config = setup()
    config.points.farmBox.standX = nil
    rejects(function() Core.validate(config) end, "standing")
    config = setup()
    config.points.pnb.y = 8.5
    rejects(function() Core.validate(config) end, "Invalid tile")
end)
test("Invalid speeds and stack thresholds cannot bypass limits", function()
    local config = setup()
    config.options.punchDelay = 0.01
    rejects(function() Core.validate(config) end, "punchDelay")
    config = setup()
    config.options.seedThreshold = 201
    rejects(function() Core.validate(config) end, "seedThreshold")
    config = setup()
    config.options.seedThreshold = 199.5
    rejects(function() Core.validate(config) end, "whole number")
    config = setup()
    config.options.moveTimeout = math.huge
    rejects(function() Core.validate(config) end, "moveTimeout")
    config = setup()
    config.options.placeDelay = 0/0
    rejects(function() Core.validate(config) end, "placeDelay")
end)
test("Profile filenames allow readable names and reject path traversal", function()
    assert(Core.profileName("  Sugar Cane - Farm_1  ") == "Sugar Cane - Farm_1")
    rejects(function() Core.profileName("../Other/profile") end)
    rejects(function() Core.profileName("..\\Other") end)
    rejects(function() Core.profileName("") end)
    rejects(function() Core.profileName(string.rep("x", 49)) end)
end)

return string.format("%d configuration/layout/storage tests passed", passed)
