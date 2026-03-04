local function ExtractDPS(text)
    -- First check for channeled patterns with duration: "24 Arcane damage every 1 sec for 3 sec"
    local channelDmgStr, channelTickStr, channelDurationStr = text:match(
        "([%d,]+)%s+%S+%s+damage%s+every%s+([%d%.]+)%s+sec%s+for%s+([%d%.]+)%s+sec")
    if not (channelDmgStr and channelTickStr and channelDurationStr) then
        channelDmgStr, channelTickStr, channelDurationStr = text:match(
            "([%d,]+)%s+damage%s+every%s+([%d%.]+)%s+sec%s+for%s+([%d%.]+)%s+sec")
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

    -- This matches DoT patterns like: "12 Arcane damage over 9 sec"
    -- It looks for a number, optionally with commas, followed by a damage type, "damage over" and then another number.
    local damageStr, secondsStr = text:match("([%d,]+)%s+%S+%s+damage%s+over%s+(%d+)")

    -- In some tooltips, "damage" might not be preceded by a type, or the text might vary slightly.
    -- Let's provide a fallback pattern for just "X damage over Y" if the first fails.
    if not (damageStr and secondsStr) then
        damageStr, secondsStr = text:match("([%d,]+)%s+damage%s+over%s+(%d+)")
    end

    -- print(damageStr);
    if damageStr and secondsStr then
        -- Remove commas from large numbers
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

    -- Find the cast time first, e.g., "1.5 sec cast"
    local castTimeStr = text:match("([%d%.]+)%s+sec%s+cast")
    if castTimeStr then
        timeDivisor = tonumber(castTimeStr)
    end

    -- If no cast time, check for a cooldown, e.g., "8 sec cooldown"
    if not timeDivisor then
        local cooldownStr = text:match("([%d%.]+)%s+sec%s+cooldown")
        if cooldownStr then
            timeDivisor = tonumber(cooldownStr)
        end
    end

    -- If no cast time and no cooldown, check if it's "Instant" (assume 1.5s GCD)
    if not timeDivisor then
        -- Usually it's just "Instant" in the tooltip
        if text:match("Instant") then
            timeDivisor = 1.5
        end
    end

    if not timeDivisor or timeDivisor <= 0 then
        return nil, nil
    end

    -- Look for range damage: "12 to 15 Nature damage"
    local minDmgStr, maxDmgStr = text:match("([%d,]+)%s+to%s+([%d,]+)%s+%S+%s+damage")
    if not (minDmgStr and maxDmgStr) then
        -- Fallback for no damage type: "12 to 15 damage"
        minDmgStr, maxDmgStr = text:match("([%d,]+)%s+to%s+([%d,]+)%s+damage")
    end

    -- Return direct DPS, direct total, and the time divisor (cast/cooldown/GCD)
    if minDmgStr and maxDmgStr then
        local minDmg = tonumber((minDmgStr:gsub(",", "")))
        local maxDmg = tonumber((maxDmgStr:gsub(",", "")))
        if minDmg and maxDmg then
            local avgDmg = (minDmg + maxDmg) / 2
            return avgDmg / timeDivisor, avgDmg, timeDivisor
        end
    end

    -- Look for flat damage: "Causes 15 Nature damage" or "15 Nature damage"
    local flatDmgStr = text:match("Causes%s+([%d,]+)%s+%S+%s+damage")
    if not flatDmgStr then
        flatDmgStr = text:match("Causes%s+([%d,]+)%s+damage")
    end

    if flatDmgStr then
        local flatDmg = tonumber((flatDmgStr:gsub(",", "")))
        if flatDmg then
            return flatDmg / timeDivisor, flatDmg, timeDivisor
        end
    end

    return nil, nil, nil
end

GameTooltip:HookScript("OnTooltipSetSpell", function(tooltip)
    local _, spellID = tooltip:GetSpell()
    if spellID then
        local tooltipName = tooltip:GetName()
        local numLines = tooltip:NumLines()

        -- Combine all lines of the tooltip into a single string
        local fullText = ""

        -- Start at 2 to skip the spell's title (TextLeft1)
        for i = 2, numLines do
            local fontString = _G[tooltipName .. "TextLeft" .. i]
            if fontString then
                local text = fontString:GetText()
                if text then
                    -- Append text with a space to ensure words aren't squished together
                    fullText = fullText .. " " .. text
                end
            end
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
            -- Let's make it yellow/orange to show it's separate from DPS
            tooltip:AddLine(string.format("Est. Total Damage: %d", totalEstimatedDamage), 1.0, 0.8, 0.2)

            -- If we have both direct and DoT components, show a combined cycle DPS
            if directTotal and dotTotal and totalEstimatedTime > 0 then
                local combinedDps = totalEstimatedDamage / totalEstimatedTime
                tooltip:AddLine(string.format("Est. Cycle DPS: %.1f", combinedDps), 1.0, 0.5, 0.0)
            end
        end

        if directDps or dotDps or hasTotal then
            tooltip:Show()
        end
    end
end)
