-- Appended to mods/mnee/bindings.lua
_MNEEDATA["Cartographer"] = {
	name = "Cartographer",
	desc = "Fullscreen map with fog of war.",
}

_BINDINGS["Cartographer"] = {
	toggle_map = {
		order_id = "a",
		name = "Toggle map",
		desc = "Opens/closes the map.",
		-- Weak, so Ctrl+M (M-Nee's own menu) doesn't also toggle the map
		is_weak = true,
		keys = { ["m"] = 1 },
	},
}
