-- Game panel shortcuts dialog accessible via /wm menu (top bar handles quick access).
local _,ns=...
local Menu=ns.Register("Menu",{})
ns.Menu=Menu
local panel
local entries={
    {CHARACTER_BUTTON or "Character","CharacterMicroButton"},
    {BAGSLOT or "Bags",nil,function() ToggleAllBags() end},
    {SPELLBOOK or "Spells","SpellbookMicroButton"},
    {TALENTS or "Talents","TalentMicroButton"},
    {QUESTLOG_BUTTON or "Quests","QuestLogMicroButton"},
    {WORLD_MAP or "Map",nil,function() ToggleWorldMap() end},
    {SOCIAL_BUTTON or "Social","SocialsMicroButton"},
    {GUILD or "Guild","GuildMicroButton"},
    {MAINMENU_BUTTON or "Game menu",nil,function()
        if GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) else ShowUIPanel(GameMenuFrame) end
    end},
}
function Menu:Init()
    panel=CreateFrame("Frame","WolkaraMobileMenu",UIParent,"UIPanelDialogTemplate")
    panel:SetSize(420,300); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG"); panel:EnableMouse(true); panel:Hide()
    local title=ns.Label(panel,"GameFontNormalLarge",MAINMENU_BUTTON or "Menu"); title:SetPoint("TOP",0,-16)
    for i,e in ipairs(entries) do
        local b=ns.UIButton(panel,e[1],182,40,function()
            if InCombatLockdown() then ns.Print("Open this window outside combat."); return end
            local target=e[2] and _G[e[2]]
            if target and target.Click then target:Click() elseif e[3] then e[3]() end
            panel:Hide()
        end)
        b:SetPoint("TOPLEFT",22+((i-1)%2)*194,-48-math.floor((i-1)/2)*47)
    end
end
function Menu:Open()
    if not ns.enabled or not panel then return end
    if panel:IsShown() then panel:Hide() else ns.FitPanel(panel); panel:Show() end
end
function Menu:Disable() if panel then panel:Hide() end end
function Menu:CombatStarts() if panel then panel:Hide() end end
