local _, GM = ...

-- On-screen text. Code looks text up by its English wording, L["Joined"], and
-- gets the English back when there's no translation, so English needs no table.
--
-- To translate, add a file like Locales/deDE.lua after this one in the TOC:
--
--   local _, GM = ...
--   if GetLocale() ~= "deDE" then return end
--   local L = GM.L
--   L["Joined"] = "Beigetreten"
--
-- Keep any %s / %d in the same order as the English.

GM.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
