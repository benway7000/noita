-- Capturing spells from a wand into a blueprint, and applying a blueprint onto a wand

local M = {}

local EZWand
local action_lookup = {}

function M.init(ezwand, lookup)
  EZWand = ezwand
  action_lookup = lookup
end

local function get_player()
  return EntityGetWithTag("player_unit")[1]
end

function M.spell_name(action_id)
  local action = action_lookup[action_id]
  if action and action.name then
    return GameTextGetTranslatedOrNot(action.name)
  end
  return action_id
end

function M.get_held_wand()
  local player = get_player()
  if not player then return nil end
  local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
  if not inventory_2_comp then return nil end
  local active_item = ComponentGetValue2(inventory_2_comp, "mActiveItem")
  if active_item and active_item ~= 0 and EZWand.IsWand(active_item) then
    return active_item
  end
end

-- Same check as Advanced Spell Inventory: inside a workshop (Holy Mountain) or has the tinker everywhere perk
function M.can_edit_wands()
  local player = get_player()
  if not player then return false end
  local px, py = EntityGetTransform(player)
  for i, entity_id in ipairs(EntityGetWithTag("workshop")) do
    local hitbox_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "HitboxComponent")
    if hitbox_comp then
      local x, y = EntityGetTransform(entity_id)
      local aabb_min_x = ComponentGetValue2(hitbox_comp, "aabb_min_x")
      local aabb_min_y = ComponentGetValue2(hitbox_comp, "aabb_min_y")
      local aabb_max_x = ComponentGetValue2(hitbox_comp, "aabb_max_x")
      local aabb_max_y = ComponentGetValue2(hitbox_comp, "aabb_max_y")
      if px > (x + aabb_min_x) and px < (x + aabb_max_x) and py > (y + aabb_min_y) and py < (y + aabb_max_y) then
        return true
      end
    end
  end
  return GameGetGameEffectCount(player, "EDIT_WANDS_EVERYWHERE") > 0
end

-- Returns the wand's (non always cast) spells as a slot list, trailing empty slots trimmed
function M.capture_from_wand(wand_id)
  local wand = EZWand(wand_id)
  local slots = {}
  local capacity = wand.capacity
  for i = 1, capacity do
    slots[i] = ""
  end
  for i, spell in ipairs(wand:GetSpells()) do
    local index = spell.inventory_x + 1
    if index >= 1 then
      slots[index] = spell.action_id
    end
  end
  while #slots > 0 and slots[#slots] == "" do
    table.remove(slots)
  end
  return slots
end

local function get_spell_inventory()
  local player = get_player()
  if player then
    for i, child in ipairs(EntityGetAllChildren(player) or {}) do
      if EntityGetName(child) == "inventory_full" then
        return child
      end
    end
  end
end

local function get_action_id(entity_id)
  local item_action_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemActionComponent")
  if item_action_comp then
    return ComponentGetValue2(item_action_comp, "action_id")
  end
end

local function get_uses_remaining(entity_id)
  local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
  if item_comp then
    return ComponentGetValue2(item_comp, "uses_remaining")
  end
  return -1
end

local function set_inventory_slot(entity_id, x, y)
  local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
  if item_comp then
    ComponentSetValue2(item_comp, "inventory_slot", x, y)
  end
end

-- Spells with the most uses left are taken first (-1 = unlimited), the ones with 0 last
local function uses_score(uses)
  return uses < 0 and math.huge or uses
end

-- Returns spell entities in the regular spell inventory grouped by action_id
local function get_inventory_spells()
  local result = {}
  local spell_inventory = get_spell_inventory()
  for i, entity_id in ipairs(spell_inventory and EntityGetAllChildren(spell_inventory) or {}) do
    local action_id = get_action_id(entity_id)
    if action_id then
      result[action_id] = result[action_id] or {}
      table.insert(result[action_id], { entity_id = entity_id, uses = get_uses_remaining(entity_id) })
    end
  end
  for action_id, list in pairs(result) do
    table.sort(list, function(a, b) return uses_score(a.uses) > uses_score(b.uses) end)
  end
  return result
end

-- Advanced Spell Inventory runs in its own Lua state, it's talked to through Globals (see its process_api_request).
-- It writes a heartbeat every frame while its storage is usable.
local ASI_REQUEST_KEY = "AdvancedSpellInventory_api_request"
local ASI_RESPONSE_KEY = "AdvancedSpellInventory_api_response"
local ASI_HEARTBEAT_KEY = "AdvancedSpellInventory_api_heartbeat"
local ASI_TIMEOUT_FRAMES = 60

function M.is_asi_available()
  if not ModIsEnabled("AdvancedSpellInventory") then
    return false
  end
  local heartbeat = tonumber(GlobalsGetValue(ASI_HEARTBEAT_KEY, "")) or -1000
  return GameGetFrameNum() - heartbeat <= 10
end

-- Puts a spell that came off the wand into the spell inventory, or the floor if that's full
local function stash_spell_locally(entity_id)
  local player = get_player()
  local spell_inventory = get_spell_inventory()
  local inventory_2_comp = player and EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
  if spell_inventory and inventory_2_comp then
    local size_x = ComponentGetValue2(inventory_2_comp, "full_inventory_slots_x")
    local size_y = ComponentGetValue2(inventory_2_comp, "full_inventory_slots_y")
    local occupied = {}
    for i, child in ipairs(EntityGetAllChildren(spell_inventory) or {}) do
      local item_comp = EntityGetFirstComponentIncludingDisabled(child, "ItemComponent")
      if item_comp then
        local x, y = ComponentGetValue2(item_comp, "inventory_slot")
        occupied[y * size_x + x] = true
      end
    end
    for y = 0, size_y - 1 do
      for x = 0, size_x - 1 do
        if not occupied[y * size_x + x] then
          EntityRemoveFromParent(entity_id)
          EntityAddChild(spell_inventory, entity_id)
          set_inventory_slot(entity_id, x, y)
          return
        end
      end
    end
  end
  -- No room anywhere, drop it at the player's feet
  EntityRemoveFromParent(entity_id)
  if player then
    local px, py = EntityGetTransform(player)
    EntityApplyTransform(entity_id, px, py)
  end
  EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_world", true)
  EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_inventory", false)
  EntitySetComponentsWithTagEnabled(entity_id, "item_unidentified", false)
end

local function refresh_inventory()
  local player = get_player()
  local inventory_2_comp = player and EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
  if inventory_2_comp then
    ComponentSetValue2(inventory_2_comp, "mForceRefresh", true)
    ComponentSetValue2(inventory_2_comp, "mActualActiveItem", 0)
  end
end

-- If the blueprint has more slots than the wand, removes empty slots until it fits (or there are none left),
-- rightmost first
function M.fit_slots(slots, capacity)
  local fitted = {}
  for i, action_id in ipairs(slots) do fitted[i] = action_id end
  local i = #fitted
  while #fitted > capacity and i >= 1 do
    if fitted[i] == "" then
      table.remove(fitted, i)
    end
    i = i - 1
  end
  return fitted
end

-- Applies the blueprint onto the wand, as far as it can be done right away. Returns a result:
-- {
--   missing = { { slot, action_id } },  -- not found anywhere
--   overflow = { action_id },          -- blueprint slots beyond the wand's capacity
--   stores = { entity_id },            -- spells that came off the wand, still waiting to go into ASI
--   takes = { { slot, action_id } },   -- spells still to be taken from ASI
-- }
-- If stores or takes aren't empty, pass the result to M.send_asi_request and later M.finish (or M.fallback).
-- Spells on the wand that the blueprint doesn't use come off it, so the wand ends up holding just the blueprint.
function M.apply(bp, wand_id)
  local wand = EZWand(wand_id)
  local capacity = wand.capacity
  local use_asi = M.is_asi_available()
  local result = { missing = {}, overflow = {}, stores = {}, takes = {}, wand_id = wand_id }

  -- What should end up in which slot (0-based position -> action_id)
  local wanted = {}
  for i, action_id in ipairs(M.fit_slots(bp.slots, capacity)) do
    if action_id ~= "" then
      if i > capacity then
        table.insert(result.overflow, action_id)
      else
        wanted[i - 1] = action_id
      end
    end
  end

  local pool = wand:GetSpells()
  local used = {}
  local filled = {}
  -- Pass 1: spells already in the right place stay there
  for i, spell in ipairs(pool) do
    if wanted[spell.inventory_x] == spell.action_id and not filled[spell.inventory_x] then
      used[i] = true
      filled[spell.inventory_x] = spell.entity_id
    end
  end
  -- Pass 2: reuse the wand's other spells by moving them to the right slot (keeps their charges)
  for pos = 0, capacity - 1 do
    local action_id = wanted[pos]
    if action_id and not filled[pos] then
      for i, spell in ipairs(pool) do
        if not used[i] and spell.action_id == action_id then
          used[i] = true
          filled[pos] = spell.entity_id
          break
        end
      end
    end
  end
  -- Everything else comes off the wand. Spells for ASI stay on the wand until ASI takes them,
  -- parked on slots past the end so they don't collide with the new layout.
  local parked = 0
  for i, spell in ipairs(pool) do
    if not used[i] then
      if use_asi then
        table.insert(result.stores, spell.entity_id)
        set_inventory_slot(spell.entity_id, capacity + 100 + parked, 0)
        parked = parked + 1
      else
        stash_spell_locally(spell.entity_id)
      end
    end
  end
  -- Always write the slot, freshly spawned wands have all spells at 0 until the inventory is opened
  for pos, entity_id in pairs(filled) do
    set_inventory_slot(entity_id, pos, 0)
  end
  -- Pass 3: fill the rest from the spell inventory, what's not there is asked from Advanced Spell Inventory
  local inventory_spells = get_inventory_spells()
  for pos = 0, capacity - 1 do
    local action_id = wanted[pos]
    if action_id and not filled[pos] then
      local candidates = inventory_spells[action_id]
      if candidates and #candidates > 0 then
        local entity_id = table.remove(candidates, 1).entity_id
        EntityRemoveFromParent(entity_id)
        EntityAddChild(wand_id, entity_id)
        set_inventory_slot(entity_id, pos, 0)
        filled[pos] = entity_id
      elseif use_asi then
        table.insert(result.takes, { pos, action_id })
      else
        table.insert(result.missing, { pos, action_id })
      end
    end
  end

  if #result.stores == 0 and #result.takes == 0 then
    refresh_inventory()
  end
  return result
end

function M.needs_asi(result)
  return #result.stores > 0 or #result.takes > 0
end

-- Sends the ASI part of an apply, returns the request id
function M.send_asi_request(result)
  local id = tostring(GameGetFrameNum()) .. "_" .. tostring(math.random(100000, 999999))
  local takes = {}
  for i, take in ipairs(result.takes) do
    takes[i] = take[1] .. ":" .. take[2]
  end
  GlobalsSetValue(ASI_RESPONSE_KEY, "")
  GlobalsSetValue(ASI_REQUEST_KEY, table.concat({ id, tostring(result.wand_id), table.concat(result.stores, ","), table.concat(takes, ",") }, "|"))
  result.request_id = id
  result.request_frame = GameGetFrameNum()
  return id
end

-- Checks for ASI's response. Returns true once the result is complete (missing then includes what ASI didn't have).
-- Returns false while still waiting, and nil if ASI didn't answer in time (use M.fallback then).
function M.poll_asi_response(result)
  local response = GlobalsGetValue(ASI_RESPONSE_KEY, "")
  local id, failed = response:match("^([^|]*)|(.*)$")
  if id == result.request_id then
    GlobalsSetValue(ASI_RESPONSE_KEY, "")
    for take in failed:gmatch("[^,]+") do
      local slot, action_id = take:match("^(%d+):(.+)$")
      if slot then
        table.insert(result.missing, { tonumber(slot), action_id })
      end
    end
    return true
  end
  if GameGetFrameNum() - result.request_frame > ASI_TIMEOUT_FRAMES then
    return nil
  end
  return false
end

-- ASI didn't answer: withdraw the request, put the spells meant for ASI into the spell inventory instead
function M.fallback(result)
  GlobalsSetValue(ASI_REQUEST_KEY, "")
  for i, entity_id in ipairs(result.stores) do
    if EntityGetIsAlive(entity_id) then
      stash_spell_locally(entity_id)
    end
  end
  for i, take in ipairs(result.takes) do
    table.insert(result.missing, take)
  end
  refresh_inventory()
end

-- Missing spells in slot order, as action_ids
function M.missing_action_ids(result)
  table.sort(result.missing, function(a, b) return a[1] < b[1] end)
  local ids = {}
  for i, entry in ipairs(result.missing) do
    ids[i] = entry[2]
  end
  return ids
end

-- "Spark Bolt x2" style lines, in order of first appearance
function M.group_names(action_ids)
  local order, counts = {}, {}
  for i, action_id in ipairs(action_ids) do
    if not counts[action_id] then
      table.insert(order, action_id)
      counts[action_id] = 0
    end
    counts[action_id] = counts[action_id] + 1
  end
  local lines = {}
  for i, action_id in ipairs(order) do
    local name = M.spell_name(action_id)
    table.insert(lines, counts[action_id] > 1 and (name .. " x" .. counts[action_id]) or name)
  end
  return lines
end

return M
