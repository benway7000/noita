-- Appended to mods/mnee/bindings.lua
_MNEEDATA["WandBlueprints"] = {
	name = "Wand Blueprints",
	desc = "Toggle the blueprint panel and apply blueprints to the held wand.",
}

_BINDINGS["WandBlueprints"] = {
	toggle = {
		order_id = "a",
		name = "Toggle panel",
		desc = "Opens/closes the Wand Blueprints panel.",
		keys = { ["_"] = 1 },
	},
}

for i = 1, 10 do
	_BINDINGS["WandBlueprints"]["hotkey_" .. i] = {
		order_id = ("b%02d"):format(i),
		name = "Blueprint hotkey " .. i,
		desc = "Applies the blueprint assigned to hotkey " .. i .. " to the held wand.",
		keys = { ["_"] = 1 },
	}
end
