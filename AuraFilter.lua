-- AuraFilter.lua
-- Filtert Debuffs auf dem Target Frame
-- Unterstützt drei Modi: onlyMine | whitelist | blacklist
-- Slash: /af  oder  /aurafilter

local addonName, addon = ...

-- ---------------------------------------------------------------------------
-- Saved Variables & Defaults
-- ---------------------------------------------------------------------------
local defaults = {
    enabled    = true,
    targetDebuffs = {
        mode      = "onlyMine",  -- "onlyMine" | "whitelist" | "blacklist" | "all"
        whitelist = {},          -- [spellID] = "Name"  → nur diese zeigen
        blacklist = {},          -- [spellID] = "Name"  → diese verstecken
    },
}

local function ApplyDefaults(target, src)
    for k, v in pairs(src) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                ApplyDefaults(target[k], v)
            else
                target[k] = v
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Aura-Filter Logik
-- ---------------------------------------------------------------------------

-- Gibt zurück ob eine Aura angezeigt werden soll
local function ShouldShowDebuff(spellId, sourceUnit)
    local cfg = AuraFilterDB.targetDebuffs
    local mode = cfg.mode

    if mode == "all" then
        return true

    elseif mode == "onlyMine" then
        return sourceUnit == "player"

    elseif mode == "whitelist" then
        return cfg.whitelist[spellId] ~= nil

    elseif mode == "blacklist" then
        return cfg.blacklist[spellId] == nil
    end

    return true
end

-- Iteriert alle Debuffs auf dem Target und blendet unerwünschte aus.
-- Funktioniert mit dem alten TargetFrame-Button-System (Classic-style TargetFrame)
-- sowie dem neueren System via C_UnitAuras.
local function FilterTargetDebuffs()
    if not AuraFilterDB.enabled then return end

    -- Neueres API: C_UnitAuras + direktes Iterieren der Debuff-Buttons
    local frame = TargetFrame
    if not frame then return end

    -- Debuff-Buttons liegen in TargetFrame.debuffFrames (TWW / Midnight)
    local debuffFrames = frame.debuffFrames
    if not debuffFrames then return end

    for i, button in ipairs(debuffFrames) do
        if button and button:IsShown() then
            local auraData = button.auraData
            if auraData then
                local spellId    = auraData.spellId or 0
                local sourceUnit = auraData.sourceUnit or ""
                if not ShouldShowDebuff(spellId, sourceUnit) then
                    button:Hide()
                end
            else
                -- Fallback: button hat kein auraData → über C_UnitAuras nachschlagen
                local aura = C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL")
                if aura then
                    local sourceUnit = aura.sourceUnit or ""
                    local spellId    = aura.spellId or 0
                    if not ShouldShowDebuff(spellId, sourceUnit) then
                        button:Hide()
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        AuraFilterDB = AuraFilterDB or {}
        ApplyDefaults(AuraFilterDB, defaults)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Ins Update-System einklinken: nach jedem TargetFrame-Aura-Update filtern
        if TargetFrame then
            hooksecurefunc(TargetFrame, "UpdateDebuffs", function()
                FilterTargetDebuffs()
            end)
            -- Fallback: generischer Aura-Update-Hook
            hooksecurefunc("TargetFrame_UpdateAuras", function()
                FilterTargetDebuffs()
            end)
        end
        print("|cff00ccff[AuraFilter]|r geladen. |cffffcc00/af help|r für Befehle.")

    elseif event == "UNIT_AURA" and arg1 == "target" then
        FilterTargetDebuffs()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash Commands
-- ---------------------------------------------------------------------------
local function PrintHelp()
    print("|cff00ccff[AuraFilter]|r Befehle:")
    print("  |cffffcc00/af mode onlyMine|r    – Nur eigene Debuffs zeigen (Standard)")
    print("  |cffffcc00/af mode whitelist|r   – Nur Spells aus der Whitelist zeigen")
    print("  |cffffcc00/af mode blacklist|r   – Alle außer Spells auf der Blacklist")
    print("  |cffffcc00/af mode all|r         – Alle Debuffs zeigen (Filter aus)")
    print("  |cffffcc00/af white add <ID> [Name]|r  – Spell zur Whitelist hinzufügen")
    print("  |cffffcc00/af white remove <ID>|r      – Spell aus Whitelist entfernen")
    print("  |cffffcc00/af white list|r             – Whitelist anzeigen")
    print("  |cffffcc00/af black add <ID> [Name]|r  – Spell zur Blacklist hinzufügen")
    print("  |cffffcc00/af black remove <ID>|r      – Spell aus Blacklist entfernen")
    print("  |cffffcc00/af black list|r             – Blacklist anzeigen")
    print("  |cffffcc00/af status|r           – Aktuelle Einstellungen")
    print("  |cffffcc00/af enable|r / |cffffcc00disable|r – Addon an/aus")
end

local function PrintStatus()
    local cfg = AuraFilterDB.targetDebuffs
    print("|cff00ccff[AuraFilter]|r Status:")
    print(string.format("  Addon:  %s", AuraFilterDB.enabled and "|cff00ff00Aktiv|r" or "|cffff4444Inaktiv|r"))
    print(string.format("  Modus:  |cffffcc00%s|r", cfg.mode))

    local wCount, bCount = 0, 0
    for _ in pairs(cfg.whitelist) do wCount = wCount + 1 end
    for _ in pairs(cfg.blacklist) do bCount = bCount + 1 end
    print(string.format("  Whitelist: %d Einträge | Blacklist: %d Einträge", wCount, bCount))
end

local function PrintList(list, label)
    print(string.format("|cff00ccff[AuraFilter]|r %s:", label))
    local any = false
    for id, name in pairs(list) do
        print(string.format("  |cffffcc00%s|r – %s", id, name))
        any = true
    end
    if not any then print("  (leer)") end
end

SLASH_AURAFILTER1 = "/af"
SLASH_AURAFILTER2 = "/aurafilter"

SlashCmdList["AURAFILTER"] = function(msg)
    local cmd, sub, rest = msg:match("^(%S*)%s*(%S*)%s*(.*)")
    cmd = cmd:lower()
    sub = sub:lower()

    if cmd == "" or cmd == "help" then
        PrintHelp()

    elseif cmd == "status" then
        PrintStatus()

    elseif cmd == "enable" then
        AuraFilterDB.enabled = true
        FilterTargetDebuffs()
        print("|cff00ccff[AuraFilter]|r |cff00ff00Aktiviert.|r")

    elseif cmd == "disable" then
        AuraFilterDB.enabled = false
        -- Alle Debuff-Buttons wieder einblenden
        if TargetFrame and TargetFrame.debuffFrames then
            for _, btn in ipairs(TargetFrame.debuffFrames) do
                btn:Show()
            end
        end
        print("|cff00ccff[AuraFilter]|r |cffff4444Deaktiviert.|r")

    elseif cmd == "mode" then
        local validModes = { onlyMine=true, whitelist=true, blacklist=true, all=true }
        if not validModes[sub] then
            print("|cff00ccff[AuraFilter]|r Ungültiger Modus. Erlaubt: onlyMine | whitelist | blacklist | all")
            return
        end
        AuraFilterDB.targetDebuffs.mode = sub
        FilterTargetDebuffs()
        print(string.format("|cff00ccff[AuraFilter]|r Modus gesetzt: |cffffcc00%s|r", sub))

    elseif cmd == "white" then
        local cfg = AuraFilterDB.targetDebuffs
        if sub == "add" then
            local idStr, name = rest:match("^(%S+)%s*(.*)")
            local id = tonumber(idStr)
            if not id then print("|cff00ccff[AuraFilter]|r Ungültige Spell-ID."); return end
            cfg.whitelist[tostring(id)] = (name ~= "" and name) or ("Spell #"..id)
            print(string.format("|cff00ccff[AuraFilter]|r Whitelist +|cffffcc00%d|r", id))
            FilterTargetDebuffs()
        elseif sub == "remove" then
            local id = tonumber(rest:match("^(%S+)"))
            if not id then print("|cff00ccff[AuraFilter]|r Ungültige Spell-ID."); return end
            cfg.whitelist[tostring(id)] = nil
            print(string.format("|cff00ccff[AuraFilter]|r Whitelist –|cffffcc00%d|r", id))
            FilterTargetDebuffs()
        elseif sub == "list" then
            PrintList(AuraFilterDB.targetDebuffs.whitelist, "Whitelist")
        else
            print("|cff00ccff[AuraFilter]|r /af white add|remove|list")
        end

    elseif cmd == "black" then
        local cfg = AuraFilterDB.targetDebuffs
        if sub == "add" then
            local idStr, name = rest:match("^(%S+)%s*(.*)")
            local id = tonumber(idStr)
            if not id then print("|cff00ccff[AuraFilter]|r Ungültige Spell-ID."); return end
            cfg.blacklist[tostring(id)] = (name ~= "" and name) or ("Spell #"..id)
            print(string.format("|cff00ccff[AuraFilter]|r Blacklist +|cffffcc00%d|r", id))
            FilterTargetDebuffs()
        elseif sub == "remove" then
            local id = tonumber(rest:match("^(%S+)"))
            if not id then print("|cff00ccff[AuraFilter]|r Ungültige Spell-ID."); return end
            cfg.blacklist[tostring(id)] = nil
            print(string.format("|cff00ccff[AuraFilter]|r Blacklist –|cffffcc00%d|r", id))
            FilterTargetDebuffs()
        elseif sub == "list" then
            PrintList(AuraFilterDB.targetDebuffs.blacklist, "Blacklist")
        else
            print("|cff00ccff[AuraFilter]|r /af black add|remove|list")
        end

    else
        print("|cff00ccff[AuraFilter]|r Unbekannter Befehl. |cffffcc00/af help|r")
    end
end
