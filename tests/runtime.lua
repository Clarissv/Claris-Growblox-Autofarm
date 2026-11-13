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
        spawn = function(fn, ...)
            if context.spawn then return context.spawn(fn, ...) end
            return fn(...)
        end,
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
            [954] = { name = "Sugar Cane", hits = 2 }, [955] = { kind = "seed" },
            [18] = { kind = "tool" }, [1422] = { display = true }, [12] = { door = true },
        },
    }
    app.token, app.job, app.jobToken = 1, "transfer", 1
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
        assert(f.allowLatePickup or (f.controls.dir() == 0 and not f.controls.jumping()),
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
    for _, mode in ipairs({"pnb", "transfer"}) do
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
