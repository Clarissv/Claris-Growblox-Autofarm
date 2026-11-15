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
local function onlyMigrationFiles(files)
    for path in pairs(files) do if not path:match("/migration%.json$") then return false end end
    return true
end
local function fixture(userId, storage)
    storage = storage or {files = {}, encoded = {}, serial = 0}
    local env, files, encoded, queue = { ClarisGrowbloxTest = true }, storage.files, storage.encoded, {}
    local ticks = 0
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
            storage.serial = storage.serial + 1
            local key = "mock-json-" .. storage.serial
            encoded[key] = value
            return key
        end,
        JSONDecode = function(_, text) return encoded[text] end,
    }
    local localPlayer = { UserId = userId or 1234, Name = "TestPlayer", DisplayName = "Test Player", GetAttribute = function() return nil end }
    local services = {
        HttpService = http, Players = { LocalPlayer = localPlayer },
        ReplicatedStorage = { GetAttribute = function() return "session-registry" end },
        UserInputService = { GetFocusedTextBox = function() return nil end },
        Workspace = {GetServerTimeNow = function() return os.clock() end},
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
            assert(context.waits < 10000, "Offline task exceeded 10000 scheduler waits without completing or stopping")
            local elapsed = math.max(seconds or 0.03, 0.000001)
            ticks = ticks + elapsed -- A real scheduler yield advances time even for a zero/tiny wait.
            local pending = queue
            queue = {}
            for _, fn in ipairs(pending) do fn() end
            if context.onWait then context.onWait(elapsed) end
            return elapsed
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
    context.encoded, context.storage = encoded, storage
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
    local bindings = {getgenv=getgenv, isfile=isfile, isfolder=isfolder, makefolder=makefolder,
        readfile=readfile, writefile=writefile, delfile=delfile, game=game, task=task}
    local clock = os.clock
    context.activate = function()
        for key, value in pairs(bindings) do _G[key] = value end
        os.clock = clock
    end
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
            local desired = direction * (f.world.riding and f.world.riding.speed or 7.2)
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

local function lowCeilingPNBFixture()
    local f = fixture()
    f.world.w, f.world.h, f.world.name = 16, 12, "CLSXIVSTORAGE234"
    f.app.runtime.items[1422].solid = true
    f.app.runtime.items[102] = {name="Platform",platform=true}
    f.world.fg = {}
    for y=0,11 do
        f.world.fg[y]={}
        for x=0,15 do
            local solid = y==6 or y==5 and x<=5 or y==4 and x==5
                or y==2 and x<=9 or x==9 and (y==3 or y==4)
            f.world.fg[y][x] = solid and 2 or x==6 and y==4 and 102 or 0
        end
    end
    f.world.fg[4][0], f.world.fg[4][4] = 1422, 1422
    f.app.runtime.body.solidAt = function(x,y)
        if x<0 or x>=f.world.w or y>=f.world.h then return true end
        local item=f.app.runtime.items[f.world.fg[y] and f.world.fg[y][x] or 0]
        return item and item.solid == true or false
    end
    f.app.config.points.pnb = {world=f.world.name,x=2,y=4}
    f.app.config.points.seedBox = {world=f.world.name,x=0,y=4,standX=1,standY=4}
    f.app.config.points.blockBox = {world=f.world.name,x=4,y=4,standX=3,standY=4}
    f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = 10.5, 5.999, 0, 0
    f.app.job = "plant"
    f.map = f.hooks.navigationMap(f.app.runtime)
    return f
end

test("Low-ceiling storage routing jumps onto the side platform before entering the raised PNB room", function()
    local f = lowCeilingPNBFixture()
    local route, issue = f.hooks.Navigation.plan(f.map,{x=6,y=5},{x=1,y=4},{fullWorld=true})
    assert(route, issue)
    assert(route[1].jump and route[1].x == 6 and route[1].y == 3,
        "The low roof permits the platform landing even when a full jump would hit it")
    assert(route[#route].x == 1 and route[#route].y == 4)
end)

test("The movement follower reaches both PNB boxes from the lower white-door entrance under a low roof", function()
    local f = lowCeilingPNBFixture()
    local visited = attachPhysics(f,f.map)
    f.hooks.moveTo(1,4,f.world.name,1)
    assert(visited["6:3"] and visited["1:4"] and math.abs(f.avatar.x-1.5)<0.16)
    f.hooks.moveTo(3,4,f.world.name,1)
    assert(visited["3:4"] and f.avatar.grounded and math.abs(f.avatar.x-3.5)<0.16)
    assert(f.controls.dir()==0 and not f.controls.jumping())
end)

test("Ceiling collision resolution cannot open a sealed or inaccessible PNB corridor", function()
    local f = lowCeilingPNBFixture()
    f.world.fg[3][3],f.world.fg[4][3] = 2,2
    local route,issue=f.hooks.Navigation.plan(f.map,{x=10,y=5},{x=1,y=4},{fullWorld=true})
    assert(not route and issue:find("No walking/jumping route",1,true))
    rejects(function() f.hooks.moveTo(1,4,f.world.name,1) end,"Route: CLSXIVSTORAGE234: from tile 10, 5 to standing tile 1, 4")
    assert(f.app.navigationDebug:find("Failed CLSXIVSTORAGE234: from tile 10, 5",1,true))
    assert(f.app.navigationDebug:find("to standing tile 1, 4",1,true))
end)

test("Low-ceiling navigation retains support and headroom checks at saved box positions", function()
    local f = lowCeilingPNBFixture()
    f.world.fg[4][1]=2
    local route,issue=f.hooks.Navigation.plan(f.map,{x=6,y=5},{x=1,y=4},{fullWorld=true})
    assert(not route and issue:find("no accessible support or headroom",1,true))
    f.world.fg[4][1],f.world.fg[5][1],f.world.fg[6][1]=0,0,0
    route,issue=f.hooks.Navigation.plan(f.map,{x=6,y=5},{x=1,y=4},{fullWorld=true})
    assert(not route and issue:find("no accessible support or headroom",1,true))
end)

test("Planting refills through the low-ceiling PNB route before leaving storage for its farm", function()
    local f = lowCeilingPNBFixture()
    attachPhysics(f,f.map)
    f.app.config.points.plantBox = f.app.config.points.seedBox
    f.app.config.planting = {seedId=955,storageWorld=f.world.name,worlds={"FARM"}}
    f.boxes[0],f.serverSeeds,f.withdrawals={{955,10}},0,0
    f.server=function(name,x,y,id)
        if name=="GetInventory" then return {slots=f.serverSeeds>0 and {{955,f.serverSeeds}} or {},capacity=54} end
        assert(name=="DisplayItem" and x==0 and y==4 and id==nil)
        assert(math.abs(f.avatar.x-1.5)<0.16 and math.abs(f.avatar.y-5)<0.22)
        f.withdrawals,f.serverSeeds=f.withdrawals+1,10
        f.boxes[0]={}
        return true,{taken={{955,10}}}
    end
    f.world.enter=function(name)
        assert(name=="FARM" and f.inventory:count(955)==10 and f.withdrawals==1)
        f.app:stop()
        return true
    end
    rejects(function() f.hooks.runPlant(1,{state={phase="stock",worldIndex=1,skipped={}}}) end,"Stopped")
    assert(f.withdrawals==1 and f.inventory:count(955)==10 and f.app.pending==0)
end)

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
    local first = f.files["ClarisGrowblox/accounts/1234/pnb-resume.json"]
    task.wait(121)
    f.hooks.refreshPNBCheckpoint()
    assert(f.files["ClarisGrowblox/accounts/1234/pnb-resume.json"] ~= first)
    f.app:stop()
    task.wait(121)
    f.hooks.refreshPNBCheckpoint()
    assert(not f.files["ClarisGrowblox/accounts/1234/pnb-resume.json"])
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
test("Rejected direct return-world entry preserves a usable return checkpoint", function()
    local f = fixture()
    local entries = 0
    f.world.enter = function(name) assert(name == "FARM"); entries=entries+1; return false,"World locked" end
    f.server = function() error("Rejected world entry must not touch storage") end
    rejects(function() f.hooks.runTransfer(1, {phase = "return", cargo = 0}) end, "World locked")
    assert(entries == 3)
    assert(f.world.name == "BREAK" and f.app.resume.phase == "return" and f.app.resume.cargo == 0)
end)
test("Delivery transfers exact tracked cargo and preserves existing inventory", function()
    local f = fixture()
    f.inventory:add(954, 70)
    local serverCount, deposited = 70, 0
    f.world.enter = function(name) assert(name == "FARM"); return false,"End test after delivery" end
    f.server = function(name, x, y, id, _, _, n)
        if name == "GetInventory" then return {slots = {{954, serverCount}}, capacity = 54} end
        if name == "DisplayItem" then
            assert(x == 12 and y == 8 and id == 954 and n == 50)
            assert(f.app.resume.phase == "depositPending")
            serverCount, deposited = serverCount - n, deposited + n
            return true, {}
        end
        error("Unexpected server request: " .. name)
    end
    rejects(function() f.hooks.runTransfer(1, {phase = "deliver", cargo = 50}) end, "End test after delivery")
    assert(deposited == 50 and f.inventory:count(954) == 20)
    assert(f.app.stats.trips == 1 and f.app.stats.moved == 50)
    assert(f.app.resume.phase == "return" and f.app.resume.cargo == 0)
end)

test("Moving Drops uses four inventory reads per trip and preserves existing blocks", function()
    local f = fixture()
    f.world.name = "FARM"
    f.world.fg[8][21] = 12
    f.inventory:add(954, 20)
    local held, reads, doors, entries = 20, 0, 0, 0
    local boxes = {FARM = {[20] = {{954, 300}}}, BREAK = {[12] = {}}}
    f.world.displays.get = function(x) return boxes[f.world.name][x] or {} end
    f.world.enter = function(name) entries=entries+1; f.world.name = name; return true end
    f.server = function(name, x, y, id, _, _, n)
        if name == "GetInventory" then
            reads = reads + 1
            return {slots = {{954, held}}, capacity = 54}
        end
        if name == "UseDoor" then
            doors = doors + 1
            return true, {enter = f.world.name == "FARM" and "BREAK" or "FARM"}
        end
        assert(name == "DisplayItem")
        local storage = boxes[f.world.name]
        local before = f.hooks.Core.storageCount(storage[x], 954)
        if not id then
            assert(f.app.resume.phase == "pickupPending")
            local taken = math.min(before, 200 - held)
            storage[x], held = {{954, before - taken}}, held + taken
            return true, {taken = {{954, taken}}}
        end
        assert(n <= held and f.app.resume.phase == "depositPending")
        storage[x], held = {{954, before + n}}, held - n
        return true
    end
    f.hooks.takeControls()
    f.hooks.runTransfer(1)
    assert(f.app.stats.trips == 2 and f.app.stats.moved == 300 and doors == 0 and entries == 4)
    assert(held == 20 and f.inventory:count(954) == 20)
    assert(reads == 8, "Each withdrawal and deposit needs one before/after inventory pair, without outer repeats")
    assert(os.clock() < 0.1, "Already-ready direct entries must not impose a fixed delay")
end)

test("Door entry waits for destination readiness instead of a fixed delay", function()
    local f = fixture()
    f.server = function(name) assert(name == "UseDoor"); return true, {enter = "FARM"} end
    f.world.enter = function() f.world.name, f.avatar.active = "FARM", false; return true end
    f.onWait = function() if os.clock() >= 0.2 then f.avatar.active = true end end
    f.hooks.enterDoor(f.app.config.points.breakDoor, f.app.config.points.farmBox, "return", 0, 1)
    assert(os.clock() >= 0.2 and os.clock() < 0.3 and f.avatar.active)
end)

test("A transfer resumed during avatar loading waits before touching storage", function()
    local f = fixture()
    f.avatar.active = false
    f.inventory:add(954, 50)
    local held, deposits = 50, 0
    f.world.enter = function(name) assert(name == "FARM"); return false,"End after resumed delivery" end
    f.onWait = function() if os.clock() >= 0.15 then f.avatar.active = true end end
    f.server = function(name, x, y, id, _, _, n)
        assert(f.avatar.active and os.clock() >= 0.15, "No request should run before the arriving avatar is ready")
        if name == "GetInventory" then return {slots = {{954, held}}, capacity = 54} end
        if name == "DisplayItem" then
            assert(n == 50 and f.app.resume.phase == "depositPending")
            held, deposits = held - n, deposits + 1
            return true
        end
        error("Unexpected server request: " .. name)
    end
    rejects(function() f.hooks.runTransfer(1, {phase = "deliver", cargo = 50}) end, "End after resumed delivery")
    assert(deposits == 1 and f.app.stats.moved == 50 and held == 0)
end)

test("Stop during resumed-world loading preserves cargo without issuing requests", function()
    local f = fixture()
    f.avatar.active = false
    f.inventory:add(954, 50)
    f.server = function() error("No requests are allowed while the avatar is loading") end
    f.onWait = function() f.app.token = f.app.token + 1 end
    rejects(function() f.hooks.runTransfer(1, {phase = "deliver", cargo = 50}) end, "Stopped")
    assert(f.inventory:count(954) == 50 and f.app.stats.moved == 0 and f.app.pending == 0)
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

local function attachDropVisual(drop, parent)
    local values = {Parent = parent, Visible = true, destroyed = false, parentWrites = 0}
    local frame = setmetatable({}, {
        __index = function(_, key)
            if key == "Destroy" then return function()
                values.destroyed, values.Parent = true, nil
            end end
            return values[key]
        end,
        __newindex = function(_, key, value)
            if key == "Parent" then
                assert(not values.destroyed, "A destroyed drop must never be reparented")
                values.parentWrites = values.parentWrites + 1
            end
            values[key] = value
        end,
    })
    drop.frame, drop.pop = frame, {Scale = 0.35}
    return frame, values
end

test("FPS booster hides loose blocks, seeds and gems while preserving pickup data and displays", function()
    local f, parent = pickupFixture(), {}
    local original = {}
    for index, id in ipairs({954, 955, 112, 954}) do
        local drop = f.addDrop(index, id, 20, 10.5 + index, 8.5)
        drop.readyAt, drop.refused, drop.culled, drop.armed = 2, 1, index == 1, true
        if index == 4 then drop.display = {x = 12, y = 8} end
        attachDropVisual(drop, parent)
        original[index] = {uid = drop.uid, id = drop.id, n = drop.n, x = drop.x, y = drop.y,
            readyAt = drop.readyAt, refused = drop.refused, culled = drop.culled, armed = drop.armed}
    end
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    assert(not f.app.fpsBoosterError and f.app.fpsHidden == 3 and #f.drops == 4 and #f.requests == 0)
    for index, drop in ipairs(f.drops) do
        for key, value in pairs(original[index]) do assert(drop[key] == value, "Do not change native pickup data") end
        drop.frame.Visible = true -- Native visibility writes must not reveal hidden sprites.
        assert(drop.frame.Parent == (index == 4 and parent or nil))
        assert(drop.pop.Scale == (index == 4 and 0.35 or 1))
    end
    f.app.config.options.fpsBooster = false
    f.hooks.pollFPSBooster(true)
    for _, drop in ipairs(f.drops) do assert(drop.frame.Parent == parent and drop.inBlock == nil and drop.pop.Scale == 0.35) end
    assert(f.app.fpsState == nil and f.app.fpsHidden == 0)
end)

test("FPS booster catches new drops on its bounded poll without rewriting existing frames", function()
    local f, parent = pickupFixture(), {}
    local first = f.addDrop(1, 954, 10)
    local _, values = attachDropVisual(first, parent)
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    local second = f.addDrop(2, 955, 10)
    attachDropVisual(second, parent)
    f.hooks.pollFPSBooster()
    assert(second.frame.Parent == parent and values.parentWrites == 1)
    task.wait(1.1)
    f.hooks.pollFPSBooster()
    assert(second.frame.Parent == nil and values.parentWrites == 1 and f.app.fpsHidden == 2)
end)

test("Hidden PNB blocks, seeds and gems still collect in partial batches without resurrecting frames", function()
    local f, parent = pickupFixture(), {}
    local frames = {}
    for index, id in ipairs({954, 955, 112}) do
        local drop = f.addDrop(index, id, 20)
        frames[index] = attachDropVisual(drop, parent)
    end
    local taken = f.world.dropTaken
    f.world.dropTaken = function(uid, remaining)
        taken(uid, remaining)
        if remaining == 0 then frames[uid]:Destroy() end
    end
    f.accept = function(_, want) return math.min(6, want) end
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    f.collect()
    assert(#f.drops == 0 and #f.requests > 3 and f.inventory:count(954) == 20 and f.inventory:count(955) == 20)
    assert(f.app.stats.gems == 20 and f.serverGems == 120)
    f.hooks.pollFPSBooster(true)
    f.app.config.options.fpsBooster = false
    f.hooks.pollFPSBooster(true)
    assert(f.app.fpsState == nil and not f.app.fpsBoosterError)
    for _, frame in ipairs(frames) do assert(frame.destroyed and frame.Parent == nil) end
end)

test("A large FPS scan yields and normal Stop retains the graphics setting", function()
    local f, parent = pickupFixture(), {}
    for uid = 1, 2000 do attachDropVisual(f.addDrop(uid, 954, 1), parent) end
    f.app.config.options.fpsBooster = true
    local before = f.waits or 0
    f.onWait = function() f.onWait = nil; f.app:stop() end
    f.hooks.pollFPSBooster(true)
    assert(f.app.alive and f.app.config.options.fpsBooster and f.app.fpsHidden == 2000)
    assert((f.waits or 0) - before >= 3 and (f.waits or 0) - before <= 4)
    assert(#f.drops == 2000 and #f.requests == 0 and f.app.pending == 0)
end)

test("Unloading during a yielded FPS scan restores every detached frame", function()
    local f, parent = pickupFixture(), {}
    for uid = 1, 1200 do attachDropVisual(f.addDrop(uid, 954, 1), parent) end
    f.app.config.options.fpsBooster = true
    f.onWait = function() f.onWait = nil; f.app:destroy() end
    f.hooks.pollFPSBooster(true)
    assert(not f.app.alive and f.app.fpsState == nil and f.app.fpsHidden == 0)
    for _, drop in ipairs(f.drops) do assert(drop.frame.Parent == parent and drop.inBlock == nil and drop.pop.Scale == 0.35) end
end)

test("Native list shifts during FPS polling cannot discard live frame restoration data", function()
    local f, parent = pickupFixture(), {}
    for uid = 1, 1025 do attachDropVisual(f.addDrop(uid, 954, 1), parent) end
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    local removed
    f.onWait = function()
        f.onWait = nil
        removed = table.remove(f.drops, 1)
        removed.frame:Destroy()
    end
    f.hooks.pollFPSBooster(true)
    assert(f.app.fpsHidden == 1024 and #f.drops == 1024)
    f.app.config.options.fpsBooster = false
    f.hooks.pollFPSBooster(true)
    for _, drop in ipairs(f.drops) do assert(drop.frame.Parent == parent and drop.inBlock == nil) end
    assert(removed.frame.destroyed and removed.frame.Parent == nil and not f.app.fpsBoosterError)
end)

test("FPS polling restores a loose sprite that becomes a Display Box sprite", function()
    local f, parent = pickupFixture(), {}
    local drop = f.addDrop(1, 954, 10)
    attachDropVisual(drop, parent)
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    drop.display, drop.inBlock = {x = 12, y = 8}, true
    f.hooks.pollFPSBooster(true)
    assert(drop.frame.Parent == parent and drop.inBlock and f.app.fpsHidden == 0)
end)

test("A visual write failure rolls back the booster without stopping farming or making requests", function()
    local f, parent = pickupFixture(), {}
    local drop = f.addDrop(1, 954, 10)
    attachDropVisual(drop, parent)
    drop.pop = setmetatable({}, {__index = function() return 0.35 end,
        __newindex = function() error("Scale write denied") end})
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    assert(f.app.fpsBoosterError:find("Scale write denied", 1, true) and f.app.job == "transfer" and f.app.alive)
    assert(drop.frame.Parent == parent and drop.inBlock == nil and #f.requests == 0 and f.app.pending == 0)
end)

test("Script reload restores prior drop visuals and preserves the saved booster choice and progress", function()
    local f, parent = pickupFixture(), {}
    local drop = f.addDrop(1, 954, 10)
    attachDropVisual(drop, parent)
    f.app.config.options.fpsBooster = true
    f.app.config.planting = {seedId = 955, storageWorld = "STOCK", worlds = {"FARM"}}
    f.hooks.savePlantResume({worldIndex = 1, phase = "farm", skipped = {}})
    f.hooks.pollFPSBooster(true)
    local runtime, next = f.app.runtime, f.reload(true)
    assert(drop.frame.Parent == parent and drop.inBlock == nil and next.App.config.options.fpsBooster)
    assert(next.readPlantResume().state.worldIndex == 1)
    next.App.runtime = runtime
    next.pollFPSBooster(true)
    assert(drop.frame.Parent == nil and next.App.fpsHidden == 1)
    next.App.config.options.fpsBooster = false
    next.pollFPSBooster(true)
    assert(drop.frame.Parent == parent and not next.App.fpsBoosterError)
end)

test("FPS polling follows a same-server world change and restores only the new live drops", function()
    local f, oldParent, newParent = pickupFixture(), {}, {}
    local old = f.addDrop(1, 954, 10)
    attachDropVisual(old, oldParent)
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    old.frame:Destroy()
    f.drops[1] = nil
    f.world.name = "NEXT"
    local current = f.addDrop(2, 955, 10)
    attachDropVisual(current, newParent)
    f.hooks.pollFPSBooster(true)
    assert(current.frame.Parent == nil and f.app.fpsHidden == 1)
    f.app.config.options.fpsBooster = false
    f.hooks.pollFPSBooster(true)
    assert(current.frame.Parent == newParent and old.frame.Parent == nil and not f.app.fpsBoosterError)
end)

test("An unavailable drop list preserves FPS restore records until cleanup can retry", function()
    local f, parent = pickupFixture(), {}
    local drop = f.addDrop(1, 954, 10)
    attachDropVisual(drop, parent)
    f.app.config.options.fpsBooster = true
    f.hooks.pollFPSBooster(true)
    local getter = f.world.dropList
    f.world.dropList = function() error("World reload in progress") end
    f.app.config.options.fpsBooster = false
    f.hooks.pollFPSBooster(true)
    assert(f.app.fpsState and f.app.fpsBoosterError and drop.frame.Parent == nil)
    f.world.dropList = getter
    f.hooks.pollFPSBooster(true)
    assert(drop.frame.Parent == parent and f.app.fpsState == nil and not f.app.fpsBoosterError)
end)

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
        assert(f.world.name == "FARM" and x == 12 and y == 8 and (id == 954 or id == 955))
        assert(n > 0 and n <= (f.serverItems[id] or 0))
        f.serverItems[id] = f.serverItems[id] - n
        local total = f.hooks.Core.itemCount(f.boxes[x], id)
        local rows = {}
        for _, row in ipairs(f.boxes[x]) do if row[1] ~= id then rows[#rows+1] = row end end
        rows[#rows+1] = {id, total + n}
        f.boxes[x] = rows
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
    assert(f.hooks.Core.itemCount(f.boxes[12], 954) == 320 and f.hooks.Core.itemCount(f.boxes[12], 955) == 10 and f.inventory:count(954) == 0)
    assert(f.app.stats.harvested == 120 and f.app.stats.stashed == 320)
    assert(#f.drops == 1 and seed.n == 0 and gems.n == 0 and other.n == 5 and f.app.stats.gems == 20)
    assert(f.app.stats.harvestSeeds == 10 and f.app.stats.stashedSeeds == 10)
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
    assert(rejected == 0 and visited["4:8"] and #f.drops == 0)
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

test("The movement follower descends one farm row around its edge platform", function()
    for _, side in ipairs({-1, 1}) do
        local f = fixture()
        f.world.w, f.world.h = 12, 10
        local map = {w = 12, h = 10,
            solid = function(x, y) return y == 9 or (y == 3 or y == 5 or y == 7) and x >= 2 and x <= 9 end,
            platform = function(x, y) return (x == 1 or x == 10) and (y == 3 or y == 5 or y == 7) end}
        f.app.runtime.body.solidAt = map.solid
        f.app.runtime.items[102] = {platform = true}
        f.world.fg = {}
        for y = 0, 9 do
            f.world.fg[y] = {}
            for x = 0, 11 do f.world.fg[y][x] = map.platform(x, y) and 102 or map.solid(x, y) and 2 or 0 end
        end
        local x = side == -1 and 1 or 10
        f.avatar.x, f.avatar.y, f.app.job = x + 0.5, 2.999, "harvest"
        local route, issue = f.hooks.Navigation.plan(map, {x = x, y = 2}, {x = x, y = 4}, {fullWorld = true})
        assert(route and #route == 1 and route[1].drop, issue or "A platform descent must be one direct edge")
        local visited = attachPhysics(f, map)
        f.hooks.moveTo(x, 4, "BREAK", 1)
        assert(visited[x .. ":4"] and math.abs(f.avatar.x - (x + 0.5)) < 0.16)
        assert(f.avatar.y < 5.1, "The descent must land on the next row instead of falling to the bottom")
    end
end)

test("Stopping during a platform descent cancels steering and restores the native controls", function()
    local f = fixture()
    f.world.w, f.world.h = 12, 10
    f.app.runtime.items[102] = {platform = true}
    local map = {w = 12, h = 10,
        solid = function(x, y) return y == 9 or (y == 3 or y == 5) and x >= 2 and x <= 9 end,
        platform = function(x, y) return (x == 1 or x == 10) and (y == 3 or y == 5) end}
    f.app.runtime.body.solidAt, f.world.fg = map.solid, {}
    for y = 0, 9 do
        f.world.fg[y] = {}
        for x = 0, 11 do f.world.fg[y][x] = map.platform(x, y) and 102 or map.solid(x, y) and 2 or 0 end
    end
    f.avatar.x, f.avatar.y, f.app.job = 1.5, 2.999, "harvest"
    local dir, jump = f.controls.dir, f.controls.jumping
    attachPhysics(f, map)
    local physics, stopped = f.onWait, false
    f.onWait = function(dt)
        physics(dt)
        if f.avatar.y > 3.02 then stopped = true; f.app:stop() end
    end
    rejects(function() f.hooks.moveTo(1, 4, "BREAK", 1) end, "Stopped")
    assert(stopped and f.app.controls == nil and f.controls.dir == dir and f.controls.jumping == jump)
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
        return want
    end
    f.harvest()
    assert(#accepted==3 and accepted[1]==3 and accepted[2]==2 and accepted[3]==1)
    assert(#f.drops==0 and f.app.stats.stashed==30)
end)

test("Harvest revisits partially collected stacks after walking pickup replies settle", function()
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
    end
    f.harvest()
    assert(#f.drops==0 and f.app.stats.stashed==8)
end)

test("Harvest revisits a not-yet-ready stack after its readiness delay", function()
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
    end
    f.harvest()
    assert(delayed and #f.drops==0 and f.app.stats.stashed==12)
end)

test("Harvest finishes more than eight nearby UIDs across bounded walking batches", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f,map)
    for uid=1,12 do f.addDrop(uid,954,1,4.5,8.5) end
    f.addDrop(13,954,1,2.5,8.5)
    f.accept=function(drop,want)
        if math.abs(drop.x-f.avatar.x)>0.8 then return 0 end
        return want
    end
    local delayed = {}
    f.spawn = function(fn) delayed[#delayed + 1] = {fn=fn, at=os.clock()+0.3} end
    local physics=f.onWait
    f.onWait=function(dt)
        physics(dt)
        local ready = {}
        for index=#delayed,1,-1 do
            if delayed[index].at <= os.clock() then
                ready[#ready+1]=delayed[index].fn
                table.remove(delayed,index)
            end
        end
        for _, complete in ipairs(ready) do complete() end
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
            f.app:stop()
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

test("Harvest uses the native menu Respawn action when the world has no respawn method", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f, map)
    f.addDrop(1, 954, 20, 4.5, 8.5)
    f.accept = function(drop, want) return math.abs(drop.x - f.avatar.x) < 0.6 and want or 0 end
    local respawns = 0
    f.app.runtime.respawn = function()
        assert(f.world.respawn == nil and f.app.pending == 1)
        respawns = respawns + 1
        f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = 10.5, 8.999, 0, 0
    end
    f.app.runtime.respawnSource = "native menu adapter"
    f.harvest()
    assert(respawns == 1 and f.app.stats.stashed == 20 and #f.deposits == 1,
        "An adapter-bound Respawn must replace the walking return")
end)

test("An enabled but unavailable respawn hook explains the walking fallback", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    attachPhysics(f, map)
    f.addDrop(1, 954, 20, 4.5, 8.5)
    f.accept = function(drop, want) return math.abs(drop.x - f.avatar.x) < 0.6 and want or 0 end
    f.harvest()
    assert(f.app.stats.stashed == 20 and f.app.harvestReturnDebug:find("unavailable", 1, true))
    assert(table.concat(f.app.logs, "\n"):find("Respawn unavailable", 1, true))
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
    assert(refused == 0, "The farm route must reach the upper row before requesting its drops")
    assert(visited["10:6"] and #f.drops == 0 and f.app.stats.stashed == 20)
end)

local function zigzagHarvestFixture()
    local f = harvestFixture()
    f.world.w, f.world.h = 16, 11
    harvestFloor(f)
    f.app.runtime.items[102] = {platform = true}
    for _, y in ipairs({3, 5, 7}) do
        for x = 1, 14 do f.world.fg[y][x] = (x == 1 or x == 14) and 102 or 2 end
    end
    f.app.runtime.body.solidAt = function(x, y)
        if x < 0 or x >= f.world.w or y >= f.world.h then return true end
        local item = f.app.runtime.items[f.world.fg[y] and f.world.fg[y][x] or 0]
        return item and item.solid == true or false
    end
    f.visited = attachPhysics(f, f.hooks.navigationMap(f.app.runtime))
    f.accepted, f.respawns = {}, 0
    f.accept = function(drop, want)
        assert(f.hooks.Navigation.pickupOverlap(f.avatar, drop), "Farm pickups must overlap the avatar on the correct row")
        f.accepted[#f.accepted + 1] = drop.uid
        return want
    end
    f.app.runtime.respawn = function()
        assert(f.app.pending == 1)
        f.respawns = f.respawns + 1
        f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = 10.5, 8.999, 0, 0
    end
    return f
end

local function treeHarvestFixture(method)
    local f = zigzagHarvestFixture()
    f.app.config.harvesting.method = method or "fist"
    f.app.runtime.items[955].grow = 100
    f.app.runtime.items[898] = {name = "Dear John Tractor", kind = "cloth", slot = "feet", ride = "tractor"}
    f.app.runtime.items[777] = {name = "Boots", kind = "cloth", slot = "feet"}
    f.inventory:add(898, 1)
    f.inventory:add(777, 1)
    f.serverItems[898], f.serverItems[777] = 1, 1
    f.trees, f.treeActions, f.wearActions, f.worn = {}, {}, {}, 777
    f.app.runtime.harvestGear = {
        feet = function() return f.worn end,
        wear = function(id)
            if f.worn == id then f.worn = nil else f.worn = id end
            f.wearActions[#f.wearActions + 1] = {id = id, worn = f.worn, y = f.avatar.y}
            f.world.riding = f.worn == 898 and {harvest = true, speed = 3.6} or nil
        end,
    }
    f.app.runtime.treeRipe = function(x, y, id)
        local tree = f.trees[y * f.world.w + x]
        if not tree then return nil end
        return 1000 + os.clock() >= tree.p + (f.app.runtime.items[id].grow or 0)
    end
    function f.addTree(x, y, ripe, id)
        f.world.fg[y][x] = id or 955
        f.trees[y * f.world.w + x] = {p = ripe == false and 1000 or 0}
    end
    local function destroy(x, y, tractor)
        assert(f.app.controls and f.app.controls.pausePickup, "Tree harvesting must suppress automatic pickups")
        assert(f.world.fg[y][x] == 955 and f.app.runtime.treeRipe(x, y, 955))
        if f.refuseTree then return end
        if tractor and f.tractorMissed and f.tractorMissed[y*f.world.w+x] then return end
        if not tractor and f.fistRefused then return end
        f.treeActions[#f.treeActions + 1] = {x = x, y = y, tractor = tractor, avatarX=f.avatar.x, avatarY=f.avatar.y}
        f.world.fg[y][x], f.trees[y * f.world.w + x] = 0, nil
        f.addDrop(100 + #f.treeActions, 954, 10, x + 0.5, y + 0.5)
        if f.treeDrops then f.treeDrops(x, y, #f.treeActions) end
    end
    f.app.runtime.handlers = {hit = function(x, y)
        assert(f.worn ~= 898, "Fist must remove the automatic harvesting vehicle first")
        assert(f.avatar.grounded and math.abs(f.avatar.x - (x + 0.5)) <= 2.5
            and math.abs(y + 0.5 - (f.avatar.y - 0.475)) <= 2.5, "Fist must stay within native reach")
        f.hits = (f.hits or 0) + 1
        return destroy(x, y, false)
    end}
    f.world.ride = function(now)
        if not f.world.riding or not f.world.riding.harvest then return end
        local y = math.floor(f.avatar.y - 0.475)
        for x = math.floor(f.avatar.x - 0.3), math.floor(f.avatar.x + 0.3) do
            if f.world.fg[y] and f.world.fg[y][x] == 955 and f.app.runtime.treeRipe(x, y, 955) then
                destroy(x, y, true)
            end
        end
    end
    local physics = f.onWait
    f.onWait = function(dt)
        physics(dt)
        if f.app.controls then f.world.ride(os.clock()) end
    end
    local accept = f.accept
    f.accept = function(drop, want)
        if drop.id ~= 112 then
            assert(not f.world.riding or not f.world.riding.harvest, "Block/seed collection must remove the tractor")
            assert(#f.treeActions == (f.expectedTrees or 0), "All trees must be harvested before the first block/seed pickup")
        end
        return accept(drop, want)
    end
    return f
end

test("Harvest collects blocks, seeds and gems during zigzag movement with batched inventory reads", function()
    local f = zigzagHarvestFixture()
    for row=1,3 do
        for x=2,13 do
            for index,id in ipairs({954,955,112}) do f.addDrop(row*1000+x*3+index,id,1,x+0.5,row*2+0.5) end
        end
    end
    local accept, moving, reads, peak = f.accept, 0, 0, 0
    f.accept = function(drop,want)
        if math.abs(f.avatar.vx) > 0.8 and f.controls.dir() ~= 0 then moving=moving+1 end
        return accept(drop,want)
    end
    local server = f.server
    f.server = function(name,...)
        if name == "GetInventory" then reads=reads+1 end
        return server(name,...)
    end
    f.spawn = function(fn) peak=math.max(peak,f.app.pending); task.defer(fn) end
    f.harvest()
    assert(moving >= 90, "Most pickups must happen while walking: " .. moving .. "/108")
    assert(peak <= 8 and reads < 30, "Moving collection must bound requests and avoid a backpack RPC per drop")
    assert(#f.drops == 0 and f.app.pending == 0 and f.app.stats.gems == 36 and f.serverGems == 136)
    assert(f.app.stats.harvested == 36 and f.app.stats.harvestSeeds == 36)
    assert(f.hooks.Core.itemCount(f.boxes[12],954) == 36 and f.hooks.Core.itemCount(f.boxes[12],955) == 36)
    assert(f.inventory:count(112) == 0 and f.hooks.Core.itemCount(f.boxes[12],112) == 0)
end)

test("A gem-only harvest walks occupied rows without storing gems or visiting empty rows", function()
    local f = zigzagHarvestFixture()
    f.addDrop(1,112,7,2.5,4.5)
    f.addDrop(2,112,11,13.5,4.5)
    local balance
    f.app.runtime.gemHud = {setGems=function(n) balance=n end}
    f.harvest()
    assert(#f.drops == 0 and f.app.stats.gems == 18 and balance == 118)
    assert(#f.deposits == 0 and f.respawns == 0 and not f.visited["1:2"])
    assert(f.app.stats.harvestSeeds == 0 and f.app.stats.harvested == 0)
end)

test("Walking pickup reservations prevent overflow with delayed replies and mixed stacked drops", function()
    local f = zigzagHarvestFixture()
    for x=2,13 do
        f.addDrop(x*10,954,30,x+0.5,2.5)
        f.addDrop(x*10+1,955,30,x+0.5,2.5)
        f.addDrop(x*10+2,112,3,x+0.5,2.5)
    end
    local delayed, physics, peak = {}, f.onWait, 0
    f.spawn = function(fn)
        peak=math.max(peak,f.app.pending)
        delayed[#delayed+1]={fn=fn,at=os.clock()+0.07}
    end
    f.onWait = function(dt)
        physics(dt)
        local ready={}
        for index=#delayed,1,-1 do
            if delayed[index].at <= os.clock() then
                ready[#ready+1]=delayed[index].fn; table.remove(delayed,index)
            end
        end
        for _,complete in ipairs(ready) do complete() end
        assert((f.serverItems[954] or 0) <= 200 and (f.serverItems[955] or 0) <= 200)
    end
    f.accept = function(drop,want)
        if not f.hooks.Navigation.pickupOverlap(f.avatar,drop) then return 0 end
        if drop.id ~= 112 then assert((f.serverItems[drop.id] or 0)+want <= 200) end
        return want
    end
    f.harvest()
    assert(peak <= 8 and #delayed == 0 and #f.drops == 0 and f.app.pending == 0)
    assert(f.app.stats.harvested == 360 and f.app.stats.harvestSeeds == 360 and f.app.stats.gems == 36)
    assert(f.hooks.Core.itemCount(f.boxes[12],954) == 360 and f.hooks.Core.itemCount(f.boxes[12],955) == 360)
    assert(f.serverItems[954] == 0 and f.serverItems[955] == 0)
end)

test("Fist harvests ripe trees in zigzag order before collecting their drops", function()
    local f = treeHarvestFixture("fist")
    for _, y in ipairs({2, 4, 6}) do for _, x in ipairs({2, 7, 13}) do f.addTree(x, y) end end
    f.expectedTrees = 9
    f.harvest()
    assert(f.hits == 9 and f.app.stats.trees == 9 and f.app.stats.stashed == 90)
    local order = {}
    for _, point in ipairs(f.treeActions) do order[#order + 1] = point.x .. ":" .. point.y end
    assert(table.concat(order, ",") == "2:2,7:2,13:2,13:4,7:4,2:4,2:6,7:6,13:6", table.concat(order, ","))
    assert(f.world.fg[4][4] == 0 and f.worn == 777)
end)

test("Tractor harvests by native walking, removes it between rows, and restores the previous footwear", function()
    local f = treeHarvestFixture("tractor")
    for _, y in ipairs({2, 4, 6}) do for _, x in ipairs({2, 7, 13}) do f.addTree(x, y) end end
    f.expectedTrees = 9
    f.harvest()
    assert(not f.hits and f.app.stats.trees == 9 and f.app.stats.stashed == 90 and f.worn == 777)
    local order, equips = {}, 0
    for _, point in ipairs(f.treeActions) do assert(point.tractor); order[#order + 1] = point.x .. ":" .. point.y end
    assert(table.concat(order, ",") == "2:2,7:2,13:2,13:4,7:4,2:4,2:6,7:6,13:6", table.concat(order, ","))
    for _, action in ipairs(f.wearActions) do
        if action.worn == 898 then
            equips = equips + 1
            assert(math.floor(action.y - 0.01) == (equips == 1 and 2 or equips == 2 and 4 or 6))
        end
    end
    assert(equips == 3 and f.world.riding == nil)
end)

local function addTreeCurrency(f)
    f.treeDrops = function(x, y, index)
        f.addDrop(1000 + index * 2, 112, 3, x + 0.5, y + 0.5)
        f.addDrop(1001 + index * 2, 955, 2, x + 0.5, y + 0.5)
    end
end

test("Tractor collects gems while harvesting before blocks/seeds, with complete gem totals and HUD", function()
    local f = treeHarvestFixture("tractor")
    addTreeCurrency(f)
    for _, y in ipairs({2,4,6}) do for _, x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees, f.app.stats.gems = 9, 5
    local displayed = f.addDrop(9000,112,100,7.5,2.5)
    displayed.display = true
    f.addDrop(9001,956,10,7.5,2.5)
    local accept, early, moving, balance = f.accept, 0, 0
    f.accept = function(drop,want)
        if drop.id == 112 and f.world.riding and f.world.riding.harvest then
            if #f.treeActions < f.expectedTrees then early = early+1 end
            if f.controls.dir() ~= 0 and math.abs(f.avatar.vx) > 0.8 then moving = moving+1 end
        end
        return accept(drop,want)
    end
    f.app.runtime.gemHud = {setGems=function(n) balance=n end}
    f.harvest()
    assert(early >= 6 and moving >= 6, "Gems should be picked up during the moving Tractor pass")
    assert(f.app.stats.gems == 32 and f.serverGems == 127 and balance == 127)
    assert(f.app.status:find("27 gems collected",1,true), f.app.status)
    assert(f.app.stats.stashed == 90 and f.app.stats.stashedSeeds == 18)
    assert(f.hooks.Core.itemCount(f.boxes[12],112) == 0 and f.inventory:count(112) == 0)
    assert(#f.drops == 2 and not displayed.taking and f.app.pending == 0 and f.worn == 777)
end)

test("Tractor leaves unready/refused gems for the final sweep and handles partial gem takes", function()
    local f = treeHarvestFixture("tractor")
    for _, x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.expectedTrees = 3
    f.treeDrops = function(x,y,index)
        local drop = f.addDrop(1000+index,112,index+3,x+0.5,y+0.5)
        if index == 1 then drop.readyAt = os.clock()+1 end
    end
    local accept, refused, partial, readiness = f.accept, 0, 0, false
    f.accept = function(drop,want)
        if drop.id == 112 then
            assert(os.clock() >= (drop.readyAt or 0))
            local riding = f.world.riding and f.world.riding.harvest
            if drop.uid == 1001 then readiness = not riding end
            if drop.uid == 1002 and riding then refused = refused+1; return 0 end
            if drop.uid == 1003 and want > 2 then partial = partial+1; return 2 end
        end
        return accept(drop,want)
    end
    f.harvest()
    assert(readiness and refused == 1 and partial > 0)
    assert(#f.drops == 0 and f.app.stats.gems == 15 and f.serverGems == 115)
    assert(f.app.stats.stashed == 30 and f.app.pending == 0)
end)

test("Native suppressed pickup attempts cannot postpone fresh gems until after Tractor harvesting", function()
    local f = treeHarvestFixture("tractor")
    addTreeCurrency(f)
    for _, x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.expectedTrees = 3
    local physics, accept, early, suppressed = f.onWait, f.accept, 0, 0
    f.onWait = function(dt)
        physics(dt)
        if not f.app.controls then return end
        for _, drop in ipairs(f.drops) do
            if not drop.taking and f.hooks.Navigation.pickupOverlap(f.avatar,drop)
                and os.clock() >= math.max(drop.readyAt or 0,(drop.refused or -math.huge)+1) then
                -- Match the native client's bookkeeping around the intercepted hook.
                drop.taking = true
                assert(f.world.takeDrop(drop.uid,drop.n) == 0)
                drop.taking, drop.refused = false, os.clock()
                if drop.id == 112 then suppressed = suppressed+1 end
            end
        end
    end
    f.accept = function(drop,want)
        if drop.id == 112 and f.world.riding and f.world.riding.harvest then early = early+1 end
        return accept(drop,want)
    end
    f.harvest()
    assert(suppressed == 3 and early == 3, "All fresh gems should be collected despite synthetic cooldowns")
    assert(#f.drops == 0 and f.app.stats.gems == 9 and f.serverGems == 109)
    assert(f.app.stats.stashed == 30 and f.app.stats.stashedSeeds == 6 and f.app.pending == 0)
end)

test("Delayed Tractor gem replies stay bounded while driving and settle before storage travel", function()
    local f = treeHarvestFixture("tractor")
    for _, x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.expectedTrees = 3
    f.treeDrops = function(x,y,index)
        for n=1,12 do f.addDrop(1000+index*20+n,112,1,x+0.5,y+0.5) end
    end
    local delayed, physics, peak, moving = {}, f.onWait, 0, 0
    f.spawn = function(fn)
        peak = math.max(peak,f.app.pending)
        if f.world.riding and f.world.riding.harvest then
            delayed[#delayed+1] = {fn=fn,at=os.clock()+0.12}
        else task.defer(fn) end
    end
    f.onWait = function(dt)
        if #delayed > 0 and f.controls.dir() ~= 0 then moving = moving+1 end
        physics(dt)
        local ready = {}
        for index=#delayed,1,-1 do
            if delayed[index].at <= os.clock() then
                ready[#ready+1] = delayed[index].fn; table.remove(delayed,index)
            end
        end
        for _,complete in ipairs(ready) do complete() end
    end
    local server = f.server
    f.server = function(name,...)
        if name == "DisplayItem" then assert(#delayed == 0, "Gem replies must settle before storage travel") end
        return server(name,...)
    end
    f.harvest()
    assert(peak == 8 and moving > 0 and #delayed == 0 and f.app.pending == 0)
    assert(#f.drops == 0 and f.app.stats.gems == 36 and f.serverGems == 136 and f.app.stats.stashed == 30)
end)

test("Stop holds an in-flight Tractor gem until its late reply settles once", function()
    local f = treeHarvestFixture("tractor")
    for _, x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.expectedTrees = 3
    local gem, delayed
    f.treeDrops = function(x,y,index)
        if index == 1 then gem = f.addDrop(1000,112,7,x+0.5,y+0.5) end
    end
    f.spawn = function(fn)
        if f.world.riding and f.world.riding.harvest then delayed = fn else fn() end
    end
    local physics = f.onWait
    f.onWait = function(dt)
        if delayed then f.app:stop() else physics(dt) end
    end
    rejects(f.harvest,"Stopped")
    assert(delayed and gem.taking and f.app.pending == 1 and f.worn == 777)
    assert(#f.treeActions < 3 and f.app.stats.stashed == 0)
    f.allowLatePickup, f.allowMovingPickup = true, true
    f.accept = function(drop,want) assert(drop == gem); return want end
    delayed()
    assert(not gem.taking and f.app.pending == 0 and f.app.stats.gems == 7 and f.serverGems == 107)
    for _,drop in ipairs(f.drops) do assert(drop ~= gem) end
end)

test("Late Tractor gem replies do not modify drops or totals after a world change", function()
    local f = treeHarvestFixture("tractor")
    for _, x in ipairs({2,7,13}) do f.addTree(x,2) end
    local gem, delayed
    f.treeDrops = function(x,y,index)
        if index == 1 then gem = f.addDrop(1000,112,7,x+0.5,y+0.5) end
    end
    f.spawn = function(fn)
        if f.world.riding and f.world.riding.harvest then delayed = fn else fn() end
    end
    local physics = f.onWait
    f.onWait = function(dt)
        if delayed then f.world.name, f.world.fg = "OTHER", {} else physics(dt) end
    end
    rejects(f.harvest,"The world changed")
    assert(delayed and gem.taking and f.app.pending == 1)
    f.allowLatePickup, f.allowMovingPickup = true, true
    f.accept = function(drop,want) assert(drop == gem); return want end
    delayed()
    assert(not gem.taking and gem.n == 7 and f.app.pending == 0 and f.app.stats.gems == 0)
    assert(f.serverGems == 107 and f.worn == 777)
end)

local function requireForwardTractorPass(f)
    local physics = f.onWait
    f.onWait = function(dt)
        if f.world.riding and f.world.riding.harvest and f.controls.dir() ~= 0 then
            local y = math.floor(f.avatar.y-0.01)
            local direction = y == 4 and -1 or 1
            assert(f.controls.dir() == direction, "Tractor must not reverse along a row to revisit misses")
        end
        physics(dt)
    end
end

local function harvestPlantingFixture(seeds)
    local f = treeHarvestFixture("tractor")
    f.app.config.options.harvestPlanting = true
    f.app.config.planting = {seedId=955, storageWorld="BREAK", worlds={"FARM"}}
    f.app.config.rotation.farms.FARM = f.app.config.points.farmBox
    f.app.rotationState = {phase="harvest", worldIndex=1, cycle=1, work=0, seedCargo=0}
    f.app.job = "rotation"
    f.inventory:add(955, seeds)
    f.serverItems[955], f.seedPlants = seeds, {}
    f.app.runtime.handlers.canPlace = function(_, x, y)
        return not (f.deniedPlants and f.deniedPlants[y*f.world.w+x])
            and f.avatar.grounded and math.abs(f.avatar.x - (x+0.5)) <= 2.5
            and math.abs(y+0.5-(f.avatar.y-0.475)) <= 2.5
    end
    f.app.runtime.handlers.plantSeed = function(id, x, y)
        assert(id == 955 and f.world.fg[y][x] == 0 and f.serverItems[id] > 0)
        assert(f.app.controls.pausePickup, "Harvest planting must keep automatic pickups suspended")
        local saved = f.hooks.readRotationResume()
        local pending = saved.state.harvestPlant.pending
        local last = pending.tiles[#pending.tiles]
        assert(saved.state.phase == "harvest" and last.x == x and last.y == y,
            "The rotation must persist each harvest seed before planting")
        f.seedPlants[#f.seedPlants+1] = {x=x,y=y,avatarY=f.avatar.y,
            moving=math.abs(f.avatar.vx) > 0.8 and f.controls.dir() ~= 0,
            tractor=f.world.riding and f.world.riding.harvest or false}
        f.addTree(x,y,false)
        f.inventory:remove(id,1)
        if not f.refuseSeed then f.serverItems[id] = f.serverItems[id]-1 end
    end
    requireForwardTractorPass(f)
    return f
end

test("Rotation replants cleared trees while the Tractor keeps its forward zigzag pass", function()
    local f = harvestPlantingFixture(9)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees = 9
    f.harvest()
    assert(f.app.stats.trees==9 and f.app.stats.planted==9 and #f.seedPlants==9 and f.app.stats.stashed==90)
    local moving = 0
    for _,point in ipairs(f.seedPlants) do
        assert(point.tractor and math.floor(point.avatarY-0.01)==point.y)
        if point.moving then moving = moving+1 end
        assert(f.world.fg[point.y][point.x]==955 and not f.app.runtime.treeRipe(point.x,point.y,955))
    end
    assert(moving>=6, "Replanting should share the Tractor movement")
    assert(f.app.rotationState.harvestPlant.pending==nil and f.worn==777)
end)

test("Tractor gem pickups preserve seed confirmation during combined harvest planting", function()
    local f = harvestPlantingFixture(9)
    addTreeCurrency(f)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees = 9
    local accept, early = f.accept, 0
    f.accept = function(drop,want)
        if drop.id == 112 and f.world.riding and f.world.riding.harvest and #f.treeActions < 9 then early = early+1 end
        return accept(drop,want)
    end
    f.harvest()
    assert(early > 0 and f.app.stats.gems == 27 and f.serverGems == 127)
    assert(f.app.stats.trees == 9 and f.app.stats.planted == 9 and #f.seedPlants == 9)
    assert(f.app.stats.stashed == 90 and f.app.stats.stashedSeeds == 18 and f.serverItems[955] == 0)
    assert(f.app.rotationState.harvestPlant.pending == nil and f.worn == 777 and f.app.pending == 0)
end)

test("Retrying combined Tractor collection does not wait for its newly replanted trees", function()
    local f = harvestPlantingFixture(9)
    addTreeCurrency(f)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees = 9
    local physics, interrupted, allowCollection = f.onWait, false, false
    f.onWait = function(dt)
        if not allowCollection and f.app.harvestPhase == "Collecting blocks, seeds and gems" then
            interrupted = true
            error("Returning to the saved position timed out. Check the route.")
        end
        physics(dt)
    end
    rejects(f.harvest,"Returning to the saved position timed out")
    assert(interrupted and f.app.stats.planted == 9 and #f.drops > 0)
    allowCollection = true
    assert(f.harvest() ~= false, "Collection retries must finish the current harvest before the next maturity wait")
    assert(#f.drops == 0 and f.app.stats.stashed == 90 and f.app.stats.stashedSeeds == 18)
    assert(#f.treeActions == 9 and #f.seedPlants == 9 and f.app.stats.gems == 27)
end)

test("A collection checkpoint reload finishes Tractor blocks/seeds with growing replacements and full backpacks", function()
    local f = harvestPlantingFixture(36)
    addTreeCurrency(f)
    for _,y in ipairs({2,4,6}) do for x=2,13 do f.addTree(x,y) end end
    f.expectedTrees = 36
    local physics, allowCollection = f.onWait, false
    f.onWait = function(dt)
        if not allowCollection and f.app.harvestPhase == "Collecting blocks, seeds and gems" then
            error("Returning to the saved position timed out. Check the route.")
        end
        physics(dt)
    end
    rejects(f.harvest,"Returning to the saved position timed out")
    local runtime, saved = f.app.runtime, f.hooks.readRotationResume()
    assert(saved.state.harvestPass.world == "FARM" and saved.state.harvestPass.phase == "collect")
    assert(saved.state.harvestPlant.pending == nil and #f.seedPlants == 36)
    f.hooks = f.reload()
    f.app = f.hooks.App
    f.app.runtime, f.app.config, f.app.rotationState = runtime, saved.config, saved.state
    f.app.job, f.app.token, allowCollection = "rotation", 1, true
    f.worn, f.world.riding = 898, {harvest=true,speed=3.6}
    assert(f.harvest() ~= false)
    assert(#f.drops == 0 and #f.treeActions == 36 and #f.seedPlants == 36)
    assert(f.app.stats.stashed == 360 and f.app.stats.stashedSeeds == 72 and #f.deposits >= 3)
    assert(f.serverGems == 208 and f.app.pending == 0 and f.worn == 898)
end)

test("An approved partial Tractor pass resumes remaining trees despite its growing replanted rows", function()
    local f = harvestPlantingFixture(9)
    addTreeCurrency(f)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees = 9
    local physics, allowHarvest = f.onWait, false
    f.onWait = function(dt)
        if not allowHarvest and #f.seedPlants >= 3 then
            error("Returning to the saved position timed out. Check the route.")
        end
        physics(dt)
    end
    rejects(f.harvest,"Returning to the saved position timed out")
    assert(#f.treeActions >= 3 and #f.treeActions < 9 and #f.seedPlants >= 3)
    assert(f.hooks.readRotationResume().state.harvestPass.phase == "trees")
    allowHarvest = true
    assert(f.harvest() ~= false)
    assert(#f.drops == 0 and #f.treeActions == 9 and f.app.stats.stashed == 90 and f.app.stats.stashedSeeds == 18)
    assert(f.serverGems == 127 and f.app.pending == 0)
end)

test("Tractor misses are broken and replanted with Fist from the same lower position", function()
    local f = harvestPlantingFixture(9)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.tractorMissed,f.expectedTrees = {[2*f.world.w+7]=true,[6*f.world.w+7]=true},9
    f.harvest()
    assert(f.hits==2 and f.app.stats.trees==9 and f.app.stats.planted==9 and f.app.stats.stashed==90)
    local below = 0
    for _,point in ipairs(f.seedPlants) do
        if point.x==7 and (point.y==2 or point.y==6) then
            below = below+1
            assert(not point.tractor and math.floor(point.avatarY-0.01)==point.y+2,
                "Do not return to the upper row to replant a cleaned tree")
        end
    end
    assert(below==2 and f.worn==777)
end)

test("A rejected combined harvest seed retries from the next lower row without stopping collection", function()
    local f=harvestPlantingFixture(9)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees=9
    local plant,rejected,retries=f.app.runtime.handlers.plantSeed,false,0
    f.app.runtime.handlers.plantSeed=function(id,x,y)
        plant(id,x,y)
        if x==2 and y==2 then
            if not rejected then
                rejected=true
                f.world.fg[y][x],f.trees[y*f.world.w+x]=0,nil
                f.serverItems[id]=f.serverItems[id]+1
            else
                retries=retries+1
                assert(math.floor(f.avatar.y-0.01)==4)
            end
        end
    end
    f.harvest()
    assert(rejected and retries==1 and f.app.stats.planted==9 and f.app.stats.stashed==90)
    assert(#f.seedPlants==10 and f.app.rotationState.harvestPlant.pending==nil and f.worn==777)
end)

test("Dense tree rows harvest and replant through multiple seed batches without Tractor reversals", function()
    local f=harvestPlantingFixture(36)
    for _,y in ipairs({2,4,6}) do for x=2,13 do f.addTree(x,y) end end
    f.expectedTrees=36
    f.harvest()
    assert(f.app.stats.trees==36 and f.app.stats.planted==36 and #f.seedPlants==36 and f.app.stats.stashed==360)
    assert(f.app.rotationState.harvestPlant.pending==nil and f.worn==777)
end)

test("Running out of harvest planting seeds finishes harvesting without interrupting the row", function()
    local f = harvestPlantingFixture(2)
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.expectedTrees = 9
    f.harvest()
    assert(f.app.stats.trees==9 and f.app.stats.planted==2 and #f.seedPlants==2 and f.app.stats.stashed==90)
    assert(f.world.fg[6][13]==0 and f.serverItems[955]==0 and f.worn==777)
end)

test("Denied harvest planting leaves that cleared tile for normal replanting", function()
    local f = harvestPlantingFixture(3)
    for _,x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.deniedPlants,f.expectedTrees = {[2*f.world.w+7]=true},3
    f.harvest()
    assert(f.app.stats.planted==2 and f.app.stats.trees==3 and f.world.fg[2][7]==0)
    assert(f.hooks.Core.storageCount(f.boxes[12],955,954)==1)
end)

test("Unconfirmed harvest seed placements are skipped while harvesting and collection finish", function()
    local f = harvestPlantingFixture(1)
    f.addTree(2,2)
    f.refuseSeed,f.expectedTrees = true,1
    f.harvest()
    assert(f.app.stats.planted==0 and f.app.stats.stashed==10 and f.worn==777)
    assert(f.hooks.readRotationResume().state.harvestPlant.pending==nil)
    assert(f.app.plantingRecovery:find("skipped 1",1,true))
end)

test("An interrupted harvest seed reconciles even when only growing trees remain", function()
    local f = harvestPlantingFixture(2)
    f.addTree(2,2,false)
    f.app.rotationState.harvestPlant={worldIndex=1,phase="farm",skipped={},
        pending={world="FARM",x=2,y=2,before=3,tiles={{x=2,y=2}}}}
    f.harvest()
    assert(f.app.stats.planted==1 and #f.seedPlants==0 and #f.treeActions==0)
    assert(f.hooks.readRotationResume().state.harvestPlant.pending==nil)
end)

test("Stop during harvest planting restores footwear and leaves later trees untouched", function()
    local f = harvestPlantingFixture(3)
    for _,x in ipairs({2,7,13}) do f.addTree(x,2) end
    local plant = f.app.runtime.handlers.plantSeed
    f.app.runtime.handlers.plantSeed = function(id,x,y) plant(id,x,y); f.app:stop() end
    rejects(f.harvest,"Stopped")
    assert(#f.seedPlants==1 and f.world.fg[2][7]==955 and #f.requests==0 and f.worn==777)
end)

test("Tractor finishes each forward row and clears sparse misses with Fist from lower rows", function()
    local f = treeHarvestFixture("tractor")
    for _,y in ipairs({2,4,6}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.tractorMissed = {[2*f.world.w+7]=true,[6*f.world.w+7]=true}
    f.expectedTrees = 9
    requireForwardTractorPass(f)
    f.harvest()
    assert(f.hits == 2 and #f.treeActions == 9 and f.app.stats.trees == 9 and f.app.stats.stashed == 90)
    for _,point in ipairs(f.treeActions) do
        if not point.tractor then
            assert(point.x == 7 and math.floor(point.avatarY-0.01) == point.y+2,
                "Missed trees should be punched from the next lower row")
        end
    end
    assert(f.worn == 777 and f.app.pending == 0)
end)

test("Resumed Tractor harvesting walks to its work row before equipping the vehicle", function()
    local f=treeHarvestFixture("tractor")
    f.worn,f.world.riding=898,{harvest=true,speed=3.6}
    for _,x in ipairs({2,7,13}) do f.addTree(x,4) end
    f.expectedTrees=3
    local wear=f.app.runtime.harvestGear.wear
    f.app.runtime.harvestGear.wear=function(id)
        wear(id)
        if f.worn==898 and f.app.harvestPhase=="Breaking ripe trees" then
            assert(math.abs(f.avatar.x-14.5)<0.16 and math.abs(f.avatar.y-5)<0.22,
                "Equip Tractor only after reaching the row entry")
        end
    end
    local physics=f.onWait
    f.onWait=function(dt)
        if f.controls.dir()~=0 and f.world.riding and f.world.riding.harvest then
            assert(math.floor(f.avatar.y-0.01)==4,
                "Return travel must use walking speed; Tractor is only for the harvest pass at "
                    .. f.avatar.x .. ", " .. f.avatar.y .. "; phase " .. tostring(f.app.harvestPhase))
        end
        physics(dt)
    end
    f.harvest()
    assert(f.app.stats.trees==3 and f.app.stats.stashed==30 and f.worn==898)
end)

test("An empty lower row clears Tractor misses with Fist without equipping the vehicle", function()
    local f = treeHarvestFixture("tractor")
    for _,x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.tractorMissed,f.expectedTrees = {[2*f.world.w+7]=true},3
    requireForwardTractorPass(f)
    f.harvest()
    assert(f.hits == 1 and f.app.stats.trees == 3 and f.app.stats.stashed == 30)
    for _,action in ipairs(f.wearActions) do
        if action.worn == 898 then assert(math.floor(action.y-0.01) == 2) end
    end
    local point=f.treeActions[#f.treeActions]
    assert(not point.tractor and point.y==2 and math.floor(point.avatarY-0.01)==4)
end)

test("The lowest Tractor row uses the supported bottom floor for Fist cleanup", function()
    local f = treeHarvestFixture("tractor")
    for _,x in ipairs({2,7,13}) do f.addTree(x,6) end
    f.tractorMissed,f.expectedTrees = {[6*f.world.w+7]=true},3
    requireForwardTractorPass(f)
    f.harvest()
    assert(f.hits==1 and f.app.stats.trees==3 and f.app.stats.stashed==30)
    for _,point in ipairs(f.treeActions) do
        if not point.tractor then assert(point.y==6 and math.floor(point.avatarY-0.01)==8) end
    end
end)

test("Tractor misses use a normal Fist approach when no lower standing position exists", function()
    local f = treeHarvestFixture("tractor")
    f.world.h = 8
    f.world.fg[6][0],f.boxes[0] = 1422,{}
    f.app.config.points.farmBox = {world="FARM",x=0,y=6,standX=1,standY=6}
    f.avatar.x,f.avatar.y=1.5,6.999
    local server=f.server
    f.server=function(name,x,y,id,unused,unused2,n)
        if name~="DisplayItem" then return server(name,x,y,id,unused,unused2,n) end
        assert(x==0 and y==6 and id==954 and f.serverItems[id]>=n)
        f.serverItems[id]=f.serverItems[id]-n
        f.boxes[0]={{954,f.hooks.Core.itemCount(f.boxes[0],954)+n}}
        f.deposits[#f.deposits+1]=n
        return true
    end
    f.app.config.options.harvestRespawn=false
    for _,x in ipairs({2,7,13}) do f.addTree(x,6) end
    f.tractorMissed,f.expectedTrees = {[6*f.world.w+7]=true},3
    requireForwardTractorPass(f)
    f.harvest()
    assert(f.hits==1 and f.app.stats.trees==3 and f.app.stats.stashed==30)
    for _,point in ipairs(f.treeActions) do
        if not point.tractor then assert(math.floor(point.avatarY-0.01)==6) end
    end
    assert(f.worn==777)
end)

test("Refused Fist cleanup pauses Tractor harvesting before collecting any drops", function()
    local f=treeHarvestFixture("tractor")
    for _,x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.tractorMissed,f.fistRefused={[2*f.world.w+7]=true},true
    requireForwardTractorPass(f)
    rejects(f.harvest,"Fist did not harvest the missed tree")
    assert(f.hits==3 and #f.treeActions==2 and f.world.fg[2][7]==955)
    assert(#f.requests==0 and f.worn==777 and f.app.stats.trees==2)
end)

test("Stop during Fist cleanup prevents more Tractor passes and restores previous footwear", function()
    local f=treeHarvestFixture("tractor")
    for _,y in ipairs({2,4}) do for _,x in ipairs({2,7,13}) do f.addTree(x,y) end end
    f.tractorMissed={[2*f.world.w+7]=true}
    local hit=f.app.runtime.handlers.hit
    f.app.runtime.handlers.hit=function(x,y)
        hit(x,y)
        f.app:stop()
    end
    requireForwardTractorPass(f)
    rejects(f.harvest,"Stopped")
    assert(f.hits==1 and #f.requests==0 and f.worn==777 and f.app.controls==nil)
    assert(f.world.fg[4][2]==955, "Lower-row trees after the cleanup position must stay untouched after Stop")
end)

test("Changed missed trees are never punched as another crop during Tractor cleanup", function()
    local f=treeHarvestFixture("tractor")
    for _,x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.tractorMissed={[2*f.world.w+7]=true}
    local physics=f.onWait
    f.onWait=function(dt)
        physics(dt)
        if f.avatar.y>4 and #f.treeActions==2 then f.world.fg[2][7]=627 end
    end
    rejects(f.harvest,"missed tree was replaced")
    assert(not f.hits and f.world.fg[2][7]==627 and #f.requests==0 and f.worn==777)
end)

test("A growing tree prevents the Tractor from starting a partially ripe farm", function()
    local f=treeHarvestFixture("tractor")
    for _,x in ipairs({2,7,13}) do f.addTree(x,2) end
    f.addTree(5,2,false)
    f.tractorMissed,f.expectedTrees={[2*f.world.w+7]=true},3
    requireForwardTractorPass(f)
    assert(f.harvest()==false)
    assert(not f.hits and f.world.fg[2][5]==955 and f.app.stats.trees==0 and f.app.stats.stashed==0)
    assert(#f.treeActions==0 and #f.wearActions==0 and #f.requests==0)
    assert(f.worn==777)
end)

test("Both harvest methods wait for growing selected trees outside the detected farm rows", function()
    for _,method in ipairs({"fist","tractor"}) do
        local f=treeHarvestFixture(method)
        f.addTree(2,2)
        f.addTree(8,0,false)
        assert(f.harvest()==false)
        assert(#f.treeActions==0 and #f.requests==0 and #f.wearActions==0 and f.app.stats.trees==0)
        assert(f.app.status:find("Waiting for all trees",1,true) and f.app.harvestMaturity:find("1 growing",1,true))
    end
end)

test("A partially ripe farm starts harvesting only after its final tree matures", function()
    local f=treeHarvestFixture("fist")
    f.addTree(2,2)
    f.addTree(7,4,false)
    assert(f.harvest()==false and #f.treeActions==0)
    f.trees[4*f.world.w+7].p=0
    f.expectedTrees=2
    f.harvest()
    assert(f.hits==2 and f.app.stats.trees==2 and f.app.stats.stashed==20)
    assert(f.app.harvestMaturity:find("0 growing",1,true))
end)

test("An immature standalone farm neither collects old drops nor starts automatic Moving Drops", function()
    local f=treeHarvestFixture("fist")
    f.addTree(2,2)
    f.addTree(7,4,false)
    f.addDrop(1000,954,1,2.5,2.5)
    f.app.job=nil
    f.app.config.options.moveAfterHarvest=true
    installToggles(f)
    f.hooks.start("harvest")
    assert(not f.app.lastError,f.app.lastError)
    assert(f.app.job==nil and #f.treeActions==0 and #f.requests==0 and #f.deposits==0)
    assert(f.app.status:find("Waiting for all trees",1,true) and not f.app.runToggles.transfer.Value)
end)

test("Stop cancels the whole-world maturity scan before movement or harvesting", function()
    local f=treeHarvestFixture("fist")
    f.world.h=33
    f.addTree(2,2)
    f.onWait=function() f.app:stop() end
    rejects(f.harvest,"Stopped")
    assert(#f.treeActions==0 and #f.requests==0 and f.app.stats.trees==0)
end)

test("Growing trees alone do not cause harvest movement or punches", function()
    local f = treeHarvestFixture("fist")
    f.addTree(2, 2, false)
    local physics = f.onWait
    f.onWait = function(dt)
        assert(f.controls.dir() == 0 and not f.controls.jumping())
        physics(dt)
    end
    f.harvest()
    assert(not f.hits and #f.treeActions == 0 and #f.wearActions == 0 and #f.requests == 0)
end)

test("Tractor requires ownership and rejects mixed seed farms before moving or changing clothing", function()
    local f = treeHarvestFixture("tractor")
    f.addTree(2, 2)
    f.inventory:remove(898, 1)
    f.serverItems[898] = 0
    rejects(f.harvest, "Tractor is not in the backpack")
    assert(#f.treeActions == 0 and #f.wearActions == 0 and #f.requests == 0)
    f.inventory:add(898, 1)
    f.serverItems[898] = 1
    f.app.runtime.items[627] = {kind = "seed", grow = 100}
    f.addTree(3, 4, false, 627)
    rejects(f.harvest, "another seed type")
    assert(#f.treeActions == 0 and #f.wearActions == 0 and f.worn == 777)
end)

test("A refused Fist harvest pauses before any drops are collected", function()
    local f = treeHarvestFixture("fist")
    f.addTree(2, 2)
    f.refuseTree = true
    rejects(f.harvest, "Fist did not harvest")
    assert(f.hits == 3 and f.world.fg[2][2] == 955 and #f.requests == 0 and f.worn == 777)
end)

test("Stop during tractor harvesting restores clothing and prevents further tree actions or pickups", function()
    local f = treeHarvestFixture("tractor")
    f.addTree(2, 2)
    f.addTree(7, 2)
    local physics = f.onWait
    f.onWait = function(dt)
        physics(dt)
        if #f.treeActions == 1 then f.app:stop() end
    end
    rejects(f.harvest, "Stopped")
    assert(#f.treeActions == 1 and f.world.fg[2][7] == 955 and #f.requests == 0)
    assert(f.worn == 777 and f.app.controls == nil)
end)

test("Fist removes an already-worn tractor and harvests only the selected crop", function()
    local f = treeHarvestFixture("fist")
    f.addTree(2, 2)
    f.app.runtime.items[627] = {name = "Other Seed", kind = "seed", grow = 100}
    f.addTree(7, 4, true, 627)
    f.worn, f.world.riding = 898, {harvest = true, speed = 3.6}
    f.expectedTrees = 1
    f.harvest()
    assert(f.hits == 1 and not f.treeActions[1].tractor and f.world.fg[4][7] == 627)
    assert(f.worn == 898 and f.app.stats.trees == 1)
end)

test("Missing tree growth data refuses harvest before movement or pickup", function()
    local f = treeHarvestFixture("fist")
    f.addTree(2, 2)
    f.trees[2 * f.world.w + 2] = nil
    rejects(f.harvest, "growth data is not ready")
    assert(not f.hits and #f.wearActions == 0 and #f.requests == 0)
end)

test("Tree and equipment discovery binds shared native upvalues, including empty metadata", function()
    local f = fixture()
    f.services.Workspace.GetServerTimeNow = function() return 1000 end
    local items, world, trees, renders, worn = f.app.runtime.items, f.world, {}, {}, {feet = 898}
    prepareDiscovery(f, true)
    attachWorldHandlers(f, items)
    local ripe = function(id, tree) return 1000 >= tree.p + (items[id].grow or 0) end
    local gear = {
        onWear = function(id) assert(world.fg); worn.feet = id end,
        isWorn = function(id) return worn.feet == id end,
    }
    world.ride = function() assert(world.fg); return trees, ripe, gear end
    local setTree = function(x, y, tree) trees[y * world.w + x] = tree; renders[x] = nil end
    local oldInfo = getinfo
    getinfo = function(fn)
        if fn == ripe then return {name = "treeRipe"} end
        if fn == setTree then return {name = "setTree"} end
        return oldInfo(fn)
    end
    table.insert(f.discoveryObjects, setTree)
    local r = f.hooks.connectGame()
    assert(r.treeRipe and r.harvestGear and r.harvestGear.feet() == 898)
    assert(r.treeRipe(2, 2, 955) == nil, "Empty metadata must not imply a ripe tree")
    setTree(2, 2, {p = 0})
    assert(r.treeRipe(2, 2, 955) == true)
    setTree(2, 2, {p = 2000})
    assert(r.treeRipe(2, 2, 955) == false)
    assert(r.treeRemaining(2, 2, 955) == 1000)
    r.harvestGear.wear(777)
    assert(worn.feet == 777)
    local transfer = f.hooks.connectGame({transferOnly = true})
    assert(transfer.treeRipe == nil and transfer.harvestGear == nil and transfer.farmingDeferred)
end)

test("Harvest follows top-left zigzag rows and lands at both platform edges", function()
    local f = zigzagHarvestFixture()
    for row = 1, 3 do
        for column, x in ipairs({2, 7, 13}) do f.addDrop(row * 10 + column, 954, 5, x + 0.5, row * 2 + 0.5) end
    end
    f.harvest()
    assert(table.concat(f.accepted, ",") == "11,12,13,23,22,21,31,32,33", table.concat(f.accepted, ","))
    for _, tile in ipairs({"1:2", "14:2", "14:4", "1:4", "1:6"}) do
        assert(f.visited[tile], "The zigzag must visit " .. tile)
    end
    assert(#f.drops == 0 and f.app.stats.stashed == 45 and f.respawns == 1)
end)

local function watchForwardCollection(f)
    local physics, accept, started, progress = f.onWait,f.accept,{},{}
    f.accept = function(drop,want)
        local amount = accept(drop,want)
        if amount > 0 then started[math.floor(drop.y)] = true end
        return amount
    end
    f.onWait = function(dt)
        physics(dt)
        local y = math.floor(f.avatar.y-0.01)
        if y >= 2 and y <= 6 and y%2 == 0 then
            local active = f.app.status:find("Collecting farm row",1,true) and f.app.status:find(" at " .. y .. "...",1,true)
            local live = false
            for _,drop in ipairs(f.drops) do if math.floor(drop.y) == y then live=true; break end end
            if active and started[y] and live and f.avatar.grounded then
                local direction = (y/2)%2 == 1 and 1 or -1
                local forward = f.avatar.x*direction
                if progress[y] then assert(forward >= progress[y]-0.3,
                    "Collection reversed along row " .. y .. " instead of finishing its forward pass") end
                progress[y] = math.max(progress[y] or forward,forward)
            elseif not active then progress[y] = nil end
        end
    end
end

test("Delayed row pickups keep one zigzag direction instead of crossing the row and returning", function()
    local f = zigzagHarvestFixture()
    for row=1,3 do for column,x in ipairs({2,7,13}) do
        f.addDrop(row*10+column,954,5,x+0.5,row*2+0.5)
    end end
    local physics, progress, delayed = f.onWait, {}, false
    f.onWait = function(dt)
        physics(dt)
        local y = math.floor(f.avatar.y-0.01)
        local row = y/2
        if row >= 1 and row <= 3 and row == math.floor(row) then
            local direction = row%2 == 1 and 1 or -1
            local entry = direction == 1 and "1:" .. y or "14:" .. y
            local live, started = false, false
            for _,uid in ipairs(f.accepted) do if uid == row*10+(direction == 1 and 1 or 3) then started=true; break end end
            for _,drop in ipairs(f.drops) do if math.floor(drop.y) == y then live=true; break end end
            if started and f.visited[entry] and live then
                local forward = f.avatar.x*direction
                if progress[row] then assert(forward >= progress[row]-0.3,
                    "Collection reversed along row " .. y .. " instead of finishing its forward pass") end
                progress[row] = math.max(progress[row] or forward,forward)
            end
        end
        if not delayed then
            for _,drop in ipairs(f.drops) do
                if drop.uid == 12 and f.hooks.Navigation.pickupOverlap(f.avatar,drop) then
                    delayed,drop.pending,drop.readyAt = true,true,os.clock()+1
                end
            end
        end
        for _,drop in ipairs(f.drops) do
            if drop.uid == 12 and delayed and os.clock() >= drop.readyAt then drop.pending=false end
        end
    end
    f.harvest()
    assert(delayed and table.concat(f.accepted,",") == "11,12,13,23,22,21,31,32,33")
    assert(#f.drops == 0 and f.app.stats.stashed == 45 and f.app.pending == 0)
end)

test("Clustered partial pickups finish in one forward pass with at most eight delayed requests", function()
    local f = zigzagHarvestFixture()
    for row=1,3 do
        f.addDrop(row*1000,954,1,2.5,row*2+0.5)
        for n=1,12 do
            f.addDrop(row*1000+n,954,3,7.5,row*2+0.5)
            f.addDrop(row*1000+100+n,955,1,7.5,row*2+0.5)
            f.addDrop(row*1000+200+n,112,1,7.5,row*2+0.5)
        end
        f.addDrop(row*1000+999,954,1,13.5,row*2+0.5)
    end
    local accept, peak, queued, physics = f.accept,0,{},f.onWait
    f.accept = function(drop,want) return accept(drop,math.min(want,1)) end
    f.spawn = function(fn)
        peak = math.max(peak,f.app.pending)
        queued[#queued+1] = {fn=fn,at=os.clock()+0.15}
    end
    f.onWait = function(dt)
        physics(dt)
        local ready = {}
        for index=#queued,1,-1 do
            if queued[index].at <= os.clock() then ready[#ready+1]=queued[index].fn; table.remove(queued,index) end
        end
        for _,fn in ipairs(ready) do fn() end
    end
    watchForwardCollection(f)
    f.harvest()
    assert(peak <= 8 and #queued == 0 and f.app.pending == 0 and #f.drops == 0)
    assert(f.app.stats.stashed == 114 and f.app.stats.stashedSeeds == 36 and f.app.stats.gems == 36)
end)

test("Inventory confirmations stop forward steering while slow replies settle instead of skipping row drops", function()
    local f = zigzagHarvestFixture()
    for row=1,3 do for x=2,13 do f.addDrop(row*100+x,954,1,x+0.5,row*2+0.5) end end
    local server = f.server
    f.server = function(name,...)
        if name == "GetInventory" then task.wait(0.35) end
        return server(name,...)
    end
    watchForwardCollection(f)
    f.harvest()
    assert(#f.drops == 0 and f.app.stats.stashed == 36 and f.app.pending == 0)
end)

test("A low-FPS forward collection pass brakes before passing a delayed row drop", function()
    local f = zigzagHarvestFixture()
    for row=1,3 do for column,x in ipairs({2,7,13}) do f.addDrop(row*10+column,954,2,x+0.5,row*2+0.5) end end
    local wait, physics, delayed = task.wait,f.onWait,false
    task.wait = function(dt) return wait(math.max(dt or 0.03,1/12)) end
    f.spawn = function(fn) task.defer(fn) end
    f.onWait = function(dt)
        physics(dt)
        for _,drop in ipairs(f.drops) do
            if drop.uid == 12 then
                if not delayed and f.hooks.Navigation.pickupOverlap(f.avatar,drop) then
                    delayed,drop.pending,drop.readyAt = true,true,os.clock()+1
                end
                if delayed and os.clock() >= drop.readyAt then drop.pending=false end
            end
        end
    end
    watchForwardCollection(f)
    f.harvest()
    task.wait = wait
    assert(delayed and table.concat(f.accepted,",") == "11,12,13,23,22,21,31,32,33")
    assert(#f.drops == 0 and f.app.stats.stashed == 18 and f.app.pending == 0)
end)

test("Genuine pickup refusals retry in reach during the forward row pass", function()
    local f = zigzagHarvestFixture()
    for row=1,3 do for column,x in ipairs({2,7,13}) do f.addDrop(row*10+column,954,2,x+0.5,row*2+0.5) end end
    local accept, refused = f.accept,{}
    f.accept = function(drop,want)
        if not refused[drop.uid] then refused[drop.uid]=os.clock(); return 0 end
        assert(os.clock()-refused[drop.uid] >= 1)
        return accept(drop,want)
    end
    watchForwardCollection(f)
    f.harvest()
    assert(table.concat(f.accepted,",") == "11,12,13,23,22,21,31,32,33")
    assert(#f.drops == 0 and #f.requests == 18 and f.app.stats.stashed == 18)
end)

test("A large gem UID keeps making pickup progress during a forward wait longer than the action timeout", function()
    local f = zigzagHarvestFixture()
    f.addDrop(1,112,1,2.5,2.5)
    f.addDrop(2,112,100000,7.5,2.5)
    f.addDrop(3,112,1,13.5,2.5)
    local accept = f.accept
    f.accept = function(drop,want)
        task.wait(0.15)
        return accept(drop,math.min(want,1000))
    end
    watchForwardCollection(f)
    f.harvest()
    assert(os.clock() > f.app.config.options.actionTimeout and #f.drops == 0)
    assert(f.app.stats.gems == 100002 and f.serverGems == 100102 and f.app.pending == 0)
    assert(#f.deposits == 0)
end)

test("A full harvest backpack returns to its current row after respawn without skipping a partial stack", function()
    local f = zigzagHarvestFixture()
    f.addDrop(11, 954, 10, 2.5, 2.5)
    f.addDrop(12, 954, 250, 7.5, 2.5)
    f.addDrop(13, 954, 10, 13.5, 2.5)
    f.addDrop(21, 954, 10, 2.5, 4.5)
    f.addDrop(23, 954, 10, 13.5, 4.5)
    f.harvest()
    assert(table.concat(f.accepted, ",") == "11,12,12,13,23,21", table.concat(f.accepted, ","))
    assert(#f.drops == 0 and f.app.stats.stashed == 290 and f.respawns == 2)
    assert(f.deposits[1] == 200 and f.deposits[2] == 90 and f.app.pending == 0)
end)

test("Harvest skips an empty upper row and starts the first occupied row from the left", function()
    local f = zigzagHarvestFixture()
    f.addDrop(21, 954, 10, 2.5, 4.5)
    f.addDrop(23, 954, 10, 13.5, 4.5)
    f.harvest()
    assert(table.concat(f.accepted, ",") == "21,23")
    assert(not f.visited["1:2"] and not f.visited["14:2"] and f.visited["1:4"])
    assert(not table.concat(f.app.logs, "\n"):find("Collecting farm row 1/", 1, true))
end)

test("Harvest with no selected loose or held blocks completes without walking or respawning", function()
    for _, otherDrops in ipairs({false, true}) do
        local f = zigzagHarvestFixture()
        f.avatar.x, f.avatar.y = 3.5, 6.999
        if otherDrops then
            f.addDrop(1, 18, 10, 2.5, 2.5)
            f.addDrop(2, 1, 10, 13.5, 4.5)
            local display = f.addDrop(3, 954, 10, 7.5, 2.5)
            display.display = true
        end
        local physics = f.onWait
        f.onWait = function(dt)
            assert(f.controls.dir() == 0 and not f.controls.jumping(), "Empty harvest must not request movement")
            physics(dt)
        end
        f.harvest()
        assert(f.avatar.x == 3.5 and math.abs(f.avatar.y - 6.999) < 0.001)
        assert(#f.requests == 0 and #f.deposits == 0 and f.respawns == 0)
        assert(f.app.status:find("Finished collecting harvest", 1, true))
    end
end)

test("The next occupied row reverses after an empty middle row without crossing it to find its entry", function()
    local f = zigzagHarvestFixture()
    f.addDrop(11, 954, 10, 2.5, 2.5)
    f.addDrop(13, 954, 10, 13.5, 2.5)
    f.addDrop(31, 954, 10, 2.5, 6.5)
    f.addDrop(33, 954, 10, 13.5, 6.5)
    f.addDrop(21, 18, 10, 7.5, 4.5)
    local physics = f.onWait
    f.onWait = function(dt)
        physics(dt)
        local topFinished, lowerStarted = false,false
        for _,uid in ipairs(f.accepted) do
            if uid == 13 then topFinished=true elseif uid == 33 then lowerStarted=true end
        end
        if topFinished and not lowerStarted and f.avatar.grounded and math.floor(f.avatar.y-0.01) == 6 then
            assert(f.avatar.x >= 12.9, "The next row must collect from the arrival side, not cross it to start again")
        end
    end
    f.harvest()
    assert(table.concat(f.accepted, ",") == "11,13,33,31")
    assert(not table.concat(f.app.logs, "\n"):find("Collecting farm row 2/", 1, true))
    assert(#f.drops == 1 and f.drops[1].id == 18 and f.app.stats.stashed == 40)
end)

test("Harvest stops crossing the last occupied row as soon as its only stack is gone", function()
    local f = zigzagHarvestFixture()
    f.addDrop(11, 954, 10, 7.5, 2.5)
    local respawn = f.app.runtime.respawn
    f.app.runtime.respawn = function()
        assert(math.abs(f.avatar.x - 7.5) < 0.6, "The cleared row must not be crossed to its empty far edge")
        return respawn()
    end
    f.harvest()
    assert(f.respawns == 1 and f.app.stats.stashed == 10 and #f.drops == 0)
    assert(not f.visited["14:2"])
end)

test("Harvest cancels positioning when its destination row loses its last floating block", function()
    local f = zigzagHarvestFixture()
    f.addDrop(11, 954, 10, 7.5, 2.5)
    local physics, cleared = f.onWait, false
    f.onWait = function(dt)
        physics(dt)
        if not cleared and f.avatar.y < 7.5 then
            cleared = true
            for index = #f.drops, 1, -1 do table.remove(f.drops, index) end
        end
    end
    f.harvest()
    assert(cleared and not f.visited["1:2"] and not f.visited["14:2"])
    assert(#f.requests == 0 and #f.deposits == 0 and f.respawns == 0)
end)

test("An empty harvest still stores selected blocks already held without inspecting farm rows", function()
    local f = zigzagHarvestFixture()
    f.avatar.x, f.avatar.y = 3.5, 6.999
    f.inventory:add(954, 20)
    f.serverItems[954] = 20
    f.harvest()
    assert(#f.requests == 0 and #f.deposits == 1 and f.deposits[1] == 20 and f.respawns == 1)
    assert(not f.visited["1:2"] and not f.visited["14:2"] and f.app.stats.stashed == 20)
end)

test("Harvest stashes a backpack filled by the last stack before travelling to another row", function()
    local f = zigzagHarvestFixture()
    f.addDrop(11, 954, 200, 7.5, 2.5)
    f.addDrop(21, 954, 20, 2.5, 4.5)
    local respawn = f.app.runtime.respawn
    f.app.runtime.respawn = function()
        if f.respawns == 0 then
            assert(math.abs(f.avatar.y - 3) < 0.22 and math.abs(f.avatar.x - 7.5) < 0.6,
                "A full backpack must be stored before travelling to the next row")
        end
        return respawn()
    end
    f.harvest()
    assert(f.app.stats.stashed == 220 and f.deposits[1] == 200 and f.deposits[2] == 20 and f.respawns == 2)
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

test("A nearby harvest drop retries from a fractional supported position when no tile center overlaps it", function()
    local f = harvestFixture()
    local map = harvestFloor(f)
    for x = 0,f.world.w-1 do f.world.fg[9][x] = (x == 9 or x == 10 or x == 12) and 1 or 0 end
    f.avatar.x = 9.05
    attachPhysics(f,map)
    local drop = f.addDrop(26,954,20,8.5,8.5)
    local goal = f.hooks.Navigation.pickupGoal(map,f.avatar,drop,{nativeOnly=true})
    assert(not goal and f.hooks.Navigation.pickupOverlap(f.avatar,drop),
        "Fixture must reproduce native reach without a supported tile-center pickup goal")
    f.accept = function(candidate,want)
        if #f.requests == 1 then return 0 end -- A temporary server refusal needs a retry.
        assert(f.hooks.Navigation.pickupOverlap(f.avatar,candidate), "Retry must use actual native overlap")
        return want
    end
    f.harvest()
    assert(#f.requests == 2 and f.requests[2].time-f.requests[1].time >= 1)
    assert(#f.drops == 0 and f.app.stats.stashed == 20 and f.app.pending == 0)
    assert(f.app.harvestCollectionRecovery:find("current supported position",1,true))
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
    attachPhysics(f, harvestFloor(f))
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
    f.doors, f.entries = 0, 0
    f.world.displays.get = function(x) return f.worldBoxes[f.world.name][x] or {} end
    f.world.enter = function(name)
        assert(name == "FARM" or name == "BREAK")
        assert(f.app.stats.stashed > 0 and #f.drops == 0, "Transfer must wait for all harvest drops to be stored")
        f.entries = f.entries+1
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
    assert(not f.app.lastError and f.app.job == nil and f.doors == 0 and f.entries == 2)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12], 954) == 23)
    assert(f.app.stats.harvested == 23 and f.app.stats.stashed == 23 and f.app.stats.moved == 23)
    assert(not f.app.runToggles.harvest.Value and not f.app.runToggles.transfer.Value)
    assert(f.app.runToggles.transfer.history[1] == true and not f.hooks.readPNBResume())
    local record = f.files["ClarisGrowblox/accounts/1234/resume.json"]
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

test("Two accounts sharing executor files keep concurrent session staging and backups separate", function()
    local storage = {files={}, encoded={}, serial=0}
    local first, second = fixture(1234, storage), fixture(5678, storage)
    first.app.config.options.placeDelay, second.app.config.options.placeDelay = 0.3, 0.7
    first.activate()
    local rawWrite, interleave = writefile
    interleave = function(path, value)
        if path == first.app.dataFolder .. "/session.json.pending" then
            second.activate()
            second.hooks.saveSession()
            first.activate()
            writefile = interleave
        end
        rawWrite(path, value)
    end
    writefile = interleave
    first.hooks.saveSession()
    first.activate()
    first.app.config.options.placeDelay = 0.4
    first.hooks.saveSession()
    second.activate()
    second.app.config.options.placeDelay = 0.8
    second.hooks.saveSession()
    local http = second.services.HttpService
    assert(http:JSONDecode(storage.files[first.app.dataFolder .. "/session.json"]).config.options.placeDelay == 0.4)
    assert(http:JSONDecode(storage.files[second.app.dataFolder .. "/session.json"]).config.options.placeDelay == 0.8)
    assert(http:JSONDecode(storage.files[first.app.dataFolder .. "/session.json.bak"]).config.options.placeDelay == 0.3)
    assert(http:JSONDecode(storage.files[second.app.dataFolder .. "/session.json.bak"]).config.options.placeDelay == 0.7)
    assert(storage.files[first.app.dataFolder .. "/session.json.pending"] == nil)
    assert(storage.files[second.app.dataFolder .. "/session.json.pending"] == nil)
    first.activate()
    assert(first.reload().App.config.options.placeDelay == 0.4)
    second.activate()
    assert(second.reload().App.config.options.placeDelay == 0.8)
end)

test("Same profile names, exports, checkpoints and clearing stay separate on a shared device", function()
    local storage = {files={}, encoded={}, serial=0}
    local first, second = fixture(1234, storage), fixture(5678, storage)
    for index, f in ipairs({first,second}) do
        f.activate()
        f.app.job = nil
        f.app.config.planting = {seedId=955,storageWorld="BREAK",worlds={"FARM"}}
        f.app.config.points.plantBox = f.app.config.points.seedBox
        f.app.config.points.pnb.x = index == 1 and 10 or 15
        f.app.config.rotation.farms.FARM = f.app.config.points.farmBox
        local text, record = f.hooks.exportConfiguration()
        f.hooks.importConfiguration(text, "Shared Name")
        f.hooks.saveConfigExport(record)
        f.hooks.savePNBResume()
        f.hooks.savePlantResume({phase="farm",worldIndex=1,skipped={}})
        f.hooks.saveRotationResume({phase=index == 1 and "drainPNB" or "wait",worldIndex=1,cycle=index,work=20,seedCargo=0})
        f.files[f.app.dataFolder .. "/resume.json"] = "private transfer " .. index
    end
    first.activate()
    assert(first.hooks.readRotationResume().state.phase == "drainPNB")
    assert(first.hooks.readPNBResume().config.points.pnb.x == 10)
    first.hooks.clearRotationResume()
    local ownExport = first.services.HttpService:JSONDecode(first.files[first.app.dataFolder .. "/exports/Default.json"])
    assert(ownExport.config.points.pnb.x == 10)
    second.activate()
    assert(second.hooks.readRotationResume().state.phase == "wait")
    assert(second.hooks.readPlantResume().state.worldIndex == 1)
    assert(second.hooks.readPNBResume().config.points.pnb.x == 15)
    local profile = second.services.HttpService:JSONDecode(second.files[second.app.dataFolder .. "/profiles/Shared Name.json"])
    assert(profile.points.pnb.x == 15 and second.files[second.app.dataFolder .. "/resume.json"] == "private transfer 2")
    first.activate()
    local text = first.hooks.exportConfiguration()
    first.hooks.importConfiguration(text, "New Setup")
    second.activate()
    assert(second.hooks.readRotationResume() and second.hooks.readPNBResume() and second.hooks.readPlantResume())
    assert(second.files[second.app.dataFolder .. "/resume.json"] == "private transfer 2")
end)

test("Legacy migration copies only owned records and recovers a profile from its owned session snapshot", function()
    local f = fixture()
    f.app.profile = "Same Name"
    f.hooks.saveSession()
    f.hooks.savePNBResume()
    local session, checkpoint = f.files[f.app.dataFolder .. "/session.json"], f.files[f.app.dataFolder .. "/pnb-resume.json"]
    f.files["ClarisGrowblox/session.json"], f.files["ClarisGrowblox/pnb-resume.json"] = session, checkpoint
    f.files["ClarisGrowblox/resume.json"] = f.services.HttpService:JSONEncode({version=1,userId=5678,active=false})
    f.files["ClarisGrowblox/plant-resume.json"] = "broken legacy JSON"
    local otherConfig = f.hooks.Core.defaults(); otherConfig.blockId=628
    f.files["ClarisGrowblox/profiles/Same Name.json"] = f.services.HttpService:JSONEncode(otherConfig)
    f.files[f.app.dataFolder .. "/session.json"], f.files[f.app.dataFolder .. "/pnb-resume.json"] = nil, nil
    f.files[f.app.dataFolder .. "/migration.json"] = nil
    local next = f.reload()
    assert(next.App.profile == "Same Name" and next.App.config.blockId == 954 and not next.App.storageMigrationError)
    assert(next.readPNBResume().userId == 1234 and next.App.migratedFiles == 2)
    assert(f.services.HttpService:JSONDecode(f.files[next.App.dataFolder .. "/profiles/Same Name.json"]).blockId == 954)
    assert(f.files[next.App.dataFolder .. "/resume.json"] == nil and f.files[next.App.dataFolder .. "/plant-resume.json"] == nil)
    assert(f.files["ClarisGrowblox/session.json"] == session and f.files["ClarisGrowblox/pnb-resume.json"] == checkpoint)
    next.App:stop()
    assert(f.reload().readPNBResume() == nil, "Cleared migrated work must never be resurrected from the legacy file")
    local other = fixture(5678, f.storage)
    assert(other.app.config.blockId == 954 and other.app.sessionRestoreError == nil)
    -- fixture sets block selection for test setup, but no foreign session/profile was loaded.
    assert(other.app.profile == "Default" and other.files[other.app.dataFolder .. "/session.json"] == nil)
    assert(other.files[other.app.dataFolder .. "/pnb-resume.json"] == nil)
    assert(other.files[other.app.dataFolder .. "/resume.json"] and other.app.migratedFiles == 1)
end)

test("An existing account setup wins over legacy files and account swaps cannot inherit the old app", function()
    local f = fixture()
    f.app.profile, f.app.config.options.collectDelay = "Account One", 0.4
    f.hooks.saveSession()
    local legacy = f.hooks.Core.defaults(); legacy.options.collectDelay=0.9
    f.files["ClarisGrowblox/session.json"] = f.services.HttpService:JSONEncode({version=1,userId=1234,config=legacy,profile="Legacy"})
    f.files[f.app.dataFolder .. "/migration.json"] = nil
    assert(f.reload().App.config.options.collectDelay == 0.4)
    f.player.UserId = 5678
    local next = f.reload(true)
    assert(next.App.userId == 5678 and next.App.profile == "Default" and next.App.config.blockId == 0)
    assert(not next.App.sessionRestoreError)
    f.player.UserId = 1234
    assert(f.reload(true).App.profile == "Account One")
end)

test("An interrupted legacy migration retries without overwriting copied settings or losing the active profile", function()
    local f = fixture()
    f.app.profile = "Migration Retry"
    f.hooks.saveSession()
    local session = f.files[f.app.dataFolder .. "/session.json"]
    f.files["ClarisGrowblox/session.json"] = session
    f.files[f.app.dataFolder .. "/session.json"], f.files[f.app.dataFolder .. "/migration.json"] = nil, nil
    local rawWrite = writefile
    writefile = function(path,value)
        if path:find("/profiles/",1,true) then error("disk full during profile migration") end
        rawWrite(path,value)
    end
    local next = f.reload()
    assert(next.App.storageMigrationError:find("disk full",1,true))
    assert(next.App.profile == "Migration Retry" and next.App.config.blockId == 954)
    assert(f.files[next.App.dataFolder .. "/migration.json"] == nil)
    writefile = rawWrite
    next = f.reload()
    assert(not next.App.storageMigrationError and next.App.profile == "Migration Retry")
    assert(f.files[next.App.dataFolder .. "/profiles/Migration Retry.json"])
    assert(f.files[next.App.dataFolder .. "/migration.json"] and f.files["ClarisGrowblox/session.json"] == session)
end)

test("A changed account cannot write configuration into the previous account folder", function()
    local f = fixture()
    f.hooks.saveSession()
    local saved = f.files[f.app.dataFolder .. "/session.json"]
    f.player.UserId = 5678
    rejects(f.hooks.saveSession, "account changed")
    rejects(function() f.hooks.checkpoint(1) end, "account changed")
    assert(f.files[f.app.dataFolder .. "/session.json"] == saved)
end)

test("A session from another account or a damaged profile cannot replace defaults", function()
    local f = fixture()
    f.hooks.saveSession()
    f.player.UserId = 888
    local next = f.reload()
    assert(next.App.config.blockId == 0 and next.App.sessionRestoreError == nil and next.App.userId == 888)
    f.player.UserId = 1234
    local record = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/session.json"])
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

local function zigzagPlantingFixture(seeds, worlds)
    local f = plantingFixture(seeds, 100, worlds)
    f.app.runtime.items[102] = {platform = true}
    local grid = f.grids.FARM1
    for y = 0, 7 do
        for x = 0, 6 do
            grid[y][x] = (y == 2 or y == 4 or y == 6) and x >= 1 and x <= 5
                and ((x == 1 or x == 5) and 102 or 2) or 0
        end
    end
    f.avatar.x, f.avatar.y = 3.5, 5.999
    f.controls.dir, f.controls.jumping = function() return 0 end, function() return false end
    f.onEnter = function(name)
        if name == "FARM1" then f.avatar.x, f.avatar.y = 3.5, 5.999 end
        return true
    end
    return f
end

local function wideZigzagPlantingFixture(seeds)
    local f = zigzagPlantingFixture(seeds)
    f.world.w = 34
    for _, grid in pairs(f.grids) do
        for y = 0, 7 do for x = 7, 33 do grid[y][x] = y == 6 and 2 or 0 end end
    end
    for y = 0, 7 do
        for x = 0, 33 do
            f.grids.FARM1[y][x] = (y == 2 or y == 4 or y == 6) and x >= 1 and x <= 32
                and ((x == 1 or x == 32) and 102 or 2) or 0
        end
    end
    f.avatar.x, f.avatar.y = 17.5, 5.999
    f.onEnter = function(name)
        if name == "FARM1" then f.avatar.x, f.avatar.y = 17.5, 5.999 end
        return true
    end
    return f
end

test("Planting streams a long row in order with moving placements and bounded saved batches", function()
    local f = plantingFixture(40, 100)
    f.world.w = 32
    for _, grid in pairs(f.grids) do
        for y = 0, 7 do for x = 7, 31 do grid[y][x] = y == 6 and 2 or 0 end end
    end
    local server, reads, moving, previous, largest = f.server, 0, 0, nil, 0
    f.server = function(name, ...)
        if name == "GetInventory" then reads = reads + 1 end
        return server(name, ...)
    end
    f.onPlant = function(_, x)
        local pending = f.hooks.readPlantResume().state.pending
        assert(pending.tiles[#pending.tiles].x == x, "Each attempted tile must be saved before planting")
        largest = math.max(largest, #pending.tiles)
        assert(#pending.tiles <= 8)
        if math.abs(f.avatar.vx) > 0.8 then moving = moving + 1 end
        if previous then assert(os.clock() - previous >= 0.2 - 0.000001, "Native cooldown must be respected") end
        previous = os.clock()
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 32 and f.app.stats.planted == 32 and f.serverSeeds == 8)
    for index, point in ipairs(f.plantCalls) do assert(point.x == index - 1 and point.y == 5) end
    assert(moving >= 24, "Most seeds should be placed while moving, rather than after centering")
    assert(largest == 8 and reads <= 8, "Inventory checks should confirm batches instead of each tile")
end)

test("A delayed planting inventory reply holds the next batch until all eight seeds confirm", function()
    local f = plantingFixture(20, 100)
    f.world.w = 12
    for y = 0, 7 do for x = 7, 11 do f.grids.FARM1[y][x] = y == 6 and 2 or 0 end end
    local server, delayed, confirmed = f.server, false, false
    f.server = function(name, ...)
        if name == "GetInventory" and #f.plantCalls == 8 then
            if not delayed then
                delayed = true
                assert(f.app.controls.direction == 0)
                return {slots = {{955, 20}}, capacity = 54}
            end
            confirmed = true
        end
        return server(name, ...)
    end
    f.onPlant = function() if #f.plantCalls > 8 then assert(confirmed, "Do not start another optimistic batch") end end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(delayed and confirmed and #f.plantCalls == 12 and f.app.stats.planted == 12 and f.serverSeeds == 8)
end)

test("A partially rejected planting batch keeps accepted seeds and continues past rejected tiles", function()
    local f = plantingFixture(10, 100)
    f.onPlant = function()
        if #f.plantCalls == 3 then
            f.onPlant = nil
            f.grids.FARM1[5][1], f.serverSeeds = 0, f.serverSeeds + 1
        end
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.serverSeeds == 4 and f.app.stats.planted == 6 and #f.plantCalls == 7)
    local occurrences = {}
    for _, point in ipairs(f.plantCalls) do occurrences[point.x] = (occurrences[point.x] or 0) + 1 end
    assert(occurrences[0] == 1 and occurrences[1] == 1 and occurrences[2] == 1)
    assert(f.grids.FARM1[5][1]==0 and f.hooks.readPlantResume()==nil)
end)

local function rejectedUpperFixture(seeds)
    local f=zigzagPlantingFixture(seeds or 20)
    local canPlace=f.app.runtime.handlers.canPlace
    f.app.runtime.handlers.canPlace=function(item,x,y)
        if x==2 and y==1 and math.floor(f.avatar.y-0.01)==3 then
            return f.hooks.Core.plantingTile(f.world,f.app.runtime.items,x,y)
                and math.abs(f.avatar.x-(x+0.5))<=2.5 and math.abs(y+0.5-(f.avatar.y-0.475))<=2.5
        end
        return canPlace(item,x,y)
    end
    f.onPlant=function(_,x,y)
        if x==2 and y==1 then
            if not f.refusedUpper then
                f.refusedUpper=true
                f.grids.FARM1[y][x],f.serverSeeds=0,f.serverSeeds+1
            else
                f.lowerRetries=(f.lowerRetries or 0)+1
                assert(math.floor(f.avatar.y-0.01)==3,"Retry the missed tile from the lower row")
            end
        end
    end
    return f
end

test("Rejected upper seeds are retried while planting the next row without returning upward", function()
    local f=rejectedUpperFixture()
    f.hooks.start("plant")
    assert(not f.app.lastError,f.app.lastError)
    assert(f.lowerRetries==1 and #f.plantCalls==16 and f.app.stats.planted==15 and f.serverSeeds==5)
    assert(f.grids.FARM1[1][2]==955 and f.hooks.readPlantResume()==nil)
end)

test("An already full lower row still provides the one retry approach for an upper seed", function()
    local f=rejectedUpperFixture()
    for x=1,5 do f.grids.FARM1[3][x]=955 end
    f.hooks.start("plant")
    assert(not f.app.lastError,f.app.lastError)
    assert(f.lowerRetries==1 and #f.plantCalls==11 and f.app.stats.planted==10)
    assert(f.grids.FARM1[1][2]==955)
end)

test("Deferred upper tiles survive a seed refill and retain their lower-row retry", function()
    local f=rejectedUpperFixture(2)
    local entered=f.onEnter
    f.onEnter=function(name)
        if name=="STOCK" then
            local saved=f.hooks.readPlantResume()
            assert(saved.state.deferred["2:1"].tries==0 and saved.state.skipped["2:1"])
        end
        return entered(name)
    end
    f.hooks.start("plant")
    assert(not f.app.lastError,f.app.lastError)
    assert(f.withdrawals==1 and f.lowerRetries==1 and #f.plantCalls==16 and f.app.stats.planted==15)
end)

test("Deferred planting checkpoints preserve coordinates and reject invalid retry counts", function()
    local f=zigzagPlantingFixture(20)
    f.hooks.savePlantResume({worldIndex=1,phase="farm",skipped={["2:1"]="placement not confirmed"},
        deferred={["2:1"]={x=2,y=1,tries=0}}})
    local saved=f.hooks.readPlantResume()
    assert(saved.state.deferred["2:1"].x==2 and saved.state.deferred["2:1"].tries==0)
    saved.state.deferred["2:1"].tries=2
    f.hooks.savePlantResume(saved.state)
    rejects(f.hooks.readPlantResume,"Invalid deferred planting tile")
end)

test("A second refusal from below is skipped without repeatedly spending seeds", function()
    local f=rejectedUpperFixture()
    local first=f.onPlant
    f.onPlant=function(id,x,y)
        first(id,x,y)
        if x==2 and y==1 and f.lowerRetries then f.grids.FARM1[y][x],f.serverSeeds=0,f.serverSeeds+1 end
    end
    f.hooks.start("plant")
    assert(not f.app.lastError,f.app.lastError)
    assert(f.lowerRetries==1 and #f.plantCalls==16 and f.app.stats.planted==14 and f.grids.FARM1[1][2]==0)
end)

test("A seed count change outside the attempted batch remains a critical failure", function()
    local f=plantingFixture(10,100)
    f.onPlant=function(_,x,y) f.serverSeeds=f.serverSeeds-2; f.grids.FARM1[y][x]=0 end
    f.hooks.start("plant")
    assert(f.app.lastError:find("Seed count changed unexpectedly",1,true))
    assert(#f.plantCalls==1 and f.hooks.readPlantResume().state.pending)
end)

test("A rotation walking timeout replans from the current position and succeeds on its next attempt", function()
    local f=plantingFixture(10,100)
    f.app.job,f.app.rotationState="rotation",{phase="plant"}
    local calls=0
    f.hooks.moveTo(5,5,"FARM1",1,function()
        calls=calls+1
        if calls==1 then error("Returning to the saved position timed out. Check the route.") end
    end)
    assert(calls>1 and math.abs(f.avatar.x-5.5)<0.16 and f.app.job=="rotation")
    assert(f.app.navigationRecovery:find("attempt 2/3",1,true) and #f.plantCalls==0)
end)

test("A picker interruption preserves and reconciles several outstanding moving seed placements", function()
    local f = plantingFixture(10, 100)
    local pending
    f.onPlant = function()
        if #f.plantCalls == 4 then
            pending = f.hooks.readPlantResume().state.pending
            assert(#pending.tiles == 4 and pending.before == 10)
            f.onPlant = nil
            f.world.name, f.avatar.active = "", false
        end
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(pending and #f.plantCalls == 7 and f.app.stats.planted == 7 and f.serverSeeds == 3)
    for index, point in ipairs(f.plantCalls) do assert(point.x == index - 1) end
end)

test("A late foreground rollback retires its rejected tile and allows the next seed batch", function()
    local f = plantingFixture(20, 100)
    f.world.w = 12
    for y = 0, 7 do for x = 7, 11 do f.grids.FARM1[y][x] = y == 6 and 2 or 0 end end
    local server, physics, confirmedRead, corrected = f.server, f.onWait, false, false
    f.server = function(name, ...)
        if name == "GetInventory" and #f.plantCalls == 8 then confirmedRead = true end
        return server(name, ...)
    end
    f.onWait = function(dt)
        physics(dt)
        if confirmedRead and not corrected then
            corrected = true
            f.grids.FARM1[5][0], f.serverSeeds = 0, f.serverSeeds + 1
        end
    end
    f.hooks.start("plant")
    assert(corrected and not f.app.lastError,f.app.lastError)
    assert(#f.plantCalls == 12 and f.app.stats.planted == 11 and f.hooks.readPlantResume()==nil)
    assert(f.grids.FARM1[5][0]==0 and f.serverSeeds==9)
end)

test("A planting inventory timeout retains the batch instead of skipping a tile and spending more seeds", function()
    local f = plantingFixture(20, 100)
    f.world.w = 12
    for y = 0, 7 do for x = 7, 11 do f.grids.FARM1[y][x] = y == 6 and 2 or 0 end end
    local server = f.server
    f.server = function(name, ...)
        if name == "GetInventory" and #f.plantCalls == 8 then error("Game request timed out") end
        return server(name, ...)
    end
    f.hooks.start("plant")
    assert(f.app.lastError:find("Game request timed out", 1, true))
    local state = f.hooks.readPlantResume().state
    assert(#f.plantCalls == 8 and #state.pending.tiles == 8 and state.pending.before == 20)
    assert(next(state.skipped) == nil and f.app.stats.planted == 0)
end)

test("Saved planting batches reject duplicate, sparse, oversized or cross-row tile evidence", function()
    local f = plantingFixture(10, 100)
    local function record(tiles)
        f.hooks.savePlantResume({worldIndex = 1, phase = "farm", skipped = {},
            pending = {world = "FARM1", x = 0, y = 5, before = 10, tiles = tiles}})
    end
    record({{x = 0, y = 5}, {x = 0, y = 5}})
    rejects(f.hooks.readPlantResume, "batch tile")
    record({{x = 0, y = 5}, {x = 1, y = 3}})
    rejects(f.hooks.readPlantResume, "batch tile")
    record({{x = 0, y = 5}, [3] = {x = 2, y = 5}})
    rejects(f.hooks.readPlantResume, "batch list")
    local tiles = {}
    for x = 0, 8 do tiles[#tiles + 1] = {x = x, y = 5} end
    record(tiles)
    rejects(f.hooks.readPlantResume, "seed batch")
end)

test("Planting follows both platform turns and retains zigzag order after a completed row refill", function()
    local f = zigzagPlantingFixture(5, {"FARM1", "FARM2"})
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 22 and f.withdrawals == 1)
    for index, point in ipairs(f.plantCalls) do
        if index <= 15 then
            local row, column = math.floor((index - 1) / 5) + 1, (index - 1) % 5 + 1
            assert(point.y == row * 2 - 1 and point.x == (row % 2 == 1 and column or 6 - column),
                "Wrong zigzag placement at " .. index .. ": " .. point.x .. ", " .. point.y)
        else assert(point.world == "FARM2" and point.x == index - 16, "A new farm must restart from the left") end
    end
end)

test("A seed refill resumes either direction of an unfinished upper row with moving batches", function()
    for _, initial in ipairs({16, 40}) do
        local f = wideZigzagPlantingFixture(initial)
        local resumedRow, moving, placements = initial == 16 and 1 or 3, 0, 0
        f.onPlant = function(_, x, y)
            if f.withdrawals > 0 and y == resumedRow then
                local pending = f.hooks.readPlantResume().state.pending
                assert(pending.tiles, "Refill returned to per-tile planting on the unfinished row")
                placements = placements + 1
                if math.abs(f.avatar.vx) > 0.8 then moving = moving + 1 end
            end
        end
        f.hooks.start("plant")
        assert(not f.app.lastError, f.app.lastError)
        assert(#f.plantCalls == 96 and f.withdrawals == 1 and f.app.stats.planted == 96)
        assert(placements == (initial == 16 and 16 or 24) and moving >= math.floor(placements * 0.75),
            "The resumed row should continue planting during movement: initial " .. initial .. ", moving " .. moving .. "/" .. placements)
        for index, point in ipairs(f.plantCalls) do
            local row, column = math.floor((index - 1) / 32) + 1, (index - 1) % 32 + 1
            assert(point.y == row * 2 - 1 and point.x == (row % 2 == 1 and column or 33 - column),
                "Refill must retain the current row direction and never replay occupied tiles")
        end
    end
end)

test("A fresh planting instance reconciles a pending seed then streams its saved upper row", function()
    local f = wideZigzagPlantingFixture(120)
    for x = 1, 16 do f.grids.FARM1[1][x] = 955 end
    f.serverSeeds = 104
    f.inventory:remove(955, 16)
    f.hooks.savePlantResume({phase = "farm", worldIndex = 1, skipped = {},
        rows = f.hooks.Core.farmRows(f.world, f.app.runtime.items), rowY = 1,
        pending = {world = "FARM1", x = 16, y = 1, before = 105, tiles = {{x = 16, y = 1}}}})
    local runtime, next = f.app.runtime, f.reload()
    f.hooks, f.app = next, next.App
    f.app.runtime = runtime
    local moving = 0
    f.onPlant = function(_, x, y)
        if y == 1 then
            assert(x > 16 and next.readPlantResume().state.pending.tiles)
            if math.abs(f.avatar.vx) > 0.8 then moving = moving + 1 end
        end
    end
    next.start("plant", next.readPlantResume())
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 80 and f.plantCalls[1].x == 17 and f.plantCalls[1].y == 1)
    assert(moving >= 12 and f.app.stats.planted == 81 and f.serverSeeds == 24 and f.withdrawals == 0)
end)

test("A planting picker interruption after the top row preserves the next row direction", function()
    local f = zigzagPlantingFixture(20)
    f.onPlant = function()
        if #f.plantCalls == 5 then f.onPlant = nil; f.world.name, f.avatar.active = "", false end
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 15 and f.plantCalls[6].x == 5 and f.plantCalls[6].y == 3)
    assert(f.plantCalls[11].x == 1 and f.plantCalls[11].y == 5)
end)

test("Planting skips full upper and middle rows without losing the lower row direction", function()
    local f = zigzagPlantingFixture(20)
    for x = 1, 5 do f.grids.FARM1[1][x], f.grids.FARM1[3][x] = 955, 955 end
    local physics, reachedUpper = f.onWait, false
    f.onWait = function(dt)
        physics(dt)
        if f.avatar.y < 4.8 then reachedUpper = true end
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 5 and not reachedUpper and f.withdrawals == 0)
    for index, point in ipairs(f.plantCalls) do assert(point.y == 5 and point.x == index) end
end)

test("Planting removes a harvesting tractor so occupied trees remain intact during travel", function()
    local f = zigzagPlantingFixture(20)
    f.app.runtime.harvestGear = {
        feet = function() return f.worn end,
        wear = function(id)
            if f.worn == id then f.worn = nil else f.worn = id end
            f.world.riding = f.worn == 898 and {harvest = true, speed = 3.6} or nil
        end,
    }
    f.worn, f.world.riding = 898, {harvest = true, speed = 3.6}
    for x = 1, 5 do f.grids.FARM1[1][x] = 955 end
    local physics = f.onWait
    f.onWait = function(dt)
        assert(f.worn ~= 898, "Planting movement must not auto-harvest existing trees")
        physics(dt)
    end
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 10 and f.worn == 898)
    for x = 1, 5 do assert(f.grids.FARM1[1][x] == 955) end
end)

test("Refill world loads remove a restored Tractor before returning to the unfinished planting row", function()
    local f=wideZigzagPlantingFixture(2)
    f.app.runtime.harvestGear={feet=function() return f.worn end,wear=function(id)
        if f.worn==id then f.worn=nil else f.worn=id end
        f.world.riding=f.worn==898 and {harvest=true,speed=3.6} or nil
    end}
    f.worn,f.world.riding=898,{harvest=true,speed=3.6}
    local enter=f.onEnter
    f.onEnter=function(name)
        enter(name)
        f.worn,f.world.riding=898,{harvest=true,speed=3.6} -- Simulate worn ride restoration on arrival.
        return true
    end
    local physics=f.onWait
    f.onWait=function(dt)
        if f.controls.dir()~=0 or f.controls.jumping() then
            assert(f.worn~=898 and not f.world.riding,
                "Storage approaches and return-to-row travel must keep the Tractor off")
        end
        physics(dt)
    end
    f.onPlant=function() assert(f.worn~=898) end
    f.hooks.start("plant")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.plantCalls==96 and f.withdrawals==1 and f.worn==898)
end)

test("An occupied solid edge does not prevent planting the rest of its row", function()
    local f = zigzagPlantingFixture(20)
    f.grids.FARM1[1][1] = 2
    f.hooks.start("plant")
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plantCalls == 14 and f.plantCalls[1].x == 2 and f.plantCalls[1].y == 1)
    assert(f.plantCalls[5].x == 5 and f.plantCalls[5].y == 3 and f.grids.FARM1[1][1] == 2)
end)

test("Saved planting rows survive reload and reject changed order or an unrelated row cursor", function()
    local f = zigzagPlantingFixture(20)
    local rows = f.hooks.Core.farmRows(f.world, f.app.runtime.items)
    f.hooks.savePlantResume({worldIndex = 1, phase = "farm", skipped = {}, rows = rows, rowY = 1})
    rows[1].left = 4
    local next = f.reload()
    local saved = next.readPlantResume()
    assert(saved.state.rows[1].left == 1 and #saved.state.rows == 3 and saved.state.rowY == 1)
    saved.state.rows[2].y = 1
    next.savePlantResume(saved.state)
    rejects(next.readPlantResume, "farm row order")
    saved.state.rows[2].y, saved.state.rowY = 3, 2
    next.savePlantResume(saved.state)
    rejects(next.readPlantResume, "planting row")
    saved.state.rowY, saved.state.rows = nil, {[2] = saved.state.rows[2]}
    next.savePlantResume(saved.state)
    -- The public writer canonicalizes arrays; damaged persisted arrays must still reject.
    local record = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/plant-resume.json"])
    record.state.rows = {[2] = {y = 3, left = 1, right = 5}}
    rejects(next.readPlantResume, "farm row list")
end)

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

test("Server seed refusals skip each tile once and leave the rest of the task running", function()
    local f = plantingFixture(10, 100)
    f.rejectPlant = true
    f.hooks.start("plant")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.plantCalls==7 and f.serverSeeds==10 and f.app.stats.planted==0 and f.hooks.readPlantResume()==nil)
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
    local record = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/plant-resume.json"])
    record.userId = 99
    rejects(function() f.hooks.readPlantResume() end, "another account")
    record.userId, record.updatedAt = 1234, os.time() - 21601
    rejects(function() f.hooks.readPlantResume() end, "six hours")
end)

test("A spent seed with missing tile evidence is logged and deferred without an immediate duplicate", function()
    local f = plantingFixture(9, 100)
    f.app.job, f.app.jobToken = "plant", 1
    local state = {worldIndex = 1, phase = "farm", skipped = {}, pending = {world = "FARM1", x = 0, y = 5, before = 10}}
    f.hooks.reconcilePlant(state,1)
    assert(state.pending==nil and state.deferred["0:5"] and #f.plantCalls==0 and f.app.stats.planted==0)
    assert(f.app.plantingRecovery:find("skipped 1",1,true))
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
    f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = 2.5, 5.999, 0, 0
    f.app.job, f.app.rotationState = "rotation", {phase = "replant"}
    f.hooks.moveTo(2, 2, "BREAK", 1)
    assert(math.abs(f.avatar.x - 2.5) < 0.16 and math.abs(f.avatar.y - 3) < 0.22,
        "Rotation replanting must use the full farm navigation search too")
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

local function actualUIFixture(withCatalog)
    local f = fixture()
    if withCatalog then largeSeedCatalog(f) end
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
    function tab:Dropdown(props)
        local c = control(props)
        c.Set = nil -- Vendored WindUI dropdowns expose Select/Refresh, not Set.
        c:Refresh(c.Values)
        return c
    end
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
    return f, app, controls, workers, firstGCWait
end

test("Actual UI startup limits seed entries, renders once, and supports a bounded catalog search", function()
    local f, app, controls, workers, firstGCWait = actualUIFixture(true)
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

test("The FPS toggle applies during an active task and saves its choice without changing that task", function()
    local f, app, controls = actualUIFixture()
    local parent, drop = {}, {uid = 1, id = 954, n = 10, x = 5.5, y = 8.5}
    f.drops[1] = drop
    attachDropVisual(drop, parent)
    app.job, app.jobToken, app.pending = "rotation", app.token, 1
    local checkpoint = {version = 1, active = true, userId = f.player.UserId, profile = app.profile,
        config = f.hooks.Core.validate(app.config), updatedAt = os.time() - 60,
        state = {phase = "seedDepositPending", seedCargo = 10, cycle = 2, worldIndex = 1}}
    f.files["ClarisGrowblox/accounts/1234/rotation-resume.json"] = f.services.HttpService:JSONEncode(checkpoint)
    local token = app.token
    controls["FPS booster: hide floating drops"]:Set(true)
    assert(app.config.options.fpsBooster and drop.frame.Parent == nil and app.fpsHidden == 1)
    local session = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/session.json"])
    assert(session.config.options.fpsBooster and app.job == "rotation" and app.token == token and app.pending == 1)
    local restored = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/rotation-resume.json"])
    assert(restored.config.options.fpsBooster and restored.updatedAt == checkpoint.updatedAt)
    assert(restored.state.phase == "seedDepositPending" and restored.state.seedCargo == 10 and restored.state.cycle == 2)
    controls["FPS booster: hide floating drops"]:Set(false)
    assert(not app.config.options.fpsBooster and drop.frame.Parent == parent and app.job == "rotation" and app.pending == 1)
    assert(not f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/rotation-resume.json"]).config.options.fpsBooster)
end)

test("Use PNB seeds updates the real UI after entering farms with Select-only WindUI dropdowns", function()
    local f, app, controls, workers = actualUIFixture()
    assert(controls["Harvest method"].Set == nil)
    controls["Dirt farm worlds (in order)"].Props.Callback("FARM1, FARM2")
    controls["Use PNB seeds for planting"].Props.Callback()
    workers[3]()
    assert(app.config.planting.seedId == 955 and app.config.planting.storageWorld == "BREAK")
    assert(app.config.points.plantBox.x == app.config.points.seedBox.x and app.config.points.plantBox.world == "BREAK")
    assert(controls["Seed to plant"].Value == "Sugar Cane Seed [955]" and controls["Seed storage world"].Value == "BREAK")
    assert(controls["Dirt farm worlds (in order)"].Value == "FARM1, FARM2" and controls["Harvest method"].Value == "Fist")
    assert(not app.syncingUI and not app.syncingPlantUI and not app.syncingWebhookUI)
    controls["Dirt farm worlds (in order)"].Props.Callback("FARM2, FARM3")
    assert(app.config.planting.worlds[2] == "FARM3", "Seed setup must not leave later settings changes locked")
    assert(app.runtime.farmingDeferred and app.pending == 0 and f.pickups == 0 and f.displays == 0)
end)

test("Actual UI imports, loads, and resets profiles with the supported harvest dropdown method", function()
    local f, app, controls, workers = actualUIFixture()
    app.config.harvesting.method = "tractor"
    app.config.options.harvestPlanting = true
    app.config.planting.worlds = {"FARM1", "FARM2"}
    local record = f.hooks.Core.exportConfig(app.config, "Portable UI", "0.1.25")
    controls["Configuration text"].Value = f.services.HttpService:JSONEncode(record)
    controls["Import config"].Props.Callback()
    workers[3]()
    assert(app.profile == "Portable UI" and controls["Harvest method"].Value == "Dear John Tractor" and not app.syncingUI)
    assert(f.files["ClarisGrowblox/accounts/1234/profiles/Portable UI.json"] and app.job == nil)
    assert(controls["Replant during harvest"].Value and app.config.options.harvestPlanting)
    -- The fixture codec stores tables by reference; snapshot the saved JSON as
    -- real serialization does before changing the live configuration.
    f.encoded[f.files["ClarisGrowblox/accounts/1234/profiles/Portable UI.json"]] = f.hooks.Core.validate(app.config)
    controls["Harvest method"].Props.Callback("Fist")
    controls["Replant during harvest"]:Set(false)
    assert(app.config.harvesting.method == "fist")
    controls["Saved profiles"].Props.Callback("Portable UI")
    controls["Load selected profile"].Props.Callback()
    workers[4]()
    assert(app.config.harvesting.method == "tractor" and controls["Harvest method"].Value == "Dear John Tractor")
    assert(controls["Replant during harvest"].Value and app.config.options.harvestPlanting)
    assert(controls["Dirt farm worlds (in order)"].Value == "FARM1, FARM2" and not app.syncingUI)
    controls["New empty configuration"].Props.Callback()
    workers[5]()
    assert(app.profile == "New Farm" and controls["Harvest method"].Value == "Fist" and not app.syncingUI)
    assert(not controls["Replant during harvest"].Value and not app.config.options.harvestPlanting)
end)

test("Moving Drops UI saves Seeds, restores it on import/load, and blocks changes during active cargo", function()
    local f, app, controls, workers = actualUIFixture()
    assert(not controls["Save Farm door to breaking world"] and not controls["Save Breaking door to farm world"])
    assert(controls["Save Destination Display Box"] and controls["Save Farm storage"])
    controls["Item to move"].Props.Callback({"Seeds"})
    assert(app.config.moving.item == "seeds")
    local session = f.services.HttpService:JSONDecode(f.files[app.dataFolder .. "/session.json"])
    assert(session.config.moving.item == "seeds")
    app.config.points.moveBox = {world="OTHER",x=4,y=8,standX=3,standY=8}
    local record = f.hooks.Core.exportConfig(app.config,"Seed transfer","0.1.38")
    controls["Configuration text"].Value = f.services.HttpService:JSONEncode(record)
    controls["Import config"].Props.Callback()
    workers[3]()
    assert(app.config.moving.item == "seeds" and controls["Item to move"].Value == "Seeds")
    assert(app.config.points.moveBox.world == "OTHER" and app.job == nil)
    f.encoded[f.files[app.dataFolder .. "/profiles/Seed transfer.json"]] = f.hooks.Core.validate(app.config)
    controls["Item to move"].Props.Callback("Blocks")
    assert(app.config.moving.item == "blocks")
    controls["Saved profiles"].Props.Callback("Seed transfer")
    controls["Load selected profile"].Props.Callback()
    workers[4]()
    assert(app.config.moving.item == "seeds" and controls["Item to move"].Value == "Seeds")
    app.job, app.pending, app.resume = "transfer",1,{phase="depositPending",item="seeds",cargo=100}
    controls["Item to move"].Value = "Blocks"
    controls["Item to move"].Props.Callback("Blocks")
    assert(app.config.moving.item == "seeds" and controls["Item to move"].Value == "Seeds")
    assert(app.pending == 1 and app.resume.cargo == 100 and not app.syncingUI)
    app.job, app.pending, app.resume = nil,0,nil
    controls["New empty configuration"].Props.Callback()
    workers[5]()
    assert(app.config.moving.item == "blocks" and controls["Item to move"].Value == "Blocks")
end)

test("Harvest replanting toggle preserves active rotation and honors UI synchronization", function()
    local f, app, controls = actualUIFixture()
    local toggle = controls["Replant during harvest"]
    toggle:Set(true)
    assert(app.config.options.harvestPlanting)
    local session = f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/1234/session.json"])
    assert(session.config.options.harvestPlanting)
    app.job = "rotation"
    toggle:Set(false)
    assert(app.config.options.harvestPlanting and toggle.Value and not app.syncingUI)
    app.syncingUI = true
    toggle:Set(false)
    assert(app.config.options.harvestPlanting and app.syncingUI)
    app.syncingUI = false
end)

test("Changing harvest method during a task restores the dropdown using Select without changing config", function()
    local _, app, controls = actualUIFixture()
    app.job = "rotation"
    controls["Harvest method"].Value = "Dear John Tractor"
    controls["Harvest method"].Props.Callback("Dear John Tractor")
    assert(app.config.harvesting.method == "fist" and controls["Harvest method"].Value == "Fist")
    assert(not app.syncingUI)
end)

test("A UI refresh error restores the settings guard and allows seed setup to be retried", function()
    local _, app, controls, workers = actualUIFixture()
    local input, set = controls["Profile name"], controls["Profile name"].Set
    input.Set = function() error("UI render failed") end
    controls["Use PNB seeds for planting"].Props.Callback()
    workers[3]()
    assert(app.status:find("UI render failed", 1, true) and not app.syncingUI and not app.configuring)
    input.Set = set
    controls["Dirt farm worlds (in order)"].Props.Callback("FARM1, FARM2")
    assert(app.config.planting.worlds[2] == "FARM2")
    controls["Use PNB seeds for planting"].Props.Callback()
    workers[4]()
    assert(controls["Seed storage world"].Value == "BREAK" and controls["Harvest method"].Value == "Fist")
    assert(not app.syncingUI and not app.configuring)
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
    assert(f.app.discoveryPerformance.steps <= #f.discoveryObjects + 5100,
        "Full attachment should index the snapshot once and scan only functions for ownership")
    for _, n in pairs(reads) do assert(n == 1, "A function's upvalues were repeatedly scanned") end
end)

test("Transfer attachment skips unrelated function upvalues and defers punching hooks", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    attachWorldHandlers(f, items)
    f.world.definitions = function() return items end
    local noise = {}
    for n = 1, 5000 do
        local value = n
        local fn = function() return value end
        noise[fn] = true
        table.insert(f.discoveryObjects, fn)
    end
    for n = 1, 10000 do table.insert(f.discoveryObjects, {noise = n}) end
    local reads = 0
    getupvalues = function(fn)
        assert(not noise[fn], "Moving Drops must not inspect unrelated function upvalues")
        reads = reads + 1
        local values = {}
        for index = 1, 100 do
            local name, value = debug.getupvalue(fn, index)
            if not name then break end
            if value ~= nil then values[index] = value end
        end
        return values
    end
    local r = f.hooks.connectGame({transferOnly = true})
    assert(r.ready and r.farmingDeferred and r.items == items and r.inventory == f.inventory)
    assert(reads < 30, "Transfer attachment must read only the necessary world/controller methods")
    assert(f.app.discoveryPerformance.steps <= #f.discoveryObjects + 100,
        "Fast attachment must not repeatedly traverse unrelated tables/functions")
    assert(f.app.discoveryPerformance.yields <= 3, "Lightweight indexing should avoid repeated per-frame waits")
    -- PNB can still discover its handlers when selected later.
    getupvalues = nil
    f.app.job, f.boxes[12] = nil, {}
    f.avatar.x, f.app.config.points.blockBox.standX = 10.5, 10
    f.server = function(name) assert(name == "GetInventory"); return {slots = {}, capacity = 54} end
    f.hooks.start("pnb")
    assert(not f.app.runtime.farmingDeferred and f.app.runtime.handlers.hit and not f.app.lastError)
end)

test("Fast attachment binds Respawn from the menu adapter belonging to the active world", function()
    local f = fixture()
    local items = f.app.runtime.items
    prepareDiscovery(f, true)
    attachWorldHandlers(f, items)
    local world = f.world
    world.enter = function() return true end
    world.definitions = function() return items end
    local called = 0
    local adapter = {enter = world.enter, currentWorld = function() return world.name end,
        respawn = function() called = called + 1 end}
    local otherWorld = {name = "OTHER"}
    local unrelated = {enter = world.enter, currentWorld = function() return otherWorld.name end,
        respawn = function() error("Unrelated adapter must never be selected") end}
    table.insert(f.discoveryObjects, unrelated)
    table.insert(f.discoveryObjects, adapter)
    local r = f.hooks.connectGame({transferOnly = true})
    assert(r.respawn == adapter.respawn and r.respawnSource == "native menu adapter" and called == 0)
    r.respawn()
    assert(called == 1 and world.respawn == nil)
end)

test("Respawn discovery accepts aliases but rejects conflicting menu actions", function()
    local f = fixture()
    local world = f.world
    world.enter = function() return true end
    local currentWorld = function() return world.name end
    local first = {enter = world.enter, currentWorld = currentWorld,
        respawn = function() error("Discovery must not execute Respawn") end}
    local alias = {enter = world.enter, currentWorld = currentWorld, respawn = first.respawn}
    assert(f.hooks.findRespawn(world, {first, alias}) == first.respawn)
    local other = {enter = world.enter, currentWorld = currentWorld,
        respawn = function() error("Conflicting action must not be chosen") end}
    local action, source = f.hooks.findRespawn(world, {first, other})
    assert(not action and source:find("ambiguous", 1, true))
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

local function mixedTransferFixture(seedFirst)
    local f = pickupFixture()
    f.world.name, f.app.job = "FARM", "transfer"
    f.avatar.x, f.avatar.y = 13.5, 9
    f.world.fg[8][21] = 12
    f.worldBoxes = {FARM = {[20]={{955,450},{954,430}}}, BREAK = {[12]={},[8]={}}}
    f.withdrawals, f.seedWithdrawals = 0, 0
    f.world.displays.get = function(x) return f.worldBoxes[f.world.name][x] or {} end
    f.world.enter = function(name) f.world.name = name; return true end
    local base = f.server
    f.server = function(name, x, y, id, _, _, n)
        if name == "GetInventory" then return base(name) end
        if name == "UseDoor" then return true, {enter=f.world.name == "FARM" and "BREAK" or "FARM"} end
        assert(name == "DisplayItem")
        local rows = f.worldBoxes[f.world.name][x]
        assert(rows)
        if not id then
            f.withdrawals = f.withdrawals + 1
            local taken = {}
            for _, row in ipairs(rows) do
                local got = math.min(row[2], 200 - (f.serverItems[row[1]] or 0))
                if got > 0 then
                    row[2] = row[2] - got
                    f.serverItems[row[1]] = (f.serverItems[row[1]] or 0) + got
                    taken[#taken+1] = {row[1],got}
                    if row[1] == 955 then f.seedWithdrawals = f.seedWithdrawals + 1 end
                    if seedFirst then seedFirst = false; break end
                end
            end
            if f.afterWithdraw then f.afterWithdraw(taken) end
            return true, {taken=taken}
        end
        if f.beforeDeposit then f.beforeDeposit(id,n) end
        assert(n > 0 and n <= (f.serverItems[id] or 0))
        f.serverItems[id] = f.serverItems[id] - n
        local found = false
        for _, row in ipairs(rows) do if row[1] == id then row[2],found = row[2]+n,true end end
        if not found then rows[#rows+1]={id,n} end
        return true
    end
    return f
end

test("Mixed Farm storage moves every block, keeps a full seed stack between trips, and returns seeds", function()
    for _, seedFirst in ipairs({false,true}) do
        local f = mixedTransferFixture(seedFirst)
        f.serverItems[954], f.serverItems[955] = 20, 25
        f.inventory:add(954,20); f.inventory:add(955,25)
        f.beforeDeposit = function(id)
            if f.world.name == "BREAK" then assert(id == 954 and f.serverItems[955] == 200) end
        end
        f.hooks.takeControls()
        f.hooks.runTransfer(1)
        assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],954) == 430)
        assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],955) == 0)
        assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[20],955) == 475)
        assert(f.serverItems[954] == 20 and f.serverItems[955] == 0)
        assert(f.app.stats.trips == 3 and f.seedWithdrawals == 1 and f.app.resume == nil)
    end
end)

test("A seed-only Farm box finishes without withdrawing its seeds and returns seeds already held", function()
    local f = mixedTransferFixture()
    f.worldBoxes.FARM[20] = {{955,450}}
    f.serverItems[955] = 80; f.inventory:add(955,80)
    f.hooks.takeControls(); f.hooks.runTransfer(1)
    assert(f.withdrawals == 0 and f.app.stats.trips == 0 and f.serverItems[955] == 0)
    assert(f.hooks.Core.storageCount(f.worldBoxes.FARM[20],955) == 530)
end)

test("Seeds transfer from a mixed Farm box using only two saved boxes and return held blocks", function()
    for _, blocksFirst in ipairs({false,true}) do
        local f = mixedTransferFixture(true)
        f.app.config.moving.item = "seeds"
        f.app.config.points.moveBox = f.app.config.points.blockBox
        f.app.config.points.pnb, f.app.config.points.blockBox, f.app.config.points.seedBox = nil,nil,nil
        f.app.config.points.farmDoor, f.app.config.points.breakDoor = nil,nil
        if blocksFirst then f.worldBoxes.FARM[20] = {{954,430},{955,450}} end
        f.worldBoxes.BREAK[12] = {{954,100}} -- The destination can already contain the matching block.
        f.serverItems[954], f.serverItems[955] = 25,20
        f.inventory:add(954,25); f.inventory:add(955,20)
        local entries, enter, server = {}, f.world.enter, f.server
        f.world.enter = function(name) entries[#entries+1]=name; return enter(name) end
        f.server = function(name, ...)
            assert(name ~= "UseDoor", "Moving Drops must use direct world entry")
            return server(name, ...)
        end
        f.beforeDeposit = function(id)
            if f.world.name == "BREAK" then assert(id == 955, "Only selected seeds may reach the destination") end
        end
        f.hooks.takeControls(); f.hooks.runTransfer(1)
        assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],955) == 450)
        assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],954) == 100)
        assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[20],955) == 0)
        assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[20],954) == 455)
        assert(f.serverItems[955] == 20 and f.serverItems[954] == 0 and f.app.stats.moved == 450)
        assert(f.app.stats.trips == 3 and #entries == 6 and f.app.pending == 0 and not f.app.resume)
    end
end)

test("Moving Drops starts in the destination world and visits its source directly without a PNB setup", function()
    local f = mixedTransferFixture()
    f.app.config.points.moveBox = f.app.config.points.blockBox
    f.app.config.points.pnb, f.app.config.points.blockBox, f.app.config.points.seedBox = nil,nil,nil
    f.app.config.points.farmDoor, f.app.config.points.breakDoor = nil,nil
    f.world.name = "BREAK"
    local first, enter = nil,f.world.enter
    f.world.enter = function(name) first=first or name; return enter(name) end
    f.hooks.takeControls(); f.hooks.runTransfer(1)
    assert(first == "FARM" and f.world.name == "FARM" and f.app.stats.moved == 430)
    assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[20],955) == 450 and not f.app.plantState)
    assert(not f.files[f.app.dataFolder .. "/plant-resume.json"], "Transfer entry must not create a planting checkpoint")
end)

test("A block-only farm box leaves blocks untouched when Seeds is selected", function()
    local f = mixedTransferFixture()
    f.app.config.moving.item = "seeds"
    f.worldBoxes.FARM[20] = {{954,430}}
    f.serverItems[954]=80; f.inventory:add(954,80)
    f.hooks.takeControls(); f.hooks.runTransfer(1)
    assert(f.withdrawals == 0 and f.app.stats.moved == 0 and f.serverItems[954] == 0)
    assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[20],954) == 510)
end)

test("A selected seed trip saves its cargo and companion blocks across a world-change script reload", function()
    local f = mixedTransferFixture()
    f.app.config.moving.item = "seeds"
    f.app.config.points.moveBox = f.app.config.points.blockBox
    f.app.config.points.farmDoor, f.app.config.points.breakDoor = nil,nil
    f.app.job, f.app.jobToken = nil,nil
    installToggles(f)
    f.env.ClarisGrowbloxLoaderURL = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"
    local queued, enter = 0,f.world.enter
    queue_on_teleport = function(code)
        assert(code:find("ClarisGrowbloxAutoResume",1,true)); queued=queued+1
    end
    f.world.enter = function(name)
        enter(name)
        if name == "BREAK" and f.app.stats.moved == 0 then return true,nil,true end
        return true
    end
    f.onWait = function() if f.app.teleporting then f.app.alive=false end end
    f.hooks.start("transfer")
    local runtime = f.app.runtime
    local saved = f.services.HttpService:JSONDecode(f.files[f.app.dataFolder .. "/resume.json"])
    assert(queued == 1 and saved.item == "seeds" and saved.phase == "deliver" and saved.cargo == 200 and saved.companion == 200)
    assert(saved.config.moving.item == "seeds" and saved.config.points.moveBox.world == "BREAK")
    assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],955) == 0)
    f.hooks = f.reload()
    f.app = f.hooks.App
    f.app.runtime, f.app.config, f.app.profile = runtime,saved.config,saved.profile
    f.world.enter, f.onWait = enter,nil
    f.hooks.start("transfer",saved)
    queue_on_teleport = nil
    assert(not f.app.lastError,f.app.lastError)
    assert(f.app.stats.moved == 450 and f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],955) == 450)
    assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],954) == 0)
    assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[20],954) == 430 and f.serverItems[954] == 0)
    assert(not f.app.resume and f.app.pending == 0 and not f.app.plantState)
end)

test("An interrupted selected seed deposit retains both item types and cannot replay its mutation", function()
    local f = mixedTransferFixture()
    f.app.config.moving.item = "seeds"
    f.app.config.points.moveBox = f.app.config.points.blockBox
    f.beforeDeposit = function(id)
        if f.world.name == "BREAK" then assert(id == 955); error("Seed destination denied") end
    end
    f.hooks.takeControls()
    rejects(function() f.hooks.runTransfer(1) end,"Seed destination denied")
    assert(f.app.resume.item == "seeds" and f.app.resume.phase == "depositPending" and f.app.resume.cargo == 200)
    assert(f.serverItems[955] == 200 and f.serverItems[954] == 200 and f.app.pending == 0)
    rejects(function() f.hooks.runTransfer(1,f.app.resume) end,"Invalid transfer resume phase")
end)

test("An interrupted mixed withdrawal retains the pending checkpoint and both item types", function()
    local f = mixedTransferFixture()
    f.afterWithdraw = function() error("Connection interrupted after storage mutation") end
    f.hooks.takeControls()
    rejects(function() f.hooks.runTransfer(1) end,"Connection interrupted")
    assert(f.app.resume.phase == "pickupPending" and f.serverItems[954] == 200 and f.serverItems[955] == 200)
end)

test("Refused seed return preserves the full seed stack and an ambiguous-return checkpoint", function()
    local f = mixedTransferFixture()
    f.worldBoxes.FARM[20] = {{955,50}}
    f.serverItems[955] = 200; f.inventory:add(955,200)
    f.beforeDeposit = function() error("Seed return denied") end
    f.hooks.takeControls()
    rejects(function() f.hooks.runTransfer(1) end,"Seed return denied")
    assert(f.app.resume.phase == "seedReturnPending" and f.serverItems[955] == 200)
end)

test("Harvest refills seed room independently of block room and finishes both stacks", function()
    local f = zigzagHarvestFixture()
    f.addDrop(11,955,450,7.5,2.5)
    f.addDrop(12,954,30,7.5,2.5)
    f.harvest()
    assert(#f.drops == 0 and f.app.stats.harvestSeeds == 450 and f.app.stats.stashedSeeds == 450)
    assert(f.hooks.Core.itemCount(f.boxes[12],955) == 450 and f.hooks.Core.itemCount(f.boxes[12],954) == 30)
    assert(f.app.stats.harvested == 30 and f.app.pending == 0)
end)

test("Seed-only harvest visits its row and restores an already-worn tractor without cutting another crop", function()
    local f = treeHarvestFixture("fist")
    f.worn, f.world.riding = 898, {harvest=true,speed=3.6}
    f.addTree(2,4,true,627)
    f.addDrop(11,955,20,7.5,2.5)
    f.harvest()
    assert(f.app.stats.stashedSeeds == 20 and #f.treeActions == 0 and f.world.fg[4][2] == 627 and f.worn == 898)
end)

local function rotationFixture()
    local f = mixedTransferFixture()
    f.app.job, f.app.jobToken = nil, nil
    f.app.config.planting = {seedId=955, storageWorld="BREAK", worlds={"FARM","FARM2"}}
    f.app.config.points.plantBox = f.app.config.points.seedBox
    f.app.config.points.seedBox.standX = 9
    f.app.config.points.blockBox.standX = 11
    f.app.config.options.harvestRespawn = false
    f.app.config.rotation.farms = {}
    f.grids, f.worldDrops, f.treeTimes = {}, {}, {}
    f.worldBoxes = {FARM={[0]={}}, FARM2={[0]={}}, BREAK={[12]={},[8]={{955,10}}}}
    for _, name in ipairs({"FARM","FARM2","BREAK"}) do
        local grid = {}
        for y = 0,19 do grid[y]={}; for x=0,29 do grid[y][x]=0 end end
        for x = 0, (name == "BREAK" and 14 or 5) do grid[9][x]=2 end
        if name == "BREAK" then grid[8][8],grid[8][12]=1422,1422
        else
            grid[8][0]=1422
            for y=0,7 do grid[y][0]=2 end
            f.app.config.rotation.farms[name]={world=name,x=0,y=8,standX=1,standY=8}
        end
        f.grids[name], f.worldDrops[name], f.treeTimes[name] = grid,{},{}
    end
    f.app.config.points.farmBox = f.app.config.rotation.farms.FARM
    f.world.fg, f.drops = f.grids.FARM, f.worldDrops.FARM
    f.world.name, f.avatar.x, f.avatar.y = "FARM",1.5,8.999
    f.world.dropList = function() return f.worldDrops[f.world.name] end
    f.world.dropTaken = function(uid, remaining)
        for index, drop in ipairs(f.drops) do
            if drop.uid == uid then drop.n=remaining; if remaining == 0 then table.remove(f.drops,index) end; return end
        end
    end
    f.entries, f.plants, f.harvests, f.pnbBlocks, f.uid = {}, {}, {}, 0, 0
    f.world.enter = function(name)
        f.entries[#f.entries+1] = name
        f.world.name, f.world.fg, f.drops = name, f.grids[name], f.worldDrops[name]
        f.avatar.x, f.avatar.y, f.avatar.vx, f.avatar.vy = name == "BREAK" and 10.5 or 1.5,8.999,0,0
        f.avatar.active, f.avatar.dead, f.avatar.grounded = true,false,true
        return true
    end
    f.app.runtime.items[955].grow = 100
    f.app.runtime.items[1422].solid = true
    f.app.runtime.body.solidAt = function(x,y)
        if x < 0 or x >= f.world.w or y >= f.world.h then return true end
        local item = f.app.runtime.items[f.world.fg[y] and f.world.fg[y][x] or 0]
        return item and item.solid or false
    end
    f.app.runtime.treeRipe = function(x,y)
        local planted = f.treeTimes[f.world.name][y*f.world.w+x]
        if planted == nil then return nil end
        return os.clock() >= planted + f.app.runtime.items[955].grow
    end
    f.app.runtime.treeRemaining = function(x,y)
        local planted = f.treeTimes[f.world.name][y*f.world.w+x]
        return planted and math.max(0, planted + f.app.runtime.items[955].grow - os.clock())
    end
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        plantSeed = function(id,x,y)
            assert(f.world.name ~= "BREAK" and f.serverItems[id] > 0)
            f.world.fg[y][x] = id
            f.treeTimes[f.world.name][y*f.world.w+x] = os.clock()
            f.inventory:remove(id,1); f.serverItems[id] = f.serverItems[id]-1
            f.plants[#f.plants+1]={world=f.world.name,x=x,y=y}
        end,
        setTile = function(_,x,y,id)
            assert(f.world.name == "BREAK" and x == 10 and y == 7)
            f.world.fg[y][x]=id; f.serverItems[id]=f.serverItems[id]-1
        end,
        hit = function(x,y)
            local id = f.world.fg[y][x]
            assert(id == 954 or id == 955)
            f.world.fg[y][x]=0
            f.uid=f.uid+2
            if id == 955 then
                assert(f.app.runtime.treeRipe(x,y))
                f.harvests[#f.harvests+1]={world=f.world.name,x=x,y=y}
                f.addDrop(f.uid,954,1,x+0.5,y+0.5)
            else f.pnbBlocks=f.pnbBlocks+1 end
            f.addDrop(f.uid+1,955,1,x+0.5,y+0.5)
        end,
    }
    f.allowMovingPickup = true
    attachPhysics(f,f.hooks.navigationMap(f.app.runtime))
    local physics = f.onWait
    f.onWait = function(dt)
        if f.app.job and f.app.controls then -- Waiting for trees releases movement wrappers.
            physics(dt)
        end
        if f.afterWait then f.afterWait(dt) end
    end
    installToggles(f)
    f.app.runToggles.rotation={Value=false,Set=function(self,v) self.Value=v end}
    return f
end

local function fillGrowingFarms(f, readyIn)
    f.worldBoxes.BREAK[8] = {{955,200}}
    f.worldBoxes.BREAK[12] = {{954,400}}
    for _, name in ipairs(f.app.config.planting.worlds) do
        for x=1,5 do
            f.grids[name][8][x] = 955
            f.treeTimes[name][8*f.world.w+x] = os.clock() + readyIn[name] - f.app.runtime.items[955].grow
        end
    end
end

test("An empty PNB with a saved future deadline recovers loose and stored crop without harvesting growing trees", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=600,FARM2=600})
    f.worldBoxes.BREAK[8],f.worldBoxes.BREAK[12] = {},{}
    f.worldBoxes.FARM[0] = {{954,401},{955,5}}
    f.addDrop(10000,954,3,2.5,8.5)
    f.addDrop(10001,955,2,3.5,8.5)
    f.addDrop(10002,112,7,4.5,8.5)
    f.app.config.options.harvestPlanting = true
    f.hooks.saveRotationResume({phase="waitPNB",worldIndex=1,cycle=1,work=0,seedCargo=0,
        readyAt={FARM=600,FARM2=600},completed={}})
    f.afterWait = function()
        if f.pnbBlocks == 2 then
            local saved = f.hooks.readRotationResume().state
            assert(not saved.completed.FARM and not saved.collectOnly and saved.readyAt.FARM > os.clock())
            f.app:stop()
        end
    end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.worldDrops.FARM == 0 and f.hooks.Core.itemCount(f.worldBoxes.FARM[0],954) == 0)
    assert(#f.harvests == 0 and #f.plants == 0 and f.pnbBlocks == 2)
    assert(f.app.stats.moved == 404 and f.app.stats.harvested == 3 and f.app.stats.harvestSeeds == 2)
    assert(f.serverGems == 107 and f.hooks.Core.itemCount(f.worldBoxes.BREAK[8],955) >= 7)
    assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],954) == 204)
end)

test("Rotation defers an unsupported drop and transfers an 8000-block mixed farm box before PNB", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=2000,FARM2=2000})
    f.worldBoxes.BREAK[12] = {}
    f.worldBoxes.FARM[0] = {{954,8000},{955,3}}
    local inaccessible = f.addDrop(10000,954,9,4.5,1.5)
    f.addDrop(10001,954,1,2.5,8.5)
    f.addDrop(10002,955,2,3.5,8.5)
    f.addDrop(10003,112,7,4.5,8.5)
    f.hooks.saveRotationResume({phase="wait",worldIndex=1,cycle=1,work=0,seedCargo=0,completed={},readyAt={}})
    local hit = f.app.runtime.handlers.hit
    f.app.runtime.handlers.hit = function(x,y)
        if f.world.name == "BREAK" then
            assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[0],954) == 0,
                "PNB must wait for all 8000 farm blocks to be transported")
            assert(f.app.stats.moved == 8001 and f.app.stats.harvestSeeds == 2)
        end
        return hit(x,y)
    end
    local finalState
    f.afterWait = function()
        if f.pnbBlocks == 1 then finalState=f.hooks.readRotationResume().state; f.app:stop() end
    end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.worldDrops.FARM == 1 and f.worldDrops.FARM[1] == inaccessible and inaccessible.n == 9)
    assert(#f.harvests == 0 and #f.plants == 0 and f.app.pending == 0)
    assert(f.serverGems == 107 and f.app.stats.moved == 8001)
    assert(finalState.deferredHarvest.FARM["10000"].id == 954)
    assert(f.app.harvestCollectionRecovery:find("No reachable floor",1,true))
end)

test("Deferred harvest drops survive reloads, avoid repeat visits, and retry after moving", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=2000,FARM2=2000})
    f.worldBoxes.BREAK[12] = {}
    local drop = f.addDrop(10000,955,4,4.5,1.5)
    f.hooks.saveRotationResume({phase="wait",worldIndex=1,cycle=1,work=0,seedCargo=0,completed={},readyAt={},
        deferredHarvest={FARM={["10000"]={id=955,x=4.5,y=1.5,retryAt=300}}}})
    local saved = f.hooks.readRotationResume()
    local moved, finalState = false
    f.afterWait = function()
        if not moved and f.app.status:find("waiting for growing trees",1,true) then
            assert(f.app.rotationState.phase == "waitPNB" and #f.worldDrops.FARM == 1)
            assert(f.app.stats.harvestSeeds == 0, "Deferred drop must not start another collection pass")
            moved = true
            drop.y = 8.5
            f.app.rotationState.readyAt.FARM = 0 -- Next scheduled visit sees its new position.
        elseif moved and f.app.stats.harvestSeeds == 4 and f.world.name == "BREAK" then
            finalState=f.hooks.readRotationResume().state
            f.app:stop()
        end
    end
    f.hooks.start("rotation",saved)
    assert(not f.app.lastError,f.app.lastError)
    assert(moved and #f.worldDrops.FARM == 0 and f.app.stats.harvestSeeds == 4)
    assert(not finalState.deferredHarvest.FARM["10000"])
end)

test("Rotation retries an expired deferred harvest drop and rejects corrupt deferred records", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=2000,FARM2=2000})
    f.worldBoxes.BREAK[12] = {}
    f.addDrop(10000,954,1,2.5,8.5)
    local state = {phase="wait",worldIndex=1,cycle=1,work=0,seedCargo=0,completed={},readyAt={},
        deferredHarvest={FARM={["10000"]={id=954,x=2.5,y=8.5,retryAt=0}}}}
    f.hooks.saveRotationResume(state)
    f.afterWait = function() if f.pnbBlocks == 1 then f.app:stop() end end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.worldDrops.FARM == 0 and f.app.stats.moved == 1)
    state.deferredHarvest.FARM["10000"].retryAt = "bad"
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"deferred harvest location or time")
end)

test("Rotation skips a repeatedly refused drop on its forward row without abandoning other pickups", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=2000,FARM2=2000})
    f.worldBoxes.BREAK[12] = {}
    local refused = f.addDrop(10000,954,9,2.5,8.5)
    f.addDrop(10001,954,1,4.5,8.5)
    local accept = f.accept
    f.accept = function(drop,want)
        if drop.uid == 10000 then return 0 end
        return accept and accept(drop,want) or want
    end
    f.hooks.saveRotationResume({phase="wait",worldIndex=1,cycle=1,work=0,seedCargo=0,completed={},readyAt={}})
    local finalState
    f.afterWait = function()
        if f.pnbBlocks == 1 then finalState=f.hooks.readRotationResume().state; f.app:stop() end
    end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.worldDrops.FARM == 1 and f.worldDrops.FARM[1] == refused and f.app.stats.moved == 1)
    assert(finalState.deferredHarvest.FARM["10000"] and f.app.pending == 0)
    local attempts = 0
    for _,request in ipairs(f.requests) do if request.uid == 10000 then attempts=attempts+1 end end
    assert(attempts == 3, "Isolated refusal must be deferred after three settled attempts")
end)

test("Empty seed/block supply checks the farms once and waits without repeating an empty drain", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=600,FARM2=600})
    f.worldBoxes.BREAK[8],f.worldBoxes.BREAK[12] = {},{}
    f.hooks.saveRotationResume({phase="waitPNB",worldIndex=1,cycle=1,work=0,seedCargo=0,
        readyAt={FARM=600,FARM2=600},completed={}})
    local waited, final = 0
    f.afterWait = function(dt)
        if f.app.status:find("PNB block storage is empty",1,true) then
            waited = waited+dt
            if waited >= 15 then
                final = f.hooks.readRotationResume().state
                f.app:stop()
            end
        end
    end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError,f.app.lastError)
    assert(final.pnbEmpty and final.emptyChecks.FARM and final.emptyChecks.FARM2 and final.phase == "waitPNB")
    local drains = 0
    for _,line in ipairs(f.app.logs) do if line:find("Seed supply exhausted",1,true) then drains=drains+1 end end
    assert(drains == 1 and #f.entries == 5, "Empty supply must not repeat drains or farm changes")
    assert(#f.harvests == 0 and #f.plants == 0 and f.pnbBlocks == 0 and #f.requests == 0)
end)

test("A stock-only transfer resumes across script reset before collecting seeds and resuming PNB", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=600,FARM2=600})
    f.worldBoxes.BREAK[8],f.worldBoxes.BREAK[12] = {},{}
    f.worldBoxes.FARM[0] = {{954,10},{955,7}}
    f.addDrop(10000,954,3,2.5,8.5)
    f.addDrop(10001,112,4,3.5,8.5)
    f.app.config.options.harvestPlanting = true
    f.hooks.saveRotationResume({phase="waitPNB",worldIndex=1,cycle=1,work=0,seedCargo=0,
        readyAt={FARM=600,FARM2=600},completed={}})
    f.env.ClarisGrowbloxLoaderURL = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"
    local queued, enter = 0, f.world.enter
    queue_on_teleport = function() queued=queued+1 end
    f.world.enter = function(name)
        enter(name)
        if name == "BREAK" and f.app.stats.moved == 0 and f.app.rotationState.collectOnly
            and f.app.rotationState.phase == "transfer" then return true,nil,true end
        return true
    end
    f.afterWait = function() if f.app.teleporting then f.app.alive=false end end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    local runtime, saved = f.app.runtime, f.hooks.readRotationResume()
    assert(queued == 1 and saved.state.collectOnly and saved.state.transfer.phase == "deliver")
    assert(saved.state.pnbEmpty and #f.harvests == 0 and #f.plants == 0 and #f.worldDrops.FARM == 0)
    f.hooks = f.reload()
    f.app = f.hooks.App
    f.app.runtime, f.app.config, f.app.profile = runtime, saved.config, saved.profile
    f.world.enter = enter
    f.afterWait = function() if f.pnbBlocks == 2 then f.app:stop() end end
    f.hooks.start("rotation",saved)
    queue_on_teleport = nil
    assert(not f.app.lastError,f.app.lastError)
    assert(f.pnbBlocks == 2 and #f.harvests == 0 and #f.plants == 0 and f.serverGems == 104)
    assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[0],954) == 0 and f.hooks.Core.itemCount(f.worldBoxes.FARM[0],955) == 0)
    assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[8],955) >= 7)
end)

test("PNB claims leftover blocks/seeds/gems before treating empty storage as exhausted", function()
    local f = rotationFixture()
    f.world.enter("BREAK")
    f.worldBoxes.BREAK[8],f.worldBoxes.BREAK[12] = {},{}
    f.addDrop(10000,954,1,10.5,8.5)
    f.addDrop(10001,955,3,10.5,8.5)
    f.addDrop(10002,112,4,10.5,8.5)
    f.app.job,f.app.token = "pnb",1
    f.hooks.takeControls()
    assert(f.hooks.runPNB(1) == true)
    assert(f.pnbBlocks == 1 and #f.worldDrops.BREAK == 0 and f.serverGems == 104)
    assert(f.serverItems[955] == 4 and f.inventory:count(955) == 4 and f.app.pending == 0)
end)

test("Saved stock recovery cannot approve tree harvesting or accept malformed empty-supply state", function()
    local f = rotationFixture()
    local state = {phase="harvest",worldIndex=1,cycle=1,work=0,seedCargo=0,
        collectOnly=true,harvestPass={world="FARM",phase="trees"}}
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"Stock collection cannot start a tree harvest")
    state.harvestPass.phase = "collect"
    f.hooks.saveRotationResume(state)
    assert(f.hooks.readRotationResume().state.collectOnly)
    state.collectOnly,state.harvestPass,state.phase,state.pnbEmpty = nil,nil,"waitPNB","yes"
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"Invalid saved PNB supply state")
    state.pnbEmpty,state.emptyChecks = true,{FARM=1}
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"Invalid saved rotation schedule value")
end)

test("Existing farm stock is recovered without harvesting growing trees or delaying a ready farm", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=0})
    f.treeTimes.FARM[8*f.world.w+1]=0-f.app.runtime.items[955].grow
    f.worldBoxes.FARM[0]={{954,1},{955,1}}
    f.addDrop(10000,954,1,2.5,8.5)
    f.afterWait=function() if #f.harvests==5 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.harvests==5 and f.harvests[1].world=="FARM2" and #f.worldDrops.FARM==0)
    assert(f.hooks.Core.storageCount(f.worldBoxes.FARM[0],954,955)==0 and f.app.stats.moved==2)
end)

test("An unapproved immature harvest recovers stored stock without breaking or planting trees", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=200})
    f.worldBoxes.FARM[0]={{954,1}}
    f.app.config.options.harvestPlanting=true
    f.hooks.saveRotationResume({phase="harvest",worldIndex=1,cycle=1,work=0,seedCargo=0,completed={},readyAt={}})
    f.afterWait=function() if f.pnbBlocks==2 then f.app:stop() end end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.harvests==0 and #f.plants==0 and f.pnbBlocks==2)
    assert(f.hooks.Core.storageCount(f.worldBoxes.FARM[0],954,955)==0 and f.app.stats.moved==1)
end)

test("Combined rotation loads PNB seeds and replants both ripe farms during harvest before breaking", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=0,FARM2=0})
    f.app.config.options.harvestPlanting=true
    local plant=f.app.runtime.handlers.plantSeed
    f.app.runtime.handlers.plantSeed=function(id,x,y)
        assert(f.app.rotationState.phase=="harvest" and f.pnbBlocks==0,
            "Cleared ripe farms should replant in their harvest pass before PNB")
        assert(f.serverItems[id]>0 and f.hooks.Core.storageCount(f.worldBoxes.BREAK[8],955)==0,
            "Stock should be loaded from the PNB box before harvesting")
        plant(id,x,y)
    end
    f.afterWait=function() if f.app.stats.cycles==1 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.harvests==10 and #f.plants==10 and f.app.stats.planted==10 and f.pnbBlocks==0)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954)==410)
end)

test("Full Rotation transports blocks to PNB independently of standalone Seeds and destination settings", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=0,FARM2=0})
    f.app.config.moving.item = "seeds"
    f.app.config.points.moveBox = f.app.config.points.farmBox
    f.afterWait = function() if f.app.stats.cycles == 1 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.harvests == 10 and f.app.stats.moved == 10)
    assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],954) == 410)
    assert(f.hooks.Core.itemCount(f.worldBoxes.BREAK[12],955) == 0)
    assert(f.hooks.Core.itemCount(f.worldBoxes.FARM[0],954) == 0)
end)

test("Rotation retries combined harvest collection before leaving a newly replanted farm", function()
    local f = rotationFixture()
    fillGrowingFarms(f,{FARM=0,FARM2=0})
    f.app.config.options.harvestPlanting = true
    local interrupted, retrying, enter = false, false, f.world.enter
    f.afterWait = function()
        if f.app.status:find("Retrying rotation phase harvest",1,true) then retrying = true end
        if not retrying and #f.harvests == 5 and f.app.harvestPhase == "Collecting blocks, seeds and gems" then
            interrupted = true
            error("Returning to the saved position timed out. Check the route.")
        end
        if f.app.stats.cycles == 1 then f.app:stop() end
    end
    f.world.enter = function(name)
        if name == "BREAK" and #f.harvests >= 5 then
            assert(#f.worldDrops.FARM == 0, "Rotation must collect the first farm before leaving for PNB")
            if #f.harvests == 10 then assert(#f.worldDrops.FARM2 == 0) end
        end
        return enter(name)
    end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(interrupted and retrying and #f.harvests == 10 and #f.plants == 10)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954) == 410)
    assert(f.app.stats.stashed == 10 and f.app.stats.stashedSeeds == 400 and f.app.stats.cycles == 1)
    assert(not f.app.rotationState or f.app.rotationState.harvestPass == nil)
end)

test("Saved harvest passes cannot apply another farm's approval or collect an unconfirmed seed batch", function()
    local f = rotationFixture()
    local state = {phase="harvest",worldIndex=1,cycle=1,work=0,seedCargo=0,
        harvestPass={world="FARM2",phase="collect"}}
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"Invalid saved harvest pass")
    state.harvestPass = {world="FARM",phase="collect"}
    state.harvestPlant = {worldIndex=1,phase="farm",skipped={},
        pending={world="FARM",x=1,y=8,before=1,tiles={{x=1,y=8}}}}
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"unconfirmed planting batch")
    state.harvestPlant.pending, state.harvestPass.phase = nil, "trees"
    f.hooks.saveRotationResume(state)
    assert(f.hooks.readRotationResume().state.harvestPass.phase == "trees")
    state.phase = "wait"
    f.hooks.saveRotationResume(state)
    rejects(f.hooks.readRotationResume,"Invalid saved harvest pass")
end)

test("An interrupted harvest stock withdrawal never retries its storage request on resume", function()
    local f=rotationFixture()
    f.app.config.options.harvestPlanting=true
    f.hooks.saveRotationResume({phase="harvestPickupPending",worldIndex=1,cycle=1,work=0,seedCargo=0})
    local saved=f.hooks.readRotationResume()
    f.server=function() error("No server request may run for ambiguous harvest stock") end
    f.hooks.start("rotation",saved)
    assert(f.app.lastError:find("harvest seed withdrawal was interrupted",1,true))
    assert(#f.entries==0 and #f.plants==0 and #f.harvests==0)
end)

test("Combined rotation automatically refills and replants the spaces left after carried seeds run out", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=0,FARM2=0})
    f.worldBoxes.BREAK[8]={{955,3}}
    f.app.config.options.harvestPlanting=true
    local plant,phases=f.app.runtime.handlers.plantSeed,{}
    f.app.runtime.handlers.plantSeed=function(id,x,y)
        assert(f.pnbBlocks==0)
        phases[#phases+1]=f.app.rotationState.phase
        plant(id,x,y)
    end
    f.afterWait=function() if f.app.stats.cycles==1 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    local combined,refilled=0,0
    for _,phase in ipairs(phases) do
        if phase=="harvest" then combined=combined+1
        elseif phase=="replant" then refilled=refilled+1 end
    end
    assert(combined==6 and refilled==4 and #f.harvests==10 and f.app.stats.planted==10)
end)

test("Harvest stock world-change checkpoints retain the combined setting and farm target", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=0,FARM2=0})
    f.app.config.options.harvestPlanting=true
    f.env.ClarisGrowbloxLoaderURL="https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"
    local queued,enter={},f.world.enter
    queue_on_teleport=function(code) queued[#queued+1]=code end
    f.world.enter=function(name) enter(name); return true,nil,true end
    f.afterWait=function() if f.app.teleporting then f.app.alive=false end end
    f.hooks.saveRotationResume({phase="harvestStock",worldIndex=2,cycle=1,work=0,seedCargo=0})
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(#queued==1 and queued[1]:find("ClarisGrowbloxAutoResume = true",1,true))
    local next=f.reload()
    local saved=next.readRotationResume()
    assert(saved.state.phase=="harvestStock" and saved.state.worldIndex==2 and saved.config.options.harvestPlanting)
    queue_on_teleport=nil
end)

test("Full growing farms skip planting with seed stock available and run PNB while waiting", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=200})
    f.afterWait=function() if f.pnbBlocks == 3 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.plants == 0 and #f.harvests == 0 and f.pnbBlocks == 3)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[8],955) == 200)
    assert(#f.entries == 2 and f.entries[1] == "FARM2" and f.entries[2] == "BREAK")
end)

test("Repeated transient walking timeouts keep rotation active and retry the saved phase after cooldown", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=200})
    local plan,calls,cooled=f.hooks.Navigation.plan,0,false
    f.hooks.Navigation.plan=function(...)
        calls=calls+1
        if calls<=3 then error("Returning to the saved position timed out. Check the route.") end
        return plan(...)
    end
    f.afterWait=function()
        if f.app.navigationRecovery and f.app.navigationRecovery:find("Retrying rotation phase",1,true) then
            cooled=true
            assert(f.app.job=="rotation" and f.app.runToggles.rotation.Value)
            assert(f.hooks.readRotationResume().state.phase=="waitPNB")
        end
        if f.pnbBlocks==1 then f.app:stop() end
    end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(cooled and calls>3 and f.pnbBlocks==1 and #f.harvests==0)
end)

test("A refused planting tile leaves full rotation active and moves on to farm waiting", function()
    local f=rotationFixture()
    local plant,rejected,keptRunning=f.app.runtime.handlers.plantSeed,false,false
    f.app.runtime.handlers.plantSeed=function(id,x,y)
        plant(id,x,y)
        if f.world.name=="FARM" and x==1 and not rejected then
            rejected=true
            f.world.fg[y][x],f.treeTimes.FARM[y*f.world.w+x]=0,nil
            f.serverItems[id]=f.serverItems[id]+1
        end
    end
    f.afterWait=function()
        if f.app.stats.planted==9 and f.app.status:find("PNB block storage is empty",1,true) then
            keptRunning=true
            assert(f.app.job=="rotation" and f.app.runToggles.rotation.Value)
            assert(f.hooks.readRotationResume().state.phase=="waitPNB")
            f.app:stop()
        end
    end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(rejected and keptRunning and #f.plants==10 and f.app.stats.planted==9)
    assert(f.grids.FARM[8][1]==0 and #f.harvests==0)
end)

test("Harvest deadlines interrupt PNB with blocks remaining and the cleared farm is replanted first", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=40,FARM2=200})
    local brokenAtHarvest, brokenAtPlant
    local hit,plant=f.app.runtime.handlers.hit,f.app.runtime.handlers.plantSeed
    f.app.runtime.handlers.hit=function(x,y)
        if f.world.name ~= "BREAK" and not brokenAtHarvest then brokenAtHarvest=f.pnbBlocks end
        hit(x,y)
    end
    f.app.runtime.handlers.plantSeed=function(...)
        brokenAtPlant=brokenAtPlant or f.pnbBlocks
        plant(...)
    end
    f.afterWait=function() if #f.plants == 5 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(brokenAtHarvest > 0 and brokenAtHarvest == brokenAtPlant and brokenAtPlant == f.pnbBlocks)
    assert(#f.harvests == 5 and f.harvests[1].world == "FARM" and #f.plants == 5)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954) > 0, "PNB must yield before draining storage")
    assert(f.grids.BREAK[7][10] == 0 and #f.worldDrops.BREAK == 0 and f.app.pending == 0,
        "The current PNB block and its pickups must settle before leaving")
end)

test("A later farm that matures first has harvest priority over an earlier growing farm", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=40})
    f.afterWait=function() if #f.plants == 5 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(f.pnbBlocks > 0 and #f.harvests == 5 and f.harvests[1].world == "FARM2")
    assert(#f.plants == 5 and f.plants[1].world == "FARM2")
end)

test("Empty PNB storage waits in the breaking world without repeated farm travel or planting", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=200})
    f.worldBoxes.BREAK[12]={}
    local waits=0
    f.afterWait=function()
        if f.app.status:find("PNB block storage is empty",1,true) then
            waits=waits+1
            if waits == 3 then f.app:stop() end
        end
    end
    f.hooks.start("rotation")
    assert(not f.app.lastError and f.pnbBlocks == 0 and #f.plants == 0 and #f.harvests == 0)
    assert(#f.entries == 2 and f.world.name == "BREAK" and f.withdrawals == 0)
end)

test("Seed exhaustion drains every stored PNB block before resuming unfinished planting", function()
    local f=rotationFixture()
    f.worldBoxes.BREAK[8],f.worldBoxes.BREAK[12]={},{{954,10}}
    f.afterWait=function() if #f.plants == 3 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.plants == 3 and f.pnbBlocks == 10 and #f.harvests == 0)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954) == 0)
end)

test("Empty seed stock defers already-ripe farms until all PNB blocks and pickups finish", function()
    local f = rotationFixture()
    fillGrowingFarms(f, {FARM=0, FARM2=0})
    f.worldBoxes.BREAK[8], f.worldBoxes.BREAK[12] = {}, {{954,4}}
    local hit = f.app.runtime.handlers.hit
    f.app.runtime.handlers.hit = function(x,y)
        if f.world.name ~= "BREAK" then
            assert(f.pnbBlocks == 4 and f.serverItems[954] == 0 and #f.worldDrops.BREAK == 0,
                "Ripe harvest must wait for the entire PNB drain and pickups")
            assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954) == 0)
            assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[8],955) == 4)
        end
        hit(x,y)
    end
    f.afterWait = function() if #f.harvests == 5 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.pnbBlocks == 4 and #f.harvests == 5 and #f.plants == 0)
end)

test("Using the final seeds to fill every farm still drains PNB before ripe harvest", function()
    local f = rotationFixture()
    f.worldBoxes.BREAK[12] = {{954,4}}
    f.app.runtime.items[955].grow = 0.01
    local hit = f.app.runtime.handlers.hit
    f.app.runtime.handlers.hit = function(x,y)
        if f.world.name ~= "BREAK" then assert(f.pnbBlocks == 4 and #f.plants == 10) end
        hit(x,y)
    end
    f.afterWait = function() if #f.harvests == 5 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError, f.app.lastError)
    assert(f.pnbBlocks == 4 and #f.plants == 10 and #f.harvests == 5)
end)

test("A saved PNB drain stays active after reload even when breaking has produced seeds", function()
    local f = rotationFixture()
    fillGrowingFarms(f, {FARM=0, FARM2=0})
    f.worldBoxes.BREAK[8], f.worldBoxes.BREAK[12] = {{955,3}}, {{954,4}}
    f.hooks.saveRotationResume({phase="drainPNB", worldIndex=1, cycle=1, work=3, seedCargo=0,
        readyAt={FARM=0,FARM2=0}, completed={}, seedWait=true})
    local runtime, next = f.app.runtime, f.reload()
    f.hooks, f.app = next, next.App
    f.app.runtime = runtime
    local saved = next.readRotationResume()
    f.app.config, f.app.profile = saved.config, saved.profile
    local hit = runtime.handlers.hit
    runtime.handlers.hit = function(x,y)
        if f.world.name ~= "BREAK" then assert(f.pnbBlocks == 4) end
        hit(x,y)
    end
    f.afterWait = function() if #f.harvests == 5 then f.app:stop() end end
    next.start("rotation", saved)
    assert(not f.app.lastError, f.app.lastError)
    assert(f.pnbBlocks == 4 and #f.harvests == 5 and #f.plants == 0)
end)

test("Stop interrupts a depleted-seed PNB drain before harvest or planting", function()
    local f = rotationFixture()
    fillGrowingFarms(f, {FARM=0,FARM2=0})
    f.worldBoxes.BREAK[8], f.worldBoxes.BREAK[12] = {}, {{954,10}}
    f.afterWait = function() if f.pnbBlocks == 2 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError and f.pnbBlocks == 2 and #f.harvests == 0 and #f.plants == 0)
    assert(f.hooks.readRotationResume() == nil)
end)

test("Invalid saved seed-check and PNB drain phases cannot bypass checkpoint validation", function()
    local f = rotationFixture()
    f.hooks.saveRotationResume({phase="drainPNB",worldIndex=1,cycle=1,work=0,seedCargo=201})
    rejects(f.hooks.readRotationResume, "seed cargo")
    f.hooks.saveRotationResume({phase="checkSeeds",worldIndex=1,cycle=1,work=0,seedCargo=0})
    assert(f.hooks.readRotationResume().state.phase == "checkSeeds")
end)

test("World-change execution queues the loader and restores rotation config and PNB schedule after a reset", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=250})
    f.app.profile="Cloud Rotation"
    f.env.ClarisGrowbloxLoaderURL="https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/loader.lua"
    local queued,enter={},f.world.enter
    queue_on_teleport=function(code) queued[#queued+1]=code end
    f.world.enter=function(name)
        enter(name)
        if name == "BREAK" then return true,nil,true end
        return true
    end
    f.afterWait=function() if f.app.teleporting then f.app.alive=false end end
    f.hooks.start("rotation")
    assert(#queued == 1 and queued[1]:find("ClarisGrowbloxAutoResume = true",1,true))
    assert(queued[1]:find(f.env.ClarisGrowbloxLoaderURL,1,true))
    local runtime=f.app.runtime
    local next=f.reload()
    f.hooks,f.app=next,next.App
    f.app.runtime=runtime
    local saved=next.readRotationResume()
    assert(saved.state.phase == "checkSeeds" and saved.state.readyAt.FARM > f.services.Workspace:GetServerTimeNow())
    assert(saved.profile == "Cloud Rotation" and saved.config.planting.worlds[2] == "FARM2")
    assert(saved.config.points.pnb.world == "BREAK" and saved.config.rotation.farms.FARM2.x == 0)
    f.app.config,f.app.profile=saved.config,saved.profile
    f.world.enter=enter
    f.entries={}
    f.afterWait=function() if f.pnbBlocks == 2 then f.app:stop() end end
    next.start("rotation",saved)
    queue_on_teleport=nil
    assert(not f.app.lastError and f.pnbBlocks == 2 and #f.entries == 0 and #f.plants == 0 and #f.harvests == 0)
    assert(#queued == 2, "Each fresh script must register its world-change execution again")
end)

test("A past saved server-time deadline resumes harvest before placing another PNB block", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=0,FARM2=200})
    local clock=os.clock
    f.services.Workspace.GetServerTimeNow=function() return 5000+clock() end
    f.app.runtime.treeRipe=function(x,y)
        local planted=f.treeTimes[f.world.name][y*f.world.w+x]
        return planted and clock() >= planted+f.app.runtime.items[955].grow
    end
    f.hooks.saveRotationResume({phase="waitPNB",worldIndex=1,cycle=1,work=0,seedCargo=0,
        completed={},readyAt={FARM=5000,FARM2=5200}})
    task.wait(1000)
    os.clock=function() return clock()-1000 end -- Executor uptime changes; server time does not.
    f.afterWait=function() if #f.harvests == 5 then f.app:stop() end end
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(not f.app.lastError and f.pnbBlocks == 0 and #f.harvests == 5 and f.harvests[1].world == "FARM")
end)

test("A storage withdrawal that crosses the harvest deadline never places another PNB block", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=40,FARM2=200})
    local server,delayed=f.server,false
    f.server=function(name,x,...)
        local results=table.pack(server(name,x,...))
        if name == "DisplayItem" and x == 12 and not delayed then delayed=true; task.wait(60) end
        return table.unpack(results,1,results.n)
    end
    f.afterWait=function() if #f.harvests == 5 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(delayed and f.pnbBlocks == 0 and #f.harvests == 5 and f.inventory:count(954) == 0)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954) == 400)
end)

test("A reset during replant restores its config and reconciles the confirmed seed without planting twice", function()
    local f=rotationFixture()
    fillGrowingFarms(f,{FARM=200,FARM2=200})
    for x=1,5 do f.grids.FARM2[8][x]=0; f.treeTimes.FARM2[8*f.world.w+x]=nil end
    f.grids.FARM2[8][1],f.treeTimes.FARM2[8*f.world.w+1]=955,os.clock()
    f.serverItems[955]=9; f.inventory:add(955,9)
    f.app.profile="Replant Recovery"
    f.hooks.saveRotationResume({phase="replant",worldIndex=2,cycle=1,work=10,seedCargo=0,
        completed={FARM=true},readyAt={},plant={phase="farm",worldIndex=2,skipped={},
            pending={world="FARM2",x=1,y=8,before=10}}})
    local runtime=f.app.runtime
    local next=f.reload()
    f.hooks,f.app=next,next.App
    f.app.runtime=runtime
    local saved=next.readRotationResume()
    f.app.config,f.app.profile=saved.config,saved.profile
    f.afterWait=function() if f.app.stats.cycles == 1 then f.app:stop() end end
    next.start("rotation",saved)
    assert(not f.app.lastError,f.app.lastError)
    assert(f.app.profile == "Replant Recovery" and #f.plants == 4 and f.app.stats.planted == 5)
    assert(f.plants[1].x == 2 and f.plants[1].world == "FARM2" and #f.harvests == 0 and f.pnbBlocks == 0)
end)

test("A fresh rotation instance restores multiple pending replant seeds without replaying them", function()
    local f = rotationFixture()
    fillGrowingFarms(f, {FARM = 200, FARM2 = 200})
    for x = 1, 5 do f.grids.FARM2[8][x] = 0; f.treeTimes.FARM2[8 * f.world.w + x] = nil end
    for x = 1, 3 do f.grids.FARM2[8][x] = 955; f.treeTimes.FARM2[8 * f.world.w + x] = os.clock() end
    f.serverItems[955] = 7; f.inventory:add(955, 7)
    local plant = f.app.runtime.handlers.plantSeed
    f.app.runtime.handlers.plantSeed = function(...)
        plant(...)
        assert(f.hooks.readRotationResume().state.plant.pending.tiles,
            "Saved rotation row cursors must resume batch planting after repositioning")
    end
    f.hooks.saveRotationResume({phase = "replant", worldIndex = 2, cycle = 1, work = 10, seedCargo = 0,
        completed = {FARM = true}, readyAt = {}, plant = {phase = "farm", worldIndex = 2, skipped = {},
            rows = {{y = 8, left = 1, right = 5}}, rowY = 8,
            pending = {world = "FARM2", x = 1, y = 8, before = 10,
                tiles = {{x = 1, y = 8}, {x = 2, y = 8}, {x = 3, y = 8}}}}})
    local runtime, next = f.app.runtime, f.reload()
    f.hooks, f.app = next, next.App
    f.app.runtime = runtime
    local saved = next.readRotationResume()
    assert(#saved.state.plant.pending.tiles == 3)
    f.app.config, f.app.profile = saved.config, saved.profile
    f.afterWait = function() if f.app.stats.cycles == 1 then f.app:stop() end end
    next.start("rotation", saved)
    assert(not f.app.lastError, f.app.lastError)
    assert(#f.plants == 2 and f.plants[1].x == 4 and f.plants[2].x == 5 and f.app.stats.planted == 5)
    assert(#f.harvests == 0 and f.pnbBlocks == 0)
end)

test("Invalid saved harvest deadlines are rejected before rotation can enter a world", function()
    local f=rotationFixture()
    f.hooks.saveRotationResume({phase="waitPNB",worldIndex=1,cycle=1,work=0,seedCargo=0,
        completed={},readyAt={FARM=-1}})
    rejects(f.hooks.readRotationResume,"schedule value")
    assert(#f.entries == 0 and f.pnbBlocks == 0)
end)

test("An interrupted PNB inventory deposit pauses rotation without replaying storage or travel", function()
    local f=rotationFixture()
    f.hooks.saveRotationResume({phase="pnbStorePending",worldIndex=1,cycle=1,work=0,seedCargo=0})
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(f.app.lastError:find("storage request was interrupted",1,true) and #f.entries == 0 and f.withdrawals == 0)
    assert(f.hooks.readRotationResume().state.phase == "pnbStorePending")
end)

test("Full rotation plants both farms, waits for maturity, harvests seeds and blocks, runs PNB, and repeats", function()
    local f = rotationFixture()
    local waited = false
    f.afterWait = function()
        if f.app.status:find("growing trees",1,true) and not f.app.controls then
            waited=true
            assert(f.controls.dir() == -1 and f.controls.jumping() == true, "Maturity waits release original controls")
        end
        if f.app.stats.cycles == 2 then f.app:stop() end
    end
    f.hooks.start("rotation")
    assert(not f.app.lastError, f.app.lastError)
    assert(waited and f.app.stats.cycles == 2 and f.pnbBlocks == 15 and #f.harvests == 20, "wait=" .. tostring(waited) .. " cycles=" .. f.app.stats.cycles .. " PNB=" .. f.pnbBlocks .. " trees=" .. #f.harvests .. " plants=" .. #f.plants)
    assert(#f.plants == 30 and f.plants[1].world == "FARM" and f.plants[6].world == "FARM2")
    assert(f.plants[11].world == "FARM" and f.plants[16].world == "FARM2")
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[8],955) + f.inventory:count(955) == 15)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[12],954) == 5, "Seed depletion drains PNB stock; subsequent harvest waits for the next growth period")
    assert(f.app.stats.harvestSeeds == 20 and f.app.stats.stashedSeeds >= 20,
        "All harvested seeds are stored, including any held seeds returned with them")
    assert(f.app.job == nil and not f.app.runToggles.rotation.Value and not f.hooks.readRotationResume())
end)

test("A rotation stopped during maturity wait makes no tree, pickup, or PNB actions", function()
    local f = rotationFixture()
    f.app.runtime.items[955].grow = 500
    f.afterWait = function()
        if f.app.status:find("growing trees",1,true) then f.app:stop() end
    end
    f.hooks.start("rotation")
    assert(not f.app.lastError and #f.plants == 10 and #f.harvests == 0 and #f.requests == 0 and f.pnbBlocks == 0)
    assert(not f.hooks.readRotationResume())
end)

test("Saved rotation resumes the second farm's transfer and replants only that farm without repeating its harvest", function()
    local f = rotationFixture()
    f.worldBoxes.FARM2[0]={{955,5}}
    f.worldBoxes.BREAK[12]={{954,5}}
    f.serverItems[955]=200; f.inventory:add(955,200)
    f.hooks.saveRotationResume({phase="transfer",worldIndex=2,cycle=1,work=10,seedCargo=0,
        transfer={phase="return",cargo=0,seeds=200}})
    local saved=f.hooks.readRotationResume()
    f.afterWait=function() if f.app.stats.cycles == 1 then f.app:stop() end end
    f.hooks.start("rotation",saved)
    assert(not f.app.lastError,f.app.lastError)
    assert(#f.plants == 5 and f.plants[1].world == "FARM2" and #f.harvests == 0 and f.pnbBlocks == 0 and f.app.stats.cycles == 1)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[8],955) + f.inventory:count(955) == 210)
end)

test("Ambiguous rotation seed withdrawals pause before world entry or additional storage mutations", function()
    local f=rotationFixture()
    f.hooks.saveRotationResume({phase="seedPickupPending",worldIndex=1,cycle=1,work=10,seedCargo=0})
    f.hooks.start("rotation",f.hooks.readRotationResume())
    assert(f.app.lastError:find("storage request was interrupted",1,true) and #f.entries == 0 and f.withdrawals == 0)
    assert(f.hooks.readRotationResume().state.phase == "seedPickupPending")
end)

test("Rotation reconciles a planted seed after a picker interruption and continues the farm list", function()
    local f=rotationFixture()
    local plant=f.app.runtime.handlers.plantSeed
    local interrupted=false
    f.app.runtime.handlers.plantSeed=function(...)
        plant(...)
        if not interrupted then
            interrupted=true
            f.world.name,f.avatar.active="",false
        end
    end
    f.afterWait=function() if f.app.stats.cycles == 1 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(interrupted and #f.plants == 20 and #f.harvests == 10 and f.pnbBlocks == 5)
    assert(f.app.stats.planted == 20 and f.app.stats.cycles == 1)
end)

test("Rotation rejoins PNB after an interrupted break without placing or harvesting twice", function()
    local f=rotationFixture()
    f.worldBoxes.BREAK[12]={{954,10}}
    local hit=f.app.runtime.handlers.hit
    local interrupted=false
    f.app.runtime.handlers.hit=function(...)
        hit(...)
        if f.world.name == "BREAK" and not interrupted then
            interrupted=true
            f.world.name,f.avatar.active="",false
        end
    end
    f.afterWait=function() if f.app.stats.cycles == 1 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError,f.app.lastError)
    assert(interrupted and #f.plants == 20 and #f.harvests == 10 and f.pnbBlocks == 10)
    assert(f.hooks.Core.storageCount(f.worldBoxes.BREAK[8],955) + f.inventory:count(955) == 10)
end)

test("An empty rotation with no seeds or crop pauses after checking the list instead of repeating empty travel", function()
    local f=rotationFixture()
    f.worldBoxes.BREAK[8]={}
    f.hooks.start("rotation")
    assert(f.app.lastError:find("no harvest or stored crop",1,true))
    assert(#f.plants == 0 and #f.harvests == 0 and f.pnbBlocks == 0 and f.app.stats.cycles == 0)
    assert(#f.entries < 15)
end)

test("Rotation recovery files preserve progress independently and reject account or phase corruption", function()
    local f=rotationFixture()
    local state={phase="wait",worldIndex=2,cycle=3,work=10,seedCargo=0}
    f.hooks.saveRotationResume(state)
    state.worldIndex=1
    local saved=f.hooks.readRotationResume()
    assert(saved.state.worldIndex == 2 and saved.state.cycle == 3)
    saved.userId=999
    rejects(f.hooks.readRotationResume,"another account")
    saved.userId=f.player.UserId; saved.state.phase="unknown"
    rejects(f.hooks.readRotationResume,"rotation phase")
end)

test("Export includes unsaved settings and all farm locations without exporting running-task state", function()
    local f=rotationFixture()
    f.app.profile="Emulator Farms"
    f.app.config.harvesting.method="tractor"
    f.app.config.options.collectDelay=0.7
    f.app.job,f.app.pending="rotation",2
    f.app.rotationState={phase="transfer",cargo=100}
    local text,record=f.hooks.exportConfiguration()
    assert(f.services.HttpService:JSONDecode(text) == record and record.profile == "Emulator Farms")
    assert(record.config.options.collectDelay == 0.7 and record.config.rotation.farms.FARM2.world == "FARM2")
    assert(record.userId == nil and record.state == nil and record.active == nil)
    assert(f.app.job == "rotation" and f.app.pending == 2 and onlyMigrationFiles(f.files))
    writefile=nil
    assert(f.hooks.exportConfiguration())
end)

test("Export files preserve the portable format and back up a previous export", function()
    local f=fixture()
    local _,record=f.hooks.exportConfiguration()
    local path=f.hooks.saveConfigExport(record)
    assert(path == "ClarisGrowblox/accounts/1234/exports/Default.json")
    local saved=f.services.HttpService:JSONDecode(f.files[path])
    assert(saved.format == "ClarisGrowbloxConfig" and saved.config.blockId == 954)
    f.app.config.options.collectDelay=0.8
    local _,nextRecord=f.hooks.exportConfiguration()
    assert(f.hooks.saveConfigExport(nextRecord) == path)
    assert(f.services.HttpService:JSONDecode(f.files[path .. ".bak"]).config.options.collectDelay == 0.1)
end)

test("Import on another account persists the whole setup locally and clears old task checkpoints without starting", function()
    local source=rotationFixture()
    source.app.profile="Emulator Farms"
    source.app.config.harvesting.method="tractor"
    source.app.config.webhook.url="https://discord.com/api/webhooks/123/mock_token"
    source.app.config.webhook.enabled=true
    local _,record=source.hooks.exportConfiguration()
    local f=fixture(5678)
    f.app.job,f.app.jobToken=nil,nil
    for _,name in ipairs({"resume","pnb-resume","plant-resume","rotation-resume"}) do
        f.files["ClarisGrowblox/accounts/5678/" .. name .. ".json"]="old local checkpoint"
    end
    f.app.resume,f.app.plantState,f.app.rotationState={cargo=100},{pending=true},{phase="pnb"}
    local text=f.services.HttpService:JSONEncode(record)
    assert(f.hooks.importConfiguration(text,"Cloud Phone Farms") == "Cloud Phone Farms")
    assert(f.app.config.rotation.farms.FARM2.x == 0 and f.app.config.harvesting.method == "tractor")
    assert(f.app.config.webhook.url == source.app.config.webhook.url and f.app.config.webhook.enabled)
    assert(f.app.job == nil and f.app.resume == nil and f.app.plantState == nil and f.app.rotationState == nil)
    assert(f.world.name == "BREAK" and f.avatar.x == 13.5 and f.pickups == 0)
    assert(f.files["ClarisGrowblox/accounts/5678/resume.json"] == nil and f.files["ClarisGrowblox/accounts/5678/rotation-resume.json"] == nil)
    local profile=f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/5678/profiles/Cloud Phone Farms.json"])
    local session=f.services.HttpService:JSONDecode(f.files["ClarisGrowblox/accounts/5678/session.json"])
    assert(profile.planting.worlds[2] == "FARM2" and session.userId == 5678 and session.profile == "Cloud Phone Farms")
    local nextApp=f.reload().App
    assert(nextApp.profile == "Cloud Phone Farms" and nextApp.config.rotation.farms.FARM2.world == "FARM2")
    assert(nextApp.config.points.pnb.x == 10 and nextApp.config.points.plantBox.world == "BREAK" and nextApp.job == nil)
end)

test("Malformed pasted JSON and recovery records cannot change the current setup or checkpoints", function()
    local f=fixture()
    f.app.job=nil
    local config=f.app.config
    f.files["ClarisGrowblox/accounts/1234/resume.json"]="old checkpoint"
    rejects(function() f.hooks.importConfiguration("loadstring(game:HttpGet('example'))()") end,"Invalid configuration JSON")
    rejects(function() f.hooks.importConfiguration(string.rep("x",131073)) end,"too large")
    local recovery=f.services.HttpService:JSONEncode({version=1,userId=123,config=config,phase="deliver",cargo=200})
    rejects(function() f.hooks.importConfiguration(recovery) end,"recovery files")
    assert(f.app.config == config and f.app.profile == "Default" and f.files["ClarisGrowblox/accounts/1234/resume.json"] == "old checkpoint")
    assert(f.files["ClarisGrowblox/accounts/1234/session.json"] == nil)
end)

test("Import refuses a running task or outstanding request before writing files", function()
    local f=fixture()
    local text=f.hooks.exportConfiguration()
    rejects(function() f.hooks.importConfiguration(text) end,"Stop the current task")
    f.app.job,f.app.pending=nil,1
    rejects(function() f.hooks.importConfiguration(text) end,"pending requests")
    assert(onlyMigrationFiles(f.files) and f.app.config.blockId == 954)
end)

test("A failed import save retains the previous profile, session, and recovery state", function()
    local f=fixture()
    f.app.job=nil
    local profilePath="ClarisGrowblox/accounts/1234/profiles/Default.json"
    f.files[profilePath]="previous profile"
    f.hooks.saveSession()
    local priorSession=f.files["ClarisGrowblox/accounts/1234/session.json"]
    f.files["ClarisGrowblox/accounts/1234/resume.json"]="prior cargo"
    local oldConfig=f.app.config
    local _,record=f.hooks.exportConfiguration()
    record.config.blockId=628
    local text=f.services.HttpService:JSONEncode(record)
    local write=writefile
    writefile=function(path,value)
        if path == "ClarisGrowblox/accounts/1234/session.json.pending" then error("disk full") end
        return write(path,value)
    end
    rejects(function() f.hooks.importConfiguration(text) end,"disk full")
    assert(f.app.config == oldConfig and f.app.config.blockId == 954)
    assert(f.files[profilePath] == "previous profile" and f.files["ClarisGrowblox/accounts/1234/session.json"] == priorSession)
    assert(f.files["ClarisGrowblox/accounts/1234/resume.json"] == "prior cargo")
end)

test("Import backs up an existing named profile and accepts a saved profile file", function()
    local f=fixture()
    f.app.job=nil
    local path="ClarisGrowblox/accounts/1234/profiles/Cloud Phone.json"
    f.files[path]="previous cloud setup"
    local config=f.hooks.Core.validate(f.app.config)
    config.options.collectDelay=0.9
    local text=f.services.HttpService:JSONEncode(config)
    f.hooks.importConfiguration(text,"Cloud Phone")
    assert(f.files[path .. ".bak"] == "previous cloud setup" and f.app.profile == "Cloud Phone")
    assert(f.app.config.options.collectDelay == 0.9 and f.app.config.rotation.farms.FARM.x == 20)
end)

test("Work reports describe Full Rotation progress and all harvest counters without pinging", function()
    local f=rotationFixture()
    f.app.job="rotation"
    f.app.rotationState={phase="harvest",worldIndex=2,cycle=3}
    f.app.stats.trees,f.app.stats.harvestSeeds,f.app.stats.stashedSeeds,f.app.stats.cycles=20,8,7,2
    f.hooks.setWebhookSetting("discordId","123456789012345678")
    local payload=f.hooks.webhookPayload(f.app.config,f.app.profile)
    assert(reportField(payload,"Farm status"):find("Full Rotation",1,true))
    assert(reportField(payload,"Rotation progress"):find("Cycle: 3",1,true))
    assert(reportField(payload,"Rotation progress"):find("2/2 (FARM2)",1,true))
    local totals=reportField(payload,"This script session")
    assert(totals:find("Trees harvested: 20",1,true) and totals:find("Harvest seeds collected: 8",1,true))
    assert(totals:find("Harvest seeds stored: 7",1,true) and totals:find("Rotations completed: 2",1,true))
    assert(payload.content == nil and payload.allowed_mentions.users == nil and #payload.allowed_mentions.parse == 0)
end)

test("Failure payloads ping exactly the configured Discord user and suppress all other mentions", function()
    local f=fixture()
    f.hooks.setWebhookSetting("discordId","<@123456789012345678>")
    local payload=f.hooks.webhookPayload(f.app.config,"Fault",{}, {kind="failure",mode="harvest",message="Pickup refused @everyone <@&999999999999999999>"})
    assert(payload.content == "<@123456789012345678> Growblox task failed.")
    assert(#payload.allowed_mentions.users == 1 and payload.allowed_mentions.users[1] == "123456789012345678")
    assert(#payload.allowed_mentions.parse == 0 and payload.allowed_mentions.roles == nil)
    assert(payload.embeds[1].title == "Growblox task failed" and payload.embeds[1].color == 0xE74C3C)
    assert(reportField(payload,"Failure"):find("Pickup refused",1,true))
    f.hooks.setWebhookSetting("discordId","")
    payload=f.hooks.webhookPayload(f.app.config,"Fault",{}, {kind="failure",mode="pnb",message="Failed"})
    assert(payload.content == "Growblox task failed." and payload.allowed_mentions.users == nil)
end)

test("A task failure queues one immediate ping even when periodic reporting is Off", function()
    local f=harvestFixture()
    f.app.job=nil
    f.serverItems[954]=200; f.inventory:add(954,200)
    local server=f.server
    setupWebhook(f)
    f.hooks.setWebhookSetting("discordId","123456789012345678")
    f.server=function(name,...)
        if name == "DisplayItem" then return false,"Farm box access denied" end
        assert(name ~= "GetGems" and name ~= "GetLevel","Failure alerts must not wait for failed game queries")
        return server(name,...)
    end
    f.hooks.start("harvest")
    assert(f.app.lastError and f.app.job == nil and not f.app.config.webhook.enabled)
    assert(#f.app.webhookState.events == 1 and f.app.webhookState.events[1].kind == "failure")
    f.hooks.pollWebhook()
    assert(#f.posts == 1 and #f.app.webhookState.events == 0 and f.app.webhookState.status == "Failure alert sent.")
    local payload=f.encoded[f.posts[1].Body]
    assert(reportField(payload,"Failure"):find("Farm box access denied",1,true))
    assert(reportField(payload,"Farm status"):find("Harvesting",1,true))
    task.wait(60); f.hooks.pollWebhook()
    assert(#f.posts == 1 and f.app.pending == 0 and f.serverItems[954] == 200)
end)

test("Failure alerts can be switched Off and Stop never creates a failure ping", function()
    local f=fixture()
    setupWebhook(f)
    f.hooks.setWebhookSetting("failureAlerts",false)
    assert(not f.hooks.queueWebhookEvent("failure","Error","pnb"))
    f.hooks.setWebhookSetting("failureAlerts",true)
    f.app.job,f.app.jobToken=nil,nil
    f.spawn=function(fn) f.spawn=nil; task.defer(fn) end
    f.hooks.start("pnb")
    f.app:stop(); task.wait(0.01); f.hooks.pollWebhook()
    assert(#f.posts == 0 and #f.app.webhookState.events == 0 and not f.app.lastError)
end)

test("A completed PNB task sends a work report without pinging the failure user", function()
    local f=fixture()
    setupWebhook(f)
    f.app.job,f.app.jobToken=nil,nil
    f.avatar.x=10.5
    f.app.config.points.blockBox.standX=10
    f.boxes[12]={}
    f.server=function(name) assert(name == "GetInventory"); return {slots={},capacity=54} end
    f.hooks.setWebhookSetting("discordId","123456789012345678")
    f.hooks.setWebhookSetting("enabled",true)
    f.hooks.start("pnb")
    assert(not f.app.lastError and #f.app.webhookState.events == 1)
    f.hooks.pollWebhook()
    local payload=f.encoded[f.posts[1].Body]
    assert(payload.embeds[1].title == "Growblox work report" and payload.content == nil)
    assert(reportField(payload,"Farm status"):find("Place & Break",1,true))
    assert(payload.allowed_mentions.users == nil and f.app.webhookState.status == "Work report sent.")
end)

test("Failure reports preserve fault-time progress while waiting behind another request", function()
    local f=rotationFixture()
    setupWebhook(f)
    f.hooks.setWebhookSetting("discordId","123456789012345678")
    f.app.job="rotation"
    f.app.rotationState={phase="transfer",worldIndex=2,cycle=4}
    f.app.stats.trees=12
    f.app.webhookState.inFlight=true
    assert(f.hooks.queueWebhookEvent("failure","Lost crop cargo","rotation"))
    f.hooks.pollWebhook(); assert(#f.posts == 0)
    f.app.stats.trees=99
    f.app.rotationState={phase="plant",worldIndex=1,cycle=5}
    f.app.webhookState.inFlight=false
    f.hooks.pollWebhook()
    local payload=f.encoded[f.posts[1].Body]
    assert(reportField(payload,"Rotation progress"):find("Cycle: 4",1,true))
    assert(reportField(payload,"Rotation progress"):find("Phase: transfer",1,true))
    assert(reportField(payload,"This script session"):find("Trees harvested: 12",1,true))
end)

test("Late successful failure delivery is acknowledged without posting a duplicate ping", function()
    local f=fixture()
    setupWebhook(f)
    f.hooks.queueWebhookEvent("failure","Failed while offline","pnb")
    deferReportRequests(f,2)
    f.hooks.pollWebhook()
    assert(f.app.webhookState.pending == 1 and #f.posts == 0 and #f.app.webhookState.events == 1)
    f.hooks.pollWebhook(); assert(#f.delayed == 1)
    f.delayed[1](); f.spawn=nil
    f.hooks.pollWebhook()
    assert(#f.posts == 1 and #f.app.webhookState.events == 0 and f.app.webhookState.pending == 0)
    task.wait(60); f.hooks.pollWebhook(); assert(#f.posts == 1)
end)

test("Failure delivery retries are bounded and never expose webhook tokens", function()
    local f=fixture()
    setupWebhook(f)
    f.env.request=function(options)
        f.posts[#f.posts+1]=options
        error("Network error with test_token")
    end
    f.hooks.queueWebhookEvent("failure","Task failed","transfer")
    f.hooks.pollWebhook(); assert(#f.posts == 1)
    task.wait(9); f.hooks.pollWebhook(); assert(#f.posts == 1)
    task.wait(1); f.hooks.pollWebhook(); assert(#f.posts == 2)
    task.wait(20); f.hooks.pollWebhook(); assert(#f.posts == 3)
    assert(#f.app.webhookState.events == 0 and f.app.webhookState.status:find("three attempts",1,true))
    assert(not f.app.webhookState.status:find("test_token",1,true))
    task.wait(60); f.hooks.pollWebhook(); assert(#f.posts == 3)
end)

test("Discord rate limits retain the failure alert until the permitted retry", function()
    local f=fixture()
    setupWebhook(f)
    local attempts=0
    f.env.request=function(options)
        attempts=attempts+1
        f.posts[#f.posts+1]=options
        if attempts == 1 then return {StatusCode=429,Body=f.services.HttpService:JSONEncode({retry_after=30})} end
        return {StatusCode=204}
    end
    f.hooks.queueWebhookEvent("failure","Access refused","harvest")
    f.hooks.pollWebhook()
    assert(attempts == 1 and #f.app.webhookState.events == 1)
    task.wait(29); f.hooks.pollWebhook(); assert(attempts == 1)
    task.wait(1); f.hooks.pollWebhook()
    assert(attempts == 2 and #f.app.webhookState.events == 0 and f.app.webhookState.status == "Failure alert sent.")
end)

test("Failure notifications work without an attached game and profile changes discard old queued alerts", function()
    local f=fixture()
    setupWebhook(f)
    f.app.runtime=nil
    assert(f.hooks.queueWebhookEvent("failure","Could not attach game","connection"))
    f.hooks.pollWebhook()
    assert(#f.posts == 1 and reportField(f.encoded[f.posts[1].Body],"World") == "World picker / unconnected")
    assert(f.hooks.queueWebhookEvent("failure","Old failure","pnb"))
    f.app.config=f.hooks.Core.defaults()
    f.hooks.resetWebhookSchedule()
    task.wait(60); f.hooks.pollWebhook()
    assert(#f.posts == 1 and #f.app.webhookState.events == 0)
end)

test("Failure Discord IDs and toggles survive session reload and invalid IDs preserve the previous value", function()
    local f=fixture()
    f.hooks.setWebhookSetting("discordId","123456789012345678")
    rejects(function() f.hooks.setWebhookSetting("discordId","@everyone") end,"Discord user ID")
    assert(f.app.config.webhook.discordId == "123456789012345678")
    f.hooks.setWebhookSetting("failureAlerts",false)
    f.hooks.saveSession()
    local next=f.reload()
    assert(next.App.config.webhook.discordId == "123456789012345678" and not next.App.config.webhook.failureAlerts)
end)

test("Completed rotation cycles send their work snapshot after Stop without a failure ping", function()
    local f=rotationFixture()
    local server=f.server
    setupWebhook(f)
    f.server=server
    f.hooks.setWebhookSetting("discordId","123456789012345678")
    f.hooks.setWebhookSetting("enabled",true)
    f.afterWait=function() if f.app.stats.cycles == 1 then f.app:stop() end end
    f.hooks.start("rotation")
    assert(not f.app.lastError and f.app.stats.cycles == 1 and #f.app.webhookState.events == 1)
    f.hooks.pollWebhook()
    local payload=f.encoded[f.posts[1].Body]
    assert(payload.embeds[1].title == "Growblox work report" and payload.content == nil)
    assert(reportField(payload,"Rotation progress"):find("Cycle: 1",1,true))
    assert(reportField(payload,"Farm status"):find("Completed rotation cycle 1",1,true))
    assert(reportField(payload,"This script session"):find("Trees harvested: 10",1,true))
end)

test("A task setup failure sends a failure alert instead of silently refusing the start", function()
    local f=fixture()
    setupWebhook(f)
    f.app.job,f.app.jobToken=nil,nil
    f.app.config.points.pnb=nil
    local started=f.hooks.setRunningEnabled("pnb",true)
    assert(not started and f.app.job == nil and #f.app.webhookState.events == 1)
    f.hooks.pollWebhook()
    assert(#f.posts == 1 and reportField(f.encoded[f.posts[1].Body],"Failure"):find("Could not start task",1,true))
end)

test("A failure preempts periodic stat queries and can post while those read-only queries remain stuck", function()
    local f=fixture()
    setupWebhook(f)
    deferReportRequests(f,2)
    f.onWait=function()
        f.onWait=nil
        f.hooks.queueWebhookEvent("failure","Disconnected during work","pnb")
    end
    f.hooks.sendWebhook(true)
    assert(#f.delayed == 2 and f.app.webhookState.pending == 2 and f.app.webhookState.httpPending == 0)
    assert(#f.posts == 0 and #f.app.webhookState.events == 1)
    f.spawn=nil
    f.hooks.pollWebhook()
    assert(#f.posts == 1 and f.app.webhookState.pending == 2 and f.app.webhookState.httpPending == 0)
    assert(f.encoded[f.posts[1].Body].embeds[1].title == "Growblox task failed")
    for _,complete in ipairs(f.delayed) do complete() end
    assert(f.app.webhookState.pending == 0 and #f.app.webhookState.events == 0 and f.app.pending == 0)
end)

return string.format("%d actual-script runtime tests passed (mock services/server)", passed)
