local issecretvalue = _G.issecretvalue
local issecrettable = _G.issecrettable
local canaccessvalue = _G.canaccessvalue

local function IsSecret(val)
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, val)
        if ok and secret then return true end
    end
    if issecrettable then
        local ok, secret = pcall(issecrettable, val)
        if ok and secret then return true end
    end
    if canaccessvalue then
        local ok, canAccess = pcall(canaccessvalue, val)
        if ok and not canAccess then return true end
    end
    return false
end

local function IsSafeValue(val)
    if val == nil then return false end
    if IsSecret(val) then return false end
    return true
end

local function IsSafeString(val)
    if not IsSafeValue(val) then return false end
    local ok, isStr = pcall(function()
        return type(val) == "string" and string.find(val, "") ~= nil
    end)
    return (ok and isStr) == true
end

local function CleanTooltipText(text)
    if not IsSafeString(text) then return "" end
    -- Remove texture markup |T...|t
    text = string.gsub(text, "|T.-|t", "")
    -- Remove atlas markup |A...|a
    text = string.gsub(text, "|A.-|a", "")
    -- Remove hex color codes |cffffffff or |cffffff
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|c%x%x%x%x%x%x", "")
    -- Remove named color codes |cn...:
    text = string.gsub(text, "|cn[%a_]+:", "")
    -- Remove closing tag |r
    text = string.gsub(text, "|r", "")
    -- Remove hyperlink tags |H...|h and |h
    text = string.gsub(string.gsub(text, "|H.-|h", ""), "|h", "")
    -- Replace non-breaking spaces (UTF-8 \194\160) with standard space
    text = string.gsub(text, "\194\160", " ")
    return text
end

local function ExtractDPS(text)
    -- First check for channeled patterns with duration: "24 Arcane damage every 1 sec for 3 sec"
    local channelDmgStr, channelTickStr, channelDurationStr = text:match(
        "([%d,]+)%s+%S+%s+damage%s+every%s+([%d%.]+)%s+sec[%.%a]*%s+for%s+([%d%.]+)%s+sec")
    if not (channelDmgStr and channelTickStr and channelDurationStr) then
        channelDmgStr, channelTickStr, channelDurationStr = text:match(
            "([%d,]+)%s+damage%s+every%s+([%d%.]+)%s+sec[%.%a]*%s+for%s+([%d%.]+)%s+sec")
    end

    if channelDmgStr and channelTickStr and channelDurationStr then
        channelDmgStr = channelDmgStr:gsub(",", "")
        local damage = tonumber(channelDmgStr)
        local tickTime = tonumber(channelTickStr)
        local duration = tonumber(channelDurationStr)
        if damage and tickTime and tickTime > 0 and duration then
            local ticks = math.floor(duration / tickTime)
            local totalDamage = damage * ticks
            return damage / tickTime, totalDamage, duration
        end
    end

    -- Fallback for channel without duration: "24 Arcane damage every 1 sec"
    local channelDmgStr2, channelTickStr2 = text:match("([%d,]+)%s+%S+%s+damage%s+every%s+([%d%.]+)%s+sec")
    if not (channelDmgStr2 and channelTickStr2) then
        channelDmgStr2, channelTickStr2 = text:match("([%d,]+)%s+damage%s+every%s+([%d%.]+)%s+sec")
    end

    if channelDmgStr2 and channelTickStr2 then
        channelDmgStr2 = channelDmgStr2:gsub(",", "")
        local damage = tonumber(channelDmgStr2)
        local tickTime = tonumber(channelTickStr2)
        if damage and tickTime and tickTime > 0 then
            return damage / tickTime, nil, nil
        end
    end

    -- Range DoT patterns: "12 to 15 Fire damage over 9 sec"
    local minDoTStr, maxDoTStr, dotRangeSecStr = text:match("([%d,]+)%s+to%s+([%d,]+)%s+%S+%s+damage%s+over%s+([%d%.]+)")
    if not (minDoTStr and maxDoTStr and dotRangeSecStr) then
        minDoTStr, maxDoTStr, dotRangeSecStr = text:match("([%d,]+)%s+to%s+([%d,]+)%s+damage%s+over%s+([%d%.]+)")
    end

    if minDoTStr and maxDoTStr and dotRangeSecStr then
        local minDmg = tonumber((minDoTStr:gsub(",", "")))
        local maxDmg = tonumber((maxDoTStr:gsub(",", "")))
        local seconds = tonumber(dotRangeSecStr)
        if minDmg and maxDmg and seconds and seconds > 0 then
            local avgDmg = (minDmg + maxDmg) / 2
            return avgDmg / seconds, avgDmg, seconds
        end
    end

    -- Flat DoT patterns like: "12 Arcane damage over 9 sec" or "12 damage over 9"
    local damageStr, secondsStr = text:match("([%d,]+)%s+%S+%s+damage%s+over%s+([%d%.]+)")
    if not (damageStr and secondsStr) then
        damageStr, secondsStr = text:match("([%d,]+)%s+damage%s+over%s+([%d%.]+)")
    end

    if damageStr and secondsStr then
        damageStr = damageStr:gsub(",", "")
        local damage = tonumber(damageStr)
        local seconds = tonumber(secondsStr)

        if damage and seconds and seconds > 0 then
            return damage / seconds, damage, seconds
        end
    end

    return nil, nil, nil
end

local function ExtractDirectDPS(text)
    local timeDivisor = nil

    -- Find the cast time first, e.g., "1.5 sec cast", "1.5 second cast", "1.5 sec. cast"
    local castTimeStr = text:match("([%d%.]+)%s+sec[%.%a]*%s+cast")
    if castTimeStr then
        timeDivisor = tonumber(castTimeStr)
    end

    -- If no cast time, check for a cooldown, e.g., "8 sec cooldown", "Cooldown: 8 sec"
    if not timeDivisor then
        local cooldownStr = text:match("([%d%.]+)%s+sec[%.%a]*%s+cooldown")
            or text:match("[Cc]ooldown:%s*([%d%.]+)%s+sec")
        if cooldownStr then
            timeDivisor = tonumber(cooldownStr)
        end
    end

    -- If no cast time and no cooldown, check if it's "Instant" (assume 1.5s GCD)
    if not timeDivisor then
        if text:match("Instant") then
            timeDivisor = 1.5
        end
    end

    if not timeDivisor or timeDivisor <= 0 then
        return nil, nil, nil
    end

    -- Look for range damage: "12 to 15 Nature damage" or "12 to 15 damage"
    -- Ensure it is not part of a range DoT ("12 to 15 Nature damage over 9 sec")
    local isRangeDot = text:match("([%d,]+)%s+to%s+([%d,]+)%s+%S+%s+damage%s+over")
        or text:match("([%d,]+)%s+to%s+([%d,]+)%s+damage%s+over")

    if not isRangeDot then
        local minDmgStr, maxDmgStr = text:match("([%d,]+)%s+to%s+([%d,]+)%s+%S+%s+damage")
        if not (minDmgStr and maxDmgStr) then
            minDmgStr, maxDmgStr = text:match("([%d,]+)%s+to%s+([%d,]+)%s+damage")
        end

        if minDmgStr and maxDmgStr then
            local minDmg = tonumber((minDmgStr:gsub(",", "")))
            local maxDmg = tonumber((maxDmgStr:gsub(",", "")))
            if minDmg and maxDmg then
                local avgDmg = (minDmg + maxDmg) / 2
                return avgDmg / timeDivisor, avgDmg, timeDivisor
            end
        end
    end

    -- Look for flat direct damage: "Causes 15 Nature damage", "Deals 15 Nature damage", "Inflicts 15 Nature damage", "for 15 Nature damage"
    local flatDmgStr = text:match("[Cc]auses%s+([%d,]+)%s+%S+%s+damage")
        or text:match("[Dd]eals%s+([%d,]+)%s+%S+%s+damage")
        or text:match("[Ii]nflicts%s+([%d,]+)%s+%S+%s+damage")
        or text:match("for%s+([%d,]+)%s+%S+%s+damage")

    if not flatDmgStr then
        flatDmgStr = text:match("[Cc]auses%s+([%d,]+)%s+damage")
            or text:match("[Dd]eals%s+([%d,]+)%s+damage")
            or text:match("[Ii]nflicts%s+([%d,]+)%s+damage")
            or text:match("for%s+([%d,]+)%s+damage")
    end

    if flatDmgStr then
        -- Ensure this flat damage is not part of a DoT ("X damage over Y sec")
        local isDot = text:match(flatDmgStr .. "%s+%S+%s+damage%s+over")
            or text:match(flatDmgStr .. "%s+damage%s+over")

        if not isDot then
            local flatDmg = tonumber((flatDmgStr:gsub(",", "")))
            if flatDmg then
                return flatDmg / timeDivisor, flatDmg, timeDivisor
            end
        end
    end

    return nil, nil, nil
end

local function GetTooltipText(tooltip, data)
    local fullText = ""

    -- 1. Modern TooltipData lines if provided by TooltipDataProcessor
    if IsSafeValue(data) and IsSafeValue(data.lines) then
        -- Start at 2 to skip the spell's title (line 1)
        for i = 2, #data.lines do
            local lineData = data.lines[i]
            if IsSafeValue(lineData) then
                if IsSafeString(lineData.leftText) then
                    local cleaned = CleanTooltipText(lineData.leftText)
                    if cleaned ~= "" then
                        fullText = fullText .. " " .. cleaned
                    end
                end
                if IsSafeString(lineData.rightText) then
                    local cleaned = CleanTooltipText(lineData.rightText)
                    if cleaned ~= "" then
                        fullText = fullText .. " " .. cleaned
                    end
                end
            end
        end
    end

    -- 2. Fallback to scanning FontStrings on the tooltip frame
    if fullText == "" and tooltip and tooltip.GetName then
        local okName, tooltipName = pcall(tooltip.GetName, tooltip)
        if okName and IsSafeString(tooltipName) then
            local numLines = 0
            if tooltip.NumLines then
                local okLines, lines = pcall(tooltip.NumLines, tooltip)
                if okLines and IsSafeValue(lines) and type(lines) == "number" then
                    numLines = lines
                end
            end
            for i = 2, numLines do
                local leftFs = _G[tooltipName .. "TextLeft" .. i]
                if leftFs and leftFs.GetText then
                    local okText, text = pcall(leftFs.GetText, leftFs)
                    if okText and IsSafeString(text) then
                        local cleaned = CleanTooltipText(text)
                        if cleaned ~= "" then
                            fullText = fullText .. " " .. cleaned
                        end
                    end
                end
                local rightFs = _G[tooltipName .. "TextRight" .. i]
                if rightFs and rightFs.GetText then
                    local okText, text = pcall(rightFs.GetText, rightFs)
                    if okText and IsSafeString(text) then
                        local cleaned = CleanTooltipText(text)
                        if cleaned ~= "" then
                            fullText = fullText .. " " .. cleaned
                        end
                    end
                end
            end
        end
    end

    return fullText
end

local function HasDpsLines(tooltip, data)
    if IsSafeValue(data) and IsSafeValue(data.lines) then
        for _, lineData in ipairs(data.lines) do
            if IsSafeValue(lineData) then
                local lt = lineData.leftText
                if IsSafeString(lt) then
                    local ok, found = pcall(function()
                        return string.find(lt, "Direct DPS:")
                            or string.find(lt, "DoT DPS:")
                            or string.find(lt, "Est%. Total Damage:")
                    end)
                    if ok and found then
                        return true
                    end
                end
            end
        end
    end

    if tooltip and tooltip.GetName then
        local okName, tooltipName = pcall(tooltip.GetName, tooltip)
        if okName and IsSafeString(tooltipName) then
            local numLines = 0
            if tooltip.NumLines then
                local okLines, lines = pcall(tooltip.NumLines, tooltip)
                if okLines and IsSafeValue(lines) and type(lines) == "number" then
                    numLines = lines
                end
            end
            for i = 1, numLines do
                local leftFs = _G[tooltipName .. "TextLeft" .. i]
                if leftFs and leftFs.GetText then
                    local okText, text = pcall(leftFs.GetText, leftFs)
                    if okText and IsSafeString(text) then
                        local ok, found = pcall(function()
                            return string.find(text, "Direct DPS:")
                                or string.find(text, "DoT DPS:")
                                or string.find(text, "Est%. Total Damage:")
                        end)
                        if ok and found then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

local function SafeProcessSpellTooltip(tooltip, data)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local spellID = nil
    if IsSafeValue(data) and IsSafeValue(data.id) then
        spellID = data.id
    end
    if not spellID and tooltip.GetSpell then
        local ok, _, sid = pcall(tooltip.GetSpell, tooltip)
        if ok and IsSafeValue(sid) then
            spellID = sid
        end
    end

    -- Verify it's a spell tooltip
    local isSpellType = false
    if IsSafeValue(data) and IsSafeValue(data.type) and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
        isSpellType = (data.type == Enum.TooltipDataType.Spell)
    end

    if not spellID and not isSpellType then
        return
    end

    -- Prevent duplicate lines from repeated calls
    if HasDpsLines(tooltip, data) then
        return
    end

    local fullText = GetTooltipText(tooltip, data)
    if not IsSafeString(fullText) or fullText == "" then
        return
    end

    -- Try to extract direct DPS
    local directDps, directTotal, directTime = ExtractDirectDPS(fullText)
    if directDps then
        -- Add direct DPS line in a light blue color
        tooltip:AddLine(string.format("Direct DPS: %.1f", directDps), 0.2, 0.8, 1.0)
    end

    -- Try to extract DoT DPS from the combined text
    local dotDps, dotTotal, dotTime = ExtractDPS(fullText)
    if dotDps then
        -- Add the DoT DPS line in a light green color
        tooltip:AddLine(string.format("DoT DPS: %.1f", dotDps), 0.2, 1.0, 0.2)
    end

    local totalEstimatedDamage = 0
    local totalEstimatedTime = 0
    local hasTotal = false

    if directTotal then
        totalEstimatedDamage = totalEstimatedDamage + directTotal
        -- Only add the directTime (cast time/GCD) if there isn't a DoT duration taking over
        -- or if it's an actual cast time/cooldown (not just assuming 1.5s for instant)
        if directTime and (not dotTime or directTime ~= 1.5) then
            totalEstimatedTime = totalEstimatedTime + directTime
        end
        hasTotal = true
    end

    if dotTotal then
        totalEstimatedDamage = totalEstimatedDamage + dotTotal
        if dotTime then
            totalEstimatedTime = totalEstimatedTime + dotTime
        end
        hasTotal = true
    end

    if hasTotal then
        -- Yellow/orange line for total estimated damage
        tooltip:AddLine(string.format("Est. Total Damage: %d", totalEstimatedDamage), 1.0, 0.8, 0.2)

        -- If we have both direct and DoT components, show a combined cycle DPS
        if directTotal and dotTotal and totalEstimatedTime > 0 then
            local combinedDps = totalEstimatedDamage / totalEstimatedTime
            tooltip:AddLine(string.format("Est. Cycle DPS: %.1f", combinedDps), 1.0, 0.5, 0.0)
        end
    end

    -- In legacy HookScript mode, tooltip:Show() was needed to resize the tooltip frame.
    -- In TooltipDataProcessor mode, Show() is automatically handled by the engine.
    if not data and (directDps or dotDps or hasTotal) then
        tooltip:Show()
    end
end

local function ProcessSpellTooltip(tooltip, data)
    pcall(SafeProcessSpellTooltip, tooltip, data)
end

-- Registration: Support modern TooltipDataProcessor (WoW Forever / 10.0+) and fallback to OnTooltipSetSpell (Classic)
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, ProcessSpellTooltip)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript and tt:HasScript("OnTooltipSetSpell") then
            tt:HookScript("OnTooltipSetSpell", function(tooltip)
                ProcessSpellTooltip(tooltip, nil)
            end)
        end
    end
end
