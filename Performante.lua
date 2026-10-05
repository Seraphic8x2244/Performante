-- Performante
-- Vanilla WoW 1.12.1 / Lua 5.0.3
-- 0.2.0: communications, frametime/hitch and Lua-memory diagnostics.

local ADDON_NAME = "Performante"
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME, "Version")
local L = Performante_L

local Performante = CreateFrame("Frame", "PerformanteFrame", UIParent)
local driver = CreateFrame("Frame", "PerformanteDriver", UIParent)

local counts = {}
local sorted = {}
local totalMessages = 0
local commsDirty = true

local paused = false
local currentView = "comms"
local monitoringReady = false
local uiElapsed = 0

local currentFrameMs = 0
local worstFrameMs = 0
local hitch33 = 0
local hitch50 = 0
local hitch100 = 0
local hitch200 = 0
local hitchTimes = {}
local hitchValues = {}
local hitchLogCount = 0
local HITCH_LOG_LIMIT = 4
local HITCH_LOG_THRESHOLD = 50

local currentMemoryKb = 0
local memoryBaselineKb = 0

local MAX_ROWS = 11

local commsWidgets = {}
local frameWidgets = {}

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

local function FormatSessionTime(seconds)
    local minutes = math.floor(seconds / 60)
    local wholeSeconds = math.floor(seconds - (minutes * 60))
    return string.format("%02d:%02d", minutes, wholeSeconds)
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
    local i
    for i = 1, table.getn(group) do
        if shown then
            group[i]:Show()
        else
            group[i]:Hide()
        end
    end
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
commsTab:SetWidth(76)
commsTab:SetHeight(20)
commsTab:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -30)
commsTab:SetText(L.COMMS)

local frameTab = CreateFrame("Button", nil, Performante, "UIPanelButtonTemplate")
frameTab:SetWidth(88)
frameTab:SetHeight(20)
frameTab:SetPoint("LEFT", commsTab, "RIGHT", 6, 0)
frameTab:SetText(L.FRAMETIME)

local pauseState = Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pauseState:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -34)
pauseState:SetWidth(100)
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

local countHeader = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
countHeader:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -18, -65)
countHeader:SetWidth(150)
countHeader:SetJustifyH("RIGHT")
countHeader:SetText(L.MESSAGES)

local commsDivider = AddWidget(commsWidgets, Performante:CreateTexture(nil, "ARTWORK"))
commsDivider:SetTexture(1, 1, 1)
commsDivider:SetAlpha(0.16)
commsDivider:SetHeight(1)
commsDivider:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -80)
commsDivider:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -12, -80)

local rows = {}
local i
for i = 1, MAX_ROWS do
    local row = {}

    row.prefix = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    row.prefix:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -84 - ((i - 1) * 15))
    row.prefix:SetWidth(238)
    row.prefix:SetJustifyH("LEFT")
    row.prefix:SetText("")

    row.count = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    row.count:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -18, -84 - ((i - 1) * 15))
    row.count:SetWidth(60)
    row.count:SetJustifyH("RIGHT")
    row.count:SetText("")

    rows[i] = row
end

local overflow = AddWidget(commsWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
overflow:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -250)
overflow:SetText("")

local currentLabel = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
currentLabel:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -68)
currentLabel:SetWidth(145)
currentLabel:SetJustifyH("LEFT")

local worstLabel = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlight"))
worstLabel:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -68)
worstLabel:SetWidth(145)
worstLabel:SetJustifyH("RIGHT")

local memoryLabel = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
memoryLabel:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -91)
memoryLabel:SetWidth(302)
memoryLabel:SetJustifyH("LEFT")

local hitchTitle = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
hitchTitle:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -116)
hitchTitle:SetText(L.HITCHES)

local hitch33Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch33Label:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -136)
hitch33Label:SetWidth(140)
hitch33Label:SetJustifyH("LEFT")

local hitch50Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch50Label:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -136)
hitch50Label:SetWidth(140)
hitch50Label:SetJustifyH("RIGHT")

local hitch100Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch100Label:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -154)
hitch100Label:SetWidth(140)
hitch100Label:SetJustifyH("LEFT")

local hitch200Label = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
hitch200Label:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -14, -154)
hitch200Label:SetWidth(140)
hitch200Label:SetJustifyH("RIGHT")

local frameDivider = AddWidget(frameWidgets, Performante:CreateTexture(nil, "ARTWORK"))
frameDivider:SetTexture(1, 1, 1)
frameDivider:SetAlpha(0.16)
frameDivider:SetHeight(1)
frameDivider:SetPoint("TOPLEFT", Performante, "TOPLEFT", 12, -174)
frameDivider:SetPoint("TOPRIGHT", Performante, "TOPRIGHT", -12, -174)

local recentTitle = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
recentTitle:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -184)
recentTitle:SetText(L.RECENT_HITCHES)

local hitchRows = {}
for i = 1, HITCH_LOG_LIMIT do
    local hitchRow = AddWidget(frameWidgets, Performante:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    hitchRow:SetPoint("TOPLEFT", Performante, "TOPLEFT", 14, -202 - ((i - 1) * 14))
    hitchRow:SetWidth(302)
    hitchRow:SetJustifyH("LEFT")
    hitchRow:SetText("")
    hitchRows[i] = hitchRow
end

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

    local prefix, count
    for prefix, count in pairs(counts) do
        table.insert(sorted, { prefix = prefix, count = count })
    end

    table.sort(sorted, function(a, b)
        if a.count == b.count then
            return a.prefix < b.prefix
        end
        return a.count > b.count
    end)

    commsDirty = false
end

local function RefreshComms()
    BuildSortedList()

    countHeader:SetText(L.MESSAGES .. ": " .. totalMessages)

    local numRows = table.getn(sorted)
    local index
    for index = 1, MAX_ROWS do
        if index <= numRows then
            rows[index].prefix:SetText(sorted[index].prefix)
            rows[index].count:SetText(tostring(sorted[index].count))
        else
            rows[index].prefix:SetText("")
            rows[index].count:SetText("")
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

    local index
    for index = 1, HITCH_LOG_LIMIT do
        if index <= hitchLogCount then
            hitchRows[index]:SetText(FormatSessionTime(hitchTimes[index]) .. "   " .. string.format("%.1f ms", hitchValues[index]))
        elseif index == 1 then
            hitchRows[index]:SetText(L.NO_HITCHES)
        else
            hitchRows[index]:SetText("")
        end
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
    else
        RefreshFrametime()
    end
end

local function SetView(view)
    currentView = view

    if currentView == "comms" then
        ShowGroup(commsWidgets, true)
        ShowGroup(frameWidgets, false)
        commsTab:Disable()
        frameTab:Enable()
    else
        ShowGroup(commsWidgets, false)
        ShowGroup(frameWidgets, true)
        commsTab:Enable()
        frameTab:Disable()
    end

    Refresh()
end

local function ResetAll()
    counts = {}
    sorted = {}
    totalMessages = 0
    commsDirty = true

    currentFrameMs = 0
    worstFrameMs = 0
    hitch33 = 0
    hitch50 = 0
    hitch100 = 0
    hitch200 = 0
    hitchLogCount = 0

    currentMemoryKb = gcinfo()
    memoryBaselineKb = currentMemoryKb
    uiElapsed = 0

    Refresh()
end

local function AddHitch(frameMs)
    local index
    for index = HITCH_LOG_LIMIT, 2, -1 do
        hitchTimes[index] = hitchTimes[index - 1]
        hitchValues[index] = hitchValues[index - 1]
    end

    hitchTimes[1] = GetTime()
    hitchValues[1] = frameMs

    if hitchLogCount < HITCH_LOG_LIMIT then
        hitchLogCount = hitchLogCount + 1
    end
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
        if paused then
            return
        end

        local prefix = arg1
        if not prefix or prefix == "" then
            prefix = "<no prefix>"
        end

        if counts[prefix] then
            counts[prefix] = counts[prefix] + 1
        else
            counts[prefix] = 1
        end

        totalMessages = totalMessages + 1
        commsDirty = true
    end
end)

driver:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0

    if monitoringReady and not paused then
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

        if currentFrameMs > HITCH_LOG_THRESHOLD then
            AddHitch(currentFrameMs)
        end
    end

    uiElapsed = uiElapsed + elapsed
    if uiElapsed >= 0.5 then
        uiElapsed = 0

        if monitoringReady and not paused then
            currentMemoryKb = gcinfo()
        end

        if Performante:IsShown() then
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
