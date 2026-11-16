-- WritPath Buy next: the plan's shopping list at the auction house, a click per purchase.
-- WoW only lets an addon buy inside a click, so WritPath searches by itself, shows what it found
-- on the button, and your click buys it. Then it moves on.
--   Forever runs the modern auction house (C_AuctionHouse), like Auctionator assumes:
--     items (writs, gear)        one click:  PlaceBid(auctionID, buyout)
--     commodities (potions, ...) two clicks: StartCommoditiesPurchase (a firm price quote), then Confirm
--   The classic auction house (QueryAuctionItems / PlaceAuctionBid) is kept as a fallback.
--   * cheapest first, never your own auctions
--   * stacks: the cheapest that doesn't give you more than you need, else the cheapest one
--   * price cap: more than 25% over the price the plan was built on isn't bought unless you say so
--   * purchases may arrive by mail: what WritPath bought counts as yours before it's in your bags
-- The list comes from the plan (Start route or Send to Auctionator in the planner).

local CAP = 1.25
local G, W_, Y, GREY = "|cFF00FF25", "|cFFFCDC00", "|cFF00BCD4", "|cFFAAAAAA"
local MODERN = C_AuctionHouse and C_AuctionHouse.SendSearchQuery and true or false
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local function Count(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end
local function ItemName(id)
  if C_Item and C_Item.GetItemNameByID then local n = C_Item.GetItemNameByID(id); if n then return n end end
  return GetItemInfo and (GetItemInfo(id)) or nil
end
local function Coins(c)
  c = math.floor((c or 0) + 0.5)
  local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
  if g > 0 then return g .. "g " .. s .. "s" end
  if s > 0 then return s .. "s " .. c % 100 .. "c" end
  return c % 100 .. "c"
end

---------------------------------------------------------------- the list
-- { id, name, total = how many you need, unit = price the plan was built on, base = in your bags when the
--   list was made, bought = bought here since (may still be in the mail) }
function WritPath_SetShopList(list)
  for _, it in ipairs(list or {}) do it.base, it.bought = Count(it.id), 0 end
  WritPathNav.shopList = list
  WritPathNav.shopAt = time()
  if WritPath_BuyerRefresh then WritPath_BuyerRefresh() end
end

local state = { phase = "idle" }   -- idle, searching, ready, over, none, quote, confirm, buying, unsure, done
local function List() return WritPathNav and WritPathNav.shopList or {} end
local function Have(it) return math.max(Count(it.id), (it.base or 0) + (it.bought or 0)) end
local function Need(it) return math.max(0, (it.total or 1) - Have(it)) end
local function NextItem()
  for i, it in ipairs(List()) do if not it.skipped and Need(it) > 0 then return i, it end end
end
local function Progress()
  local done, total = 0, 0
  for _, it in ipairs(List()) do total = total + 1; if Need(it) == 0 then done = done + 1 end end
  return done, total
end

---------------------------------------------------------------- panel beside the auction house
local panel, title, itemText, statusText, mainBtn, altBtn, closeBtn
local fonts, btns, skin = {}, {}, nil
local function Text(parent, template, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true); fs:SetWidth(width)
  fonts[#fonts + 1] = fs
  return fs
end
local function AHFrame() return AuctionHouseFrame or AuctionFrame end
local function Build()
  if panel then return end
  local W = 250
  panel = CreateFrame("Frame", "WritPathBuyer", UIParent, "BackdropTemplate")
  panel:SetWidth(W); panel:SetFrameStrata("HIGH"); panel:SetClampedToScreen(true)
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  title = Text(panel, "GameFontNormal", W - 40); title:SetPoint("TOPLEFT", 10, -9)
  closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); closeBtn:SetSize(20, 20); closeBtn:SetPoint("TOPRIGHT", -3, -3)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)
  itemText = Text(panel, "GameFontHighlight", W - 20)
  statusText = Text(panel, "GameFontHighlightSmall", W - 20)
  mainBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); mainBtn:SetHeight(26); btns[#btns + 1] = mainBtn
  altBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); altBtn:SetHeight(22); btns[#btns + 1] = altBtn
  if skin then
    skin.Shell(panel); skin.CloseButton(closeBtn)
    for _, b in ipairs(btns) do skin.Button(b); if skin.StateButtonLabel then skin.StateButtonLabel(b) end end
    for _, fs in ipairs(fonts) do skin.Font(fs) end
  else
    local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
    panel:SetBackdrop(flat); panel:SetBackdropColor(0.06, 0.06, 0.07, 0.96); panel:SetBackdropBorderColor(0, 0, 0, 1)
  end
end
local function Dock()   -- beside the auction house window, whichever one this client has
  local ah = AHFrame()
  panel:ClearAllPoints()
  if ah then panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, -24) else panel:SetPoint("LEFT", UIParent, "LEFT", 40, 0) end
end
if EllesmereUI and EllesmereUI.RegisterSkin then EllesmereUI.RegisterSkin("WritPathBuyer", function(S) skin = S end) end

local Search

local function Render()
  if not panel then return end
  local done, total = Progress()
  title:SetText(("Writ shopping  %s%d / %d|r"):format(GREY, done, total))
  local it, p = state.it, state.pick
  local main, alt, status
  local unit = it and it.unit and it.unit > 0 and Coins(it.unit) or "?"
  if not it then
    itemText:SetText(total == 0 and (GREY .. "No shopping list yet.|r") or (G .. "Everything on the list is bought.|r"))
    status = total == 0 and "Start a route (or press Send to Auctionator) in the planner." or "Nothing left to buy."
  else
    itemText:SetText((ItemName(it.id) or it.name or "?") .. (Need(it) > 1 and (" x" .. Need(it)) or ""))
    local ph = state.phase
    if ph == "searching" then status, main = "Searching the auction house...", "Searching..."
    elseif ph == "ready" then
      local each = p.qty > 1 and (" (" .. Coins(p.unit) .. " each)") or ""
      status = ("Cheapest: %s%s|r for %d%s. The plan expected %s each."):format(Y, Coins(p.total), p.qty, each, unit)
      main = (p.kind == "commodity" and "Get price: " or "Buy for ") .. Coins(p.total)
      alt = "Skip"
    elseif ph == "over" then
      status = W_ .. ("Cheapest is %s each, more than %d%% over the %s the plan was built on."):format(Coins(p.unit), (CAP - 1) * 100, unit) .. "|r"
      main, alt = "Skip", "Buy anyway: " .. Coins(p.total)
    elseif ph == "quote" then status, main = "Getting a firm price...", "Getting price..."
    elseif ph == "confirm" then
      status = ("Firm price: %s%s|r for %d (%s each).%s"):format(Y, Coins(state.quoteTotal), p.qty, Coins(state.quoteUnit),
        state.quoteUnit > p.unit * 1.0001 and (W_ .. " Higher than the search showed.|r") or "")
      local overCap = it.unit and it.unit > 0 and state.quoteUnit > it.unit * CAP
      main, alt = (overCap and "Confirm anyway: " or "Confirm: ") .. Coins(state.quoteTotal), "Cancel"
    elseif ph == "none" then status, main = W_ .. "Not on the auction house right now.|r", "Skip"
    elseif ph == "buying" then status, main = "Buying...", "Buying..."
    elseif ph == "unsure" then
      status, main = W_ .. "The game didn't confirm that purchase. Check your mail and bags before buying again.|r", "Search again"
    else status, main = "Ready.", "Find it" end
  end
  statusText:SetText(status or "")
  itemText:ClearAllPoints(); itemText:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -32)
  local y = -32 - itemText:GetStringHeight() - 6
  statusText:ClearAllPoints(); statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y)
  y = y - statusText:GetStringHeight() - 10
  if main then
    mainBtn:SetText(main); mainBtn:Show()
    mainBtn:ClearAllPoints(); mainBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y); mainBtn:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    local busy = state.phase == "searching" or state.phase == "buying" or state.phase == "quote"
    if busy then mainBtn:Disable() else mainBtn:Enable() end
    y = y - 30
  else mainBtn:Hide() end
  if alt then
    altBtn:SetText(alt); altBtn:Show()
    altBtn:ClearAllPoints(); altBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y); altBtn:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    y = y - 26
  else altBtn:Hide() end
  panel:SetHeight(-y + 8)
end

---------------------------------------------------------------- searching (no click needed)
local queued, waiting = false, false
function Search()
  state.pick = nil
  state.i, state.it = NextItem()
  if not state.it then state.phase = "done"; Render(); return end
  state.phase = "searching"; queued, waiting = true, false
  Render()
end
WritPath_BuyerRefresh = function() if panel and panel:IsShown() then Search() end end

local function Ready()
  if MODERN then return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady() end
  return CanSendAuctionQuery and CanSendAuctionQuery()
end
local function SendQuery()
  local it = state.it
  if MODERN then
    -- one search: the game answers with commodity results or item results, whichever this item is
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(it.id), { sortOrder = 0, reverseSort = false }, true)
  else
    if SortAuctionSetSort then SortAuctionSetSort("list", "unitprice") end
    QueryAuctionItems(ItemName(it.id) or it.name, nil, nil, 0, nil, nil, false, true, nil)
  end
end

local function Decide(pick)
  state.pick = pick
  local it = state.it
  if not pick then state.phase = "none"
  elseif it.unit and it.unit > 0 and pick.unit > it.unit * CAP then state.phase = "over"
  else state.phase = "ready" end
  Render()
end

-- commodities: the cheapest units first, as many as you need (or all there are)
local function ChooseCommodity(itemID)
  local need, got, total, top = Need(state.it), 0, 0, 0
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    local mine = r and (r.containsOwnerItem or (r.owners and r.owners[1] == "player"))
    if r and not mine and got < need then
      local take = math.min(r.quantity or 0, need - got)
      got, total, top = got + take, total + take * r.unitPrice, r.unitPrice
    end
  end
  if got == 0 then return Decide(nil) end
  Decide({ kind = "commodity", itemID = itemID, qty = got, total = total, unit = total / got, top = top })
end

-- items: the cheapest auction that doesn't give you more than you need, else the cheapest one
local function ChooseItem(itemKey)
  local need, fit, any = Need(state.it), nil, nil
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not (r.containsOwnerItem or r.containsAccountItem) then
      local q = r.quantity or 1
      local l = { kind = "item", auctionID = r.auctionID, qty = q, total = r.buyoutAmount, unit = r.buyoutAmount / q }
      if q <= need and (not fit or l.unit < fit.unit) then fit = l end
      if not any or l.total < any.total then any = l end
    end
  end
  Decide(fit or any)
end

-- classic auction house
local function ChooseClassic()
  local it, me = state.it, UnitName("player")
  local need, fit, any = Need(it), nil, nil
  for i = 1, (GetNumAuctionItems("list")) or 0 do
    local info = { GetAuctionItemInfo("list", i) }
    local count, buyout, owner, itemId = info[3] or 1, info[10] or 0, info[14], info[17]
    if itemId == it.id and buyout > 0 and owner ~= me then
      local l = { kind = "classic", index = i, qty = count, total = buyout, unit = buyout / count, itemId = itemId }
      if count <= need and (not fit or l.unit < fit.unit) then fit = l end
      if not any or l.total < any.total then any = l end
    end
  end
  Decide(fit or any)
end

---------------------------------------------------------------- buying (inside a click)
local function Bought(qty)
  local it = state.it
  it.bought = (it.bought or 0) + qty
  Print(("Bought %s%s for %s."):format(ItemName(it.id) or it.name or "item", qty > 1 and (" x" .. qty) or "", Coins(state.paid or 0)))
  Search()
end

local function Buy()
  local p = state.pick
  state.since = GetTime()
  if p.kind == "item" then
    state.phase, state.paid = "buying", p.total
    C_AuctionHouse.PlaceBid(p.auctionID, p.total)
  elseif p.kind == "commodity" then
    state.phase = "quote"
    C_AuctionHouse.StartCommoditiesPurchase(p.itemID, p.qty)
  else
    local info = { GetAuctionItemInfo("list", p.index) }   -- still the same auction as shown?
    if not (info[17] == p.itemId and (info[3] or 1) == p.qty and (info[10] or 0) == p.total) then Search(); return end
    state.phase, state.paid, state.countBefore = "buying", p.total, Count(state.it.id)
    PlaceAuctionBid("list", p.index, p.total)
  end
  Render()
end

local function Click()
  local ph = state.phase
  if ph == "ready" then Buy()
  elseif ph == "confirm" then
    state.phase, state.paid, state.since = "buying", state.quoteTotal, GetTime()
    C_AuctionHouse.ConfirmCommoditiesPurchase(state.pick.itemID, state.pick.qty)
    Render()
  elseif ph == "over" or ph == "none" then state.it.skipped = true; Search()
  elseif ph ~= "searching" and ph ~= "buying" and ph ~= "quote" then Search() end
end
local function AltClick()
  local ph = state.phase
  if ph == "ready" then state.it.skipped = true; Search()
  elseif ph == "over" then Buy()
  elseif ph == "confirm" then
    if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
    Search()
  end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM", "BAG_UPDATE_DELAYED" }) do ev:RegisterEvent(e) end
if MODERN then
  for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED",
                       "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
                       "AUCTION_HOUSE_PURCHASE_COMPLETED" }) do pcall(ev.RegisterEvent, ev, e) end
else
  ev:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end

local WON = ERR_AUCTION_WON_S and ERR_AUCTION_WON_S:gsub("%%s", "(.+)") or "You won an auction for (.+)"

ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "AUCTION_HOUSE_SHOW" then
    Build(); Dock()
    mainBtn:SetScript("OnClick", Click); altBtn:SetScript("OnClick", AltClick)
    -- a list belongs to a plan: keep it while that route runs, or for a few hours after "Send to Auctionator"
    -- without a route. A leftover from an old plan is dropped instead of popping up at every visit.
    local routeOn = WritPathNav.route and #WritPathNav.route > 0
    local fresh = WritPathNav.shopAt and time() - WritPathNav.shopAt < 3 * 3600
    if not routeOn and not fresh then WritPathNav.shopList = nil end
    for _, it in ipairs(List()) do it.skipped = nil end
    -- only when the planner left you something to buy; an empty or finished list stays out of the way
    if not NextItem() then panel:Hide(); return end
    panel:Show()
    Search()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    queued, waiting = false, false
    if panel then panel:Hide() end
  elseif not (panel and panel:IsShown() and state.it) then
    return
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if waiting and a1 == state.it.id then waiting = false; ChooseCommodity(a1) end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if waiting and a1 and a1.itemID == state.it.id then waiting = false; ChooseItem(a1) end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    if waiting then
      for i = 1, (GetNumAuctionItems("list")) or 0 do   -- wait until every seller's name has loaded
        if select(14, GetAuctionItemInfo("list", i)) == nil then return end
      end
      waiting = false; ChooseClassic()
    end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if state.phase == "quote" then
      state.quoteUnit, state.quoteTotal = a1, a2
      local it = state.it
      if it.unit and it.unit > 0 and a1 > it.unit * CAP and state.pick.unit <= it.unit * CAP then
        -- the firm price jumped over the cap: say so before anything is bought
        Print(("%s went up to %s each, over the cap."):format(ItemName(it.id) or it.name, Coins(a1)))
      end
      state.phase = "confirm"; Render()
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
    if state.phase == "quote" or state.phase == "confirm" or state.phase == "buying" then Search() end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if state.phase == "buying" then Bought(state.pick.qty) end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if state.phase == "buying" and state.pick.kind == "item" then Bought(state.pick.qty) end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- "You won an auction for X": a buyout went through (any auction house)
    if state.phase == "buying" and state.pick.kind ~= "commodity" and type(a1) == "string" and a1:match(WON) then Bought(state.pick.qty) end
  elseif event == "BAG_UPDATE_DELAYED" then
    if state.phase == "buying" and state.pick.kind == "classic" and Count(state.it.id) > (state.countBefore or 0) then Bought(state.pick.qty) end
  elseif event == "UI_ERROR_MESSAGE" then
    if state.phase == "buying" or state.phase == "quote" then Search() end   -- sold to someone else, or not enough gold
  end
end)

-- queries go out as soon as the auction house allows one; a purchase that's never confirmed stops and asks
ev:SetScript("OnUpdate", function()
  if queued and state.it and Ready() then
    queued, waiting = false, true
    SendQuery()
  end
  if (state.phase == "buying" or state.phase == "quote") and GetTime() - (state.since or 0) > 8 then
    state.phase = "unsure"; Render()
  end
end)

WritPath_BuyerInternals = { State = state, Click = Click, AltClick = AltClick, Search = Search }
