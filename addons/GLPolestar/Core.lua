-- GLPolestar - collects Guidelime guides and registers them with Polestar.
--
-- Three sources, all converted by Convert.lua and registered as guides of one
-- Polestar community pack ("Guidelime guides" in Polestar's guide menu):
--   * Guidelime guide addons: they call Guidelime.registerGuide(text, group) as
--     they load; this addon wraps that call (it loads after Guidelime and, by
--     its folder name, before them) and keeps a copy of every guide.
--   * Guidelime's own custom guides (its editor): registered the same way at login.
--   * Guides pasted into this addon's window (/glp), kept in GLPolestarDB.
local ADDON, ns = ...
local C = ns.Convert

ns.VERSION = "1.0.0"

function ns.Print(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cff9acd32Guidelime for Polestar|r: " .. msg)
end

local API = Polestar and Polestar.API
ns.ready = API and API.version == 1 and type(Polestar.RegisterPack) == "function"
  and type(Polestar.RegisterGuide) == "function" or false

---------------------------------------------------------------------------------------------
-- The pack
---------------------------------------------------------------------------------------------
if ns.ready then
  local ok, err = Polestar.RegisterPack({
    addon = ADDON, id = C.PACK, format = 5,
    title = "Guidelime guides", author = "Guidelime guide authors", version = ns.VERSION,
    license = "Each guide's own",
    source = "Guidelime guides converted in game by Guidelime for Polestar",
    notes = "Guides written for Guidelime. Report problems in a guide to its author.",
  })
  if not ok then
    ns.ready = false
    ns.packError = err
  end
end

---------------------------------------------------------------------------------------------
-- Guides
---------------------------------------------------------------------------------------------
ns.guides = {} -- id -> record
ns.order = {}  -- ids, in the order they came in
ns.counts = { addon = 0, pasted = 0 }

-- text, group, source ("addon" | "pasted") -> record
-- record = { id, title, group, source, steps, warnings, err }
function ns.Add(text, group, source)
  group = (type(group) == "string" and group ~= "") and group or "Imported"
  local def, warnings = C.Convert(text, group)
  local rec = { group = group, source = source }
  if not def then
    rec.err = warnings
    rec.title = (type(text) == "string" and text:match("%[N%s*[%d%.%-%s]*([^%]]+)%]")) or "?"
    rec.id = "?" .. tostring(#ns.order + 1)
  else
    rec.id, rec.title, rec.steps, rec.warnings = def.id, def.title, #def.steps, warnings
    if not ns.ready then
      rec.err = "Polestar is not ready"
    else
      local ok, err = Polestar.RegisterGuide(def)
      if not ok then rec.err = err or "refused" end
    end
  end
  if not ns.guides[rec.id] then ns.order[#ns.order + 1] = rec.id end
  ns.guides[rec.id] = rec
  if not rec.err then ns.counts[source] = (ns.counts[source] or 0) + 1 end
  return rec
end

-- Guidelime's group names: "Guidelime_Sage" reads "Sage", as in Guidelime's own list.
local function groupName(group)
  if type(group) ~= "string" then return nil end
  return (group:gsub("^Guidelime_", ""))
end

---------------------------------------------------------------------------------------------
-- The hook on Guidelime.registerGuide
---------------------------------------------------------------------------------------------
local hooked = false
local function hook()
  if hooked or type(Guidelime) ~= "table" or type(Guidelime.registerGuide) ~= "function" then return end
  hooked = true
  local original = Guidelime.registerGuide
  Guidelime.registerGuide = function(guide, group, ...)
    if type(guide) == "string" then
      local ok, err = pcall(ns.Add, guide, groupName(group), "addon")
      if not ok then ns.Print("could not convert a guide: %s", tostring(err)) end
    end
    return original(guide, group, ...)
  end
end
hook()
ns.hooked = function() return hooked end

---------------------------------------------------------------------------------------------
-- Pasted guides (GLPolestarDB.pasted: id -> { text, group })
---------------------------------------------------------------------------------------------
function ns.Paste(text, group)
  local rec = ns.Add(text, group, "pasted")
  if rec.steps then
    GLPolestarDB.pasted[rec.id] = { text = text, group = rec.group }
  end
  return rec
end

function ns.RemovePasted(id)
  if GLPolestarDB.pasted[id] then
    GLPolestarDB.pasted[id] = nil
    return true
  end
  return false
end

---------------------------------------------------------------------------------------------
-- Guide addons that loaded before the hook
---------------------------------------------------------------------------------------------
-- The addons that depend on Guidelime and are loaded: its guide addons.
local function guideAddons()
  local list = {}
  local A = C_AddOns
  if not (A and A.GetNumAddOns and A.GetAddOnDependencies and A.IsAddOnLoaded) then return list end
  for i = 1, A.GetNumAddOns() do
    local name = A.GetAddOnInfo(i)
    if name and name ~= ADDON and A.IsAddOnLoaded(name) then
      for _, dep in ipairs({ A.GetAddOnDependencies(name) }) do
        if dep == "Guidelime" then
          list[#list + 1] = name
          break
        end
      end
    end
  end
  return list
end
ns.GuideAddons = guideAddons

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON then
    GLPolestarDB = type(GLPolestarDB) == "table" and GLPolestarDB or {}
    GLPolestarDB.pasted = GLPolestarDB.pasted or {}
    -- Pasted guides come in before login, so Polestar's saved tabs find them.
    for _, p in pairs(GLPolestarDB.pasted) do
      pcall(ns.Add, p.text, p.group, "pasted")
    end
  elseif event == "ADDON_LOADED" and name == "Guidelime" then
    hook()
  elseif event == "PLAYER_LOGIN" then
    if not ns.ready then
      if ns.packError then
        ns.Print("Polestar refused the guide pack: %s", tostring(ns.packError))
      else
        ns.Print("this Polestar has no guide API this addon knows (it needs Polestar.API version 1).")
      end
      return
    end
    local addons = guideAddons()
    -- Guidelime's custom guides come through the hook too, at login; leave them out of the count.
    local custom = 0
    if type(GuidelimeData) == "table" and type(GuidelimeData.customGuides) == "table" then
      for _ in pairs(GuidelimeData.customGuides) do custom = custom + 1 end
    end
    if #addons > 0 and ns.counts.addon <= custom then
      ns.Print("%d Guidelime guide addon(s) loaded before this addon could catch their guides (%s). Keep the folder name GLPolestar so it loads first.",
        #addons, table.concat(addons, ", "))
    end
    local failed = 0
    for _, id in ipairs(ns.order) do
      if ns.guides[id].err then failed = failed + 1 end
    end
    if failed > 0 then
      ns.Print("%d guide(s) could not be converted; /glp list shows why.", failed)
    end
  end
end)

---------------------------------------------------------------------------------------------
-- /glp
---------------------------------------------------------------------------------------------
local function sortedIds()
  local ids = {}
  for _, id in ipairs(ns.order) do ids[#ids + 1] = id end
  return ids
end

local function list()
  local ids = sortedIds()
  if #ids == 0 then
    ns.Print("no guides yet. Install Guidelime guide addons, or paste a guide with /glp.")
    return
  end
  for i, id in ipairs(ids) do
    local r = ns.guides[id]
    local state
    if r.err then
      state = "|cffff5555" .. tostring(r.err) .. "|r"
    else
      state = ("%d steps"):format(r.steps)
      if r.warnings and #r.warnings > 0 then state = state .. (", |cffffcc00%d warning(s)|r"):format(#r.warnings) end
    end
    DEFAULT_CHAT_FRAME:AddMessage(("  %d. [%s] %s%s - %s"):format(i, r.group, r.title,
      r.source == "pasted" and " (pasted)" or "", state))
  end
end

local function byIndex(arg)
  local ids = sortedIds()
  local n = tonumber(arg)
  local id = n and ids[n]
  return id and ns.guides[id], id
end

SLASH_GLPOLESTAR1 = "/glp"
SlashCmdList.GLPOLESTAR = function(msg)
  local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" then
    ns.ToggleWindow()
  elseif cmd == "list" then
    list()
  elseif cmd == "open" then
    local r, id = byIndex(arg)
    if not r or r.err then
      ns.Print("no guide %s that Polestar took; see /glp list.", arg)
    elseif not Polestar.Engine.SetGuide(id) then
      ns.Print("Polestar could not open it (is the Guidelime guides pack switched off under Options > Community guides?).")
    end
  elseif cmd == "warnings" then
    local r = byIndex(arg)
    if not r then
      ns.Print("no guide %s; see /glp list.", arg)
    elseif not r.warnings or #r.warnings == 0 then
      ns.Print("%s: no warnings.", r.title)
    else
      ns.Print("%s:", r.title)
      for _, w in ipairs(r.warnings) do DEFAULT_CHAT_FRAME:AddMessage("  " .. w) end
    end
  elseif cmd == "remove" then
    local r, id = byIndex(arg)
    if r and r.source == "pasted" and ns.RemovePasted(id) then
      ns.Print("removed %s; it leaves Polestar's guide menu after a /reload.", r.title)
    else
      ns.Print("only pasted guides can be removed; see /glp list.")
    end
  else
    ns.Print("/glp - paste a guide; /glp list; /glp open <n>; /glp warnings <n>; /glp remove <n>")
  end
end
