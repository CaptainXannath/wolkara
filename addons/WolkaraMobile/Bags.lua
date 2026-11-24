-- Touch-only bag gestures. Existing container buttons and textures remain the game's.
local _,ns=...
local Bags=ns.Register("Bags",{})
ns.Bags=Bags
local watched, roots={},{}
local panel, active, use
Bags.CLICK=[=[
    if not control:GetAttribute("enabled") then return end
    local gesture=control:GetAttribute("gesture")
    if not down then control:SetAttribute("gesture",nil) end
    if gesture=="drag" then return false end
    if gesture=="hold" then
        if not down then control:CallMethod("ShowBagOptions",self:GetName()) end
        return false
    end
    if gesture=="tap" then
        if control:GetAttribute("moving") then
            if not down then control:SetAttribute("moving",nil) end
            return "LeftButton"
        end
        return "RightButton"
    end
]=]
local function Slot(button)
    local root=roots[button]; if not root then return end
    local bag=button.GetBagID and button:GetBagID() or root:GetID()
    local slot=button.GetSlotID and button:GetSlotID() or button:GetID()
    if type(bag)=="number" and bag>=0 and bag<=4 and type(slot)=="number" and slot>0 then return bag,slot end
end
function Bags:Close() if panel and not InCombatLockdown() then panel:Hide() end; active=nil end
local function Show(name)
    if not ns.enabled or InCombatLockdown() then return end
    local b=_G[name]; if not b then return end
    local bag,slot=Slot(b)
    if not bag then return end
    active={button=b,bag=bag,slot=slot}
    use:SetAttribute("type","item"); use:SetAttribute("item",bag.." "..slot)
    ns.FitPanel(panel); panel:Show()
    if GameTooltip then
        GameTooltip:SetOwner(panel,"ANCHOR_RIGHT")
        if GameTooltip.SetBagItem then GameTooltip:SetBagItem(bag,slot) end
    end
end
function Bags:Watch()
    if not ns.bridge or InCombatLockdown() then return end
    ns.bridge.ShowBagOptions=function(_,name) Show(name) end
    local function Walk(frame,root,depth)
        if depth>3 then return end
        for _,b in ipairs({frame:GetChildren()}) do
            local name=b.GetName and b:GetName()
            local kind=b.GetObjectType and b:GetObjectType()
            if name and (kind=="Button" or kind=="ItemButton") and
                (b.icon or b.Icon or b.iconTexture or _G[name.."IconTexture"]) then
                roots[b]=root
                if Slot(b) and not watched[b] then
                    SecureHandlerWrapScript(b,"OnClick",ns.bridge,Bags.CLICK)
                    watched[b]=true
                end
            elseif b.GetChildren then Walk(b,root,depth+1) end
        end
    end
    for i=1,(NUM_CONTAINER_FRAMES or 13) do
        local f=_G["ContainerFrame"..i]
        if f then Walk(f,f,0); if ns.Windows then ns.Windows.Watch(f) end end
    end
    local combined=_G.ContainerFrameCombinedBags
    if combined then Walk(combined,combined,0); if ns.Windows then ns.Windows.Watch(combined) end end
end
function Bags:Init()
    panel=CreateFrame("Frame","WolkaraMobileBagOptions",UIParent,"UIPanelDialogTemplate,SecureHandlerStateTemplate")
    panel:SetSize(260,258); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true); panel:Hide()
    panel:SetAttribute("_onstate-combat", "if newstate == 'yes' then self:Hide() end")
    RegisterStateDriver(panel,"combat","[combat] yes; no")
    local title=ns.Label(panel,"GameFontNormalLarge","Item options"); title:SetPoint("TOP",0,-18)
    use=CreateFrame("Button","WolkaraMobileBagUse",panel,"SecureActionButtonTemplate,UIPanelButtonTemplate")
    use:SetSize(210,40); use:SetPoint("TOP",0,-46); use:SetText("Use / Equip")
    use:RegisterForClicks("AnyUp","AnyDown"); use:SetAttribute("useOnKeyDown",false)
    use:SetScript("PostClick",function(_,_,down) if not down and not InCombatLockdown() then Bags:Close() end end)
    local move=ns.UIButton(panel,"Move item",210,40,function()
        if not active or InCombatLockdown() then return end
        local pickup=C_Container and C_Container.PickupContainerItem or PickupContainerItem
        if pickup then
            pickup(active.bag,active.slot); ns.bridge:SetAttribute("moving",true)
        end
        Bags:Close()
    end); move:SetPoint("TOP",0,-92)
    local link=ns.UIButton(panel,"Link in chat",210,40,function()
        if not active then return end
        local get=C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
        local text=get and get(active.bag,active.slot)
        if text and ChatEdit_InsertLink then ChatEdit_InsertLink(text) end
        Bags:Close()
    end); link:SetPoint("TOP",0,-138)
    local close=ns.UIButton(panel,CANCEL or "Cancel",210,40,function() Bags:Close() end)
    close:SetPoint("TOP",0,-184)
    panel:SetScript("OnHide",function() if GameTooltip then GameTooltip:Hide() end end)
    if type(UpdateContainerFrameAnchors)=="function" then
        hooksecurefunc("UpdateContainerFrameAnchors",function() Bags:Watch() end)
    end
end
function Bags:Layout() self:Watch() end
function Bags:Disable()
    self:Close()
    if ns.bridge then ns.bridge:SetAttribute("moving",nil) end
end
function Bags:CombatStarts()
    active=nil
    if GameTooltip then GameTooltip:Hide() end
end
function Bags:AfterCombat() self:Watch() end
ns.On("BAG_UPDATE",function() Bags:Close(); Bags:Watch() end)
ns.On("ADDON_LOADED",function() if ns.db then Bags:Watch() end end)

ns.On("CURSOR_CHANGED",function()
    if ns.bridge and not InCombatLockdown() and not GetCursorInfo() then ns.bridge:SetAttribute("moving",nil) end
end)
