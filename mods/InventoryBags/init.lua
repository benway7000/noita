dofile_once("data/scripts/lib/utilities.lua")
dofile_once("data/scripts/gun/gun_enums.lua")
dofile_once("mods/InventoryBags/lib/coroutines.lua")
local utf8 = dofile_once("mods/InventoryBags/lib/utf8.lua")
dofile_once("mods/InventoryBags/lib/polytools/polytools_init.lua").init("mods/InventoryBags/lib/polytools")
local polytools = dofile_once("mods/InventoryBags/lib/polytools/polytools.lua")
local nxml = dofile_once("mods/InventoryBags/lib/nxml.lua")
local EZWand = dofile_once("mods/InventoryBags/lib/EZWand/EZWand.lua")

local function _get_binding_pressed(mod_name, binding_name)
	return false
end

if ModIsEnabled("mnee") then
	ModLuaFileAppend("mods/mnee/bindings.lua", "mods/InventoryBags/mnee.lua")
	dofile_once("mods/mnee/lib.lua")
	function _get_binding_pressed(binding_name)
		return get_binding_pressed("InvBags", binding_name)
	end
end

local poly_place_x = 6666666
local poly_place_y = 6666666

local num_tabs_wands = 5
local num_tabs_items = 5
local storage_version = 1
local active_wand_tab = 1
local active_item_tab = 1
local wand_storage_changed = true
local item_storage_changed = true
local last_stored_entity = {}
local cached_stored_wands
local entity_killed_this_frame
local was_polymorphed = false

local function get_serialized_ez(entity_id)
	for i, comp in ipairs(EntityGetComponentIncludingDisabled(entity_id, "VariableStorageComponent") or {}) do
		if ComponentGetValue2(comp, "name") == "serialized_ez" then
			return ComponentGetValue2(comp, "value_string")
		end
	end
end

local sorting_directions = { ASCENDING = 1, DESCENDING = 2 }
local sorting_functions = {
	{ "data/ui_gfx/inventory/icon_gun_shuffle.png", function (a, b)
		return (a.props.shuffle and 1 or 0) - (b.props.shuffle and 1 or 0)
	end, "Shuffle" },
	{ "data/ui_gfx/inventory/icon_gun_actions_per_round.png", function (a, b)
		return a.props.spellsPerCast - b.props.spellsPerCast
	end, "Spells/Cast" },
	{ "data/ui_gfx/inventory/icon_fire_rate_wait.png", function (a, b)
		return a.props.castDelay - b.props.castDelay
	end, "Cast Delay" },
	{ "data/ui_gfx/inventory/icon_gun_reload_time.png", function (a, b)
		return a.props.rechargeTime - b.props.rechargeTime
	end, "Recharge Time" },
	{ "data/ui_gfx/inventory/icon_mana_max.png", function (a, b)
		return a.props.manaMax - b.props.manaMax
	end, "Mana Max" },
	{ "data/ui_gfx/inventory/icon_mana_charge_speed.png", function (a, b)
		return a.props.manaChargeSpeed - b.props.manaChargeSpeed
	end, "Mana Charge Speed" },
	{ "data/ui_gfx/inventory/icon_gun_capacity.png", function (a, b)
		return a.props.capacity - b.props.capacity
	end, "Capacity" },
	{ "data/ui_gfx/inventory/icon_spread_degrees.png", function (a, b)
		return a.props.spread - b.props.spread
	end, "Spread" },
}

local default_sorting_function = function(a, b)
	return a.container_entity_id < b.container_entity_id
end
local function sort_wand(sorting_function, a, b, sorting_direction)
	local result
	if sorting_direction == sorting_directions.ASCENDING then
		result = sorting_function(a, b)
	else
		result = sorting_function(b, a)
	end
	if result < 0 then return true end
	if result > 0 then return false end
	if sorting_direction == sorting_directions.ASCENDING then
		return default_sorting_function(a, b)
	else
		return default_sorting_function(b, a)
	end
end

-- Remember the last chosen sort so it survives the stored wands list being rebuilt (e.g. after dropping a wand)
local function sort_stored_wands(wands)
	local sort_index = tonumber(GlobalsGetValue("InventoryBags_wand_sort_index", "0"))
	local sort_direction = tonumber(GlobalsGetValue("InventoryBags_wand_sort_direction", "0"))
	local sorting_function = sorting_functions[sort_index]
	if sorting_function then
		table.sort(wands, function(a, b)
			return sort_wand(sorting_function[2], a, b, sort_direction)
		end)
	else
		table.sort(wands, default_sorting_function)
	end
end

local function split_string(inputstr, sep)
  sep = sep or "%s"
  local t= {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

local function ends_with(str, ending)
	if not str then error("str is nil", 2) end
  return ending == "" or str:sub(-#ending) == ending
end

local function get_item_image(entity_id)
	local image_file = "data/ui_gfx/gun_actions/unidentified.png"
	local item_component = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
	if item_component then
		image_file = ComponentGetValue2(item_component, "ui_sprite")
		if image_file == "" then
			-- This is for spells when player has spells materialized perk
			local sprite_component = EntityGetFirstComponentIncludingDisabled(entity_id, "SpriteComponent", "item_identified")
			if sprite_component then
				image_file = ComponentGetValue2(sprite_component, "image_file")
			end
		end
		if ends_with(image_file, ".xml") then
			image_file = get_xml_sprite(image_file)
		end
	end
	return image_file
end

local function get_variable_storage_component(entity_id, var_store_name)
	for i, comp in ipairs(EntityGetComponentIncludingDisabled(entity_id, "VariableStorageComponent") or {}) do
		if ComponentGetValue2(comp, "name") == var_store_name then
			return comp
		end
	end
end

function get_active_item()
	local player = EntityGetWithTag("player_unit")[1]
	if player then
		local inventory2 = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
		local mActualActiveItem = ComponentGetValue2(inventory2, "mActualActiveItem")
		return mActualActiveItem > 0 and mActualActiveItem or nil
	end
end

function get_inventory_position(entity)
	local item_component = EntityGetFirstComponentIncludingDisabled(entity, "ItemComponent")
	return ComponentGetValue2(item_component, "inventory_slot")
end

function set_inventory_position(entity, slot)
	local item_component = EntityGetFirstComponentIncludingDisabled(entity, "ItemComponent")
	ComponentSetValue2(item_component, "inventory_slot", slot, 0)
end

function is_wand(entity)
	local ability_component = EntityGetFirstComponentIncludingDisabled(entity, "AbilityComponent")
	if not ability_component then
		return false
	end
	return ComponentGetValue2(ability_component, "use_gun_script") == true
end

function is_item(entity)
	local ability_component = EntityGetFirstComponentIncludingDisabled(entity, "AbilityComponent")
	local ending_mc_guffin_component = EntityGetFirstComponentIncludingDisabled(entity, "EndingMcGuffinComponent")
	return (not ability_component) or ending_mc_guffin_component or ComponentGetValue2(ability_component, "use_gun_script") == false
end

function get_inventory()
	local player = EntityGetWithTag("player_unit")[1]
	if player then
		for i, child in ipairs(EntityGetAllChildren(player) or {}) do
			if EntityGetName(child) == "inventory_quick" then
				return child
			end
		end
	end
end

function get_held_wands()
	local inventory = get_inventory()
	if inventory then
		local active_item = get_active_item()
		local wands = {}
		for i, wand in ipairs(EntityGetAllChildren(inventory) or {}) do
			if is_wand(wand) then
				local baggable = get_variable_storage_component(wand, "InventoryBags_not_baggable") == nil
				local sprite_component = EntityGetFirstComponentIncludingDisabled(wand, "SpriteComponent")
				local image_file = ComponentGetValue2(sprite_component, "image_file")
				if ends_with(image_file, ".xml") then
					image_file = get_xml_sprite(image_file)
				end
				table.insert(wands, {
					entity_id = wand,
					image_file = image_file,
					inventory_slot = get_inventory_position(wand),
					active = wand == active_item,
					baggable = baggable
				})
			end
		end
		return wands
	else
		return {}
	end
end

function get_held_items()
	local inventory = get_inventory()
	if inventory then
		local active_item = get_active_item()
		local items = {}
		for i, item in ipairs(EntityGetAllChildren(inventory) or {}) do
			if is_item(item) then
				local baggable = get_variable_storage_component(item, "InventoryBags_not_baggable") == nil
				local item_component = EntityGetFirstComponentIncludingDisabled(item, "ItemComponent")
				if item_component then
					table.insert(items, {
						entity_id = item,
						image_file = get_item_image(item),
						inventory_slot = get_inventory_position(item) % 4,
						active = item == active_item,
						baggable = baggable
					})
				end
			end
		end
		return items
	else
		return {}
	end
end

function get_stored_wands(tab_number)
	tab_number = tab_number or 1
	if not wand_storage_changed then
		return cached_stored_wands
	else
		local wand_storage = EntityGetWithName("wand_storage_container")
		local out = {}
		if wand_storage > 0 then
			local tab_entity = get_tab_entity(wand_storage, tab_number)
			for i, container_entity_id in ipairs(EntityGetAllChildren(tab_entity) or {}) do
				if entity_killed_this_frame ~= container_entity_id then
					local serialized_ez, serialized_poly
					for i, comp in ipairs(EntityGetComponentIncludingDisabled(container_entity_id, "VariableStorageComponent") or {}) do
						if ComponentGetValue2(comp, "name") == "serialized_ez" then
							serialized_ez = ComponentGetValue2(comp, "value_string")
						end
						if ComponentGetValue2(comp, "name") == "serialized_poly" then
							serialized_poly = ComponentGetValue2(comp, "value_string")
						end
					end
					local wand = EZWand.Deserialize(serialized_ez)
					if ends_with(wand.sprite_image_file, ".xml") then
						wand.sprite_image_file = get_xml_sprite(wand.sprite_image_file)
					end
					wand.container_entity_id = container_entity_id
					wand.serialized_poly = serialized_poly
					table.insert(out, wand)
				end
			end
			sort_stored_wands(out)
		end
		wand_storage_changed = false
		cached_stored_wands = out
		return cached_stored_wands
	end
end

function get_stored_items(tab_number)
	tab_number = tab_number or 1
	if not item_storage_changed then
		return cached_stored_items
	else
		local item_storage = EntityGetWithName("item_storage_container")
		local out = {}
		if item_storage > 0 then
			local tab_entity = get_tab_entity(item_storage, tab_number)
			for i, container_entity_id in ipairs(EntityGetAllChildren(tab_entity) or {}) do
				if entity_killed_this_frame ~= container_entity_id then
					local image_file, potion_color, tooltip, serialized_poly
					for i, comp in ipairs(EntityGetComponentIncludingDisabled(container_entity_id, "VariableStorageComponent")) do
						if ComponentGetValue2(comp, "name") == "serialized_image_file" then
							image_file = ComponentGetValue2(comp, "value_string")
						end
						if ComponentGetValue2(comp, "name") == "serialized_potion_color" then
							potion_color = ComponentGetValue2(comp, "value_int")
						end
						if ComponentGetValue2(comp, "name") == "serialized_tooltip" then
							tooltip = ComponentGetValue2(comp, "value_string"):gsub("<NEWLINE>", "\n")
						end
						if ComponentGetValue2(comp, "name") == "serialized_poly" then
							serialized_poly = ComponentGetValue2(comp, "value_string")
						end
					end
					local item = {}
					item.container_entity_id = container_entity_id
					item.serialized_poly = serialized_poly
					item.image_file = image_file
					item.potion_color = potion_color
					item.tooltip = tooltip
					table.insert(out, item)
				end
			end
			table.sort(out, function (a, b)
				return a.container_entity_id < b.container_entity_id
			end)
		end
		item_storage_changed = false
		cached_stored_items = out
		return cached_stored_items
	end
end

function string_match_percent(ser1, ser2)
  local character_match_amount = 0
  local longest_length = math.max(ser1:len(), ser2:len())
  for i=1, longest_length do
    if ser1:sub(i,i) == ser2:sub(i,i) then
      character_match_amount = character_match_amount + 1
    end
  end
  return character_match_amount / longest_length
end

if ModIsEnabled("quant.ew") then
	ModLuaFileAppend("mods/quant.ew/files/api/extra_modules.lua", "mods/InventoryBags/files/entangled_serialize.lua")
end

-- For EntangledWorlds https://github.com/IntQuant/noita_entangled_worlds
function serialize_entity_ew(entity)
	local serialized = CrossCall("InventoryBags_serialize_entity", entity)
	EntityKill(entity)
	return serialized
end

---Needs to be called from inside an async function. Kills entity and returns the serialized string after 1 frame.
function serialize_entity(entity)
	if ModIsEnabled("quant.ew") then
		return serialize_entity_ew(entity)
	end
	if not coroutine.running() then
		error("serialize_entity() must be called from inside an async function", 2)
	end
	-- Need to do this because we poly the entity and thus lose the reference to it,
	-- because the polymorphed entity AND the one that it turns back into both have different entity_ids than the original
	-- That's why we first move it to some location where it will hopefully be the only entity, so we can later get it back
	-- But this also means that this location will be saved in the serialized string, and when it gets deserialized,
	-- will spawn there again (Test this later to confirm!!! Too lazy right now)
	EntityRemoveFromParent(entity)
	EntityApplyTransform(entity, poly_place_x, poly_place_y)
	-- Some spells like BOMB are missing InheritTransformComponent
	-- manually move the card actions to target location to hide the sprite flashes
	for i, v in ipairs(EntityGetAllChildren(entity) or {}) do
		EntityApplyTransform(v, poly_place_x, poly_place_y)
	end
	local serialized = polytools.save(entity)
	wait(0)
	-- Kill the wand AND call cards IF for some unknown reason they are also detected with EntityGetInRadius
	for i, v in ipairs(EntityGetInRadius(poly_place_x, poly_place_y, 5)) do
		EntityRemoveFromParent(v)
		EntityKill(v)
	end
	return serialized
end

-- For EntangledWorlds https://github.com/IntQuant/noita_entangled_worlds
function deserialize_entity_ew(serialized)
	return CrossCall("InventoryBags_deserialize_entity", serialized, poly_place_x, poly_place_y)
end


function deserialize_entity(str)
	if ModIsEnabled("quant.ew") then
		return deserialize_entity_ew(str)
	end
	if not coroutine.running() then
		error("deserialize_entity() must be called from inside an async function", 2)
	end
	-- Move the entity to a unique location so that we can get a reference to the entity with EntityGetInRadius once polymorph wears off
	-- Apply polymorph which, when it runs out after 1 frame will turn the entity back into it's original form, which we provide
	polytools.spawn(poly_place_x, poly_place_y, str) -- x, y is irrelevant since entity retains its old location
	-- Wait 1 frame for the polymorph to wear off
	wait(0)
	local all_entities = EntityGetInRadius(poly_place_x, poly_place_y, 3)
	return EntityGetRootEntity(all_entities[1])
end

function get_tab_entity(storage_entity, tab_number)
	for i, child in ipairs(EntityGetAllChildren(storage_entity) or {}) do
		if EntityGetName(child) == "tab_" .. tab_number then
			return child
		end
	end
end

function create_storage_entity(ez, poly)
	local entity = EntityCreateNew("InventoryBags_stored_wand")
	EntityAddComponent2(entity, "VariableStorageComponent", {
		name = "serialized_ez",
		value_string = ez
	})
	EntityAddComponent2(entity, "VariableStorageComponent", {
		name = "serialized_poly",
		value_string = poly
	})
	return entity
end

function create_item_storage_entity(image_file, potion_color, tooltip, poly)
	local entity = EntityCreateNew("InventoryBags_stored_item")
	EntityAddComponent2(entity, "VariableStorageComponent", {
		name = "serialized_image_file",
		value_string = image_file
	})
	EntityAddComponent2(entity, "VariableStorageComponent", {
		name = "serialized_potion_color",
		value_int = potion_color
	})
	EntityAddComponent2(entity, "VariableStorageComponent", {
		name = "serialized_tooltip",
		value_string = tooltip:gsub("\n", "<NEWLINE>")
	})
	EntityAddComponent2(entity, "VariableStorageComponent", {
		name = "serialized_poly",
		value_string = poly
	})
	return entity
end

function put_wand_in_storage(wand, tab_number)
	if not coroutine.running() then
		error("put_wand_in_storage() must be called from inside an async function", 2)
	end
	tab_number = tab_number or 1
	local player = EntityGetWithTag("player_unit")[1]
	local wand_storage = EntityGetWithName("wand_storage_container")
	if player and wand_storage > 0 then
		wait(0) -- I don't know why this is needed but it won't work otherwise...
		local ez = EZWand(wand):Serialize()
		local poly = serialize_entity(wand)
		local new_entry = create_storage_entity(ez, poly)
		local tab_entity = get_tab_entity(wand_storage, tab_number)
		last_stored_entity = {
			container_entity_id = new_entry,
			serialized_poly = poly,
			tab_number = tab_number
		}
		EntityAddChild(tab_entity, new_entry)
		wand_storage_changed = true
	end
end

function tooltipify_item(item)
	local ability_component = EntityGetFirstComponentIncludingDisabled(item, "AbilityComponent")
	local item_component = EntityGetFirstComponentIncludingDisabled(item, "ItemComponent")
	local potion_component = EntityGetFirstComponentIncludingDisabled(item, "PotionComponent")
	if not item_component then
		return "data/ui_gfx/gun_actions/unidentified.png", 0, "Something went wrong :[\n \nNo ItemComponent found"
	end
	local description = ComponentGetValue2(item_component, "ui_description")
	description = GameTextGetTranslatedOrNot(description)
	local material_inventory_lines = ""
	local item_name
	if ability_component then
		item_name = ComponentGetValue2(ability_component, "ui_name")
	end
	-- Item name is either stored on AbilityComponent:ui_name or if that doesn't exist, ItemComponent:item_name
	if not item_name then
		item_name = ComponentGetValue2(item_component, "item_name") or "ERROR"
	end
	if potion_component then
		local main_material_id = GetMaterialInventoryMainMaterial(item)
		local main_material = CellFactory_GetUIName(main_material_id)
		main_material = GameTextGetTranslatedOrNot(main_material)
		local material_inventory_component = EntityGetFirstComponentIncludingDisabled(item, "MaterialInventoryComponent")
		local material_sucker_component = EntityGetFirstComponentIncludingDisabled(item, "MaterialSuckerComponent")
		local barrel_size = 1000
		if material_sucker_component then
			barrel_size = ComponentGetValue2(material_sucker_component, "barrel_size")
		end
		local count_per_material_type = {}
		if material_inventory_component then
			count_per_material_type = ComponentGetValue2(material_inventory_component, "count_per_material_type")
		end
		local total_amount = 0
		-- Apparently there's a bug where sometimes it generates millions of newlines? Could not reproduce it.
		-- But let's try to prevent that from happening anyways by only allowing some max number of iterations.
		local current_iterations = 0
		for material_id, amount in pairs(count_per_material_type) do
			if amount > 0 then
				total_amount = total_amount + amount
				local material_name = CellFactory_GetUIName(material_id-1)
				material_name = GameTextGetTranslatedOrNot(material_name)
				material_inventory_lines = material_inventory_lines .. ("%s (%d)"):format(material_name:gsub("^%l", string.upper), amount) .. "\n"
				current_iterations = current_iterations + 1
				if current_iterations >= 30 then
					break
				end
			end
		end
		local fill_percent = math.ceil((total_amount / barrel_size) * 100)
		item_name = (GameTextGet(item_name, main_material) .. GameTextGet("$item_potion_fullness", fill_percent)):upper()
	else
		local uses_remaining = ComponentGetValue2(item_component, "uses_remaining")
		item_name = GameTextGetTranslatedOrNot(item_name):upper()
		if uses_remaining ~= -1 then
			item_name = ("%s (%s)"):format(item_name, uses_remaining)
		end
	end

	local potion_color = GameGetPotionColorUint(item)
	local tooltip = item_name .. "\n \n"
	tooltip = tooltip .. description
	if material_inventory_lines ~= "" then
		tooltip = tooltip .. "\n \n" .. material_inventory_lines
	end
	local image_file = get_item_image(item)
	return image_file, potion_color, tooltip
end

function put_item_in_storage(item, tab_number)
	if not coroutine.running() then
		error("put_item_in_storage() must be called from inside an async function", 2)
	end
	tab_number = tab_number or 1
	local item_storage = EntityGetWithName("item_storage_container")
	local num_items_stored = #(EntityGetAllChildren(item_storage) or {})
	local player = EntityGetWithTag("player_unit")[1]
	if player and item_storage > 0 then
		wait(0) -- I don't know why this is needed but it won't work otherwise...
		local image_file, potion_color, tooltip = tooltipify_item(item)
		local poly = serialize_entity(item)
		local new_entry = create_item_storage_entity(image_file, potion_color ,tooltip, poly)
		local tab_entity = get_tab_entity(item_storage, tab_number)
		last_stored_entity = {
			container_entity_id = new_entry,
			serialized_poly = poly,
			tab_number = tab_number
		}
		EntityAddChild(tab_entity, new_entry)
		item_storage_changed = true
	end
end

function has_enough_space_for_wand()
	return #get_held_wands() < 4
end

function has_enough_space_for_item()
	return #get_held_items() < 4
end

function scroll_inventory(amount)
	local player = EntityGetWithTag("player_unit")[1]
	local controls_comp = EntityGetComponentIncludingDisabled(player, "ControlsComponent")[1]
	-- Disable the controls component so we can set the state ourself instead of it getting it from the input device
	ComponentSetValue2(controls_comp, "enabled", false)
	-- Just to make sure this gets re-enabled even it a bug occurs in the code after this
	async(function()
		-- Wait one frame then enable it again
		wait(0)
		ComponentSetValue2(controls_comp, "enabled", true)
	end)
	local inventory_2_comp = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
	if inventory_2_comp then
		-- This will only skip 1 equip message, but it's better than nothing
		ComponentSetValue2(inventory_2_comp, "mDontLogNextItemEquip", true)
	end
	-- This allows us to simulate inventory scrolling
	-- Thanks to Lobzyr on the Noita discord for figuring this out
	ComponentSetValue2(controls_comp, "mButtonDownChangeItemR", true)
	ComponentSetValue2(controls_comp, "mButtonFrameChangeItemR", GameGetFrameNum() + 1)
	ComponentSetValue2(controls_comp, "mButtonCountChangeItemR", amount)
end

---Returns a table of entity ids currently occupying the inventory, their index is their inventory position
---@return table inventory In the form: { [0] = nil, [1] = 307, } etc
---@return number active_item
function get_inventory_and_active_item()
	local inventory = get_inventory()
	inventory = EntityGetAllChildren(inventory) or {}
	local current_active_item = get_active_item()
	local inv_out = {}
	local active_item
	for i, entity_id in ipairs(inventory) do
		if entity_id == current_active_item then
			active_item = current_active_item
		end
		local item_component = EntityGetFirstComponentIncludingDisabled(entity_id, "ItemComponent")
		if item_component then
			local inventory_slot_x = ComponentGetValue2(item_component, "inventory_slot")
			local non_wand_offset = not is_wand(entity_id) and 4 or 0
			inv_out[inventory_slot_x+1 + non_wand_offset] = entity_id
		end
	end
	return inv_out, active_item
end

function pick_up_wand_and_place_in_inventory(wand, slot)
	local item_comp = EntityGetFirstComponentIncludingDisabled(wand, "ItemComponent")
	if item_comp then
		ComponentSetValue2(item_comp, "is_pickable", true)
		ComponentSetValue2(item_comp, "play_pick_sound", false)
		ComponentSetValue2(item_comp, "next_frame_pickable", 0)
		ComponentSetValue2(item_comp, "npc_next_frame_pickable", 0)
	end
	local first_free_wand_slot = get_first_free_wand_slot()
	local new_slot = slot and slot or first_free_wand_slot
	set_inventory_position(wand, new_slot)
	local inventory = get_inventory()
	-- For some reason this is neccessary because even though wand doesn't have a parent
	-- and EntityGetParent even returns 0, it still complains that "Error: child already has a parent!"
	EntityRemoveFromParent(wand)
	EntityAddChild(inventory, wand)
end

function pick_up_item_and_place_in_inventory(item, slot)
	local item_comp = EntityGetFirstComponentIncludingDisabled(item, "ItemComponent")
	if item_comp then
		ComponentSetValue2(item_comp, "is_pickable", true)
		ComponentSetValue2(item_comp, "play_pick_sound", false)
		ComponentSetValue2(item_comp, "next_frame_pickable", 0)
		ComponentSetValue2(item_comp, "npc_next_frame_pickable", 0)
	end
	local first_free_item_slot = get_first_free_item_slot()
	local new_slot = slot and slot or first_free_item_slot
	set_inventory_position(item, new_slot)
	local inventory = get_inventory()
	-- For some reason this is neccessary because even though item doesn't have a parent
	-- and EntityGetParent even returns 0, it still complains that "Error: child already has a parent!"
	EntityRemoveFromParent(item)
	EntityAddChild(inventory, item)
end

function scroll_inventory_to_slot(new_slot)
	local inventory_slots, active_item = get_inventory_and_active_item()
	local currently_selected_slot = 0
	if active_item then
		local active_item_item_comp = EntityGetFirstComponentIncludingDisabled(active_item, "ItemComponent")
		if active_item_item_comp then
			currently_selected_slot = ComponentGetValue2(active_item_item_comp, "inventory_slot")
		end
		if not is_wand(active_item) then
			-- Potions/Items start at 0, so add 4 to get the absolute position of the item in the inventory
			currently_selected_slot = currently_selected_slot + 4
		end
	end
	local change_amount = 0
	for i=currently_selected_slot, currently_selected_slot+8 do
		local slot_to_check = i % 8
		if slot_to_check == new_slot then
			break
		end
		if inventory_slots[slot_to_check+1] then
			change_amount = change_amount + 1
		end
	end
	if not active_item then
		change_amount = change_amount + 1
	end
	scroll_inventory(change_amount)
end

function create_and_pick_up_wand(serialized, slot)
	if not coroutine.running() then
		error("create_and_pick_up_wand() must be called from inside an async function", 2)
	end
	pick_up_wand_and_place_in_inventory(deserialize_entity(serialized), slot) -- wait(0)
	scroll_inventory_to_slot(slot)
end

function create_and_pick_up_item(serialized, slot)
	local new_item = deserialize_entity(serialized)
	-- "Pick up" item and place it in inventory
	local item_comp = EntityGetFirstComponentIncludingDisabled(new_item, "ItemComponent")
	ComponentSetValue2(item_comp, "is_pickable", true)
	ComponentSetValue2(item_comp, "play_pick_sound", false)
	ComponentSetValue2(item_comp, "next_frame_pickable", 0)
	ComponentSetValue2(item_comp, "npc_next_frame_pickable", 0)
	local first_free_item_slot = get_first_free_item_slot()
	local new_slot = slot and slot or first_free_item_slot
	GamePickUpInventoryItem(EntityGetWithTag("player_unit")[1], new_item, false)
	set_inventory_position(new_item, new_slot)
	local inventory = get_inventory()
	if EntityGetParent(new_item) > 0 then
		EntityRemoveFromParent(new_item)
	end
	EntityAddChild(inventory, new_item)
	-- /"Pick up" item and place it in inventory

	-- Scroll to new item to select it
	local inventory_slots, active_item = get_inventory_and_active_item()
	local currently_selected_slot = 0
	if active_item then
		local active_item_item_comp = EntityGetFirstComponentIncludingDisabled(active_item, "ItemComponent")
		if active_item_item_comp then
			currently_selected_slot = ComponentGetValue2(active_item_item_comp, "inventory_slot")
		end
		if not is_wand(active_item) then
			-- Potions/Items start at 0, so add 4 to get the absolute position of the item in the inventory
			currently_selected_slot = currently_selected_slot + 4
		end
	end
	local change_amount = 0
	for i=currently_selected_slot, currently_selected_slot+8 do
		local slot_to_check = i % 8
		if slot_to_check == new_slot then
			break
		end
		if inventory_slots[slot_to_check+1] then
			change_amount = change_amount + 1
		end
	end
	if not active_item then
		change_amount = change_amount + 1
	end
	scroll_inventory(change_amount)
	-- /Scroll to new item to select it
end

function retrieve_or_swap_wand(wand, tab_number)
	if not tab_number then
		error("Tab number expected", 2)
	end
	local inventory = get_inventory()
	if inventory > 0 then
		local active_item = get_active_item()
		local inventory_slot
		-- If we're already holding 4 wands and have none selected, don't do anything, otherwise swap the held wand with the stored one
		if not has_enough_space_for_wand() and active_item then
			if not is_wand(active_item) then
				return
			else
				-- Swap
				inventory_slot = get_inventory_position(active_item)
				put_wand_in_storage(active_item, tab_number)
			end
		end
		local first_free_wand_slot = get_first_free_wand_slot()
		-- Make sure we only pick up the wand if either we have a wand selected that we will swap with, or have enough space
		if inventory_slot or first_free_wand_slot then
			create_and_pick_up_wand(wand.serialized_poly, inventory_slot or first_free_wand_slot)
			EntityKill(wand.container_entity_id)
			async(function()
				wait(0)
				wand_storage_changed = true
			end)
		end
	end
end

local function uninventorify_entity(entity_id)
	EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_hand", false)
	EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_inventory", false)
	EntitySetComponentsWithTagEnabled(entity_id, "enabled_in_world", true)
	EntityRemoveFromParent(entity_id)
end

local function remove_entity_from_inventory(entity_id)
	if type(entity_id) ~= "number" then return end
	uninventorify_entity(entity_id)
	local player = EntityGetWithTag("player_unit")[1]
	if player then
		local inv2 = EntityGetFirstComponentIncludingDisabled(player, "Inventory2Component")
		if inv2 then
			local mActiveItem = ComponentGetValue2(inv2, "mActiveItem")
			if entity_id == mActiveItem then
				ComponentSetValue2(inv2, "mActiveItem", 0)
				ComponentSetValue2(inv2, "mActualActiveItem", 0)
				ComponentSetValue2(inv2, "mForceRefresh", true)
			end
		end
	end
	return entity_id
end

local function place_entity_in_front_of_player(entity_id)
	local player = EntityGetWithTag("player_unit")[1]
	local target_x, target_y = GameGetCameraPos()
	if player then
		local x, y, rot, scale_x = EntityGetTransform(player)
		target_x = x + 10 * scale_x
		target_y = y - 5
	end
	for i, child in ipairs(EntityGetAllChildren(entity_id) or {}) do
		EntityApplyTransform(child, target_x, target_y)
	end
	EntityApplyTransform(entity_id, target_x, target_y)
end

function take_out_wand_and_place_it_next_to_player(wand)
	local entity = remove_entity_from_inventory(wand)
	if not entity then
		entity = deserialize_entity(wand.serialized_poly)
		uninventorify_entity(entity)
		EntityKill(wand.container_entity_id)
	end
	place_entity_in_front_of_player(entity)
	if sounds_enabled then
		local cx, cy = GameGetCameraPos()
		GamePlaySound("data/audio/Desktop/ui.bank", "ui/item_remove", cx, cy)
	end
	local vel_comp = EntityGetFirstComponentIncludingDisabled(entity, "VelocityComponent")
	if vel_comp then
		ComponentSetValue2(vel_comp, "mVelocity", 0, -100)
	end
	wait(0)
	wand_storage_changed = true
end

function retrieve_or_swap_item(item, tab_number)
	if not tab_number then
		error("Tab number expected", 2)
	end
	local inventory = get_inventory()
	local item_storage = EntityGetWithName("item_storage_container")
	if inventory > 0 and item_storage > 0 then
		local active_item = get_active_item()
		local inventory_slot
		if not has_enough_space_for_item() and active_item then
			if not is_item(active_item) then
				return
			else
				-- Swap
				inventory_slot = get_inventory_position(active_item)
				put_item_in_storage(active_item, tab_number)
			end
		end
		local first_free_item_slot = get_first_free_item_slot()
		-- Make sure we only pick up the item if either we have an item selected that we will swap with, or have enough space
		if inventory_slot or first_free_item_slot then
			create_and_pick_up_item(item.serialized_poly, (inventory_slot or first_free_item_slot) + 4)
			EntityKill(item.container_entity_id)
			async(function()
				wait(0)
				item_storage_changed = true
			end)
		end
	end
end

function take_out_item_and_place_it_next_to_player(item)
	local entity = remove_entity_from_inventory(item)
	if not entity then
		entity = deserialize_entity(item.serialized_poly)
		uninventorify_entity(entity)
		EntityKill(item.container_entity_id)
	end
	if sounds_enabled then
		local cx, cy = GameGetCameraPos()
		GamePlaySound("data/audio/Desktop/ui.bank", "ui/item_remove", cx, cy)
	end
	place_entity_in_front_of_player(entity)
	wait(0)
	item_storage_changed = true
end

function get_first_free_wand_slot()
	local wands = get_held_wands()
	local free_wand_slots = { true, true, true, true }
	for i, wand in ipairs(wands) do
		free_wand_slots[wand.inventory_slot+1] = false
	end
	for slot, slot_is_free in ipairs(free_wand_slots) do
		if slot_is_free then
			return slot-1
		end
	end
end

function get_first_free_item_slot()
	local items = get_held_items()
	local free_item_slots = { true, true, true, true }
	for i, item in ipairs(items) do
		free_item_slots[item.inventory_slot+1] = false
	end
	for slot, slot_is_free in ipairs(free_item_slots) do
		if slot_is_free then
			return slot-1
		end
	end
end

local sprite_xml_path_cache = {}
local _ModTextFileGetContent = ModTextFileGetContent
function get_xml_sprite(sprite_xml_path)
	if sprite_xml_path_cache[sprite_xml_path] then
		return sprite_xml_path_cache[sprite_xml_path]
	end
	local xml = nxml.parse(_ModTextFileGetContent(sprite_xml_path))
	sprite_xml_path_cache[sprite_xml_path] = xml.attr.filename
	return xml.attr.filename
end

function OnPlayerSpawned(player)
	GlobalsSetValue("InventoryBags_is_open", "0")
	GlobalsSetValue("InventoryBags_active_wand_tab", tostring(active_wand_tab))
	GlobalsSetValue("InventoryBags_active_item_tab", tostring(active_item_tab))
	if not spell_lookup then
		spell_lookup = {}
		dofile_once("data/scripts/gun/gun_actions.lua")
		for i, action in ipairs(actions) do
			spell_lookup[action.id] = {
				icon = action.sprite,
				type = action.type
			}
		end
	end
	local function create_and_add_tab_storage_entities(parent_container_id, num_tabs)
		local first_tab_storage_entity
		for i=1, num_tabs do
			local tab_entity = EntityCreateNew("tab_" .. i)
			if i == 1 then
				first_tab_storage_entity = tab_entity
			end
			EntityAddChild(parent_container_id, tab_entity)
		end
		return first_tab_storage_entity
	end
	local wand_storage = EntityGetWithName("wand_storage_container")
	if wand_storage == 0 then
		wand_storage = EntityCreateNew("wand_storage_container")
		create_and_add_tab_storage_entities(wand_storage, 5)
		EntityAddChild(player, wand_storage)
		GlobalsSetValue("InventoryBags_active_storage_version", storage_version)
	else
		if tonumber(GlobalsGetValue("InventoryBags_active_storage_version", "0")) ~= storage_version then
			local old_wands = EntityGetAllChildren(wand_storage)
			local first_tab_storage_entity = create_and_add_tab_storage_entities(wand_storage, 5)
			-- Child entities are serialized wands
			for i, entity_id in ipairs(old_wands or {}) do
				EntityRemoveFromParent(entity_id)
				EntityAddChild(first_tab_storage_entity, entity_id)
			end
		end
	end
	local item_storage = EntityGetWithName("item_storage_container")
	if item_storage == 0 then
		item_storage = EntityCreateNew("item_storage_container")
		create_and_add_tab_storage_entities(item_storage, 5)
		EntityAddChild(player, item_storage)
	else
		if tonumber(GlobalsGetValue("InventoryBags_active_storage_version", "0")) ~= storage_version then
			GlobalsSetValue("InventoryBags_active_storage_version", storage_version)
			local old_items = EntityGetAllChildren(item_storage)
			local first_tab_storage_entity = create_and_add_tab_storage_entities(item_storage, 5)
			-- Child entities are serialized items
			for i, entity_id in ipairs(old_items or {}) do
				EntityRemoveFromParent(entity_id)
				EntityAddChild(first_tab_storage_entity, entity_id)
			end
		end
	end
end

function is_inventory_open()
	local player = EntityGetWithTag("player_unit")[1]
	if player then
		local inventory_gui_component = EntityGetFirstComponentIncludingDisabled(player, "InventoryGuiComponent")
		if inventory_gui_component then
			return ComponentGetValue2(inventory_gui_component, "mActive")
		end
	end
end

sounds_enabled = ModSettingGet("InventoryBags.sounds_enabled") or false
button_pos_x = ModSettingGet("InventoryBags.pos_x") or 2
button_pos_y = ModSettingGet("InventoryBags.pos_y") or 22
button_locked = ModSettingGet("InventoryBags.locked")
show_wand_bag = ModSettingGet("InventoryBags.show_wand_bag")
show_item_bag = ModSettingGet("InventoryBags.show_item_bag")
show_tabs = ModSettingGet("InventoryBags.show_tabs")
num_tabs_wands = tonumber(ModSettingGet("InventoryBags.num_tabs_wands")) or 5
num_tabs_items = tonumber(ModSettingGet("InventoryBags.num_tabs_items")) or 5
local opening_inv_closes_bags = ModSettingGet("InventoryBags.opening_inv_closes_bags")
local auto_storage = ModSettingGet("InventoryBags.auto_storage")
local auto_storage_blocklist_type = ModSettingGet("InventoryBags.list_type") or "blacklist"
local auto_storage_num_blocklist_entries = ModSettingGet("InventoryBags.num_blocklist_entries") or 0
local auto_storage_blocklist_entries = {}
for i=1, auto_storage_num_blocklist_entries do
	local entry = ModSettingGet("InventoryBags.blocklist_entries." .. tostring(i))
  table.insert(auto_storage_blocklist_entries, entry)
end

local tab_labels = {
	wands = {},
	items = {},
}

function load_label_settings()
	for i=1, 5 do
		tab_labels.wands[i] = ModSettingGet("InventoryBags.tab_label_wands_" .. i) or ""
		tab_labels.items[i] = ModSettingGet("InventoryBags.tab_label_items_" .. i) or ""
	end
end

load_label_settings()

local bags_wand_capacity = ModSettingGet("InventoryBags.wands_per_tab")
local bags_item_capacity = ModSettingGet("InventoryBags.items_per_tab")

-- OnModSettingsChanged() seems to not work
function OnPausedChanged(is_paused, is_inventory_pause)
	if not button_locked and is_paused then
		ModSettingSetNextValue("InventoryBags.pos_x", button_pos_x, false)
		ModSettingSetNextValue("InventoryBags.pos_y", button_pos_y, false)
	else
		button_pos_x = ModSettingGet("InventoryBags.pos_x") or 2
		button_pos_y = ModSettingGet("InventoryBags.pos_y") or 22
	end
	sounds_enabled = ModSettingGet("InventoryBags.sounds_enabled") or false
	button_locked = ModSettingGet("InventoryBags.locked")
	show_wand_bag = ModSettingGet("InventoryBags.show_wand_bag")
	show_item_bag = ModSettingGet("InventoryBags.show_item_bag")
	num_tabs_wands = tonumber(ModSettingGet("InventoryBags.num_tabs_wands")) or 5
	num_tabs_items = tonumber(ModSettingGet("InventoryBags.num_tabs_items")) or 5
	bags_wand_capacity = ModSettingGet("InventoryBags.wands_per_tab")
	bags_item_capacity = ModSettingGet("InventoryBags.items_per_tab")
	opening_inv_closes_bags = ModSettingGet("InventoryBags.opening_inv_closes_bags")
	auto_storage = ModSettingGet("InventoryBags.auto_storage")

	auto_storage_blocklist_type = ModSettingGet("InventoryBags.list_type") or "blacklist"
	auto_storage_num_blocklist_entries = ModSettingGet("InventoryBags.num_blocklist_entries") or 0
	auto_storage_blocklist_entries = {}
	for i=1, auto_storage_num_blocklist_entries do
		local entry = ModSettingGet("InventoryBags.blocklist_entries." .. tostring(i))
	  table.insert(auto_storage_blocklist_entries, entry)
	end

	max_wand_rows = math.ceil(bags_wand_capacity / 4)
	max_item_rows = math.ceil(bags_item_capacity / 4)
	load_label_settings()
end

local function blocklist_check(item_comp)
	local item_name = ComponentGetValue2(item_comp, "item_name")
	if auto_storage_blocklist_type == "whitelist" then
		for i=1, auto_storage_num_blocklist_entries do
			local item_name = utf8.lower(GameTextGetTranslatedOrNot(item_name))
			local name_found = utf8.find(item_name, auto_storage_blocklist_entries[i]:lower(), 1, true)
			if name_found then
				return true
			end
		end
		return false
	else
		for i=1, auto_storage_num_blocklist_entries do
			local item_name = utf8.lower(GameTextGetTranslatedOrNot(item_name))
			local name_found = utf8.find(item_name, auto_storage_blocklist_entries[i]:lower(), 1, true)
			if name_found then
				return false
			end
		end
		return true
	end
end

function wand_bag_has_space()
	local wands = get_stored_wands(active_wand_tab)
	return #wands < bags_wand_capacity
end

function item_bag_has_space()
	local items = get_stored_items(active_item_tab)
	return #items < bags_item_capacity
end

function quick_store()
	local active_item = get_active_item() or -1
	if EntityGetIsAlive(active_item) then
		if is_wand(active_item) then
			if wand_bag_has_space() then
				async(function()
					put_wand_in_storage(active_item, active_wand_tab)
					scroll_inventory(1)
				end)
			end
		else
			if item_bag_has_space() then
				async(function()
					put_item_in_storage(active_item, active_item_tab)
					scroll_inventory(1)
				end)
			end
		end
	end
end

function swap_with_last_stored_item()
	async(function()
		while swap_in_progress do
			wait(1)
		end
		swap_in_progress = true
		local name = EntityGetName(last_stored_entity.container_entity_id)
		local temp = last_stored_entity
		local active_item = get_active_item()
		if not active_item then return end
		local inventory_slot = get_inventory_position(active_item)
		if name == "InventoryBags_stored_wand" and is_wand(active_item) then
			put_wand_in_storage(active_item, last_stored_entity.tab_number)
			local first_free_wand_slot = get_first_free_wand_slot()
			local serialized, slot = temp.serialized_poly, inventory_slot or first_free_wand_slot
			pick_up_wand_and_place_in_inventory(deserialize_entity(serialized), slot) -- wait(0)
			scroll_inventory_to_slot(slot)
			EntityKill(temp.container_entity_id)
			entity_killed_this_frame = temp.container_entity_id
			wand_storage_changed = true
		elseif name == "InventoryBags_stored_item" and is_item(active_item) then
			put_item_in_storage(active_item, last_stored_entity.tab_number)
			local first_free_item_slot = get_first_free_item_slot()
			local serialized, slot = temp.serialized_poly, inventory_slot or first_free_item_slot
			pick_up_item_and_place_in_inventory(deserialize_entity(serialized), slot) -- wait(0)
			scroll_inventory_to_slot(slot)
			EntityKill(temp.container_entity_id)
			entity_killed_this_frame = temp.container_entity_id
			item_storage_changed = true
		end
		swap_in_progress = false
	end)
end

function OnWorldPreUpdate()
  if opening_inv_closes_bags and GameIsInventoryOpen() then
    open = false
		GlobalsSetValue("InventoryBags_is_open", "0")
  end
	if auto_storage then
		if wand_bag_has_space() then
			for i, wand in ipairs(get_held_wands()) do
				local item_comp = EntityGetFirstComponentIncludingDisabled(wand.entity_id, "ItemComponent")
				if item_comp and wand.baggable and ComponentGetValue2(item_comp, "mFramePickedUp") == GameGetFrameNum() and blocklist_check(item_comp) then
					async(function()
						put_wand_in_storage(wand.entity_id, active_wand_tab)
					end)
				end
			end
		end
		if item_bag_has_space() then
			for i, item in ipairs(get_held_items()) do
				local item_comp = EntityGetFirstComponentIncludingDisabled(item.entity_id, "ItemComponent")
				if item_comp and item.baggable and ComponentGetValue2(item_comp, "mFramePickedUp") == GameGetFrameNum() and blocklist_check(item_comp) then
					async(function()
						put_item_in_storage(item.entity_id, active_item_tab)
					end)
				end
			end
		end
	end
	-- This is for making async functions work
	wake_up_waiting_threads(1)
	-- Detect polymorph
	local player = EntityGetWithTag("player_unit")[1]
	if not player then
		was_polymorphed = true
		return
	end
	if was_polymorphed then
		was_polymorphed = false
		wand_storage_changed = true
		item_storage_changed = true
	end

	gui = gui or GuiCreate()
	open = open or false
	current_id = 1
	local function new_id()
		current_id = current_id + 1
		return current_id
	end
	GuiStartFrame(gui)
	if GameGetIsGamepadConnected() then
		GuiOptionsAdd(gui, GUI_OPTION.NonInteractive)
	end
	GuiOptionsAdd(gui, GUI_OPTION.NoPositionTween)
  -- Allow speed clicking
  GuiOptionsAdd(gui, GUI_OPTION.HandleDoubleClickAsClick)
  GuiOptionsAdd(gui, GUI_OPTION.ClickCancelsDoubleClick)

	local inventory_open = is_inventory_open()
	-- If button dragging is enabled in the settings and the inventory is not open, make it draggable
	if not inventory_open and not button_locked then
		GuiOptionsAddForNextWidget(gui, GUI_OPTION.IsExtraDraggable)
		GuiOptionsAddForNextWidget(gui, GUI_OPTION.DrawNoHoverAnimation)
		GuiImageButton(gui, 5318008, button_pos_x, button_pos_y, "", "mods/InventoryBags/files/gui_button_invisible.png")
		local _, _, hovered, x, y, draw_width, draw_height, draw_x, draw_y = GuiGetPreviousWidgetInfo(gui)
		if draw_x ~= 0 and draw_y ~= 0 and draw_x ~= button_pos_x and draw_y ~= button_pos_y then
			button_pos_x = draw_x - draw_width / 2
			button_pos_y = draw_y - draw_height / 2
		end
	end
	if _get_binding_pressed("quick_store") then
		quick_store()
	end
	if _get_binding_pressed("swap_with_last_stored_item") then
		swap_with_last_stored_item()
	end
	-- Toggle it open/closed
	if not inventory_open and (GuiImageButton(gui, new_id(), button_pos_x, button_pos_y, "", "mods/InventoryBags/files/gui_button.png")
		or _get_binding_pressed("toggle")) then
		open = not open
		if sounds_enabled then
			local px, py = EntityGetFirstHitboxCenter(player)
			GamePlaySound("data/audio/Desktop/ui.bank", "ui/inventory_" .. (open and "open" or "close"), px, py)
		end
		GlobalsSetValue("InventoryBags_is_open", open and 1 or 0)
	end

	if open and not inventory_open then
		local slot_width, slot_height = 16, 16
		local slot_margin = 1
		local slot_width_total, slot_height_total = (slot_width + slot_margin * 2), (slot_height + slot_margin * 2)
		local spacer = 4
		local held_wands = get_held_wands()
		local stored_wands = get_stored_wands(active_wand_tab)
		local held_items = get_held_items()
		local stored_items = get_stored_items(active_item_tab)
		local rows_wands = math.max(4, math.ceil((#stored_wands + 1) / 4))
		local rows_items = math.max(4, math.ceil((#stored_items + 1) / 4))
		local box_width = slot_width_total * 4
		local box_height_wands = slot_height_total * (rows_wands+1) + spacer
		local box_height_items = slot_height_total * (rows_items+1) + spacer
		local origin_x, origin_y = 23, 48
		-- Render wand bag
		local tooltip_wand
		if show_wand_bag then
			GuiZSetForNextWidget(gui, 20)
			GuiImageNinePiece(gui, new_id(), origin_x, origin_y, box_width, box_height_wands, 1, "mods/InventoryBags/files/container_9piece.png", "mods/InventoryBags/files/container_9piece.png")
			-- Render an invisible image over the whole bag to prevent clicks firing wands
			for offset_y=0, box_height_wands+8, 10 do
				GuiZSetForNextWidget(gui, -99999)
				GuiImage(gui, new_id(), origin_x - 4, origin_y - 4 + offset_y, "mods/InventoryBags/files/invisible_80x10.png", 1, 1, 1)
			end
			-- Render tabs
			for i=1, num_tabs_wands do
				local add_text_offset = 0
				if i == 1 then
					add_text_offset = 1
				end
				GuiZSetForNextWidget(gui, 21)
				local is_active_wand_tab = function() return active_wand_tab == i end
				if GuiImageButton(gui, new_id(), origin_x - 16, origin_y + 5 + (i-1) * 17, "", "mods/InventoryBags/files/tab_left_empty" .. (is_active_wand_tab() and "_active" or "") .. ".png") then
					active_wand_tab = i
					GlobalsSetValue("InventoryBags_active_wand_tab", tostring(active_wand_tab))
					wand_storage_changed = true
				end
				if tab_labels.wands[i] ~= "" then
					GuiTooltip(gui, tab_labels.wands[i], "")
				end
				GuiColorSetForNextWidget(gui, 1, 1, 1, is_active_wand_tab() and 0.8 or 0.5)
				GuiText(gui, origin_x - 10 + add_text_offset, origin_y + 8 + (i-1) * 17, i)
			end
			local taken_slots = {}
			-- Render the held wands and save the taken positions so we can render the empty slots after this
			for i, wand in ipairs(held_wands) do
				if wand then
					taken_slots[wand.inventory_slot] = true
					local left_clicked, right_clicked = GuiImageButton(gui, new_id(), origin_x + slot_margin + wand.inventory_slot * slot_width_total, origin_y + slot_margin, "", "data/ui_gfx/inventory/inventory_box.png")
					if left_clicked and wand_bag_has_space() then
						if wand.baggable then
							async(function()
								put_wand_in_storage(wand.entity_id, active_wand_tab)
							end)
						else
							local var_store = get_variable_storage_component(wand.entity_id, "InventoryBags_not_baggable")
							-- To indicate that an attempt was made to put this into the bag, for other mods to read out if they want
							ComponentSetValue2(var_store, "value_bool", true)
						end
					elseif right_clicked then
						async(function()
							take_out_wand_and_place_it_next_to_player(wand.entity_id)
						end)
					end
					local _, _, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
					local w, h = GuiGetImageDimensions(gui, wand.image_file, 1) -- scale
					local scale = hovered and 1.2 or 1
					if hovered then
						tooltip_wand = EZWand.Deserialize(EZWand(wand.entity_id):Serialize()) --wand.entity_id
					end
					GuiZSetForNextWidget(gui, -9)
					if wand.active then
						GuiImage(gui, new_id(), x + (width / 2 - (16 * scale) / 2), y + (height / 2 - (16 * scale) / 2), "mods/InventoryBags/files/highlight_box.png", 1, scale, scale)
					end
					GuiZSetForNextWidget(gui, -10)
					GuiImage(gui, new_id(), x + (width / 2 - (w * scale) / 2), y + (height / 2 - (h * scale) / 2), wand.image_file, 1, scale, scale, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
				end
			end
			for i=0, (4-1) do
				if not taken_slots[i] then
					GuiImage(gui, new_id(), origin_x + slot_margin + i * slot_width_total, origin_y + slot_margin, "data/ui_gfx/inventory/inventory_box.png", 1, 1, 1)
				end
			end
			for iy=0, (rows_wands-1) do
				for ix=0, (4-1) do
					local idx = (iy*4 + ix) + 1
					local wand = stored_wands[(iy*4 + ix) + 1]
					if wand then
						local left_clicked, right_clicked = GuiImageButton(gui, new_id(), origin_x + slot_margin + ix * slot_width_total, origin_y + spacer + slot_margin + slot_height_total + iy * slot_height_total, "", "data/ui_gfx/inventory/inventory_box.png")
						if left_clicked then
							async(function()
								retrieve_or_swap_wand(wand, active_wand_tab)
							end)
						elseif right_clicked then
							async(function()
								take_out_wand_and_place_it_next_to_player(wand)
							end)
						end
						local _, _, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
						local w, h = GuiGetImageDimensions(gui, wand.sprite_image_file, 1) -- scale
						local scale = hovered and 1.2 or 1
						if hovered then
							tooltip_wand = wand
						end
						GuiZSetForNextWidget(gui, -10)
						GuiImage(gui, new_id(), x + (width / 2 - (w * scale) / 2), y + (height / 2 - (h *scale) / 2), wand.sprite_image_file, 1, scale, scale, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
					else
						if idx > bags_wand_capacity then
							GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
						end
						GuiImage(gui, new_id(), origin_x + slot_margin + ix * slot_width_total, origin_y + spacer + slot_margin + slot_height_total + iy * slot_height_total, "data/ui_gfx/inventory/inventory_box.png", 1, 1, 1)
					end
				end
			end
			-- Render sort icons
			local icon_w, icon_h = 14, 14
			local icons_per_row = 4
			local xxx = box_width - icon_w * icons_per_row
			GuiZSetForNextWidget(gui, 21)
			GuiImageNinePiece(gui, new_id(), origin_x + xxx - 8, origin_y + box_height_wands, icon_w * icons_per_row, icon_h * 2 + 4, 1, "mods/InventoryBags/files/container_9piece.png", "mods/InventoryBags/files/container_9piece.png")
			-- Render click blocking images
			for i=1, 3 do
				GuiZSetForNextWidget(gui, -99999)
				GuiImage(gui, new_id(), origin_x - 4, origin_y + box_height_wands + (i-1) * 10, "mods/InventoryBags/files/invisible_80x10.png", 1, 1, 1)
			end
			for i, v in ipairs(sorting_functions) do
				local offset_x = (i-1) * icon_w-- + 4
				local offset_y = math.floor((i - 1) / icons_per_row) * icon_h -- + 8
				offset_x = offset_x % (icon_w * icons_per_row)
				local x = origin_x + offset_x + xxx / 2 + 4
				local y = origin_y + box_height_wands + offset_y + 8
				local left_clicked, right_clicked = GuiImageButton(gui, new_id(), x, y, "", v[1])
				GuiTooltip(gui, ("Sort wands by %s"):format(v[3]), "Left click = Sort ascending\nRight click = Sort descending")
				if left_clicked or right_clicked then
					-- wand_storage_changed = true
					if sounds_enabled then
						local cx, cy = GameGetCameraPos()
						GamePlaySound("data/audio/Desktop/ui.bank", "ui/item_move_success", cx, cy)
					end
					GlobalsSetValue("InventoryBags_wand_sort_index", tostring(i))
					GlobalsSetValue("InventoryBags_wand_sort_direction", tostring(left_clicked and sorting_directions.ASCENDING or sorting_directions.DESCENDING))
					sort_stored_wands(cached_stored_wands)
				end
			end
		end
		-- Render item bag
		local tooltip_item
		if show_item_bag then
			origin_x = origin_x + box_width + 9
			GuiZSetForNextWidget(gui, 20)
			GuiImageNinePiece(gui, new_id(), origin_x, origin_y, box_width, box_height_items, 1, "mods/InventoryBags/files/container_9piece.png", "mods/InventoryBags/files/container_9piece.png")
			-- Render an invisible image over the whole bag to prevent clicks firing wands
			for offset_y=0, box_height_items+8, 10 do
				GuiZSetForNextWidget(gui, -99999)
				GuiImage(gui, new_id(), origin_x - 4, origin_y - 4 + offset_y, "mods/InventoryBags/files/invisible_80x10.png", 1, 1, 1)
			end
			-- Render tabs
			for i=1, num_tabs_items do
				local add_text_offset = 0
				if i == 1 then
					add_text_offset = 1
				end
				GuiZSetForNextWidget(gui, 21)
				local is_active_item_tab = function() return active_item_tab == i end
				if GuiImageButton(gui, new_id(), origin_x + 76, origin_y + 5 + (i-1) * 17, "", "mods/InventoryBags/files/tab_right_empty" .. (is_active_item_tab() and "_active" or "") .. ".png") then
					active_item_tab = i
					GlobalsSetValue("InventoryBags_active_item_tab", tostring(active_item_tab))
					item_storage_changed = true
				end
				if tab_labels.items[i] ~= "" then
					GuiTooltip(gui, tab_labels.items[i], "")
				end
				GuiColorSetForNextWidget(gui, 1, 1, 1, is_active_item_tab() and 0.8 or 0.5)
				GuiText(gui, origin_x + 78 + add_text_offset, origin_y + 8 + (i-1) * 17, i)
			end
			local taken_slots = {}
			-- Render the held items and save the taken positions so we can render the empty slots after this
			for i, item in ipairs(held_items) do
				if item then
					taken_slots[item.inventory_slot] = true
					local left_clicked, right_clicked = GuiImageButton(gui, new_id(), origin_x + slot_margin + item.inventory_slot * slot_width_total, origin_y + slot_margin, "", "data/ui_gfx/inventory/inventory_box.png")
					if left_clicked and item_bag_has_space() then
						if item.baggable then
							async(function()
								put_item_in_storage(item.entity_id, active_item_tab)
							end)
						else
							local var_store = get_variable_storage_component(item.entity_id, "InventoryBags_not_baggable")
							-- To indicate that an attempt was made to put this into the bag, for other mods to read out if they want
							ComponentSetValue2(var_store, "value_bool", true)
						end
					elseif right_clicked then
						async(function()
							take_out_item_and_place_it_next_to_player(item.entity_id)
						end)
					end
					local _, _, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
					local w, h = GuiGetImageDimensions(gui, item.image_file, 1)
					local scale = hovered and 1.2 or 1
					if hovered then
						local image_file, potion_color, tooltip = tooltipify_item(item.entity_id)
						tooltip_item = tooltip
					end
					GuiZSetForNextWidget(gui, -9)
					if item.active then
						GuiImage(gui, new_id(), x + (width / 2 - (16 * scale) / 2), y + (height / 2 - (16 * scale) / 2), "mods/InventoryBags/files/highlight_box.png", 1, scale, scale)
					end
					GuiZSetForNextWidget(gui, -10)
					local potion_color = GameGetPotionColorUint(item.entity_id)
					if potion_color ~= 0 then
						local b = bit.rshift(bit.band(potion_color, 0xFF0000), 16) / 0xFF
						local g = bit.rshift(bit.band(potion_color, 0xFF00), 8) / 0xFF
						local r = bit.band(potion_color, 0xFF) / 0xFF
						GuiColorSetForNextWidget(gui, r, g, b, 1)
					end
					GuiImage(gui, new_id(), x + (width / 2 - (w * scale) / 2), y + (height / 2 - (h * scale) / 2), item.image_file, 1, scale, scale, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
				end
			end
			for i=0, (4-1) do
				if not taken_slots[i] then
					GuiImage(gui, new_id(), origin_x + slot_margin + i * slot_width_total, origin_y + slot_margin, "data/ui_gfx/inventory/inventory_box.png", 1, 1, 1)
				end
			end
			for iy=0, (rows_items-1) do
				for ix=0, (4-1) do
					local idx = (iy*4 + ix) + 1
					local item = stored_items[(iy*4 + ix) + 1]
					if item then
						local left_clicked, right_clicked = GuiImageButton(gui, new_id(), origin_x + slot_margin + ix * slot_width_total, origin_y + spacer + slot_margin + slot_height_total + iy * slot_height_total, "", "data/ui_gfx/inventory/inventory_box.png")
						if left_clicked then
							async(function()
								retrieve_or_swap_item(item, active_item_tab)
							end)
						elseif right_clicked then
							async(function()
								take_out_item_and_place_it_next_to_player(item)
							end)
						end
						local _, _, hovered, x, y, width, height = GuiGetPreviousWidgetInfo(gui)
						local w, h = GuiGetImageDimensions(gui, item.image_file, 1)
						local scale = hovered and 1.2 or 1
						if hovered then
							tooltip_item = item.tooltip
						end
						GuiZSetForNextWidget(gui, -10)
						local potion_color = item.potion_color
						if potion_color ~= 0 then
							local b = bit.rshift(bit.band(potion_color, 0xFF0000), 16) / 0xFF
							local g = bit.rshift(bit.band(potion_color, 0xFF00), 8) / 0xFF
							local r = bit.band(potion_color, 0xFF) / 0xFF
							GuiColorSetForNextWidget(gui, r, g, b, 1)
						end
						GuiImage(gui, new_id(), x + (width / 2 - (w * scale) / 2), y + (height / 2 - (h *scale) / 2), item.image_file, 1, scale, scale, 0, GUI_RECT_ANIMATION_PLAYBACK.Loop)
					else
						if idx > bags_item_capacity then
							GuiColorSetForNextWidget(gui, 0.8, 0.8, 0.8, 1)
						end
						GuiImage(gui, new_id(), origin_x + slot_margin + ix * slot_width_total, origin_y + spacer + slot_margin + slot_height_total + iy * slot_height_total, "data/ui_gfx/inventory/inventory_box.png", 1, 1, 1)
					end
				end
			end
		end
		-- Render a tooltip of the hovered wand if we have any
		if tooltip_wand then
			EZWand.RenderTooltip(origin_x + box_width + 30, origin_y + 5, tooltip_wand, gui, -100)
		end
		-- Render a tooltip of the hovered item if we have any
		if tooltip_item then
			GuiBeginAutoBox(gui)
			GuiLayoutBeginHorizontal(gui, origin_x + box_width + 30, origin_y + 5, true)
			GuiLayoutBeginVertical(gui, 0, 0)
			local lines = split_string(tooltip_item, "\n")
			for i, line in ipairs(lines) do
				local offset = line == " " and -7 or 0
				GuiZSetForNextWidget(gui, -101)
				GuiText(gui, 0, offset, line)
			end
			GuiLayoutEnd(gui)
			GuiLayoutEnd(gui)
			GuiZSetForNextWidget(gui, -100)
			GuiEndAutoBoxNinePiece(gui)
		end
	end
end
