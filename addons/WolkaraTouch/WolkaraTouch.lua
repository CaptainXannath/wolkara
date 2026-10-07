-- Original Wolkara code, MIT licensed. Action execution is provided exclusively
-- by Blizzard's secure templates; an input never queues or repeats an action.
local actions, modifiers, menus = {}, {}, {}
local root, pendingLayout
local PAGE_FIRST_SLOT = { [0] = 1, 61, 49, 25, 37 }
local CIRCLE = "Interface\\AddOns\\WolkaraTouch\\Circle"
local function ActionAPI(name, ...)
    local fn = C_ActionBar and C_ActionBar[name] or _G[name]
    if fn then return fn(...) end
end

local function Notice(text)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.78, 0.3) end
end

local function RefreshAction(button)
    local slot = button:GetAttribute("action")
    if not slot then return end
    button.icon:SetTexture(ActionAPI("GetActionTexture", slot))
    -- Only pass cooldown values to the display. Do not branch on combat-secret
    -- values returned by newer clients.
    local start, duration, _, rate = ActionAPI("GetActionCooldown", slot)
    if type(start) == "table" then
        local info = start
        button.cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
    elseif type(start) == "number" and type(duration) == "number" then
        button.cooldown:SetCooldown(start, duration, rate)
    end
end

local function RefreshAll()
    for _, button in ipairs(actions) do RefreshAction(button) end
    if not root then return end
    local page = root:GetAttribute("page") or 0
    root.caption:SetText(page == 0 and "BASE" or "M" .. page)
    for index, button in ipairs(modifiers) do
        if page == index then
            button.fill:SetVertexColor(0.77, 0.55, 0.20, 0.95)
        else
            button.fill:SetVertexColor(0.04, 0.12, 0.16, 0.88)
        end
    end
end

local function DropAction(button)
    if InCombatLockdown() then
        Notice("Arrange abilities outside combat.")
        return
    end
    if GetCursorInfo() then
        PlaceAction(button:GetAttribute("action"))
        RefreshAll()
    end
end

local function PickUpAction(button)
    if InCombatLockdown() then
        Notice("Arrange abilities outside combat.")
        return
    end
    PickupAction(button:GetAttribute("action"))
    RefreshAll()
end

local function Tooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetAction(button:GetAttribute("action"))
    GameTooltip:Show()
end

local function ColorTexture(parent, layer, r, g, b, a, inset)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function SizeLabel(label, size)
    local font, _, flags = label:GetFont()
    if font then label:SetFont(font, size, flags) end
end

local function MakeAction(index)
    local button = CreateFrame("Button", "WolkaraTouchAction" .. index,
        root, "SecureActionButtonTemplate")
    -- Respect the client's key-down preference without executing on both edges.
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetAttribute("type", "action")
    button:SetAttribute("action", index)
    button:SetAttribute("checkselfcast", true)
    button:SetAttribute("checkfocuscast", true)
    for page = 0, 4 do
        button:SetAttribute("page" .. page, PAGE_FIRST_SLOT[page] + index - 1)
    end
    ColorTexture(button, "BACKGROUND", 0.65, 0.50, 0.24, 0.9)
    ColorTexture(button, "BORDER", 0.02, 0.06, 0.08, 0.9, 2)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 3, -3)
    button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:EnableMouse(false)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.label:SetPoint("BOTTOMRIGHT", -4, 3)
    button.label:SetText(index)
    local highlight = ColorTexture(button, "HIGHLIGHT", 1, 0.85, 0.5, 0.22)
    button:SetHighlightTexture(highlight)
    local pressed = ColorTexture(button, "OVERLAY", 0, 0, 0, 0.35)
    button:SetPushedTexture(pressed)
    -- Never replace the template's secure OnClick with an addon callback.
    button:SetScript("OnDragStart", PickUpAction)
    button:SetScript("OnReceiveDrag", DropAction)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:HookScript("OnAttributeChanged", function(self, name)
        if name == "action" then RefreshAction(self) end
    end)
    return button
end

-- Only a real button click executes this restricted snippet. Selecting a page
-- does not cast, move actions, synthesize a modifier key or alter WoW's main bar.
local PAGE_CLICK = [[
    if down or button ~= "LeftButton" then return end
    local header = self:GetFrameRef("header")
    local page = self:GetAttribute("page")
    if header:GetAttribute("page") == page then page = 0 end
    for index = 1, 8 do
        local action = self:GetFrameRef("action" .. index)
        action:SetAttribute("action", action:GetAttribute("page" .. page))
    end
    header:SetAttribute("page", page)
]]

local function MakeModifier(index)
    local button = CreateFrame("Button", "WolkaraTouchModifier" .. index,
        root, "SecureHandlerClickTemplate")
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("page", index)
    button:SetFrameRef("header", root)
    for slot, action in ipairs(actions) do button:SetFrameRef("action" .. slot, action) end
    button:SetAttribute("_onclick", PAGE_CLICK)
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture(CIRCLE)
    border:SetVertexColor(0.85, 0.66, 0.31, 0.95)
    button.fill = button:CreateTexture(nil, "BORDER")
    button.fill:SetPoint("TOPLEFT", 2, -2)
    button.fill:SetPoint("BOTTOMRIGHT", -2, 2)
    button.fill:SetTexture(CIRCLE)
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.label:SetPoint("CENTER")
    button.label:SetText("M" .. index)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("M" .. index .. ": select page; tap again for base")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function MenuAction(kind)
    if InCombatLockdown() and kind ~= "Menu" then
        Notice("Open this menu outside combat.")
        return
    end
    if kind == "Spells" then
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleSpellBook then
            PlayerSpellsUtil.ToggleSpellBook()
        elseif ToggleSpellBook then ToggleSpellBook(BOOKTYPE_SPELL or "spell")
        else Notice("Open the spellbook from the game's menu.") end
    elseif kind == "Talents" then
        if PlayerSpellsUtil and PlayerSpellsUtil.ToggleTalentsFrame then
            PlayerSpellsUtil.ToggleTalentsFrame()
        elseif ToggleTalentFrame then ToggleTalentFrame()
        else Notice("Open talents from the game's menu.") end
    elseif kind == "Character" and ToggleCharacter then ToggleCharacter("PaperDollFrame")
    elseif kind == "Bags" and ToggleAllBags then ToggleAllBags()
    elseif kind == "Map" and ToggleWorldMap then ToggleWorldMap()
    elseif kind == "Menu" then
        if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame)
        else ShowUIPanel(GameMenuFrame) end
    end
end

local function Layout()
    if not root then return end
    if InCombatLockdown() then pendingLayout = true; return end
    pendingLayout = nil
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if width <= 0 or height <= 0 then return end
    local size = math.min(height * 0.125, width * 0.075)
    local gap, modifierSize = size * 0.12, size * 0.78
    local panelWidth, panelHeight = size * 2 + gap * 2 + modifierSize, size * 4 + gap * 3
    root:ClearAllPoints()
    root:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -width * 0.04, -height * 0.20)
    root:SetSize(panelWidth, panelHeight)
    for index, button in ipairs(actions) do
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", root, "TOPLEFT", column * (size + gap), -row * (size + gap))
        button:SetSize(size, size)
        SizeLabel(button.label, size * 0.20)
    end
    for index, button in ipairs(modifiers) do
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0,
            -(index - 1) * (size + gap) - (size - modifierSize) * 0.5)
        button:SetSize(modifierSize, modifierSize)
        SizeLabel(button.label, modifierSize * 0.30)
    end
    SizeLabel(root.caption, size * 0.19)
    local menuGap, menuWidth = width * 0.006, width * 0.097
    for index, button in ipairs(menus) do
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT",
            -width * 0.04 - (6 - index) * (menuWidth + menuGap), height * 0.025)
        button:SetSize(menuWidth, height * 0.075)
        SizeLabel(button.label, math.min(height * 0.029, menuWidth * 0.19))
    end
end

local function Initialize()
    if root or InCombatLockdown() then return end
    root = CreateFrame("Frame", "WolkaraTouchPanel", UIParent, "SecureHandlerBaseTemplate")
    root:SetFrameStrata("MEDIUM")
    root:SetAttribute("page", 0)
    root.caption = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    root.caption:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 6)
    for index = 1, 8 do actions[index] = MakeAction(index) end
    for index = 1, 4 do modifiers[index] = MakeModifier(index) end
    root:HookScript("OnAttributeChanged", function(_, name)
        if name == "page" then RefreshAll() end
    end)
    for index, label in ipairs({ "Spells", "Character", "Talents", "Bags", "Map", "Menu" }) do
        local button = CreateFrame("Button", "WolkaraTouchMenu" .. index, root)
        button:RegisterForClicks("LeftButtonUp")
        ColorTexture(button, "BACKGROUND", 0.08, 0.13, 0.16, 0.9)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER")
        button.label:SetText(label)
        button:SetScript("OnClick", function() MenuAction(label) end)
        menus[index] = button
    end
    Layout()
    RefreshAll()
end

local events = CreateFrame("Frame")
for _, name in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN",
    "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do events:RegisterEvent(name) end
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Initialize()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Initialize()
        if pendingLayout then Layout() end
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        Layout()
    end
    RefreshAll()
end)
