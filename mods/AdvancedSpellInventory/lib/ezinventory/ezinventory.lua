local EZMouse = dofile("%PATH%lib/EZMouse/EZMouse.lua")("%PATH%lib/EZMouse/")

local function is_inside_rect(x, y, rect_x, rect_y, width, height)
	return not ((x < rect_x) or (x > rect_x + width) or (y < rect_y) or (y > rect_y + height))
end

local function get_direction( x1, y1, x2, y2 )
	return math.atan2( ( y2 - y1 ), ( x2 - x1 ) )
end

local function get_distance( x1, y1, x2, y2 )
	local result = math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 )
	return result
end

local sounds_enabled = true
local animations_enabled = false
local animation_speed = 0.5
local content_being_dragged = nil
local slot_instances = {}
-- The privates should be read-only from outside
local slot_privates = setmetatable({}, { __mode = "k" })
-- This is indexed by content
local widgets = setmetatable({}, { __mode = "k" })
local extra_info = {}
local widget_extra_info = setmetatable({}, { __mode = "k" })

local Slot__mt = {}
Slot__mt.__index = Slot__mt

local last_frame_sound_played = 0
local function play_ui_sound(name)
  local frame_num = GameGetFrameNum()
  if not sounds_enabled or last_frame_sound_played == frame_num then
    return
  end
  -- Don't play multiple sounds in one frame, the logic for this is easier than
  -- coordinating which sound should take precedence, like when playing two move sounds when swapping
  last_frame_sound_played = frame_num
  local cx, cy = GameGetCameraPos()
  -- play_ui_sound("item_switch_places")  -- when swapping
  -- play_ui_sound("item_remove") -- when swapping
  -- play_ui_sound("item_move_success") -- when moving, not swapping
  GamePlaySound("data/audio/Desktop/ui.bank", "ui/" .. name, cx, cy)
end

local function slot_is_hovered(slot)
  return is_inside_rect(EZMouse.screen_x, EZMouse.screen_y, slot.x, slot.y, slot.width, slot.height)
end

local function fire_event(slot, event_name, event_args)
  for i, listener in ipairs(slot_privates[slot].event_listeners[event_name]) do
    listener(slot, event_args)
  end
end

local animations = {}
-- Takes a function that takes gui and new_id as argument and should return true when the animation is finished
local function add_animation(func)
  table.insert(animations, func)
end

local function update_animations(gui, new_id)
  -- Traverse backwards so we can remove while iterating
  for i=#animations, 1, -1 do
    local func = animations[i]
    if func(gui, new_id) then
      table.remove(animations, i)
    end
  end
end

local function update(gui, visible)
  if visible == nil then
    visible = true
  end

  content_being_dragged = nil
  EZMouse.update(gui, visible)

  local id = 1
  local function new_id()
    id = id + 1
    return id
  end

  -- if GameGetFrameNum() % 60 == 0 then
  --   local count = 0
  --   for k, v in pairs(widgets) do
  --     count = count + 1
  --   end
  --   print("#Widgets: ", count)
  -- end

  update_animations(gui, new_id)

  for i, slot in ipairs(slot_instances) do
    -- if widgets[slot_privates[slot].content] then
    --   widgets[slot_privates[slot].content]:DebugDraw(gui)
    -- end
    slot_privates[slot].content_cleared_this_frame = false
    slot_privates[slot].hovered = widgets[slot_privates[slot].content] and widgets[slot_privates[slot].content].hovered or false
    slot_privates[slot].dragging = widgets[slot_privates[slot].content] and widgets[slot_privates[slot].content].dragging or false
    if slot_privates[slot].content and widgets[slot_privates[slot].content].dragging then
      content_being_dragged = slot_privates[slot].content
    end
  end
  -- Do custom PositionTween when letting go of item and it snaps back
  for slot, values in pairs(extra_info) do
    local dir = get_direction(values.target_x, values.target_y, values.x, values.y)
    local dist = get_distance(values.target_x, values.target_y, values.x, values.y)
    values.x = values.x - math.cos(dir) * dist * animation_speed
    values.y = values.y - math.sin(dir) * dist * animation_speed
    if dist < 1 then
      values.x = values.target_x
      values.y = values.target_y
      extra_info[slot] = nil
    end
  end
  if visible then
    for i, slot in ipairs(slot_instances) do
      slot:Render(gui, new_id)
    end
  end
end

function Slot__mt:Destroy()
  error("destroy", 2)
  if widgets[slot_privates[self].content] then
    widgets[slot_privates[self].content]:Destroy()
    widgets[slot_privates[self].content] = nil
  end
  for i=#slot_instances, 1, -1 do
    if slot_instances[i] == self then
      table.remove(slot_instances, i)
    end
  end
end

function Slot__mt:AddEventListener(event_name, event_listener)
  if not slot_privates[self].event_listeners[event_name] then
    error("Event with name '" .. event_name .. "' doesn't exist.", 2)
  end
  table.insert(slot_privates[self].event_listeners[event_name], event_listener)
  return event_listener
end

function Slot__mt:RemoveEventListener(event_name, event_listener)
  if not slot_privates[self].event_listeners[event_name] then
    error("Event with name '" .. event_name .. "' doesn't exist.", 2)
  end
  local was_removed = false
  for i=#slot_privates[self].event_listeners[event_name], 1, -1 do
    if slot_privates[self].event_listeners[event_name][i] == event_listener then
      table.remove(slot_privates[self].event_listeners[event_name], i)
      was_removed = true
      break
    end
  end
  return was_removed
end

function Slot__mt:Render(gui, new_id)
  local slot_sprite_w, slot_sprite_h = GuiGetImageDimensions(gui, "data/ui_gfx/inventory/full_inventory_box.png", 1)
  local scale = self.width / slot_sprite_w
  if slot_privates[self].content and self.visible then
    local sprite_w, sprite_h = GuiGetImageDimensions(gui, slot_privates[self].content.sprite)
    -- local offset_x, offset_y = 2 * scale, 2 * scale --  (difference between sprite_size and slot_size) / 2
    local offset_x, offset_y = (self.width - sprite_w) / 2 * scale, (self.height - sprite_h) / 2 * scale --  (difference between sprite_size and slot_size) / 2
    -- Make content sprite slightly bigger when it's being hovered
    if widgets[slot_privates[self].content].hovered and not widgets[slot_privates[self].content].dragging then
      -- scale = scale * 1.2
      -- offset_x = offset_x - 1.5 * scale
      -- offset_y = offset_y - 1.5 * scale
      if not extra_info[self] and slot_privates[self].content.tooltip_func then
        GuiIdPushString(gui, "EZInventory_tooltip")
        slot_privates[self].content.tooltip_func(gui, self.x, self.y + self.height + 10, self.z - 2000, slot_privates[self].content)
        GuiIdPop(gui)
      end
    end
    local x = widgets[slot_privates[self].content].x
    local y = widgets[slot_privates[self].content].y
    if extra_info[self] then
      x = extra_info[self].x
      y = extra_info[self].y
    end
    -- If it's being dragged, render it on top of all the other contents
    local z = self.z - 1
    local rot = 0
    if widgets[slot_privates[self].content].dragging then
      z = z - 500
    elseif animations_enabled then
      rot = math.sin(GameGetFrameNum() / 6) * 0.05
    end
    GuiZSetForNextWidget(gui, z - 1)
    GuiImage(gui, new_id(), x - (sprite_w - self.width) / 2,  y - (sprite_h - self.height) / 2, slot_privates[self].content.sprite, 1, 1, 1, rot)

    local stack_size = (slot_privates[self].content.stack_size or 1)
    if (slot_privates[self].content.max_stack_size or 1) > 1 and stack_size > 1 then
      GuiZSetForNextWidget(gui, z - 2)
      GuiColorSetForNextWidget(gui, 0.9, 0.9, 0.9, 1)
      local text_width, text_height = GuiGetTextDimensions(gui, tostring(stack_size), 1, 1, "data/fonts/font_small_numbers.xml", true)
      GuiText(gui, x + self.width - text_width - 2, y + self.height - text_height - 2, tostring(stack_size), 1, "data/fonts/font_small_numbers.xml", true)
    end

    if slot_privates[self].content.render_after then
      slot_privates[self].content:render_after(self, gui, new_id, x, y, z, scale)
    end
    -- widgets[slot_privates[self].content]:DebugDraw(gui)
  end
  local background_sprite = slot_privates[self].background_sprite
  -- Highlight slot if something is being dragged and the slot being hovered does not contain an item, or it's the same slot the item is being dragged from
  if content_being_dragged and slot_is_hovered(self) and (not slot_privates[self].content or (slot_privates[self].content == content_being_dragged)) then
    background_sprite = slot_privates[self].background_sprite_highlight
  end
  GuiZSetForNextWidget(gui, self.z)
  GuiImage(gui, new_id(), self.x, self.y, background_sprite, 1, scale, scale)
end

function Slot__mt:ClearContent()
  local content = slot_privates[self].content
  if content then
    widget_extra_info[content].drag_start_handler = nil
    widget_extra_info[content].drag_end_handler = nil
    widget_extra_info[content].shift_click_handler = nil
    widgets[content]:Destroy()
    widgets[content] = nil
    slot_privates[self].content = nil
    slot_privates[self].content_cleared_this_frame = true
  end
end

-- Splits a stack, content_cpy_func should return a copy of the content
function Slot__mt:SplitContent(target_slot, amount)
  local self_content = slot_privates[self].content
  -- local target_content = slot_privates[target_slot].content
  if (self_content.stack_size or 1) <= amount then
    error("Can't split, not enough amount", 2)
  end
  self_content.stack_size = self_content.stack_size - amount
  local content_copy = self_content:clone()-- content_cpy_func(self_content)
  content_copy.stack_size = amount
  extra_info[target_slot] = {
    target_x = target_slot.x,
    target_y = target_slot.y,
    x = widgets[self_content].x,
    y = widgets[self_content].y,
  }
  target_slot:SetContent(content_copy)
  play_ui_sound("item_move_success")
  fire_event(self, "move_content", { content = self_content, target = target_slot, split = true })
end

-- Moves content from one slot to another, if the other slot is occupied, swaps contents
function Slot__mt:MoveContent(target_slot, skip_check)
  -- print(("MoveContent (%s[%s] -> %s[%s])"):format(self.z, slot_privates[self].content, target_slot.z, slot_privates[target_slot].content))
  if not self.content then
    error("Can't move content, source slot is empty.", 2)
  end
  local target_content = slot_privates[target_slot].content
  -- First save our content, then clear current slots content,
  -- move that into the other content and if that slot already has content, move that into this one
  local self_content = slot_privates[self].content
  -- slot_privates[self].content = nil

  -- Need to check this before resetting content
  local can_stack = self:CanStackWith(target_slot)
  if can_stack then
    target_content.stack_size = (target_content.stack_size or 1) + (self_content.stack_size or 1)
    play_ui_sound("item_move_success")
    -- Capture the start values in a closure, to be used in the animation function
    local pos_x, pos_y = widgets[self_content].x, widgets[self_content].y
    local target_x, target_y = target_slot.x, target_slot.y
    local img = self_content.sprite
    local scale = self.width / 20
    local offset_x, offset_y = 2 * scale, 2 * scale
    add_animation(function(gui, new_id)
      local dir = get_direction(target_x, target_y, pos_x, pos_y)
      local dist = get_distance(target_x, target_y, pos_x, pos_y)
      pos_x = pos_x - math.cos(dir) * dist * animation_speed
      pos_y = pos_y - math.sin(dir) * dist * animation_speed
      if dist < 1 then
        return true
      else
        local z = self.z
        GuiZSetForNextWidget(gui, z - 1)
        GuiImage(gui, new_id(), pos_x + offset_x, pos_y + offset_y, img, 1, scale, scale)
        if self_content.render_after then
          self_content:render_after(self, gui, new_id, pos_x + offset_x, pos_y + offset_y, z, scale)
        end
        return false
      end
    end)
    -- Need to set it again otherwise ClearContent doesn't work, this part could be designed better...
    slot_privates[self].content = self_content
    self:ClearContent()
    fire_event(self, "move_content", { content = self_content, target = target_slot, stack_moved = true })
    return
  end

  -- If this can't be moved onto a stack, can it even move there at all?
  if not skip_check and (self.data.move_check and not self.data.move_check(self, target_slot)) then
    return "not moved"
  end
  -- If we can't stack, and we could move there check if there is already something in the target slot
  -- because then we would have to swap
  if target_content then
    -- We can only swap if the target content can even move into ours
    if not skip_check and target_slot.data.move_check and not target_slot.data.move_check(target_slot, self) then
      return "not moved"
    end
  end

  -- If we can't even fit our stack size into target slot, split instead of moving
  local max_target_stack_size = target_slot.data.get_max_stack_size(self, self_content)
  -- TODO: I don't think this works properly
  if max_target_stack_size < self_content.stack_size then
    self:SplitContent(target_slot, max_target_stack_size)
    return "split"
  else
    -- Clear it like this instead of ClearContent because we don't want to destroy the widgets, we need to reuse them
    slot_privates[self].content = nil
    if target_content then
      -- Swap
      play_ui_sound("item_switch_places")
      target_slot:MoveContent(self)
    end

    extra_info[target_slot] = {
      target_x = target_slot.x,
      target_y = target_slot.y,
      x = widgets[self_content].x,
      y = widgets[self_content].y,
    }

    play_ui_sound("item_move_success")
    -- Need to do this after storing extra info because SetContent changes widget.x and y
    target_slot:SetContent(self_content)
    fire_event(self, "move_content", { content = self_content, target = target_slot })
  end
end

function Slot__mt:__index(key)
  if key == "content" or key == "hovered" or key == "dragging" then
    return slot_privates[self][key]
  else
    -- local x = rawget(self, key)
    -- print('key (' .. tostring(key) .. ':'.. type(key) .. ')')
    -- print('x (' .. tostring(x) .. ':'.. type(x) .. ')')
    return Slot__mt[key] or rawget(self, key)
  end
end

function Slot__mt:__newindex(key, value)
  -- print("new index: ", key, tostring(value))
  if key == "draggable" then
    for i, widget in pairs(widgets) do
      -- widget.enabled = value
      -- print("Enabled: ", tostring(value))
    end
  end
  if key == "enabled" then
    if self.content then
      widgets[self.content].draggable = value
    end
  end
  if key == "hovered" then
    error("Can't set read-only property '" .. key .. "'", 2)
  end
  slot_privates[self][key] = value
end

function Slot__mt:SetContent(content, dont_fire_event)
  if type(content) ~= "table" then
    error("Content cannot be empty, to clear the content use ClearContent instead", 2)
  end
  if slot_privates[self].content then
    self:ClearContent()
  end
  slot_privates[self].content = content
  local function drag_start_handler(widget, event)
    extra_info[self] = nil
  end
  local function drag_end_handler(widget, event)
    -- Check if we're moving it onto another slot
    local was_moved_to_another_slot = false
    local was_moved_to_self = false
    for i, target_slot in ipairs(slot_instances) do
      if slot_is_hovered(target_slot) then
        if target_slot ~= self then
          -- Check if we even can move there and if not, stay in its own slot and do nothing
          local result = self:MoveContent(target_slot)
          if result == "not moved" or result == "split" then
            was_moved_to_self = true
            break
          end
          was_moved_to_another_slot = true
        else
          was_moved_to_self = true
        end
        break
      end
    end
    -- If it wasn't dropped onto another slot, make it tween back to its original place
    if not was_moved_to_another_slot or was_moved_to_self then
      extra_info[self] = {
        target_x = event.start_x,
        target_y = event.start_y,
        x = widget.x,
        y = widget.y,
      }
      widget.x = event.start_x
      widget.y = event.start_y
      if not was_moved_to_self then
        fire_event(self, "drop_content", { content = content })
        if slot_privates[self].content_cleared_this_frame then
          return
        end
      end
    end
  end
  local function shift_click_handler(widget, event)
    fire_event(self, "shift_click", event)
  end
  if not widgets[content] then
    widgets[content] = EZMouse.Widget({
      x = self.x,
      y = self.y,
      z = self.z - 1000,
      width = self.width,
      height = self.height,
      draggable = true, --not InputIsKeyDown(Key_LSHIFT), --true,
      enabled = true,
      drag_anchor = "top_left",
      constraints = { left = 0, top = 0, right = 999, bottom = 999 } -- TODO: Fill constraints with screen width and height
    })
  else
    widgets[content].x = self.x
    widgets[content].y = self.y
    widgets[content].z = self.z
  end
  widget_extra_info[content] = widget_extra_info[content] or {}
  if widget_extra_info[content].drag_start_handler then
    widgets[content]:RemoveEventListener("drag_start", widget_extra_info[content].drag_start_handler)
  end
  if widget_extra_info[content].drag_end_handler then
    widgets[content]:RemoveEventListener("drag_end", widget_extra_info[content].drag_end_handler)
  end
  if widget_extra_info[content].shift_click_handler then
    widgets[content]:RemoveEventListener("shift_click", widget_extra_info[content].shift_click_handler)
  end
  widgets[content]:AddEventListener("drag_start", drag_start_handler)
  widgets[content]:AddEventListener("drag_end", drag_end_handler)
  widgets[content]:AddEventListener("shift_click", shift_click_handler)
  widget_extra_info[content].drag_start_handler = drag_start_handler
  widget_extra_info[content].drag_end_handler = drag_end_handler
  widget_extra_info[content].shift_click_handler = shift_click_handler
  if not dont_fire_event then
    fire_event(self, "set_content", { content = content })
  end
end

function Slot__mt:CanStackWith(target_slot)
  local self_content = slot_privates[self].content
  local target_content = slot_privates[target_slot].content
  if not self_content or not target_content then
    return false
  end
  if not target_content.stackable_with then
    error("content has no 'stackable_with' function defined", 2)
  end
  if target_content.stackable_with(self, target_slot) then --self_content, target_content) then
    if (target_content.max_stack_size or 1) >= (target_content.stack_size or 1) + (self_content.stack_size or 1) then
      return true
    end
  end
  return false
end

local function init_prop(value, default_value, var_type)
  if value == nil then
    value = default_value
  end
  if var_type == "boolean" then
    value = not not value
  end
  return value
end

local function new_slot(props)
  local o = setmetatable({
    x = props.x,
    y = props.y,
    z = props.z or 1,
    data = props.data, -- Should contain static data like slot_number or slot type like "Headgear" or whatever
    width = props.width,
    height = props.height,
    visible = init_prop(props.visible, true, "boolean"),
    -- greyed_out = init_prop(props.greyed_out, false, "boolean"),
  }, Slot__mt)
  slot_privates[o] = {
    background_sprite = "data/ui_gfx/inventory/full_inventory_box.png",
    background_sprite_highlight = "data/ui_gfx/inventory/full_inventory_box_highlight.png",
    event_listeners = {
      set_content = {}, -- Gets called once the content has been set
      move_content = {}, -- Gets called on the slot it was moved FROM, once the content has been moved to another slot
      drop_content = {}, -- Gets called when the content is dropped into "the world"
      shift_click = {}, -- Gets called when the content is dropped into "the world"
    },
    draggable = init_prop(props.draggable, true, "boolean")
  }

  table.insert(slot_instances, o)
  return o
end

return {
  Slot = new_slot,
  Update = update,
  UpdateCustomScreenResolution = EZMouse.UpdateCustomScreenResolution,
  Reset = function()
    GuiDestroy(gui)
    gui = GuiCreate()
  end,
  SetSoundsEnabled = function(enabled)
    sounds_enabled = enabled
  end,
  SetAnimationsEnabled = function(enabled)
    animations_enabled = enabled
  end
}
