dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "WandBlueprints"
mod_settings_version = 1

mod_settings =
{
	{
		id = "show_button",
		ui_name = "Show button",
		ui_description = "Show the on-screen button that opens the blueprint panel.\nRight-click and drag it to move it.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "require_tinkering",
		ui_name = "Applying blueprints requires wand tinkering",
		ui_description = "Only allow applying blueprints where wands can be edited\n(Holy Mountain or the Tinker With Wands Everywhere perk).",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "rename_wands",
		ui_name = "Name wands after their blueprint",
		ui_description = "A wand whose spells match a blueprint is named after it, so the name shows\nin the game's wand tooltip. The wand's own name comes back once it stops matching.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "show_wands_panel",
		ui_name = "Show wands panel",
		ui_description = "Show your 4 wands and the blueprint each one matches next to the blueprint list.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		id = "show_hotbar_info",
		ui_name = "Show blueprints on the hotbar",
		ui_description = "Mark hotbar wands that match a blueprint (the key its hotkey is bound to,\nor its icon if it has none), and show the held wand's blueprint name under the hotbar.",
		value_default = true,
		scope = MOD_SETTING_SCOPE_RUNTIME,
	},
	{
		not_setting = true,
		ui_fn = function(mod_id, gui, in_main_menu, im_id, setting)
			if GuiButton(gui, im_id, 0, 0, "[ Reset button position ]") then
				ModSettingSet("WandBlueprints.button_pos_x", 182)
				ModSettingSet("WandBlueprints.button_pos_y", 41)
			end
		end,
	},
}

function ModSettingsUpdate(init_scope)
	local old_version = mod_settings_get_version(mod_id)
	mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
	return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
	mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
