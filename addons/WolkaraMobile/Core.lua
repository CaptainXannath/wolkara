-- Wolkara mobile interface. Compatibility helpers adapted from pookee/WolkaraRoue (MIT).
local _, ns = ...
ns.MAX_BUTTONS = 64
ns.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
ns.STICK_X, ns.STICK_Y = 0.12, 0.222
ns.enabled, ns.editing = false, false
local modules, events, pending = {}, {}, nil
local pendingEdit, pendingDone
function ns.Print(text) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffWolkara:|r " .. tostring(text)) end
function ns.Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then ns.errors=(ns.errors or 0)+1; ns.Print(label .. ": " .. tostring(err)) end
    return ok
end
function ns.Register(name, module) module.name=name; modules[#modules+1]=module; return module end
function ns.Each(method, ...)
    for _, m in ipairs(modules) do if m[method] then ns.Guard(m.name, m[method], m, ...) end end
end
function ns.On(event, fn)
    if not events[event] then events[event]={}; ns.events:RegisterEvent(event) end
    table.insert(events[event], fn)
end
ns.events=CreateFrame("Frame")
ns.events:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(events[event] or {}) do ns.Guard(event,fn,...) end
end)
function ns.Clamp(n, low, high) return math.max(low,math.min(high,n)) end
function ns.MarkChanged() ns.dirty=true end
function ns.Layout()
    if InCombatLockdown() then ns.pendingLayout=true; return end
    if ns.enabled then ns.Each("Layout") end
end
function ns.Refresh() if ns.enabled then ns.Each("Refresh") end end
function ns.SetEnabled(on)
    if InCombatLockdown() then pending=on; ns.Print("Interface change queued until combat ends."); return end
    pending=nil; ns.enabled=on and true or false
    ns.db.enabled=ns.enabled
    if ns.bridge then ns.bridge:SetAttribute("enabled",ns.enabled); ns.bridge:SetAttribute("gesture",nil) end
    if ns.enabled then ns.Layout(); ns.Refresh()
    else ns.editing=false; pendingEdit=nil; ns.Each("Disable") end
end
function ns.SetEditing(on)
    if not ns.enabled then return end
    if InCombatLockdown() then pendingEdit=on; ns.Print("Ability editing queued until combat ends."); return end
    pendingEdit=nil
    ns.editing=on and true or false
    ns.Each("SetEditing",ns.editing); ns.Layout(); ns.Refresh()
end
function ns.FinishEditing()
    if InCombatLockdown() then pendingDone=true; ns.Print("Saving queued until combat ends."); return end
    pendingDone=nil
    ns.SetEditing(false)
    if ns.dirty then ns.dirty=false; ReloadUI() end -- explicit Done & save, never a timer
end
function ns.Circle(frame, texture)
    if frame and frame.CreateMaskTexture and texture and texture.AddMaskTexture then
        local mask = frame:CreateMaskTexture()
        mask:SetTexture(ns.CIRCLE, "CLAMPTOEDGE", "CLAMPTOEDGE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
        return true
    end
    return false
end
function ns.Box(frame, layer, r,g,b,a)
    local t=frame:CreateTexture(nil,layer); t:SetAllPoints(); t:SetColorTexture(r,g,b,a); return t
end
function ns.Disc(frame, layer, r,g,b,a, inset)
    local t=frame:CreateTexture(nil,layer)
    if t.SetTexture then t:SetTexture(ns.WHITE) end
    if t.SetVertexColor then t:SetVertexColor(r,g,b,a) end
    if t.SetColorTexture then t:SetColorTexture(r,g,b,a) end
    inset = inset or 0
    if inset ~= 0 then
        t:SetPoint("TOPLEFT", -inset, inset)
        t:SetPoint("BOTTOMRIGHT", inset, -inset)
    else
        t:SetAllPoints()
    end
    ns.Circle(frame, t)
    return t
end
function ns.Label(frame,font,text)
    local l=frame:CreateFontString(nil,"OVERLAY",font or "GameFontNormal"); l:SetText(text or ""); return l
end
function ns.FitPanel(frame)
    frame:SetScale(1)
    frame:SetScale(math.min(1,(UIParent:GetWidth()-24)/frame:GetWidth(),(UIParent:GetHeight()-24)/frame:GetHeight()))
    frame:SetClampedToScreen(true)
end
function ns.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

function ns.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

function ns.SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if type(info) == "table" then return info.startTime, info.duration, info.isEnabled end
        return info
    end
    if GetSpellCooldown then return GetSpellCooldown(id) end
end

function ns.SpellUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(id) end
    if IsUsableSpell then
        local name = ns.SpellName(id)
        if name then return IsUsableSpell(name) end
    end
    return true, false
end

function ns.SpellInRange(id)
    if not UnitExists("target") then return nil end
    if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(id, "target") end
    if IsSpellInRange then
        local name = ns.SpellName(id)
        local result = name and IsSpellInRange(name, "target")
        if result == 1 then return true elseif result == 0 then return false end
    end
    return nil
end

function ns.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

function ns.ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if GetItemInfo then return (GetItemInfo(id)) end
end

function ns.ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
    if GetItemCount then return GetItemCount(id) end
    return 0
end

function ns.ItemSpell(id)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) end
    if GetItemSpell then return GetItemSpell(id) end
end

function ns.ItemCooldown(id)
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
    if GetItemCooldown then return GetItemCooldown(id) end
end

function ns.PickupEntry(entry)
    if entry.kind == "spell" then
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(entry.id) elseif PickupSpell then PickupSpell(entry.id) end
    elseif entry.kind == "item" then
        if C_Item and C_Item.PickupItem then C_Item.PickupItem(entry.id) elseif PickupItem then PickupItem(entry.id) end
    elseif entry.kind == "macro" then
        PickupMacro(entry.id)
    end
end

-- What the cursor holds as an assignable slot entry: a spell, item, or macro.
function ns.CursorEntry()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        if b == "pet" then
            ns.Print("Pet abilities cannot be placed in an action circle.")
            return nil
        end
        local spellID = c
        if not spellID and a and GetSpellBookItemInfo then
            local _, id = GetSpellBookItemInfo(a, b)
            spellID = id
        end
        if spellID then return { kind = "spell", id = spellID } end
    elseif kind == "item" and a then
        return { kind = "item", id = a }
    elseif kind == "macro" and a then
        local name = GetMacroInfo(a)
        if name then return { kind = "macro", id = name } end
    elseif kind then
        ns.Print("Only spells, usable items, and macros can be dropped here.")
    end
    return nil
end

ns.On("ADDON_LOADED",function(name)
    if name~="WolkaraMobile" then return end
    if type(WolkaraMobileDB)~="table" then WolkaraMobileDB={} end
    ns.db=WolkaraMobileDB
    if type(ns.db.buttons)~="table" then ns.db.buttons={} end
    ns.Each("Init")
end)
ns.On("PLAYER_LOGIN",function() if ns.db.hostSession~=ns.hostSession then
        ns.db.hostSession=ns.hostSession; ns.db.enabled=ns.hostEnabled==true
    end
    ns.SetEnabled(ns.db.enabled==true) end)
ns.On("PLAYER_REGEN_DISABLED",function()
    -- Do not change protected attributes here: combat has already begun.
    ns.Each("CombatStarts")
end)
ns.On("PLAYER_REGEN_ENABLED",function()
    if pending~=nil then ns.SetEnabled(pending) end
    if ns.pendingLayout then ns.pendingLayout=false; ns.Layout() end
    ns.Each("AfterCombat")
    if pendingEdit~=nil then ns.SetEditing(pendingEdit) end
    if pendingDone then ns.FinishEditing() end
end)
ns.On("DISPLAY_SIZE_CHANGED",function() ns.Layout() end)
ns.On("UI_SCALE_CHANGED",function() ns.Layout() end)
