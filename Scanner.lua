-- WritPath's own price scan: one full read of the auction house (the same "replicate" request Auctionator's full
-- scan uses, so it takes about as long), keeping only the writs and the items they ask for. For each of those it
-- saves the cheapest listings with their sizes, so a writ only sold as a stack is priced as what you'd really pay.
-- The game allows one full read every 15 minutes (for any addon: Auctionator's counts too). In between, the same
-- button runs a summary scan instead (what Auctionator's no-wait scan does): an empty search paged to the end, one
-- line per item with its lowest price and how many are listed. No stack sizes, but no wait either.
-- WritPathPrices = { t = when, auctions = how many were read, items = { [item id] = { c = commodity, l = { {unit, qty}, ... } } } }
-- At the auction house a small WritPath panel sits under the window: the scan button, how old the prices are, and a
-- progress bar while it scans. EllesmereUI's look when it's installed.
local S = {}
WritPath_Scanner = S
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local COOLDOWN = 15 * 60
local KEEP = 8   -- cheapest listings kept per item
local GREY, GOLD, RED = "|cFFAAAAAA", "|cFFFFD100", "|cFFFF5722"

local function Wanted()
  local w = {}
  for id, wr in pairs(WritPath_Writs or {}) do
    w[id] = true
    if wr.req then w[wr.req] = true end
  end
  -- Waylaid Crates and what they're filled with (Favor.lua)
  for _, c in ipairs(WritPath_Crates or {}) do
    w[c[1]] = true
    for _, f in ipairs(c[6]) do w[f[1]] = true end
  end
  return w
end

local function LastFullScan()
  local mine = WritPathPrices and WritPathPrices.replicateAt or 0
  local sv = AUCTIONATOR_SAVEDVARS or {}
  return math.max(mine, sv.TimeOfLastReplicateScan or 0)
end
function S.Wait() return math.max(0, COOLDOWN - (time() - LastFullScan())) end
local function Clock(secs) return ("%d:%02d"):format(math.floor(secs / 60), secs % 60) end
local function Ago(secs)
  if secs < 90 then return "just now" end
  if secs < 5400 then return math.floor(secs / 60 + 0.5) .. " min old" end
  if secs < 172800 then return math.floor(secs / 3600 + 0.5) .. " h old" end
  return math.floor(secs / 86400 + 0.5) .. " days old"
end

---------------------------------------------------------------- the panel
local panel, icon, title, status, bar, barText, scanBtn
local fonts, skin = {}, nil
local phase = { kind = "idle" }   -- idle, wait, read, done, fail
local accent = { 1, 0.82, 0 }

local function Text(parent, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
  fonts[#fonts + 1] = fs
  return fs
end

local Render
local function Build()
  if panel then return end
  local W = 280
  panel = CreateFrame("Frame", "WritPathScanPanel", UIParent, "BackdropTemplate")
  panel:SetSize(W, 74); panel:SetFrameStrata("HIGH"); panel:SetClampedToScreen(true); panel:Hide()
  icon = panel:CreateTexture(nil, "ARTWORK"); icon:SetSize(30, 30); icon:SetPoint("TOPLEFT", 8, -8)
  icon:SetTexture("Interface/AddOns/WritPath/Media/icon")
  title = Text(panel, "GameFontNormal"); title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1); title:SetText("WritPath prices")
  status = Text(panel); status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3); status:SetWidth(W - 46 - 96)
  scanBtn = CreateFrame("Button", "WritPathScanButton", panel, "UIPanelButtonTemplate")
  scanBtn:SetSize(84, 22); scanBtn:SetPoint("TOPRIGHT", -8, -10); scanBtn:SetText("Scan")
  scanBtn:SetScript("OnClick", function() S.Start() end)
  scanBtn:SetScript("OnEnter", function(self)
    -- beside the panel, not above it: the panel sits at the top of the screen, where a tooltip above it gets pushed
    -- back down over the button
    GameTooltip:SetOwner(self, "ANCHOR_NONE"); GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPRIGHT", panel, "TOPLEFT", -4, 0); GameTooltip:SetText("Scan writ prices")
    GameTooltip:AddLine("Reads the auction house and keeps the prices of writs and the items they ask for. A detailed scan (every listing, stacks too) when the game allows one, every 15 minutes; otherwise a quick summary scan (lowest price per item).", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- the progress bar
  bar = CreateFrame("StatusBar", nil, panel)
  bar:SetPoint("BOTTOMLEFT", 8, 8); bar:SetPoint("BOTTOMRIGHT", -8, 8); bar:SetHeight(14)
  bar:SetStatusBarTexture("Interface/BUTTONS/WHITE8X8"); bar:SetMinMaxValues(0, 1); bar:SetValue(0)
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
  local edge = CreateFrame("Frame", nil, bar, "BackdropTemplate"); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetBackdrop({ edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }); edge:SetBackdropBorderColor(0, 0, 0, 1)
  barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); barText:SetPoint("CENTER", 0, 0)
  fonts[#fonts + 1] = barText
  if skin then
    skin.Shell(panel); skin.Button(scanBtn)
    if skin.StateButtonLabel then skin.StateButtonLabel(scanBtn) end
    for _, fs in ipairs(fonts) do skin.Font(fs) end
    if skin.GetAccentColor then local r, g, b = skin.GetAccentColor(); if r then accent = { r, g, b } end end
  else
    local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
    panel:SetBackdrop(flat); panel:SetBackdropColor(0.06, 0.06, 0.07, 0.96); panel:SetBackdropBorderColor(0, 0, 0, 1)
  end
  bar:SetStatusBarColor(accent[1], accent[2], accent[3], 0.9)
  -- the countdown and the waiting pulse
  local acc = 0
  panel:SetScript("OnUpdate", function(_, e)
    acc = acc + e
    if phase.kind == "wait" or phase.kind == "browse" then
      if phase.kind == "wait" then
        local p = (math.sin(GetTime() * 3) + 1) / 2
        bar:SetMinMaxValues(0, 1); bar:SetValue(0.1 + 0.15 * p)
      end
    end
    if acc > 0.5 then acc = 0; Render() end
  end)
end
if EllesmereUI and EllesmereUI.RegisterSkin then EllesmereUI.RegisterSkin("WritPathScan", function(S2) skin = S2 end) end

function Render()
  if not panel then return end
  local t = WritPathPrices and WritPathPrices.t
  local wait = S.Wait()
  local line = t and ("Prices " .. Ago(time() - t)) or (RED .. "No scan yet|r")
  local working = phase.kind == "wait" or phase.kind == "read" or phase.kind == "load" or phase.kind == "browse"
  if not working then
    line = line .. GREY .. (wait > 0 and (" · detailed scan in " .. Clock(wait)) or " · detailed scan ready") .. "|r"
  end
  status:SetText(line)
  if working then scanBtn:Disable() else scanBtn:Enable() end
  if phase.kind == "idle" then
    bar:SetMinMaxValues(0, 1); bar:SetValue(t and 1 or 0)
    barText:SetText(t and (GREY .. (WritPathPrices.count or 0) .. " writ prices · " .. (WritPathPrices.kind == "summary" and "summary scan" or "detailed scan") .. "|r") or (GREY .. "Press Scan to read writ prices|r"))
  elseif phase.kind == "wait" then
    barText:SetText("Waiting for the auction house...")
  elseif phase.kind == "read" then
    bar:SetMinMaxValues(0, math.max(1, phase.n)); bar:SetValue(phase.i)
    barText:SetText(("Reading %s / %s auctions"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(phase.i) or phase.i, BreakUpLargeNumbers and BreakUpLargeNumbers(phase.n) or phase.n))
  elseif phase.kind == "browse" then
    local p = (math.sin(GetTime() * 2) + 1) / 2
    bar:SetMinMaxValues(0, 1); bar:SetValue(0.2 + 0.6 * p)
    barText:SetText(("Summary scan: %s items read..."):format(BreakUpLargeNumbers and BreakUpLargeNumbers(phase.n or 0) or (phase.n or 0)))
  elseif phase.kind == "load" then
    bar:SetMinMaxValues(0, 1); bar:SetValue(0.95)
    barText:SetText(("Loading item data for %d auctions..."):format(phase.left))
  elseif phase.kind == "done" then
    bar:SetMinMaxValues(0, 1); bar:SetValue(1)
    barText:SetText(GOLD .. ("Done (%s): %d writ prices in %d s"):format(phase.summary and "summary" or "detailed", phase.count, phase.secs) .. "|r")
  elseif phase.kind == "fail" then
    bar:SetMinMaxValues(0, 1); bar:SetValue(0)
    barText:SetText(RED .. phase.why .. "|r")
  end
end

---------------------------------------------------------------- scanning
local busy, got, startedAt = false, false, 0
local ev = CreateFrame("Frame")

local function Finish(found, n, missed, summary)
  local items, count = {}, 0
  local statusFn = C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus
  local COMMODITY = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
  for id, l in pairs(found) do
    table.sort(l, function(a, b) return a[1] < b[1] end)
    while #l > KEEP do table.remove(l) end
    local ok, st = false, nil
    if statusFn then ok, st = pcall(statusFn, id) end
    items[id] = { c = summary or (ok and st == COMMODITY) or nil, l = l }
    count = count + 1
  end
  WritPathPrices = WritPathPrices or {}
  WritPathPrices.items, WritPathPrices.t, WritPathPrices.auctions, WritPathPrices.count = items, time(), n, count
  WritPathPrices.kind = summary and "summary" or "detailed"
  busy = false
  ev:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  ev:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); ev:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  local secs = math.floor(GetTime() - startedAt + 0.5)
  phase = { kind = "done", count = count, secs = secs, summary = summary }
  Render()
  Print(("%s scan: %d %s in %d s, prices for %d writs and writ items saved."):format(summary and "Summary" or "Detailed", n,
    summary and "items" or "auctions", secs, count)
    .. ((missed or 0) > 0 and (" %d auctions' item data never loaded."):format(missed) or ""))
  if WritPath_PlannerLearned then WritPath_PlannerLearned() end
end

local function Process()
  local n = C_AuctionHouse.GetNumReplicateItems() or 0
  local want, me = Wanted(), UnitName("player")
  local found, i = {}, 0
  local pending, asked = {}, {}   -- auctions of wanted items whose data the client hasn't loaded yet
  phase = { kind = "read", i = 0, n = n }
  -- one auction: kept when it's complete; an item the client hasn't loaded yet comes back without its count and
  -- price, so its data is requested and the auction read again afterwards (as Auctionator's full scan does)
  local function Take(k)
    local info = { C_AuctionHouse.GetReplicateItemInfo(k) }
    local q, buy, owner, id, full = info[3], info[10], info[14], info[17], info[18]
    if not (id and want[id]) then return true end
    if not (q and buy and q > 0) or full == false then
      if not asked[id] and C_Item and C_Item.RequestLoadItemDataByID then asked[id] = true; pcall(C_Item.RequestLoadItemDataByID, id) end
      return false
    end
    if buy > 0 and owner ~= me then
      local l = found[id] or {}
      l[#l + 1] = { buy / q, q }
      found[id] = l
    end
    return true
  end
  local tries = 0
  local function Resolve()
    if not busy then return end
    local still = {}
    for _, k in ipairs(pending) do if not Take(k) then still[#still + 1] = k end end
    pending = still
    tries = tries + 1
    phase = { kind = "load", left = #pending }
    Render()
    if #pending > 0 and tries < 30 then C_Timer.After(0.5, Resolve) else Finish(found, n, #pending) end
  end
  local function Step()
    if not busy then return end   -- the auction house was closed
    local stop = math.min(i + 2000, n)
    for k = i, stop - 1 do
      if not Take(k) then pending[#pending + 1] = k end
    end
    i = stop
    phase.i = i
    Render()
    if i < n then C_Timer.After(0, Step)
    elseif #pending > 0 then C_Timer.After(0.5, Resolve)
    else Finish(found, n, 0) end
  end
  Step()
end

local function Fail(why)
  busy = false
  phase = { kind = "fail", why = why }
  Render()
  Print(why)
end

-- the summary scan: an empty search, paged to the end; one line per item (lowest price, how many listed)
local sFound, sCount, sWant
local function SummaryAdd(results)
  for _, r in ipairs(results or {}) do
    local id = r.itemKey and r.itemKey.itemID
    sCount = sCount + 1
    if id and sWant[id] and (r.totalQuantity or 0) > 0 and (r.minPrice or 0) > 0 then
      sFound[id] = { { r.minPrice, r.totalQuantity } }
    end
  end
  phase = { kind = "browse", n = sCount }
end
local function SummaryNext()
  if C_AuctionHouse.HasFullBrowseResults and not C_AuctionHouse.HasFullBrowseResults() then
    C_AuctionHouse.RequestMoreBrowseResults()
  else
    Finish(sFound, sCount, 0, true)
  end
end
local function StartSummary()
  if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then Fail("This auction house can't do a summary scan."); return end
  busy, got, startedAt = true, false, GetTime()
  sFound, sCount, sWant = {}, 0, Wanted()
  phase = { kind = "browse", n = 0 }
  Render()
  ev:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); ev:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
  C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
  C_Timer.After(120, function() if busy and phase.kind == "browse" then Fail("The summary scan didn't finish. Try again.") end end)
end
S.Summary = { Add = SummaryAdd, Next = SummaryNext }

-- one button: the detailed scan when the game allows one, otherwise the summary scan
function S.Start()
  if busy then return end
  local wait = S.Wait()
  if wait > 0 or not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
    if wait > 0 then Print(("Detailed scan possible again in %s: running a summary scan now."):format(Clock(wait))) end
    StartSummary()
    return
  end
  busy, got, startedAt = true, false, GetTime()
  WritPathPrices = WritPathPrices or {}
  WritPathPrices.replicateAt = time()
  phase = { kind = "wait" }
  Render()
  ev:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  C_AuctionHouse.ReplicateItems()
  C_Timer.After(90, function()
    if busy and not got then Fail("The auction house didn't answer the scan. Try again in 15 minutes.") end
  end)
end

ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:SetScript("OnEvent", function(_, event, a1)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    if busy and not got then got = true; Process() end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if busy and phase.kind == "browse" then
      sFound, sCount = {}, 0   -- a fresh batch: the results so far, from the start
      SummaryAdd(C_AuctionHouse.GetBrowseResults()); Render(); SummaryNext()
    end
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    if busy and phase.kind == "browse" then SummaryAdd(a1); Render(); SummaryNext() end
  elseif event == "AUCTION_HOUSE_SHOW" then
    Build()
    local ah = AuctionHouseFrame or AuctionFrame
    panel:ClearAllPoints()
    -- above the auction house window, on the right (below it are other addons' tabs, like Auctionator's)
    if ah then panel:SetPoint("BOTTOMRIGHT", ah, "TOPRIGHT", 0, 4) else panel:SetPoint("CENTER") end
    if phase.kind == "done" or phase.kind == "fail" then phase = { kind = "idle" } end
    panel:Show(); Render()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if panel then panel:Hide() end
    if busy then Fail("The scan stopped: the auction house was closed.") end
  end
end)

-- what one unit costs when you need n of them, from WritPath's scan: the cheapest units first (on this auction house
-- every purchase buys one at a time, items and commodities alike). nil when the scan didn't see it.
function WritPath_ScanPrice(id, n)
  local e = WritPathPrices and WritPathPrices.items and WritPathPrices.items[id]
  if not (e and e.l and e.l[1]) then return nil end
  n = math.max(1, n or 1)
  local got2, cost = 0, 0
  for _, x in ipairs(e.l) do
    local take = math.min(x[2], n - got2)
    got2, cost = got2 + take, cost + take * x[1]
    if got2 >= n then break end
  end
  if got2 < n then return nil end
  return cost / n
end
function WritPath_ScanTime() return WritPathPrices and WritPathPrices.t end
-- how many of an item the last scan saw listed (nil: the scan didn't see it at all)
function WritPath_ScanAvail(id)
  local e = WritPathPrices and WritPathPrices.items and WritPathPrices.items[id]
  if not (e and e.l) then return nil end
  local n = 0
  for _, x in ipairs(e.l) do n = n + (x[2] or 0) end
  return n
end
