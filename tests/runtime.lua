-- Executes the actual generated script through its explicit offline test hooks.
-- Roblox services, storage, and scheduling are mocked; this does not test a live server.
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
table.unpack = table.unpack or unpack
local passed = 0
local nativeRequire = require
local function test(name, fn)
    local ok, message = pcall(fn)
    assert(ok, name .. ": " .. tostring(message))
    passed = passed + 1
end
local function rejects(fn, fragment)
    local ok, message = pcall(fn)
    assert(not ok, "Expected rejection")
    if fragment then assert(tostring(message):find(fragment, 1, true), tostring(message)) end
end
local function fixture()
    local env, files, encoded, queue = { ClarisGrowbloxTest = true }, {}, {}, {}
    local ticks, serial = 0, 0
    local context = { pickups = 0, displays = 0 }
    request, http_request, syn, http = nil, nil, nil, nil
    shared, getrenv, getrawmetatable, getgc = {}, nil, nil, nil
    getupvalues, getupvalue, getinfo = nil, nil, nil
    typeof = nil
    require = nativeRequire
    os.clock = function() return ticks end
    getgenv = function() return env end
    isfile = function(path) return files[path] ~= nil end
    isfolder = function() return true end
    makefolder = function() end
    readfile = function(path) assert(files[path]); return files[path] end
    writefile = function(path, text) files[path] = text end
    delfile = function(path) files[path] = nil end
    local http = {
        JSONEncode = function(_, value)
            serial = serial + 1
            local key = "mock-json-" .. serial
            encoded[key] = value
            return key
        end,
        JSONDecode = function(_, text) return encoded[text] end,
    }
    local localPlayer = { UserId = 1234, Name = "TestPlayer", DisplayName = "Test Player", GetAttribute = function() return nil end }
    local services = {
        HttpService = http, Players = { LocalPlayer = localPlayer },
        ReplicatedStorage = { GetAttribute = function() return "session-registry" end },
        UserInputService = { GetFocusedTextBox = function() return nil end },
    }
    game = { GetService = function(_, name) assert(services[name], name); return services[name] end }
    task = {
        spawn = function(fn, ...)
            if context.spawn then return context.spawn(fn, ...) end
            return fn(...)
        end,
        defer = function(fn) queue[#queue + 1] = fn end,
        wait = function(seconds)
            context.waits = (context.waits or 0) + 1
            ticks = ticks + (seconds or 0.03)
            local pending = queue
            queue = {}
            for _, fn in ipairs(pending) do fn() end
            if context.onWait then context.onWait(seconds or 0.03) end
            return seconds
        end,
    }
    local function loadScript()
-- CLARIS_RUNTIME_SOURCE
    end
    local hooks = loadScript()
    context.reload = function(keepPrevious)
        if not keepPrevious then env.ClarisGrowbloxApp = nil end
        return loadScript()
    end
    context.hooks, context.env, context.files = hooks, env, files
    context.encoded = encoded
    local app = hooks.App
    app.config.blockId = 954
    local function point(world, x)
        return { world = world, x = x, y = 8, standX = 13, standY = 8 }
    end
    app.config.points = {
        pnb = { world = "BREAK", x = 10, y = 8 },
        blockBox = point("BREAK", 12), seedBox = point("BREAK", 8),
        farmBox = point("FARM", 20), farmDoor = point("FARM", 21),
        breakDoor = point("BREAK", 13),
    }
    local inventory = { slots = {}, capacity = 54 }
    function inventory:count(id)
        for _, slot in ipairs(self.slots) do if slot.id == id then return slot.n end end
        return 0
    end
    function inventory:room(id) return 200 - self:count(id) end
    function inventory:add(id, n)
        for _, slot in ipairs(self.slots) do
            if slot.id == id then slot.n = slot.n + n; return n end
        end
        self.slots[#self.slots + 1] = { id = id, n = n }
        return n
    end
    function inventory:remove(id, n)
        for index, slot in ipairs(self.slots) do
            if slot.id == id then
                assert(slot.n >= n)
                slot.n = slot.n - n
                if slot.n == 0 then table.remove(self.slots, index) end
                return true
            end
        end
        return false
    end
    local drops, boxes = {}, { [12] = {{954, 1000}}, [8] = {{955, 500}}, [20] = {{954, 300}} }
    local grid = {}
    for y = 0, 19 do
        grid[y] = {}
        for x = 0, 29 do grid[y][x] = 0 end
    end
    grid[8][8], grid[8][12], grid[8][20], grid[8][13] = 1422, 1422, 1422, 12
    local world = {
        name = "BREAK", w = 30, h = 20, fg = grid,
        dropList = function() return drops end,
        displays = { get = function(x) return boxes[x] end },
        displayTake = function() context.displays = context.displays + 1 end,
        takeDrop = function(_, n) context.pickups = context.pickups + 1; return n end,
        dropTaken = function(uid, remaining)
            for index, drop in pairs(drops) do
                if drop.uid == uid then
                    drop.n = remaining
                    if remaining == 0 then table.remove(drops, index) end
                    return
                end
            end
        end,
        call = function(...) assert(context.server, "No mock server configured"); return context.server(...) end,
    }
    local controls = { dir = function() return -1 end, jumping = function() return true end }
    local avatar = { active = true, dead = false, x = 13.5, y = 9, vx = 0, vy = 0, facing = 1, grounded = true }
    app.runtime = {
        world = world, inventory = inventory, controls = controls,
        body = { state = function() return avatar end, solidAt = function() return false end },
        items = {
            [0] = {name = "Blank", solid = false}, [2] = {name = "Dirt", solid = true, hits = 3},
            [954] = { name = "Sugar Cane", hits = 2 }, [955] = { name = "Sugar Cane Seed", kind = "seed" },
            [18] = { name = "Fist", kind = "tool" }, [1422] = { name = "Display Box", display = true },
            [12] = { name = "Door", door = true },
        },
    }
    app.token, app.job, app.jobToken = 1, "transfer", 1
    context.app, context.world, context.inventory = app, world, inventory
    context.player, context.services = localPlayer, services
    context.controls, context.avatar, context.drops, context.boxes = controls, avatar, drops, boxes
    return context
end

local function raisedFarm(f)
    for _, row in pairs(f.world.fg) do for x in pairs(row) do row[x] = 0 end end
    f.app.runtime.items[1] = {solid = true}
    f.app.runtime.items[102] = {platform = true}
    f.app.runtime.items[224] = {entrance = true, solid = true}
    local grid = f.world.fg
    for x = 4, 16 do grid[13][x] = 1 end
    for y = 11, 12 do
        for x = 6, 9 do grid[y][x] = 1 end
        for x = 12, 14 do grid[y][x] = 1 end
    end
    grid[11][10], grid[9][10] = 1, 1 -- World lock and raised dirt.
    grid[12][11], grid[11][11] = 1, 224 -- Entrance beside the lock, with a floor below.
    grid[10][9] = 1 -- This representative route has its left approach closed.
    grid[10][11], grid[9][11], grid[9][12] = 102, 102, 102
    for x = 7, 13 do grid[4][x] = 1 end
    for y = 5, 9 do grid[y][7], grid[y][13] = 1, 1 end
    f.avatar.x, f.avatar.y = 10.5, 11
    f.app.runtime.body.solidAt = function(x, y)
        if x < 0 or x >= f.world.w or y >= f.world.h then return true end
        local id = grid[y] and grid[y][x] or 0
        if id == 224 then return f.entranceClosed or false end
        return id == 1
    end
    return f.hooks.navigationMap(f.app.runtime)
end

test("Raised-farm navigation uses the side entrance instead of jumping under dirt", function()
    local f = fixture()
    local map = raisedFarm(f)
    local route, message = f.hooks.Navigation.plan(map, {x = 10, y = 10}, {x = 10, y = 8})
    assert(route, message)
    local entrance, jumped = false, false
    for _, step in ipairs(route) do
        if step.x == 11 and step.y == 11 then entrance = true end
        if step.jump then jumped = true end
    end
    assert(entrance and jumped and route[#route].x == 10 and route[#route].y == 8)
end)

test("The movement map respects closed entrances and excludes harmful supports", function()
    local f = fixture()
    local map = raisedFarm(f)
    f.entranceClosed = true
    assert(map.solid(11, 11))
    f.app.runtime.items[4] = {solid = true, hurts = true}
    f.world.fg[13][17] = 4
    assert(map.danger(17, 13))
    local route, message = f.hooks.Navigation.plan(map, {x = 10, y = 10}, {x = 17, y = 12})
    assert(not route and message:find("support", 1, true))
end)

test("Navigation refuses a sealed destination rather than repeatedly jumping", function()
    local f = fixture()
    local map = raisedFarm(f)
    for x = 9, 11 do f.world.fg[8][x] = 1 end
    local route, message = f.hooks.Navigation.plan(map, {x = 10, y = 10}, {x = 10, y = 8})
    assert(not route and message:find("headroom", 1, true))
end)

local function attachPhysics(f, map)
    local previousJump = false
    local visited = {}
    local function fits(x, feet)
        for tx = math.floor(x - 0.299), math.floor(x + 0.299) do
            for ty = math.floor(feet - 0.949), math.floor(feet - 0.002) do
                if map.solid(tx, ty) then return false end
            end
        end
        return true
    end
    f.onWait = function(seconds)
        if not f.avatar.active or f.avatar.dead then return end
        local subdivisions = math.max(1, math.ceil(seconds / 0.005))
        local dt, state = seconds / subdivisions, f.avatar
        for _ = 1, subdivisions do
            local jump, direction = f.controls.jumping(), f.controls.dir()
            if jump and not previousJump and state.grounded then state.vy, state.grounded = -19.8997487421324, false end
            previousJump = jump
            local acceleration = direction == 0 and (state.grounded and 48 or 17) or (state.grounded and 36 or 22)
            local desired = direction * 7.2
            if state.vx < desired then state.vx = math.min(desired, state.vx + acceleration * dt)
            else state.vx = math.max(desired, state.vx - acceleration * dt) end
            local nextX = state.x + state.vx * dt
            if fits(nextX, state.y) then state.x = nextX else state.vx = 0 end
            state.vy = math.min(24, state.vy + (state.vy < 0 and not jump and 143 or 55) * dt)
            local nextFeet, landed = state.y + state.vy * dt, false
            if state.vy >= 0 then
                for row = math.ceil(state.y - 0.001), math.floor(nextFeet + 0.001) do
                    for x = math.floor(state.x - 0.299), math.floor(state.x + 0.299) do
                        if map.solid(x, row) or map.platform(x, row) then
                            state.y, state.vy, landed = row - 0.001, 0, true
                            break
                        end
                    end
                    if landed then break end
                end
            end
            if not landed then
                if fits(state.x, nextFeet) then state.y = nextFeet
                else state.vy = 0 end
            end
            state.grounded = landed
            if landed then visited[math.floor(state.x) .. ":" .. math.floor(state.y - 0.01)] = true end
        end
    end
    return visited
end

test("The actual movement controller climbs from the lock via the side entrance", function()
    local f = fixture()
    local map = raisedFarm(f)
    local visited = attachPhysics(f, map)
    f.hooks.moveTo(10, 8, "BREAK", 1)
    assert(visited["11:11"], "The avatar must reach the side entrance approach")
    assert(math.abs(f.avatar.x - 10.5) < 0.16 and math.abs(f.avatar.y - 9) < 0.22)
    assert(f.controls.dir() == 0 and not f.controls.jumping() and f.avatar.grounded)
end)

test("An avatar already on the destination tile finishes its small centering move", function()
    for _, offset in ipairs({-0.20, 0.20}) do
        local f = fixture()
        local map = raisedFarm(f)
        f.avatar.x, f.avatar.y = 10.5 + offset, 8.999
        attachPhysics(f, map)
        local originalPlan, plans = f.hooks.Navigation.plan, 0
        f.hooks.Navigation.plan = function(...)
            plans = plans + 1
            assert(plans <= 4, "Centering on the current tile must yield to movement, not repeatedly plan an empty route")
            return originalPlan(...)
        end
        local began = os.clock()
        f.hooks.moveTo(10, 8, "BREAK", 1)
        assert(math.abs(f.avatar.x - 10.5) < 0.16 and f.avatar.grounded)
        assert(os.clock() > began and os.clock() - began < 0.75)
        assert(f.controls.dir() == 0 and not f.controls.jumping())
    end
end)

test("PNB refills from the box, returns to the dirt, and continues placing and breaking", function()
    local f = fixture()
    local map = raisedFarm(f)
    f.world.fg[8][8], f.world.fg[8][12] = 1422, 1422
    f.avatar.x, f.avatar.y, f.app.job = 10.5, 8.999, "pnb"
    f.app.config.points.blockBox.standX = 11
    f.boxes[12] = {{954, 1}}
    attachPhysics(f, map)
    local originalPlan, plans = f.hooks.Navigation.plan, 0
    f.hooks.Navigation.plan = function(...)
        plans = plans + 1
        assert(plans <= 12, "A refill must not spin while the avatar is already on a saved standing tile")
        return originalPlan(...)
    end
    local serverCount, withdrawals, placements, hits = 0, 0, 0, 0
    f.server = function(name, x, y)
        if name == "GetInventory" then return {slots = serverCount > 0 and {{954, serverCount}} or {}, capacity = 54} end
        assert(name == "DisplayItem" and x == 12 and y == 8)
        assert(withdrawals == 0)
        serverCount, withdrawals, f.boxes[12] = 1, withdrawals + 1, {}
        return true, {taken = {{954, 1}}}
    end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(_, x, y, id)
            assert(withdrawals == 1 and serverCount == 1 and x == 10 and y == 7)
            assert(math.abs(f.avatar.x - 10.5) < 0.16)
            f.world.fg[y][x], serverCount, placements = id, 0, placements + 1
        end,
        hit = function(x, y)
            hits = hits + 1
            if hits == 2 then f.world.fg[y][x] = 0 end
        end,
    }
    f.hooks.takeControls()
    f.hooks.runPNB(1)
    assert(withdrawals == 1 and placements == 1 and f.app.stats.broken == 1 and serverCount == 0)
    assert(f.app.status:find("Finished", 1, true))
end)

test("Stopping while following a route restores controls and prevents later jumps", function()
    local f = fixture()
    raisedFarm(f)
    local original = f.controls.jumping
    f.onWait = function() f.onWait = nil; f.app:stop() end
    rejects(function() f.hooks.moveTo(10, 8, "BREAK", 1) end, "Stopped")
    assert(f.app.controls == nil and f.controls.jumping == original)
end)

local function entryFixture()
    local f = fixture()
    f.app.job, f.app.jobToken, f.avatar.x = nil, nil, 10.5
    f.app.config.points.blockBox.standX, f.boxes[12] = 10, {}
    f.world.name, f.avatar.active = "", false
    f.entries = 0
    f.world.enter = function(name)
        assert(name == "BREAK")
        assert(f.app.pending == 1, "Only the owned entry request should be pending")
        f.entries = f.entries + 1
        f.world.name, f.avatar.active, f.avatar.dead = "BREAK", true, false
        f.avatar.x, f.avatar.y = 10.5, 9
        return true
    end
    f.server = function(name)
        assert(name == "GetInventory" and f.avatar.active and f.world.name == "BREAK")
        return {slots = {}, capacity = 54}
    end
    return f
end

test("PNB re-enters the saved world from the picker and resumes the loop", function()
    local f = entryFixture()
    f.hooks.start("pnb")
    assert(f.entries == 1 and f.app.job == nil and not f.app.lastError)
    assert(not f.app.recovering and f.app.status:find("Finished", 1, true))
    assert(not f.hooks.readPNBResume(), "Normal completion must clear automatic farm recovery")
end)

test("World re-entry follows the side-platform route before restarting PNB", function()
    local f = entryFixture()
    local map = raisedFarm(f)
    f.world.fg[8][8], f.world.fg[8][12] = 1422, 1422
    f.world.name, f.avatar.active = "", false
    local visited = attachPhysics(f, map)
    f.world.enter = function(name)
        assert(name == "BREAK")
        f.entries = f.entries + 1
        f.world.name, f.avatar.active = "BREAK", true
        f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = 10.5, 11, 0, 0
        return true
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and visited["11:11"] and not f.app.lastError)
    assert(f.app.job == nil and f.app.status:find("Finished", 1, true))
end)

test("Being sent to the picker during an inventory RPC still triggers recovery", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "BREAK", true
    local first = true
    f.server = function(name)
        assert(name == "GetInventory")
        if first then
            first = false
            f.world.name, f.avatar.active = "", false
            return nil
        end
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and not f.app.lastError and f.app.job == nil)
end)

test("Recovery enters the world when an inactive exit becomes the picker later", function()
    local f = entryFixture()
    f.world.name = "BREAK"
    f.onWait = function() f.onWait = nil; f.world.name = "" end
    f.hooks.start("pnb")
    assert(f.entries == 1 and not f.app.lastError and f.app.status:find("Finished", 1, true))
end)

test("Recovery rejects a briefly ready avatar before a second picker transition", function()
    local f = entryFixture()
    local interrupted = false
    f.onWait = function()
        if f.entries == 1 and not interrupted then
            interrupted = true
            f.world.name, f.avatar.active = "", false
        end
    end
    f.hooks.start("pnb")
    assert(interrupted and f.entries == 2 and not f.app.lastError)
    assert(f.app.status:find("Finished", 1, true))
end)

test("An invalid inventory reply with an inactive avatar and stale world name recovers", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "BREAK", true
    local first = true
    f.server = function(name)
        assert(name == "GetInventory")
        if first then first = false; f.avatar.active = false; return nil end
        return {slots = {}, capacity = 54}
    end
    f.onWait = function()
        if not f.avatar.active then f.world.name = ""; f.onWait = nil end
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and not f.app.lastError and f.app.job == nil)
end)

test("A picker transition appearing after the failed inventory response still recovers", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "BREAK", true
    local began, interrupted = os.clock(), false
    f.server = function(name)
        assert(name == "GetInventory")
        if not interrupted then return nil end
        return {slots = {}, capacity = 54}
    end
    f.onWait = function()
        if not interrupted and os.clock() - began >= 0.75 then
            interrupted = true
            f.world.name, f.avatar.active = "", false
        end
    end
    f.hooks.start("pnb")
    assert(interrupted and f.entries == 1 and not f.app.lastError)
end)

test("A genuinely malformed backpack stops after bounded reads without erasing items", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "BREAK", true
    f.inventory:add(954, 7)
    local reads = 0
    f.server = function(name) assert(name == "GetInventory"); reads = reads + 1; return {} end
    f.hooks.start("pnb")
    assert(reads == 3 and f.entries == 0 and f.app.job == nil and f.inventory:count(954) == 7)
    assert(f.app.lastError:find("Invalid backpack response", 1, true))
end)

test("Inventory replies arriving after a world exit are not applied before re-entry", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "BREAK", true
    f.inventory:add(954, 7)
    local originalEnter, first = f.world.enter, true
    f.world.enter = function(name)
        assert(f.inventory:count(954) == 7, "A world exit must not reconcile an interrupted inventory reply")
        return originalEnter(name)
    end
    f.server = function(name)
        assert(name == "GetInventory")
        if first then first = false; f.world.name, f.avatar.active = "", false end
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and not f.app.lastError and f.inventory:count(954) == 0)
end)

test("A second picker return during recovery inventory refresh retries recovery", function()
    local f = entryFixture()
    local first = true
    f.server = function(name)
        assert(name == "GetInventory")
        if first then
            first = false
            f.world.name, f.avatar.active = "", false
            return nil
        end
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(f.entries == 2 and not f.app.lastError and f.app.status:find("Finished", 1, true))
end)

test("Entering a different world during the rejoin delay cancels the saved entry", function()
    local f = entryFixture()
    f.onWait = function() f.onWait = nil; f.world.name, f.avatar.active = "OTHER", true end
    f.hooks.start("pnb")
    assert(f.entries == 0 and f.app.job == nil and f.app.lastError:find("another world", 1, true))
end)

test("Repeated picker interruptions during recovery stop after three recovery attempts", function()
    local f = entryFixture()
    f.server = function(name)
        assert(name == "GetInventory")
        f.world.name, f.avatar.active = "", false
        return nil
    end
    f.hooks.start("pnb")
    assert(f.entries == 3 and f.app.job == nil and f.app.controls == nil)
    assert(f.app.lastError:find("interrupted three times", 1, true))
end)

test("Picker discovery binds the correct entry adapter, HUD cleanup, and text focus", function()
    local f = entryFixture()
    local hudCalls, focusCalls = 0, 0
    local panel = {Visible = true, mockInstance = true,
        IsA = function(_, kind) return kind == "GuiObject" end,
        FindFirstChild = function(_, name) if name == "recent" or name == "WorldName" then return {} end end}
    local input = {mockInstance = true, IsA = function(_, kind) return kind == "TextBox" end,
        ReleaseFocus = function() focusCalls = focusCalls + 1 end}
    local hud = function() hudCalls = hudCalls + 1 end
    local wrapper, foreign = function() end, function() end
    local oldTypeof, oldUpvalues, oldInfo = typeof, getupvalues, getinfo
    typeof = function(value) return type(value) == "table" and value.mockInstance and "Instance" or type(value) end
    getinfo = function(fn) return {name = fn == hud and "hud" or "enter"} end
    getupvalues = function(fn)
        if fn == wrapper then return {{enter = f.world.enter}, panel, input, hud} end
        if fn == foreign then return {{enter = function() end}, panel, input, hud} end
        return {}
    end
    local picker = f.hooks.findWorldPicker(f.world, {foreign, wrapper})
    assert(picker and picker.panel == panel)
    picker.complete()
    assert(not panel.Visible and hudCalls == 1 and focusCalls == 1)
    typeof, getupvalues, getinfo = oldTypeof, oldUpvalues, oldInfo
end)

test("A visible picker with a stale active world re-enters and restores the game HUD", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "BREAK", true
    local panel, cleanup = {Visible = true}, 0
    f.app.runtime.picker = {panel = panel, complete = function() panel.Visible = false; cleanup = cleanup + 1 end}
    f.server = function(name)
        if name == "ListWorlds" then return {recent = {"BREAK", "FARM"}} end
        assert(name == "GetInventory" and not panel.Visible, "No inventory request should run underneath the world picker")
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and cleanup == 1 and not panel.Visible and not f.app.lastError)
    assert(f.app.status:find("Finished", 1, true))
end)

test("Recovery selects the most recent matching breaking world from ListWorlds", function()
    local f = entryFixture()
    local lists = 0
    f.server = function(name)
        if name == "ListWorlds" then lists = lists + 1; return {recent = {"BREAK", "FARM"}} end
        assert(name == "GetInventory")
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(lists == 1 and f.entries == 1 and not f.app.lastError)
    assert(f.app.recentWorldDebug:find("Recent position 1: BREAK", 1, true))
end)

test("A different newest recent world does not redirect the saved breaking setup", function()
    local f = entryFixture()
    f.server = function(name)
        if name == "ListWorlds" then return {recent = {"OTHER", "BREAK"}} end
        assert(name == "GetInventory")
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and not f.app.lastError)
    assert(f.app.recentWorldDebug:find("Recent position 2: BREAK", 1, true))
end)

test("An unavailable recent-world list falls back to the saved PNB world", function()
    local f = entryFixture()
    f.server = function(name)
        if name == "ListWorlds" then error("ListWorlds unavailable") end
        assert(name == "GetInventory")
        return {slots = {}, capacity = 54}
    end
    f.hooks.start("pnb")
    assert(f.entries == 1 and not f.app.lastError and f.app.pending == 0)
    assert(f.app.recentWorldDebug:find("using BREAK", 1, true))
end)

test("Starting PNB saves its profile and arms the loader for a server teleport", function()
    local f = entryFixture()
    local queued
    f.env.ClarisGrowbloxLoaderURL = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"
    queue_on_teleport = function(code) queued = code end
    f.spawn = function(fn) f.spawn = nil; task.defer(fn) end
    f.hooks.start("pnb")
    local saved = f.hooks.readPNBResume()
    assert(saved and saved.config.points.pnb.world == "BREAK" and saved.config.blockId == 954)
    assert(queued:find("ClarisGrowbloxAutoResume", 1, true) and queued:find(f.env.ClarisGrowbloxLoaderURL, 1, true))
    f.app:stop()
    task.wait(0.01)
    assert(not f.hooks.readPNBResume())
    queue_on_teleport = nil
end)

test("Farm recovery files reject another account or an expired checkpoint", function()
    local f = fixture()
    f.hooks.savePNBResume()
    local saved = f.hooks.readPNBResume()
    saved.userId = 999
    rejects(function() f.hooks.readPNBResume() end, "another account")
    saved.userId, saved.updatedAt = f.player.UserId, os.time() - 7 * 3600
    rejects(function() f.hooks.readPNBResume() end, "six hours")
end)

test("Farm checkpoints refresh during a long run but never after Stop", function()
    local f = fixture()
    f.app.job = "pnb"
    f.hooks.savePNBResume()
    local first = f.files["ClarisGrowblox/pnb-resume.json"]
    task.wait(121)
    f.hooks.refreshPNBCheckpoint()
    assert(f.files["ClarisGrowblox/pnb-resume.json"] ~= first)
    f.app:stop()
    task.wait(121)
    f.hooks.refreshPNBCheckpoint()
    assert(not f.files["ClarisGrowblox/pnb-resume.json"])
end)

test("Failed world entry stops after three attempts with the farm toggle Off", function()
    local f = entryFixture()
    f.world.enter = function() f.entries = f.entries + 1; return false, "World access denied" end
    f.app.runToggles.pnb = {Value = false, Set = function(self, value) self.Value = value end}
    f.hooks.start("pnb")
    assert(f.entries == 3 and f.app.job == nil and f.app.controls == nil)
    assert(f.app.lastError:find("World access denied", 1, true) and not f.app.runToggles.pnb.Value)
end)

test("World recovery can be disabled in a saved profile", function()
    local f = entryFixture()
    f.app.config.options.autoRejoin = false
    f.hooks.start("pnb")
    assert(f.entries == 0 and f.app.job == nil and f.app.lastError:find("world picker", 1, true))
end)

test("Stopping during rejoin cancels subsequent entry attempts", function()
    local f = entryFixture()
    f.onWait = function() f.onWait = nil; f.app:stop() end
    f.hooks.start("pnb")
    assert(f.entries == 0 and f.app.job == nil and f.app.controls == nil and not f.app.lastError)
    assert(not f.hooks.readPNBResume())
end)

test("Unexpected entry into a different live world does not redirect or farm it", function()
    local f = entryFixture()
    f.world.name, f.avatar.active = "OTHER", true
    f.hooks.start("pnb")
    assert(f.entries == 0 and f.app.job == nil and f.app.lastError:find("world changed", 1, true))
end)

test("Recovery waits for pending pickup settlement before entering the world", function()
    local f = entryFixture()
    f.app.job, f.app.jobToken, f.app.pending = "pnb", 1, 1
    f.onWait = function() f.onWait = nil; f.app.pending = 0 end
    f.hooks.recoverPNB(f.hooks.recoverable("World picker", "BREAK", "worldPicker"), 1)
    assert(f.entries == 1 and f.app.pending == 0 and not f.app.recovering)
end)

test("A ready avatar after respawn resumes without another world entry", function()
    local f = entryFixture()
    f.app.job, f.app.jobToken, f.world.name, f.avatar.dead = "pnb", 1, "BREAK", true
    f.onWait = function() f.onWait = nil; f.avatar.active, f.avatar.dead = true, false end
    f.hooks.recoverPNB(f.hooks.recoverable("Respawning", "BREAK", "avatar"), 1)
    assert(f.entries == 0 and f.app.controls and not f.app.recovering)
end)

test("The anti-AFK handler follows the setting and disconnects on unload", function()
    local f = fixture()
    local inputs, captured, callback, disconnected = 0, 0, nil, false
    Vector2 = {new = function(x, y) return {x = x, y = y} end}
    f.services.VirtualUser = {
        CaptureController = function() captured = captured + 1 end,
        ClickButton2 = function(_, point) assert(point.x == 0 and point.y == 0); inputs = inputs + 1 end,
    }
    f.player.Idled = {Connect = function(_, fn)
        callback = fn
        return {Disconnect = function() disconnected = true end}
    end}
    assert(f.hooks.installAntiAFK())
    callback()
    callback()
    assert(inputs == 1 and captured == 1, "Repeated idle events must not spam input")
    f.app.config.options.antiAFK = false
    task.wait(61)
    callback()
    assert(inputs == 1)
    f.app.config.options.antiAFK = true
    callback()
    assert(inputs == 2)
    f.app:destroy()
    callback()
    assert(disconnected and inputs == 2 and f.app.idleConnection == nil)
end)

test("Unavailable idle input records a diagnostic without stopping the farm", function()
    local f = fixture()
    assert(not f.hooks.installAntiAFK())
    assert(f.app.antiAFKError and f.app.alive and f.app.job == "transfer")
end)

test("Storage auto-pickup is suppressed and all wrappers restore on stop", function()
    local f = fixture()
    local originalDisplay, originalTake = f.world.displayTake, f.world.takeDrop
    local originalDir, originalJump = f.controls.dir, f.controls.jumping
    local hold = f.hooks.takeControls()
    f.world.displayTake(8, 8)
    assert(f.displays == 0)
    assert(f.world.takeDrop(100, 5) == 5 and f.pickups == 1)
    assert(hold.autoTakes == 1)
    task.wait(0.01)
    assert(hold.autoTakes == 0)
    f.app:stop()
    assert(f.world.displayTake == originalDisplay and f.world.takeDrop == originalTake)
    assert(f.controls.dir == originalDir and f.controls.jumping == originalJump)
    rejects(function() f.hooks.checkpoint(1) end, "Stopped")
end)
test("Wrapper cleanup respects another script replacing a control", function()
    local f = fixture()
    f.hooks.takeControls()
    local replacement = function() return 7 end
    f.controls.dir = replacement
    f.hooks.releaseControls()
    assert(f.controls.dir == replacement)
end)
test("A pending server operation prevents a new job from starting", function()
    local f = fixture()
    f.app.job, f.app.pending = nil, 1
    rejects(function() f.hooks.start("pnb") end, "pending requests")
    assert(f.app.job == nil and f.app.controls == nil)
end)
test("Snapshot refresh waits for pickup completion and prevents duplicate additions", function()
    local f = fixture()
    f.inventory:add(954, 70)
    f.inventory:add(18, 1)
    local hold = f.hooks.takeControls()
    hold.autoTakes = 1
    f.onWait = function() hold.autoTakes = 0 end
    local requested = false
    f.server = function(name)
        assert(name == "GetInventory")
        assert(hold.autoTakes == 0 and hold.syncing)
        assert(f.world.takeDrop(999, 20) == 0)
        assert(f.pickups == 0)
        requested = true
        return { slots = {{954, 50}}, capacity = 60 }
    end
    f.hooks.refreshInventory(1)
    assert(requested and not hold.syncing)
    assert(f.inventory:count(954) == 50 and f.inventory:count(18) == 1 and f.inventory.capacity == 60)
end)
test("Missing saved cargo stops delivery instead of silently transferring less", function()
    local f = fixture()
    f.inventory:add(954, 20)
    f.server = function(name)
        assert(name == "GetInventory", "Missing cargo must not be deposited")
        return {slots = {{954, 20}}, capacity = 54}
    end
    rejects(function() f.hooks.runTransfer(1, {phase = "deliver", cargo = 50}) end, "cargo is missing")
    assert(f.app.stats.moved == 0 and f.app.resume == nil)
end)
test("A rejected return door preserves a usable return checkpoint", function()
    local f = fixture()
    f.server = function(name)
        assert(name == "UseDoor")
        return false, "Door locked"
    end
    rejects(function() f.hooks.runTransfer(1, {phase = "return", cargo = 0}) end, "Door locked")
    assert(f.world.name == "BREAK" and f.app.resume.phase == "return" and f.app.resume.cargo == 0)
end)
test("Delivery transfers exact tracked cargo and preserves existing inventory", function()
    local f = fixture()
    f.inventory:add(954, 70)
    local serverCount, deposited = 70, 0
    f.server = function(name, x, y, id, _, _, n)
        if name == "GetInventory" then return {slots = {{954, serverCount}}, capacity = 54} end
        if name == "DisplayItem" then
            assert(x == 12 and y == 8 and id == 954 and n == 50)
            assert(f.app.resume.phase == "depositPending")
            serverCount, deposited = serverCount - n, deposited + n
            return true, {}
        end
        assert(name == "UseDoor")
        return false, "End test after delivery"
    end
    rejects(function() f.hooks.runTransfer(1, {phase = "deliver", cargo = 50}) end, "End test after delivery")
    assert(deposited == 50 and f.inventory:count(954) == 20)
    assert(f.app.stats.trips == 1 and f.app.stats.moved == 50)
    assert(f.app.resume.phase == "return" and f.app.resume.cargo == 0)
end)
test("Mixed farm storage is rejected before a mutating withdrawal", function()
    local f = fixture()
    f.world.name = "FARM"
    f.boxes[20] = {{954, 200}, {955, 20}}
    f.hooks.takeControls()
    f.server = function(name)
        assert(name ~= "DisplayItem", "A mixed box must never be withdrawn")
        return {slots = {}, capacity = 54}
    end
    rejects(function() f.hooks.withdraw(f.app.config.points.farmBox, 954, 1) end, "different item")
end)

test("Optimistic placement without server inventory consumption cannot advance the farm", function()
    local f = fixture()
    f.inventory:add(954, 5)
    local called = false
    f.server = function(name)
        assert(name == "GetInventory")
        return { slots = {{954, 5}}, capacity = 54 }
    end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(layer, x, y, id)
            assert(layer == "fg")
            called = true
            f.world.fg[y][x] = id
        end,
    }
    f.hooks.takeControls()
    rejects(function() f.hooks.placeTile({x = 10, y = 7}, 954, 1) end, "server did not consume")
    assert(called and f.world.fg[7][10] == 954)
    assert(f.inventory:count(954) == 5 and f.app.stats.broken == 0)
    assert(not f.app.controls.pausePickup)
end)

test("Several placements continue without tile echoes when the server consumes each block", function()
    local f = fixture()
    f.inventory:add(954, 5)
    local serverCount, placements = 5, 0
    f.server = function(name)
        assert(name == "GetInventory")
        return { slots = {{954, serverCount}}, capacity = 54 }
    end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(_, x, y, id)
            f.world.fg[y][x] = id
            serverCount, placements = serverCount - 1, placements + 1
        end,
    }
    f.hooks.takeControls()
    for x = 8, 10 do f.hooks.placeTile({x = x, y = 7}, 954, 1) end
    assert(serverCount == 2 and placements == 3 and f.inventory:count(954) == 2)
    assert(not f.app.controls.pausePickup)
end)

test("A correction during the settling period stops the action", function()
    local f = fixture()
    f.world.fg[7][10] = 954
    f.onWait = function() f.world.fg[7][10] = 0 end
    rejects(function() f.hooks.settleTile(10, 7, 954, 0.2, "BREAK", 1) end, "changed while the action settled")
end)

test("Ten single-block PNB cycles use only the tile directly above the player", function()
    local f = fixture()
    f.inventory:add(954, 10)
    f.avatar.x = 10.5
    f.app.config.points.blockBox.standX = 10
    f.boxes[12] = {}
    local serverCount, placements, hits, totalHits = 10, 0, {}, 0
    f.server = function(name)
        assert(name == "GetInventory", "Empty storage should not cause a withdrawal request")
        return {slots = {{954, serverCount}}, capacity = 54}
    end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(layer, x, y, id)
            assert(layer == "fg" and f.world.fg[y][x] == 0)
            assert(x == 10 and y == 7, "PNB must not create distant outer-column drops")
            f.world.fg[y][x] = id
            hits[y * f.world.w + x] = 0
            serverCount, placements = serverCount - 1, placements + 1
        end,
        hit = function(x, y)
            local key = y * f.world.w + x
            hits[key] = (hits[key] or 0) + 1
            totalHits = totalHits + 1
            if hits[key] == 2 then f.world.fg[y][x] = 0 end
        end,
    }
    f.hooks.takeControls()
    f.hooks.runPNB(1)
    assert(placements == 10 and f.app.stats.broken == 10 and serverCount == 0 and totalHits == 20)
    for _, cell in ipairs(f.hooks.Core.grid(f.app.config.points.pnb)) do
        assert(f.world.fg[cell.y][cell.x] == 0 and hits[cell.y * f.world.w + cell.x] == 2)
    end
end)

local function pickupFixture()
    local f = fixture()
    f.avatar.x = 10.5
    f.serverItems, f.serverGems, f.requests = {}, 100, {}
    function f.addDrop(uid, id, n, x, y)
        local drop = {uid = uid, id = id, n = n, x = x or 10.5, y = y or 6.5}
        f.drops[#f.drops + 1] = drop
        return drop
    end
    f.world.takeDrop = function(uid, want)
        assert(f.allowLatePickup or (f.app.controls and f.app.controls.pausePickup),
            "Direct collection must quiesce native pickups")
        assert(f.allowLatePickup or f.allowMovingPickup or (f.controls.dir() == 0 and not f.controls.jumping()),
            "Floating drops must not require walking")
        local drop
        for _, candidate in pairs(f.drops) do if candidate.uid == uid then drop = candidate end end
        assert(drop and drop.taking)
        f.requests[#f.requests + 1] = {uid = uid, want = want, time = os.clock()}
        local got = want
        if f.accept then got = f.accept(drop, want) end
        if type(got) == "number" and got > 0 and got <= want then
            if drop.id == 112 then f.serverGems = f.serverGems + got
            else f.serverItems[drop.id] = (f.serverItems[drop.id] or 0) + got end
            if f.packetTaken then f.world.dropTaken(uid, drop.n - got) end
        end
        return got
    end
    f.server = function(name)
        if name == "GetGems" then return f.serverGems end
        assert(name == "GetInventory")
        local slots = {}
        for id, n in pairs(f.serverItems) do if n > 0 then slots[#slots + 1] = {id, n} end end
        return {slots = slots, capacity = 54}
    end
    function f.collect()
        f.hooks.takeControls()
        return f.hooks.collectDrops(f.app.config.points.pnb, 954, 955, 1)
    end
    return f
end

test("Floating PNB drops are claimed by UID without walking or double credit", function()
    local f = pickupFixture()
    f.addDrop(101, 954, 12, 9.3, 7.1)
    f.addDrop(102, 955, 8, 11.7, 7)
    f.addDrop(103, 112, 25)
    local hudBalance
    f.app.runtime.gemHud = {setGems = function(n) hudBalance = n end}
    f.collect()
    assert(#f.requests == 3 and #f.drops == 0)
    assert(f.inventory:count(954) == 12 and f.inventory:count(955) == 8)
    assert(f.inventory:count(112) == 0 and f.app.stats.gems == 25 and hudBalance == 125)
    assert(f.avatar.x == 10.5 and f.avatar.y == 9 and not f.app.controls.pausePickup)
end)

test("Direct collection excludes boxes, pending, distant, and unrelated drops", function()
    local f = pickupFixture()
    f.addDrop(101, 954, 12).display = {x = 12, y = 8}
    f.addDrop(102, 955, 8).pending = true
    f.addDrop(103, 954, 1, 20, 6.5)
    f.addDrop(104, 954, 1, 10.5, 3)
    f.addDrop(105, 18, 1)
    f.addDrop(106, 954, 1, 10.5, 12)
    f.addDrop(107, 112, 1, 8.5, 7.5) -- Old outer columns are outside the new farming area.
    f.addDrop(108, 112, 1, 12.5, 7.5)
    f.collect()
    assert(#f.requests == 0 and #f.drops == 8)
end)

test("Multiple drop requests start together and share one inventory reconciliation", function()
    local f = pickupFixture()
    f.addDrop(101, 954, 12)
    f.addDrop(102, 955, 8)
    f.addDrop(103, 112, 25)
    local snapshot, reads, balances, peak = f.server, 0, 0, 0
    f.server = function(name)
        if name == "GetInventory" then reads = reads + 1 end
        if name == "GetGems" then balances = balances + 1 end
        return snapshot(name)
    end
    f.app.runtime.gemHud = {setGems = function() end}
    f.spawn = function(fn)
        peak = math.max(peak, f.app.pending)
        task.defer(fn) -- Simulate pending RPC replies rather than immediate responses.
    end
    f.collect()
    assert(peak == 3, "All three pickup requests must be in flight together")
    assert(reads == 2 and balances == 1, "Only pre-batch and post-batch snapshots are needed")
    assert(#f.requests == 3 and f.requests[1].time == f.requests[3].time)
    assert(f.inventory:count(954) == 12 and f.inventory:count(955) == 8 and f.app.pending == 0)
end)

test("Single-block PNB claims returned blocks and other drops before placing again", function()
    local f = pickupFixture()
    f.serverItems[954] = 1
    f.app.config.points.blockBox.standX, f.boxes[12] = 10, {}
    local placements, hits, uid = 0, 0, 100
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(_, x, y, id)
            assert(x == 10 and y == 7 and #f.drops == 0,
                "Each break must be collected before the next placement")
            placements, hits = placements + 1, 0
            assert(placements <= 3)
            f.serverItems[954] = f.serverItems[954] - 1
            f.world.fg[y][x] = id
        end,
        hit = function(x, y)
            hits = hits + 1
            if hits < 2 then return end
            f.world.fg[y][x] = 0
            uid = uid + 3
            f.addDrop(uid, 955, 2, 10.5, 7.5)
            f.addDrop(uid + 1, 112, 3, 10.5, 7.5)
            if placements < 3 then f.addDrop(uid + 2, 954, 1, 10.5, 7.5) end
        end,
    }
    f.hooks.takeControls()
    f.hooks.runPNB(1)
    assert(placements == 3 and f.app.stats.broken == 3 and #f.drops == 0)
    assert(f.inventory:count(954) == 0 and f.inventory:count(955) == 6 and f.app.stats.gems == 9)
end)

test("Punching waits only for the unelapsed placement grace period", function()
    local f = fixture()
    f.avatar.x = 10.5
    local serverCount, placedAt, hitAt = 1, nil, nil
    f.server = function() return {slots = {{954, serverCount}}, capacity = 54} end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(_, x, y, id)
            placedAt, serverCount = os.clock(), 0
            f.world.fg[y][x] = id
        end,
        hit = function(x, y)
            hitAt = os.clock()
            f.world.fg[y][x] = 0
        end,
    }
    f.hooks.takeControls()
    f.hooks.placeTile({x = 10, y = 7}, 954, 1)
    f.hooks.breakTile({x = 10, y = 7}, 954, 1)
    assert(hitAt - placedAt >= 0.32 and hitAt - placedAt < 0.38,
        "The completed placement delay must count toward the initial hit grace period")
end)

test("Concurrent item pickups reserve room across every drop of the same item", function()
    local f = pickupFixture()
    f.serverItems[954] = 190
    f.addDrop(101, 954, 8)
    f.addDrop(102, 954, 8)
    f.addDrop(103, 954, 8)
    f.spawn = function(fn) task.defer(fn) end
    f.collect()
    assert(#f.requests == 2 and f.requests[1].want == 8 and f.requests[2].want == 2)
    assert(f.inventory:count(954) == 200 and #f.drops == 2)
    assert(f.drops[1].n == 6 and f.drops[2].n == 8)
end)

test("Pickup bursts cap the number of in-flight requests", function()
    local f = pickupFixture()
    for uid = 1, 11 do f.addDrop(uid, 112, 1) end
    local peak = 0
    f.spawn = function(fn)
        peak = math.max(peak, f.app.pending)
        task.defer(fn)
    end
    f.collect()
    assert(peak == 8 and #f.requests == 11 and #f.drops == 0 and f.app.stats.gems == 11)
    assert(f.requests[1].time == f.requests[8].time and f.requests[9].time > f.requests[8].time)
end)

test("Partial pickups use remaining counts and recheck backpack room", function()
    local f = pickupFixture()
    f.serverItems[954] = 190
    local drop = f.addDrop(101, 954, 15)
    f.accept = function(_, want) return math.min(want, 4) end
    f.collect()
    assert(#f.requests == 3 and f.requests[1].want == 10 and f.requests[3].want == 2)
    assert(f.inventory:count(954) == 200 and drop.n == 5 and not drop.taking)
end)

test("A packet count update before the pickup response is applied only once", function()
    local f = pickupFixture()
    f.serverItems[954], f.packetTaken = 198, true
    local drop = f.addDrop(101, 954, 5)
    f.collect()
    assert(#f.requests == 1 and f.inventory:count(954) == 200 and drop.n == 3)
end)

test("Seed threshold deposits free room for the remaining loose seeds", function()
    local f = pickupFixture()
    f.serverItems[955] = 195
    f.addDrop(101, 955, 15)
    f.app.config.points.seedBox.standX = 10
    local snapshot, deposited = f.server, 0
    f.server = function(name, x, y, id, _, _, n)
        if name ~= "DisplayItem" then return snapshot(name) end
        assert(x == 8 and y == 8 and id == 955 and n == 200)
        f.serverItems[955], deposited = f.serverItems[955] - n, deposited + n
        return true, {}
    end
    f.collect()
    assert(deposited == 200 and f.inventory:count(955) == 10 and #f.drops == 0)
    assert(f.requests[1].want == 5 and f.requests[2].want == 10)
end)

test("Rejected pickups retry after the native cooldown and retain the drop", function()
    local f = pickupFixture()
    local drop = f.addDrop(101, 954, 5)
    f.accept = function() return 0 end
    rejects(f.collect, "server refused nearby drop pickups")
    assert(#f.requests == 3 and drop.n == 5 and not drop.taking)
    for index = 2, 3 do assert(f.requests[index].time - f.requests[index - 1].time >= 1) end
    assert(not f.app.controls.pausePickup and f.app.pending == 0)
end)

test("A native ask timeout can recover on a later pickup attempt", function()
    local f = pickupFixture()
    f.addDrop(101, 954, 5)
    f.accept = function(_, want) if #f.requests == 1 then return nil end; return want end
    f.collect()
    assert(#f.requests == 2 and f.inventory:count(954) == 5 and #f.drops == 0)
    assert(f.requests[2].time - f.requests[1].time >= 1)
end)

test("Drop readiness and initial native refusal are respected", function()
    local f = pickupFixture()
    local drop = f.addDrop(101, 954, 5)
    drop.readyAt, drop.refused = 2, 1.5
    f.collect()
    assert(#f.requests == 1 and f.requests[1].time >= 2.5)
end)

test("Another drop removed by a previous request is not claimed from a stale list", function()
    local f = pickupFixture()
    f.addDrop(101, 954, 5)
    local other = f.addDrop(102, 955, 5)
    f.accept = function(drop, want)
        if drop.uid == 101 then f.world.dropTaken(other.uid, 0) end
        return want
    end
    f.collect()
    assert(#f.requests == 1 and #f.drops == 0)
end)

test("Stop during a pickup batch holds every UID until its accepted result settles", function()
    local f = pickupFixture()
    local drop = f.addDrop(101, 954, 5)
    local seed = f.addDrop(102, 955, 2)
    local gem = f.addDrop(103, 112, 3)
    local spawns, delayed = 0, {}
    f.spawn = function(fn)
        spawns = spawns + 1
        if spawns > 1 then delayed[#delayed + 1] = fn; return end
        return fn()
    end
    f.onWait = function()
        if #delayed > 0 then f.onWait = nil; f.app:stop() end
    end
    rejects(f.collect, "Stopped")
    assert(#delayed == 3 and drop.taking and seed.taking and gem.taking)
    assert(f.app.pending == 3 and f.app.controls == nil)
    -- The request has already started, so its late response still updates the drop.
    f.allowLatePickup = true
    for _, fn in ipairs(delayed) do fn() end
    assert(not drop.taking and not seed.taking and not gem.taking and f.app.pending == 0 and #f.drops == 0)
    assert(f.serverItems[954] == 5 and f.serverItems[955] == 2 and f.app.stats.gems == 3)
end)

test("Pickup hook failures clear taking and restore native pickup suppression", function()
    local f = pickupFixture()
    local drop = f.addDrop(101, 954, 5)
    f.world.dropTaken = function() error("Drop render failure") end
    rejects(f.collect, "Drop render failure")
    assert(not drop.taking and f.app.pending == 0 and not f.app.controls.pausePickup)
end)

local function installToggles(f)
    for _, mode in ipairs({"pnb", "transfer", "harvest", "plant"}) do
        local control = {Value = false, history = {}}
        function control:Set(value, callback, instant)
            assert(callback == false and instant == false)
            self.Value = value
            self.history[#self.history + 1] = value
        end
        f.app.runToggles[mode] = control
    end
    f.hooks.syncRunToggles()
end

test("Running toggles reflect the active task and turn Off immediately on Stop", function()
    local f = fixture()
    installToggles(f)
    assert(f.app.runToggles.transfer.Value and not f.app.runToggles.pnb.Value)
    f.app.pending = 1
    assert(f.hooks.setRunningEnabled("transfer", false))
    assert(not f.app.runToggles.transfer.Value and not f.app.runToggles.pnb.Value)
    assert(f.app.status:find("pending server request", 1, true))
end)

test("A second task cannot turn its toggle On while the other task runs", function()
    local f = fixture()
    installToggles(f)
    f.app.runToggles.pnb.Value = true -- User interaction.
    local ok = f.hooks.setRunningEnabled("pnb", true)
    assert(not ok and not f.app.runToggles.pnb.Value and f.app.runToggles.transfer.Value)
end)

test("Invalid setup rolls an attempted On toggle back Off", function()
    local f = fixture()
    f.app.job, f.app.jobToken = nil, nil
    f.app.config.points.pnb = nil
    installToggles(f)
    f.app.runToggles.pnb.Value = true
    local ok = f.hooks.setRunningEnabled("pnb", true)
    assert(not ok and f.app.job == nil and not f.app.runToggles.pnb.Value)
end)

test("Worker completion switches an On toggle Off and releases controls", function()
    local f = fixture()
    f.app.job, f.app.jobToken, f.avatar.x = nil, nil, 10.5
    f.boxes[12], f.app.config.points.blockBox.standX = {}, 10
    f.server = function(name) assert(name == "GetInventory"); return {slots = {}, capacity = 54} end
    installToggles(f)
    f.spawn = function(fn) f.spawn = nil; task.defer(fn) end
    assert(f.hooks.setRunningEnabled("pnb", true))
    assert(f.app.runToggles.pnb.Value and f.app.job == "pnb")
    task.wait(0.01)
    assert(f.app.job == nil and f.app.controls == nil and not f.app.runToggles.pnb.Value)
    assert(not f.app.lastError and f.app.status:find("Finished", 1, true))
end)

test("Worker setup failure switches the toggle Off and records its error", function()
    local f = fixture()
    f.app.job, f.app.jobToken, f.app.runtime.controls = nil, nil, nil
    installToggles(f)
    assert(f.hooks.setRunningEnabled("pnb", true))
    assert(f.app.job == nil and f.app.controls == nil and not f.app.runToggles.pnb.Value)
    assert(f.app.lastError and f.app.status:find("Paused", 1, true))
end)

test("A resumed transfer and unload also synchronize running toggles", function()
    local f = fixture()
    f.app.job, f.app.jobToken = nil, nil
    installToggles(f)
    f.spawn = function(fn) f.spawn = nil; task.defer(fn) end
    f.hooks.start("transfer", {phase = "deliver", cargo = 50})
    assert(f.app.runToggles.transfer.Value and not f.app.runToggles.pnb.Value)
    f.app:destroy()
    assert(not f.app.runToggles.transfer.Value and not f.app.alive)
    task.wait(0.01)
    assert(f.app.controls == nil and f.app.job == nil)
end)

test("Stop during placement releases pickup suppression and prevents another placement", function()
    local f = fixture()
    f.inventory:add(954, 5)
    local serverCount, placements = 5, 0
    f.server = function() return {slots = {{954, serverCount}}, capacity = 54} end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(_, x, y, id)
            f.world.fg[y][x] = id
            serverCount, placements = serverCount - 1, placements + 1
        end,
    }
    local originalTake = f.world.takeDrop
    f.hooks.takeControls()
    f.onWait = function() f.onWait = nil; f.app:stop() end
    rejects(function() f.hooks.placeTile({x = 10, y = 7}, 954, 1) end, "Stopped")
    assert(placements == 1 and f.app.controls == nil and f.world.takeDrop == originalTake)
end)

local function moduleMap(f)
    return {
        RnyflzPbj74 = f.app.runtime.items,
        hAYmgnN0A36 = {},
        j1PKXTgzz = { tileChanged = { listen = function() end }, worldTag = function() return 1 end },
    }
end

test("Game runtime shared is used when Delta's shared table is isolated", function()
    local f = fixture()
    local modules = moduleMap(f)
    shared = {}
    getrenv = function() return { shared = { ["session-registry"] = setmetatable({}, {__index = modules}) } } end
    local resolved, source = f.hooks.resolveRegistry({})
    assert(resolved == modules and source == "game runtime shared")
end)

test("GC can recover the module map without access to game shared", function()
    local f = fixture()
    local modules = moduleMap(f)
    shared, getrenv = {}, nil
    local resolved, source = f.hooks.resolveRegistry({{}, modules})
    assert(resolved == modules and source == "GC module map")
    resolved, source = f.hooks.resolveRegistry({setmetatable({}, {__index = modules})})
    assert(resolved == modules and source == "GC module map")
end)

test("Attachment failure records registry availability and world discovery", function()
    local f = fixture()
    shared, getrenv = {}, nil
    getgc = function() return {} end
    f.app.runtime = nil
    rejects(function() f.hooks.connectGame() end, "Could not identify one active Growblox world table")
    assert(f.app.connectionError and not f.app.connectionError:find("Join a Growblox world", 1, true))
    assert(f.app.discoveryReport[1]:find("unavailable; Qz attribute: present", 1, true))
    assert(f.app.discoveryReport[2]:find("World tables: 0", 1, true))
    rejects(function() f.hooks.runtime() end, "Could not identify one active Growblox world table")
end)

local function prepareDiscovery(f, liveInventory)
    local modules = moduleMap(f)
    f.world.displayPut, f.world.useDoor = function() end, function() end
    function f.world.backpackNow()
        local rows = {}
        for _, slot in pairs(f.inventory.slots) do table.insert(rows, {slot.id, slot.n}) end
        return rows
    end
    local objects = {f.world, modules}
    if liveInventory then table.insert(objects, f.inventory) end
    f.discoveryObjects = objects
    getgc = function() return objects end
    return modules
end

local function copyDefinitions(items)
    local copy = {}
    for id, item in pairs(items) do copy[id] = item end
    return copy
end

test("Protected registry proxies can be recovered from their method upvalues", function()
    local f = fixture()
    local modules = moduleMap(f)
    local proxy = setmetatable({
        WaitForChild = function(_, key) return modules[key] end,
        FindFirstChild = function(_, key) return modules[key] end,
    }, {__index = modules, __metatable = "locked"})
    f.env.shared = {["session-registry"] = proxy}
    local resolved, source = f.hooks.resolveRegistry({})
    assert(resolved == modules and source == "executor globals")
end)

test("The item registry entry does not require unrelated packet and fingerprint keys", function()
    local f = fixture()
    local modules = prepareDiscovery(f, true)
    modules.j1PKXTgzz, modules.hAYmgnN0A36 = nil, nil
    require = function() error("Already loaded item tables do not require modules") end
    local r = f.hooks.connectGame()
    assert(r.items == modules.RnyflzPbj74 and r.inventory == f.inventory)
end)

local function mockItemModule()
    typeof = function(value) return type(value) == "table" and value.mockModule and "Instance" or type(value) end
    return {mockModule = true, IsA = function(_, class) return class == "ModuleScript" end}
end

test("Only the known item ModuleScript is required when registry access works", function()
    local f = fixture()
    local items = f.app.runtime.items
    local modules = prepareDiscovery(f, true)
    local reference, calls = mockItemModule(), 0
    modules.RnyflzPbj74 = reference
    require = function(value) assert(value == reference); calls = calls + 1; return items end
    assert(f.hooks.connectGame().items == items and calls == 1)
end)

test("A failed registry require can fall back to a unique loaded GC definition table", function()
    local f = fixture()
    local items = f.app.runtime.items
    local modules = prepareDiscovery(f, true)
    modules.RnyflzPbj74 = mockItemModule()
    table.insert(f.discoveryObjects, items)
    require = function() error("Delta cannot require this reference") end
    assert(f.hooks.connectGame().items == items)
    assert(table.concat(f.app.discoveryReport, "\n"):find("Registry item lookup: item module require failed", 1, true))
end)

test("An invalid registry result does not trigger requires of arbitrary GC modules", function()
    local f = fixture()
    local modules = prepareDiscovery(f, true)
    local reference, calls = mockItemModule(), 0
    modules.RnyflzPbj74 = reference
    table.insert(f.discoveryObjects, mockItemModule())
    require = function(value) assert(value == reference); calls = calls + 1; return {} end
    rejects(function() f.hooks.connectGame() end, "item definitions are inaccessible")
    assert(calls == 1 and table.concat(f.app.discoveryReport, "\n"):find("definition fingerprint mismatch", 1, true))
end)

local function attachWorldHandlers(f, items)
    local world = f.world
    local handlers = {
        setTile = function(_, x, y, id) assert(items[id]); world.fg[y][x] = id end,
        hit = function(x, y) return items[world.fg[y][x]] end,
        canPlace = function(x, y, id) return world.fg[y][x] == 0 and items[id] ~= nil end,
    }
    local body = f.app.runtime.body
    local avatar = f.avatar
    body.H, body.HW = 0.95, 0.3
    body.state = function() assert(world.fg); return avatar end
    f.controls.punchPressed, f.controls.setScale = function() end, function() end
    f.controls.place, f.controls.edit = function() end, function() end
    f.discoveryObjects[#f.discoveryObjects + 1] = body
    f.discoveryObjects[#f.discoveryObjects + 1] = f.controls
    local names = {}
    for name, fn in pairs(handlers) do
        names[fn] = name
        f.discoveryObjects[#f.discoveryObjects + 1] = fn
    end
    getinfo = function(fn) return {name = names[fn]} end
    return handlers
end

test("Live world handler upvalues allow complete attachment with renamed module keys", function()
    local f = fixture()
    local items = f.app.runtime.items
    local modules = prepareDiscovery(f, true)
    modules.RenamedItems, modules.RnyflzPbj74 = items, nil
    local handlers = attachWorldHandlers(f, items)
    require = function() error("Must not require unidentified modules") end
    f.app.runtime = nil
    local r = f.hooks.connectGame()
    assert(r.ready and r.items == items and r.handlers.hit == handlers.hit and r.inventory == f.inventory)
    assert(f.app.connectionError == nil and f.app.discoveryReport[1]:find("Registry: unavailable", 1, true))
    assert(table.concat(f.app.discoveryReport, "\n"):find("Item definitions: live world function upvalues", 1, true))
end)

test("Unnamed world-owned functions can supply definitions without farming hook names", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    table.remove(f.discoveryObjects, 2)
    local world = f.world
    table.insert(f.discoveryObjects, function(id) assert(world.fg); return items[id] end)
    local r = f.hooks.connectGame()
    assert(r.items == items and not r.ready and r.inventory == f.inventory)
end)

test("Missing Qz and registry still allow a unique item table from GC", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    f.services.ReplicatedStorage.GetAttribute = function() return nil end
    f.discoveryObjects[2] = items
    table.insert(f.discoveryObjects, items) -- Same table appearing twice is unambiguous.
    table.insert(f.discoveryObjects, {[1422] = {name = "Display Box", display = true}})
    local r = f.hooks.connectGame()
    assert(r.items == items and f.app.discoveryReport[1]:find("Qz attribute: missing", 1, true))
    assert(table.concat(f.app.discoveryReport, "\n"):find("Item definitions: GC item definitions", 1, true))
end)

test("World-owned definitions take precedence over stale copies in GC", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    attachWorldHandlers(f, items)
    f.discoveryObjects[2] = copyDefinitions(items)
    assert(f.hooks.connectGame().items == items)
end)

test("Distinct world-owned item tables are rejected instead of arbitrarily selected", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    attachWorldHandlers(f, items)
    local other = copyDefinitions(items)
    f.world.otherItems = function() return other end
    f.app.runtime = nil
    rejects(function() f.hooks.connectGame() end, "item definitions are ambiguous")
    assert(f.app.runtime == nil and table.concat(f.app.discoveryReport, "\n"):find("ambiguous live world tables (2)", 1, true))
end)

test("Distinct GC item tables are rejected when ownership cannot be established", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    f.discoveryObjects[2] = items
    table.insert(f.discoveryObjects, copyDefinitions(items))
    rejects(function() f.hooks.connectGame() end, "item definitions are ambiguous in GC")
end)

test("Incomplete definitions and unrelated GC metamethods cannot attach", function()
    local f = fixture()
    prepareDiscovery(f, true)
    f.discoveryObjects[2] = {[954] = {name = "Sugar Cane", hits = 2}}
    table.insert(f.discoveryObjects, setmetatable({}, {__index = function() error("Must not invoke GC metamethods") end}))
    f.app.runtime = nil
    rejects(function() f.hooks.connectGame() end, "item definitions are inaccessible from Delta")
    assert(f.app.connectionError:find("script attachment failure", 1, true))
    local report = table.concat(f.app.discoveryReport, "\n")
    assert(report:find("World tables: 1", 1, true) and report:find("Item definitions: not found", 1, true))
end)

test("Missing motion and punch hooks do not prevent loading the live backpack", function()
    local f = fixture()
    f.inventory:add(954, 61)
    prepareDiscovery(f, true)
    local r = f.hooks.connectGame()
    assert(r.inventory == f.inventory and r.inventory:count(954) == 61)
    assert(r.ready == false and #r.issues > 0)
    f.app.job = nil
    rejects(function() f.hooks.start("pnb") end, "Inventory loaded, but farming hooks are unavailable")
    assert(f.app.job == nil and f.app.controls == nil)
end)

test("Backpack snapshots can populate the selector without private inventory upvalues", function()
    local f = fixture()
    f.inventory:add(954, 61)
    prepareDiscovery(f, false)
    local r = f.hooks.connectGame()
    assert(r.readInventoryView and r.inventory:count(954) == 61 and r.ready == false)
    f.inventory:add(954, 10)
    r.readInventoryView()
    assert(r.inventory:count(954) == 71)
end)

local function reportField(payload, name)
    for _, field in ipairs(payload.embeds[1].fields) do if field.name == name then return field.value end end
end
local function setupWebhook(f)
    f.posts = {}
    f.hooks.setWebhookSetting("url", "https://discord.com/api/webhooks/123/test_token")
    f.server = function(name)
        if name == "GetGems" then return 12345 end
        assert(name == "GetLevel", "Reporting must not issue inventory or storage actions")
        return 12, 500, 1000
    end
    f.env.request = function(options)
        f.posts[#f.posts + 1] = options
        return {StatusCode = 204, Success = true}
    end
end

test("Discord stats include player, session totals, backpack, and matching mixed-box counts", function()
    local f = fixture()
    f.inventory:add(954, 17)
    f.inventory:add(955, 45)
    f.boxes[12] = {{954, 1000}, {955, 10}, {954, 300}}
    f.app.stats.broken, f.app.stats.gems, f.app.stats.trips, f.app.stats.moved = 30, 55, 2, 400
    local payload = f.hooks.webhookPayload(f.app.config, "Sugar Cane", {level = 12, gems = 0})
    assert(reportField(payload, "Player"):find("TestPlayer", 1, true))
    assert(reportField(payload, "World") == "BREAK" and reportField(payload, "Profile") == "Sugar Cane")
    assert(reportField(payload, "Level") == "12" and reportField(payload, "Gems") == "0")
    assert(reportField(payload, "Backpack") == "Blocks: 17\nSeeds: 45")
    assert(reportField(payload, "Block Display Box"):find("1300 in BREAK", 1, true))
    assert(reportField(payload, "Seed Display Box"):find("500 in BREAK", 1, true))
    assert(reportField(payload, "Farm Display Box"):find("Unavailable", 1, true))
    assert(reportField(payload, "This script session"):find("Blocks broken: 30", 1, true))
    assert(#payload.allowed_mentions.parse == 0 and #f.boxes[12] == 3)
    assert(f.app.pending == 0 and f.app.stats.moved == 400)
end)

test("Box reports distinguish empty boxes, missing places, and invalid saved tiles", function()
    local f = fixture()
    f.boxes[12] = {}
    f.app.config.points.farmBox = nil
    f.world.fg[8][8] = 0
    local payload = f.hooks.webhookPayload(f.app.config, "Default")
    assert(reportField(payload, "Block Display Box"):find("0 in BREAK", 1, true))
    assert(reportField(payload, "Seed Display Box"):find("Unavailable", 1, true))
    assert(reportField(payload, "Farm Display Box") == "Not saved")
    f.world.name = ""
    payload = f.hooks.webhookPayload(f.app.config, "Default")
    assert(reportField(payload, "World") == "World picker / unconnected")
    assert(reportField(payload, "Block Display Box"):find("Unavailable", 1, true))
end)

test("Display Box reporting can be disabled without requiring a farming setup", function()
    local f = fixture()
    f.hooks.setWebhookSetting("includeBoxes", false)
    f.app.config.blockId, f.app.config.points = 0, {}
    local payload = f.hooks.webhookPayload(f.app.config, "New Farm")
    assert(reportField(payload, "Block Display Box") == nil and reportField(payload, "Seed Display Box") == nil)
    assert(reportField(payload, "Backpack") == "Blocks: Unavailable\nSeeds: Unavailable")
end)

test("Send now posts JSON using Delta's HTTP function while automatic reports are Off", function()
    local f = fixture()
    setupWebhook(f)
    assert(f.hooks.sendWebhook(true))
    assert(not f.app.config.webhook.enabled and #f.posts == 1)
    local options, state = f.posts[1], f.app.webhookState
    assert(options.Method == "POST" and options.Headers["Content-Type"] == "application/json")
    assert(options.Url == "https://discord.com/api/webhooks/123/test_token?wait=true")
    assert(reportField(f.encoded[options.Body], "Gems") == "12345")
    assert(reportField(f.encoded[options.Body], "Level") == "12")
    assert(state.status == "Report sent." and state.lastSent and state.pending == 0)
    assert(f.app.job == "transfer" and f.app.pending == 0)
end)

test("Automatic reporting converts entered minutes to seconds and stops when switched Off", function()
    local f = fixture()
    setupWebhook(f)
    f.hooks.setWebhookSetting("intervalMinutes", 1.5)
    f.hooks.setWebhookSetting("enabled", true)
    f.hooks.pollWebhook()
    assert(#f.posts == 1)
    task.wait(89)
    f.hooks.pollWebhook()
    assert(#f.posts == 1)
    task.wait(1)
    f.hooks.pollWebhook()
    assert(#f.posts == 2)
    f.hooks.setWebhookSetting("enabled", false)
    task.wait(300)
    f.hooks.pollWebhook()
    assert(#f.posts == 2 and f.app.job == "transfer")
end)

test("Changing minutes while farming reschedules reports and invalid input preserves settings", function()
    local f = fixture()
    setupWebhook(f)
    f.hooks.setWebhookSetting("enabled", true)
    f.hooks.pollWebhook()
    f.hooks.setWebhookSetting("intervalMinutes", 2)
    rejects(function() f.hooks.setWebhookSetting("intervalMinutes", nil) end, "interval")
    assert(f.app.config.webhook.intervalMinutes == 2)
    task.wait(119)
    f.hooks.pollWebhook()
    assert(#f.posts == 1)
    task.wait(1)
    f.hooks.pollWebhook()
    assert(#f.posts == 2 and f.app.job == "transfer")
end)

test("Manual reports respect a cooldown even with automatic reporting disabled", function()
    local f = fixture()
    setupWebhook(f)
    assert(f.hooks.sendWebhook(true))
    local ok, message = f.hooks.sendWebhook(true)
    assert(not ok and message:find("five seconds", 1, true) and #f.posts == 1)
    task.wait(5)
    assert(f.hooks.sendWebhook(true) and #f.posts == 2)
end)

test("Missing executor HTTP support does not issue game requests or interrupt farming", function()
    local f = fixture()
    setupWebhook(f)
    f.env.request = nil
    f.server = function() error("Must check HTTP support before fetching stats") end
    local ok, message = f.hooks.sendWebhook(true)
    assert(not ok and message:find("unavailable", 1, true))
    assert(f.app.job == "transfer" and f.app.pending == 0 and f.app.webhookState.pending == 0)
end)

test("Network exceptions and rejected responses never expose webhook tokens in diagnostics", function()
    local f = fixture()
    setupWebhook(f)
    f.env.request = function() error("connection failed to https://discord.com/api/webhooks/123/test_token") end
    assert(f.hooks.sendWebhook(true))
    assert(f.app.webhookState.status:find("request failed", 1, true))
    assert(not f.app.webhookState.status:find("test_token", 1, true) and #f.app.logs == 0)
    task.wait(5)
    f.env.request = function() return {StatusCode = 404, Body = "test_token"} end
    f.hooks.sendWebhook(true)
    assert(f.app.webhookState.status:find("HTTP 404", 1, true))
    assert(not f.app.webhookState.status:find("test_token", 1, true) and f.app.job == "transfer")
end)

test("Discord rate limits delay both automatic and manual reports", function()
    local f = fixture()
    setupWebhook(f)
    f.hooks.setWebhookSetting("intervalMinutes", 1)
    f.hooks.setWebhookSetting("enabled", true)
    f.env.request = function()
        return {StatusCode = 429, Body = f.services.HttpService:JSONEncode({retry_after = 120})}
    end
    f.hooks.pollWebhook()
    assert(f.app.webhookState.retryAt == 120)
    f.env.request = function(options) f.posts[#f.posts + 1] = options; return {StatusCode = 200} end
    task.wait(119)
    f.hooks.pollWebhook()
    assert(not f.hooks.sendWebhook(true) and #f.posts == 0)
    task.wait(1)
    f.hooks.pollWebhook()
    assert(#f.posts == 1 and f.app.webhookState.status == "Report sent.")
end)

test("Unavailable level or gem stats still allow a report with clearly unavailable values", function()
    local f = fixture()
    setupWebhook(f)
    f.server = function(name)
        if name == "GetGems" then return {} end
        error("GetLevel unsupported")
    end
    f.hooks.sendWebhook(true)
    local payload = f.encoded[f.posts[1].Body]
    assert(reportField(payload, "Gems") == "Unavailable" and reportField(payload, "Level") == "Unavailable")
    assert(reportField(payload, "Block Display Box"):find("1000", 1, true))
end)

local function deferReportRequests(f, firstDeferred)
    -- The Lua 5.1 runner cannot yield through pcall; delay spawned request
    -- completion explicitly instead of using Luau's yielding coroutines.
    f.delayed = {}
    local launches = 0
    f.spawn = function(fn, ...)
        launches = launches + 1
        if launches < firstDeferred then return fn(...) end
        local arguments = table.pack(...)
        f.delayed[#f.delayed + 1] = function() return fn(table.unpack(arguments, 1, arguments.n)) end
    end
end

test("A timed-out Discord request remains reserved until its late response settles", function()
    local f = fixture()
    setupWebhook(f)
    deferReportRequests(f, 4) -- Worker and both stat queries run; HTTP completion is delayed.
    f.hooks.sendWebhook(true)
    local state = f.app.webhookState
    assert(state.status:find("timed out", 1, true) and state.pending == 1 and not state.inFlight)
    assert(f.app.pending == 0 and f.app.job == "transfer" and not f.hooks.sendWebhook(true))
    assert(#f.posts == 0 and #f.delayed == 1)
    f.delayed[1]()
    assert(state.pending == 0 and state.lastSent == nil)
    f.spawn = nil
    assert(f.hooks.sendWebhook(true) and #f.posts == 2 and state.lastSent)
end)

test("Disabling reporting during a stat query cancels its pending post", function()
    local f = fixture()
    setupWebhook(f)
    deferReportRequests(f, 2) -- Both stat-query completions are delayed.
    f.hooks.setWebhookSetting("enabled", true)
    f.onWait = function()
        f.onWait = nil
        f.hooks.setWebhookSetting("enabled", false)
    end
    f.hooks.pollWebhook()
    assert(#f.posts == 0 and f.app.webhookState.pending == 2 and f.app.pending == 0)
    for _, complete in ipairs(f.delayed) do complete() end
    assert(f.app.webhookState.pending == 0 and not f.app.config.webhook.enabled)
    f.hooks.pollWebhook()
    assert(#f.posts == 0)
end)

test("Reloading a different profile reschedules reporting and unload prevents future sends", function()
    local f = fixture()
    setupWebhook(f)
    f.hooks.setWebhookSetting("enabled", true)
    f.hooks.pollWebhook()
    local oldGeneration = f.app.webhookState.generation
    f.app.config = f.hooks.Core.defaults()
    f.hooks.resetWebhookSchedule()
    assert(f.app.webhookState.generation > oldGeneration and not f.app.config.webhook.enabled)
    task.wait(300)
    f.hooks.pollWebhook()
    assert(#f.posts == 1)
    f.app:destroy()
    assert(not f.hooks.sendWebhook(true))
    f.hooks.pollWebhook()
    assert(#f.posts == 1)
end)

test("Discord reporting supports the http_request executor fallback", function()
    local f = fixture()
    setupWebhook(f)
    http_request, f.env.request = f.env.request, nil
    assert(f.hooks.sendWebhook(true) and #f.posts == 1)
end)

local function harvestFixture()
    local f = pickupFixture()
    f.allowMovingPickup = true
    f.app.job, f.world.name = "harvest", "FARM"
    f.app.config.points.farmBox = {world = "FARM", x = 12, y = 8, standX = 10, standY = 8}
    f.boxes[12] = {}
    f.deposits = {}
    local originalServer = f.server
    f.server = function(name, x, y, id, _, _, n)
        if name ~= "DisplayItem" then return originalServer(name) end
        assert(f.world.name == "FARM" and x == 12 and y == 8 and id == 954)
        assert(n > 0 and n <= (f.serverItems[id] or 0))
        f.serverItems[id] = f.serverItems[id] - n
        local total = f.hooks.Core.storageCount(f.boxes[x], id)
        f.boxes[x] = {{id, total + n}}
        f.deposits[#f.deposits + 1] = n
        return true
    end
    function f.harvest()
        f.hooks.takeControls()
        return f.hooks.runHarvest(1)
    end
    return f
end

local function harvestFloor(f)
    f.app.runtime.items[1] = {solid = true}
    f.app.runtime.items[1422].solid = true
    for _, row in pairs(f.world.fg) do for x in pairs(row) do row[x] = 0 end end
    for x = 0, f.world.w - 1 do f.world.fg[9][x] = 1 end
    f.world.fg[8][12], f.avatar.y = 1422, 8.999
    f.app.runtime.body.solidAt = function(x, y)
        if x < 0 or x >= f.world.w or y >= f.world.h then return true end
        local id = f.world.fg[y] and f.world.fg[y][x] or 0
        return id == 1 or id == 1422
    end
    return f.hooks.navigationMap(f.app.runtime)
end

test("Harvest collection stores held blocks and all selected drops while leaving other items", function()
    local f = harvestFixture()
    f.inventory:add(954, 200)
    f.serverItems[954] = 200
    for uid = 1, 12 do f.addDrop(uid, 954, 10, uid + 0.5, 2.5) end
    local pending = f.drops[12]
    pending.pending = true
    local seed, gems, other = f.addDrop(101, 955, 10), f.addDrop(102, 112, 20), f.addDrop(103, 1, 5)
    f.onWait = function() if os.clock() >= 0.2 then pending.pending = false end end
    f.harvest()
    assert(f.hooks.Core.storageCount(f.boxes[12], 954) == 320 and f.inventory:count(954) == 0)
    assert(f.app.stats.harvested == 120 and f.app.stats.stashed == 320)
    assert(#f.drops == 3 and seed.n == 10 and gems.n == 20 and other.n == 5)
    assert(f.app.status:find("Finished collecting harvest", 1, true))
end)

test("A large harvested stack is collected and deposited in capacity-sized trips", function()
    local f = harvestFixture()
    f.packetTaken = true -- Packet updates must not double-subtract a partial pickup.
    f.addDrop(1, 954, 450, 25.5, 2.5)
    f.harvest()
    assert(#f.requests == 3 and f.requests[1].want == 200 and f.requests[2].want == 200 and f.requests[3].want == 50)
    assert(#f.deposits == 3 and f.deposits[1] == 200 and f.deposits[2] == 200 and f.deposits[3] == 50)
    assert(#f.drops == 0 and f.inventory:count(954) == 0 and f.app.stats.stashed == 450)
end)

test("Harvest pickups run eight at a time with room reserved across the batch", function()
    local f = harvestFixture()
    for uid = 1, 12 do f.addDrop(uid, 954, 10, uid + 0.5, 3.5) end
    local peak = 0
    f.hooks.takeControls()
    f.spawn = function(fn)
        peak = math.max(peak, f.app.pending)
        task.defer(fn)
    end
    f.hooks.runHarvest(1)
    assert(peak == 8 and #f.requests == 12 and f.app.pending == 0)
    assert(f.app.stats.harvested == 120 and f.hooks.Core.storageCount(f.boxes[12], 954) == 120)
end)

test("Harvest collection walks to distant drops when the server requires proximity", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    local visited = attachPhysics(f, map)
    f.addDrop(1, 954, 20, 4.5, 8.5)
    local rejected = 0
    f.accept = function(drop, want)
        if math.abs(drop.x - f.avatar.x) > 0.6 then rejected = rejected + 1; return 0 end
        return want
    end
    f.harvest()
    assert(rejected == 1 and visited["4:8"] and #f.drops == 0)
    assert(f.hooks.Core.storageCount(f.boxes[12], 954) == 20 and f.app.stats.stashed == 20)
    assert(math.abs(f.avatar.x - 10.5) < 0.16 and f.controls.dir() == 0)
end)

test("Straight walking segments merge without merging turns, jumps, or falls", function()
    local f = fixture()
    local route = {
        {fromX=2,fromY=8,x=3,y=8,jump=false,duration=0.2},
        {fromX=3,fromY=8,x=4,y=8,jump=false,duration=0.2},
        {fromX=4,fromY=8,x=3,y=8,jump=false,duration=0.2},
        {fromX=3,fromY=8,x=5,y=8,jump=true,duration=0.7},
        {fromX=5,fromY=8,x=6,y=12,jump=false,duration=0.8},
        {fromX=6,fromY=12,x=7,y=12,jump=false,duration=0.2},
    }
    local runs = f.hooks.Navigation.straightRuns(route)
    assert(#runs == 5 and runs[1].x == 4 and #runs[1].edges == 2 and runs[1].duration == 0.4)
    assert(runs[2].x == 3 and runs[3].jump and runs[4].y == 12 and runs[5].fromX == 6)
    assert(#route == 6 and route[1].x == 3)
end)

test("A long straight movement keeps heading without braking and reversing at each tile", function()
    local f = fixture()
    local map = {w=30,h=20,solid=function(_,y) return y>=9 end,platform=function() return false end}
    f.app.runtime.body.solidAt = map.solid
    f.avatar.x, f.avatar.y, f.app.job = 3.5, 8.999, "harvest"
    local visited = attachPhysics(f, map)
    local physics, right = f.onWait, 0
    f.onWait = function(dt)
        assert(f.controls.dir() >= 0, "A straight rightward run must not reverse to recenter intermediate tiles")
        if f.controls.dir() > 0 then right = right + 1 end
        physics(dt)
    end
    f.hooks.moveTo(25,8,"BREAK",1)
    assert(right > 0 and visited["25:8"] and os.clock() < 4.5)
    assert(math.abs(f.avatar.x - 25.5) < 0.16 and f.controls.dir() == 0)
end)

test("Harvest clears successive row drops in one direction before continuing", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    for uid=1,3 do f.addDrop(uid,954,10,5.5-uid,8.5) end
    local accepted = {}
    f.accept = function(drop,want)
        if math.abs(drop.x-f.avatar.x)>0.6 then return 0 end
        accepted[#accepted+1]=drop.uid
        assert(f.controls.dir()==0,"The player must hold position during pickup settlement")
        return want
    end
    f.harvest()
    assert(#accepted==3 and accepted[1]==1 and accepted[2]==2 and accepted[3]==3)
    assert(#f.drops==0 and f.app.stats.stashed==30)
end)

test("Harvest does not pass a partially collected stack while its pickup replies are delayed", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    local stack=f.addDrop(1,954,6,4.5,8.5)
    f.addDrop(2,954,2,2.5,8.5)
    f.accept=function(drop,want)
        if math.abs(drop.x-f.avatar.x)>0.8 then return 0 end
        task.wait(0.2)
        return math.min(want,2)
    end
    local physics=f.onWait
    f.onWait=function(dt)
        physics(dt)
        assert(f.avatar.x>=3.5 or stack.n==0,"The player passed a stack before all pickup replies removed it")
    end
    f.harvest()
    assert(#f.drops==0 and f.app.stats.stashed==8)
end)

test("Harvest waits for a not-yet-ready nearby stack before advancing along the row", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    local stack=f.addDrop(1,954,10,4.5,8.5)
    f.addDrop(2,954,2,2.5,8.5)
    f.accept=function(drop,want) return math.abs(drop.x-f.avatar.x)<=0.8 and want or 0 end
    local physics,delayed=f.onWait,false
    f.onWait=function(dt)
        physics(dt)
        if not delayed and math.abs(f.avatar.x-stack.x)<=0.6 then
            stack.readyAt,stack.pending,delayed=os.clock()+1,true,true
        end
        if delayed and os.clock()>=stack.readyAt then stack.pending=false end
        assert(f.avatar.x>=3.5 or stack.n==0,"The player ran past a stack whose readiness delay had not finished")
    end
    f.harvest()
    assert(delayed and #f.drops==0 and f.app.stats.stashed==12)
end)

test("Harvest clears more than eight nearby UIDs before leaving the pickup position", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    for uid=1,12 do f.addDrop(uid,954,1,4.5,8.5) end
    f.addDrop(13,954,1,2.5,8.5)
    f.accept=function(drop,want)
        if math.abs(drop.x-f.avatar.x)>0.8 then return 0 end
        task.wait(0.3)
        return want
    end
    local physics=f.onWait
    f.onWait=function(dt)
        physics(dt)
        if f.avatar.x<3.5 then
            for _,drop in ipairs(f.drops) do
                assert(drop.x~=4.5,"The player left UIDs behind after filling its eight-request batch")
            end
        end
    end
    f.harvest()
    assert(#f.drops==0 and f.app.stats.stashed==13)
    assert(not table.concat(f.app.logs,"\n"):find("Trying another route",1,true),
        "Waiting for pickup batches must not mark the walking route as failed")
end)

test("Stopping while a nearby stack is pending keeps it in the world without moving past it", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    local stack=f.addDrop(1,954,10,4.5,8.5)
    f.accept=function() return 0 end
    local physics,waiting=f.onWait,false
    f.onWait=function(dt)
        physics(dt)
        if math.abs(f.avatar.x-stack.x)<=0.6 then
            stack.pending,waiting=true,true
            if f.controls.dir()==0 then f.app:stop() end
        end
    end
    rejects(f.harvest,"Stopped")
    assert(waiting and stack.n==10 and f.avatar.x>=3.5 and f.app.stats.stashed==0 and f.app.pending==0)
end)

test("Harvest respawns after pickups settle and deposits the preserved backpack", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    f.addDrop(1,954,20,4.5,8.5)
    f.accept = function(drop,want) return math.abs(drop.x-f.avatar.x)<=0.6 and want or 0 end
    f.respawns=0
    local physics, readyAt = f.onWait
    f.world.respawn=function()
        assert(f.app.pending==1 and f.app.stats.harvested==20 and f.serverItems[954]==20)
        for _,drop in pairs(f.drops) do assert(not drop.taking) end
        f.respawns=f.respawns+1
        f.avatar.dead,readyAt=true,os.clock()+0.2
    end
    f.onWait=function(dt)
        if readyAt and os.clock()>=readyAt then
            f.avatar.x,f.avatar.y,f.avatar.vx,f.avatar.vy,f.avatar.dead=10.5,8.999,0,0,false
            readyAt=nil
        end
        physics(dt)
    end
    f.harvest()
    assert(f.respawns==1 and #f.deposits==1 and f.deposits[1]==20 and f.inventory:count(954)==0)
    assert(not f.avatar.dead and f.app.pending==0)
end)

test("Disabling harvest respawn preserves the walking return to storage", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    f.app.config.options.harvestRespawn=false
    f.world.respawn=function() error("Respawn is disabled") end
    f.addDrop(1,954,20,4.5,8.5)
    f.accept=function(drop,want) return math.abs(drop.x-f.avatar.x)<=0.6 and want or 0 end
    f.harvest()
    assert(f.app.stats.stashed==20 and math.abs(f.avatar.x-10.5)<0.16)
end)

test("Moving harvest batches respect backpack capacity and resume after a respawn deposit", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    f.addDrop(1,954,190,6.5,8.5)
    f.addDrop(2,954,30,4.5,8.5)
    f.accept=function(drop,want)
        assert((f.serverItems[954] or 0)+want<=200)
        return math.abs(drop.x-f.avatar.x)<=0.6 and want or 0
    end
    f.world.respawn=function()
        assert(f.app.pending==1)
        f.avatar.x,f.avatar.y,f.avatar.vx,f.avatar.vy=10.5,8.999,0,0
    end
    f.harvest()
    assert(#f.deposits==2 and f.deposits[1]==200 and f.deposits[2]==20)
    assert(#f.drops==0 and f.serverItems[954]==0 and f.app.stats.stashed==220 and f.app.pending==0)
end)

test("Respawn storage return waits for an asynchronous moving pickup batch", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    f.addDrop(1,954,20,4.5,8.5)
    local acceptedAt,returnedAt,respawned
    f.accept=function(drop,want)
        if math.abs(drop.x-f.avatar.x)>0.6 then return 0 end
        acceptedAt=os.clock()
        task.wait(0.1)
        returnedAt=os.clock()
        return want
    end
    f.spawn=function(fn) task.defer(fn) end
    f.world.respawn=function()
        assert(f.app.pending==1 and returnedAt and os.clock()>=returnedAt)
        assert(f.inventory:count(954)==20 and f.serverItems[954]==20)
        respawned=true
        f.avatar.x,f.avatar.y,f.avatar.vx,f.avatar.vy=10.5,8.999,0,0
    end
    f.harvest()
    assert(respawned and returnedAt>acceptedAt and f.app.stats.stashed==20 and f.app.pending==0)
end)

test("Stopping during a storage respawn retains harvested blocks without depositing", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    f.addDrop(1,954,20,4.5,8.5)
    f.accept=function(drop,want) return math.abs(drop.x-f.avatar.x)<=0.6 and want or 0 end
    f.world.respawn=function() f.avatar.dead=true end
    local physics=f.onWait
    f.onWait=function(dt)
        if f.avatar.dead then f.app:stop() else physics(dt) end
    end
    rejects(f.harvest,"Stopped")
    assert(f.serverItems[954]==20 and f.inventory:count(954)==20 and #f.deposits==0 and f.app.pending==0)
end)

test("Harvest collection uses distant edge platforms and returns to storage from a lower row", function()
    local f = harvestFixture()
    f.world.w, f.world.h, f.world.fg = 82, 15, {}
    f.app.runtime.items[102] = {platform = true}
    for y = 0, 14 do
        f.world.fg[y] = {}
        for x = 0, 81 do f.world.fg[y][x] = (y == 12 or y == 9 and x <= 77) and 2 or 0 end
    end
    f.world.fg[10][78], f.world.fg[9][79], f.world.fg[8][12] = 102, 102, 1422
    f.app.runtime.body.solidAt = function(x, y)
        if x < 0 or x >= 82 or y >= 15 then return true end
        return f.world.fg[y] and f.world.fg[y][x] == 2 or false
    end
    f.avatar.x, f.avatar.y = 10.5, 8.999
    local visited = attachPhysics(f, f.hooks.navigationMap(f.app.runtime))
    f.addDrop(1799, 954, 20, 4.5, 11.5)
    f.accept = function(drop, want)
        if math.abs(drop.x - f.avatar.x) > 0.6 or math.abs(drop.y - (f.avatar.y - 0.5)) > 0.6 then return 0 end
        return want
    end
    f.harvest()
    assert(visited["4:11"] and #f.drops == 0 and f.app.stats.stashed == 20)
    assert(f.hooks.Core.storageCount(f.boxes[12], 954) == 20)
    assert(math.abs(f.avatar.x - 10.5) < 0.16 and math.abs(f.avatar.y - 9) < 0.22)
    assert(not f.controls.jumping() and f.controls.dir() == 0)
end)

test("Dirt farm navigation descends through an open column beyond eight tiles", function()
    local f = fixture()
    local map = {w = 30, h = 16,
        solid = function(x, y)
            return y == 15 or y >= 3 and y <= 13 and y % 2 == 1
                and x >= 2 and x <= 27 and x ~= 10 and x ~= 11 and x ~= 12 and x ~= 20 and x ~= 21 and x ~= 22
        end,
        platform = function(x, y)
            return y >= 3 and y <= 13 and y % 2 == 1
                and (x == 1 or x == 28 or x == 10 or x == 12 or x == 20 or x == 22)
        end}
    local route, message = f.hooks.Navigation.plan(map, {x = 27, y = 2}, {x = 2, y = 12},
        {fullWorld = true, maxNodes = 4000})
    assert(route, message)
    local descended = false
    for _, step in ipairs(route) do if not step.jump and step.y - step.fromY > 8 then descended = true end end
    assert(descended, "The route must descend a shaft rather than require jumping through dirt")
end)

test("Extended pickup candidates remain available before server reach is known", function()
    local f = fixture()
    local map = {w = 8, h = 16, solid = function(_, y) return y == 11 end,
        platform = function() return false end}
    local goal, message = f.hooks.Navigation.pickupGoal(map, {x = 4.5, y = 10.999}, {x = 4.5, y = 8.5})
    assert(goal, message)
    assert(goal.x == 4 and goal.y == 10)
end)

test("Harvest walks onto an upper row instead of retrying its drops from the row below", function()
    local f = harvestFixture()
    harvestFloor(f)
    f.app.runtime.items[102] = {platform = true}
    for x = 4, 24 do f.world.fg[7][x] = 1 end
    f.world.fg[8][3], f.world.fg[7][2] = 102, 102
    local visited = attachPhysics(f, f.hooks.navigationMap(f.app.runtime))
    f.addDrop(2089, 954, 20, 10.5, 6.5)
    local refused = 0
    f.accept = function(drop, want)
        local overlap = math.abs(drop.x - f.avatar.x) < 0.6
            and drop.y + 0.3 > f.avatar.y - 0.95 and drop.y - 0.3 < f.avatar.y
        if not overlap then refused = refused + 1; return 0 end
        return want
    end
    f.harvest()
    assert(refused == 1, "The initial refusal must trigger movement rather than another lower-row pickup")
    assert(visited["10:6"] and #f.drops == 0 and f.app.stats.stashed == 20)
end)

test("A route pickup refusal lets harvest recenter before retrying the stack", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f, map)
    f.addDrop(1, 954, 20, 4.5, 8.5)
    f.accept = function(drop, want)
        return math.abs(drop.x - f.avatar.x) < 0.16 and want or 0
    end
    f.harvest()
    assert(#f.drops == 0 and f.app.stats.stashed == 20)
    assert(#f.requests <= 3, "Refused pickups must not consume three attempts at the same off-center position")
end)

test("Extended pickup candidates are excluded when native overlap is required", function()
    local f = fixture()
    local map = {w = 8, h = 16, solid = function(_, y) return y == 11 end,
        platform = function() return false end}
    local goal = f.hooks.Navigation.pickupGoal(map, {x = 4.5, y = 10.999}, {x = 4.5, y = 8.5},
        {nativeOnly = true})
    assert(not goal, "A drop two rows above the avatar does not overlap its body")
end)

test("Harvest pickup route search yields and honors cancellation during a distant detour", function()
    local f = fixture()
    local map = {w = 82, h = 15, solid = function(x, y) return y == 12 or y == 9 and x <= 77 end,
        platform = function(x, y) return x == 78 and y == 10 or x == 79 and y == 9 end}
    local yields = 0
    rejects(function()
        f.hooks.Navigation.pickupGoal(map, {x = 10.5, y = 8.999}, {x = 4.5, y = 11.5}, {
            step = function() yields = yields + 1; error("Stopped during pickup route search") end,
        })
    end, "Stopped during pickup route search")
    assert(yields == 1)
end)

test("The movement follower lands after a tall fall through a world-edge column", function()
    local f = fixture()
    f.world.w, f.world.h = 8, 64
    local map = {w = 8, h = 64,
        solid = function(x, y) return x < 0 or x >= 8 or y >= 63 or y == 3 and x <= 5 end,
        platform = function() return false end}
    f.app.runtime.body.solidAt = map.solid
    f.avatar.x, f.avatar.y, f.app.job = 5.5, 2.999, "harvest"
    local visited = attachPhysics(f, map)
    f.hooks.moveTo(6, 62, "BREAK", 1)
    assert(visited["6:62"] and f.avatar.grounded and math.abs(f.avatar.y - 63) < 0.22)
    assert(f.controls.dir() == 0 and not f.controls.jumping())
end)

test("An unreachable harvest drop produces a location diagnostic instead of completing", function()
    local f = harvestFixture()
    harvestFloor(f)
    local drop = f.addDrop(9, 954, 20, 4.5, 1.5)
    f.accept = function() return 0 end
    rejects(f.harvest, "No reachable floor or platform")
    assert(drop.n == 20 and f.app.stats.stashed == 0 and #f.deposits == 0)
end)

test("Harvest collection respects drop readiness and the native refusal cooldown", function()
    local f = harvestFixture()
    local drop = f.addDrop(1, 954, 20)
    drop.readyAt, drop.refused = 0.4, 0
    f.onWait = function() drop.refused = os.clock() end -- Suppressed native attempts must not postpone our pickup.
    f.harvest()
    assert(#f.requests == 1 and f.requests[1].time >= 1 and f.app.stats.stashed == 20)
end)

test("A harvested drop refused at the standing position stops after three spaced attempts", function()
    local f = harvestFixture()
    harvestFloor(f)
    local drop = f.addDrop(5, 954, 20, 10.5, 8.5)
    f.accept = function() return 0 end
    rejects(f.harvest, "refused harvested drop uid 5")
    assert(#f.requests == 3 and f.requests[2].time - f.requests[1].time >= 1)
    assert(f.requests[3].time - f.requests[2].time >= 1 and drop.n == 20 and not drop.taking)
    assert(f.app.pending == 0 and not f.app.controls.pausePickup and f.app.stats.stashed == 0)
end)

test("Rejected farm deposits retain backpack blocks and keep Moving Drops Off", function()
    local f = harvestFixture()
    f.inventory:add(954, 200)
    f.serverItems[954] = 200
    f.app.job = nil
    installToggles(f)
    local originalServer = f.server
    f.server = function(name, ...)
        if name == "DisplayItem" then return false, "Box access denied" end
        return originalServer(name, ...)
    end
    f.hooks.start("harvest")
    assert(f.inventory:count(954) == 200 and f.app.stats.stashed == 0 and f.app.job == nil)
    assert(f.app.lastError:find("Box access denied", 1, true) and not f.app.runToggles.harvest.Value)
    assert(not f.app.runToggles.transfer.Value)
end)

test("Stopping a harvest pickup keeps pending UIDs owned until late settlement", function()
    local f = harvestFixture()
    local first, second = f.addDrop(1, 954, 10), f.addDrop(2, 954, 10)
    local launches, delayed = 0, {}
    f.spawn = function(fn)
        launches = launches + 1
        if launches > 1 then delayed[#delayed + 1] = fn; return end
        return fn()
    end
    f.onWait = function() if #delayed > 0 then f.onWait = nil; f.app:stop() end end
    rejects(f.harvest, "Stopped")
    assert(first.taking and second.taking and f.app.pending == 2 and #f.deposits == 0)
    f.allowLatePickup = true
    for _, complete in ipairs(delayed) do complete() end
    assert(not first.taking and not second.taking and #f.drops == 0 and f.app.pending == 0)
    assert(f.serverItems[954] == 20 and f.app.stats.harvested == 20 and f.app.stats.stashed == 0)
end)

local function harvestTransferFixture()
    local f = harvestFixture()
    f.app.job, f.app.config.options.moveAfterHarvest = nil, true
    f.app.config.points.farmDoor = {world = "FARM", x = 13, y = 8, standX = 10, standY = 8}
    f.app.config.points.blockBox.standX, f.app.config.points.breakDoor.standX = 10, 10
    f.worldBoxes = {FARM = {}, BREAK = {}}
    f.doors = 0
    f.world.displays.get = function(x) return f.worldBoxes[f.world.name][x] or {} end
    f.world.enter = function(name)
        assert(name == "FARM" or name == "BREAK")
        f.world.name, f.avatar.active = name, true
        f.avatar.x, f.avatar.y = 10.5, 9
        return true
    end
    f.server = function(name, x, y, id, _, _, n)
        if name == "GetInventory" then
            return {slots = (f.serverItems[954] or 0) > 0 and {{954, f.serverItems[954]}} or {}, capacity = 54}
        end
        if name == "UseDoor" then
            assert(f.app.stats.stashed > 0 and #f.drops == 0, "Transfer must wait for all harvest drops to be stored")
            f.doors = f.doors + 1
            return true, {enter = f.world.name == "FARM" and "BREAK" or "FARM"}
        end
        assert(name == "DisplayItem" and x == 12 and y == 8)
        local boxes = f.worldBoxes[f.world.name]
        local total = f.hooks.Core.storageCount(boxes[x], 954)
        if id == nil then
            boxes[x] = {}
            f.serverItems[954] = (f.serverItems[954] or 0) + total
            return true, {taken = {{954, total}}}
        end
        assert(id == 954 and n <= (f.serverItems[954] or 0))
        f.serverItems[954] = f.serverItems[954] - n
        boxes[x] = {{954, total + n}}
        return true
    end
    installToggles(f)
    return f
end

test("Harvest completion switches to Moving Drops and transports the stored harvest", function()
    local f = harvestTransferFixture()
    f.addDrop(1, 954, 23)
    f.hooks.start("harvest")
    assert(not f.app.lastError and f.app.job == nil and f.doors == 2)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12], 954) == 23)
    assert(f.app.stats.harvested == 23 and f.app.stats.stashed == 23 and f.app.stats.moved == 23)
    assert(not f.app.runToggles.harvest.Value and not f.app.runToggles.transfer.Value)
    assert(f.app.runToggles.transfer.history[1] == true and not f.hooks.readPNBResume())
    local record = f.files["ClarisGrowblox/resume.json"]
    assert(f.app.resume == nil and (not record or not f.services.HttpService:JSONDecode(record).active))
end)

test("Automatic transfer never starts after an uncollected harvest drop fails", function()
    local f = harvestTransferFixture()
    harvestFloor(f)
    f.addDrop(1, 954, 23, 4.5, 1.5)
    f.accept = function() return 0 end
    f.hooks.start("harvest")
    assert(f.app.lastError and f.doors == 0 and f.app.job == nil and f.app.stats.stashed == 0)
    assert(not f.app.runToggles.harvest.Value and not f.app.runToggles.transfer.Value)
end)

test("Stopping during the empty-harvest settling check cancels automatic transfer", function()
    local f = harvestTransferFixture()
    f.onWait = function() f.onWait = nil; f.app:stop() end
    f.hooks.start("harvest")
    assert(f.doors == 0 and not f.app.lastError and f.app.job == nil)
    assert(not f.app.runToggles.harvest.Value and not f.app.runToggles.transfer.Value)
end)

test("Unsaved current settings survive a fresh script instance through the session file", function()
    local f = fixture()
    f.app.profile, f.app.config.options.placeDelay = "My Farm", 0.6
    f.app.config.planting = {seedId = 955, storageWorld = "STOCK", worlds = {"FARM1", "FARM2"}}
    f.hooks.saveSession()
    local next = f.reload()
    assert(next.App.profile == "My Farm" and next.App.config.blockId == 954)
    assert(next.App.config.options.placeDelay == 0.6 and next.App.config.points.farmDoor.world == "FARM")
    assert(next.App.config.points.blockBox.x == 12 and next.App.config.planting.worlds[2] == "FARM2")
    next.App.config.planting.worlds[1] = "OTHER"
    assert(f.app.config.planting.worlds[1] == "FARM1")
end)

test("Reloading an existing idle app preserves its newest configuration", function()
    local f = fixture()
    f.hooks.saveSession()
    f.app.job, f.app.config.options.collectDelay = nil, 0.8
    f.app.profile = "Newest Setup"
    local next = f.reload(true)
    assert(next.App.profile == "Newest Setup" and next.App.config.options.collectDelay == 0.8 and not f.app.alive)
end)

test("A session from another account or a damaged profile cannot replace defaults", function()
    local f = fixture()
    f.hooks.saveSession()
    f.player.UserId = 888
    local next = f.reload()
    assert(next.App.config.blockId == 0 and next.App.sessionRestoreError:find("another account", 1, true))
    f.player.UserId = 1234
    local record = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/session.json"])
    record.config.options.placeDelay = -1
    next = f.reload()
    assert(next.App.config.blockId == 0 and next.App.sessionRestoreError:find("placeDelay", 1, true))
end)

test("Session write errors are visible and prevent an unprotected transfer entry", function()
    local f = fixture()
    writefile = function() error("disk full") end
    f.hooks.pollSession()
    assert(f.app.sessionSaveError:find("disk full", 1, true))
    local used = false
    f.world.call = function() used = true end
    f.avatar.x, f.avatar.y = 13.5, 9
    rejects(function() f.hooks.enterDoor(f.app.config.points.breakDoor, f.app.config.points.farmBox, "return", 0, 1) end, "disk full")
    assert(not used)
end)

local function plantingFixture(seedCount, stockCount, worlds)
    local f = fixture()
    f.app.job, f.app.jobToken = nil, nil
    f.app.config.planting = {seedId = 955, storageWorld = "STOCK", worlds = worlds or {"FARM1"}}
    f.app.config.points.plantBox = {world = "STOCK", x = 6, y = 5, standX = 5, standY = 5}
    f.world.w, f.world.h = 7, 8
    f.grids, f.entries, f.plantCalls, f.withdrawals = {}, {}, {}, 0
    for _, name in ipairs({"STOCK", "FARM1", "FARM2"}) do
        local grid = {}
        for y = 0, 7 do
            grid[y] = {}
            for x = 0, 6 do grid[y][x] = y == 6 and 2 or 0 end
        end
        f.grids[name] = grid
    end
    f.grids.STOCK[5][6] = 1422
    f.world.name, f.world.fg = "FARM1", f.grids.FARM1
    f.serverSeeds, f.stock = seedCount or 0, stockCount or 0
    if f.serverSeeds > 0 then f.inventory:add(955, f.serverSeeds) end
    f.world.displays.get = function(x, y)
        if f.world.name == "STOCK" and x == 6 and y == 5 then return {{955, f.stock}} end
    end
    local function enter(name)
        f.entries[#f.entries + 1] = name
        f.world.name, f.world.fg = name, assert(f.grids[name])
        f.avatar.active, f.avatar.dead, f.avatar.grounded = true, false, true
        f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = 0.5, 6, 0, 0
        if f.onEnter then return f.onEnter(name) end
        return true
    end
    f.world.enter = enter
    f.nativeEnter = enter
    f.avatar.x, f.avatar.y = 0.5, 6
    f.app.runtime.body.solidAt = function(x, y)
        if x < 0 or x >= f.world.w or y >= f.world.h then return true end
        local item = f.app.runtime.items[f.world.fg[y] and f.world.fg[y][x] or 0]
        return item and item.solid == true or false
    end
    f.server = function(name, x, y, id)
        if name == "GetInventory" then return {slots = f.serverSeeds > 0 and {{955, f.serverSeeds}} or {}, capacity = 54} end
        assert(name == "DisplayItem" and f.world.name == "STOCK" and x == 6 and y == 5 and id == nil)
        f.withdrawals = f.withdrawals + 1
        if f.denyStorage then return false, "Seed box access denied" end
        local n = math.min(200 - f.serverSeeds, f.stock)
        f.serverSeeds, f.stock = f.serverSeeds + n, f.stock - n
        return true, {taken = {{955, n}}}
    end
    f.app.runtime.handlers = {
        canPlace = function(item, x, y)
            local a = f.avatar
            return item.kind == "seed" and f.hooks.Core.plantingTile(f.world, f.app.runtime.items, x, y)
                and math.abs(x + 0.5 - a.x) < 2 and math.abs(y + 0.5 - (a.y - 0.475)) < 2
                and not (f.deniedX == x)
        end,
        plantSeed = function(id, x, y)
            assert(f.app.runtime.handlers.canPlace(f.app.runtime.items[id], x, y))
            assert(id == 955 and f.world.fg[y][x] == 0)
            f.plantCalls[#f.plantCalls + 1] = {world = f.world.name, x = x, y = y}
            f.world.fg[y][x] = id
            f.inventory:remove(id, 1) -- The real native helper owns this optimistic removal.
            if f.rejectPlant then f.world.fg[y][x] = 0 else f.serverSeeds = f.serverSeeds - 1 end
            if f.onPlant then f.onPlant(id, x, y) end
        end,
    }
    attachPhysics(f, f.hooks.navigationMap(f.app.runtime))
    installToggles(f)
    return f
end

test("Planting walks to empty supported cells while skipping doors, vents, trees, and floating corners", function()
    local f = plantingFixture(20, 100)
    f.app.runtime.items[100] = {name = "Air Vent", solid = false}
    f.grids.FARM1[5][1], f.grids.FARM1[5][2], f.grids.FARM1[5][3] = 12, 100, 955
    f.grids.FARM1[6][6] = 0
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.app.stats.planted == 3 and #f.plantCalls == 3 and f.withdrawals == 0)
    for _, x in ipairs({0, 4, 5}) do assert(f.grids.FARM1[5][x] == 955) end
    assert(f.grids.FARM1[5][1] == 12 and f.grids.FARM1[5][2] == 100 and f.grids.FARM1[5][6] == 0)
    assert(f.app.job == nil and not f.app.runToggles.plant.Value and f.hooks.readPlantResume() == nil)
end)

test("Planting refills at zero seeds and advances through multiple farm worlds", function()
    local f = plantingFixture(2, 400, {"FARM1", "FARM2"})
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.app.stats.planted == 14 and #f.plantCalls == 14 and f.withdrawals == 1)
    assert(f.entries[1] == "STOCK" and f.entries[2] == "FARM1" and f.entries[3] == "FARM2")
    assert(f.stock == 200 and f.serverSeeds == 188 and f.app.profile == "Default" and f.app.config.blockId == 954)
    for _, name in ipairs({"FARM1", "FARM2"}) do for x = 0, 6 do assert(f.grids[name][5][x] == 955) end end
end)

test("An empty seed box ends planting without pretending remaining farms are full", function()
    local f = plantingFixture(1, 0, {"FARM1", "FARM2"})
    f.hooks.start("plant")
    assert(not f.app.lastError and f.app.stats.planted == 1 and f.withdrawals == 0)
    assert(f.app.status:find("seed storage box is empty", 1, true) and f.grids.FARM2[5][0] == 0)
    assert(f.hooks.readPlantResume() == nil and not f.app.runToggles.plant.Value)
end)

test("Already filled farms advance without fetching unnecessary seeds", function()
    local f = plantingFixture(0, 100, {"FARM1", "FARM2"})
    for x = 0, 6 do f.grids.FARM1[5][x], f.grids.FARM2[5][x] = 955, 955 end
    f.hooks.start("plant")
    assert(not f.app.lastError and f.withdrawals == 0 and #f.plantCalls == 0 and f.world.name == "FARM2")
end)

test("Denied planting cells are skipped without consuming seeds or modifying obstacles", function()
    local f = plantingFixture(10, 100)
    f.deniedX = 2
    f.hooks.start("plant")
    assert(not f.app.lastError and f.app.stats.planted == 6 and f.grids.FARM1[5][2] == 0)
    assert(f.serverSeeds == 4 and table.concat(f.app.logs, "\n"):find("1 tiles skipped", 1, true))
end)

test("Server seed rejection stops at one attempt and can be safely reconciled before retry", function()
    local f = plantingFixture(10, 100)
    f.rejectPlant = true
    f.hooks.start("plant")
    assert(f.app.lastError:find("did not confirm a planted seed", 1, true) and #f.plantCalls == 1)
    local saved = f.hooks.readPlantResume()
    assert(saved.state.pending.x == 0 and f.serverSeeds == 10 and f.app.stats.planted == 0)
    f.rejectPlant = false
    f.hooks.start("plant", saved)
    assert(not f.app.lastError and f.app.stats.planted == 7 and f.serverSeeds == 3)
end)

test("Stopping immediately after native planting prevents further planting and restores controls", function()
    local f = plantingFixture(10, 100)
    local originalTake = f.world.takeDrop
    f.onPlant = function() f.app:stop() end
    f.hooks.start("plant")
    assert(#f.plantCalls == 1 and not f.app.lastError and f.app.job == nil and f.app.controls == nil)
    assert(f.world.takeDrop == originalTake and f.hooks.readPlantResume() == nil and not f.app.runToggles.plant.Value)
end)

test("A picker interruption after a consumed seed rejoins and reconciles before continuing", function()
    local f = plantingFixture(10, 100)
    f.onPlant = function()
        f.onPlant = nil
        f.world.name, f.avatar.active = "", false
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.app.stats.planted == 7 and #f.plantCalls == 7 and #f.entries == 1 and f.entries[1] == "FARM1")
    assert(f.serverSeeds == 3 and not f.app.runToggles.plant.Value)
end)

test("Denied seed storage retains an ambiguous withdrawal checkpoint and refuses replay", function()
    local f = plantingFixture(0, 100)
    f.denyStorage = true
    f.hooks.start("plant")
    assert(f.app.lastError:find("Seed box access denied", 1, true) and f.withdrawals == 1)
    local saved = f.hooks.readPlantResume()
    assert(saved.state.phase == "pickupPending")
    f.hooks.start("plant", saved)
    assert(f.withdrawals == 1 and f.app.lastError:find("storage withdrawal was interrupted", 1, true))
end)

test("A server teleport stores farm index and restores the full configuration in a fresh instance", function()
    local f = plantingFixture(0, 100, {"FARM1", "FARM2"})
    f.app.profile = "Sugar Cane Farms"
    f.onEnter = function() return true, nil, true end
    local queued
    queue_on_teleport = function(code) queued = code end
    f.env.ClarisGrowbloxLoaderURL = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"
    f.hooks.start("plant")
    queue_on_teleport = nil
    assert(f.app.teleporting and f.withdrawals == 0 and queued:find("ClarisGrowbloxAutoResume", 1, true))
    local next = f.reload()
    local saved = next.readPlantResume()
    assert(next.App.profile == "Sugar Cane Farms" and next.App.config.points.farmDoor.world == "FARM")
    assert(next.App.config.planting.seedId == 955 and next.App.config.planting.worlds[2] == "FARM2")
    assert(saved.state.phase == "stock" and saved.state.worldIndex == 1 and saved.config.points.plantBox.x == 6)
end)

test("Planting checkpoints validate account, expiry, index, and pending placement evidence", function()
    local f = plantingFixture(10, 100)
    f.hooks.savePlantResume({worldIndex = 1, phase = "farm", skipped = {}, pending = {world = "FARM1", x = 0, y = 5, before = 10}})
    local saved = f.hooks.readPlantResume()
    saved.state.pending.world = "OTHER"
    f.hooks.savePlantResume(saved.state)
    rejects(function() f.hooks.readPlantResume() end, "pending seed world")
    f.hooks.savePlantResume({worldIndex = 1, phase = "farm", skipped = {}})
    local record = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/plant-resume.json"])
    record.userId = 99
    rejects(function() f.hooks.readPlantResume() end, "another account")
    record.userId, record.updatedAt = 1234, os.time() - 21601
    rejects(function() f.hooks.readPlantResume() end, "six hours")
end)

test("A consumed seed with missing tile evidence cannot be silently retried", function()
    local f = plantingFixture(9, 100)
    f.app.job, f.app.jobToken = "plant", 1
    local state = {worldIndex = 1, phase = "farm", skipped = {}, pending = {world = "FARM1", x = 0, y = 5, before = 10}}
    rejects(function() f.hooks.reconcilePlant(state, 1) end, "Cannot reconcile")
    assert(state.pending and #f.plantCalls == 0)
end)

test("Full-world planting navigation reaches the row through a distant side corridor", function()
    local f = fixture()
    local map = {w = 42, h = 8, solid = function(x, y) return y == 6 or (y == 3 and x <= 37) end,
        platform = function(x, y) return x == 38 and y == 4 or x == 39 and y == 3 end}
    local start, goal = {x = 2, y = 5}, {x = 2, y = 2}
    assert(not f.hooks.Navigation.plan(map, start, goal))
    local route, message = f.hooks.Navigation.plan(map, start, goal, {fullWorld = true, maxNodes = 4000})
    assert(route, message)
    local edge = false
    for _, step in ipairs(route) do if step.x >= 38 then edge = true end end
    assert(edge)
end)

test("Planting on platforms uses the same follower and native support checks", function()
    local f = plantingFixture(10, 100)
    f.app.runtime.items[102] = {name = "Platform", platform = true}
    f.grids.FARM1[6][5], f.grids.FARM1[6][6] = 102, 0
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.app.stats.planted == 6 and f.grids.FARM1[5][5] == 955 and f.grids.FARM1[5][6] == 0)
end)

test("Unreachable supported tiles are reported without claiming every tile was filled", function()
    local f = plantingFixture(10, 100)
    for y = 0, 5 do f.grids.FARM1[y][3] = 2 end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.app.stats.planted == 3 and f.grids.FARM1[5][4] == 0 and f.serverSeeds == 7)
    assert(table.concat(f.app.logs, "\n"):find("3 tiles skipped due to access or route", 1, true))
end)

test("Mixed seed boxes are rejected before requesting a withdrawal", function()
    local f = plantingFixture(0, 100)
    f.world.displays.get = function() return {{955, 100}, {627, 20}} end
    f.hooks.start("plant")
    assert(f.app.lastError:find("different item", 1, true) and f.withdrawals == 0)
    assert(#f.plantCalls == 0 and f.hooks.readPlantResume().state.phase == "stock")
end)

test("The actual planting follower travels around a distant row edge", function()
    local f = fixture()
    f.world.w, f.world.h = 82, 8
    f.world.fg = {}
    f.app.runtime.items[102] = {platform = true}
    for y = 0, 7 do
        f.world.fg[y] = {}
        for x = 0, 81 do f.world.fg[y][x] = (y == 6 or y == 3 and x <= 77) and 2 or 0 end
    end
    f.world.fg[4][78], f.world.fg[3][79] = 102, 102
    f.app.runtime.body.solidAt = function(x, y)
        if x < 0 or x >= 82 or y >= 8 then return true end
        return f.world.fg[y] and f.world.fg[y][x] == 2 or false
    end
    f.avatar.x, f.avatar.y, f.app.job = 2.5, 6, "plant"
    local visited = attachPhysics(f, f.hooks.navigationMap(f.app.runtime))
    f.hooks.moveTo(2, 2, "BREAK", 1)
    assert(math.abs(f.avatar.x - 2.5) < 0.16 and math.abs(f.avatar.y - 3) < 0.22)
    local edge = false
    for key in pairs(visited) do if tonumber(key:match("^(%d+):")) >= 78 then edge = true end end
    assert(edge)
end)

test("Discovery exposes a unique native plantSeed hook belonging to the active world", function()
    local f = fixture()
    prepareDiscovery(f, true)
    attachWorldHandlers(f, f.app.runtime.items)
    local world = f.world
    local plantSeed = function(id, x, y) world.fg[y][x] = id end
    table.insert(f.discoveryObjects, plantSeed)
    local names = getinfo
    getinfo = function(fn) return fn == plantSeed and {name = "plantSeed"} or names(fn) end
    local r = f.hooks.connectGame()
    assert(r.ready and r.handlers.plantSeed == plantSeed)
end)

test("Ambiguous native planting hooks stay unavailable without disabling existing PNB", function()
    local f = fixture()
    prepareDiscovery(f, true)
    attachWorldHandlers(f, f.app.runtime.items)
    local world = f.world
    local first = function(id, x, y) world.fg[y][x] = id end
    local second = function(id, x, y) world.fg[y][x] = id end
    table.insert(f.discoveryObjects, first)
    table.insert(f.discoveryObjects, second)
    local names = getinfo
    getinfo = function(fn) return (fn == first or fn == second) and {name = "plantSeed"} or names(fn) end
    local r = f.hooks.connectGame()
    assert(r.ready and r.handlers.plantSeed == nil)
    assert(table.concat(f.app.discoveryReport, "\n"):find("Planting hook: ambiguous", 1, true))
end)

test("More than a stack of planting seeds triggers another refill in the current farm", function()
    local f = plantingFixture(0, 400, {"FARM1", "FARM2"})
    f.world.w = 121
    for _, grid in pairs(f.grids) do
        for y = 0, 7 do for x = 7, 120 do grid[y][x] = y == 6 and 2 or 0 end end
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.app.stats.planted == 242 and #f.plantCalls == 242 and f.withdrawals == 2)
    assert(f.stock == 0 and f.serverSeeds == 158)
    assert(f.entries[4] == "STOCK" and f.entries[5] == "FARM2")
    for _, name in ipairs({"FARM1", "FARM2"}) do for x = 0, 120 do assert(f.grids[name][5][x] == 955) end end
end)

local function largeSeedCatalog(f)
    for n = 1, 10000 do f.app.runtime.items[n + 2000] = {name = string.format("Bulk Seed %05d", n), kind = "seed"} end
end

test("Actual UI startup limits seed entries, renders once, and supports a bounded catalog search", function()
    local f = fixture()
    largeSeedCatalog(f)
    f.app.job, f.app.jobToken, f.app.config.planting.seedId = nil, nil, 955
    f.inventory:add(955, 5)
    prepareDiscovery(f, true)
    local getter, firstGCWait = getgc, nil
    getgc = function() firstGCWait = firstGCWait or (f.waits or 0); return getter() end
    local controls, workers = {}, {}
    local tab = {}
    local function control(props)
        local c = {Value = props.Value, Values = props.Values or {}, Props = props, refreshes = 0, maxRows = 0}
        function c:Set(value)
            self.Value = value
            if props.Callback then props.Callback(value) end
        end
        function c:Refresh(values)
            self.Values, self.refreshes = values, self.refreshes + 1
            self.maxRows = math.max(self.maxRows, #values)
            if props.Callback then props.Callback(self.Value) end
        end
        function c:Select(value) self.Value = value; self:Refresh(self.Values) end
        controls[props.Title] = c
        return c
    end
    for _, kind in ipairs({"Button", "Input", "Toggle", "Slider"}) do tab[kind] = function(_, props) return control(props) end end
    function tab:Dropdown(props) local c = control(props); c:Refresh(c.Values); return c end
    function tab:Paragraph(props)
        local c = control(props)
        c.ParagraphFrame = {SetTitle = function() end, SetDesc = function(_, text) c.Desc = text end}
        return c
    end
    local window = {OnDestroy = function() end, Tab = function() return tab end, Destroy = function() end}
    f.env.ClarisGrowbloxWindUI = {CreateWindow = function() return window end, Notify = function() end}
    UDim2 = {fromOffset = function(x, y) return {x, y} end}
    listfiles = function() return {} end
    f.player.Idled = {Connect = function() return {Disconnect = function() end} end}
    f.spawn = function(fn) workers[#workers + 1] = fn end
    f.env.ClarisGrowbloxTest = false
    local app = f.reload(true) -- Execute the actual UI path, beyond the usual test hooks.
    assert(#workers == 2 and app.window == window)
    workers[1]() -- Run connection/bootstrap; leave the perpetual status loop scheduled.
    local seeds = controls["Seed to plant"]
    assert(seeds.maxRows <= 40, "Startup built " .. seeds.maxRows .. " seed rows")
    assert(seeds.refreshes == 2, "Seed list was rebuilt more than once after initial creation")
    assert(firstGCWait > 0, "The GC snapshot ran before yielding a frame to the window")
    assert(seeds.Value == "Sugar Cane Seed [955]" and app.config.planting.seedId == 955)
    controls["Seed storage world"].Value = "UNSUBMITTED"
    controls["Find seed by name or ID"].Props.Callback("Bulk Seed")
    workers[3]()
    assert(seeds.maxRows <= 40 and #seeds.Values == 40 and seeds.Value == "Sugar Cane Seed [955]")
    assert(controls["Seed storage world"].Value == "UNSUBMITTED", "Searching overwrote another input")
    controls["Find seed by name or ID"].Props.Callback("10001")
    workers[4]()
    local label
    for _, value in ipairs(seeds.Values) do if value:find("[10001]", 1, true) then label = value end end
    assert(label and #seeds.Values == 2)
    seeds.Value = label
    seeds.Props.Callback(label)
    assert(app.config.planting.seedId == 10001 and app.config.points.farmDoor.world == "FARM")
end)

test("Default seed choices use inventory, the saved seed, box contents, and related block seed", function()
    local f = fixture()
    largeSeedCatalog(f)
    f.inventory:add(955, 5)
    f.app.config.planting.seedId = 3000
    f.app.config.points.plantBox = f.app.config.points.blockBox
    f.boxes[12] = {{4000, 5000}}
    local labels, lookup, selected = f.hooks.seedChoices("")
    assert(#labels == 3 and lookup[selected] == 3000)
    local ids = {}
    for _, id in pairs(lookup) do ids[id] = true end
    assert(ids[955] and ids[3000] and ids[4000] and not ids[5000])
end)

test("Catalog searches yield and keep selection visible within a fixed render limit", function()
    local f = fixture()
    largeSeedCatalog(f)
    f.app.config.planting.seedId = 955
    local before = f.waits or 0
    local labels, lookup, selected, more = f.hooks.seedChoices("bulk seed")
    assert(#labels == 40 and more and lookup[selected] == 955 and (f.waits or 0) > before)
    labels, lookup, selected = f.hooks.seedChoices("12000")
    assert(#labels == 2 and lookup["Bulk Seed 10000 [12000]"] == 12000 and lookup[selected] == 955)
end)

test("A large discovery snapshot yields and reads each function's upvalues at most once", function()
    local f = fixture()
    prepareDiscovery(f, true)
    attachWorldHandlers(f, f.app.runtime.items)
    for n = 1, 10000 do table.insert(f.discoveryObjects, {noise = n}) end
    for n = 1, 5000 do
        local noise = n
        table.insert(f.discoveryObjects, function() return noise end)
    end
    local reads = {}
    getupvalues = function(fn)
        reads[fn] = (reads[fn] or 0) + 1
        local values = {}
        for n = 1, 100 do
            local name, value = debug.getupvalue(fn, n)
            if not name then break end
            if value ~= nil then values[n] = value end
        end
        return values
    end
    local r = f.hooks.connectGame()
    assert(r.ready and f.app.discoveryPerformance.yields > 0)
    for _, n in pairs(reads) do assert(n == 1, "A function's upvalues were repeatedly scanned") end
end)

test("Discovery stops at its next frame boundary when the app is unloaded", function()
    local f = fixture()
    prepareDiscovery(f, true)
    for n = 1, 10000 do table.insert(f.discoveryObjects, {noise = n}) end
    local waits = 0
    f.onWait = function()
        waits = waits + 1
        if waits == 2 then f.app.alive = false end
    end
    f.app.runtime = nil
    rejects(function() f.hooks.connectGame() end, "unloaded during discovery")
    assert(f.app.runtime == nil and waits == 2)
end)

return string.format("%d actual-script runtime tests passed (mock services/server)", passed)
