-- WritPath's own price scan: one full read of the auction house (the same "replicate" request Auctionator's full
-- scan uses, so it takes about as long), keeping only the writs and the items they ask for. For each of those it
-- saves the cheapest listings with their sizes, so a writ only sold as a stack is priced as what you'd really pay.
-- The game allows one full read every 15 minutes (for any addon: Auctionator's counts too).
-- WritPathPrices = { t = when, auctions = how many were read, items = { [item id] = { c = commodity, l = { {unit, qty}, ... } } } }
local S = {}
WritPath_Scanner = S
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local COOLDOWN = 15 * 60
local KEEP = 8   -- cheapest listings kept per item

local function Wanted()
  local w = {}
  for id, wr in pairs(WritPath_Writs or {}) do
    w[id] = true
    if wr.req then w[wr.req] = true end
  end
  return w
end

local function LastFullScan()
  local mine = WritPathPrices and WritPathPrices.replicateAt or 0
  local sv = AUCTIONATOR_SAVEDVARS or {}
  return math.max(mine, sv.TimeOfLastReplicateScan or 0)
end
function S.Wait() return math.max(0, COOLDOWN - (time() - LastFullScan())) end

local busy, got, startedAt = false, false, 0
local ev = CreateFrame("Frame")

local function Finish(found, n)
  local items, count = {}, 0
  local status = C_AuctionHouse and C_AuctionHouse.GetItemCommodityStatus
  local COMMODITY = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
  for id, l in pairs(found) do
    table.sort(l, function(a, b) return a[1] < b[1] end)
    while #l > KEEP do table.remove(l) end
    local ok, st = false, nil
    if status then ok, st = pcall(status, id) end
    items[id] = { c = ok and st == COMMODITY or nil, l = l }
    count = count + 1
  end
  WritPathPrices = WritPathPrices or {}
  WritPathPrices.items, WritPathPrices.t, WritPathPrices.auctions = items, time(), n
  busy = false
  ev:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  Print(("Scanned %d auctions in %d s: prices for %d writs and writ items saved."):format(n, math.floor(GetTime() - startedAt + 0.5), count))
  if WritPath_PlannerLearned then WritPath_PlannerLearned() end
end

local function Process()
  local n = C_AuctionHouse.GetNumReplicateItems() or 0
  local want, me = Wanted(), UnitName("player")
  local found, i = {}, 0
  local function Step()
    local stop = math.min(i + 2000, n)
    for k = i, stop - 1 do
      local info = { C_AuctionHouse.GetReplicateItemInfo(k) }
      local q, buy, owner, id = info[3], info[10], info[14], info[17]
      if id and want[id] and q and q > 0 and buy and buy > 0 and owner ~= me then
        local l = found[id] or {}
        l[#l + 1] = { buy / q, q }
        found[id] = l
      end
    end
    i = stop
    if i < n then C_Timer.After(0, Step) else Finish(found, n) end
  end
  Step()
end

function S.Start()
  if busy then Print("A scan is already running."); return end
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then Print("This auction house can't do a full scan."); return end
  local wait = S.Wait()
  if wait > 0 then
    Print(("The auction house allows one full scan every 15 minutes (Auctionator's count too): try again in %d:%02d."):format(math.floor(wait / 60), wait % 60))
    return
  end
  busy, got, startedAt = true, false, GetTime()
  WritPathPrices = WritPathPrices or {}
  WritPathPrices.replicateAt = time()
  ev:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  Print("Scanning the auction house for writs and the items they ask for...")
  C_AuctionHouse.ReplicateItems()
  C_Timer.After(90, function()
    if busy and not got then busy = false; Print("The auction house didn't answer the scan. Try again in 15 minutes.") end
  end)
end

ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
local button
ev:SetScript("OnEvent", function(_, event)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    if busy and not got then got = true; Process() end
  elseif event == "AUCTION_HOUSE_SHOW" then
    local ah = AuctionHouseFrame or AuctionFrame
    if not button then
      button = CreateFrame("Button", "WritPathScanButton", UIParent, "UIPanelButtonTemplate")
      button:SetSize(150, 22); button:SetText("WritPath: scan writs"); button:SetFrameStrata("HIGH")
      button:SetScript("OnClick", S.Start)
      button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Scan writ prices")
        GameTooltip:AddLine("Reads the whole auction house once and keeps the prices of writs and the items they ask for. Once every 15 minutes.", 1, 1, 1, true)
        local w = S.Wait()
        if w > 0 then GameTooltip:AddLine(("Next scan in %d:%02d."):format(math.floor(w / 60), w % 60), 1, 0.82, 0) end
        GameTooltip:Show()
      end)
      button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    button:ClearAllPoints()
    if ah then button:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", 0, -4) else button:SetPoint("CENTER") end
    button:Show()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if button then button:Hide() end
    if busy then busy = false; Print("The scan stopped: the auction house was closed.") end
  end
end)

-- what one unit costs when you need n of them, from WritPath's scan: commodities can be bought a unit at a time,
-- other listings only whole (a stack of 6 writs costs all 6). nil when the scan didn't see it.
function WritPath_ScanPrice(id, n)
  local e = WritPathPrices and WritPathPrices.items and WritPathPrices.items[id]
  if not (e and e.l and e.l[1]) then return nil end
  n = math.max(1, n or 1)
  local got, cost = 0, 0
  for _, x in ipairs(e.l) do
    local take = e.c and math.min(x[2], n - got) or x[2]
    got, cost = got + take, cost + take * x[1]
    if got >= n then break end
  end
  if got < n then return nil end
  return cost / n
end
function WritPath_ScanTime() return WritPathPrices and WritPathPrices.t end
