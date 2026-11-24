-- AHAdvisor - the suggestions window and the item tooltip lines.
local _, ns = ...
local UI = {}
ns.UI = UI

local ROWS, ROW_H = 14, 24
local FILTERS = {
  { id = "all", label = "All" },
  { id = "buy", label = "Buy", kinds = { Vendor = true, Snipe = true, Dip = true, Rising = true, Pattern = true } },
  { id = "sell", label = "Sell", kinds = { Sell = true } },
  { id = "craft", label = "Craft", kinds = { Craft = true } },
}
local KIND_COLOR = {
  Vendor = "40ff40", Snipe = "40c0ff", Dip = "80a0ff", Rising = "ffd040",
  Pattern = "d080ff", Sell = "ff9040", Craft = "60e0c0",
}

local frame, rows, offset, filter, shown = nil, {}, 0, "all", {}

local function ItemIcon(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  if GetItemIcon then return GetItemIcon(id) end
  return select(10, GetItemInfo(id))
end

local function QualityHex(q)
  local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c and c.hex then return c.hex end
  return "|cffffffff"
end

local function ItemLink(key)
  local id = ns.IdFromKey(key)
  local _, link = GetItemInfo(id or 0)
  return link
end

-- search the item in Blizzard's browse tab
local function SearchAH(name)
  if not (ns.ahOpen and AuctionFrame and AuctionFrame:IsShown() and BrowseName) then return false end
  if ns.Scan.Busy() then ns.Print("Wait for the scan to finish.") return true end
  if AuctionFrameTab1 and AuctionFrameBrowse and not AuctionFrameBrowse:IsShown() then AuctionFrameTab1:Click() end
  BrowseName:SetText(name)
  if AuctionFrameBrowse_Search then AuctionFrameBrowse_Search() end
  return true
end

local function ShowRowTooltip(row)
  local s = row.sug
  if not s then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  local link = ItemLink(s.key)
  GameTooltip:AddLine((QualityHex(s.q)) .. (s.name or link or s.key) .. "|r")
  GameTooltip:AddLine(string.format("|cff%s%s|r: %s", KIND_COLOR[s.kind] or "ffffff", s.kind, s.action), 1, 1, 1, true)
  GameTooltip:AddLine(" ")
  for _, line in ipairs(s.reasons or {}) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
  GameTooltip:AddLine(" ")
  if s.cost and s.cost > 0 then GameTooltip:AddDoubleLine("Gold needed", ns.Money(s.cost), 0.7, 0.7, 0.7, 1, 1, 1) end
  GameTooltip:AddDoubleLine("Estimated profit", ns.Money(s.profit), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("Confidence", string.format("%d%%", s.conf * 100), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: search it on the auction house. Shift-click: link it.", 0.5, 0.8, 1, true)
  GameTooltip:Show()
end

local function Filtered()
  wipe(shown)
  local kinds
  for _, f in ipairs(FILTERS) do if f.id == filter then kinds = f.kinds end end
  for _, s in ipairs(ns.Analysis.list) do
    if not kinds or kinds[s.kind] then shown[#shown + 1] = s end
  end
  return shown
end

local function UpdateRows()
  if not frame then return end
  local list = shown
  offset = math.max(0, math.min(offset, #list - ROWS))
  for i = 1, ROWS do
    local row, s = rows[i], list[offset + i]
    row.sug = s
    if s then
      local id = ns.IdFromKey(s.key)
      row.icon:SetTexture(ItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.name:SetText(QualityHex(s.q) .. (s.name or ("item " .. s.key)) .. "|r")
      row.kind:SetText(string.format("|cff%s%s|r", KIND_COLOR[s.kind] or "ffffff", s.kind))
      row.action:SetText(s.action)
      row.profit:SetText(ns.Money(s.profit))
      row.conf:SetText(string.format("%d%%", s.conf * 100))
      row:Show()
    else
      row:Hide()
    end
  end
  if #list == 0 then
    local R = ns.R()
    if (R.scans or 0) == 0 then
      frame.empty:SetText("No data yet.\n\nOpen the auction house and press Scan.\nScan a few times a day: suggestions get better as history builds up.")
    elseif (R.scans or 0) < 3 then
      frame.empty:SetText("Learning prices...\n\nA few more scans (preferably hours apart) are needed before\nthe advisor can tell a bargain from a normal price.")
    else
      frame.empty:SetText("Nothing worth doing right now with these filters.\n\nTry /aha minprofit or /aha minconf with a lower value, or scan again later.")
    end
    frame.empty:Show()
  else
    frame.empty:Hide()
  end
  frame.count:SetText(#list > 0 and string.format("%d-%d of %d", offset + 1, math.min(#list, offset + ROWS), #list) or "")
end

local function UpdateButtons()
  if not frame then return end
  frame.scan:SetEnabled(ns.ahOpen and not ns.Scan.Busy())
  for _, b in ipairs(frame.filters) do
    if b.id == filter then b:LockHighlight() else b:UnlockHighlight() end
  end
end

function UI.Refresh()
  if not frame then return end
  Filtered()
  UpdateRows()
  UpdateButtons()
  local A, R = ns.Analysis, ns.R()
  if (R.lastScan or 0) > 0 then
    local age = time() - R.lastScan
    local ageText = age < 3600 and string.format("%d min ago", age / 60) or string.format("%d h ago", age / 3600)
    frame.info:SetText(string.format("Last scan %s - %d scans so far.%s", ageText, R.scans or 0,
      A.fresh == false and " |cffff8040Scan again for buy suggestions.|r" or ""))
  else
    frame.info:SetText("")
  end
end

function UI.SetStatus(text)
  if not frame then return end
  frame.status:SetText(text or "")
  UpdateButtons()
end

local function MakeText(parent, template, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT")
  if width then fs:SetWidth(width) end
  fs:SetWordWrap(false)
  return fs
end

local COLS = { -- x, width
  name = { 34, 200 }, kind = { 240, 56 }, action = { 300, 250 }, profit = { 556, 90 }, conf = { 650, 40 },
}

local function Create()
  local f = CreateFrame("Frame", "AHAdvisorFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame = f
  f:SetSize(712, 110 + ROWS * ROW_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24,
      insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
  end
  tinsert(UISpecialFrames, "AHAdvisorFrame")
  f:Hide()

  local title = MakeText(f, "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("AHAdvisor")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  f.scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.scan:SetSize(90, 22)
  f.scan:SetPoint("TOPLEFT", 130, -12)
  f.scan:SetText("Scan")
  f.scan:SetScript("OnClick", function() ns.Scan.Start() end)

  f.filters = {}
  local prev
  for _, def in ipairs(FILTERS) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(60, 22)
    b:SetText(def.label)
    b.id = def.id
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", f.scan, "RIGHT", 24, 0) end
    b:SetScript("OnClick", function()
      filter, offset = def.id, 0
      UI.Refresh()
    end)
    f.filters[#f.filters + 1] = b
    prev = b
  end

  f.info = MakeText(f, "GameFontDisableSmall", "LEFT", 560)
  f.info:SetPoint("TOPLEFT", 16, -42)

  -- column headers
  local headers = { name = "Item", kind = "Type", action = "Suggestion", profit = "Profit", conf = "Conf." }
  for col, text in pairs(headers) do
    local h = MakeText(f, "GameFontNormalSmall", (col == "profit" or col == "conf") and "RIGHT" or "LEFT", COLS[col][2])
    h:SetPoint("TOPLEFT", COLS[col][1], -62)
    h:SetText(text)
  end

  local list = CreateFrame("Frame", nil, f)
  list:SetPoint("TOPLEFT", 10, -76)
  list:SetSize(692, ROWS * ROW_H)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    UpdateRows()
  end)

  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, list)
    row:SetSize(692, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    if i % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND")
      stripe:SetAllPoints()
      stripe:SetColorTexture(1, 1, 1, 0.03)
    end
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 4, ROW_H - 4)
    row.icon:SetPoint("LEFT", 6, 0)
    for col, def in pairs(COLS) do
      local fs = MakeText(row, nil, (col == "profit" or col == "conf") and "RIGHT" or "LEFT", def[2])
      fs:SetPoint("LEFT", def[1] - 10, 0)
      row[col] = fs
    end
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      local s = self.sug
      if not s then return end
      if IsShiftKeyDown() then
        local link = ItemLink(s.key)
        if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
      elseif not SearchAH(s.name or "") then
        ns.Print("Open the auction house to search for %s.", s.name or "it")
      end
    end)
    rows[i] = row
  end

  f.empty = MakeText(list, "GameFontNormal", "CENTER", 600)
  f.empty:SetWordWrap(true)
  f.empty:SetPoint("CENTER")

  f.status = MakeText(f, "GameFontHighlightSmall", "LEFT", 540)
  f.status:SetPoint("BOTTOMLEFT", 16, 14)
  f.status:SetText(ns.Scan.statusText or "")
  f.count = MakeText(f, "GameFontDisableSmall", "RIGHT", 140)
  f.count:SetPoint("BOTTOMRIGHT", -16, 14)

  f:SetScript("OnShow", function() UI.Refresh() end)
end

function UI.Show()
  if not frame then Create() end
  frame:Show()
  ns.Analysis.Run()
end

function UI.Toggle()
  if frame and frame:IsShown() then frame:Hide() else UI.Show() end
end

function UI.OnAuctionHouse(open)
  if open and AuctionFrame and not UI.ahButton then
    local b = CreateFrame("Button", nil, AuctionFrame, "UIPanelButtonTemplate")
    b:SetSize(80, 20)
    b:SetPoint("TOPRIGHT", AuctionFrame, "TOPRIGHT", -40, -14)
    b:SetText("Advisor")
    b:SetScript("OnClick", UI.Toggle)
    UI.ahButton = b
  end
  if open and ns.settings.autoOpen then
    UI.Show()
    if AuctionFrame and frame then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 0, -10)
    end
  end
  UpdateButtons()
end

---------------------------------------------------------------------------------------------
-- Tooltip: what the advisor knows about an item
---------------------------------------------------------------------------------------------
ns.Tooltip = {}

local function AddLines(tt)
  if not tt or not tt.GetItem then return end
  local _, link = tt:GetItem()
  local key = ns.KeyFromLink(link)
  if not key or not AHAdvisorDB then return end
  local it = ns.R().items[key]
  if not it or not it.cur then return end
  local now = time()
  local cur = it.cur
  local base, vol = ns.Data.Stats(it, now)
  local rate = ns.Data.Rate(it)
  local slope, r2 = ns.Data.Trend(it, 7)
  local age = now - cur.t
  tt:AddDoubleLine("|cff33ff99AHAdvisor|r", age < 3600 and string.format("%d min ago", age / 60)
    or string.format("%d h ago", age / 3600), 1, 1, 1, 0.6, 0.6, 0.6)
  if cur.qty > 0 then
    tt:AddDoubleLine("  Market now", string.format("%s  (%d listed)", ns.Money(cur.mv), cur.qty), 0.8, 0.8, 0.8, 1, 1, 1)
  else
    tt:AddDoubleLine("  Market now", "none listed", 0.8, 0.8, 0.8, 1, 0.5, 0.25)
  end
  if base then
    tt:AddDoubleLine("  Normal price", string.format("%s  (+/-%d%%)", ns.Money(base), vol * 100), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  if rate then tt:AddDoubleLine("  Sells per day", string.format("~%.1f", rate), 0.8, 0.8, 0.8, 1, 1, 1) end
  if slope and r2 >= 0.5 and math.abs(slope) >= 0.01 then
    tt:AddDoubleLine("  Week trend", string.format("%+.1f%% a day", slope * 100), 0.8, 0.8, 0.8,
      slope > 0 and 0.4 or 1, slope > 0 and 1 or 0.4, 0.4)
  end
end

function ns.Tooltip.Init()
  if ns.Tooltip.done then return end
  ns.Tooltip.done = true
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt == GameTooltip or tt == ItemRefTooltip then AddLines(tt) end
    end)
  else
    GameTooltip:HookScript("OnTooltipSetItem", AddLines)
    if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", AddLines) end
  end
end
