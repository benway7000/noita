-- Blueprints persist across runs in a single mod setting
-- Format: "WBP1" header, then blueprints separated by ";": name|icon|note|hotkey|slot,slot,...|category
-- (category was added later, blueprints without it load as "other")
-- An empty slot is an empty string between commas. Free text is percent-escaped.

local M = {}

local setting_key = "WandBlueprints.data"
local header = "WBP1"
local max_hotkey = 10

-- icon_action is the spell whose sprite represents the category on its tab
M.CATEGORIES = {
  { id = "combat", name = "Combat", icon_action = "LIGHT_BULLET" },
  { id = "digging", name = "Digging", icon_action = "DIGGER" },
  { id = "travel", name = "Travel", icon_action = "TELEPORT_PROJECTILE" },
  { id = "healing", name = "Healing", icon_action = "HEAL_BULLET" },
  { id = "other", name = "Other" },
}
M.DEFAULT_CATEGORY = "other"
local category_by_id = {}
for i, category in ipairs(M.CATEGORIES) do
  category_by_id[category.id] = category
end

function M.get_category(id)
  return category_by_id[id] or category_by_id[M.DEFAULT_CATEGORY]
end

local function escape(s)
  return (tostring(s or ""):gsub("[%%|,;\n\r]", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

local function unescape(s)
  return (s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function split(input, sep)
  local result = {}
  for v in string.gmatch(input .. sep, "([^" .. sep .. "]*)" .. sep) do
    table.insert(result, v)
  end
  return result
end

-- A blueprint: { name = string, icon = action_id or "", note = string, hotkey = 0..10 (0 = none), slots = { action_id or "" },
--   category = one of the CATEGORIES ids }
function M.new_blueprint(name, slots, category)
  local icon = ""
  for i, action_id in ipairs(slots or {}) do
    if action_id ~= "" then
      icon = action_id
      break
    end
  end
  return { name = name or "", icon = icon, note = "", hotkey = 0, slots = slots or {}, category = category_by_id[category] and category or M.DEFAULT_CATEGORY }
end

function M.copy(bp)
  local slots = {}
  for i, v in ipairs(bp.slots) do slots[i] = v end
  return { name = bp.name, icon = bp.icon, note = bp.note, hotkey = bp.hotkey, slots = slots, category = bp.category }
end

function M.load()
  local blueprints = {}
  local data = ModSettingGet(setting_key)
  if type(data) ~= "string" or data == "" then
    return blueprints
  end
  local lines = split(data, ";")
  if lines[1] ~= header then
    print("[WandBlueprints] Unknown data format, ignoring stored blueprints")
    return blueprints
  end
  for i = 2, #lines do
    local line = lines[i]
    if line ~= "" then
      local fields = split(line, "|")
      local slots = {}
      if fields[5] and fields[5] ~= "" then
        for j, action_id in ipairs(split(fields[5], ",")) do
          slots[j] = unescape(action_id)
        end
      end
      local hotkey = tonumber(fields[4]) or 0
      if hotkey < 0 or hotkey > max_hotkey then hotkey = 0 end
      table.insert(blueprints, {
        name = unescape(fields[1] or ""),
        icon = unescape(fields[2] or ""),
        note = unescape(fields[3] or ""),
        hotkey = hotkey,
        category = category_by_id[unescape(fields[6] or "")] and unescape(fields[6]) or M.DEFAULT_CATEGORY,
        slots = slots,
      })
    end
  end
  return blueprints
end

function M.save(blueprints)
  local out = { header }
  for i, bp in ipairs(blueprints) do
    local slots = {}
    for j, action_id in ipairs(bp.slots) do
      slots[j] = escape(action_id)
    end
    table.insert(out, table.concat({
      escape(bp.name), escape(bp.icon), escape(bp.note), tostring(bp.hotkey or 0), table.concat(slots, ","),
      escape(bp.category or M.DEFAULT_CATEGORY)
    }, "|"))
  end
  ModSettingSet(setting_key, table.concat(out, ";"))
end

return M
