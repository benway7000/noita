dofile_once("mods/AdvancedSpellInventory/lib/polytools/polytools_init.lua").init("mods/AdvancedSpellInventory/lib/polytools")
local polytools = dofile_once("mods/AdvancedSpellInventory/lib/polytools/polytools.lua")

local poly_place_x, poly_place_y = -951493, 993842
---Needs to be called from inside an async function. Kills entity and returns the serialized string after 1 frame.
function serialize_entity(entity)
	if not coroutine.running() then
		error("serialize_entity() must be called from inside an async function", 2)
	end
	EntityRemoveFromParent(entity)
	-- Need to do this because we poly the entity and thus lose the reference to it,
	-- because the polymorphed entity AND the one that it turns back into both have different entity_ids than the original
	-- That's why we first move it to some location where it will hopefully be the only entity, so we can later get it back
	-- But this also means that this location will be saved in the serialized string, and when it gets deserialized,
	-- will spawn there again (Test this later to confirm!!! Too lazy right now)
	EntityApplyTransform(entity, poly_place_x, poly_place_y)
	local serialized = polytools.save(entity)
	wait(0)
	-- Kill the wand AND call cards IF for some unknown reason they are also detected with EntityGetInRadius
	for i, v in ipairs(EntityGetInRadius(poly_place_x, poly_place_y, 5)) do
		EntityRemoveFromParent(v)
		EntityKill(v)
	end
	return serialized
end

function deserialize_entity(str)
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