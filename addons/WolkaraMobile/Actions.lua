-- Adapted from pookee/wolkaraforever, 1843b131 (MIT); see LICENSE.
-- Mobile touch action circle shared across free-placed and side-bar spell slots.

local _, ns = ...

ns.BUILTIN = {
    { kind = "macrotext", id = "/targetenemy", name = "Target enemy", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { kind = "macrotext", id = "/startattack", name = "Auto attack", icon = "Interface\\Icons\\INV_Sword_04" },
    { kind = "macrotext", id = "/assist", name = "Assist", icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { kind = "macrotext", id = "/targetfriend", name = "Target friend", icon = "Interface\\Icons\\Spell_Holy_Heal" },
    { kind = "macrotext", id = "/cleartarget", name = "Clear target", icon = "Interface\\Icons\\Spell_Shadow_Teleport" },
    { kind = "macrotext", id = "/follow", name = "Follow", icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
    { kind = "macrotext", id = "/sit", name = "Sit", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
}

ns.DESKTOP_BAR_LIMIT = 180

local function ValidActionID(value)
    return not ns.IsSecret(value) and type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

function ns.DesktopActionList()
    local ordered, records = {}, {}
    local function append(slot)
        local kind, id, subtype = ns.ActionInfo(slot)
        if ns.IsSecret(kind) or ns.IsSecret(id) or ns.IsSecret(subtype) or not kind or not id then return end
        local texture = ns.ActionTexture(slot)
        if not ns.IsSecret(texture) and not texture then return end
        local key = tostring(kind) .. ":" .. tostring(id) .. ":" .. tostring(subtype or "")
        if records[key] then return end
        records[key] = { slot = slot, kind = kind, id = id, subtype = subtype, texture = texture }
        ordered[#ordered + 1] = key
    end
    local page = ns.ActionBarPage() or 1
    if ns.IsSecret(page) or type(page) ~= "number" or page < 1 then page = 1 end
    local first = (math.max(1, math.min(6, page)) - 1) * 12 + 1
    for slot = first, first + 11 do append(slot) end
    for slot = 1, ns.DESKTOP_BAR_LIMIT do append(slot) end
    return ordered, records
end

function ns.SplitDesktopToSides(ordered, records)
    local profile, count = { left = {}, right = {} }, 0
    for _, key in ipairs(ordered or {}) do
        local rec = records and records[key]
        if rec then
            count = count + 1
            local target = (count % 2 == 1) and profile.right or profile.left
            if ValidActionID(rec.id) and (rec.kind == "item" or (rec.kind == "spell" and rec.subtype ~= "pet" and rec.subtype ~= "flyout")) then
                target[#target + 1] = { kind = rec.kind, id = rec.id }
            else
                target[#target + 1] = { kind = "desktop", key = key }
            end
        end
    end
    return profile
end

function ns.EntryIcon(entry, records)
    if not entry then return nil end
    if entry.kind == "spell" then return ns.SpellIcon(entry.id) end
    if entry.kind == "item" then return ns.ItemIcon(entry.id) end
    if entry.kind == "macro" then
        local _, icon = GetMacroInfo(entry.id)
        return icon
    end
    if entry.kind == "macrotext" then return entry.icon end
    if entry.kind == "desktop" then
        local rec = records and records[entry.key]
        if rec then return ns.ActionTexture(rec.slot) or rec.texture end
    elseif entry.kind == "action" and entry.id then
        return ns.ActionTexture(entry.id)
    end
end

function ns.EntryName(entry, records)
    if not entry then return nil end
    local kind, id = entry.kind, entry.id
    if kind == "desktop" then
        local rec = records and records[entry.key]
        if not rec then return entry.key end
        kind, id = rec.kind, rec.id
    end
    if kind == "spell" then return ns.SpellName(id) end
    if kind == "item" then return ns.ItemName(id) end
    if kind == "macro" and GetMacroInfo then return GetMacroInfo(id) or entry.name or id end
    return entry.name or (id and tostring(id))
end

function ns.ApplyButton(button, records)
    if InCombatLockdown() then return false end
    button.suppressed = nil
    local entry = button:GetEntry()
    local recs = records or ns.desktopRecords
    button:SetAttribute("action", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macro", nil)
    button:SetAttribute("macrotext", nil)
    local rec = entry and entry.kind == "desktop" and recs and recs[entry.key] or nil
    if not ns.enabled or ns.editing or not entry then
        button:SetAttribute("type", nil)
    elseif rec and rec.slot then
        button:SetAttribute("type", "action")
        button:SetAttribute("action", rec.slot)
    elseif entry.kind == "action" and entry.id then
        button:SetAttribute("type", "action")
        button:SetAttribute("action", entry.id)
    elseif entry.kind == "spell" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", ns.SpellName(entry.id) or entry.id)
    elseif entry.kind == "item" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. entry.id)
    elseif entry.kind == "macro" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macro", entry.id)
    elseif entry.kind == "macrotext" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", entry.id)
    else
        button:SetAttribute("type", nil)
    end
    return true
end

local GLOBAL_COOLDOWN = 2
local ticking = {}

function ns.CooldownText(remaining)
    if remaining >= 60 then return math.ceil(remaining / 60) .. "m" end
    if remaining >= 3 then return tostring(math.ceil(remaining)) end
    return string.format("%.1f", remaining)
end

local function StopTimer(button)
    ticking[button] = nil
    if button.timer then button.timer:SetText("") end
    button.icon:SetDesaturated(false)
end

local ticker = CreateFrame("Frame")
local sinceTick = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    if not ns.enabled then return end
    sinceTick = sinceTick + elapsed
    if sinceTick < 0.1 then return end
    sinceTick = 0
    local now = GetTime()
    for button, ends in pairs(ticking) do
        if ends - now <= 0 then StopTimer(button) else button.timer:SetText(ns.CooldownText(ends - now)) end
    end
end)

function ns.UpdateCooldown(button)
    local entry = button:GetEntry()
    local slot = button.GetAttribute and button:GetAttribute("action")
    local start, duration, enable
    if slot then
        start, duration, enable = ns.ActionCooldown(slot)
    elseif entry and entry.kind == "spell" then
        start, duration, enable = ns.SpellCooldown(entry.id)
    elseif entry and entry.kind == "item" then
        start, duration, enable = ns.ItemCooldown(entry.id)
    end
    if not ns.IsSecret(start) and not ns.IsSecret(duration)
        and start and duration and duration > 0 and enable ~= 0 and enable ~= false then
        if CooldownFrame_Set then
            CooldownFrame_Set(button.cooldown, start, duration, 1)
        else
            button.cooldown:SetCooldown(start, duration)
            button.cooldown:Show()
        end
        if duration > GLOBAL_COOLDOWN and button.timer then
            ticking[button] = start + duration
            button.timer:SetText(ns.CooldownText(math.max(0, start + duration - GetTime())))
            button.icon:SetDesaturated(true)
        else
            StopTimer(button)
        end
    else
        if button.cooldown.Clear then button.cooldown:Clear() end
        button.cooldown:Hide()
        StopTimer(button)
    end
end

function ns.UpdateState(button)
    local entry = button:GetEntry()
    if not entry then return end
    local slot = button.GetAttribute and button:GetAttribute("action")
    local usable, noPower, inRange = true, false, nil
    if slot then
        usable, noPower = ns.ActionUsable(slot)
        inRange = ns.ActionInRange(slot)
    elseif entry.kind == "spell" then
        usable, noPower = ns.SpellUsable(entry.id)
        inRange = ns.SpellInRange(entry.id)
    elseif entry.kind == "item" then
        usable = (ns.ItemCount(entry.id) or 0) > 0
    end
    if inRange == false then
        button.icon:SetVertexColor(0.95, 0.3, 0.3)
    elseif noPower then
        button.icon:SetVertexColor(0.4, 0.5, 1)
    elseif usable == false then
        button.icon:SetVertexColor(0.45, 0.45, 0.45)
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
end

function ns.RefreshButton(button)
    local entry = button:GetEntry()
    local slot = button.GetAttribute and button:GetAttribute("action")
    button.count:SetText("")
    if entry then
        button.icon:SetTexture(ns.EntryIcon(entry, ns.desktopRecords) or ns.QUESTION)
        button.icon:Show()
        button.plus:Hide()
        if button.ring then button.ring:SetVertexColor(0.65, 0.49, 0.28, 0.95) end
        if slot then
            local count = ns.ActionCount(slot)
            if not ns.IsSecret(count) and type(count) == "number" and count > 1 then
                button.count:SetText(count)
            end
        elseif entry.kind == "item" then
            local count = ns.ItemCount(entry.id) or 0
            if count ~= 1 then button.count:SetText(count) end
        end
    else
        button.icon:Hide()
        button.plus:Show()
        if button.ring then button.ring:SetVertexColor(0.65, 0.49, 0.28, 0.45) end
    end
    button.icon:SetVertexColor(1, 1, 1)
    button.editGlow:SetShown(ns.editing)
    ns.UpdateCooldown(button)
    ns.UpdateState(button)
end

function ns.AssignEntry(button, entry)
    button:SetEntry(entry)
    ns.MarkChanged()
    ns.RefreshButton(button)
    ns.ApplyButton(button)
    if button.OnAssigned then button:OnAssigned() end
end

function ns.AssignFromCursor(button)
    if InCombatLockdown() then
        ns.Print("Assign abilities outside combat.")
        return
    end
    local entry = ns.CursorEntry()
    if not entry then return end
    local previous = button:GetEntry()
    ns.AssignEntry(button, entry)
    ClearCursor()
    if previous and previous.kind ~= "macrotext" then ns.PickupEntry(previous) end
end

function ns.CreateActionButton(name, parent, size, getEntry, setEntry)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button:SetSize(size, size)
    button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("AnyUp", "AnyDown")
    button.GetEntry = function() return getEntry() end
    button.SetEntry = function(_, entry) setEntry(entry) end

    button.ring = ns.Disc(button, "BACKGROUND", 0.78, 0.70, 0.50, 0.55, 2)
    ns.Disc(button, "BORDER", 0.05, 0.05, 0.08, 0.85, 0)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local round = ns.Circle(button, button.icon)
    if not round then button:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2") end

    button.plus = ns.Label(button, "GameFontNormalHuge", "+")
    button.plus:SetPoint("CENTER")
    button.plus:SetTextColor(0.65, 0.62, 0.55)

    button.count = ns.Label(button, "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -6, 6)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    if round and button.cooldown.SetSwipeTexture then button.cooldown:SetSwipeTexture(ns.CIRCLE) end
    if button.cooldown.SetUseCircularEdge then button.cooldown:SetUseCircularEdge(true) end
    if button.cooldown.SetSwipeColor then button.cooldown:SetSwipeColor(0, 0, 0, 0.75) end
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(true) end
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
    button.timer = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    button.timer:SetPoint("CENTER")
    button.timer:SetTextColor(1, 1, 1)
    button.timer:SetShadowOffset(1, -1)

    button.editGlow = ns.Disc(button, "OVERLAY", 1, 0.8, 0.2, 0.28, 0)
    button.editGlow:Hide()
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    highlight:SetBlendMode("ADD")

    button:SetScript("PreClick", function(self)
        if InCombatLockdown() or self.swiped then return end
        if ns.editing or GetCursorInfo() or not self:GetEntry() then
            self:SetAttribute("type", nil)
            self.suppressed = true
        end
    end)
    button:SetScript("PostClick", function(self, _, down)
        if self.swiped and not down then self.swiped = nil; return end
        local gesture=ns.bridge and ns.bridge:GetAttribute("gesture")
        if gesture=="drag" or gesture=="hold" then return end
        if InCombatLockdown() or down or not self.suppressed then return end
        if GetCursorInfo() then
            ns.AssignFromCursor(self)
        elseif ns.editing and ns.SelectButton then
            ns.SelectButton(self)
        elseif ns.Picker then
            ns.Picker:Open(self)
        end
        ns.ApplyButton(self)
    end)
    button:SetScript("OnReceiveDrag", function(self) ns.AssignFromCursor(self) end)
    return button
end
