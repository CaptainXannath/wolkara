-- Curved side action arcs, desktop bar sync, and interactive arc editor.
local _, ns = ...
local Abilities = ns.Register("Abilities", {})
ns.Abilities = Abilities

local DESIGN_HEIGHT = 720
local ICON_MAX = 60
local ICON_GAP = 7
local ROW_GAP = 9
local ARC_MARGIN = 14
local HANDLE_HEIGHT = 34
local SIDES = { "left", "right" }
local DESKTOP_BARS = {
    "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarLeft", "MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7",
    "MicroMenuContainer", "MicroMenu", "BagsBar",
}

local eventsFrame, editShield, tools
local selectionLabel, assignBtn, removeBtn, setCaption, prevSetBtn, nextSetBtn, addSetBtn, delSetBtn
local switcher
local actionPages, editGroups = {}, {}
local draft, selectedPreview, dragPreview, movingGroup
local barAlpha, barMouse, barHooks = {}, {}, {}
local trackerHooked, refreshQueued, pendingSync = false, false, false

local function ValidEntry(e)
    if type(e) ~= "table" then return false end
    local k = e.kind
    return (k == "spell" or k == "item" or k == "macro" or k == "macrotext" or k == "action" or k == "mount" or k == "battlepet") and e.id ~= nil
        or (k == "desktop" and type(e.key) == "string")
end

local function CopyEntry(e)
    if not ValidEntry(e) then return {} end
    return { kind = e.kind, id = e.id, key = e.key, spell = e.spell, name = e.name, icon = e.icon }
end

local function CopyPositions(src)
    local out = {}
    if type(src) ~= "table" then return out end
    for _, side in ipairs(SIDES) do
        local p = src[side]
        if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number"
            and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1 then
            out[side] = { x = p.x, y = p.y }
        end
    end
    return out
end

local function CopyPage(page)
    local out = { left = {}, right = {}, positions = CopyPositions(type(page) == "table" and page.positions) }
    if type(page) ~= "table" then return out end
    local remaining = ns.MAX_BUTTONS
    for _, side in ipairs(SIDES) do
        local list = type(page[side]) == "table" and page[side] or {}
        for _, slot in ipairs(list) do
            if remaining <= 0 then break end
            if type(slot) == "table" then
                out[side][#out[side] + 1] = CopyEntry(slot)
                remaining = remaining - 1
            end
        end
    end
    return out
end

local function CopyPages(pages)
    local out = {}
    for _, page in ipairs(pages or {}) do
        out[#out + 1] = CopyPage(page)
    end
    if #out == 0 then out[1] = CopyPage() end
    return out
end

local function TotalSlotsInPage(page)
    return #page.left + #page.right
end

local function DefaultPageFromGame()
    local ordered, records = ns.DesktopActionList()
    ns.desktopRecords = records
    if #ordered > 0 then
        local split = ns.SplitDesktopToSides(ordered, records)
        return { left = split.left, right = split.right, positions = {} }, true
    end
    local page = { left = {}, right = {}, positions = {} }
    for _ = 1, 8 do page.left[#page.left + 1] = {} end
    for _ = 1, 6 do page.right[#page.right + 1] = {} end
    return page, false
end

local function MigrateLegacyButtons()
    if type(ns.db.buttons) ~= "table" or #ns.db.buttons == 0 then return nil end
    local page = { left = {}, right = {}, positions = {} }
    local hasEntries = false
    for i, b in ipairs(ns.db.buttons) do
        if type(b) == "table" and ValidEntry(b.entry) then
            hasEntries = true
            local side = (type(b.x) == "number" and b.x >= 0.5) and page.right or (i > 12 and page.right or page.left)
            side[#side + 1] = CopyEntry(b.entry)
        end
    end
    if hasEntries then return page end
    return nil
end

local function EnsureDBPages()
    if type(ns.db.pages) ~= "table" or #ns.db.pages == 0 then
        local migrated = MigrateLegacyButtons()
        if migrated then
            ns.db.pages = { migrated }
            ns.db.customized = true
        else
            local page, fromDesktop = DefaultPageFromGame()
            ns.db.pages = { page }
            ns.db.customized = not fromDesktop and ns.db.seeded or false
        end
        ns.db.seeded = true
    else
        ns.db.pages = CopyPages(ns.db.pages)
    end
    if type(ns.db.activePage) ~= "number" or ns.db.activePage < 1 or ns.db.activePage > #ns.db.pages then
        ns.db.activePage = 1
    end
end

local function SyncDesktopIfUnmodified()
    if ns.db.customized or ns.editing then return end
    local ordered, records = ns.DesktopActionList()
    ns.desktopRecords = records
    if #ordered > 0 then
        local split = ns.SplitDesktopToSides(ordered, records)
        local pos = ns.db.pages[1] and CopyPositions(ns.db.pages[1].positions) or {}
        ns.db.pages[1] = { left = split.left, right = split.right, positions = pos }
    end
end

local function ArcGeometry(count, viewport, mirrored)
    local maxWidth = math.max(110, viewport * 0.307)
    local maxHeight = DESIGN_HEIGHT * 0.325
    local maxCurve = math.min(52, maxWidth * 0.12)
    local width, height = math.min(205, maxWidth), 56
    local points = {}
    if count == 0 then return width, height, points end

    local columns, rows, diameter = 1, count, 0
    for cand = 1, count do
        local bands = math.ceil(count / cand)
        local size = math.min(
            ICON_MAX,
            (maxWidth + ICON_GAP) / (cand + 0.10) - ICON_GAP,
            (maxHeight - maxCurve + ROW_GAP) / bands - ROW_GAP
        )
        if size > diameter or (size == diameter and bands < rows) then
            columns, rows, diameter = cand, bands, size
        end
    end
    if diameter <= 0 then return width, height, points end

    local stepX, stepY = diameter + ICON_GAP, diameter + ROW_GAP
    width = (columns + 0.10) * stepX - ICON_GAP
    local curve = math.min(maxCurve, (width - diameter) * 0.13)
    height = rows * stepY - ROW_GAP + curve
    for row = 1, rows do
        local perRow = math.ceil((count - #points) / (rows - row + 1))
        local inset = (columns - perRow) * stepX + (row % 2 == 1 and 0.10 * stepX or 0)
        local rowScale = math.max(0.84, 1 - 0.065 * (row - 1))
        for col = 1, perRow do
            local x = diameter / 2 + inset + (col - 1) * stepX
            local ratio = (x - diameter / 2) / math.max(1, width - diameter)
            local y = diameter / 2 + (row - 1) * stepY + curve * (1 - ((ratio - 0.30) / 0.70) ^ 2)
            points[#points + 1] = { x = mirrored and width - x or x, y = y, size = diameter * rowScale }
        end
    end
    return width, height, points
end

local function ArcTravel(width, height, viewport)
    return math.max(0, viewport - width - 2 * ARC_MARGIN),
        math.max(0, DESIGN_HEIGHT - height - HANDLE_HEIGHT - 2 * ARC_MARGIN)
end

local function PlaceArcFrame(frame, side, scale, width, height, viewport, pos)
    frame:SetScale(scale)
    frame:SetSize(width, height)
    frame:ClearAllPoints()
    local x = math.max(ARC_MARGIN, viewport * 0.027)
    if side == "right" then x = viewport - x - width end
    local y = DESIGN_HEIGHT * 0.230
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        local tx, ty = ArcTravel(width, height, viewport)
        x = ARC_MARGIN + ns.Clamp(pos.x, 0, 1) * tx
        y = ARC_MARGIN + ns.Clamp(pos.y, 0, 1) * ty
    end
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function MuteBarTree(frame)
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local clicks = frame.IsMouseClickEnabled and frame:IsMouseClickEnabled()
    local motion = frame.IsMouseMotionEnabled and frame:IsMouseMotionEnabled()
    if clicks or motion then
        local st = barMouse[frame] or {}
        st.clicks = st.clicks or clicks
        st.motion = st.motion or motion
        barMouse[frame] = st
        if clicks and frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
        if motion and frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(false) end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do MuteBarTree(child) end
    end
end

local function RestoreDesktopBars()
    if InCombatLockdown() then return end
    for bar, alpha in pairs(barAlpha) do
        barAlpha[bar] = nil
        if bar.SetAlpha then bar:SetAlpha(alpha) end
    end
    for frame, st in pairs(barMouse) do
        if st.clicks and frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(true) end
        if st.motion and frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
    end
    barMouse = {}
end

local function UpdateDesktopBars(hide)
    if InCombatLockdown() then return end
    local editActive = EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive()
    if not hide or editActive then
        RestoreDesktopBars()
        return
    end
    for _, name in ipairs(DESKTOP_BARS) do
        local bar = _G[name]
        if bar and not (bar.IsForbidden and bar:IsForbidden()) then
            if not barHooks[bar] and type(hooksecurefunc) == "function" then
                hooksecurefunc(bar, "SetAlpha", function(f, a)
                    if barAlpha[f] and not ns.IsSecret(a) and a ~= 0 then f:SetAlpha(0) end
                end)
                if bar.HookScript then
                    bar:HookScript("OnShow", function(f)
                        if barAlpha[f] and not InCombatLockdown() then MuteBarTree(f) end
                    end)
                end
                barHooks[bar] = true
            end
            if barAlpha[bar] == nil then barAlpha[bar] = bar.GetAlpha and bar:GetAlpha() or 1 end
            if bar.SetAlpha then bar:SetAlpha(0) end
            MuteBarTree(bar)
        end
    end
end

local function LimitTrackerHeight(tracker)
    if not ns.enabled or (InCombatLockdown() and tracker.IsProtected and tracker:IsProtected()) then return end
    local maxH = UIParent:GetHeight() * 0.137
    if maxH > 0 and tracker:GetHeight() > maxH then tracker:SetHeight(maxH) end
end

local function EnsureSwitcher()
    if switcher then return switcher end
    switcher = CreateFrame("Button", "WolkaraMobileCycleSet", UIParent, "UIPanelButtonTemplate,SecureHandlerClickTemplate")
    switcher:SetFrameStrata("HIGH")
    switcher:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 20)
    switcher:SetSize(128, 38)
    switcher:RegisterForClicks("LeftButtonUp")
    switcher:SetAttribute("_onclick", [[
        if down or button ~= "LeftButton" then return end
        local count = self:GetAttribute("pageCount")
        if not count or count < 2 then return end
        local current = self:GetAttribute("page") or 1
        local nextPage = current % count + 1
        local curF = self:GetFrameRef("page" .. current)
        local nxtF = self:GetFrameRef("page" .. nextPage)
        if curF then curF:Hide() end
        if nxtF then nxtF:Show() end
        self:SetAttribute("page", nextPage)
    ]])
    switcher:HookScript("OnAttributeChanged", function(_, attr, val)
        if attr ~= "page" or not ns.db or not ns.db.pages or not val then return end
        ns.db.activePage = val
        switcher:SetText(string.format("Set %d / %d", val, #ns.db.pages))
        Abilities:Refresh()
    end)
    switcher:Hide()
    return switcher
end

local function EnsureActionPage(index)
    if actionPages[index] then return actionPages[index] end
    local container = CreateFrame("Frame", "WolkaraMobilePage" .. index, UIParent)
    container:Hide()
    local page = { frame = container, groups = {} }
    for _, side in ipairs(SIDES) do
        local prefix = "WolkaraMobile" .. (side == "left" and "Left" or "Right") .. (index > 1 and ("Set" .. index) or "")
        local panel = CreateFrame("Frame", prefix, container)
        panel:SetClampedToScreen(true)
        page.groups[side] = { panel = panel, prefix = prefix, buttons = {} }
    end
    actionPages[index] = page
    EnsureSwitcher():SetFrameRef("page" .. index, container)
    return page
end

local function EnsureLiveButton(pageIndex, side, slotIndex)
    local group = EnsureActionPage(pageIndex).groups[side]
    local b = group.buttons[slotIndex]
    if b then return b end
    local name = group.prefix .. "Button" .. slotIndex
    b = ns.CreateActionButton(name, group.panel, 44,
        function()
            local p = ns.db and ns.db.pages and ns.db.pages[pageIndex]
            local e = p and p[side] and p[side][slotIndex]
            return ValidEntry(e) and e or nil
        end,
        function(entry)
            if not (ns.db and ns.db.pages and ns.db.pages[pageIndex]) then return end
            ns.db.pages[pageIndex][side][slotIndex] = CopyEntry(entry)
            ns.db.customized = true
        end)
    b:SetFrameStrata("LOW")
    b.mobilePage, b.mobileSide, b.mobileSlot = pageIndex, side, slotIndex
    b.OnAssigned = function() ns.MarkChanged() end
    group.buttons[slotIndex] = b
    if ns.WrapAbilityButton then ns.WrapAbilityButton(b) end
    return b
end

local function LayoutPage(pageData, groupMap, editing, scale, viewport)
    for _, side in ipairs(SIDES) do
        local group = groupMap[side]
        local list = pageData[side] or {}
        local arcW, arcH, points = ArcGeometry(#list, viewport, side == "right")
        local parent = editing and group.editor or group.panel
        local btns = editing and group.previews or group.buttons
        PlaceArcFrame(parent, side, scale, arcW, arcH, viewport, pageData.positions and pageData.positions[side])
        for idx, pt in ipairs(points) do
            local btn = btns[idx]
            if btn then
                btn:SetSize(pt.size, pt.size)
                btn:ClearAllPoints()
                btn:SetPoint("CENTER", parent, "BOTTOMLEFT", pt.x, pt.y)
            end
        end
    end
end

local function LayoutAll()
    if not ns.enabled or movingGroup then return end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if w <= 0 or h <= 0 then return end
    local scale = h / DESIGN_HEIGHT
    local viewport = w / scale
    if ns.editing and draft then
        LayoutPage(draft.pages[draft.index], editGroups, true, scale, viewport)
    elseif not InCombatLockdown() and ns.db and ns.db.pages then
        for idx, pageData in ipairs(ns.db.pages) do
            local pageObj = actionPages[idx]
            if pageObj then LayoutPage(pageData, pageObj.groups, false, scale, viewport) end
        end
        if switcher then switcher:SetScale(scale) end
    end
end

local function SyncLiveButtons()
    if InCombatLockdown() then pendingSync = true; return end
    pendingSync = false
    SyncDesktopIfUnmodified()
    if not ns.db or not ns.db.pages then return end
    local active = math.max(1, math.min(ns.db.activePage or 1, #ns.db.pages))
    ns.db.activePage = active
    for pageIdx, pageData in ipairs(ns.db.pages) do
        local pageObj = EnsureActionPage(pageIdx)
        for _, side in ipairs(SIDES) do
            local list = pageData[side] or {}
            local group = pageObj.groups[side]
            for slotIdx = 1, #list do
                local b = EnsureLiveButton(pageIdx, side, slotIdx)
                ns.ApplyButton(b, ns.desktopRecords)
                ns.RefreshButton(b)
                b:SetShown(ns.enabled and not ns.editing)
            end
            for slotIdx = #list + 1, #group.buttons do
                local b = group.buttons[slotIdx]
                ns.ApplyButton(b, ns.desktopRecords)
                b:Hide()
            end
            group.panel:SetShown(ns.enabled and #list > 0)
        end
        pageObj.frame:SetShown(ns.enabled and not ns.editing and pageIdx == active)
    end
    for idx = #ns.db.pages + 1, #actionPages do
        actionPages[idx].frame:Hide()
    end
    local sw = EnsureSwitcher()
    sw:SetAttribute("pageCount", #ns.db.pages)
    sw:SetAttribute("page", active)
    sw:SetText(string.format("Set %d / %d", active, #ns.db.pages))
    sw:SetShown(ns.enabled and not ns.editing and #ns.db.pages > 1)
    LayoutAll()
end

local UpdateEditorUI

local function SwapDraftSlots(first, second)
    if not draft or not first or not second then return end
    local page = draft.pages[draft.index]
    local a, b = page[first.mobileSide], page[second.mobileSide]
    a[first.mobileIndex], b[second.mobileIndex] = b[second.mobileIndex], a[first.mobileIndex]
    draft.customized = true
end

local function EnsurePreviewButton(group, index)
    if group.previews[index] then return group.previews[index] end
    local b = CreateFrame("Button", nil, group.editor)
    b.mobileSide, b.mobileIndex = group.side, index
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b.ring = ns.Disc(b, "BACKGROUND", 0.65, 0.49, 0.28, 0.9, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    ns.Circle(b, b.icon)
    b.plus = ns.Label(b, "GameFontNormalHuge", "+")
    b.plus:SetPoint("CENTER")
    b.plus:SetTextColor(0.85, 0.78, 0.60)
    b:SetScript("OnClick", function(self)
        if not draft or dragPreview or ns.Picker:IsOpen() then return end
        if selectedPreview and selectedPreview ~= self then
            SwapDraftSlots(selectedPreview, self)
            selectedPreview = nil
        else
            selectedPreview = (selectedPreview ~= self) and self or nil
        end
        UpdateEditorUI()
    end)
    b:SetScript("OnDragStart", function(self)
        if not draft or ns.Picker:IsOpen() then return end
        selectedPreview, dragPreview = nil, self
        UpdateEditorUI()
    end)
    b:SetScript("OnDragStop", function(self)
        if not draft or dragPreview ~= self then return end
        local target
        local page = draft.pages[draft.index]
        for _, side in ipairs(SIDES) do
            for idx = 1, #page[side] do
                local other = editGroups[side].previews[idx]
                if other and other ~= self and other.IsMouseOver and other:IsMouseOver() then
                    target = other
                    break
                end
            end
            if target then break end
        end
        if target then SwapDraftSlots(self, target) end
        dragPreview = nil
        UpdateEditorUI()
    end)
    group.previews[index] = b
    return b
end

local function OpenPickerForDraftSlot(side, slotIndex)
    if not draft or ns.Picker:IsOpen() then return end
    local page = draft.pages[draft.index]
    ns.Picker:OpenForSlot(function(binding)
        if not draft or draft.pages[draft.index] ~= page then return end
        page[side][slotIndex] = CopyEntry(binding)
        draft.customized = true
        selectedPreview = nil
        UpdateEditorUI()
    end, nil, page[side][slotIndex] and ValidEntry(page[side][slotIndex]) and "Replace slot" or "Add ability")
end

UpdateEditorUI = function()
    if not draft or not editShield then return end
    local page = draft.pages[draft.index]
    local canAdd = TotalSlotsInPage(page) < ns.MAX_BUTTONS
    for _, side in ipairs(SIDES) do
        local group, list = editGroups[side], page[side]
        for idx, slot in ipairs(list) do
            local btn = EnsurePreviewButton(group, idx)
            if ValidEntry(slot) then
                btn.icon:SetTexture(ns.EntryIcon(slot, ns.desktopRecords) or ns.QUESTION)
                btn.icon:Show()
                btn.plus:Hide()
            else
                btn.icon:Hide()
                btn.plus:Show()
            end
            if btn == selectedPreview or btn == dragPreview then
                btn.ring:SetVertexColor(1, 0.83, 0.45, 1)
            else
                btn.ring:SetVertexColor(0.68, 0.51, 0.28, 0.9)
            end
            btn:Show()
        end
        for idx = #list + 1, #group.previews do
            group.previews[idx]:Hide()
        end
        if group.add.SetEnabled then group.add:SetEnabled(canAdd) end
    end
    local sel = selectedPreview and page[selectedPreview.mobileSide][selectedPreview.mobileIndex]
    if sel then
        selectionLabel:SetText(ValidEntry(sel) and (ns.EntryName(sel, ns.desktopRecords) or "Slot") or "Empty slot")
        assignBtn:SetEnabled(true)
        removeBtn:SetEnabled(true)
    else
        selectionLabel:SetText("Tap a circle or + to add")
        assignBtn:SetEnabled(false)
        removeBtn:SetEnabled(false)
    end
    setCaption:SetText(string.format("Set %d / %d", draft.index, #draft.pages))
    prevSetBtn:SetEnabled(draft.index > 1)
    nextSetBtn:SetEnabled(draft.index < #draft.pages)
    delSetBtn:SetEnabled(draft.index > 1)
    local scale = UIParent:GetHeight() / DESIGN_HEIGHT
    if scale > 0 then tools:SetScale(scale) end
    LayoutAll()
end

local function NormalizedCoord(value, travel)
    if travel <= 0 then return 0.5 end
    return ns.Clamp((value - ARC_MARGIN) / travel, 0, 1)
end

local function BuildEditorUI()
    editShield = CreateFrame("Frame", "WolkaraMobileArcEditor", UIParent)
    editShield:SetFrameStrata("DIALOG")
    editShield:SetAllPoints(UIParent)
    editShield:EnableMouse(true)
    editShield:Hide()
    local shade = editShield:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.07, 0.05, 0.03, 0.32)

    tools = CreateFrame("Frame", "WolkaraMobileArcTools", editShield)
    tools:SetPoint("TOP", UIParent, "TOP", 0, -68)
    tools:SetSize(284, 144)

    selectionLabel = tools:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    selectionLabel:SetPoint("TOP", 0, 2)
    selectionLabel:SetWidth(280)

    assignBtn = ns.UIButton(tools, "Assign", 130, 36, function()
        if selectedPreview then OpenPickerForDraftSlot(selectedPreview.mobileSide, selectedPreview.mobileIndex) end
    end)
    assignBtn:SetPoint("TOPLEFT", 4, -26)

    removeBtn = ns.UIButton(tools, "Remove", 130, 36, function()
        if not draft or not selectedPreview or ns.Picker:IsOpen() then return end
        local page = draft.pages[draft.index]
        table.remove(page[selectedPreview.mobileSide], selectedPreview.mobileIndex)
        draft.customized = true
        selectedPreview = nil
        UpdateEditorUI()
    end)
    removeBtn:SetPoint("TOPRIGHT", -4, -26)

    setCaption = tools:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    setCaption:SetPoint("TOP", 0, -78)
    prevSetBtn = ns.UIButton(tools, "<", 40, 32, function()
        if draft and draft.index > 1 then draft.index = draft.index - 1; selectedPreview = nil; UpdateEditorUI() end
    end)
    prevSetBtn:SetPoint("TOPLEFT", 4, -68)
    nextSetBtn = ns.UIButton(tools, ">", 40, 32, function()
        if draft and draft.index < #draft.pages then draft.index = draft.index + 1; selectedPreview = nil; UpdateEditorUI() end
    end)
    nextSetBtn:SetPoint("TOPRIGHT", -4, -68)
    addSetBtn = ns.UIButton(tools, "Add set", 130, 32, function()
        if not draft then return end
        local cur = draft.pages[draft.index]
        draft.pages[#draft.pages + 1] = { left = {}, right = {}, positions = CopyPositions(cur.positions) }
        draft.index = #draft.pages
        selectedPreview = nil
        UpdateEditorUI()
    end)
    addSetBtn:SetPoint("BOTTOMLEFT", 4, 0)
    delSetBtn = ns.UIButton(tools, "Remove set", 130, 32, function()
        if not draft or draft.index <= 1 then return end
        table.remove(draft.pages, draft.index)
        draft.index = math.min(draft.index, #draft.pages)
        selectedPreview = nil
        UpdateEditorUI()
    end)
    delSetBtn:SetPoint("BOTTOMRIGHT", -4, 0)

    for _, side in ipairs(SIDES) do
        local ed = CreateFrame("Frame", "WolkaraMobileArcGroup" .. side, editShield)
        ed:SetMovable(true)
        ed:SetClampedToScreen(true)
        local g = { side = side, editor = ed, previews = {} }

        local move = CreateFrame("Button", "WolkaraMobileMove" .. side, ed, "UIPanelButtonTemplate")
        move:SetPoint("BOTTOM", ed, "TOP", -22, 5)
        move:SetSize(148, HANDLE_HEIGHT)
        move:SetClampedToScreen(true)
        move:SetText("Move arc")
        move:RegisterForDrag("LeftButton")
        move:SetScript("OnDragStart", function()
            if not draft or ns.Picker:IsOpen() then return end
            movingGroup = g
            ed:StartMoving()
        end)
        move:SetScript("OnDragStop", function()
            if not draft or movingGroup ~= g then return end
            ed:StopMovingOrSizing()
            if ed.SetUserPlaced then ed:SetUserPlaced(false) end
            movingGroup = nil
            local uiScale = UIParent:GetEffectiveScale()
            local sc = uiScale > 0 and (ed:GetEffectiveScale() / uiScale) or 1
            local tx, ty = ArcTravel(ed:GetWidth(), ed:GetHeight(), UIParent:GetWidth() / sc)
            local left = ed.GetLeft and ed:GetLeft()
            local bottom = ed.GetBottom and ed:GetBottom()
            if left and bottom then
                local uiLeft = (UIParent.GetLeft and UIParent:GetLeft() or 0) / sc
                local uiBot = (UIParent.GetBottom and UIParent:GetBottom() or 0) / sc
                draft.pages[draft.index].positions[side] = {
                    x = NormalizedCoord(left - uiLeft, tx),
                    y = NormalizedCoord(bottom - uiBot, ty),
                }
            end
            LayoutAll()
        end)
        g.move = move

        local add = CreateFrame("Button", "WolkaraMobileAdd" .. side, ed, "UIPanelButtonTemplate")
        add:SetPoint("LEFT", move, "RIGHT", 4, 0)
        add:SetSize(40, HANDLE_HEIGHT)
        add:SetClampedToScreen(true)
        add:SetText("+")
        add:SetScript("OnClick", function()
            if not draft then return end
            local page = draft.pages[draft.index]
            if TotalSlotsInPage(page) >= ns.MAX_BUTTONS then return end
            OpenPickerForDraftSlot(side, #page[side] + 1)
        end)
        g.add = add
        editGroups[side] = g
    end
end

function Abilities:Init()
    EnsureDBPages()
    BuildEditorUI()
    eventsFrame = CreateFrame("Frame")
    local elapsed = 0
    eventsFrame:SetScript("OnUpdate", function(_, dt)
        if not ns.enabled or ns.editing or not ns.db or not ns.db.pages then return end
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        local idx = ns.db.activePage or 1
        local p = actionPages[idx]
        if not p then return end
        for _, side in ipairs(SIDES) do
            for _, btn in ipairs(p.groups[side].buttons) do
                if btn:IsShown() then ns.UpdateState(btn) end
            end
        end
    end)
end

function Abilities:Layout()
    local tracker = _G.ObjectiveTrackerFrame
    if tracker and tracker.UpdateHeight and not trackerHooked and type(hooksecurefunc) == "function" then
        hooksecurefunc(tracker, "UpdateHeight", LimitTrackerHeight)
        trackerHooked = true
    end
    UpdateDesktopBars(ns.enabled)
    SyncLiveButtons()
end

function Abilities:Refresh()
    if not ns.enabled or not ns.db or not ns.db.pages then return end
    local idx = ns.db.activePage or 1
    local p = actionPages[idx]
    if not p then return end
    for _, side in ipairs(SIDES) do
        for _, btn in ipairs(p.groups[side].buttons) do
            if btn:IsShown() then ns.RefreshButton(btn) end
        end
    end
end

function Abilities:SetEditing(on)
    if on then
        if not draft then
            draft = {
                pages = CopyPages(ns.db.pages),
                index = ns.db.activePage or 1,
                customized = ns.db.customized == true,
            }
            selectedPreview, dragPreview, movingGroup = nil, nil, nil
        end
        for _, p in ipairs(actionPages) do
            for _, side in ipairs(SIDES) do
                for _, btn in ipairs(p.groups[side].buttons) do btn:Hide() end
            end
            p.frame:Hide()
        end
        if switcher then switcher:Hide() end
        editShield:Show()
        UpdateEditorUI()
    else
        if movingGroup then
            movingGroup.editor:StopMovingOrSizing()
            movingGroup = nil
        end
        ns.Picker:Close()
        draft, selectedPreview, dragPreview = nil, nil, nil
        if editShield then editShield:Hide() end
        SyncLiveButtons()
    end
end

function Abilities:SaveEditing()
    if not draft then return end
    ns.db.pages = CopyPages(draft.pages)
    ns.db.activePage = math.max(1, math.min(draft.index, #ns.db.pages))
    ns.db.customized = draft.customized
end

function Abilities:CancelEditing()
    draft, selectedPreview, dragPreview, movingGroup = nil, nil, nil, nil
end

function Abilities:ResetDefaults()
    local fresh, fromDesktop = DefaultPageFromGame()
    if draft then
        draft.pages[draft.index] = CopyPage(fresh)
        if draft.index == 1 then draft.customized = not fromDesktop end
        selectedPreview, dragPreview = nil, nil
        UpdateEditorUI()
    elseif ns.db and ns.db.pages then
        ns.db.pages = { CopyPage(fresh) }
        ns.db.activePage = 1
        ns.db.customized = not fromDesktop
        SyncLiveButtons()
    end
end

function Abilities:Disable()
    if editShield then editShield:Hide() end
    ns.Picker:Close()
    draft, selectedPreview, dragPreview, movingGroup = nil, nil, nil, nil
    for _, p in ipairs(actionPages) do
        for _, side in ipairs(SIDES) do
            for _, btn in ipairs(p.groups[side].buttons) do btn:Hide() end
            p.groups[side].panel:Hide()
        end
        p.frame:Hide()
    end
    if switcher then switcher:Hide() end
    RestoreDesktopBars()
end

function Abilities:CombatStarts()
    if editShield then editShield:Hide() end
end

function Abilities:AfterCombat()
    if ns.enabled then
        UpdateDesktopBars(true)
        if pendingSync then SyncLiveButtons() else LayoutAll() end
    else
        RestoreDesktopBars()
    end
end

local function QueueLiveSync()
    if not ns.enabled or refreshQueued then return end
    refreshQueued = true
    local after = C_Timer and C_Timer.After
    if after then
        after(0, function()
            refreshQueued = false
            if ns.enabled then SyncLiveButtons() end
        end)
    else
        refreshQueued = false
        SyncLiveButtons()
    end
end

ns.On("SPELL_UPDATE_COOLDOWN", function() Abilities:Refresh() end)
ns.On("ACTIONBAR_UPDATE_COOLDOWN", function() Abilities:Refresh() end)
ns.On("ACTIONBAR_UPDATE_USABLE", function() Abilities:Refresh() end)
ns.On("BAG_UPDATE", function() Abilities:Refresh() end)
ns.On("SPELLS_CHANGED", QueueLiveSync)
ns.On("ACTIONBAR_SLOT_CHANGED", QueueLiveSync)
ns.On("ACTIONBAR_PAGE_CHANGED", QueueLiveSync)
