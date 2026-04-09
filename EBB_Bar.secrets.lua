local ELKBUFFBARS, private = ...
local ElkBuffBars = private.addon

local LSM3 = LibStub("LibSharedMedia-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(ELKBUFFBARS)

local ipairs				= ipairs
local tonumber				= tonumber
local unpack				= unpack
local pcall					= pcall

local math_max				= math.max
local math_min				= math.min
local math_floor            = math.floor

local string_format			= string.format
local string_match			= string.match
local string_utf8len		= string.utf8len

local TIMELEFT_SECRET_PLACEHOLDER = "?"

local issecretvalue = issecretvalue or function() return false end
-- 12.x: false means addon code must not do arithmetic/compare on the value; pair with issecretvalue.
local canaccessvalue = canaccessvalue or function() return true end

--- Remaining time from C_UnitAuras duration objects may be a secret number; never use % / floor on those.
local function timeAmountMustUseBlizzardFormatter(t)
    if t == nil then
        return true
    end
    if issecretvalue(t) then
        return true
    end
    if not canaccessvalue(t) then
        return true
    end
    return false
end

local function getSafeTimeleftFromExpiry(data)
    local expiry = data.expirytime
    if expiry == nil then
        return nil
    end
    if issecretvalue(expiry) then
        return nil
    end
    if not canaccessvalue(expiry) then
        return nil
    end

    local t = math_max(0, expiry - GetTime())
    if data.timeMod and data.timeMod > 0 then
        t = t / data.timeMod
    end
    return t
end

local function resolveSafeTimeleft(currentValue, data, duration, elapsed)
    if data.type == "FAKE" then
        return data.expirytime or 0
    end

    if duration then
        local remaining = duration:GetRemainingDuration()
        if remaining ~= nil and not issecretvalue(remaining) and canaccessvalue(remaining) then
            if remaining > 0 then
                return remaining
            end
        end
    end

    local fallback = getSafeTimeleftFromExpiry(data)
    if fallback ~= nil then
        if fallback > 0 then
            return fallback
        end
    end

    if not issecretvalue(data.expires) and not data.expires then
        return nil
    end

    if currentValue ~= nil and currentValue > 0 then
        if elapsed and elapsed > 0 then
            return math_max(0, currentValue - elapsed)
        end
        return currentValue
    end

    local safeMax = data.timemax
    if safeMax ~= nil and not issecretvalue(safeMax) and canaccessvalue(safeMax) and safeMax > 0 then
        return safeMax
    end

    return nil
end

local function CopyBarData(dst, src)
    dst = dst or {}
    for k in pairs(dst) do
        dst[k] = nil
    end
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

-- Secret seconds cannot be passed to SecondsToTimeAbbrev either (it compares internally — see TimeUtil.lua).
local prototype = {}
local prototype_mt = {__index = prototype}


-- curve copied from Plater-Nameplates/Plater_Auras.lua for now
local DEBUFF_DISPLAY_COLOR_INFO = {
    [0] = DEBUFF_TYPE_NONE_COLOR,
    [1] = DEBUFF_TYPE_MAGIC_COLOR,
    [2] = DEBUFF_TYPE_CURSE_COLOR,
    [3] = DEBUFF_TYPE_DISEASE_COLOR,
    [4] = DEBUFF_TYPE_POISON_COLOR,
    [9] = DEBUFF_TYPE_BLEED_COLOR, -- enrage
    [11] = DEBUFF_TYPE_BLEED_COLOR,
}
local dispelColorCurve = C_CurveUtil.CreateColorCurve()
dispelColorCurve:SetType(Enum.LuaCurveType.Step)
for i, c in pairs(DEBUFF_DISPLAY_COLOR_INFO) do
    dispelColorCurve:AddPoint(i, c)
end


function ElkBuffBars:NewBar()
    local bar = setmetatable({}, prototype_mt)
    bar.frames = {}
    return bar
end

function prototype:Reset()
    local container = self.frames.container
    container:SetScript("OnUpdate", nil)
    container:Hide()
    container:ClearAllPoints()
    if not InCombatLockdown() then
        self:RecycleSAB()
    end
    self.layout = nil
    self.data = nil
    self.timeleft = nil
    self:SetParent()
end

function prototype:GetContainer()
    return self.frames.container
end

function prototype:SetParent(parent)
    if self.frames.container then
        self.frames.container:SetParent(parent and parent.frames.container or UIParent)
    end
    self.parent = parent
end

local playerunit = {
    pet = true,
    player = true,
    vehicle = true,
}

function prototype:OnClick(button)
    if button == "LeftButton" then
        if IsAltKeyDown() then
            self.parent:ToggleConfigMode()
        elseif IsControlKeyDown() then
            if (self.data.realtype == "BUFF"
             or self.data.realtype == "DEBUFF"
             or self.data.realtype == "TENCH") then
                ElkBuffBars:AddAuraToBlacklist(self.parent.layout.id, self.data.realtype, self.data.name)
            end
        elseif IsShiftKeyDown() then
            -- local activeWindow = ChatEdit_GetActiveWindow()
            -- if activeWindow then
            --     if not self.data.expires then
            --         activeWindow:Insert(self:GetDataString("NAMERANK"))
            --     else
            --         activeWindow:Insert(self:GetDataString("NAMERANK").." - "..string_format(self:GetTimeString(self.timeleft, self.layout.timeformat)))
            --     end
            -- end
        elseif self.data.realtype == "TRACKING" then
            if LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC then
                -- no tracking menu in Classic
                return
            end
            if GameTooltip:GetOwner() == self.frames.container then
                GameTooltip:Hide()
            end
            if MinimapCluster and MinimapCluster.Tracking then
                -- this breaks the original menu position :(
                -- local anchor = AnchorUtil.CreateAnchor("TOPRIGHT", self.frames.container, "BOTTOMLEFT", 0, 0);
                -- MinimapCluster.Tracking.Button:SetMenuAnchor(anchor)
                MinimapCluster.Tracking.Button:OpenMenu()
            else
                MiniMapTrackingButton:OpenMenu()
            end
        end
--~ 	elseif button == "RightButton" then
--~ 		if not playerunit[self.parent.layout.target] then return end
--~ 		if self.data.realtype == "BUFF" then
--~ 			CancelUnitBuff(self.parent.layout.target, self.data.index)
--~ 			ElkBuffBars:CancelPlayerAura(self.data.realname, self.data.icon)
--~ 		elseif self.data.realtype == "TENCH" then
--~ 			CancelItemTempEnchantment(self.data.index - 15)
--~ 			ElkBuffBars:CancelPlayerTEnch(self.data.index, self.data.icon)
--~ 		end
    end
end

function prototype:OnEnter()
    local realtype = self.data.realtype
    if self.layout.tooltipanchor == "default" then
        GameTooltip_SetDefaultAnchor(GameTooltip, self.frames.container)
    else
        GameTooltip:SetOwner(self.frames.container, self.layout.tooltipanchor)
    end

    if realtype == "BUFF" or realtype == "DEBUFF" then
        if realtype == "BUFF" then
            GameTooltip:SetUnitAura(self.parent.layout.target, self.data.index, "HELPFUL")
        else
            GameTooltip:SetUnitAura(self.parent.layout.target, self.data.index, "HARMFUL")
        end
        if (self.layout.tooltipcaster) then
            local classColor = RAID_CLASS_COLORS[self.data.casterClass]
            if classColor then
                GameTooltip:AddDoubleLine(L["TOOLTIP_CASTER"], self.data.casterName, nil, nil, nil, classColor.r, classColor.g, classColor.b)
            else
                GameTooltip:AddDoubleLine(L["TOOLTIP_CASTER"], self.data.casterName)
            end
            GameTooltip:Show()
        end
        return
    end

    if realtype == "TENCH" then
        if self.parent.layout.target ~= "player" then
            return
        end
        GameTooltip:SetInventoryItem("player", self.data.index)
        return
    end

    if realtype == "TRACKING" then
        if self.parent.layout.target ~= "player" then
            return
        end
        if LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC then
            -- only one tracking active
            GameTooltip:SetTrackingSpell()
            return
        end
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Tracking")
        local trackingData
        local count = C_Minimap.GetNumTrackingTypes()
        for id = 1, count do
            trackingData = C_Minimap.GetTrackingInfo(id)
            if trackingData.active then
                if trackingData.type == "spell" then
                    GameTooltip:AddLine("|T"..trackingData.texture..":0::::0.0625:0.9:0.0625:0.9|t |cffffffff"..trackingData.name)
                else
                    GameTooltip:AddLine("|T"..trackingData.texture..":0::::0:1:0:1|t |cffffffff"..trackingData.name)
                end
            end
        end
        GameTooltip:Show()
        return
    end
end

function prototype:OnLeave()
    GameTooltip:Hide()
end

function prototype:OnUpdate(elapsed)
    local frames = self.frames
    local data = self.data

    self.updateThrottle = (self.updateThrottle or 0) - elapsed
    if self.updateThrottle > 0 then
        return
    end
    self.updateThrottle = 0.05

    local duration
    if data.auraid and data.expires then
        duration = C_UnitAuras.GetAuraDuration(self.parent.layout.target, data.auraid)
    end

    local resolved = resolveSafeTimeleft(self.timeleft, data, duration, elapsed)
    if resolved ~= nil then
        self.timeleft = resolved
    end
    self:UpdateTimeleft()

    if frames.bar and frames.bar:IsShown() then
        local canUseDurationObject = false
        if duration then
            local remaining = duration:GetRemainingDuration()
            canUseDurationObject = remaining ~= nil and not issecretvalue(remaining) and canaccessvalue(remaining)
        end

        if canUseDurationObject then
            frames.bar:SetTimerDuration(duration, nil, Enum.StatusBarTimerDirection.RemainingTime)
        else
            local safeMax = data.timemax
            if safeMax ~= nil and not issecretvalue(safeMax) and canaccessvalue(safeMax) and safeMax > 0 and self.timeleft ~= nil then
                frames.bar:SetMinMaxValues(0, safeMax)
                frames.bar:SetValue(self.timeleft)
            end
        end
    end

    if not issecretvalue(data.expires) and not data.expires then
        frames.container:SetScript("OnUpdate", nil)
    end
end

function prototype:UpdateLayout(layout)
    if layout then
        self.layout = layout
    else
        layout = self.layout
        if not layout then
            return
        end
    end

    local frames = self.frames

-- container
    if not frames.container then
        frames.container = CreateFrame("button", nil, UIParent)
        frames.container:SetFrameStrata("BACKGROUND")
        frames.container.bar = self
--~ 		frames.container:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        frames.container:RegisterForClicks("LeftButtonUp")
        frames.container:SetScript("OnClick", function(this, button) this.bar:OnClick(button) end )
        frames.container:SetScript("OnEnter", function(this) this.bar:OnEnter() end )
        frames.container:SetScript("OnLeave", function(this) this.bar:OnLeave() end )
    end
    if layout.clickthrough then
        frames.container:EnableMouse(false)
    else
        frames.container:EnableMouse(true)
    end
    frames.container:SetHeight(layout.height)
    frames.container:SetWidth(layout.width)
--~ 	frames.container:SetAlpha(layout.alpha)
    local leftoffset = 0
    local rightoffset = 0

-- icon
    if layout.icon then
        if not frames.icon then
            frames.icon = frames.container:CreateTexture(nil, "BACKGROUND")
        end
        frames.icon:ClearAllPoints()
        frames.icon:SetHeight(layout.height)
        frames.icon:SetWidth(layout.height)
        if layout.icon == "LEFT" then
            leftoffset = layout.height
            frames.icon:SetPoint("LEFT", frames.container)

        end
        if layout.icon == "RIGHT" then
            rightoffset = -layout.height
            frames.icon:SetPoint("RIGHT", frames.container)

        end
        frames.icon:Show()
    else
        if frames.icon then frames.icon:Hide() end
    end

-- iconcount
    if layout.icon and layout.iconcount then
        if not frames.iconcount then
            frames.iconcount = frames.container:CreateFontString(nil, "OVERLAY")
        end
        frames.iconcount:ClearAllPoints()
        frames.iconcount:SetPoint(layout.iconcountanchor, frames.icon, layout.iconcountanchor, (string_match(layout.iconcountanchor, "LEFT") and 3) or (string_match(layout.iconcountanchor, "RIGHT") and -3) or 0, (string_match(layout.iconcountanchor, "TOP") and -3) or (string_match(layout.iconcountanchor, "BOTTOM") and 3) or 0)
        frames.iconcount:SetFont(LSM3:Fetch("font", layout.iconcountfont), layout.iconcountfontsize, "OUTLINE")
        frames.iconcount:SetTextColor(layout.iconcountcolor[1], layout.iconcountcolor[2], layout.iconcountcolor[3], 1)
        frames.iconcount:Show()
    else
        if frames.iconcount then frames.iconcount:Hide() end
    end

-- iconborder
    if layout.icon then
        if not frames.iconborder then
            frames.iconborder = frames.container:CreateTexture(nil, "OVERLAY")
        end
        frames.iconborder:ClearAllPoints()
        frames.iconborder:SetPoint("TOPLEFT", frames.icon)
        frames.iconborder:SetPoint("BOTTOMRIGHT", frames.icon)
        frames.iconborder:Show()
    else
        if frames.iconborder then frames.iconborder:Hide() end
    end

-- bar
    if layout.bgbar then
        if not frames.bgbar then
            frames.bgbar = frames.container:CreateTexture(nil, "BACKGROUND")
        end
        frames.bgbar:ClearAllPoints()
        frames.bgbar:SetPoint("TOPLEFT", frames.container, "TOPLEFT", leftoffset, 0)
        frames.bgbar:SetPoint("BOTTOMRIGHT", frames.container, "BOTTOMRIGHT", rightoffset, 0)
        frames.bgbar:SetTexture(LSM3:Fetch("statusbar", layout.bartexture))
        frames.bgbar:Show()
    else
        if frames.bgbar then frames.bgbar:Hide() end
    end

    if layout.bar then
        if not frames.bar then
            frames.bar = CreateFrame("StatusBar", nil, frames.container)
            frames.bar:SetUsingParentLevel(true)
        end
        frames.bar:ClearAllPoints()
        frames.bar:SetPoint("TOPLEFT",      frames.container,   "TOPLEFT",      leftoffset,     0)
        frames.bar:SetPoint("BOTTOMRIGHT",  frames.container,   "BOTTOMRIGHT",  rightoffset,    0)
        frames.bar:SetStatusBarTexture(LSM3:Fetch("statusbar", layout.bartexture))
        frames.bar:SetFillStyle(layout.barright and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
        frames.bar:Show()
    else
        if frames.bar then frames.bar:Hide() end
    end

--[=[
    if layout.bar then
        if not frames.bar then
            frames.bar = frames.container:CreateTexture(nil, "ARTWORK")
        end
        frames.bar:ClearAllPoints()
        if layout.barright then
            frames.bar:SetPoint("TOPRIGHT",     frames.container,   "TOPRIGHT",     rightoffset,    0)
            frames.bar:SetPoint("BOTTOMRIGHT",  frames.container,   "BOTTOMRIGHT",  rightoffset,    0)
        else
            frames.bar:SetPoint("TOPLEFT",      frames.container,   "TOPLEFT",      leftoffset,     0)
            frames.bar:SetPoint("BOTTOMLEFT",   frames.container,   "BOTTOMLEFT",   leftoffset,     0)
        end
        frames.bar:SetWidth(0)
        frames.bar:SetTexture(LSM3:Fetch("statusbar", layout.bartexture))
        frames.bar:Show()
    else
        if frames.bar then frames.bar:Hide() end
    end
]=]

    if layout.bar and layout.spark then
        if not frames.spark then
            frames.spark = frames.container:CreateTexture(nil, "OVERLAY")
            frames.spark:SetTexture([[Interface\CastingBar\UI-CastingBar-Spark]])
            frames.spark:SetWidth(16)
            frames.spark:SetBlendMode("ADD")
        end
        frames.spark:ClearAllPoints()
        local bar_texture = frames.bar:GetStatusBarTexture()
        if layout.barright then
            frames.spark:SetPoint("TOP", bar_texture, "TOPLEFT", 0, 7)
            frames.spark:SetPoint("BOTTOM", bar_texture, "BOTTOMLEFT", 0, -7)
            frames.spark:SetTexCoord(1, 0, 0, 1)
        else
            frames.spark:SetPoint("TOP", bar_texture, "TOPRIGHT", 0, 7)
            frames.spark:SetPoint("BOTTOM", bar_texture, "BOTTOMRIGHT", 0, -7)
            frames.spark:SetTexCoord(0, 1, 0, 1)
        end
        frames.spark:Show()
    else
        if frames.spark then frames.spark:Hide() end
    end

    local padding = layout.padding
-- textTL
    if layout.textTL then
        if not frames.textTL then
            frames.textTL = frames.container:CreateFontString(nil, "OVERLAY")
        end
        local fontString = frames.textTL
        fontString:ClearAllPoints()
        fontString:SetPoint("TOPLEFT", frames.container, "TOPLEFT", leftoffset + padding, -padding)
        fontString:SetFontObject(GameFontNormal)
        fontString:SetFont(LSM3:Fetch("font", layout.textTLfont), layout.textTLfontsize, layout.textTLstyle)
        fontString:SetTextColor(layout.textTLcolor[1], layout.textTLcolor[2], layout.textTLcolor[3], 1)
        if not layout.textTR then
            fontString:SetPoint("TOPRIGHT", frames.container, "TOPRIGHT", rightoffset - padding, -padding)
            fontString:SetJustifyH(layout.textTLalign)
        else
            fontString:SetJustifyH("LEFT")
        end
        if not layout.textBL then
            fontString:SetPoint("BOTTOMLEFT", frames.container, "BOTTOMLEFT", leftoffset + padding, padding)
            fontString:SetJustifyV("MIDDLE")
        else
            fontString:SetJustifyV("TOP")
        end
        fontString:SetWordWrap(false)
        fontString:Show()
    else
        if frames.textTL then frames.textTL:Hide() end
    end

-- textTR
    if layout.textTR then
        if not frames.textTR then
            frames.textTR = frames.container:CreateFontString(nil, "OVERLAY")
        end
        local fontString = frames.textTR
        fontString:ClearAllPoints()
        fontString:SetPoint("TOPRIGHT", frames.container, "TOPRIGHT", rightoffset - padding, -padding)
        fontString:SetFontObject(GameFontNormal)
        fontString:SetFont(LSM3:Fetch("font", layout.textTRfont), layout.textTRfontsize, layout.textTRstyle)
        fontString:SetTextColor(layout.textTRcolor[1], layout.textTRcolor[2], layout.textTRcolor[3], 1)
        fontString:SetJustifyH("RIGHT")
        if not layout.textBL then
            fontString:SetPoint("BOTTOMRIGHT", frames.container, "BOTTOMRIGHT", rightoffset - padding, padding)
            fontString:SetJustifyV("MIDDLE")
        else
            fontString:SetJustifyV("TOP")
        end
        if layout.textTL then
            fontString:SetPoint("TOPLEFT", frames.textTL, "TOPLEFT", 10, 0)
        end
        fontString:SetWordWrap(false)
        fontString:Show()
    else
        if frames.textTR then frames.textTR:Hide() end
    end

-- textBL
    if layout.textTL and layout.textBL then
        if not frames.textBL then
            frames.textBL = frames.container:CreateFontString(nil, "OVERLAY")
        end
        local fontString = frames.textBL
        fontString:ClearAllPoints()
        fontString:SetPoint("BOTTOMLEFT", frames.container, "BOTTOMLEFT", leftoffset + padding, padding)
        fontString:SetFontObject(GameFontNormal)
        fontString:SetFont(LSM3:Fetch("font", layout.textBLfont), layout.textBLfontsize, layout.textBLstyle)
        fontString:SetTextColor(layout.textBLcolor[1], layout.textBLcolor[2], layout.textBLcolor[3], 1)
        if not layout.textBR then
            fontString:SetPoint("BOTTOMRIGHT", frames.container, "BOTTOMRIGHT", rightoffset - padding, padding)
            fontString:SetJustifyH(layout.textBLalign)
        else
            fontString:SetJustifyH("LEFT")
        end
        fontString:SetWordWrap(false)
        fontString:Show()
    else
        if frames.textBL then frames.textBL:Hide() end
    end

-- textBR
    if layout.textTL and layout.textBR then
        if not frames.textBR then
            frames.textBR = frames.container:CreateFontString(nil, "OVERLAY")
        end
        local fontString = frames.textBR
        fontString:ClearAllPoints()
        fontString:SetPoint("BOTTOMRIGHT", frames.container, "BOTTOMRIGHT", rightoffset - padding, padding)
        fontString:SetFontObject(GameFontNormal)
        fontString:SetFont(LSM3:Fetch("font", layout.textBRfont), layout.textBRfontsize, layout.textBRstyle)
        fontString:SetTextColor(layout.textBRcolor[1], layout.textBRcolor[2], layout.textBRcolor[3], 1)
        fontString:SetJustifyH("RIGHT")
        if layout.textBL then
            fontString:SetPoint("BOTTOMLEFT", frames.textBL, "BOTTOMLEFT", 10, 0)
        end
        fontString:SetWordWrap(false)
        fontString:Show()
    else
        if frames.textBR then frames.textBR:Hide() end
    end

-- precomputations
    self.barwidth_total = layout.width - leftoffset + rightoffset		-- rightoffset is <= 0
    self.barwidth_padded = self.barwidth_total - 2 * layout.padding
    self.trdwidth = self.barwidth_padded / 3

end

local updateFunc = function(self, elapsed) self.bar:OnUpdate(elapsed) end

function prototype:UpdateData(data)
    if data then
        local old = self.data
        if old then
            local oldTimed = not issecretvalue(old.expires) and old.expires
            local newTimed = not issecretvalue(data.expires) and data.expires

            local changedAuraKind =
                old.realtype ~= data.realtype or
                oldTimed ~= newTimed

            if changedAuraKind then
                self.timeleft = nil
            end
        else
            self.timeleft = nil
        end

        self.data = CopyBarData(self.data, data)
    else
        data = self.data
        if not data then
            return
        end
    end

    data = self.data

    local frames = self.frames
    local layout = self.layout
    local unit = self.parent.layout.target

    local duration
    if data.auraid and data.expires then
        duration = C_UnitAuras.GetAuraDuration(unit, data.auraid)
    end

    local resolved = resolveSafeTimeleft(self.timeleft, data, duration)
    if not issecretvalue(data.expires) and not data.expires then
        self.timeleft = nil
    elseif resolved ~= nil then
        self.timeleft = resolved
    end

    if layout.icon then
        frames.icon:SetTexture(data.icon)
        -- if data.canStealOrPurge then
        --     frames.iconborder:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Stealable")
        --     frames.iconborder:SetTexCoord(0, 1, 0, 1)
        --     frames.iconborder:SetBlendMode("ADD")
        --     frames.iconborder:Show()
        -- else
        if data.type == "DEBUFF" then
            frames.iconborder:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
            frames.iconborder:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
            if data.auraid and data.expires then
                local debuffcolor = C_UnitAuras.GetAuraDispelTypeColor(unit, data.auraid, dispelColorCurve) or DEBUFF_TYPE_NONE_COLOR
                frames.iconborder:SetVertexColor(debuffcolor:GetRGBA())
            else
                local debuffcolor = DEBUFF_TYPE_NONE_COLOR
                frames.iconborder:SetVertexColor(debuffcolor:GetRGBA())
            end
            frames.iconborder:SetBlendMode("BLEND")
            frames.iconborder:Show()
        elseif data.type == "TENCH" then
            frames.iconborder:SetTexture("Interface\\Buttons\\UI-TempEnchant-Border")
            frames.iconborder:SetTexCoord(0, 1, 0, 1)
            frames.iconborder:SetBlendMode("BLEND")
            frames.iconborder:Show()
        else
            frames.iconborder:Hide()
        end
        if layout.iconcount then
            if data.auraid then
                frames.iconcount:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, data.auraid))
                frames.iconcount:Show()
            elseif data.maxcharges and data.charges and data.charges > 0 then
                frames.iconcount:SetText(data.charges)
                frames.iconcount:Show()
            else
                frames.iconcount:Hide()
            end
        end
    end
    if layout.bar then
        if not issecretvalue(data.expires) and not data.expires then
            frames.bar:SetMinMaxValues(0, 1)
            frames.bar:SetValue(layout.timelessfull and 1 or 0)
            if frames.spark then
                frames.spark:Hide()
            end
        else
            local canUseDurationObject = false
            if duration then
                local remaining = duration:GetRemainingDuration()
                canUseDurationObject = remaining ~= nil and not issecretvalue(remaining) and canaccessvalue(remaining)
            end

            if canUseDurationObject then
                frames.bar:SetTimerDuration(duration, nil, Enum.StatusBarTimerDirection.RemainingTime)
            else
                local safeMax = data.timemax
                if safeMax ~= nil and not issecretvalue(safeMax) and canaccessvalue(safeMax) and safeMax > 0 and self.timeleft ~= nil then
                    frames.bar:SetMinMaxValues(0, safeMax)
                    frames.bar:SetValue(self.timeleft)
                end
            end

            if layout.spark then
                frames.spark:SetAlpha((self.timeleft ~= nil) and 1 or 0)
            end
        end
        local barcolorR, barcolorG, barcolorB, barcolorA = unpack(layout["barcolor"])
        if data.type == "DEBUFF" and layout.debufftypecolor then
            if data.auraid then
                local debuffcolor = C_UnitAuras.GetAuraDispelTypeColor(unit, data.auraid, dispelColorCurve) or DEBUFF_TYPE_NONE_COLOR
                barcolorR, barcolorG, barcolorB = debuffcolor:GetRGBA()
            else
                local debuffcolor = DEBUFF_TYPE_NONE_COLOR
                barcolorR, barcolorG, barcolorB = debuffcolor:GetRGBA()
            end
        end
        --frames.bar:SetStatusBarColor(barcolorR, barcolorG, barcolorB, barcolorA)
        frames.bar:GetStatusBarTexture():SetVertexColor(barcolorR, barcolorG, barcolorB, barcolorA)
    end
    if layout.bgbar then
        frames.bgbar:SetVertexColor(unpack(layout["barbgcolor"]))
    end

    if data.realtype == "FAKE" then -- no scripts for Blessing of Demonstration
        frames.container:SetScript("OnUpdate", nil)
    else
        self.updateThrottle = 0
        frames.container:SetScript("OnUpdate", updateFunc)
    end
    self:UpdateText()
    self:UpdateTimeleft()

    if not InCombatLockdown() then
        if not layout.clickthrough and playerunit[self.parent.layout.target]
          and (data.type == "BUFF" or data.type == "TENCH" or data.type == "TRACKING") then
            local SAB = self.SAB
            if not SAB then
                SAB = ElkBuffBars:GetSAB()
                SAB:SetPoint("TOPLEFT", frames.container, "TOPLEFT")
                SAB:SetPoint("BOTTOMRIGHT", frames.container, "BOTTOMRIGHT")
                SAB:SetFrameStrata(frames.container:GetFrameStrata())
                SAB:SetFrameLevel(frames.container:GetFrameLevel() + 1)
                SAB:SetAttribute("_bar", self)
                SAB:Show()
                frames.container:EnableMouse(false)
            end
            SAB:SetAttribute("unit", self.parent.layout.target)
            if data.type == "BUFF" then
                SAB:SetAttribute("*type2", "cancelaura")
                SAB:SetAttribute("*index2", data.index)
                SAB:SetAttribute("*target-slot2", nil);
            elseif data.type == "TENCH" then
                SAB:SetAttribute("*type2", "cancelaura")
                SAB:SetAttribute("*index2", nil)
                SAB:SetAttribute("*target-slot2", data.id);
            else -- data.type == "TRACKING"
                SAB:SetAttribute("*type2", "OnRightClickTracking")
                SAB:SetAttribute("*index2", nil)
                SAB:SetAttribute("*target-slot2", nil);
            end
            self.SAB = SAB
        else
            self:RecycleSAB()
        end
    end
end

function prototype:RecycleSAB()
    if self.SAB then
        ElkBuffBars:RecycleSAB(self.SAB)
        self.SAB = nil
        if self.layout.clickthrough then
            self.frames.container:EnableMouse(false)
        else
            self.frames.container:EnableMouse(true)
        end
    end
end

local romandigits = {	{["r"] = "M",  ["a"] = 1000},
                        {["r"] = "CM", ["a"] =  900},
                        {["r"] = "D",  ["a"] =  500},
                        {["r"] = "CD", ["a"] =  400},
                        {["r"] = "C",  ["a"] =  100},
                        {["r"] = "XC", ["a"] =   90},
                        {["r"] = "L",  ["a"] =   50},
                        {["r"] = "XL", ["a"] =   40},
                        {["r"] = "X",  ["a"] =   10},
                        {["r"] = "IX", ["a"] =    9},
                        {["r"] = "V",  ["a"] =    5},
                        {["r"] = "IV", ["a"] =    4},
                        {["r"] = "I",  ["a"] =    1}
                    }

local arabic_to_roman = setmetatable({}, {__index=function(self,arabic)
    arabic = tonumber(arabic)
    if not arabic then
        return nil
    end

    local original = arabic
    local roman = ""
    for i, v in ipairs(romandigits) do
        while arabic >= v.a do
            arabic = arabic - v.a
            roman = roman .. v.r
        end
    end

    self[original] = roman
    return roman
end})

function prototype:GetDataString(datatype)
    local charges = "" --self.data.maxcharges and self.data.charges and self.data.charges > 0 and " x"..self.data.charges or ""
    if datatype == "NAME" then return self:GetNameString() end
    if datatype == "NAMERANK" then return self:GetNameString()..(self.data.rank and (" "..arabic_to_roman[self.data.rank]) or "") end
    if datatype == "NAMECOUNT" then return self:GetNameString()..charges end
    if datatype == "NAMERANKCOUNT" then return self:GetNameString()..(self.data.rank and (" "..arabic_to_roman[self.data.rank]) or "")..charges end
    if datatype == "RANK" then return self.data.rank and arabic_to_roman[self.data.rank] or "" end
    if datatype == "COUNT" then return charges end
    if datatype == "TIMELEFT" then
        local fmt, a, b, c = self:GetTimeString(self.timeleft, self.layout.timeformat, self.layout.timeFraction)
        if fmt == nil or fmt == "" then
            return ""
        end
        if a ~= nil then
            return string_format(fmt, a, b, c)
        end
        return fmt
    end
    if datatype == "DEBUFFTYPE" then return self.data.debufftype end
    if datatype == "CASTER" then
        local classColor = RAID_CLASS_COLORS[self.data.casterClass]
        if classColor then
            return "|c"..classColor.colorStr..self.data.casterName.."|r"
        else
            return self.data.casterName
        end
    end
    return "???"
end

function prototype:GetNameString()
    local layout = self.layout
    local name = self.data.name
    -- Secret aura names cannot be measured, used as table keys, or passed through utf8.lua.
    if issecretvalue(name) then
        return name
    end
    if layout.abbreviate_name > 0 and string_utf8len(name) > layout.abbreviate_name then
        return ElkBuffBars.ShortName[name]
    else
        return name
    end
end

local function getTimeFormatCondensed(timeAmount, timeFraction)
    local seconds = timeAmount % 60 or 0
    local minutes = math_floor(timeAmount / 60) % 60
    local hours = math_floor(timeAmount / 3600)
    if (hours > 0) then
        return "%dh %dm", hours, minutes
    elseif (minutes > 0) then
        return "%dm %ds", minutes, seconds
    else
        return (timeFraction and "%.1fs" or "%ds"), seconds
    end
end

local function getTimeFormatClock(timeAmount, timeFraction)
    local seconds = timeAmount % 60 or 0
    local minutes = math_floor(timeAmount / 60) % 60
    local hours = math_floor(timeAmount / 3600)
    if (hours > 0) then
        return "%d:%02d:%02d", hours, minutes, seconds
    elseif (minutes > 0) then
        return "%d:%02d", minutes, seconds
    else
        return (timeFraction and "%.1fs" or "%ds"), seconds
    end
end

function prototype:GetTimeString(timeAmount, timeFormat, timeFraction)
    local exp = self.data.expires
    if not issecretvalue(exp) and not exp then
        return "", 0
    end

    if timeAmount == nil then
        return TIMELEFT_SECRET_PLACEHOLDER, 0
    end

    -- Opaque seconds: no Lua math and no SecondsToTimeAbbrev (it compares secrets internally).
    if timeAmountMustUseBlizzardFormatter(timeAmount) then
        return TIMELEFT_SECRET_PLACEHOLDER, 0
    end

    if timeFormat == "DEFAULT" then
        local ok, s = pcall(SecondsToTimeAbbrev, timeAmount)
        if ok and s and s ~= "" then
            return s
        end
        return string.format("%.1fs", timeAmount)
    end
    if timeFormat == "CLOCK" then
        local ok, a, b, c, d = pcall(getTimeFormatClock, timeAmount, timeFraction)
        if ok then
            return a, b, c, d
        end
        local ok2, s = pcall(SecondsToTimeAbbrev, timeAmount)
        if ok2 and s and s ~= "" then
            return s, 0
        end
        return TIMELEFT_SECRET_PLACEHOLDER, 0
    end
    if timeFormat == "CONDENSED" then
        local ok, a, b, c, d = pcall(getTimeFormatCondensed, timeAmount, timeFraction)
        if ok then
            return a, b, c, d
        end
        local ok2, s = pcall(SecondsToTimeAbbrev, timeAmount)
        if ok2 and s and s ~= "" then
            return s, 0
        end
        return TIMELEFT_SECRET_PLACEHOLDER, 0
    end
    return "???"
end

function prototype:UpdateText()
    local frames = self.frames
    local layout = self.layout
    if layout.textTL then
        frames.textTL:SetText(self:GetDataString(layout.textTL))
    end
    if layout.textTR then
        frames.textTR:SetText(self:GetDataString(layout.textTR))
    end
    if layout.textTL and layout.textBL then
        frames.textBL:SetText(self:GetDataString(layout.textBL))
    end
    if layout.textTL and layout.textBR then
        frames.textBR:SetText(self:GetDataString(layout.textBR))
    end
    -- self:UpdateTextWidth()
end

function prototype:UpdateTimeleft()
    local frames = self.frames
    local layout = self.layout

    local fmt, a, b, c = self:GetTimeString(self.timeleft, layout.timeformat, layout.timeFraction)
    local textAlpha = (fmt ~= nil and fmt ~= "") and 1 or 0

    local function ApplyTime(fs)
        if not fs then
            return
        end
        if not fmt or fmt == "" then
            fs:SetText("")
            fs:SetAlpha(0)
            return
        end
        if a ~= nil then
            fs:SetFormattedText(fmt, a, b, c)
        else
            fs:SetText(fmt)
        end
        fs:SetAlpha(textAlpha)
    end

    if layout.textTL == "TIMELEFT" then
        ApplyTime(frames.textTL)
    end
    if layout.textTR == "TIMELEFT" then
        ApplyTime(frames.textTR)
    end
    if layout.textBL == "TIMELEFT" then
        ApplyTime(frames.textBL)
    end
    if layout.textBR == "TIMELEFT" then
        ApplyTime(frames.textBR)
    end
end

function prototype:UpdateTextWidth()
    local frames = self.frames
    local layout = self.layout
    local trdwidth = self.trdwidth
    if layout.textTL and layout.textTR then
        local TLwidth = frames.textTL:GetStringWidth() + 5
        local TRwidth = frames.textTR:GetStringWidth() + 5
        if TLwidth < trdwidth then
            frames.textTL:SetWidth(TLwidth)
        elseif TRwidth < trdwidth then
            frames.textTL:SetWidth(self.barwidth_padded - TRwidth)
        else
            frames.textTL:SetWidth(trdwidth + (TLwidth * trdwidth)/(TLwidth + TRwidth))
        end
    end
    if layout.textTL and layout.textBL and layout.textBR then
        local BLwidth = frames.textBL:GetStringWidth() + 5
        local BRwidth = frames.textBR:GetStringWidth() + 5
        if BLwidth < trdwidth then
            frames.textBL:SetWidth(BLwidth)
        elseif BRwidth < trdwidth then
            frames.textBL:SetWidth(self.barwidth_padded - BRwidth)
        else
            frames.textBL:SetWidth(trdwidth + (BLwidth * trdwidth)/(BLwidth + BRwidth))
        end
    end
end
