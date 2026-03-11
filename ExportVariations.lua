-- ExportVariations.lua
-- DaVinci Resolve Script: Export 4 Variations
--
-- Watermark = auto-detected by smallest total clip file size, with manual override
-- Song      = all audio tracks (all off for "no song" variations)
-- Requires in/out points to be set on the timeline.

local ui   = fu.UIManager
local disp = bmd.UIDispatcher(ui)

-- -----------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------
local function getFileSizeBytes(path)
    if not path or path == "" then return 0 end
    local handle = io.popen('stat -f%z "' .. path:gsub('"', '\\"') .. '" 2>/dev/null')
    if not handle then return 0 end
    local result = handle:read("*n")
    handle:close()
    return result or 0
end

local function formatBytes(bytes)
    if bytes > 1048576 then return string.format("%.1f MB", bytes / 1048576)
    elseif bytes > 1024 then return string.format("%.1f KB", bytes / 1024)
    else return bytes .. " B" end
end

-- Scan video tracks, return list of {index, name, totalBytes} sorted smallest first
local function scanVideoTracks(timeline)
    local videoCount = timeline:GetTrackCount("video")
    local tracks = {}
    for i = 1, videoCount do
        local name = timeline:GetTrackName("video", i) or ("V" .. i)
        local totalBytes = 0
        local clips = timeline:GetItemListInTrack("video", i)
        if clips then
            for _, clip in ipairs(clips) do
                local mpi = clip:GetMediaPoolItem()
                if mpi then
                    local path = mpi:GetClipProperty("File Path")
                    if path then totalBytes = totalBytes + getFileSizeBytes(path) end
                end
            end
        end
        tracks[i] = { index = i, name = name, totalBytes = totalBytes }
    end
    return tracks
end

-- -----------------------------------------------------------------------
-- UI
-- -----------------------------------------------------------------------
local win = disp:AddWindow({
    ID          = "ExportVariations",
    WindowTitle = "Export 4 Variations",
    Geometry    = { 500, 300, 460, 300 },
}, {
    ui:VGroup{ Spacing = 8,
        ui:HGroup{ Spacing = 8,
            ui:Label{ Text = "Folder name:", Weight = 0 },
            ui:LineEdit{
                ID              = "FolderName",
                PlaceholderText = "e.g. ClientName_ProjectV1",
            },
        },
        ui:HGroup{ Spacing = 8,
            ui:Label{ Text = "Watermark track:", Weight = 0 },
            ui:ComboBox{ ID = "WatermarkCombo" },
            ui:Button{
                ID          = "RefreshBtn",
                Text        = "↺",
                MinimumSize = { 28, 28 },
                MaximumSize = { 28, 28 },
                Weight      = 0,
            },
        },
        ui:HGroup{ Spacing = 8,
            ui:HGap{},
            ui:Button{
                ID          = "ExportBtn",
                Text        = "Export 4 Variations",
                MinimumSize = { 180, 32 },
                Weight      = 0,
            },
            ui:HGap{},
        },
        ui:TextEdit{
            ID       = "Log",
            ReadOnly = true,
            Text     = "Ready.",
        },
    },
})

local itm = win:GetItems()

local logContent = "Ready."
local function log(msg)
    print("[ExportVariations] " .. msg)
    logContent = logContent .. "\n" .. msg
    itm.Log.Text = logContent
end

-- Populate the watermark ComboBox, auto-selecting smallest track
local trackData     = {}  -- { index, name, totalBytes } per combo entry
local comboCount    = 0   -- how many items are currently in the combo

local function populateWatermarkCombo()
    local project  = resolve:GetProjectManager():GetCurrentProject()
    local timeline = project and project:GetCurrentTimeline()

    -- Clear existing items using our own counter
    for i = 1, comboCount do
        itm.WatermarkCombo:RemoveItem(0)
    end
    comboCount = 0
    trackData  = {}

    if not timeline then
        itm.WatermarkCombo:AddItem("No timeline open")
        comboCount = 1
        return
    end

    local tracks = scanVideoTracks(timeline)
    if #tracks == 0 then
        itm.WatermarkCombo:AddItem("No video tracks")
        comboCount = 1
        return
    end

    -- Find smallest (by file size) — likely the watermark/logo
    local smallestIdx = 1
    local smallestBytes = math.huge
    for _, t in ipairs(tracks) do
        if t.totalBytes > 0 and t.totalBytes < smallestBytes then
            smallestBytes = t.totalBytes
            smallestIdx = t.index
        end
    end

    -- Populate combo, tagging the auto-detected track
    for _, t in ipairs(tracks) do
        local label
        if t.index == smallestIdx then
            label = string.format("V%d: %s  (%s) ← suggested", t.index, t.name, formatBytes(t.totalBytes))
        else
            local sizeStr = t.totalBytes > 0 and formatBytes(t.totalBytes) or "no clips"
            label = string.format("V%d: %s  (%s)", t.index, t.name, sizeStr)
        end
        itm.WatermarkCombo:AddItem(label)
        comboCount = comboCount + 1
        trackData[#trackData + 1] = t
    end

    -- Select the suggested track
    itm.WatermarkCombo.CurrentIndex = smallestIdx - 1
end

-- -----------------------------------------------------------------------
-- Export logic
-- -----------------------------------------------------------------------
local function doExport(folderName)

    local project = resolve:GetProjectManager():GetCurrentProject()
    if not project then log("ERROR: No project open.") return end

    local timeline = project:GetCurrentTimeline()
    if not timeline then log("ERROR: No active timeline.") return end

    log("NOTE: Make sure in/out points are set on the timeline.")

    -- Track counts
    local videoCount = timeline:GetTrackCount("video")
    local audioCount = timeline:GetTrackCount("audio")
    if videoCount == 0 then log("ERROR: No video tracks.") return end
    if audioCount == 0 then log("ERROR: No audio tracks.") return end

    -- Watermark track from combo selection
    local comboIdx    = itm.WatermarkCombo.CurrentIndex  -- 0-based
    local watermarkTrack = comboIdx + 1
    if not trackData[comboIdx + 1] then
        log("ERROR: Invalid watermark track selection.")
        return
    end
    log(string.format("Watermark: V%d  |  Audio tracks: %d", watermarkTrack, audioCount))

    -- Save original track states
    local origVideo, origAudio = {}, {}
    for i = 1, videoCount do
        local ok, val = pcall(function() return timeline:GetIsTrackEnabled("video", i) end)
        origVideo[i] = ok and val or true
    end
    for i = 1, audioCount do
        local ok, val = pcall(function() return timeline:GetIsTrackEnabled("audio", i) end)
        origAudio[i] = ok and val or true
    end

    -- Output folder
    local outputDir = os.getenv("HOME") .. "/Documents/" .. folderName
    os.execute('mkdir -p "' .. outputDir .. '"')
    log("Output: " .. outputDir)

    -- Timeline settings
    local tlWidth  = tonumber(timeline:GetSetting("timelineResolutionWidth"))  or 1920
    local tlHeight = tonumber(timeline:GetSetting("timelineResolutionHeight")) or 1080
    local tlFps    = timeline:GetSetting("timelineFrameRate") or "25"
    log(string.format("Timeline: %dx%d @ %sfps", tlWidth, tlHeight, tlFps))

    local variations = {
        { true,  true,  folderName .. "_song_watermark"       },
        { true,  false, folderName .. "_no_song_watermark"    },
        { false, true,  folderName .. "_song_no_watermark"    },
        { false, false, folderName .. "_no_song_no_watermark" },
    }

    local ok, err = pcall(function()
        for i, v in ipairs(variations) do
            local wmOn, audioOn, filename = v[1], v[2], v[3]

            resolve:OpenPage("edit")
            timeline:SetTrackEnable("video", watermarkTrack, wmOn)
            for a = 1, audioCount do
                timeline:SetTrackEnable("audio", a, audioOn)
            end
            resolve:OpenPage("deliver")

            project:SetRenderSettings({
                SelectAllFrames = false,
                TargetDir       = outputDir,
                CustomName      = filename,
                Format          = "MP4",
                VideoCodec      = "H264",
                FormatWidth     = tlWidth,
                FormatHeight    = tlHeight,
                FrameRate       = tlFps,
            })

            local jobId = project:AddRenderJob()
            log(string.format("[%d/4] Rendering: %s", i, filename))

            project:StartRendering(jobId)

            -- Wait for render to START (up to 15s)
            local startDeadline = os.time() + 15
            while not project:IsRenderingInProgress() do
                if os.time() > startDeadline then
                    log(string.format("[%d/4] WARNING: render did not start in time", i))
                    break
                end
                local t = os.time() + 1
                repeat until os.time() >= t
            end

            -- Wait for render to FINISH
            while project:IsRenderingInProgress() do
                local t = os.time() + 1
                repeat until os.time() >= t
            end

            log(string.format("[%d/4] Done.", i))
        end
    end)

    -- Always restore tracks
    resolve:OpenPage("edit")
    for i, enabled in pairs(origVideo) do
        timeline:SetTrackEnable("video", i, enabled)
    end
    for i, enabled in pairs(origAudio) do
        timeline:SetTrackEnable("audio", i, enabled)
    end
    resolve:OpenPage("deliver")
    log("Tracks restored.")

    if not ok then
        log("ERROR: " .. tostring(err))
        itm.ExportBtn.Enabled = true
        return
    end

    log("All 4 exports complete!")
    log("Saved to: " .. outputDir)
    os.execute('open "' .. outputDir .. '"')
    itm.ExportBtn.Enabled = true
end

-- -----------------------------------------------------------------------
-- Event handlers
-- -----------------------------------------------------------------------
win.On.ExportBtn.Clicked = function(ev)
    local name = itm.FolderName.Text:match("^%s*(.-)%s*$")
    if not name or name == "" then
        log("Please enter a folder name.")
        return
    end
    itm.ExportBtn.Enabled = false
    logContent = ""
    itm.Log.Text = ""
    log("Starting: " .. name)
    local ok, err = pcall(doExport, name)
    if not ok then
        log("FATAL: " .. tostring(err))
        itm.ExportBtn.Enabled = true
    end
end

win.On.RefreshBtn.Clicked = function(ev)
    populateWatermarkCombo()
    log("Track list refreshed.")
end

win.On.ExportVariations.Close = function(ev)
    disp:ExitLoop()
end

-- -----------------------------------------------------------------------
-- Run
-- -----------------------------------------------------------------------
populateWatermarkCombo()
win:Show()
disp:RunLoop()
win:Hide()
