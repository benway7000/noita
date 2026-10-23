dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/debug/keycodes.lua")
dofile_once("data/scripts/lib/coroutines.lua")
dofile_once("data/scripts/gun/gun_enums.lua")
dofile_once("data/scripts/debug/keycodes.lua")
dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/init.lua")("mods/AdvancedSpellInventory/lib/EZInventory/")

ModRegisterAudioEventMappings("mods/AdvancedSpellInventory/audio/GUIDs.txt")

local EZWand
local EZInventory = dofile_once("mods/AdvancedSpellInventory/lib/EZInventory/EZInventory.lua")
local EZMouse = dofile("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/EZMouse.lua")("mods/AdvancedSpellInventory/lib/EZInventory/lib/EZMouse/")

local action_lookup = {
  -- For "bugged" spells
  [""] = {
		sprite = "data/ui_gfx/gun_actions/unidentified.png"
  }
}
local spell_types = {
  { name = "Everything", icon = "mods/AdvancedSpellInventory/files/spell_type_all.png" },
  { type = ACTION_TYPE_PROJECTILE, name = GameTextGetTranslatedOrNot("$inventory_actiontype_projectile"), icon = "data/ui_gfx/inventory/item_bg_projectile.png" },
  { type = ACTION_TYPE_STATIC_PROJECTILE, name = GameTextGetTranslatedOrNot("$inventory_actiontype_staticprojectile"), icon = "data/ui_gfx/inventory/item_bg_static_projectile.png" },
  { type = ACTION_TYPE_MODIFIER, name = GameTextGetTranslatedOrNot("$inventory_actiontype_modifier"), icon = "data/ui_gfx/inventory/item_bg_modifier.png" },
  { type = ACTION_TYPE_DRAW_MANY, name = GameTextGetTranslatedOrNot("$inventory_actiontype_drawmany"), icon = "data/ui_gfx/inventory/item_bg_draw_many.png" },
  { type = ACTION_TYPE_MATERIAL, name = GameTextGetTranslatedOrNot("$inventory_actiontype_material"), icon = "data/ui_gfx/inventory/item_bg_material.png" },
  { type = ACTION_TYPE_OTHER, name = GameTextGetTranslatedOrNot("$inventory_actiontype_other"), icon = "data/ui_gfx/inventory/item_bg_other.png" },
  { type = ACTION_TYPE_UTILITY, name = GameTextGetTranslatedOrNot("$inventory_actiontype_utility"), icon = "data/ui_gfx/inventory/item_bg_utility.png" },
  { type = ACTION_TYPE_PASSIVE, name = GameTextGetTranslatedOrNot("$inventory_actiontype_passive"), icon = "data/ui_gfx/inventory/item_bg_passive.png" },
}

local function is_keybind_down() return false end
local function is_dump_keybind_down() return false end
if ModIsEnabled("mnee") then
	ModLuaFileAppend("mods/mnee/bindings.lua", "mods/AdvancedSpellInventory/files/mnee.lua")
end

local function is_wand(entity)
	local ability_component = EntityGetFirstComponentIncludingDisabled(entity, "AbilityComponent")
	if not ability_component then
		return false
	end
	return ComponentGetValue2(ability_component, "use_gun_script") == true
end

local function can_edit_wands(player)
  if player then
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
    if GameGetGameEffectCount(player, "EDIT_WANDS_EVERYWHERE") > 0 then
      return true
    end
  end
  return false
end

-- Add script to spell refresh
do
  local file_path = "data/entities/particles/image_emitters/spell_refresh_effect.xml"
  local content = ModTextFileGetContent(file_path)
  ModTextFileSetContent(file_path, content:gsub([[</Entity>]], [[
    <LuaComponent
      script_source_file="mods/AdvancedSpellInventory/files/spell_refresh_add.lua"
      execute_every_n_frame="-1"
      execute_on_added="1"
      remove_after_executed="1"
    ></LuaComponent>
</Entity>
  ]]))
end

local show_button = ModSettingGet("AdvancedSpellInventory.show_button")
local sounds_enabled = ModSettingGet("AdvancedSpellInventory.sounds_enabled")
local enable_funny_dump_sound = ModSettingGet("AdvancedSpellInventory.enable_funny_dump_sound")
local dump_button_image = enable_funny_dump_sound and "dump_button.png" or "dump_button2.png"
local spell_dump_needs_wand_tinkering = ModSettingGet("AdvancedSpellInventory.spell_dump_needs_wand_tinkering")
EZInventory.SetSoundsEnabled(sounds_enabled)
local function play_ui_sound(name)
  if not sounds_enabled then
    return
  end
  local cx, cy = GameGetCameraPos()
  GamePlaySound("data/audio/Desktop/ui.bank", "ui/" .. name, cx, cy)
end

-- Reads a value like fire_rate_wait from the same metadata the spell tooltip uses (global function defined by EZWand)
local function get_action_stat(action_id, stat)
  local metadata = get_action_metadata(action_id)
  return metadata and metadata.c[stat] or 0
end

local sorting_functions
sorting_functions = {
  cast_delay = function(a, b)
    local delay_a = get_action_stat(a.spell.action_id, "fire_rate_wait")
    local delay_b = get_action_stat(b.spell.action_id, "fire_rate_wait")
    if delay_a < delay_b then return true end
    if delay_a > delay_b then return false end
    return sorting_functions.alphabetical(a, b)
  end,
  recharge_time = function(a, b)
    local recharge_a = get_action_stat(a.spell.action_id, "reload_time")
    local recharge_b = get_action_stat(b.spell.action_id, "reload_time")
    if recharge_a < recharge_b then return true end
    if recharge_a > recharge_b then return false end
    return sorting_functions.alphabetical(a, b)
  end,
  alphabetical = function(a, b)
    local name_a = GameTextGetTranslatedOrNot(action_lookup[a.spell.action_id].name)
    local name_b = GameTextGetTranslatedOrNot(action_lookup[b.spell.action_id].name)
    return name_a < name_b
  end,
  uses_remaining = function(a, b)
    -- First sort by uses remaining, and if they're equal alphabetically
    if a.spell.uses_remaining < b.spell.uses_remaining then return true end
    if a.spell.uses_remaining > b.spell.uses_remaining then return false end
    return sorting_functions.alphabetical(a, b)
  end,
  amount = function(a, b)
    -- First sort by amount, and if they're equal alphabetically
    if a.stack_size < b.stack_size then return true end
    if a.stack_size > b.stack_size then return false end
    return sorting_functions.alphabetical(a, b)
  end,
  type = function(a, b)
    -- First sort by uses remaining, and if they're equal alphabetically
    local type_a = action_lookup[a.spell.action_id].type
    local type_b = action_lookup[b.spell.action_id].type
    if type_a < type_b then return true end
    if type_a > type_b then return false end
    return sorting_functions.alphabetical(a, b)
  end,
}

local button_pos_x = tonumber(ModSettingGet("AdvancedSpellInventory.button_pos_x")) or 162
local button_pos_y = tonumber(ModSettingGet("AdvancedSpellInventory.button_pos_y")) or 41
local open = false
local origin_x, origin_y =
  tonumber(MagicNumbersGetValue("UI_FULL_INVENTORY_OFFSET_X"))
  + tonumber(MagicNumbersGetValue("UI_BARS_POS_X")),
  tonumber(MagicNumbersGetValue("UI_BARS_POS_Y")) --170, 48
local full_inventory_slots_x, full_inventory_slots_y
local filter_panel_height
local slot_width, slot_height
local search_filter = ""
local filter_by_type
local num_rows = ModSettingGet("AdvancedSpellInventory.num_rows")
local auto_storage = ModSettingGet("AdvancedSpellInventory.auto_storage")
local enable_spell_refresh_in_storage = ModSettingGet("AdvancedSpellInventory.enable_spell_refresh_in_storage")
local opening_inv_closes_spell_inv = ModSettingGet("AdvancedSpellInventory.opening_inv_closes_spell_inv")
local num_blocklist_entries = ModSettingGet("AdvancedSpellInventory.num_blocklist_entries")
local blocklist_entries = {}
local function update_blocklist()
  blocklist_entries = {}
  for i=1, num_blocklist_entries do
    local name = ModSettingGet("AdvancedSpellInventory.blocklist_entries." .. i)
    -- It should always exist, but just to shut up the IDE warnings...
    if name then
      local exact_match = ModSettingGet("AdvancedSpellInventory.blocklist_entries." .. i .. ".exact_match")
      table.insert(blocklist_entries, {
        name = name,
        exact_match = exact_match
      })
    end
  end
end
update_blocklist()

local function can_spell_be_stored(action_id)
  local name = GameTextGetTranslatedOrNot(action_lookup[action_id].name)
  for i, entry in ipairs(blocklist_entries) do
    if entry.exact_match then
      if entry.name == name then
        return false
      end
    else
      if name:lower():match(entry.name:lower()) then
        return false
      end
    end
  end
  return true
end

function OnPausedChanged(is_paused, is_main_menu)
  if not is_paused then
    button_pos_x = tonumber(ModSettingGet("AdvancedSpellInventory.button_pos_x")) or 162
    button_pos_y = tonumber(ModSettingGet("AdvancedSpellInventory.button_pos_y")) or 41
    show_button = ModSettingGet("AdvancedSpellInventory.show_button")
    sounds_enabled = ModSettingGet("AdvancedSpellInventory.sounds_enabled")
    enable_funny_dump_sound = ModSettingGet("AdvancedSpellInventory.enable_funny_dump_sound")
    dump_button_image = enable_funny_dump_sound and "dump_button.png" or "dump_button2.png"
    enable_spell_refresh_in_storage = ModSettingGet("AdvancedSpellInventory.enable_spell_refresh_in_storage")
    opening_inv_closes_spell_inv = ModSettingGet("AdvancedSpellInventory.opening_inv_closes_spell_inv")
    update_blocklist()
    spell_dump_needs_wand_tinkering = ModSettingGet("AdvancedSpellInventory.spell_dump_needs_wand_tinkering")
    EZInventory.SetSoundsEnabled(sounds_enabled)
    EZInventory.UpdateCustomScreenResolution()
  end
end

local function get_spell_inventory()
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    for i, child in ipairs(EntityGetAllChildren(player) or {}) do
      if EntityGetName(child) == "inventory_full" then
        return child
      end
    end
  end
end

local function is_inventory_open()
	local player = EntityGetWithTag("player_unit")[1]
	if player then
		local inventory_gui_component = EntityGetFirstComponentIncludingDisabled(player, "InventoryGuiComponent")
		if inventory_gui_component then
			return ComponentGetValue2(inventory_gui_component, "mActive")
		end
	end
end

local function get_spells_in_inventory()
  local spells = {}
  local spell_inventory = get_spell_inventory()
  if spell_inventory then
    for i, spell in ipairs(EntityGetAllChildren(spell_inventory) or {}) do
      local action_id
      local item_action_comp = EntityGetFirstComponentIncludingDisabled(spell, "ItemActionComponent")
      if item_action_comp then
        action_id = ComponentGetValue2(item_action_comp, "action_id")
      end
      local inv_x, inv_y, ui_sprite, uses_remaining
      local item_comp = EntityGetFirstComponentIncludingDisabled(spell, "ItemComponent")
      if item_comp then
        inv_x, inv_y = ComponentGetValue2(item_comp, "inventory_slot")
        uses_remaining = ComponentGetValue2(item_comp, "uses_remaining")
        ui_sprite = action_lookup[action_id] and action_lookup[action_id].sprite or ComponentGetValue2(item_comp, "ui_sprite")
      end
      table.insert(spells, {
        entity_id = spell,
        item_comp = item_comp,
        action_id = action_id,
        inv_x = inv_x,
        inv_y = inv_y,
        ui_sprite = ui_sprite,
        uses_remaining = uses_remaining,
      })
    end
    return spells
  else
    return nil
  end
end

local function get_inventory_size()
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
    if inventory_2_comp then
      return
        ComponentGetValue2(inventory_2_comp, "full_inventory_slots_x"),
        ComponentGetValue2(inventory_2_comp, "full_inventory_slots_y")
    end
  end
end

local spell_tooltip_size_cache = setmetatable({}, { __mode = "k" })
local function calculate_spell_tooltip_size(gui, x, y, z, content)
  return spell_tooltip_size_cache[content] or { width = 0, height = 0 }
end

local tooltip_size_cache = setmetatable({}, { __mode = "k" })
local function calculate_other_tooltip_size(gui, x, y, z, content)
  return tooltip_size_cache[content] or { width = 0, height = 0 }
end

-- Keeps a tooltip on screen: slots in the lower half of the screen get their tooltip above the slot, the rest below,
-- and it's kept within the screen edges
-- anchor_y is the y EZInventory asks the tooltip to be drawn at (10px below the slot)
local function fit_tooltip_to_screen(gui, x, y, width, height, anchor_y)
  if width <= 0 or height <= 0 then
    -- Size isn't known until the tooltip has been drawn once (tooltip_func hides it for that frame)
    return x, y
  end
  local margin = 4
  local screen_width, screen_height = GuiGetScreenDimensions(gui)
  local slot_center_y = anchor_y - 10 - slot_height / 2
  if slot_center_y > screen_height / 2 then
    y = anchor_y - 20 - slot_height - height
  end
  y = math.max(margin, math.min(y, screen_height - height - margin))
  x = math.max(margin, math.min(x, screen_width - width - margin))
  return x, y
end

local function draw_other_tooltip(gui, x, y, z, content)
  local name = ComponentGetValue2(content.spell.item_comp, "item_name")
  local desc = ComponentGetValue2(content.spell.item_comp, "ui_description")
  local sprite = ComponentGetValue2(content.spell.item_comp, "ui_sprite")
  GuiIdPushString(gui, "tooltip")
  GuiBeginAutoBox(gui)
  GuiLayoutBeginHorizontal(gui, x, y, true)
  GuiLayoutBeginVertical(gui, 0, 0, true)
  GuiZSetForNextWidget(gui, z - 1)
  GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
  GuiText(gui, 0, 0, GameTextGetTranslatedOrNot(name):upper())
  GuiZSetForNextWidget(gui, z - 1)
  GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
  GuiText(gui, 0, 5, GameTextGetTranslatedOrNot(desc))
  GuiLayoutEnd(gui)
  GuiZSetForNextWidget(gui, z - 1)
  GuiImage(gui, 3, 10, 0, sprite, 1, 2, 2)
  GuiLayoutEnd(gui)
  GuiZSetForNextWidget(gui, z)
  GuiEndAutoBoxNinePiece(gui)
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  if not tooltip_size_cache[content] then
    tooltip_size_cache[content] = { width = width - slot_width, height = height }
  end
  GuiIdPop(gui)
end

local function draw_tooltip(gui, x, y, z, content)
  local action_id = content.spell.action_id
  if action_id and action_id ~= "" then
    local size = calculate_spell_tooltip_size(gui, x, y, z, content)
    local tooltip_x, tooltip_y = fit_tooltip_to_screen(gui, x + 2 - size.width / 2, y, size.width, size.height, y)
    if content.spell.entity_id then
      EZWand.RenderSpellTooltip(content.spell.entity_id, tooltip_x, tooltip_y, gui)
    else
      EZWand.RenderSpellTooltip(action_id, tooltip_x, tooltip_y, gui, {
        uses_remaining = content.spell.uses_remaining
      })
    end
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    if not spell_tooltip_size_cache[content] then
      spell_tooltip_size_cache[content] = { width = width, height = height }
    end
  elseif not action_id then
    local size = calculate_other_tooltip_size(gui, x, y, z, content)
    local box_width = size.width > 0 and size.width + slot_width or 0
    local tooltip_x, tooltip_y = fit_tooltip_to_screen(gui, x - size.width / 2, y + 7, box_width, size.height, y)
    draw_other_tooltip(gui, tooltip_x, tooltip_y, z, content)
  else
    GuiBeginAutoBox(gui)
    GuiZSetForNextWidget(gui, z - 1)
    GuiText(gui, x, y, "Bugged spell oh no :(")
    GuiZSetForNextWidget(gui, z)
    GuiEndAutoBoxNinePiece(gui)
  end
end

local function tooltip_func(gui, x, y, z, content)
  local action_id = content.spell.action_id
  local is_bugged = action_id == ""
  local size_known = is_bugged or (action_id and spell_tooltip_size_cache[content] or tooltip_size_cache[content]) ~= nil
  if not size_known then
    -- The tooltip can't be positioned correctly before it's been drawn once, so draw it invisibly first to measure it
    GuiAnimateBegin(gui)
    GuiIdPushString(gui, "tooltip_measure")
    GuiAnimateAlphaFadeIn(gui, 3, 0, 0, true)
    draw_tooltip(gui, x, y, z, content)
    GuiIdPop(gui)
    GuiAnimateEnd(gui)
  end
  GuiAnimateBegin(gui)
  GuiIdPushString(gui, "tooltip_animation")
  GuiAnimateScaleIn(gui, 1, 0.08, false)
  GuiAnimateAlphaFadeIn(gui, 2, 0.15, 0.15, false)
  draw_tooltip(gui, x, y, z, content)
  GuiIdPop(gui)
  GuiAnimateEnd(gui)
end

local function does_spell_match_filter(filter, spell)
  local matches = true
  filter = filter:lower()
  if spell.action_id then
    local action_id = spell.action_id
    -- local description = GameTextGetTranslatedOrNot(action_lookup[action_id].description)
    if filter_by_type then
      matches = matches and (action_lookup[action_id].type == filter_by_type)
    end
    if filter ~= "" then
      local name = GameTextGetTranslatedOrNot(action_lookup[action_id].name or ""):lower()
      local id = action_id:lower()
      matches = matches and (name:find(filter) ~= nil) -- or description:find(filter)
    end
    return matches
  end
  return false
end

local function render_after(self, slot, gui, new_id, x, y, z, scale)
  if self.spell.action_id then
    GuiZSetForNextWidget(gui, z - 0.5)
    GuiImage(gui, new_id(), x, y, EZWand.get_spell_bg(self.spell.action_id), 1, 1, 1)
  end
  if self.spell.uses_remaining >= 0 then
    GuiZSetForNextWidget(gui, z - 2)
    GuiColorSetForNextWidget(gui, 0.9, 0.9, 0.9, 1)
    GuiText(gui, x + 2, y + 2, self.spell.uses_remaining, 1, "data/fonts/font_small_numbers.xml", true)
  end
  -- Grey it out if filters are active
  if not does_spell_match_filter(search_filter or "", self.spell) then
    GuiZSetForNextWidget(gui, z - 2.1)
    local scale_x = slot.width / 20
    local scale_y = slot.height / 20
    GuiImage(gui, new_id(), x, y, "mods/AdvancedSpellInventory/files/grey.png", 1, scale_x, scale_y)
  end
end

local function are_spells_same(a, b)
  return a.action_id == b.action_id and a.uses_remaining == b.uses_remaining
end

-- gets called before moving to check whether it can stack with target slot
-- a is source slot, b is target
local function stackable_with(a, b)
  if b.data.is_storage then
    return are_spells_same(a.content.spell, b.content.spell)
  end
  return false
end

local function clone_content(content)
  return {
    sprite = content.sprite,
    spell = {
      entity_id = content.spell.entity_id,
      item_comp = content.spell.item_comp,
      action_id = content.spell.action_id,
      inv_x = content.spell.inv_x,
      inv_y = content.spell.inv_y,
      uses_remaining = content.spell.uses_remaining,
    },
    max_stack_size = content.max_stack_size,
    render_after = content.render_after,
    stackable_with = content.stackable_with,
    tooltip_func = content.tooltip_func,
    clone = content.clone_content
  }
end

local function make_content_from_action_id(action_id, stack_size, uses_remaining)
  local sprite = action_lookup[action_id] and action_lookup[action_id].sprite
  return {
    sprite = sprite,
    stack_size = tonumber(stack_size),
    max_stack_size = 999,
    stackable_with = stackable_with,
    render_after = render_after,
    tooltip_func = tooltip_func,
    clone = clone_content,
    spell = {
      entity_id = nil,
      item_comp = nil,
      action_id = action_id,
      inv_x = 1,
      inv_y = 1,
      uses_remaining = tonumber(uses_remaining),
    },
  }
end

local function make_content_from_entity(entity_id)
  local action_id
  local item_action_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemActionComponent")
  if item_action_comp then
    action_id = ComponentGetValue2(item_action_comp, "action_id")
  end
  local inv_x, inv_y, ui_sprite, uses_remaining
  local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
  if item_comp then
    inv_x, inv_y = ComponentGetValue2(item_comp, "inventory_slot")
    uses_remaining = ComponentGetValue2(item_comp, "uses_remaining")
    ui_sprite = action_lookup[action_id] and action_lookup[action_id].sprite or ComponentGetValue2(item_comp, "ui_sprite")
  end
  return {
    sprite = ui_sprite,
    stack_size = 1,
    max_stack_size = 999,
    stackable_with = stackable_with,
    render_after = render_after,
    tooltip_func = tooltip_func,
    clone = clone_content,
    spell = {
      entity_id = entity_id,
      item_comp = item_comp,
      action_id = action_id,
      inv_x = inv_x,
      inv_y = inv_y,
      uses_remaining = uses_remaining,
    },
  }
end

local storage_slots
local slots

-- The storage is one long (sparse) list of contents, storage_slots is a window into it which starts at scroll_row
-- The visible slots are the source of truth for their range, sync before reading storage, refresh after changing it
local storage = {}
local scroll_row = 0
local total_rows = num_rows
local scroll_key = "AdvancedSpellInventory_scroll_row"
local storage_hovered = false
local dragging_scrollbar = false
local scrollbar_grab_offset = 0
local inventory_enabled_last_frame

local function view_offset()
  return scroll_row * full_inventory_slots_x
end

local function last_occupied_index()
  local last = 0
  for i in pairs(storage) do
    if i > last then
      last = i
    end
  end
  return last
end

-- Always keep one empty row below the last spell so there's room to put things
local function recompute_total_rows()
  total_rows = math.max(num_rows, math.ceil(last_occupied_index() / full_inventory_slots_x) + 1)
end

local function is_dragging_content()
  for i, slot in ipairs(storage_slots or {}) do
    if slot.dragging then return true end
  end
  for i, slot in ipairs(slots or {}) do
    if slot.dragging then return true end
  end
  return false
end

local function sync_visible_to_storage()
  if not storage_slots then return end
  local offset = view_offset()
  for i, slot in ipairs(storage_slots) do
    storage[offset + i] = slot.content
  end
end

local function refresh_visible()
  if not storage_slots then return end
  -- Clear all first, the same content might have been visible in another slot and SetContent reuses its widget
  for i, slot in ipairs(storage_slots) do
    slot:ClearContent()
  end
  local offset = view_offset()
  for i, slot in ipairs(storage_slots) do
    local content = storage[offset + i]
    if content then
      slot:SetContent(content)
    end
  end
end

local function set_scroll_row(row)
  if not storage_slots or is_dragging_content() then return end
  local old_scroll_row = scroll_row
  sync_visible_to_storage()
  recompute_total_rows()
  scroll_row = math.max(0, math.min(row, total_rows - num_rows))
  if scroll_row ~= old_scroll_row then
    refresh_visible()
    GlobalsSetValue(scroll_key, tostring(scroll_row))
  end
end

-- Stackable spell anywhere first, otherwise the first free index from the current view onward, wrapping around
local function find_storage_index(content)
  local last = last_occupied_index()
  for i=1, last do
    if storage[i] and are_spells_same(content.spell, storage[i].spell) then
      return i
    end
  end
  local start = view_offset() + 1
  for i=start, last do
    if not storage[i] then return i end
  end
  for i=1, start - 1 do
    if not storage[i] then return i end
  end
  return last + 1
end

local function store_content(content)
  local i = find_storage_index(content)
  if storage[i] then
    storage[i].stack_size = storage[i].stack_size + content.stack_size
  else
    storage[i] = content
  end
  return i
end

local function make_stored_content_from_entity(entity_id)
  local content = make_content_from_entity(entity_id)
  content.spell.entity_id = nil
  content.spell.item_comp = nil
  return content
end

local function get_first_free_inventory_slot()
  for i, slot in ipairs(slots or {}) do
    if slot.content == nil then
      return slot
    end
  end
end

local key = "AdvancedSpellInventory_stored_spells"
local function load_stored_spells()
  local serialized = GlobalsGetValue(key, "")
  local stored_spells = string_split(serialized, "|")
  storage = {}
  for i, spell in ipairs(stored_spells) do
    if spell ~= "" then
      local values = string_split(spell, ";") -- stack_size;action_id;uses_remaining
      local stack_size, action_id, uses_remaining = unpack(values)
      storage[i] = make_content_from_action_id(action_id, stack_size, uses_remaining)
    end
  end
  recompute_total_rows()
  scroll_row = math.max(0, math.min(tonumber(GlobalsGetValue(scroll_key, "0")) or 0, total_rows - num_rows))
  refresh_visible()
end

local function save_stored_spells()
  sync_visible_to_storage()
  local out = {}
  for i=1, last_occupied_index() do
    local content = storage[i]
    if content then
      local spell = content.spell
      local str = ("%d;%s;%d"):format(content.stack_size, spell.action_id, spell.uses_remaining)
      table.insert(out, str)
    else
      table.insert(out, "")
    end
  end
  GlobalsSetValue(key, table.concat(out, "|"))
end

-- Keep the display in sync with what's in the spell inventory
-- Simply recreating all widgets is probably more efficient than doing all kinds of checks to only update the ones that changed
local function update_slots()
  for i, slot in ipairs(slots) do
    slot:ClearContent()
  end
  for i, spell in ipairs(get_spells_in_inventory() or {}) do
    local did_store_spell = false
    if storage_slots and auto_storage and spell.action_id and can_spell_be_stored(spell.action_id) and spell.item_comp and ComponentGetValue2(spell.item_comp, "mFramePickedUp") == GameGetFrameNum() then
      sync_visible_to_storage()
      store_content(make_stored_content_from_entity(spell.entity_id))
      EntityKill(spell.entity_id)
      did_store_spell = true
    end
    if not did_store_spell then
      -- Problem: Sometimes in vanilla, items can have the same inv slot set, so indexing by inv slot is suboptimal...
      local slot = slots[spell.inv_y * full_inventory_slots_x + spell.inv_x + 1]
      slot:SetContent(make_content_from_entity(spell.entity_id))
    else
      refresh_visible()
      save_stored_spells()
    end
  end
end

local function sort_spells_in_storage(func, sort_order)
  sync_visible_to_storage()
  local contents = {}
  for i=1, last_occupied_index() do
    if storage[i] then
      table.insert(contents, storage[i])
    end
  end
  -- Merge same spells
  for i=#contents, 1, -1 do
    local content = contents[i]
    for j=i-1, 1, -1 do
      local content2 = contents[j]
      if are_spells_same(content.spell, content2.spell) then
        content2.stack_size = content2.stack_size + content.stack_size
        table.remove(contents, i)
        break
      end
    end
  end
  table.sort(contents, function(a, b)
    if sort_order == "ascending" then
      return func(a, b)
    elseif sort_order == "descending" then
      return func(b, a)
    end
    error("You misspelled sort_order, stringly typed strikes again")
    return true
  end)
  storage = {}
  for i, content in ipairs(contents) do
    storage[i] = content
  end
  recompute_total_rows()
  scroll_row = math.max(0, math.min(scroll_row, total_rows - num_rows))
  refresh_visible()
  save_stored_spells()
end

local function has_infinite_spells()
  local world_entity_id = GameGetWorldStateEntity()
  if world_entity_id then
    local worldstate_comp = EntityGetFirstComponentIncludingDisabled(world_entity_id, "WorldStateComponent")
    if worldstate_comp then
      return ComponentGetValue2(worldstate_comp, "perk_infinite_spells")
    end
  end
  return false
end

local function update_spell_uses()
  if not storage_slots then return end
  -- Visible slots hold the same content tables as storage, so updating storage updates them too
  sync_visible_to_storage()
  for i, content in pairs(storage) do
    if has_infinite_spells() and not action_lookup[content.spell.action_id].never_unlimited then
      content.spell.uses_remaining = -1
    else
      content.spell.uses_remaining = action_lookup[content.spell.action_id].max_uses or -1
    end
  end
  save_stored_spells()
end

local infinite_spells_last_frame = false
local function update_storage_if_unlimited_perks()
  local infinite_spells = has_infinite_spells()
  if infinite_spells ~= infinite_spells_last_frame then
    infinite_spells_last_frame = infinite_spells
    update_spell_uses()
  end
end

local previous_spells
local function has_spell_inventory_changed()
  local player = EntityGetWithTag("player_unit")[1]
  if not player then
    return false
  end
  local spells = get_spells_in_inventory()
  local _previous_spells = previous_spells
  previous_spells = spells
  if not spells or not _previous_spells then
    return false
  end
  if #_previous_spells ~= #spells then
    return true
  end
  for i=1, #spells do
    if spells[i].entity_id ~= _previous_spells[i].entity_id then
      return true
    end
    if spells[i].action_id ~= _previous_spells[i].action_id then
      return true
    end
    if spells[i].uses_remaining ~= _previous_spells[i].uses_remaining then
      return true
    end
    if spells[i].inv_x ~= _previous_spells[i].inv_x then
      return true
    end
    if spells[i].inv_y ~= _previous_spells[i].inv_y then
      return true
    end
  end
end

-- Gets called when dropping content into the world, not onto other slots
local function drop_content_handler(self, ev)
  local player = EntityGetWithTag("player_unit")[1]
  if player then
    play_ui_sound("item_remove")
    if self.data.is_storage then
      local mx, my = DEBUG_GetMouseWorld()
      SetRandomSeed(GameGetFrameNum() + mx, my)
      for i=1, self.content.stack_size do
        local px, py = EntityGetFirstHitboxCenter(player)
        local entity_id = CreateItemActionEntity(self.content.spell.action_id, px, py)
        local vel_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "VelocityComponent")
        if vel_comp then
          local dx, dy = mx - px, my - py
          local dist = math.sqrt(dx * dx + dy * dy)
          dist = math.min(dist, 100)
          dist = dist + Random(5, 10)
          local dir = math.atan2(dy, dx)
          dir = dir + Randomf(math.rad(-20), math.rad(20))
          local vx, vy = math.cos(dir) * dist, math.sin(dir) * dist
          ComponentSetValue2(vel_comp, "mVelocity", vx, vy)
          EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_world", true)
          EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_inventory", false)
          EntitySetComponentsWithTagEnabled(entity_id, "item_unidentified", false)
        end
        local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
        if item_comp then
          ComponentSetValue2(item_comp, "uses_remaining", self.content.spell.uses_remaining)
        end
        if ModIsEnabled("quant.ew") then
          CrossCall("ew_thrown", entity_id)
        end
      end
    else
      local entity_id = self.content.spell.entity_id
      local vel_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "VelocityComponent")
      if vel_comp then
        local px, py = EntityGetFirstHitboxCenter(player)
        local mx, my = DEBUG_GetMouseWorld()
        local dx, dy = mx - px, my - py
        local dist = math.sqrt(dx * dx + dy * dy)
        dist = math.min(dist, 100)
        local dir = math.atan2(dy, dx)
        local vx, vy = math.cos(dir) * dist, math.sin(dir) * dist
        ComponentSetValue2(vel_comp, "mVelocity", vx, vy)
        EntityRemoveFromParent(entity_id)
        EntityApplyTransform(entity_id, px, py)
        EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_world", true)
        EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_inventory", false)
        EntitySetComponentsWithTagEnabled(entity_id, "item_unidentified", false)
      end
      local item_comp = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
      if item_comp then
        ComponentSetValue2(item_comp, "uses_remaining", self.content.spell.uses_remaining)
      end
      if ModIsEnabled("quant.ew") then
        CrossCall("ew_thrown", entity_id)
      end
    end
  end
  self:ClearContent()
  save_stored_spells()
end

function string_split(input, sep)
  local result = {}
  for v in string.gmatch(input..sep, '([^'.. sep ..']*)' .. sep) do
    table.insert(result, v)
  end
  return result
end

function OnPlayerSpawned(player)
  frame_player_spawned = GameGetFrameNum()
  -- open starts out false, so don't let a saved "1" tell other mods (WandBlueprints) the panel is open
  GlobalsSetValue("AdvancedSpellInventory_is_open", "0")
  if ModIsEnabled("mnee") then
    function is_keybind_down()
      return get_binding_pressed("AdvSpellInv", "toggle")
    end
    function is_dump_keybind_down()
      return get_binding_pressed("AdvSpellInv", "dump")
    end
  end
end

local function button(gui, new_id, text, active)
  local w, h = GuiGetTextDimensions(gui, text)
  GuiText(gui, 2, 0, "")
  local _, _, _, tx, ty = GuiGetPreviousWidgetInfo(gui)
  tx = tx - 1
  GuiImageNinePiece(gui, new_id(), tx - 2, ty, w + 7, h + 2, 0, "data/debug/whitebox.png")
  local clicked, _, hovered = GuiGetPreviousWidgetInfo(gui)
  -- GuiGetPreviousWidgetInfo does not return right click for GuiImageNinePiece, so get it manually
  local right_clicked = hovered and InputIsMouseButtonJustDown(Mouse_right)
  GuiZSetForNextWidget(gui, 20 - 1)
  GuiImageNinePiece(gui, new_id(), tx + 3, ty + 2, w - 1, h - 4, 1, "mods/AdvancedSpellInventory/files/button_9piece" .. (active and "_active" or "") .. ".png")
  if hovered then
    GuiColorSetForNextWidget(gui, 0.95, 0.95, 0.7, 1)
  end
  GuiText(gui, 0, 0, text)
  GuiText(gui, 1, 0, "")
  return clicked, right_clicked
end

local function render_filter_panel(gui, new_id, origin_x, origin_y)
  local total_height = 0
  -- Sort buttons
  GuiLayoutBeginHorizontal(gui, origin_x, origin_y, true)
  GuiText(gui, 0, 0, " Sort by: ")
  local o = {
    { "A-Z", sorting_functions.alphabetical },
    { "Uses", sorting_functions.uses_remaining },
    { "Amount", sorting_functions.amount },
    { "Type", sorting_functions.type },
    { "Delay", sorting_functions.cast_delay },
    { "Recharge", sorting_functions.recharge_time },
  }
  for i, entry in ipairs(o) do
    local name, func = entry[1], entry[2]
    local clicked, right_clicked = button(gui, new_id, name, false)
    if clicked or right_clicked then
      sort_spells_in_storage(func, clicked and "ascending" or "descending")
    end
  end
  local v = ""
  if input_focused then
    GuiAnimateBegin(gui)
    GuiAnimateAlphaFadeIn(gui, new_id(), 0, 0, true)
    GuiBeginAutoBox(gui)
    GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
    GuiZSetForNextWidget(gui, -99999999999)
    GuiBeginScrollContainer(gui, new_id(), EZMouse.screen_x, EZMouse.screen_y, 10, 10, false, 0, 0)
    GuiEndAutoBoxNinePiece(gui)
    GuiAnimateEnd(gui)

    -- The input itself has to be invisible too, otherwise its blinking cursor shows up at the mouse
    GuiAnimateBegin(gui)
    GuiAnimateAlphaFadeIn(gui, new_id(), 0, 0, true)
    v = GuiTextInput(gui, new_id(), 0, 0, "", 0, 8)
    GuiAnimateEnd(gui)

    GuiEndScrollContainer(gui)
  else
    -- Use up the same ids as above, so the ids of the following widgets don't change when focus changes
    for _ = 1, 4 do new_id() end
  end
  -- Input field with logic to disable inputs and have backspace-holding delete functionality
  if input_focused then
    GuiColorSetForNextWidget(gui, 0.9, 0.9, 0, 1)
  end
  GuiText(gui, 1, 0, " Filter:")
  local new_search_filter = GuiTextInput(gui, new_id(), 0, 0, search_filter or "", 54, 8)
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  -- The first row's height, measured here because the caret drawn below would otherwise be the last widget of the row
  local first_row_height = height
  if InputIsMouseButtonJustDown(Mouse_right) and hovered then
    new_search_filter = ""
    search_filter = ""
  end
  if #new_search_filter < 8 then
    new_search_filter = new_search_filter .. v
  end
  if InputIsKeyJustDown(Key_BACKSPACE) then
    input_backspace_down_frame = GameGetFrameNum()
    new_search_filter = new_search_filter:gsub(".?$", "")
  elseif input_focused and InputIsKeyDown(Key_BACKSPACE) and input_backspace_down_frame + 15 < GameGetFrameNum() and GameGetFrameNum() % 5 == 0 then
    new_search_filter = new_search_filter:gsub(".?$", "")
  end
  if new_search_filter ~= search_filter then
    search_filter_changed = true
  end
  if input_focused then
    search_filter = new_search_filter
    -- The real input never has focus (typing goes through the hidden one), so draw a blinking cursor ourselves.
    -- It is drawn every frame and blinks via alpha: skipping it would shift the ids of all following widgets
    -- on every blink, which makes Noita's GUI reposition them back and forth.
    local text_w = GuiGetTextDimensions(gui, search_filter)
    local caret_x = math.min(x + 2 + text_w, x + width - 2)
    local alpha = GameGetFrameNum() % 40 < 24 and 1 or 0
    GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
    GuiZSetForNextWidget(gui, -1)
    GuiColorSetForNextWidget(gui, 0.9, 0.9, 0, 1)
    GuiImage(gui, new_id(), caret_x, y + 1, "data/debug/whitebox.png", alpha, 1 / 20, (height - 2) / 20)
  else
    new_id()
  end
  if InputIsMouseButtonJustDown(Mouse_left) then
    input_focused = hovered
  elseif InputIsKeyJustDown(Key_RETURN) then
    input_focused = false
  end
  input_hovered = hovered
  GuiLayoutEnd(gui)
  -- Second row, filter by spell type
  total_height = total_height + first_row_height + 2
  GuiLayoutBeginHorizontal(gui, origin_x - 1, origin_y + first_row_height + 2, true)
  local text = "Filter spells by type:"
  local text_width, text_height = GuiGetTextDimensions(gui, text)
  GuiText(gui, 4, (slot_height - text_height) / 2, text)
  for i, spell_type in ipairs(spell_types) do
    local scale = slot_width / 20
    GuiImage(gui, new_id(), 0, 0, spell_type.icon, 1, scale, scale)
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    if spell_type.type == filter_by_type then
      GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
      GuiColorSetForNextWidget(gui, 0, 1, 0, 1)
      local checkbox_w, checkbox_h = GuiGetImageDimensions(gui, "data/debug/sui_checkbox_overlay.png", scale)
      GuiImage(gui, new_id(), x - (checkbox_w - slot_width) / 2, y - (checkbox_h - slot_height) / 2, "data/debug/sui_checkbox_overlay.png", 1, scale, scale)
    end
    if clicked then
      filter_by_type = spell_type.type
    end
    GuiTooltip(gui, spell_type.name, "")
  end
  GuiLayoutEnd(gui)
  local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
  total_height = total_height + height
  return total_height
end

local function take_a_dump(player)
  if spell_dump_needs_wand_tinkering and not can_edit_wands(player) then
    GamePlaySound("data/audio/Desktop/ui.bank", "ui/button_denied", 0, 0)
    GamePrint("Can only dump spells if wand tinkering is possible.")
    return
  end
  local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
  if inventory_2_comp then
    local active_wand_entity_id = ComponentGetValue2(inventory_2_comp, "mActiveItem")
    if is_wand(active_wand_entity_id) and storage_slots then
      sync_visible_to_storage()
      for i, spell in ipairs(EZWand(active_wand_entity_id):GetSpells()) do
        if can_spell_be_stored(spell.action_id) then
          store_content(make_stored_content_from_entity(spell.entity_id))
          -- Apparently required according to some of my older comments, because EntityKill takes one frame to take effect
          EntityRemoveFromParent(spell.entity_id)
          EntityKill(spell.entity_id)
        end
      end
      refresh_visible()
      ComponentSetValue2(inventory_2_comp, "mForceRefresh", true)
      ComponentSetValue2(inventory_2_comp, "mActualActiveItem", 0)
      if sounds_enabled then
        if enable_funny_dump_sound then
          GamePlaySound("mods/AdvancedSpellInventory/audio/AdvancedSpellInventory.bank", "dump", 0, 0)
        else
          play_ui_sound("new_unlock")
        end
      end
      save_stored_spells()
    end
  end
end

-- Request channel for other mods, used by WandBlueprints. Every mod runs in its own Lua state, so this goes through
-- Globals (shared between mods) and spell entities (also shared). A request is a single string:
--   id|wand_entity_id|store_entity,store_entity,...|slot:ACTION_ID,slot:ACTION_ID,...
-- The spell entities are moved into storage first, then for each slot:ACTION_ID one spell is taken from storage and
-- put onto the wand at that (0-based) slot. The response is "id|slot:ACTION_ID,..." listing the ones not in storage.
local api_request_key = "AdvancedSpellInventory_api_request"
local api_response_key = "AdvancedSpellInventory_api_response"
-- Written every frame while storage is usable, so other mods know ASI is there and ready
local api_heartbeat_key = "AdvancedSpellInventory_api_heartbeat"

-- Removes one spell with this action_id from storage, preferring the stack with the most uses left (-1 = unlimited)
-- Returns its uses_remaining, or nil if there is none. Call sync_visible_to_storage() before.
local function take_from_storage(action_id)
  local best_index, best_score
  for i, content in pairs(storage) do
    if content.spell.action_id == action_id then
      local uses = content.spell.uses_remaining
      local score = uses < 0 and math.huge or uses
      if not best_score or score > best_score then
        best_index, best_score = i, score
      end
    end
  end
  if not best_index then return nil end
  local content = storage[best_index]
  local uses_remaining = content.spell.uses_remaining
  content.stack_size = content.stack_size - 1
  if content.stack_size <= 0 then
    storage[best_index] = nil
  end
  return uses_remaining
end

local function process_api_request()
  if not storage_slots or is_dragging_content() then
    return
  end
  GlobalsSetValue(api_heartbeat_key, tostring(GameGetFrameNum()))
  local request = GlobalsGetValue(api_request_key, "")
  if request == "" then
    return
  end
  GlobalsSetValue(api_request_key, "")
  local parts = string_split(request, "|")
  local id, wand_id = parts[1], tonumber(parts[2])
  sync_visible_to_storage()
  -- Stores first, so a cleared wand's spells can be taken right back out
  for i, entity_string in ipairs(string_split(parts[3] or "", ",")) do
    local entity_id = tonumber(entity_string)
    if entity_id and EntityGetIsAlive(entity_id) then
      store_content(make_stored_content_from_entity(entity_id))
      EntityRemoveFromParent(entity_id)
      EntityKill(entity_id)
    end
  end
  local missing = {}
  local wand_alive = wand_id and EntityGetIsAlive(wand_id)
  for i, take in ipairs(string_split(parts[4] or "", ",")) do
    local slot, action_id = take:match("^(%d+):(.+)$")
    if slot then
      local uses_remaining = wand_alive and take_from_storage(action_id)
      if uses_remaining then
        local action_entity = CreateItemActionEntity(action_id)
        EntitySetComponentsWithTagEnabled(action_entity, "enabled_in_world", false)
        EntitySetComponentsWithTagEnabled(action_entity, "enabled_in_inventory", true)
        local item_comp = EntityGetFirstComponentIncludingDisabled(action_entity, "ItemComponent")
        if item_comp then
          ComponentSetValue2(item_comp, "inventory_slot", tonumber(slot), 0)
          ComponentSetValue2(item_comp, "uses_remaining", uses_remaining)
        end
        EntityAddChild(wand_id, action_entity)
      else
        table.insert(missing, take)
      end
    end
  end
  refresh_visible()
  save_stored_spells()
  -- Make the game pick up the changed wand
  local player = EntityGetWithTag("player_unit")[1]
  local inventory_2_comp = player and EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
  if inventory_2_comp then
    ComponentSetValue2(inventory_2_comp, "mForceRefresh", true)
    ComponentSetValue2(inventory_2_comp, "mActualActiveItem", 0)
  end
  GlobalsSetValue(api_response_key, id .. "|" .. table.concat(missing, ","))
end

-- While typing into the filter, M-Nee's service mode mutes every mod's M-Nee bindings (this mod's toggle, Cartographer's
-- map key, WandBlueprints' hotkeys...), the same thing WandBlueprints does for its text fields
-- Re-added every frame while typing, in case another mod lifted it (WandBlueprints does when its own typing ends),
-- but only removed when typing here ends, so M-Nee's own use of it isn't undone
local typing_last_frame = false
local function update_mnee_typing_lock(typing)
  if not (mnee and mnee.SERV_MODE) then return end
  if typing and not GameHasFlagRun(mnee.SERV_MODE) then
    GameAddFlagRun(mnee.SERV_MODE)
  elseif not typing and typing_last_frame then
    GameRemoveFlagRun(mnee.SERV_MODE)
  end
  typing_last_frame = typing
end

function OnWorldPostUpdate()
  if opening_inv_closes_spell_inv and GameIsInventoryOpen() then
    open = false
    GlobalsSetValue("AdvancedSpellInventory_is_open", "0")
  end

  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)

  EZMouse.update(gui)

  if not slot_width then
    slot_width, slot_height = GuiGetImageDimensions(gui, "data/ui_gfx/inventory/full_inventory_box.png", 1)
  end

  -- Run this 1 frame after player has spawned
  if frame_player_spawned == GameGetFrameNum() - 1 then
    if ModIsEnabled("mnee") then
      dofile_once("mods/mnee/lib.lua")
    end
    -- Do this here so mods have enough time to do their gun_actions.lua mod appends
    dofile_once("data/scripts/gun/gun_actions.lua")
    EZWand = dofile_once("mods/AdvancedSpellInventory/lib/EZWand/EZWand.lua")
    for i, action in ipairs(actions) do
      action_lookup[action.id] = action
    end

    -- Render the middle panel part once to calculate its size, jank yea yea
    filter_panel_height = render_filter_panel(gui, new_id, 0, -100000)

    if not slots then
      slots = {}
      full_inventory_slots_x, full_inventory_slots_y = get_inventory_size()
      for y=1, full_inventory_slots_y do
        for x=1, full_inventory_slots_x do
          local idx = x + (y-1) * full_inventory_slots_x
          slots[idx] = EZInventory.Slot({
            x = origin_x + (x-1) * slot_width,
            y = origin_y + (y-1) * slot_height,
            data = {
              slot_x = x,
              slot_y = y,
              move_check = function(self, target_slot)
                return (self.content.spell.action_id ~= nil or not target_slot.data.is_storage) and can_spell_be_stored(self.content.spell.action_id)
              end,
              -- Needs to return the max stack size this slot can hold of the provided content
              get_max_stack_size = function(self, content)
                return 1
              end
            },
            width = slot_width,
            height = slot_height,
          })
          slots[idx]:AddEventListener("shift_click", function(self, ev)
            if self.content then
              sync_visible_to_storage()
              local target_index = find_storage_index(self.content)
              local visible_index = target_index - view_offset()
              if storage_slots[visible_index] then
                self:MoveContent(storage_slots[visible_index])
              elseif self.content.spell.action_id and can_spell_be_stored(self.content.spell.action_id) then
                -- Target is scrolled out of view, so put it there directly instead of moving it to a slot
                local entity_id = self.content.spell.entity_id
                store_content(make_stored_content_from_entity(entity_id))
                EntityKill(entity_id)
                self:ClearContent()
                play_ui_sound("item_move_success")
                save_stored_spells()
              end
            end
          end)
          slots[idx]:AddEventListener("drop_content", drop_content_handler)
          slots[idx]:AddEventListener("move_content", function(self, ev)
            if ev.target.data.is_storage then
              EntityKill(ev.content.spell.entity_id)
              ev.content.spell.entity_id = nil
              ev.content.spell.item_comp = nil
              save_stored_spells()
            else
              ComponentSetValue2(ev.content.spell.item_comp, "inventory_slot", ev.target.data.slot_x - 1, ev.target.data.slot_y - 1)
            end
          end)
        end
      end
      update_slots()

      storage_slots = {}
      for y=1, num_rows do
        for x=1, full_inventory_slots_x do
          local storage_slot = EZInventory.Slot({
            x = origin_x + (x-1) * slot_width,
            y = origin_y + (y-1) * slot_height + (full_inventory_slots_y * slot_height) + filter_panel_height + 4,
            data = {
              is_storage = true,
              slot_x = x,
              slot_y = y,
              x = x,
              y = y,
              move_check = function(self, target_slot)
                if not target_slot.data.is_storage and target_slot.content and self.content.stack_size > 1 then
                  return false
                end
                return true
              end,
              get_max_stack_size = function(self, content)
                return math.huge
              end
            },
            width = slot_width,
            height = slot_height,
          })
          storage_slot:AddEventListener("shift_click", function(self, ev)
            if self.content then
              local free_slot = get_first_free_inventory_slot()
              if free_slot then
                self:MoveContent(free_slot)
              end
            end
          end)
          storage_slot:AddEventListener("drop_content", drop_content_handler)
          storage_slot:AddEventListener("move_content", function(self, ev)
            if not ev.target.data.is_storage then
              local action_entity = CreateItemActionEntity(ev.content.spell.action_id)
              -- Created as a world item, switch it to its in-inventory state ourselves instead of relying on
              -- Inventory2Component, which is disabled while the storage is hovered
              EntitySetComponentsWithTagEnabled(action_entity, "enabled_in_world", false)
              EntitySetComponentsWithTagEnabled(action_entity, "enabled_in_inventory", true)
              local item_comp = EntityGetFirstComponentIncludingDisabled(action_entity, "ItemComponent")
              if item_comp then
                ComponentSetValue2(item_comp, "inventory_slot", ev.target.data.slot_x - 1, ev.target.data.slot_y - 1)
                ComponentSetValue2(item_comp, "uses_remaining", ev.content.spell.uses_remaining)
              end
              local spell_inventory = get_spell_inventory()
              EntityAddChild(spell_inventory, action_entity)
            end
            save_stored_spells()
          end)
          storage_slots[(y-1) * full_inventory_slots_x + x] = storage_slot
        end
      end
    end
    load_stored_spells()
  end

  update_storage_if_unlimited_perks()
  if has_spell_inventory_changed() then
    update_slots()
  end
  -- Keeps total_rows up to date (grows/shrinks as spells are moved around) and the scroll position within bounds
  set_scroll_row(scroll_row)
  -- Requests from other mods (WandBlueprints)
  process_api_request()

  -- Refresh spells in spell storage if spell refresh is picked up
  if enable_spell_refresh_in_storage and GlobalsGetValue("AdvancedSpellInventory_spells_refreshed", "0") == "1" then
    GlobalsSetValue("AdvancedSpellInventory_spells_refreshed", "0")
    update_spell_uses()
  end

  -- Allow speed clicking
  GuiOptionsAdd(gui, GUI_OPTION.HandleDoubleClickAsClick)
  GuiOptionsAdd(gui, GUI_OPTION.ClickCancelsDoubleClick)

  if GameGetIsGamepadConnected() then
		GuiOptionsAdd(gui, GUI_OPTION.NonInteractive)
	end
	GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)

  local player = EntityGetWithTag("player_unit")[1]
	local inventory_open = is_inventory_open()
  local inventory_bags_open = GlobalsGetValue("InventoryBags_is_open", "0") ~= "0"
	if player then
    local button_clicked = false
    if not inventory_open and not inventory_bags_open and show_button then
      local image = InputIsKeyDown(Key_LSHIFT) and dump_button_image or "gui_button.png"
      button_clicked = GuiImageButton(gui, 99999, button_pos_x, button_pos_y, "", "mods/AdvancedSpellInventory/files/" .. image)
      local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
      if hovered and InputIsMouseButtonDown(Mouse_right) then
        dragging_button = true
      end
      if InputIsKeyDown(Key_LSHIFT) then
        GuiTooltip(gui, "Take a dump", "Dump all spells of currently active wand to spell storage")
      end
    end
    -- Toggle it open/closed
    local keybind_down = is_keybind_down()
    -- Hotkey while the vanilla inventory is open: close it and open instead of toggling.
    -- The frame stamp lets InventoryBags (sharing the same hotkey) do the same. It's matched within a couple of
    -- frames, not exactly: this runs in OnWorldPostUpdate and InventoryBags in OnWorldPreUpdate, so the two can
    -- see the same keypress a frame apart.
    local frame = tostring(GameGetFrameNum())
    local stamp = tonumber(GlobalsGetValue("InvHotkey_closed_inventory_frame", ""))
    local inventory_just_closed = stamp and math.abs(GameGetFrameNum() - stamp) <= 2
    if keybind_down and (inventory_open or inventory_just_closed) then
      local inventory_gui_component = EntityGetFirstComponentIncludingDisabled(player, "InventoryGuiComponent")
      if inventory_gui_component then
        ComponentSetValue2(inventory_gui_component, "mActive", false)
      end
      GlobalsSetValue("InvHotkey_closed_inventory_frame", frame)
      inventory_open = false
      if not open then
        open = true
        GlobalsSetValue("AdvancedSpellInventory_is_open", "1")
        play_ui_sound("inventory_open")
      end
    elseif keybind_down or (not InputIsKeyDown(Key_LSHIFT) and button_clicked) then
      open = not open
      GlobalsSetValue("AdvancedSpellInventory_is_open", tostring(open and 1 or 0))
      play_ui_sound("inventory_" .. (open and "open" or "close"))
    elseif is_dump_keybind_down() or (InputIsKeyDown(Key_LSHIFT) and button_clicked) then
      take_a_dump(player)
    end
  end

  if InputIsMouseButtonJustUp(Mouse_right) then
    dragging_button = false
    ModSettingSet("AdvancedSpellInventory.button_pos_x", button_pos_x)
    ModSettingSet("AdvancedSpellInventory.button_pos_y", button_pos_y)
  end
  if dragging_button then
    button_pos_x, button_pos_y = EZMouse.screen_x - 10, EZMouse.screen_y - 10
  end

  for i, slot in ipairs(slots or {}) do
    if slot.hovered and InputIsMouseButtonJustDown(Mouse_right) then
      drop_content_handler(slot)
      slot:ClearContent()
    end
  end
  for i, slot in ipairs(storage_slots or {}) do
    if slot.hovered and InputIsMouseButtonJustDown(Mouse_right) then
      drop_content_handler(slot)
      slot:ClearContent()
    end
  end

  local visible = open and not inventory_open and (player ~= nil)
  local dragging_enabled = not InputIsKeyDown(Key_LSHIFT)
  EZInventory.Update(gui, visible, dragging_enabled)
  storage_hovered = false
  local over_scrollbar = false
  if not visible or not InputIsMouseButtonDown(Mouse_left) then
    dragging_scrollbar = false
  end
	if visible and storage_slots then
    local mx, my = EZMouse.screen_x, EZMouse.screen_y
    local storage_top = origin_y + full_inventory_slots_y * slot_height + filter_panel_height + 4
    local storage_height = num_rows * slot_height
    local track_x = origin_x + full_inventory_slots_x * slot_width + 8
    local track_y = storage_top + 3
    local track_w = 3
    local track_h = storage_height - 8
    local max_scroll = total_rows - num_rows
    -- Includes the borders of the nine piece
    over_scrollbar = max_scroll > 0 and mx >= track_x - 4 and mx <= track_x + track_w + 4 and my >= track_y - 4 and my <= track_y + track_h + 4
    storage_hovered = over_scrollbar or (mx >= origin_x and mx <= track_x and my >= storage_top and my <= storage_top + storage_height)
    if storage_hovered then
      if InputIsMouseButtonJustDown(Mouse_wheel_up) then
        set_scroll_row(scroll_row - 1)
      elseif InputIsMouseButtonJustDown(Mouse_wheel_down) then
        set_scroll_row(scroll_row + 1)
      end
    end
    max_scroll = total_rows - num_rows
    if max_scroll > 0 then
      local thumb_h = math.min(track_h, math.max(6, math.floor(track_h * num_rows / total_rows)))
      local thumb_travel = track_h - thumb_h
      local thumb_y = track_y + thumb_travel * scroll_row / max_scroll
      local over_thumb = over_scrollbar and my >= thumb_y - 1 and my <= thumb_y + thumb_h + 1
      if over_scrollbar and InputIsMouseButtonJustDown(Mouse_left) then
        if over_thumb then
          dragging_scrollbar = true
          scrollbar_grab_offset = my - thumb_y
        elseif my < thumb_y then
          set_scroll_row(scroll_row - num_rows)
        else
          set_scroll_row(scroll_row + num_rows)
        end
      end
      if dragging_scrollbar and thumb_travel > 0 then
        local fraction = (my - scrollbar_grab_offset - track_y) / thumb_travel
        set_scroll_row(math.floor(fraction * max_scroll + 0.5))
      end
      thumb_y = track_y + thumb_travel * scroll_row / max_scroll
      GuiZSetForNextWidget(gui, 19)
      GuiImageNinePiece(gui, new_id(), track_x, track_y, track_w, track_h, 1, "mods/AdvancedSpellInventory/files/container_9piece.png")
      GuiTooltip(gui, ("Rows %d-%d of %d"):format(scroll_row + 1, scroll_row + num_rows, total_rows), "Scroll with the mouse wheel while hovering the storage")
      local brightness = (over_thumb or dragging_scrollbar) and 1 or 0.7
      GuiZSetForNextWidget(gui, 18)
      GuiColorSetForNextWidget(gui, brightness, brightness, brightness, 1)
      GuiImage(gui, new_id(), track_x, thumb_y, "data/debug/whitebox.png", 1, track_w / 20, thumb_h / 20)
    end
  end
	if visible then
    local title_text = GameTextGetTranslatedOrNot("$hud_title_actionstorage")
    local text_w, text_h = GuiGetTextDimensions(gui, title_text)
    GuiZSetForNextWidget(gui, 20)
    GuiText(gui, origin_x, origin_y - 2 - text_h, title_text)
    GuiZSetForNextWidget(gui, 21)
    GuiColorSetForNextWidget(gui, 0, 0, 0, 1)
    -- Title "Spells"
    GuiText(gui, origin_x, origin_y - 2 - text_h + 1, title_text)
    local panel_width = full_inventory_slots_x * slot_width - 2
    local panel_height = full_inventory_slots_y * slot_height + num_rows * slot_height + filter_panel_height + 2
    -- Container with border
    GuiZSetForNextWidget(gui, 20)
    GuiImageNinePiece(gui, new_id(), origin_x + 1, origin_y + 1, panel_width, panel_height, 1, "mods/AdvancedSpellInventory/files/container_9piece.png", "mods/AdvancedSpellInventory/files/container_9piece.png")
    local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
    -- Block mouse clicks if panel is hovered
    if hovered or over_scrollbar or dragging_scrollbar then
      local mx, my = EZMouse.screen_x, EZMouse.screen_y
      GuiZSetForNextWidget(gui, 0)
      GuiImage(gui, new_id(), mx - 100, my - 100, "data/debug/whitebox.png", 0.0001, 10, 10)
    end
    render_filter_panel(gui, new_id, origin_x + 2, origin_y + (full_inventory_slots_y * slot_height) + 4)
	end

  -- Disable controls if input field is hovered
  if player then
    local controls_enabled = not visible or not input_focused
    if controls_enabled ~= controls_enabled_last_frame then
      local controls_comp = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
      if controls_comp then
        EntityRemoveComponent(player, controls_comp)
        controls_comp = EntityAddComponent2(player, "ControlsComponent")
        ComponentSetValue2(controls_comp, "enabled", controls_enabled)
      end
    end
    controls_enabled_last_frame = controls_enabled
    -- Also disable the inventory while the storage is hovered, so the mouse wheel scrolls it instead of switching wands
    local inventory_enabled = controls_enabled and not storage_hovered
    if inventory_enabled ~= inventory_enabled_last_frame then
      local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
      if inventory_2_comp then
        EntitySetComponentIsEnabled(player, inventory_2_comp, inventory_enabled)
      end
    end
    inventory_enabled_last_frame = inventory_enabled
  end
  -- Outside the player check, so a polymorph or death mid-typing still lifts the mute
  update_mnee_typing_lock(visible and input_focused and player ~= nil)
end
