-- Synthetic API/secure-handler harness, never attached to a running game.
-- This tests our page/drag/layout logic, not Blizzard's secure engine or taint.
local addonPath, apiFlavor = arg[1], arg[2]
local frames, combat, secure = {}, false, false
local cursor, slots, transfers, notices, opened = nil, {}, {}, {}, {}
local function equal(a, b, message)
    assert(a == b, (message or "unexpected value") .. ": " .. tostring(a) .. " != " .. tostring(b))
end
local function compile(source, environment)
    if loadstring then
        local fn = assert(loadstring(source))
        setfenv(fn, environment)
        return fn
    end
    return assert(load(source, "synthetic secure snippet", "t", environment))
end
local Widget = {}
Widget.__index = Widget
function Widget:SetPoint(...) self.point = { ... } end
function Widget:ClearAllPoints() self.point = nil end
function Widget:SetAllPoints(...) self.allPoints = { ... } end
function Widget:SetSize(width, height)
    assert(not (combat and self.protected and not secure), "insecure layout in combat")
    self.width, self.height = width, height
end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetFrameStrata(value) self.strata = value end
function Widget:RegisterForClicks(...) self.clicks = { ... } end
function Widget:RegisterForDrag(...) self.drags = { ... } end
function Widget:SetText(text) self.text = text end
function Widget:GetFont() return "synthetic-font", 12, "" end
function Widget:SetFont(...) self.font = { ... } end
function Widget:SetTexture(texture) self.texture = texture end
function Widget:SetColorTexture(...) self.color = { ... } end
function Widget:SetVertexColor(...) self.color = { ... } end
function Widget:SetTexCoord(...) self.texCoords = { ... } end
function Widget:SetHighlightTexture(texture) self.highlight = texture end
function Widget:SetPushedTexture(texture) self.pressed = texture end
function Widget:SetCooldown(...) self.cooldownValues = { ... } end
function Widget:EnableMouse(value) self.mouse = value end
function Widget:SetFrameRef(name, frame) self.refs[name] = frame end
function Widget:GetFrameRef(name) return self.refs[name] end
function Widget:RegisterEvent(name) self.events[name] = true end
function Widget:SetScript(name, fn)
    assert(not (name == "OnClick" and self.template == "SecureActionButtonTemplate"),
        "addon overwrote secure action handler")
    self.scripts[name] = fn
end
function Widget:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Widget:GetAttribute(name) return self.attributes[name] end
function Widget:SetAttribute(name, value)
    assert(not (combat and self.protected and not secure), "insecure attribute in combat")
    self.attributes[name] = value
    if self.scripts.OnAttributeChanged then
        local previous = secure
        secure = false
        self.scripts.OnAttributeChanged(self, name, value)
        secure = previous
    end
end
local function NewWidget()
    return setmetatable({ scripts = {}, attributes = {}, refs = {}, events = {} }, Widget)
end
function Widget:CreateTexture() return NewWidget() end
function Widget:CreateFontString() return NewWidget() end
function CreateFrame(kind, name, parent, template)
    local frame = NewWidget()
    frame.name, frame.kind, frame.parent, frame.template = name, kind, parent, template
    frame.protected = (template and template:find("Secure")) or (parent and parent.protected)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 880)
function InCombatLockdown() return combat end
function GetCursorInfo() if cursor then return "spell", cursor end end
function PickupAction(slot)
    assert(not combat)
    transfers[#transfers + 1] = { "pickup", slot }
    cursor, slots[slot] = slots[slot], cursor
end
function PlaceAction(slot)
    assert(not combat)
    transfers[#transfers + 1] = { "place", slot }
    cursor, slots[slot] = slots[slot], cursor
end
local function getTexture(slot) return slots[slot] and "texture:" .. slots[slot] end
local function getCooldown(slot)
    if apiFlavor == "modern" then return { startTime = 10, duration = 2, modRate = 1 } end
    return 10, 2, 1, 1
end
if apiFlavor == "modern" then
    C_ActionBar = { GetActionTexture = getTexture, GetActionCooldown = getCooldown }
    PlayerSpellsUtil = {
        ToggleSpellBook = function() opened[#opened + 1] = "Spells" end,
        ToggleTalentsFrame = function() opened[#opened + 1] = "Talents" end,
    }
else
    GetActionTexture, GetActionCooldown = getTexture, getCooldown
    function ToggleSpellBook() opened[#opened + 1] = "Spells" end
    function ToggleTalentFrame() opened[#opened + 1] = "Talents" end
end
function ToggleCharacter() opened[#opened + 1] = "Character" end
function ToggleAllBags() opened[#opened + 1] = "Bags" end
function ToggleWorldMap() opened[#opened + 1] = "Map" end
GameMenuFrame = { IsShown = function() return false end }
function ShowUIPanel() opened[#opened + 1] = "Menu" end
function HideUIPanel() opened[#opened + 1] = "Menu" end
UIErrorsFrame = { AddMessage = function(_, text) notices[#notices + 1] = text end }
GameTooltip = {
    SetOwner = function() end, SetAction = function() end, SetText = function() end,
    Show = function() end, Hide = function() end,
}
-- These must never be called by ordinary addon Lua, from events or UI scripts.
function UseAction() error("insecure action execution") end
function CastSpellByID() error("insecure spell execution") end
function RunMacroText() error("insecure macro execution") end
assert(loadfile(addonPath))("WolkaraTouch")
local function event(name)
    for _, frame in ipairs(frames) do
        if frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name) end
    end
end
local function pageClick(index, mouseButton, down)
    local button = _G["WolkaraTouchModifier" .. index]
    equal(button.template, "SecureHandlerClickTemplate")
    local snippet = button:GetAttribute("_onclick")
    -- Restricted snippets must not require unsupported closures or Lua tables.
    assert(not snippet:match("%f[%a]function%f[%A]"))
    assert(not snippet:find("{", 1, true))
    secure = true
    compile(snippet, { self = button, button = mouseButton or "LeftButton", down = down })()
    secure = false
end

-- Login/reload in combat must not construct or move protected UI.
combat = true
event("PLAYER_LOGIN")
assert(not WolkaraTouchPanel)
combat = false
event("PLAYER_REGEN_ENABLED")
assert(WolkaraTouchPanel)
local base = { [0] = 1, 61, 49, 25, 37 }
local count = #frames
event("PLAYER_ENTERING_WORLD")
equal(#frames, count, "initialization must be idempotent")
for index = 1, 8 do
    local button = _G["WolkaraTouchAction" .. index]
    equal(button.template, "SecureActionButtonTemplate")
    equal(button:GetAttribute("type"), "action")
    equal(button:GetAttribute("action"), index)
    equal(button.clicks[1], "AnyDown")
    equal(button.clicks[2], "AnyUp")
    equal(button.cooldown.cooldownValues[1], 10)
    for page = 0, 4 do equal(button:GetAttribute("page" .. page), base[page] + index - 1) end
end

-- Page changes in combat only alter attributes from the secure click snippet.
combat = true
for page = 1, 4 do
    pageClick(page)
    equal(WolkaraTouchPanel:GetAttribute("page"), page)
    for index = 1, 8 do equal(_G["WolkaraTouchAction" .. index]:GetAttribute("action"), base[page] + index - 1) end
    equal(WolkaraTouchPanel.caption.text, "M" .. page)
end
pageClick(4, "RightButton")
pageClick(4, "LeftButton", true)
equal(WolkaraTouchPanel:GetAttribute("page"), 4, "wrong button/edge must not change page")
pageClick(4)
equal(WolkaraTouchPanel:GetAttribute("page"), 0, "second tap returns to base")

-- A selected modifier remains selected while moving a spell from the spellbook.
combat = false
cursor = "spellbook-spell"
pageClick(2)
equal(cursor, "spellbook-spell", "page selection must preserve cursor contents")
equal(#transfers, 0, "page selection must not modify action slots")
local action = WolkaraTouchAction5
action.scripts.OnReceiveDrag(action)
equal(slots[53], "spellbook-spell")
equal(action.icon.texture, "texture:spellbook-spell")
equal(WolkaraTouchPanel:GetAttribute("page"), 2)
equal(cursor, nil)
action.scripts.OnDragStart(action)
equal(cursor, "spellbook-spell")
pageClick(3)
WolkaraTouchAction8.scripts.OnReceiveDrag(WolkaraTouchAction8)
equal(slots[32], "spellbook-spell", "drag can cross page selection")
local before = #transfers
combat = true
cursor = "blocked-spell"
action.scripts.OnReceiveDrag(action)
action.scripts.OnDragStart(action)
equal(#transfers, before, "combat drag must be rejected")
equal(cursor, "blocked-spell")
equal(#notices, 2)

-- Relayout requested in combat is delayed until it is safe.
local oldWidth = WolkaraTouchPanel.width
UIParent.width, UIParent.height = 1024, 768
event("UI_SCALE_CHANGED")
equal(WolkaraTouchPanel.width, oldWidth)
combat = false
event("PLAYER_REGEN_ENABLED")
assert(WolkaraTouchPanel.width ~= oldWidth)
for _, screen in ipairs({ { 1920, 880 }, { 1024, 768 }, { 2732, 2048 }, { 1334, 750 } }) do
    UIParent.width, UIParent.height = screen[1], screen[2]
    event("DISPLAY_SIZE_CHANGED")
    local width, height = screen[1], screen[2]
    local panelLeft = width * 0.96 - WolkaraTouchPanel.width
    assert(panelLeft >= width * 0.67, "ability panel enters camera region")
    assert(height * 0.20 + WolkaraTouchPanel.height <= height * 0.84, "panel enters bottom controls")
    for index = 1, 6 do
        local menu = _G["WolkaraTouchMenu" .. index]
        assert(menu.height + height * 0.025 <= height * 0.16, "menu outside direct-touch strip")
    end
end

for index = 1, 6 do _G["WolkaraTouchMenu" .. index].scripts.OnClick() end
equal(table.concat(opened, ","), "Spells,Character,Talents,Bags,Map,Menu")
combat = true
WolkaraTouchMenu3.scripts.OnClick()
equal(#opened, 6, "talents must not open from insecure code in combat")
print("WolkaraTouch " .. apiFlavor .. ": page, drag, combat deferral and layout checks passed")
