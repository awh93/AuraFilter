-- AuraFilter.lua
-- Filtert Debuffs auf dem Target Frame
-- Midnight 12.0 kompatibel: pcall um alle Aura-Datenzugriffe (Secret Values)
-- Slash: /af  oder  /aurafilter

local addonName, addon = ...

-- ---------------------------------------------------------------------------
-- Saved Variables & Defaults
-- ---------------------------------------------------------------------------
local defaults = {
    enabled    = true,
    secretFallback = "hide",   -- Was tun wenn Daten secret sind: "hide" | "show"
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
-- Sicheres Lesen von Aura-Feldern (Secret Values → pcall)
-- ---------------------------------------------------------------------------

-- Liest einen Wert sicher aus einer Aura-Tabelle.
-- Gibt nil zurück wenn der Wert ein Secret ist.
local function SafeGet(aura, field)
    local ok, val = pcall(function() return aura[field] end)
    if not ok then return nil end
    -- Secret Values sind kein string/number → noch mal prüfen
    local ok2 = pcall(function()
        local _ = tostring(val) == tostring(val)
    end)
    if not ok2 then return nil end
    return val
end

-- ---------------------------------------------------------------------------
-- Filter-Entscheidung
-- ---------------------------------------------------------------------------
local function ShouldShowDebuff(spellId, sourceUnit)
    local cfg  = AuraFilterDB.targetDebuffs
    local mode = cfg.mode

    if mode == "all" then
        return true

    elseif mode == "onlyMine" then
        if sourceUnit == nil then
            -- Secret → Fallback-Einstellung anwenden
            return AuraFilterDB.secretFallback == "show"
        end
        return sourceUnit == "player"

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
-- Debuff-Buttons finden (mehrere mögliche Strukturen in Midnight)
-- ---------------------------------------------------------------------------
local function GetDebuffButtons()
    if not TargetFrame then return nil end

    -- Midnight / TWW: TargetFrame.debuffFrames
    if TargetFrame.debuffFrames and #TargetFrame.debuffFrames > 0 then
        return TargetFrame.debuffFrames
    end

    -- Ältere Struktur: TargetFrameDebuff1..n
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

    return nil
end

-- ---------------------------------------------------------------------------
-- Haupt-Filter
-- ---------------------------------------------------------------------------
local function FilterTargetDebuffs()
    if not AuraFilterDB or not AuraFilterDB.enabled then return end

    local buttons = GetDebuffButtons()
    if not buttons then return end

    for i, button in ipairs(buttons) do
        if not button then break end

        -- Button-Sichtbarkeit sicher lesen
        local isShown
        pcall(function() isShown = button:IsShown() end)

        if isShown then
            local spellId, sourceUnit

            -- 1. Versuch: button.auraData (neuere Builds)
            if button.auraData then
                spellId    = SafeGet(button.auraData, "spellId")
                sourceUnit = SafeGet(button.auraData, "sourceUnit")

            -- 2. Versuch: button.auraInstanceID → C_UnitAuras
            elseif button.auraInstanceID then
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "target", button.auraInstanceID)
                if ok and aura then
                    spellId    = SafeGet(aura, "spellId")
                    sourceUnit = SafeGet(aura, "sourceUnit")
                end

            -- 3. Versuch: Index-basiert via C_UnitAuras
            else
                local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL")
                if ok and aura then
                    spellId    = SafeGet(aura, "spellId")
                    sourceUnit = SafeGet(aura, "sourceUnit")
                end
            end

            if not ShouldShowDebuff(spellId, sourceUnit) then
                pcall(function() button:Hide() end)
            end
        end
    end
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
        -- Sicher hooken: beide möglichen Funktionen probieren
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
    print("  |cffffcc00/af mode onlyMine|r    – Nur eigene Debuffs zeigen (Standard)")
    print("  |cffffcc00/af mode whitelist|r   – Nur Spells aus der Whitelist zeigen")
    print("  |cffffcc00/af mode blacklist|r   – Alle außer Spells auf der Blacklist")
    print("  |cffffcc00/af mode all|r         – Alle Debuffs zeigen (Filter aus)")
    print("  |cffffcc00/af secret hide|r      – Secret-Auras verstecken (Standard, Instanzen)")
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

        local df = TargetFrame and TargetFrame.debuffFrames
        print("TargetFrame.debuffFrames: " .. tostring(df ~= nil)
            .. (df and (" (Anzahl: "..tostring(#df)..")") or ""))
        print("TargetFrameDebuff1 (global): " .. tostring(_G["TargetFrameDebuff1"] ~= nil))

        -- HARMFUL auras mit filter "HARMFUL" vs "HARMFUL|PLAYER"
        local function countAuras(filter)
            local n = 0
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, filter)
                if not ok or not a then break end
                n = n + 1
                local sid  = SafeGet(a, "spellId")
                local src  = SafeGet(a, "sourceUnit")
                local name = SafeGet(a, "name")
                local iid  = SafeGet(a, "auraInstanceID")
                print(string.format("  [%s] #%d spellId=%s src=%s name=%s instanceID=%s",
                    filter, i, tostring(sid), tostring(src), tostring(name), tostring(iid)))
            end
            return n
        end

        local total  = countAuras("HARMFUL")
        local mine   = countAuras("HARMFUL|PLAYER")
        print("HARMFUL total: " .. total .. "  |  HARMFUL|PLAYER (nur eigene): " .. mine)

        -- TargetFrame-Kindframes bis Tiefe 2 auflisten
        print("-- TargetFrame children (depth 2) --")
        local function listChildren(frame, depth)
            if depth > 2 then return end
            local ok, children = pcall(function() return {frame:GetChildren()} end)
            if not ok then return end
            for _, child in ipairs(children) do
                local cname = (pcall(function() return child:GetName() end)) and child:GetName() or "?"
                local ctype = (pcall(function() return child:GetObjectType() end)) and child:GetObjectType() or "?"
                print(string.rep("  ", depth) .. tostring(cname) .. " [" .. tostring(ctype) .. "]")
                listChildren(child, depth + 1)
            end
        end
        if TargetFrame then listChildren(TargetFrame, 0) end

        print("|cff00ccff[AuraFilter]|r === END DEBUG ===")

    else
        print("|cff00ccff[AuraFilter]|r Unbekannter Befehl. |cffffcc00/af help|r")
    end
end
