-- Headless PoB on a PoB XML. Run via the matching tools/pob_plan.sh.
local xmlPath, planPath, outPath = arg[1], arg[2], arg[3]
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

-- Plan a passive-tree path: allocate steps in order, report cost and stats after each, save XML.
-- Usage (via pob_plan.sh): pob_plan.lua BUILD.xml PLAN.json OUT.xml
-- PLAN.json = [{"label": "...", "id": 12345} | {"label": "...", "name": "Stamina", "cluster": false}, ...]
loadBuildFromXML(readFile(xmlPath), "x")
runCallback("OnFrame")
local plan = dkjson.decode(readFile(planPath))
local function snap()
	build.buildFlag = true; runCallback("OnFrame")
	local o = build.calcsTab.mainOutput
	local m = o.Minion or {}
	local alloc = 0
	for _, n in pairs(build.spec.allocNodes) do if not n.ascendancyName and n.type ~= "ClassStart" then alloc = alloc + 1 end end
	return { dps = (m.CombinedDPS and m.CombinedDPS > 0) and m.CombinedDPS or (o.CombinedDPS or 0), ehp = o.TotalEHP or 0, phys = o.PhysicalMaximumHitTaken or 0, life = o.Life or 0, es = o.EnergyShield or 0,
		mana = o.ManaUnreserved or 0, int = (o.Int or 0) - (o.ReqInt or 0), dex = (o.Dex or 0) - (o.ReqDex or 0), str = (o.Str or 0) - (o.ReqStr or 0),
		fire = o.FireResist, cold = o.ColdResist, light = o.LightningResist, chaos = o.ChaosResist, points = alloc }
end
local out = { base = snap(), steps = {} }
for _, st in ipairs(plan) do
	local target
	if st.id then target = build.spec.nodes[st.id] end
	if not target and st.name then
		for id, n in pairs(build.spec.nodes) do
			if (n.dn == st.name or n.name == st.name) and not n.alloc and n.pathDist and n.pathDist < 1000
				and ((st.cluster and id >= 65536) or (not st.cluster and id < 65536)) then
				if not target or n.pathDist < target.pathDist then target = n end
			end
		end
	end
	local rec = { label = st.label }
	if not target then rec.error = "not found"
	elseif target.alloc then rec.error = "already allocated"
	else
		rec.node = target.dn or target.name; rec.id = target.id; rec.cost = target.pathDist
		rec.path = {}
		for _, p in ipairs(target.path or {}) do rec.path[#rec.path + 1] = p.dn or p.name end
		build.spec:AllocNode(target)
		build.spec:AddUndoState()
		rec.stats = snap()
	end
	out.steps[#out.steps + 1] = rec
end
if outPath and outPath ~= "" then
	local f = assert(io.open(outPath, "w")); f:write(build:SaveDB("plan")); f:close()
end
print(dkjson.encode(out, { indent = true }))
