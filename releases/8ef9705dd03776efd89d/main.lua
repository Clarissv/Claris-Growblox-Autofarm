-- Built by build.mjs. Use the generated loader.lua in Delta.
local Core = (function()
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

end)()
local VERSION = "0.1.2"
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = getgenv and getgenv() or _G
local ROOT = "ClarisGrowblox"
local PROFILE_DIR = ROOT .. "/profiles"
local RESUME_FILE = ROOT .. "/resume.json"

if env.ClarisGrowbloxApp then
    -- Reloading an idle script should preserve a paused transfer checkpoint.
    local previous = env.ClarisGrowbloxApp
    previous.alive = false
    previous.token = previous.token + 1
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
    stats = { broken = 0, trips = 0, moved = 0 },
}
env.ClarisGrowbloxApp = App
local WindUI
local ui = {}

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
local function bounded(fn, seconds, token, ...)
    local arguments = table.pack(...)
    local done, result = false, nil
    App.pending = App.pending + 1
    task.spawn(function()
        result = table.pack(pcall(fn, table.unpack(arguments, 1, arguments.n)))
        App.pending = App.pending - 1
        done = true
    end)
    local deadline = os.clock() + seconds
    while not done do
        if token then checkpoint(token) end
        assert(App.alive, "Script unloaded.")
        assert(os.clock() < deadline, "Request timed out. Wait for it to finish before restarting.")
        task.wait(0.05)
    end
    if token then checkpoint(token) end
    assert(result[1], tostring(result[2]))
    return table.unpack(result, 2, result.n)
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
        readInventoryView = readInventoryView, ready = #issues == 0 }
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
local function worldCheck(name, token)
    checkpoint(token)
    local r = runtime()
    assert(r.world.name == name, "The world changed. Stopping to protect the saved locations.")
    assert(not player:GetAttribute("Frozen"), "Your character is frozen.")
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

local function moveTo(x, y, worldName, token)
    local r = worldCheck(worldName, token)
    tileAt(x, y)
    local hold = takeControls()
    local targetX, targetY = x + 0.5, y + 1
    local began = os.clock()
    local state = position()
    local progressX, progressedAt, lastJump = state.x, began, -math.huge
    while true do
        worldCheck(worldName, token)
        state = position()
        if math.abs(state.x - targetX) < 0.16 and math.abs(state.y - targetY) < 0.22
            and math.abs(state.vx or 0) < 0.8 then
            hold.direction, hold.jump = 0, false
            return
        end
        assert(os.clock() - began < App.config.options.moveTimeout,
            "Could not reach the saved position. Check the path and save a reachable standing tile.")
        if UserInputService:GetFocusedTextBox() then
            hold.direction, hold.jump = 0, false
        else
            local dx = targetX - state.x
            hold.direction = math.abs(dx) > 0.12 and (dx > 0 and 1 or -1) or 0
            if math.abs(state.x - progressX) > 0.15 then
                progressX, progressedAt = state.x, os.clock()
            end
            local nextX = math.floor(state.x + hold.direction * 0.65)
            local feetTile = math.floor(state.y - 0.05)
            local blocked = hold.direction ~= 0 and r.body.solidAt(nextX, feetTile)
            local needsJump = targetY < state.y - 0.3 or blocked or os.clock() - progressedAt > 0.6
            if needsJump and state.grounded and os.clock() - lastJump > 0.45 then
                lastJump = os.clock()
            end
            hold.jump = needsJump and os.clock() - lastJump < 0.13
        end
        pause(0.03, token)
    end
end
local function moveToPoint(point, token)
    moveTo(point.standX or point.x, point.standY or point.y, point.world, token)
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
    assert(result[1], tostring(result[2]))
    return table.unpack(result, 2, result.n)
end
local function placeTile(point, id, token)
    return withoutPickups(function()
        local name = App.config.points.pnb.world
        local r = worldCheck(name, token)
        -- Quiesce automatic pickups so a server inventory delta identifies this
        -- placement rather than a concurrently collected copy of the same block.
        local before = refreshInventory(token)[id] or 0
        assert(tileAt(point.x, point.y) == 0, "The PNB grid contains another block.")
        assert(r.handlers.canPlace(r.items[id], point.x, point.y),
            "Cannot place at " .. point.x .. ", " .. point.y .. ". Check reach, access, and empty tiles.")
        assert(before > 0, "No blocks are left in your backpack.")
        r.handlers.setTile("fg", point.x, point.y, id, false, (position().facing or 1) < 0)
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
    pause(0.32, token) -- Growblox ignores hits during its initial placement grace period.
    while tileAt(point.x, point.y) == id do
        worldCheck(name, token)
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
    -- The normal client handles pickup, gems, local inventory, and drop removal.
    -- Walk underneath relevant loose drops instead of racing its takeDrop coroutine.
    pause(App.config.options.collectDelay, token)
    local r = worldCheck(anchor.world, token)
    local columns = {}
    for _, drop in pairs(r.world.dropList()) do
        if not drop.display and not drop.pending and (drop.n or 0) > 0
            and (drop.id == 112 or drop.id == blockId or drop.id == seedId)
            and math.abs(drop.x - (anchor.x + 0.5)) <= 2.8
            and drop.y >= anchor.y - 2.5 and drop.y <= anchor.y + 1.25 then
            columns[math.clamp(math.floor(drop.x), anchor.x - 2, anchor.x + 2)] = true
        end
    end
    for x = anchor.x - 2, anchor.x + 2 do
        if columns[x] then
            moveTo(x, anchor.y, anchor.world, token)
            pause(App.config.options.collectDelay, token)
        end
    end
    moveToPoint(anchor, token)
    refreshInventory(token)
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
        assert(id == 0 or id == blockId, "Clear the 2 x 5 grid above the PNB spot before starting.")
    end
    storageCount(p.blockBox, blockId)
    storageCount(p.seedBox, seedId)
    while true do
        worldCheck(p.pnb.world, token)
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
        setStatus("Placing " .. runtime().items[blockId].name .. " in the 2 x 5 grid...")
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
    releaseControls()
    clearResume()
    setStatus(self.pending > 0 and "Stopped; waiting for a pending server request." or "Stopped.")
end
function App:destroy()
    if not self.alive then return end
    self:stop()
    self.alive = false
    if self.window then pcall(function() self.window:Destroy() end) end
    if env.ClarisGrowbloxApp == self then env.ClarisGrowbloxApp = nil end
end
local function start(mode, saved)
    idle()
    local r = runtime()
    assert(r.ready ~= false, "Inventory loaded, but farming hooks are unavailable: " .. table.concat(r.issues or {}, " "))
    Core.checkSetup(App.config, mode, runtime().items)
    App.token = App.token + 1
    local token = App.token
    App.job = mode
    App.lastError = nil
    takeControls()
    task.spawn(function()
        local ok, message = xpcall(function()
            if mode == "pnb" then runPNB(token) else runTransfer(token, saved) end
        end, function(err) return tostring(err) end)
        releaseControls()
        App.job = nil
        if not ok and token == App.token and App.alive then
            App.lastError = message
            setStatus("Paused: " .. message)
            notify(message)
        end
        if mode == "transfer" and ok then clearResume() end
    end)
end

if env.ClarisGrowbloxTest then
    return { App = App, Core = Core, start = start, checkpoint = checkpoint,
        runTransfer = runTransfer, runPNB = runPNB, refreshInventory = refreshInventory,
        withdraw = withdraw, deposit = deposit, releaseControls = releaseControls,
        takeControls = takeControls, collectDrops = collectDrops, enterDoor = enterDoor,
        settleTile = settleTile, placeTile = placeTile, breakTile = breakTile, resolveRegistry = resolveRegistry,
        discover = discover, connectGame = connectGame, runtime = runtime }
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
local function startAction(mode)
    return function()
        local ok, message = pcall(start, mode)
        if not ok then notify(tostring(message)) end
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
pnbTab:Paragraph({ Title = "PNB layout", Desc = "Seed box - Empty - Player - Empty - Block box\nFive columns and two rows of empty foreground tiles directly above the player." })
for _, key in ipairs({ "pnb", "blockBox", "seedBox" }) do
    ui.points[key] = pnbTab:Paragraph({ Title = ui.pointTitles[key], Desc = "Not saved" })
end
pnbTab:Button({ Title = "Save PNB spot and matching boxes", Desc = "Stand on the middle platform, then press this button.", Callback = uiAction(capturePNB) })
pnbTab:Button({ Title = "Save block storage", Desc = "Stand beside the right Display Box.", Callback = uiAction(function() captureNearby("blockBox", "box") end) })
pnbTab:Button({ Title = "Save seed storage", Desc = "Stand beside the left Display Box.", Callback = uiAction(function() captureNearby("seedBox", "box") end) })
pnbTab:Button({ Title = "Start Place & Break", Callback = startAction("pnb") })
pnbTab:Button({ Title = "Stop", Callback = function() App:stop() end })

ui.transferStatus = transferTab:Paragraph({ Title = "Status", Desc = App.status })
transferTab:Paragraph({ Title = "Moving Drops setup", Desc = "Harvest manually and put the selected blocks in the farm Display Box. Save both boxes and both linked doors. Start in the farm world." })
for _, key in ipairs({ "farmBox", "farmDoor", "breakDoor" }) do
    ui.points[key] = transferTab:Paragraph({ Title = ui.pointTitles[key], Desc = "Not saved" })
    local pointKey = key
    transferTab:Button({ Title = "Save " .. ui.pointTitles[key], Desc = "Stand beside the target and press Save.",
        Callback = uiAction(function() captureNearby(pointKey, pointKey == "farmBox" and "box" or "door") end) })
end
transferTab:Paragraph({ Title = "Destination storage", Desc = "Use Save block storage on the Place & Break tab for the breaking world's destination box." })
transferTab:Button({ Title = "Start Moving Drops", Callback = startAction("transfer") })
transferTab:Button({ Title = "Stop", Callback = function() App:stop() end })

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
profileTab:Button({ Title = "Resume saved transfer", Callback = function()
    local ok, message = pcall(resumeTransfer)
    if not ok then notify(tostring(message)) end
end })
profileTab:Button({ Title = "Clear saved transfer", Desc = "Use after checking an interrupted storage request. Items stay where they are.", Callback = uiAction(function()
    clearResume()
    setStatus("Cleared saved transfer.")
end) })

settingsTab:Paragraph({ Title = "Settings", Desc = "These settings are saved separately in each named configuration." })
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
        .. "\n" .. table.concat(App.discoveryReport, "\n")
    local clipboard = setclipboard or toclipboard
    if clipboard then clipboard(text); notify("Diagnostics copied.") else print(text); notify("Diagnostics printed to the console.") end
end })
settingsTab:Button({ Title = "Unload script", Callback = function() App:destroy() end })
ui.log = settingsTab:Paragraph({ Title = "Recent activity", Desc = "Ready." })

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
    elseif env.ClarisGrowbloxAutoResume and App.resume then
        env.ClarisGrowbloxAutoResume = nil
        local resumed, problem = pcall(resumeTransfer)
        if not resumed then setStatus(tostring(problem)); notify(tostring(problem)) end
    end
end)
task.spawn(function()
    while App.alive do
        local suffix = "\nProfile: " .. App.profile .. "  |  Blocks broken: " .. App.stats.broken
            .. "  |  Trips: " .. App.stats.trips .. "  |  Blocks moved: " .. App.stats.moved
        pcall(function()
            paragraphSet(ui.status, "Status", App.status .. suffix)
            paragraphSet(ui.transferStatus, "Status", App.status .. suffix)
            paragraphSet(ui.log, "Recent activity", table.concat(App.logs, "\n"))
        end)
        task.wait(1)
    end
end)
return App
