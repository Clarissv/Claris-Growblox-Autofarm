-- Shared-device job coordination. Each account owns one heartbeat file; only the
-- elected leader publishes assignments. Cargo and role preferences stay private.
local Botting = {}
local roles = {breaker = true, collector = true, rotation = true}
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end
function Botting.fingerprint(c)
    local b, p = c.botting, c.points
    local parts = {tostring(c.blockId), tostring(c.planting.seedId), b.world, tostring(b.lowWater), tostring(b.highWater), tostring(b.expectedAccounts)}
    local function point(value)
        parts[#parts + 1] = value and table.concat({value.world, value.x, value.y}, ":") or "-"
    end
    point(p.blockBox); point(p.seedBox); point(p.breakDoor); point(b.collector)
    for _, spot in ipairs(b.spots) do point(spot) end
    for _, world in ipairs(c.planting.worlds) do parts[#parts + 1] = world; point(c.rotation.farms[world]) end
    return table.concat(parts, "|")
end
function Botting.members(records, fingerprint, now)
    local members = {}
    for _, record in pairs(records) do
        if type(record) == "table" and record.version == 1 and record.fingerprint == fingerprint
            and type(record.id) == "number" and record.id > 0 and record.id == math.floor(record.id)
            and roles[record.role] and type(record.at) == "number" and record.at <= now + 5 and record.at >= now - 90
            and type(record.level) == "number" and record.level >= 0 and type(record.pending or 0) == "number"
            and (record.active == true or (record.pending or 0) > 0) then
            members[#members + 1] = copy(record)
        end
    end
    table.sort(members, function(a, b) return a.id < b.id end)
    return members
end
function Botting.schedule(previous, members, c, now)
    local board = copy(previous or {version = 1, sequence = 0, farms = {}, jobs = {}, drain = false})
    board.version, board.at, board.leader = 1, now, members[1] and members[1].id
    board.jobs, board.farms = board.jobs or {}, board.farms or {}
    local previousJobs = copy(board.jobs)
    local byId, newestStock = {}, board.stock
    for _, member in ipairs(members) do
        byId[tostring(member.id)] = member
        local sensor = member.sensor
        if type(sensor) == "table" and type(sensor.at) == "number" and sensor.at >= now - 90 then
            if sensor.world == c.botting.world and type(sensor.blocks) == "number" and type(sensor.seeds) == "number"
                and (not newestStock or sensor.at >= newestStock.at) then newestStock = copy(sensor) end
            if c.rotation.farms[sensor.world] then
                local farm = board.farms[sensor.world] or {}
                if not farm.at or sensor.at >= farm.at then
                    for _, key in ipairs({"at", "empty", "ripe", "growing", "remaining", "loose", "gems", "stored", "maturityKnown"}) do farm[key] = sensor[key] end
                    board.farms[sensor.world] = farm
                end
            end
        end
    end
    board.stock = newestStock
    local stockFresh = newestStock and newestStock.at >= now - 90
    local blocks, seeds = stockFresh and newestStock.blocks or nil, stockFresh and newestStock.seeds or 0
    local seedsInTransit, heldBlocks = false, stockFresh and (newestStock.breakingTiles or 0) or 0
    for _, member in ipairs(members) do
        if (member.carriedSeeds or 0) > 0 then seedsInTransit = true end
        heldBlocks = heldBlocks + (member.carriedBlocks or 0)
    end
    if blocks then
        if blocks >= c.botting.highWater then board.drain = true
        elseif blocks <= c.botting.lowWater then board.drain = false end
        if seeds == 0 and blocks + heldBlocks > 0 and not seedsInTransit then board.seedDrain = true end
        if blocks == 0 and heldBlocks == 0 then board.seedDrain = false end
    end
    local busy, locks = {}, {}
    for owner, job in pairs(board.jobs) do
        local member = byId[owner]
        if not member or member.done == job.id or member.abandoned == job.id then
            if member and member.done == job.id and job.kind == "harvest" then
                local farm = board.farms[job.world] or {}
                farm.harvesting, farm.harvestedAt = false, now
                board.farms[job.world] = farm
            end
            if member and member.done == job.id and job.kind == "plant" then
                local farm = board.farms[job.world] or {}
                farm.plantAfter = now + 60; board.farms[job.world] = farm
            end
            if member and member.done == job.id and job.kind == "collect" then
                local farm = board.farms[job.world] or {}
                farm.collectTurn = (job.partition or 1) % 2 + 1; board.farms[job.world] = farm
            end
            board.jobs[owner] = nil
        elseif job.kind ~= "break" and job.kind ~= "collector" and job.kind ~= "wait" then
            busy[owner] = true
            locks[job.kind .. ":" .. job.world .. ":" .. (job.partition or 0)] = true
        elseif (member.pending or 0) > 0 then busy[owner] = true
        else board.jobs[owner] = nil end
    end
    local activeCollector, occupied = false, {}
    for _, member in ipairs(members) do
        if member.active and member.role == "collector" and (member.level or 0) >= 10
            and (not busy[tostring(member.id)] or board.jobs[tostring(member.id)].kind == "collector") then activeCollector = true end
        if busy[tostring(member.id)] and board.jobs[tostring(member.id)].kind == "break" then occupied[member.spot or 1] = member.id end
        if busy[tostring(member.id)] and board.jobs[tostring(member.id)].kind == "harvest" then
            local farm = board.farms[board.jobs[tostring(member.id)].world] or {}
            farm.harvesting = true; board.farms[board.jobs[tostring(member.id)].world] = farm
        end
        if member.active and member.role == "collector" and member.collectBreak and not busy[tostring(member.id)] then occupied[member.spot or 1] = member.id end
    end
    local function issue(member, kind, world, partition)
        local old = previousJobs[tostring(member.id)]
        if (kind == "break" or kind == "collector" or kind == "wait") and old and old.kind == kind and old.world == world then
            local job = copy(old); board.jobs[tostring(member.id)] = job; return job
        end
        board.sequence = (board.sequence or 0) + 1
        local job = {id = tostring(board.leader) .. ":" .. board.sequence, kind = kind, world = world,
            owner = member.id, partition = partition, partitions = partition and 2 or nil}
        board.jobs[tostring(member.id)] = job
        if kind == "harvest" then job.approved = board.farms[world].harvesting == true; board.farms[world].harvesting = true end
        locks[kind .. ":" .. world .. ":" .. (partition or 0)] = true
        return job
    end
    -- Harvest-capable rotation workers get first choice of ripe farms. Other
    -- workers can collect existing stock while this account makes new drops.
    local ordered = copy(members)
    table.sort(ordered, function(a, b)
        local ap = a.role == "rotation" and a.harvester and 0 or a.role == "rotation" and 1 or 2
        local bp = b.role == "rotation" and b.harvester and 0 or b.role == "rotation" and 1 or 2
        return ap == bp and a.id < b.id or ap < bp
    end)
    for _, member in ipairs(ordered) do
        local owner = tostring(member.id)
        if not busy[owner] and member.active and not ((member.pending or 0) > 0) then
            local level = member.level or 0
            local help = blocks and blocks <= c.botting.lowWater
            local farmWorker = member.role == "rotation" or help and member.role == "breaker"
            -- Keep a sole collector at BNS whenever breakers are producing drops.
            local hasBreaker = false
            for _, other in ipairs(members) do if other.active and other.role == "breaker" and not busy[tostring(other.id)] then hasBreaker = true end end
            if member.role == "collector" and help and not hasBreaker then farmWorker = true end
            local assigned
            if level >= 10 and farmWorker and stockFresh then
                -- Drain mode still finishes loose drops and occupied farm boxes.
                for _, world in ipairs(c.planting.worlds) do
                    local farm = board.farms[world]
                    if farm and ((farm.loose or 0) > 0 or (farm.gems or 0) > 0 or (farm.stored or 0) > 0
                        or farm.harvesting and locks["harvest:" .. world .. ":0"]) then
                        for offset = 0, 1 do
                            local partition = ((farm.collectTurn or 1) + offset - 1) % 2 + 1
                            if not locks["collect:" .. world .. ":" .. partition] then assigned = issue(member, "collect", world, partition); break end
                        end
                    end
                    if assigned then break end
                end
                if not assigned and member.harvester then
                    for _, world in ipairs(c.planting.worlds) do
                        local farm = board.farms[world]
                        if farm and farm.at and farm.at >= now - 90 and (farm.ripe or 0) > 0
                            and (farm.harvesting or farm.growing == 0 and not board.drain and not board.seedDrain)
                            and not locks["harvest:" .. world .. ":0"] then
                            assigned = issue(member, "harvest", world); break
                        end
                    end
                end
            end
            -- Planting is last priority. A filling/draining farm still gets its
            -- empty dirt planted; low-level accounts are eligible for this only.
            local canPlant = farmWorker or help and level < 10 or board.drain and member.role ~= "collector"
            if not assigned and canPlant and stockFresh and seeds > 0 and not board.seedDrain then
                for _, world in ipairs(c.planting.worlds) do
                    local farm = board.farms[world]
                    if farm and (farm.empty or 0) > 0 and now >= (farm.plantAfter or 0) and not locks["plant:" .. world .. ":0"] then
                        assigned = issue(member, "plant", world); break
                    end
                end
            end
            if not assigned and farmWorker and level >= 10 and member.role ~= "collector" and stockFresh then
                for _, world in ipairs(c.planting.worlds) do
                    local farm = board.farms[world]
                    local due = not farm or not farm.at or farm.maturityKnown==false or now - farm.at >= math.min(60, math.max(5, farm.remaining or 60))
                    if due and not locks["inspect:" .. world .. ":0"] then assigned = issue(member, "inspect", world); break end
                end
            end
            if not assigned then
                if member.role == "collector" and level >= 10 then assigned = issue(member, "collector", c.botting.world)
                elseif occupied[member.spot or 1] then assigned = issue(member, "wait", c.botting.world)
                else
                    occupied[member.spot or 1] = member.id
                    assigned = issue(member, "break", c.botting.world)
                    assigned.collectOwn = not activeCollector -- Preserve seeds/gems if the collector is unavailable.
                end
            end
        end
    end
    return board
end

function Botting.new(App, api)
    local self = {core = Botting, preferences = {role = "breaker", spot = 1, collectBreak = false, autoStart = false}}
    local member, board, sensor, nextPoll, nextLevel, nextSensor, connected, polling, leaseReady
    local memberCache = {}
    local function path() return App.config.botting.folder .. "/" .. App.config.botting.team end
    local function ensure()
        api.filesystem()
        assert(type(listfiles) == "function", "Shared Botting needs listfiles in the executor.")
        local current = path():sub(1, 1) == "/" and "/" or ""
        for part in path():gmatch("[^/]+") do
            current = current == "" and part or current == "/" and current .. part or current .. "/" .. part
            if not isfolder(current) then makefolder(current) end
        end
    end
    local function read(pathname)
        local ok, value = pcall(function() if isfile(pathname) then return api.decode(readfile(pathname)) end end)
        if ok and type(value) == "table" then return value end
    end
    local function members()
        local records = {}
        local prior = read(path() .. "/board.json") or read(path() .. "/board.json.bak") or board
        if prior and prior.fingerprint == Botting.fingerprint(App.config) then
            for id, peer in pairs(prior.peers or {}) do
                if type(peer) == "table" and type(peer.at) == "number" and (not memberCache[id] or peer.at > memberCache[id].at) then memberCache[id] = peer end
            end
        end
        for _, filename in ipairs(listfiles(path())) do
            local normalized = filename:gsub("\\", "/")
            local id = normalized:match("([^/]+)$"):match("^(%d+)%.json$")
            if id then
                local value = read(normalized:find("/", 1, true) and normalized or path() .. "/" .. normalized)
                if value and value.version == 1 and type(value.at) == "number" and tostring(value.id) == id then
                    assert(not (value.fingerprint ~= Botting.fingerprint(App.config) and value.active and value.at >= os.time() - 90),
                        "This team name is active with a different layout. Import the same setup or choose another team name.")
                    if value.fingerprint == Botting.fingerprint(App.config) then memberCache[id] = value end
                end
            end
        end
        for id, record in pairs(memberCache) do
            if record.fingerprint == Botting.fingerprint(App.config) and record.at >= os.time() - 90 then records[#records + 1] = record
            else memberCache[id] = nil end
        end
        local fingerprint, now = Botting.fingerprint(App.config), os.time()
        local live = Botting.members(records, fingerprint, now)
        local registered = copy(records)
        for _, record in ipairs(registered) do record.active = true end
        self.detectedCount = #Botting.members(registered, fingerprint, now)
        return live
    end
    local preferences = read(api.roleFile)
    if preferences and preferences.userId == App.userId and roles[preferences.role] and type(preferences.spot) == "number" then
        self.preferences = {role = preferences.role, spot = preferences.spot,
            collectBreak = preferences.collectBreak == true, autoStart = preferences.autoStart == true}
    end
    function self.savePreferences()
        local record = copy(self.preferences); record.userId = App.userId
        api.write(api.roleFile, record)
    end
    function self.setRole(role, spot, collectBreak)
        api.idle()
        assert(roles[role], "Choose Breaker, Collector or Rotation.")
        if spot then assert(spot >= 1 and spot == math.floor(spot) and spot <= 12, "Choose a valid breaker spot number.") end
        self.preferences.role, self.preferences.spot = role, spot or self.preferences.spot
        if collectBreak ~= nil then self.preferences.collectBreak = collectBreak == true end
        self.preferences.autoStart = false
        self.savePreferences()
        self.stop()
    end
    function self.save()
        if not App.botState then return end
        api.saveSession()
        api.write(api.resumeFile, {version = 1, active = true, userId = App.userId, at = os.time(),
            config = api.validate(App.config), profile = App.profile, state = copy(App.botState)})
    end
    function self.readResume()
        local record = read(api.resumeFile)
        if not record or not record.active then return end
        assert(record.version == 1 and record.userId == App.userId and type(record.state) == "table", "Invalid account Botting checkpoint.")
        record.config = api.validate(record.config)
        return record
    end
    function self.poll(force)
        if polling or not App.alive or not (connected or App.job == "botting") then return end
        if not force and os.clock() < (nextPoll or 0) then return end
        polling, nextPoll = true, os.clock() + 2
        local ok, issue = pcall(function()
            ensure()
            if not nextLevel or os.clock() >= nextLevel then
                local queried, level = pcall(api.level)
                if queried and type(level) == "number" and level >= 1 then
                    self.level, nextLevel, self.levelError = math.floor(level), os.clock() + 60, nil
                else
                    self.levelError, nextLevel = "Account level refresh unavailable; using last confirmed level.", os.clock() + 10
                    assert(self.level, "Account level is unavailable; Botting farm collection is disabled.")
                end
            end
            if not nextSensor or os.clock() >= nextSensor then sensor = api.observe(); nextSensor = os.clock() + 3 end
            local state = App.botState
            member = {version = 1, id = App.userId, fingerprint = Botting.fingerprint(App.config), at = os.time(),
                role = self.preferences.role, spot = self.preferences.spot, level = self.level,
                collectBreak = self.preferences.collectBreak,
                carriedSeeds = api.count(App.config.planting.seedId),
                carriedBlocks = api.count(App.config.blockId),
                harvester = api.hasHarvester(), active = App.job == "botting" and (not state or state.active ~= false), pending = App.pending,
                sensor = sensor, done = state and state.done, abandoned = state and state.abandoned}
            api.write(path() .. "/" .. App.userId .. ".json", member)
            local live = members()
            self.teamCount, self.teamMembers = #live, live
            local existing = read(path() .. "/board.json") or read(path() .. "/board.json.bak") or board
            if existing and (existing.version ~= 1 or existing.fingerprint ~= member.fingerprint) then existing = nil end
            if live[1] and live[1].id == App.userId then
                local nextBoard = Botting.schedule(existing, live, App.config, os.time())
                nextBoard.fingerprint = member.fingerprint
                nextBoard.peers = {}
                for _, peer in ipairs(live) do nextBoard.peers[tostring(peer.id)] = peer end
                -- Recheck election immediately before publishing after observation yields.
                local confirm = members()
                if confirm[1] and confirm[1].id == App.userId then api.write(path() .. "/board.json", nextBoard); existing = nextBoard end
            end
            if existing and live[1] and existing.leader == live[1].id and existing.at >= os.time() - 90 then board = existing
            else board = nil end
            self.board = board
            self.debug = "Detected " .. self.detectedCount .. " accounts; " .. #live .. " active; " .. (board and ("leader " .. board.leader
                .. "; storage " .. (board.stock and board.stock.blocks or "unknown") .. "; " .. (board.drain and "draining" or "supplying")) or "waiting for team leader")
        end)
        polling = false
        self.error = not ok and tostring(issue) or nil
    end
    function self.connect()
        connected = true; self.poll(true)
        assert(not self.error, self.error)
        return self.debug
    end
    function self.guard(settling)
        if not leaseReady or App.job ~= "botting" or not App.botState or not App.botState.job or settling and App.pending > 0 then return end
        local job = App.botState.job
        if job.kind == "break" or job.kind == "collector" or job.kind == "wait" then return end
        local current = board and board.jobs[tostring(App.userId)]
        assert(board and board.at >= os.time() - 90 and current and current.id == job.id,
            "Botting team lease is unavailable; waiting before continuing farm actions.")
    end
    function self.stop()
        if not connected and not App.botState and not self.preferences.autoStart then return end
        self.preferences.autoStart = false
        pcall(self.savePreferences)
        if App.botState then
            App.botState.active = false
            if App.pending == 0 and App.botState.job then App.botState.abandoned = App.botState.job.id end
            pcall(self.save)
        end
        if member then member.active, member.at, member.pending = false, os.time(), App.pending; pcall(api.write, path() .. "/" .. App.userId .. ".json", member) end
    end
    function self.beforeStorage(action, point, id, amount, companionId)
        if App.job ~= "botting" then return end
        local state = App.botState
        state.storage = {action = action, point = copy(point), id = id, amount = amount,
            before = api.count(id), companionId = companionId, companionBefore = companionId and api.count(companionId)}
        self.save()
    end
    function self.afterStorage()
        if App.job == "botting" then
            App.botState.storage = nil; self.save()
            sensor, nextSensor = api.observe(), os.clock() + 3
            self.poll(true)
        end
    end
    function self.resetImport()
        if not App.botState and not read(api.resumeFile) and not self.preferences.autoStart then return end
        self.stop(); App.botState = nil
        api.write(api.resumeFile, {version = 1, active = false, userId = App.userId})
    end
    function self.run(token, saved)
        App.botState = saved and copy(saved.state) or {active = true, retries = 0}
        local state = App.botState
        state.active, leaseReady = true, false
        assert(not state.storage, "An interrupted Botting storage request needs inventory/box review. Use Clear saved Botting after checking cargo.")
        assert(App.config.botting.spots[self.preferences.spot], "Choose a saved Botting breaker spot for this account.")
        self.preferences.autoStart, connected = true, true
        self.savePreferences(); self.save(); api.queue()
        -- Observe and renew the saved lease where the account arrived. Sending
        -- every reload to BNS first loops forever when farm entry teleports.
        self.poll(true)
        assert(not self.error, self.error)
        if self.detectedCount < App.config.botting.expectedAccounts then
            self.preferences.autoStart = false; self.savePreferences()
            error("Botting sees " .. self.detectedCount .. "/" .. App.config.botting.expectedAccounts
                .. " accounts. Connect every instance first and verify they share the same team folder.")
        end
        while true do
            leaseReady = false
            api.checkpoint(token)
            self.poll()
            local assignment = board and board.jobs[tostring(App.userId)]
            if assignment and state.done == assignment.id then
                api.pause(2, token)
            elseif not assignment or self.error then
                api.status(self.error or "Botting: waiting for shared team assignments..."); api.pause(2, token)
            else
                if not state.job or state.job.id ~= assignment.id then
                    if state.job and (state.phase == "deliver" or state.phase == "source") then
                        assert(not state.storage, "Review interrupted Botting storage before changing jobs.")
                        api.flushCargo(token)
                    end
                    state.job, state.phase, state.rotation, state.plant, state.done, state.abandoned = copy(assignment), nil, nil, nil, nil, nil
                    state.retries = 0; self.save()
                else state.job = copy(assignment) end
                local job = state.job
                leaseReady = true
                local ok, issue = pcall(function()
                    self.guard()
                    if job.kind == "wait" then
                        api.status("Botting: breaker spot is already assigned to another account; select another spot.")
                        api.pause(2, token)
                    elseif job.kind == "break" or job.kind == "collector" then
                        api.go(App.config.botting.world, token)
                        if job.kind == "collector" then
                            api.collectBNS(token, self.preferences.collectBreak)
                        else api.breakStep(token, job.collectOwn) end
                    else
                        api.status("Botting " .. job.kind .. ": " .. job.world .. "...")
                        -- Refill and delivery phases own their world travel.
                        -- Forcing their farm destination before those phases
                        -- runs creates another farm/BNS loop after a teleport.
                        if job.kind ~= "plant" and not (job.kind == "collect" and state.phase) then
                            api.go(job.world, token)
                        end
                        self.guard()
                        if job.kind == "harvest" then
                            assert(self.level >= 10 and api.hasHarvester(), "Only level 10+ accounts owning a harvesting vehicle can harvest.")
                            api.harvest(job, token)
                        elseif job.kind == "collect" then
                            assert(self.level >= 10, "Level 1-9 accounts cannot collect or move farm blocks and seeds.")
                            api.collectFarm(job, token)
                        elseif job.kind == "plant" then api.plant(job, token)
                        elseif job.kind == "inspect" and api.inspect then api.inspect(job,token)
                        end
                        sensor, nextSensor = api.observe(), os.clock() + 3
                        state.done, state.rotation, state.plant = job.id, nil, nil
                        self.save(); self.poll(true)
                        api.report("work", "Botting finished " .. job.kind .. " in " .. job.world)
                    end
                end)
                if not ok then
                    leaseReady = false
                    api.checkpoint(token)
                    api.halt()
                    state.retries = (state.retries or 0) + 1
                    self.error = tostring(issue)
                    api.report("failure", "Botting " .. job.kind .. ": " .. tostring(issue))
                    self.save()
                    assert(App.pending == 0 and not state.storage and not (state.plant and state.plant.pending),
                        "Botting paused with an unconfirmed request: " .. tostring(issue))
                    api.status("Botting retry in 5s: " .. tostring(issue))
                    api.pause(5, token)
                else api.pause(0.05, token) end
            end
        end
    end
    return self
end
return Botting
