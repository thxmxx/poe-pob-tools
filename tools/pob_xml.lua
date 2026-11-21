-- Headless PoB on a PoB XML. Run via the matching tools/pob_xml.sh.
local xmlPath, specP, itemP, skillP, mainSkillName = arg[1], arg[2], arg[3], arg[4], arg[5]
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
if false then for i, spec in ipairs(build.treeTab.specList) do io.stderr:write("SPEC ", i, " ", tostring(spec.title), " n=", tostring(#(spec.allocNodes and {} or {})), "\n") end end
local function starts(s, p) return s and p and p ~= "" and s:sub(1, #p) == p end
for i, spec in ipairs(build.treeTab.specList) do
	if starts(spec.title, specP) then build.treeTab:SetActiveSpec(i) end
end
for _, id in ipairs(build.itemsTab.itemSetOrderList) do
	if starts(build.itemsTab.itemSets[id].title, itemP) then build.itemsTab:SetActiveItemSet(id) end
end
for _, id in ipairs(build.skillsTab.skillSetOrderList) do
	if starts(build.skillsTab.skillSets[id].title, skillP) then build.skillsTab:SetActiveSkillSet(id) end
end
runCallback("OnFrame")
for i, g in ipairs(build.skillsTab.socketGroupList) do
	for _, gem in ipairs(g.gemList) do
		if gem.nameSpec == mainSkillName and g.enabled ~= false then build.mainSocketGroup = i end
	end
end
build.buildFlag = true
runCallback("OnFrame")
local o = build.calcsTab.mainOutput
local out = { spec = build.treeTab.specList[build.treeTab.activeSpec].title,
	itemSet = build.itemsTab.itemSets[build.itemsTab.activeItemSetId].title,
	ascend = build.spec.curAscendClassName, level = build.characterLevel, nodes = 0, slots = {}, groups = {}, stats = {}, minion = {} }
for _ in pairs(build.spec.allocNodes) do out.nodes = out.nodes + 1 end
for name, slot in pairs(build.itemsTab.slots) do local it = build.itemsTab.items[slot.selItemId]; if it then out.slots[name] = it.name end end
for i, g in ipairs(build.skillsTab.socketGroupList) do local n = {}; for _, gem in ipairs(g.gemList) do n[#n+1] = gem.nameSpec end; out.groups[i] = table.concat(n, "+") end
out.main = build.mainSocketGroup
out.ascNodes = {}
for id, node in pairs(build.spec.allocNodes) do if node.ascendancyName and node.isNotable then out.ascNodes[#out.ascNodes+1] = node.dn end end
out.nodes = 0; for _ in pairs(build.spec.allocNodes) do out.nodes = out.nodes + 1 end
for k, v in pairs(o) do if type(v) == "number" then out.stats[k] = v end end
if type(o.Minion) == "table" then for k, v in pairs(o.Minion) do if type(v) == "number" then out.minion[k] = v end end end
-- per-skill reservation (which skills eat life/mana)
do
	local env = build.calcsTab.mainEnv
	out.reservations = {}
	for _, s in ipairs(env.player.activeSkillList) do
		local sd = s.skillData
		if os.getenv("RESDBG") or (sd.ManaReservedBase or 0) > 0 or (sd.LifeReservedBase or 0) > 0 then
			out.reservations[#out.reservations + 1] = string.format("%s: mana %s (%s%%) life %s (%s%%)", s.activeEffect.grantedEffect.name .. (os.getenv("RESDBG") and (" [mrp=" .. tostring(s.activeEffect.grantedEffectLevel.manaReservationPercent) .. " sup=" .. table.concat((function() local t = {} for _, e in ipairs(s.effectList or {}) do t[#t+1] = e.grantedEffect.name end return t end)(), ",") .. "]") or ""),
				tostring(sd.ManaReservedBase or 0), tostring(sd.ManaReservedPercent or 0), tostring(sd.LifeReservedBase or 0), tostring(sd.LifeReservedPercent or 0))
		end
	end
end
print(dkjson.encode(out, { indent = true }))
