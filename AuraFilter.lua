-- AuraFilter.lua
-- Filtert Debuffs auf dem Target Frame
-- Midnight 12.0 kompatibel: pcall um alle Aura-Datenzugriffe (Secret Values)
-- onlyMine: spiegelt Nameplate-Debuffs (Blizzards Filterlogik), Fallback HARMFUL|PLAYER
-- Slash: /af  oder  /aurafilter

local addonName, addon = ...

-- ---------------------------------------------------------------------------
-- Saved Variables & Defaults
-- ---------------------------------------------------------------------------
local defaults = {
    enabled    = true,
    secretFallback = "hide",
    targetDebuffs = {
        mode      = "onlyMine",  -- "onlyMine" | "whitelist" | "blacklist" | "all"
        whitelist = {},
        blacklist = {},
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
-- Sicheres Lesen von Aura-Feldern (Secret Values → pcall)
-- ---------------------------------------------------------------------------
local function SafeGet(aura, field)
    local ok, val = pcall(function() return aura[field] end)
    if not ok then return nil end
    local ok2 = pcall(function()
        local _ = tostring(val) == tostring(val)
    end)
    if not ok2 then return nil end
    return val
end

-- ---------------------------------------------------------------------------
-- Nameplate mirror: auraInstanceIDs aller sichtbaren Nameplate-Debuffs
-- ---------------------------------------------------------------------------
local function GetNameplateAuraInstanceIDs()
    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    if not nameplate then return nil end

    local set = {}
    local found = 0

    local function scan(frame, depth)
        if depth > 6 then return end
        local ok, children = pcall(function() return {frame:GetChildren()} end)
        if not ok then return end
        for _, child in ipairs(children) do
            local ok2, iid = pcall(function() return child.auraInstanceID end)
            if ok2 and iid and type(iid) == "number" then
                local shown
                pcall(function() shown = child:IsShown() end)
                if shown then
                    set[iid] = true
                    found = found + 1
                end
            end
            scan(child, depth + 1)
        end
    end

    scan(nameplate, 0)
    if found == 0 then return nil end
    return set
end

-- ---------------------------------------------------------------------------
-- Fallback: HARMFUL|PLAYER instanceID-Set
-- ---------------------------------------------------------------------------
local function GetPlayerAuraInstanceIDs()
    local set = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
        if not ok or not aura then break end
        local iid = SafeGet(aura, "auraInstanceID")
        if iid then set[iid] = true end
    end
    return set
end

-- ---------------------------------------------------------------------------
-- Filter-Entscheidung
-- ---------------------------------------------------------------------------
local function ShouldShowDebuff(spellId, instanceID, showIDs)
    local cfg  = AuraFilterDB.targetDebuffs
    local mode = cfg.mode

    if mode == "all" then
        return true

    elseif mode == "onlyMine" then
        if showIDs and instanceID then
            return showIDs[instanceID] == true
        end
        return AuraFilterDB.secretFallback == "show"

    elseif mode == "whitelist" then
        if spellId == nil then
            return AuraFilterDB.secretFallback == "show"
        end
        return cfg.whitelist[tostring(spellId)] ~= nil

    elseif mode == "blacklist" then
        if spellId == nil then
            return AuraFilterDB.secretFallback == "show"
        end
        return cfg.blacklist[tostring(spellId)] == nil
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Debuff-Buttons des TargetFrame finden
-- ---------------------------------------------------------------------------
local function GetDebuffButtons()
    if not TargetFrame then return nil end

    -- Classic / TWW: TargetFrame.debuffFrames
    if TargetFrame.debuffFrames and #TargetFrame.debuffFrames > 0 then
        return TargetFrame.debuffFrames
    end

    -- Legacy globals
    local buttons = {}
    for i = 1, 40 do
        local btn = _G["TargetFrameDebuff"..i]
        if btn then
            table.insert(buttons, btn)
        else
            break
        end
    end
    if #buttons > 0 then return buttons end

    -- Midnight 12.0: unbenannte direkte Kinder von TargetFrame
    -- mit einem direkten Kind namens "TargetFrameCooldown"
    local ok, children = pcall(function() return {TargetFrame:GetChildren()} end)
    if ok then
        for _, child in ipairs(children) do
            local ok2, gcs = pcall(function() return {child:GetChildren()} end)
            if ok2 then
                for _, gc in ipairs(gcs) do
                    local ok3, gcName = pcall(function() return gc:GetName() end)
                    if ok3 and gcName and gcName == "TargetFrameCooldown" then
                        table.insert(buttons, child)
                        break
                    end
                end
            end
        end
    end
    if #buttons > 0 then return buttons end

    return nil
end

-- ---------------------------------------------------------------------------
-- Haupt-Filter (läuft verzögert via C_Timer so dass Blizzard zuerst updated)
-- ---------------------------------------------------------------------------
local function FilterTargetDebuffsNow()
    if not AuraFilterDB or not AuraFilterDB.enabled then return end

    local cfg = AuraFilterDB.targetDebuffs
    if cfg.mode == "all" then return end

    local buttons = GetDebuffButtons()
    if not buttons or #buttons == 0 then return end

    -- Show-Set aufbauen
    local showIDs = nil
    if cfg.mode == "onlyMine" then
        showIDs = GetNameplateAuraInstanceIDs()
        if not showIDs then
            showIDs = GetPlayerAuraInstanceIDs()
        end
    end

    for i, button in ipairs(buttons) do
        if not button then break end

        -- auraInstanceID direkt vom Button lesen (in Midnight bestätigt lesbar)
        local instanceID
        local ok1, val1 = pcall(function() return button.auraInstanceID end)
        if ok1 and val1 and type(val1) == "number" then
            instanceID = val1
        end

        -- Fallback: button.auraData
        if not instanceID and button.auraData then
            instanceID = SafeGet(button.auraData, "auraInstanceID")
        end

        -- Fallback: Index-basiert
        if not instanceID then
            local ok2, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
            if ok2 and aura then
                instanceID = SafeGet(aura, "auraInstanceID")
            end
        end

        if instanceID then
            -- Button hat eine aktive Aura: explizit show ODER hide setzen.
            -- Wichtig: wir setzen beides, damit vorherige Filter-Zustände
            -- immer korrekt überschrieben werden.
            if ShouldShowDebuff(nil, instanceID, showIDs) then
                pcall(function() button:Show() end)
            else
                pcall(function() button:Hide() end)
            end
        end
        -- instanceID == nil → leerer Slot, Blizzard verwaltet
    end
end

-- Verzögert ausführen damit Blizzards Frame-Update zuerst abgeschlossen ist
local function FilterTargetDebuffs()
    C_Timer.After(0, FilterTargetDebuffsNow)
end

-- ---------------------------------------------------------------------------
-- Events & Hooks
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        AuraFilterDB = AuraFilterDB or {}
        ApplyDefaults(AuraFilterDB, defaults)
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        pcall(function()
            hooksecurefunc(TargetFrame, "UpdateDebuffs", FilterTargetDebuffs)
        end)
        pcall(function()
            hooksecurefunc("TargetFrame_UpdateAuras", FilterTargetDebuffs)
        end)
        print("|cff00ccff[AuraFilter]|r geladen. |cffffcc00/af help|r für Befehle.")

    elseif event == "UNIT_AURA" and arg1 == "target" then
        FilterTargetDebuffs()

    elseif event == "PLAYER_TARGET_CHANGED" then
        FilterTargetDebuffs()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash Commands
-- ---------------------------------------------------------------------------
local function PrintHelp()
    print("|cff00ccff[AuraFilter]|r Befehle:")
    print("  |cffffcc00/af mode onlyMine|r    – Nameplate-Debuffs spiegeln (Standard)")
    print("  |cffffcc00/af mode whitelist|r   – Nur Spells aus der Whitelist zeigen")
    print("  |cffffcc00/af mode blacklist|r   – Alle außer Spells auf der Blacklist")
    print("  |cffffcc00/af mode all|r         – Alle Debuffs zeigen (Filter aus)")
    print("  |cffffcc00/af secret hide|r      – Secret-Auras verstecken (Standard)")
    print("  |cffffcc00/af secret show|r      – Secret-Auras trotzdem anzeigen")
    print("  |cffffcc00/af white add <ID> [Name]|r  – Spell zur Whitelist")
    print("  |cffffcc00/af white remove <ID>|r      – Spell aus Whitelist")
    print("  |cffffcc00/af white list|r             – Whitelist anzeigen")
    print("  |cffffcc00/af black add <ID> [Name]|r  – Spell zur Blacklist")
    print("  |cffffcc00/af black remove <ID>|r      – Spell aus Blacklist")
    print("  |cffffcc00/af black list|r             – Blacklist anzeigen")
    print("  |cffffcc00/af status|r           – Aktuelle Einstellungen")
    print("  |cffffcc00/af enable|r / |cffffcc00disable|r – Addon an/aus")
end

local function PrintStatus()
    local cfg = AuraFilterDB.targetDebuffs
    print("|cff00ccff[AuraFilter]|r Status:")
    print(string.format("  Addon:          %s", AuraFilterDB.enabled and "|cff00ff00Aktiv|r" or "|cffff4444Inaktiv|r"))
    print(string.format("  Modus:          |cffffcc00%s|r", cfg.mode))
    print(string.format("  Secret-Fallback:|cffffcc00%s|r", AuraFilterDB.secretFallback))
    local wCount, bCount = 0, 0
    for _ in pairs(cfg.whitelist) do wCount = wCount + 1 end
    for _ in pairs(cfg.blacklist) do bCount = bCount + 1 end
    print(string.format("  Whitelist: %d | Blacklist: %d Einträge", wCount, bCount))
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
        -- Alle Buttons wieder zeigen
        local buttons = GetDebuffButtons()
        if buttons then
            for _, btn in ipairs(buttons) do
                pcall(function() btn:Show() end)
            end
        end
        print("|cff00ccff[AuraFilter]|r |cffff4444Deaktiviert.|r")

    elseif cmd == "secret" then
        if sub == "hide" or sub == "show" then
            AuraFilterDB.secretFallback = sub
            FilterTargetDebuffs()
            print(string.format("|cff00ccff[AuraFilter]|r Secret-Fallback: |cffffcc00%s|r", sub))
        else
            print("|cff00ccff[AuraFilter]|r /af secret hide|show")
        end

    elseif cmd == "mode" then
        local validModes = { onlyMine=true, whitelist=true, blacklist=true, all=true }
        if not validModes[sub] then
            print("|cff00ccff[AuraFilter]|r Erlaubt: onlyMine | whitelist | blacklist | all")
            return
        end
        AuraFilterDB.targetDebuffs.mode = sub
        FilterTargetDebuffs()
        print(string.format("|cff00ccff[AuraFilter]|r Modus: |cffffcc00%s|r", sub))

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
            PrintList(cfg.whitelist, "Whitelist")
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
            PrintList(cfg.blacklist, "Blacklist")
        else
            print("|cff00ccff[AuraFilter]|r /af black add|remove|list")
        end

    elseif cmd == "debug" then
        print("|cff00ccff[AuraFilter]|r === DEBUG ===")
        print("TargetFrame: " .. tostring(TargetFrame ~= nil))

        -- Nameplate
        local nameplate = C_NamePlate.GetNamePlateForUnit("target")
        print("Nameplate für target: " .. tostring(nameplate ~= nil))
        if nameplate then
            local npIDs = GetNameplateAuraInstanceIDs()
            if npIDs then
                local count, ids = 0, ""
                for iid in pairs(npIDs) do count = count + 1; ids = ids .. iid .. " " end
                print("  Nameplate auraInstanceIDs (" .. count .. "): " .. ids)
            else
                print("  Keine sichtbaren Auras auf Nameplate")
            end
        end

        -- HARMFUL auras
        local function countAuras(filter)
            local n = 0
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
                if not ok or not a then break end
                n = n + 1
                local iid = SafeGet(a, "auraInstanceID")
                print(string.format("  [%s] #%d instanceID=%s", filter, i, tostring(iid)))
            end
            return n
        end
        local total = countAuras("HARMFUL")
        local mine  = countAuras("HARMFUL|PLAYER")
        print("HARMFUL total: " .. total .. "  |  HARMFUL|PLAYER: " .. mine)

        -- GetDebuffButtons + Button-Inspektion
        local buttons = GetDebuffButtons()
        print("GetDebuffButtons: " .. (buttons and (tostring(#buttons).." gefunden") or "nil"))
        if buttons then
            for i, btn in ipairs(buttons) do
                local ok, iid = pcall(function() return btn.auraInstanceID end)
                local shown
                pcall(function() shown = btn:IsShown() end)
                print(string.format("  btn#%d auraInstanceID=%s shown=%s",
                    i, (ok and tostring(iid) or "err"), tostring(shown)))
            end
        end

        print("|cff00ccff[AuraFilter]|r === END DEBUG ===")

    else
        print("|cff00ccff[AuraFilter]|r Unbekannter Befehl. |cffffcc00/af help|r")
    end
end
