-- OneCast's look: the game's own Forever art, never recoloured. Its text colours for the
-- collection's parchment and the windows' highlights live here, so every page inks the same.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- ink is text on the parchment pages, inkSoft quieter text; lead, soft, good and bad are text
-- colours for highlights, notes, good news and bad.
local FOREVER = {
	id = "forever",
	label = "Forever",
	ink = { 0.18, 0.10, 0.02 },
	inkSoft = { 0.36, 0.25, 0.14 },
	lead = "|cff7a2a00",
	soft = "|cff6b5233",
	good = "|cff1f6b1f",
	bad = "|cffa01c1c",
}

function Theme.Current()
	return FOREVER
end
