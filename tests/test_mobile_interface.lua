-- Synthetic addon API fixture: no client files, account, gameplay or network.
-- Exercises our actual modules and restricted snippets. Physical WoW validation
-- remains required for FrameXML version differences and combat security/taint.
unpack = unpack or table.unpack
local compile = loadstring or load
local combat, now, reloads = false, 100, 0
local secure = false
local frames, bindings, messages = {}, {}, {}
local cursor, pickedUp = nil, nil
local masksAdded, maskTextures = 0, {}
local bagsToggled, mapToggled = 0, 0

function InCombatLockdown() return combat end
function GetTime() return now end
function UnitExists() return false end
function GetCursorInfo()
    if not cursor then return nil end
    return cursor.kind, cursor.a, cursor.b, cursor.c
end
function ClearCursor() cursor = nil end
function PickupSpell(id) pickedUp = { kind = "spell", id = id }; cursor = { kind = "spell", c = id } end
function PickupItem(id) pickedUp = { kind = "item", id = id }; cursor = { kind = "item", a = id } end
function PickupMacro(id) pickedUp = { kind = "macro", id = id }; cursor = { kind = "macro", a = 1 } end
function GetSpellInfo(id) return "Spell " .. tostring(id) end
function GetSpellTexture() return "fixture-icon" end
function GetSpellCooldown() return 0, 0, 1 end
function IsUsableSpell() return true, false end
function GetNumSpellTabs() return 0 end
function GetItemIcon(id) return "item-icon-" .. tostring(id) end
function GetItemInfo(id) return "Item " .. tostring(id) end
function GetItemCount() return 5 end
function GetMacroInfo(id) return "Macro " .. tostring(id), "macro-icon" end
function GetNumMacros() return 0, 0 end
function ToggleAllBags() bagsToggled = bagsToggled + 1 end
function ToggleWorldMap() mapToggled = mapToggled + 1 end
function ReloadUI() reloads = reloads + 1 end
function RegisterStateDriver(f, state, body) f.drivers = f.drivers or {}; f.drivers[state] = body end
function SetOverrideBindingClick(_, _, key, button) bindings[key] = button end
function hooksecurefunc(name, fn)
    local original = _G[name]
    _G[name] = function(...) local r = original(...); fn(...); return r end
end
function ShowUIPanel(f) f:Show() end
function HideUIPanel(f) f:Hide() end
function UpdateContainerFrameAnchors() end
C_Timer = { After = function(_, fn) fn() end }
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, s) messages[#messages + 1] = s end }

local Frame = {}
local function Noop() end
for _, name in ipairs({
    "SetAllPoints", "SetColorTexture", "SetTextColor", "SetTexCoord",
    "SetDesaturated", "SetVertexColor", "SetBlendMode", "SetNormalTexture",
    "SetShadowOffset", "SetFrameStrata", "SetMovable", "EnableMouse",
    "RegisterForClicks", "RegisterForDrag", "RegisterEvent", "SetUseCircularEdge",
    "SetSwipeTexture", "SetSwipeColor", "SetHideCountdownNumbers",
    "SetJustifyV", "SetMaxLines", "SetCooldown", "Clear"
}) do Frame[name] = Noop end
function Frame:SetTexture(path) self.texturePath = path end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Frame:GetName() return self.name end
function Frame:GetObjectType() return self.kind end
function Frame:GetChildren() return unpack(self.children) end
function Frame:GetParent() return self.parent end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetPoint(...) self.points = { { ... } } end
function Frame:GetPoint(i) return unpack(self.points[i]) end
function Frame:GetNumPoints() return #self.points end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetCenter() local p = self.points[1]; return p and p[4] or 500, p and p[5] or 300 end
function Frame:GetRight() return self.w end
function Frame:GetTop() return self.h end
function Frame:SetScale(n) assert(not (combat and self.protected)); self.scale = n end
function Frame:GetScale() return self.scale end
function Frame:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:SetClampedToScreen(on) self.clamped = on end
function Frame:IsClampedToScreen() return self.clamped end
function Frame:SetClampRectInsets(...) self.insets = { ... } end
function Frame:GetClampRectInsets() return unpack(self.insets) end
function Frame:IsProtected() return self.protected end
function Frame:SetAttribute(key, value)
    assert(secure or not (combat and self.protected), "insecure protected attribute in combat")
    self.attrs[key] = value
end
function Frame:GetAttribute(key) return self.attrs[key] end
function Frame:SetFrameRef(key, value) self.refs[key] = value end
function Frame:GetFrameRef(key) return self.refs[key] end
function Frame:CallMethod(key, ...)
    local previous = secure; secure = false
    local value = self[key](self, ...)
    secure = previous; return value
end
function Frame:GetID() return self.id or 0 end
function Frame:SetID(id) self.id = id end
function Frame:SetFrameLevel(n) self.level = n end
function Frame:GetFrameLevel() return self.level end
function Frame:SetText(t) self.label = t; if self.font then self.font.label = t end end
function Frame:GetFontString() self.font = self.font or self:CreateFontString(); self.font.label = self.label; return self.font end
function Frame:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() assert(not (combat and self.protected), "insecure hide in combat"); self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(on) if on then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:Click(button, down)
    button = button or "LeftButton"; down = down or false
    if self.scripts.PreClick then self.scripts.PreClick(self, button, down) end
    if self.scripts.OnClick then self.scripts.OnClick(self, button, down) end
    if self.scripts.PostClick then self.scripts.PostClick(self, button, down) end
end
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({
        kind = kind, name = name, parent = parent, children = {}, scripts = {},
        attrs = {}, refs = {}, points = {}, insets = { 0, 0, 0, 0 },
        shown = true, scale = 1, w = 100, h = 100, level = 1, clamped = false,
        protected = template and template:find("Secure") ~= nil
    }, { __index = Frame })
    if parent then parent.children[#parent.children + 1] = f end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    if template and template:find("SecureActionButtonTemplate") then
        f.scripts.OnClick = function(self, _, down)
            if not down and self.attrs.type then self.casts = (self.casts or 0) + 1 end
        end
    end
    return f
end
function Frame:CreateTexture() return CreateFrame("Texture", nil, nil) end
function Frame:CreateMaskTexture() return CreateFrame("MaskTexture", nil, nil) end
function Frame:AddMaskTexture(mask)
    masksAdded = masksAdded + 1
    if mask and mask.texturePath then maskTextures[mask.texturePath] = true end
end
function Frame:CreateFontString() return CreateFrame("FontString", nil, nil) end
function SecureHandlerWrapScript(f, script, control, body)
    local snippet = assert(compile("return function(self,control,button,down) " .. body .. " end"))()
    local original = f:GetScript(script)
    f:SetScript(script, function(self, button, down)
        secure = true
        local override = snippet(self, control, button, down)
        secure = false
        if override == false then return end
        if original then original(self, override or button, down) end
    end)
end

UIParent = CreateFrame("Frame", "UIParent"); UIParent:SetSize(1000, 700)
GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent); GameMenuFrame:Hide()
local original = CreateFrame("Frame", "QuestFrame", UIParent)
original:SetSize(600, 1200); original:SetScale(.8); original:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -25)
original:SetClampRectInsets(1, 2, 3, 4)
local bag = CreateFrame("Frame", "ContainerFrame1", UIParent); bag:SetID(0)
local slot = CreateFrame("ItemButton", "ContainerFrame1Item1", bag); slot:SetID(1); slot.icon = slot:CreateTexture()
local clicks = {}; slot:SetScript("OnClick", function(_, button, down) if not down then clicks[#clicks + 1] = button end end)

local ns = {}
for line in io.lines("addons/WolkaraMobile/WolkaraMobile.toc") do
    if line:match("%.lua$") then assert(loadfile("addons/WolkaraMobile/" .. line))("WolkaraMobile", ns) end
end
local function Event(name, ...) ns.events:GetScript("OnEvent")(ns.events, name, ...) end
local function Clean()
    for _, s in ipairs(messages) do assert(not s:match("attempt") and not s:match("insecure"), s) end
end
local function Button(parent, text)
    for _, f in ipairs(parent.children) do
        if f.kind == "Button" and (f.label == text or f.font and f.font.label == text) then return f end
    end
    error("missing button " .. text)
end

ns.hostSession = "fixture-session"
Event("ADDON_LOADED", "WolkaraMobile"); Clean()
-- Pre-seeded 12 left + 8 right side round buttons masked with TempPortraitAlphaMask.
assert(#ns.db.buttons == 20 and ns.db.seeded)
assert(ns.db.buttons[1].x <= 0.25 and ns.db.buttons[13].x >= 0.75)
assert(masksAdded >= 20 and maskTextures[ns.CIRCLE])
assert(not WolkaraMobileAbility21)

Event("PLAYER_LOGIN"); assert(not ns.enabled and original:GetScale() == .8)
assert(bindings["ALT-CTRL-SHIFT-F6"] == "WolkaraMobileCommand1")
assert(bindings["ALT-SHIFT-F7"] == "WolkaraMobileCommand8")

local tracePath = os.getenv("WOLKARA_MOBILE_EVENT_TRACE")
if tracePath then
    local modifiers, received, pendingKey = {}, {}, nil
    local modifierCodes = { [58] = "ALT", [61] = "ALT", [59] = "CTRL", [62] = "CTRL", [56] = "SHIFT", [60] = "SHIFT", [55] = "META", [54] = "META" }
    local bits = { ALT = 2^19, CTRL = 2^18, SHIFT = 2^17, META = 2^20 }
    local function Has(n, bit) return n % (2 * bit) >= bit end
    local function Chord(code)
        local parts = {}
        for _, key in ipairs({ "ALT", "CTRL", "SHIFT", "META" }) do if modifiers[key] then parts[#parts + 1] = key end end
        assert(code == 97 or code == 98, "bridge must not emit bag function keys")
        parts[#parts + 1] = code == 97 and "F6" or "F7"
        return table.concat(parts, "-")
    end
    for line in io.lines(tracePath) do
        local cmd, kind, code, flags = line:match("^(%d+)\t(%d+)\t(%d+)\t(%d+)$")
        cmd, kind, code, flags = tonumber(cmd), tonumber(kind), tonumber(code), tonumber(flags)
        assert(cmd and kind and code and flags, "malformed trace")
        if kind == 12 then
            local key = assert(modifierCodes[code], "invalid modifier transition")
            modifiers[key] = Has(flags, bits[key])
        elseif kind == 10 then
            pendingKey = Chord(code); assert(bindings[pendingKey], "native chord missing from addon: " .. pendingKey)
        elseif kind == 11 then
            assert(pendingKey == Chord(code), "modifier state lost before key-up")
            local button = assert(_G[bindings[pendingKey]])
            assert(button:GetName() == "WolkaraMobileCommand" .. (cmd + 1), "wrong bridge command")
            local fn = assert(compile("return function(self) " .. button:GetAttribute("_onclick") .. " end"))()
            secure = true; fn(button); secure = false; received[cmd] = true; pendingKey = nil
        else
            error("unexpected trace event")
        end
    end
    for cmd = 0, 7 do assert(received[cmd], "missing command round trip") end
    assert(not pendingKey)
    for _, held in pairs(modifiers) do assert(not held, "modifier left held") end
    assert((ns.hostCommands or 0) > 0 and not ns.errors)
    ns.SetEnabled(false); ns.editing = false; ns.dirty = false; ns.bridge:SetAttribute("gesture", nil)
    SlashCmdList.WOLKARAMOBILE(); assert(messages[#messages]:find("v1.1.0"))
    print("MOBILE_BRIDGE_ROUNDTRIP_PASS: native modifier edges resolve all 8 actual addon bindings")
end

local function Mark(gesture) ns.bridge.attrs.gesture = gesture end
slot:Click(); assert(clicks[#clicks] == "LeftButton") -- Disabled mode never converts.
ns.SetEnabled(true); assert(ns.enabled and original:GetScale() < .8)
-- Top-right HUD box was removed in favor of the iOS top bar; /wm menu opens panel explicitly.
SlashCmdList.WOLKARAMOBILE("menu"); assert(WolkaraMobileMenu:IsShown())
SlashCmdList.WOLKARAMOBILE("menu"); assert(not WolkaraMobileMenu:IsShown())

slot:Click(); assert(clicks[#clicks] == "LeftButton") -- Untagged physical pointer unchanged.
Mark("tap"); slot:Click(); assert(clicks[#clicks] == "RightButton")
assert(ns.bridge:GetAttribute("gesture") == nil)
slot:Click(); assert(clicks[#clicks] == "LeftButton")
local count = #clicks
Mark("drag"); slot:Click(); assert(#clicks == count)
Mark("hold"); slot:Click(); assert(#clicks == count and WolkaraMobileBagOptions:IsShown())
Mark(nil); Button(WolkaraMobileBagOptions, "Cancel"):Click(); assert(not WolkaraMobileBagOptions:IsShown())

-- Drop a spell directly onto a seeded round side button via OnReceiveDrag & swap with an item.
local ability1 = WolkaraMobileAbility1
local ability2 = WolkaraMobileAbility2
local right1 = WolkaraMobileAbility13
assert(ability1:IsShown() and ability2:IsShown() and right1:IsShown())
cursor = { kind = "spell", c = 456 }
ability1:GetScript("OnReceiveDrag")(ability1)
assert(ns.db.buttons[1].entry.kind == "spell" and ns.db.buttons[1].entry.id == 456)
assert(cursor == nil and ability1:GetAttribute("type") == "spell" and ability1:GetAttribute("spell") == "Spell 456")

cursor = { kind = "item", a = 789 }
ability1:GetScript("OnReceiveDrag")(ability1)
assert(ns.db.buttons[1].entry.kind == "item" and ns.db.buttons[1].entry.id == 789)
assert(pickedUp and pickedUp.kind == "spell" and pickedUp.id == 456)
cursor = nil

-- Re-assign spell 123 on ability1 and test Picker -> Edit Layout + Hide empty + drag move + Reset sides.
ns.AssignEntry(ability1, { kind = "spell", id = 123 })
Mark("tap"); ability2:Click("LeftButton", true); ability2:Click("LeftButton", false)
assert(ns.Picker:IsOpen())
Button(WolkaraMobilePicker, "Edit Layout"):Click()
assert(not ns.Picker:IsOpen() and ns.editing)

ns.SelectButton(ability1)
Button(WolkaraMobileEditor, "Larger"):Click(); assert(ns.db.buttons[1].size == 48)
ability1:GetScript("OnDragStart")(ability1)
ability1:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 720, 420)
ability1:GetScript("OnDragStop")(ability1)
assert(math.abs(ns.db.buttons[1].x - .72) < .001 and math.abs(ns.db.buttons[1].y - .6) < .001)

Button(WolkaraMobileEditor, "Hide empty"):Click()
assert(ns.db.hideEmpty)
ns.SetEditing(false); ability1.swiped = nil
assert(ability1:IsShown() and not ability2:IsShown() and not right1:IsShown())

Mark("tap"); ability1:Click("LeftButton", true); ability1:Click(); assert(ability1.casts == 1)
Mark("drag"); ability1:Click(); assert(ability1.casts == 1)
Mark("hold"); ability1:Click(); assert(ability1.casts == 1)

SlashCmdList.WOLKARAMOBILE("reset")
assert(#ns.db.buttons == 20 and ns.db.buttons[1].x <= 0.25 and ns.db.buttons[1].entry.id == 123)

-- Combat: no protected attributes/layout changes, drag never casts, off queues.
combat = true; Event("PLAYER_REGEN_DISABLED")
Mark("tap"); ability1:Click(); assert(ability1.casts == 2)
Mark("drag"); ability1:Click(); Mark("drag"); slot:Click(); assert(ability1.casts == 2 and #clicks == count)
ns.SetEnabled(false); assert(ns.enabled)
combat = false; Event("PLAYER_REGEN_ENABLED"); assert(not ns.enabled and not ability1:IsShown())
assert(original:GetScale() == .8 and original:IsClampedToScreen() == false)
local a, b, c, d = original:GetClampRectInsets(); assert(a == 1 and b == 2 and c == 3 and d == 4)
local _, _, _, x, y = original:GetPoint(1); assert(x == 12 and y == -25)
assert(ns.db.buttons[1].entry.id == 123) -- Toggle never discards layout.

-- Explicit save only; rendering, resize, enable/disable never reload the UI.
assert(reloads == 0); ns.SetEnabled(true); ns.FinishEditing(); assert(reloads == 1)
ns.SetEnabled(false); Event("PLAYER_LOGIN"); assert(not ns.enabled) -- Same-session reload keeps toggle.
ns.hostSession = "next-launch"; ns.hostEnabled = true; Event("PLAYER_LOGIN"); assert(ns.enabled)

ns.SetEditing(true)
for _ = 21, 70 do Button(WolkaraMobileEditor, "Add"):Click() end
assert(#ns.db.buttons == 64)
ns.AssignEntry(WolkaraMobileAbility64, { kind = "spell", id = 999 })
ns.SetEditing(false)
Mark("drag"); WolkaraMobileAbility64:Click(); assert(not WolkaraMobileAbility64.casts)
Mark("tap"); WolkaraMobileAbility64:Click(); assert(WolkaraMobileAbility64.casts == 1)
ns.SetEnabled(false); Clean()
assert(not ns.errors)
print("MOBILE_ADDON_PASS: seeded side round buttons, drag/drop assignment, hide-empty, /wm menu & reset, combat queue and limits")
