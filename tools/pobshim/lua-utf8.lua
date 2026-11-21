-- Minimal pure-Lua stand-in for the luautf8 C module, enough for headless PoB.
-- PoB only uses find/gsub/match/sub/reverse (number formatting) and next (EditControl UI).
-- Byte-based string functions are correct for the ASCII text these paths handle.
local M = {}
M.find, M.gsub, M.match, M.sub, M.gmatch, M.len = string.find, string.gsub, string.match, string.sub, string.gmatch, string.len
M.upper, M.lower, M.byte, M.char, M.format, M.rep = string.upper, string.lower, string.byte, string.char, string.format, string.rep

function M.reverse(s)
	-- reverse by UTF-8 code points
	local out = {}
	for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		table.insert(out, 1, ch)
	end
	return table.concat(out)
end

-- utf8.next(s, i [, n]): byte index of the n-th code point after position i
function M.next(s, i, n)
	i, n = i or 0, n or 1
	local len = #s
	local step = n >= 0 and 1 or -1
	for _ = 1, math.abs(n) do
		repeat
			i = i + step
			if i < 1 or i > len then return nil end
			local b = s:byte(i)
		until not (b >= 128 and b < 192)
	end
	return i, s:sub(i, i)
end

return M
