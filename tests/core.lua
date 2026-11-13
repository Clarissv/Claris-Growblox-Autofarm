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
    config.options.collectDelay = 0.75 -- Existing profiles retain their saved extra delay.
    local saved = Core.validate(config)
    assert(saved.options.collectDelay == 0.75 and Core.defaults().options.collectDelay == 0.1)
    assert(Core.checkSetup(saved, "pnb", items))
    assert(Core.checkSetup(saved, "transfer", items))
    saved.points.pnb.x = 11
    saved.options.punchDelay = 1
    assert(config.points.pnb.x == 10 and config.options.punchDelay == 0.24)
end)
test("PNB selects exactly one tile directly above the player", function()
    local grid = Core.grid(setup().points.pnb)
    assert(#grid == 1 and grid[1].x == 10 and grid[1].y == 7)
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

test("Old profiles gain recovery settings and new profiles retain explicit choices", function()
    local config = setup()
    config.options.antiAFK, config.options.autoRejoin = nil, nil
    local saved = Core.validate(config)
    assert(saved.options.antiAFK and saved.options.autoRejoin)
    config.options.antiAFK, config.options.autoRejoin = false, false
    saved = Core.validate(config)
    assert(not saved.options.antiAFK and not saved.options.autoRejoin)
end)

test("Invalid anti-AFK or world-recovery values are rejected", function()
    local config = setup()
    config.options.antiAFK = "yes"
    rejects(function() Core.validate(config) end, "antiAFK")
    config = setup()
    config.options.autoRejoin = 1
    rejects(function() Core.validate(config) end, "autoRejoin")
end)

test("Older profiles default to disabled Discord reports without losing saved places", function()
    local config = setup()
    config.webhook = nil
    local saved = Core.validate(config)
    assert(saved.webhook.url == "" and not saved.webhook.enabled and saved.webhook.includeBoxes)
    assert(saved.webhook.intervalMinutes == 5 and saved.points.pnb.x == 10)
end)

test("Profiles preserve independent webhook URLs, toggles, and minutes", function()
    local config = setup()
    config.webhook = {url = " https://discord.com/api/webhooks/123/test_token ", enabled = true,
        intervalMinutes = 2.5, includeBoxes = false}
    local saved = Core.validate(config)
    assert(saved.webhook.url == "https://discord.com/api/webhooks/123/test_token")
    assert(saved.webhook.enabled and not saved.webhook.includeBoxes and saved.webhook.intervalMinutes == 2.5)
    saved.webhook.intervalMinutes = 30
    assert(config.webhook.intervalMinutes == 2.5)
end)

test("Webhook URLs require the real Discord host and a webhook endpoint", function()
    assert(Core.webhookURL("https://discord.com/api/v10/webhooks/123/test_token/")
        == "https://discord.com/api/v10/webhooks/123/test_token")
    assert(Core.webhookURL("https://discordapp.com/api/webhooks/123/test-token"))
    for _, url in ipairs({"http://discord.com/api/webhooks/123/test", "https://example.com/api/webhooks/123/test",
        "https://discord.com.evil.test/api/webhooks/123/test", "https://discord.com/api/users/123/test",
        "https://discord.com/api/webhooks/123/test?redirect=elsewhere", "https://discord.com@evil.test/api/webhooks/123/test"}) do
        rejects(function() Core.webhookURL(url) end)
    end
end)

test("Invalid intervals and incomplete webhook settings are rejected", function()
    for _, value in ipairs({0, 0.5, 1441, math.huge, "5", 0/0}) do
        local config = setup()
        config.webhook.intervalMinutes = value
        rejects(function() Core.validate(config) end, "interval")
    end
    local config = setup()
    config.webhook.enabled = true
    rejects(function() Core.validate(config) end, "URL")
    config.webhook.enabled, config.webhook.includeBoxes = false, "yes"
    rejects(function() Core.validate(config) end, "toggles")
end)

test("Reporting counts matching stacks in mixed boxes and rejects damaged contents", function()
    local rows = {{954, 10}, {955, 50}, {954, 20}}
    assert(Core.itemCount(rows, 954) == 30 and Core.itemCount(rows, 955) == 50)
    assert(#rows == 3 and rows[1][2] == 10 and Core.itemCount({}, 954) == 0)
    rejects(function() Core.itemCount(nil, 954) end, "unavailable")
    rejects(function() Core.itemCount({{954, -1}}, 954) end, "Invalid")
end)

test("Harvest collection requires only the chosen block and farm Display Box", function()
    local config = setup()
    config.points = {farmBox = config.points.farmBox}
    assert(Core.checkSetup(config, "harvest", items))
    config.points.farmBox = nil
    rejects(function() Core.checkSetup(config, "harvest", items) end, "farmBox")
end)

test("Older profiles keep automatic harvest transfer Off and validate explicit choices", function()
    local config = setup()
    config.options.moveAfterHarvest = nil
    assert(not Core.validate(config).options.moveAfterHarvest)
    config.options.moveAfterHarvest = true
    assert(Core.validate(config).options.moveAfterHarvest)
    config.options.moveAfterHarvest = "yes"
    rejects(function() Core.validate(config) end, "moveAfterHarvest")
end)

test("Old profiles receive empty planting settings and planting validates independent of PNB", function()
    local config = Core.defaults()
    config.planting = nil
    assert(Core.validate(config).planting.seedId == 0)
    config.planting = {seedId = 955, storageWorld = "STOCK", worlds = {"FARM1", "FARM2"}}
    config.points.plantBox = box("STOCK", 8, 8)
    assert(Core.checkSetup(config, "plant", items) and config.blockId == 0)
    local copy = Core.validate(config)
    copy.planting.worlds[1] = "OTHER"
    assert(config.planting.worlds[1] == "FARM1")
end)

test("World input retains order while normalizing and removing duplicate names", function()
    local list = Core.parseWorlds(" farm1, FARM2; farm1\r\n farm3 ")
    assert(#list == 3 and list[1] == "FARM1" and list[3] == "FARM3")
    rejects(function() Core.parseWorlds("farm 1") end, "world name")
    assert(#Core.parseWorlds("") == 0)
end)

test("Planting setup rejects nonseeds, mismatched storage, and planting the storage world", function()
    local config = Core.defaults()
    config.planting = {seedId = 954, storageWorld = "STOCK", worlds = {"FARM1"}}
    config.points.plantBox = box("STOCK", 8, 8)
    rejects(function() Core.checkSetup(config, "plant", items) end, "Choose a seed")
    config.planting.seedId = 955
    config.points.plantBox.world = "OTHER"
    rejects(function() Core.checkSetup(config, "plant", items) end, "entered storage world")
    config.points.plantBox.world = "STOCK"
    config.planting.worlds[1] = "STOCK"
    rejects(function() Core.checkSetup(config, "plant", items) end, "must be different")
end)

test("Damaged planting lists and seed IDs cannot enter saved profiles", function()
    local config = Core.defaults()
    config.planting.worlds = {[2] = "FARM"}
    rejects(function() Core.validate(config) end, "world list")
    config.planting.worlds = {"farm", "FARM"}
    rejects(function() Core.validate(config) end, "Duplicate")
    config.planting.worlds = {}
    config.planting.seedId = 0.5
    rejects(function() Core.validate(config) end, "planting settings")
end)

test("Planting skips occupied doors, vents, existing seeds, and floating corners", function()
    local defs = {[0] = {}, [2] = {solid = true}, [102] = {platform = true}, [12] = {door = true},
        [100] = {name = "Air Vent", solid = false}, [955] = {kind = "seed"}}
    local world = {w = 6, h = 3, fg = {[0] = {[0]=0,[1]=12,[2]=100,[3]=955,[4]=0,[5]=0},
        [1] = {[0]=2,[1]=2,[2]=2,[3]=2,[4]=102,[5]=0}, [2] = {}}}
    assert(Core.plantingTile(world, defs, 0, 0) and Core.plantingTile(world, defs, 4, 0))
    for _, x in ipairs({1, 2, 3, 5}) do assert(not Core.plantingTile(world, defs, x, 0)) end
    assert(not Core.plantingTile(world, defs, 6, 0) and not Core.plantingTile(world, defs, 0, 2))
end)

test("Supported planting rows alternate direction despite unequal row spacing", function()
    local world = {w = 3, h = 6, fg = {}}
    for y = 0, 5 do world.fg[y] = {[0]=0,[1]=0,[2]=0} end
    for x = 0, 2 do world.fg[1][x], world.fg[4][x] = 2, 2 end
    local tiles = Core.plantingTiles(world, {[0] = {}, [2] = {solid = true}})
    assert(#tiles == 6 and tiles[1].x == 0 and tiles[3].x == 2)
    assert(tiles[4].y == 3 and tiles[4].x == 2 and tiles[6].x == 0)
end)

return string.format("%d configuration/layout/storage tests passed", passed)
