-- Scoped Growblox GUI rendering overrides. Never change world grids or item data.
return function(App, upvalues)
    local Map = {}
    local function gui(value, class)
        return type(typeof) == "function" and typeof(value) == "Instance" and value:IsA(class)
    end
    local function tile(frame)
        if not gui(frame, "ImageLabel") then return end
        local id, z = frame:GetAttribute("id"), frame:GetAttribute("z")
        if type(id) == "number" and (z == 2 or z == 3 or z == 4) then return id, z end
    end
    local function discover(r)
        assert(type(r.world.treeLook) == "function", "Map renderer unavailable; retrying.")
        local values, root = upvalues(r.world.treeLook)
        for _, value in pairs(values) do
            if gui(value, "GuiObject") then
                for _, child in ipairs(value:GetChildren()) do
                    if tile(child) ~= nil then
                        assert(not root or root == value, "Map renderer is ambiguous; retrying.")
                        root = value
                        break
                    end
                end
            end
        end
        assert(root, "Map tile frames unavailable; retrying.")
        return root, values
    end
    local function restoreFrame(frame, record)
        if frame.Parent == nil then return end -- Native renderer destroys/rebuilds its pools.
        for key, saved in pairs(record) do
            if frame[key] == saved.applied then frame[key] = saved.original end
        end
    end
    local function override(frame, record, key, value)
        local current, saved = frame[key], record[key]
        if not saved then
            saved = {original = current}
            record[key] = saved -- Record first so failed property writes remain reversible.
        elseif current ~= saved.applied then
            saved.original = current -- Native tile reuse/repainting supersedes the old texture.
        end
        if current ~= value then frame[key] = value end
        saved.applied = value
    end
    function Map.restore()
        local state, failed = App.fpsMapState
        App.fpsMapCount = 0
        if not state then return true end
        for frame, record in pairs(state.records) do
            local ok, issue = pcall(restoreFrame, frame, record)
            if ok then state.records[frame] = nil else failed = tostring(issue) end
        end
        if state.lowChanged then
            local ok, issue = pcall(function()
                if state.world.lowGfx == true then state.world.lowGfx = state.lowOriginal end
            end)
            if ok then state.lowChanged = nil else failed = tostring(issue) end
        end
        if failed then App.fpsMapError = "Could not restore map visuals: " .. failed; return false end
        App.fpsMapState = nil
        return true
    end
    function Map.poll(force)
        if not App.alive or not App.config.options.fpsGreyMap then
            if Map.restore() then App.fpsMapError = nil end
            return
        end
        local r = App.runtime
        if not r or App.fpsMapBusy then return end
        if not force and os.clock() < (App.nextFPSMapScan or 0) then return end
        App.fpsMapBusy = true
        local ok, issue = pcall(function()
            local state = App.fpsMapState
            if not state or state.world ~= r.world or state.root.Parent == nil then
                assert(Map.restore(), App.fpsMapError)
                local root, values = discover(r)
                state = {world = r.world, root = root, values = values, records = {}}
                App.fpsMapState = state
                -- Native low graphics limits distant tree drawings and cosmetic effects.
                -- Assign the local flag only; the game's server-backed setting is untouched.
                if type(r.world.lowGfx) == "boolean" and not r.world.lowGfx then
                    state.lowOriginal, state.lowChanged = r.world.lowGfx, true
                    r.world.lowGfx = true
                end
            end
            local work, lastYield, count = 0, os.clock(), 0
            local function checkpoint()
                work = work + 1
                if work >= 512 or os.clock() - lastYield >= 0.006 then
                    task.wait()
                    work, lastYield = 0, os.clock()
                end
                return App.alive and App.config.options.fpsGreyMap and App.runtime == r and App.fpsMapState == state
            end
            local targets = {}
            for _, frame in ipairs(state.root:GetChildren()) do
                if not checkpoint() then return end
                local id, z = tile(frame)
                if id and id >= 0 then
                    local item = r.items and r.items[id]
                    if not (item and (item.display or item.displayOne or item.door or item.entrance
                        or item.vip or item.lock or item.area)) then targets[frame] = z end
                end
            end
            -- Tree sprites lack tile attributes. Only inspect confirmed native tree frames,
            -- never the avatar, HUD, sky, dropped items or Display Box contents.
            for _, value in pairs(state.values) do
                if type(value) == "table" and value ~= r.world and value ~= r.items then
                    for _, tree in pairs(value) do
                        if not checkpoint() then return end
                        if type(tree) == "table" and type(tree.tree) == "table" and type(tree.id) == "number"
                            and gui(tree.frame, "GuiObject") and tree.frame.Parent == state.root then
                            for _, frame in ipairs(tree.frame:GetDescendants()) do
                                if not checkpoint() then return end
                                if gui(frame, "ImageLabel") then targets[frame] = frame.ZIndex end
                            end
                        end
                    end
                end
            end
            for frame, record in pairs(state.records) do
                if not checkpoint() then return end
                if not targets[frame] or frame.Parent == nil then
                    restoreFrame(frame, record)
                    state.records[frame] = nil
                end
            end
            for frame, z in pairs(targets) do
                if not checkpoint() then return end
                if frame.Parent ~= nil then
                    local record = state.records[frame] or {}
                    state.records[frame] = record
                    override(frame, record, "Image", "")
                    local shade = z == 2 and 90 or 140
                    override(frame, record, "BackgroundColor3", Color3.fromRGB(shade, shade, shade))
                    override(frame, record, "BackgroundTransparency", z == 3 and 1 or frame.ImageTransparency)
                    count = count + 1
                end
            end
            App.fpsMapCount = count
        end)
        App.fpsMapBusy, App.nextFPSMapScan = false, os.clock() + 1
        App.fpsMapError = not ok and tostring(issue) or nil
        if not ok then Map.restore() end -- Cosmetic failure must not stop rotation.
    end
    return Map
end
