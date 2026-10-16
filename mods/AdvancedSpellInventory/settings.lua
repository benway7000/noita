dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "AdvancedSpellInventory"
mod_settings_version = 1

local function int_slider(mod_id, gui, in_main_menu, im_id, setting)
	local setting_id = mod_setting_get_id(mod_id, setting)
	local value = tonumber(ModSettingGetNextValue(setting_id)) or 0
	GuiLayoutBeginHorizontal(gui, 0, 0, false, 0, 2)
	GuiText(gui, 0, 0, setting.ui_name)
	value = GuiSlider(gui, im_id, 0, 1, "", value, setting.value_min, setting.value_max, setting.value_default, 1, " ", 50)
	GuiText(gui, 4, 0, ("%d"):format(value))
	GuiLayoutEnd(gui)
	value = math.floor(value + 0.5)
	ModSettingSetNextValue(setting_id, value, false)
end

local custom_gui

mod_settings =
{
	{
		id = "show_button",
		ui_name = "Show button",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "sounds_enabled",
		ui_name = "Enable sounds",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "enable_spell_refresh_in_storage",
		ui_name = "Spell refresh affects stored spells",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "num_rows",
		ui_name = "Visible storage rows",
		ui_description = "How many storage rows are visible at once.\nStorage grows automatically, scroll with the mouse wheel or scrollbar.",
		value_default = 3,
		value_min = 1,
		value_max = 14,
		ui_fn = int_slider,
		scope = MOD_SETTING_SCOPE_RUNTIME_RESTART,
	},
	{
		id = "auto_storage",
		ui_name = "Pick up spells directly to storage",
		ui_description = "If you pick up spells, they will go directly\ninto the storage instead of regular spell inventory.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME_RESTART,
	},
	{
		id = "opening_inv_closes_spell_inv",
		ui_name = "Close when opening Inventory",
		ui_description = "Will close the Advanced Spell Inventory when opening the main inventory,\ninstead of just temporarily hiding it while the main inventory is open.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "spell_dump_needs_wand_tinkering",
		ui_name = "Dumping spells requires wand tinkering",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "enable_funny_dump_sound",
		ui_name = "Huh, I wonder what this does, I should enable it and dump my spells to find out",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		not_setting = true,
		ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
			if GuiButton(gui, im_id, 0, 0, "[ Reset button position ]") then
				ModSettingSet("AdvancedSpellInventory.button_pos_x", 162)
				ModSettingSet("AdvancedSpellInventory.button_pos_y", 41)
			end
		end
	},
	-- Blocklist
	{
		category_id = "blocklist",
		ui_name = "Blocklist",
		ui_description = "Entries in here will not be able to be put into the inventory.",
		foldable = true,
		settings = {
			{
				scope = MOD_SETTING_SCOPE_RUNTIME,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					local id = 2
					local function new_id()
						id = id + 1
						return id
					end
					local function get_setting_id(idx)
						return mod_id .. "." .. "blocklist_entries." .. idx
					end
					GuiIdPush(gui, im_id)
					GuiLayoutBeginVertical(gui, 0, 0)
					local num_entries = ModSettingGetNextValue(mod_id .. "." .. "num_blocklist_entries") or 0
					for i=1, num_entries do
						GuiLayoutBeginHorizontal(gui, 5, 0, true)
						local text = ModSettingGetNextValue(get_setting_id(i)) or ""
						local new_text = GuiTextInput(gui, new_id(), 0, 0, tostring(text), 100, 100)
						if text ~= new_text then
							ModSettingSetNextValue(get_setting_id(i), new_text, false)
						end
						local setting_id = get_setting_id(i) .. ".exact_match"
						local checked = not not ModSettingGetNextValue(setting_id)
						if GuiButton(gui, new_id(), 0, 0, ("Exact match: [%s]"):format(checked and "*" or "  ")) then
							ModSettingSetNextValue(setting_id, not checked, false)
						end
						GuiTooltip(gui, [[If enabled, requires exact spell name, case sensitive.
For example: "Spitter bolt" will not match "Spitter Bolt"
If disabled, it is enough if the filter appears in the name.
For example: "bolt" will match "Spitter Bolt", "Lightning Bolt" etc]], "")
						GuiText(gui, 0, 0, " - ")
						if GuiButton(gui, new_id(), 0, 0, "[ Remove entry ]") then
							for i2=i, num_entries-1 do
								local next_entry = ModSettingGetNextValue(get_setting_id(i2+1)) or ""
								ModSettingSetNextValue(get_setting_id(i2), next_entry, false)
								next_entry = ModSettingGetNextValue(get_setting_id(i2+1) .. ".exact_match") or false
								ModSettingSetNextValue(get_setting_id(i2) .. ".exact_match", next_entry, false)
							end
							ModSettingRemove(get_setting_id(num_entries))
							ModSettingRemove(get_setting_id(num_entries) .. ".exact_match")
							ModSettingSetNextValue(mod_id .. ".num_blocklist_entries", num_entries - 1, false)
						end
						GuiLayoutEnd(gui)
					end
					if GuiButton(gui, new_id(), 5, 0, "[ Add new entry ]") then
						ModSettingSetNextValue(mod_id .. ".num_blocklist_entries", num_entries + 1, false)
					end
					GuiLayoutEnd(gui)
					local _, _, _, _, _, _, _, _, _, _, draw_height = GuiGetPreviousWidgetInfo(gui)
					GuiIdPop(gui)
					-- Add empty space to push the layout down because for some reason it's not working
					GuiText(gui, 0, (draw_height + 2) * (num_entries-1), " ")
				end
			},
		}
	},
	{
		category_id = "custom_resolution",
		foldable = true,
		_folded = true,
		ui_name = "Custom Resolution",
		ui_description = "If you modified your config.xml with a custom\ninternal render resolution, set the same here\nso that the mouse coordinate detection works correctly.",
		settings = {
			{
				not_setting = true,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					local custom_screen_resolution_x = ModSettingGetNextValue("EZMouse.custom_screen_resolution_x")
					local custom_screen_resolution_y = ModSettingGetNextValue("EZMouse.custom_screen_resolution_y")
					GuiIdPush(gui, im_id)
					GuiLayoutBeginHorizontal(gui, 0, 0)
					GuiText(gui, 0, 0, "Width: ")
					local new_x = GuiTextInput(gui, 2, 0, 0, tostring(custom_screen_resolution_x or ""), 50, 6, "0123456789")
					if tonumber(new_x) ~= custom_screen_resolution_x then
						if tonumber(new_x) == nil then
							ModSettingRemove("EZMouse.custom_screen_resolution_x")
						else
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_x", tonumber(new_x) or 1280, false)
							ModSettingSet("EZMouse.custom_screen_resolution_x", tonumber(new_x) or 1280)
						end
					end
					GuiText(gui, 0, 0, "Height: ")
					local new_y = GuiTextInput(gui, 3, 0, 0, tostring(custom_screen_resolution_y or ""), 50, 6, "0123456789")
					if tonumber(new_y) ~= custom_screen_resolution_y then
						if tonumber(new_y) == nil then
							ModSettingRemove("EZMouse.custom_screen_resolution_y")
						else
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_y", tonumber(new_y) or 720, false)
							ModSettingSet("EZMouse.custom_screen_resolution_y", tonumber(new_y) or 720)
						end
					end
					GuiLayoutEnd(gui)
					GuiIdPop(gui)
				end
			},
			{
				not_setting = true,
				ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
					GuiIdPush(gui, im_id)
					local clicked, right_clicked = GuiButton(gui, 0, 0, 0, "[ Auto-config custom resolution ]")
					GuiTooltip(gui, "Right click to reset", "")
					if clicked then
						config_resolution = true
						custom_gui = GuiCreate()
					elseif right_clicked then
						ModSettingRemove("EZMouse.custom_screen_resolution_x")
						ModSettingRemove("EZMouse.custom_screen_resolution_y")
					end
					if config_resolution then
						GuiStartFrame(custom_gui)
						local mx, my = InputGetMousePosOnScreen()
						GuiZSetForNextWidget(custom_gui, -99999999)
						local screen_width, screen_height = GuiGetScreenDimensions(custom_gui)
						local text = "Move your mouse to the very BOTTOM RIGHT CORNER of your screen and CLICK"
						local text_width, text_height = GuiGetTextDimensions(custom_gui, text)
						GuiText(custom_gui, (screen_width - text_width) / 2, (screen_height - text_height) / 2, text)
						GuiZSetForNextWidget(custom_gui, -9999999)
						GuiColorSetForNextWidget(custom_gui, 0, 0, 0, 1)
						GuiImage(custom_gui, 1, 0, 0, "data/debug/whitebox.png", 0.8, 1000, 1000)
						local clicked2, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(custom_gui)
						local rx, ry = 0, 0
						if not clicked and clicked2 then
							rx, ry = math.ceil(mx), math.ceil(my)
							config_resolution = false
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_x", rx, false)
							ModSettingSetNextValue("EZMouse.custom_screen_resolution_y", ry, false)
							ModSettingSet("EZMouse.custom_screen_resolution_x", rx)
							ModSettingSet("EZMouse.custom_screen_resolution_y", ry)
							GuiDestroy(custom_gui)
							custom_gui = nil
						end
					end
					GuiIdPop(gui)
				end
			},
		}
	},
}

function ModSettingsUpdate(init_scope)
	local old_version = mod_settings_get_version(mod_id)
	mod_settings_update(mod_id, mod_settings, init_scope)
	-- Save the blocklist
	local num_blocklist_entries = ModSettingGetNextValue(mod_id .. ".num_blocklist_entries") or 0
	ModSettingSet(mod_id .. ".num_blocklist_entries", num_blocklist_entries)
	for i=1, num_blocklist_entries do
		local entry = ModSettingGetNextValue(mod_id .. ".blocklist_entries." .. tostring(i)) or ""
		ModSettingSet(mod_id .. ".blocklist_entries." .. tostring(i), entry)
		local exact_match = ModSettingGetNextValue(mod_id .. ".blocklist_entries." .. tostring(i) .. ".exact_match") or false
		ModSettingSet(mod_id .. ".blocklist_entries." .. tostring(i) .. ".exact_match", exact_match)
	end
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
