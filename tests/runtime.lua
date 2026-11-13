-- Executes the actual generated script through its explicit offline test hooks.
-- Roblox services, storage, and scheduling are mocked; this does not test a live server.
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
table.unpack = table.unpack or unpack
local passed = 0
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
    local localPlayer = { UserId = 1234, GetAttribute = function() return nil end }
    local services = {
        HttpService = http, Players = { LocalPlayer = localPlayer },
        ReplicatedStorage = { GetAttribute = function() return "session-registry" end },
        UserInputService = { GetFocusedTextBox = function() return nil end },
    }
    game = { GetService = function(_, name) assert(services[name], name); return services[name] end }
    task = {
        spawn = function(fn, ...) return fn(...) end,
        defer = function(fn) queue[#queue + 1] = fn end,
        wait = function(seconds)
            ticks = ticks + (seconds or 0.03)
            local pending = queue
            queue = {}
            for _, fn in ipairs(pending) do fn() end
            if context.onWait then context.onWait() end
            return seconds
        end,
    }
    local hooks = (function()
-- CLARIS_RUNTIME_SOURCE
    end)()
    context.hooks, context.env, context.files = hooks, env, files
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
        call = function(...) assert(context.server, "No mock server configured"); return context.server(...) end,
    }
    local controls = { dir = function() return -1 end, jumping = function() return true end }
    local avatar = { active = true, dead = false, x = 13.5, y = 9, vx = 0, vy = 0, facing = 1, grounded = true }
    app.runtime = {
        world = world, inventory = inventory, controls = controls,
        body = { state = function() return avatar end, solidAt = function() return false end },
        items = {
            [954] = { name = "Sugar Cane", hits = 2 }, [955] = { kind = "seed" },
            [18] = { kind = "tool" }, [1422] = { display = true }, [12] = { door = true },
        },
    }
    app.token, app.job = 1, "transfer"
    context.app, context.world, context.inventory = app, world, inventory
    context.controls, context.avatar, context.drops, context.boxes = controls, avatar, drops, boxes
    return context
end

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

test("Optimistic placement without a server acknowledgment cannot advance the farm", function()
    local f = fixture()
    f.inventory:add(954, 5)
    local called = false
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(layer, x, y, id)
            assert(layer == "fg")
            called = true
            f.world.fg[y][x] = id
        end,
    }
    rejects(function() f.hooks.placeTile({x = 10, y = 7}, 954, 1) end, "No server confirmation")
    assert(called and f.world.fg[7][10] == 954)
    assert(f.inventory:count(954) == 4 and f.app.stats.broken == 0)
end)

test("A fresh acknowledgment from the current grid confirms placement", function()
    local f = fixture()
    f.inventory:add(954, 5)
    f.app.runtime.handlers = {
        canPlace = function() return true end,
        setTile = function(_, x, y, id)
            f.world.fg[y][x] = id
            f.onWait = function()
                f.app.tileEvents[y * f.world.w + x] = {serial = 1, id = id, world = "BREAK", fg = f.world.fg}
            end
        end,
    }
    f.hooks.placeTile({x = 10, y = 7}, 954, 1)
    assert(f.inventory:count(954) == 4)
end)

test("Acknowledgments from an old world grid are ignored", function()
    local f = fixture()
    f.world.fg[7][10] = 954
    f.app.tileEvents[7 * f.world.w + 10] = {serial = 3, id = 954, world = "BREAK", fg = {}}
    rejects(function() f.hooks.waitTile(10, 7, 954, 0, "BREAK", 1) end, "No server confirmation")
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

test("Registry failure stays visible instead of being blamed on world entry", function()
    local f = fixture()
    shared, getrenv = {}, nil
    getgc = function() return {} end
    f.app.runtime = nil
    rejects(function() f.hooks.connectGame() end, "module registry is inaccessible")
    assert(f.app.connectionError and not f.app.connectionError:find("Join a Growblox world", 1, true))
    rejects(function() f.hooks.runtime() end, "module registry is inaccessible")
end)

local function prepareDiscovery(f, liveInventory)
    local modules = moduleMap(f)
    shared, getrenv = {}, nil
    f.world.displayPut, f.world.useDoor = function() end, function() end
    function f.world.backpackNow()
        local rows = {}
        for _, slot in pairs(f.inventory.slots) do table.insert(rows, {slot.id, slot.n}) end
        return rows
    end
    local objects = {f.world, modules}
    if liveInventory then table.insert(objects, f.inventory) end
    getgc = function() return objects end
    require = function(reference) return reference end
    return modules
end

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

return string.format("%d actual-script runtime tests passed (mock services/server)", passed)
