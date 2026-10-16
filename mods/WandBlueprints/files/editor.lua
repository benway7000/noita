-- Blueprint editor: name, note, hotkey, icon and the spell slots, edited with drag and drop like a wand.
-- EZInventory slots can't be destroyed, so a fixed pool is created once and unused slots are parked offscreen.

local M = {}

local EZInventory, EZWand, ui, apply
local storage = dofile_once("mods/WandBlueprints/files/storage.lua")
local action_lookup, all_actions

local COLS = 10
local MAX_SLOTS = 40
local PALETTE_ROWS = 5
local PALETTE_SIZE = COLS * PALETTE_ROWS
local PARK_X, PARK_Y = -1000, -1000
local MAX_NAME_LENGTH = 30
local MAX_NOTE_LENGTH = 60
local MAX_HOTKEY = 10
local UNIDENTIFIED = "data/ui_gfx/gun_actions/unidentified.png"

local spell_types = {
  { name = "Everything", icon = "mods/WandBlueprints/files/spell_type_all.png" },
  { type = ACTION_TYPE_PROJECTILE, name = "$inventory_actiontype_projectile", icon = "data/ui_gfx/inventory/item_bg_projectile.png" },
  { type = ACTION_TYPE_STATIC_PROJECTILE, name = "$inventory_actiontype_staticprojectile", icon = "data/ui_gfx/inventory/item_bg_static_projectile.png" },
  { type = ACTION_TYPE_MODIFIER, name = "$inventory_actiontype_modifier", icon = "data/ui_gfx/inventory/item_bg_modifier.png" },
  { type = ACTION_TYPE_DRAW_MANY, name = "$inventory_actiontype_drawmany", icon = "data/ui_gfx/inventory/item_bg_draw_many.png" },
  { type = ACTION_TYPE_MATERIAL, name = "$inventory_actiontype_material", icon = "data/ui_gfx/inventory/item_bg_material.png" },
  { type = ACTION_TYPE_OTHER, name = "$inventory_actiontype_other", icon = "data/ui_gfx/inventory/item_bg_other.png" },
  { type = ACTION_TYPE_UTILITY, name = "$inventory_actiontype_utility", icon = "data/ui_gfx/inventory/item_bg_utility.png" },
  { type = ACTION_TYPE_PASSIVE, name = "$inventory_actiontype_passive", icon = "data/ui_gfx/inventory/item_bg_passive.png" },
}

local slot_width, slot_height = 20, 20
local strip_slots, palette_slots, icon_slot
local layout -- Absolute positions, computed when the slots are created

-- Editing state
local state -- { bp = blueprint copy, index = index in list or nil for new, num_slots }
local palette_filter = ""
local palette_type
local palette_page = 0
local palette_dirty = false
local category_dropdown_open = false
local icon_dirty = false

function M.init(ezinventory, ezwand, ui_module, apply_module, lookup, actions_list)
  EZInventory = ezinventory
  EZWand = ezwand
  ui = ui_module
  apply = apply_module
  action_lookup = lookup
  all_actions = actions_list
end

local function sprite_for(action_id)
  local action = action_lookup[action_id]
  return action and action.sprite or UNIDENTIFIED
end

local function render_after(self, slot, gui, new_id, x, y, z, scale)
  GuiZSetForNextWidget(gui, z - 0.5)
  GuiImage(gui, new_id(), x, y, EZWand.get_spell_bg(self.spell.action_id), 1, 1, 1)
end

local function tooltip_func(gui, x, y, z, content)
  local action_id = content.spell.action_id
  ui.spell_tooltip(gui, action_id, x, y, y - 10 - slot_height, slot_height, action_lookup[action_id] ~= nil)
end

local function make_content(action_id)
  return {
    sprite = sprite_for(action_id),
    stack_size = 1,
    max_stack_size = 1,
    stackable_with = function() return false end,
    render_after = render_after,
    tooltip_func = tooltip_func,
    clone = function(self) return make_content(self.spell.action_id) end,
    spell = { action_id = action_id },
  }
end

local function kind_of(slot)
  return slot.data.kind
end

local function strip_position(i)
  return layout.strip_x + ((i - 1) % COLS) * slot_width, layout.strip_y + math.floor((i - 1) / COLS) * slot_height
end

local function strip_rows()
  return math.max(1, math.ceil(state.num_slots / COLS))
end

local function palette_y()
  return layout.strip_y + strip_rows() * slot_height + 18
end

local function first_empty_strip_slot()
  for i = 1, state.num_slots do
    if not strip_slots[i].content then
      return strip_slots[i]
    end
  end
end

-- Shows the first num_slots strip slots, parks the rest (and clears whatever they held)
local function update_strip_visibility()
  for i, slot in ipairs(strip_slots) do
    if i <= state.num_slots then
      if slot.x == PARK_X and not slot.content then
        slot.x, slot.y = strip_position(i)
      end
    else
      slot:ClearContent()
      slot.x, slot.y = PARK_X, PARK_Y
    end
  end
  palette_dirty = true
end

local function get_filtered_actions()
  local result = {}
  local filter = palette_filter:lower()
  for i, action in ipairs(all_actions) do
    local matches = (palette_type == nil or action.type == palette_type)
    if matches and filter ~= "" then
      matches = GameTextGetTranslatedOrNot(action.name or ""):lower():find(filter, 1, true) ~= nil
    end
    if matches then
      table.insert(result, action.id)
    end
  end
  return result
end

local filtered_actions = {}
local function refresh_palette()
  filtered_actions = get_filtered_actions()
  local num_pages = math.max(1, math.ceil(#filtered_actions / PALETTE_SIZE))
  palette_page = math.max(0, math.min(palette_page, num_pages - 1))
  local py = palette_y()
  for i, slot in ipairs(palette_slots) do
    slot:ClearContent()
    slot.x = layout.strip_x + ((i - 1) % COLS) * slot_width
    slot.y = py + math.floor((i - 1) / COLS) * slot_height
    local action_id = filtered_actions[palette_page * PALETTE_SIZE + i]
    if action_id then
      slot:SetContent(make_content(action_id), true)
    end
  end
  palette_dirty = false
end

local function refresh_icon()
  icon_slot:ClearContent()
  if state.bp.icon ~= "" then
    icon_slot:SetContent(make_content(state.bp.icon), true)
    -- Not draggable, it's only a drop target
    icon_slot.enabled = false
  end
  icon_dirty = false
end

local function set_strip_spells(slots)
  for i, slot in ipairs(strip_slots) do
    slot:ClearContent()
  end
  state.num_slots = math.max(1, math.min(#slots, MAX_SLOTS))
  update_strip_visibility()
  for i = 1, state.num_slots do
    local slot = strip_slots[i]
    slot.x, slot.y = strip_position(i)
    if slots[i] and slots[i] ~= "" then
      slot:SetContent(make_content(slots[i]), true)
    end
  end
end

local function create_slots(gui)
  local screen_width = GuiGetScreenDimensions(gui)
  layout = {}
  layout.panel_w = COLS * slot_width + 12
  layout.panel_x = screen_width - layout.panel_w - ui.PANEL_RIGHT_MARGIN
  layout.panel_h = 0
  layout.panel_y = 46
  layout.x = layout.panel_x + 6
  layout.y = layout.panel_y + 5
  layout.strip_x = layout.x
  layout.strip_y = layout.y + 63

  local function new_slot(kind, data)
    data = data or {}
    data.kind = kind
    data.get_max_stack_size = function(self, content) return 1 end
    return EZInventory.Slot({
      x = PARK_X, y = PARK_Y,
      width = slot_width, height = slot_height,
      data = data,
    })
  end

  strip_slots = {}
  for i = 1, MAX_SLOTS do
    local slot = new_slot("strip", {
      move_check = function(self, target)
        return true
      end,
    })
    slot:AddEventListener("move_content", function(self, ev)
      if kind_of(ev.target) == "palette" then
        -- Dropped onto the palette means removed from the blueprint
        self:ClearContent()
        palette_dirty = true
      elseif kind_of(ev.target) == "icon" then
        -- Dropped onto the icon: becomes the icon, but stays in the blueprint (the old icon got swapped in here)
        local action_id = ev.content.spell.action_id
        state.bp.icon = action_id
        self:ClearContent()
        self:SetContent(make_content(action_id), true)
        icon_dirty = true
      end
    end)
    slot:AddEventListener("drop_content", function(self, ev)
      -- Let go somewhere inside the editor that isn't a slot: it already snapped back, keep it
      if ui.is_mouse_inside(layout.panel_x - 3, layout.panel_y - 3, layout.panel_w + 6, layout.panel_h + 6) then
        return
      end
      -- Dragged out into the world, remove it
      self:ClearContent()
      ui.play_sound("item_remove")
    end)
    strip_slots[i] = slot
  end

  palette_slots = {}
  for i = 1, PALETTE_SIZE do
    local slot = new_slot("palette", {
      move_check = function(self, target)
        return kind_of(target) == "strip" or kind_of(target) == "icon"
      end,
    })
    slot:AddEventListener("move_content", function(self, ev)
      if kind_of(ev.target) == "icon" then
        state.bp.icon = ev.content.spell.action_id
        icon_dirty = true
      end
      -- The palette is an infinite source, put a fresh copy back (and drop whatever got swapped in)
      palette_dirty = true
    end)
    slot:AddEventListener("shift_click", function(self, ev)
      if not self.content then return end
      local target = first_empty_strip_slot()
      if not target and state.num_slots < MAX_SLOTS then
        state.num_slots = state.num_slots + 1
        update_strip_visibility()
        target = strip_slots[state.num_slots]
      end
      if target then
        target:SetContent(make_content(self.content.spell.action_id), true)
        ui.play_sound("item_move_success")
      end
    end)
    palette_slots[i] = slot
  end

  icon_slot = new_slot("icon", {
    move_check = function(self, target)
      -- The icon itself can't be dragged (see refresh_icon), this only allows spells to swap in.
      -- The swapped out icon gets thrown away when the palette or strip slot refreshes.
      return true
    end,
  })
  icon_slot:AddEventListener("move_content", function(self, ev)
    icon_dirty = true
    palette_dirty = true
  end)
end

function M.is_open()
  return state ~= nil
end

-- Typing into one of the editor's text inputs
function M.is_typing()
  return state ~= nil and ui.focused_input ~= nil
end

function M.open(gui, bp, index)
  if not strip_slots then
    create_slots(gui)
  end
  state = { bp = bp, index = index, num_slots = 1 }
  category_dropdown_open = false
  icon_slot.x, icon_slot.y = layout.x, layout.y
  set_strip_spells(bp.slots)
  refresh_icon()
  refresh_palette()
end

function M.close()
  if not state then return end
  for i, slot in ipairs(strip_slots) do
    slot:ClearContent()
    slot.x, slot.y = PARK_X, PARK_Y
  end
  for i, slot in ipairs(palette_slots) do
    slot:ClearContent()
    slot.x, slot.y = PARK_X, PARK_Y
  end
  icon_slot:ClearContent()
  icon_slot.x, icon_slot.y = PARK_X, PARK_Y
  ui.focused_input = nil
  state = nil
end

local function collect_slots()
  local slots = {}
  for i = 1, state.num_slots do
    local content = strip_slots[i].content
    slots[i] = content and content.spell.action_id or ""
  end
  return slots
end

local function hotkey_label(hotkey)
  if hotkey == 0 then
    return "None"
  end
  local keys
  if mnee and mnee.get_binding_keys then
    local ok, result = pcall(mnee.get_binding_keys, "WandBlueprints", "hotkey_" .. hotkey, true)
    if ok then keys = result end
  end
  if not ModIsEnabled("mnee") then
    keys = "needs M-Nee"
  end
  return hotkey .. "  [" .. (keys or "?") .. "]"
end

-- Renders the editor. Returns nil, or { action = "save", bp, index } / { action = "cancel" }
function M.update(gui, new_id, notify)
  if not state then return end
  if palette_dirty then refresh_palette() end
  if icon_dirty then refresh_icon() end

  -- Right click removes a spell from the blueprint
  if InputIsMouseButtonJustDown(Mouse_right) then
    for i = 1, state.num_slots do
      if strip_slots[i].hovered then
        strip_slots[i]:ClearContent()
        ui.play_sound("item_remove")
      end
    end
  end

  local x, y = layout.x, layout.y
  local num_pages = math.max(1, math.ceil(#filtered_actions / PALETTE_SIZE))
  local py = palette_y()
  local footer_y = py + PALETTE_ROWS * slot_height + 4
  layout.panel_h = footer_y + 14 - layout.panel_y
  ui.panel(gui, new_id, layout.panel_x, layout.panel_y, layout.panel_w, layout.panel_h)

  ui.capture_typing(gui, new_id)

  -- Icon slot needs a backdrop hint when empty
  if state.bp.icon == "" then
    GuiZSetForNextWidget(gui, 0.5)
    GuiColorSetForNextWidget(gui, 0.6, 0.6, 0.6, 1)
    GuiText(gui, x + 5, y + 5, "?")
  end
  -- The category dropdown opens upwards over the rows above it, those are shown read-only meanwhile,
  -- otherwise clicks on the dropdown would also land on the widgets underneath
  local dropdown_was_open = category_dropdown_open
  GuiText(gui, x + 24, y, "Name")
  if category_dropdown_open then
    GuiText(gui, x + 52, y, ui.fit_text(gui, state.bp.name, 146))
  else
    state.bp.name = ui.text_input(gui, new_id, "name", x + 50, y, state.bp.name, 150, MAX_NAME_LENGTH)
  end
  GuiText(gui, x + 24, y + 11, "Hotkey")
  local hx = x + 56
  if not category_dropdown_open then
    local clicked, _, w = ui.button(gui, new_id, hx, y + 11, "<")
    if clicked then state.bp.hotkey = (state.bp.hotkey - 1) % (MAX_HOTKEY + 1) end
    hx = hx + w
    local clicked, _, w = ui.button(gui, new_id, hx, y + 11, ">")
    if clicked then state.bp.hotkey = (state.bp.hotkey + 1) % (MAX_HOTKEY + 1) end
    hx = hx + w + 2
  end
  GuiText(gui, hx, y + 12, ui.fit_text(gui, hotkey_label(state.bp.hotkey), x + COLS * slot_width - hx))
  GuiText(gui, x, y + 24, "Note")
  if category_dropdown_open then
    GuiText(gui, x + 28, y + 24, ui.fit_text(gui, state.bp.note, 172))
  else
    state.bp.note = ui.text_input(gui, new_id, "note", x + 26, y + 24, state.bp.note, 174, MAX_NOTE_LENGTH)
  end

  -- Category dropdown
  local cy = y + 37
  GuiText(gui, x, cy + 1, "Category")
  local category = storage.get_category(state.bp.category)
  local dropdown_x = x + 44
  local clicked = ui.button(gui, new_id, dropdown_x, cy, category.name .. " v", category_dropdown_open)
  if clicked then
    category_dropdown_open = not category_dropdown_open
    ui.focused_input = nil
  end
  if dropdown_was_open then
    local option_h = 11
    local width = 0
    for i, c in ipairs(storage.CATEGORIES) do
      width = math.max(width, GuiGetTextDimensions(gui, c.name))
    end
    width = width + 8
    local height = #storage.CATEGORIES * option_h + 2
    local dropdown_y = cy - height - 2
    GuiZSetForNextWidget(gui, -60)
    GuiImageNinePiece(gui, new_id(), dropdown_x + 3, dropdown_y, width, height, 1, "mods/WandBlueprints/files/container_9piece.png")
    for i, c in ipairs(storage.CATEGORIES) do
      GuiZSetForNextWidget(gui, -61)
      if c.id == category.id then
        GuiColorSetForNextWidget(gui, 1, 1, 0.6, 1)
      end
      if GuiButton(gui, new_id(), dropdown_x + 6, dropdown_y + 1 + (i - 1) * option_h, c.name) then
        state.bp.category = c.id
        category_dropdown_open = false
      end
    end
    -- Clicking anywhere else closes it
    if InputIsMouseButtonJustDown(Mouse_left) and not clicked
      and not ui.is_mouse_inside(dropdown_x + 3, dropdown_y, width, height) then
      category_dropdown_open = false
    end
  end

  -- Slot count and loading from wand
  local sy = y + 50
  GuiText(gui, x, sy + 1, ("Spells (%d)"):format(state.num_slots))
  local bx = x + 52
  local clicked, _, w = ui.button(gui, new_id, bx, sy, "-")
  if clicked and state.num_slots > 1 then
    state.num_slots = state.num_slots - 1
    update_strip_visibility()
  end
  bx = bx + w
  local clicked, _, w = ui.button(gui, new_id, bx, sy, "+")
  if clicked and state.num_slots < MAX_SLOTS then
    state.num_slots = state.num_slots + 1
    update_strip_visibility()
  end
  bx = bx + w + 4
  local clicked = ui.button(gui, new_id, bx, sy, "Load from held wand")
  if clicked then
    local wand_id = apply.get_held_wand()
    if wand_id then
      local slots = apply.capture_from_wand(wand_id)
      if #slots > MAX_SLOTS then
        notify({ ("Wand has %d spell slots, only the first %d were loaded"):format(#slots, MAX_SLOTS) })
      end
      set_strip_spells(slots)
    else
      notify({ "No wand held" })
    end
  end

  -- Palette filter row
  local fy = py - 15
  GuiText(gui, x, fy + 1, "Filter")
  local new_filter = ui.text_input(gui, new_id, "filter", x + 28, fy + 1, palette_filter, 50, 12)
  if new_filter ~= palette_filter then
    palette_filter = new_filter
    palette_page = 0
    palette_dirty = true
  end
  local tx = x + 84
  for i, spell_type in ipairs(spell_types) do
    local scale = 0.6
    GuiImage(gui, new_id(), tx, fy, spell_type.icon, 1, scale, scale)
    local clicked, _, hovered = GuiGetPreviousWidgetInfo(gui)
    if spell_type.type == palette_type then
      GuiZSetForNextWidget(gui, -1)
      GuiColorSetForNextWidget(gui, 0, 1, 0, 1)
      GuiImage(gui, new_id(), tx - 1, fy - 1, "data/debug/sui_checkbox_overlay.png", 1, scale, scale)
    end
    if clicked then
      palette_type = spell_type.type
      palette_page = 0
      palette_dirty = true
    end
    GuiTooltip(gui, GameTextGetTranslatedOrNot(spell_type.name), "")
    tx = tx + 13
  end

  -- Footer: palette pages, save, cancel
  local result
  local fx = x
  local clicked, _, w = ui.button(gui, new_id, fx, footer_y, "<")
  if clicked and palette_page > 0 then
    palette_page = palette_page - 1
    palette_dirty = true
  end
  fx = fx + w
  GuiText(gui, fx + 1, footer_y + 1, ("%d/%d"):format(palette_page + 1, num_pages))
  fx = fx + GuiGetTextDimensions(gui, ("%d/%d"):format(palette_page + 1, num_pages)) + 4
  local clicked, _, w = ui.button(gui, new_id, fx, footer_y, ">")
  if clicked and palette_page < num_pages - 1 then
    palette_page = palette_page + 1
    palette_dirty = true
  end
  fx = fx + w + 2
  GuiColorSetForNextWidget(gui, 0.7, 0.7, 0.7, 1)
  GuiText(gui, fx, footer_y + 1, "(?)")
  GuiTooltip(gui, "How to edit",
    "Drag spells from the list into the slots above.\n" ..
    "Shift-click a spell in the list to add it to the first free slot.\n" ..
    "Drag slots to rearrange them, drag out or right-click to remove.\n" ..
    "Drag a spell from the list or the slots onto the icon slot to set the icon.\n" ..
    "Right-click a text field to clear it.")

  local save_w = GuiGetTextDimensions(gui, "Save") + 9
  local cancel_w = GuiGetTextDimensions(gui, "Cancel") + 9
  local right = x + COLS * slot_width
  if ui.button(gui, new_id, right - save_w - cancel_w - 2, footer_y, "Cancel") then
    result = { action = "cancel" }
  end
  if ui.button(gui, new_id, right - save_w, footer_y, "Save") then
    local bp = state.bp
    bp.slots = collect_slots()
    if bp.name == "" then bp.name = "Unnamed" end
    result = { action = "save", bp = bp, index = state.index }
  end
  return result
end

return M
