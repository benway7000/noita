dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "InventoryBags"
mod_settings_version = 2

local function num_slots_input(mod_id, gui, in_main_menu, im_id, setting)
	local old_value = tostring(ModSettingGetNextValue(mod_setting_get_id(mod_id, setting)) or setting.value_default)
	GuiLayoutBeginHorizontal(gui, 0, 0)
	GuiText(gui, 0, 0, setting.ui_name .. ": ")
	local new_value = tonumber(GuiTextInput(gui, im_id, 0, 0, old_value, 50, 4, "0123456789")) or 0
	local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
	if right_clicked then
		new_value = setting.value_default
	end
	GuiLayoutEnd(gui)
	ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), new_value, false)
	mod_setting_handle_change_callback(mod_id, gui, in_main_menu, setting, old_value, new_value)
end

local function num_tabs_ui_fn(mod_id, gui, in_main_menu, im_id, setting)
	local old_value = tonumber(ModSettingGetNextValue(mod_setting_get_id(mod_id, setting))) or setting.value_default
	local new_value = GuiSlider(gui, im_id, 0, 0, setting.ui_name .. ": ", old_value, setting.value_min, setting.value_max, setting.value_default, 1, " ", 50)
	new_value = math.floor(new_value + 0.5)
	local clicked, right_clicked, hovered, x, y, width, height, draw_x, draw_y, draw_width, draw_height = GuiGetPreviousWidgetInfo(gui)
	GuiOptionsAddForNextWidget(gui, GUI_OPTION.Layout_NoLayouting)
	GuiText(gui, x + width + 5, y - 1, tostring(new_value))
	if right_clicked then
		new_value = setting.value_default
	end
	ModSettingSetNextValue(mod_setting_get_id(mod_id, setting), new_value, false)
	mod_setting_handle_change_callback(mod_id, gui, in_main_menu, setting, old_value, new_value)
end

mod_settings =
{
	{
		id = "pos_x",
		ui_name = "Horizontal position",
		ui_description = "",
		value_default = 2,
		value_min = 0,
		value_max = 1000,
		value_display_multiplier = 1,
		value_display_formatting = " x = $0",
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "pos_y",
		ui_name = "Vertical position",
		ui_description = "",
		value_default = 22,
		value_min = 0,
		value_max = 1000,
		value_display_multiplier = 1,
		value_display_formatting = " y = $0",
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		ui_fn = mod_setting_vertical_spacing,
		not_setting = true,
	},
	{
		id = "sounds_enabled",
		ui_name = "Enable sounds",
		ui_description = "Whether sounds should be played for opening/closing the bag or dropping items.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "locked",
		ui_name = "Lock button",
		ui_description = "When unlocked, button can be dragged to a new position",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "show_wand_bag",
		ui_name = "Show wand bag",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "show_item_bag",
		ui_name = "Show item bag",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "num_tabs_wands",
		ui_name = "Amount of wand tabs",
		value_default = 5,
		value_min = 0,
		value_max = 5,
		ui_fn = num_tabs_ui_fn,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "num_tabs_items",
		ui_name = "Amount of item tabs",
		value_default = 5,
		value_min = 0,
		value_max = 5,
		ui_fn = num_tabs_ui_fn,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "wands_per_tab",
		ui_name = "Max wands per tab",
		value_default = 9999,
		ui_fn = num_slots_input,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "items_per_tab",
		ui_name = "Max items per tab",
		value_default = 9999,
		ui_fn = num_slots_input,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "opening_inv_closes_bags",
		ui_name = "Auto close when opening inventory",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "auto_storage",
		ui_name = "Auto storage",
		ui_description = "Automatically place picked up wands/items directly into\nthe currently selected tab of their respective bag.",
		value_default = false,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		category_id = "auto_storage_blocklist",
		ui_name = "Auto storage blocklist",
		ui_description = "Define a blocklist for wands/items that should not be auto-stored (blacklist),\nor only those that should be auto-stored (whitelist).\n\nIt checks if the item name contains whatever you enter, case insensitive,\nfor example 'tablet' will match 'Emerald Tablet - Volume IX'",
		foldable = true,
		settings = {
			{
				id = "list_type",
				ui_name = "List type",
				ui_description = "Blacklist = These will not be auto-stored\nWhitelist = Only these will be auto-stored, not any others",
				value_default = "blacklist",
				values = { { "blacklist", "Blacklist" }, { "whitelist", "Whitelist" } },
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
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
						if GuiButton(gui, new_id(), 0, 0, "[ Remove entry ]") then
							for i2=i, num_entries-1 do
								local next_entry = ModSettingGetNextValue(get_setting_id(i2+1)) or ""
								ModSettingSetNextValue(get_setting_id(i2), next_entry, false)
							end
							ModSettingRemove(get_setting_id(num_entries))
							ModSettingSetNextValue(mod_id .. ".num_blocklist_entries", num_entries - 1, false)
						end
						GuiLayoutEnd(gui)
					end
					if GuiButton(gui, new_id(), 5, 0, "[ Add new entry ]") then
						ModSettingSetNextValue(mod_id .. ".num_blocklist_entries", num_entries + 1, false)
					end
					GuiLayoutEnd(gui)
					GuiIdPop(gui)
					-- Add empty space to push the layout down because for some reason it's not working
					for i=1, num_entries+1 do
						GuiText(gui, 0, 0, " ")
					end
				end
			},
		}
	},
	{
		category_id = "tab_labels",
		ui_name = "Tab Labels",
		ui_description = "Labels for the tabs when hovering over them.\nKeep the mouse hovered over these text fields to enter text.",
		foldable = true,
		settings = {
			{
				id = "tab_label_wands_1",
				ui_name = "Wand bag 1",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_wands_2",
				ui_name = "Wand bag 2",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_wands_3",
				ui_name = "Wand bag 3",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_wands_4",
				ui_name = "Wand bag 4",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_wands_5",
				ui_name = "Wand bag 5",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_items_1",
				ui_name = "Item bag 1",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_items_2",
				ui_name = "Item bag 2",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_items_3",
				ui_name = "Item bag 3",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_items_4",
				ui_name = "Item bag 4",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
			{
				id = "tab_label_items_5",
				ui_name = "Item bag 5",
				ui_description = "",
				value_default = "",
				scope = MOD_SETTING_SCOPE_RUNTIME,
			},
		}
	}
}

function adjust_setting_values(screen_width, screen_height)
	if not screen_width then
		local gui = GuiCreate()
		GuiStartFrame(gui)
		screen_width, screen_height = GuiGetScreenDimensions(gui)
	end
	for i, setting in ipairs(mod_settings) do
		if setting.id == "pos_x" then
			setting.value_max = screen_width
		elseif setting.id == "pos_y" then
			setting.value_max = screen_height
		end
	end
end

function ModSettingsUpdate(init_scope)
	local old_version = mod_settings_get_version(mod_id)
	if old_version == 1 then
		local old_num_tabs = ModSettingGet("InventoryBags.num_tabs") or 5
		ModSettingSet("InventoryBags.num_tabs_wands", old_num_tabs)
		ModSettingSetNextValue("InventoryBags.num_tabs_wands", old_num_tabs, true)
		ModSettingSet("InventoryBags.num_tabs_items", old_num_tabs)
		ModSettingSetNextValue("InventoryBags.num_tabs_items", old_num_tabs, true)
	end
	mod_settings_update(mod_id, mod_settings, init_scope)
	-- Save the blocklist
	local blocklist_type = ModSettingGetNextValue(mod_id .. ".list_type") or "blacklist"
	ModSettingSet(mod_id .. ".list_type", blocklist_type)
	local num_blocklist_entries = ModSettingGetNextValue(mod_id .. ".num_blocklist_entries") or 0
	ModSettingSet(mod_id .. ".num_blocklist_entries", num_blocklist_entries)
	for i=1, num_blocklist_entries do
		local entry = ModSettingGetNextValue(mod_id .. ".blocklist_entries." .. tostring(i)) or ""
		ModSettingSet(mod_id .. ".blocklist_entries." .. tostring(i), entry)
	end
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui( gui, in_main_menu )
	new_screen_width, new_screen_height = GuiGetScreenDimensions(gui)
	-- Update settings when resolution changes
	if screen_width ~= new_screen_width or screen_height ~= new_screen_height then
		adjust_setting_values(new_screen_width, new_screen_height)
	end
	screen_width = new_screen_width
	screen_height = new_screen_height

	mod_settings_gui( mod_id, mod_settings, gui, in_main_menu )
end
