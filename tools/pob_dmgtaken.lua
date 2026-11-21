-- Headless PoB on a PoB XML. Run via the matching tools/pob_dmgtaken.sh.
local xmlPath, mainSkillName = arg[1], arg[2]
-- PoB's bundled LuaJIT accepts compound assignment (a += b, s ..= t); stock LuaJIT does not.
-- Rewrite `lhs op= expr` lines to `lhs = lhs op (expr)` when files are loaded.
local function rewrite(src)
	return (src:gsub("([^\n]*)", function(line)
		local ind, lhs, op, rhs = line:match("^(%s*)([%a_][%w_%.%[%]\"']*)%s*([%+%-%*/%%]%.?)=%s*(.-)%s*$")
		if not lhs then
			ind, lhs, op, rhs = line:match("^(%s*)([%a_][%w_%.%[%]\"']*)%s*(%.%.)=%s*(.-)%s*$")
		end
		if lhs and rhs ~= "" and not rhs:match("^=") then
			return ind .. lhs .. " = " .. lhs .. " " .. op .. " (" .. rhs .. ")"
		end
		return line
	end))
end
local l_loadfile = loadfile
function loadfile(path, ...)
	local f = io.open(path, "rb")
	if not f then return l_loadfile(path, ...) end
	local src = f:read("*a"); f:close()
	if src:find("[%+%-%*/%.]=") then src = rewrite(src) end
	return load(src, "@" .. path)
end
function dofile(path)
	local fn = assert(loadfile(path)); return fn()
end
-- same rewrite for modules loaded through require()
local loaders = package.loaders or package.searchers
table.insert(loaders, 2, function(name)
	local path = package.searchpath and package.searchpath(name, package.path)
	if not path then
		local rel = name:gsub("%.", "/")
		for pat in package.path:gmatch("[^;]+") do
			local cand = pat:gsub("%?", rel)
			local fh = io.open(cand, "rb")
			if fh then fh:close(); path = cand; break end
		end
	end
	if not path then return nil end
	local fn, err = loadfile(path)
	if not fn then error("error loading module '" .. name .. "' from file '" .. path .. "':\n\t" .. err) end
	return fn
end)

-- Headless Inflate() is a stub, so timeless jewel data (zip parts) can't be read.
-- Serve the pre-decompressed tables from tools/data/timeless/<Name>.bin instead
-- (generated once by decompressing Data/TimelessJewelData/<Name>.zip.part* with zlib).
do
	local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
	package.preload["Modules.DataJewelFileLoader"] = function()
		return function(jewelTypeName)
			local f = io.open(here .. "/data/timeless/" .. jewelTypeName .. ".bin", "rb")
			if not f then return nil end
			local s = f:read("*a"); f:close(); return s
		end
	end
end
dofile("HeadlessWrapper.lua")
local dkjson = require("dkjson")
-- Usage (via pob_xml.sh): pob_xml.lua BUILD.xml SPEC_TITLE_PREFIX ITEMSET_PREFIX SKILLSET_PREFIX MAIN_SKILL
local function readFile(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end


loadBuildFromXML(readFile(xmlPath), "x")
runCallback("OnFrame")
for i, g in ipairs(build.skillsTab.socketGroupList) do
	for _, gem in ipairs(g.gemList) do if gem.nameSpec == mainSkillName and g.enabled ~= false then build.mainSocketGroup = i end end
end
build.buildFlag = true; runCallback("OnFrame")
local db = build.calcsTab.mainEnv.player.modDB
for _, stat in ipairs({ "DamageTaken", "DamageTakenWhenHit", "PhysicalDamageTaken", "PhysicalDamageTakenWhenHit", "ElementalDamageTaken", "DamageTakenFromHits" }) do
	for _, t in ipairs({ "MORE", "INC" }) do
		for _, m in ipairs(db:Tabulate(t, nil, stat)) do
			print(stat, t, m.value, tostring(m.mod.source), m.mod.name)
		end
	end
end
