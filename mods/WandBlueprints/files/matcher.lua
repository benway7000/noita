-- Finds which of the player's 4 wands match a blueprint, and (optionally) names matching wands after their blueprint.
-- Wands are checked every CHECK_INTERVAL frames, so spells changed any way at all (Holy Mountain, other mods) are
-- picked up, and right away after the blueprints or a wand changed through this mod (see M.mark_dirty).

local M = {}

local EZWand
local apply

local CHECK_INTERVAL = 30
local NUM_WAND_SLOTS = 4
-- Kept on a renamed wand: its name from before, so it can be put back once the wand stops matching
local ORIGINAL_NAME = "WandBlueprints_original_name"

-- [1..4] = { entity_id, slots = trimmed slot list, capacity, sprite (png or nil), bp = matching blueprint or nil }
M.wands = {}
-- [blueprint table] = { wand slot numbers (1..4) that match it }
M.by_blueprint = {}

local last_check_frame = -1000
local dirty = true
local sprite_cache = {}

function M.init(ezwand, apply_module)
  EZWand = ezwand
  apply = apply_module
end

function M.mark_dirty()
  dirty = true
end

local function trimmed(slots)
  local out = {}
  for i, action_id in ipairs(slots) do out[i] = action_id end
  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end
  return out
end

local function key(slots)
  return table.concat(slots, ",")
end

-- A wand matches a blueprint if it holds exactly the blueprint's spells, or exactly what applying it to a wand of
-- this capacity produces (empty slots dropped to fit). Blueprints without spells never match.
local function matches(bp, wand_key, capacity)
  local slots = trimmed(bp.slots)
  if #slots == 0 then return false end
  return key(slots) == wand_key or key(trimmed(apply.fit_slots(bp.slots, capacity))) == wand_key
end

-- Wand sprites are a png or a sprite xml, GuiImage needs the png. Returns nil if there isn't one.
local function sprite_png(file)
  if file == nil or file == "" then return nil end
  if file:match("%.png$") then return file end
  if sprite_cache[file] == nil then
    local ok, content = pcall(ModTextFileGetContent, file)
    sprite_cache[file] = ok and content and content:match('filename%s*=%s*"([^"]+%.png)"') or false
  end
  return sprite_cache[file] or nil
end

local function get_player_wands(player)
  local wands = {}
  for i, child in ipairs(EntityGetAllChildren(player) or {}) do
    if EntityGetName(child) == "inventory_quick" then
      for j, item in ipairs(EntityGetAllChildren(child) or {}) do
        if EZWand.IsWand(item) then
          local item_comp = EntityGetFirstComponentIncludingDisabled(item, "ItemComponent")
          local slot = item_comp and ComponentGetValue2(item_comp, "inventory_slot")
          if slot and slot >= 0 and slot < NUM_WAND_SLOTS then
            wands[slot + 1] = item
          end
        end
      end
    end
  end
  return wands
end

local function get_original_name_storage(wand_id)
  for i, comp in ipairs(EntityGetComponentIncludingDisabled(wand_id, "VariableStorageComponent") or {}) do
    if ComponentGetValue2(comp, "name") == ORIGINAL_NAME then
      return comp
    end
  end
end

local function set_name(wand_id, name)
  local item_comp = EntityGetFirstComponentIncludingDisabled(wand_id, "ItemComponent")
  if not item_comp then return end
  if not get_original_name_storage(wand_id) then
    EntityAddComponent2(wand_id, "VariableStorageComponent", {
      name = ORIGINAL_NAME,
      value_string = ComponentGetValue2(item_comp, "item_name"),
      value_int = ComponentGetValue2(item_comp, "always_use_item_name_in_ui") and 1 or 0,
    })
  end
  if ComponentGetValue2(item_comp, "item_name") ~= name then
    ComponentSetValue2(item_comp, "item_name", name)
  end
  ComponentSetValue2(item_comp, "always_use_item_name_in_ui", true)
end

local function restore_name(wand_id)
  local storage = get_original_name_storage(wand_id)
  if not storage then return end
  local item_comp = EntityGetFirstComponentIncludingDisabled(wand_id, "ItemComponent")
  if item_comp then
    ComponentSetValue2(item_comp, "item_name", ComponentGetValue2(storage, "value_string"))
    ComponentSetValue2(item_comp, "always_use_item_name_in_ui", ComponentGetValue2(storage, "value_int") == 1)
  end
  EntityRemoveComponent(wand_id, storage)
end

-- Call every frame, only does work every CHECK_INTERVAL frames or when marked dirty
function M.update(player, blueprints, rename_wands)
  local frame = GameGetFrameNum()
  if not dirty and frame - last_check_frame < CHECK_INTERVAL then return end
  dirty = false
  last_check_frame = frame

  M.wands = {}
  M.by_blueprint = {}
  for slot, wand_id in pairs(get_player_wands(player)) do
    local wand = EZWand(wand_id)
    local slots = apply.capture_from_wand(wand_id)
    local wand_key = key(slots)
    local info = { entity_id = wand_id, slots = slots, capacity = wand.capacity, sprite = sprite_png(wand:GetSprite()) }
    for i, bp in ipairs(blueprints) do
      if matches(bp, wand_key, wand.capacity) then
        -- The first match names the wand, the list shows the wand next to every match
        info.bp = info.bp or bp
        M.by_blueprint[bp] = M.by_blueprint[bp] or {}
        table.insert(M.by_blueprint[bp], slot)
      end
    end
    if rename_wands and info.bp then
      set_name(wand_id, info.bp.name)
    else
      restore_name(wand_id)
    end
    M.wands[slot] = info
  end
end

return M
