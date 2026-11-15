-- Built by build.mjs. Use the generated loader.lua in Delta.
local Core = __CLARIS_CORE__
local Navigation = __CLARIS_NAV__
local VERSION = "0.1.41"
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local env = getgenv and getgenv() or _G
local ACCOUNT_ID = player.UserId
assert(type(ACCOUNT_ID) == "number" and ACCOUNT_ID > 0 and ACCOUNT_ID == math.floor(ACCOUNT_ID),
    "The Roblox account is not ready. Run the loader after signing in.")
local LEGACY_ROOT = "ClarisGrowblox"
local ROOT = LEGACY_ROOT .. "/accounts/" .. tostring(ACCOUNT_ID)
local PROFILE_DIR = ROOT .. "/profiles"
local RESUME_FILE = ROOT .. "/resume.json"
local PNB_RESUME_FILE = ROOT .. "/pnb-resume.json"
local SESSION_FILE = ROOT .. "/session.json"
local PLANT_RESUME_FILE = ROOT .. "/plant-resume.json"
local ROTATION_RESUME_FILE = ROOT .. "/rotation-resume.json"
local saveRotationResume
local enterPlantWorld
local queueWebhookEvent
local restoreFPSBooster, pollFPSBooster
local previousSession = env.ClarisGrowbloxApp

if env.ClarisGrowbloxApp then
    -- Reloading an idle script should preserve a paused transfer checkpoint.
    local previous = env.ClarisGrowbloxApp
    previous.alive = false
    previous.token = previous.token + 1
    if previous.restoreFPSBooster then pcall(previous.restoreFPSBooster) end
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
    assert(player.UserId == ACCOUNT_ID, "The Roblox account changed. Reload the script for this account.")
    assert(type(readfile) == "function" and type(writefile) == "function"
        and type(isfolder) == "function" and type(makefolder) == "function",
        "Delta file functions are unavailable. Profile saving needs readfile/writefile/makefolder.")
    for _, folder in ipairs({LEGACY_ROOT, LEGACY_ROOT .. "/accounts", ROOT, PROFILE_DIR}) do
        if not isfolder(folder) then makefolder(folder) end
    end
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
    userId = ACCOUNT_ID, dataFolder = ROOT,
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
    assert(player.UserId == ACCOUNT_ID, "The Roblox account changed. Reload the script for this account.")
    local config, profile = Core.validate(App.config), Core.profileName(App.profile)
    local signature = encode({config = config, profile = profile})
    if signature == App.sessionSignature then return end
    writeJSON(SESSION_FILE, {version = 1, userId = ACCOUNT_ID, config = config, profile = profile})
    App.sessionSignature, App.sessionSaveError = signature, nil
end
local function saveFPSPreference()
    saveSession()
    -- A queued resume reads its own configuration snapshot. Update only this
    -- visual preference, preserving pending cargo, tile evidence and timestamps.
    for _, path in ipairs({RESUME_FILE, PNB_RESUME_FILE, PLANT_RESUME_FILE, ROTATION_RESUME_FILE, ROOT .. "/botting-resume.json"}) do
        if exists(path) then
            local record = decode(readfile(path))
            if type(record) == "table" and record.active and record.userId == ACCOUNT_ID
                and record.profile == App.profile then
                record.config = Core.validate(record.config)
                record.config.options.fpsBooster = App.config.options.fpsBooster
                record.config.options.fpsGreyMap = App.config.options.fpsGreyMap
                record.config.options.fpsHideWorld = App.config.options.fpsHideWorld
                writeJSON(path, record)
            end
        end
    end
end
local function restoreSession(previous)
    local record
    if previous and previous.userId == ACCOUNT_ID and previous.config then
        record = {version = 1, userId = ACCOUNT_ID, config = previous.config, profile = previous.profile}
    elseif exists(SESSION_FILE) then record = decode(readfile(SESSION_FILE)) end
    if not record then return false end
    assert(type(record) == "table", "The saved session file is invalid.")
    assert(record.version == 1, "Unsupported saved session schema: " .. tostring(record.version))
    assert(record.userId == ACCOUNT_ID, "The saved session belongs to another account.")
    App.config, App.profile = Core.validate(record.config), Core.profileName(record.profile)
    return true
end
local function migrateLegacyStorage()
    local marker = ROOT .. "/migration.json"
    if exists(marker) then return end
    local migrated, session = 0, nil
    for _, name in ipairs({"session", "resume", "pnb-resume", "plant-resume", "rotation-resume"}) do
        local oldPath, newPath = LEGACY_ROOT .. "/" .. name .. ".json", ROOT .. "/" .. name .. ".json"
        if not exists(newPath) and exists(oldPath) then
            local ok, record = pcall(function() return decode(readfile(oldPath)) end)
            if ok and type(record) == "table" and record.userId == ACCOUNT_ID then
                writeJSON(newPath, record)
                migrated = migrated + 1
                if name == "session" then session = record end
            end
        end
    end
    -- Legacy profile files have no owner. Recover the active profile from the
    -- owned session snapshot, rather than a same-name file another account used.
    if not session and exists(SESSION_FILE) then
        local ok, record = pcall(function() return decode(readfile(SESSION_FILE)) end)
        if ok and type(record) == "table" and record.userId == ACCOUNT_ID then session = record end
    end
    if session then
        local ok, config, profile = pcall(function()
            return Core.validate(session.config), Core.profileName(session.profile)
        end)
        if ok then
            local path = PROFILE_DIR .. "/" .. profile .. ".json"
            if not exists(path) then writeJSON(path, config) end
        end
    end
    -- Never delete shared legacy files, and never resurrect cleared checkpoints
    -- on later reloads. Each account completes migration independently.
    writeJSON(marker, {version = 1, userId = ACCOUNT_ID})
    App.migratedFiles = migrated
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
local function checkpoint(token, settling)
    assert(App.alive and App.job and token == App.token, "Stopped.")
    assert(player.UserId == ACCOUNT_ID, "The Roblox account changed. Reload the script for this account.")
    if App.botting then App.botting.guard(settling) end
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
        if token then checkpoint(token, true) end
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
    return {values = {}, names = {}, work = 0, steps = 0, yields = 0, reads = 0, lastYield = os.clock()}
end
local function scanStep(scan, stage)
    assert(App.alive, "This script was unloaded during discovery.")
    App.startupStage = stage
    scan.work = scan.work + 1
    scan.steps = scan.steps + 1
    if scan.work >= 8192 or os.clock() - scan.lastYield >= 0.006 then
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
    for _, object in pairs(scan.tables or objects) do
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
    local registry, registrySource = resolveRegistry({}, scan)
    local registryKey = ReplicatedStorage:GetAttribute("Qz")
    local worlds, physics, controls, huds, backpacks, menus, entries = {}, {}, {}, {}, {}, {}, {}
    scan.tables, scan.functions = {}, {}
    for _, object in pairs(objects) do
        scanStep(scan, "Indexing world and controls")
        if type(object) == "table" then
            table.insert(scan.tables, object)
            if not registry then
                local map = registryMap(object, scan)
                if map then registry, registrySource = map, "GC module map"
                elseif registryKey ~= nil then
                    map = registryMap(rawget(object, registryKey), scan)
                    if map then registry, registrySource = map, "GC shared table" end
                end
            end
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
            if type(rawget(object, "setGems")) == "function" and type(rawget(object, "addGems")) == "function"
                and type(rawget(object, "setWorld")) == "function" and type(rawget(object, "isTyping")) == "function" then
                table.insert(huds, object)
            end
            if inventoryObject(object) then table.insert(backpacks, object) end
            if type(rawget(object, "respawn")) == "function" then table.insert(menus, object) end
        elseif type(object) == "function" then
            table.insert(scan.functions, object)
            if functionName(object, scan) == "enter" then table.insert(entries, object) end
        end
    end
    objects = nil -- Do not retain the unfiltered GC snapshot between attachment stages.
    App.discoveryReport = { "Registry: " .. registrySource }
    table.insert(App.discoveryReport, "World tables: " .. #worlds .. "; avatar controllers: "
        .. #physics .. "; touch controls: " .. #controls)
    assert(#worlds == 1, "Could not identify one active Growblox world table (found " .. #worlds .. ").")
    local world = worlds[1]
    local issues = {}
    local gemHud
    for _, candidate in ipairs(huds) do
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
            for _, candidate in ipairs(backpacks) do
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
        for _, object in ipairs(scan.functions) do
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
    local items, itemSource = resolveItems(world, scan.functions, registry, scan)
    local respawn, respawnSource = findRespawn(world, menus, scan)
    local treeRipe, harvestGear, treeRemaining
    if not scan.transferOnly then treeRipe, harvestGear, treeRemaining = treeGrowthHooks(world, items, handlers, scan) end
    table.insert(App.discoveryReport, "Item definitions: " .. itemSource)
    local runtime = { world = world, body = body, controls = controls[1], inventory = inventory,
        items = items, handlers = handlers, issues = issues,
        readInventoryView = readInventoryView, ready = #issues == 0, gemHud = gemHud,
        picker = findWorldPicker(world, entries, scan), farmingDeferred = scan.transferOnly,
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
    App.discoveryPerformance = {yields = scan.yields, upvalueReads = scan.reads, steps = scan.steps,
        tables = #scan.tables, functions = #scan.functions, seconds = os.clock() - startedAt}
    table.insert(App.discoveryReport, "Discovery: " .. scan.yields .. " frame yields; " .. scan.reads
        .. " function upvalue reads; " .. scan.steps .. " indexed checks; " .. string.format("%.2fs", App.discoveryPerformance.seconds))
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
    if restoreFPSBooster then restoreFPSBooster() end
    App.runtime = result
    if pollFPSBooster then pollFPSBooster(true) end
    App.connectionError = nil
    return result
end

local function runtime()
    assert(App.runtime, App.connectionError or "The script has not attached to Growblox yet. Use Reconnect in Settings.")
    return App.runtime
end
-- Growblox's drops are 2D GUI sprites. Keep native frames alive for count,
-- pickup and world cleanup, but detach loose sprites from the rendered GUI.
-- Native visibility writes cannot reveal a detached frame; no per-frame hooks
-- or property-change listeners are needed for thousands of drops.
do
local function restoreDropVisual(frame, record)
    if frame.Parent == nil then frame.Parent = record.parent end
    if not record.drop.display then
        if record.drop.inBlock == true then record.drop.inBlock = record.inBlock end
        if record.pop and record.pop.Scale == 1 then record.pop.Scale = record.scale end
    end
end
local function restoreFloatingDrops()
    local state = App.fpsState
    App.fpsHidden = 0
    if not state then return true end
    local present = {}
    local ok, drops = pcall(state.world.dropList)
    if not ok or type(drops) ~= "table" then
        App.fpsBoosterError = "Could not restore floating visuals: drop list unavailable."
        return false
    end
    for _, drop in pairs(drops) do present[drop] = true end
    local failed
    for frame, record in pairs(state.records) do
        if present[record.drop] and record.drop.frame == frame then
            -- Removed drops have been destroyed by the native client. Never
            -- recreate them or restore an old world's removed drop records.
            local restored, issue = pcall(restoreDropVisual, frame, record)
            if restored then state.records[frame] = nil else failed = tostring(issue) end
        else state.records[frame] = nil end
    end
    if failed then App.fpsBoosterError = "Could not restore floating visuals: " .. failed; return false end
    App.fpsState = nil
    return true
end
local function pollFloatingDrops(force)
    if not App.alive or not App.config.options.fpsBooster then
        if restoreFloatingDrops() then App.fpsBoosterError = nil end
        return
    end
    local r = App.runtime
    if not r or type(r.world.dropList) ~= "function" or App.fpsBusy then return end
    if not force and os.clock() < (App.nextFPSScan or 0) then return end
    App.fpsBusy = true
    local ok, issue = pcall(function()
        local state = App.fpsState
        if not state or state.world ~= r.world then
            assert(restoreFloatingDrops(), App.fpsBoosterError)
            state = {world = r.world, records = {}}
            App.fpsState = state
        end
        local drops = r.world.dropList()
        assert(type(drops) == "table", "Floating drop visuals are unavailable.")
        local work, lastYield = 0, os.clock()
        for _, drop in pairs(drops) do
            work = work + 1
            if work >= 512 or os.clock() - lastYield >= 0.006 then
                task.wait()
                if not App.alive or not App.config.options.fpsBooster or App.runtime ~= r or App.fpsState ~= state then return end
                work, lastYield = 0, os.clock()
            end
            if type(drop) == "table" and type(drop.uid) == "number" and not drop.display and drop.frame then
                local frame = drop.frame
                if not state.records[frame] then
                    local changed, value = pcall(function()
                        local parent = frame.Parent
                        if not parent then return end
                        local pop = drop.pop
                        local saved = {drop = drop, parent = parent, inBlock = drop.inBlock,
                            pop = pop, scale = pop and pop.Scale}
                        state.records[frame] = saved -- Track before mutating so a failure remains reversible.
                        frame.Parent = nil
                        drop.inBlock = true -- Native bobbing branch only; not pickup culling/access.
                        if pop then pop.Scale = 1 end
                    end)
                    assert(changed, "Could not reduce floating drop visuals: " .. tostring(value))
                end
            end
        end
        -- Native pickups can remove/shift rows during the yielded scan. Re-read
        -- membership before pruning so a missed row cannot lose its restore data.
        local present, hidden = {}, 0
        for _, drop in pairs(r.world.dropList()) do if type(drop) == "table" then present[drop] = true end end
        for frame, record in pairs(state.records) do
            if not present[record.drop] or record.drop.frame ~= frame then state.records[frame] = nil
            elseif record.drop.display then
                restoreDropVisual(frame, record)
                state.records[frame] = nil
            else hidden = hidden + 1 end
        end
        App.fpsHidden = hidden
        App.nextFPSScan = os.clock() + 1
    end)
    App.fpsBusy = false
    App.fpsBoosterError = not ok and tostring(issue) or nil
    if not ok then restoreFloatingDrops() end -- Visual failure must not interrupt a farming task.
end
local greyMap = (__CLARIS_FPS__)(App, upvalues)
restoreFPSBooster = function()
    local dropsOK, mapOK = restoreFloatingDrops(), greyMap.restore()
    return dropsOK and mapOK
end
pollFPSBooster = function(force)
    pollFloatingDrops(force)
    greyMap.poll(force)
end
App.restoreFPSBooster = restoreFPSBooster
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
        syncing = false, pausePickup = false, suppressedTakes = {} }
    hold.dirOverride = function() return hold.direction end
    hold.jumpOverride = function() return hold.jump end
    controls.dir, controls.jumping = hold.dirOverride, hold.jumpOverride
    hold.displayOverride = function() end
    hold.takeOverride = function(uid, ...)
        if hold.syncing or hold.pausePickup then
            hold.suppressedTakes[uid] = {grid = world.fg, at = os.clock()}
            return 0
        end
        hold.suppressedTakes[uid] = nil
        hold.autoTakes = hold.autoTakes + 1
        local result = table.pack(pcall(hold.takeDrop, uid, ...))
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
local function transientRouteFault(problem)
    if type(problem)~="string" then return false end
    return problem:find("Returning to the saved position timed out",1,true)
        or problem:find("Could not reach the saved position",1,true)
        or problem:find("The planned jumps did not reach the platforms",1,true)
        or problem:find("The avatar did not land on a reachable floor or platform",1,true)
end
local function walkTo(x, y, worldName, token, onStep)
    local r = worldCheck(worldName, token)
    tileAt(x, y)
    local hold = takeControls()
    local targetX, targetY = x + 0.5, y + 1
    local rotationPhase = App.rotationState and App.rotationState.phase
    local farmNavigation = App.job == "plant" or App.job == "harvest" or App.job == "rotation" or App.job == "botting"
        and (rotationPhase == "plant" or rotationPhase == "replant" or rotationPhase == "harvest"
            or rotationPhase == "harvestStock" or rotationPhase == "harvestPickupPending")
    local timeout = farmNavigation and math.max(90, App.config.options.moveTimeout) or App.config.options.moveTimeout
    local deadline, banned, replans = os.clock() + timeout, {}, 0
    local function collectionStep(state)
        if not onStep then return true, 0 end
        local started = os.clock()
        local proceed = onStep(state)
        local waited = os.clock() - started
        -- Pickup waiting has its own timeout and is not a failed walking step.
        deadline = deadline + waited
        return proceed ~= false, waited, proceed == "hold"
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
        local proceed, _, pacing = collectionStep(state)
        if not proceed then hold.direction, hold.jump = 0, false; return false end
        while pacing do
            hold.direction, hold.jump = 0, false
            pause(0.025, token)
            deadline = deadline + 0.025
            worldCheck(worldName, token)
            state = position()
            proceed, _, pacing = collectionStep(state)
            if not proceed then return false end
        end
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
        local routeContext = worldName .. ": from tile " .. start.x .. ", " .. start.y
            .. " to standing tile " .. x .. ", " .. y
        App.navigationDebug = "Planning " .. routeContext
        local route, message = Navigation.plan(navigationMap(r), start, {x = x, y = y}, {
            banned = banned, fullWorld = farmNavigation,
            maxNodes = farmNavigation and math.min(12000, r.world.w * r.world.h) or 1600,
            step = function() pause(0, token); worldCheck(worldName, token) end,
        })
        if not route then
            App.navigationDebug = "Failed " .. routeContext .. "; " .. tostring(message)
            error(tostring(message) .. " Route: " .. routeContext, 0)
        end
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
                local proceed, waited, pacing = collectionStep(state)
                began, movedAt = began + waited, movedAt + waited
                if not proceed then hold.direction, hold.jump = 0, false; return false end
                state = position()
                if not pacing and reached(state, waypoint.x + 0.5, waypoint.y + 1) then break end
                assert(os.clock() < deadline, "Returning to the saved position timed out. Check the route.")
                if UserInputService:GetFocusedTextBox() or pacing then
                    hold.direction, hold.jump = 0, false
                    movedAt = os.clock()
                    if pacing then
                        -- Keep the next planting or pickup target in reach while
                        -- its native action is pending, without reversing a row.
                        began, deadline = began + 0.025, deadline + 0.025
                    end
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
local function moveTo(x,y,worldName,token,onStep)
    for attempt=1,3 do
        local result=table.pack(pcall(walkTo,x,y,worldName,token,onStep))
        if result[1] then return table.unpack(result,2,result.n) end
        checkpoint(token)
        local state=App.rotationState
        local pending=App.plantState and App.plantState.pending
            or state and (state.plant and state.plant.pending or state.harvestPlant and state.harvestPlant.pending)
        if (App.job~="rotation" and App.job~="botting") or App.pending>0 or pending or not transientRouteFault(result[2]) or attempt==3 then
            error(result[2],0)
        end
        worldCheck(worldName,token)
        local hold=takeControls()
        hold.direction,hold.jump=0,false
        App.navigationRecovery=worldName .. ": replanning walking route, attempt " .. (attempt+1) .. "/3"
        setStatus("Movement delayed; " .. App.navigationRecovery .. "...")
        pause(0.5,token)
    end
end
local function moveToPoint(point, token)
    moveTo(point.standX or point.x, point.standY or point.y, point.world, token)
end
local function assertPNBPosition()
    if App.job ~= "pnb" and not (App.job == "rotation" and App.rotationState
        and (App.rotationState.phase == "pnb" or App.rotationState.phase == "waitPNB" or App.rotationState.phase == "drainPNB")) then return end
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
    if App.botting then App.botting.beforeStorage("withdraw", point, id, nil, companionId) end
    local ok, result = bounded(runtime().world.call, App.config.options.actionTimeout, token,
        "DisplayItem", point.x, point.y, nil)
    if not ok and App.botting then App.botting.afterStorage() end
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
    if App.botting then App.botting.afterStorage() end
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
    if App.botting then App.botting.beforeStorage("deposit", point, id, amount, companionId) end
    local ok, result = bounded(runtime().world.call, App.config.options.actionTimeout, token,
        "DisplayItem", point.x, point.y, id, nil, nil, amount, point.x + 0.5)
    if not ok and App.botting then App.botting.afterStorage() end
    assert(ok, type(result) == "string" and result or "The storage deposit was rejected.")
    refreshInventory(token)
    assert(count(id) <= before - amount, "The server did not confirm the storage deposit.")
    if App.botting then App.botting.afterStorage() end
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
    writeJSON(PNB_RESUME_FILE, {version = 1, active = true, userId = ACCOUNT_ID, updatedAt = os.time(),
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
    assert(record.version == 1 and record.userId == ACCOUNT_ID, "The saved farm belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600,
        "The saved farm is over six hours old. Load your profile and start it again.")
    record.config, record.profile = Core.validate(record.config), Core.profileName(record.profile)
    return record
end
local function saveResume(phase, cargo, item)
    saveSession()
    item = item or (App.rotationState and "blocks" or App.config.moving.item)
    local blockId, seedId = App.config.blockId, Core.seedId(runtime().items, App.config.blockId)
    local record = { version = 1, active = true, userId = ACCOUNT_ID, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, phase = phase, cargo = cargo or 0,
        item = item, companion = count(item == "seeds" and blockId or seedId), seeds = count(seedId) }
    writeJSON(RESUME_FILE, record)
    App.resume = record
    if App.rotationState then
        App.rotationState.transfer = {phase = phase, cargo = cargo or 0, seeds = record.seeds,
            item = item, companion = record.companion}
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

local function takeDropBatch(anchor, targets, attempts, retryAt, eligible, token, onTaken, options)
    local r = worldCheck(anchor.world, token)
    local take = App.controls and App.controls.takeDrop or r.world.takeDrop
    assert(type(take) == "function" and type(r.world.dropTaken) == "function",
        "The loose-drop pickup hooks are unavailable. Copy diagnostics from Settings.")
    local jobs, reserved = {}, {}
    local deadline = os.clock() + App.config.options.actionTimeout
    for _, drop in ipairs(targets) do
        if #jobs >= (options and options.limit or 8) then break end
        worldCheck(anchor.world, token)
        assertPNBPosition()
        local present = false
        for _, current in pairs(r.world.dropList()) do if current == drop then present = true; break end end
        local room = drop.id == 112 and 65535 or math.max(0, r.inventory:room(drop.id)
            - (reserved[drop.id] or 0) - (options and options.reserved[drop.id] or 0))
        local want = math.floor(math.min(drop.n, room, 65535))
        if want > 0 and present and eligible(drop) then
            local before, grid, uid, id = drop.n, r.world.fg, drop.uid, drop.id
            local state = position()
            if id ~= 112 then reserved[id] = (reserved[id] or 0) + want end
            attempts[uid] = (attempts[uid] or 0) + 1
            if App.controls then App.controls.suppressedTakes[uid] = nil end
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
            table.insert(jobs, {request = request, uid = uid, id = id, want = want, deadline = deadline, started = os.clock(),
                avatarX = state.x, avatarY = state.y, dropX = drop.x, dropY = drop.y})
        end
    end
    if options and options.defer then return jobs end
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

local makeHarvestPlanter
local function runTreeHarvest(token)
    local name, id = App.config.points.farmBox.world, App.config.blockId
    local r = worldCheck(name, token)
    local rotation, pass = App.rotationState, App.rotationState and App.rotationState.harvestPass
    assert(not pass or pass.world == name and pass.phase == "trees", "The saved tree pass belongs to another farm or harvest stage.")
    local seedId = Core.seedId(r.items, id)
    local planter = App.job ~= "botting" and App.rotationState and App.config.options.harvestPlanting and makeHarvestPlanter(token) or nil
    if not Core.hasTrees(r.world, seedId) then
        App.harvestMaturity = name .. ": no selected trees"
        suspendHarvestVehicle(token)
        return
    end
    if r.farmingDeferred then
        setStatus("Connecting tree harvesting hooks...")
        r = connectGame()
        worldCheck(name, token)
    end
    assert(type(r.treeRipe) == "function", "Tree growth hooks are unavailable. Reconnect and copy diagnostics.")
    local growing, ripeCount, remaining = Core.treeGrowth(r.world, seedId, r.treeRipe, r.treeRemaining,
        function() pause(0, token); worldCheck(name, token) end)
    App.harvestMaturity = name .. ": " .. ripeCount .. " ripe; " .. growing .. " growing"
    if growing > 0 and not pass then
        suspendHarvestVehicle(token)
        App.harvestPhase = "Waiting for all farm trees to grow"
        setStatus("Waiting for all trees in " .. name .. " to grow: " .. growing .. " still growing; check again in "
            .. math.ceil(remaining) .. "s.")
        return false
    end
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
    end
    assert(r.handlers and type(r.handlers.hit) == "function", "The Fist tree harvesting hook is unavailable; Tractor also needs it for missed trees.")
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
    local gems = (function()
        local jobs, attempts, retryAt, deferred = {}, {}, {}, {}
        local nextScan = 0
        local function settle(waitAll)
            for index = #jobs, 1, -1 do
                local job = jobs[index]
                if waitAll or job.request.done then
                    local amount = awaitRequest(job.request, job.deadline, token)
                    if amount > 0 then attempts[job.uid] = 0
                    else deferred[job.uid] = true end -- Retry in the collection pass, without reversing the tractor.
                    table.remove(jobs, index)
                else
                    assert(os.clock() < job.deadline, "Request timed out. Wait for it to finish before restarting.")
                end
            end
        end
        local function step()
            worldCheck(name, token)
            settle(false)
            if #jobs >= 8 or os.clock() < nextScan then return end
            nextScan = os.clock() + 0.05
            local state = position()
            local function eligible(drop, avatar)
                return type(drop) == "table" and drop.id == 112 and not drop.display
                    and type(drop.uid) == "number" and type(drop.n) == "number" and drop.n > 0
                    and type(drop.x) == "number" and type(drop.y) == "number"
                    and not drop.pending and not drop.taking and not deferred[drop.uid]
                    and Navigation.pickupOverlap(avatar or position(), drop)
                    and os.clock() >= math.max(drop.readyAt or 0, retryAt[drop.uid] or 0)
            end
            local targets = {}
            for _, drop in pairs(r.world.dropList()) do
                if type(drop) == "table" and drop.id == 112 and type(drop.uid) == "number" then
                    local refused = drop.refused or -math.huge
                    local suppressed = App.controls and App.controls.suppressedTakes[drop.uid]
                    -- The native loop marks our blocked attempts as refusals.
                    -- Only genuine server refusals should delay currency pickup.
                    if suppressed and suppressed.grid == r.world.fg and refused >= suppressed.at then
                        refused = -math.huge
                    end
                    retryAt[drop.uid] = retryAt[drop.uid] or (refused + 1)
                    if eligible(drop, state) then table.insert(targets, drop) end
                end
            end
            -- Claim only currency during tree work. Blocks/seeds stay suppressed
            -- so planting's server seed counts remain unambiguous.
            local batch = takeDropBatch({world = name}, targets, attempts, retryAt, eligible, token, nil,
                {defer = true, limit = 8 - #jobs})
            for _, job in ipairs(batch) do table.insert(jobs, job) end
            settle(false)
        end
        return {step = step, finish = function() settle(true) end}
    end)()
    local missed, counted = {}, {}
    local function countTree(point)
        local key = point.y * r.world.w + point.x
        assert(tileAt(point.x, point.y) == 0, "A harvested tree was replaced before confirmation.")
        if not counted[key] then counted[key], App.stats.trees = true, App.stats.trees + 1 end
        point.done = true
    end
    local function pending(point)
        if point.done then return false end
        local current = tileAt(point.x, point.y)
        if current == 0 then
            settleTile(point.x, point.y, 0, 0.25, name, token)
            countTree(point)
            return false
        end
        assert(current == seedId, "A missed tree was replaced before Fist cleanup. Check the farm before resuming.")
        local ripe = r.treeRipe(point.x, point.y, seedId)
        assert(ripe ~= nil, "Tree growth data is not ready during Fist cleanup.")
        if not ripe then point.done = true; return false end -- Leave newly growing trees alone.
        return true
    end
    local function fistReach(state, point)
        -- Native punching compares both axes with the base 2.5-tile reach.
        return state.grounded and math.abs(point.x + 0.5 - state.x) <= 2.5
            and math.abs(point.y + 0.5 - (state.y - 0.475)) <= 2.5
    end
    local function fistMiss(point)
        local tries = 0
        App.harvestPhase = "Fist cleanup of missed trees"
        setStatus("Clearing missed tree at " .. point.x .. ", " .. point.y .. " with Fist...")
        while pending(point) do
            worldCheck(name, token)
            assert(fistReach(position(), point), "The missed tree is outside Fist reach. Check the cleanup standing position.")
            assert(not r.world.riding or not r.world.riding.harvest, "Remove the tractor before Fist cleanup.")
            tries = tries + 1
            assert(tries <= 3, "Fist did not harvest the missed tree at " .. point.x .. ", " .. point.y .. ". Check access.")
            r.handlers.hit(point.x, point.y)
            pause(math.max(0.25, App.config.options.punchDelay), token)
        end
        if planter then planter.plant(point) end
        App.harvestPhase = "Breaking ripe trees"
    end
    local function rowMisses(row)
        local targets = {}
        for _, point in ipairs(missed) do
            local x = math.max(row.left, math.min(row.right, point.x))
            if pending(point) and point.y < row.y and fistReach({x=x+0.5,y=row.y+1,grounded=true}, point) then
                table.insert(targets, point)
            end
        end
        return targets
    end
    local function cleanupFromRow(row, restoreTractor)
        return function(state)
            worldCheck(name, token)
            if not state.grounded or math.abs(state.y - (row.y + 1)) > 0.22 then return end
            local targets, nearby = rowMisses(row), false
            for _, point in ipairs(targets) do
                local x = math.max(row.left, math.min(row.right, point.x))
                if math.abs(x + 0.5 - state.x) <= 0.55 then nearby = true; break end
            end
            if not nearby then return end
            feet(nil)
            table.sort(targets, function(a,b) return a.x * row.direction < b.x * row.direction end)
            for _, point in ipairs(targets) do
                if pending(point) and fistReach(position(), point) then fistMiss(point) end
            end
            if restoreTractor then feet(tractor) end
        end
    end
    App.harvestPhase, App.harvestGearError = "Breaking ripe trees", nil
    if rotation and not pass then
        -- Approval survives retries/reloads after we have replanted cleared tiles.
        -- Growing replacements must not cancel the rest of this harvest pass.
        rotation.harvestPass = {world = name, phase = "trees"}
        saveRotationResume(rotation)
    end
    for _, row in ipairs(rows) do
        worldCheck(name, token)
        local points = Core.ripeTrees(r.world, seedId, row, r.treeRipe)
        if #points > 0 then
            setStatus((method == "tractor" and "Driving Dear John Tractor" or "Harvesting with Fist") .. " on row " .. row.y .. "...")
            feet(nil) -- Approach the work row at walking speed, including after a refill/resume.
            moveTo(row.direction == 1 and row.left or row.right, row.y, name, token)
            if method == "tractor" then
                feet(tractor)
                local cleanup = cleanupFromRow(row, true)
                -- One forward row pass. Missing trees are cleared with Fist from
                -- a lower row instead of reversing the slow tractor to retry.
                moveTo(row.direction == 1 and row.right or row.left, row.y, name, token, function(state)
                    worldCheck(name, token)
                    assert(gear.feet() == tractor, "Dear John Tractor was unequipped during harvesting.")
                    cleanup(state)
                    local proceed = planter and planter.step(row, points, countTree)
                    gems.step()
                    return proceed
                end)
                feet(nil)
                gems.finish()
                if planter then planter.finish() end
                pause(0.25, token) -- Observe late tree corrections before queuing misses.
                for _, point in ipairs(points) do
                    if not point.done then
                        if tileAt(point.x, point.y) == 0 then countTree(point)
                        elseif pending(point) then table.insert(missed, point) end
                    end
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
                            if planter then planter.plant(point) end
                        end
                    end
                end
            end
        elseif method == "tractor" then
            -- An empty lower row can still provide a fast Fist approach to
            -- misses above it. Do not equip the tractor for this cleanup.
            local targets = rowMisses(row)
            if #targets > 0 then
                moveTo(row.direction == 1 and row.left or row.right, row.y, name, token)
                table.sort(targets, function(a,b) return a.x * row.direction < b.x * row.direction end)
                local last = targets[#targets]
                local cleanup = cleanupFromRow(row, false)
                moveTo(math.max(row.left, math.min(row.right, last.x)), row.y, name, token, function(state)
                    cleanup(state)
                    return #rowMisses(row) > 0
                end)
            end
        end
    end
    if method == "tractor" then
        feet(nil)
        for _, point in ipairs(missed) do
            if pending(point) then
                local state, goal = position(), nil
                if not fistReach(state, point) or state.y <= point.y + 1.1 then
                    local map, candidates = navigationMap(r), {}
                    for y=point.y+1,math.min(point.y+2,r.world.h-2) do
                        for x=math.max(0,point.x-2),math.min(point.x+2,r.world.w-1) do
                            if fistReach({x=x+0.5,y=y+1,grounded=true},point)
                                and not map.solid(x,y) and (map.solid(x,y+1) or map.platform(x,y+1))
                                and not map.danger(x,y) and not map.danger(x,y+1) then
                                table.insert(candidates,{x=x,y=y,distance=math.abs(x+0.5-state.x)+math.abs(y+1-state.y)})
                            end
                        end
                    end
                    table.sort(candidates,function(a,b) return a.distance < b.distance end)
                    for _, candidate in ipairs(candidates) do
                        local route = Navigation.plan(map,{x=math.floor(state.x),y=math.floor(state.y-0.01)},candidate,{
                            fullWorld=true,maxNodes=math.min(12000,r.world.w*r.world.h),
                            step=function() pause(0,token); worldCheck(name,token) end})
                        if route then goal=candidate; break end
                    end
                    -- Farms without a reachable lower support use a normal
                    -- walking approach on the tree row, with the tractor off.
                    goal=goal or point
                    moveTo(goal.x,goal.y,name,token)
                end
                fistMiss(point)
            end
        end
    end
    if planter then planter.finish() end
    App.harvestPhase = "Collecting blocks, seeds and gems"
end

local function harvestDropDeferred(name, drop)
    local rotation = App.rotationState or (App.job == "botting" and App.botState)
    local deferred = rotation and rotation.deferredHarvest and rotation.deferredHarvest[name]
    local key = tostring(drop.uid)
    local saved = deferred and deferred[key]
    if not saved then return false end
    if saved.id == drop.id and math.abs(saved.x-drop.x) < 0.1 and math.abs(saved.y-drop.y) < 0.1
        and Workspace:GetServerTimeNow() < saved.retryAt then return true end
    deferred[key] = nil -- Retry when the drop moves or its cooldown expires.
    return false
end

local function runHarvest(token)
    Core.checkSetup(App.config, "harvest", runtime().items)
    local box, id = App.config.points.farmBox, App.config.blockId
    local r = worldCheck(box.world, token)
    local seedId = Core.seedId(r.items, id)
    storageCount(box, id, seedId) -- Reject unsuitable storage before claiming anything.
    return harvestEquipmentScope(function() return withoutPickups(function()
        local storedBefore, seedsBefore, gemsBefore = App.stats.stashed, App.stats.stashedSeeds, App.stats.gems
        refreshInventory(token)
        local rotation, pass = App.rotationState, App.rotationState and App.rotationState.harvestPass
        assert(not pass or pass.world == box.world, "The saved harvest pass belongs to another farm.")
        if pass and pass.phase == "collect" then
            assert(not rotation.harvestPlant or not rotation.harvestPlant.pending,
                "A harvest planting batch is still pending before collection. Check the saved rotation.")
            suspendHarvestVehicle(token)
            setStatus("Resuming harvest block, seed and gem collection in " .. box.world .. "...")
        else
            if runTreeHarvest(token) == false then return false end
            if rotation then
                -- Save before collection travel or storage respawns can interrupt us.
                rotation.harvestPass = {world = box.world, phase = "collect"}
                saveRotationResume(rotation)
            end
        end
        r = worldCheck(box.world, token)
        App.harvestPhase = "Collecting blocks, seeds and gems"
        local attempts, retryAt, needsApproach, approached = {}, {}, {}, {}
        local lastRefusal = {}
        App.lastHarvestRefusal = nil
        local sweepRow, sweepX, sweepDirection
        local farmRows, farmRowsByY, activeFarmRow, restrictRoute = {}, {}, nil, false
        local rangeLimited, emptySince = false, nil
        local deadline = os.clock() + App.config.options.actionTimeout
        local routeJobs, routeReserved, routeAccepted = {}, {}, 0
        local waitingDrop, waitingAt
        local deferredCount = 0
        App.harvestCollectionRecovery = "No drops deferred"
        local lastCollectionStep
        local function selected(drop)
            return type(drop) == "table" and not drop.display and (drop.id == id or drop.id == seedId or drop.id == 112)
                and type(drop.uid) == "number" and type(drop.n) == "number" and drop.n > 0
                and type(drop.x) == "number" and type(drop.y) == "number"
                and not harvestDropDeferred(box.world, drop)
                and (not App.botDropFilter or App.botDropFilter(drop))
        end
        local function deferDrop(drop, message)
            assert(rotation and App.pending == 0, message)
            rotation.deferredHarvest = rotation.deferredHarvest or {}
            local deferred = rotation.deferredHarvest[box.world] or {}
            rotation.deferredHarvest[box.world] = deferred
            deferred[tostring(drop.uid)] = {id=drop.id,x=drop.x,y=drop.y,retryAt=Workspace:GetServerTimeNow()+300}
            deferredCount = deferredCount+1
            deadline = os.clock()+App.config.options.actionTimeout
            App.harvestCollectionRecovery = "Deferred uid " .. drop.uid .. " at " .. drop.x .. ", " .. drop.y
                .. " for 5 minutes: " .. message
            saveRotationResume(rotation)
            setStatus(App.harvestCollectionRecovery .. " Continuing collection and Farm storage transfer.")
        end
        local function capacityBlocked()
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) and drop.id ~= 112 and r.inventory:room(drop.id) - (routeReserved[drop.id] or 0) <= 0 then
                    if (routeReserved[drop.id] or 0) > 0 then return true end
                    assert(count(drop.id) > 0, "Your backpack has no room for harvested blocks or seeds. Free a slot before collecting.")
                    return true
                end
            end
            return false
        end
        local function onTaken(_, takenId, amount)
            if takenId == id then App.stats.harvested = App.stats.harvested + amount
            elseif takenId == seedId then App.stats.harvestSeeds = App.stats.harvestSeeds + amount end
        end
        local function near(state, drop)
            return Navigation.pickupOverlap(state, drop)
        end
        local function pickupCooldown(drop)
            if retryAt[drop.uid] == nil then
                local refused = drop.refused or -math.huge
                local blocked = App.controls and App.controls.suppressedTakes[drop.uid]
                if blocked and blocked.grid == r.world.fg and refused >= blocked.at then refused = -math.huge end
                retryAt[drop.uid] = refused + 1
            end
            return retryAt[drop.uid]
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
            if rotation then
                deferDrop(drop, "Server refused three settled pickups; " .. tostring(lastRefusal[drop.uid]))
                return
            end
            error("The server refused harvested drop uid " .. drop.uid .. " at " .. drop.x .. ", " .. drop.y
                .. ". Last pickup: " .. tostring(lastRefusal[drop.uid])
                .. ". Check pickup reach and access; copy diagnostics.")
        end
        local function applyResults(results, fromRoute, deferred)
            local accepted = false
            for _, result in ipairs(results) do
                if result.amount > 0 then
                    accepted, needsApproach[result.uid] = true, nil
                    if waitingDrop == result.uid then waitingAt = os.clock() end
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
            if accepted and not deferred then
                refreshInventory(token)
                deadline = os.clock() + App.config.options.actionTimeout
            end
            return accepted
        end
        local function settleRoute(waitAll)
            local results = {}
            for index = #routeJobs, 1, -1 do
                local job = routeJobs[index]
                if waitAll or job.request.done then
                    local amount = awaitRequest(job.request, job.deadline, token)
                    if amount > 0 then attempts[job.uid], routeAccepted = 0, routeAccepted + 1 end
                    if job.id ~= 112 then
                        routeReserved[job.id] = (routeReserved[job.id] or 0) - job.want + amount
                    end
                    job.amount = amount
                    table.insert(results, job)
                    table.remove(routeJobs, index)
                else assert(os.clock() < job.deadline, "Request timed out. Wait for it to finish before restarting.") end
            end
            if #results > 0 then applyResults(results, true, true) end
            if #routeJobs == 0 and (waitAll or routeAccepted >= 8) then
                if routeAccepted > 0 then
                    local hold = takeControls()
                    local direction, jumping = hold.direction, hold.jump
                    hold.direction, hold.jump = 0, false
                    refreshInventory(token)
                    hold.direction, hold.jump = direction, jumping
                end
                routeReserved, routeAccepted = {}, 0
            end
        end
        local function collectOnRoute(state)
            local now = os.clock()
            local stepDuration = math.min(0.2,math.max(0.025,now-(lastCollectionStep or now)))
            lastCollectionStep = now
            settleRoute(false)
            if restrictRoute and not rowHasDrops(activeFarmRow) then return false end
            if not state.grounded then return end
            sweepRow, sweepX = math.floor(state.y - 0.01), state.x
            if capacityBlocked() then return false end
            local function eligible(drop)
                return selected(drop) and onActiveRow(drop) and near(position(), drop)
                    and not needsApproach[drop.uid] and not drop.pending and not drop.taking
                    and os.clock() >= math.max(drop.readyAt or 0, retryAt[drop.uid] or 0)
            end
            local targets = {}
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) and near(state, drop) and onActiveRow(drop) then
                    pickupCooldown(drop)
                    if restrictRoute and needsApproach[drop.uid] and math.abs(drop.x-state.x) < 0.2
                        and math.abs(state.vx or 0) < 0.8 then needsApproach[drop.uid] = nil end
                    if (attempts[drop.uid] or 0) >= 3 then settleRoute(true); checkAttempts(drop) end
                    if eligible(drop) then table.insert(targets, drop) end
                end
            end
            -- Keep steering while native pickup replies settle. Reserve backpack
            -- room across all outstanding jobs and reconcile once per eight takes.
            local jobs = takeDropBatch(box, targets, attempts, retryAt, eligible, token, onTaken,
                {defer = true, limit = 8 - #routeJobs, reserved = routeReserved})
            for _, job in ipairs(jobs) do
                table.insert(routeJobs, job)
                if job.id ~= 112 then routeReserved[job.id] = (routeReserved[job.id] or 0) + job.want end
            end
            settleRoute(false)
            if restrictRoute then
                local current, row = position(), farmRows[activeFarmRow]
                if current.grounded and math.abs(current.y-(row.y+1)) < 0.22 then
                    local velocity = math.max(0,(current.vx or 0)*sweepDirection)
                    local braking = velocity*velocity/96 + velocity*stepDuration + 0.04
                    local blocker, offset
                    for _, drop in pairs(r.world.dropList()) do
                        if selected(drop) and onActiveRow(drop) then
                            local forward = (drop.x-current.x)*sweepDirection
                            local fresh = false
                            if drop.taking and stepDuration <= 0.04 and braking-forward < 0.55 then
                                for _, job in ipairs(routeJobs) do
                                    if job.uid == drop.uid and not job.request.done and os.clock()-job.started < 0.04 then fresh=true; break end
                                end
                            end
                            if not fresh and forward >= -0.6 and forward <= braking and (not offset or forward < offset) then
                                blocker,offset = drop,forward
                            end
                        end
                    end
                    if blocker then
                        if waitingDrop ~= blocker.uid then waitingDrop,waitingAt = blocker.uid,os.clock() end
                        assert(os.clock()-waitingAt < App.config.options.actionTimeout,
                            "Harvested drop uid " .. blocker.uid .. " did not settle during the forward row pass. Check pickup readiness and access.")
                        return "hold"
                    end
                end
            end
            waitingDrop,waitingAt = nil,nil
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
            settleRoute(true)
            waitingDrop,waitingAt = nil,nil
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
        if #farmRows >= 1 then
            local collectionDirection = 1
            for index = 1, #farmRows do
                -- Empty rows do not change the side where the previous pass ended.
                if rowHasDrops(index) then
                    activeFarmRow = index
                    restrictRoute, rangeLimited = true, true
                    local row, direction = farmRows[index], collectionDirection
                    sweepDirection = direction
                    local entry, exit = direction == 1 and row.left or row.right, direction == 1 and row.right or row.left
                    if capacityBlocked() then
                        stash()
                    end
                    setStatus("Collecting farm row " .. index .. "/" .. #farmRows .. " at " .. row.y .. "...")
                    moveTo(entry, row.y, box.world, token, function() return rowHasDrops(index) end)
                    while true do
                        worldCheck(box.world, token)
                        if not rowHasDrops(index) then break end
                        if capacityBlocked() then
                            stash()
                            local nextDrop
                            for _, drop in pairs(r.world.dropList()) do
                                if selected(drop) and onActiveRow(drop) and (not nextDrop or drop.x*direction < nextDrop.x*direction) then
                                    nextDrop = drop
                                end
                            end
                            if nextDrop then
                                local resumeX = math.max(row.left,math.min(row.right,math.floor(nextDrop.x)))
                                moveTo(resumeX,row.y,box.world,token,function() return rowHasDrops(index) end)
                            end
                            setStatus("Collecting farm row " .. index .. "/" .. #farmRows .. " at " .. row.y .. "...")
                        end
                        -- Resolve each stack before running beyond its pickup
                        -- overlap. Never schedule a return sweep along this row.
                        local finished = moveTo(exit,row.y,box.world,token,collectOnRoute)
                        settleRoute(true)
                        deadline = os.clock()+App.config.options.actionTimeout
                        if finished ~= false then break end
                    end
                    collectionDirection = -collectionDirection
                end
            end
            activeFarmRow, restrictRoute = nil, false
        end
        settleRoute(true)
        while true do
            worldCheck(box.world, token)
            local state = position()
            local remaining = {}
            for _, drop in pairs(r.world.dropList()) do
                if selected(drop) then
                    -- Suppressed native pickup attempts can keep updating refused.
                    -- Freeze its initial cooldown; our own refusals update retryAt.
                    pickupCooldown(drop)
                    table.insert(remaining, drop)
                end
            end
            if #remaining == 0 then
                stash()
                emptySince = emptySince or os.clock()
                if os.clock() - emptySince >= math.max(0.3, App.config.options.collectDelay) then
                    if App.stats.gems > gemsBefore and r.gemHud then
                        local gems = bounded(r.world.call, App.config.options.actionTimeout, token, "GetGems")
                        assert(type(gems) == "number" and gems >= 0, "Invalid gem balance from the server.")
                        r.gemHud.setGems(gems)
                    end
                    setStatus("Finished collecting harvest: " .. (App.stats.stashed - storedBefore)
                        .. " blocks and " .. (App.stats.stashedSeeds - seedsBefore) .. " seeds stored in the farm Display Box; "
                        .. (App.stats.gems - gemsBefore) .. " gems collected."
                        .. (deferredCount > 0 and " " .. deferredCount .. " inaccessible drops deferred; continuing with stored harvest." or ""))
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
                    if selected(drop) and ready(drop) then
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
                    local here = position()
                    if not goal and here.grounded and near(here, nextDrop) then
                        -- A fractional position at a floor edge can overlap the
                        -- drop even when no supported tile center does. Let the
                        -- server decide before giving up or requesting a route.
                        local hold = takeControls()
                        hold.direction, hold.jump = 0, false
                        needsApproach[nextDrop.uid], approached[nextDrop.uid] = nil, true
                        App.harvestCollectionRecovery = "Retrying nearby uid " .. nextDrop.uid .. " from the current supported position"
                        setStatus(App.harvestCollectionRecovery)
                        deadline = os.clock()+App.config.options.actionTimeout
                        pause(0.03, token)
                    elseif not goal and rotation then
                        settleRoute(true)
                        deferDrop(nextDrop, tostring(message))
                        deadline = os.clock()+App.config.options.actionTimeout
                    else
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
                                if selected(drop) and math.floor(drop.y) == goal.y and (tileX - goal.x) * sweepDirection > 0
                                    and (edge - tileX) * sweepDirection >= 0 then goal.x = tileX end
                            end
                        end
                        local finished = moveTo(goal.x, goal.y, box.world, token, collectOnRoute)
                        settleRoute(true)
                        if finished ~= false and near(position(), nextDrop) then
                            needsApproach[nextDrop.uid], approached[nextDrop.uid] = nil, true
                        end
                        deadline = os.clock() + App.config.options.actionTimeout
                        pause(0.03, token)
                    end
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
            -- An interrupted final iteration may have left its block or seed
            -- drops beside the spot. Claim them before declaring supply empty.
            collectDrops(p.pnb, blockId, seedId, token)
            if count(blockId) == 0 then
                setStatus("Refilling blocks from the right storage box...")
                local taken = withdraw(p.blockBox, blockId, token)
                if taken == 0 then
                    setStatus("Finished: no blocks remain in your backpack or block storage.")
                    return true
                end
                moveToPoint(p.pnb, token)
            end
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
    local p, blockId = App.config.points, App.config.blockId
    local seedId = Core.seedId(runtime().items, blockId)
    local item = travel and "blocks" or saved and saved.item or App.config.moving.item
    assert(item == "blocks" or item == "seeds", "Invalid saved Moving Drops item.")
    local id, companionId = item == "seeds" and seedId or blockId, item == "seeds" and blockId or seedId
    local companionName = item == "seeds" and "blocks" or "seeds"
    local destination = travel and p.blockBox or Core.transferDestination(App.config)
    local phase = saved and saved.phase or "pickup"
    local cargo = saved and saved.cargo or 0
    local function save(nextPhase, amount) saveResume(nextPhase, amount, item) end
    local function go(name)
        save(phase, cargo)
        if travel then travel(name) else enterPlantWorld(name, nil, token, true) end
    end
    assert(phase == "pickup" or phase == "deliver" or phase == "return" or phase == "returnSeeds", "Invalid transfer resume phase.")
    if saved then
        local expected = {[p.farmBox.world] = true}
        if phase ~= "pickup" then expected[destination.world] = true end
        local deadline = os.clock() + App.config.options.actionTimeout + 15
        setStatus("Waiting for the transfer world and avatar...")
        while true do
            checkpoint(token)
            local r = runtime()
            assert(r.world.name == nil or r.world.name == "" or expected[r.world.name],
                "The saved transfer arrived in an unexpected world. Check its saved boxes.")
            if expected[r.world.name] then
                if pickerOpen(r) then r.picker.complete() end
                local state = r.body and r.body.state()
                if state and state.active and not state.dead and not player:GetAttribute("Frozen") then break end
            end
            assert(os.clock() < deadline, "The transfer world or avatar did not become ready after loading.")
            pause(0.05, token)
        end
        if saved.companion or item == "blocks" and saved.seeds then
            refreshInventory(token)
            assert(count(companionId) >= (saved.companion or saved.seeds),
                "Some saved transfer " .. companionName .. " are missing. Check the backpack before resuming.")
        end
    else go(p.farmBox.world) end
    while true do
        checkpoint(token)
        if phase == "pickup" then
            worldCheck(p.farmBox.world, token)
            if storageCount(p.farmBox, id, companionId) == 0 then
                phase = "returnSeeds"
                save(phase, 0)
            else
                setStatus("Taking " .. item .. " from Farm storage; holding up to 200 " .. companionName .. " for mixed-box transfers...")
                save("pickupPending", 0)
                local taken, companion = withdraw(p.farmBox, id, token, companionId)
                assert(taken > 0 or companion > 0 and count(companionId) <= 200, "No selected items or matching companion items were withdrawn.")
                -- Keep the other item between trips so it cannot fill the next withdrawal.
                cargo = taken
                phase = taken > 0 and "deliver" or "pickup"
                save(phase, cargo)
            end
        elseif phase == "deliver" then
            if runtime().world.name == p.farmBox.world then
                setStatus("Going to the destination Display Box world...")
                go(destination.world)
            end
            worldCheck(destination.world, token)
            setStatus("Putting the transported " .. item .. " into destination storage...")
            -- Save the count before issuing a mutating request. An interrupted deposit is
            -- ambiguous; resume refuses to repeat it until the player checks the inventory.
            local moved = deposit(destination, id, cargo, token, function(available)
                assert(available >= cargo, "Some saved cargo is missing. Check your backpack before resuming.")
                save("depositPending", cargo)
            end, not travel and companionId or nil)
            App.stats.trips = App.stats.trips + 1
            App.stats.moved = App.stats.moved + moved
            cargo = 0
            phase = "return"
            save(phase, cargo)
        elseif phase == "return" then
            if runtime().world.name == destination.world then
                setStatus("Returning to the Farm Display Box world...")
                go(p.farmBox.world)
            end
            worldCheck(p.farmBox.world, token)
            phase = "pickup"
            save(phase, 0)
        elseif phase == "returnSeeds" then
            worldCheck(p.farmBox.world, token)
            if count(companionId) > 0 then
                setStatus("Returning the held " .. companionName .. " to the Farm Display Box...")
                deposit(p.farmBox, companionId, count(companionId), token, function()
                    save("seedReturnPending", 0)
                end, id)
            end
            clearResume()
            setStatus("Finished: all Farm storage " .. item .. " moved; held " .. companionName .. " returned to the same box.")
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
    local copy = {worldIndex = state.worldIndex, phase = state.phase, skipped = {}, pending = state.pending, deferred = {}}
    if state.rows then
        copy.rows = {}
        for _, row in ipairs(state.rows) do
            table.insert(copy.rows, {y = row.y, left = row.left, right = row.right})
        end
        copy.rowY = state.rowY
    end
    for key, reason in pairs(state.skipped or {}) do copy.skipped[key] = reason end
    for key, point in pairs(state.deferred or {}) do copy.deferred[key] = {x=point.x,y=point.y,tries=point.tries} end
    writeJSON(PLANT_RESUME_FILE, {version = 1, active = true, userId = ACCOUNT_ID, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, state = copy})
    App.plantState = state
    if App.job == "botting" and App.botState then App.botState.plant = state; App.botting.save() end
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
    assert(record.version == 1 and record.userId == ACCOUNT_ID, "The saved planting task belongs to another account or script version.")
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
    if state.deferred then
        assert(type(state.deferred) == "table", "Invalid deferred planting tiles.")
        for key, point in pairs(state.deferred) do
            assert(type(point) == "table" and type(point.x) == "number" and point.x == math.floor(point.x)
                and point.x >= 0 and point.x <= 65535 and type(point.y) == "number" and point.y == math.floor(point.y)
                and point.y >= 0 and point.y <= 65535 and key == point.x .. ":" .. point.y
                and (point.tries == 0 or point.tries == 1), "Invalid deferred planting tile.")
        end
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
        if point.tiles then
            assert(type(point.tiles) == "table" and #point.tiles >= 1 and #point.tiles <= 8
                and #point.tiles <= point.before, "Invalid pending seed batch.")
            local seen = {}
            for key in pairs(point.tiles) do
                assert(type(key) == "number" and key == math.floor(key) and key >= 1 and key <= #point.tiles,
                    "Invalid pending seed batch list.")
            end
            for _, tile in ipairs(point.tiles) do
                assert(type(tile) == "table" and type(tile.x) == "number" and tile.x == math.floor(tile.x)
                    and tile.x >= 0 and tile.x <= 65535 and tile.y == point.y and not seen[tile.x],
                    "Invalid pending seed batch tile.")
                seen[tile.x] = true
            end
            assert(point.tiles[1].x == point.x, "Invalid pending seed batch origin.")
        end
    end
    return record
end
enterPlantWorld = function(name, state, token, moving)
    suspendHarvestVehicle(token)
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
            assert(attempts <= 3, "World entry repeatedly returned to the picker: " .. name)
            assert(type(r.world.enter) == "function", "The world entry hook is unavailable.")
            if App.job == "botting" then App.botting.save()
            elseif App.rotationState then saveRotationResume(App.rotationState)
            elseif moving then
                assert(App.resume, "Moving Drops checkpoint is missing before world entry.")
                saveResume(App.resume.phase, App.resume.cargo, App.resume.item)
            else savePlantResume(state) end
            local queued = queueResume()
            setStatus("Entering " .. name .. "...")
            local entered, message, teleport = bounded(r.world.enter, App.config.options.actionTimeout + 15, token, name)
            if teleport then
                App.teleporting = true
                setStatus(queued and (App.rotationState and "Changing servers; rotation will resume after loading."
                        or moving and "Changing servers; Moving Drops will resume after loading." or "Changing servers; planting will resume after loading.")
                    or (App.rotationState and "Changing servers. Run the loader after arrival, then use Resume saved rotation."
                        or moving and "Changing servers. Run the loader after arrival, then use Resume saved transfer."
                        or "Changing servers. Run the loader after arrival, then use Resume planting."))
                local teleportDeadline = os.clock() + 45
                while os.clock() < teleportDeadline do pause(0.2, token) end
                error(App.rotationState and "Server teleport did not finish. Use Resume saved rotation after arrival."
                    or moving and "Server teleport did not finish. Use Resume saved transfer after arrival."
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
            if os.clock() - stableSince >= (moving and 0 or 1) then break end
        else stableSince = nil end
        assert(os.clock() < deadline, "World or avatar did not finish loading: " .. name)
        pause(0.1, token)
    end
    App.teleporting = false
    -- A world reload can restore the worn ride. Remove it again before stock
    -- movement or returning to the unfinished planting/harvest position.
    suspendHarvestVehicle(token)
    takeControls()
    if App.job == "botting" and App.botting and App.botting.shortcut and name == App.config.botting.world then App.botting.shortcut(token) end
    if not moving then refreshInventory(token) end
end
local function deferPlantTile(state, point, reason)
    local key=point.x .. ":" .. point.y
    state.deferred=state.deferred or {}
    local previous=state.deferred[key]
    state.deferred[key]={x=point.x,y=point.y,tries=previous and previous.tries or 0}
    state.skipped[key]=reason
end
-- Native placement is optimistic. Keep confirmed seeds, retire only this
-- bounded batch, and defer ordinary refusals without aborting the rotation.
local function confirmPlantBatch(state, token, save, lastPlant)
    local pending=state.pending
    if not pending then return end
    local name,id=pending.world,App.config.planting.seedId
    local tiles=pending.tiles or {pending}
    local hold=takeControls()
    hold.direction,hold.jump=0,false
    pause(math.max(0,(lastPlant or 0)+0.2-os.clock()),token)
    local deadline=os.clock()+App.config.options.actionTimeout
    while true do
        worldCheck(name,token)
        local actual=refreshInventory(token)[id] or 0
        assert(actual<=pending.before and actual>=pending.before-#tiles,
            "Seed count changed unexpectedly while planting. Check diagnostics before resuming.")
        local planted,values=0,{}
        for index,point in ipairs(tiles) do
            local value=tileAt(point.x,point.y)
            assert(value==0 or value==id,"A pending planting tile changed to another item. Check the farm before resuming.")
            values[index]=value
            if value==id then planted=planted+1 end
        end
        local consistent=actual==pending.before-planted
        if consistent or os.clock()>=deadline then
            local stable,settled=true,os.clock()+0.12
            repeat
                worldCheck(name,token)
                for index,point in ipairs(tiles) do
                    if tileAt(point.x,point.y)~=values[index] then stable=false; break end
                end
                if not stable then break end
                pause(0.03,token)
            until os.clock()>=settled
            for index,point in ipairs(tiles) do
                if tileAt(point.x,point.y)~=values[index] then stable=false; break end
            end
            -- A partial batch needs one more authoritative count before it is
            -- retired. Successful batches retain their normal one-read path.
            if stable and (not consistent or planted<#tiles) then
                stable=(refreshInventory(token)[id] or 0)==actual
            end
            if stable then
                local confirmed=math.min(planted,pending.before-actual)
                local assigned,skipped=0,0
                for index,point in ipairs(tiles) do
                    if values[index]==id and assigned<confirmed then assigned=assigned+1
                    else
                        deferPlantTile(state,point,"placement not confirmed")
                        skipped=skipped+1
                    end
                end
                App.stats.planted=App.stats.planted+confirmed
                state.pending=nil
                save(state)
                if skipped>0 then
                    App.plantingRecovery=name .. ": skipped " .. skipped .. " unconfirmed tiles near " .. pending.x .. ", " .. pending.y
                    setStatus(App.plantingRecovery .. "; continuing and retrying from below where reachable.")
                end
                return actual,skipped==0
            end
        end
        pause(0.15,token)
    end
end
local function reconcilePlant(state, token)
    if state.pending then confirmPlantBatch(state,token,savePlantResume) end
end
local function plantTile(point, state, token, save)
    save=save or savePlantResume
    return withoutPickups(function()
        local name, id = App.config.planting.worlds[state.worldIndex], App.config.planting.seedId
        local r = worldCheck(name, token)
        local before = refreshInventory(token)[id] or 0
        if not Core.plantingTile(r.world, r.items, point.x, point.y) then return false end
        if not r.handlers.canPlace(r.items[id], point.x, point.y) then return false end
        assert(before > 0, "No planting seeds are left in the backpack.")
        state.pending = {world = name, x = point.x, y = point.y, before = before, tiles={{x=point.x,y=point.y}}}
        save(state)
        r.handlers.plantSeed(id, point.x, point.y)
        local _,confirmed=confirmPlantBatch(state,token,save,os.clock()+math.max(0,App.config.options.placeDelay-0.2))
        return confirmed
    end)
end
local function plantRetryTargets(row,state)
    local targets={}
    for _,point in pairs(state.deferred or {}) do
        local x=math.max(row.left,math.min(row.right,point.x))
        if point.tries==0 and point.y<row.y and math.abs(point.x-x)<=2.5
            and math.abs(point.y+0.5-(row.y+1-0.475))<=2.5
            and Core.plantingTile(runtime().world,runtime().items,point.x,point.y) then table.insert(targets,point) end
    end
    table.sort(targets,function(a,b) return a.x*(row.direction or 1)<b.x*(row.direction or 1) end)
    return targets
end
local function retryPlantFromBelow(row,state,token,save)
    save=save or savePlantResume
    local name=App.config.planting.worlds[state.worldIndex]
    local r,attempts=worldCheck(name,token),0
    local avatar=position()
    if not avatar.grounded or math.abs(avatar.y-(row.y+1))>0.22 then return attempts end
    for _,point in ipairs(plantRetryTargets(row,state)) do
        local anchor=math.max(row.left,math.min(row.right,point.x))
        if math.abs(avatar.x-(anchor+0.5))<=0.55 then
            local key=point.x .. ":" .. point.y
            if not Core.plantingTile(r.world,r.items,point.x,point.y) then state.deferred[key]=nil; save(state)
            elseif count(App.config.planting.seedId)>0 then
                point.tries=1
                save(state) -- One lower-row retry per tile; never loop on a refusal.
                if r.handlers.canPlace(r.items[App.config.planting.seedId],point.x,point.y) then
                    attempts=attempts+1
                    setStatus("Retrying planting at " .. point.x .. ", " .. point.y .. " from below...")
                    if plantTile(point,state,token,save) then state.skipped[key],state.deferred[key]=nil,nil
                    else state.skipped[key]="placement refused after lower-row retry" end
                else state.skipped[key]="lower-row placement not permitted" end
                save(state)
            end
        end
    end
    return attempts
end
-- Run the native seed helper while walking. Only a small, saved batch may be
-- optimistic; server inventory plus every tile must agree before more seeds.
local function plantRow(row, reverse, state, token)
    return withoutPickups(function()
        local name, id = App.config.planting.worlds[state.worldIndex], App.config.planting.seedId
        local r = worldCheck(name, token)
        local points = {}
        for x = reverse and row.right or row.left, reverse and row.left or row.right, reverse and -1 or 1 do
            if not state.skipped[x .. ":" .. row.y] and Core.plantingTile(r.world, r.items, x, row.y) then
                table.insert(points, {x = x, y = row.y})
            end
        end
        if #points == 0 or count(id) == 0 then return end
        -- rowY preserves zigzag progress, not the avatar's position after entry.
        -- A refill/reload may return below the row or beyond its next empty tile.
        local avatar, first = position(), points[1]
        local ahead = (first.x + 0.5 - avatar.x) * (reverse and -1 or 1)
        if not avatar.grounded or math.abs(avatar.y - (row.y + 1)) > 0.22 or ahead < -1.2 then
            moveTo(first.x, row.y, name, token, function()
                return Core.rowHasPlantingSpace(r.world, r.items, row, state.skipped)
            end)
        end
        local available = refreshInventory(token)[id] or 0
        local cursor, nextPlant, lastPlant = 1, 0, 0
        local function confirm()
            if state.pending then available=confirmPlantBatch(state,token,savePlantResume,lastPlant) end
        end
        local function step(avatar)
            checkpoint(token)
            worldCheck(name, token)
            for _,point in ipairs(plantRetryTargets(row,state)) do
                local anchor=math.max(row.left,math.min(row.right,point.x))
                if avatar.grounded and math.abs(avatar.y-(row.y+1))<=0.22
                    and math.abs(avatar.x-(anchor+0.5))<=0.55 then
                    confirm()
                    retryPlantFromBelow(row,state,token)
                    available=count(id)
                    break
                end
            end
            if state.pending then
                local corrected = false
                for _, point in ipairs(state.pending.tiles) do if tileAt(point.x, point.y) ~= id then corrected = true end end
                if corrected or #state.pending.tiles >= 8 or count(id) == 0 then confirm() end
            end
            if available == 0 then return false end
            local point = points[cursor]
            if not point then return false end
            avatar = position() -- A batch confirmation may have yielded during movement.
            local ahead = (point.x + 0.5 - avatar.x) * (reverse and -1 or 1)
            if avatar.grounded and math.abs(avatar.y - (row.y + 1)) <= 0.22 and ahead < -1.2 then return false end
            if not avatar.grounded or math.abs(avatar.y - (row.y + 1)) > 0.22
                or math.abs(avatar.x - (point.x + 0.5)) > 1.2
                or UserInputService:GetFocusedTextBox() then return true end
            if os.clock() < nextPlant then return ahead <= 0.55 and "hold" or true end
            if not Core.plantingTile(r.world, r.items, point.x, point.y) then cursor = cursor + 1; return true end
            if not r.handlers.canPlace(r.items[id], point.x, point.y) then
                if math.abs(avatar.x - (point.x + 0.5)) <= 0.55 then
                    deferPlantTile(state,point,"not permitted")
                    savePlantResume(state)
                    cursor = cursor + 1
                end
                return true
            end
            local pending = state.pending or {world = name, x = point.x, y = point.y, before = available, tiles = {}}
            table.insert(pending.tiles, {x = point.x, y = point.y})
            state.pending = pending
            savePlantResume(state) -- Persist every attempted tile before the native action.
            r.handlers.plantSeed(id, point.x, point.y)
            checkpoint(token)
            worldCheck(name, token)
            lastPlant, nextPlant = os.clock(), os.clock() + math.max(0.15, App.config.options.placeDelay)
            cursor = cursor + 1
            if tileAt(point.x, point.y) ~= id then confirm() end
            return true
        end
        local destination, stepFailed = points[#points], false
        local ok, issue = pcall(moveTo, destination.x, row.y, name, token, function(avatar)
            local succeeded, proceed = pcall(step, avatar)
            if not succeeded then stepFailed = true; error(proceed, 0) end
            return proceed
        end)
        checkpoint(token)
        worldCheck(name, token)
        if not ok and stepFailed then error(issue, 0) end
        confirm()
        if not ok then error(issue, 0) end
        -- Any missed cells (slow replies, obstacles or small native reach) are
        -- visited by the existing precise per-tile fallback in zigzag order.
    end)
end
-- Rotation keeps harvest planting separate from the later refill/replant task.
-- Native harvesting and planting both change foreground optimistically, so
-- leave a correction window before replanting and confirm bounded seed batches.
makeHarvestPlanter = function(token)
    local rotation, id = App.rotationState, App.config.planting.seedId
    local name = App.config.planting.worlds[rotation.worldIndex]
    local r = worldCheck(name, token)
    assert(r.handlers and type(r.handlers.plantSeed) == "function" and type(r.handlers.canPlace) == "function",
        "Planting hooks are unavailable for harvest replanting.")
    local state = rotation.harvestPlant or {worldIndex=rotation.worldIndex, phase="farm", skipped={}}
    assert(state.worldIndex == rotation.worldIndex, "Harvest planting belongs to a different farm. Check saved rotation.")
    rotation.harvestPlant = state
    local function save() saveRotationResume(rotation) end
    if state.pending then
        confirmPlantBatch(state,token,save)
    end
    local available, nextPlant, lastPlant = refreshInventory(token)[id] or 0, 0, 0
    local function confirm()
        if state.pending then available=confirmPlantBatch(state,token,save,lastPlant) end
    end
    local function seedsLeft()
        return available - (state.pending and #state.pending.tiles or 0)
    end
    local function plant(point)
        worldCheck(name, token)
        if state.pending and state.pending.y ~= point.y then confirm() end
        if seedsLeft() == 0 then confirm() end
        if available == 0 or not Core.plantingTile(r.world, r.items, point.x, point.y)
            or not r.handlers.canPlace(r.items[id], point.x, point.y) or UserInputService:GetFocusedTextBox() then return false end
        local hold = takeControls()
        if os.clock() < nextPlant then
            hold.direction, hold.jump = 0, false
            pause(nextPlant - os.clock(), token)
            worldCheck(name, token)
            if not Core.plantingTile(r.world, r.items, point.x, point.y)
                or not r.handlers.canPlace(r.items[id], point.x, point.y) then return false end
        end
        local pending = state.pending or {world=name, x=point.x, y=point.y, before=available, tiles={}}
        table.insert(pending.tiles, {x=point.x, y=point.y})
        state.pending = pending
        save() -- Save before the native seed action, including when planting from below.
        r.handlers.plantSeed(id, point.x, point.y)
        checkpoint(token)
        worldCheck(name, token)
        lastPlant, nextPlant = os.clock(), os.clock() + math.max(0.15, App.config.options.placeDelay)
        if #pending.tiles >= 8 or seedsLeft() == 0 or tileAt(point.x, point.y) ~= id then confirm() end
        return true
    end
    return {plant=plant, finish=confirm, step=function(row, points, countTree)
        worldCheck(name, token)
        local current=position()
        for _,point in ipairs(plantRetryTargets(row,state)) do
            local anchor=math.max(row.left,math.min(row.right,point.x))
            if current.grounded and math.abs(current.y-(row.y+1))<=0.22 and math.abs(current.x-(anchor+0.5))<=0.55 then
                confirm()
                retryPlantFromBelow(row,state,token,save)
                available=count(id)
                break
            end
        end
        if seedsLeft() == 0 then confirm() end
        if available == 0 then return end -- Finish harvesting; normal replanting handles restocks.
        local avatar = position()
        if not avatar.grounded or math.abs(avatar.y - (row.y + 1)) > 0.22 then return end
        for _, point in ipairs(points) do
            if not point.done then
                if tileAt(point.x, point.y) == 0 then
                    point.clearedAt = point.clearedAt or os.clock()
                    local behind = (avatar.x - (point.x + 0.5)) * row.direction
                    if behind >= 0.25 and behind <= 1.7 then
                        if os.clock() - point.clearedAt < 0.25 or os.clock() < nextPlant then
                            if behind >= 1.2 then return "hold" end
                        elseif Core.plantingTile(r.world, r.items, point.x, point.y)
                            and r.handlers.canPlace(r.items[id], point.x, point.y) then
                            countTree(point)
                            plant(point)
                            return
                        end
                    end
                else point.clearedAt = nil end
            end
        end
    end}
end
local function rotationFarmStatus(r, box, id, seedId, token)
    local growing, ripeCount, remaining = Core.treeGrowth(r.world, seedId, r.treeRipe, r.treeRemaining,
        function() pause(0, token); worldCheck(box.world, token) end)
    App.harvestMaturity = box.world .. ": " .. ripeCount .. " ripe; " .. growing .. " growing"
    local stock = storageCount(box, id, seedId) > 0 or storageCount(box, seedId, id) > 0
    for _, drop in pairs(r.world.dropList()) do
        if not drop.display and (drop.id == id or drop.id == seedId or drop.id == 112) and (drop.n or 0) > 0
            and not harvestDropDeferred(box.world, drop) then stock = true end
    end
    -- Existing harvest can supply PNB without breaking any of the growing trees.
    return growing, growing == 0 and (ripeCount > 0 or stock), remaining, stock
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
            local r, refill, streamedRows = runtime(), false, {}
            if not state.rows then state.rows = Core.farmRows(r.world, r.items); savePlantResume(state) end
            for _, row in ipairs(state.rows) do
                assert(row.y < r.world.h - 1 and row.right < r.world.w, "Saved farm rows no longer fit this world. Clear saved planting and start again.")
            end
            setStatus("Planting " .. r.items[id].name .. " in " .. name .. " (" .. state.worldIndex .. "/" .. #settings.worlds .. ")...")
            local visits={}
            for index,row in ipairs(state.rows) do
                row.direction=index%2==1 and 1 or -1
                -- Even a full/empty lower row may be the approach for an upper
                -- rejected tile. Determine that work when we reach this row.
                table.insert(visits,{retryRow=row})
                for x=row.direction==1 and row.left or row.right,row.direction==1 and row.right or row.left,row.direction do
                    if Core.plantingTile(r.world,r.items,x,row.y) then table.insert(visits,{x=x,y=row.y}) end
                end
            end
            for _, point in ipairs(visits) do
                checkpoint(token)
                worldCheck(name, token)
                local key=not point.retryRow and point.x .. ":" .. point.y
                if point.retryRow then
                    local row=point.retryRow
                    local targets=plantRetryTargets(row,state)
                    if #targets>0 and not Core.rowHasPlantingSpace(r.world,r.items,row,state.skipped) then
                        if count(id)==0 then refill=true; break end
                        local arrived,issue=pcall(function()
                            local first,last=targets[1],targets[#targets]
                            moveTo(math.max(row.left,math.min(row.right,first.x)),row.y,name,token)
                            moveTo(math.max(row.left,math.min(row.right,last.x)),row.y,name,token,function()
                                retryPlantFromBelow(row,state,token)
                                return count(id)>0 and #plantRetryTargets(row,state)>0
                            end)
                        end)
                        checkpoint(token)
                        worldCheck(name,token)
                        if not arrived then
                            if state.pending or type(issue)=="table" and issue.recoverable then error(issue,0) end
                            local text=tostring(issue)
                            assert(text:find("route",1,true) or text:find("position",1,true) or text:find("support",1,true)
                                or text:find("platform",1,true) or text:find("timed out",1,true),text)
                            for _,target in ipairs(targets) do
                                target.tries=1
                                state.skipped[target.x .. ":" .. target.y]="lower-row approach unreachable"
                            end
                            savePlantResume(state)
                        end
                    end
                elseif not state.skipped[key] and Core.plantingTile(r.world, r.items, point.x, point.y) then
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
                            if not streamedRows[point.y] then
                                streamedRows[point.y] = true
                                for index, row in ipairs(state.rows) do
                                    if row.y == point.y then plantRow(row, index % 2 == 0, state, token); break end
                                end
                            end
                            if not state.skipped[key] and Core.plantingTile(r.world, r.items, point.x, point.y) then moveTo(point.x, point.y, name, token) end
                        end)
                    end
                    checkpoint(token)
                    worldCheck(name, token)
                    if not arrived then
                        -- A request timeout during batch confirmation must never
                        -- be treated as an unreachable tile and overwrite cargo.
                        if state.pending then error(issue, 0) end
                        if type(issue) == "table" and issue.recoverable then error(issue, 0) end
                        local text = tostring(issue)
                        assert(text:find("route", 1, true) or text:find("position", 1, true) or text:find("support", 1, true)
                            or text:find("platform", 1, true) or text:find("timed out", 1, true), text)
                        if Core.plantingTile(r.world, r.items, point.x, point.y) then deferPlantTile(state,point,"unreachable") end
                    elseif not permitted or (not state.skipped[key] and Core.plantingTile(r.world, r.items, point.x, point.y)
                        and count(id) > 0 and not plantTile(point, state, token)) then
                        deferPlantTile(state,point,state.skipped[key] or "not permitted")
                    end
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
                    local growing, crop, left, stock = rotationFarmStatus(r, App.config.rotation.farms[name], App.config.blockId, id, token)
                    rotation.readyAt[name] = growing > 0 and not crop and not stock and Workspace:GetServerTimeNow() + left or 0
                    rotation.emptyChecks = rotation.emptyChecks or {}
                    rotation.emptyChecks[name] = true
                end
                setStatus("Processed " .. name .. ": " .. skipped .. " tiles skipped due to access or route. Moving to the next farm.")
                state.worldIndex, state.skipped, state.rows, state.rowY, state.deferred = state.worldIndex + 1, {}, nil, nil, {}
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
    if App.job == "botting" and App.botState then
        App.botState.rotation, App.botState.deferredHarvest = state, state.deferredHarvest
        App.rotationState = state; App.botting.save(); return
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, item in pairs(value) do result[key] = copy(item) end
        return result
    end
    saveSession()
    writeJSON(ROTATION_RESUME_FILE, {version = 1, active = true, userId = ACCOUNT_ID, updatedAt = os.time(),
        config = Core.validate(App.config), profile = App.profile, state = copy(state)})
    App.rotationState = state
    App.lastRotationSave = os.clock()
end
local function readRotationResume()
    if not exists(ROTATION_RESUME_FILE) then return nil end
    local record = decode(readfile(ROTATION_RESUME_FILE))
    if not record.active then return nil end
    assert(record.version == 1 and record.userId == ACCOUNT_ID, "The saved rotation belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600, "Saved rotation is over six hours old. Check inventory and start again.")
    record.config, record.profile = Core.validate(record.config), Core.profileName(record.profile)
    local state = record.state
    local phases = {plant=true, wait=true, waitPNB=true, checkSeeds=true, drainPNB=true, pnbStorePending=true, replant=true, harvest=true, harvestStock=true, harvestPickupPending=true, transfer=true, seeds=true, seedDeliver=true,
        seedPickupPending=true, seedDepositPending=true, pnb=true, finish=true}
    assert(type(state) == "table" and phases[state.phase], "Invalid saved rotation phase.")
    for _, key in ipairs({"worldIndex", "cycle", "work", "seedCargo"}) do
        assert(type(state[key]) == "number" and state[key] >= 0 and state[key] == math.floor(state[key]), "Invalid saved rotation progress.")
    end
    assert(state.worldIndex >= 1 and state.worldIndex <= #record.config.planting.worlds and state.seedCargo <= 200,
        "Invalid saved rotation farm or seed cargo.")
    for _, key in ipairs({"completed", "readyAt", "emptyChecks"}) do
        if state[key] ~= nil then
            assert(type(state[key]) == "table", "Invalid saved rotation schedule.")
            for index, value in pairs(state[key]) do
                assert(type(index) == "string" and record.config.rotation.farms[index], "Invalid saved rotation scheduled farm.")
                assert(key ~= "readyAt" and type(value) == "boolean"
                    or key == "readyAt" and type(value) == "number" and value == value and value >= 0 and value < math.huge,
                    "Invalid saved rotation schedule value.")
            end
        end
    end
    if state.seedWait ~= nil then assert(type(state.seedWait) == "boolean", "Invalid saved rotation seed wait.") end
    if state.pnbEmpty ~= nil then assert(type(state.pnbEmpty) == "boolean", "Invalid saved PNB supply state.") end
    if state.deferredHarvest ~= nil then
        assert(type(state.deferredHarvest) == "table", "Invalid saved deferred harvest drops.")
        for name, drops in pairs(state.deferredHarvest) do
            assert(record.config.rotation.farms[name] and type(drops) == "table", "Invalid saved deferred harvest farm.")
            for uid, drop in pairs(drops) do
                assert(type(uid) == "string" and uid:match("^%d+$") and type(drop) == "table"
                    and type(drop.id) == "number" and drop.id > 0 and drop.id == math.floor(drop.id), "Invalid saved deferred harvest drop.")
                for _, key in ipairs({"x", "y", "retryAt"}) do
                    local value = drop[key]
                    assert(type(value) == "number" and value == value and value >= 0 and value < math.huge,
                        "Invalid saved deferred harvest location or time.")
                end
            end
        end
    end
    if state.collectOnly ~= nil then
        assert(type(state.collectOnly) == "boolean", "Invalid saved stock collection state.")
        if state.collectOnly then
            assert(({harvest=true,transfer=true,seeds=true,seedDeliver=true,seedPickupPending=true,seedDepositPending=true})[state.phase],
                "Stock collection belongs to a different rotation phase.")
            assert(state.phase ~= "harvest" or state.harvestPass and state.harvestPass.phase == "collect",
                "Stock collection cannot start a tree harvest.")
        end
    end
    if state.harvestPass then
        local pass = state.harvestPass
        assert(type(pass) == "table" and state.phase == "harvest"
            and pass.world == record.config.planting.worlds[state.worldIndex]
            and (pass.phase == "trees" or pass.phase == "collect"), "Invalid saved harvest pass.")
        assert(pass.phase ~= "collect" or not state.harvestPlant or not state.harvestPlant.pending,
            "A saved harvest collection pass has an unconfirmed planting batch.")
    end
    if state.plant then
        readPlantResume({version=1, active=true, userId=record.userId, updatedAt=record.updatedAt,
            config=record.config, profile=record.profile, state=state.plant})
    end
    if state.harvestPlant then
        assert(type(state.harvestPlant) == "table" and state.phase == "harvest" and state.harvestPlant.worldIndex == state.worldIndex
            and state.harvestPlant.phase == "farm", "Invalid saved harvest planting progress.")
        assert(not state.harvestPlant.pending or type(state.harvestPlant.pending.tiles) == "table",
            "Missing saved harvest planting batch.")
        readPlantResume({version=1, active=true, userId=record.userId, updatedAt=record.updatedAt,
            config=record.config, profile=record.profile, state=state.harvestPlant})
    end
    if state.transfer then
        local t = state.transfer
        assert(type(t) == "table" and ({pickup=true, deliver=true, returnSeeds=true, ["return"]=true,
            pickupPending=true, depositPending=true, seedReturnPending=true})[t.phase]
            and type(t.cargo) == "number" and t.cargo >= 0 and t.cargo <= 200 and t.cargo == math.floor(t.cargo)
            and type(t.seeds) == "number" and t.seeds >= 0 and t.seeds <= 200 and t.seeds == math.floor(t.seeds),
            "Invalid saved rotation transfer.")
        assert(t.item == nil or t.item == "blocks", "Rotation transfer must carry blocks.")
        assert(t.companion == nil or type(t.companion) == "number" and t.companion >= 0
            and t.companion <= 200 and t.companion == math.floor(t.companion), "Invalid saved rotation companion items.")
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
    state.emptyChecks = state.emptyChecks or {}
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
    local function afterPlant()
        if state.seedWait then transition("drainPNB")
        elseif count(seedId) == 0 then transition("checkSeeds")
        else continueFarms() end
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
            assert(state.phase ~= "harvestPickupPending", "A harvest seed withdrawal was interrupted. Check the backpack and PNB seed box, then clear saved rotation.")
            if state.transfer then assert(state.transfer.phase ~= "pickupPending" and state.transfer.phase ~= "depositPending"
                and state.transfer.phase ~= "seedReturnPending",
                "A rotation transfer storage request was interrupted. Check the backpack and boxes, then clear saved rotation.") end
            local ok, problem = pcall(function()
                local name = settings.worlds[state.worldIndex]
                p.farmBox = App.config.rotation.farms[name]
                if state.phase == "plant" then
                    if not state.plant then state.completed, state.readyAt, state.emptyChecks = {}, {}, {} end
                    state.seedWait = not runPlant(token, state.plant and {state=state.plant} or nil)
                    state.plant = nil
                    clearPlantResume()
                    local index = nextFarm()
                    state.worldIndex = index or 1
                    afterPlant()
                elseif state.phase == "checkSeeds" then
                    travel(p.pnb.world)
                    refreshInventory(token)
                    if count(seedId) == 0 and storageCount(p.seedBox, seedId) == 0 then
                        transition("drainPNB")
                    else continueFarms() end
                elseif state.phase == "wait" then
                    travel(name)
                    local r = worldCheck(name, token)
                    local growing, crop, remaining, stock = rotationFarmStatus(r, p.farmBox, id, seedId, token)
                    state.emptyChecks[name] = true
                    if crop then
                        state.readyAt[name] = nil
                        transition(App.config.options.harvestPlanting and "harvestStock" or "harvest")
                    elseif stock then
                        state.readyAt[name] = growing > 0 and Workspace:GetServerTimeNow() + remaining or 0
                        state.collectOnly = true
                        state.harvestPass = {world=name,phase="collect"}
                        setStatus("Collecting existing drops and stored harvest from " .. name .. " while trees grow...")
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
                elseif state.phase == "waitPNB" or state.phase == "drainPNB" then
                    travel(p.pnb.world)
                    takeControls()
                    refreshInventory(token)
                    local hasWork = count(id) > 0 or storageCount(p.blockBox,id) > 0
                    for _, point in ipairs(Core.grid(p.pnb)) do
                        if tileAt(point.x,point.y) ~= 0 then hasWork = true end
                    end
                    for _, drop in pairs(runtime().world.dropList()) do
                        if not drop.display and (drop.id == id or drop.id == seedId or drop.id == 112) and (drop.n or 0) > 0
                            and math.abs(drop.x-(p.pnb.x+0.5)) <= 1.25
                            and drop.y >= p.pnb.y-1.5 and drop.y <= p.pnb.y+1.25 then hasWork = true end
                    end
                    if hasWork then state.pnbEmpty, state.emptyChecks = false, {} end
                    if state.phase == "waitPNB" then
                        if not state.pnbEmpty and count(seedId) == 0 and storageCount(p.seedBox, seedId) == 0 then transition("drainPNB") end
                    end
                    local draining = state.phase == "drainPNB"
                    if draining then setStatus("Seed supply exhausted: finishing all PNB blocks before planting or harvesting.") end
                    local brokenBefore = App.stats.broken
                    local exhausted = state.pnbEmpty and not hasWork or runPNB(token, not draining and yieldPNB or nil)
                    state.pnbEmpty = exhausted == true
                    state.work = state.work + App.stats.broken - brokenBefore
                    storePNBInventory()
                    if draining then
                        assert(exhausted, "PNB drain ended before the block supply was exhausted.")
                        transition("waitPNB")
                        setStatus("PNB block supply finished. Resuming farm planting and harvest scheduling.")
                    end
                    local index, deadline = nextFarm()
                    local stockIndex
                    if exhausted then
                        -- Check each waiting farm once when PNB runs empty, even
                        -- if an older checkpoint saved a future maturity deadline.
                        for candidate, farm in ipairs(settings.worlds) do
                            if not state.completed[farm] and not state.emptyChecks[farm] then stockIndex=candidate; break end
                        end
                    end
                    if index and deadline <= Workspace:GetServerTimeNow() then
                        state.worldIndex = index
                        transition("wait")
                    elseif state.seedWait and storageCount(p.seedBox, seedId) > 0 then
                        transition("plant")
                    elseif stockIndex then
                        state.worldIndex = stockIndex
                        setStatus("PNB is empty; checking " .. settings.worlds[stockIndex] .. " for existing harvest...")
                        transition("wait")
                    elseif exhausted and not index then
                        state.seedWait = false
                        transition("finish")
                    elseif exhausted then
                        releaseControls()
                        setStatus("Rotation " .. state.cycle .. ": waiting for growing trees; PNB block storage is empty.")
                        saveRotationResume(state)
                        pause(math.min(5, math.max(0.1, deadline - Workspace:GetServerTimeNow())), token)
                    end
                elseif state.phase == "harvestStock" then
                    refreshInventory(token)
                    -- Carry stock before the pass. Never leave a row mid-pass
                    -- for a refill; the normal replant phase fills any leftovers.
                    if runtime().inventory:room(seedId) > 0 then
                        travel(p.seedBox.world)
                        if storageCount(p.seedBox, seedId) > 0 then
                            transition("harvestPickupPending")
                            withdraw(p.seedBox, seedId, token)
                        end
                    end
                    transition("harvest")
                elseif state.phase == "harvest" then
                    travel(name)
                    takeControls()
                    local harvested = runHarvest(token)
                    state.harvestPlant = nil
                    state.harvestPass = nil
                    if harvested == false then
                        state.collectOnly = nil
                        -- Recheck after reload/refill as well as scheduled entry.
                        -- New growing trees defer this farm to the normal PNB wait.
                        state.readyAt[name] = nil
                        transition("wait")
                    else
                        state.work = state.work + storageCount(p.farmBox, id, seedId) + storageCount(p.farmBox, seedId, id)
                        transition("transfer")
                    end
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
                    if storageCount(p.farmBox, seedId, id) == 0 then
                        if state.collectOnly then
                            state.collectOnly = nil
                            continueFarms() -- Keep this farm scheduled for its real tree harvest.
                        else transition("replant") end
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
                    afterPlant()
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
                if state.phase == "pnb" or state.phase == "waitPNB" or state.phase == "drainPNB" then problem = classifyPNBFault(problem, token) end
                assert(state.phase ~= "seedPickupPending" and state.phase ~= "seedDepositPending" and state.phase ~= "pnbStorePending" and state.phase ~= "harvestPickupPending"
                    and (not state.transfer or state.transfer.phase ~= "pickupPending" and state.transfer.phase ~= "depositPending"
                        and state.transfer.phase ~= "seedReturnPending"),
                    "A rotation storage request was interrupted. Check the backpack and boxes before resuming. " .. tostring(problem))
                local moving=transientRouteFault(problem) and App.pending==0
                    and not (state.plant and state.plant.pending) and not (state.harvestPlant and state.harvestPlant.pending)
                if moving then
                    releaseControls()
                    saveRotationResume(state)
                    App.navigationRecovery="Retrying rotation phase " .. state.phase .. " after a movement timeout"
                    setStatus(App.navigationRecovery .. "; trying again in 5s.")
                    pause(5,token)
                else
                    assert(App.config.options.autoRejoin and type(problem) == "table" and problem.recoverable, tostring(problem))
                    failures = failures + 1
                    assert(failures <= 3, "Rotation recovery failed three times. Check connection and copy diagnostics.")
                    releaseControls()
                    setStatus("Rotation interrupted; returning to the saved phase...")
                    if state.phase == "pnb" or state.phase == "waitPNB" or state.phase == "drainPNB" then
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
        end
    end)
end

function App:stop()
    self.token = self.token + 1
    self.teleporting = false
    self.recovering = false
    syncRunToggles()
    releaseControls()
    if self.botting then self.botting.stop() end
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
    restoreFPSBooster()
    if self.idleConnection then self.idleConnection:Disconnect(); self.idleConnection = nil end
    if self.window then pcall(function() self.window:Destroy() end) end
    if env.ClarisGrowbloxApp == self then env.ClarisGrowbloxApp = nil end
end
local function start(mode, saved)
    idle()
    local r = runtime()
    if r.farmingDeferred and (mode == "pnb" or mode == "plant" or mode == "rotation" or mode == "botting") then
        setStatus("Connecting " .. (mode == "pnb" and "Place & Break" or "Planting") .. " hooks...")
        releaseControls()
        App.configuring = true
        local ok, result = pcall(connectGame)
        App.configuring = false
        if not ok then error(result, 0) end
        r = result
    end
    if mode == "harvest" or mode == "plant" or mode == "rotation" or mode == "botting" then
        assert(r.body and r.controls and type(r.inventory.room) == "function" and type(r.inventory.add) == "function"
            and type(r.inventory.remove) == "function", "Collection and planting need the live backpack and movement hooks.")
        if mode == "plant" or mode == "rotation" or mode == "botting" then assert(r.handlers and type(r.handlers.canPlace) == "function" and type(r.handlers.plantSeed) == "function",
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
            elseif mode == "botting" then
                harvestEquipmentScope(function() suspendHarvestVehicle(token); App.botting.run(token, saved) end)
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
                local harvested = runHarvest(token)
                if harvested ~= false and App.config.options.moveAfterHarvest then
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
        if mode == "botting" then
            App.rotationState, App.botDropFilter = nil, nil
            if App.botState then App.botState.active = false end
            App.botting.poll(true)
        end
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
        or job == "botting" and "Botting"
        or job == "connection" and "Game connection" or job == "resume" and "Resume saved task" or "Off"
    field("Farm status", mode .. (App.recovering and " (recovering)" or "") .. "\n" .. reportText(event and event.message or App.status, 600))
    field("Harvest method", config.harvesting.method == "tractor" and "Dear John Tractor" or "Fist", true)
    if job == "botting" and App.botting then
        field("Botting team", "Role: " .. App.botting.preferences.role .. "; spot " .. App.botting.preferences.spot
            .. "\n" .. reportText(App.botting.debug or "Connecting", 500))
    end
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
    local session = {version = 1, userId = ACCOUNT_ID, config = config, profile = profile}
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
    if App.botting then App.botting.resetImport() end
    App.config, App.profile = config, profile
    App.sessionSignature, App.sessionSaveError, App.sessionRestoreError = signature, nil, nil
    resetWebhookSchedule()
    setStatus("Imported and saved profile: " .. profile .. ". Check locations, then start your task.")
    return profile
end

do
    local Botting = __CLARIS_BOTTING__
    local api = {roleFile = ROOT .. "/botting-role.json", resumeFile = ROOT .. "/botting-resume.json",
        filesystem = filesystem, decode = decode, write = writeJSON, saveSession = saveSession, validate = Core.validate,
        idle = idle, count = count, checkpoint = checkpoint, pause = pause, queue = queueResume, status = setStatus,
        report = function(kind, text) if queueWebhookEvent then queueWebhookEvent(kind, text, "botting") end end,
        halt = function() if App.controls then App.controls.direction, App.controls.jump = 0, false end end,
        level = function() return bounded(runtime().world.call, App.config.options.actionTimeout, nil, "GetLevel") end}
    function api.hasHarvester()
        local r = App.runtime
        if not r then return false end
        for id, item in pairs(r.items) do
            if item.name == "Dear John Tractor" and item.ride == "tractor" and count(id) > 0 then return true end
        end
        return false
    end
    function api.observe()
        local r = App.runtime
        if not r or not r.body or not r.body.state().active then return end
        local name, b = r.world.name, App.config.botting
        local sensor = {world = name, at = os.time()}
        if name == b.world then
            sensor.blocks = storageCount(App.config.points.blockBox, App.config.blockId)
            sensor.seeds = storageCount(App.config.points.seedBox, App.config.planting.seedId)
            sensor.breakingTiles = 0
            for _, spot in ipairs(b.spots) do
                if r.world.fg[spot.y - 1] and r.world.fg[spot.y - 1][spot.x] == App.config.blockId then sensor.breakingTiles = sensor.breakingTiles + 1 end
            end
        elseif App.config.rotation.farms[name] then
            sensor.empty, sensor.loose, sensor.gems = 0, 0, 0
            for _, row in ipairs(Core.farmRows(r.world, r.items)) do
                for x = row.left, row.right do if Core.plantingTile(r.world, r.items, x, row.y) then sensor.empty = sensor.empty + 1 end end
            end
            local ok, growing, ripe, remaining = pcall(Core.treeGrowth, r.world, App.config.planting.seedId, r.treeRipe, r.treeRemaining)
            if ok then sensor.growing, sensor.ripe, sensor.remaining = growing, ripe, remaining end
            for _, drop in pairs(r.world.dropList()) do
                if not drop.display and (drop.n or 0) > 0 and not harvestDropDeferred(name, drop) then
                    if drop.id == App.config.blockId or drop.id == App.config.planting.seedId then sensor.loose = sensor.loose + drop.n
                    elseif drop.id == 112 then sensor.gems = sensor.gems + drop.n end
                end
            end
            local box = App.config.rotation.farms[name]
            sensor.stored = storageCount(box, App.config.blockId, App.config.planting.seedId)
                + storageCount(box, App.config.planting.seedId, App.config.blockId)
        end
        return sensor
    end
    local shortcutAt = 0
    function api.shortcut(token)
        local door, b, r = App.config.points.breakDoor, App.config.botting, runtime()
        if not door or r.world.name ~= b.world or os.clock() < shortcutAt then return end
        local state, distance = position(), math.huge
        for _, spot in ipairs(b.spots) do distance = math.min(distance, math.abs(state.x - (spot.x + 0.5)) + math.abs(state.y - (spot.y + 1))) end
        if distance < 8 then return end
        shortcutAt = os.clock() + 10
        local ok, issue = pcall(function()
            moveToPoint(door, token)
            local metadata = r.items[tileAt(door.x, door.y)]
            assert(metadata and (metadata.door or metadata.entrance or metadata.vip), "Saved BNS shortcut is no longer a door.")
            App.botting.save()
            local accepted, response = bounded(r.world.call, App.config.options.actionTimeout, token, "UseDoor", door.x, door.y)
            assert(accepted and type(response) == "table" and type(response.go) == "table", "BNS door must lead to the breaking lane in this same world.")
            r.world.goTo(response.go[1], response.go[2]); pause(0.15, token)
            App.doorReadyDebug = "BNS same-world shortcut used"
        end)
        checkpoint(token)
        if not ok then App.doorReadyDebug = "BNS door unavailable; walking: " .. tostring(issue) end
    end
    function api.go(name, token)
        suspendHarvestVehicle(token)
        local r = runtime()
        if r.world.name ~= name or pickerOpen(r) or not r.body.state().active or r.body.state().dead then
            enterPlantWorld(name, App.botState and App.botState.plant or {worldIndex = 1, phase = "farm", skipped = {}}, token)
        else takeControls() end
        if name == App.config.botting.world then api.shortcut(token) end
        takeControls().pausePickup = true -- All Botting pickups have one explicit owner.
    end
    local collectAttempts, collectRetry, collectDeferred = {}, {}, {}
    local function collectorAnchor()
        local b = App.config.botting
        if b.collector then return b.collector end
        local sorted = {}
        for _, spot in ipairs(b.spots) do sorted[#sorted + 1] = spot end
        table.sort(sorted, function(a, b) return a.x < b.x end)
        return sorted[math.ceil(#sorted / 2)]
    end
    local function pickupStep(anchor, token, fallback, includeSeeds)
        local r, blockId, seedId = runtime(), App.config.blockId, App.config.planting.seedId
        local function selected(drop)
            return not drop.display and not drop.pending and not drop.taking and (drop.n or 0) > 0
                and (drop.id == 112 or drop.id == blockId or includeSeeds and drop.id == seedId)
                and os.clock() >= (collectDeferred[drop.uid] or 0)
                and type(drop.x) == "number" and type(drop.y) == "number"
                and drop.y >= anchor.y - 1.5 and drop.y <= anchor.y + 1.25
        end
        local minX, maxX = anchor.x - 1.25, anchor.x + 1.75
        if fallback then
            for _, spot in ipairs(App.config.botting.spots) do minX = math.min(minX, spot.x - 0.75); maxX = math.max(maxX, spot.x + 1.75) end
        end
        local targets, far
        targets = {}
        local state = position()
        for _, drop in pairs(r.world.dropList()) do
            if selected(drop) and drop.x >= minX and drop.x <= maxX then
                local near = math.abs(drop.x - state.x) <= 1.25 and drop.y >= state.y - 2.5 and drop.y <= state.y + 0.25
                if near and (collectAttempts[drop.uid] or 0) < 3 and os.clock() >= math.max(drop.readyAt or 0, collectRetry[drop.uid] or 0) then
                    targets[#targets + 1] = drop
                elseif fallback and (not near or (collectAttempts[drop.uid] or 0) >= 3) then far = far or drop end
            end
        end
        if #targets > 0 then
            takeDropBatch(anchor, targets, collectAttempts, collectRetry, selected, token)
            refreshInventory(token)
        elseif far then
            local goal = Navigation.pickupGoal(navigationMap(r), state, far, {nativeOnly = true})
            if goal then
                moveTo(goal.x, goal.y, anchor.world, token)
                collectAttempts[far.uid], collectRetry[far.uid] = 0, 0
                local results = takeDropBatch(anchor, {far}, collectAttempts, collectRetry, selected, token)
                if results[1] and results[1].amount == 0 then collectDeferred[far.uid] = os.clock() + 5 end
                refreshInventory(token)
            else
                collectDeferred[far.uid] = os.clock() + 300
                App.harvestCollectionRecovery = "BNS drop " .. far.uid .. " deferred; no reachable supported pickup spot"
            end
        end
    end
    local function unloadBNS(token, seedsOnly)
        local p, id, seed = App.config.points, App.config.blockId, App.config.planting.seedId
        api.go(App.config.botting.world, token)
        refreshInventory(token)
        local blocks, seeds = count(id), count(seed)
        if not seedsOnly and blocks > 0 then deposit(p.blockBox, id, blocks, token) end
        if seeds > 0 and App.botting.level >= 10 then deposit(p.seedBox, seed, seeds, token) end
        return blocks, seeds
    end
    function api.breakStep(token, collectOwn)
        local spot = App.config.botting.spots[App.botting.preferences.spot]
        api.go(spot.world, token); moveToPoint(spot, token)
        refreshInventory(token)
        if App.botting.level >= 10 and count(App.config.planting.seedId) >= App.config.options.seedThreshold then
            unloadBNS(token, true); moveToPoint(spot, token)
        end
        local id, target = App.config.blockId, {x = spot.x, y = spot.y - 1}
        if tileAt(target.x, target.y) == 0 and count(id) == 0 then
            local taken = withdraw(App.config.points.blockBox, id, token)
            if taken == 0 then setStatus("Botting: BNS block storage is empty; waiting for farm supply."); pause(1, token); return end
            moveToPoint(spot, token)
        end
        local oldPNB = App.config.points.pnb
        App.config.points.pnb = spot
        local ok, issue = pcall(function()
            local cell = tileAt(target.x, target.y)
            assert(cell == 0 or cell == id, "Clear the tile above this Botting breaker spot.")
            if cell == 0 then placeTile(target, id, token) end
            if tileAt(target.x, target.y) == id then breakTile(target, id, token) end
        end)
        App.config.points.pnb = oldPNB
        if not ok then error(issue, 0) end
        if collectOwn then pickupStep(spot, token, false, App.botting.level >= 10) end
    end
    function api.collectBNS(token, alsoBreak)
        local anchor = alsoBreak and App.config.botting.spots[App.botting.preferences.spot] or collectorAnchor()
        moveToPoint(anchor, token)
        if alsoBreak then api.breakStep(token, false) end
        pickupStep(anchor, token, true, true)
        if count(App.config.blockId) >= 200 or count(App.config.planting.seedId) >= App.config.options.seedThreshold then
            unloadBNS(token); moveToPoint(anchor, token)
        end
        if App.status ~= "Botting Collector: collecting nearby blocks, seeds and gems; breakers continue." then
            setStatus("Botting Collector: collecting nearby blocks, seeds and gems; breakers continue.")
        end
        pause(0.1, token)
    end
    local function farmScope(job, token, fn)
        local oldBox, oldRotation, oldFilter = App.config.points.farmBox, App.rotationState, App.botDropFilter
        App.config.points.farmBox = App.config.rotation.farms[job.world]
        local state = App.botState
        state.rotation = state.rotation or {phase = "harvest", cycle = 1, worldIndex = 1, work = 0, seedCargo = 0}
        state.rotation.deferredHarvest = state.deferredHarvest or state.rotation.deferredHarvest or {}
        for index, world in ipairs(App.config.planting.worlds) do if world == job.world then state.rotation.worldIndex = index end end
        App.rotationState = state.rotation
        local result = table.pack(pcall(function() return harvestEquipmentScope(function() suspendHarvestVehicle(token); return fn() end) end))
        App.config.points.farmBox, App.rotationState, App.botDropFilter = oldBox, oldRotation, oldFilter
        if not result[1] then error(result[2], 0) end
        return table.unpack(result, 2, result.n)
    end
    function api.harvest(job, token)
        return farmScope(job, token, function()
            if job.approved and not App.rotationState.harvestPass then App.rotationState.harvestPass = {world = job.world, phase = "trees"} end
            return withoutPickups(function() return runTreeHarvest(token) end)
        end)
    end
    function api.transferBoth(job, token)
        local source = App.config.rotation.farms[job.world]
        local state, id, seed = App.botState, App.config.blockId, App.config.planting.seedId
        state.phase = state.phase or "source"
        while true do
            checkpoint(token)
            if state.phase == "source" then
                api.go(source.world, token); refreshInventory(token)
                if count(id) > 0 or count(seed) > 0 then state.phase = "deliver"
                else
                    local blocks, seeds = storageCount(source, id, seed), storageCount(source, seed, id)
                    if blocks == 0 and seeds == 0 then state.phase = nil; App.botting.save(); return end
                    local primary, companion = blocks > 0 and id or seed, blocks > 0 and seed or id
                    withdraw(source, primary, token, companion)
                    state.phase = "deliver"
                end
                App.botting.save()
            elseif state.phase == "deliver" then
                local blocks = unloadBNS(token)
                App.stats.moved = App.stats.moved + blocks
                App.stats.trips = App.stats.trips + 1
                state.phase = "source"; App.botting.save()
            else error("Invalid Botting mixed transfer phase.") end
        end
    end
    function api.collectFarm(job, token)
        if not App.botState.phase then
            farmScope(job, token, function()
                App.rotationState.harvestPass = {world = job.world, phase = "collect"}
                local rows = Core.farmRows(runtime().world, runtime().items)
                App.botDropFilter = function(drop)
                    local nearest, distance
                    for index, row in ipairs(rows) do
                        local delta = math.abs(drop.y - (row.y + 0.5))
                        if not distance or delta < distance then nearest, distance = index, delta end
                    end
                    local group = nearest and distance <= 1.5 and nearest - 1 or drop.uid
                    return group % job.partitions == job.partition - 1
                end
                runHarvest(token)
            end)
            App.botState.phase = "source"; App.botting.save()
        end
        api.transferBoth(job, token)
    end
    function api.plant(job, token)
        local index
        for i, world in ipairs(App.config.planting.worlds) do if world == job.world then index = i end end
        local state = App.botState.plant or {worldIndex = index, phase = "farm", skipped = {}}
        App.rotationState = nil
        local result = runPlant(token, {state = state}, index)
        App.plantState = nil
        return result
    end
    App.botting = Botting.new(App, api)
    api.flushCargo = unloadBNS
    App.botting.shortcut, App.botting.api = api.shortcut, api
end

local migrationOK, migrationProblem = pcall(migrateLegacyStorage)
App.storageMigrationError = not migrationOK and tostring(migrationProblem) or nil
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
        pollFPSBooster = pollFPSBooster, restoreFPSBooster = restoreFPSBooster,
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
ui.bottingTab = window:Tab({ Title = "Botting", Icon = "users" })
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
    local point = key == "moveBox" and Core.transferDestination(App.config) or App.config.points[key]
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
    if ui.movingBlock then
        ui.movingBlock.Value = selectedLabel
        ui.movingBlock:Refresh(labels)
    end
end
local function chooseBlock(label)
    if App.syncingUI then return end
    local id = blockLabels[label]
    if id then
        if App.job or App.configuring or App.pending > 0 then
            notify("Stop the task before selecting another block.")
            return
        end
        App.config.blockId = id
        local previous = App.syncingUI
        App.syncingUI = true
        local ok, issue = pcall(function()
            blockDropdown:Select(label)
            if ui.movingBlock then ui.movingBlock:Select(label) end
        end)
        App.syncingUI = previous
        if not ok then error(issue, 0) end
    end
end
ui.points, ui.pointTitles = {}, {
    pnb = "PNB spot", blockBox = "Block storage (breaking world)", seedBox = "Seed storage (left box)",
    farmBox = "Farm storage", farmDoor = "Farm door to breaking world", breakDoor = "Breaking door to farm world",
    plantBox = "Planting seed storage", moveBox = "Destination Display Box",
}
ui.status = pnbTab:Paragraph({ Title = "Status", Desc = App.status })
blockDropdown = pnbTab:Dropdown({
    Title = "Block to farm", Desc = "Select a block from your backpack; this also selects the Moving Drops block.",
    Values = {}, SearchBarEnabled = true,
    Callback = chooseBlock,
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
transferTab:Paragraph({ Title = "Moving Drops setup", Desc = "Choose your crop and whether to move Blocks or Seeds. Save the Farm and destination Display Boxes. Moving Drops enters their worlds directly; start in either world. Mixed farm boxes are supported: only the chosen type reaches the destination, and held companion items return to the Farm box after the last trip." })
ui.movingBlock = transferTab:Dropdown({ Title = "Crop to move", Values = {}, SearchBarEnabled = true,
    Desc = "Uses the same selected crop as Place & Break and Harvest Drops.", Callback = chooseBlock })
transferTab:Button({ Title = "Refresh crop choices", Callback = uiAction(refreshBlocks) })
ui.movingItem = transferTab:Dropdown({ Title = "Item to move", Values = {"Blocks", "Seeds"},
    Value = App.config.moving.item == "seeds" and "Seeds" or "Blocks",
    Callback = function(value)
        if type(value) == "table" then value = value[1] end
        if App.syncingUI then return end
        if App.job or App.configuring or App.pending > 0 then
            notify("Stop the task before changing the transfer item.")
            App.syncingUI = true
            ui.movingItem:Select(App.config.moving.item == "seeds" and "Seeds" or "Blocks")
            App.syncingUI = false
            return
        end
        assert(value == "Blocks" or value == "Seeds", "Choose Blocks or Seeds.")
        App.config.moving.item = value == "Seeds" and "seeds" or "blocks"
        updatePoints()
        saveSession()
    end })
for _, key in ipairs({ "farmBox", "moveBox" }) do
    ui.points[key] = transferTab:Paragraph({ Title = ui.pointTitles[key], Desc = "Not saved" })
    local pointKey = key
    transferTab:Button({ Title = "Save " .. ui.pointTitles[key], Desc = "Stand beside the target and press Save.",
        Callback = uiAction(function() captureNearby(pointKey, "box") end) })
end
transferTab:Paragraph({ Title = "Destination storage", Desc = "Save the box you want to receive the chosen item. Existing configurations use PNB block storage for Blocks or PNB seed storage for Seeds until you save a destination here. Use separate PNB boxes for blocks and seeds when running Full Rotation." })
App.runToggles.transfer = transferTab:Toggle({ Title = "Moving Drops", Value = false,
    Desc = "On moves the chosen blocks or seeds. Off stops it. Turns off automatically when the task ends.",
    Callback = function(enabled) setRunningEnabled("transfer", enabled) end })

local selectedProfile, profileNameInput, profileDropdown = nil, nil, nil
local settingsControls = {}
ui.harvestStatus = harvestTab:Paragraph({ Title = "Status", Desc = App.status })
harvestTab:Paragraph({ Title = "Harvest trees and collect drops", Desc = "Start only when every tree of the selected crop in this world is fully grown. Then break trees and collect matching blocks, seeds and gems: left to right, down to the next occupied row, then right to left. Slow pickups settle before leaving reach. Blocks and seeds share the Farm Display Box; gems update your balance. Rotation defers inaccessible drops and transfers stored harvest while growing farms wait." })
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
harvestTab:Paragraph({ Title = "Dear John Tractor", Desc = "Keep the tractor in your backpack. Drive each row once and collect nearby gems while harvesting, then clear misses with Fist from a lower row where reachable. Blocks, seeds and remaining gems are collected afterward with the tractor off. Travel and Fist also remove it; previous footwear is restored afterward. Use Fist for farms containing different seed types." })
ui.harvestPoint = harvestTab:Paragraph({ Title = "Farm storage", Desc = pointText("farmBox") })
harvestTab:Button({ Title = "Save Farm storage", Desc = "Stand beside the farm world's Display Box.",
    Callback = uiAction(function() captureNearby("farmBox", "box") end) })
settingsControls.moveAfterHarvest = harvestTab:Toggle({ Title = "Start Moving Drops after collection", Value = App.config.options.moveAfterHarvest,
    Desc = "Finish harvest collection, then move the item selected on Moving Drops. Save the Farm and destination Display Boxes first.",
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
    Desc = "Requires every selected tree in the world to be fully grown. An immature farm stops with a waiting status; start again when ready, or use Full Rotation to wait automatically. Off stops.",
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
        ui.movingItem:Select(App.config.moving.item == "seeds" and "Seeds" or "Blocks")
        profileNameInput:Set(App.profile)
        if App.runtime then refreshBlocks() end
        refreshSeeds()
        updatePoints()
        resetWebhookSchedule()
        syncWebhookControls()
        pollFPSBooster(true)
        if App.botting.syncUI then App.botting.syncUI() end
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
profileTab:Paragraph({ Title = "Named configurations", Desc = "Each profile saves the chosen block, saved locations, timing settings, and Discord webhook settings. Files are separate for Roblox account " .. ACCOUNT_ID .. " in " .. PROFILE_DIR .. "." })
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
    App.botting.resetImport()
    App.config, App.profile = nextConfig, selectedProfile
    syncUI()
    setStatus("Loaded profile: " .. App.profile)
end) })
profileTab:Button({ Title = "New empty configuration", Callback = uiAction(function()
    App.botting.resetImport()
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

do
    local tab, controls = ui.bottingTab, {}
    local previousSync = App.syncingUI
    App.syncingUI = true
    local labels = {breaker = "Breaker", collector = "Collector", rotation = "Rotation"}
    local function saveSetup()
        App.config = Core.validate(App.config); saveSession(); updatePoints()
        if App.botting.syncUI then App.botting.syncUI() end
    end
    local function sameBNS()
        local world = runtime().world.name
        if App.config.botting.world == "" then App.config.botting.world = world end
        assert(App.config.botting.world == world, "Visit the saved BNS world before saving its layout.")
    end
    local function anchor()
        sameBNS()
        local state = position()
        assert(state.grounded, "Stand on the BNS floor before saving a spot.")
        return {world = runtime().world.name, x = math.floor(state.x), y = math.floor(state.y - 0.01)}
    end
    tab:Paragraph({Title = "Shared cloudphone team", Desc = "Import the same farm setup into every account, then choose each account's role and breaker spot here. Roles and recovery stay private. Shared jobs require every instance to see the same team folder; Connect team shows detected accounts."})
    controls.team = tab:Input({Title = "Botting team name", Value = App.config.botting.team, Callback = function(value)
        if App.syncingUI then return end
        local ok, issue = pcall(function() idle(); App.config.botting.team = Core.profileName(value); saveSetup() end)
        if not ok then notify(tostring(issue)) end
    end})
    controls.folder = tab:Input({Title = "Shared team folder", Value = App.config.botting.folder,
        Desc = "Folder visible to every instance. Default: ClarisGrowblox/teams. Android shared-storage paths also work when permitted by your executor.", Callback = function(value)
            if App.syncingUI then return end
            local old = App.config.botting.folder
            local ok, issue = pcall(function() idle(); App.config.botting.folder = tostring(value); saveSetup() end)
            if not ok then App.config.botting.folder = old; notify(tostring(issue)) end
        end})
    controls.expected = tab:Input({Title = "Expected team accounts", Value = tostring(App.config.botting.expectedAccounts),
        Desc = "Default 4. Connect all instances before starting. Missing teammates block startup so isolated files cannot silently create competing farm jobs.", Callback = function(value)
            if App.syncingUI then return end
            local old = App.config.botting.expectedAccounts
            local ok, issue = pcall(function() idle(); App.config.botting.expectedAccounts = tonumber(value); saveSetup() end)
            if not ok then App.config.botting.expectedAccounts = old; notify(tostring(issue)) end
        end})
    controls.role = tab:Dropdown({Title = "This account's role", Values = {"Breaker", "Collector", "Rotation"},
        Value = labels[App.botting.preferences.role], Callback = function(value)
            if App.syncingUI then return end
            local role
            for key, label in pairs(labels) do if label == value then role = key end end
            if not role then return end
            local ok, issue = pcall(App.botting.setRole, role)
            if not ok then notify(tostring(issue)) end
        end})
    controls.spot = tab:Dropdown({Title = "This account's breaker spot", Values = {"Save spots first"},
        Callback = function(value)
            if App.syncingUI or not tonumber(value) then return end
            local ok, issue = pcall(App.botting.setRole, App.botting.preferences.role, tonumber(value))
            if not ok then notify(tostring(issue)) end
        end})
    controls.collectBreak = tab:Toggle({Title = "Collector also breaks", Value = App.botting.preferences.collectBreak,
        Desc = "Use a free saved breaker spot for this collector. A dedicated collector can spend more time collecting and unloading.", Callback = function(value)
            if App.syncingUI then return end
            local ok, issue = pcall(App.botting.setRole, App.botting.preferences.role, nil, value)
            if not ok then notify(tostring(issue)) end
        end})
    ui.bottingLayout = tab:Paragraph({Title = "BNS layout", Desc = "Save the shortcut door, two boxes, breaker spots and collector position."})
    tab:Button({Title = "Save BNS shortcut door", Callback = uiAction(function()
        sameBNS(); captureNearby("breakDoor", "door"); saveSetup()
    end)})
    tab:Button({Title = "Save BNS block Display Box", Callback = uiAction(function()
        sameBNS(); captureNearby("blockBox", "box"); saveSetup()
    end)})
    tab:Button({Title = "Save BNS seed Display Box", Callback = uiAction(function()
        sameBNS(); captureNearby("seedBox", "box")
        local box = App.config.points.seedBox
        App.config.points.plantBox = {world = box.world, x = box.x, y = box.y, standX = box.standX, standY = box.standY}
        App.config.planting.storageWorld = box.world
        if Core.farmable(runtime().items[App.config.blockId]) then App.config.planting.seedId = Core.seedId(runtime().items, App.config.blockId) end
        saveSetup()
    end)})
    tab:Button({Title = "Add BNS breaker spot", Desc = "Stand at each circle and add its spot, one at a time. Blocks are placed directly above it.", Callback = uiAction(function()
        local point, spots = anchor(), App.config.botting.spots
        assert(#spots < 12, "At most 12 breaker spots can be saved.")
        for _, saved in ipairs(spots) do assert(saved.x ~= point.x or saved.y ~= point.y, "This breaker spot is already saved.") end
        tileAt(point.x, point.y - 1); spots[#spots + 1] = point; saveSetup()
        setStatus("Saved Botting breaker spot " .. #spots)
    end)})
    tab:Button({Title = "Save BNS collector position", Desc = "The middle of the breaking lane is recommended. Nearby pickups are attempted while stationary; refused or farther drops use a short walking fallback.", Callback = uiAction(function()
        App.config.botting.collector = anchor(); saveSetup()
    end)})
    tab:Button({Title = "Clear BNS breaker spots", Callback = uiAction(function()
        App.config.botting.spots, App.config.botting.collector = {}, nil; saveSetup()
    end)})
    tab:Button({Title = "Save this farm's Botting harvest box", Desc = "Use the Planting farm list. Visit each farm and stand beside its mixed block/seed Display Box.", Callback = uiAction(function()
        captureNearby("farmBox", "box"); saveSetup()
    end)})
    tab:Paragraph({Title = "Storage policy", Desc = "At 6,000 blocks or less, breakers help farm jobs. At 36,000, finish existing farm cleanup and transfers, fill empty dirt, then break until 6,000 remain. Planting is last priority. Level 1-9 accounts can only plant on farms; only level 10+ accounts owning a Tractor can harvest."})
    tab:Button({Title = "Connect team / refresh teammates", Callback = uiAction(function()
        Core.checkSetup(App.config, "botting", runtime().items)
        setStatus(App.botting.connect())
    end)})
    App.runToggles.botting = tab:Toggle({Title = "Continuous Botting", Value = false,
        Desc = "Run this account's role with shared farm assignments. Role choice survives importing configs. World changes queue the loader and resume this account's Botting checkpoint.",
        Callback = function(value) setRunningEnabled("botting", value) end})
    function App.botting.resume()
        idle()
        local saved = App.botting.readResume()
        assert(saved, "No saved Botting session is available.")
        App.config, App.profile = saved.config, Core.profileName(saved.profile)
        syncUI(); start("botting", saved)
    end
    tab:Button({Title = "Resume saved Botting", Callback = function()
        local ok, issue = pcall(App.botting.resume); if not ok then notify(tostring(issue)) end
    end})
    tab:Button({Title = "Clear saved Botting", Desc = "Review backpack and boxes first if a storage request was interrupted. Keeps the imported layout and this account's role.", Callback = uiAction(function()
        App.botting.resetImport(); setStatus("Cleared this account's saved Botting progress.")
    end)})
    ui.bottingStatus = tab:Paragraph({Title = "Team status", Desc = "Not connected"})
    function App.botting.syncUI()
        local previous = App.syncingUI
        App.syncingUI = true
        controls.team:Set(App.config.botting.team); controls.folder:Set(App.config.botting.folder)
        controls.expected:Set(tostring(App.config.botting.expectedAccounts))
        controls.role:Select(labels[App.botting.preferences.role]); controls.collectBreak:Set(App.botting.preferences.collectBreak)
        local values, lines = {}, {"World: " .. (App.config.botting.world ~= "" and App.config.botting.world or "not saved")}
        for index, point in ipairs(App.config.botting.spots) do values[#values + 1] = tostring(index); lines[#lines + 1] = index .. ": " .. point.x .. ", " .. point.y end
        controls.spot:Refresh(#values > 0 and values or {"Save spots first"})
        controls.spot:Select(values[App.botting.preferences.spot] or "Save spots first")
        local collector = App.config.botting.collector
        lines[#lines + 1] = "Collector: " .. (collector and (collector.x .. ", " .. collector.y) or "middle saved breaker spot")
        lines[#lines + 1] = "Shared folder: " .. App.config.botting.folder .. "/" .. App.config.botting.team
        paragraphSet(ui.bottingLayout, "BNS layout", table.concat(lines, "\n"))
        App.syncingUI = previous
    end
    App.botting.syncUI()
    App.syncingUI = previousSync
end

rotationTab:Paragraph({ Title = "Plant, harvest, break, repeat", Desc = "Use the full Planting farm list. Fill empty rows and break PNB stock while trees grow. Ready farms normally interrupt PNB for harvest, transfer and replant. If planting seed supply runs out, finish all remaining PNB blocks first, storing produced seeds, then resume farms. Full farms skip planting. Account-specific progress resumes across supported world changes." })
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
settingsControls.harvestPlanting = rotationTab:Toggle({ Title = "Replant during harvest", Value = App.config.options.harvestPlanting,
    Desc = "Bring PNB seeds before harvesting. Plant cleared tiles behind the tractor, or after Fist cleanup from below. Finish the forward pass when seeds run out; normal replanting refills and fills remaining spaces. Save your profile to keep this setting.",
    Callback = function(value)
        if App.syncingUI then return end
        if App.job or App.configuring or App.pending > 0 then
            notify("Stop the task before changing harvest replanting.")
            App.syncingUI = true
            settingsControls.harvestPlanting:Set(App.config.options.harvestPlanting, false, false)
            App.syncingUI = false
            return
        end
        App.config.options.harvestPlanting = value
        pcall(saveSession)
    end })
App.runToggles.rotation = rotationTab:Toggle({ Title = "Continuous full rotation", Value = false,
    Desc = "Run PNB while farms grow. When planting seeds run out, finish all PNB blocks before more planting or harvest. Choose your harvesting method on Harvest Drops.",
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
    assert(record.version == 1 and record.userId == ACCOUNT_ID, "The saved transfer belongs to another account or script version.")
    assert(type(record.updatedAt) == "number" and os.time() - record.updatedAt < 21600,
        "Saved transfer is over six hours old. Check your backpack and clear it before restarting.")
    record.config = Core.validate(record.config)
    record.profile = Core.profileName(record.profile)
    assert(type(record.cargo) == "number" and record.cargo >= 0 and record.cargo <= 200 and record.cargo == math.floor(record.cargo),
        "Invalid cargo in the saved transfer.")
    assert(({pickup=true, deliver=true, returnSeeds=true, ["return"]=true,
        pickupPending=true, depositPending=true, seedReturnPending=true})[record.phase], "Invalid saved transfer phase.")
    record.item = record.item or record.config.moving.item
    assert(record.item == "blocks" or record.item == "seeds", "Invalid saved Moving Drops item.")
    for _, key in ipairs({"seeds", "companion"}) do
        local value = record[key]
        assert(value == nil or type(value) == "number" and value >= 0 and value <= 200 and value == math.floor(value),
            "Invalid saved transfer " .. key .. ".")
    end
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
    {"fpsBooster", "FPS booster: hide floating drops", "Hide loose blocks, seeds and gems and stop their bobbing. Collection continues; Display Boxes stay visible. Turn Off to restore visuals."},
    {"fpsGreyMap", "FPS booster: Grey map", "Replace map and nearby tree textures with grey shapes and reduce distant tree visuals. Keep the sky, avatar, controls, doors and Display Boxes. Turn Off to restore textures."},
    {"fpsHideWorld", "FPS booster: Hide game world", "Hide the game viewport, map, avatars, weather and effects while automation continues. The script menu stays usable. Turn Off to restore the view before saving locations or playing manually."},
}) do
    local key = info[1]
    settingsControls[key] = settingsTab:Toggle({Title = info[2], Desc = info[3], Value = App.config.options[key],
        Callback = function(value)
            if App.syncingUI then return end
            if key ~= "fpsBooster" and key ~= "fpsGreyMap" and key ~= "fpsHideWorld" and (App.job or App.configuring or App.pending > 0) then
                notify("Stop the task before changing settings.")
                settingsControls[key]:Set(App.config.options[key], false, false)
                return
            end
            App.config.options[key] = value
            if key == "antiAFK" and value then installAntiAFK() end
            if key == "fpsBooster" or key == "fpsGreyMap" or key == "fpsHideWorld" then
                pollFPSBooster(true)
                local ok, issue = pcall(saveFPSPreference)
                App.fpsSaveError = not ok and tostring(issue) or nil
                if not ok then notify("Could not save the FPS booster setting: " .. tostring(issue)) end
            end
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
        .. "\nRoblox account: " .. ACCOUNT_ID .. "\nAccount data: " .. ROOT
        .. "\nAccount migration: " .. (App.storageMigrationError or "ready")
        .. "\nPending requests: " .. App.pending .. "\n" .. table.concat(App.logs, "\n")
        .. "\nConnection error: " .. (App.connectionError or "none")
        .. "\nLoader: " .. (env.ClarisGrowbloxLoaderDebug or "direct script")
        .. "\nLast door: " .. (App.doorReadyDebug or "not used")
        .. "\nAnti-AFK: " .. (App.antiAFKError or "ready")
        .. "\nFPS booster: " .. (App.config.options.fpsBooster and "On" or "Off")
        .. "; hidden loose sprites: " .. (App.fpsHidden or 0) .. "; " .. (App.fpsBoosterError or "ready")
        .. "\nGrey map: " .. (App.config.options.fpsGreyMap and "On" or "Off")
        .. "; simplified sprites: " .. (App.fpsMapCount or 0) .. "; " .. (App.fpsMapError or "ready")
        .. "\nHidden game world: " .. (App.config.options.fpsHideWorld and "On" or "Off") .. "; hidden: " .. tostring(App.fpsWorldHidden == true)
        .. "\nBotting role: " .. App.botting.preferences.role .. "; spot " .. App.botting.preferences.spot
        .. "; level " .. (App.botting.level or "unknown") .. "; " .. (App.botting.debug or "not connected")
        .. "\nBotting error: " .. (App.botting.error or "none")
        .. "\nBotting job: " .. (App.botState and App.botState.job and (App.botState.job.kind .. " in " .. App.botState.job.world) or "idle")
        .. "\nFPS setting save: " .. (App.fpsSaveError or "ready")
        .. "\nNavigation: " .. (App.navigationDebug or "no route requested")
        .. "\nLast refused harvest pickup: " .. (App.lastHarvestRefusal or "none")
        .. "\nHarvest collection recovery: " .. (App.harvestCollectionRecovery or "not requested")
        .. "\nMoving Drops item: " .. App.config.moving.item .. "; destination: " .. pointText("moveBox")
        .. "\nHarvest storage return: " .. (App.harvestReturnDebug or "not requested")
        .. "\nRotation phase: " .. (App.rotationState and (App.rotationState.phase .. "; cycle " .. App.rotationState.cycle
            .. "; farm " .. App.rotationState.worldIndex .. "/" .. #App.config.planting.worlds) or "idle")
        .. "\nHarvest method: " .. App.config.harvesting.method .. "; phase: " .. (App.harvestPhase or "not started")
        .. "\nSaved harvest pass: " .. (App.rotationState and App.rotationState.harvestPass
            and (App.rotationState.harvestPass.world .. "; " .. App.rotationState.harvestPass.phase) or "not started")
        .. "\nExisting harvest recovery: " .. (App.rotationState and App.rotationState.collectOnly and "collecting/transferring farm stock" or "not active")
        .. "\nPNB supply: " .. (App.rotationState and App.rotationState.pnbEmpty and "empty; farm stock checks enabled" or "not marked empty")
        .. "\nTrees harvested: " .. App.stats.trees .. "; equipment restore: " .. (App.harvestGearError or "ready")
        .. "\nFarm maturity check: " .. (App.harvestMaturity or "not requested")
        .. "\nPlanting recovery: " .. (App.plantingRecovery or "not requested")
        .. "\nNavigation recovery: " .. (App.navigationRecovery or "not requested")
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
        local botOK, bot = pcall(App.botting.readResume)
        if botOK and bot then setStatus("Saved Botting found. Use Resume saved Botting on Botting.")
        elseif not botOK then notify(tostring(bot)) end
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
    elseif env.ClarisGrowbloxAutoResume or App.botting.preferences.autoStart then
        env.ClarisGrowbloxAutoResume = nil
        local resumed, problem = pcall(function()
            if App.botting.preferences.autoStart and App.botting.readResume() then App.botting.resume()
            elseif readRotationResume() then resumeRotation()
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
        App.botting.poll()
        pollFPSBooster()
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
            paragraphSet(ui.bottingStatus, "Team status", (App.botting.debug or "Not connected") .. "\nRole: " .. App.botting.preferences.role
                .. "; breaker spot " .. App.botting.preferences.spot .. "\n" .. App.status .. "\n" .. (App.botting.error or ""))
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
