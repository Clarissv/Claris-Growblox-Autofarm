-- Built by build.mjs. Use the generated loader.lua in Delta.
local Core = (function()
-- Pure configuration and layout helpers; bundled into the runnable script.
local Core = {}
Core.VERSION = 1
Core.REPO = "https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/"
Core.POINTS = { "pnb", "blockBox", "seedBox", "farmBox", "farmDoor", "breakDoor" }
Core.BOOL_OPTIONS = { "antiAFK", "autoRejoin" }
Core.LIMITS = {
    placeDelay = { 0.15, 2 }, punchDelay = { 0.22, 2 },
    collectDelay = { 0, 5 }, actionTimeout = { 5, 30 },
    moveTimeout = { 5, 90 }, seedThreshold = { 1, 200 },
}

function Core.defaults()
    return {
        version = Core.VERSION, blockId = 0, points = {},
        options = { placeDelay = 0.2, punchDelay = 0.24, collectDelay = 0.1,
            actionTimeout = 10, moveTimeout = 30, seedThreshold = 200, antiAFK = true, autoRejoin = true },
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
    return out
end

function Core.grid(anchor)
    local result = {}
    -- One block directly above the player keeps new drops within pickup reach.
    table.insert(result, { x = anchor.x, y = anchor.y - 1 })
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
        assert(p.pnb.x >= 2 and p.pnb.y >= 1, "PNB tile or storage layout is outside the world.")
    else
        assert(p.farmBox.world == p.farmDoor.world, "Farm storage and farm door must be in the same world.")
        assert(p.blockBox.world == p.breakDoor.world, "Block storage and return door must be in the same world.")
        assert(p.farmBox.world ~= p.blockBox.world, "Farm and breaking worlds must be different.")
    end
    return true
end

return Core

end)()
local Navigation = (function()
-- Pure 2D walking/jumping planner. Coordinates use the game's downward Y axis.
local Navigation = {}

function Navigation.steer(dx, vx, braking)
    if math.abs(dx) < 0.06 then return 0 end
    if vx * dx > 0 and math.abs(dx) <= vx * vx / (2 * (braking or 17)) + 0.04 then return 0 end
    return dx > 0 and 1 or -1
end

function Navigation.plan(map, start, goal, options)
    options = options or {}
    local speed, gravity = map.speed or 7.2, map.gravity or 55
    local jumpSpeed = map.jumpSpeed or 19.8997487421324
    local minX = math.max(0, math.min(start.x, goal.x) - 12)
    local maxX = math.min(map.w - 1, math.max(start.x, goal.x) + 12)
    local minY = math.max(0, math.min(start.y, goal.y) - 5)
    local maxY = math.min(map.h - 2, math.max(start.y, goal.y) + 12)
    local solids, supports, stands = {}, {}, {}
    local function key(x, y) return y * map.w + x end
    local function solid(x, y)
        if x < 0 or x >= map.w or y >= map.h then return true end
        if y < 0 then return false end
        local k = key(x, y)
        if solids[k] == nil then solids[k] = map.solid(x, y) and true or false end
        return solids[k]
    end
    local function danger(x, y) return map.danger and map.danger(x, y) end
    local function support(x, y)
        if x < 0 or x >= map.w or y < 0 or y >= map.h then return false end
        local k = key(x, y)
        if supports[k] == nil then
            supports[k] = not danger(x, y) and (solid(x, y) or (map.platform and map.platform(x, y))) and true or false
        end
        return supports[k]
    end
    local function fits(x, feet)
        for tx = math.floor(x - 0.299), math.floor(x + 0.299) do
            for ty = math.floor(feet - 0.949), math.floor(feet - 0.002) do
                if solid(tx, ty) or danger(tx, ty) then return false end
            end
        end
        return true
    end
    local function standable(x, y)
        if x < minX or x > maxX or y < minY or y > maxY then return false end
        local k = key(x, y)
        if stands[k] == nil then stands[k] = fits(x + 0.5, y + 1) and support(x, y + 1) end
        return stands[k]
    end
    if not standable(goal.x, goal.y) then return nil, "The saved standing tile has no accessible support or headroom." end
    if not standable(start.x, start.y) then return nil, "Wait until the avatar is standing on a floor or platform." end
    local function travel(from, to, jumping)
        local x, feet, vx, vy = from.x + 0.5, from.y + 1, 0, jumping and -jumpSpeed or 0
        local targetX, dt = to.x + 0.5, 0.025
        for step = 1, 100 do
            local direction = Navigation.steer(targetX - x, vx)
            local desired = direction * speed
            local acceleration = direction == 0 and 17 or 22
            if vx < desired then vx = math.min(desired, vx + acceleration * dt)
            else vx = math.max(desired, vx - acceleration * dt) end
            local nx = x + vx * dt
            if fits(nx, feet) then x = nx else vx = 0 end
            vy = math.min(24, vy + gravity * dt)
            local nextFeet = feet + vy * dt
            local onLaunchFloor = false
            if vy >= 0 then
                for row = math.ceil(feet - 0.001), math.floor(nextFeet + 0.001) do
                    if support(math.floor(x - 0.299), row) or support(math.floor(x + 0.299), row) then
                        if math.abs(x - targetX) < 0.35 and row == to.y + 1 then return step * dt end
                        if not jumping and row == from.y + 1 then
                            feet, vy, onLaunchFloor = row, 0, true
                            break
                        end
                        return nil -- Landed on an intermediate surface; plan it as a separate hop.
                    end
                end
            end
            if onLaunchFloor then -- Walk off the current ledge before simulating its fall.
            elseif fits(x, nextFeet) then feet = nextFeet
            elseif vy < 0 then vy = 0
            else return nil end
            if feet > maxY + 2 then return nil end
        end
    end
    local function estimate(x, y) return (math.abs(x - goal.x) + math.abs(y - goal.y) * 0.6) / speed end
    local initial = {x = start.x, y = start.y, cost = 0, score = estimate(start.x, start.y)}
    local open, best, closed = {initial}, {[key(start.x, start.y)] = initial}, {}
    local expansions = 0
    while #open > 0 and expansions < (options.maxNodes or 1600) do
        local selected = 1
        for index = 2, #open do if open[index].score < open[selected].score then selected = index end end
        local node = table.remove(open, selected)
        local nodeKey = key(node.x, node.y)
        if not closed[nodeKey] then
            if node.x == goal.x and node.y == goal.y then
                local route = {}
                while node.parent do
                    table.insert(route, 1, {x = node.x, y = node.y, jump = node.jump,
                        fromX = node.parent.x, fromY = node.parent.y, duration = node.duration})
                    node = node.parent
                end
                return route
            end
            closed[nodeKey], expansions = true, expansions + 1
            local function offer(x, y, jumping)
                if not standable(x, y) then return end
                local destinationKey = key(x, y)
                local edgeKey = nodeKey .. ":" .. destinationKey .. ":" .. tostring(jumping)
                if closed[destinationKey] or (options.banned and options.banned[edgeKey]) then return end
                local duration
                if not jumping and y == node.y then duration = 1 / speed
                else duration = travel(node, {x = x, y = y}, jumping) end
                if not duration then return end
                local cost = node.cost + duration + (jumping and 0.12 or 0)
                if not best[destinationKey] or cost < best[destinationKey].cost then
                    local nextNode = {x = x, y = y, cost = cost, score = cost + estimate(x, y),
                        parent = node, jump = jumping, duration = duration}
                    best[destinationKey] = nextNode
                    table.insert(open, nextNode)
                end
            end
            for _, dx in ipairs({-1, 1}) do
                for dy = 0, 8 do
                    if standable(node.x + dx, node.y + dy) then offer(node.x + dx, node.y + dy, false); break end
                    if solid(node.x + dx, node.y + dy) then break end
                end
            end
            for dx = -4, 4 do
                for dy = -3, 3 do
                    if dx ~= 0 or dy ~= 0 then offer(node.x + dx, node.y + dy, true) end
                end
            end
        end
    end
    return nil, "No walking/jumping route reaches the saved spot. Check door access and stepping platforms."
end

return Navigation

end)()
local VERSION = "0.1.5"
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = getgenv and getgenv() or _G
local ROOT = "ClarisGrowblox"
local PROFILE_DIR = ROOT .. "/profiles"
local RESUME_FILE = ROOT .. "/resume.json"
local PNB_RESUME_FILE = ROOT .. "/pnb-resume.json"

if env.ClarisGrowbloxApp then
    -- Reloading an idle script should preserve a paused transfer checkpoint.
    local previous = env.ClarisGrowbloxApp
    previous.alive = false
    previous.token = previous.token + 1
    if previous.idleConnection then pcall(function() previous.idleConnection:Disconnect() end) end
    if previous.controls then
        local hold = previous.controls
        if hold.table.dir == hold.dirOverride then hold.table.dir = hold.dir end
        if hold.table.jumping == hold.jumpOverride then hold.table.jumping = hold.jumping end
        if hold.world.displayTake == hold.displayOverride then hold.world.displayTake = hold.displayTake end
        if hold.world.takeDrop == hold.takeOverride then hold.world.takeDrop = hold.takeDrop end
        previous.controls = nil
    end
    if previous.window then pcall(function() previous.window:Destroy() end) end
end

local function decode(text)
    return HttpService:JSONDecode(text)
end
local function encode(value)
    return HttpService:JSONEncode(value)
end
local function exists(path)
    return type(isfile) == "function" and isfile(path)
end
local function filesystem()
    assert(type(readfile) == "function" and type(writefile) == "function"
        and type(isfolder) == "function" and type(makefolder) == "function",
        "Delta file functions are unavailable. Profile saving needs readfile/writefile/makefolder.")
    if not isfolder(ROOT) then makefolder(ROOT) end
    if not isfolder(PROFILE_DIR) then makefolder(PROFILE_DIR) end
end
local function writeJSON(path, value)
    filesystem()
    local text = encode(value)
    local staged = path .. ".pending"
    writefile(staged, text)
    assert(readfile(staged) == text, "Could not verify the saved file.")
    if exists(path) then writefile(path .. ".bak", readfile(path)) end
    writefile(path, text)
    assert(readfile(path) == text, "Could not finish saving. The previous file is in .bak.")
    if type(delfile) == "function" then pcall(delfile, staged) end
end

local App = {
    alive = true, job = nil, token = 0, pending = 0, configuring = false,
    config = Core.defaults(), profile = "Default", status = "Connecting to Growblox...",
    logs = {}, controls = nil, runtime = nil, resume = nil,
    connectionError = nil, discoveryReport = {},
    stats = { broken = 0, trips = 0, moved = 0, gems = 0 }, runToggles = {},
}
env.ClarisGrowbloxApp = App
local WindUI
local ui = {}

local function syncRunToggles()
    App.syncingRunToggles = true
    for mode, control in pairs(App.runToggles) do
        local enabled = App.alive and App.job == mode and App.jobToken == App.token
        if control.Value ~= enabled then
            pcall(function() control:Set(enabled, false, false) end)
        end
    end
    App.syncingRunToggles = false
end

local function setStatus(text)
    App.status = text
    print("[Claris Growblox] " .. text)
    table.insert(App.logs, 1, os.date("%H:%M:%S") .. "  " .. text)
    if #App.logs > 30 then table.remove(App.logs) end
end
local function notify(text)
    if WindUI then
        pcall(function()
            WindUI:Notify({ Title = "Claris Growblox", Content = text, Duration = 6 })
        end)
    end
end
local function idle()
    assert(App.alive, "This script was unloaded.")
    assert(not App.job and not App.configuring and App.pending == 0,
        "Stop the current task and wait for pending requests before changing setup.")
end
local function checkpoint(token)
    assert(App.alive and App.job and token == App.token, "Stopped.")
end
local function pause(seconds, token)
    local deadline = os.clock() + seconds
    repeat
        if token then checkpoint(token) end
        task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
    until os.clock() >= deadline
end
local function beginRequest(fn, ...)
    local arguments = table.pack(...)
    local request = { done = false }
    App.pending = App.pending + 1
    task.spawn(function()
        request.result = table.pack(pcall(fn, table.unpack(arguments, 1, arguments.n)))
        App.pending = App.pending - 1
        request.done = true
    end)
    return request
end
local function awaitRequest(request, deadline, token)
    while not request.done do
        if token then checkpoint(token) end
        assert(App.alive, "Script unloaded.")
        assert(os.clock() < deadline, "Request timed out. Wait for it to finish before restarting.")
        task.wait(0.05)
    end
    if token then checkpoint(token) end
    if not request.result[1] then error(request.result[2], 0) end
    return table.unpack(request.result, 2, request.result.n)
end
local function bounded(fn, seconds, token, ...)
    local deadline = os.clock() + seconds
    return awaitRequest(beginRequest(fn, ...), deadline, token)
end

local function upvalues(fn)
    local getAll = getupvalues or (debug and debug.getupvalues)
    if type(getAll) == "function" then
        local ok, values = pcall(getAll, fn)
        if ok and type(values) == "table" then return values end
    end
    local getOne = getupvalue or (debug and debug.getupvalue)
    local result = {}
    if type(getOne) == "function" then
        for index = 1, 100 do
            local ok, first, second = pcall(getOne, fn, index)
            if not ok or first == nil then break end
            -- Executors return a value; standard Lua returns name, value.
            if second ~= nil then result[index] = second else result[index] = first end
        end
    end
    return result
end
local function functionName(fn)
    if debug and type(debug.info) == "function" then
        local ok, name = pcall(debug.info, fn, "n")
        if ok and name and name ~= "" then return name end
    end
    local getInfo = getinfo or (debug and debug.getinfo)
    if type(getInfo) == "function" then
        local ok, info = pcall(getInfo, fn)
        if ok and type(info) == "table" then return info.name end
    end
    return nil
end
local function owns(fn, world)
    for _, value in pairs(upvalues(fn)) do
        if value == world then return true end
    end
    return false
end
local function readField(value, key)
    local ok, field = pcall(function() return value[key] end)
    if ok then return field end
end

local function registryMap(candidate)
    if type(candidate) ~= "table" then return nil end
    local function matches(value)
        return type(value) == "table" and rawget(value, "RnyflzPbj74") ~= nil
            and rawget(value, "j1PKXTgzz") ~= nil and rawget(value, "hAYmgnN0A36") ~= nil
    end
    if matches(candidate) then return candidate end
    -- The game publishes a proxy whose module references live in __index.
    -- Inspect that table without invoking arbitrary GC-table metamethods.
    local ok, meta = pcall(getmetatable, candidate)
    if ok and type(meta) == "table" and matches(rawget(meta, "__index")) then
        return rawget(meta, "__index")
    end
    if type(getrawmetatable) == "function" then
        ok, meta = pcall(getrawmetatable, candidate)
        if ok and type(meta) == "table" and matches(rawget(meta, "__index")) then
            return rawget(meta, "__index")
        end
    end
end

local function resolveRegistry(objects)
    local key = ReplicatedStorage:GetAttribute("Qz")
    local containers = { { label = "executor shared", value = shared },
        { label = "executor globals", value = env.shared } }
    if type(getrenv) == "function" then
        local ok, gameEnvironment = pcall(getrenv)
        if ok and type(gameEnvironment) == "table" then
            table.insert(containers, { label = "game runtime shared", value = gameEnvironment.shared })
        end
    end
    for _, container in ipairs(containers) do
        if key ~= nil and type(container.value) == "table" then
            local map = registryMap(rawget(container.value, key))
            if map then return map, container.label end
        end
    end
    for _, object in pairs(objects or {}) do
        local map = registryMap(object)
        if map then return map, "GC module map" end
        if key ~= nil and type(object) == "table" then
            map = registryMap(rawget(object, key))
            if map then return map, "GC shared table" end
        end
    end
    error("Growblox module registry is inaccessible from Delta. Qz attribute: "
        .. (key ~= nil and "present" or "missing") .. ". This is a script attachment failure, not a world-entry check.", 0)
end

local function inventoryObject(candidate)
    return type(candidate) == "table" and type(rawget(candidate, "slots")) == "table"
        and type(readField(candidate, "count")) == "function"
        and type(readField(candidate, "room")) == "function"
        and type(readField(candidate, "add")) == "function"
        and type(readField(candidate, "remove")) == "function"
end

local function discover()
    assert(type(getgc) == "function", "Delta must expose getgc(true) to read Growblox's 2D client.")
    local objects = getgc(true)
    local registry, registrySource = resolveRegistry(objects)
    App.discoveryReport = { "Registry: " .. registrySource }
    local worlds, physics, controls = {}, {}, {}
    for _, object in pairs(objects) do
        if type(object) == "table" then
            if type(rawget(object, "backpackNow")) == "function"
                and type(rawget(object, "displayPut")) == "function"
                and type(rawget(object, "useDoor")) == "function"
                and type(rawget(object, "fg")) == "table" then
                table.insert(worlds, object)
            end
            if type(rawget(object, "state")) == "function"
                and type(rawget(object, "solidAt")) == "function"
                and rawget(object, "H") == 0.95 and rawget(object, "HW") == 0.3 then
                table.insert(physics, object)
            end
            if type(rawget(object, "dir")) == "function"
                and type(rawget(object, "jumping")) == "function"
                and type(rawget(object, "punchPressed")) == "function"
                and type(rawget(object, "setScale")) == "function"
                and type(rawget(object, "place")) == "function"
                and type(rawget(object, "edit")) == "function" then
                table.insert(controls, object)
            end
        end
    end
    table.insert(App.discoveryReport, "World tables: " .. #worlds .. "; avatar controllers: "
        .. #physics .. "; touch controls: " .. #controls)
    assert(#worlds == 1, "Could not identify one active Growblox world table (found " .. #worlds .. ").")
    local world = worlds[1]
    local issues = {}
    local gemHud
    for _, candidate in pairs(objects) do
        if type(candidate) == "table" and type(rawget(candidate, "setGems")) == "function"
            and type(rawget(candidate, "addGems")) == "function"
            and type(rawget(candidate, "setWorld")) == "function"
            and type(rawget(candidate, "isTyping")) == "function" then
            if not gemHud or (type(rawget(candidate, "onMessage")) == "function" and owns(candidate.onMessage, world)) then
                gemHud = candidate
            end
        end
    end
    local body
    for _, candidate in ipairs(physics) do
        if owns(candidate.state, world) then
            if body then
                body = nil
                table.insert(issues, "Multiple avatar controllers match the active world.")
                break
            end
            body = candidate
        end
    end
    if not body then table.insert(issues, "Local avatar state hook is unavailable.") end
    if #controls ~= 1 then table.insert(issues, "Expected one touch controller; found " .. #controls .. ".") end
    local inventory
    for _, candidate in pairs(upvalues(world.backpackNow)) do
        if inventoryObject(candidate) then
            inventory = candidate
        end
    end
    if not inventory then
        local ok, snapshot = pcall(world.backpackNow)
        local matches = {}
        if ok and type(snapshot) == "table" then
            local counts = {}
            for _, slot in pairs(snapshot) do counts[slot[1]] = (counts[slot[1]] or 0) + slot[2] end
            for _, candidate in pairs(objects) do
                if inventoryObject(candidate) then
                    local identical, seen = true, {}
                    for _, slot in pairs(candidate.slots) do
                        if counts[slot.id] ~= slot.n then identical = false; break end
                        seen[slot.id] = true
                    end
                    for id in pairs(counts) do if not seen[id] then identical = false end end
                    if identical then table.insert(matches, candidate) end
                end
            end
        end
        if #matches == 1 then inventory = matches[1] end
    end
    local readInventoryView
    if not inventory then
        -- Listing the backpack does not require private mutation hooks.
        inventory = { slots = {} }
        readInventoryView = function()
            local snapshot = world.backpackNow()
            local slots = {}
            for _, slot in pairs(snapshot) do table.insert(slots, { id = slot[1], n = slot[2] }) end
            inventory.slots = slots
        end
        function inventory:count(id)
            local total = 0
            for _, slot in pairs(self.slots) do if slot.id == id then total = total + slot.n end end
            return total
        end
        readInventoryView()
        table.insert(issues, "Backpack is readable; its live mutation hooks are unavailable.")
    end
    local handlers = {}
    for _, object in pairs(objects) do
        if type(object) == "function" then
            local name = functionName(object)
            if (name == "setTile" or name == "hit" or name == "canPlace") and owns(object, world) then
                if handlers[name] then
                    table.insert(issues, "Multiple " .. name .. " handlers match the world.")
                else
                    handlers[name] = object
                end
            end
        end
    end
    for _, name in ipairs({ "setTile", "hit", "canPlace" }) do
        if not handlers[name] then table.insert(issues, "Missing farming handler: " .. name) end
    end
    local items = require(registry.RnyflzPbj74)
    local packets = require(registry.j1PKXTgzz)
    local runtime = { world = world, body = body, controls = controls[1], inventory = inventory,
        items = items, packets = packets, handlers = handlers, issues = issues,
        readInventoryView = readInventoryView, ready = #issues == 0, gemHud = gemHud }
    table.insert(App.discoveryReport, "Inventory: " .. (readInventoryView and "readable snapshot" or "live backpack"))
    table.insert(App.discoveryReport, "Farming hooks: " .. (#issues == 0 and "ready" or table.concat(issues, " ")))
    -- The game already owns tileChanged handling. Own actions are optimistic and
    -- need not receive an echo; do not add a listener or require an acknowledgment.
    return runtime
end

local function connectGame()
    App.discoveryReport = {}
    local ok, result = pcall(discover)
    if not ok then
        App.connectionError = tostring(result)
        error(App.connectionError, 0)
    end
    App.runtime = result
    App.connectionError = nil
    return result
end

local function runtime()
    assert(App.runtime, App.connectionError or "The script has not attached to Growblox yet. Use Reconnect in Settings.")
    return App.runtime
end
local function position()
    local r = runtime()
    assert(r.body, "The avatar state hook is unavailable. Copy the game connection diagnostics from Settings.")
    local state = r.body.state()
    assert(state.active and not state.dead, "Join a world and wait until your character is ready.")
    return state
end
local function recoverable(message, worldName, reason)
    return setmetatable({ message = message, world = worldName, reason = reason, recoverable = true },
        { __tostring = function(value) return value.message end })
end
local function worldCheck(name, token)
    checkpoint(token)
    local r = runtime()
    if r.world.name == "" or r.world.name == nil then
        error(recoverable("Returned to the world picker.", name, "worldPicker"), 0)
    end
    assert(r.world.name == name, "The world changed. Stopping to protect the saved locations.")
    assert(not player:GetAttribute("Frozen"), "Your character is frozen.")
    if r.body then
        local state = r.body.state()
        if not state.active or state.dead then
            error(recoverable("Waiting for the avatar to become ready.", name, "avatar"), 0)
        end
    end
    position()
    return r
end
local function tileAt(x, y)
    local world = runtime().world
    assert(x >= 0 and y >= 0 and x < world.w and y < world.h, "Saved tile is outside this world.")
    return world.fg[y] and world.fg[y][x] or 0
end
local function count(id)
    return runtime().inventory:count(id)
end

local function refreshInventory(token)
    local r = runtime()
    local hold = App.controls
    if hold then
        hold.syncing = true
        local deadline = os.clock() + App.config.options.actionTimeout
        while true do
            if token then checkpoint(token) end
            local taking = hold.autoTakes > 0
            for _, drop in pairs(r.world.dropList()) do
                if drop.taking then taking = true end
            end
            if not taking then break end
            assert(os.clock() < deadline, "Waiting for an existing pickup timed out.")
            pause(0.05, token)
        end
    end
    local snapshot = bounded(r.world.call, App.config.options.actionTimeout, token, "GetInventory")
    assert(type(snapshot) == "table" and type(snapshot.slots) == "table", "Invalid backpack response.")
    local desired = {}
    for _, slot in pairs(snapshot.slots) do
        local id, n = slot[1], slot[2]
        assert(type(id) == "number" and type(n) == "number", "Invalid backpack slot response.")
        desired[id] = (desired[id] or 0) + n
    end
    if type(snapshot.capacity) == "number" then r.inventory.capacity = snapshot.capacity end
    -- Match the client's InventorySync handler, preserving tools absent from the snapshot.
    local current = {}
    for _, slot in ipairs(r.inventory.slots) do current[slot.id] = slot.n end
    for id, n in pairs(current) do
        if r.items[id] and r.items[id].kind ~= "tool" and n > (desired[id] or 0) then
            r.inventory:remove(id, n - (desired[id] or 0))
        end
    end
    for id, n in pairs(desired) do
        local missing = n - r.inventory:count(id)
        if missing > 0 then r.inventory:add(id, missing) end
    end
    if hold then hold.syncing = false end
    return desired
end

local function releaseControls()
    local hold = App.controls
    if hold then
        if hold.table.dir == hold.dirOverride then hold.table.dir = hold.dir end
        if hold.table.jumping == hold.jumpOverride then hold.table.jumping = hold.jumping end
        if hold.world.displayTake == hold.displayOverride then hold.world.displayTake = hold.displayTake end
        if hold.world.takeDrop == hold.takeOverride then hold.world.takeDrop = hold.takeDrop end
        App.controls = nil
    end
end
local function takeControls()
    if App.controls then return App.controls end
    local controls = runtime().controls
    local world = runtime().world
    local hold = { table = controls, dir = controls.dir, jumping = controls.jumping, direction = 0, jump = false,
        world = world, displayTake = world.displayTake, takeDrop = world.takeDrop, autoTakes = 0,
        syncing = false, pausePickup = false }
    hold.dirOverride = function() return hold.direction end
    hold.jumpOverride = function() return hold.jump end
    controls.dir, controls.jumping = hold.dirOverride, hold.jumpOverride
    hold.displayOverride = function() end
    hold.takeOverride = function(...)
        if hold.syncing or hold.pausePickup then return 0 end
        hold.autoTakes = hold.autoTakes + 1
        local result = table.pack(pcall(hold.takeDrop, ...))
        task.defer(function() hold.autoTakes = hold.autoTakes - 1 end)
        if not result[1] then error(result[2]) end
        return table.unpack(result, 2, result.n)
    end
    world.displayTake, world.takeDrop = hold.displayOverride, hold.takeOverride
    App.controls = hold
    return hold
end

local function navigationMap(r)
    local world = r.world
    local function itemAt(x, y) return r.items[world.fg[y] and world.fg[y][x] or 0] end
    return {
        w = world.w, h = world.h, speed = 7.2 * (world.speedScale or 1),
        gravity = 55 * (world.gravityScale or 1),
        solid = function(x, y) return r.body.solidAt(x, y) end,
        platform = function(x, y) local item = itemAt(x, y); return item and item.platform end,
        danger = function(x, y)
            local item = itemAt(x, y)
            return item and (item.deadly or item.lava or item.spikes)
        end,
    }
end
local function moveTo(x, y, worldName, token)
    local r = worldCheck(worldName, token)
    tileAt(x, y)
    local hold = takeControls()
    local targetX, targetY = x + 0.5, y + 1
    local deadline, banned, replans = os.clock() + App.config.options.moveTimeout, {}, 0
    local function reached(state, tx, ty, tolerance)
        return state.grounded and math.abs(state.x - tx) < (tolerance or 0.16)
            and math.abs(state.y - ty) < 0.22 and math.abs(state.vx or 0) < 0.8
    end
    while true do
        worldCheck(worldName, token)
        local state = position()
        if reached(state, targetX, targetY) then hold.direction, hold.jump = 0, false; return end
        assert(os.clock() < deadline, "Could not reach the saved position. Check stepping platforms and door access.")
        hold.direction, hold.jump = 0, false
        local landingDeadline = math.min(deadline, os.clock() + 2.5)
        while not state.grounded do
            assert(os.clock() < landingDeadline, "The avatar did not land on a reachable floor or platform.")
            pause(0.03, token)
            worldCheck(worldName, token)
            state = position()
        end
        local start = {x = math.floor(state.x), y = math.floor(state.y - 0.01)}
        local route, message = Navigation.plan(navigationMap(r), start, {x = x, y = y}, {banned = banned})
        assert(route, message)
        if #route == 0 then route = {{x = x, y = y, fromX = start.x, fromY = start.y, jump = false, duration = 0.2}} end
        App.navigationDebug = "Planned " .. #route .. " walking/jumping steps to " .. x .. ", " .. y
        local failed
        for _, waypoint in ipairs(route) do
            local began, movedAt, movedX, movedY = os.clock(), os.clock(), state.x, state.y
            local launchAt, airborne = nil, false
            while true do
                worldCheck(worldName, token)
                state = position()
                if reached(state, waypoint.x + 0.5, waypoint.y + 1, 0.24) then break end
                assert(os.clock() < deadline, "Returning to the saved position timed out. Check the route.")
                if UserInputService:GetFocusedTextBox() then
                    hold.direction, hold.jump = 0, false
                    movedAt = os.clock()
                else
                    hold.direction = Navigation.steer(waypoint.x + 0.5 - state.x, state.vx or 0,
                        state.grounded and 48 or 17)
                    if waypoint.jump and not launchAt and state.grounded then launchAt = os.clock() end
                    if launchAt and not state.grounded then airborne = true end
                    hold.jump = launchAt ~= nil and ((not airborne and os.clock() - launchAt < 0.2)
                        or (airborne and not state.grounded and (state.vy or 0) < -0.1))
                    if math.abs(state.x - movedX) + math.abs(state.y - movedY) > 0.08 then
                        movedX, movedY, movedAt = state.x, state.y, os.clock()
                    end
                    if os.clock() - movedAt > 1 or os.clock() - began > math.max(2.5, waypoint.duration + 1.5) then
                        failed = waypoint
                        break
                    end
                end
                pause(0.025, token)
            end
            hold.direction, hold.jump = 0, false
            if failed then break end
        end
        if failed then
            local from = failed.fromY * r.world.w + failed.fromX
            local destination = failed.y * r.world.w + failed.x
            banned[from .. ":" .. destination .. ":" .. tostring(failed.jump)] = true
            replans = replans + 1
            assert(replans <= 4, "The planned jumps did not reach the platforms. Check the entrance and route layout.")
            setStatus("Trying another route around the obstacle...")
        end
    end
end
local function moveToPoint(point, token)
    moveTo(point.standX or point.x, point.standY or point.y, point.world, token)
end
local function assertPNBPosition()
    if App.job ~= "pnb" then return end
    local point, state = App.config.points.pnb, position()
    if not state.grounded or math.abs(state.x - (point.x + 0.5)) > 0.3
        or math.abs(state.y - (point.y + 1)) > 0.25 then
        error(recoverable("The avatar left the breaking spot.", point.world, "position"), 0)
    end
end

local function boxRows(point)
    local r = runtime()
    assert(r.world.name == point.world, "Storage box is in another world.")
    local item = r.items[tileAt(point.x, point.y)]
    assert(item and item.display and not item.displayOne, "The saved tile is not a Display Box.")
    return r.world.displays.get(point.x, point.y) or {}
end
local function storageCount(point, id)
    return Core.storageCount(boxRows(point), id)
end
local function withdraw(point, id, token)
    worldCheck(point.world, token)
    moveToPoint(point, token)
    if storageCount(point, id) == 0 then return 0 end
    refreshInventory(token)
    assert(runtime().inventory:room(id) > 0, "Your backpack has no room for this block.")
    local before = count(id)
    local ok, result = bounded(runtime().world.call, App.config.options.actionTimeout, token,
        "DisplayItem", point.x, point.y, nil)
    assert(ok and type(result) == "table", type(result) == "string" and result or "Storage withdrawal failed.")
    local taken = 0
    for _, row in pairs(result.taken or {}) do
        assert(row[1] == id, "The storage box changed and another item was withdrawn. Check your backpack.")
        taken = taken + row[2]
    end
    refreshInventory(token)
    assert(taken > 0 and count(id) >= before + taken, "The server did not confirm blocks in your backpack.")
    return taken
end
local function deposit(point, id, amount, token)
    worldCheck(point.world, token)
    moveToPoint(point, token)
    storageCount(point, id)
    refreshInventory(token)
    amount = math.min(math.floor(amount), count(id))
    assert(amount > 0, "No items are available to deposit.")
    local before = count(id)
    local ok, result = bounded(runtime().world.call, App.config.options.actionTimeout, token,
        "DisplayItem", point.x, point.y, id, nil, nil, amount, point.x + 0.5)
    assert(ok, type(result) == "string" and result or "The storage deposit was rejected.")
    refreshInventory(token)
    assert(count(id) <= before - amount, "The server did not confirm the storage deposit.")
    return amount
end

local function clearResume()
    App.resume = nil
    if exists(RESUME_FILE) and type(delfile) == "function" then
        pcall(delfile, RESUME_FILE)
    elseif type(writefile) == "function" then
        pcall(writeJSON, RESUME_FILE, { version = 1, active = false })
    end
end
local function clearPNBResume()
    if exists(PNB_RESUME_FILE) and type(delfile) == "function" then
        pcall(delfile, PNB_RESUME_FILE)
    elseif exists(PNB_RESUME_FILE) and type(writefile) == "function" then
        pcall(writeJSON, PNB_RESUME_FILE, {version = 1, active = false})
    end
end
local function savePNBResume()
    writeJSON(PNB_RESUME_FILE, {version = 1, active = true, userId = player.UserId, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile})
end
local function readPNBResume()
    if not exists(PNB_RESUME_FILE) then return nil end
    local record = decode(readfile(PNB_RESUME_FILE))
    if not record.active then return nil end
    assert(record.version == 1 and record.userId == player.UserId, "The saved farm belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600,
        "The saved farm is over six hours old. Load your profile and start it again.")
    record.config, record.profile = Core.validate(record.config), Core.profileName(record.profile)
    return record
end
local function saveResume(phase, cargo)
    local record = { version = 1, active = true, userId = player.UserId, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, phase = phase, cargo = cargo or 0 }
    writeJSON(RESUME_FILE, record)
    App.resume = record
end
local function queueResume()
    local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    local loader = env.ClarisGrowbloxLoaderURL
    if type(queue) ~= "function" or type(loader) ~= "string" or not loader:match("^https://") then
        return false
    end
    if not App.queued then
        local code = "task.wait(3); getgenv().ClarisGrowbloxAutoResume = true; "
            .. "loadstring(game:HttpGet(" .. string.format("%q", loader) .. "))()"
        queue(code)
        App.queued = true
    end
    return true
end
local function enterDoor(door, destination, nextPhase, cargo, token)
    moveToPoint(door, token)
    local r = worldCheck(door.world, token)
    local metadata = r.items[tileAt(door.x, door.y)]
    assert(metadata and (metadata.door or metadata.entrance or metadata.vip), "Saved door no longer exists.")
    saveResume(nextPhase, cargo)
    local canResume = queueResume()
    local ok, response = bounded(r.world.call, App.config.options.actionTimeout, token,
        "UseDoor", door.x, door.y)
    assert(ok and type(response) == "table", type(response) == "string" and response
        or "The door was rejected. Check its link, access, and password.")
    if response.go then
        r.world.goTo(response.go[1], response.go[2])
    else
        assert(type(response.enter) == "string", "Door returned no destination world.")
        local entered, message, teleport = bounded(r.world.enter, App.config.options.actionTimeout + 15,
            token, response.enter)
        if teleport then
            releaseControls()
            App.teleporting = true
            setStatus(canResume and "Changing servers; Moving Drops will resume after loading."
                or "Changing servers. Run the GitHub loader again, then press Resume saved transfer.")
            local deadline = os.clock() + 45
            while os.clock() < deadline do pause(0.2, token) end
            App.teleporting = false
            error("Server teleport did not finish. Check the door and press Resume saved transfer.")
        end
        assert(entered, tostring(message or "Could not enter the destination world."))
    end
    pause(0.5, token)
    worldCheck(destination.world, token)
end

local function settleTile(x, y, id, seconds, worldName, token)
    local deadline = os.clock() + seconds
    repeat
        worldCheck(worldName, token)
        assert(tileAt(x, y) == id, "Tile " .. x .. ", " .. y .. " changed while the action settled. Stopping.")
        pause(0.03, token)
    until os.clock() >= deadline
end
local function withoutPickups(fn)
    local hold = App.controls
    local previous = hold and hold.pausePickup
    if hold then hold.pausePickup = true end
    local result = table.pack(pcall(fn))
    if hold then hold.pausePickup = previous end
    if not result[1] then error(result[2], 0) end
    return table.unpack(result, 2, result.n)
end
local function placeTile(point, id, token)
    return withoutPickups(function()
        local name = App.config.points.pnb.world
        local r = worldCheck(name, token)
        assertPNBPosition()
        -- Quiesce automatic pickups so a server inventory delta identifies this
        -- placement rather than a concurrently collected copy of the same block.
        local before = refreshInventory(token)[id] or 0
        assert(tileAt(point.x, point.y) == 0, "The PNB grid contains another block.")
        assert(r.handlers.canPlace(r.items[id], point.x, point.y),
            "Cannot place at " .. point.x .. ", " .. point.y .. ". Check reach, access, and empty tiles.")
        assert(before > 0, "No blocks are left in your backpack.")
        r.handlers.setTile("fg", point.x, point.y, id, false, (position().facing or 1) < 0)
        App.lastPlacement = {x = point.x, y = point.y, world = name, grid = r.world.fg, at = os.clock()}
        r.inventory:remove(id, 1)
        pause(App.config.options.placeDelay, token)
        local deadline = os.clock() + App.config.options.actionTimeout
        while true do
            worldCheck(name, token)
            local after = refreshInventory(token)[id] or 0
            if after == before - 1 then break end
            assert(after == before, "Backpack changed unexpectedly while placing. Stopping.")
            assert(os.clock() < deadline, "The server did not consume a block for tile "
                .. point.x .. ", " .. point.y .. ". Check placement access and range.")
            pause(0.15, token)
        end
        settleTile(point.x, point.y, id, 0.12, name, token)
    end)
end
local function breakTile(point, id, token)
    local name = App.config.points.pnb.world
    local r = worldCheck(name, token)
    assert(tileAt(point.x, point.y) == id, "The target tile changed. Stopping before punching another block.")
    local deadline = os.clock() + App.config.options.actionTimeout + (r.items[id].hits or 1) * App.config.options.punchDelay
    local placed = App.lastPlacement
    if placed and placed.world == name and placed.grid == r.world.fg
        and placed.x == point.x and placed.y == point.y then
        local remaining = 0.32 - (os.clock() - placed.at)
        if remaining > 0 then pause(remaining, token) end
    end
    while tileAt(point.x, point.y) == id do
        worldCheck(name, token)
        assertPNBPosition()
        assert(os.clock() < deadline, "Block did not break. Check permissions and your punching range.")
        local state = position()
        assert(math.abs(point.x + 0.5 - state.x) <= 2.75
            and math.abs(point.y + 0.5 - (state.y - 0.475)) <= 2.75,
            "Player moved outside the PNB grid's punching range.")
        r.handlers.hit(point.x, point.y)
        pause(App.config.options.punchDelay, token)
    end
    assert(tileAt(point.x, point.y) == 0, "The block changed while breaking.")
    -- Match the normal client's hit completion. Allow its optimistic deletion to
    -- settle and observe corrections; the following cycle reconciles inventory.
    -- A tileChanged echo is not a required response to an own-player break.
    settleTile(point.x, point.y, 0, math.max(0.18, App.config.options.punchDelay), name, token)
    App.stats.broken = App.stats.broken + 1
end

local function collectDrops(anchor, blockId, seedId, token)
    pause(App.config.options.collectDelay, token)
    return withoutPickups(function()
        local r = worldCheck(anchor.world, token)
        refreshInventory(token) -- Finish preexisting normal pickup callbacks first.
        local take = App.controls and App.controls.takeDrop or r.world.takeDrop
        assert(type(take) == "function" and type(r.world.dropTaken) == "function",
            "The loose-drop pickup hooks are unavailable. Copy diagnostics from Settings.")
        local attempts, retryAt, deadline = {}, {}, os.clock() + App.config.options.actionTimeout
        local gemsTaken = 0
        local function nearby(drop)
            return not drop.display and not drop.pending and type(drop.uid) == "number"
                and type(drop.n) == "number" and drop.n > 0 and not drop.taking
                and (drop.id == 112 or drop.id == blockId or drop.id == seedId)
                and type(drop.x) == "number" and type(drop.y) == "number"
                and math.abs(drop.x - (anchor.x + 0.5)) <= 1.25
                and drop.y >= anchor.y - 1.5 and drop.y <= anchor.y + 1.25
        end
        local function updateGems()
            if gemsTaken > 0 and r.gemHud then
                local gems = bounded(r.world.call, App.config.options.actionTimeout, token, "GetGems")
                assert(type(gems) == "number" and gems >= 0, "Invalid gem balance from the server.")
                r.gemHud.setGems(gems)
                gemsTaken = 0
            end
        end
        while true do
            worldCheck(anchor.world, token)
            assertPNBPosition()
            if count(seedId) >= App.config.options.seedThreshold then
                setStatus("Putting collected seeds into the left storage box...")
                deposit(App.config.points.seedBox, seedId, count(seedId), token)
                moveToPoint(anchor, token)
                deadline = os.clock() + App.config.options.actionTimeout
            end
            local targets, waiting, refused = {}, false, false
            for _, drop in pairs(r.world.dropList()) do
                if nearby(drop) then
                    local room = drop.id == 112 and 65535 or r.inventory:room(drop.id)
                    if room > 0 then
                        -- Normal pickup uses a one-second refusal cooldown. Read
                        -- its initial timestamp once: suppressed native attempts
                        -- must not keep postponing our own requests.
                        retryAt[drop.uid] = retryAt[drop.uid] or ((drop.refused or -math.huge) + 1)
                        if (attempts[drop.uid] or 0) >= 3 then
                            refused = true
                        elseif math.max(drop.readyAt or 0, retryAt[drop.uid]) > os.clock() then
                            waiting = true
                        else
                            table.insert(targets, drop)
                        end
                    end
                end
            end
            if #targets == 0 then
                updateGems()
                if refused then
                    local details = {}
                    for _, drop in pairs(r.world.dropList()) do
                        if nearby(drop) and (attempts[drop.uid] or 0) >= 3 then
                            table.insert(details, string.format("uid %d, item %d, count %d at %.2f, %.2f",
                                drop.uid, drop.id, drop.n, drop.x, drop.y))
                        end
                    end
                    error("The server refused nearby drop pickups: " .. table.concat(details, "; ")
                        .. ". Check reach and access; copy diagnostics.")
                end
                if not waiting then return end
                assert(os.clock() < deadline, "Nearby drops did not become ready for pickup.")
                pause(0.05, token)
            else
                setStatus("Collecting nearby drops together...")
                local jobs, reserved = {}, {}
                local requestDeadline = os.clock() + App.config.options.actionTimeout
                for _, drop in ipairs(targets) do
                    if #jobs >= 8 then break end
                    worldCheck(anchor.world, token)
                    -- Reserve stack room before launching concurrent requests.
                    -- A previous response can also remove another listed drop.
                    local present = false
                    for _, current in pairs(r.world.dropList()) do
                        if current == drop then present = true; break end
                    end
                    local room = drop.id == 112 and 65535
                        or math.max(0, r.inventory:room(drop.id) - (reserved[drop.id] or 0))
                    local want = math.floor(math.min(drop.n, room, 65535))
                    if want > 0 and present and nearby(drop) then
                        local before, grid = drop.n, r.world.fg
                        local uid, dropId = drop.uid, drop.id
                        if dropId ~= 112 then reserved[dropId] = (reserved[dropId] or 0) + want end
                        attempts[uid] = (attempts[uid] or 0) + 1
                        drop.taking = true
                        -- Apply drop removal inside the owned request. If Stop occurs
                        -- during a pending request, the accepted result still settles
                        -- once, and the normal picker cannot race the same UID.
                        local request = beginRequest(function()
                            local ok, result = pcall(function()
                                local amount = take(uid, want)
                                if amount == nil then amount = 0 end -- Native ask timeout.
                                assert(type(amount) == "number" and amount >= 0 and amount <= want
                                    and amount == math.floor(amount), "Invalid pickup response from the server.")
                                if amount > 0 and r.world.name == anchor.world and r.world.fg == grid then
                                    local remaining = math.min(drop.n, math.max(0, before - amount))
                                    r.world.dropTaken(uid, remaining)
                                    if dropId == 112 then App.stats.gems = App.stats.gems + amount end
                                elseif amount == 0 then
                                    retryAt[uid] = os.clock() + 1
                                    drop.refused = os.clock()
                                end
                                return amount
                            end)
                            drop.taking = false
                            assert(ok, tostring(result))
                            return result
                        end)
                        table.insert(jobs, {request = request, uid = uid, id = dropId})
                    end
                end
                local accepted = false
                for _, job in ipairs(jobs) do
                    local got = awaitRequest(job.request, requestDeadline, token)
                    if got > 0 then
                        accepted = true
                        if job.id == 112 then gemsTaken = gemsTaken + got end
                        attempts[job.uid] = 0
                    end
                end
                if accepted then
                    -- Reconcile once after the whole batch settles, so pickups
                    -- do not wait for a second RPC between each drop.
                    refreshInventory(token)
                    deadline = os.clock() + App.config.options.actionTimeout
                end
            end
        end
    end)
end

local function runPNB(token)
    Core.checkSetup(App.config, "pnb", runtime().items)
    local p = App.config.points
    local blockId = App.config.blockId
    local seedId = Core.seedId(runtime().items, blockId)
    worldCheck(p.pnb.world, token)
    moveToPoint(p.pnb, token)
    local grid = Core.grid(p.pnb)
    for _, point in ipairs(grid) do
        local id = tileAt(point.x, point.y)
        assert(id == 0 or id == blockId, "Clear the tile directly above the PNB spot before starting.")
    end
    storageCount(p.blockBox, blockId)
    storageCount(p.seedBox, seedId)
    while true do
        worldCheck(p.pnb.world, token)
        moveToPoint(p.pnb, token)
        refreshInventory(token)
        if count(seedId) >= App.config.options.seedThreshold then
            setStatus("Putting seeds into the left storage box...")
            deposit(p.seedBox, seedId, count(seedId), token)
            moveToPoint(p.pnb, token)
        end
        local existing = false
        for _, point in ipairs(grid) do
            if tileAt(point.x, point.y) == blockId then existing = true end
        end
        if count(blockId) == 0 and not existing then
            setStatus("Refilling blocks from the right storage box...")
            local taken = withdraw(p.blockBox, blockId, token)
            if taken == 0 then
                setStatus("Finished: no blocks remain in your backpack or block storage.")
                return
            end
            moveToPoint(p.pnb, token)
        end
        setStatus("Placing one " .. runtime().items[blockId].name .. " directly above the player...")
        for _, point in ipairs(grid) do
            local id = tileAt(point.x, point.y)
            assert(id == 0 or id == blockId, "A different block appeared in the PNB grid.")
            if id == 0 and count(blockId) > 0 then placeTile(point, blockId, token) end
        end
        setStatus("Breaking the selected blocks...")
        for _, point in ipairs(grid) do
            if tileAt(point.x, point.y) == blockId then breakTile(point, blockId, token) end
        end
        setStatus("Collecting gems, seeds, and returned blocks...")
        collectDrops(p.pnb, blockId, seedId, token)
    end
end

local function recoverPNB(problem, token)
    assert(App.config.options.autoRejoin, tostring(problem))
    local name = App.config.points.pnb.world
    assert(problem.world == name, "Recovery target differs from the saved PNB world.")
    local r = runtime()
    releaseControls()
    App.recovering = true
    local pendingDeadline = os.clock() + App.config.options.actionTimeout + 5
    while App.pending > 0 do
        checkpoint(token)
        assert(os.clock() < pendingDeadline, "A previous request did not settle; cannot rejoin yet.")
        pause(0.05, token)
    end
    if r.world.name == nil or r.world.name == "" then
        assert(type(r.world.enter) == "function", "The world re-entry hook is unavailable.")
        savePNBResume()
        local canResume = queueResume()
        local entered, message, teleport
        for attempt = 1, 3 do
            checkpoint(token)
            setStatus("Rejoining " .. name .. " (attempt " .. attempt .. "/3)...")
            pause(attempt == 1 and 1 or 2, token)
            entered, message, teleport = bounded(r.world.enter, App.config.options.actionTimeout + 15, token, name)
            if entered or teleport then break end
            assert(App.pending == 0, "A world entry request is still pending.")
        end
        if teleport then
            App.teleporting = true
            setStatus(canResume and "Changing servers; the saved farm will resume after loading."
                or "Changing servers. Run the loader after arrival, then use Resume saved farm.")
            local deadline = os.clock() + 45
            while os.clock() < deadline do pause(0.2, token) end
            error("Server teleport did not finish. Use Resume saved farm after checking the world.")
        end
        assert(entered, tostring(message or "Could not rejoin the saved world."))
    end
    setStatus("Waiting for the saved world and avatar to load...")
    local readyDeadline = os.clock() + App.config.options.actionTimeout + 15
    while true do
        checkpoint(token)
        local state = r.body and r.body.state()
        if r.world.name == name and state and state.active and not state.dead
            and not player:GetAttribute("Frozen") then break end
        assert(r.world.name == name or r.world.name == "" or r.world.name == nil,
            "Arrived in another world. Check the saved PNB world.")
        assert(os.clock() < readyDeadline, "The saved world or avatar did not become ready.")
        pause(0.1, token)
    end
    takeControls()
    refreshInventory(token)
    App.lastPlacement = nil
    setStatus("Finding a route back to the breaking spot...")
    moveToPoint(App.config.points.pnb, token)
    App.recovering = false
    setStatus("Back at the breaking spot. Resuming Place & Break...")
end

local function runTransfer(token, saved)
    Core.checkSetup(App.config, "transfer", runtime().items)
    local p, id = App.config.points, App.config.blockId
    local phase = saved and saved.phase or "pickup"
    local cargo = saved and saved.cargo or 0
    assert(phase == "pickup" or phase == "deliver" or phase == "return", "Invalid transfer resume phase.")
    if not saved then worldCheck(p.farmBox.world, token) end
    while true do
        checkpoint(token)
        if phase == "pickup" then
            worldCheck(p.farmBox.world, token)
            moveToPoint(p.farmBox, token)
            refreshInventory(token)
            if storageCount(p.farmBox, id) == 0 then
                clearResume()
                setStatus("Finished: the farm storage box is empty.")
                return
            end
            setStatus("Taking blocks from the farm storage box...")
            saveResume("pickupPending", 0)
            local taken = withdraw(p.farmBox, id, token)
            assert(taken > 0, "No blocks were withdrawn.")
            -- Track only this trip's cargo; existing inventory blocks stay with the player.
            cargo = taken
            saveResume("deliver", cargo)
            phase = "deliver"
        elseif phase == "deliver" then
            if runtime().world.name == p.farmBox.world then
                setStatus("Going through the door to the breaking world...")
                enterDoor(p.farmDoor, p.blockBox, "deliver", cargo, token)
            end
            worldCheck(p.blockBox.world, token)
            setStatus("Putting the transported blocks into PNB storage...")
            refreshInventory(token)
            assert(count(id) >= cargo, "Some saved cargo is missing. Check your backpack before resuming.")
            -- Save the count before issuing a mutating request. An interrupted deposit is
            -- ambiguous; resume refuses to repeat it until the player checks the inventory.
            saveResume("depositPending", cargo)
            local moved = deposit(p.blockBox, id, cargo, token)
            App.stats.trips = App.stats.trips + 1
            App.stats.moved = App.stats.moved + moved
            cargo = 0
            phase = "return"
            saveResume(phase, cargo)
        elseif phase == "return" then
            if runtime().world.name == p.blockBox.world then
                setStatus("Returning through the door to the farm world...")
                enterDoor(p.breakDoor, p.farmBox, "return", 0, token)
            end
            worldCheck(p.farmBox.world, token)
            phase = "pickup"
            saveResume(phase, 0)
        end
    end
end

function App:stop()
    self.token = self.token + 1
    self.teleporting = false
    self.recovering = false
    syncRunToggles()
    releaseControls()
    clearResume()
    clearPNBResume()
    setStatus(self.pending > 0 and "Stopped; waiting for a pending server request." or "Stopped.")
end
function App:destroy()
    if not self.alive then return end
    self:stop()
    self.alive = false
    if self.idleConnection then self.idleConnection:Disconnect(); self.idleConnection = nil end
    if self.window then pcall(function() self.window:Destroy() end) end
    if env.ClarisGrowbloxApp == self then env.ClarisGrowbloxApp = nil end
end
local function start(mode, saved)
    idle()
    local r = runtime()
    assert(r.ready ~= false, "Inventory loaded, but farming hooks are unavailable: " .. table.concat(r.issues or {}, " "))
    Core.checkSetup(App.config, mode, runtime().items)
    if mode == "pnb" and App.config.options.autoRejoin then savePNBResume(); queueResume()
    elseif mode == "transfer" then clearPNBResume() end
    App.token = App.token + 1
    local token = App.token
    App.job = mode
    App.jobToken = token
    App.lastError = nil
    syncRunToggles()
    task.spawn(function()
        local ok, message = xpcall(function()
            checkpoint(token)
            takeControls()
            if mode == "pnb" then
                while true do
                    local completed, problem = pcall(runPNB, token)
                    if completed then break end
                    if type(problem) == "table" and problem.recoverable and App.config.options.autoRejoin then
                        recoverPNB(problem, token)
                    else error(problem, 0) end
                end
            else runTransfer(token, saved) end
        end, function(err) return tostring(err) end)
        releaseControls()
        App.job = nil
        App.jobToken = nil
        App.recovering = false
        syncRunToggles()
        if not ok and token == App.token and App.alive then
            App.lastError = message
            setStatus("Paused: " .. message)
            notify(message)
        end
        if mode == "transfer" and ok then clearResume() end
        if mode == "pnb" and (ok or not App.teleporting) then clearPNBResume() end
    end)
end

local function setRunningEnabled(mode, enabled)
    if App.syncingRunToggles then return true end
    local ok, message = pcall(function()
        if enabled then
            if App.job == mode and App.jobToken == App.token then return end
            start(mode)
        elseif App.job == mode and App.jobToken == App.token then
            App:stop()
        end
    end)
    syncRunToggles()
    if not ok then notify(tostring(message)) end
    return ok, message
end

local function installAntiAFK()
    if App.idleConnection then return true end
    local ok, service = pcall(function() return game:GetService("VirtualUser") end)
    if not ok then App.antiAFKError = tostring(service); return false end
    local connected, connection = pcall(function()
        return player.Idled:Connect(function()
            if not App.alive or not App.config.options.antiAFK then return end
            if App.lastIdleInput and os.clock() - App.lastIdleInput < 60 then return end
            local sent, message = pcall(function()
                service:CaptureController()
                service:ClickButton2(Vector2.new(0, 0))
            end)
            if sent then App.lastIdleInput, App.antiAFKError = os.clock(), nil
            else App.antiAFKError = tostring(message) end
        end)
    end)
    if not connected then App.antiAFKError = tostring(connection); return false end
    App.idleConnection, App.antiAFKError = connection, nil
    return true
end

if env.ClarisGrowbloxTest then
    return { App = App, Core = Core, start = start, checkpoint = checkpoint,
        runTransfer = runTransfer, runPNB = runPNB, refreshInventory = refreshInventory,
        withdraw = withdraw, deposit = deposit, releaseControls = releaseControls,
        takeControls = takeControls, collectDrops = collectDrops, enterDoor = enterDoor,
        settleTile = settleTile, placeTile = placeTile, breakTile = breakTile, resolveRegistry = resolveRegistry,
        discover = discover, connectGame = connectGame, runtime = runtime,
        syncRunToggles = syncRunToggles, setRunningEnabled = setRunningEnabled,
        Navigation = Navigation, navigationMap = navigationMap, moveTo = moveTo, worldCheck = worldCheck,
        recoverPNB = recoverPNB, recoverable = recoverable, installAntiAFK = installAntiAFK,
        savePNBResume = savePNBResume, readPNBResume = readPNBResume }
end

local function loadWindUI()
    if type(env.ClarisGrowbloxWindUI) == "table" then return env.ClarisGrowbloxWindUI end
    local url = env.ClarisGrowbloxWindUIURL or (Core.REPO .. "vendor/WindUI.lua")
    local source = game:HttpGet(url)
    local chunk, message = loadstring(source, "Claris WindUI")
    assert(chunk, message)
    return chunk()
end
WindUI = loadWindUI()
local window = WindUI:CreateWindow({
    Title = "Claris Growblox Autofarm", Author = "Claris | v" .. VERSION,
    Folder = ROOT, Icon = "sprout", Size = UDim2.fromOffset(640, 560),
    OpenButton = { Title = "Claris Growblox", Enabled = true, Draggable = true, OnlyMobile = false },
})
App.window = window
window:OnDestroy(function() App:destroy() end)
local pnbTab = window:Tab({ Title = "Place & Break", Icon = "hammer" })
local transferTab = window:Tab({ Title = "Moving Drops", Icon = "truck" })
local profileTab = window:Tab({ Title = "Configurations", Icon = "save" })
local settingsTab = window:Tab({ Title = "Settings", Icon = "settings" })

local function paragraphSet(paragraph, title, desc)
    if paragraph and paragraph.ParagraphFrame then
        paragraph.ParagraphFrame:SetTitle(title)
        paragraph.ParagraphFrame:SetDesc(desc)
    end
end
local function pointText(key)
    local point = App.config.points[key]
    if not point then return "Not saved" end
    local text = point.world .. "  |  tile " .. point.x .. ", " .. point.y
    if point.standX then text = text .. "  |  stand " .. point.standX .. ", " .. point.standY end
    return text
end
local function updatePoints()
    for key, paragraph in pairs(ui.points or {}) do
        paragraphSet(paragraph, ui.pointTitles[key], pointText(key))
    end
end
local function uiAction(fn)
    return function()
        task.spawn(function()
            local ok, message = pcall(idle)
            if not ok then notify(tostring(message)); return end
            App.configuring = true
            ok, message = xpcall(fn, function(err) return tostring(err) end)
            App.configuring = false
            if not ok then setStatus(message); notify(message) end
        end)
    end
end
local function captureNearby(key, kind)
    local r, state = runtime(), position()
    local standX, standY = math.floor(state.x), math.floor(state.y - 0.01)
    local candidates = {}
    for y = math.max(0, standY - 2), math.min(r.world.h - 1, standY + 1) do
        for x = math.max(0, standX - 3), math.min(r.world.w - 1, standX + 3) do
            local item = r.items[tileAt(x, y)]
            local matches = item and (kind == "box" and item.display and not item.displayOne
                or kind == "door" and (item.door or item.vip))
            if matches then
                local distance = (x + 0.5 - state.x) ^ 2 + (y + 1 - state.y) ^ 2
                table.insert(candidates, { x = x, y = y, distance = distance })
            end
        end
    end
    table.sort(candidates, function(a, b) return a.distance < b.distance end)
    assert(candidates[1], "Stand beside the " .. kind .. " and try saving again.")
    assert(not candidates[2] or math.abs(candidates[1].distance - candidates[2].distance) > 0.1,
        "Two targets are equally close. Stand closer to the one you want to save.")
    local chosen = candidates[1]
    App.config.points[key] = { world = r.world.name, x = chosen.x, y = chosen.y,
        standX = standX, standY = standY }
    updatePoints()
    setStatus("Saved " .. ui.pointTitles[key] .. ": " .. pointText(key))
end
local function capturePNB()
    local r, state = runtime(), position()
    local point = { world = r.world.name, x = math.floor(state.x), y = math.floor(state.y - 0.01) }
    assert(state.grounded, "Stand still on the PNB platform before saving.")
    for _, cell in ipairs(Core.grid(point)) do tileAt(cell.x, cell.y) end
    App.config.points.pnb = point
    -- Save the screenshot's two boxes automatically when this exact layout exists.
    for key, offset in pairs({ seedBox = -2, blockBox = 2 }) do
        local x, y = point.x + offset, point.y
        local item = r.items[tileAt(x, y)]
        if item and item.display and not item.displayOne then
            App.config.points[key] = { world = point.world, x = x, y = y,
                standX = point.x + (offset < 0 and -1 or 1), standY = point.y }
        end
    end
    updatePoints()
    setStatus("Saved PNB spot. Matching left/right Display Boxes were saved too.")
end

local blockLabels, blockDropdown = {}, nil
local function refreshBlocks()
    local r = App.runtime or connectGame()
    if r.readInventoryView then r.readInventoryView() end
    local ids, seen = {}, {}
    for _, slot in ipairs(r.inventory.slots) do
        if Core.farmable(r.items[slot.id]) and not seen[slot.id] then
            table.insert(ids, slot.id); seen[slot.id] = true
        end
    end
    local selected = App.config.blockId
    if selected > 0 and Core.farmable(r.items[selected]) and not seen[selected] then
        table.insert(ids, selected)
    end
    table.sort(ids, function(a, b) return r.items[a].name < r.items[b].name end)
    local labels, selectedLabel = {}, nil
    blockLabels = {}
    for _, id in ipairs(ids) do
        local label = r.items[id].name .. " [" .. id .. "]  |  " .. count(id) .. " in backpack"
        blockLabels[label] = id
        table.insert(labels, label)
        if id == selected then selectedLabel = label end
    end
    blockDropdown:Refresh(labels)
    blockDropdown:Select(selectedLabel)
end
ui.points, ui.pointTitles = {}, {
    pnb = "PNB spot", blockBox = "Block storage (breaking world)", seedBox = "Seed storage (left box)",
    farmBox = "Farm storage", farmDoor = "Farm door to breaking world", breakDoor = "Breaking door to farm world",
}
ui.status = pnbTab:Paragraph({ Title = "Status", Desc = App.status })
blockDropdown = pnbTab:Dropdown({
    Title = "Block to farm", Desc = "Select a block from your backpack; this also selects the Moving Drops block.",
    Values = {}, SearchBarEnabled = true,
    Callback = function(label)
        if App.syncingUI then return end
        local id = blockLabels[label]
        if id then
            if App.job or App.configuring or App.pending > 0 then
                notify("Stop the task before selecting another block.")
                return
            end
            App.config.blockId = id
        end
    end,
})
pnbTab:Button({ Title = "Refresh inventory choices", Callback = uiAction(refreshBlocks) })
pnbTab:Paragraph({ Title = "PNB layout", Desc = "Seed box - Empty - Player - Empty - Block box\nPlace one block directly above the player, break it, collect nearby drops, and repeat." })
for _, key in ipairs({ "pnb", "blockBox", "seedBox" }) do
    ui.points[key] = pnbTab:Paragraph({ Title = ui.pointTitles[key], Desc = "Not saved" })
end
pnbTab:Button({ Title = "Save PNB spot and matching boxes", Desc = "Stand on the middle platform, then press this button.", Callback = uiAction(capturePNB) })
pnbTab:Button({ Title = "Save block storage", Desc = "Stand beside the right Display Box.", Callback = uiAction(function() captureNearby("blockBox", "box") end) })
pnbTab:Button({ Title = "Save seed storage", Desc = "Stand beside the left Display Box.", Callback = uiAction(function() captureNearby("seedBox", "box") end) })
App.runToggles.pnb = pnbTab:Toggle({ Title = "Place & Break", Value = false,
    Desc = "On runs the farm. Off stops it. Turns off automatically when the task ends.",
    Callback = function(enabled) setRunningEnabled("pnb", enabled) end })

ui.transferStatus = transferTab:Paragraph({ Title = "Status", Desc = App.status })
transferTab:Paragraph({ Title = "Moving Drops setup", Desc = "Harvest manually and put the selected blocks in the farm Display Box. Save both boxes and both linked doors. Start in the farm world." })
for _, key in ipairs({ "farmBox", "farmDoor", "breakDoor" }) do
    ui.points[key] = transferTab:Paragraph({ Title = ui.pointTitles[key], Desc = "Not saved" })
    local pointKey = key
    transferTab:Button({ Title = "Save " .. ui.pointTitles[key], Desc = "Stand beside the target and press Save.",
        Callback = uiAction(function() captureNearby(pointKey, pointKey == "farmBox" and "box" or "door") end) })
end
transferTab:Paragraph({ Title = "Destination storage", Desc = "Use Save block storage on the Place & Break tab for the breaking world's destination box." })
App.runToggles.transfer = transferTab:Toggle({ Title = "Moving Drops", Value = false,
    Desc = "On moves the blocks. Off stops it. Turns off automatically when the task ends.",
    Callback = function(enabled) setRunningEnabled("transfer", enabled) end })

local selectedProfile, profileNameInput, profileDropdown = nil, nil, nil
local settingsControls = {}
local function syncUI()
    App.syncingUI = true
    for key, control in pairs(settingsControls) do control:Set(App.config.options[key]) end
    profileNameInput:Set(App.profile)
    if App.runtime then refreshBlocks() end
    updatePoints()
    App.syncingUI = false
end
local function profilePath(name)
    return PROFILE_DIR .. "/" .. Core.profileName(name) .. ".json"
end
local function listProfiles()
    filesystem()
    assert(type(listfiles) == "function", "Delta listfiles is required to list saved profiles.")
    local names = {}
    for _, path in ipairs(listfiles(PROFILE_DIR)) do
        local basename = path:gsub("\\", "/"):match("([^/]+)%.json$")
        if basename then table.insert(names, basename) end
    end
    table.sort(names)
    profileDropdown:Refresh(names)
    if selectedProfile then profileDropdown:Select(selectedProfile) end
    return names
end
profileTab:Paragraph({ Title = "Named configurations", Desc = "Each profile saves the chosen block, every world/tile/standing position, and timing settings. Give each farm setup its own name. Files stay in Delta's ClarisGrowblox/profiles folder." })
profileNameInput = profileTab:Input({ Title = "Profile name", Value = App.profile, Placeholder = "e.g. Sugar Cane - Farm 1", Callback = function() end })
profileDropdown = profileTab:Dropdown({ Title = "Saved profiles", Values = {}, SearchBarEnabled = true,
    Callback = function(name) selectedProfile = name end })
profileTab:Button({ Title = "Save profile / Save as", Callback = uiAction(function()
    local name = Core.profileName(profileNameInput.Value)
    writeJSON(profilePath(name), Core.validate(App.config))
    App.profile, selectedProfile = name, name
    listProfiles()
    setStatus("Saved profile: " .. name)
end) })
profileTab:Button({ Title = "Load selected profile", Callback = uiAction(function()
    assert(selectedProfile, "Choose a saved profile first.")
    local nextConfig = Core.validate(decode(readfile(profilePath(selectedProfile))))
    App.config, App.profile = nextConfig, selectedProfile
    syncUI()
    setStatus("Loaded profile: " .. App.profile)
end) })
profileTab:Button({ Title = "New empty configuration", Callback = uiAction(function()
    App.config, App.profile = Core.defaults(), "New Farm"
    syncUI()
    setStatus("New configuration. Save the locations, then save it under a new name.")
end) })
profileTab:Button({ Title = "Refresh saved profiles", Callback = uiAction(listProfiles) })
profileTab:Button({ Title = "Delete selected profile", Callback = uiAction(function()
    assert(selectedProfile, "Choose a saved profile first.")
    local name = Core.profileName(selectedProfile)
    assert(type(delfile) == "function", "Delta delfile is required to delete profiles.")
    local path = profilePath(name)
    if exists(path) then delfile(path) end
    if exists(path .. ".bak") then delfile(path .. ".bak") end
    selectedProfile = nil
    profileDropdown:Select(nil)
    listProfiles()
    setStatus("Deleted profile: " .. name)
end) })

local function readResume()
    if not exists(RESUME_FILE) then return nil end
    local record = decode(readfile(RESUME_FILE))
    if not record.active then return nil end
    assert(record.version == 1 and record.userId == player.UserId, "The saved transfer belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600,
        "Saved transfer is over six hours old. Check your backpack and clear it before restarting.")
    record.config = Core.validate(record.config)
    record.profile = Core.profileName(record.profile)
    assert(type(record.cargo) == "number" and record.cargo >= 0 and record.cargo <= 200,
        "Invalid cargo in the saved transfer.")
    return record
end
local function resumeTransfer()
    idle()
    local saved = readResume()
    assert(saved, "No saved transfer is available.")
    assert(saved.phase ~= "depositPending" and saved.phase ~= "pickupPending",
        "A storage request was interrupted. Check the backpack and boxes, clear the saved transfer, then start again.")
    App.config, App.profile, App.resume = saved.config, saved.profile, saved
    syncUI()
    start("transfer", saved)
end
local function resumeFarm()
    idle()
    local saved = readPNBResume()
    assert(saved, "No saved farm is available. Load your profile and start Place & Break.")
    App.config, App.profile = saved.config, saved.profile
    syncUI()
    start("pnb")
end
profileTab:Button({ Title = "Resume saved farm", Desc = "Return to the saved PNB world and breaking spot after a server change.",
    Callback = function()
        local ok, message = pcall(resumeFarm)
        if not ok then notify(tostring(message)) end
    end })
profileTab:Button({ Title = "Resume saved transfer", Callback = function()
    local ok, message = pcall(resumeTransfer)
    if not ok then notify(tostring(message)) end
end })
profileTab:Button({ Title = "Clear saved transfer", Desc = "Use after checking an interrupted storage request. Items stay where they are.", Callback = uiAction(function()
    clearResume()
    setStatus("Cleared saved transfer.")
end) })

settingsTab:Paragraph({ Title = "Settings", Desc = "These settings are saved separately in each named configuration." })
for _, info in ipairs({
    {"antiAFK", "Anti-AFK", "Send an idle keep-alive while this script is loaded."},
    {"autoRejoin", "Rejoin world and return to PNB", "Re-enter the saved world from the world picker, then walk and jump back to the breaking spot."},
}) do
    local key = info[1]
    settingsControls[key] = settingsTab:Toggle({Title = info[2], Desc = info[3], Value = App.config.options[key],
        Callback = function(value)
            if App.syncingUI then return end
            if App.job or App.configuring or App.pending > 0 then
                notify("Stop the task before changing settings.")
                settingsControls[key]:Set(App.config.options[key], false, false)
                return
            end
            App.config.options[key] = value
        end})
end
local sliderInfo = {
    { "placeDelay", "Delay after placement", 0.05 }, { "punchDelay", "Delay between punches", 0.02 },
    { "collectDelay", "Time to wait for drops", 0.05 }, { "actionTimeout", "Server request timeout", 1 },
    { "moveTimeout", "Movement timeout", 1 }, { "seedThreshold", "Store seeds at this count", 1 },
}
for _, info in ipairs(sliderInfo) do
    local key, title, step = info[1], info[2], info[3]
    local limits = Core.LIMITS[key]
    settingsControls[key] = settingsTab:Slider({ Title = title, Step = step,
        Value = { Min = limits[1], Max = limits[2], Default = App.config.options[key] },
        Callback = function(value)
            if App.syncingUI then return end
            if App.job or App.configuring or App.pending > 0 then
                notify("Stop the task before changing settings.")
                return
            end
            App.config.options[key] = value
        end,
    })
end
ui.diagnostics = settingsTab:Paragraph({ Title = "Game connection", Desc = "Connecting..." })
local function reconnect()
    releaseControls()
    App.runtime = connectGame()
    App.syncingUI = true
    refreshBlocks()
    App.syncingUI = false
    paragraphSet(ui.diagnostics, "Game connection", "Attached to " .. App.runtime.world.name
        .. "\n" .. table.concat(App.discoveryReport, "\n"))
    setStatus(App.runtime.ready and "Connected. Select a block and save your locations."
        or "Inventory loaded. Some farming hooks are unavailable; see Settings for details.")
end
settingsTab:Button({ Title = "Reconnect to game", Callback = uiAction(reconnect) })
settingsTab:Button({ Title = "Copy diagnostics", Callback = function()
    local text = "Claris Growblox " .. VERSION .. "\n"
        .. "World: " .. (App.runtime and App.runtime.world.name or "unconnected")
        .. "\nProfile: " .. App.profile .. "\nStatus: " .. App.status
        .. "\nPending requests: " .. App.pending .. "\n" .. table.concat(App.logs, "\n")
        .. "\nConnection error: " .. (App.connectionError or "none")
        .. "\nAnti-AFK: " .. (App.antiAFKError or "ready")
        .. "\nNavigation: " .. (App.navigationDebug or "no route requested")
        .. "\n" .. table.concat(App.discoveryReport, "\n")
    local clipboard = setclipboard or toclipboard
    if clipboard then clipboard(text); notify("Diagnostics copied.") else print(text); notify("Diagnostics printed to the console.") end
end })
settingsTab:Button({ Title = "Unload script", Callback = function() App:destroy() end })
ui.log = settingsTab:Paragraph({ Title = "Recent activity", Desc = "Ready." })
installAntiAFK()

task.spawn(function()
    local deadline = os.clock() + 30
    while App.alive and not ReplicatedStorage:GetAttribute("Qz") and os.clock() < deadline do task.wait(0.25) end
    if not App.alive then return end
    App.configuring = true
    local ok, message = pcall(function()
        reconnect()
        listProfiles()
        if exists(RESUME_FILE) then
            local resumeOK, saved = pcall(readResume)
            if resumeOK and saved then
                App.resume = saved
                setStatus("Saved transfer found. Resume it from Configurations.")
            elseif not resumeOK then
                notify(tostring(saved))
            end
        end
    end)
    App.configuring = false
    if not ok then
        paragraphSet(ui.diagnostics, "Game connection", tostring(message))
        setStatus(tostring(message))
        notify(tostring(message))
    elseif env.ClarisGrowbloxAutoResume then
        env.ClarisGrowbloxAutoResume = nil
        local resumed, problem = pcall(function()
            if readPNBResume() then resumeFarm()
            elseif App.resume then resumeTransfer() end
        end)
        if not resumed then setStatus(tostring(problem)); notify(tostring(problem)) end
    end
end)
task.spawn(function()
    while App.alive do
        syncRunToggles()
        local suffix = "\nProfile: " .. App.profile .. "  |  Blocks broken: " .. App.stats.broken
            .. "  |  Trips: " .. App.stats.trips .. "  |  Blocks moved: " .. App.stats.moved
            .. "  |  Gems collected: " .. App.stats.gems
        pcall(function()
            paragraphSet(ui.status, "Status", App.status .. suffix)
            paragraphSet(ui.transferStatus, "Status", App.status .. suffix)
            paragraphSet(ui.log, "Recent activity", table.concat(App.logs, "\n"))
        end)
        task.wait(1)
    end
end)
return App
