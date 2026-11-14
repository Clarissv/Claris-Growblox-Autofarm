-- Execute the generated loader with real release bytes and mocked executor APIs.
local MAIN = -- CLARIS_MAIN_ASSET
local WIND = -- CLARIS_WIND_ASSET
local passed = 0
local function test(name, fn)
    local ok, message = pcall(fn)
    assert(ok, name .. ": " .. tostring(message))
    passed = passed + 1
end
local function fixture(files)
    local f = {files = files or {}, folders = {}, requests = {}, env = {}, queued = {}, time = 0}
    getgenv = function() return f.env end
    isfile = function(path) return f.files[path] ~= nil end
    readfile = function(path) assert(f.files[path]); return f.files[path] end
    writefile = function(path, source) f.files[path] = source end
    isfolder = function(path) return f.folders[path] == true end
    makefolder = function(path) f.folders[path] = true end
    os.clock = function() return f.time end
    task = {
        spawn = function(fn)
            -- Lua 5.1 cannot yield across pcall; defer complete mocked replies.
            if f.async then f.queued[#f.queued + 1] = fn else fn() end
        end,
        wait = function(seconds)
            f.time = f.time + (seconds or 0.03)
            local queued = f.queued
            f.queued = {}
            if f.async and #queued > 0 then
                assert(#queued == 2, "Both downloads must start before either is awaited")
            end
            for _, fn in ipairs(queued) do fn() end
        end,
    }
    game = {HttpGet = function(_, url)
        f.requests[#f.requests + 1] = url
        if f.networkError then error("Offline") end
        if f.wrongBytes then return "return {}" end
        return url:find("vendor/WindUI.lua", 1, true) and WIND or MAIN
    end}
    loadstring = function(source, label)
        assert(source == MAIN or source == WIND, "Only verified release bytes may execute")
        if label == "Claris WindUI" then return function() return {} end end
        assert(label == "Claris Growblox Autofarm")
        return function() return "started" end
    end
    function f.load()
-- CLARIS_LOADER_SOURCE
    end
    return f
end

test("Uncached release downloads start together and populate the cache", function()
    local f = fixture()
    f.async = true
    assert(f.load() == "started" and #f.requests == 2)
    local assets = 0
    for path, source in pairs(f.files) do
        assert(path:find("ClarisGrowblox/cache/", 1, true))
        assert(source == MAIN or source == WIND)
        assets = assets + 1
    end
    assert(assets == 2 and f.env.ClarisGrowbloxLoaderDebug:find("downloaded", 1, true))
end)

test("A new server environment reuses verified release files while offline", function()
    local first = fixture()
    first.load()
    local next = fixture(first.files)
    next.networkError = true
    assert(next.load() == "started" and #next.requests == 0)
    assert(next.env.ClarisGrowbloxLoaderDebug:find("main cached; WindUI cached", 1, true))
end)

test("A damaged cached script is downloaded again without reloading cached WindUI", function()
    local first = fixture()
    first.load()
    for path in pairs(first.files) do
        if path:sub(-8) == "main.lua" then
            -- Same length, different bytes: size alone must not pass validation.
            first.files[path] = "!" .. MAIN:sub(2)
        end
    end
    local next = fixture(first.files)
    assert(next.load() == "started" and #next.requests == 1)
    assert(not next.requests[1]:find("WindUI.lua", 1, true))
end)

test("Unavailable or unwritable cache files do not prevent ordinary loading", function()
    local f = fixture()
    readfile, writefile, isfile, isfolder, makefolder = nil, nil, nil, nil, nil
    assert(f.load() == "started" and #f.requests == 2)
    f = fixture()
    writefile = function() error("Disk full") end
    assert(f.load() == "started" and #f.requests == 2)
end)

test("Incorrect download bytes are rejected before compiling or caching them", function()
    local f = fixture()
    f.wrongBytes = true
    local ok, message = pcall(f.load)
    assert(not ok and tostring(message):find("release bytes do not match", 1, true))
    assert(next(f.files) == nil and f.env.ClarisGrowbloxWindUI == nil)
end)

test("A running farm prevents reload before any cache or network work", function()
    local f = fixture()
    f.env.ClarisGrowbloxApp = {job = "transfer", pending = 0}
    local ok, message = pcall(f.load)
    assert(not ok and tostring(message):find("Stop the running farm", 1, true) and #f.requests == 0)
end)

return string.format("%d generated-loader cache/download tests passed", passed)
