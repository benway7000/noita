local active_left = tonumber(GlobalsGetValue("active_left", "1"))
local active_right = tonumber(GlobalsGetValue("active_right", "1"))

return function(gui, new_id, x, y)
  for i=1, 5 do
    local add_text_offset = 0
    if i == 1 then
      add_text_offset = 1
    end
    -- Left side (Wand tabs)
    GuiZSetForNextWidget(gui, 21)
    local is_active_left = active_left == i
    if GuiImageButton(gui, new_id(), x - 16, y + 5 + (i-1) * 17, "", "mods/InventoryBags/files/tab_left_empty" .. (is_active_left and "_active" or "") .. ".png") then
    -- if GuiImageButton(gui, new_id(), x - 16, y + 5 + (i-1) * 17, "", "mods/InventoryBags/files/tab_left_" .. i .. ".png") then
      GlobalsSetValue("active_left", i)
      -- active_left = i
    end
    -- GuiOptionsAddForNextWidget(gui, GUI_OPTION.Align_Center)
    GuiColorSetForNextWidget(gui, 1, 1, 1, 0.8)
    GuiText(gui, x - 10 + add_text_offset, y + 8 + (i-1) * 17, i)
    -- Right side (Item tabs)
    GuiZSetForNextWidget(gui, 21)
    local is_active_right = active_right == i
    if GuiImageButton(gui, new_id(), x + 157, y + 5 + (i-1) * 17, "", "mods/InventoryBags/files/tab_right_empty" .. (is_active_right and "_active" or "") .. ".png") then
    -- if GuiImageButton(gui, new_id(), x + 153, y + 5 + (i-1) * 17, "", "mods/InventoryBags/files/tab_right_" .. i .. ".png") then
      -- active_right = i
      GlobalsSetValue("active_right", i)
    end
    GuiText(gui, x + 159 + add_text_offset, y + 8 + (i-1) * 17, i)
  end
end
