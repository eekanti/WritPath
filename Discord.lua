-- WritPath: the WritPath Discord's invite link, ready to copy.
--
-- Addons can't put text on the clipboard (only Blizzard's own UI can), so the Discord button, /writs discord and a
-- shift-click on the minimap button show the link already selected in a small box: Ctrl+C copies it. Enter or
-- Escape closes the box. A chat line says the same, with the link, for anyone who'd rather copy it from chat.

local DISCORD = "https://discord.gg/8PJXe24u5V"
WritPath_DISCORD = DISCORD

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end
local H = "|cFFFFD100"

-- WritPath's own frame, not a StaticPopup (an addon using those taints them: see Planner.lua's confirm window)
local win, box
local function Build()
  if win then return win end
  win = CreateFrame("Frame", "WritPathDiscord", UIParent, "BackdropTemplate")
  win:SetSize(300, 74); win:SetPoint("CENTER", 0, 160)
  win:SetFrameStrata("DIALOG"); win:SetToplevel(true); win:EnableMouse(true); win:SetClampedToScreen(true)
  local bg = win:CreateTexture(nil, "BACKGROUND", nil, -8); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 1)
  win:Hide()
  tinsert(UISpecialFrames, "WritPathDiscord")   -- Escape closes it
  local note = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  note:SetPoint("TOP", 0, -12); note:SetText("WritPath Discord: press " .. H .. "Ctrl+C|r to copy")
  box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
  box:SetSize(260, 22); box:SetPoint("TOP", note, "BOTTOM", 2, -10); box:SetAutoFocus(false)
  -- selectable but not editable; Enter and Escape close it
  box:SetScript("OnTextChanged", function(self, user) if user then self:SetText(DISCORD); self:HighlightText() end end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
  box:SetScript("OnEnterPressed", function() win:Hide() end)
  box:SetScript("OnEscapePressed", function() win:Hide() end)
  win:SetScript("OnHide", function() box:ClearFocus() end)
  local S = WritPath_Skin and WritPath_Skin()
  if S then
    S.Shell(win); S.EditBox(box); S.Font(note)
  else
    win:SetBackdrop({ bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 })
    win:SetBackdropColor(0.06, 0.06, 0.07, 0.97); win:SetBackdropBorderColor(0, 0, 0, 1)
  end
  return win
end

function WritPath_CopyDiscord()
  Build()
  box:SetText(DISCORD)
  win:Show(); win:Raise()
  box:SetFocus(); box:HighlightText()
  Print("The Discord link is selected: press " .. H .. "Ctrl+C|r to copy it, then paste it in your browser. " .. DISCORD)
end
WritPath_DiscordInternals = { Win = function() return win end, Box = function() return box end }   -- for tests

-- once per player: there's a Discord now
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  WritPathNav = WritPathNav or {}
  if WritPathNav.discordTold then return end
  WritPathNav.discordTold = true
  C_Timer.After(4, function() Print("WritPath has a Discord for help and news: click the Discord logo on the guide, or " .. H .. "/writs discord|r") end)
end)
