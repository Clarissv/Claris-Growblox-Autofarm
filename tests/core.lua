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

test("FPS booster is optional in old profiles and portable when enabled", function()
    local config = setup()
    config.options.fpsBooster = nil
    assert(Core.validate(config).options.fpsBooster == false)
    config.options.fpsBooster = true
    local record = Core.exportConfig(config, "FPS Farm", "0.1.27")
    local imported = Core.importConfig(record)
    assert(imported.options.fpsBooster == true)
    config.options.fpsBooster = "yes"
    rejects(function() Core.validate(config) end, "fpsBooster")
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

test("Harvest respawn preference survives profiles and defaults On for older profiles", function()
    local config = setup()
    config.options.harvestRespawn = nil
    assert(Core.validate(config).options.harvestRespawn)
    config.options.harvestRespawn = false
    assert(not Core.validate(config).options.harvestRespawn)
    config.options.harvestRespawn = "yes"
    rejects(function() Core.validate(config) end, "harvestRespawn")
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

test("A filled upper row does not reverse the next row after a seed refill", function()
    local world = {w = 5, h = 6, fg = {}}
    local items = {[0] = {}, [2] = {solid = true}, [955] = {kind = "seed"}}
    for y = 0, 5 do world.fg[y] = {}; for x = 0, 4 do world.fg[y][x] = 0 end end
    for x = 0, 4 do world.fg[1][x], world.fg[4][x] = 2, 2 end
    local rows = Core.farmRows(world, items)
    for x = 0, 4 do world.fg[0][x] = 955 end
    world.fg[3][4] = 955
    local tiles = Core.plantingTiles(world, items, rows)
    assert(#tiles == 4 and tiles[1].y == 3 and tiles[1].x == 3 and tiles[4].x == 0)
    assert(Core.plantingTiles(world, items)[1].x == 3)
end)

test("Solid walls and isolated box roofs do not reverse long farm rows", function()
    local world = {w = 7, h = 8, fg = {}}
    local items = {[0] = {}, [2] = {solid = true}, [1422] = {solid = true, display = true}}
    for y = 0, 7 do world.fg[y] = {}; for x = 0, 6 do world.fg[y][x] = 0 end end
    for x = 1, 5 do world.fg[2][x], world.fg[6][x] = 2, 2 end
    for y = 0, 6 do world.fg[y][0] = 2 end
    world.fg[4][6] = 1422
    local rows = Core.farmRows(world, items)
    assert(#rows == 2 and rows[1].y == 1 and rows[2].y == 5)
    assert(rows[1].left == 1 and rows[2].direction == -1)
    local tiles = Core.plantingTiles(world, items, rows)
    assert(#tiles == 10 and tiles[1].x == 1 and tiles[6].x == 5 and tiles[6].y == 5)
end)

test("Harvest methods default older profiles to Fist and preserve Tractor independently", function()
    local config = setup()
    config.harvesting = nil
    assert(Core.validate(config).harvesting.method == "fist")
    config.harvesting = {method = "tractor"}
    local saved = Core.validate(config)
    assert(saved.harvesting.method == "tractor")
    saved.harvesting.method = "fist"
    assert(config.harvesting.method == "tractor")
    config.harvesting.method = "unknown"
    rejects(function() Core.validate(config) end, "harvesting method")
end)

test("Ripe trees follow physical row direction while growing trees and other crops are skipped", function()
    local world = {w = 5, h = 5, fg = {}}
    for y = 0, 4 do world.fg[y] = {}; for x = 0, 4 do world.fg[y][x] = 0 end end
    for x = 0, 4 do world.fg[3][x] = 955 end
    world.fg[3][2] = 627
    local row = {y = 3, left = 0, right = 4, direction = -1}
    local points = Core.ripeTrees(world, 955, row, function(x) return x ~= 1 end)
    assert(#points == 3 and points[1].x == 4 and points[2].x == 3 and points[3].x == 0)
    rejects(function() Core.ripeTrees(world, 955, row, function() return nil end) end, "growth data")
    assert(Core.hasTrees(world, 955) and not Core.hasTrees(world, 123))
end)

test("Planting row space excludes occupied, unsupported, and previously skipped cells", function()
    local world = {w = 4, h = 3, fg = {[0] = {[0]=955,[1]=0,[2]=0,[3]=0}, [1] = {[0]=2,[1]=2,[2]=0,[3]=2}}}
    local items = {[2]={solid=true}}
    local row = {y = 0, left = 0, right = 3}
    assert(Core.rowHasPlantingSpace(world, items, row))
    assert(not Core.rowHasPlantingSpace(world, items, row, {["1:0"] = "denied", ["3:0"] = "unreachable"}))
end)

test("Farm boxes accept the matching block and seed while dedicated PNB boxes remain strict", function()
    local rows={{955,300},{954,450},{954,50}}
    assert(Core.storageCount(rows,954,955) == 500 and Core.storageCount(rows,955,954) == 300)
    rejects(function() Core.storageCount(rows,954) end,"different item")
    rejects(function() Core.storageCount({{955,200},{18,1}},954,955) end,"different item")
end)

test("Legacy Farm storage migrates into an independent per-world rotation map", function()
    local config=setup()
    config.rotation=nil
    local saved=Core.validate(config)
    assert(saved.rotation.farms[config.points.farmBox.world].x == config.points.farmBox.x)
    config.rotation={farms={FARM={world="OTHER",x=1,y=1,standX=1,standY=1}}}
    rejects(function() Core.validate(config) end,"rotation storage world")
end)

test("Full rotation requires matching planting seeds, shared PNB seed storage, and a box for every farm", function()
    local config=setup()
    config.planting={seedId=955,storageWorld="BREAK",worlds={"FARM","FARM2"}}
    config.points.plantBox=config.points.seedBox
    config.rotation.farms={FARM=config.points.farmBox}
    local items={[954]={hits=2},[955]={kind="seed"},[627]={kind="seed"}}
    rejects(function() Core.checkSetup(config,"rotation",items) end,"FARM2")
    config.rotation.farms.FARM2={world="FARM2",x=1,y=1,standX=1,standY=1}
    assert(Core.checkSetup(config,"rotation",items))
    config.planting.seedId=627
    rejects(function() Core.checkSetup(config,"rotation",items) end,"must match")
    config.planting.seedId=955
    config.points.plantBox={world="BREAK",x=7,y=8,standX=7,standY=8}
    rejects(function() Core.checkSetup(config,"rotation",items) end,"PNB seed box")
end)

test("Portable exports retain all setup fields and round trip independently of device or account", function()
    local config=setup()
    config.planting={seedId=955,storageWorld="BREAK",worlds={"FARM","FARM2"}}
    config.harvesting.method="tractor"
    config.rotation.farms.FARM2={world="FARM2",x=7,y=8,standX=6,standY=8}
    local record=Core.exportConfig(config,"Emulator Farms","0.1.22")
    assert(record.format == "ClarisGrowbloxConfig" and record.version == 1)
    assert(record.userId == nil and record.state == nil and record.cargo == nil and record.active == nil)
    local imported,name=Core.importConfig(record)
    assert(name == "Emulator Farms" and imported.harvesting.method == "tractor")
    assert(imported.planting.worlds[2] == "FARM2" and imported.rotation.farms.FARM2.x == 7)
    imported.rotation.farms.FARM2.x=1
    assert(record.config.rotation.farms.FARM2.x == 7 and config.rotation.farms.FARM2.x == 7)
end)

test("Configuration imports accept saved profile JSON and optional profile names", function()
    local config=setup()
    config.harvesting,config.rotation=nil,nil
    local imported,name=Core.importConfig(config)
    assert(name == "Imported Farm" and imported.harvesting.method == "fist" and imported.rotation.farms.FARM.x == 20)
    local record=Core.exportConfig(config,"Source","0.1.22")
    local _,renamed=Core.importConfig(record," Cloud Phone ")
    assert(renamed == "Cloud Phone")
    local _,unchanged=Core.importConfig(record,"  ")
    assert(unchanged == "Source")
    rejects(function() Core.importConfig(record,"../Other") end,"1-48")
end)

test("Configuration imports reject foreign exports, unsupported versions, recovery records, and damaged settings", function()
    local record=Core.exportConfig(setup(),"Source","0.1.22")
    record.format="OtherApp"
    rejects(function() Core.importConfig(record) end,"Unsupported configuration export")
    record.format,record.version="ClarisGrowbloxConfig",2
    rejects(function() Core.importConfig(record) end,"Unsupported configuration export")
    rejects(function() Core.importConfig({version=1,userId=123,config=setup(),phase="deliver",cargo=200}) end,"recovery files")
    record.version,record.config.blockId=1,-1
    rejects(function() Core.importConfig(record) end,"block ID")
end)

test("Discord user IDs remain exact strings and accept a copied user mention", function()
    local id="123456789012345678"
    assert(Core.discordUserId(" " .. id .. " ") == id)
    assert(Core.discordUserId("<@" .. id .. ">") == id and Core.discordUserId("<@!" .. id .. ">") == id)
    assert(Core.discordUserId(nil) == "" and Core.discordUserId("  ") == "")
    for _,bad in ipairs({123456789012345678,"123","012345678901234567","123456789012345678901","@everyone","<@&123456789012345678>"}) do
        rejects(function() Core.discordUserId(bad) end)
    end
end)

test("Legacy webhook settings default to failure alerts without a ping and preserve new settings in exports", function()
    local config=setup()
    config.webhook={url="https://discord.com/api/webhooks/123/test_token",enabled=false,intervalMinutes=5,includeBoxes=true}
    local saved=Core.validate(config)
    assert(saved.webhook.failureAlerts and saved.webhook.discordId == "")
    saved.webhook.discordId="123456789012345678"
    saved.webhook.failureAlerts=false
    local imported=Core.importConfig(Core.exportConfig(saved,"Reports","0.1.23"))
    assert(imported.webhook.discordId == "123456789012345678" and not imported.webhook.failureAlerts)
    saved.webhook.failureAlerts="yes"
    rejects(function() Core.validate(saved) end,"failure alert toggle")
end)

return string.format("%d configuration/layout/storage tests passed", passed)
