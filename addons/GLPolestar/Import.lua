-- GLPolestar - the paste window (/glp): paste a Guidelime guide, add it to Polestar.
local _, ns = ...

local win

local function build()
  local f = CreateFrame("Frame", "GLPolestarWindow", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(560, 440)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "GLPolestarWindow")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -6)
  f.title:SetText("Guidelime for Polestar")

  local help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  help:SetPoint("TOPLEFT", 14, -32)
  help:SetPoint("TOPRIGHT", -14, -32)
  help:SetJustifyH("LEFT")
  help:SetText("Paste a Guidelime guide (its text, starting with [N ...]). It is added to Polestar's guide menu under Community guides > Guidelime guides, and kept for your next logins.")

  local groupLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  groupLabel:SetPoint("TOPLEFT", 16, -70)
  groupLabel:SetText("Folder:")

  local group = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  group:SetSize(200, 20)
  group:SetPoint("LEFT", groupLabel, "RIGHT", 10, 0)
  group:SetAutoFocus(false)
  group:SetText("Imported")
  f.group = group

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -98)
  scroll:SetPoint("BOTTOMRIGHT", -34, 48)
  local bg = scroll:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", -4, 4)
  bg:SetPoint("BOTTOMRIGHT", 4, -4)
  bg:SetColorTexture(0, 0, 0, 0.4)

  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetMaxLetters(0)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(500)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(box)
  scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
  f.box = box

  local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", 16, 20)
  status:SetPoint("RIGHT", f, "RIGHT", -230, 0)
  status:SetJustifyH("LEFT")
  status:SetWordWrap(true)
  f.status = status

  local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  add:SetSize(100, 24)
  add:SetPoint("BOTTOMRIGHT", -16, 14)
  add:SetText("Add guide")

  local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  open:SetSize(100, 24)
  open:SetPoint("RIGHT", add, "LEFT", -6, 0)
  open:SetText("Open it")
  open:Disable()

  add:SetScript("OnClick", function()
    local text = box:GetText()
    if not text:find("%[N") then
      status:SetText("|cffff5555That is not a Guidelime guide: it has no [N ...] name.|r")
      return
    end
    local rec = ns.Paste(text, group:GetText())
    if rec.err then
      status:SetText("|cffff5555" .. tostring(rec.err) .. "|r")
      open:Disable()
      f.lastId = nil
    else
      local w = rec.warnings and #rec.warnings or 0
      status:SetText(("|cff55ff55Added %s: %d steps.|r%s"):format(rec.title, rec.steps,
        w > 0 and (" |cffffcc00%d warning(s), see /glp list.|r"):format(w) or ""))
      box:SetText("")
      f.lastId = rec.id
      open:Enable()
    end
  end)

  open:SetScript("OnClick", function()
    if f.lastId and Polestar.Engine.SetGuide(f.lastId) then f:Hide() end
  end)

  f:Hide()
  return f
end

function ns.ToggleWindow()
  win = win or build()
  if win:IsShown() then
    win:Hide()
  else
    win.status:SetText("")
    win:Show()
    win.box:SetFocus()
  end
end
