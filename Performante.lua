-- Performante
-- Vanilla WoW 1.12.1 / Lua 5.0.3
-- 0.4.1: bounded temporary event capture with hitch/event correlation alongside accepted 0.3 diagnostics.

local ADDON_NAME = "Performante"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")
local L = Performante_L

local Performante = CreateFrame("Frame", "PerformanteFrame", UIParent)
local driver = CreateFrame("Frame", "PerformanteDriver", UIParent)
local captureFrame = CreateFrame("Frame", "PerformanteCaptureFrame", UIParent)

local CAPTURE_BUCKETS = 10
local CAPTURE_BUCKET_SECONDS = 0.5
local CAPTURE_MAX_SECONDS = 30
local CAPTURE_EVENTS = {
    "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE", "BAG_UPDATE",
    "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_MISSES",
    "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS", "CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES",
    "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
    "CHAT_MSG_COMBAT_PARTY_HITS", "CHAT_MSG_COMBAT_PARTY_MISSES",
    "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES",
    "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF", "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_BUFF", "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS", "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS", "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
    "CHAT_MSG_SPELL_SELF_BUFF", "CHAT_MSG_SPELL_SELF_DAMAGE",
    "PLAYER_TARGET_CHANGED", "SPELLCAST_DELAYED", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED",
    "SPELLCAST_START", "SPELLCAST_STOP", "UNIT_AURA", "UNIT_HEALTH", "UNIT_MANA"
}
local captureEntries = {}
local captureActive = false
local captureClock = 0
local captureTotal = 0
local captureAutoStopped = false
local captureBucketTotals = {}
local captureBucketStamps = {}
local correlatedHitches = 0
local isolatedHitches = 0
local worstCorrelatedHitchMs = 0
local worstCorrelationEventCount = 0
local worstCorrelationBaselineCount = 0
local worstCorrelationTopNames = { "", "", "" }
local worstCorrelationTopCounts = { 0, 0, 0 }

local counts = {}
local sorted = {}
local inboundMessages = 0
local outboundMessages = 0
local commsDirty = true
local commsClock = 0
local RATE_BUCKETS = 5

local paused = false
local currentView = "comms"
local monitoringReady = false

local function ClearCaptureData()
    local i
    local j
    captureClock = 0
    captureTotal = 0
    captureAutoStopped = false
    correlatedHitches = 0
    isolatedHitches = 0
    worstCorrelatedHitchMs = 0
    worstCorrelationEventCount = 0
    worstCorrelationBaselineCount = 0
    for j = 1, CAPTURE_BUCKETS do
        captureBucketTotals[j] = 0
        captureBucketStamps[j] = -1
    end
    for j = 1, 3 do
        worstCorrelationTopNames[j] = ""
        worstCorrelationTopCounts[j] = 0
    end
    for i = 1, table.getn(CAPTURE_EVENTS) do
        local entry = captureEntries[CAPTURE_EVENTS[i]]
        if not entry then
            entry = { count = 0, buckets = {}, stamps = {} }
            captureEntries[CAPTURE_EVENTS[i]] = entry
        end
        entry.count = 0
        for j = 1, CAPTURE_BUCKETS do
            entry.buckets[j] = 0
            entry.stamps[j] = -1
        end
    end
end

local function StopCapture(autoStopped)
    local i
    if captureActive then
        for i = 1, table.getn(CAPTURE_EVENTS) do
            captureFrame:UnregisterEvent(CAPTURE_EVENTS[i])
        end
    end
    captureActive = false
    captureAutoStopped = autoStopped and true or false
end

local function StartCapture()
    local i
    StopCapture(false)
    ClearCaptureData()
    for i = 1, table.getn(CAPTURE_EVENTS) do
        captureFrame:RegisterEvent(CAPTURE_EVENTS[i])
    end
    captureActive = true
end

local function RecordCapturedEvent(eventName)
    if not captureActive or paused or not monitoringReady then return end
    local entry = captureEntries[eventName]
    if not entry then return end
    entry.count = entry.count + 1
    captureTotal = captureTotal + 1
    local bucket = math.floor(captureClock / CAPTURE_BUCKET_SECONDS)
    local slot = math.mod(bucket, CAPTURE_BUCKETS) + 1
    if entry.stamps[slot] ~= bucket then
        entry.stamps[slot] = bucket
        entry.buckets[slot] = 0
    end
    if captureBucketStamps[slot] ~= bucket then
        captureBucketStamps[slot] = bucket
        captureBucketTotals[slot] = 0
    end
    entry.buckets[slot] = entry.buckets[slot] + 1
    captureBucketTotals[slot] = captureBucketTotals[slot] + 1
end

local function CaptureRecentRate(entry)
    local bucket = math.floor(captureClock / CAPTURE_BUCKET_SECONDS)
    local sum = 0
    local i
    for i = 1, CAPTURE_BUCKETS do
        local stamp = entry.stamps[i]
        if stamp <= bucket and stamp > bucket - CAPTURE_BUCKETS then
            sum = sum + entry.buckets[i]
        end
    end
    return sum / (CAPTURE_BUCKETS * CAPTURE_BUCKET_SECONDS)
end

local function CaptureBucketTotal(bucket)
    if bucket < 0 then return 0 end
    local slot = math.mod(bucket, CAPTURE_BUCKETS) + 1
    if captureBucketStamps[slot] == bucket then
        return captureBucketTotals[slot]
    end
    return 0
end

local function CaptureEventWindowCount(entry, firstBucket, lastBucket)
    local sum = 0
    local bucket
    for bucket = firstBucket, lastBucket do
        if bucket >= 0 then
            local slot = math.mod(bucket, CAPTURE_BUCKETS) + 1
            if entry.stamps[slot] == bucket then
                sum = sum + entry.buckets[slot]
            end
        end
    end
    return sum
end

local function RecordHitchCorrelation(frameMs)
    if not captureActive or paused or frameMs <= 50 then return end

    -- Event handlers run between OnUpdate calls while captureClock still names the
    -- pre-advance bucket. Correlate that bucket plus its predecessor (1.0s trailing).
    -- Compare with the immediately preceding 1.0s pair; no future/symmetric window
    -- is invented because those events have not happened when the hitch is detected.
    local bucket = math.floor(captureClock / CAPTURE_BUCKET_SECONDS)
    local eventCount = CaptureBucketTotal(bucket) + CaptureBucketTotal(bucket - 1)
    local baselineCount = CaptureBucketTotal(bucket - 2) + CaptureBucketTotal(bucket - 3)
    local stormAssociated = false

    -- "Storm" is a local burst classification, not causation: require both a
    -- meaningful absolute increase and >=50% growth over the preceding window.
    if eventCount >= baselineCount + 10 and eventCount * 2 >= baselineCount * 3 then
        stormAssociated = true
        correlatedHitches = correlatedHitches + 1
    else
        isolatedHitches = isolatedHitches + 1
    end

    if frameMs > worstCorrelatedHitchMs then
        local i
        local ranked = {}
        worstCorrelatedHitchMs = frameMs
        worstCorrelationEventCount = eventCount
        worstCorrelationBaselineCount = baselineCount
        for i = 1, table.getn(CAPTURE_EVENTS) do
            local eventName = CAPTURE_EVENTS[i]
            local entry = captureEntries[eventName]
            local count = CaptureEventWindowCount(entry, bucket - 1, bucket)
            if count > 0 then
                table.insert(ranked, { name = eventName, count = count })
            end
        end
        table.sort(ranked, function(a, b)
            if a.count == b.count then return a.name < b.name end
            return a.count > b.count
        end)
        for i = 1, 3 do
            if ranked[i] then
                worstCorrelationTopNames[i] = ranked[i].name
                worstCorrelationTopCounts[i] = ranked[i].count
            else
                worstCorrelationTopNames[i] = ""
                worstCorrelationTopCounts[i] = 0
            end
        end
    end
end

local function CaptureStatus()
    local ranked = {}
    local i
    for i = 1, table.getn(CAPTURE_EVENTS) do
        local eventName = CAPTURE_EVENTS[i]
        local entry = captureEntries[eventName]
        if entry and entry.count > 0 then
            table.insert(ranked, { name = eventName, count = entry.count, rate = CaptureRecentRate(entry) })
        end
    end
    table.sort(ranked, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
    local state = captureActive and "ACTIVE" or "STOPPED"
    if captureAutoStopped then state = "STOPPED (30s limit)" end
    DEFAULT_CHAT_FRAME:AddMessage("Performante capture: " .. state .. ", " .. string.format("%.1f", captureClock) .. "s, " .. captureTotal .. " events")
    local limit = table.getn(ranked)
    if limit > 5 then limit = 5 end
    for i = 1, limit do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. ranked[i].name .. ": " .. ranked[i].count .. " (" .. string.format("%.1f/s", ranked[i].rate) .. ")")
    end
    DEFAULT_CHAT_FRAME:AddMessage("  >50ms hitch correlation: " .. correlatedHitches .. " burst-associated, " .. isolatedHitches .. " isolated")
    if worstCorrelatedHitchMs > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("  Worst captured hitch: " .. string.format("%.1f ms", worstCorrelatedHitchMs) .. ", events " .. worstCorrelationEventCount .. " vs prior " .. worstCorrelationBaselineCount)
        for i = 1, 3 do
            if worstCorrelationTopCounts[i] > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    " .. worstCorrelationTopNames[i] .. ": " .. worstCorrelationTopCounts[i])
            end
        end
    end
end

ClearCaptureData()

-- Five fixed one-second buckets per observed prefix, allocated only once.
local function RecordMessage(prefix, outbound)
    if paused or not monitoringReady then return end
    if not prefix or prefix == "" then prefix = "<no prefix>" end
    local entry = counts[prefix]
    if not entry then
        entry = { prefix = prefix, inbound = 0, outbound = 0, total = 0, buckets = {}, seconds = {} }
        counts[prefix] = entry
    end
    if outbound then
        entry.outbound = entry.outbound + 1
        outboundMessages = outboundMessages + 1
    else
        entry.inbound = entry.inbound + 1
        inboundMessages = inboundMessages + 1
    end
    entry.total = entry.total + 1
    local second = math.floor(commsClock)
    local slot = math.mod(second, RATE_BUCKETS) + 1
    if entry.seconds[slot] ~= second then
        entry.seconds[slot] = second
        entry.buckets[slot] = 0
    end
    entry.buckets[slot] = entry.buckets[slot] + 1
    commsDirty = true
end

local function RecentRate(entry)
    local second = math.floor(commsClock)
    local sum = 0
    local j
    for j = 1, RATE_BUCKETS do
        local stamp = entry.seconds[j]
        if stamp and stamp <= second and stamp > second - RATE_BUCKETS then
            sum = sum + entry.buckets[j]
        end
    end
    return sum / RATE_BUCKETS
end

local originalSendAddonMessage = SendAddonMessage
if originalSendAddonMessage then
    -- Native Vanilla API uses prefix, message, distribution, optional target.
    -- Never alter the message, call order, recipient or native return values.
    SendAddonMessage = function(prefix, message, distribution, target)
        RecordMessage(prefix, true)
        return originalSendAddonMessage(prefix, message, distribution, target)
    end
end
local uiElapsed = 0
local graphRedrawElapsed = 0

local currentFrameMs = 0
local worstFrameMs = 0
local hitch33 = 0
local hitch50 = 0
local hitch100 = 0
local hitch200 = 0

local currentMemoryKb = 0
local memoryBaselineKb = 0

local MAX_ROWS = 11

local GRAPH_SAMPLE_COUNT = 80
local GRAPH_SAMPLE_INTERVAL = 0.10
local GRAPH_REDRAW_INTERVAL = 0.20
local GRAPH_MAX_MS = 200
local GRAPH_HEIGHT = 150
local GRAPH_BASE_Y = -235
local GRAPH_BAR_START_X = 54
local GRAPH_BAR_STEP = 3
local GRAPH_BAR_WIDTH = 2

local graphSamples = {}
local graphWriteIndex = 0
local graphSampleCount = 0
local graphSampleElapsed = 0
local graphBucketWorstMs = 0

local commsWidgets = {}
local frameWidgets = {}
local graphWidgets = {}
local graphBars = {}

local i
for i = 1, GRAPH_SAMPLE_COUNT do
    graphSamples[i] = 0
end

local function AddWidget(group, widget)
    table.insert(group, widget)
    return widget
end

local function SetWindowShown(shown)
    if not PerformanteDB then
        PerformanteDB = {}
    end

    PerformanteDB.shown = shown

    if shown then
        Performante:Show()
    else
        Performante:Hide()
    end
end

local function RestoreWindowVisibility()
    if not PerformanteDB then
        PerformanteDB = {}
    end

    if PerformanteDB.shown == nil then
        PerformanteDB.shown = true
    end

    if PerformanteDB.shown then
        Performante:Show()
    else
        Performante:Hide()
    end
end

local function FormatMemory(kb)
    if kb >= 1024 then
        return string.format("%.1f MB", kb / 1024)
    end

    return string.format("%.0f KB", kb)
end

local function FormatMemoryDelta(kb)
    local sign = ""

    if kb > 0 then
        sign = "+"
    elseif kb < 0 then
        sign = "-"
        kb = -kb
    end

    return sign .. FormatMemory(kb)
end

local function ShowGroup(group, shown)
    local index
    for index = 1, table.getn(group) do
        if shown then
            group[index]:Show()
        else
            group[index]:Hide()
        end
    end
end

local function GraphY(ms)
    local clamped = ms
    if clamped < 0 then
        clamped = 0
    elseif clamped > GRAPH_MAX_MS then
        clamped = GRAPH_MAX_MS
    end

    return GRAPH_BASE_Y + ((clamped / GRAPH_MAX_MS) * GRAPH_HEIGHT)
end

Performante:SetWidth(330)
Performante:SetHeight(286)
Performante:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Performante:SetMovable(1)
Performante:EnableMouse(1)
Performante:RegisterForDrag("LeftButton")
Performante:SetFrameStrata("DIALOG")
Performante:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
Performante:SetBackdropColor(0, 0, 0, 0.90)

Performante:SetScript("OnDragStart", function()
    this:StartMoving()
end)

Performante:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
end)

local title = Performante:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -10)
title:SetText(L.TITLE .. " " .. (ADDON_VERSION or ""))

local closeButton = CreateFrame("Button", nil, Performante, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -2, -2)

local commsTab = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
commsTab:SetWidth(66)
commsTab:SetHeight(20)
commsTab:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -30)
commsTab:SetText(L.COMMS)

local frameTab = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
frameTab:SetWidth(82)
frameTab:SetHeight(20)
frameTab:SetPoint("LEFT", commsTab, "RIGHT", 4, 0)
frameTab:SetText(L.FRAMETIME)

local graphTab = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
graphTab:SetWidth(62)
graphTab:SetHeight(20)
graphTab:SetPoint("LEFT", frameTab, "RIGHT", 4, 0)
graphTab:SetText(L.GRAPH)

local pauseState = Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pauseState:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -34)
pauseState:SetWidth(72)
pauseState:SetJustifyH("RIGHT")
pauseState:SetText("")

local topDivider = Performante:CreateTexture(nil, "ARTWORK")
topDivider:SetTexture(1, 1, 1)
topDivider:SetAlpha(0.20)
topDivider:SetHeight(1)
topDivider:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -57)
topDivider:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -12, -57)

local prefixHeader = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
prefixHeader:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -65)
prefixHeader:SetText(L.PREFIX)

local headerSpecs = { { L.INBOUND, -165 }, { L.OUTBOUND, -115 }, { L.TOTAL, -65 }, { L.RATE, -16 } }
for i = 1, 4 do
    local h = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    h:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", headerSpecs[i][2], -65)
    h:SetWidth(i == 4 and 56 or 42)
    h:SetJustifyH("RIGHT")
    h:SetText(headerSpecs[i][1])
end

local commsDivider = AddWidget(commsWidgets, Performante:CreateTexture(nil, "ARTWORK"))
commsDivider:SetTexture(1, 1, 1)
commsDivider:SetAlpha(0.16)
commsDivider:SetHeight(1)
commsDivider:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -80)
commsDivider:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -12, -80)

local rows = {}
for i = 1, MAX_ROWS do
    local row = {}

    row.prefix = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    row.prefix:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -84 - ((i - 1) * 15))
    row.prefix:SetWidth(108)
    row.prefix:SetJustifyH("LEFT")
    row.prefix:SetText("")

    row.columns = {}
    local offsets = { -165, -115, -65, -16 }
    local j
    for j = 1, 4 do
        local col = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
        col:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", offsets[j], -84 - ((i - 1) * 15))
        col:SetWidth(j == 4 and 56 or 42)
        col:SetJustifyH("RIGHT")
        col:SetText("")
        row.columns[j] = col
    end

    rows[i] = row
end

local overflow = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
overflow:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -250)
overflow:SetText("")

local currentLabel = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
currentLabel:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -70)
currentLabel:SetWidth(145)
currentLabel:SetJustifyH("LEFT")

local worstLabel = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
worstLabel:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -70)
worstLabel:SetWidth(145)
worstLabel:SetJustifyH("RIGHT")

local memoryLabel = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
memoryLabel:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -96)
memoryLabel:SetWidth(302)
memoryLabel:SetJustifyH("LEFT")

local hitchTitle = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
hitchTitle:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -128)
hitchTitle:SetText(L.HITCHES)

local hitch33Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch33Label:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -150)
hitch33Label:SetWidth(140)
hitch33Label:SetJustifyH("LEFT")

local hitch50Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch50Label:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -150)
hitch50Label:SetWidth(140)
hitch50Label:SetJustifyH("RIGHT")

local hitch100Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch100Label:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -174)
hitch100Label:SetWidth(140)
hitch100Label:SetJustifyH("LEFT")

local hitch200Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch200Label:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -174)
hitch200Label:SetWidth(140)
hitch200Label:SetJustifyH("RIGHT")

local frameNote = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
frameNote:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -211)
frameNote:SetWidth(302)
frameNote:SetJustifyH("LEFT")
frameNote:SetText(L.GRAPH_HINT)

local graphNote = AddWidget(graphWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
graphNote:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -66)
graphNote:SetWidth(302)
graphNote:SetJustifyH("LEFT")
graphNote:SetText(L.GRAPH_NOTE)

local graphGuideValues = { 200, 100, 50, 33 }
for i = 1, table.getn(graphGuideValues) do
    local guideValue = graphGuideValues[i]

    local guide = AddWidget(graphWidgets, Performante:CreateTexture(nil, "BACKGROUND"))
    guide:SetTexture(1, 1, 1)
    guide:SetAlpha(guideValue == 200 and 0.18 or 0.12)
    guide:SetHeight(1)
    guide:SetPoint("TOPLEFT", Performante, "TOPLEFT", 48, GraphY(guideValue))
    guide:SetWidth(258)

    local guideLabel = AddWidget(graphWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    guideLabel:SetPoint("RIGHT", guide, "LEFT", -4, 0)
    guideLabel:SetWidth(30)
    guideLabel:SetJustifyH("RIGHT")
    guideLabel:SetText(guideValue)
end

local graphBase = AddWidget(graphWidgets, Performante:CreateTexture(nil, "BACKGROUND"))
graphBase:SetTexture(1, 1, 1)
graphBase:SetAlpha(0.18)
graphBase:SetHeight(1)
graphBase:SetPoint("TOPLEFT", Performante, "TOPLEFT", 48, GRAPH_BASE_Y)
graphBase:SetWidth(258)

local graphZeroLabel = AddWidget(graphWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
graphZeroLabel:SetPoint("RIGHT", graphBase, "LEFT", -4, 0)
graphZeroLabel:SetWidth(30)
graphZeroLabel:SetJustifyH("RIGHT")
graphZeroLabel:SetText("0")

for i = 1, GRAPH_SAMPLE_COUNT do
    local bar = AddWidget(graphWidgets, Performante:CreateTexture(nil, "ARTWORK"))
    bar:SetTexture(1, 1, 1)
    bar:SetAlpha(0.75)
    bar:SetWidth(GRAPH_BAR_WIDTH)
    bar:SetHeight(1)
    bar:SetPoint("BOTTOMLEFT", Performante, "TOPLEFT", GRAPH_BAR_START_X + ((i - 1) * GRAPH_BAR_STEP), GRAPH_BASE_Y)
    graphBars[i] = bar
end

local graphOldLabel = AddWidget(graphWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
graphOldLabel:SetPoint("TOPLEFT", Performante, "TOPLEFT", 48, -241)
graphOldLabel:SetText("-8s")

local graphNowLabel = AddWidget(graphWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
graphNowLabel:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -24, -241)
graphNowLabel:SetText(L.NOW)

local resetButton = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
resetButton:SetWidth(72)
resetButton:SetHeight(20)
resetButton:SetPoint("BOTTOMLEFT", Performante, "BOTTOMLEFT", 12, 10)
resetButton:SetText(L.RESET)

local pauseButton = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
pauseButton:SetWidth(72)
pauseButton:SetHeight(20)
pauseButton:SetPoint("LEFT", resetButton, "RIGHT", 8, 0)
pauseButton:SetText(L.PAUSE)

local function BuildSortedList()
    if not commsDirty then
        return
    end

    sorted = {}

    local prefix, entry
    for prefix, entry in pairs(counts) do
        table.insert(sorted, entry)
    end

    table.sort(sorted, function(a, b)
        if a.total == b.total then
            return a.prefix < b.prefix
        end
        return a.total > b.total
    end)

    commsDirty = false
end

local function RefreshComms()
    BuildSortedList()

    local numRows = table.getn(sorted)
    local index
    for index = 1, MAX_ROWS do
        if index <= numRows then
            rows[index].prefix:SetText(sorted[index].prefix)
            local entry = sorted[index]
            rows[index].columns[1]:SetText(tostring(entry.inbound))
            rows[index].columns[2]:SetText(tostring(entry.outbound))
            rows[index].columns[3]:SetText(tostring(entry.total))
            rows[index].columns[4]:SetText(string.format("%.1f", RecentRate(entry)))
        else
            rows[index].prefix:SetText("")
            local j
            for j = 1, 4 do rows[index].columns[j]:SetText("") end
        end
    end

    if numRows > MAX_ROWS then
        overflow:SetText("+ " .. (numRows - MAX_ROWS) .. " " .. L.MORE_PREFIXES)
    else
        overflow:SetText("")
    end
end

local function RefreshFrametime()
    currentLabel:SetText(L.CURRENT .. ": " .. string.format("%.1f ms", currentFrameMs))
    worstLabel:SetText(L.WORST .. ": " .. string.format("%.1f ms", worstFrameMs))
    memoryLabel:SetText(L.MEMORY .. ": " .. FormatMemory(currentMemoryKb) .. "  (" .. FormatMemoryDelta(currentMemoryKb - memoryBaselineKb) .. ")")

    hitch33Label:SetText("> 33 ms: " .. hitch33)
    hitch50Label:SetText("> 50 ms: " .. hitch50)
    hitch100Label:SetText("> 100 ms: " .. hitch100)
    hitch200Label:SetText("> 200 ms: " .. hitch200)
end

local function GetGraphSample(displayIndex)
    local emptySlots = GRAPH_SAMPLE_COUNT - graphSampleCount
    if displayIndex <= emptySlots then
        return 0
    end

    local historyIndex = displayIndex - emptySlots
    local sourceIndex = graphWriteIndex - graphSampleCount + historyIndex

    while sourceIndex <= 0 do
        sourceIndex = sourceIndex + GRAPH_SAMPLE_COUNT
    end

    while sourceIndex > GRAPH_SAMPLE_COUNT do
        sourceIndex = sourceIndex - GRAPH_SAMPLE_COUNT
    end

    return graphSamples[sourceIndex] or 0
end

local function DrawGraph()
    local index
    for index = 1, GRAPH_SAMPLE_COUNT do
        local sampleMs = GetGraphSample(index)
        local height = (sampleMs / GRAPH_MAX_MS) * GRAPH_HEIGHT

        if height < 1 then
            height = 1
        elseif height > GRAPH_HEIGHT then
            height = GRAPH_HEIGHT
        end

        graphBars[index]:SetHeight(height)
    end
end

local function Refresh()
    if paused then
        pauseState:SetText("|cffffcc00" .. L.PAUSED .. "|r")
    else
        pauseState:SetText("")
    end

    if currentView == "comms" then
        RefreshComms()
    elseif currentView == "frametime" then
        RefreshFrametime()
    else
        DrawGraph()
    end
end

local function SetView(view)
    currentView = view

    ShowGroup(commsWidgets, currentView == "comms")
    ShowGroup(frameWidgets, currentView == "frametime")
    ShowGroup(graphWidgets, currentView == "graph")

    if currentView == "comms" then
        commsTab:Disable()
    else
        commsTab:Enable()
    end

    if currentView == "frametime" then
        frameTab:Disable()
    else
        frameTab:Enable()
    end

    if currentView == "graph" then
        graphTab:Disable()
    else
        graphTab:Enable()
    end

    Refresh()
end

local function ResetGraph()
    local index
    for index = 1, GRAPH_SAMPLE_COUNT do
        graphSamples[index] = 0
    end

    graphWriteIndex = 0
    graphSampleCount = 0
    graphSampleElapsed = 0
    graphBucketWorstMs = 0
    graphRedrawElapsed = 0
end

local function ResetAll()
    counts = {}
    sorted = {}
    inboundMessages = 0
    outboundMessages = 0
    commsClock = 0
    commsDirty = true

    currentFrameMs = 0
    worstFrameMs = 0
    hitch33 = 0
    hitch50 = 0
    hitch100 = 0
    hitch200 = 0

    currentMemoryKb = gcinfo()
    memoryBaselineKb = currentMemoryKb
    uiElapsed = 0

    ResetGraph()
    ClearCaptureData()
    Refresh()
end

local function PushGraphSample(frameMs)
    graphWriteIndex = graphWriteIndex + 1
    if graphWriteIndex > GRAPH_SAMPLE_COUNT then
        graphWriteIndex = 1
    end

    graphSamples[graphWriteIndex] = frameMs

    if graphSampleCount < GRAPH_SAMPLE_COUNT then
        graphSampleCount = graphSampleCount + 1
    end
end

local function AdvanceGraph(elapsed, frameMs)
    local slots
    local slot

    if frameMs > graphBucketWorstMs then
        graphBucketWorstMs = frameMs
    end

    graphSampleElapsed = graphSampleElapsed + elapsed
    if graphSampleElapsed < GRAPH_SAMPLE_INTERVAL then
        return
    end

    slots = math.floor(graphSampleElapsed / GRAPH_SAMPLE_INTERVAL)
    if slots > GRAPH_SAMPLE_COUNT then
        slots = GRAPH_SAMPLE_COUNT
    end

    PushGraphSample(graphBucketWorstMs)

    for slot = 2, slots do
        PushGraphSample(0)
    end

    graphSampleElapsed = graphSampleElapsed - (slots * GRAPH_SAMPLE_INTERVAL)
    if graphSampleElapsed >= GRAPH_SAMPLE_INTERVAL then
        graphSampleElapsed = 0
    end

    graphBucketWorstMs = 0
end

closeButton:SetScript("OnClick", function()
    SetWindowShown(false)
end)

commsTab:SetScript("OnClick", function()
    SetView("comms")
end)

frameTab:SetScript("OnClick", function()
    SetView("frametime")
end)

graphTab:SetScript("OnClick", function()
    SetView("graph")
end)

resetButton:SetScript("OnClick", function()
    ResetAll()
end)

pauseButton:SetScript("OnClick", function()
    paused = not paused

    if paused then
        pauseButton:SetText(L.RESUME)
    else
        pauseButton:SetText(L.PAUSE)
    end

    Refresh()
end)

captureFrame:SetScript("OnEvent", function()
    RecordCapturedEvent(event)
end)

driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("VARIABLES_LOADED")
driver:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        RestoreWindowVisibility()
        currentMemoryKb = gcinfo()
        memoryBaselineKb = currentMemoryKb
        monitoringReady = true
        Refresh()
    elseif event == "CHAT_MSG_ADDON" then
        RecordMessage(arg1, false)
    end
end)

driver:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0

    if monitoringReady and not paused then
        commsClock = commsClock + elapsed
        currentFrameMs = elapsed * 1000

        if currentFrameMs > worstFrameMs then
            worstFrameMs = currentFrameMs
        end

        if currentFrameMs > 33 then
            hitch33 = hitch33 + 1
        end
        if currentFrameMs > 50 then
            hitch50 = hitch50 + 1
        end
        if currentFrameMs > 100 then
            hitch100 = hitch100 + 1
        end
        if currentFrameMs > 200 then
            hitch200 = hitch200 + 1
        end

        RecordHitchCorrelation(currentFrameMs)
        AdvanceGraph(elapsed, currentFrameMs)
        if captureActive then
            captureClock = captureClock + elapsed
            if captureClock >= CAPTURE_MAX_SECONDS then
                captureClock = CAPTURE_MAX_SECONDS
                StopCapture(true)
                DEFAULT_CHAT_FRAME:AddMessage("Performante: event capture stopped at 30-second safety limit. Use /perf capture status.")
            end
        end
    end

    uiElapsed = uiElapsed + elapsed
    graphRedrawElapsed = graphRedrawElapsed + elapsed

    if uiElapsed >= 0.5 then
        uiElapsed = 0

        if monitoringReady and not paused then
            currentMemoryKb = gcinfo()

            if Performante:IsShown() and currentView ~= "graph" then
                Refresh()
            end
        end
    end

    if graphRedrawElapsed >= GRAPH_REDRAW_INTERVAL then
        graphRedrawElapsed = 0

        if monitoringReady and not paused and Performante:IsShown() and currentView == "graph" then
            Refresh()
        end
    end
end)

SLASH_PERFORMANTE1 = "/performante"
SLASH_PERFORMANTE2 = "/perf"
SlashCmdList["PERFORMANTE"] = function(msg)
    local command = string.lower(msg or "")

    if command == "reset" then
        ResetAll()
        SetWindowShown(true)
    elseif command == "pause" then
        paused = true
        pauseButton:SetText(L.RESUME)
        Refresh()
    elseif command == "resume" then
        paused = false
        pauseButton:SetText(L.PAUSE)
        Refresh()
    elseif command == "comms" then
        SetWindowShown(true)
        SetView("comms")
    elseif command == "frametime" or command == "frame" then
        SetWindowShown(true)
        SetView("frametime")
    elseif command == "graph" then
        SetWindowShown(true)
        SetView("graph")
    elseif command == "capture start" then
        StartCapture()
        DEFAULT_CHAT_FRAME:AddMessage("Performante: event capture started (30-second maximum).")
    elseif command == "capture stop" then
        StopCapture(false)
        CaptureStatus()
    elseif command == "capture status" or command == "capture" then
        CaptureStatus()
    elseif command == "show" then
        SetWindowShown(true)
    elseif command == "hide" then
        SetWindowShown(false)
    else
        if Performante:IsShown() then
            SetWindowShown(false)
        else
            SetWindowShown(true)
        end
    end
end

Performante:Hide()
SetView("comms")
