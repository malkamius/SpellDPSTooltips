local function CleanTooltipText(text)
    if not text then return "" end
    -- Remove texture markup |T...|t
    text = text:gsub("|T.-|t", "")
    -- Remove atlas markup |A...|a
    text = text:gsub("|A.-|a", "")
    -- Remove hex color codes |cffffffff or |cffffff
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|c%x%x%x%x%x%x", "")
    -- Remove named color codes |cn...:
    text = text:gsub("|cn[%a_]+:", "")
    -- Remove closing tag |r
    text = text:gsub("|r", "")
    -- Remove hyperlink tags |H...|h and |h
    text = text:gsub("|H.-|h", ""):gsub("|h", "")
    -- Replace non-breaking spaces (UTF-8 \194\160) with standard space
    text = text:gsub("\194\160", " ")
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
    if data and data.lines and #data.lines > 0 then
        -- Start at 2 to skip the spell's title (line 1)
        for i = 2, #data.lines do
            local lineData = data.lines[i]
            if lineData then
                if lineData.leftText and lineData.leftText ~= "" then
                    fullText = fullText .. " " .. CleanTooltipText(lineData.leftText)
                end
                if lineData.rightText and lineData.rightText ~= "" then
                    fullText = fullText .. " " .. CleanTooltipText(lineData.rightText)
                end
            end
        end
    end

    -- 2. Fallback to scanning FontStrings on the tooltip frame
    if fullText == "" and tooltip and tooltip.GetName then
        local tooltipName = tooltip:GetName()
        if tooltipName then
            local numLines = tooltip:NumLines() or 0
            for i = 2, numLines do
                local leftFs = _G[tooltipName .. "TextLeft" .. i]
                if leftFs then
                    local text = leftFs:GetText()
                    if text and text ~= "" then
                        fullText = fullText .. " " .. CleanTooltipText(text)
                    end
                end
                local rightFs = _G[tooltipName .. "TextRight" .. i]
                if rightFs then
                    local text = rightFs:GetText()
                    if text and text ~= "" then
                        fullText = fullText .. " " .. CleanTooltipText(text)
                    end
                end
            end
        end
    end

    return fullText
end

local function HasDpsLines(tooltip, data)
    if data and data.lines then
        for _, lineData in ipairs(data.lines) do
            local lt = lineData.leftText
            if lt and (lt:find("Direct DPS:") or lt:find("DoT DPS:") or lt:find("Est%. Total Damage:")) then
                return true
            end
        end
    end

    if tooltip and tooltip.GetName then
        local tooltipName = tooltip:GetName()
        if tooltipName then
            local numLines = tooltip:NumLines() or 0
            for i = 1, numLines do
                local leftFs = _G[tooltipName .. "TextLeft" .. i]
                if leftFs then
                    local text = leftFs:GetText()
                    if text and (text:find("Direct DPS:") or text:find("DoT DPS:") or text:find("Est%. Total Damage:")) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function ProcessSpellTooltip(tooltip, data)
    if not tooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end

    local spellID = (data and data.id)
    if not spellID and tooltip.GetSpell then
        local _, sid = tooltip:GetSpell()
        spellID = sid
    end

    -- Verify it's a spell tooltip
    if not spellID and not (data and Enum and Enum.TooltipDataType and data.type == Enum.TooltipDataType.Spell) then
        return
    end

    -- Prevent duplicate lines from repeated calls
    if HasDpsLines(tooltip, data) then
        return
    end

    local fullText = GetTooltipText(tooltip, data)
    if not fullText or fullText == "" then
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
