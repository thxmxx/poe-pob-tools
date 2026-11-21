-- Headless PoB on a PoB XML. Run via the matching tools/pob_trim.sh.
local xmlPath, targetLevel, outPath, mainSkillName = arg[1], tonumber(arg[2]), arg[3], arg[4]
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

-- Trim a tree down to the points available at targetLevel, removing the least valuable leaf nodes first.
-- Usage (via pob_trim.sh): pob_trim.lua BUILD.xml LEVEL OUT.xml "Main Skill"
loadBuildFromXML(readFile(xmlPath), "x")
runCallback("OnFrame")
if mainSkillName and mainSkillName ~= "" then
	for i, g in ipairs(build.skillsTab.socketGroupList) do
		for _, gem in ipairs(g.gemList) do if gem.nameSpec == mainSkillName and g.enabled ~= false then build.mainSocketGroup = i end end
	end
end
build.characterLevel = targetLevel
build.configTab:BuildModList()
build.buildFlag = true; runCallback("OnFrame")
local function used() local u = build.spec:CountAllocNodes(); return u end
local extra = build.calcsTab.mainOutput.ExtraPoints or 0
local avail = targetLevel - 1 + 23 + extra
local out = { avail = avail, usedStart = used(), removed = {} }
local base0 = build.calcsTab.mainOutput
out.start = { dps = base0.CombinedDPS, ehp = base0.TotalEHP, life = base0.Life }
while used() > avail do
	local calcFunc, calcBase = build.calcsTab:GetMiscCalculator()
	local best, bestLoss
	for id, node in pairs(build.spec.allocNodes) do
		if not node.ascendancyName and node.type ~= "ClassStart" and node.type ~= "AscendClassStart" and node.type ~= "Keystone"
			and not (node.type == "Socket" and build.itemsTab.sockets[id] and build.itemsTab.sockets[id].selItemId ~= 0)
			and node.depends and #node.depends <= 1 and not (build.calcsTab.mainEnv.grantedPassives or {})[id] and not (os.getenv("KEEP_OVERRIDES") and build.spec.hashOverrides[id]) then
			local o = calcFunc({ removeNodes = { [node] = true } })
			local loss = (1 - (o.CombinedDPS or 0) / math.max(calcBase.CombinedDPS or 1, 1)) + (1 - (o.TotalEHP or 0) / math.max(calcBase.TotalEHP or 1, 1))
			if not best or loss < bestLoss then best, bestLoss = node, loss end
		end
	end
	if not best then break end
	out.removed[#out.removed + 1] = { id = best.id, name = best.dn or best.name, loss = bestLoss }
	build.spec:DeallocNode(best)
	build.spec:AddUndoState()
	build.buildFlag = true; runCallback("OnFrame")
end
local o = build.calcsTab.mainOutput
out.final = { dps = o.CombinedDPS, ehp = o.TotalEHP, life = o.Life, used = used() }
local f = assert(io.open(outPath, "w")); f:write(build:SaveDB("trim")); f:close()
print(dkjson.encode(out, { indent = true }))
