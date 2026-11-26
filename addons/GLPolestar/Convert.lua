-- GLPolestar - Guidelime guide text -> a Polestar guide table.
--
-- A Guidelime guide is text: every line is a step, and codes in brackets carry
-- the meaning ("Accept [QA33 Wolves Across the Border] [G 48,42 Elwynn Forest]").
-- Parse() splits the text into lines of text and code elements; Build() turns
-- them into Polestar's guide table (docs/PACK_FORMAT.md in the Polestar repo,
-- "RegisterGuide(def)"). Where Polestar's quest database is loaded, quests get
-- their giver, hand-in NPC and objective targets from it, so the arrow can lead.
local _, ns = ...

local C = {}
ns.Convert = C

C.PACK = "guidelime"

local HEARTHSTONE = 8690

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Guidelime's markup out of a text: *highlight* and "\\" line breaks.
local function clean(s)
  -- Colour codes too: Polestar prints "|" as written.
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("%*([^\n]-)%*", "%1"):gsub("%*%*", "*"):gsub("\\\\", "\n")
  s = s:gsub("[ \t]+", " "):gsub(" ?\n ?", "\n")
  return trim(s)
end

local function slug(s)
  s = s:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  return s ~= "" and s or "guide"
end

local function num(s)
  return s and s ~= "" and tonumber(s) or nil
end

-- Guidelime names a guide "<min>-<max> <title>" within its group; NX refers to that.
function C.GuideName(minLevel, maxLevel, title)
  title = trim(title or "")
  if minLevel or maxLevel then
    return ((minLevel and tostring(minLevel) or "") .. "-" .. (maxLevel and tostring(maxLevel) or "") .. " " .. title)
  end
  return title
end

function C.GuideId(group, name)
  return C.PACK .. "/" .. slug(group or "guidelime") .. "/" .. slug(name)
end

---------------------------------------------------------------------------------------------
-- Classes, races, factions as Guidelime writes them (upper case, no spaces)
---------------------------------------------------------------------------------------------
local CLASSES = {
  WARRIOR = "WARRIOR", PALADIN = "PALADIN", HUNTER = "HUNTER", ROGUE = "ROGUE", PRIEST = "PRIEST",
  SHAMAN = "SHAMAN", MAGE = "MAGE", WARLOCK = "WARLOCK", DRUID = "DRUID", DEATHKNIGHT = "DEATHKNIGHT",
}
local CLASS_LIST = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local RACES = {
  HUMAN = "Human", DWARF = "Dwarf", NIGHTELF = "NightElf", GNOME = "Gnome", DRAENEI = "Draenei",
  ORC = "Orc", UNDEAD = "Scourge", SCOURGE = "Scourge", TAUREN = "Tauren", TROLL = "Troll", BLOODELF = "BloodElf",
}
local RACE_FACTION = {
  Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance", Draenei = "Alliance",
  Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde",
}
local FACTION_RACES = {
  Alliance = { "Human", "Dwarf", "NightElf", "Gnome", "Draenei" },
  Horde = { "Orc", "Scourge", "Tauren", "Troll", "BloodElf" },
}
local FACTIONS = { ALLIANCE = "Alliance", HORDE = "Horde" }

local SKILLS = {
  FIRSTAID = "First Aid", COOKING = "Cooking", FISHING = "Fishing", ALCHEMY = "Alchemy",
  BLACKSMITHING = "Blacksmithing", ENCHANTING = "Enchanting", ENGINEERING = "Engineering",
  HERBALISM = "Herbalism", LEATHERWORKING = "Leatherworking", MINING = "Mining", SKINNING = "Skinning",
  TAILORING = "Tailoring", RIDING = "Riding", LOCKPICKING = "Lockpicking",
}

-- "Human,!Warrior,Alliance" -> { classes, races, factions, notClasses, notRaces }
local function appliesTo(tag)
  local out = { classes = {}, races = {}, factions = {}, notClasses = {}, notRaces = {} }
  for token in tag:upper():gsub("%s", ""):gmatch("[^,]+") do
    local neg = token:sub(1, 1) == "!"
    if neg then token = token:sub(2) end
    if CLASSES[token] then
      table.insert(neg and out.notClasses or out.classes, CLASSES[token])
    elseif RACES[token] then
      table.insert(neg and out.notRaces or out.races, RACES[token])
    elseif FACTIONS[token] and not neg then
      table.insert(out.factions, FACTIONS[token])
    end
    -- Reputation, skill, spell, item, flavor (Classic, SoD, Hardcore ...) conditions: not carried over.
  end
  return out
end

---------------------------------------------------------------------------------------------
-- Parse
---------------------------------------------------------------------------------------------
-- Every code Guidelime knows. Longest first when matching: "REP" before "R", "QA" before "Q".
local CODES = {}
for _, c in ipairs({ "N", "NX", "LI", "D", "DL", "GA", "A", "O", "OC", "C", "OR", "Q", "QA", "QC", "QT", "QS",
  "QP", "QW", "G", "L", "XP", "H", "F", "T", "S", "P", "V", "R", "GG", "GL", "CI", "REP", "UI", "GI", "GT",
  "TAR", "SP", "LE", "SK" }) do
  CODES[c] = true
end

local function splitCode(raw)
  for n = 3, 1, -1 do
    local c = raw:sub(1, n)
    if CODES[c] then return c, trim(raw:sub(n + 1)) end
  end
  return nil, raw
end

-- "1-6 Title", "6-12Title", "Title" -> min, max, title
local function levelsAndTitle(tag)
  local a, b, title = tag:match("^%s*(%d*%.?%d*)%s*%-?%s*(%d*%.?%d*)%s*(.-)%s*$")
  return num(a), num(b), title or tag
end

-- text -> { title, minLevel, maxLevel, details, applies, next = { names }, lines = { { elements } } }
-- An element is { text = "..." } or { code = "QA", tag = "33 Wolves Across the Border" }.
function C.Parse(text)
  local g = { next = {}, lines = {}, unknown = {} }
  text = text:gsub("\r\n?", "\n"):gsub("\\\\\n", "\\\\")
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("%-%-.*", "")
    if line:find("%S") then
      local elements = {}
      local rest = line:gsub("(.-)%[(.-)%]", function(before, raw)
        if before ~= "" then elements[#elements + 1] = { text = before } end
        local code, tag = splitCode(raw)
        if not code then
          g.unknown[#g.unknown + 1] = raw
          elements[#elements + 1] = { text = raw }
        elseif code == "N" then
          g.minLevel, g.maxLevel, g.title = levelsAndTitle(tag)
        elseif code == "NX" then
          local a, b, t = levelsAndTitle(tag)
          g.next[#g.next + 1] = C.GuideName(a, b, t)
        elseif code == "D" then
          g.details = tag
        elseif code == "GA" then
          g.applies = appliesTo(tag)
        elseif code == "DL" or code == "GG" or code == "GL" or code == "GI" or code == "GT" then
          -- download links and Guidelime's automation switches: nothing to carry over
        else
          elements[#elements + 1] = { code = code, tag = tag }
        end
        return ""
      end)
      if rest ~= "" then elements[#elements + 1] = { text = rest } end
      if #elements > 0 then g.lines[#g.lines + 1] = elements end
    end
  end
  return g
end

---------------------------------------------------------------------------------------------
-- Names and places: Polestar's quest database when it is there, else the client
---------------------------------------------------------------------------------------------
local dbTried = false
local function questDB()
  local Q = Polestar and Polestar.QuestDB
  if not (Q and Q.IsLoaded) then return nil end
  if not Q.IsLoaded() and not dbTried and Q.Load then
    dbTried = true
    pcall(Q.Load)
  end
  return Q.IsLoaded() and Q or nil
end

local function db(fn, ...)
  local Q = questDB()
  if not (Q and Q[fn]) then return nil end
  local ok, v = pcall(Q[fn], ...)
  return ok and v or nil
end

local function given(title)
  return title and title ~= "" and title ~= "-" and title or nil
end

-- titles: the guide's own names for quests so far (a guide names a quest once, at [QA]).
local function questTitle(id, title, titles)
  local t = given(title)
  if t then
    titles[id] = t
    return t
  end
  t = titles[id] or db("GetQuestTitle", id)
  if not t and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, v = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and type(v) == "string" and v ~= "" then t = v end
  end
  return t or ("Quest #" .. id), t == nil
end

local function itemName(id, title)
  local n = given(title)
  if not n then
    local item = db("GetItem", id)
    n = item and item.name
  end
  if not n and C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(id) end
  if not n and GetItemInfo then n = GetItemInfo(id) end
  return n or ("Item #" .. id)
end

local function spellName(id)
  local n
  if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id) end
  if not n and GetSpellInfo then n = GetSpellInfo(id) end
  return n
end

-- The spawn of an NPC or object to lead to: one on `map` if any, else the first.
local function place(entity, map)
  local spawns = entity and entity.spawns
  if type(spawns) ~= "table" or #spawns == 0 then return nil end
  for _, s in ipairs(spawns) do
    if s.map == map then return s end
  end
  return spawns[1]
end

local function locate(goal, spawn)
  if spawn and spawn.map and spawn.x and spawn.y then
    goal.map, goal.x, goal.y, goal.f = spawn.map, spawn.x, spawn.y, spawn.f
  end
end

-- An accept's giver or a turnin's recipient: npc/npcName or object/objName, placed.
local function questEnd(goal, refs, map)
  if not refs then return end
  local npc = refs.npc and refs.npc[1]
  if npc then
    local e = db("GetNpc", npc)
    goal.npc, goal.npcName = npc, e and e.name or nil
    if not goal.npcName then goal.npc = nil end
    locate(goal, place(e, map))
    return
  end
  local obj = refs.object and refs.object[1]
  if obj then
    local e = db("GetObject", obj)
    if e and e.name then goal.object, goal.objName = obj, e.name end
    locate(goal, place(e, map))
  end
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------
local LOCATABLE = { accept = true, turnin = true, complete = true, kill = true, collect = true,
  interact = true, use = true, task = true, note = true, vendor = true, train = true }

-- One step's goals from its elements. st: the guide's running state (current zone).
local function buildStep(elements, st, warn)
  local goals, parts, hasText = {}, {}, false
  local only, optionalStep, loc
  local last

  local function add(goal)
    goals[#goals + 1] = goal
    last = goal
    return goal
  end

  -- x,y[,radius] [zone]
  local function coords(tag)
    local x, y, rest = tag:match("^(%d+%.?%d*)%s*,%s*(%d+%.?%d*)%s*(.*)$")
    if not x then return nil end
    local radius
    local r, z = rest:match("^,%s*(%d*%.?%d*)%s*(.*)$")
    if r then radius, rest = num(r), z end
    rest = trim(rest)
    if rest ~= "" then
      local map = ns.Zones.MapID(rest)
      if map then
        st.zone = map
      else
        warn("unknown zone " .. rest)
        return nil
      end
    end
    if not st.zone then
      warn("coordinates before any zone")
      return nil
    end
    x, y = tonumber(x), tonumber(y)
    if x < 0 or x > 100 or y < 0 or y > 100 then return nil end
    return { map = st.zone, x = x, y = y, f = "e" }, radius
  end

  for _, el in ipairs(elements) do
    if el.text then
      parts[#parts + 1] = el.text
      if el.text:find("%a") then hasText = true end
    else
      local code, tag = el.code, el.tag
      if code == "QA" or code == "QP" or code == "QT" or code == "QC" or code == "Q" or code == "QW" or code == "QS" then
        local id, oi, title = tag:match("^(%d+)%s*,?%s*(%d*)%s*(.-)%s*$")
        id, oi = num(id), num(oi)
        if not id then
          warn("quest code without an id: " .. tag)
        else
          local name, unnamed = questTitle(id, title, st.titles)
          if title ~= "-" and not unnamed then parts[#parts + 1] = name end
          local q = (code ~= "QS") and db("GetQuest", id) or nil
          if code == "QA" or code == "QP" then
            local goal = add({ t = "accept", quest = id, title = name })
            if q then questEnd(goal, q.start, st.zone) end
          elseif code == "QT" then
            local goal = add({ t = "turnin", quest = id, title = name })
            if q then questEnd(goal, q.finish, st.zone) end
          elseif code == "QS" then
            -- Guidelime's "skip this quest": nothing to do in Polestar.
          elseif oi then
            local o = q and q.objectives and q.objectives[oi]
            local goal
            if o and o.kind == "kill" and o.id then
              local e = db("GetNpc", o.id)
              goal = add({ t = "kill", target = (e and e.name) or name, npc = e and e.name and o.id or nil, count = o.count })
              locate(goal, place(e, st.zone))
            elseif o and o.kind == "item" and o.id then
              goal = add({ t = "collect", item = o.id, itemName = itemName(o.id), count = o.count })
            elseif o and o.kind == "object" and o.id then
              local e = db("GetObject", o.id)
              if e and e.name then
                goal = add({ t = "interact", object = o.id, objName = e.name })
                locate(goal, place(e, st.zone))
              end
            end
            -- Anything else: read the goal by its quest log line.
            goal = goal or add({ t = "kill", target = name, logLine = true })
            goal.quest, goal.oi = id, oi
            if code == "QW" then goal.optional = true end
          else
            local goal = add({ t = "complete", quest = id, title = name })
            if code == "QW" then goal.optional = true end
          end
          -- No zone named yet: the quest's place gives one, as Guidelime takes the quest's zone.
          if not st.zone and last and last.map then st.zone = last.map end
        end
      elseif code == "G" then
        local p, radius = coords(tag)
        if p then
          p.t = "goto"
          if radius and radius > 0 then p.r = radius end
          add(p)
        end
      elseif code == "L" then
        loc = coords(tag) or loc
      elseif code == "XP" then
        local level, sign, amount, text = tag:match("^(%d+)%s*([%+%-%.]?)(%d*)%s*(.-)%s*$")
        level = num(level)
        if level then
          local goal = add({ t = "level", level = level })
          if sign == "." and amount ~= "" then
            local frac = tonumber("0." .. amount)
            if frac and frac > 0 and frac < 1 then goal.frac = frac end
          end
          if text ~= "" then goal.text = clean(text) end
          parts[#parts + 1] = text ~= "" and text or ("level " .. tag)
        else
          warn("bad XP code: " .. tag)
        end
      elseif code == "H" then
        if tag ~= "" then
          add({ t = "hearth", location = tag })
        else
          add({ t = "cast", spell = HEARTHSTONE, spellName = spellName(HEARTHSTONE) or "Hearthstone" })
        end
        parts[#parts + 1] = tag
      elseif code == "F" then
        add(tag ~= "" and { t = "fly", location = tag } or { t = "task", text = "Fly" })
        parts[#parts + 1] = tag
      elseif code == "P" then
        add(tag ~= "" and { t = "getfp", location = tag } or { t = "task", text = "Get the flight path" })
        parts[#parts + 1] = tag
      elseif code == "S" then
        add(tag ~= "" and { t = "sethome", location = tag } or { t = "task", text = "Set your hearthstone" })
        parts[#parts + 1] = tag
      elseif code == "T" then
        add({ t = "train", class = true })
        parts[#parts + 1] = tag
      elseif code == "V" or code == "R" then
        add({ t = "vendor", text = code == "R" and "Repair" or nil })
        parts[#parts + 1] = tag
      elseif code == "CI" then
        local id, count, title = tag:match("^(%d+)%s*,?%s*(%d*)%s*(.-)%s*$")
        id = num(id)
        if id then
          local n = itemName(id, title)
          add({ t = "collect", item = id, itemName = n, count = num(count) or 1 })
          if title ~= "-" then parts[#parts + 1] = n end
        end
      elseif code == "UI" then
        local id, _, title = tag:match("^(%d+)%s*,?%s*(%d*)%s*(.-)%s*$")
        id = num(id)
        if id then
          -- Guidelime's use-item button; in Polestar an optional goal with the item to click.
          add({ t = "use", item = id, itemName = itemName(id, title), optional = true })
        end
      elseif code == "TAR" then
        local id, title = tag:match("^(%d+)%s*(.-)%s*$")
        local e = num(id) and db("GetNpc", num(id))
        local n = given(title) or (e and e.name)
        if n then
          add({ t = "note", text = "Target: " .. n })
          parts[#parts + 1] = n
        end
      elseif code == "SP" then
        local id, _, title = tag:match("^(%d+)%s*,?%s*(%d*)%s*(.-)%s*$")
        id = num(id)
        local n = id and (given(title) or spellName(id))
        if n then
          add({ t = "cast", spell = id, spellName = n })
          parts[#parts + 1] = n
        else
          parts[#parts + 1] = tag
        end
      elseif code == "LE" then
        -- "SP 20271" or several: "SP 20271, SP 19740"
        local names = {}
        for id in tag:gmatch("[Ss][Pp]%s*(%d+)") do
          id = tonumber(id)
          local n = spellName(id)
          if n then
            add({ t = "learn", spell = id, spellName = n })
            names[#names + 1] = n
          end
        end
        parts[#parts + 1] = #names > 0 and table.concat(names, ", ") or tag
      elseif code == "SK" then
        local skill, value = tag:match("^([^%d]+)%s*(%d*)")
        local name = skill and SKILLS[skill:upper():gsub("%s", "")]
        if name then
          add({ t = "skill", skill = name, level = num(value) or 1 })
          parts[#parts + 1] = name .. (value ~= "" and (" " .. value) or "")
        end
      elseif code == "REP" then
        parts[#parts + 1] = tag
      elseif code == "LI" then
        local _, _, t = levelsAndTitle(tag)
        parts[#parts + 1] = t
      elseif code == "A" then
        local a = appliesTo(tag)
        only = only or {}
        local function put(key, list, prefix)
          for _, v in ipairs(list) do
            only[key] = only[key] or {}
            table.insert(only[key], prefix .. v)
          end
        end
        put("classes", a.classes, ""); put("classes", a.notClasses, "!")
        put("races", a.races, ""); put("races", a.notRaces, "!")
        put("factions", a.factions, "")
      elseif code == "O" then
        if tag ~= "" then parts[#parts + 1] = tag end
        if last then last.optional = true else optionalStep = true end
      elseif code == "OC" then
        optionalStep = true
        if tag ~= "" then parts[#parts + 1] = tag end
      elseif code == "C" then
        if tag ~= "" then parts[#parts + 1] = tag end
      end
      -- OR: Guidelime's "any one goal completes the step"; Polestar has no such step.
    end
  end

  if loc then
    for _, goal in ipairs(goals) do
      -- The author's spot wins over the database's for quest objectives (mobs spawn in many places).
      if LOCATABLE[goal.t] and (not goal.map or goal.oi) then
        goal.map, goal.x, goal.y, goal.f = loc.map, loc.x, loc.y, loc.f
      end
    end
  end

  local note = hasText and clean(table.concat(parts, "")) or nil
  if note == "" then note = nil end
  if #goals == 0 then
    if not note then return nil end
    -- A line of text only: Guidelime ticks it by hand, and so does Polestar.
    local goal = add({ t = "task", text = note })
    if loc then goal.map, goal.x, goal.y, goal.f = loc.map, loc.x, loc.y, loc.f end
    note = nil
  end
  if optionalStep then
    for _, goal in ipairs(goals) do goal.optional = true end
  end
  if only then
    for key, list in pairs(only) do
      if #list == 0 then only[key] = nil end
    end
    if next(only) == nil then only = nil end
  end
  return { note = note, only = only, goals = goals }
end

-- parsed: C.Parse's result; group: the guide's group (Guidelime's guide list heading).
-- -> def, warnings | nil, err
function C.Build(parsed, group)
  if not parsed.title or parsed.title == "" then return nil, "the guide has no [N ...] name" end
  local warnings = {}
  local function warn(msg) warnings[#warnings + 1] = msg end
  for _, raw in ipairs(parsed.unknown) do warn("unknown code [" .. raw .. "]") end

  local name = C.GuideName(parsed.minLevel, parsed.maxLevel, parsed.title)
  local def = {
    id = C.GuideId(group, name),
    pack = C.PACK,
    title = clean(parsed.title),
    minLevel = parsed.minLevel,
    maxLevel = parsed.maxLevel,
    category = "Leveling",
    folder = group,
    author = group,
    steps = {},
  }

  local a = parsed.applies
  if a then
    if #a.factions > 0 then def.faction = a.factions[1] end
    if #a.classes > 0 then
      def.classes = a.classes
    elseif #a.notClasses > 0 then
      local skip = {}
      for _, c in ipairs(a.notClasses) do skip[c] = true end
      def.classes = {}
      for _, c in ipairs(CLASS_LIST) do
        if not skip[c] then def.classes[#def.classes + 1] = c end
      end
    end
    if #a.races > 0 then
      def.races = a.races
    elseif #a.notRaces > 0 then
      local skip = {}
      for _, r in ipairs(a.notRaces) do skip[r] = true end
      def.races = {}
      for _, r in ipairs(def.faction and FACTION_RACES[def.faction] or { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll" }) do
        if not skip[r] then def.races[#def.races + 1] = r end
      end
    end
    -- A guide for races of one side is that side's.
    if not def.faction and def.races and #def.races > 0 then
      local side = RACE_FACTION[def.races[1]]
      for _, r in ipairs(def.races) do
        if RACE_FACTION[r] ~= side then side = nil end
      end
      def.faction = side
    end
  end

  if parsed.details then
    local d = clean(parsed.details)
    if d ~= "" then def.pitch = #d > 240 and (d:sub(1, 237) .. "...") or d end
  end

  if #parsed.next > 0 then
    -- Every NX the player fits is offered; guides that are not there are left out by Polestar.
    def.nextChoices = {}
    for _, n in ipairs(parsed.next) do
      def.nextChoices[#def.nextChoices + 1] = C.GuideId(group, n)
    end
  end

  local st = { titles = {} }
  for i, elements in ipairs(parsed.lines) do
    local step = buildStep(elements, st, function(msg) warn(("line %d: %s"):format(i, msg)) end)
    if step then def.steps[#def.steps + 1] = step end
  end
  if #def.steps == 0 then return nil, "the guide has no steps" end
  return def, warnings
end

-- text, group -> def, warnings | nil, err
function C.Convert(text, group)
  if type(text) ~= "string" then return nil, "the guide is not text" end
  local ok, parsed = pcall(C.Parse, text)
  if not ok then return nil, "could not read the guide: " .. tostring(parsed) end
  local ok2, def, warnings = pcall(C.Build, parsed, group)
  if not ok2 then return nil, "could not convert the guide: " .. tostring(def) end
  return def, warnings
end
