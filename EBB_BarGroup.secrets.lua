local ELKBUFFBARS, private = ...
local ElkBuffBars = private.addon

local ipairs				= ipairs
local pairs					= pairs

local table_insert          = table.insert
local table_remove          = table.remove
local table_sort            = table.sort
local table_wipe            = table.wipe

local DATA_DEMO = {
    index           = -1,
    auraid          = nil,
    spellid         = nil,
    name            = "Blessing of Demonstration",
    realname        = "Blessing of Demonstration",
    rank            = 23,
    type            = "FAKE",
    realtype        = "FAKE",
    debufftype      = nil,
    expires         = true,
    expirytime      = 817,
    timemax         = 1200,
    timeMod         = 0,
    charges         = 5,
    maxcharges      = 5,
    icon            = [[Interface\Icons\INV_Misc_QuestionMark]],
    ismine          = true,
    casterName      = "Buffbot",
    casterClass     = "PRIEST",
    canStealOrPurge = false,
    raw             = nil,
}

local prototype = {}
local prototype_mt = {__index = prototype}

function prototype:MarkPending(flag)
    self[flag] = true
end

function prototype:IsCombatLiveUpdateGroup()
    local t = self.layout and self.layout.filter and self.layout.filter.type
    return t and not t.TENCH and not t.TRACKING
end

function prototype:FlushPending()
    if InCombatLockdown() then
        return
    end

    -- consume flags first to avoid accidental loops
    local doData = self.pendingFullData
    local doBars = self.pendingUpdateBars
    local doLayout = self.pendingSetLayout
    local doPos = self.pendingSetPosition
    local doAnchor = self.pendingUpdateAnchor

    self.pendingFullData = false
    self.pendingUpdateBars = false
    self.pendingSetLayout = false
    self.pendingSetPosition = false
    self.pendingUpdateAnchor = false

    -- safest practical order for this addon
    if doData then
        self:UpdateData()
        return
    end

    if doBars then
        self:UpdateBars()
    end
    if doLayout then
        self:SetLayout()
    end
    if doPos then
        self:SetPosition()
    end
    if doAnchor then
        self:UpdateAnchor()
    end
end

function ElkBuffBars:NewBarGroup()
    local group = setmetatable({}, prototype_mt)

    group.bars = {}
    group.data = {}
    group.frames = {}

    -- deferred structural work flags
    group.pendingUpdateBars = false
    group.pendingSetLayout = false
    group.pendingSetPosition = false
    group.pendingUpdateAnchor = false
    group.pendingFullData = false

    local container = CreateFrame("button", nil, UIParent)
    container:SetFrameStrata("BACKGROUND")
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    group.frames.container = container

    return group
end

function prototype:Reset()
    self.frames.container:ClearAllPoints()
    self.frames.container:Hide()
    for k, v in pairs(self.bars) do
        ElkBuffBars:RecycleBar(v)
        self.bars[k] = nil
    end

    local data = self.data
    for k in pairs(data) do
        data[k] = nil
    end

    self.layout = nil
end

function prototype:GetContainer()
    return self.frames.container
end

function prototype:SetLayout(layout)
    if InCombatLockdown() then
        if layout then
            self.layout = layout
        end
        self:MarkPending("pendingSetLayout")
        return
    end

    if layout then
        self.layout = layout
    else
        layout = self.layout
        if not layout then
            return
        end
    end

    for _, bar in ipairs(self.bars) do
        bar:UpdateLayout(layout.bars)
    end
    if layout.bars.clickthrough then
        self.frames.container:EnableMouse(false)
    else
        self.frames.container:EnableMouse(true)
    end
    self.frames.container:SetAlpha(layout.alpha)
    self.frames.container:SetScale(layout.scale)
    self:UpdateAnchor()
    self:UpdateBarPositions()
end

function prototype:SetPosition()
    if InCombatLockdown() then
        self:MarkPending("pendingSetPosition")
        return
    end

    local layout = self.layout
    self.frames.container:ClearAllPoints()
    if layout.stickto then
        self.frames.container:SetPoint((layout.growup and "BOTTOM" or "TOP")..(layout.stickside or ""), ElkBuffBars.bargroups[layout.stickto]:GetContainer(), (layout.growup and "TOP" or "BOTTOM")..(layout.stickside or ""), 0, layout.growup and ElkBuffBars.db.profile.groupspacing or -ElkBuffBars.db.profile.groupspacing)
    elseif layout.x and layout.y then
        self.frames.container:SetPoint(layout.growup and "BOTTOMLEFT" or "TOPLEFT", UIParent, "BOTTOMLEFT", layout.x, layout.y)
    else
        self.frames.container:SetPoint("CENTER", UIParent, "CENTER")
        self:ToggleConfigMode(true)
    end
end

local anchor_backdrop = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = false, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right =5, top = 5, bottom = 5 },
}
function prototype:ToggleConfigMode(enabled)
    if enabled == nil then
        enabled = not self.layout.configmode
    end
    if enabled then
        self.layout.configmode = true
        self:UpdateAnchor()
    else
        self.layout.configmode = false
        self:UpdateAnchor()
    end
end

function prototype:UpdateAnchor()
    if InCombatLockdown() then
        self:MarkPending("pendingUpdateAnchor")
        return
    end

    local show = self.layout.anchorshown or self.layout.configmode
    if show then
        if not self.frames.anchor then
            self.frames.anchor = CreateFrame("Button", nil, self.frames.container, BackdropTemplateMixin and "BackdropTemplate")
            self.frames.anchor:SetBackdrop(anchor_backdrop)
            self.frames.anchor:SetHeight(25)
            self.frames.anchortext = self.frames.anchor:CreateFontString(nil, "OVERLAY")
            self.frames.anchortext:SetFontObject(GameFontNormalSmall)
            self.frames.anchortext:ClearAllPoints()
            self.frames.anchortext:SetTextColor(1, 1, 1, 1)
            self.frames.anchortext:SetPoint("CENTER", self.frames.anchor, "CENTER")
            self.frames.anchortext:SetJustifyH("CENTER")
            self.frames.anchortext:SetJustifyV("MIDDLE")

            self.frames.anchor.bargroup = self
            self.frames.anchor:SetScript("OnDragStart", function(this) this.bargroup:StartMoving() end)
            self.frames.anchor:SetScript("OnDragStop", function(this) this.bargroup:StopMoving() end)

            self.frames.anchor:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            self.frames.anchor:SetScript("OnClick", function(this, button) this.bargroup:OnClick(button) end)
        end

        if self.layout.configmode then
            self.frames.anchor:RegisterForDrag("LeftButton")
            if not self.frames.anchorgear_l then
                self.frames.anchorgear_l = self.frames.anchor:CreateTexture()
                self.frames.anchorgear_l:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
                self.frames.anchorgear_l:SetHeight(15)
                self.frames.anchorgear_l:SetWidth(15)
                self.frames.anchorgear_l:SetPoint("TOPLEFT", 5, -5)
            end
            if not self.frames.anchorgear_r then
                self.frames.anchorgear_r = self.frames.anchor:CreateTexture()
                self.frames.anchorgear_r:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
                self.frames.anchorgear_r:SetHeight(15)
                self.frames.anchorgear_r:SetWidth(15)
                self.frames.anchorgear_r:SetPoint("TOPRIGHT", -5, -5)
            end
            self.frames.anchorgear_l:Show()
            self.frames.anchorgear_r:Show()
        else
            self.frames.anchor:RegisterForDrag()
            if self.frames.anchorgear_l then
                self.frames.anchorgear_l:Hide()
            end
            if self.frames.anchorgear_r then
                self.frames.anchorgear_r:Hide()
            end
        end

        self.frames.anchor:SetWidth(self.layout.bars.width)
        self.frames.anchor:SetBackdropColor(self.layout.bars.barcolor[1], self.layout.bars.barcolor[2], self.layout.bars.barcolor[3], .5)
        self.frames.anchortext:SetText(self.layout.anchortext)
        self.frames.anchor:Show()
    else
        if self.frames.anchor then
            self.frames.anchor:Hide()
        end
    end

    self:UpdateBarPositions()
end

function prototype:StartMoving()
    self.frames.container:StartMoving()
end

function prototype:StopMoving()
    self.frames.container:StopMovingOrSizing()
    self.frames.container:SetUserPlaced(false) -- don't save in frame cache
    if not ElkBuffBars:StickGroup(self) then
        self.layout.x = self.frames.container:GetLeft()
        self.layout.y = self.layout.growup and self.frames.container:GetBottom() or self.frames.container:GetTop()
        self.frames.container:ClearAllPoints()
        self.frames.container:SetPoint(self.layout.growup and "BOTTOMLEFT" or "TOPLEFT", UIParent, "BOTTOMLEFT", self.layout.x, self.layout.y)
    end
end

function prototype:OnClick(button)
    if button == "LeftButton" then
        if IsAltKeyDown() then
            self:ToggleConfigMode()
        end
    elseif button == "RightButton" then
        if (self.layout.configmode) then
            self:ShowMenu()
        end
    end
end

function prototype:ShowMenu()
    -- @Phanx: TODO: menu?
    --Dewdrop:Open(self.frames.anchor, "children", ElkBuffBars:GetGroupOptions(self.layout.id))
    ElkBuffBars:OpenGroupOptions(self.layout.id)
end

-- updates position of bars (+ anchor) inside the container; sets container height
function prototype:UpdateBarPositions()
    local lastframe = nil
    local height = 0
    if self.layout.anchorshown or self.layout.configmode then
        self:UpdateBarPosition(self.frames.anchor, lastframe)
        lastframe = self.frames.anchor
        height = height + 25
    end
    for _, bar in ipairs(self.bars) do
        if height > 0 then
            height = height + self.layout.barspacing
        end
        self:UpdateBarPosition(bar:GetContainer(), lastframe)
        height = height + self.layout.bars.height
        lastframe = bar:GetContainer()
    end
    if height < 1 then height = 1 end -- add some height for empty groups in order to have them work as relative anchors
    self.frames.container:SetHeight(height)
    self.frames.container:SetWidth(self.layout.bars.width)
end

-- update the position of 'frame'; anchors it to 'relframe' if given
function prototype:UpdateBarPosition(frame, relframe)
    local growup = self.layout.growup
    frame:ClearAllPoints()
    if not relframe then
        frame:SetPoint(growup and "BOTTOM" or "TOP", self.frames.container, growup and "BOTTOM" or "TOP")
    else
        frame:SetPoint(growup and "BOTTOM" or "TOP", relframe, growup and "TOP" or "BOTTOM", 0, growup and self.layout.barspacing or -self.layout.barspacing)
    end
end

local function safeComparableTime(v)
    if v == nil then
        return nil
    end
    if issecretvalue and issecretvalue(v) then
        return nil
    end
    if canaccessvalue and not canaccessvalue(v) then
        return nil
    end
    return v
end

local function safeComparableString(v)
    if v == nil then
        return ""
    end
    if issecretvalue and issecretvalue(v) then
        return ""
    end
    if canaccessvalue and not canaccessvalue(v) then
        return ""
    end
    return v
end

local sorting = {
    name = function(a, b)
        return safeComparableString(a.name) < safeComparableString(b.name)
    end,

    timeleft = function(a, b)
        if not a.expires then
            if b.expires then
                return true
            end
            return safeComparableString(a.name) < safeComparableString(b.name)
        end
        if not b.expires then
            return false
        end

        local at = safeComparableTime(a.expirytime)
        local bt = safeComparableTime(b.expirytime)

        if at == nil then
            at = safeComparableTime(a.timemax)
        end
        if bt == nil then
            bt = safeComparableTime(b.timemax)
        end

        if at == nil then
            if bt ~= nil then
                return false
            end
            return safeComparableString(a.name) < safeComparableString(b.name)
        end
        if bt == nil then
            return true
        end

        if at == bt then
            return safeComparableString(a.name) < safeComparableString(b.name)
        end
        return at > bt
    end,

    timemax = function(a, b)
        if not a.expires then
            if b.expires then
                return true
            end
            return safeComparableString(a.name) < safeComparableString(b.name)
        end
        if not b.expires then
            return false
        end

        local at = safeComparableTime(a.timemax)
        local bt = safeComparableTime(b.timemax)

        if at == nil then
            if bt ~= nil then
                return false
            end
            return safeComparableString(a.name) < safeComparableString(b.name)
        end
        if bt == nil then
            return true
        end

        if at == bt then
            return safeComparableString(a.name) < safeComparableString(b.name)
        end
        return at > bt
    end,
}

local sortmap = {}
-- creates data for which bars will be created
function prototype:UpdateData(updated)
    if updated and not updated[self.layout.target] then return end
    local layout = self.layout
    local data = self.data
    for k in pairs(data) do
        data[k] = nil
    end

    local sortRule = Enum.UnitAuraSortRule.Default
    local sortDirection = Enum.UnitAuraSortDirection.Normal

    if self.layout.sorting == "name" then
        sortRule = Enum.UnitAuraSortRule.NameOnly
    elseif self.layout.sorting == "timeleft" then
        if InCombatLockdown() and self:IsCombatLiveUpdateGroup() then
            -- keep a stable order in combat; ExpirationOnly causes churn with secret/unreadable timers
            sortRule = Enum.UnitAuraSortRule.Default
            sortDirection = Enum.UnitAuraSortDirection.Normal
        else
            sortRule = Enum.UnitAuraSortRule.ExpirationOnly
            sortDirection = Enum.UnitAuraSortDirection.Reverse
        end
    end

    if layout.target == "player" then
        for _, v in pairs(ElkBuffBars.trackingdata) do
            if self:CheckFilter(v) then
                table_insert(data, v)
            end
        end
    end

    if InCombatLockdown() and self:IsCombatLiveUpdateGroup() then
        for _, v in pairs(ElkBuffBars.buffdata[layout.target]) do
            if self:CheckFilter(v) then
                table_insert(data, v)
            end
        end

        for _, v in pairs(ElkBuffBars.debuffdata[layout.target]) do
            if self:CheckFilter(v) then
                table_insert(data, v)
            end
        end
    else
        for _, v in pairs(ElkBuffBars.buffdata[layout.target]) do
            if self:CheckFilter(v) then
                sortmap[v.auraid] = v
            end
        end
        if next(sortmap) then
            local auraInstanceIDs = C_UnitAuras.GetUnitAuraInstanceIDs(layout.target, "HELPFUL", nil, sortRule, sortDirection)
            for _, v in pairs(auraInstanceIDs) do
                if sortmap[v] then
                    table_insert(data, sortmap[v])
                end
            end
        end
        table_wipe(sortmap)

        for _, v in pairs(ElkBuffBars.debuffdata[layout.target]) do
            if self:CheckFilter(v) then
                sortmap[v.auraid] = v
            end
        end
        if next(sortmap) then
            local auraInstanceIDs = C_UnitAuras.GetUnitAuraInstanceIDs(layout.target, "HARMFUL", nil, sortRule, sortDirection)
            for _, v in pairs(auraInstanceIDs) do
                if sortmap[v] then
                    table_insert(data, sortmap[v])
                end
            end
        end
        table_wipe(sortmap)
    end

    if layout.target == "player" then
        for _, v in pairs(ElkBuffBars.tenchdata) do
            if self:CheckFilter(v) then
                table_insert(data, v)
            end
        end
    end

    if InCombatLockdown() and self:IsCombatLiveUpdateGroup() then
        if self.layout.sorting == "name" and sorting.name then
            table_sort(data, sorting.name)
        elseif self.layout.sorting == "timeleft" and sorting.timeleft then
            table_sort(data, sorting.timeleft)
        elseif self.layout.sorting == "timemax" and sorting.timemax then
            table_sort(data, sorting.timemax)
        end
    end

    if self.layout.configmode then
        table_insert(data, DATA_DEMO)
    end
    if self.layout.sorting == "timemax" and sorting.timemax and not (InCombatLockdown() and self:IsCombatLiveUpdateGroup()) then
        table_sort(data, sorting.timemax)
    end

    if InCombatLockdown() and not self:IsCombatLiveUpdateGroup() then
        self.pendingFullData = false
        self.pendingUpdateBars = true
        return
    end

    self:UpdateBars()
end

-- creates bars from data
function prototype:UpdateBars()
    if InCombatLockdown() and not self:IsCombatLiveUpdateGroup() then
        self:MarkPending("pendingUpdateBars")
        return
    end

    local bars = self.bars

    for i = 1, #self.data do
        if not bars[i] then
            bars[i] = ElkBuffBars:GetBar()
            bars[i]:UpdateLayout(self.layout.bars)
            bars[i]:SetParent(self)
        end
        bars[i]:UpdateData(self.data[i])
    end

    for i = #bars, #self.data + 1, -1 do
        ElkBuffBars:RecycleBar(bars[i])
        bars[i] = nil
    end

    self:UpdateBarPositions()
    self.frames.container:Show()

    for _, bar in ipairs(bars) do
        bar:GetContainer():Show()
    end
end

-- orders the bars to update the texts shown
function prototype:UpdateText()
    for _, bar in ipairs(self.bars) do
        bar:UpdateText()
    end
end

-- orders the bars to update the time shown
function prototype:UpdateTimeleft()
    for _, bar in ipairs(self.bars) do
        bar:UpdateTimeleft()
    end
end

-- checks for various filter settings
function prototype:CheckFilter(data)
    if not self.layout then
        return false
    end

    local filter = self.layout.filter

    if not filter.type[data.type] then
        return false
    end

    if filter.selfcast then
        local ismine
        if data.raw and data.raw.sourceUnit then
            local source = data.raw.sourceUnit
            ismine = UnitIsUnit(source, "player") or UnitIsUnit(source, "pet") or UnitIsUnit(source, "vehicle")
        else
            ismine = data.ismine
        end

        if (filter.selfcast == "blacklist" and ismine) or (filter.selfcast == "whitelist" and not ismine) then
            return false
        end
    end

    return true
end

function prototype:RecycleSABs()
    if not InCombatLockdown() then
        for _, v in pairs(self.bars) do
            v:RecycleSAB()
        end
    end
end
