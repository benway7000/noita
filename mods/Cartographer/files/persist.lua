-- Per-run persistence.
--
-- The map is written to its own file in the save folder rather than into the
-- run's globals. Globals end up inside world_state.xml, and a long run's map
-- runs to megabytes, which is not something to trust the engine's XML
-- handling with. A file of our own has no such concerns, so the payload is
-- stored as raw bytes with no base64 and no size cap. This is why the mod
-- needs request_no_api_restrictions: a sandboxed mod has no io.
--
-- The save folder outlives any one run, so the file carries a run id and is
-- only trusted when that id matches the one kept in the run's globals. A new
-- game has no id yet, gets a fresh one, and so never picks up an old map.
-- NG+ keeps the run's globals but not its world, so the NG+ cycle is part of
-- the id too.
--
-- Serialising a thousand chunks at once would cost a visible hitch, so the
-- work is spread over frames: a snapshot of the chunk list is taken and a
-- handful are encoded per frame until the job finishes and the file is
-- written.

local C = dofile_once("mods/cartographer/files/config.lua")
local store = dofile_once("mods/cartographer/files/store.lua")
local markers = dofile_once("mods/cartographer/files/markers.lua")

local CHUNK = C.CHUNK
local UNKNOWN = C.UNKNOWN
local EMPTY_ROW = string.rep(string.char(UNKNOWN), CHUNK)

local floor = math.floor
local schar, sbyte, ssub = string.char, string.byte, string.sub
local concat = table.concat

local FILE_NAME = "cartographer_map.dat"
local FILE_MAGIC = "CARTOGRAPHER 2"
local KEY_RUN = "CARTOGRAPHER_RUN_ID"
local VERSION = "VM1" -- chunk payload format, shared with the old globals

-- Where runs started before the move to a file kept their map. Read once to
-- migrate, then cleared after the first successful file write.
local LEGACY_KEYS = {
	{ count = "CARTOGRAPHER_PARTS", part = "CARTOGRAPHER_DATA_", markers = "CARTOGRAPHER_MARKERS" },
	-- From before the mod was renamed.
	{ count = "VALHEIM_MAP_PARTS", part = "VALHEIM_MAP_DATA_", markers = "VALHEIM_MAP_MARKERS" },
}

local M = {}

M.chunks_per_frame = 24
M.autosave_interval = 1800 -- frames (~30s at 60fps)

-- Why the last save failed, or nil. Shown on the map so a failure is never
-- silent: reloading would lose everything explored since the last good save.
M.error = nil

local job = nil
local last_save_frame = 0
local loaded = false
local run_id = nil
-- NG+ cycle the map belongs to. NG+ keeps the run (and its globals) but
-- regenerates the world, so the map is keyed on run id + cycle.
local ng_plus = nil
-- Cleared on the first file write of the session. Checked every session rather
-- than only after a migration, in case a crash lost the clear last time.
local legacy_pending = true

local function ng_plus_count()
	return tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0
end

local function file_id()
	return run_id .. ":" .. ng_plus
end

-- ------------------------------------------------------------------- paths

-- Noita keeps its saves under %USERPROFILE%\AppData\LocalLow, and Proton
-- sets USERPROFILE too, so this holds on Linux as well.
local function file_path()
	local home = os.getenv("USERPROFILE")
	if not home or home == "" then return nil end
	return home .. "\\AppData\\LocalLow\\Nolla_Games_Noita\\save00\\" .. FILE_NAME
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

-- Write to a temp file and swap it in, so a crash mid-write can never leave
-- a truncated map behind. Windows will not rename over an existing file, so
-- the old one is removed first; load() falls back to the temp file to cover
-- a crash in that gap.
local function write_file(data)
	local path = file_path()
	if not path then return false, "save folder not found" end
	local tmp = path .. ".tmp"

	local f, err = io.open(tmp, "wb")
	if not f then return false, tostring(err) end
	local ok, werr = f:write(data)
	f:close()
	if not ok then
		os.remove(tmp)
		return false, tostring(werr)
	end

	os.remove(path)
	local rok, rerr = os.rename(tmp, path)
	if not rok then return false, tostring(rerr) end
	return true
end

-- ------------------------------------------------------------------ base64

-- Only needed to read maps out of the old globals.

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, #B64 do B64R[ssub(B64, i, i)] = i - 1 end

local function b64decode(s)
	s = s:gsub("[^A-Za-z0-9+/=]", "")
	local out = {}
	local i = 1
	while i + 3 <= #s do
		local c1, c2, c3, c4 = ssub(s, i, i), ssub(s, i + 1, i + 1), ssub(s, i + 2, i + 2), ssub(s, i + 3, i + 3)
		local v = (B64R[c1] or 0) * 262144 + (B64R[c2] or 0) * 4096
		if c3 == "=" then
			out[#out + 1] = schar(floor(v / 65536) % 256)
		elseif c4 == "=" then
			v = v + (B64R[c3] or 0) * 64
			out[#out + 1] = schar(floor(v / 65536) % 256, floor(v / 256) % 256)
		else
			v = v + (B64R[c3] or 0) * 64 + (B64R[c4] or 0)
			out[#out + 1] = schar(floor(v / 65536) % 256, floor(v / 256) % 256, v % 256)
		end
		i = i + 4
	end
	return concat(out)
end

-- --------------------------------------------------------------------- RLE

local function rle_encode(s)
	local out = {}
	local i, n = 1, #s
	while i <= n do
		local v = sbyte(s, i)
		local j = i + 1
		while j <= n and sbyte(s, j) == v and (j - i) < 255 do j = j + 1 end
		out[#out + 1] = schar(v, j - i)
		i = j
	end
	return concat(out)
end

local function rle_decode(s, expect)
	local out = {}
	local i = 1
	while i + 1 <= #s do
		out[#out + 1] = string.rep(schar(sbyte(s, i)), sbyte(s, i + 1))
		i = i + 2
	end
	local r = concat(out)
	if expect and #r < expect then r = r .. string.rep(schar(UNKNOWN), expect - #r) end
	return r
end

-- ------------------------------------------------------------------ packing

local function u16(n) return schar(n % 256, floor(n / 256) % 256) end
local function u32(n)
	return schar(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end
local function ru16(s, i) return sbyte(s, i) + sbyte(s, i + 1) * 256, i + 2 end
local function ru32(s, i)
	return sbyte(s, i) + sbyte(s, i + 1) * 256 + sbyte(s, i + 2) * 65536 + sbyte(s, i + 3) * 16777216, i + 4
end

local function encode_chunk(ch)
	local rows = {}
	for ry = 0, CHUNK - 1 do
		rows[#rows + 1] = ch.rows[ry] or EMPTY_ROW
	end
	local body = rle_encode(concat(rows))
	local biome = tostring(ch.biome or "")
	if #biome > 255 then biome = ssub(biome, 1, 255) end
	return u16(ch.gx + 32768) .. u16(ch.gy + 32768)
		.. schar(#biome) .. biome
		.. u32(#body) .. body
end

-- Rebuilds the store from a VM1 payload. Returns false if it is not one.
local function decode_payload(raw)
	if #raw < 7 or ssub(raw, 1, 3) ~= VERSION then return false end

	local i = 4
	local total
	total, i = ru32(raw, i)

	store.reset()
	for _ = 1, total do
		if i + 4 > #raw then break end
		local gx, gy, blen
		gx, i = ru16(raw, i)
		gy, i = ru16(raw, i)
		gx, gy = gx - 32768, gy - 32768
		blen = sbyte(raw, i); i = i + 1
		local biome = ssub(raw, i, i + blen - 1); i = i + blen
		local blen2
		blen2, i = ru32(raw, i)
		local body = ssub(raw, i, i + blen2 - 1); i = i + blen2

		local flat = rle_decode(body, CHUNK * CHUNK)
		local ch = store.chunk(gx, gy, true)
		ch.biome = (biome ~= "") and biome or nil
		local known = 0
		for ry = 0, CHUNK - 1 do
			local row = ssub(flat, ry * CHUNK + 1, (ry + 1) * CHUNK)
			if row ~= EMPTY_ROW then
				ch.rows[ry] = row
				for k = 1, CHUNK do
					if sbyte(row, k) ~= UNKNOWN then known = known + 1 end
				end
			end
		end
		ch.known = known
		ch.lod_stale = true
		store.known_cells = store.known_cells + known

		-- Rebuild explored bounds from what we restored.
		if known > 0 then
			local x0, y0 = gx * CHUNK, gy * CHUNK
			local x1, y1 = x0 + CHUNK - 1, y0 + CHUNK - 1
			if not store.min_cx then
				store.min_cx, store.max_cx, store.min_cy, store.max_cy = x0, x1, y0, y1
			else
				if x0 < store.min_cx then store.min_cx = x0 end
				if x1 > store.max_cx then store.max_cx = x1 end
				if y0 < store.min_cy then store.min_cy = y0 end
				if y1 > store.max_cy then store.max_cy = y1 end
			end
		end
	end

	return true
end

-- ---------------------------------------------------------------- save job

local function clear_legacy()
	for _, k in ipairs(LEGACY_KEYS) do
		local count = tonumber(GlobalsGetValue(k.count, "0")) or 0
		for p = 1, count do GlobalsSetValue(k.part .. p, "") end
		GlobalsSetValue(k.count, "0")
		GlobalsSetValue(k.markers, "")
	end
end

local function begin_job()
	local list = {}
	for _, col in pairs(store.chunks) do
		for _, ch in pairs(col) do
			if ch.known > 0 then list[#list + 1] = ch end
		end
	end
	job = { list = list, i = 1, parts = { VERSION, u32(#list) } }
end

-- File layout: a text header (magic, run id, marker byte count), then the
-- serialised markers, then the binary chunk payload.
local function finish_job()
	local m = markers.serialize()
	local data = FILE_MAGIC .. "\n" .. file_id() .. "\n" .. #m .. "\n" .. m .. concat(job.parts)
	job = nil
	last_save_frame = GameGetFrameNum()

	local ok, err = write_file(data)
	if not ok then
		M.error = err
		return
	end
	M.error = nil

	-- The map now lives in the file, so stop carrying the old copy around
	-- in the save.
	if legacy_pending then
		clear_legacy()
		legacy_pending = false
	end
end

-- Starting NG+ regenerates the world without respawning the player or
-- reloading mods, so the only sign is the cycle count going up. When it does,
-- the old map no longer describes anything: drop it (and any half-written
-- save of it) and let the scanner start over. Runs whether or not persistence
-- is on, since the in-memory map is just as stale either way.
function M.check_new_game_plus()
	local n = ng_plus_count()
	if ng_plus == nil then ng_plus = n end
	if n == ng_plus then return end
	ng_plus = n
	job = nil
	store.reset()
	markers.reset()
	last_save_frame = GameGetFrameNum()
end

function M.tick()
	if job then
		local n = 0
		while job.i <= #job.list and n < M.chunks_per_frame do
			job.parts[#job.parts + 1] = encode_chunk(job.list[job.i])
			job.i = job.i + 1
			n = n + 1
		end
		if job.i > #job.list then finish_job() end
		return
	end

	if not loaded then return end
	if GameGetFrameNum() - last_save_frame >= M.autosave_interval and store.chunk_count > 0 then
		begin_job()
	end
end

-- Runs the whole save immediately, for shutdown-ish moments.
function M.save_now()
	if not loaded then return end
	begin_job()
	while job do
		local n = 0
		while job.i <= #job.list and n < 4096 do
			job.parts[#job.parts + 1] = encode_chunk(job.list[job.i])
			job.i = job.i + 1
			n = n + 1
		end
		if job.i > #job.list then finish_job() end
	end
end

-- -------------------------------------------------------------------- load

-- Reads this run's map from the file. False if there is none, or if the file
-- belongs to some other run.
local function load_file()
	local path = file_path()
	if not path then return false end
	local data = read_file(path) or read_file(path .. ".tmp")
	if not data then return false end

	local id, mlen, pos = data:match("^" .. FILE_MAGIC .. "\n([^\n]*)\n(%d+)\n()")
	if not id then return false end
	-- Files written before NG+ keying carry the bare run id. Only trust those
	-- outside NG+, since there is no telling which cycle they were saved in.
	if id ~= file_id() and not (ng_plus == 0 and id == run_id) then return false end
	mlen = tonumber(mlen)

	markers.deserialize(ssub(data, pos, pos + mlen - 1))
	decode_payload(ssub(data, pos + mlen))
	return true
end

-- Reads a map left in the globals by an older version of the mod.
local function load_legacy()
	for _, k in ipairs(LEGACY_KEYS) do
		local count = tonumber(GlobalsGetValue(k.count, "0")) or 0
		if count > 0 then
			markers.deserialize(GlobalsGetValue(k.markers, ""))
			local parts = {}
			for p = 1, count do
				parts[#parts + 1] = GlobalsGetValue(k.part .. p, "")
			end
			return decode_payload(b64decode(concat(parts)))
		end
	end
	return false
end

function M.load()
	-- OnPlayerSpawned can fire more than once in a session (respawns, polymorph
	-- shenanigans). Reloading would reset the store and throw away everything
	-- explored since the last autosave, so only ever load once.
	if loaded then return false end
	loaded = true
	last_save_frame = GameGetFrameNum()

	run_id = GlobalsGetValue(KEY_RUN, "")
	if run_id == "" then
		run_id = ("%d-%d"):format(os.time(), floor(os.clock() * 1000000))
		GlobalsSetValue(KEY_RUN, run_id)
	end
	ng_plus = ng_plus_count()

	if load_file() then return true end
	return load_legacy()
end

return M
