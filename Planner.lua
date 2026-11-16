-- WritPath planner: picks writs by price for a rep target and builds the guide route for them.
--  * customers: WritDB.lua, overridden by map pins learned in game (WritPathLearned)
--  * prices:    Auctionator's last scan, read live (writ + requested items, minus what you already own)
--  * picking:   cheapest gold per rep, plus travel time priced at "time worth" silver per minute;
--               one writ per customer per day, customers already used today are skipped
--  * route:     shortest order through the picked customers, then handed to the guide window
-- /writs plan  opens the planner on your own writs ("My writs"); /writs buy  opens the price planner

local DB, CUST = WritPath_Writs, WritPath_Customers
local REP = { Journeyman = 75, Expert = 125, Artisan = 200 }
local POUCH_GUESS = { Journeyman = 1200, Expert = 6700, Artisan = 7456 }   -- copper, until your own log has some
local G, W_, Y = "|cFF00FF25", "|cFFFCDC00", "|cFF00BCD4"
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

-- how many you have: in your bags, plus what WritPath bought for you that's still in the mail
local function Count(id)
  if not id then return 0 end
  local n = 0
  if C_Item and C_Item.GetItemCount then n = C_Item.GetItemCount(id) or 0
  elseif GetItemCount then n = GetItemCount(id) or 0 end
  return n + (WritPath_InMail and WritPath_InMail(id) or 0)
end
local function Done(q) return C_QuestLog.IsQuestFlaggedCompleted(q) end
local function InLog(q) return C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q) ~= nil end
local function ItemName(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemNameByID then local n = C_Item.GetItemNameByID(id); if n then return n end end
  return GetItemInfo and (GetItemInfo(id)) or nil
end
local function MapName(m) local i = m and C_Map.GetMapInfo(m); return i and i.name or "?" end

local function Coins(c)
  c = math.floor((c or 0) + 0.5)
  local neg = c < 0; c = math.abs(c)
  local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
  local t = g > 0 and (g .. "g " .. s .. "s") or (s > 0 and (s .. "s " .. c % 100 .. "c") or (c % 100 .. "c"))
  return (neg and "-" or "") .. t
end

---------------------------------------------------------------- learning customers from map pins
local zoneMaps
local function ZoneMaps()
  if zoneMaps then return zoneMaps end
  zoneMaps = {}
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  for m = 1, 5000 do
    local info = C_Map.GetMapInfo(m)
    if info and info.mapType == zoneType then zoneMaps[#zoneMaps + 1] = m end
  end
  return zoneMaps
end

-- a pin shows on every zone map around it, squashed to the edge on the neighbours:
-- keep the one furthest from any edge
local function FindPin(q)
  local best, bestScore
  for _, m in ipairs(ZoneMaps()) do
    local ok, pins = pcall(C_QuestLog.GetQuestsOnMap, m)
    if ok and pins then
      for _, p in ipairs(pins) do
        if p.questID == q and p.x then
          local s = math.min(p.x, 1 - p.x, p.y, 1 - p.y)
          if not bestScore or s > bestScore then
            best, bestScore = { map = m, x = math.floor(p.x * 1000 + 0.5) / 10, y = math.floor(p.y * 1000 + 0.5) / 10 }, s
          end
        end
      end
    end
  end
  return best
end

local Customer   -- defined below

local learnTries = 0
local Learn
local function Learned()   -- something new: an open planner shows it straight away
  if WritPath_PlannerLearned then WritPath_PlannerLearned() end
end

function Learn()
  local missing, found = false, false
  for id, w in pairs(DB) do
    if not WritPathLearned[id] and InLog(w.q) then
      local pin = FindPin(w.q)
      if not pin then missing = true end
      if pin then
        found = true
        pin.t = time(); WritPathLearned[id] = pin
        Print(("Learned where %s goes: %s %.1f, %.1f"):format(w.name, MapName(pin.map), pin.x, pin.y))
        -- a planned route waiting on this spot gets the exact point now
        for _, s in ipairs(WritPathNav and WritPathNav.route or {}) do
          if s.writ == id then
            local c = Customer(id)
            s.at = { pin.map, pin.x, pin.y, c and c.npc or w.name }
            for i = #s.lines, 1, -1 do if s.lines[i]:find("Exact spot unknown") then table.remove(s.lines, i) end end
          end
        end
        if WritPath_Refresh then WritPath_Refresh() end
      end
    end
  end
  if found then Learned() end
  -- a pin that isn't on the map yet: look again every 5 seconds, for up to a minute
  if missing and learnTries < 12 then learnTries = learnTries + 1; C_Timer.After(5, Learn) end
  if not missing then learnTries = 0 end
end

-- At a turn-in you're standing next to the customer and the game knows their name: the best data there is.
-- It's saved for the writ and for its customer, so every writ that customer takes gets the exact spot.
local turnin
local function NoteTurnin()
  local name = UnitName("npc") or UnitName("target")
  local here = WritPath_Travel.PlayerPoint()
  if name and here then turnin = { npc = name, map = here.map, x = here.x, y = here.y, at = GetTime() } end
end
local function LearnTurnin(q)
  if not (turnin and GetTime() - turnin.at < 120) then return end
  for id, w in pairs(DB) do
    if w.q == q then
      local old = WritPathLearned[id]
      local spot = { map = turnin.map, x = math.floor(turnin.x * 10 + 0.5) / 10, y = math.floor(turnin.y * 10 + 0.5) / 10,
                     npc = turnin.npc, src = "turnin", t = time() }
      WritPathLearned[id] = spot
      WritPathLearned.npcs = WritPathLearned.npcs or {}
      local key = w.c or ("npc:" .. turnin.npc)
      local known = WritPathLearned.npcs[key]
      WritPathLearned.npcs[key] = { map = spot.map, x = spot.x, y = spot.y, npc = turnin.npc, t = spot.t }
      local base = w.c and CUST[w.c]
      if not known and not (base and base.x and base.npc == turnin.npc) then
        Print(("Learned %s's spot for %s: %s %.1f, %.1f."):format(turnin.npc, w.name, MapName(spot.map), spot.x, spot.y))
        Learned()
      end
      return
    end
  end
end

-- where a writ is turned in: your learned pin first, then the database; nil when nobody knows yet.
-- key identifies the customer (one writ per customer per day)
function Customer(id)
  local w = DB[id]; if not w then return nil end
  local base = w.c and CUST[w.c]
  local LW = WritPathLearned or {}
  local L = LW[id]
  if type(L) == "table" and L.map then
    local key = w.c or (L.npc and ("npc:" .. L.npc))
    if not key then   -- no name known: learned pins on the same spot are the same customer
      local low = id
      for oid, o in pairs(LW) do   -- writ pins only (numeric keys); the rest is travel data
        if type(oid) == "number" and type(o) == "table" and o.map == L.map and o.x and math.abs(o.x - L.x) < 0.8
           and math.abs(o.y - L.y) < 0.8 and oid < low then low = oid end
      end
      key = (DB[low] and DB[low].c) or ("pin" .. low)
    end
    return { key = key, npc = L.npc or (base and base.npc), map = L.map, x = L.x, y = L.y, exact = true }
  end
  -- this customer's spot learned at another writ's turn-in
  local N = w.c and LW.npcs and LW.npcs[w.c]
  if N then return { key = w.c, npc = N.npc or (base and base.npc), map = N.map, x = N.x, y = N.y, exact = true } end
  if not (base and base.map) then return nil end
  return { key = w.c, npc = base.npc, map = base.map, x = base.x or 50, y = base.y or 50, exact = base.x ~= nil }
end

local function UsedToday()
  local used = {}
  for id, w in pairs(DB) do
    if Done(w.q) then local c = Customer(id); if c then used[c.key] = w.name end end
  end
  return used
end

---------------------------------------------------------------- prices
-- a price: what the auction house really asked in the last half hour (seen while buying: a stack you'd have
-- to take whole counts in full), else Auctionator's last scan
local SEEN_FOR = 30 * 60
local function Price(item)
  if not item then return nil end
  local seen = WritPathNav and WritPathNav.seenPrice and WritPathNav.seenPrice[item]
  if seen and time() - (seen.t or 0) < SEEN_FOR then return seen.u end
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then return nil end
  local ok, p = pcall(api.GetAuctionPriceByItemID, "WritPath", item)
  return ok and p or nil
end

-- copper to do this writ now: the writ (unless you have it) plus the items you're still missing
local function Cost(id)
  local w = DB[id]
  local have = Count(id) > 0 or InLog(w.q)
  local writ = have and 0 or Price(id)
  if not writ then return nil, "no AH price for the writ" end
  if not w.req then return nil, "requested item unknown" end
  local need = math.max(0, (w.n or 1) - Count(w.req))
  local item = need == 0 and 0 or Price(w.req)
  if not item then return nil, "no AH price for " .. (ItemName(w.req) or "the item") end
  return writ + item * need, have, need
end

local function PouchAverage(tier)
  local sum, n = 0, 0
  for _, e in ipairs(WritPathMoney and WritPathMoney.log or {}) do
    if e.tier == tier and e.paid then sum, n = sum + e.paid, n + 1 end
  end
  return n > 0 and sum / n or POUCH_GUESS[tier]
end

---------------------------------------------------------------- travel (Travel.lua: real paths)
local Travel = WritPath_Travel
local Pos, PlayerPos = Travel.Point, Travel.PlayerPoint
local memo = setmetatable({}, { __mode = "k" })
local function Secs(a, b)
  if not (a and b) then return 600 end
  local row = memo[a]; if not row then row = setmetatable({}, { __mode = "k" }); memo[a] = row end
  local t = row[b]
  if not t then t = Travel.Time(a, b); row[b] = t end
  return t
end
local function ResetMemo() memo = setmetatable({}, { __mode = "k" }) end

local function PathSecs(start, route)
  local t, prev = 0, start
  for _, p in ipairs(route) do t = t + Secs(prev, p.pos) + 20; prev = p.pos end
  return t
end

local function InsertAt(start, route, pos)
  local best, at
  for i = 1, #route + 1 do
    local prev = i == 1 and start or route[i - 1].pos
    local nxt = route[i] and route[i].pos
    local dt = Secs(prev, pos) + (nxt and (Secs(pos, nxt) - Secs(prev, nxt)) or 0)
    if not best or dt < best then best, at = dt, i end
  end
  return best, at
end

local function TwoOpt(start, route)
  local improved = true
  while improved do
    improved = false
    for i = 1, #route - 1 do
      for j = i + 1, #route do
        local before = PathSecs(start, route)
        local a, b = i, j
        while a < b do route[a], route[b] = route[b], route[a]; a, b = a + 1, b - 1 end
        if PathSecs(start, route) < before - 1 then improved = true
        else a, b = i, j; while a < b do route[a], route[b] = route[b], route[a]; a, b = a + 1, b - 1 end end
      end
    end
  end
end

---------------------------------------------------------------- picking writs
-- every writ you could do right now, with why the others can't be
local function Candidates(zoneOnly)
  local used, list, skipped = UsedToday(), {}, {}
  for id, w in pairs(DB) do
    local rep = REP[w.tier]
    local c = Customer(id)
    local why
    if Done(w.q) then why = "done today"
    elseif not c then why = "customer unknown"
    elseif used[c.key] then why = "customer used today (" .. used[c.key] .. ")"
    elseif not c.exact and not zoneOnly then why = "only the zone is known" end
    local cost, have, need
    if not why then cost, have = Cost(id); if not cost then why = have end end
    if why then skipped[#skipped + 1] = { id = id, why = why }
    else
      local _, h, n = Cost(id)
      list[#list + 1] = { id = id, w = w, rep = rep, cost = cost, have = h, need = n, c = c, pos = Pos(c.map, c.x, c.y) }
    end
  end
  return list, skipped
end

---------------------------------------------------------------- the writs you already have, in the best order
-- best order from where you stand: every order tried (with pruning) up to EXACT stops, else insertion + 2-opt
local EXACT = 10
local function BestOrder(start, stops, quick)
  local n = #stops
  if n <= 1 then return stops end
  -- the same writs always go in the same order, whichever plan they came from
  local sorted = {}
  for i, s in ipairs(stops) do sorted[i] = s end
  table.sort(sorted, function(a, b) return a.id < b.id end)
  stops = sorted
  local pts = { start }
  for i, s in ipairs(stops) do pts[i + 1] = s.pos end
  local T = {}   -- travel seconds between every pair, worked out once
  for i = 1, n + 1 do T[i] = {}; for j = 1, n + 1 do T[i][j] = i == j and 0 or Secs(pts[i], pts[j]) end end
  -- a good first answer: cheapest insertion, then 2-opt
  local order = {}
  for i = 1, n do
    local best, at
    for k = 1, #order + 1 do
      local a, b = k == 1 and 1 or order[k - 1], order[k]
      local d = T[a][i + 1] + (b and (T[i + 1][b] - T[a][b]) or 0)
      if not best or d < best then best, at = d, k end
    end
    table.insert(order, at, i + 1)
  end
  local function Len(o) local t, p = 0, 1; for _, j in ipairs(o) do t = t + T[p][j]; p = j end; return t end
  -- 2-opt: reverse a stretch of the route when that's shorter. Only the two joining legs and the stretch's
  -- direction change, so each try is worked out from running sums instead of re-measuring the whole route.
  local F, B = {}, {}   -- F[k]: time along order[1..k] forwards; B[k]: the same stretch backwards
  local function Sums()
    F[1], B[1] = 0, 0
    for k = 2, n do F[k] = F[k - 1] + T[order[k - 1]][order[k]]; B[k] = B[k - 1] + T[order[k]][order[k - 1]] end
  end
  Sums()
  local passes, improved = 0, true
  while improved and passes < 50 do
    improved, passes = false, passes + 1
    for i = 1, n - 1 do
      for j = i + 1, n do
        local prev = i == 1 and 1 or order[i - 1]
        local nxt = order[j + 1]
        local oi, oj = order[i], order[j]
        local delta = T[prev][oj] + (nxt and T[oi][nxt] or 0) + (B[j] - B[i])
                    - T[prev][oi] - (nxt and T[oj][nxt] or 0) - (F[j] - F[i])
        if delta < -0.5 then
          local a, b = i, j
          while a < b do order[a], order[b] = order[b], order[a]; a, b = a + 1, b - 1 end
          Sums(); improved = true
        end
      end
    end
  end
  -- exact: try every order, dropping any branch already longer than the best found
  if n <= EXACT and not quick then
    local bestLen, bestOrder = Len(order), { unpack(order) }
    local used, cur = {}, {}
    local function DFS(depth, last, len)
      if len >= bestLen then return end
      if depth > n then bestLen, bestOrder = len, { unpack(cur) }; return end
      for j = 2, n + 1 do
        if not used[j] then
          used[j] = true; cur[depth] = j
          DFS(depth + 1, j, len + T[last][j])
          used[j] = nil
        end
      end
    end
    DFS(1, 1, 0)
    order = bestOrder
  end
  local out = {}
  for k, j in ipairs(order) do out[k] = stops[j - 1] end
  return out
end

-- writs in your bags or quest log; one per customer today, the rest wait for tomorrow
local function PlanOwned(only, skipQuest)   -- only: just these writ ids; skipQuest: a quest just handed in
  Travel.Reset(); ResetMemo()
  local used = UsedToday()
  local stops, later, unknown, byCustomer = {}, {}, {}, {}
  local owned = {}
  for id, w in pairs(DB) do
    if (Count(id) > 0 or InLog(w.q)) and not Done(w.q) and w.q ~= skipQuest and (not only or only[id]) then owned[#owned + 1] = id end
  end
  table.sort(owned, function(a, b)    -- higher rep first, so a shared customer gets the better writ today
    local ra, rb = REP[DB[a].tier] or 0, REP[DB[b].tier] or 0
    if ra ~= rb then return ra > rb end
    return a < b
  end)
  for _, id in ipairs(owned) do
    local w, c = DB[id], Customer(id)
    if not c then
      unknown[#unknown + 1] = { id = id, w = w, why = InLog(w.q) and "map pin not read yet" or "accept it so its map pin shows where it goes" }
    elseif used[c.key] then
      later[#later + 1] = { id = id, w = w, why = "already handed in to this customer today (" .. used[c.key] .. ")" }
    elseif byCustomer[c.key] then
      later[#later + 1] = { id = id, w = w, why = "same customer as " .. byCustomer[c.key].w.name }
    else
      local cost, have, need = Cost(id)
      local stop = { id = id, w = w, rep = REP[w.tier] or 0, c = c, pos = Pos(c.map, c.x, c.y),
                     cost = cost or 0, have = true, need = need or math.max(0, (w.n or 1) - Count(w.req)) }
      byCustomer[c.key] = stop
      stops[#stops + 1] = stop
    end
  end
  local start = PlayerPos()
  local route = BestOrder(start, stops)
  local rep, cost, pouches = 0, 0, 0
  for _, p in ipairs(route) do rep, cost, pouches = rep + p.rep, cost + p.cost, pouches + PouchAverage(p.w.tier) end
  return { route = route, rep = rep, cost = cost, secs = PathSecs(start, route), pouches = pouches, target = rep,
           start = start, later = later, unknown = unknown, owned = #owned, mine = true }
end

-- what to buy for a rep target: your own writs first (already paid for, they count toward the target),
-- then writs to fill the rest; never two writs for one customer, never a customer used today; the whole
-- set in the best order.
--   Cheapest: exact. A knapsack in steps of 25 rep over the customers, at most one writ each, for the
--             least gold that reaches the target.
--   Fastest:  starts from the quickest greedy pick (and from the cheapest set), then keeps swapping or
--             dropping writs while the whole route gets shorter.
--   PlanBoth makes sure the fastest is never slower than the cheapest, nor the cheapest dearer than the fastest.

local function RepOf(set) local r = 0; for _, c in ipairs(set) do r = r + c.rep end; return r end
local function CostOf(set) local r = 0; for _, c in ipairs(set) do r = r + c.cost end; return r end
local function Join(a, b) local t = {}; for _, x in ipairs(a) do t[#t + 1] = x end; for _, x in ipairs(b) do t[#t + 1] = x end; return t end

-- the writs you could buy, minus any whose customer one of your own writs already takes
local function Buyable(zoneOnly, ownedKeys)
  local list = {}
  for _, c in ipairs((Candidates(zoneOnly))) do
    if c.pos and not (Count(c.id) > 0 or InLog(c.w.q)) and not ownedKeys[c.c.key] then list[#list + 1] = c end
  end
  return list
end

local function CheapestSet(cands, need)
  if need <= 0 then return {} end
  local U = math.ceil(need / 25)
  local groups, keys = {}, {}
  for _, c in ipairs(cands) do
    local g = groups[c.c.key]
    if not g then g = {}; groups[c.c.key] = g; keys[#keys + 1] = c.c.key end
    g[#g + 1] = c
  end
  table.sort(keys)
  local INF = math.huge
  local dp = { [0] = 0 }
  for u = 1, U do dp[u] = INF end
  local picks = {}
  for gi, key in ipairs(keys) do
    local nd, pk = {}, {}
    for u = 0, U do nd[u] = dp[u] end
    for _, c in ipairs(groups[key]) do
      local r = math.floor(c.rep / 25)
      for u = 0, U do
        if dp[u] < INF then
          local v = math.min(U, u + r)
          if dp[u] + c.cost < nd[v] then nd[v] = dp[u] + c.cost; pk[v] = { c = c, from = u } end
        end
      end
    end
    picks[gi], dp = pk, nd
  end
  local u = U
  while u > 0 and dp[u] == INF do u = u - 1 end   -- target out of reach: the most rep there is
  local set = {}
  for gi = #keys, 1, -1 do
    local p = picks[gi][u]
    if p then set[#set + 1] = p.c; u = p.from end
  end
  return set
end

local function GreedyFast(start, owned, cands, need)
  local route, rep, keys, set = {}, 0, {}, {}
  for _, p in ipairs(owned) do route[#route + 1] = p end
  while rep < need do
    local best, bestScore, bestAt
    for _, c in ipairs(cands) do
      if not keys[c.c.key] and not c.inGreedy then
        local dt, at = InsertAt(start, route, c.pos)
        local score = (dt + 20) / math.min(c.rep, need - rep) + c.cost * 1e-7
        if not bestScore or score < bestScore then best, bestScore, bestAt = c, score, at end
      end
    end
    if not best then break end
    best.inGreedy, keys[best.c.key] = true, true
    table.insert(route, bestAt, best); set[#set + 1] = best; rep = rep + best.rep
  end
  for _, c in ipairs(cands) do c.inGreedy = nil end
  return set
end

local function Improve(start, owned, cands, need, seed)
  if RepOf(seed) < need then return seed end   -- can't reach the target: nothing to swap or drop
  local function Eval(set) return PathSecs(start, BestOrder(start, Join(owned, set), true)) end
  -- only the 30 writs closest to this route are worth trying as swaps
  local route = Join(owned, seed)
  local function Near(c)
    local best = Secs(start, c.pos)
    for _, p in ipairs(route) do local t = Secs(p.pos, c.pos); if t < best then best = t end end
    return best
  end
  local near = {}
  for _, c in ipairs(cands) do near[#near + 1] = { c = c, d = Near(c) } end
  table.sort(near, function(a, b) return a.d < b.d end)
  cands = {}
  for i = 1, math.min(30, #near) do cands[i] = near[i].c end
  local cur, curT = seed, Eval(seed)
  for _ = 1, 10 do
    local bestT, bestCost, bestSet = curT, CostOf(cur), nil
    local function Try(set)
      local t = Eval(set)
      if t < bestT - 1 or (t < bestT + 1 and CostOf(set) < bestCost) then bestT, bestCost, bestSet = t, CostOf(set), set end
    end
    local have, total = {}, RepOf(cur)
    for _, c in ipairs(cur) do have[c.c.key] = c end
    for i = 1, #cur do
      if total - cur[i].rep >= need then                  -- drop one
        local t = {}; for j, c in ipairs(cur) do if j ~= i then t[#t + 1] = c end end
        Try(t)
      end
      for _, c in ipairs(cands) do                        -- swap one for another
        local holder = have[c.c.key]
        if c ~= cur[i] and (not holder or holder == cur[i]) and total - cur[i].rep + c.rep >= need then
          local t = {}; for j, x in ipairs(cur) do t[j] = (j == i) and c or x end
          Try(t)
        end
      end
    end
    if not bestSet then break end
    cur, curT = bestSet, bestT
  end
  return cur
end

local function Finish(start, owned, set, target, mine, mode)
  local route = BestOrder(start, Join(owned, set))
  local rep, cost, pouches, bought = 0, 0, 0, 0
  for _, p in ipairs(route) do
    rep, cost, pouches = rep + p.rep, cost + p.cost, pouches + PouchAverage(p.w.tier)
    if not p.have then bought = bought + 1 end
  end
  return { route = route, rep = rep, cost = cost, secs = PathSecs(start, route), pouches = pouches, target = target,
           start = start, later = mine.later, unknown = mine.unknown, bought = bought, ownedUsed = #mine.route, mode = mode,
           set = set }
end

local function PlanBoth(target, zoneOnly)
  local mine = PlanOwned()
  local start, owned, ownedKeys = mine.start, mine.route, {}
  for _, p in ipairs(owned) do ownedKeys[p.c.key] = true end
  local cands = Buyable(zoneOnly, ownedKeys)
  local need = target - RepOf(owned)
  local cheapSet = CheapestSet(cands, need)
  local cheap = Finish(start, owned, cheapSet, target, mine, "cheap")
  local fast
  if RepOf(cheapSet) < need then
    -- the target is out of reach today: every customer has to be used, so there's nothing to choose
    -- between and the fastest plan is the same trip
    fast = cheap
  else
    local fastA = Improve(start, owned, cands, need, GreedyFast(start, owned, cands, need))
    local fastB = Improve(start, owned, cands, need, cheapSet)
    local fa, fb = Finish(start, owned, fastA, target, mine, "fast"), Finish(start, owned, fastB, target, mine, "fast")
    fast = (fb.secs < fa.secs or (fb.secs == fa.secs and fb.cost < fa.cost)) and fb or fa
  end
  if cheap.secs < fast.secs then fast = Finish(start, owned, cheapSet, target, mine, "fast") end   -- never slower
  if fast.cost < cheap.cost and fast.rep >= math.min(target, cheap.rep) then cheap = Finish(start, owned, fast.set, target, mine, "cheap") end
  -- the same writs are the same trip: share the quicker route so the two can't disagree on time
  local function Ids(plan) local t = {}; for _, p in ipairs(plan.route) do t[#t + 1] = p.id end; table.sort(t); return table.concat(t, ",") end
  if Ids(cheap) == Ids(fast) then
    local best = (fast.secs < cheap.secs) and fast or cheap
    cheap.route, cheap.secs, fast.route, fast.secs = best.route, best.secs, best.route, best.secs
  end
  -- when the target can't be reached: the most rep today, and what holds it back
  local function Ceiling(list)
    local best = {}
    for _, c in ipairs(list) do best[c.c.key] = math.max(best[c.c.key] or 0, c.rep) end
    local r = RepOf(owned); for _, v in pairs(best) do r = r + v end
    return r
  end
  local usedCount = 0; for _ in pairs(UsedToday()) do usedCount = usedCount + 1 end
  local short = { max = Ceiling(cands), usedToday = usedCount,
                  withZone = (not zoneOnly) and Ceiling(Buyable(true, ownedKeys)) or nil }
  cheap.short, fast.short = short, short
  return { cheap = cheap, fast = fast }
end

-- one plan: "cheap", "fast", or a number (gold plus travel at that many copper per minute, greedy)
local function Plan(target, mode, zoneOnly)
  if mode == "cheap" or mode == "fast" then return PlanBoth(target, zoneOnly)[mode] end
  local mine = PlanOwned()
  local start, owned, ownedKeys = mine.start, mine.route, {}
  for _, p in ipairs(owned) do ownedKeys[p.c.key] = true end
  local cands = Buyable(zoneOnly, ownedKeys)
  local route, rep, keys, set = Join(owned, {}), RepOf(owned), {}, {}
  while rep < target do
    local best, bestScore, bestAt
    for _, c in ipairs(cands) do
      if not c.taken and not keys[c.c.key] then
        local dt, at = InsertAt(start, route, c.pos)
        local score = (c.cost + mode * dt / 60) / math.min(c.rep, target - rep)
        if not bestScore or score < bestScore then best, bestScore, bestAt = c, score, at end
      end
    end
    if not best then break end
    best.taken, keys[best.c.key] = true, true
    table.insert(route, bestAt, best); set[#set + 1] = best; rep = rep + best.rep
  end
  return Finish(start, owned, set, target, mine, mode)
end

---------------------------------------------------------------- turning a plan into guide steps
local function Crossing(toInst)
  local horde = UnitFactionGroup("player") == "Horde"
  local dest = toInst == 1 and "Kalimdor" or "the Eastern Kingdoms"
  if horde then return "{zeppelin} Cross to " .. G .. dest .. "|r: zeppelin Orgrimmar - Undercity (or boat Ratchet - Booty Bay)" end
  return "{boat} Cross to " .. G .. dest .. "|r: boat Menethil Harbor - Theramore or Auberdine (or the tram via Ironforge)"
end

-- guide steps for the way from one place to the next
local function TravelSteps(steps, from, to, label)
  for _, leg in ipairs(Travel.Legs(from, to)) do
    if leg.kind == "unknown" then
      steps[#steps + 1] = { lines = { Crossing(to.inst) }, done = { arrive = { leg.into } } }
    else
      local what = leg.kind == "cross" and ("To " .. MapName(leg.into))
                or leg.kind == "fly" and (leg.fp or "Flight master") or "Dock"
      local done = leg.kind == "fly" and { taxi = true, arrive = { leg.into } } or { arrive = { leg.into } }
      steps[#steps + 1] = { at = { leg.at.map, leg.at.x, leg.at.y, what }, lines = { leg.text }, done = done }
    end
  end
end

local FP_DETOUR, GREY_ = 800, "|cFFAAAAAA"   -- yards from a customer to suggest an unlearned flight path
local function Steps(plan)
  local steps, buy, quests, items, suggested = {}, {}, {}, {}, {}
  for _, p in ipairs(plan.route) do
    if not p.have then buy[#buy + 1] = "{buy} " .. Y .. "Craftsman's Writ: " .. p.w.name .. "|r" end
    if p.need > 0 then
      buy[#buy + 1] = "{buy} " .. Y .. (ItemName(p.w.req) or p.w.name) .. "|r" .. (p.need > 1 and (" x" .. p.need) or "")
    end
    quests[#quests + 1] = p.w.q
    items[#items + 1] = { p.w.req, p.w.n or 1, p.w.q }
  end
  local first = { "{buy} At the auction house buy:" }
  for _, l in ipairs(buy) do first[#first + 1] = l end
  first[#first + 1] = W_ .. "Then right-click every writ to accept it|r"
  if #buy == 0 then first = { "{buy} You have every writ and item: right-click each writ to accept it" } end
  steps[1] = { lines = first, done = { ready = { quests = quests, items = items } } }

  local prev = plan.start
  for _, p in ipairs(plan.route) do
    if prev and p.pos then TravelSteps(steps, prev, p.pos) end
    local zone, lines = MapName(p.c.map), {}
    lines[#lines + 1] = "{goto} Go to " .. G .. (p.c.npc or "the writ customer") .. "|r in " .. zone
    lines[#lines + 1] = "{turnin} Hand in " .. Y .. p.w.name .. "|r"
    if not p.c.exact then lines[#lines + 1] = W_ .. "Exact spot unknown: once you accept the writ, its map pin sets the arrow|r" end
    steps[#steps + 1] = { at = { p.c.map, p.c.x, p.c.y, p.c.npc or p.w.name }, lines = lines,
                          done = { quests = { p.w.q } }, writ = p.id }
    -- a flight path you don't have close to this customer: worth grabbing while you're here
    local fp = Travel.UnlearnedNear and Travel.UnlearnedNear(p.pos, FP_DETOUR)
    if fp and not suggested[fp.id] then
      suggested[fp.id] = true
      local town = (fp.name or "the flight master"):match("^([^,]+)") or fp.name
      steps[#steps + 1] = { at = { fp.map, fp.x, fp.y, "Flight master" },
                            lines = { "{fp} Learn the flight path at " .. G .. town .. "|r while you're here",
                                      GREY_ .. "Talk to the flight master. Not needed? /writs next skips it.|r" },
                            done = { taxiMap = true } }
    end
    prev = p.pos or prev
  end
  return steps
end

---------------------------------------------------------------- planner window
-- Styled through EllesmereUI's skinning API when it's installed (its theme, font and accent, kept in sync);
-- otherwise a plain flat dark look. Every text has a set width and wraps; the window grows to fit.
local W = 470                     -- window width
local PAD = 12
local INNER = W - PAD * 2
local GREY = "|cFFAAAAAA"
local TIER = { Journeyman = "|cFF1EFF00J|r", Expert = "|cFF0070DDE|r", Artisan = "|cFFA335EEA|r" }

local f = CreateFrame("Frame", "WritPathPlanner", UIParent, "BackdropTemplate")
f:SetSize(W, 160); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:Hide()
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
tinsert(UISpecialFrames, "WritPathPlanner")   -- Escape closes it

local fonts, buttons, skin = {}, {}, nil   -- skin: EllesmereUI's skinning API, once it has called us
local function Text(parent, template, width, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true)
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
  if width then fs:SetWidth(width) end
  fonts[#fonts + 1] = fs
  if skin then skin.Font(fs) end   -- rows made after login get the EllesmereUI font too
  return fs
end
local function Btn(parent, label)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); btn:SetHeight(22); btn:SetText(label)
  buttons[#buttons + 1] = btn
  return btn
end
local function FitWidth(btn)
  local fs = btn:GetFontString()
  local w = fs and fs:GetStringWidth()
  btn:SetWidth(math.max(60, (type(w) == "number" and w or 40) + 26))
end

local head = Text(f, "GameFontNormal"); head:SetPoint("TOPLEFT", PAD, -9); head:SetText("Writ Planner")
local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton"); closeX:SetSize(22, 22); closeX:SetPoint("TOPRIGHT", -3, -3)

-- tabs: "My writs" and "Buy writs", with an accent bar under the active one
local mineBtn, buyBtn = Btn(f, "My writs"), Btn(f, "Buy writs")
mineBtn:SetPoint("TOPLEFT", PAD - 2, -32); buyBtn:SetPoint("LEFT", mineBtn, "RIGHT", 4, 0)
local tabBar = f:CreateTexture(nil, "OVERLAY"); tabBar:SetHeight(2); tabBar:SetColorTexture(1, 0.82, 0, 1)
-- how old the prices are: Auctionator's last full scan, and the oldest price the shown plan uses
local ageText = Text(f, "GameFontHighlightSmall", 200, "RIGHT")
ageText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -32)

-- "Buy writs" controls
local buyRow = CreateFrame("Frame", nil, f); buyRow:SetSize(INNER, 24)
local repL = Text(buyRow); repL:SetPoint("LEFT", 0, 0); repL:SetText("Rep target"); repL:SetWordWrap(false)
local repBox = CreateFrame("EditBox", nil, buyRow, "InputBoxTemplate"); repBox:SetSize(54, 20); repBox:SetAutoFocus(false)
repBox:SetNumeric(true); repBox:SetText("1000"); repBox:SetPoint("LEFT", repL, "RIGHT", 10, 0)
local zoneChk = CreateFrame("CheckButton", nil, buyRow, "UICheckButtonTemplate"); zoneChk:SetSize(22, 22)
zoneChk:SetPoint("LEFT", repBox, "RIGHT", 12, 0)
local planBtn = Btn(buyRow, "Plan"); planBtn:SetPoint("RIGHT", 0, 0)
local zoneL = Text(buyRow); zoneL:SetPoint("LEFT", zoneChk, "RIGHT", 2, 0); zoneL:SetPoint("RIGHT", planBtn, "LEFT", -8, 0)
zoneL:SetText("Include customers known by zone only")
buyRow:Hide()

-- the two answers for a rep target, side by side; click one to see its writs
local CARD_W = math.floor((INNER - 8) / 2)
local function Card()
  local c = CreateFrame("Button", nil, f, "BackdropTemplate"); c:SetWidth(CARD_W)
  c.text = Text(c, nil, CARD_W - 16); c.text:SetPoint("TOPLEFT", 8, -7)
  c.sel = c:CreateTexture(nil, "OVERLAY"); c.sel:SetHeight(2); c.sel:SetPoint("BOTTOMLEFT", 1, 1); c.sel:SetPoint("BOTTOMRIGHT", -1, 1)
  c.sel:SetColorTexture(1, 0.82, 0, 1); c.sel:Hide()
  c:Hide(); return c
end
local cards = { cheap = Card(), fast = Card() }

-- the list, summary and notes scroll; tabs and cards stay at the top, the buttons at the bottom
local SB = 22                      -- room for the scroll bar
local LIST_W = INNER - SB
local scroll = CreateFrame("ScrollFrame", "WritPathPlannerScroll", f, "UIPanelScrollFrameTemplate")
scroll.scrollBarHideable = true    -- the bar hides itself when everything fits
local content = CreateFrame("Frame", nil, scroll); content:SetSize(LIST_W, 10)
scroll:SetScrollChild(content)
scroll:EnableMouseWheel(true)
local function Bar()
  local b = rawget(scroll, "ScrollBar") or scroll.ScrollBar
  if type(b) ~= "table" then b = _G["WritPathPlannerScrollScrollBar"] end
  return type(b) == "table" and b or nil
end

-- writ entries: two lines on the left (name; customer, zone, minutes), cost on the right
local COST_W = 92
local rowPool = {}
local function Row(i)
  local r = rowPool[i]
  if r then return r end
  r = CreateFrame("Frame", nil, content); r:SetWidth(LIST_W)
  r.left = Text(r, nil, LIST_W - COST_W - 6); r.left:SetPoint("TOPLEFT", 0, 0); r.left:SetSpacing(2)
  r.right = Text(r, nil, COST_W, "RIGHT"); r.right:SetPoint("TOPRIGHT", 0, 0)
  rowPool[i] = r
  return r
end

local summary = Text(content, nil, LIST_W)
local note = Text(content, "GameFontDisableSmall", LIST_W)
local goBtn = Btn(f, "Start route"); goBtn:Disable()
local shopBtn = Btn(f, "Send to Auctionator"); shopBtn:Disable()
local clearBtn = Btn(f, "Clear")   -- clears the route, the plan and its shopping (asks first)
clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)

---------------------------------------------------------------- the EllesmereUI look (or a plain fallback)
local accent = { 1, 0.82, 0 }
local function Accent()
  if skin and skin.GetAccentColor then local r, g, b = skin.GetAccentColor(); if r then accent = { r, g, b } end end
  tabBar:SetColorTexture(accent[1], accent[2], accent[3], 1)
  for _, c in pairs(cards) do c.sel:SetColorTexture(accent[1], accent[2], accent[3], 1) end
end
local function ApplySkin(S)
  skin = S
  S.Shell(f)
  S.CloseButton(closeX)
  for _, btn in ipairs(buttons) do S.Button(btn); if S.StateButtonLabel then S.StateButtonLabel(btn) end end
  S.EditBox(repBox, { padInput = true })
  S.Checkbox(zoneChk)
  for _, c in pairs(cards) do S.Panel(c, { inset = true }) end
  if Bar() and S.ScrollBar then S.ScrollBar(Bar()) end
  for _, fs in ipairs(fonts) do S.Font(fs) end
  Accent()
  if S.OnLooksChanged then S.OnLooksChanged(Accent) end
end
if EllesmereUI and EllesmereUI.RegisterSkin then EllesmereUI.RegisterSkin("WritPath", ApplySkin) end

local function PlainLook()   -- no EllesmereUI (or its skinning is off for WritPath): flat dark with thin borders
  if skin then return end
  local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
  f:SetBackdrop(flat); f:SetBackdropColor(0.06, 0.06, 0.07, 0.96); f:SetBackdropBorderColor(0, 0, 0, 1)
  for _, c in pairs(cards) do c:SetBackdrop(flat); c:SetBackdropColor(0.1, 0.1, 0.12, 1); c:SetBackdropBorderColor(0, 0, 0, 1) end
end

---------------------------------------------------------------- filling the window
local current, plans, choice
local function Minutes(secs) return math.floor((secs or 0) / 60 + 0.5) end

-- what still has to be bought for a plan: writs you don't have, items you're short of
local function ShoppingFor(plan)
  local list = {}
  for _, p in ipairs(plan and plan.route or {}) do
    if not p.have then list[#list + 1] = { id = p.id, name = ItemName(p.id) or ("Craftsman's Writ: " .. p.w.name), n = 1 } end
    if p.need and p.need > 0 then list[#list + 1] = { id = p.w.req, name = ItemName(p.w.req), n = p.need } end
  end
  return list
end

-- the list for the "Buy next" button at the auction house: how many of each thing the plan needs in your
-- bags (an item two writs both ask for is counted for both), with the price the plan was built on
local function BuyList(plan)
  local byId, order = {}, {}
  local function Add(id, n, name)
    if not id then return end
    local e = byId[id]
    if not e then e = { id = id, name = name, total = 0, unit = Price(id) }; byId[id] = e; order[#order + 1] = e end
    e.total = e.total + n
  end
  for _, p in ipairs(plan and plan.route or {}) do
    if not p.have then Add(p.id, 1, ItemName(p.id) or ("Craftsman's Writ: " .. p.w.name)) end
    Add(p.w.req, p.w.n or 1, ItemName(p.w.req))
  end
  local list = {}
  for _, e in ipairs(order) do if Count(e.id) < e.total then list[#list + 1] = e end end
  return list
end

local function SelectTab(btn)
  tabBar:ClearAllPoints(); tabBar:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -1); tabBar:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", -2, -1)
end

local function ShortText(plan)
  local sh = plan.short or {}
  local t = ("Short of %d: %d rep is the most you can do today. Each customer takes one writ a day"):format(plan.target, sh.max or plan.rep)
  if (sh.usedToday or 0) > 0 then t = t .. (", and you've already handed in to %d of them today"):format(sh.usedToday) end
  t = t .. "."
  if sh.withZone and sh.withZone > (sh.max or 0) then
    t = t .. (" Tick \"Include customers known by zone only\" to reach up to %d."):format(sh.withZone)
  end
  return t
end

local function Ago(secs)
  if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. " min" end
  if secs < 2 * 86400 then return math.floor(secs / 3600) .. " h" end
  return math.floor(secs / 86400) .. " days"
end

local function PriceAge(plan)
  local sv = AUCTIONATOR_SAVEDVARS or {}
  local last = math.max(sv.TimeOfLastBrowseScan or 0, sv.TimeOfLastReplicateScan or 0)
  local t
  if last > 0 then
    local secs = time() - last
    t = (secs > 86400 and W_ or GREY) .. "Last full AH scan: " .. Ago(secs) .. " ago|r"
  else
    t = W_ .. "No full AH scan yet|r"
  end
  -- prices also update from ordinary AH searches: the oldest one this plan relies on
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  local oldest
  if api and api.GetAuctionAgeByItemID then
    local function Check(id)
      local ok, days = pcall(api.GetAuctionAgeByItemID, "WritPath", id)
      if ok and type(days) == "number" and (not oldest or days > oldest) then oldest = days end
    end
    for _, p in ipairs(plan and plan.route or {}) do
      if not p.have then Check(p.id) end
      if p.need and p.need > 0 and p.w.req then Check(p.w.req) end
    end
  end
  if oldest and oldest >= 1 then
    t = t .. "\n" .. (oldest >= 3 and W_ or GREY) .. "Oldest price in this plan: " .. oldest .. (oldest == 1 and " day|r" or " days|r")
  end
  return t
end

local function Show(plan, top)
  current = plan
  ageText:SetText(PriceAge(plan))
  local y = 0
  local entries, prev = {}, plan.start
  for i, p in ipairs(plan.route) do
    local leg = (prev and p.pos) and Minutes(Secs(prev, p.pos)) or nil
    prev = p.pos or prev
    local flags = (p.need > 0 and ("  " .. W_ .. "needs item|r") or "") .. (p.c.exact and "" or ("  " .. W_ .. "spot not exact|r"))
    local left = ("%d. %s %s\n%s%s · %s%s|r%s"):format(i, TIER[p.w.tier] or "", p.w.name, GREY, p.c.npc or "writ customer",
      MapName(p.c.map), leg and (" · ~" .. leg .. " min") or "", flags)
    local right = plan.mine and (p.need > 0 and (Y .. Coins(p.cost) .. "|r") or "") or (p.have and (GREY .. "yours|r") or (Y .. Coins(p.cost) .. "|r"))
    entries[#entries + 1] = { left, right }
  end
  for _, l in ipairs(plan.later or {}) do entries[#entries + 1] = { W_ .. "Tomorrow:|r " .. l.w.name .. "\n" .. GREY .. l.why .. "|r", "" } end
  for _, l in ipairs(plan.unknown or {}) do entries[#entries + 1] = { W_ .. "Not placed yet:|r " .. l.w.name .. "\n" .. GREY .. l.why .. "|r", "" } end
  for i = 1, math.max(#entries, #rowPool) do
    local r = Row(i)
    if entries[i] then
      r.left:SetText(entries[i][1]); r.right:SetText(entries[i][2])
      local h = math.max(r.left:GetStringHeight(), r.right:GetStringHeight()) + 6
      r:SetHeight(h); r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y); r:Show()
      y = y - h
    else r:Hide() end
  end

  y = y - 6
  summary:ClearAllPoints(); summary:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  local net = plan.pouches - plan.cost
  if #plan.route == 0 then
    summary:SetText(W_ .. (plan.mine and (plan.owned == 0 and "No writs in your bags or quest log."
      or "None of your writs can go today: see the lines above.")
      or "Nothing to plan: no writ with a known customer and an AH price is free today.") .. "|r")
  elseif plan.mine then
    summary:SetText(("%s%d writs today, %d rep|r · ~%d min · pouches ~%s%s"):format(G, #plan.route, plan.rep,
      Minutes(plan.secs), Coins(plan.pouches), plan.cost > 0 and (" · missing items " .. Coins(plan.cost)) or ""))
  else
    summary:SetText(("%s%d rep|r: %d yours + %d to buy · cost %s · ~%d min · net %s%s|r"):format(G, plan.rep,
      plan.ownedUsed or 0, plan.bought or 0, Coins(plan.cost), Minutes(plan.secs), net >= 0 and G or "|cFFFF5722", Coins(net))
      .. (plan.rep < plan.target and ("\n" .. W_ .. ShortText(plan) .. "|r") or ""))
  end
  y = y - summary:GetStringHeight() - 6

  local fps, own = Travel.KnownFlightPaths()
  note:ClearAllPoints(); note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  local roads, ships = Travel.Learned()
  note:SetText((plan.mine and "Shortest order from where you stand, one writ per customer per day. "
    or "Prices from your last Auctionator scan; times are estimates. ")
    .. ("WritPath knows %d road crossings and %d ships from your travels; more as you ride. "):format(roads, ships)
    .. (fps == 0 and "No flight paths known yet: open any flight master's map once on each continent."
     or (own >= fps and (fps .. " flight paths known.")
     or (fps .. " flight paths known (" .. (fps - own) .. " from RestedXP until you open a flight master's map on that continent)."))))
  y = y - note:GetStringHeight() - 4

  -- the scroll area takes what's left of half the screen; the window is never taller than that
  local listH = -y
  content:SetHeight(listH)
  local BOTTOM = 22 + PAD + 10                          -- buttons and the gap above them
  local maxH = math.floor((UIParent:GetHeight() or 768) * 0.5)
  local viewH = math.min(listH, math.max(90, maxH + top - BOTTOM))
  scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top); scroll:SetSize(LIST_W, viewH)
  scroll:SetVerticalScroll(0)
  local bar = Bar()
  if bar then
    if listH > viewH + 1 then bar:Show() else bar:Hide() end
  end

  if #plan.route > 0 then goBtn:Enable() else goBtn:Disable() end
  if #ShoppingFor(plan) > 0 and Auctionator and Auctionator.API then shopBtn:Enable() else shopBtn:Disable() end
  FitWidth(goBtn); FitWidth(shopBtn); FitWidth(clearBtn)
  goBtn:ClearAllPoints(); goBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
  shopBtn:ClearAllPoints(); shopBtn:SetPoint("RIGHT", goBtn, "LEFT", -6, 0)
  f:SetHeight(-top + viewH + BOTTOM)
end

local function CardText(key, plan, other)
  local same = #plan.route == #other.route
  if same then
    local ids = {}; for _, p in ipairs(other.route) do ids[p.id] = true end
    for _, p in ipairs(plan.route) do if not ids[p.id] then same = false end end
  end
  local net = plan.pouches - plan.cost
  return ("%s%s|r%s\n%s · ~%d min · %d rep\nnet %s%s|r"):format(G, key == "cheap" and "Cheapest" or "Fastest",
    same and (GREY .. "  same writs as the other|r") or "", Coins(plan.cost), Minutes(plan.secs), plan.rep,
    net >= 0 and G or "|cFFFF5722", Coins(net))
end

local CARDS_TOP = -86
local function LayoutCards()
  local h = 0
  for _, c in pairs(cards) do h = math.max(h, c.text:GetStringHeight() + 16) end
  cards.cheap:SetHeight(h); cards.fast:SetHeight(h)
  cards.cheap:ClearAllPoints(); cards.cheap:SetPoint("TOPLEFT", PAD, CARDS_TOP)
  cards.fast:ClearAllPoints(); cards.fast:SetPoint("TOPLEFT", cards.cheap, "TOPRIGHT", 8, 0)
  return CARDS_TOP - h - 10
end

local function Select(key)
  choice = key; WritPathNav.planChoice = key
  for k, c in pairs(cards) do if k == key then c.sel:Show() else c.sel:Hide() end end
  Show(plans[key], LayoutCards())
end
cards.cheap:SetScript("OnClick", function() Select("cheap") end)
cards.fast:SetScript("OnClick", function() Select("fast") end)

local function Warm(plan)   -- ask the client for item names it hasn't loaded yet
  if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  for _, p in ipairs(plan.route) do pcall(C_Item.RequestLoadItemDataByID, p.id); if p.w.req then pcall(C_Item.RequestLoadItemDataByID, p.w.req) end end
end

local function DoMine()
  buyRow:Hide(); cards.cheap:Hide(); cards.fast:Hide(); SelectTab(mineBtn)
  WritPathNav.planMode = "mine"
  local plan = PlanOwned(); Warm(plan)
  Show(plan, -64)
end

local function DoPlan()
  buyRow:ClearAllPoints(); buyRow:SetPoint("TOPLEFT", PAD, -60); buyRow:Show(); SelectTab(buyBtn)
  WritPathNav.planMode = "buy"
  if not (Auctionator and Auctionator.API) then
    cards.cheap:Hide(); cards.fast:Hide()
    Show({ route = {}, start = nil, pouches = 0, cost = 0, rep = 0, target = 0, secs = 0 }, -90)
    summary:SetText(W_ .. "Auctionator isn't loaded, so there are no prices to plan with.|r"); return
  end
  local target = tonumber(repBox:GetText()) or 1000
  local zoneOnly = zoneChk:GetChecked() and true or false
  WritPathNav.plan = { target = target, zoneOnly = zoneOnly }
  plans = PlanBoth(target, zoneOnly)
  Warm(plans.cheap); Warm(plans.fast)
  cards.cheap.text:SetText(CardText("cheap", plans.cheap, plans.fast))
  cards.fast.text:SetText(CardText("fast", plans.fast, plans.cheap))
  cards.cheap:Show(); cards.fast:Show()
  Select(WritPathNav.planChoice or "cheap")
end
mineBtn:SetScript("OnClick", DoMine)
buyBtn:SetScript("OnClick", DoPlan)
planBtn:SetScript("OnClick", DoPlan)
repBox:SetScript("OnEnterPressed", function(bx) bx:ClearFocus(); DoPlan() end)
closeX:SetScript("OnClick", function() f:Hide() end)

-- Auctionator: a shopping list called "WritPath" with exactly what this plan needs (searches at once at the AH)
local function SendToAuctionator(plan)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then Print("Auctionator isn't loaded."); return end
  local terms, missing = {}, 0
  for _, it in ipairs(ShoppingFor(plan)) do
    if it.name then
      local ok, str = pcall(api.ConvertToSearchString, "WritPath", { searchString = it.name, isExact = true, quantity = it.n })
      terms[#terms + 1] = ok and str or ('"' .. it.name .. '"')
    else missing = missing + 1 end
  end
  if #terms == 0 then Print("Nothing to buy for this plan."); return end
  local ok, err = pcall(api.CreateShoppingList, "WritPath", "WritPath", terms)
  if not ok then Print("Auctionator refused the list: " .. tostring(err)); return end
  Print(("Auctionator list \"WritPath\" ready: %d things to buy. At the auction house, open Auctionator's Shopping tab."):format(#terms)
    .. (missing > 0 and (" " .. missing .. " item names weren't loaded yet: press the button again in a moment.") or ""))
end
shopBtn:SetScript("OnClick", function()
  if not current then return end
  SendToAuctionator(current)
  if WritPath_SetShopList then WritPath_SetShopList(BuyList(current)) end
end)

goBtn:SetScript("OnClick", function()
  if not current or #current.route == 0 then return end
  WritPathNav.plannedCost = WritPathNav.plannedCost or {}
  for _, p in ipairs(current.route) do WritPathNav.plannedCost[p.w.q] = p.cost end
  WritPath_SetRoute(Steps(current), ("Writs: %d rep"):format(current.rep),
                    ("Planned writs handed in: |cFF00FF25%d rep|r"):format(current.rep))
  if WritPath_StartMoneySession then WritPath_StartMoneySession(current.cost, current.rep) end
  if WritPath_SetShopList then WritPath_SetShopList(BuyList(current)) end
  f:Hide()
  Print(("Route set: %d writs, %d rep, ~%d min."):format(#current.route, current.rep, Minutes(current.secs))
        .. (current.later and #current.later > 0 and (" " .. #current.later .. " wait for tomorrow.") or ""))
end)

-- Clear everything a plan set up: the guide's route, the money session, the buy list at the auction house,
-- Auctionator's "WritPath" shopping list, and the planner itself. What WritPath has learned stays.
local function EmptyAuctionatorList()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetShoppingListItems and api.DeleteShoppingListItem) then return end
  local ok, items = pcall(api.GetShoppingListItems, "WritPath", "WritPath")
  if not (ok and type(items) == "table") then return end   -- no such list
  for i = #items, 1, -1 do pcall(api.DeleteShoppingListItem, "WritPath", "WritPath", items[i]) end
end
function WritPath_ClearAll()
  if WritPath_SetRoute then WritPath_SetRoute(nil) end
  if WritPath_StartMoneySession then WritPath_StartMoneySession(nil) end
  if WritPath_SetShopList then WritPath_SetShopList(nil) end
  WritPathNav.shopAt, WritPathNav.plannedCost = nil, {}
  WritPathNav.plan, WritPathNav.planChoice = nil, nil
  EmptyAuctionatorList()
  current, plans, choice = nil, nil, nil
  repBox:SetText(""); zoneChk:SetChecked(false)
  cards.cheap:Hide(); cards.fast:Hide()
  Show({ route = {}, start = nil, pouches = 0, cost = 0, rep = 0, target = 0, secs = 0 }, -64)
  summary:SetText(GREY .. "Cleared. Pick My writs or Buy writs to plan again.|r"); note:SetText("")
  Print("Route and plan cleared.")
end
-- WritPath's own confirm window. Not Blizzard's StaticPopup: an addon using those shared popups taints them,
-- and the next protected thing Blizzard does with one gets blocked and blamed on WritPath.
local confirm
local function Confirm()
  if confirm then return confirm end
  local W = 300
  confirm = CreateFrame("Frame", "WritPathConfirm", UIParent, "BackdropTemplate")
  confirm:SetWidth(W); confirm:SetPoint("CENTER", 0, 120); confirm:SetFrameStrata("DIALOG")
  confirm:EnableMouse(true); confirm:SetClampedToScreen(true); confirm:Hide()
  tinsert(UISpecialFrames, "WritPathConfirm")   -- Escape answers No
  local msg = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  msg:SetWidth(W - 24); msg:SetWordWrap(true); msg:SetJustifyH("CENTER"); msg:SetPoint("TOP", 0, -14)
  msg:SetText("Clear the WritPath route, the planner and its shopping list?\n\n" .. GREY
    .. "What WritPath has learned about customers and roads stays.|r")
  local yes = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate"); yes:SetSize(110, 22); yes:SetText(YES or "Yes")
  local no = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate"); no:SetSize(110, 22); no:SetText(NO or "No")
  yes:SetPoint("TOPRIGHT", msg, "BOTTOM", -4, -12); no:SetPoint("TOPLEFT", msg, "BOTTOM", 4, -12)
  yes:SetScript("OnClick", function() confirm:Hide(); WritPath_ClearAll() end)
  no:SetScript("OnClick", function() confirm:Hide() end)
  confirm:SetHeight(14 + msg:GetStringHeight() + 12 + 22 + 14)
  if skin then
    skin.Shell(confirm); skin.Button(yes); skin.Button(no); skin.Font(msg)
    if skin.StateButtonLabel then skin.StateButtonLabel(yes); skin.StateButtonLabel(no) end
  else
    local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
    confirm:SetBackdrop(flat); confirm:SetBackdropColor(0.06, 0.06, 0.07, 0.97); confirm:SetBackdropBorderColor(0, 0, 0, 1)
  end
  return confirm
end
function WritPath_AskClear() Confirm():Show() end
WritPath_PlannerInternals_Confirm = function() return confirm end   -- for tests
clearBtn:SetScript("OnClick", WritPath_AskClear)

function WritPath_OpenPlanner(mode)
  local o = WritPathNav.plan
  if o then repBox:SetText(o.target); zoneChk:SetChecked(o.zoneOnly) end
  FitWidth(mineBtn); FitWidth(buyBtn); FitWidth(planBtn)
  f:Show()
  if (mode or WritPathNav.planMode) == "buy" then DoPlan() else DoMine() end
end
-- something new was learned (a customer's spot or name): an open planner shows it straight away
function WritPath_PlannerLearned()
  if f:IsShown() then
    if WritPathNav.planMode == "buy" then DoPlan() else DoMine() end
  end
end

function WritPath_TogglePlanner(mode)
  if f:IsShown() and (not mode or mode == WritPathNav.planMode) then f:Hide() else WritPath_OpenPlanner(mode) end
end

-- for /writs why: what the planner can't use and why
function WritPath_WhyNot()
  local _, skipped = Candidates(WritPathNav.plan and WritPathNav.plan.zoneOnly)
  local counts = {}
  for _, s in ipairs(skipped) do local k = s.why:gsub(" %(.*%)", ""); counts[k] = (counts[k] or 0) + 1 end
  for k, n in pairs(counts) do Print(("%d writs: %s"):format(n, k)) end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_COMPLETE")      -- the reward window: you're at the customer
ev:RegisterEvent("QUEST_PROGRESS")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:SetScript("OnEvent", function(_, event, a1)
  if event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then NoteTurnin(); return end
  if event == "QUEST_TURNED_IN" then
    LearnTurnin(a1)
    local q = a1
    C_Timer.After(1.5, function() if WritPath_RerouteFromHere then WritPath_RerouteFromHere(q) end end)
    return
  end
  if event == "TAXIMAP_OPENED" then
    local n = Travel.RecordFlightPaths()
    if n and n > 0 then Print(("Recorded %d flight paths for route planning."):format(n)) end
  elseif event == "PLAYER_LOGIN" then
    WritPathLearned = WritPathLearned or {}
    C_Timer.After(1, PlainLook)
    C_Timer.After(5, Learn)
  else
    C_Timer.After(1, Learn)   -- the map pin appears a moment after accepting
  end
end)

-- for Money.lua at a turn-in: name, tier and cost of a writ quest. The cost is what you paid at the auction
-- house for this writ and its items (each unit used once), else what the plan expected.
local function TakePaid(id, n)
  local p = WritPathNav and WritPathNav.paidFor and WritPathNav.paidFor[id]
  if not (p and p.qty > 0) then return nil end
  local take = math.min(n, p.qty)
  local c = p.paid / p.qty * take
  p.qty, p.paid = p.qty - take, p.paid - c
  return c * n / take
end
function WritPath_WritByQuest(q)
  for id, w in pairs(DB) do
    if w.q == q then
      local planned = WritPathNav and WritPathNav.plannedCost and WritPathNav.plannedCost[q]
      local writ, item = TakePaid(id, 1), w.req and TakePaid(w.req, w.n or 1)
      local cost = (writ or item) and math.floor((writ or 0) + (item or 0) + 0.5) or planned
      return w.name, w.tier, cost
    end
  end
end

-- After buying: the route is rebuilt from the writs and items you actually have (bags and mail), so a writ
-- that wasn't bought drops out, an item you're still missing shows up as a shopping step, and the shopping
-- list keeps only what that route needs. Called when you close the auction house.
-- After each hand-in of a route writ: the rest of the trip is worked out again from where you stand, with
-- everything WritPath knows now (flight paths placed, roads learned since the route started), and the
-- remaining customers in the best order from here. Only the writs still on the route are used.
function WritPath_RerouteFromHere(q)
  if not (WritPathNav and WritPathNav.route and #WritPathNav.route > 0) then return end
  local left, onRoute = {}, false
  for _, st in ipairs(WritPathNav.route) do
    if st.writ and DB[st.writ] then
      if DB[st.writ].q == q then onRoute = true elseif not Done(DB[st.writ].q) then left[st.writ] = true end
    end
  end
  if not onRoute or not next(left) then return end
  local plan = PlanOwned(left, q)
  if #plan.route == 0 then return end
  local steps = Steps(plan)
  -- a "learn the flight path" step right after the customer just handed in to is still ahead of you: keep it
  for i, st in ipairs(WritPathNav.route) do
    if st.writ and DB[st.writ] and DB[st.writ].q == q then
      local nxt = WritPathNav.route[i + 1]
      if nxt and nxt.done and nxt.done.taxiMap then table.insert(steps, 2, nxt) end
      break
    end
  end
  WritPath_SetRoute(steps, WritPathNav.title, WritPathNav.doneText)
  local nxt = plan.route[1]
  Print(("Rerouted from here: next %s (%s), %d writs left, ~%d min."):format(nxt.w.name, nxt.c.npc or MapName(nxt.c.map),
    #plan.route, math.floor((plan.secs or 0) / 60 + 0.5)))
end

function WritPath_ReplanFromBags()
  if not (WritPathNav and WritPathNav.route and #WritPathNav.route > 0) then return end
  local before = {}
  for _, st in ipairs(WritPathNav.route) do if st.writ then before[st.writ] = true end end
  local plan = PlanOwned()
  local after, short, dropped, added = {}, {}, {}, {}
  for _, p in ipairs(plan.route) do
    after[p.id] = true
    if p.need and p.need > 0 then short[#short + 1] = p.w.name end
  end
  for id in pairs(before) do if not after[id] and DB[id] then dropped[#dropped + 1] = DB[id].name end end
  for id in pairs(after) do if not before[id] then added[#added + 1] = DB[id].name end end
  if #dropped == 0 and #added == 0 and #short == 0 then
    Print("You have every writ and item the route needs.")
    return
  end
  table.sort(dropped); table.sort(added); table.sort(short)
  WritPath_SetRoute(Steps(plan), ("Writs: %d rep"):format(plan.rep), ("Planned writs handed in: |cFF00FF25%d rep|r"):format(plan.rep))
  if WritPathMoney and WritPathMoney.session then WritPathMoney.session.rep = plan.rep end
  local needed = {}
  for _, e in ipairs(BuyList(plan)) do needed[e.id] = e end
  if WritPath_PruneShopList then WritPath_PruneShopList(needed) end
  if WritPath_MoneyUpdate then WritPath_MoneyUpdate() end
  local msg = ("Route rebuilt from what you bought: %d writs, %d rep, ~%d min."):format(#plan.route, plan.rep, math.floor((plan.secs or 0) / 60 + 0.5))
  if #dropped > 0 then msg = msg .. " Dropped (writ not bought): " .. table.concat(dropped, ", ") .. "." end
  if #short > 0 then msg = msg .. " Still missing the item for: " .. table.concat(short, ", ") .. " (on the shopping list)." end
  if #added > 0 then msg = msg .. " Added (writs you have): " .. table.concat(added, ", ") .. "." end
  if plan.later and #plan.later > 0 then msg = msg .. " " .. #plan.later .. " writs wait for another day (same customer)." end
  Print(msg)
end

-- exposed for the test harness
WritPath_PlannerInternals = { LearnTurnin = LearnTurnin, NoteTurnin = NoteTurnin, BuyList = BuyList, PriceAgeText = function() return PriceAge(current) end, Scroll = scroll, Content = content, ApplySkin = ApplySkin, PlainLook = PlainLook, PlanBoth = PlanBoth, ShoppingFor = ShoppingFor, SendToAuctionator = SendToAuctionator, Plan = Plan, PlanOwned = PlanOwned, BestOrder = BestOrder, Steps = Steps, Travel = Travel, Customer = Customer, Candidates = Candidates, Learn = Learn }
