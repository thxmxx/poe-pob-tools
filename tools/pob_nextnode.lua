-- Headless PoB on a PoB XML. Run via the matching tools/pob_nextnode.sh.
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
-- Usage: pob_nextnode.lua BUILD.xml MAIN_SKILL  -> value of each unallocated node reachable with 1 point
local function readFile(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
loadBuildFromXML(readFile(xmlPath), "x")
runCallback("OnFrame")
for i, g in ipairs(build.skillsTab.socketGroupList) do
	for _, gem in ipairs(g.gemList) do if gem.nameSpec == mainSkillName and g.enabled ~= false then build.mainSocketGroup = i end end
end
build.buildFlag = true; runCallback("OnFrame")
local calcFunc, base = build.calcsTab:GetMiscCalculator()
local out = { base = { dps = base.CombinedDPS, ehp = base.TotalEHP, life = base.Life, maxhit = base.PhysicalMaximumHitTaken }, nodes = {} }
for id, node in pairs(build.spec.nodes) do
	if not node.alloc and node.pathDist == 1 and node.type ~= "Mastery" and not node.ascendancyName and node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
		local o = calcFunc({ addNodes = { [node] = true } })
		out.nodes[#out.nodes + 1] = { id = id, name = node.dn, type = node.type, stats = table.concat(node.sd or {}, " / "),
			dps = (o.CombinedDPS or 0) / math.max(base.CombinedDPS, 1) - 1, ehp = (o.TotalEHP or 0) / math.max(base.TotalEHP, 1) - 1,
			life = (o.Life or 0) - (base.Life or 0), maxhit = (o.PhysicalMaximumHitTaken or 0) / math.max(base.PhysicalMaximumHitTaken or 1, 1) - 1 }
	end
end
print(dkjson.encode(out, { indent = true }))
