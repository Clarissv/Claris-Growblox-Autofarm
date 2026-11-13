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
    if options.fullWorld then minX, maxX, minY, maxY = 0, map.w - 1, 0, map.h - 2 end
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
            if options.step and expansions % 64 == 0 then options.step() end
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

function Navigation.pickupGoal(map, state, drop)
    local start = {x = math.floor(state.x), y = math.floor(state.y - 0.01)}
    local centerX, centerY = math.floor(drop.x), math.floor(drop.y)
    local candidates = {}
    for y = centerY - 1, centerY + 1 do
        for x = centerX - 1, centerX + 1 do
            if x >= 0 and x < map.w and y >= 0 and y < map.h - 1
                and math.abs(drop.x - (x + 0.5)) <= 1.25
                and drop.y >= y - 1.5 and drop.y <= y + 1.25
                and not map.solid(x, y) and not (map.danger and map.danger(x, y))
                and not (map.danger and map.danger(x, y + 1))
                and (map.solid(x, y + 1) or (map.platform and map.platform(x, y + 1))) then
                local distance = math.abs(drop.x - (x + 0.5)) + math.abs(drop.y - (y + 0.5))
                table.insert(candidates, {x = x, y = y, score = distance})
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score < b.score end)
    for _, goal in ipairs(candidates) do
        if Navigation.plan(map, start, goal) then return {x = goal.x, y = goal.y} end
    end
    return nil, "No reachable floor or platform is close to this harvested drop."
end

return Navigation
