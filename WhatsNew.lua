-- OneCast "What's new" window: versions listed on the left, the selected version's notes
-- on a parchment page on the right, Newer / Older / Close below. Built from Blizzard's own
-- templates so it wears Forever's skin. Also the login chat line announcing the version,
-- with a clickable [What's new] link.

local ADDON, ns = ...

local WhatsNew = {}
ns.WhatsNew = WhatsNew

local PROJECT_URL = "https://www.curseforge.com/wow/addons/onecast"
local LINK = "addon:" .. ADDON .. ":whatsnew"

local WIDTH, HEIGHT = 760, 520
local LIST_WIDTH = 330
local ROW_HEIGHT = 34

-- Parchment ink, like quest text.
local INK = { 0.18, 0.10, 0.02 }
local INK_SOFT = { 0.32, 0.22, 0.12 }
local LEAD = "|cff7a2a00" -- the bold-ish opening phrase of each bullet

local frame
local selected = 1

local TryCreate, HasAtlas, SizedFont = ns.UI.TryCreate, ns.UI.HasAtlas, ns.UI.SizedFont

local function CountChanges(release)
	local n = 0
	for _, section in ipairs(release.sections) do
		n = n + #section[2]
	end
	return n
end

local function TotalChanges()
	local n = 0
	for _, release in ipairs(ns.CHANGELOG) do
		n = n + CountChanges(release)
	end
	return n
end

local function Inset(parent)
	local f = TryCreate("Frame", nil, parent, "InsetFrameTemplate")
	if not f then
		f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0, 0, 0, 0.5)
	end
	return f
end

-- Font of a font object at another size, for the page's big headings.
-- Page --------------------------------------------------------------------------------

local pool = { strings = {}, textures = {}, used = { strings = 0, textures = 0 } }

local function PageString(content, fontObject, size, color)
	pool.used.strings = pool.used.strings + 1
	local fs = pool.strings[pool.used.strings]
	if not fs then
		fs = content:CreateFontString(nil, "OVERLAY")
		pool.strings[pool.used.strings] = fs
	end
	SizedFont(fs, fontObject, size)
	fs:SetTextColor(color[1], color[2], color[3])
	fs:SetShadowOffset(0, 0)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(true)
	fs:ClearAllPoints()
	fs:Show()
	return fs
end

local function PageTexture(content)
	pool.used.textures = pool.used.textures + 1
	local tex = pool.textures[pool.used.textures]
	if not tex then
		tex = content:CreateTexture(nil, "ARTWORK")
		pool.textures[pool.used.textures] = tex
	end
	tex:ClearAllPoints()
	tex:SetVertexColor(1, 1, 1, 1)
	tex:Show()
	return tex
end

local function RenderPage()
	local release = ns.CHANGELOG[selected]
	local content = frame.content
	for _, fs in ipairs(pool.strings) do
		fs:Hide()
	end
	for _, tex in ipairs(pool.textures) do
		tex:Hide()
	end
	pool.used.strings, pool.used.textures = 0, 0

	local width = content:GetWidth()
	local y = 0
	local function Place(region, x, gap)
		region:SetPoint("TOPLEFT", content, "TOPLEFT", x or 0, -y)
		y = y + (region.GetStringHeight and region:GetStringHeight() or region:GetHeight()) + (gap or 0)
	end

	local title = PageString(content, QuestTitleFont, 28, INK)
	title:SetWidth(width)
	title:SetText("v" .. release.version)
	Place(title, 0, 6)

	local date = PageString(content, QuestFont, 14, INK_SOFT)
	date:SetWidth(width)
	date:SetText("发布于 " .. release.date .. "。")
	Place(date, 0, 18)

	for _, section in ipairs(release.sections) do
		local heading = PageString(content, QuestTitleFont, 18, INK)
		heading:SetText(section[1])
		heading:SetWidth(0)
		heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		local rule = PageTexture(content)
		rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.45)
		rule:SetHeight(1)
		rule:SetPoint("LEFT", heading, "RIGHT", 10, 0)
		rule:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		y = y + heading:GetStringHeight() + 12

		for _, bullet in ipairs(section[2]) do
			local dot = PageTexture(content)
			dot:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
			dot:SetTexCoord(0, 1, 0, 1)
			dot:SetSize(14, 14)
			dot:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y - 2)
			local text = PageString(content, QuestFont, 15, INK)
			text:SetWidth(width - 24)
			text:SetText(LEAD .. bullet[1] .. "|r " .. bullet[2])
			Place(text, 22, 12)
		end
		y = y + 8
	end

	content:SetHeight(math.max(y, 1))
	frame.scroll:SetVerticalScroll(0)
end

-- List ----------------------------------------------------------------------------------

-- The list shows as many versions as fit, scrolled so the selected one is always in view
-- (Newer / Older and the mouse wheel move through the rest).
local firstShown = 1

local function UpdateList()
	-- The list runs from 62 below the top to 64 above the bottom; rows start 46 down.
	local fit = math.max(1, math.floor((HEIGHT - 62 - 64 - 46 - 8) / ROW_HEIGHT))
	if selected < firstShown then
		firstShown = selected
	elseif selected >= firstShown + fit then
		firstShown = selected - fit + 1
	end
	for i, row in ipairs(frame.rows) do
		local slot = i - firstShown
		row:SetShown(slot >= 0 and slot < fit)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 8, -46 - slot * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -8, -46 - slot * ROW_HEIGHT)
		local isSelected = i == selected
		row.selectedBg:SetShown(isSelected)
		local c = isSelected and HIGHLIGHT_FONT_COLOR or NORMAL_FONT_COLOR
		row.label:SetTextColor(c.r, c.g, c.b)
		row.count:SetTextColor(c.r, c.g, c.b)
	end
	frame.newer:SetEnabled(selected > 1)
	frame.older:SetEnabled(selected < #ns.CHANGELOG)
end

local function Select(index)
	selected = math.max(1, math.min(#ns.CHANGELOG, index))
	UpdateList()
	RenderPage()
end

-- Window --------------------------------------------------------------------------------

local function CreateWindow()
	local f = TryCreate("Frame", "OneCastWhatsNewFrame", UIParent, "ButtonFrameTemplate")
	local title = (ns.DISPLAY_NAME or "哇，大鱼") .. " 更新内容  |cff9d9d9dv" .. (ns.VERSION or "?") .. "|r"
	if f then
		if ButtonFrameTemplate_HidePortrait then
			ButtonFrameTemplate_HidePortrait(f)
		end
		if f.SetTitle then
			f:SetTitle(title)
		end
		f.Inset:Hide()
	else
		f = CreateFrame("Frame", "OneCastWhatsNewFrame", UIParent, "BackdropTemplate")
		f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 } })
		local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOP", 0, -12)
		t:SetText(title)
		local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, f:GetName())
	ns.UI.KeepOpenThroughOptions(f:GetName())

	-- Top line: "Versions: N" box and the change count.
	local versions = CreateFrame("Frame", nil, f, "BackdropTemplate")
	versions:SetSize(130, 26)
	versions:SetPoint("TOPLEFT", 12, -30)
	versions:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
	versions:SetBackdropColor(0, 0, 0, 0.6)
	local versionsText = versions:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	versionsText:SetPoint("CENTER")
	versionsText:SetText("版本：|cffffffff" .. #ns.CHANGELOG .. "|r")
	local summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	summary:SetPoint("LEFT", versions, "RIGHT", 12, 0)
	summary:SetText(TotalChanges() .. " 项改动，最新在前。")

	-- Left: the version list.
	local list = Inset(f)
	list:SetPoint("TOPLEFT", 10, -62)
	list:SetPoint("BOTTOMLEFT", 10, 64)
	list:SetWidth(LIST_WIDTH)
	local listTitle = list:CreateFontString(nil, "OVERLAY")
	SizedFont(listTitle, QuestTitleFont, 20)
	listTitle:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	listTitle:SetPoint("TOPLEFT", 16, -14)
	listTitle:SetText(ns.DISPLAY_NAME or "哇，大鱼")
	local listCount = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	listCount:SetPoint("TOPRIGHT", -16, -20)
	listCount:SetText(#ns.CHANGELOG == 1 and "1 个版本" or (#ns.CHANGELOG .. " 个版本"))
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		Select(selected - delta)
	end)

	f.rows = {}
	for i, release in ipairs(ns.CHANGELOG) do
		local row = CreateFrame("Button", nil, list)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -46 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -8, -46 - (i - 1) * ROW_HEIGHT)
		row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
		row.selectedBg:SetAllPoints()
		row.selectedBg:SetColorTexture(0.72, 0.55, 0.12, 0.85)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		row.label:SetPoint("LEFT", 8, 0)
		row.label:SetText(string.format("[%s]  %s", release.version, release.date))
		row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		row.count:SetPoint("RIGHT", -8, 0)
		row.count:SetText("(" .. CountChanges(release) .. ")")
		row:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			Select(i)
		end)
		f.rows[i] = row
	end

	-- Right: the parchment page with a scrolling body.
	local page = CreateFrame("Frame", nil, f)
	page:SetPoint("TOPLEFT", list, "TOPRIGHT", 12, 0)
	page:SetPoint("BOTTOMRIGHT", -12, 64)
	local parchment = page:CreateTexture(nil, "BACKGROUND")
	parchment:SetAllPoints()
	if HasAtlas("QuestBG-Parchment") then
		parchment:SetAtlas("QuestBG-Parchment")
	else
		parchment:SetTexture("Interface\\QuestFrame\\QuestBG")
		parchment:SetTexCoord(0, 0.586, 0, 0.65)
	end

	local scroll = TryCreate("ScrollFrame", "OneCastWhatsNewScroll", page, "UIPanelScrollFrameTemplate")
		or CreateFrame("ScrollFrame", "OneCastWhatsNewScroll", page)
	scroll:SetPoint("TOPLEFT", 40, -34)
	scroll:SetPoint("BOTTOMRIGHT", -40, 24)
	scroll:EnableMouseWheel(true)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - LIST_WIDTH - 34 - 80, 1)
	scroll:SetScrollChild(content)
	if not scroll.ScrollBar then
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local max = math.max(0, content:GetHeight() - self:GetHeight())
			self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
		end)
	end
	f.scroll, f.content = scroll, content

	-- Bottom: Newer / Older on the left, Close on the right.
	f.newer = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.newer:SetSize(110, 22)
	f.newer:SetPoint("BOTTOMLEFT", 12, 36)
	f.newer:SetText("更新版本")
	f.newer:SetScript("OnClick", function() Select(selected - 1) end)
	f.older = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.older:SetSize(110, 22)
	f.older:SetPoint("LEFT", f.newer, "RIGHT", 12, 0)
	f.older:SetText("更旧版本")
	f.older:SetScript("OnClick", function() Select(selected + 1) end)
	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(110, 22)
	close:SetPoint("BOTTOMRIGHT", -12, 36)
	close:SetText(CLOSE or "关闭")
	close:SetScript("OnClick", function() f:Hide() end)

	-- Footer: where to send requests, and the project page, selectable to copy.
	local footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	footer:SetPoint("BOTTOMLEFT", 14, 12)
	footer:SetText("欢迎在 CurseForge 提交功能建议与缺陷反馈")
	local url = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	url:SetSize(200, 20)
	url:SetPoint("LEFT", footer, "RIGHT", 14, 0)
	url:SetAutoFocus(false)
	url:SetText(PROJECT_URL)
	url:SetCursorPosition(0)
	url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	url:SetScript("OnTextChanged", function(self)
		if self:GetText() ~= PROJECT_URL then
			self:SetText(PROJECT_URL)
			self:HighlightText()
		end
	end)
	url:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", url, "RIGHT", 8, 0)
	hint:SetText("点击后按 Ctrl+C")

	f:Hide()
	return f
end

function WhatsNew.Show()
	frame = frame or CreateWindow()
	frame:Show()
	Select(1)
	if ns.db then
		ns.db.seenVersion = ns.VERSION
	end
end

function WhatsNew.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		WhatsNew.Show()
	end
end

-- Login announcement --------------------------------------------------------------------

local function ChatLink()
	return "|cff71d5ff|H" .. LINK .. "|h[更新内容]|h|r"
end

-- Clicking [更新内容] in chat.
hooksecurefunc("SetItemRef", function(link)
	if link == LINK then
		WhatsNew.Show()
	end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	-- After the login chat spam, so the line isn't buried.
	C_Timer.After(4, function()
		local db = ns.db
		if not db or db.loginMessage == false then
			return
		end
		-- Until the window has been opened for this version, point at it.
		if not db.seenVersion then
			ns.Print(string.format("|cffffffffv%s|r 已安装。查看功能：%s 或 /onecast new",
				ns.VERSION, ChatLink()))
		elseif db.seenVersion ~= ns.VERSION then
			ns.Print(string.format("已更新至 |cffffffffv%s|r。查看改动：%s 或 /onecast new",
				ns.VERSION, ChatLink()))
		else
			ns.Print(string.format("|cffffffffv%s|r 已加载。%s  输入 /onecast 打开选项", ns.VERSION, ChatLink()))
		end
	end)
end)
