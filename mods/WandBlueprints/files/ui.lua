-- Shared GUI helpers, mostly the same techniques Advanced Spell Inventory uses
dofile_once("data/scripts/debug/keycodes.lua")

local M = {}

local EZMouse
local EZWand

-- Distance of the panels from the right screen edge, keeps them clear of the HUD (health, mana, gold, perks)
M.PANEL_RIGHT_MARGIN = 90

-- Which text input currently receives typing, nil if none
M.focused_input = nil
local backspace_down_frame = 0
local typed_this_frame = ""

function M.init(ezmouse, ezwand)
  EZMouse = ezmouse
  EZWand = ezwand
end

function M.mouse_pos()
  return EZMouse.screen_x, EZMouse.screen_y
end

function M.play_sound(name)
  local cx, cy = GameGetCameraPos()
  GamePlaySound("data/audio/Desktop/ui.bank", "ui/" .. name, cx, cy)
end

-- Text button at an absolute position. Returns clicked, right_clicked, width
function M.button(gui, new_id, x, y, text, active)
  local w, h = GuiGetTextDimensions(gui, text)
  GuiImageNinePiece(gui, new_id(), x, y, w + 7, h + 2, 0, "data/debug/whitebox.png")
  local clicked, _, hovered = GuiGetPreviousWidgetInfo(gui)
  -- GuiGetPreviousWidgetInfo does not return right click for GuiImageNinePiece, so get it manually
  local right_clicked = hovered and InputIsMouseButtonJustDown(Mouse_right)
  GuiZSetForNextWidget(gui, 20 - 1)
  GuiImageNinePiece(gui, new_id(), x + 5, y + 2, w - 1, h - 4, 1, "mods/WandBlueprints/files/button_9piece" .. (active and "_active" or "") .. ".png")
  if hovered then
    GuiColorSetForNextWidget(gui, 0.95, 0.95, 0.7, 1)
  end
  GuiText(gui, x + 3, y + 1, text)
  return clicked, right_clicked, w + 9
end

-- Whether the mouse is inside a rectangle, using the same coordinates EZInventory uses for drag and drop
function M.is_mouse_inside(x, y, width, height)
  local mx, my = M.mouse_pos()
  return mx >= x and mx <= x + width and my >= y and my <= y + height
end

-- Panel background with border. Blocks mouse clicks from reaching the game while hovered.
-- Hover is a rectangle test, the widget's own hover is false while EZMouse draws a dragged spell over it.
function M.panel(gui, new_id, x, y, width, height)
  GuiZSetForNextWidget(gui, 20)
  GuiImageNinePiece(gui, new_id(), x, y, width, height, 1, "mods/WandBlueprints/files/container_9piece.png", "mods/WandBlueprints/files/container_9piece.png")
  -- The nine piece border is drawn a few pixels outside of the given rectangle
  local hovered = M.is_mouse_inside(x - 3, y - 3, width + 6, height + 6)
  if hovered then
    local mx, my = M.mouse_pos()
    GuiZSetForNextWidget(gui, 0)
    GuiImage(gui, new_id(), mx - 100, my - 100, "data/debug/whitebox.png", 0.0001, 10, 10)
  end
  return hovered
end

-- Noita's text inputs only receive typing while hovered. While one of ours is focused, an invisible input
-- follows the mouse and catches what is typed, which then gets appended to the focused input. Call once per frame.
function M.capture_typing(gui, new_id)
  typed_this_frame = ""
  if not M.focused_input then return end
  local mx, my = M.mouse_pos()
  GuiAnimateBegin(gui)
  GuiAnimateAlphaFadeIn(gui, new_id(), 0, 0, true)
  GuiBeginAutoBox(gui)
  GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
  GuiZSetForNextWidget(gui, -99999999999)
  GuiBeginScrollContainer(gui, new_id(), mx, my, 10, 10, false, 0, 0)
  GuiEndAutoBoxNinePiece(gui)
  GuiAnimateEnd(gui)
  -- The input itself has to be invisible too, otherwise its blinking cursor shows up at the mouse
  GuiAnimateBegin(gui)
  GuiAnimateAlphaFadeIn(gui, new_id(), 0, 0, true)
  typed_this_frame = GuiTextInput(gui, new_id(), 0, 0, "", 0, 8)
  GuiAnimateEnd(gui)
  GuiEndScrollContainer(gui)
end

-- Text input that can be focused with a click, unfocused by clicking elsewhere or Enter. Right-click clears it.
function M.text_input(gui, new_id, key, x, y, value, width, max_length)
  local is_focused = M.focused_input == key
  if is_focused then
    GuiColorSetForNextWidget(gui, 1, 1, 0.6, 1)
  end
  GuiTextInput(gui, new_id(), x, y, value, width, max_length)
  local _, _, hovered, input_x, input_y, input_w, input_h = GuiGetPreviousWidgetInfo(gui)
  local new_value = value
  if hovered and InputIsMouseButtonJustDown(Mouse_right) then
    new_value = ""
  end
  if is_focused then
    if #new_value + #typed_this_frame <= max_length then
      new_value = new_value .. typed_this_frame
    end
    if InputIsKeyJustDown(Key_BACKSPACE) then
      backspace_down_frame = GameGetFrameNum()
      new_value = new_value:gsub(".?$", "")
    elseif InputIsKeyDown(Key_BACKSPACE) and backspace_down_frame + 15 < GameGetFrameNum() and GameGetFrameNum() % 5 == 0 then
      new_value = new_value:gsub(".?$", "")
    end
  end
  -- The real input never has focus (typing goes through the hidden one), so draw a blinking cursor ourselves
  if is_focused and GameGetFrameNum() % 40 < 24 then
    local text_w = GuiGetTextDimensions(gui, new_value)
    local caret_x = math.min(input_x + 2 + text_w, input_x + input_w - 2)
    GuiZSetForNextWidget(gui, -1)
    GuiColorSetForNextWidget(gui, 1, 1, 0.6, 1)
    GuiImage(gui, new_id(), caret_x, input_y + 1, "data/debug/whitebox.png", 1, 1 / 20, (input_h - 2) / 20)
  end
  if InputIsMouseButtonJustDown(Mouse_left) then
    if hovered then
      M.focused_input = key
    elseif is_focused then
      M.focused_input = nil
    end
  elseif is_focused and InputIsKeyJustDown(Key_RETURN) then
    M.focused_input = nil
  end
  return new_value
end

-- Shortens text with "..." until it fits into max_width
function M.fit_text(gui, text, max_width)
  if GuiGetTextDimensions(gui, text) <= max_width then
    return text
  end
  while #text > 0 and GuiGetTextDimensions(gui, text .. "...") > max_width do
    text = text:sub(1, -2)
  end
  return text .. "..."
end

-- Spell tooltips: drawn invisibly once to measure them, then kept on screen
local tooltip_sizes = {}
local function fit_tooltip_to_screen(gui, x, y, width, height, slot_top, slot_height)
  local margin = 4
  local screen_width, screen_height = GuiGetScreenDimensions(gui)
  if slot_top + slot_height / 2 > screen_height / 2 then
    y = slot_top - 10 - height
  end
  y = math.max(margin, math.min(y, screen_height - height - margin))
  x = math.max(margin, math.min(x, screen_width - width - margin))
  return x, y
end

function M.spell_tooltip(gui, action_id, x, y, slot_top, slot_height, known)
  if not known then return end
  local size = tooltip_sizes[action_id]
  if not size then
    GuiAnimateBegin(gui)
    GuiIdPushString(gui, "WandBlueprints_tooltip_measure")
    GuiAnimateAlphaFadeIn(gui, 3, 0, 0, true)
    EZWand.RenderSpellTooltip(action_id, x, y, gui)
    local _, _, _, _, _, width, height = GuiGetPreviousWidgetInfo(gui)
    tooltip_sizes[action_id] = { width = width, height = height }
    GuiIdPop(gui)
    GuiAnimateEnd(gui)
    return
  end
  local tx, ty = fit_tooltip_to_screen(gui, x + 2 - size.width / 2, y, size.width, size.height, slot_top, slot_height)
  GuiIdPushString(gui, "WandBlueprints_tooltip")
  EZWand.RenderSpellTooltip(action_id, tx, ty, gui)
  GuiIdPop(gui)
end

-- Spell icon with its type background, not interactive
function M.spell_icon(gui, new_id, x, y, action_id, sprite, scale, z)
  scale = scale or 1
  z = z or 0
  GuiZSetForNextWidget(gui, z)
  GuiImage(gui, new_id(), x, y, EZWand.get_spell_bg(action_id), 1, scale, scale)
  GuiZSetForNextWidget(gui, z - 0.5)
  GuiImage(gui, new_id(), x + 2 * scale, y + 2 * scale, sprite, 1, scale, scale)
end

return M
