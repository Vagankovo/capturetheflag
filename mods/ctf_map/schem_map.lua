assert(minetest.get_mapgen_setting("mg_name") == "singlenode", "singlenode mapgen is required.")

minetest.register_alias("mapgen_singlenode", "ctf_map:ignore")
minetest.register_alias("flowers:mushroom_red", "air")
minetest.register_alias("flowers:mushroom_brown", "air")
minetest.register_alias("flowers:waterlily", "air")
minetest.register_alias("flowers:rose", "air")
minetest.register_alias("flowers:tulip", "air")
minetest.register_alias("flowers:dandelion_yellow", "air")
minetest.register_alias("flowers:geranium", "air")
minetest.register_alias("flowers:viola", "air")
minetest.register_alias("flowers:dandelion_white", "air")
minetest.register_alias("flowers:chrysanthemum_green", "air")
minetest.register_alias("default:grass_1", "air")
minetest.register_alias("default:grass_2", "air")
minetest.register_alias("default:grass_3", "air")
minetest.register_alias("default:grass_4", "air")
minetest.register_alias("default:sand_with_kelp", "default:sand")
minetest.register_alias("default:grass_5", "air")
minetest.register_alias("default:bush_leaves", "air")
minetest.register_alias("default:bush_stem", "air")


local max_r  = 120
local mapdir = minetest.get_modpath("ctf_map") .. "/maps/"
ctf_map.map  = nil


do
	local files_hash = {}

	local dirs = minetest.get_dir_list(mapdir, true)
	table.insert(dirs, ".")
	for _, dir in pairs(dirs) do
		local files = minetest.get_dir_list(mapdir .. dir, false)
		for i=1, #files do
			files_hash[dir .. "/" .. files[i]:split(".")[1]] = true
		end
	end

	ctf_map.available_maps = {}
	for key, _ in pairs(files_hash) do
		table.insert(ctf_map.available_maps, key)
	end
	print(dump(ctf_map.available_maps))
end


function ctf_map.place_map(map)
	ctf_map.emerge_with_callbacks(nil, map.pos1, map.pos2, function()
		local schempath = mapdir .. map.schematic
		local res = minetest.place_schematic(map.pos1, schempath,
				map.rotation == "z" and "0" or "90")

		assert(res)

		local seed = minetest.get_mapgen_setting("seed")
		for _, value in pairs(ctf_map.map.teams) do
			place_chests(value.chests.from, value.chests.to, seed, value.chests.n)
			minetest.log("error", "Placing " .. value.chests.n .. " chests from " ..
					minetest.pos_to_string(value.chests.from) .. " to "..
					minetest.pos_to_string(value.chests.to))

			ctf_team_base.place(value.color, value.pos)
		end

		minetest.after(2, function()
			minetest.chat_send_all("Map: " .. map.name .. " by " .. map.author)
		end)

		minetest.after(10, function()
			minetest.fix_light(ctf_map.map.pos1, ctf_map.map.pos2)
		end)
	end, nil)
end

function ctf_match.load_map_meta(idx, name)
	local offset = vector.new(600 * idx, 0, 0)
	local meta   = Settings(mapdir .. name .. ".conf")

	local initial_stuff = meta:get("initial_stuff")
	local map = {
		idx           = idx,
		name          = meta:get("name"),
		author        = meta:get("author"),
		rotation      = meta:get("rotation"),
		schematic     = name .. ".mts",
		r             = tonumber(meta:get("r")),
		h             = tonumber(meta:get("h")),
		teams         = {},
		initial_stuff = initial_stuff and initial_stuff:split(","),
	}

	assert(map.r <= max_r)

	map.pos1 = vector.add(offset, { x = -map.r, y = -map.h / 2, z = -map.r })
	map.pos2 = vector.add(offset, { x =  map.r, y = map.h / 2,  z =  map.r })

	local i = 1
	while meta:get("team." .. i) do
		local tname  = meta:get("team." .. i)
		local tcolor = meta:get("team." .. i .. ".color")
		local tpos   = minetest.string_to_pos(meta:get("team." .. i .. ".pos"))

		local chests1 = meta:get("team." .. i .. ".chests1")
		if chests1 then
			chests1 = vector.add(offset, minetest.string_to_pos(chests1))
		elseif i == 1 then
			chests1 = vector.add(offset, { x = -map.r, y = -map.h / 2, z = 0 })
		elseif i == 2 then
			chests1 = map.pos1
		end

		local chests2 = meta:get("team." .. i .. ".chests2")
		if chests2 then
			chests2 = vector.add(offset, minetest.string_to_pos(chests2))
		elseif i == 1 then
			chests2 = map.pos2
		elseif i == 2 then
			chests2 = vector.add(offset, { x = map.r, y = map.h / 2, z = 0 })
		end


		map.teams[tname] = {
			color = tcolor,
			pos = vector.add(offset, tpos),
			chests = {
				from = chests1,
				to = chests2,
				n = tonumber(meta:get("team." .. i .. ".num_chests") or "18"),
			},
		}

		i = i + 1
	end

	return map
end

ctf_match.register_on_new_match(function()
	-- Choose next map index, but don't select the same one again
	local idx
	if ctf_map.map then
		idx = math.random(#ctf_map.available_maps - 1)
		if idx >= ctf_map.map.idx then
			idx = idx + 1
		end
	else
		idx = math.random(#ctf_map.available_maps)
	end

	-- Load meta data
	local name = ctf_map.available_maps[idx]
	ctf_map.map = ctf_match.load_map_meta(idx, name)

	-- Place map
	ctf_map.place_map(ctf_map.map)
end)

function ctf_match.create_teams()
	local number = ctf.setting("match.teams")

	for key, value in pairs(ctf_map.map.teams) do
		local name  = key
		local color = value.color
		local flag  = value.pos

		if name and color and flag then
			print(" - creating " .. key)
			ctf.team({
				name     = name,
				color    = color,
				add_team = true
			})

			ctf_flag.add(name, flag)

			minetest.after(0, function()
				ctf_flag.assert_flag(flag)
			end)
		else
			minetest.log("error", " - Failed to create " .. key)
		end
	end
end
