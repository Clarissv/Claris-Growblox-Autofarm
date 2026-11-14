-- Built by build.mjs. Use the generated loader.lua in Delta.
local Core = __CLARIS_CORE__
local Navigation = __CLARIS_NAV__
local VERSION = "0.1.25"
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = getgenv and getgenv() or _G
local ROOT = "ClarisGrowblox"
local PROFILE_DIR = ROOT .. "/profiles"
local RESUME_FILE = ROOT .. "/resume.json"
local PNB_RESUME_FILE = ROOT .. "/pnb-resume.json"
local SESSION_FILE = ROOT .. "/session.json"
local PLANT_RESUME_FILE = ROOT .. "/plant-resume.json"
local ROTATION_RESUME_FILE = ROOT .. "/rotation-resume.json"
local saveRotationResume
local queueWebhookEvent
local previousSession = env.ClarisGrowbloxApp

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
    stats = { broken = 0, trips = 0, moved = 0, gems = 0, harvested = 0, stashed = 0, planted = 0, trees = 0,
        harvestSeeds = 0, stashedSeeds = 0, cycles = 0 }, runToggles = {},
    webhookState = { pending = 0, httpPending = 0, generation = 0, events = {}, status = "Automatic reports are Off." },
    loadedAt = os.clock(),
}
env.ClarisGrowbloxApp = App
local WindUI
local ui = {}

local function saveSession()
    local config, profile = Core.validate(App.config), Core.profileName(App.profile)
    local signature = encode({config = config, profile = profile})
    if signature == App.sessionSignature then return end
    writeJSON(SESSION_FILE, {version = 1, userId = player.UserId, config = config, profile = profile})
    App.sessionSignature, App.sessionSaveError = signature, nil
end
local function restoreSession(previous)
    local record
    if previous and previous.config then
        record = {version = 1, userId = player.UserId, config = previous.config, profile = previous.profile}
    elseif exists(SESSION_FILE) then record = decode(readfile(SESSION_FILE)) end
    if not record then return false end
    assert(type(record) == "table", "The saved session file is invalid.")
    assert(record.version == 1, "Unsupported saved session schema: " .. tostring(record.version))
    assert(record.userId == player.UserId, "The saved session belongs to another account.")
    App.config, App.profile = Core.validate(record.config), Core.profileName(record.profile)
    return true
end
local function pollSession()
    if App.alive and not App.configuring then
        local ok, problem = pcall(saveSession)
        App.sessionSaveError = not ok and tostring(problem) or nil
    end
end

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

local function newScan()
    return {values = {}, names = {}, work = 0, yields = 0, reads = 0, lastYield = os.clock()}
end
local function scanStep(scan, stage)
    assert(App.alive, "This script was unloaded during discovery.")
    App.startupStage = stage
    scan.work = scan.work + 1
    if scan.work >= 2048 or os.clock() - scan.lastYield >= 0.006 then
        task.wait()
        assert(App.alive, "This script was unloaded during discovery.")
        scan.work, scan.lastYield, scan.yields = 0, os.clock(), scan.yields + 1
    end
end
local function upvalues(fn, scan)
    if scan and scan.values[fn] then return scan.values[fn] end
    local result
    local getAll = getupvalues or (debug and debug.getupvalues)
    if type(getAll) == "function" then
        local ok, values = pcall(getAll, fn)
        if ok and type(values) == "table" then result = values end
    end
    local getOne = getupvalue or (debug and debug.getupvalue)
    if not result and type(getOne) == "function" then
        result = {}
        for index = 1, 100 do
            local ok, first, second = pcall(getOne, fn, index)
            if not ok or first == nil then break end
            -- Executors return a value; standard Lua returns name, value.
            if second ~= nil then result[index] = second else result[index] = first end
        end
    end
    result = result or {}
    if scan then scan.values[fn], scan.reads = result, scan.reads + 1 end
    return result
end
local function functionName(fn, scan)
    if scan and scan.names[fn] ~= nil then return scan.names[fn] or nil end
    if debug and type(debug.info) == "function" then
        local ok, name = pcall(debug.info, fn, "n")
        if ok and name and name ~= "" then
            if scan then scan.names[fn] = name end
            return name
        end
    end
    local getInfo = getinfo or (debug and debug.getinfo)
    if type(getInfo) == "function" then
        local ok, info = pcall(getInfo, fn)
        if ok and type(info) == "table" then
            if scan then scan.names[fn] = info.name or false end
            return info.name
        end
    end
    if scan then scan.names[fn] = false end
    return nil
end
local function owns(fn, world, scan)
    for _, value in pairs(upvalues(fn, scan)) do
        if value == world then return true end
    end
    return false
end
local function readField(value, key)
    local ok, field = pcall(function() return value[key] end)
    if ok then return field end
end
local function findRespawn(world, objects, scan)
    scan = scan or newScan()
    -- Some client versions expose the method directly. The supplied client
    -- exposes it on the menu adapter, alongside enter/currentWorld instead.
    if type(rawget(world, "respawn")) == "function" then return world.respawn, "world method" end
    local found
    for _, candidate in pairs(objects or {}) do
        scanStep(scan, "Finding Respawn action")
        if type(candidate) == "table" and type(rawget(candidate, "respawn")) == "function"
            and type(rawget(world, "enter")) == "function" and rawget(candidate, "enter") == world.enter
            and type(rawget(candidate, "currentWorld")) == "function"
            and owns(candidate.currentWorld, world, scan) then
            if found and found ~= candidate.respawn then return nil, "ambiguous native menu adapters" end
            found = candidate.respawn
        end
    end
    return found, found and "native menu adapter" or "unavailable; no matching native menu adapter"
end
local function findWorldPicker(world, objects, scan)
    scan = scan or newScan()
    if type(world.enter) ~= "function" then return nil end
    local found
    for _, fn in pairs(objects or {}) do
        scanStep(scan, "Finding world picker")
        if type(fn) == "function" and functionName(fn, scan) == "enter" then
            local adapter, panel, hud, input
            for _, value in pairs(upvalues(fn, scan)) do
                if type(value) == "table" and rawget(value, "enter") == world.enter then adapter = value end
                if type(value) == "function" and functionName(value, scan) == "hud" then hud = value end
                local isInstance = type(typeof) == "function" and typeof(value) == "Instance"
                if isInstance then
                    if value:IsA("GuiObject") and value:FindFirstChild("recent", true)
                        and value:FindFirstChild("WorldName", true) then panel = value end
                    if value:IsA("TextBox") then input = value end
                end
            end
            if adapter and panel and hud then
                if found and found.panel ~= panel then return nil end
                found = {panel = panel, complete = function()
                    -- Match the normal picker entry's HUD and focus cleanup.
                    panel.Visible = false
                    hud()
                    if input then input:ReleaseFocus() end
                end}
            end
        end
    end
    return found
end
local function pickerOpen(r)
    if not r or not r.picker then return false end
    local ok, visible = pcall(function() return r.picker.panel.Visible end)
    return ok and visible == true
end

local function registryMap(candidate, scan)
    if type(candidate) ~= "table" then return nil end
    local function matches(value)
        return type(value) == "table" and rawget(value, "RnyflzPbj74") ~= nil
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
    -- Both published proxy methods close over the same map. Reading their
    -- upvalues works even when Delta cannot expose the proxy's metatable.
    if type(rawget(candidate, "WaitForChild")) == "function"
        and type(rawget(candidate, "FindFirstChild")) == "function" then
        for _, method in ipairs({ "WaitForChild", "FindFirstChild" }) do
            for _, value in pairs(upvalues(rawget(candidate, method), scan)) do
                if matches(value) then return value end
            end
        end
    end
end

local function resolveRegistry(objects, scan)
    scan = scan or newScan()
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
            local map = registryMap(rawget(container.value, key), scan)
            if map then return map, container.label end
        end
    end
    for _, object in pairs(objects or {}) do
        scanStep(scan, "Finding module registry")
        local map = registryMap(object, scan)
        if map then return map, "GC module map" end
        if key ~= nil and type(object) == "table" then
            map = registryMap(rawget(object, key), scan)
            if map then return map, "GC shared table" end
        end
    end
    return nil, "unavailable; Qz attribute: " .. (key ~= nil and "present" or "missing")
end

local function itemDefinitions(candidate)
    if type(candidate) ~= "table" then return nil end
    -- Stable item IDs and independent categories distinguish definitions from
    -- inventory rows, world grids, atlases, and unrelated GC tables. Inspect raw
    -- fields only, and never require an arbitrary ModuleScript found in GC.
    local function entry(id, name)
        local value = rawget(candidate, id)
        if type(value) == "table" and rawget(value, "name") == name then return value end
    end
    local blank, dirt, fist = entry(0, "Blank"), entry(2, "Dirt"), entry(18, "Fist")
    local door, display = entry(12, "Door"), entry(1422, "Display Box")
    if blank and rawget(blank, "solid") == false
        and dirt and rawget(dirt, "solid") == true and type(rawget(dirt, "hits")) == "number"
        and fist and rawget(fist, "kind") == "tool"
        and door and rawget(door, "door") == true
        and display and rawget(display, "display") == true then return candidate end
end

local function resolveItems(world, objects, registry, scan)
    scan = scan or newScan()
    local found, sources, seen = {}, {}, {}
    local function consider(candidate, source)
        local items = itemDefinitions(candidate)
        if items and not seen[items] then
            seen[items] = true
            table.insert(found, items)
            sources[items] = source
        end
    end
    local function inspect(fn)
        for _, value in pairs(upvalues(fn, scan)) do consider(value, "live world function upvalues") end
    end
    -- A definition table captured by this world's functions has stronger
    -- ownership evidence than a copied or stale table elsewhere in GC.
    for _, value in pairs(world) do
        scanStep(scan, "Finding item definitions")
        if type(value) == "function" then inspect(value) end
    end
    -- Transfer attachment normally gets definitions from the world's public
    -- methods. If they are hidden, retain the full ownership-based fallback.
    if scan.transferOnly and #found == 0 then scan.owned = nil end
    for _, object in pairs(scan.owned or objects) do
        scanStep(scan, "Finding item definitions")
        if type(object) == "function" and (scan.owned or owns(object, world, scan)) then inspect(object) end
    end
    if #found > 1 then
        table.insert(App.discoveryReport, "Item definitions: ambiguous live world tables (" .. #found .. ")")
        error("Growblox item definitions are ambiguous: multiple tables belong to the active world. Copy diagnostics from Settings.", 0)
    end
    if #found == 1 then return found[1], sources[found[1]] end

    local registryIssue = "unavailable"
    if registry then
        local reference = rawget(registry, "RnyflzPbj74")
        local items = itemDefinitions(reference)
        if items then return items, "module registry table" end
        if type(typeof) == "function" and typeof(reference) == "Instance" and reference:IsA("ModuleScript") then
            local ok, value = pcall(require, reference)
            if ok and itemDefinitions(value) then return value, "module registry" end
            registryIssue = ok and "definition fingerprint mismatch" or "item module require failed"
        else
            registryIssue = "item reference is not a ModuleScript or definition table"
        end
    end
    table.insert(App.discoveryReport, "Registry item lookup: " .. registryIssue)
    for _, object in pairs(objects) do
        scanStep(scan, "Finding item definitions")
        consider(object, "GC item definitions")
    end
    if #found == 1 then return found[1], sources[found[1]] end
    table.insert(App.discoveryReport, "Item definitions: " .. (#found > 1 and "ambiguous GC tables (" .. #found .. ")" or "not found"))
    error(#found > 1
        and "Growblox item definitions are ambiguous in GC. Copy diagnostics from Settings."
        or "Growblox item definitions are inaccessible from Delta. Copy diagnostics from Settings. This is a script attachment failure, not a world-entry check.", 0)
end

local function inventoryObject(candidate)
    return type(candidate) == "table" and type(rawget(candidate, "slots")) == "table"
        and type(readField(candidate, "count")) == "function"
        and type(readField(candidate, "room")) == "function"
        and type(readField(candidate, "add")) == "function"
        and type(readField(candidate, "remove")) == "function"
end

local function treeGrowthHooks(world, items, handlers, scan)
    if type(world.ride) ~= "function" or type(handlers.setTree) ~= "function" then return nil end
    local rideTables, ripe, trees, gear = {}, nil, nil, nil
    for _, value in pairs(upvalues(world.ride, scan)) do
        if type(value) == "table" and value ~= world and value ~= items then rideTables[value] = true end
        if type(value) == "table" and type(rawget(value, "onWear")) == "function"
            and type(rawget(value, "isWorn")) == "function" and owns(value.onWear, world, scan) then
            if gear and gear ~= value then return nil end
            gear = value
        end
        if type(value) == "function" and functionName(value, scan) == "treeRipe" then
            for _, captured in pairs(upvalues(value, scan)) do
                if captured == items then
                    if ripe and ripe ~= value then return nil end
                    ripe = value
                end
            end
        end
    end
    for _, value in pairs(upvalues(handlers.setTree, scan)) do
        if rideTables[value] then
            if trees and trees ~= value then return nil end
            trees = value
        end
    end
    if not trees or not ripe then return nil end
    local equipment
    if gear then
        local worn, wearTables = nil, {}
        for _, value in pairs(upvalues(gear.onWear, scan)) do if type(value) == "table" then wearTables[value] = true end end
        for _, value in pairs(upvalues(gear.isWorn, scan)) do
            if type(value) == "table" and wearTables[value] and value ~= world and value ~= items then
                if worn and worn ~= value then return nil end
                worn = value
            end
        end
        if worn then equipment = {wear = gear.onWear, feet = function() return rawget(worn, "feet") end} end
    end
    return function(x, y, id)
        local tree = trees[y * world.w + x]
        if type(tree) ~= "table" or type(tree.p) ~= "number" then return nil end
        return ripe(id, tree)
    end, equipment, function(x, y, id)
        local tree, item = trees[y * world.w + x], items[id]
        if type(tree) ~= "table" or type(tree.p) ~= "number" or not item then return nil end
        return math.max(0, tree.p + (item.grow or 0) - Workspace:GetServerTimeNow())
    end
end

local function discover(options)
    assert(type(getgc) == "function", "Delta must expose getgc(true) to read Growblox's 2D client.")
    local scan = newScan()
    scan.transferOnly = options and options.transferOnly == true
    local startedAt = os.clock()
    App.startupStage = "Reading game objects"
    task.wait() -- Let the window render before taking the executor's GC snapshot.
    assert(App.alive, "This script was unloaded during discovery.")
    local objects = getgc(true)
    local registry, registrySource = resolveRegistry(objects, scan)
    App.discoveryReport = { "Registry: " .. registrySource }
    local worlds, physics, controls = {}, {}, {}
    for _, object in pairs(objects) do
        scanStep(scan, "Finding world and controls")
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
        scanStep(scan, "Finding player HUD")
        if type(candidate) == "table" and type(rawget(candidate, "setGems")) == "function"
            and type(rawget(candidate, "addGems")) == "function"
            and type(rawget(candidate, "setWorld")) == "function"
            and type(rawget(candidate, "isTyping")) == "function" then
            if not gemHud or (type(rawget(candidate, "onMessage")) == "function" and owns(candidate.onMessage, world, scan)) then
                gemHud = candidate
            end
        end
    end
    local body
    for _, candidate in ipairs(physics) do
        if owns(candidate.state, world, scan) then
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
    for _, candidate in pairs(upvalues(world.backpackNow, scan)) do
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
                scanStep(scan, "Finding backpack")
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
    local handlers, ambiguousHandlers = {}, {}
    scan.owned = {}
    if not scan.transferOnly then
        for _, object in pairs(objects) do
            scanStep(scan, "Finding game handlers")
            if type(object) == "function" and owns(object, world, scan) then
                table.insert(scan.owned, object)
                local name = functionName(object, scan)
                if name == "setTile" or name == "hit" or name == "canPlace" or name == "plantSeed" or name == "setTree" then
                    if handlers[name] or ambiguousHandlers[name] then
                        handlers[name], ambiguousHandlers[name] = nil, true
                        if name ~= "plantSeed" and name ~= "setTree" then table.insert(issues, "Multiple " .. name .. " handlers match the world.") end
                    else
                        handlers[name] = object
                    end
                end
            end
        end
        for _, name in ipairs({ "setTile", "hit", "canPlace" }) do
            if not handlers[name] then table.insert(issues, "Missing farming handler: " .. name) end
        end
    end
    local items, itemSource = resolveItems(world, objects, registry, scan)
    local respawn, respawnSource = findRespawn(world, objects, scan)
    local treeRipe, harvestGear, treeRemaining
    if not scan.transferOnly then treeRipe, harvestGear, treeRemaining = treeGrowthHooks(world, items, handlers, scan) end
    table.insert(App.discoveryReport, "Item definitions: " .. itemSource)
    local runtime = { world = world, body = body, controls = controls[1], inventory = inventory,
        items = items, handlers = handlers, issues = issues,
        readInventoryView = readInventoryView, ready = #issues == 0, gemHud = gemHud,
        picker = findWorldPicker(world, objects, scan), farmingDeferred = scan.transferOnly,
        respawn = respawn, respawnSource = respawnSource,
        treeRipe = treeRipe, harvestGear = harvestGear, treeRemaining = treeRemaining }
    table.insert(App.discoveryReport, "Inventory: " .. (readInventoryView and "readable snapshot" or "live backpack"))
    table.insert(App.discoveryReport, "Farming hooks: " .. (scan.transferOnly and "deferred until PNB or Planting starts"
        or #issues == 0 and "ready" or table.concat(issues, " ")))
    table.insert(App.discoveryReport, "Movement and storage: " .. (#issues == 0 and "ready" or table.concat(issues, " ")))
    table.insert(App.discoveryReport, "Respawn hook: " .. respawnSource)
    table.insert(App.discoveryReport, "World picker: " .. (runtime.picker and "UI cleanup ready" or "UI hook unavailable"))
    table.insert(App.discoveryReport, "Planting hook: " .. (ambiguousHandlers.plantSeed and "ambiguous"
        or handlers.plantSeed and "ready" or "unavailable"))
    table.insert(App.discoveryReport, "Tree growth hook: " .. (runtime.treeRipe and "ready" or scan.transferOnly and "deferred" or "unavailable"))
    table.insert(App.discoveryReport, "Harvest equipment: " .. (harvestGear and "ready" or scan.transferOnly and "deferred" or "unavailable"))
    App.startupStage = "Attached"
    App.discoveryPerformance = {yields = scan.yields, upvalueReads = scan.reads, seconds = os.clock() - startedAt}
    table.insert(App.discoveryReport, "Discovery: " .. scan.yields .. " frame yields; " .. scan.reads
        .. " function upvalue reads; " .. string.format("%.2fs", App.discoveryPerformance.seconds))
    -- The game already owns tileChanged handling. Own actions are optimistic and
    -- need not receive an echo; do not add a listener or require an acknowledgment.
    return runtime
end

local function connectGame(options)
    App.discoveryReport = {}
    local ok, result = pcall(discover, options)
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
    if r.world.name == "" or r.world.name == nil or pickerOpen(r) then
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
    local name = App.job == "pnb" and App.config.points.pnb.world or r.world.name
    local snapshot
    for attempt = 1, 3 do
        if token then worldCheck(name, token) end
        snapshot = bounded(r.world.call, App.config.options.actionTimeout, token, "GetInventory")
        -- A response can arrive after leaving the world or beginning its exit
        -- animation. Check that state before treating it as a damaged backpack.
        if token then worldCheck(name, token) end
        if type(snapshot) == "table" and type(snapshot.slots) == "table" then break end
        if attempt < 3 then pause(0.25, token) end
    end
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
        w = world.w, h = world.h, speed = (world.riding and world.riding.speed or 7.2) * (world.speedScale or 1),
        gravity = 55 * (world.gravityScale or 1),
        solid = function(x, y) return r.body.solidAt(x, y) end,
        platform = function(x, y) local item = itemAt(x, y); return item and item.platform end,
        danger = function(x, y)
            local item = itemAt(x, y)
            return item and (item.deadly or item.hurts)
        end,
    }
end
local function moveTo(x, y, worldName, token, onStep)
    local r = worldCheck(worldName, token)
    tileAt(x, y)
    local hold = takeControls()
    local targetX, targetY = x + 0.5, y + 1
    local farmNavigation = App.job == "plant" or App.job == "harvest"
    local timeout = farmNavigation and math.max(90, App.config.options.moveTimeout) or App.config.options.moveTimeout
    local deadline, banned, replans = os.clock() + timeout, {}, 0
    local function collectionStep(state)
        if not onStep then return true, 0 end
        local started = os.clock()
        local proceed = onStep(state)
        local waited = os.clock() - started
        -- Pickup waiting has its own timeout and is not a failed walking step.
        deadline = deadline + waited
        return proceed ~= false, waited
    end
    -- Waypoints and the final destination must agree. A looser waypoint
    -- tolerance can otherwise accept an empty route without ever moving.
    local function reached(state, tx, ty)
        return state.grounded and math.abs(state.x - tx) < 0.16
            and math.abs(state.y - ty) < 0.22 and math.abs(state.vx or 0) < 0.8
    end
    while true do
        worldCheck(worldName, token)
        local state = position()
        if not collectionStep(state) then hold.direction, hold.jump = 0, false; return false end
        state = position()
        if reached(state, targetX, targetY) then hold.direction, hold.jump = 0, false; return end
        assert(os.clock() < deadline, "Could not reach the saved position. Check stepping platforms and door access.")
        hold.direction, hold.jump = 0, false
        local landingDeadline = math.min(deadline, os.clock() + 2.5 + r.world.h / 24)
        while not state.grounded do
            assert(os.clock() < landingDeadline, "The avatar did not land on a reachable floor or platform.")
            pause(0.03, token)
            worldCheck(worldName, token)
            state = position()
        end
        local start = {x = math.floor(state.x), y = math.floor(state.y - 0.01)}
        local route, message = Navigation.plan(navigationMap(r), start, {x = x, y = y}, {
            banned = banned, fullWorld = farmNavigation,
            maxNodes = farmNavigation and math.min(12000, r.world.w * r.world.h) or 1600,
            step = function() pause(0, token); worldCheck(worldName, token) end,
        })
        assert(route, message)
        if #route == 0 then route = {{x = x, y = y, fromX = start.x, fromY = start.y, jump = false, duration = 0.2}} end
        route = Navigation.straightRuns(route)
        App.navigationDebug = "Planned " .. #route .. " walking/jumping steps to " .. x .. ", " .. y
        local failed
        for _, waypoint in ipairs(route) do
            local began, movedAt, movedX, movedY = os.clock(), os.clock(), state.x, state.y
            local launchAt, airborne = nil, false
            while true do
                worldCheck(worldName, token)
                state = position()
                local proceed, waited = collectionStep(state)
                began, movedAt = began + waited, movedAt + waited
                if not proceed then hold.direction, hold.jump = 0, false; return false end
                state = position()
                if reached(state, waypoint.x + 0.5, waypoint.y + 1) then break end
                assert(os.clock() < deadline, "Returning to the saved position timed out. Check the route.")
                if UserInputService:GetFocusedTextBox() then
                    hold.direction, hold.jump = 0, false
                    movedAt = os.clock()
                else
                    hold.direction = waypoint.drop and Navigation.dropSteer(state, waypoint)
                        or Navigation.steer(waypoint.x + 0.5 - state.x, state.vx or 0, state.grounded and 48 or 17)
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
            for _, edge in ipairs(failed.edges) do
                local from = edge.fromY * r.world.w + edge.fromX
                local destination = edge.y * r.world.w + edge.x
                banned[from .. ":" .. destination .. ":" .. tostring(edge.jump)] = true
            end
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
    if App.job ~= "pnb" and not (App.job == "rotation" and App.rotationState
        and (App.rotationState.phase == "pnb" or App.rotationState.phase == "waitPNB")) then return end
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
local function storageCount(point, id, companionId)
    return Core.storageCount(boxRows(point), id, companionId)
end
local function withdraw(point, id, token, companionId)
    worldCheck(point.world, token)
    moveToPoint(point, token)
    if storageCount(point, id, companionId) == 0
        and (not companionId or storageCount(point, companionId, id) == 0) then return 0, 0 end
    refreshInventory(token)
    assert(runtime().inventory:room(id) > 0, "Your backpack has no room for this block.")
    local before, companionBefore = count(id), companionId and count(companionId) or 0
    local ok, result = bounded(runtime().world.call, App.config.options.actionTimeout, token,
        "DisplayItem", point.x, point.y, nil)
    assert(ok and type(result) == "table", type(result) == "string" and result or "Storage withdrawal failed.")
    local taken, companionTaken = 0, 0
    for _, row in pairs(result.taken or {}) do
        assert(row[1] == id or companionId and row[1] == companionId,
            "The storage box changed and another item was withdrawn. Check your backpack.")
        assert(type(row[2]) == "number" and row[2] > 0 and row[2] == math.floor(row[2]), "Invalid storage withdrawal count.")
        if row[1] == id then taken = taken + row[2] else companionTaken = companionTaken + row[2] end
    end
    refreshInventory(token)
    assert(taken + companionTaken > 0 and count(id) == before + taken,
        "The server did not confirm blocks in your backpack.")
    if companionId then assert(count(companionId) == companionBefore + companionTaken,
        "The server did not confirm seeds in your backpack.") end
    return taken, companionTaken
end
local function deposit(point, id, amount, token, onReady, companionId)
    worldCheck(point.world, token)
    moveToPoint(point, token)
    storageCount(point, id, companionId)
    refreshInventory(token)
    if onReady then onReady(count(id)) end
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
    saveSession()
    writeJSON(PNB_RESUME_FILE, {version = 1, active = true, userId = player.UserId, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile})
    App.lastPNBSave = os.clock()
end
local function refreshPNBCheckpoint()
    if App.alive and App.job == "pnb" and App.jobToken == App.token and App.config.options.autoRejoin
        and App.pending == 0 and not App.recovering and os.clock() - (App.lastPNBSave or -math.huge) >= 120 then
        local ok, message = pcall(savePNBResume)
        App.lastPNBSave = os.clock()
        App.recoverySaveError = not ok and tostring(message) or nil
    end
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
    saveSession()
    local record = { version = 1, active = true, userId = player.UserId, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, phase = phase, cargo = cargo or 0,
        seeds = count(Core.seedId(runtime().items, App.config.blockId)) }
    writeJSON(RESUME_FILE, record)
    App.resume = record
    if App.rotationState then
        App.rotationState.transfer = {phase = phase, cargo = cargo or 0, seeds = record.seeds}
        saveRotationResume(App.rotationState)
    end
end
local function queueResume()
    local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
    local loader = env.ClarisGrowbloxLoaderURL
    if type(queue) ~= "function" or type(loader) ~= "string" or not loader:match("^https://") then
        return false
    end
    if not App.queued then
        local code = "getgenv().ClarisGrowbloxAutoResume = true; "
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
    saveSession()
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
    local deadline = os.clock() + App.config.options.actionTimeout + 15
    local readyAt = os.clock()
    while true do
        checkpoint(token)
        assert(r.world.name == door.world or r.world.name == destination.world or r.world.name == "" or r.world.name == nil,
            "The door arrived in an unexpected world. Check its saved destination.")
        if r.world.name == destination.world then
            if pickerOpen(r) then r.picker.complete() end
            local state = r.body and r.body.state()
            if state and state.active and not state.dead and not player:GetAttribute("Frozen") then
                worldCheck(destination.world, token)
                App.doorReadyDebug = destination.world .. " ready after " .. string.format("%.2fs", os.clock() - readyAt)
                return
            end
        end
        assert(os.clock() < deadline, "The destination world or avatar did not become ready after the door.")
        pause(0.05, token)
    end
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
        worldCheck(name, token)
        assertPNBPosition()
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

local function takeDropBatch(anchor, targets, attempts, retryAt, eligible, token, onTaken)
    local r = worldCheck(anchor.world, token)
    local take = App.controls and App.controls.takeDrop or r.world.takeDrop
    assert(type(take) == "function" and type(r.world.dropTaken) == "function",
        "The loose-drop pickup hooks are unavailable. Copy diagnostics from Settings.")
    local jobs, reserved = {}, {}
    local deadline = os.clock() + App.config.options.actionTimeout
    for _, drop in ipairs(targets) do
        if #jobs >= 8 then break end
        worldCheck(anchor.world, token)
        assertPNBPosition()
        local present = false
        for _, current in pairs(r.world.dropList()) do if current == drop then present = true; break end end
        local room = drop.id == 112 and 65535 or math.max(0, r.inventory:room(drop.id) - (reserved[drop.id] or 0))
        local want = math.floor(math.min(drop.n, room, 65535))
        if want > 0 and present and eligible(drop) then
            local before, grid, uid, id = drop.n, r.world.fg, drop.uid, drop.id
            local state = position()
            if id ~= 112 then reserved[id] = (reserved[id] or 0) + want end
            attempts[uid] = (attempts[uid] or 0) + 1
            drop.taking = true
            -- Settlement owns the drop even after Stop; native pickup cannot
            -- race it and a packet's remaining count is never subtracted twice.
            local request = beginRequest(function()
                local ok, result = pcall(function()
                    local amount = take(uid, want)
                    if amount == nil then amount = 0 end
                    assert(type(amount) == "number" and amount >= 0 and amount <= want
                        and amount == math.floor(amount), "Invalid pickup response from the server.")
                    if amount > 0 and r.world.name == anchor.world and r.world.fg == grid then
                        r.world.dropTaken(uid, math.min(drop.n, math.max(0, before - amount)))
                        if id == 112 then App.stats.gems = App.stats.gems + amount end
                        if onTaken then onTaken(uid, id, amount) end
                    elseif amount == 0 then
                        retryAt[uid], drop.refused = os.clock() + 1, os.clock()
                    end
                    return amount
                end)
                drop.taking = false
                assert(ok, tostring(result))
                return result
            end)
            table.insert(jobs, {request = request, uid = uid, id = id,
                avatarX = state.x, avatarY = state.y, dropX = drop.x, dropY = drop.y})
        end
    end
    local results = {}
    for _, job in ipairs(jobs) do
        local amount = awaitRequest(job.request, deadline, token)
        if amount > 0 then attempts[job.uid] = 0 end
        table.insert(results, {uid = job.uid, id = job.id, amount = amount,
            avatarX = job.avatarX, avatarY = job.avatarY, dropX = job.dropX, dropY = job.dropY})
    end
    return results
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
                local results = takeDropBatch(anchor, targets, attempts, retryAt, nearby, token)
                local accepted = false
                for _, result in ipairs(results) do
                    local got = result.amount
                    if got > 0 then
                        accepted = true
                        if result.id == 112 then gemsTaken = gemsTaken + got end
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

local function rememberHarvestEquipment(gear)
    if App.harvestGearRestore then return end
    local previousFeet = gear.feet()
    App.harvestGearRestore = function()
        local current = gear.feet()
        if current ~= previousFeet then
            if current then gear.wear(current) end
            if previousFeet then gear.wear(previousFeet) end
        end
    end
end
local function suspendHarvestVehicle(token)
    local r = runtime()
    if not r.world.riding or not r.world.riding.harvest then return end
    if r.farmingDeferred then r = connectGame() end
    local gear = r.harvestGear
    assert(gear and gear.feet(), "Remove your harvesting vehicle; equipment hooks are unavailable.")
    rememberHarvestEquipment(gear)
    gear.wear(gear.feet())
    local deadline = os.clock() + App.config.options.actionTimeout
    while r.world.riding and r.world.riding.harvest do
        checkpoint(token)
        assert(os.clock() < deadline, "The harvesting vehicle did not unequip.")
        pause(0.025, token)
    end
end
local function harvestEquipmentScope(fn)
    local parentRestore = App.harvestGearRestore
    App.harvestGearRestore = nil
    local result = table.pack(pcall(fn))
    local restore = App.harvestGearRestore
    App.harvestGearRestore = parentRestore
    local restored, issue = true, nil
    if restore then restored, issue = pcall(restore) end
    if not restored then App.harvestGearError = tostring(issue) end
    if not result[1] then error(result[2], 0) end
    assert(restored, "Could not restore previous footwear: " .. tostring(issue))
    return table.unpack(result, 2, result.n)
end

local function runTreeHarvest(token)
    local name, id = App.config.points.farmBox.world, App.config.blockId
    local r = worldCheck(name, token)
    local seedId = Core.seedId(r.items, id)
    if not Core.hasTrees(r.world, seedId) then suspendHarvestVehicle(token); return end
    if r.farmingDeferred then
        setStatus("Connecting tree harvesting hooks...")
        r = connectGame()
        worldCheck(name, token)
    end
    assert(type(r.treeRipe) == "function", "Tree growth hooks are unavailable. Reconnect and copy diagnostics.")
    local rows, method = Core.farmRows(r.world, r.items), App.config.harvesting.method
    local work = {}
    for _, row in ipairs(rows) do
        local points = Core.ripeTrees(r.world, seedId, row, r.treeRipe)
        if #points > 0 then table.insert(work, {row = row, points = points}) end
    end
    if #work == 0 then suspendHarvestVehicle(token); return end
    local gear, tractor = r.harvestGear, nil
    if method == "tractor" then
        assert(gear and type(r.world.ride) == "function", "Tractor equipment hooks are unavailable. Reconnect and copy diagnostics.")
        for itemId, item in pairs(r.items) do
            if item.name == "Dear John Tractor" and item.ride == "tractor" and count(itemId) > 0 then
                assert(not tractor, "Multiple Dear John Tractor definitions match the backpack.")
                tractor = itemId
            end
        end
        assert(tractor, "Dear John Tractor is not in the backpack. Choose Fist or bring your tractor.")
        -- Native riding harvests every seed it crosses. Do not destroy another crop.
        for y = 0, r.world.h - 1 do
            for x = 0, r.world.w - 1 do
                local tile = r.world.fg[y] and r.world.fg[y][x]
                if tile ~= seedId and r.items[tile] and r.items[tile].kind == "seed" then
                    error("This farm contains another seed type. Use Fist for a mixed farm; Tractor harvests every tree it drives over.")
                end
            end
        end
    else assert(r.handlers and type(r.handlers.hit) == "function", "The Fist tree harvesting hook is unavailable.") end
    if gear then
        rememberHarvestEquipment(gear)
    elseif r.world.riding and r.world.riding.harvest then
        error("Remove your harvesting vehicle before using Fist; its equipment hook is unavailable.")
    end
    local function feet(itemId)
        local hold = takeControls()
        hold.direction, hold.jump = 0, false
        if gear then
            local current = gear.feet()
            if current ~= itemId then
                if current then gear.wear(current) end
                if itemId then gear.wear(itemId) end
                local deadline = os.clock() + App.config.options.actionTimeout
                while (r.world.riding and r.world.riding.harvest == true or false) ~= (itemId == tractor and tractor ~= nil) do
                    worldCheck(name, token)
                    assert(os.clock() < deadline, "Harvest equipment did not update. Check your worn footwear.")
                    pause(0.025, token)
                end
            end
        end
    end
    feet(nil)
    App.harvestPhase, App.harvestGearError = "Breaking ripe trees", nil
    for _, job in ipairs(work) do
        worldCheck(name, token)
        local row = job.row
        local points = Core.ripeTrees(r.world, seedId, row, r.treeRipe)
        if #points > 0 then
            setStatus((method == "tractor" and "Driving Dear John Tractor" or "Harvesting with Fist") .. " on row " .. row.y .. "...")
            moveTo(row.direction == 1 and row.left or row.right, row.y, name, token)
            if method == "tractor" then
                feet(tractor)
                local deadline, passes = os.clock() + math.max(90, App.config.options.moveTimeout), 0
                while true do
                    worldCheck(name, token)
                    local remaining = Core.ripeTrees(r.world, seedId, row, r.treeRipe)
                    if #remaining == 0 then
                        pause(0.25, token) -- Observe corrections before declaring the row harvested.
                        remaining = Core.ripeTrees(r.world, seedId, row, r.treeRipe)
                        if #remaining == 0 then break end
                    end
                    passes = passes + 1
                    assert(passes <= 3 and os.clock() < deadline, "Tractor did not clear ripe trees on row " .. row.y .. ". Check access and equipment.")
                    moveTo(remaining[#remaining].x, row.y, name, token, function()
                        assert(gear.feet() == tractor, "Dear John Tractor was unequipped during harvesting.")
                        return #Core.ripeTrees(r.world, seedId, row, r.treeRipe) > 0
                    end)
                    for _, point in ipairs(Core.ripeTrees(r.world, seedId, row, r.treeRipe)) do
                        moveTo(point.x, point.y, name, token)
                        local waitUntil = os.clock() + App.config.options.actionTimeout
                        while tileAt(point.x, point.y) == seedId and r.treeRipe(point.x, point.y, seedId) do
                            assert(gear.feet() == tractor, "Dear John Tractor was unequipped during harvesting.")
                            assert(os.clock() < waitUntil, "Tractor did not harvest the tree at " .. point.x .. ", " .. point.y .. ". Check access.")
                            pause(0.05, token)
                            worldCheck(name, token)
                        end
                    end
                end
                feet(nil)
                for _, point in ipairs(points) do
                    assert(tileAt(point.x, point.y) == 0, "A harvested tree was replaced before confirmation.")
                    App.stats.trees = App.stats.trees + 1
                end
            else
                for _, point in ipairs(points) do
                    worldCheck(name, token)
                    if tileAt(point.x, point.y) == seedId and r.treeRipe(point.x, point.y, seedId) then
                        moveTo(point.x, point.y, name, token)
                        if tileAt(point.x, point.y) == seedId and r.treeRipe(point.x, point.y, seedId) then
                            local tries = 0
                            repeat
                                worldCheck(name, token)
                                assert(tileAt(point.x, point.y) == seedId and r.treeRipe(point.x, point.y, seedId), "The target tree changed before harvesting.")
                                tries = tries + 1
                                assert(tries <= 3, "Fist did not harvest the ripe tree at " .. point.x .. ", " .. point.y .. ". Check access.")
                                r.handlers.hit(point.x, point.y)
                                pause(math.max(0.25, App.config.options.punchDelay), token)
                            until tileAt(point.x, point.y) ~= seedId
                            assert(tileAt(point.x, point.y) == 0, "The target tree was replaced while harvesting.")
                            settleTile(point.x, point.y, 0, 0.25, name, token)
                            App.stats.trees = App.stats.trees + 1
                        end
                    end
                end
            end
        end
    end
    App.harvestPhase = "Collecting blocks and seeds"
end

local function runHarvest(token)
    Core.checkSetup(App.config, "harvest", runtime().items)
    local box, id = App.config.points.farmBox, App.config.blockId
    local r = worldCheck(box.world, token)
    local seedId = Core.seedId(r.items, id)
    storageCount(box, id, seedId) -- Reject unsuitable storage before claiming anything.
    return harvestEquipmentScope(function() return withoutPickups(function()
        refreshInventory(token)
        runTreeHarvest(token)
        r = worldCheck(box.world, token)
        App.harvestPhase = "Collecting blocks and seeds"
        local storedBefore, seedsBefore = App.stats.stashed, App.stats.stashedSeeds
        local attempts, retryAt, needsApproach, approached = {}, {}, {}, {}
        local lastRefusal = {}
        App.lastHarvestRefusal = nil
        local sweepRow, sweepX, sweepDirection
        local farmRows, farmRowsByY, activeFarmRow, restrictRoute = {}, {}, nil, false
        local rangeLimited, emptySince = false, nil
        local deadline = os.clock() + App.config.options.actionTimeout
        local function selected(drop)
            return type(drop) == "table" and not drop.display and (drop.id == id or drop.id == seedId)
                and type(drop.uid) == "number" and type(drop.n) == "number" and drop.n > 0
                and type(drop.x) == "number" and type(drop.y) == "number"
        end
        local function capacityBlocked()
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) and r.inventory:room(drop.id) <= 0 then
                    assert(count(drop.id) > 0, "Your backpack has no room for harvested blocks or seeds. Free a slot before collecting.")
                    return true
                end
            end
            return false
        end
        local function onTaken(_, takenId, amount)
            if takenId == id then App.stats.harvested = App.stats.harvested + amount
            else App.stats.harvestSeeds = App.stats.harvestSeeds + amount end
        end
        local function near(state, drop)
            return Navigation.pickupOverlap(state, drop)
        end
        local function farmRowFor(drop)
            local closest, distance
            local y = math.floor(drop.y)
            for candidateY = y - 1, y + 1 do
                local index = farmRowsByY[candidateY]
                local row = index and farmRows[index]
                if row and drop.x >= row.left - 0.1 and drop.x <= row.right + 1.1
                    and near({x = drop.x, y = row.y + 1}, drop) then
                    local delta = math.abs(drop.y - (row.y + 0.5))
                    if not distance or delta < distance then closest, distance = index, delta end
                end
            end
            return closest
        end
        local function onActiveRow(drop)
            return not restrictRoute or farmRowFor(drop) == activeFarmRow
        end
        local function rowHasDrops(index)
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) and farmRowFor(drop) == index then return true end
            end
            return false
        end
        local function checkAttempts(drop)
            if (attempts[drop.uid] or 0) < 3 then return end
            error("The server refused harvested drop uid " .. drop.uid .. " at " .. drop.x .. ", " .. drop.y
                .. ". Last pickup: " .. tostring(lastRefusal[drop.uid])
                .. ". Check pickup reach and access; copy diagnostics.")
        end
        local function applyResults(results, fromRoute)
            local accepted = false
            for _, result in ipairs(results) do
                if result.amount > 0 then
                    accepted, needsApproach[result.uid] = true, nil
                else
                    rangeLimited = true
                    local attemptState = {x = result.avatarX, y = result.avatarY}
                    local attemptDrop = {x = result.dropX, y = result.dropY}
                    lastRefusal[result.uid] = string.format("avatar %.2f, %.2f; delta %.2f, %.2f; overlap %s",
                        result.avatarX, result.avatarY, result.dropX - result.avatarX, result.dropY - result.avatarY,
                        tostring(near(attemptState, attemptDrop)))
                    App.lastHarvestRefusal = "uid " .. result.uid .. " at " .. result.dropX .. ", " .. result.dropY
                        .. "; " .. lastRefusal[result.uid]
                    needsApproach[result.uid] = fromRoute or approached[result.uid] or nil
                    for _, drop in pairs(r.world.dropList()) do
                        if drop.uid == result.uid and near(position(), drop) then
                            needsApproach[result.uid] = true
                            break
                        end
                    end
                end
                approached[result.uid] = nil
            end
            if accepted then
                refreshInventory(token)
                deadline = os.clock() + App.config.options.actionTimeout
            end
            return accepted
        end
        local function collectOnRoute(state)
            if restrictRoute and not rowHasDrops(activeFarmRow) then return false end
            if not state.grounded then return end
            sweepRow, sweepX = math.floor(state.y - 0.01), state.x
            if capacityBlocked() then return false end
            local focus, found = {}, false
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) and near(state, drop) and onActiveRow(drop) and not needsApproach[drop.uid]
                    and math.abs(drop.x - state.x) <= 0.55 then
                    focus[drop.uid], found = true, true
                end
            end
            if not found then return end
            -- Stop advancing until these stacks are gone, including late replies,
            -- partial takes and additional batches at the same pickup position.
            local hold = takeControls()
            hold.direction, hold.jump = 0, false
            local pickupDeadline = os.clock() + App.config.options.actionTimeout
            while true do
                worldCheck(box.world, token)
                state = position()
                sweepRow, sweepX = math.floor(state.y - 0.01), state.x
                if capacityBlocked() then return false end
                local targets, remaining = {}, false
                for _, drop in pairs(r.world.dropList()) do
                    if selected(drop) and near(state, drop) and onActiveRow(drop) and not needsApproach[drop.uid] then
                        if math.abs(drop.x - state.x) <= 0.55 then focus[drop.uid] = true end
                        if focus[drop.uid] then
                            remaining = true
                            retryAt[drop.uid] = retryAt[drop.uid] or ((drop.refused or -math.huge) + 1)
                            checkAttempts(drop)
                            if not drop.pending and not drop.taking
                                and os.clock() >= math.max(drop.readyAt or 0, retryAt[drop.uid]) then
                                table.insert(targets, drop)
                            end
                        end
                    end
                end
                if not remaining then return end
                assert(os.clock() < pickupDeadline,
                    "Nearby harvested stacks did not finish collecting. Check pending drops and copy diagnostics.")
                if #targets > 0 then
                    local results = takeDropBatch(box, targets, attempts, retryAt, function(drop)
                        return selected(drop) and onActiveRow(drop) and focus[drop.uid]
                            and not drop.pending and not drop.taking and near(position(), drop)
                    end, token, onTaken)
                    if applyResults(results, true) then pickupDeadline = os.clock() + App.config.options.actionTimeout
                    else pause(0.05, token) end
                    -- A refusal leaves this UID for a precise approach after
                    -- the row pass. Do not hold and exhaust retries here.
                else pause(0.05, token) end
            end
        end
        local function returnToStorage()
            local state, point = position(), box
            local dx = math.abs(state.x - ((point.standX or point.x) + 0.5))
            local dy = math.abs(state.y - ((point.standY or point.y) + 1))
            if not App.config.options.harvestRespawn then
                App.harvestReturnDebug = "Walking; Respawn to Farm storage is Off."
                return
            end
            if dx + dy <= 4 then
                App.harvestReturnDebug = "Walking; already within four tiles of Farm storage."
                return
            end
            local respawn = r.respawn or r.world.respawn
            if type(respawn) ~= "function" then
                App.harvestReturnDebug = "Respawn unavailable: " .. (r.respawnSource or "no native action attached")
                    .. ". Walking to Farm storage."
                setStatus("Respawn unavailable; walking to Farm storage. Copy diagnostics to check the hook.")
                return
            end
            local hold = takeControls()
            hold.direction, hold.jump = 0, false
            assert(App.pending == 0, "Wait for pending pickups before respawning to storage.")
            refreshInventory(token)
            local beforeX, beforeY, beforeCount, beforeSeeds = state.x, state.y, count(id), count(seedId)
            local began = os.clock()
            App.harvestReturnDebug = "Respawn requested using " .. (r.respawnSource or "world method")
                .. " from " .. string.format("%.2f, %.2f", beforeX, beforeY)
            setStatus("Respawning near Farm storage...")
            bounded(respawn, App.config.options.actionTimeout, token)
            local readyDeadline, changed, stable = os.clock() + math.max(15, App.config.options.actionTimeout), false, nil
            while true do
                checkpoint(token)
                assert(r.world.name == box.world and not pickerOpen(r), "The world changed while respawning to Farm storage.")
                local avatar = r.body.state()
                if not avatar.active or avatar.dead or math.abs(avatar.x - beforeX) + math.abs(avatar.y - beforeY) > 0.5 then changed = true end
                if changed and avatar.active and not avatar.dead and avatar.grounded then
                    stable = stable or os.clock()
                    if os.clock() - stable >= 0.25 then break end
                else stable = nil end
                assert(os.clock() < readyDeadline, "Respawn did not finish. Items remain in the backpack; check diagnostics.")
                pause(0.05, token)
            end
            worldCheck(box.world, token)
            refreshInventory(token)
            assert(count(id) == beforeCount and count(seedId) == beforeSeeds, "Backpack blocks or seeds changed during respawn. Check inventory before restarting harvest.")
            local arrived = position()
            App.harvestReturnDebug = "Respawn finished in " .. string.format("%.2fs", os.clock() - began)
                .. " at " .. string.format("%.2f, %.2f", arrived.x, arrived.y) .. "; backpack confirmed."
        end
        local function stash()
            if count(id) == 0 and count(seedId) == 0 then return end
            returnToStorage()
            setStatus("Storing harvested " .. r.items[id].name .. " in Farm storage...")
            if count(id) > 0 then
                App.stats.stashed = App.stats.stashed + deposit(box, id, count(id), token, nil, seedId)
            end
            if count(seedId) > 0 then
                App.stats.stashedSeeds = App.stats.stashedSeeds + deposit(box, seedId, count(seedId), token, nil, id)
            end
            deadline = os.clock() + App.config.options.actionTimeout
        end
        stash() -- Includes the selected blocks already filling the backpack.
        -- Wide supported rows are the farm, rather than a storage box's roof.
        -- Retain every row in this snapshot, including rows without loose drops.
        do
            local map = navigationMap(r)
            for _, row in ipairs(Core.farmRows(r.world, r.items)) do
                local left, right, count
                count = 0
                for x = row.left, row.right do
                    if (map.solid(x, row.y + 1) or map.platform(x, row.y + 1))
                        and not map.solid(x, row.y) and not map.danger(x, row.y) and not map.danger(x, row.y + 1) then
                        left, right, count = left or x, x, count + 1
                    end
                end
                if count >= 3 then
                    table.insert(farmRows, {y = row.y, left = left, right = right})
                    farmRowsByY[row.y] = #farmRows
                end
            end
        end
        if #farmRows >= 2 then
            for index = 1, #farmRows do
                -- Keep the physical row index for direction, but visit only live harvest work.
                if rowHasDrops(index) then
                    activeFarmRow = index
                    restrictRoute, rangeLimited = true, true
                    local row, direction = farmRows[index], index % 2 == 1 and 1 or -1
                    local entry, exit = direction == 1 and row.left or row.right, direction == 1 and row.right or row.left
                    if capacityBlocked() then
                        stash()
                    end
                    setStatus("Collecting farm row " .. index .. "/" .. #farmRows .. " at " .. row.y .. "...")
                    moveTo(entry, row.y, box.world, token, function() return rowHasDrops(index) end)
                    local swept = false
                    while true do
                        worldCheck(box.world, token)
                        if not rowHasDrops(index) then break end
                        if capacityBlocked() then
                            local saved = position()
                            stash()
                            moveTo(math.floor(saved.x), math.floor(saved.y - 0.01), box.world, token,
                                function() return rowHasDrops(index) end)
                        end
                        if not swept then
                            swept = moveTo(exit, row.y, box.world, token, collectOnRoute) ~= false
                            deadline = os.clock() + App.config.options.actionTimeout
                        end
                        if swept then
                            local remaining = {}
                            for _, drop in pairs(r.world.dropList()) do
                                if selected(drop) and onActiveRow(drop) then
                                    retryAt[drop.uid] = retryAt[drop.uid] or ((drop.refused or -math.huge) + 1)
                                    table.insert(remaining, drop)
                                end
                            end
                            if #remaining == 0 then break end
                            table.sort(remaining, function(a, b)
                                return a.x == b.x and a.uid < b.uid or a.x * direction < b.x * direction
                            end)
                            local drop, state = remaining[1], position()
                            checkAttempts(drop)
                            if not near(state, drop) or needsApproach[drop.uid] then
                                local goal, message = Navigation.pickupGoal(navigationMap(r), state, drop, {
                                    nativeOnly = true, step = function() pause(0, token); worldCheck(box.world, token) end,
                                })
                                assert(goal, tostring(message) .. " Drop uid " .. drop.uid .. " at " .. drop.x .. ", " .. drop.y)
                                local finished = moveTo(goal.x, goal.y, box.world, token, collectOnRoute)
                                if finished ~= false and near(position(), drop) then
                                    needsApproach[drop.uid], approached[drop.uid] = nil, true
                                end
                                deadline = os.clock() + App.config.options.actionTimeout
                            elseif not drop.pending and not drop.taking and os.clock() >= math.max(drop.readyAt or 0, retryAt[drop.uid]) then
                                local results = takeDropBatch(box, remaining, attempts, retryAt, function(candidate)
                                    return selected(candidate) and onActiveRow(candidate) and not needsApproach[candidate.uid]
                                        and not candidate.pending and not candidate.taking and near(position(), candidate)
                                        and os.clock() >= math.max(candidate.readyAt or 0, retryAt[candidate.uid] or 0)
                                end, token, onTaken)
                                applyResults(results, true)
                                pause(0.03, token)
                            else
                                assert(os.clock() < deadline, "Harvested drops did not become ready. Check pending pickups and copy diagnostics.")
                                pause(0.05, token)
                            end
                        end
                    end
                end
            end
            activeFarmRow, restrictRoute = nil, false
        end
        while true do
            worldCheck(box.world, token)
            local state = position()
            local remaining = {}
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) then
                    -- Suppressed native pickup attempts can keep updating refused.
                    -- Freeze its initial cooldown; our own refusals update retryAt.
                    retryAt[drop.uid] = retryAt[drop.uid] or ((drop.refused or -math.huge) + 1)
                    table.insert(remaining, drop)
                end
            end
            if #remaining == 0 then
                stash()
                emptySince = emptySince or os.clock()
                if os.clock() - emptySince >= math.max(0.3, App.config.options.collectDelay) then
                    setStatus("Finished collecting harvest: " .. (App.stats.stashed - storedBefore)
                        .. " blocks and " .. (App.stats.stashedSeeds - seedsBefore) .. " seeds stored in the farm Display Box.")
                    return
                end
                pause(0.05, token)
            else
                emptySince = nil
                if capacityBlocked() then
                    stash()
                    state = position()
                end
                table.sort(remaining, function(a, b)
                    if sweepRow and sweepDirection then
                        local function inSweep(drop)
                            return math.floor(drop.y) == sweepRow and (drop.x - sweepX) * sweepDirection >= -0.2
                        end
                        local aSweep, bSweep = inSweep(a), inSweep(b)
                        if aSweep ~= bSweep then return aSweep end
                        if aSweep and a.x ~= b.x then return a.x * sweepDirection < b.x * sweepDirection end
                    end
                    local da = math.abs(a.x - state.x) + math.abs(a.y - state.y) * 2
                    local db = math.abs(b.x - state.x) + math.abs(b.y - state.y) * 2
                    return da == db and a.uid < b.uid or da < db
                end)
                local function ready(drop)
                    return not drop.pending and not drop.taking
                        and os.clock() >= math.max(drop.readyAt or 0, retryAt[drop.uid])
                end
                local function eligible(drop)
                    return selected(drop) and ready(drop) and not needsApproach[drop.uid]
                        and (not rangeLimited or near(state, drop) or approached[drop.uid])
                end
                local targets, nextDrop = {}, nil
                for _, drop in ipairs(remaining) do
                    checkAttempts(drop)
                    if ready(drop) then
                        nextDrop = nextDrop or drop
                        if eligible(drop) then table.insert(targets, drop) end
                    end
                end
                if #targets > 0 then
                    setStatus("Collecting harvested " .. r.items[id].name .. "... " .. #remaining .. " loose drops remain.")
                    local results = takeDropBatch(box, targets, attempts, retryAt, eligible, token,
                        onTaken)
                    if not applyResults(results) then pause(0.05, token) end
                elseif rangeLimited and nextDrop and (not near(state, nextDrop) or needsApproach[nextDrop.uid]) then
                    setStatus("Walking to harvested drop uid " .. nextDrop.uid .. "...")
                    local goal, message = Navigation.pickupGoal(navigationMap(r), state, nextDrop, {
                        nativeOnly = true,
                        step = function() pause(0, token); worldCheck(box.world, token) end,
                    })
                    assert(goal, tostring(message) .. " Drop uid " .. nextDrop.uid .. " at " .. nextDrop.x .. ", " .. nextDrop.y)
                    if sweepRow ~= goal.y then
                        sweepRow, sweepX = goal.y, goal.x + 0.5
                        sweepDirection = nextDrop.x >= state.x and 1 or -1
                    elseif (nextDrop.x - sweepX) * sweepDirection < -0.2 then
                        sweepDirection = -sweepDirection
                    end
                    if not needsApproach[nextDrop.uid] then
                        local edge = Navigation.rowEnd(navigationMap(r), goal, sweepDirection)
                        for _, drop in ipairs(remaining) do
                            local tileX = math.floor(drop.x)
                            if math.floor(drop.y) == goal.y and (tileX - goal.x) * sweepDirection > 0
                                and (edge - tileX) * sweepDirection >= 0 then goal.x = tileX end
                        end
                    end
                    local finished = moveTo(goal.x, goal.y, box.world, token, collectOnRoute)
                    if finished ~= false and near(position(), nextDrop) then
                        needsApproach[nextDrop.uid], approached[nextDrop.uid] = nil, true
                    end
                    deadline = os.clock() + App.config.options.actionTimeout
                    pause(0.03, token)
                else
                    assert(os.clock() < deadline, "Harvested drops did not become ready. Check pending pickups and copy diagnostics.")
                    pause(0.05, token)
                end
            end
        end
    end) end)
end

local function runPNB(token, shouldYield)
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
        -- Yield only between complete place/break/pickup iterations. An existing
        -- block from an interrupted iteration must be settled before travel.
        if not existing and shouldYield and shouldYield() then
            collectDrops(p.pnb, blockId, seedId, token)
            return false
        end
        if count(blockId) == 0 and not existing then
            setStatus("Refilling blocks from the right storage box...")
            local taken = withdraw(p.blockBox, blockId, token)
            if taken == 0 then
                setStatus("Finished: no blocks remain in your backpack or block storage.")
                return true
            end
            moveToPoint(p.pnb, token)
        end
        if not existing and shouldYield and shouldYield() then
            collectDrops(p.pnb, blockId, seedId, token)
            return false
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

local function recentPNBWorld(name, token)
    setStatus("Checking Recently Visited Worlds for " .. name .. "...")
    local ok, lists = pcall(bounded, runtime().world.call, App.config.options.actionTimeout, token, "ListWorlds")
    checkpoint(token)
    assert(App.pending == 0, "The recent-world request did not settle. Wait for it before rejoining.")
    if ok and type(lists) == "table" and type(lists.recent) == "table" then
        for index, world in ipairs(lists.recent) do
            if type(world) == "string" and world:upper() == name:upper() then
                App.recentWorldDebug = "Saved PNB world found at Recent position " .. index .. ": " .. world
                return world, true
            end
        end
    end
    App.recentWorldDebug = "Saved PNB world absent from Recent or list unavailable; using " .. name
    return name, false
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
    setStatus("Waiting for the saved world and avatar to load...")
    local readyDeadline = os.clock() + App.config.options.actionTimeout + 15
    local stableSince, entryWaitUntil, attempts = nil, 0, 0
    local recentChecked, target, fromRecent = false, name, false
    while true do
        checkpoint(token)
        assert(r.world.name == name or r.world.name == "" or r.world.name == nil,
            "Arrived in another world. Check the saved PNB world.")
        -- The exit animation can become inactive before the world name clears.
        -- Reconsider re-entry throughout loading, including a second picker return.
        if (r.world.name == nil or r.world.name == "" or pickerOpen(r)) and os.clock() >= entryWaitUntil then
            assert(type(r.world.enter) == "function", "The world re-entry hook is unavailable.")
            attempts = attempts + 1
            assert(attempts <= 3, "The saved world repeatedly returned to the picker during recovery.")
            savePNBResume()
            local canResume = queueResume()
            setStatus("Rejoining " .. name .. " (attempt " .. attempts .. "/3)...")
            pause(attempts == 1 and 1 or 2, token)
            assert(r.world.name == name or r.world.name == "" or r.world.name == nil,
                "Arrived in another world. Check the saved PNB world.")
            if r.world.name ~= name or pickerOpen(r) then
                if not recentChecked then
                    target, fromRecent = recentPNBWorld(name, token)
                    recentChecked = true
                    assert(r.world.name == name or r.world.name == "" or r.world.name == nil,
                        "Arrived in another world. Check the saved PNB world.")
                    setStatus("Rejoining " .. target .. (fromRecent and " from Recently Visited Worlds" or "")
                        .. " (attempt " .. attempts .. "/3)...")
                end
                local entered, message, teleport = bounded(r.world.enter,
                    App.config.options.actionTimeout + 15, token, target)
                if teleport then
                    App.teleporting = true
                    setStatus(canResume and "Changing servers; the saved farm will resume after loading."
                        or "Changing servers. Run the loader after arrival, then use Resume saved farm.")
                    local deadline = os.clock() + 45
                    while os.clock() < deadline do pause(0.2, token) end
                    error("Server teleport did not finish. Use Resume saved farm after checking the world.")
                end
                if not entered then
                    assert(App.pending == 0, "A world entry request is still pending.")
                    assert(attempts < 3, tostring(message or "Could not rejoin the saved world."))
                elseif r.picker then
                    assert(r.world.name == name, "Arrived in another world. Check the saved PNB world.")
                    r.picker.complete()
                end
                entryWaitUntil = os.clock() + (entered and 2 or 0)
            end
            stableSince = nil
            readyDeadline = os.clock() + App.config.options.actionTimeout + 15
            setStatus("Waiting for the saved world and avatar to load...")
        end
        local state = r.body and r.body.state()
        if r.world.name == name and not pickerOpen(r) and state and state.active and not state.dead
            and not player:GetAttribute("Frozen") then
            stableSince = stableSince or os.clock()
            if os.clock() - stableSince >= 1 then break end
        else stableSince = nil end
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

local function classifyPNBFault(problem, token)
    if type(problem) == "table" and problem.recoverable then return problem end
    releaseControls()
    local name, deadline = App.config.points.pnb.world, os.clock() + 1.5
    -- An interrupted RPC can fail before the local exit state changes. Allow
    -- that short transition to reveal itself without retrying mutating actions.
    repeat
        checkpoint(token)
        local r = runtime()
        if r.world.name == "" or r.world.name == nil or pickerOpen(r) then
            return recoverable("Returned to the world picker during an action: " .. tostring(problem), name, "worldPicker")
        end
        if r.world.name ~= name then return problem end
        local state = r.body and r.body.state()
        if state and (not state.active or state.dead) then
            return recoverable("The avatar became unavailable during an action: " .. tostring(problem), name, "avatar")
        end
        if os.clock() >= deadline then return problem end
        pause(0.1, token)
    until false
end

local function runTransfer(token, saved, travel)
    if not travel then Core.checkSetup(App.config, "transfer", runtime().items) end
    local p, id = App.config.points, App.config.blockId
    local seedId = Core.seedId(runtime().items, id)
    local phase = saved and saved.phase or "pickup"
    local cargo = saved and saved.cargo or 0
    assert(phase == "pickup" or phase == "deliver" or phase == "return" or phase == "returnSeeds", "Invalid transfer resume phase.")
    if saved then
        local expected = {[p.farmBox.world] = true}
        if phase ~= "pickup" then expected[p.blockBox.world] = true end
        local deadline = os.clock() + App.config.options.actionTimeout + 15
        setStatus("Waiting for the transfer world and avatar...")
        while true do
            checkpoint(token)
            local r = runtime()
            assert(r.world.name == nil or r.world.name == "" or expected[r.world.name],
                "The saved transfer arrived in an unexpected world. Check its doors and destination.")
            if expected[r.world.name] then
                if pickerOpen(r) then r.picker.complete() end
                local state = r.body and r.body.state()
                if state and state.active and not state.dead and not player:GetAttribute("Frozen") then break end
            end
            assert(os.clock() < deadline, "The transfer world or avatar did not become ready after loading.")
            pause(0.05, token)
        end
        if saved.seeds then
            refreshInventory(token)
            assert(count(seedId) >= saved.seeds, "Some saved transfer seeds are missing. Check the backpack before resuming.")
        end
    else worldCheck(p.farmBox.world, token) end
    while true do
        checkpoint(token)
        if phase == "pickup" then
            worldCheck(p.farmBox.world, token)
            if storageCount(p.farmBox, id, seedId) == 0 then
                phase = "returnSeeds"
                saveResume(phase, 0)
            else
                setStatus("Taking blocks from Farm storage; keeping up to 200 seeds for mixed-box transfers...")
                saveResume("pickupPending", 0)
                local taken, seeds = withdraw(p.farmBox, id, token, seedId)
                assert(taken > 0 or seeds > 0 and count(seedId) <= 200, "No blocks or matching seeds were withdrawn.")
                -- A box can return seeds first. Keep them so the next withdrawal has no seed room.
                cargo = taken
                phase = taken > 0 and "deliver" or "pickup"
                saveResume(phase, cargo)
            end
        elseif phase == "deliver" then
            if runtime().world.name == p.farmBox.world then
                setStatus("Going through the door to the breaking world...")
                if travel then travel(p.blockBox.world)
                else enterDoor(p.farmDoor, p.blockBox, "deliver", cargo, token) end
            end
            worldCheck(p.blockBox.world, token)
            setStatus("Putting the transported blocks into PNB storage...")
            -- Save the count before issuing a mutating request. An interrupted deposit is
            -- ambiguous; resume refuses to repeat it until the player checks the inventory.
            local moved = deposit(p.blockBox, id, cargo, token, function(available)
                assert(available >= cargo, "Some saved cargo is missing. Check your backpack before resuming.")
                saveResume("depositPending", cargo)
            end)
            App.stats.trips = App.stats.trips + 1
            App.stats.moved = App.stats.moved + moved
            cargo = 0
            phase = "return"
            saveResume(phase, cargo)
        elseif phase == "return" then
            if runtime().world.name == p.blockBox.world then
                setStatus("Returning through the door to the farm world...")
                if travel then travel(p.farmBox.world)
                else enterDoor(p.breakDoor, p.farmBox, "return", 0, token) end
            end
            worldCheck(p.farmBox.world, token)
            phase = "pickup"
            saveResume(phase, 0)
        elseif phase == "returnSeeds" then
            worldCheck(p.farmBox.world, token)
            if count(seedId) > 0 then
                setStatus("Returning the held seeds to the Farm Display Box...")
                deposit(p.farmBox, seedId, count(seedId), token, function()
                    saveResume("seedReturnPending", 0)
                end, id)
            end
            clearResume()
            setStatus("Finished: all Farm storage blocks moved; seeds returned to the same box.")
            return
        end
    end
end

local function clearPlantResume()
    App.plantState = nil
    if exists(PLANT_RESUME_FILE) then
        if type(delfile) == "function" then delfile(PLANT_RESUME_FILE)
        else writeJSON(PLANT_RESUME_FILE, {version = 1, active = false}) end
    end
end
local function savePlantResume(state)
    saveSession()
    local copy = {worldIndex = state.worldIndex, phase = state.phase, skipped = {}, pending = state.pending}
    if state.rows then
        copy.rows = {}
        for _, row in ipairs(state.rows) do
            table.insert(copy.rows, {y = row.y, left = row.left, right = row.right})
        end
        copy.rowY = state.rowY
    end
    for key, reason in pairs(state.skipped or {}) do copy.skipped[key] = reason end
    writeJSON(PLANT_RESUME_FILE, {version = 1, active = true, userId = player.UserId, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, state = copy})
    App.plantState = state
    if App.rotationState then
        App.rotationState.plant = state
        saveRotationResume(App.rotationState)
    end
end
local function readPlantResume(record)
    if not record then
        if not exists(PLANT_RESUME_FILE) then return nil end
        record = decode(readfile(PLANT_RESUME_FILE))
    end
    if not record.active then return nil end
    assert(record.version == 1 and record.userId == player.UserId, "The saved planting task belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600, "Saved planting is over six hours old. Start it again.")
    record.config, record.profile = Core.validate(record.config), Core.profileName(record.profile)
    local state = record.state
    assert(type(state) == "table" and type(state.worldIndex) == "number" and state.worldIndex == math.floor(state.worldIndex)
        and state.worldIndex >= 1 and state.worldIndex <= #record.config.planting.worlds + 1
        and (state.phase == "farm" or state.phase == "stock" or state.phase == "pickupPending")
        and type(state.skipped) == "table", "Invalid saved planting progress.")
    for key, reason in pairs(state.skipped) do
        assert(type(key) == "string" and key:match("^%d+:%d+$") and type(reason) == "string", "Invalid skipped planting tile.")
    end
    if state.rows then
        assert(type(state.rows) == "table", "Invalid saved farm rows.")
        for key in pairs(state.rows) do
            assert(type(key) == "number" and key == math.floor(key) and key >= 1 and key <= #state.rows,
                "Invalid saved farm row list.")
        end
        local previous = -1
        for _, row in ipairs(state.rows) do
            assert(type(row) == "table", "Invalid saved farm row.")
            for _, key in ipairs({"y", "left", "right"}) do
                assert(type(row[key]) == "number" and row[key] == math.floor(row[key])
                    and row[key] >= 0 and row[key] <= 65535, "Invalid saved farm row.")
            end
            assert(row.y > previous and row.left <= row.right, "Invalid saved farm row order.")
            previous = row.y
        end
        if state.rowY ~= nil then
            local found = false
            for _, row in ipairs(state.rows) do if row.y == state.rowY then found = true end end
            assert(found, "Invalid saved planting row.")
        end
    else assert(state.rowY == nil, "Missing saved farm rows.") end
    if state.pending then
        local point = state.pending
        assert(state.phase == "farm" and point.world == record.config.planting.worlds[state.worldIndex], "Invalid pending seed world.")
        for _, key in ipairs({"x", "y", "before"}) do
            assert(type(point[key]) == "number" and point[key] == math.floor(point[key])
                and point[key] >= 0 and point[key] <= 65535, "Invalid pending seed placement.")
        end
        assert(point.before >= 1 and point.before <= 200, "Invalid pending seed count.")
    end
    return record
end
local function enterPlantWorld(name, state, token)
    local r = runtime()
    local attempts, nextEntry, stableSince = 0, 0, nil
    local deadline = os.clock() + App.config.options.actionTimeout + 15
    releaseControls()
    while App.pending > 0 do
        checkpoint(token)
        assert(os.clock() < deadline, "A previous request did not settle; cannot enter another world yet.")
        pause(0.05, token)
    end
    while true do
        checkpoint(token)
        if (r.world.name ~= name or pickerOpen(r)) and os.clock() >= nextEntry then
            attempts = attempts + 1
            assert(attempts <= 3, "Planting world repeatedly returned to the picker: " .. name)
            assert(type(r.world.enter) == "function", "The world entry hook is unavailable.")
            if App.rotationState then saveRotationResume(App.rotationState) else savePlantResume(state) end
            local queued = queueResume()
            setStatus("Entering " .. name .. "...")
            local entered, message, teleport = bounded(r.world.enter, App.config.options.actionTimeout + 15, token, name)
            if teleport then
                App.teleporting = true
                setStatus(queued and (App.rotationState and "Changing servers; rotation will resume after loading." or "Changing servers; planting will resume after loading.")
                    or (App.rotationState and "Changing servers. Run the loader after arrival, then use Resume saved rotation."
                        or "Changing servers. Run the loader after arrival, then use Resume planting."))
                local teleportDeadline = os.clock() + 45
                while os.clock() < teleportDeadline do pause(0.2, token) end
                error(App.rotationState and "Server teleport did not finish. Use Resume saved rotation after arrival."
                    or "Server teleport did not finish. Use Resume planting after arrival.")
            end
            if not entered then assert(attempts < 3, tostring(message or "Could not enter " .. name))
            elseif r.picker and r.world.name == name then r.picker.complete() end
            nextEntry, stableSince = os.clock() + 2, nil
            deadline = os.clock() + App.config.options.actionTimeout + 15
        end
        local avatar = r.body and r.body.state()
        if r.world.name == name and not pickerOpen(r) and avatar and avatar.active and not avatar.dead
            and not player:GetAttribute("Frozen") then
            stableSince = stableSince or os.clock()
            if os.clock() - stableSince >= 1 then break end
        else stableSince = nil end
        assert(os.clock() < deadline, "Planting world or avatar did not finish loading: " .. name)
        pause(0.1, token)
    end
    App.teleporting = false
    takeControls()
    refreshInventory(token)
end
local function reconcilePlant(state, token)
    local point = state.pending
    if not point then return end
    worldCheck(point.world, token)
    local id = App.config.planting.seedId
    local actual, tile = refreshInventory(token)[id] or 0, tileAt(point.x, point.y)
    if actual == point.before - 1 and tile == id then
        App.stats.planted = App.stats.planted + 1
    else
        assert(actual == point.before and tile == 0,
            "Cannot reconcile the interrupted seed placement. Check the backpack and tile, then clear saved planting.")
    end
    state.pending = nil
    savePlantResume(state)
end
local function plantTile(point, state, token)
    return withoutPickups(function()
        local name, id = App.config.planting.worlds[state.worldIndex], App.config.planting.seedId
        local r = worldCheck(name, token)
        local before = refreshInventory(token)[id] or 0
        if not Core.plantingTile(r.world, r.items, point.x, point.y) then return false end
        if not r.handlers.canPlace(r.items[id], point.x, point.y) then return false end
        assert(before > 0, "No planting seeds are left in the backpack.")
        state.pending = {world = name, x = point.x, y = point.y, before = before}
        savePlantResume(state)
        r.handlers.plantSeed(id, point.x, point.y)
        pause(math.max(0.2, App.config.options.placeDelay), token)
        local deadline = os.clock() + App.config.options.actionTimeout
        while true do
            worldCheck(name, token)
            local after = refreshInventory(token)[id] or 0
            assert(after == before or after == before - 1, "Seed count changed unexpectedly while planting. Check diagnostics before resuming.")
            if after == before - 1 and tileAt(point.x, point.y) == id then break end
            assert(os.clock() < deadline, "The server did not confirm a planted seed at " .. point.x .. ", " .. point.y .. ".")
            pause(0.15, token)
        end
        settleTile(point.x, point.y, id, 0.12, name, token)
        App.stats.planted = App.stats.planted + 1
        state.pending = nil
        savePlantResume(state)
        return true
    end)
end
local function rotationFarmStatus(r, box, id, seedId)
    local growing, ripeCount, remaining, unknownTimer = 0, 0, nil, false
    for _, row in ipairs(Core.farmRows(r.world, r.items)) do
        for x = row.left, row.right do
            if tileAt(x, row.y) == seedId then
                assert(type(r.treeRipe) == "function", "Tree growth hooks are unavailable for rotation.")
                local ripe = r.treeRipe(x, row.y, seedId)
                assert(ripe ~= nil, "Tree growth data is not ready. Reconnect and copy diagnostics.")
                if ripe then ripeCount = ripeCount + 1
                else
                    growing = growing + 1
                    local left = type(r.treeRemaining) == "function" and r.treeRemaining(x, row.y, seedId) or nil
                    if type(left) == "number" and left == left and left > 0 and left < math.huge then
                        remaining = math.max(remaining or left, left)
                    else unknownTimer = true end
                end
            end
        end
    end
    local crop = growing == 0 and ripeCount > 0 or storageCount(box, id, seedId) > 0
        or storageCount(box, seedId, id) > 0
    for _, drop in pairs(r.world.dropList()) do
        if not drop.display and (drop.id == id or drop.id == seedId) and (drop.n or 0) > 0 then crop = true end
    end
    return growing, crop, unknownTimer and math.min(remaining or 30, 30) or remaining or 30
end
local function runPlant(token, saved, lastWorldIndex)
    return harvestEquipmentScope(function()
        suspendHarvestVehicle(token)
        Core.checkSetup(App.config, "plant", runtime().items)
        local settings, id = App.config.planting, App.config.planting.seedId
        local state = saved and saved.state or {worldIndex = 1, phase = "farm", skipped = {}}
        assert(state.phase ~= "pickupPending", "A seed storage withdrawal was interrupted. Check the backpack and box, then clear saved planting.")
        savePlantResume(state)
        local lastWorld = lastWorldIndex or #settings.worlds
        while state.worldIndex <= lastWorld do
            checkpoint(token)
            if state.phase == "stock" then
                enterPlantWorld(settings.storageWorld, state, token)
                local box = App.config.points.plantBox
                if storageCount(box, id) == 0 then
                    clearPlantResume()
                    setStatus("Planting stopped: the seed storage box is empty. Unfinished farm: " .. settings.worlds[state.worldIndex])
                    return false
                end
                state.phase = "pickupPending"
                savePlantResume(state)
                withdraw(box, id, token)
                state.phase = "farm"
                savePlantResume(state)
            end
            local name = settings.worlds[state.worldIndex]
            enterPlantWorld(name, state, token)
            reconcilePlant(state, token)
            local r, refill = runtime(), false
            if not state.rows then state.rows = Core.farmRows(r.world, r.items); savePlantResume(state) end
            for _, row in ipairs(state.rows) do
                assert(row.y < r.world.h - 1 and row.right < r.world.w, "Saved farm rows no longer fit this world. Clear saved planting and start again.")
            end
            setStatus("Planting " .. r.items[id].name .. " in " .. name .. " (" .. state.worldIndex .. "/" .. #settings.worlds .. ")...")
            for _, point in ipairs(Core.plantingTiles(r.world, r.items, state.rows)) do
                checkpoint(token)
                worldCheck(name, token)
                local key = point.x .. ":" .. point.y
                if not state.skipped[key] and Core.plantingTile(r.world, r.items, point.x, point.y) then
                    if count(id) == 0 then refill = true; break end
                    local permitted = not r.world.areas or type(r.world.areas.canEdit) ~= "function" or r.world.areas.canEdit(point.x, point.y)
                    local arrived, issue = true, nil
                    if permitted then
                        arrived, issue = pcall(function()
                            if state.rowY ~= point.y then
                                for index, row in ipairs(state.rows) do
                                    if row.y == point.y then
                                        local arrived = moveTo(index % 2 == 1 and row.left or row.right, row.y, name, token, function()
                                            return Core.rowHasPlantingSpace(r.world, r.items, row, state.skipped)
                                        end)
                                        if arrived == false then return end
                                        break
                                    end
                                end
                                state.rowY = point.y
                                savePlantResume(state)
                            end
                            if Core.plantingTile(r.world, r.items, point.x, point.y) then moveTo(point.x, point.y, name, token) end
                        end)
                    end
                    checkpoint(token)
                    worldCheck(name, token)
                    if not arrived then
                        if type(issue) == "table" and issue.recoverable then error(issue, 0) end
                        local text = tostring(issue)
                        assert(text:find("route", 1, true) or text:find("position", 1, true) or text:find("support", 1, true)
                            or text:find("platform", 1, true) or text:find("timed out", 1, true), text)
                        state.skipped[key] = "unreachable"
                    elseif not permitted or not plantTile(point, state, token) then state.skipped[key] = "not permitted" end
                    if state.skipped[key] then savePlantResume(state) end
                end
            end
            if refill then
                state.phase = "stock"
            else
                local skipped = 0
                for _ in pairs(state.skipped) do skipped = skipped + 1 end
                if App.rotationState then
                    local rotation = App.rotationState
                    local growing, crop, left = rotationFarmStatus(r, App.config.rotation.farms[name], App.config.blockId, id)
                    rotation.readyAt[name] = growing > 0 and not crop and Workspace:GetServerTimeNow() + left or 0
                end
                setStatus("Processed " .. name .. ": " .. skipped .. " tiles skipped due to access or route. Moving to the next farm.")
                state.worldIndex, state.skipped, state.rows, state.rowY = state.worldIndex + 1, {}, nil, nil
            end
            savePlantResume(state)
        end
        clearPlantResume()
        setStatus((lastWorldIndex and "Finished replanting " .. settings.worlds[lastWorldIndex] .. "."
            or "Finished planting all configured farms.") .. " Seeds planted this session: " .. App.stats.planted)
        return true
    end)
end

local function clearRotationResume()
    App.rotationState = nil
    if exists(ROTATION_RESUME_FILE) then
        if type(delfile) == "function" then delfile(ROTATION_RESUME_FILE)
        else writeJSON(ROTATION_RESUME_FILE, {version = 1, active = false}) end
    end
end
saveRotationResume = function(state)
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        return result
    end
    saveSession()
    writeJSON(ROTATION_RESUME_FILE, {version = 1, active = true, userId = player.UserId, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, state = copy(state)})
    App.rotationState = state
    App.lastRotationSave = os.clock()
end
local function readRotationResume()
    if not exists(ROTATION_RESUME_FILE) then return nil end
    local record = decode(readfile(ROTATION_RESUME_FILE))
    if not record.active then return nil end
    assert(record.version == 1 and record.userId == player.UserId, "The saved rotation belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600, "Saved rotation is over six hours old. Check inventory and start again.")
    record.config, record.profile = Core.validate(record.config), Core.profileName(record.profile)
    local state = record.state
    local phases = {plant=true, wait=true, waitPNB=true, pnbStorePending=true, replant=true, harvest=true, transfer=true, seeds=true, seedDeliver=true,
        seedPickupPending=true, seedDepositPending=true, pnb=true, finish=true}
    assert(type(state) == "table" and phases[state.phase], "Invalid saved rotation phase.")
    for _, key in ipairs({"worldIndex", "cycle", "work", "seedCargo"}) do
        assert(type(state[key]) == "number" and state[key] >= 0 and state[key] == math.floor(state[key]), "Invalid saved rotation progress.")
    end
    assert(state.worldIndex >= 1 and state.worldIndex <= #record.config.planting.worlds and state.seedCargo <= 200,
        "Invalid saved rotation farm or seed cargo.")
    for _, key in ipairs({"completed", "readyAt"}) do
        if state[key] ~= nil then
            assert(type(state[key]) == "table", "Invalid saved rotation schedule.")
            for index, value in pairs(state[key]) do
                assert(type(index) == "string" and record.config.rotation.farms[index], "Invalid saved rotation scheduled farm.")
                assert(key == "completed" and type(value) == "boolean"
                    or key == "readyAt" and type(value) == "number" and value == value and value >= 0 and value < math.huge,
                    "Invalid saved rotation schedule value.")
            end
        end
    end
    if state.seedWait ~= nil then assert(type(state.seedWait) == "boolean", "Invalid saved rotation seed wait.") end
    if state.plant then
        readPlantResume({version=1, active=true, userId=record.userId, updatedAt=record.updatedAt,
            config=record.config, profile=record.profile, state=state.plant})
    end
    if state.transfer then
        local t = state.transfer
        assert(type(t) == "table" and ({pickup=true, deliver=true, returnSeeds=true, ["return"]=true,
            pickupPending=true, depositPending=true, seedReturnPending=true})[t.phase]
            and type(t.cargo) == "number" and t.cargo >= 0 and t.cargo <= 200 and t.cargo == math.floor(t.cargo)
            and type(t.seeds) == "number" and t.seeds >= 0 and t.seeds <= 200 and t.seeds == math.floor(t.seeds),
            "Invalid saved rotation transfer.")
    end
    return record
end
local function runRotation(token, saved)
    Core.checkSetup(App.config, "rotation", runtime().items)
    local state = saved and saved.state or {phase="plant", worldIndex=1, cycle=1, work=0, seedCargo=0}
    local settings, p = App.config.planting, App.config.points
    local id, seedId = App.config.blockId, settings.seedId
    if not state.completed then
        state.completed = {}
        -- Older checkpoints processed farms in order.
        if state.phase ~= "plant" then
            for index = 1, state.worldIndex - 1 do state.completed[settings.worlds[index]] = true end
        end
    end
    state.readyAt = state.readyAt or {}
    local failures = 0
    local function transition(phase)
        state.phase = phase
        saveRotationResume(state)
    end
    local function travel(name)
        saveRotationResume(state)
        enterPlantWorld(name, state.plant or {worldIndex=1,phase="farm",skipped={}}, token)
    end
    local function nextFarm()
        local earliest, deadline
        for index, name in ipairs(settings.worlds) do
            if not state.completed[name] then
                local due = state.readyAt[name] or 0
                if not deadline or due < deadline then earliest, deadline = index, due end
            end
        end
        return earliest, deadline
    end
    local function continueFarms()
        local index, deadline = nextFarm()
        if index then
            state.worldIndex = index
            transition(deadline > Workspace:GetServerTimeNow() and "waitPNB" or "wait")
        elseif state.seedWait then transition("waitPNB")
        else transition("finish") end
    end
    local function yieldPNB()
        local _, deadline = nextFarm()
        return deadline and Workspace:GetServerTimeNow() >= deadline
            or state.seedWait and (count(seedId) > 0 or storageCount(p.seedBox, seedId) > 0)
    end
    local function storePNBInventory()
        refreshInventory(token)
        for _, target in ipairs({{p.blockBox, id}, {p.seedBox, seedId}}) do
            if count(target[2]) > 0 then
                local phase = state.phase
                transition("pnbStorePending")
                deposit(target[1], target[2], count(target[2]), token)
                transition(phase)
            end
        end
        clearPNBResume()
    end
    return harvestEquipmentScope(function()
        suspendHarvestVehicle(token)
        saveRotationResume(state)
        queueResume()
        while true do
            checkpoint(token)
            assert(state.phase ~= "seedPickupPending" and state.phase ~= "seedDepositPending" and state.phase ~= "pnbStorePending",
                "A rotation seed storage request was interrupted. Check the backpack and boxes, then clear saved rotation.")
            if state.transfer then assert(state.transfer.phase ~= "pickupPending" and state.transfer.phase ~= "depositPending"
                and state.transfer.phase ~= "seedReturnPending",
                "A rotation transfer storage request was interrupted. Check the backpack and boxes, then clear saved rotation.") end
            local ok, problem = pcall(function()
                local name = settings.worlds[state.worldIndex]
                p.farmBox = App.config.rotation.farms[name]
                if state.phase == "plant" then
                    if not state.plant then state.completed, state.readyAt = {}, {} end
                    state.seedWait = not runPlant(token, state.plant and {state=state.plant} or nil)
                    -- With insufficient stock, harvest the existing partial farms to replenish it.
                    state.plant = nil
                    clearPlantResume()
                    local index, deadline = nextFarm()
                    state.worldIndex = index or 1
                    transition(deadline and deadline > Workspace:GetServerTimeNow() and "waitPNB" or "wait")
                elseif state.phase == "wait" then
                    travel(name)
                    local r = worldCheck(name, token)
                    local growing, crop, remaining = rotationFarmStatus(r, p.farmBox, id, seedId)
                    if crop then
                        state.readyAt[name] = nil
                        transition("harvest")
                    elseif growing > 0 then
                        -- Server-time deadlines survive executor reloads and do not
                        -- require entering the same growing farm every few seconds.
                        state.readyAt[name] = Workspace:GetServerTimeNow() + remaining
                        local index, deadline = nextFarm()
                        state.worldIndex = index
                        if deadline <= Workspace:GetServerTimeNow() then transition("wait")
                        else transition("waitPNB") end
                    else
                        state.completed[name], state.readyAt[name] = true, nil
                        continueFarms()
                    end
                elseif state.phase == "waitPNB" then
                    travel(p.pnb.world)
                    takeControls()
                    local brokenBefore = App.stats.broken
                    local exhausted = runPNB(token, yieldPNB)
                    state.work = state.work + App.stats.broken - brokenBefore
                    storePNBInventory()
                    local index, deadline = nextFarm()
                    if index and deadline <= Workspace:GetServerTimeNow() then
                        state.worldIndex = index
                        transition("wait")
                    elseif state.seedWait and storageCount(p.seedBox, seedId) > 0 then
                        transition("plant")
                    elseif exhausted and not index then
                        state.seedWait = false
                        transition("finish")
                    elseif exhausted then
                        releaseControls()
                        setStatus("Rotation " .. state.cycle .. ": waiting for growing trees; PNB block storage is empty.")
                        saveRotationResume(state)
                        pause(math.min(5, math.max(0.1, deadline - Workspace:GetServerTimeNow())), token)
                    end
                elseif state.phase == "harvest" then
                    travel(name)
                    takeControls()
                    runHarvest(token)
                    state.work = state.work + storageCount(p.farmBox, id, seedId) + storageCount(p.farmBox, seedId, id)
                    transition("transfer")
                elseif state.phase == "transfer" then
                    local t = state.transfer
                    travel(t and t.phase == "deliver" and p.blockBox.world or name)
                    takeControls()
                    runTransfer(token, t, travel)
                    state.transfer = nil
                    transition("seeds")
                elseif state.phase == "seeds" then
                    travel(name)
                    takeControls()
                    assert(storageCount(p.farmBox, id, seedId) == 0, "Farm blocks changed after transfer. Check the Farm box before resuming rotation.")
                    if storageCount(p.farmBox, seedId, id) == 0 then transition("replant")
                    else
                        transition("seedPickupPending")
                        local taken, blocks = withdraw(p.farmBox, seedId, token, id)
                        assert(blocks == 0, "Farm blocks appeared during seed withdrawal. Check the backpack and boxes.")
                        state.seedCargo = taken
                        transition("seedDeliver")
                    end
                elseif state.phase == "seedDeliver" then
                    travel(p.seedBox.world)
                    takeControls()
                    deposit(p.seedBox, seedId, state.seedCargo, token, function(available)
                        assert(available >= state.seedCargo, "Some saved rotation seed cargo is missing. Check inventory.")
                        transition("seedDepositPending")
                    end)
                    state.seedCargo = 0
                    transition("seeds")
                elseif state.phase == "pnb" then
                    -- Legacy checkpoints can still be at the old post-harvest PNB
                    -- phase. Do not drain that storage before replanting the farm.
                    travel(p.pnb.world)
                    takeControls()
                    collectDrops(p.pnb, id, seedId, token)
                    storePNBInventory()
                    transition("replant")
                elseif state.phase == "replant" then
                    local planting = state.plant or {worldIndex=state.worldIndex,phase="farm",skipped={}}
                    state.seedWait = not runPlant(token, {state=planting}, state.worldIndex)
                    state.plant = nil
                    clearPlantResume()
                    state.completed[name], state.readyAt[name] = true, nil
                    continueFarms()
                elseif state.phase == "finish" then
                    assert(state.work > 0, "Rotation found no harvest or stored crop in the farm list. Check seed stock, supported rows, and access.")
                    App.stats.cycles = App.stats.cycles + 1
                    if queueWebhookEvent then queueWebhookEvent("work", "Completed rotation cycle " .. state.cycle .. ".", "rotation") end
                    state.cycle, state.worldIndex, state.work = state.cycle + 1, 1, 0
                    setStatus("Rotation complete. Starting planting cycle " .. state.cycle .. "...")
                    transition("plant")
                    pause(1, token)
                else error("Invalid rotation phase.") end
            end)
            if ok then failures = 0
            else
                checkpoint(token)
                if state.phase == "pnb" or state.phase == "waitPNB" then problem = classifyPNBFault(problem, token) end
                assert(state.phase ~= "seedPickupPending" and state.phase ~= "seedDepositPending" and state.phase ~= "pnbStorePending"
                    and (not state.transfer or state.transfer.phase ~= "pickupPending" and state.transfer.phase ~= "depositPending"
                        and state.transfer.phase ~= "seedReturnPending"),
                    "A rotation storage request was interrupted. Check the backpack and boxes before resuming. " .. tostring(problem))
                assert(App.config.options.autoRejoin and type(problem) == "table" and problem.recoverable, tostring(problem))
                failures = failures + 1
                assert(failures <= 3, "Rotation recovery failed three times. Check connection and copy diagnostics.")
                releaseControls()
                setStatus("Rotation interrupted; returning to the saved phase...")
                if state.phase == "pnb" or state.phase == "waitPNB" then
                    local interruptions = 0
                    while true do
                        local recovered, issue = pcall(recoverPNB, problem, token)
                        if recovered then break end
                        checkpoint(token)
                        interruptions = interruptions + 1
                        assert(interruptions < 3 and type(issue) == "table" and issue.recoverable,
                            "Rotation PNB recovery failed: " .. tostring(issue))
                        problem = issue
                    end
                else travel(state.phase == "seedDeliver" and p.seedBox.world or settings.worlds[state.worldIndex]) end
            end
        end
    end)
end

function App:stop()
    self.token = self.token + 1
    self.teleporting = false
    self.recovering = false
    syncRunToggles()
    releaseControls()
    clearResume()
    clearPNBResume()
    clearPlantResume()
    clearRotationResume()
    pcall(saveSession)
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
    if r.farmingDeferred and (mode == "pnb" or mode == "plant" or mode == "rotation") then
        setStatus("Connecting " .. (mode == "pnb" and "Place & Break" or "Planting") .. " hooks...")
        releaseControls()
        App.configuring = true
        local ok, result = pcall(connectGame)
        App.configuring = false
        if not ok then error(result, 0) end
        r = result
    end
    if mode == "harvest" or mode == "plant" or mode == "rotation" then
        assert(r.body and r.controls and type(r.inventory.room) == "function" and type(r.inventory.add) == "function"
            and type(r.inventory.remove) == "function", "Collection and planting need the live backpack and movement hooks.")
        if mode == "plant" or mode == "rotation" then assert(r.handlers and type(r.handlers.canPlace) == "function" and type(r.handlers.plantSeed) == "function",
            "The seed planting hooks are unavailable. Copy diagnostics from Settings.") end
    else
        assert(r.ready ~= false, "Inventory loaded, but farming hooks are unavailable: " .. table.concat(r.issues or {}, " "))
    end
    if mode == "rotation" then App.config = Core.validate(App.config) end
    Core.checkSetup(App.config, mode, runtime().items)
    if mode ~= "rotation" then clearRotationResume() end
    if mode == "plant" or mode == "rotation" then clearResume() else clearPlantResume() end
    if mode == "harvest" and App.config.options.moveAfterHarvest then Core.checkSetup(App.config, "transfer", r.items) end
    if mode == "pnb" and App.config.options.autoRejoin then savePNBResume(); queueResume()
    else clearPNBResume() end
    saveSession()
    App.token = App.token + 1
    local token = App.token
    App.job = mode
    App.jobToken = token
    App.lastError = nil
    App.teleporting, App.recovering = false, false
    local transferRan = mode == "transfer"
    syncRunToggles()
    task.spawn(function()
        local ok, message = xpcall(function()
            checkpoint(token)
            takeControls()
            if mode == "pnb" then
                while true do
                    local completed, problem = pcall(runPNB, token)
                    if completed then break end
                    checkpoint(token)
                    problem = classifyPNBFault(problem, token)
                    if type(problem) == "table" and problem.recoverable and App.config.options.autoRejoin then
                        local interruptions = 0
                        while true do
                            local recovered, nextProblem = pcall(recoverPNB, problem, token)
                            if recovered then break end
                            checkpoint(token)
                            -- Entry denials and route failures remain terminal. A
                            -- new picker/respawn fault during recovery can retry.
                            if type(nextProblem) ~= "table" or not nextProblem.recoverable then error(nextProblem, 0) end
                            interruptions = interruptions + 1
                            assert(interruptions < 3, "Recovery was interrupted three times. Check the saved world and connection.")
                            problem = nextProblem
                        end
                    else error(problem, 0) end
                end
            elseif mode == "rotation" then
                runRotation(token, saved)
            elseif mode == "plant" then
                local progress = saved
                while true do
                    local completed, problem = pcall(runPlant, token, progress)
                    if completed then break end
                    checkpoint(token)
                    if type(problem) == "table" and problem.recoverable and App.config.options.autoRejoin then
                        progress = {state = App.plantState}
                        assert(progress.state and progress.state.phase ~= "pickupPending", "Seed withdrawal was interrupted. Check the backpack before resuming.")
                        setStatus("Planting interrupted; returning to its saved world...")
                    else error(problem, 0) end
                end
            elseif mode == "harvest" then
                runHarvest(token)
                if App.config.options.moveAfterHarvest then
                    checkpoint(token)
                    App.job = "transfer"
                    transferRan = true
                    syncRunToggles()
                    setStatus("Harvest collection finished. Starting Moving Drops...")
                    harvestEquipmentScope(function() suspendHarvestVehicle(token); runTransfer(token) end)
                end
            else harvestEquipmentScope(function() suspendHarvestVehicle(token); runTransfer(token, saved) end) end
        end, function(err) return tostring(err) end)
        local endedMode = App.job or mode
        releaseControls()
        App.job = nil
        App.jobToken = nil
        App.recovering = false
        syncRunToggles()
        if not ok and token == App.token and App.alive then
            App.lastError = message
            setStatus("Paused: " .. message)
            notify(message)
            if queueWebhookEvent then queueWebhookEvent("failure", message, endedMode) end
        end
        if ok and token == App.token and App.alive and mode ~= "rotation" and queueWebhookEvent then
            queueWebhookEvent("work", App.status, endedMode)
        end
        if transferRan and ok then clearResume() end
        if mode == "pnb" and (ok or not App.teleporting) then clearPNBResume() end
    end)
end

local function setRunningEnabled(mode, enabled)
    if App.syncingRunToggles then return true end
    local starting = enabled and not App.job and not App.configuring and App.pending == 0
    local ok, message = pcall(function()
        if enabled then
            if App.job == mode and App.jobToken == App.token then return end
            start(mode)
        elseif App.job == mode and App.jobToken == App.token then
            App:stop()
        end
    end)
    syncRunToggles()
    if not ok then
        notify(tostring(message))
        if starting and queueWebhookEvent then queueWebhookEvent("failure", "Could not start task: " .. tostring(message), mode) end
    end
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

local function resetWebhookSchedule()
    local state = App.webhookState
    state.generation = state.generation + 1
    state.events = {}
    state.nextAt = os.clock() + App.config.webhook.intervalMinutes * 60
    state.status = App.config.webhook.enabled and "Automatic reports are On." or "Automatic reports are Off."
end
local function setWebhookSetting(key, value)
    assert(App.alive, "Script unloaded.")
    assert(key == "url" or key == "enabled" or key == "intervalMinutes" or key == "includeBoxes"
        or key == "discordId" or key == "failureAlerts", "Unknown webhook setting.")
    local nextSettings = {}
    for name, current in pairs(App.config.webhook) do nextSettings[name] = current end
    nextSettings[key] = value
    App.config.webhook = Core.validateWebhook(nextSettings)
    resetWebhookSchedule()
    if key == "enabled" and value then App.webhookState.nextAt = os.clock() end
end
local function reportText(value, limit)
    return tostring(value):sub(1, limit or 250)
end
local function reportBox(point, itemId)
    if not point then return "Not saved" end
    if not itemId then return "Unavailable (choose a block)" end
    local r = App.runtime
    if not r or r.world.name ~= point.world then
        return "Unavailable (box is in " .. reportText(point.world, 100) .. ")"
    end
    local ok, total = pcall(function() return Core.itemCount(boxRows(point), itemId) end)
    if not ok then return "Unavailable (check the saved Display Box)" end
    return tostring(total) .. " in " .. reportText(point.world, 100) .. " at " .. point.x .. ", " .. point.y
end
local function webhookPayload(config, profile, metrics, event)
    metrics = metrics or {}
    local r, fields = App.runtime, {}
    local function field(name, value, inline)
        table.insert(fields, {name = name, value = reportText(value, 700), inline = inline == true})
    end
    local blockId = config.blockId ~= 0 and config.blockId or nil
    local seedId
    if r and blockId then
        local ok, id = pcall(Core.seedId, r.items, blockId)
        if ok then seedId = id end
    end
    local function backpack(id)
        if not r or not id then return "Unavailable" end
        local ok, total = pcall(function()
            if r.readInventoryView then return Core.itemCount(r.world.backpackNow(), id) end
            return r.inventory:count(id)
        end)
        return ok and tostring(total) or "Unavailable"
    end
    local name = player.Name or tostring(player.UserId)
    field("Player", reportText(player.DisplayName or name, 100) .. " (@" .. reportText(name, 100) .. ")", true)
    field("World", r and r.world.name ~= "" and r.world.name or "World picker / unconnected", true)
    field("Profile", reportText(profile, 48), true)
    field("Level", metrics.level or "Unavailable", true)
    field("Gems", metrics.gems or "Unavailable", true)
    local job = event and event.mode or App.job
    local mode = job == "pnb" and "Place & Break" or job == "transfer" and "Moving Drops"
        or job == "harvest" and "Harvesting" or job == "plant" and "Planting" or job == "rotation" and "Full Rotation"
        or job == "connection" and "Game connection" or job == "resume" and "Resume saved task" or "Off"
    field("Farm status", mode .. (App.recovering and " (recovering)" or "") .. "\n" .. reportText(event and event.message or App.status, 600))
    field("Harvest method", config.harvesting.method == "tractor" and "Dear John Tractor" or "Fist", true)
    if job == "rotation" and App.rotationState then
        local progress = App.rotationState
        field("Rotation progress", "Cycle: " .. progress.cycle .. "\nPhase: " .. progress.phase
            .. "\nFarm: " .. progress.worldIndex .. "/" .. #config.planting.worlds
            .. " (" .. (config.planting.worlds[progress.worldIndex] or "Unavailable") .. ")")
    end
    local item = r and blockId and r.items[blockId]
    field("Selected block", item and (reportText(item.name or blockId, 100) .. " [" .. blockId .. "]") or "Not selected", true)
    field("Backpack", "Blocks: " .. backpack(blockId) .. "\nSeeds: " .. backpack(seedId), true)
    local minutes = math.floor((os.clock() - App.loadedAt) / 60)
    field("This script session", "Time loaded: " .. minutes .. " min\nBlocks broken: " .. App.stats.broken
        .. "\nGems collected: " .. App.stats.gems .. "\nBlocks moved: " .. App.stats.moved .. "\nTrips: " .. App.stats.trips
        .. "\nHarvest blocks collected: " .. App.stats.harvested .. "\nBlocks stashed in Farm storage: " .. App.stats.stashed
        .. "\nSeeds planted: " .. App.stats.planted .. "\nTrees harvested: " .. App.stats.trees
        .. "\nHarvest seeds collected: " .. App.stats.harvestSeeds .. "\nHarvest seeds stored: " .. App.stats.stashedSeeds
        .. "\nRotations completed: " .. App.stats.cycles)
    if job == "plant" or job == "rotation" then
        field("Planting seed", r and r.items[config.planting.seedId] and r.items[config.planting.seedId].name or "Not selected", true)
        field("Planting seeds in backpack", backpack(config.planting.seedId), true)
        if config.webhook.includeBoxes then field("Planting seed Display Box", reportBox(config.points.plantBox, config.planting.seedId), true) end
    end
    if config.webhook.includeBoxes then
        field("Block Display Box", reportBox(config.points.blockBox, blockId), true)
        field("Seed Display Box", reportBox(config.points.seedBox, seedId), true)
        field("Farm Display Box", reportBox(config.points.farmBox, blockId), true)
        field("Farm seeds", reportBox(config.points.farmBox, seedId), true)
    end
    local failure = event and event.kind == "failure"
    if failure then field("Failure", event.message) end
    local payload = { username = "Claris Growblox", allowed_mentions = {parse = {}}, embeds = {{
        title = failure and "Growblox task failed" or event and "Growblox work report" or "Growblox player stats",
        color = failure and 0xE74C3C or 0x65C18C, fields = fields,
        footer = {text = "Claris Growblox v" .. VERSION .. " | " .. os.date("!%Y-%m-%d %H:%M:%S UTC")},
    }} }
    if failure then
        local id = Core.discordUserId(config.webhook.discordId)
        payload.content = (id ~= "" and ("<@" .. id .. "> ") or "") .. "Growblox task failed."
        if id ~= "" then payload.allowed_mentions.users = {id} end
    end
    return payload
end
local function webhookTransport()
    local candidates = {request, http_request, env.request, env.http_request,
        type(syn) == "table" and syn.request or false,
        type(http) == "table" and http.request or false}
    for _, fn in pairs(candidates) do if type(fn) == "function" then return fn end end
end
-- Reporting owns its own requests: a slow Discord connection cannot stop the farm.
-- Keep unsettled requests reserved even after a timeout to prevent overlapping reports.
local function beginWebhookRequest(fn, ...)
    local arguments, state = table.pack(...), App.webhookState
    local result = {done = false}
    state.pending = state.pending + 1
    task.spawn(function()
        result.values = table.pack(pcall(fn, table.unpack(arguments, 1, arguments.n)))
        result.done = true
        state.pending = state.pending - 1
    end)
    return result
end
local function webhookMetrics()
    local r, metrics = App.runtime, {}
    if not r or not r.world.name or r.world.name == "" then return metrics end
    local gems = beginWebhookRequest(r.world.call, "GetGems")
    local level = beginWebhookRequest(r.world.call, "GetLevel")
    local deadline = os.clock() + 8
    while App.alive and not (gems.done and level.done) and os.clock() < deadline
        and not (App.webhookState.events[1] and App.webhookState.events[1].kind == "failure") do task.wait(0.05) end
    local function number(result)
        local values = result.done and result.values
        local value = values and values[1] and values[2]
        if type(value) == "number" and value == value and value >= 0 and value < math.huge then return value end
    end
    metrics.gems, metrics.level = number(gems), number(level)
    return metrics
end
local function discordRetry(response)
    local retry
    for key, value in pairs(type(response.Headers) == "table" and response.Headers or {}) do
        if tostring(key):lower() == "retry-after" then retry = tonumber(value) end
    end
    if type(response.Body) == "string" then
        local ok, body = pcall(decode, response.Body)
        if ok and type(body) == "table" then retry = tonumber(body.retry_after) or retry end
    end
    if not retry or retry ~= retry or retry == math.huge then retry = 60 end
    return math.max(1, math.min(retry, 86400))
end
local function sendWebhook(manual, event)
    local state, now = App.webhookState, os.clock()
    event = event or state.events[1]
    if not App.alive then return false, "Script unloaded." end
    if state.inFlight or (event and state.httpPending or state.pending) > 0 then
        return false, "Waiting for the previous report request to finish."
    end
    if now < (state.retryAt or 0) then return false, "Discord requested a cooldown. Try again later." end
    if state.lastAttempt and now - state.lastAttempt < 5 then return false, "Wait five seconds between reports." end
    if event and now < (event.retryAt or 0) then return false, "Waiting to retry the queued report." end
    local valid, settings = pcall(Core.validateWebhook, App.config.webhook)
    if not valid then return false, tostring(settings) end
    if settings.url == "" then return false, "Set the Discord webhook URL first." end
    if event then
        if event.kind == "failure" and not settings.failureAlerts or event.kind == "work" and not settings.enabled then
            return false, "This report type is switched Off."
        end
    elseif not manual and not settings.enabled then return false, "Automatic reports are Off." end
    local transport = webhookTransport()
    if not transport then
        state.status = "Delta HTTP request function is unavailable."
        state.nextAt = now + settings.intervalMinutes * 60
        return false, state.status
    end
    local generation, config, profile = state.generation, App.config, App.profile
    if event then event.attempts, event.rateLimited = (event.attempts or 0) + 1, false end
    state.inFlight, state.lastAttempt = true, now
    state.nextAt, state.status = now + settings.intervalMinutes * 60,
        event and (event.kind == "failure" and "Sending failure alert..." or "Sending work report...") or "Sending player stats..."
    task.spawn(function()
        local ok, message = pcall(function()
            local metrics = event and {} or webhookMetrics()
            if not App.alive or state.generation ~= generation then return end
            if not event and state.events[1] and state.events[1].kind == "failure" then
                state.lastAttempt = nil -- No HTTP post was made; let the failure alert proceed.
                return
            end
            local payload = event and event.payload or webhookPayload(config, profile, metrics)
            state.httpPending = state.httpPending + 1
            local response = beginWebhookRequest(function(options)
                local received, result = pcall(transport, options)
                state.httpPending = state.httpPending - 1
                assert(received, tostring(result))
                if event and App.alive and state.generation == generation and type(result) == "table" then
                    local status = tonumber(result.StatusCode or result.Status)
                    if status and status >= 200 and status < 300 and result.Success ~= false then
                        -- A late successful HTTP reply also acknowledges the event.
                        -- Its next poll must not post the same failure a second time.
                        event.delivered = true
                    elseif status == 429 then
                        state.retryAt = os.clock() + discordRetry(result)
                        event.rateLimited, event.retryAt = true, nil
                        event.attempts = event.attempts - 1
                    end
                end
                return result
            end, {
                Url = settings.url .. "?wait=true", Method = "POST",
                Headers = {["Content-Type"] = "application/json"}, Body = encode(payload),
            })
            local deadline = os.clock() + 15
            while App.alive and not response.done and os.clock() < deadline do task.wait(0.05) end
            if not App.alive or state.generation ~= generation then return end
            assert(response.done, "Discord request timed out; waiting for it to settle before sending again.")
            -- Executor exceptions/response bodies can contain the URL's secret token.
            assert(response.values[1], "Discord request failed. Check your connection and webhook URL.")
            local result = response.values[2]
            assert(type(result) == "table", "Invalid response from the executor HTTP function.")
            local status = tonumber(result.StatusCode or result.Status)
            if status == 429 then
                local seconds = discordRetry(result)
                state.retryAt = os.clock() + seconds
                error("Discord rate limit: retry after " .. math.ceil(seconds) .. " seconds.", 0)
            end
            assert(status and status >= 200 and status < 300 and result.Success ~= false,
                "Discord rejected the report (HTTP " .. tostring(status or "unknown") .. "). Check your webhook URL.")
            state.lastSent, state.status = os.date("%H:%M:%S"),
                event and (event.kind == "failure" and "Failure alert sent." or "Work report sent.") or "Report sent."
        end)
        state.inFlight = false
        if App.alive and state.generation == generation then
            if not ok then state.status = tostring(message) end
            if event and (event.delivered or event.attempts >= 3 and not event.rateLimited) then
                for index, queued in ipairs(state.events) do
                    if queued == event then table.remove(state.events, index); break end
                end
                if not event.delivered then state.status = "Queued report failed after three attempts: " .. tostring(message) end
            elseif event and not ok and not event.rateLimited then
                event.retryAt = os.clock() + math.max(5, event.attempts * 10)
            end
        end
    end)
    return true
end
queueWebhookEvent = function(kind, message, mode)
    if not App.alive then return false end
    local valid, config = pcall(Core.validate, App.config)
    if not valid or config.webhook.url == "" then return false end
    if kind == "failure" then
        if not config.webhook.failureAlerts then return false end
    elseif kind == "work" then
        if not config.webhook.enabled then return false end
    else return false end
    local event = {kind = kind, message = tostring(message), mode = mode, attempts = 0}
    local built, payload = pcall(webhookPayload, config, App.profile, {}, event)
    if not built then return false end
    event.payload = payload
    local state = App.webhookState
    if #state.events >= 10 then table.remove(state.events, #state.events) end
    if kind == "failure" then table.insert(state.events, 1, event) else table.insert(state.events, event) end
    state.status = kind == "failure" and "Failure alert queued." or "Work report queued."
    return true
end
local function pollWebhook()
    local state = App.webhookState
    if not App.alive or App.configuring then return end
    for index = #state.events, 1, -1 do
        if state.events[index].delivered then
            state.lastSent, state.status = os.date("%H:%M:%S"), "Queued report sent after its delayed reply."
            table.remove(state.events, index)
        end
    end
    if state.events[1] then sendWebhook(false, state.events[1])
    elseif App.config.webhook.enabled and App.runtime and os.clock() >= (state.nextAt or 0) then
        sendWebhook(false)
    end
end

local function seedChoices(query)
    local r = runtime()
    local scan, candidates, seen, relevant = newScan(), {}, {}, {}
    query = (query or ""):match("^%s*(.-)%s*$"):lower()
    local selectedId, selected = App.config.planting.seedId, nil
    for _, slot in pairs(r.inventory.slots) do relevant[slot.id] = true end
    local box = App.config.points.plantBox
    if box and box.world == r.world.name then
        local ok, rows = pcall(boxRows, box)
        if ok then for _, row in pairs(rows) do relevant[row[1]] = true end end
    end
    if App.config.blockId > 0 then
        local ok, id = pcall(Core.seedId, r.items, App.config.blockId)
        if ok then relevant[id] = true end
    end
    local function consider(id)
        if seen[id] or type(id) ~= "number" then return end
        seen[id] = true
        local item = r.items[id]
        if type(item) ~= "table" or item.kind ~= "seed" then return end
        local name = item.name or ("Seed " .. id)
        if id == selectedId or query == "" or name:lower():find(query, 1, true) or tostring(id) == query then
            local label = name .. " [" .. id .. "]"
            table.insert(candidates, {id = id, label = label, rank = id == selectedId and 0 or relevant[id] and 1 or 2})
            if id == selectedId then selected = label end
        end
    end
    consider(selectedId)
    for id in pairs(relevant) do consider(id) end
    if query ~= "" then
        for id in pairs(r.items) do
            scanStep(scan, "Finding seed choices")
            consider(id)
        end
    end
    table.sort(candidates, function(a, b) return a.rank < b.rank or a.rank == b.rank and a.label < b.label end)
    local labels, lookup = {}, {}
    for index = 1, math.min(40, #candidates) do
        local choice = candidates[index]
        labels[index], lookup[choice.label] = choice.label, choice.id
    end
    table.sort(labels)
    App.seedChoiceCount, App.seedChoiceMatches = #labels, #candidates
    App.startupStage = "Ready"
    return labels, lookup, selected, #candidates > #labels
end

local function exportConfiguration()
    local record = Core.exportConfig(App.config, App.profile, VERSION)
    return encode(record), record
end
local function saveConfigExport(record)
    filesystem()
    local directory = ROOT .. "/exports"
    if not isfolder(directory) then makefolder(directory) end
    local path = directory .. "/" .. Core.profileName(record.profile) .. ".json"
    writeJSON(path, record)
    return path
end
local function importConfiguration(text, name)
    assert(App.alive and not App.job and App.pending == 0,
        "Stop the current task and wait for pending requests before importing a configuration.")
    assert(type(text) == "string" and text:match("%S"), "Paste the exported configuration first.")
    assert(#text <= 131072, "Configuration text is too large. Paste only the exported JSON.")
    local decoded, record = pcall(decode, text)
    assert(decoded and type(record) == "table", "Invalid configuration JSON. Copy the complete export and paste it again.")
    local config, profile = Core.importConfig(record, name)
    local path = PROFILE_DIR .. "/" .. profile .. ".json"
    local prior = {[path] = exists(path) and readfile(path) or false,
        [SESSION_FILE] = exists(SESSION_FILE) and readfile(SESSION_FILE) or false}
    local session = {version = 1, userId = player.UserId, config = config, profile = profile}
    local signature = encode({config = config, profile = profile})
    local saved, problem = pcall(function()
        writeJSON(path, config)
        writeJSON(SESSION_FILE, session)
    end)
    if not saved then
        for target, previous in pairs(prior) do
            pcall(function()
                if previous then writefile(target, previous)
                elseif exists(target) and type(delfile) == "function" then delfile(target) end
            end)
        end
        error("Could not save the imported configuration: " .. tostring(problem), 0)
    end
    -- Import settings only. Old local cargo and progress must not resume under this setup.
    clearResume()
    clearPNBResume()
    clearPlantResume()
    clearRotationResume()
    App.config, App.profile = config, profile
    App.sessionSignature, App.sessionSaveError, App.sessionRestoreError = signature, nil, nil
    resetWebhookSchedule()
    setStatus("Imported and saved profile: " .. profile .. ". Check locations, then start your task.")
    return profile
end

local sessionOK, sessionProblem = pcall(restoreSession, previousSession)
App.sessionRestoreError = not sessionOK and tostring(sessionProblem) or nil
previousSession = nil

if env.ClarisGrowbloxTest then
    return { App = App, Core = Core, start = start, checkpoint = checkpoint,
        runTransfer = runTransfer, runPNB = runPNB, refreshInventory = refreshInventory,
        withdraw = withdraw, deposit = deposit, releaseControls = releaseControls,
        takeControls = takeControls, collectDrops = collectDrops, enterDoor = enterDoor,
        settleTile = settleTile, placeTile = placeTile, breakTile = breakTile, resolveRegistry = resolveRegistry,
        discover = discover, connectGame = connectGame, runtime = runtime, resolveItems = resolveItems,
        syncRunToggles = syncRunToggles, setRunningEnabled = setRunningEnabled,
        Navigation = Navigation, navigationMap = navigationMap, moveTo = moveTo, worldCheck = worldCheck,
        recoverPNB = recoverPNB, recoverable = recoverable, installAntiAFK = installAntiAFK,
        savePNBResume = savePNBResume, readPNBResume = readPNBResume, refreshPNBCheckpoint = refreshPNBCheckpoint,
        webhookPayload = webhookPayload, setWebhookSetting = setWebhookSetting,
        resetWebhookSchedule = resetWebhookSchedule, sendWebhook = sendWebhook, pollWebhook = pollWebhook,
        queueWebhookEvent = queueWebhookEvent,
        findWorldPicker = findWorldPicker, findRespawn = findRespawn, pickerOpen = pickerOpen, runHarvest = runHarvest,
        runTreeHarvest = runTreeHarvest, treeGrowthHooks = treeGrowthHooks,
        runRotation = runRotation, readRotationResume = readRotationResume, saveRotationResume = saveRotationResume,
        clearRotationResume = clearRotationResume,
        exportConfiguration = exportConfiguration, saveConfigExport = saveConfigExport, importConfiguration = importConfiguration,
        saveSession = saveSession, restoreSession = restoreSession, pollSession = pollSession,
        runPlant = runPlant, plantTile = plantTile, enterPlantWorld = enterPlantWorld,
        readPlantResume = readPlantResume, savePlantResume = savePlantResume, clearPlantResume = clearPlantResume,
        reconcilePlant = reconcilePlant, seedChoices = seedChoices }
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
local harvestTab = window:Tab({ Title = "Harvest Drops", Icon = "package" })
local plantTab = window:Tab({ Title = "Planting", Icon = "sprout" })
local transferTab = window:Tab({ Title = "Moving Drops", Icon = "truck" })
local rotationTab = window:Tab({ Title = "Full Rotation", Icon = "repeat" })
local profileTab = window:Tab({ Title = "Configurations", Icon = "save" })
local webhookTab = window:Tab({ Title = "Discord Webhook", Icon = "bell" })
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
    paragraphSet(ui.harvestPoint, "Farm storage", pointText("farmBox"))
    paragraphSet(ui.plantPoint, "Planting seed storage", pointText("plantBox"))
end
local function uiAction(fn)
    return function()
        task.spawn(function()
            local ok, message = pcall(idle)
            if not ok then notify(tostring(message)); return end
            App.configuring = true
            ok, message = xpcall(fn, function(err) return tostring(err) end)
            App.configuring = false
            if ok then ok, message = pcall(saveSession) end
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
    if key == "farmBox" then App.config.rotation.farms[r.world.name] = App.config.points[key] end
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
    blockDropdown.Value = selectedLabel
    blockDropdown:Refresh(labels)
end
ui.points, ui.pointTitles = {}, {
    pnb = "PNB spot", blockBox = "Block storage (breaking world)", seedBox = "Seed storage (left box)",
    farmBox = "Farm storage", farmDoor = "Farm door to breaking world", breakDoor = "Breaking door to farm world",
    plantBox = "Planting seed storage",
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
transferTab:Paragraph({ Title = "Moving Drops setup", Desc = "Use Harvest Drops to store blocks and matching seeds in Farm storage. Moving Drops carries blocks while holding up to 200 seeds, then returns seeds to the same box. Save both boxes and both linked doors. Start in the farm world." })
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
ui.harvestStatus = harvestTab:Paragraph({ Title = "Status", Desc = App.status })
harvestTab:Paragraph({ Title = "Harvest trees, blocks, and seeds", Desc = "Break ripe trees of the block selected on Place & Break, then collect matching blocks and seeds into the same Farm Display Box. Follow top-down zigzag rows and skip rows without work. Growing trees stay planted." })
settingsControls.harvestMethod = harvestTab:Dropdown({ Title = "Harvest method", Values = {"Fist", "Dear John Tractor"},
    Value = App.config.harvesting.method == "tractor" and "Dear John Tractor" or "Fist",
    Callback = function(value)
        if App.syncingUI then return end
        local method = value == "Fist" and "fist" or value == "Dear John Tractor" and "tractor"
        if not method then return end
        if App.job or App.configuring or App.pending > 0 then
            notify("Stop the task before changing the harvest method.")
            App.syncingUI = true
            settingsControls.harvestMethod:Select(App.config.harvesting.method == "tractor" and "Dear John Tractor" or "Fist")
            App.syncingUI = false
            return
        end
        App.config.harvesting.method = method
        pcall(saveSession)
    end })
harvestTab:Paragraph({ Title = "Dear John Tractor", Desc = "Keep the tractor in your backpack. It is equipped for tree rows and removed during travel and collection; previous footwear is restored afterward. Use Fist for farms containing different seed types." })
ui.harvestPoint = harvestTab:Paragraph({ Title = "Farm storage", Desc = pointText("farmBox") })
harvestTab:Button({ Title = "Save Farm storage", Desc = "Stand beside the farm world's Display Box.",
    Callback = uiAction(function() captureNearby("farmBox", "box") end) })
settingsControls.moveAfterHarvest = harvestTab:Toggle({ Title = "Start Moving Drops after collection", Value = App.config.options.moveAfterHarvest,
    Desc = "Finish collecting every selected block, then begin the configured door transfer. Save both doors and destination storage first.",
    Callback = function(value)
        if App.syncingUI then return end
        if App.job or App.configuring or App.pending > 0 then
            notify("Stop the task before changing automatic transfer.")
            App.syncingUI = true
            settingsControls.moveAfterHarvest:Set(App.config.options.moveAfterHarvest, false, false)
            App.syncingUI = false
            return
        end
        App.config.options.moveAfterHarvest = value
    end })
settingsControls.harvestRespawn = harvestTab:Toggle({ Title = "Respawn to Farm storage", Value = App.config.options.harvestRespawn,
    Desc = "Respawn before storing a backpack of blocks. Use when your respawn door is near Farm storage.",
    Callback = function(value)
        if App.syncingUI then return end
        if App.job or App.configuring or App.pending > 0 then
            notify("Stop the task before changing the storage return route.")
            App.syncingUI = true
            settingsControls.harvestRespawn:Set(App.config.options.harvestRespawn, false, false)
            App.syncingUI = false
            return
        end
        App.config.options.harvestRespawn = value
    end })
App.runToggles.harvest = harvestTab:Toggle({ Title = "Collect harvest", Value = false,
    Desc = "On harvests ripe trees, then collects and stores blocks. Off stops. Turns Off when finished or on a problem.",
    Callback = function(enabled) setRunningEnabled("harvest", enabled) end })
local plantControls, seedLabels = {}, {}
local seedSearch, seedSearchGeneration = "", 0
local function refreshSeeds(syncInputs)
    if not App.runtime then return end
    local labels, lookup, selected, more = seedChoices(seedSearch)
    App.syncingPlantUI = true
    seedLabels = lookup
    plantControls.seed.Value = selected
    plantControls.seed:Refresh(labels)
    if syncInputs ~= false then
        plantControls.storageWorld:Set(App.config.planting.storageWorld)
        plantControls.worlds:Set(table.concat(App.config.planting.worlds, ", "))
    end
    paragraphSet(ui.seedChoices, "Seed choices", more and "Showing up to 40 choices. Narrow the search to find another seed."
        or "Showing backpack seeds, the selected seed, and seeds in your saved box. Search by name or exact ID for other seeds.")
    App.syncingPlantUI = false
end
local function changePlantSetting(key, value)
    if App.syncingPlantUI or App.syncingUI then return end
    local ok, message = pcall(function()
        idle()
        if key == "seedId" then value = assert(seedLabels[value], "Choose a seed.")
        elseif key == "worlds" then value = Core.parseWorlds(value)
        elseif value ~= "" then value = Core.worldName(value) end
        local candidate = Core.validate(App.config)
        candidate.planting[key] = value
        App.config.planting = Core.validatePlanting(candidate.planting)
        saveSession()
    end)
    if not ok then notify(tostring(message)) end
end
ui.plantStatus = plantTab:Paragraph({ Title = "Status", Desc = App.status })
plantTab:Paragraph({ Title = "Fill dirt farms with seeds", Desc = "Start at the top-left supported farm row and alternate left-to-right and right-to-left down the farm. Skip occupied, floating, and denied tiles. Refill from the saved seed Display Box and resume the same row direction, then continue through your farm world list." })
App.syncingPlantUI = true
plantControls.search = plantTab:Input({ Title = "Find seed by name or ID", Value = "", Placeholder = "e.g. Sugar Cane or 955",
    Callback = function(value)
        if App.syncingPlantUI or App.syncingUI then return end
        seedSearch, seedSearchGeneration = tostring(value or ""), seedSearchGeneration + 1
        local generation = seedSearchGeneration
        task.spawn(function()
            task.wait(0.25)
            if not App.alive or generation ~= seedSearchGeneration then return end
            local ok, issue = pcall(refreshSeeds, false)
            if not ok and App.alive then notify(tostring(issue)) end
        end)
    end })
ui.seedChoices = plantTab:Paragraph({ Title = "Seed choices", Desc = "Backpack and saved seed choices load after connecting. Search to find other seeds." })
plantControls.seed = plantTab:Dropdown({ Title = "Seed to plant", Values = {}, SearchBarEnabled = true,
    Callback = function(value) changePlantSetting("seedId", value) end })
plantControls.storageWorld = plantTab:Input({ Title = "Seed storage world", Value = App.config.planting.storageWorld,
    Placeholder = "e.g. ZZ4", Callback = function(value) changePlantSetting("storageWorld", value) end })
plantControls.worlds = plantTab:Input({ Title = "Dirt farm worlds (in order)", Value = table.concat(App.config.planting.worlds, ", "),
    Placeholder = "FARM1, FARM2, FARM3", Callback = function(value) changePlantSetting("worlds", value) end })
ui.plantPoint = plantTab:Paragraph({ Title = "Planting seed storage", Desc = pointText("plantBox") })
plantTab:Button({ Title = "Save seed Display Box", Desc = "Stand beside the seed box in the storage world. A dedicated box also selects its seed type.",
    Callback = uiAction(function()
        captureNearby("plantBox", "box")
        App.config.planting.storageWorld = Core.worldName(runtime().world.name)
        local rows, seed = boxRows(App.config.points.plantBox), nil
        for _, row in pairs(rows) do
            assert(runtime().items[row[1]] and runtime().items[row[1]].kind == "seed", "Use a Display Box containing seeds only.")
            assert(not seed or seed == row[1], "Use a Display Box dedicated to one seed type.")
            seed = row[1]
        end
        if seed then App.config.planting.seedId = seed end
        refreshSeeds()
    end) })
plantTab:Button({ Title = "Refresh seed choices", Callback = uiAction(refreshSeeds) })
App.runToggles.plant = plantTab:Toggle({ Title = "Plant seeds", Value = false,
    Desc = "On plants and refills automatically. Off stops. Unreachable or denied tiles are reported and skipped.",
    Callback = function(enabled) setRunningEnabled("plant", enabled) end })
App.syncingPlantUI = false
local webhookControls = {}
local function syncWebhookControls()
    App.syncingWebhookUI = true
    for key, control in pairs(webhookControls) do
        local value = App.config.webhook[key]
        control:Set(key == "intervalMinutes" and tostring(value) or value)
    end
    App.syncingWebhookUI = false
end
local function syncUI()
    local previous = App.syncingUI
    App.syncingUI = true
    local ok, issue = pcall(function()
        for key, control in pairs(settingsControls) do
            if key == "harvestMethod" then
                control:Select(App.config.harvesting.method == "tractor" and "Dear John Tractor" or "Fist")
            else control:Set(App.config.options[key]) end
        end
        profileNameInput:Set(App.profile)
        if App.runtime then refreshBlocks() end
        refreshSeeds()
        updatePoints()
        resetWebhookSchedule()
        syncWebhookControls()
    end)
    App.syncingUI = previous
    if not ok then error(issue, 0) end
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
    profileDropdown.Value = selectedProfile
    profileDropdown:Refresh(names)
    return names
end
profileTab:Paragraph({ Title = "Named configurations", Desc = "Each profile saves the chosen block, saved locations, timing settings, and Discord webhook settings. Give each farm setup its own name. Files stay in Delta's ClarisGrowblox/profiles folder." })
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

do
    profileTab:Paragraph({ Title = "Transfer a configuration", Desc = "Copy your setup from an emulator to a cloud phone or another account. Includes saved places, all farm boxes, the world list, harvesting method, timing, and webhook settings. Import saves a local profile and keeps farming Off. Check each account's locations and world access before starting." })
    local configText = profileTab:Input({ Title = "Configuration text", Type = "Textarea", Value = "",
        Placeholder = "Export on the source device, then paste the full JSON here on the destination.",
        ClearTextOnFocus = false, Callback = function() end })
    local importName = profileTab:Input({ Title = "Import as profile (optional)", Value = "",
        Placeholder = "Blank keeps the exported profile name", ClearTextOnFocus = false, Callback = function() end })
    local filePath = profileTab:Input({ Title = "Configuration file path", Value = ROOT .. "/exports/" .. App.profile .. ".json",
        Desc = "For a copied export file instead of pasted text.", ClearTextOnFocus = false, Callback = function() end })
    profileTab:Button({ Title = "Export config", Desc = "Show export text, copy it to the clipboard, and save an export file when available.",
        Callback = function()
            task.spawn(function()
                local ok, problem = pcall(function()
                    local text, record = exportConfiguration()
                    configText:Set(text)
                    local copy = setclipboard or toclipboard
                    local copied = type(copy) == "function" and pcall(copy, text)
                    local saved, path = pcall(saveConfigExport, record)
                    if saved then filePath:Set(path) end
                    setStatus("Exported " .. record.profile .. (copied and "; copied to clipboard." or "; copy the Configuration text field.")
                        .. (saved and (" File: " .. path) or " Export file unavailable; use the text."))
                    notify(copied and "Configuration copied. Paste it on your other device." or "Export ready in Configuration text. Copy it to your other device.")
                end)
                if not ok then setStatus(tostring(problem)); notify(tostring(problem)) end
            end)
        end })
    local function importText(text)
        local name = importConfiguration(text, importName.Value)
        selectedProfile = name
        syncUI()
        local listed, issue = pcall(listProfiles)
        if not listed then notify("Profile imported and saved; profile list refresh failed: " .. tostring(issue)) end
    end
    profileTab:Button({ Title = "Import config", Desc = "Stop your task, paste Configuration text, then import. An existing profile with the same name is backed up.",
        Callback = uiAction(function() importText(configText.Value) end) })
    profileTab:Button({ Title = "Import config file", Desc = "Read the copied JSON file at Configuration file path and save its setup here.",
        Callback = uiAction(function()
            local path = filePath.Value
            assert(type(path) == "string" and path:match("%S") and #path <= 512, "Enter the copied configuration file path.")
            assert(exists(path), "Configuration file was not found. Copy it to this device or paste the export text.")
            local text = readfile(path)
            importText(text)
            configText:Set(text)
        end) })
end

rotationTab:Paragraph({ Title = "Plant, harvest, break, repeat", Desc = "Use the full Planting farm list. Fill empty planting rows, then break PNB stock while trees grow. When a farm is ready, finish the current block and pickups, harvest, transport its blocks/seeds, and replant before returning to PNB. Full farms skip planting. Rotation saves progress and enters worlds directly; it does not need linked doors." })
ui.rotationFarms = rotationTab:Paragraph({ Title = "Farm storage saved per world", Desc = "Visit every listed farm, stand beside its Display Box, and save it here. Harvest Drops and Moving Drops save buttons also remember each world." })
rotationTab:Button({ Title = "Save this farm's harvest box", Desc = "Stand beside a Display Box in a world from your Planting list.", Callback = uiAction(function() captureNearby("farmBox", "box") end) })
rotationTab:Button({ Title = "Use PNB seeds for planting", Desc = "Use the saved left PNB Display Box for planting stock and select the matching seed.", Callback = uiAction(function()
    local box = App.config.points.seedBox
    assert(box, "Save PNB seed storage first.")
    App.config.points.plantBox = {world=box.world, x=box.x, y=box.y, standX=box.standX, standY=box.standY}
    App.config.planting.storageWorld = box.world
    App.config.planting.seedId = Core.seedId(runtime().items, App.config.blockId)
    syncUI()
    setStatus("Rotation planting stock now uses the PNB seed box.")
end) })
ui.rotationStatus = rotationTab:Paragraph({ Title = "Status", Desc = App.status })
App.runToggles.rotation = rotationTab:Toggle({ Title = "Continuous full rotation", Value = false,
    Desc = "Planting and ready harvests take priority; run PNB while farms grow. Choose your harvesting method on Harvest Drops.",
    Callback = function(enabled) setRunningEnabled("rotation", enabled) end })
local function resumeRotation()
    idle()
    local saved = readRotationResume()
    assert(saved, "No saved rotation is available.")
    App.config, App.profile = saved.config, saved.profile
    syncUI()
    start("rotation", saved)
end
rotationTab:Button({ Title = "Resume saved rotation", Callback = function()
    local ok, message = pcall(resumeRotation); if not ok then notify(tostring(message)) end
end })
rotationTab:Button({ Title = "Clear saved rotation", Desc = "Check inventory and storage first if a storage request was interrupted. Items stay where they are.", Callback = uiAction(function()
    clearRotationResume(); clearPlantResume(); clearResume(); clearPNBResume()
    setStatus("Cleared saved rotation.")
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
    assert(saved.phase ~= "depositPending" and saved.phase ~= "pickupPending" and saved.phase ~= "seedReturnPending",
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
local function resumePlant()
    idle()
    local saved = readPlantResume()
    assert(saved, "No saved planting task is available.")
    assert(saved.state.phase ~= "pickupPending", "A seed withdrawal was interrupted. Check the backpack and storage, then clear saved planting.")
    App.config, App.profile = saved.config, saved.profile
    syncUI()
    start("plant", saved)
end
plantTab:Button({ Title = "Resume planting", Desc = "Restore the seed, world list, and progress after a server change or interruption.",
    Callback = function() local ok, message = pcall(resumePlant); if not ok then notify(tostring(message)) end end })
plantTab:Button({ Title = "Clear saved planting", Desc = "Use after checking an interrupted storage withdrawal or seed placement.",
    Callback = uiAction(function() clearPlantResume(); setStatus("Cleared saved planting.") end) })
profileTab:Button({ Title = "Clear saved transfer", Desc = "Use after checking an interrupted storage request. Items stay where they are.", Callback = uiAction(function()
    clearResume()
    setStatus("Cleared saved transfer.")
end) })

webhookTab:Paragraph({ Title = "Discord work reports", Desc = "Report task status, rotation farm/phase/cycle, trees harvested, blocks and seeds collected, PNB work, and backpack/storage counts. Timed reports also include player level and gems. Failure alerts can ping your Discord account. Save the profile to keep these settings." })
local function webhookChanged(key)
    return function(value)
        if App.syncingWebhookUI or App.syncingUI then return end
        if key == "intervalMinutes" then value = tonumber(value) end
        local ok, message = pcall(setWebhookSetting, key, value)
        if not ok then notify(tostring(message)) end
        syncWebhookControls()
    end
end
App.syncingWebhookUI = true
webhookControls.url = webhookTab:Input({ Title = "Discord webhook URL", Value = App.config.webhook.url,
    Placeholder = "https://discord.com/api/webhooks/...", Callback = webhookChanged("url") })
webhookControls.discordId = webhookTab:Input({ Title = "Discord user ID to ping on failure", Value = App.config.webhook.discordId,
    Desc = "Enable Discord Developer Mode, then Copy User ID. Leave blank for an alert without a ping.",
    Placeholder = "17-20 digit user ID", ClearTextOnFocus = false, Callback = webhookChanged("discordId") })
webhookControls.failureAlerts = webhookTab:Toggle({ Title = "Failure alerts", Value = App.config.webhook.failureAlerts,
    Desc = "Send an alert when a task pauses with an error, including when timed reports are Off. Only failures ping the saved Discord ID.",
    Callback = webhookChanged("failureAlerts") })
webhookControls.intervalMinutes = webhookTab:Input({ Title = "Send every (minutes)", Value = tostring(App.config.webhook.intervalMinutes),
    Desc = "Enter 1-1440 minutes, for example 1, 5, or 30.", Placeholder = "5", Callback = webhookChanged("intervalMinutes") })
webhookControls.includeBoxes = webhookTab:Toggle({ Title = "Include Display Box counts", Value = App.config.webhook.includeBoxes,
    Desc = "Count selected blocks/seeds in saved boxes. Boxes in another world show as unavailable.", Callback = webhookChanged("includeBoxes") })
webhookControls.enabled = webhookTab:Toggle({ Title = "Automatic webhook reports", Value = App.config.webhook.enabled,
    Desc = "Send timed progress reports, completed-task reports, and completed rotation cycles. Failure alerts use their own toggle.", Callback = webhookChanged("enabled") })
App.syncingWebhookUI = false
webhookTab:Button({ Title = "Send stats now", Callback = function()
    local ok, message = sendWebhook(true)
    if not ok then notify(message) end
end })
ui.webhookStatus = webhookTab:Paragraph({ Title = "Webhook status", Desc = App.webhookState.status })

settingsTab:Paragraph({ Title = "Settings", Desc = "These settings are saved separately in each named configuration." })
for _, info in ipairs({
    {"antiAFK", "Anti-AFK", "Keep the session active when Roblox detects idle time."},
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
            if key == "antiAFK" and value then installAntiAFK() end
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
    App.runtime = connectGame({transferOnly = true})
    App.syncingUI = true
    refreshBlocks()
    refreshSeeds()
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
        .. "\nLoader: " .. (env.ClarisGrowbloxLoaderDebug or "direct script")
        .. "\nLast door: " .. (App.doorReadyDebug or "not used")
        .. "\nAnti-AFK: " .. (App.antiAFKError or "ready")
        .. "\nNavigation: " .. (App.navigationDebug or "no route requested")
        .. "\nLast refused harvest pickup: " .. (App.lastHarvestRefusal or "none")
        .. "\nHarvest storage return: " .. (App.harvestReturnDebug or "not requested")
        .. "\nRotation phase: " .. (App.rotationState and (App.rotationState.phase .. "; cycle " .. App.rotationState.cycle
            .. "; farm " .. App.rotationState.worldIndex .. "/" .. #App.config.planting.worlds) or "idle")
        .. "\nHarvest method: " .. App.config.harvesting.method .. "; phase: " .. (App.harvestPhase or "not started")
        .. "\nTrees harvested: " .. App.stats.trees .. "; equipment restore: " .. (App.harvestGearError or "ready")
        .. "\nRecovery save: " .. (App.recoverySaveError or "ready")
        .. "\nSession save: " .. (App.sessionSaveError or "ready")
        .. "\nSession restore: " .. (App.sessionRestoreError or "ready")
        .. "\nPlanting hook: " .. (App.runtime and App.runtime.handlers.plantSeed and "ready" or "unavailable")
        .. "\nStartup stage: " .. (App.startupStage or "Building interface")
        .. "\nSeed choices rendered: " .. (App.seedChoiceCount or 0)
        .. "\nWebhook: " .. App.webhookState.status .. "\nWebhook pending requests: " .. App.webhookState.pending
        .. "\nWorld picker: " .. (App.runtime and App.runtime.picker and (pickerOpen(App.runtime) and "visible" or "hidden") or "UI hook unavailable")
        .. "\nRecent world selection: " .. (App.recentWorldDebug or "not requested")
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
        if App.sessionRestoreError then notify(App.sessionRestoreError) end
        local rotationOK, rotation = pcall(readRotationResume)
        if rotationOK and rotation then setStatus("Saved rotation found. Use Resume saved rotation on Full Rotation.")
        elseif not rotationOK then notify(tostring(rotation)) end
        local plantingOK, planting = pcall(readPlantResume)
        if plantingOK and planting then setStatus("Saved planting found. Use Resume planting on Planting.")
        elseif not plantingOK then notify(tostring(planting)) end
        local farmOK, farm = pcall(readPNBResume)
        if farmOK and farm then setStatus("Saved farm found. Use Resume saved farm from Configurations.")
        elseif not farmOK then notify(tostring(farm)) end
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
        queueWebhookEvent("failure", "Could not connect the script: " .. tostring(message), "connection")
    elseif env.ClarisGrowbloxAutoResume then
        env.ClarisGrowbloxAutoResume = nil
        local resumed, problem = pcall(function()
            if readRotationResume() then resumeRotation()
            elseif readPlantResume() then resumePlant()
            elseif readPNBResume() then resumeFarm()
            elseif App.resume then resumeTransfer() end
        end)
        if not resumed then
            setStatus(tostring(problem)); notify(tostring(problem))
            queueWebhookEvent("failure", "Could not resume the saved task: " .. tostring(problem), "resume")
        end
    end
end)
task.spawn(function()
    while App.alive do
        syncRunToggles()
        refreshPNBCheckpoint()
        if App.job == "rotation" and App.jobToken == App.token and App.rotationState and App.pending == 0
            and os.clock() - (App.lastRotationSave or -math.huge) >= 120 then
            local ok, issue = pcall(saveRotationResume, App.rotationState)
            App.recoverySaveError = not ok and tostring(issue) or nil
        end
        pollSession()
        pollWebhook()
        local suffix = "\nProfile: " .. App.profile .. "  |  Blocks broken: " .. App.stats.broken
            .. "  |  Trips: " .. App.stats.trips .. "  |  Blocks moved: " .. App.stats.moved
            .. "  |  Gems collected: " .. App.stats.gems
            .. "\nHarvest blocks collected: " .. App.stats.harvested .. "  |  Blocks stashed: " .. App.stats.stashed
            .. "  |  Seeds planted: " .. App.stats.planted
            .. "  |  Trees harvested: " .. App.stats.trees
            .. "  |  Harvest seeds collected/stored: " .. App.stats.harvestSeeds .. "/" .. App.stats.stashedSeeds
            .. "  |  Rotations completed: " .. App.stats.cycles
        pcall(function()
            paragraphSet(ui.status, "Status", App.status .. suffix)
            paragraphSet(ui.transferStatus, "Status", App.status .. suffix)
            paragraphSet(ui.harvestStatus, "Status", App.status .. suffix)
            paragraphSet(ui.plantStatus, "Status", App.status .. suffix)
            paragraphSet(ui.rotationStatus, "Status", App.status .. suffix)
            local farms = {}
            for _, name in ipairs(App.config.planting.worlds) do
                local box = App.config.rotation.farms[name]
                table.insert(farms, name .. (box and (" | tile " .. box.x .. ", " .. box.y) or " | Save harvest box in this world"))
            end
            paragraphSet(ui.rotationFarms, "Farm storage saved per world", #farms > 0 and table.concat(farms, "\n") or "Enter farm worlds on Planting, then save a harvest box in each world.")
            paragraphSet(ui.log, "Recent activity", table.concat(App.logs, "\n"))
            local state = App.webhookState
            local details = state.status .. "\nInterval: " .. App.config.webhook.intervalMinutes .. " min"
                .. "\nLast sent: " .. (state.lastSent or "Never")
                .. "\nFailure alerts: " .. (App.config.webhook.failureAlerts and "On" or "Off")
                .. "\nQueued work/failure reports: " .. #state.events
            if App.config.webhook.enabled then
                local nextAt = math.max(state.nextAt or os.clock(), state.retryAt or 0)
                details = details .. "\nNext report in: " .. math.ceil(math.max(0, nextAt - os.clock()) / 60) .. " min"
            end
            paragraphSet(ui.webhookStatus, "Webhook status", details)
        end)
        task.wait(1)
    end
end)
return App
