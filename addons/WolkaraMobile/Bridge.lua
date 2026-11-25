-- Explicit host UI gestures -> ordinary addon bindings; no game memory or injected Lua.
local _,ns=...
local Bridge=ns.Register("Host controls",{})
local keys={"ALT-CTRL-SHIFT-F6","ALT-CTRL-SHIFT-F7","ALT-CTRL-F6","ALT-CTRL-F7",
    "CTRL-SHIFT-F6","CTRL-SHIFT-F7","ALT-SHIFT-F6","ALT-SHIFT-F7"}
function ns.WrapAbilityButton(action)
    if not action or action.bridgeWrapped or not ns.bridge or InCombatLockdown() then return end
    action.bridgeWrapped=true
    SecureHandlerWrapScript(action,"OnClick",ns.bridge,[=[
        local gesture=control:GetAttribute("gesture")
        if not down then control:SetAttribute("gesture",nil) end
        if control:GetAttribute("enabled") and (gesture=="drag" or gesture=="hold") then return false end
    ]=])
end
function Bridge:Init()
    local bridge=CreateFrame("Frame","WolkaraMobileBridge",UIParent,"SecureHandlerBaseTemplate")
    ns.bridge=bridge
    function bridge:Command(command)
        ns.hostCommands=(ns.hostCommands or 0)+1
        if command=="on" then
            ns.SetEnabled(true)
            if not InCombatLockdown() then ns.Print("Round spell buttons enabled.") end
        elseif command=="off" then
            ns.SetEnabled(false)
            if not InCombatLockdown() then ns.Print("Round spell buttons disabled.") end
        elseif command=="edit" then ns.SetEditing(true)
        elseif command=="done" then ns.FinishEditing() end
    end
    local values={"on","off","edit","done","tap","hold","clear","drag"}
    for index,value in ipairs(values) do
        local b=CreateFrame("Button","WolkaraMobileCommand"..index,UIParent,"SecureHandlerClickTemplate")
        b:RegisterForClicks("AnyUp"); b:SetFrameRef("bridge",bridge); b:SetAttribute("command",value)
        b:SetAttribute("_onclick",[=[
            local bridge=self:GetFrameRef("bridge")
            local command=self:GetAttribute("command")
            if command=="tap" or command=="hold" or command=="drag" then
                bridge:SetAttribute("gesture",command)
            elseif command=="clear" then bridge:SetAttribute("gesture",nil)
            else bridge:CallMethod("Command",command) end
        ]=])
        SetOverrideBindingClick(bridge,false,keys[index],b:GetName())
    end
    for i=1,ns.MAX_BUTTONS do
        ns.WrapAbilityButton(_G["WolkaraMobileAbility"..i])
    end
    if ns.Bags then ns.Bags:Watch() end
    SLASH_WOLKARAMOBILE1="/wolkaramobile"
    SLASH_WOLKARAMOBILE2="/wm"
    SlashCmdList.WOLKARAMOBILE=function(msg)
        local cmd=type(msg)=="string" and msg:match("^%s*(%S+)") or ""
        if cmd=="edit" then
            if ns.editing then ns.FinishEditing() else ns.SetEditing(true) end
            return
        elseif cmd=="reset" then
            ns.ResetSideLayout()
            return
        elseif cmd=="menu" then
            if ns.Menu and ns.Menu.Open then ns.Menu:Open() end
            return
        end
        ns.Print("Mobile interface v1.1.0: "..(ns.enabled and "enabled" or "disabled")..
            "; host commands: "..(ns.hostCommands or 0).."; errors: "..(ns.errors or 0)..
            ". Type /wm edit or /wm reset.")
    end
end
