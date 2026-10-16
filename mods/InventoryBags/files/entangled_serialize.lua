local base64 = dofile_once("mods/quant.ew/files/resource/base64.lua")

util.add_cross_call("InventoryBags_serialize_entity", function(entity_id)
  return base64.encode(np.SerializeEntity(entity_id))
end)

util.add_cross_call("InventoryBags_deserialize_entity", function(serialized, x, y)
  return util.deserialize_entity(base64.decode(serialized), x, y)
end)

return {}
