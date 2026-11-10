-- OneCast themes: recolours of every OneCast window, chosen in the options.
--
-- A window's Blizzard frames are made of textures, which take a tint without being replaced,
-- so a theme is just this file's table of colours. Windows register what should be tinted and
-- listen for changes to redraw their text. Forever is the game's own look: with it chosen from
-- the start, nothing here ever touches a texture.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.DEFAULT = "forever"
Theme.ORDER = { "forever", "dark", "tidal", "abyss", "golden", "marsh", "moonlit", "lodge", "class" }

-- frame, inset, header and button tint those parts of a window, and parchment the book's pages.
-- ink is text on the pages, inkSoft quieter text, and lead, soft, good and bad are text colours.
-- A theme with no tints leaves the game's own art alone. grain lays a tiled texture behind a
-- window, and fromClass takes the tints from the character being played.
Theme.LIST = {
	forever = {
		id = "forever",
		label = "Forever",
		ink = { 0.18, 0.10, 0.02 },
		inkSoft = { 0.36, 0.25, 0.14 },
		lead = "|cff7a2a00",
		soft = "|cff6b5233",
		good = "|cff1f6b1f",
		bad = "|cffa01c1c",
	},
	dark = {
		id = "dark",
		label = "暗黑",
		frame = { 0.42, 0.43, 0.47 },
		inset = { 0.55, 0.56, 0.60 },
		header = { 0.55, 0.56, 0.62 },
		button = { 0.50, 0.51, 0.56 },
		parchment = { 0.24, 0.25, 0.29 },
		ink = { 0.93, 0.92, 0.88 },
		inkSoft = { 0.68, 0.67, 0.63 },
		lead = "|cffe6b85c",
		soft = "|cffa9a89f",
		good = "|cff62d862",
		bad = "|cffff7466",
	},
	tidal = {
		id = "tidal",
		label = "潮汐",
		frame = { 0.34, 0.58, 0.74 },
		inset = { 0.42, 0.62, 0.76 },
		header = { 0.40, 0.68, 0.86 },
		button = { 0.30, 0.56, 0.78 },
		parchment = { 0.62, 0.82, 0.92 },
		ink = { 0.03, 0.11, 0.20 },
		inkSoft = { 0.11, 0.26, 0.38 },
		lead = "|cff0a4f7a",
		soft = "|cff2a566f",
		good = "|cff0a5730",
		bad = "|cffa01a2c",
	},
	abyss = {
		id = "abyss",
		label = "深渊",
		frame = { 0.20, 0.30, 0.40 },
		inset = { 0.30, 0.42, 0.50 },
		header = { 0.26, 0.48, 0.56 },
		button = { 0.24, 0.42, 0.52 },
		parchment = { 0.11, 0.20, 0.27 },
		ink = { 0.82, 0.95, 0.96 },
		inkSoft = { 0.55, 0.74, 0.78 },
		lead = "|cff5fdcd6",
		soft = "|cff8fb8bd",
		good = "|cff67e08a",
		bad = "|cffff8478",
	},
	golden = {
		id = "golden",
		label = "黄金时刻",
		frame = { 0.85, 0.55, 0.25 },
		inset = { 0.88, 0.64, 0.36 },
		header = { 0.95, 0.62, 0.25 },
		button = { 0.85, 0.50, 0.22 },
		parchment = { 1.00, 0.80, 0.58 },
		ink = { 0.25, 0.11, 0.03 },
		inkSoft = { 0.43, 0.24, 0.10 },
		lead = "|cff8f3a00",
		soft = "|cff6f4522",
		good = "|cff1a5c1a",
		bad = "|cff9c1414",
	},
	marsh = {
		id = "marsh",
		label = "沼泽",
		frame = { 0.36, 0.50, 0.28 },
		inset = { 0.44, 0.56, 0.34 },
		header = { 0.46, 0.62, 0.34 },
		button = { 0.40, 0.54, 0.28 },
		parchment = { 0.76, 0.86, 0.62 },
		ink = { 0.09, 0.17, 0.06 },
		inkSoft = { 0.24, 0.33, 0.16 },
		lead = "|cff3f5a10",
		soft = "|cff465a30",
		good = "|cff0b5f2a",
		bad = "|cff9a1a1a",
	},
	moonlit = {
		id = "moonlit",
		label = "月夜",
		frame = { 0.46, 0.44, 0.66 },
		inset = { 0.54, 0.52, 0.72 },
		header = { 0.58, 0.54, 0.78 },
		button = { 0.50, 0.47, 0.72 },
		parchment = { 0.26, 0.23, 0.38 },
		ink = { 0.94, 0.93, 0.98 },
		inkSoft = { 0.73, 0.71, 0.82 },
		lead = "|cffd9c7ff",
		soft = "|cffaaa5c4",
		good = "|cff7fe0a0",
		bad = "|cffff8a8a",
	},
	lodge = {
		id = "lodge",
		label = "渔夫小屋",
		frame = { 0.62, 0.42, 0.24 },
		inset = { 0.60, 0.44, 0.28 },
		header = { 0.70, 0.46, 0.22 },
		button = { 0.66, 0.44, 0.24 },
		parchment = { 0.84, 0.68, 0.46 },
		grain = "Interface\\BlackMarket\\BlackMarketBackground-Tile",
		grainTint = { 0.95, 0.78, 0.60 },
		ink = { 0.20, 0.10, 0.03 },
		inkSoft = { 0.36, 0.22, 0.10 },
		lead = "|cff6e2f08",
		soft = "|cff4f3219",
		good = "|cff124a16",
		bad = "|cff7f1410",
	},
	class = {
		id = "class",
		label = "职业颜色",
		fromClass = true,
		parchment = { 0.24, 0.25, 0.29 },
		ink = { 0.93, 0.92, 0.88 },
		inkSoft = { 0.68, 0.67, 0.63 },
		lead = "|cffe6b85c",
		soft = "|cffa9a89f",
		good = "|cff62d862",
		bad = "|cffff7466",
	},
}

local entries = {}   -- what's been registered: { object, role, skip }
local listeners = {}
local originals = setmetatable({}, { __mode = "k" }) -- how a texture looked before any tint
local grainOwners = {} -- windows and insets that can show a theme's grain
local grainOf = setmetatable({}, { __mode = "k" })  -- owner -> its grain texture
local isGrain = setmetatable({}, { __mode = "k" })  -- grain textures, which are never tinted
local tinted = false -- a theme has been applied this session, so there's art to restore

-- Full class colours are too loud across a whole window, Priest white and Rogue yellow above
-- all, so they're mixed with grey and dimmed. The pages stay neutral so text reads the same.
local function FillClassTints(theme)
	local _, classFile = UnitClass("player")
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if not color then
		return
	end
	local function Tint(strength)
		local function Part(value)
			return (value * 0.65 + 0.45 * 0.35) * strength
		end
		return { Part(color.r), Part(color.g), Part(color.b) }
	end
	theme.frame, theme.inset, theme.header, theme.button = Tint(0.75), Tint(0.85), Tint(0.90), Tint(0.85)
	local function Light(value)
		return math.floor((value * 0.75 + 0.25) * 255 + 0.5)
	end
	theme.lead = string.format("|cff%02x%02x%02x", Light(color.r), Light(color.g), Light(color.b))
end

function Theme.Current()
	local theme = Theme.LIST[ns.db and ns.db.theme] or Theme.LIST[Theme.DEFAULT]
	if theme.fromClass and not theme.frame then
		FillClassTints(theme)
	end
	return theme
end

local function TintTexture(texture, color)
	if color then
		if not originals[texture] then
			local r, g, b, a = texture:GetVertexColor()
			originals[texture] = { r or 1, g or 1, b or 1, a or 1, texture:IsDesaturated() }
		end
		texture:SetDesaturated(true)
		texture:SetVertexColor(color[1], color[2], color[3])
	else
		local original = originals[texture]
		if original then
			texture:SetVertexColor(original[1], original[2], original[3], original[4])
			texture:SetDesaturated(original[5])
		end
	end
end

local function IsPlainTexture(region)
	return region.GetObjectType and region:GetObjectType() == "Texture"
end

local function TintRegions(frame, color, skip)
	for _, region in ipairs({ frame:GetRegions() }) do
		if IsPlainTexture(region) and not isGrain[region] and not (skip and skip[region]) then
			TintTexture(region, color)
		end
	end
end

local function ApplyEntry(entry, theme)
	local object, color = entry.object, theme[entry.role]
	if IsPlainTexture(object) then
		TintTexture(object, color)
	else
		TintRegions(object, color, entry.skip)
		if object.NineSlice then
			TintRegions(object.NineSlice, color)
		end
	end
end

-- The grain is its own texture above the owner's background, so swapping themes only shows or
-- hides it and the game's art is never replaced. It's made the first time a theme needs it.
local function ApplyGrain(owner, theme)
	local grain = grainOf[owner]
	if not theme.grain then
		if grain then
			grain:Hide()
		end
		return
	end
	if not grain then
		grain = owner:CreateTexture(nil, "BACKGROUND", nil, 7)
		grain:SetPoint("TOPLEFT", 3, -3)
		grain:SetPoint("BOTTOMRIGHT", -3, 3)
		grainOf[owner], isGrain[grain] = grain, true
	end
	grain:SetTexture(theme.grain, "REPEAT", "REPEAT")
	grain:SetHorizTile(true)
	grain:SetVertTile(true)
	grain:SetVertexColor(theme.grainTint[1], theme.grainTint[2], theme.grainTint[3])
	grain:Show()
end

-- Tint this texture, or a frame's textures and its border, in the given role. `skip` is a set
-- of textures to leave alone, such as a button's icon.
function Theme.Register(object, role, skip)
	local entry = { object = object, role = role, skip = skip }
	entries[#entries + 1] = entry
	if tinted then
		ApplyEntry(entry, Theme.Current())
	end
end

local function AddSurface(owner, role)
	Theme.Register(owner, role)
	grainOwners[#grainOwners + 1] = owner
	if tinted then
		ApplyGrain(owner, Theme.Current())
	end
end

-- An inset panel inside a window.
function Theme.Panel(inset)
	AddSurface(inset, "inset")
end

-- A whole window: its frame and its inset panel.
function Theme.Frame(frame, inset)
	AddSurface(frame, "frame")
	if inset then
		Theme.Panel(inset)
	end
end

-- fn runs whenever the theme changes, and once at startup for anything but Forever.
function Theme.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Apply()
	local theme = Theme.Current()
	tinted = tinted or theme.id ~= Theme.DEFAULT
	if tinted then
		for _, entry in ipairs(entries) do
			ApplyEntry(entry, theme)
		end
		for _, owner in ipairs(grainOwners) do
			ApplyGrain(owner, theme)
		end
	end
	for _, fn in ipairs(listeners) do
		fn(theme)
	end
end
Theme.Apply = Apply

-- Called once the saved settings are loaded.
function Theme.Init()
	if Theme.Current().id ~= Theme.DEFAULT then
		Apply()
	end
end

-- Move to a named theme, or the next one if no name is given. Returns its label, or nil if
-- there's no theme of that name.
function Theme.Choose(id)
	if not id then
		local current = Theme.Current().id
		for i, candidate in ipairs(Theme.ORDER) do
			if candidate == current then
				id = Theme.ORDER[i % #Theme.ORDER + 1]
			end
		end
	end
	local theme = Theme.LIST[id]
	if not theme then
		return nil
	end
	local setting = ns.optionSettings and ns.optionSettings.theme
	if setting then
		setting:SetValue(id)
	else
		ns.db.theme = id
		Apply()
	end
	return theme.label
end
