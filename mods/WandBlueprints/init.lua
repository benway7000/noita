dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/debug/keycodes.lua")
dofile_once("data/scripts/gun/gun_enums.lua")

-- Note: all mods' init.lua share one Lua state, so everything here is local to not clash with other mods
local lib_path = "mods/WandBlueprints/lib/EZInventory/"
dofile_once(lib_path .. "init.lua")(lib_path)
local EZInventory = dofile_once(lib_path .. "EZInventory.lua")
local EZMouse = dofile(lib_path .. "lib/EZMouse/EZMouse.lua")(lib_path .. "lib/EZMouse/")
local EZWand

local storage = dofile_once("mods/WandBlueprints/files/storage.lua")
local apply = dofile_once("mods/WandBlueprints/files/apply.lua")
local ui = dofile_once("mods/WandBlueprints/files/ui.lua")
local editor = dofile_once("mods/WandBlueprints/files/editor.lua")

ModLuaFileAppend("mods/mnee/bindings.lua", "mods/WandBlueprints/files/mnee.lua")

local MOD_ID = "WandBlueprints"
local NUM_HOTKEYS = 10
local ROW_HEIGHT = 24
local ROWS_PER_PAGE = 9
local CONFIRM_FRAMES = 180

local gui
local blueprints = storage.load()
local action_lookup = {}
local frame_player_spawned
local ready = false
local mnee_ready = false
local open = false
local list_page = 0
local active_category = ModSettingGet("WandBlueprints.active_category") or "all"
if active_category ~= "all" and storage.get_category(active_category).id ~= active_category then
  active_category = "all"
end
local tab_hovered = {}
local status_lines = {}
local confirm -- { action = "delete" | "overwrite", index, frame }
local pending_apply -- An apply waiting for Advanced Spell Inventory: { bp_name, result }
local dragging_button = false
local controls_enabled_last_frame = true
local typing_last_frame = false

local show_button = ModSettingGet(MOD_ID .. ".show_button")
local require_tinkering = ModSettingGet(MOD_ID .. ".require_tinkering")
local button_pos_x = tonumber(ModSettingGet(MOD_ID .. ".button_pos_x")) or 182
local button_pos_y = tonumber(ModSettingGet(MOD_ID .. ".button_pos_y")) or 41

function OnPausedChanged(is_paused, is_main_menu)
  if not is_paused then
    show_button = ModSettingGet(MOD_ID .. ".show_button")
    require_tinkering = ModSettingGet(MOD_ID .. ".require_tinkering")
    button_pos_x = tonumber(ModSettingGet(MOD_ID .. ".button_pos_x")) or 182
    button_pos_y = tonumber(ModSettingGet(MOD_ID .. ".button_pos_y")) or 41
    EZInventory.UpdateCustomScreenResolution()
    EZMouse.UpdateCustomScreenResolution()
  end
end

function OnPlayerSpawned(player)
  frame_player_spawned = GameGetFrameNum()
end

local function set_status(lines)
  status_lines = lines
end

local function notify(lines)
  for i, line in ipairs(lines) do
    GamePrint(line)
  end
  set_status(lines)
end

local function deny(lines)
  ui.play_sound("button_denied")
  notify(lines)
end

local function save_blueprints()
  storage.save(blueprints)
end

-- Only one blueprint can own a hotkey, the one saved last wins
local function claim_hotkey(owner)
  if owner.hotkey == 0 then return end
  for i, bp in ipairs(blueprints) do
    if bp ~= owner and bp.hotkey == owner.hotkey then
      bp.hotkey = 0
    end
  end
end

local function report_apply(bp_name, result, note)
  local missing = apply.missing_action_ids(result)
  local overflow = result.overflow
  local lines = {}
  if #missing == 0 and #overflow == 0 then
    table.insert(lines, "Blueprint " .. bp_name .. " applied")
  else
    if #missing > 0 then
      table.insert(lines, "Blueprint " .. bp_name .. " applied with missing spells:")
      for i, line in ipairs(apply.group_names(missing)) do
        table.insert(lines, line)
      end
    end
    if #overflow > 0 then
      table.insert(lines, (#missing > 0 and "" or ("Blueprint " .. bp_name .. " applied, but ")) .. "didn't fit (wand capacity):")
      for i, line in ipairs(apply.group_names(overflow)) do
        table.insert(lines, line)
      end
    end
  end
  if note then
    table.insert(lines, note)
  end
  ui.play_sound("item_move_success")
  notify(lines)
end

local function apply_blueprint(bp)
  if pending_apply then
    deny({ "Still applying blueprint " .. pending_apply.bp_name })
    return
  end
  local wand_id = apply.get_held_wand()
  if not wand_id then
    deny({ "Blueprint " .. bp.name .. ": no wand held" })
    return
  end
  if require_tinkering and not apply.can_edit_wands() then
    deny({ "Blueprint " .. bp.name .. ": can only be applied where wand tinkering is possible" })
    return
  end
  local result = apply.apply(bp, wand_id)
  if apply.needs_asi(result) then
    -- Finished in update_pending_apply once ASI has done its part
    apply.send_asi_request(result)
    pending_apply = { bp_name = bp.name, result = result }
  else
    report_apply(bp.name, result)
  end
end

local function update_pending_apply()
  if not pending_apply then return end
  local done = apply.poll_asi_response(pending_apply.result)
  if done then
    report_apply(pending_apply.bp_name, pending_apply.result)
    pending_apply = nil
  elseif done == nil then
    apply.fallback(pending_apply.result)
    report_apply(pending_apply.bp_name, pending_apply.result, "(Advanced Spell Inventory didn't respond, its spells weren't used)")
    pending_apply = nil
  end
end

local function new_blueprint_name()
  local n = #blueprints + 1
  local taken = {}
  for i, bp in ipairs(blueprints) do taken[bp.name] = true end
  while taken["Blueprint " .. n] do n = n + 1 end
  return "Blueprint " .. n
end

local function hotkey_text(bp)
  if bp.hotkey == 0 then return "" end
  local keys
  if mnee_ready then
    local ok, result = pcall(mnee.get_binding_keys, MOD_ID, "hotkey_" .. bp.hotkey, true)
    if ok then keys = result end
  end
  return "[" .. bp.hotkey .. (keys and (": " .. keys) or "") .. "]"
end

-- Shows the note and spells of a hovered blueprint next to the panel
local function render_blueprint_preview(new_id, bp, right_x, y)
  local cols = 10
  local icon_size = 16
  local scale = icon_size / 20
  local num_rows = math.max(1, math.ceil(#bp.slots / cols))
  local note_h = bp.note ~= "" and 11 or 0
  local width = cols * icon_size + 4
  local height = note_h + num_rows * icon_size + 4
  local x = right_x - width - 10
  GuiZSetForNextWidget(gui, -50)
  GuiImageNinePiece(gui, new_id(), x, y, width, height, 1, "mods/WandBlueprints/files/container_9piece.png")
  if bp.note ~= "" then
    GuiZSetForNextWidget(gui, -51)
    GuiText(gui, x + 2, y + 1, ui.fit_text(gui, bp.note, width - 4))
  end
  for i, action_id in ipairs(bp.slots) do
    local ix = x + 2 + ((i - 1) % cols) * icon_size
    local iy = y + 2 + note_h + math.floor((i - 1) / cols) * icon_size
    if action_id ~= "" then
      local action = action_lookup[action_id]
      ui.spell_icon(gui, new_id, ix, iy, action_id, action and action.sprite or "data/ui_gfx/gun_actions/unidentified.png", scale, -52)
    else
      GuiZSetForNextWidget(gui, -52)
      GuiImage(gui, new_id(), ix, iy, "data/ui_gfx/inventory/full_inventory_box.png", 0.6, scale, scale)
    end
  end
end

local function is_confirming(action, index)
  return confirm and confirm.action == action and confirm.index == index and GameGetFrameNum() - confirm.frame < CONFIRM_FRAMES
end

-- Indices into blueprints of the ones shown in the active tab
local function get_visible_indices()
  local indices = {}
  for i, bp in ipairs(blueprints) do
    if active_category == "all" or bp.category == active_category then
      table.insert(indices, i)
    end
  end
  return indices
end

local function set_active_category(id)
  if id ~= active_category then
    active_category = id
    list_page = 0
    confirm = nil
    ModSettingSet(MOD_ID .. ".active_category", id)
  end
end

-- Vertical tabs on the left side of the panel, in the style of Inventory Bags
local function render_tabs(new_id, panel_x, panel_y)
  local tabs = { { id = "all", name = "All", sprite = "mods/WandBlueprints/files/spell_type_all.png", sprite_scale = 0.5 } }
  for i, category in ipairs(storage.CATEGORIES) do
    local action = category.icon_action and action_lookup[category.icon_action]
    table.insert(tabs, { id = category.id, name = category.name, sprite = action and action.sprite, sprite_scale = 0.5 })
  end
  local counts = { all = #blueprints }
  for i, bp in ipairs(blueprints) do
    counts[bp.category] = (counts[bp.category] or 0) + 1
  end
  local tab_x = panel_x - 13
  for i, tab in ipairs(tabs) do
    local tab_y = panel_y + 5 + (i - 1) * 17
    local active = tab.id == active_category
    local image = "mods/WandBlueprints/files/tab_left_empty" .. (active and "_active" or (tab_hovered[i] and "_hover" or "")) .. ".png"
    GuiZSetForNextWidget(gui, 21)
    if GuiImageButton(gui, new_id(), tab_x, tab_y, "", image) then
      set_active_category(tab.id)
    end
    local _, _, hovered = GuiGetPreviousWidgetInfo(gui)
    tab_hovered[i] = hovered
    GuiTooltip(gui, ("%s (%d)"):format(tab.name, counts[tab.id] or 0), "")
    local alpha = active and 1 or 0.6
    if tab.sprite then
      local w, h = GuiGetImageDimensions(gui, tab.sprite, tab.sprite_scale)
      GuiZSetForNextWidget(gui, 19.5)
      GuiImage(gui, new_id(), tab_x + 3 + (8 - w) / 2, tab_y + 4 + (8 - h) / 2, tab.sprite, alpha, tab.sprite_scale, tab.sprite_scale)
    else
      GuiZSetForNextWidget(gui, 19.5)
      GuiColorSetForNextWidget(gui, 1, 1, 1, alpha)
      GuiText(gui, tab_x + 5, tab_y + 3, "?")
    end
  end
end

local function render_list(new_id)
  local screen_width = GuiGetScreenDimensions(gui)
  local panel_w = 252
  local panel_x = screen_width - panel_w - ui.PANEL_RIGHT_MARGIN
  local panel_y = 46
  local x, y = panel_x + 6, panel_y + 5
  local visible_indices = get_visible_indices()
  local num_pages = math.max(1, math.ceil(#visible_indices / ROWS_PER_PAGE))
  list_page = math.max(0, math.min(list_page, num_pages - 1))
  local list_y = y + 14
  local footer_y = list_y + ROWS_PER_PAGE * ROW_HEIGHT + 2
  local status_y = footer_y + 14
  local panel_h = status_y + #status_lines * 10 + 2 - panel_y
  ui.panel(gui, new_id, panel_x, panel_y, panel_w, panel_h)
  render_tabs(new_id, panel_x, panel_y)
  -- New blueprints go into the category of the open tab
  local new_category = active_category ~= "all" and active_category or nil

  -- Header
  local bx = x
  local clicked, _, w = ui.button(gui, new_id, bx, y - 1, "New from held wand")
  if clicked then
    local wand_id = apply.get_held_wand()
    if wand_id then
      set_status({})
      editor.open(gui, storage.new_blueprint(new_blueprint_name(), apply.capture_from_wand(wand_id), new_category), nil)
    else
      deny({ "No wand held" })
    end
  end
  bx = bx + w
  local clicked, _, w = ui.button(gui, new_id, bx, y - 1, "New empty")
  if clicked then
    set_status({})
    local slots = {}
    for i = 1, 10 do slots[i] = "" end
    editor.open(gui, storage.new_blueprint(new_blueprint_name(), slots, new_category), nil)
  end

  if #blueprints == 0 then
    GuiColorSetForNextWidget(gui, 0.7, 0.7, 0.7, 1)
    GuiText(gui, x, list_y + 2, "No blueprints yet.")
    GuiColorSetForNextWidget(gui, 0.7, 0.7, 0.7, 1)
    GuiText(gui, x, list_y + 12, "Hold a wand and click 'New from held wand'.")
  elseif #visible_indices == 0 then
    GuiColorSetForNextWidget(gui, 0.7, 0.7, 0.7, 1)
    GuiText(gui, x, list_y + 2, "No blueprints in this category.")
  end

  local hovered_bp, hovered_y
  for row = 1, ROWS_PER_PAGE do
    local index = visible_indices[list_page * ROWS_PER_PAGE + row]
    local bp = index and blueprints[index]
    if not bp then break end
    local ry = list_y + (row - 1) * ROW_HEIGHT
    local action = action_lookup[bp.icon]
    if bp.icon ~= "" then
      ui.spell_icon(gui, new_id, x, ry, bp.icon, action and action.sprite or "data/ui_gfx/gun_actions/unidentified.png", 1, 1)
    else
      GuiZSetForNextWidget(gui, 1)
      GuiImage(gui, new_id(), x, ry, "data/ui_gfx/inventory/full_inventory_box.png", 1, 1, 1)
    end
    local _, _, icon_hovered = GuiGetPreviousWidgetInfo(gui)

    local hotkey = hotkey_text(bp)
    local hotkey_w = hotkey ~= "" and GuiGetTextDimensions(gui, hotkey) or 0
    GuiText(gui, x + 23, ry, ui.fit_text(gui, bp.name, panel_w - 36 - hotkey_w))
    local _, _, name_hovered = GuiGetPreviousWidgetInfo(gui)
    if hotkey ~= "" then
      GuiColorSetForNextWidget(gui, 0.6, 0.8, 1, 1)
      GuiText(gui, x + panel_w - 12 - hotkey_w, ry, hotkey)
    end
    if icon_hovered or name_hovered then
      hovered_bp, hovered_y = bp, ry
    end

    local bx = x + 21
    local by = ry + 10
    local clicked, _, w = ui.button(gui, new_id, bx, by, "Apply")
    if clicked then
      confirm = nil
      apply_blueprint(bp)
    end
    bx = bx + w
    local clicked, _, w = ui.button(gui, new_id, bx, by, "Edit")
    if clicked then
      confirm = nil
      set_status({})
      editor.open(gui, storage.copy(bp), index)
    end
    bx = bx + w
    local overwriting = is_confirming("overwrite", index)
    local clicked, _, w = ui.button(gui, new_id, bx, by, overwriting and "Sure?" or "Overwrite", overwriting)
    GuiTooltip(gui, "Overwrite the spells with the ones on the held wand", "Click twice to confirm")
    if clicked then
      if overwriting then
        confirm = nil
        local wand_id = apply.get_held_wand()
        if wand_id then
          bp.slots = apply.capture_from_wand(wand_id)
          save_blueprints()
          notify({ "Blueprint " .. bp.name .. " overwritten" })
        else
          deny({ "No wand held" })
        end
      else
        confirm = { action = "overwrite", index = index, frame = GameGetFrameNum() }
      end
    end
    bx = bx + w
    local deleting = is_confirming("delete", index)
    local clicked = ui.button(gui, new_id, bx, by, deleting and "Sure?" or "Delete", deleting)
    GuiTooltip(gui, "Delete this blueprint", "Click twice to confirm")
    if clicked then
      if deleting then
        confirm = nil
        table.remove(blueprints, index)
        save_blueprints()
        notify({ "Blueprint " .. bp.name .. " deleted" })
      else
        confirm = { action = "delete", index = index, frame = GameGetFrameNum() }
      end
    end
  end

  if hovered_bp then
    render_blueprint_preview(new_id, hovered_bp, panel_x - 14, hovered_y)
  end

  -- Footer: pages
  if num_pages > 1 then
    local fx = x
    local clicked, _, w = ui.button(gui, new_id, fx, footer_y, "<")
    if clicked and list_page > 0 then list_page = list_page - 1 end
    fx = fx + w
    local text = ("%d/%d"):format(list_page + 1, num_pages)
    GuiText(gui, fx + 1, footer_y + 1, text)
    fx = fx + GuiGetTextDimensions(gui, text) + 4
    local clicked = ui.button(gui, new_id, fx, footer_y, ">")
    if clicked and list_page < num_pages - 1 then list_page = list_page + 1 end
  end

  for i, line in ipairs(status_lines) do
    GuiColorSetForNextWidget(gui, 0.9, 0.9, 0.6, 1)
    GuiText(gui, x, status_y + (i - 1) * 10, ui.fit_text(gui, line, panel_w - 12))
  end
end

local function handle_editor_result(result)
  if not result then return end
  if result.action == "save" then
    local bp = result.bp
    local index = result.index
    if index and blueprints[index] then
      blueprints[index] = bp
    else
      table.insert(blueprints, bp)
      index = #blueprints
    end
    -- Show the saved blueprint: switch to its tab if the open one doesn't contain it, and to its page
    if active_category ~= "all" and active_category ~= bp.category then
      set_active_category(bp.category)
    end
    for position, i in ipairs(get_visible_indices()) do
      if i == index then
        list_page = math.floor((position - 1) / ROWS_PER_PAGE)
      end
    end
    claim_hotkey(bp)
    save_blueprints()
    notify({ "Blueprint " .. bp.name .. " saved" })
  end
  editor.close()
end

-- While typing, disable the player's controls and all M-Nee bindings so keys don't do anything else
local function update_typing_lock(player, typing)
  local controls_enabled = not typing
  if controls_enabled ~= controls_enabled_last_frame then
    local controls_comp = EntityGetFirstComponentIncludingDisabled(player, "ControlsComponent")
    if controls_comp then
      EntityRemoveComponent(player, controls_comp)
      controls_comp = EntityAddComponent2(player, "ControlsComponent")
      ComponentSetValue2(controls_comp, "enabled", controls_enabled)
    end
  end
  controls_enabled_last_frame = controls_enabled
  -- M-Nee's service mode mutes every mod's M-Nee bindings (e.g. Cartographer's map key) while typing here
  if mnee_ready and typing ~= typing_last_frame then
    if typing then
      GameAddFlagRun(mnee.SERV_MODE)
    else
      GameRemoveFlagRun(mnee.SERV_MODE)
    end
  end
  typing_last_frame = typing
end

local function handle_hotkeys()
  if not mnee_ready or editor.is_typing() then return end
  if mnee.mnin_bind(MOD_ID, "toggle", true) then
    open = not open
    ui.play_sound("inventory_" .. (open and "open" or "close"))
  end
  for k = 1, NUM_HOTKEYS do
    if mnee.mnin_bind(MOD_ID, "hotkey_" .. k, true) then
      for i, bp in ipairs(blueprints) do
        if bp.hotkey == k then
          apply_blueprint(bp)
          break
        end
      end
    end
  end
end

function OnWorldPostUpdate()
  -- Start high so ids never collide with EZInventory's own widget ids on the same gui
  local id = 100000
  local function new_id()
    id = id + 1
    return id
  end

  gui = gui or GuiCreate()
  GuiStartFrame(gui)
  EZMouse.update(gui)

  -- Run this 1 frame after the player has spawned, so other mods had time to append to gun_actions.lua
  if frame_player_spawned and frame_player_spawned == GameGetFrameNum() - 1 then
    -- M-Nee is required; if it's missing, say so once and leave hotkeys off rather than erroring
    if ModIsEnabled("mnee") then
      dofile_once("mods/mnee/lib.lua")
      mnee_ready = true
    else
      GamePrint("Wand Blueprints: M-Nee is not enabled, hotkeys will not work")
    end
    dofile_once("data/scripts/gun/gun_actions.lua")
    EZWand = EZWand or dofile_once("mods/WandBlueprints/lib/EZWand/EZWand.lua")
    local all_actions = {}
    for i, action in ipairs(actions) do
      action_lookup[action.id] = action
      table.insert(all_actions, action)
    end
    apply.init(EZWand, action_lookup)
    ui.init(EZMouse, EZWand)
    editor.init(EZInventory, EZWand, ui, apply, action_lookup, all_actions)
    blueprints = storage.load()
    ready = true
  end

  GuiOptionsAdd(gui, GUI_OPTION.HandleDoubleClickAsClick)
  GuiOptionsAdd(gui, GUI_OPTION.ClickCancelsDoubleClick)
  GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)

  local player = EntityGetWithTag("player_unit")[1]
  local inventory_open = GameIsInventoryOpen()
  local visible = ready and open and player ~= nil and not inventory_open

  EZInventory.Update(gui, visible and editor.is_open())

  if not ready or not player then
    return
  end

  update_pending_apply()
  handle_hotkeys()

  -- Toggle button, right-click drag to move it
  if show_button and not inventory_open then
    local clicked = GuiImageButton(gui, new_id(), button_pos_x, button_pos_y, "", "mods/WandBlueprints/files/gui_button.png")
    local _, _, hovered = GuiGetPreviousWidgetInfo(gui)
    GuiTooltip(gui, "Wand Blueprints", "Right-click and drag to move")
    if hovered and InputIsMouseButtonDown(Mouse_right) then
      dragging_button = true
    end
    if clicked then
      open = not open
      ui.play_sound("inventory_" .. (open and "open" or "close"))
    end
  end
  if dragging_button then
    local mx, my = ui.mouse_pos()
    button_pos_x, button_pos_y = mx - 8, my - 8
    if not InputIsMouseButtonDown(Mouse_right) then
      dragging_button = false
      ModSettingSet(MOD_ID .. ".button_pos_x", button_pos_x)
      ModSettingSet(MOD_ID .. ".button_pos_y", button_pos_y)
    end
  end

  if visible then
    if editor.is_open() then
      handle_editor_result(editor.update(gui, new_id, notify))
    else
      render_list(new_id)
    end
  end

  if not visible then
    ui.focused_input = nil
  end
  update_typing_lock(player, visible and editor.is_typing())
end
