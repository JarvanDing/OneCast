-- OneCast's bobber beam: your bobber glowing, with a column of light rising from it while the
-- line is out, so it stands out on busy water, in the colour you choose (Beam colour).
--
-- Addons can't draw in the world or ask where an object is on screen. But with the game's
-- interact icons on (Mark your bobber), the soft-interact target, your bobber, gets a
-- nameplate: a real frame that follows it. The beam is drawn on that plate, and the game's own
-- gear icon on it is faded out when you'd rather have the beam alone.

local _, ns = ...

local Bobber = {}
ns.Bobber = Bobber

local BOBBER_ID = 35591    -- the fishing bobber's object ID, the sixth part of its GUID
local GLOW = "BonusChest-CircleGlow"
local RING = "PowerSwirlAnimation-YellowRing"
local SPARK = "Interface\\Cooldown\\star4"
local SIZE = 90            -- the beam's base size before the camera zoom scales it
-- The plate floats above the object it follows: the glow's middle comes down this far (in
-- sizes) to sit on the bobber.
local DROP = 0.55
local ZOOM_NEAR, ZOOM_FAR = 15, 10 -- the camera zoom the size is right at, and the bobber's distance
local SCALE_MIN, SCALE_MAX = 0.45, 2.2
local MOTES = 5

local beams = {}  -- namePlate -> beam frame
Bobber._beams = beams -- for the tests
local spare = {}  -- beam frames not in use
local faded = {}  -- unit frames whose gear icon we faded

local function Secret(v)
	return issecretvalue and issecretvalue(v)
end

-- With "Mark your bobber" on, the beam: there's one style.
local function Style()
	return ns.db and ns.db.bobberMarker and "beam" or nil
end

local function WantBeam()
	local style = Style()
	return style == "beam" or style == "both" or style == "glow"
end

-- With a controller, the game puts its own Interact button over the bobber (X on many pads),
-- though OneCast's fishing button is what reels in. Over the bobber goes that button instead.
local function PromptKey()
	local C = ns.Controller
	if not (C and ns.db and ns.db.padHints ~= false and C.Native()) then
		return nil
	end
	return C.FishingKey()
end

-- Your bobber: by its object ID where the GUID can be read, else the object you're
-- soft-targeting while you fish.
local function IsBobber(unit)
	if not (UnitIsGameObject and UnitIsGameObject(unit)) then
		return false
	end
	local guid = UnitGUID(unit)
	if type(guid) == "string" and not Secret(guid) then
		local id = tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)") or "")
		if id then
			return id == BOBBER_ID
		end
	end
	local picked = UnitIsUnit(unit, "softinteract")
	return not Secret(picked) and picked == true and ns.IsFishing and ns.IsFishing() or false
end

-- The beam's colour: your choice under Beam colour, arcane blue-violet by default.
Bobber.COLORS = {
	arcane = { 0.42, 0.38, 1 }, gold = { 1, 0.82, 0.35 }, white = { 0.95, 0.97, 1 }, blue = { 0.45, 0.75, 1 }, teal = { 0.35, 1, 0.9 },
	green = { 0.45, 1, 0.3 }, red = { 1, 0.35, 0.25 }, purple = { 0.75, 0.45, 1 }, pink = { 1, 0.5, 0.8 },
}
local GOLD = Bobber.COLORS.gold

local function ClassColor()
	local _, classFile = UnitClass("player")
	local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	return color and { color.r, color.g, color.b } or GOLD
end

local function Colors()
	local choice = ns.db and ns.db.beamColor or "arcane"
	local c
	if choice == "class" then
		c = ClassColor()
	else
		c = Bobber.COLORS[choice] or Bobber.COLORS.arcane
	end
	return c, { 1, 1, 1 }
end

Bobber.Colors = Colors


-- Recolour every beam on show: the colour setting changed.
function Bobber.Retint()
	for _, f in pairs(Bobber._beams) do
		Bobber.Tint(f)
	end
end

local function ZoomScale()
	local zoom = GetCameraZoom and GetCameraZoom()
	if type(zoom) ~= "number" or Secret(zoom) then
		return 1
	end
	return math.min(SCALE_MAX, math.max(SCALE_MIN, (ZOOM_NEAR + ZOOM_FAR) / (math.max(0, zoom) + ZOOM_FAR)))
end

local function Glow(frame, sublevel, half)
	local t = frame:CreateTexture(nil, "OVERLAY", nil, sublevel)
	t:SetBlendMode("ADD")
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(GLOW)
	if info and info.file then
		t:SetTexture(info.file)
		if half then
			-- The glow's lower half, flipped: bright and wide at the foot, fading to a point.
			t:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.bottomTexCoord,
				(info.topTexCoord + info.bottomTexCoord) / 2)
		else
			t:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord)
		end
	else
		t:SetTexture("Interface\\Buttons\\WHITE8x8")
	end
	return t
end

local function Place(frame, t, x, y, w, h, alpha)
	if alpha <= 0.003 then
		t:Hide()
		return
	end
	t:ClearAllPoints()
	t:SetPoint("CENTER", frame, "CENTER", x, y)
	t:SetSize(w, h)
	t:SetAlpha(math.min(1, alpha))
	t:Show()
end

local function NewBeam()
	local f = CreateFrame("Frame")
	f:SetSize(SIZE, SIZE)
	f.outer = Glow(f, 2, true)
	f.inner = Glow(f, 3, true)
	f.pool = Glow(f, 2)
	f.core = Glow(f, 4)
	f.halo = Glow(f, 4)
	f.heart = Glow(f, 6)
	f.ring = f:CreateTexture(nil, "OVERLAY", nil, 2)
	f.ring:SetBlendMode("ADD")
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(RING) then
		f.ring:SetAtlas(RING)
		f.ring:SetDesaturated(true)
	else
		f.ring:Hide()
		f.noRing = true
	end
	f.motes = {}
	for i = 1, MOTES do
		local m = f:CreateTexture(nil, "OVERLAY", nil, 5)
		m:SetTexture(SPARK)
		m:SetBlendMode("ADD")
		f.motes[i] = { tex = m, age = math.random() * 2, life = 1.5 + math.random() }
	end
	f.prompt = f:CreateTexture(nil, "OVERLAY", nil, 7)
	f.prompt:SetSize(26, 26)
	f.prompt:Hide()
	f.clock = 0
	f:SetScript("OnUpdate", function(self, elapsed)
		Bobber.Draw(self, math.min(elapsed, 0.1))
	end)
	return f
end

local function Tint(f)
	local base, top = Colors()
	local r, g, b = base[1], base[2], base[3]
	for _, t in ipairs({ f.outer, f.pool, f.ring }) do
		t:SetVertexColor(r, g, b)
	end
	local lr, lg, lb = r * 0.6 + 0.4, g * 0.6 + 0.4, b * 0.6 + 0.4 -- the core, lighter but still coloured
	f.inner:SetVertexColor(lr, lg, lb)
	f.core:SetVertexColor(lr, lg, lb)
	f.halo:SetVertexColor(r, g, b)
	f.heart:SetVertexColor((lr + 1) / 2, (lg + 1) / 2, (lb + 1) / 2) -- near white
	if f.inner.SetGradient and CreateColor then
		-- The inner column from the base colour at its foot to near white at its top.
		f.inner:SetGradient("VERTICAL", CreateColor(lr, lg, lb, 1), CreateColor(top[1], top[2], top[3], 1))
	end
	for _, m in ipairs(f.motes) do
		m.tex:SetVertexColor(lr, lg, lb)
	end
end
Bobber.Tint = Tint

function Bobber.Draw(f, elapsed)
	if ns.ReduceMotion and ns.ReduceMotion() then
		elapsed = 0 -- "Reduce motion": the light holds still
	end
	f.clock = f.clock + elapsed
	f:SetScale(ZoomScale())
	if f.noBeam then
		-- Only the controller's button over the bobber: no glow, column or ripples.
		for _, t in ipairs({ f.outer, f.inner, f.pool, f.core, f.halo, f.heart, f.ring }) do
			t:Hide()
		end
		for _, m in ipairs(f.motes) do
			m.tex:Hide()
		end
		return
	end
	local S, c = SIZE, f.clock
	local breath = 0.85 + 0.15 * math.sin(c * 2.2)
	local tall = 4.6 * S
	-- Fade in when it appears.
	f.fade = math.min(1, (f.fade or 0) + elapsed * 3)
	local a = f.fade
	-- On the water: a wide, deep pool of light lying flat around the bobber, a brighter one
	-- inside it, and on the bobber a tight glow with a small white-hot heart, so the float
	-- itself looks lit.
	local swell = 0.94 + 0.06 * math.sin(c * 2.2)
	Place(f, f.pool, 0, 0, 1.7 * S * swell, 0.48 * S * swell, 0.85 * a)
	Place(f, f.core, 0, 0, 0.7 * S, 0.2 * S, 0.9 * a)
	Place(f, f.halo, 0, 0.04 * S, 0.42 * S * swell, 0.42 * S * swell, 0.7 * a)
	Place(f, f.heart, 0, 0.04 * S, 0.16 * S, 0.16 * S, breath * a)
	-- A thin, intense column, fading to nothing high above.
	Place(f, f.outer, 0, tall / 2, 0.26 * S, tall, 0.6 * breath * a)
	Place(f, f.inner, 0, tall * 0.45, 0.06 * S, tall * 0.9, breath * a)
	-- A ripple spreads over the water every 2.2 seconds.
	if not f.noRing then
		local u = (c % 2.2) / 1.2
		if u < 1 then
			local e = 1 - (1 - u) * (1 - u)
			Place(f, f.ring, 0, 0, S * (0.4 + 1.5 * e), S * (0.11 + 0.42 * e), (1 - u) * 0.45 * a)
		else
			f.ring:Hide()
		end
	end
	-- Sparks drifting up the column.
	for _, m in ipairs(f.motes) do
		m.age = m.age + elapsed
		if m.age >= m.life then
			m.age, m.life = 0, 1.5 + math.random()
			m.x = (math.random() - 0.5) * 0.08 * S
			m.s = S * (0.06 + 0.06 * math.random())
		end
		local u = m.age / m.life
		Place(f, m.tex, m.x or 0, u * tall * 0.8, m.s or 10, m.s or 10, math.sin(math.pi * u) * 0.9 * a)
	end
end

local function FadeIcon(unitFrame, fade)
	local icon = unitFrame and unitFrame.SoftTargetFrame
	if not icon then
		return
	end
	if fade then
		icon:SetAlpha(0)
		faded[unitFrame] = true
	elseif faded[unitFrame] then
		icon:SetAlpha(1)
		faded[unitFrame] = nil
	end
end

-- Where the glow's middle goes: down from the plate onto the bobber. In the frame's own units,
-- so it scales with the zoom like everything else in it.
function Bobber.Place(f, namePlate)
	f:ClearAllPoints()
	f:SetPoint("CENTER", namePlate, "BOTTOM", 0, -DROP * SIZE)
end


local function Detach(namePlate)
	local f = beams[namePlate]
	if f then
		f:Hide()
		f:ClearAllPoints()
		f:SetParent(nil)
		beams[namePlate] = nil
		spare[#spare + 1] = f
	end
	FadeIcon(namePlate and namePlate.UnitFrame, false)
end

local function Attach(namePlate)
	local f = beams[namePlate]
	if not f then
		f = table.remove(spare) or NewBeam()
		f:SetParent(namePlate)
		f:SetFrameLevel(namePlate:GetFrameLevel() + 1)
		f.fade = 0
		beams[namePlate] = f
	end
	f:ClearAllPoints()
	Bobber.Place(f, namePlate)
	Tint(f)
	f:Show()
	f.noBeam = not WantBeam()
	-- With a controller, its fishing button where the game's Interact button was.
	local key = PromptKey()
	local atlas = key and ns.Controller.Atlas(key)
	if atlas then
		f.prompt:SetAtlas(atlas)
		local size = ns.Controller.GlyphPixels(30)
		f.prompt:SetSize(size, size)
		f.prompt:ClearAllPoints()
		f.prompt:SetPoint("BOTTOM", f, "CENTER", 0, 0.55 * SIZE)
		f.prompt:Show()
	else
		f.prompt:Hide()
	end
	FadeIcon(namePlate.UnitFrame, atlas ~= nil or Style() == "beam")
end

-- Every plate: the bobber's gets the beam while you fish, any other loses it.
function Bobber.Update()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local want = (WantBeam() or PromptKey()) and ns.IsFishing and ns.IsFishing()
	if not want and not next(beams) and not next(faded) then
		return -- runs on every soft-target change: idle while there's nothing to show or undo
	end
	for _, namePlate in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = namePlate.UnitFrame and namePlate.UnitFrame.unit
		if want and unit and not Secret(unit) and IsBobber(unit) then
			Attach(namePlate)
		elseif beams[namePlate] or (namePlate.UnitFrame and faded[namePlate.UnitFrame]) then
			Detach(namePlate)
		end
	end
	-- Plates gone since: their beams go too.
	for namePlate in pairs(beams) do
		if not namePlate:IsShown() then
			Detach(namePlate)
		end
	end
end

-- The line went out or came in.
function Bobber.OnFishingChanged()
	Bobber.Update()
	if ns.IsFishing and ns.IsFishing() then
		-- The plate can arrive a moment after the cast.
		C_Timer.After(0.3, Bobber.Update)
		C_Timer.After(1, Bobber.Update)
	end
end

if NamePlateDriverFrame then
	if NamePlateDriverFrame.OnNamePlateAdded then
		hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function()
			Bobber.Update()
		end)
	end
	if NamePlateDriverFrame.OnSoftTargetUpdate then
		hooksecurefunc(NamePlateDriverFrame, "OnSoftTargetUpdate", function()
			Bobber.Update()
		end)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
events:SetScript("OnEvent", function(_, event)
	if event == "NAME_PLATE_UNIT_REMOVED" then
		Bobber.Update()
	else
		-- After OneCast's own handler has set whether you're fishing.
		C_Timer.After(0, Bobber.OnFishingChanged)
	end
end)
