-- RoundClipFPS.lua
-- DaVinci Resolve Script: Round all media pool root clips to nearest whole FPS
--
-- Scans every clip in the media pool root folder.
-- If FPS has a decimal (e.g. 119.88, 59.94, 29.97), rounds to nearest integer.
-- Clips already at a whole number are skipped.

local ui   = fu.UIManager
local disp = bmd.UIDispatcher(ui)

local win = disp:AddWindow({
    ID          = "RoundClipFPS",
    WindowTitle = "Round Clip FPS",
    Geometry    = { 500, 300, 420, 260 },
}, {
    ui:VGroup{ Spacing = 8,
        ui:TextEdit{
            ID       = "Log",
            ReadOnly = true,
            Text     = "Ready. Press the button to round all clip FPS in the media pool.",
        },
        ui:HGroup{ Spacing = 8,
            ui:HGap{},
            ui:Button{
                ID          = "RunBtn",
                Text        = "Round All FPS",
                MinimumSize = { 150, 32 },
                Weight      = 0,
            },
            ui:HGap{},
        },
    },
})

local itm        = win:GetItems()
local logContent = "Ready. Press the button to round all clip FPS in the media pool."

local function log(msg)
    print("[RoundClipFPS] " .. msg)
    logContent = logContent .. "\n" .. msg
    itm.Log.Text = logContent
end

-- Try a list of known property key names for frame rate
local FPS_KEYS = { "Video Frame Rate", "FPS", "Frame Rate" }

local function getClipFPS(clip)
    for _, key in ipairs(FPS_KEYS) do
        local val = clip:GetClipProperty(key)
        if val and val ~= "" then
            local n = tonumber(val)
            if n then return n, key end
        end
    end
    return nil, nil
end

local function roundAllFPS()
    local project = resolve:GetProjectManager():GetCurrentProject()
    if not project then log("ERROR: No project open.") return end

    local mediaPool = project:GetMediaPool()
    if not mediaPool then log("ERROR: Could not get media pool.") return end

    local rootFolder = mediaPool:GetRootFolder()
    if not rootFolder then log("ERROR: Could not get root folder.") return end

    local clips = rootFolder:GetClipList()
    if not clips or #clips == 0 then
        log("No clips found in media pool root.")
        return
    end

    log(string.format("Found %d clip(s). Scanning...", #clips))

    local nRounded = 0
    local nSkipped = 0
    local nFailed  = 0

    for _, clip in ipairs(clips) do
        local name   = clip:GetName() or "?"
        local fps, key = getClipFPS(clip)

        if not fps then
            log(string.format("  ? %s — could not read FPS", name))
            nFailed = nFailed + 1
        else
            local rounded = math.floor(fps + 0.5)
            if math.abs(fps - rounded) < 0.001 then
                -- Already a whole number, skip
                nSkipped = nSkipped + 1
            else
                local ok, err = pcall(function()
                    clip:SetClipProperty(key, tostring(rounded))
                end)
                if ok then
                    log(string.format("  %s: %g → %d fps", name, fps, rounded))
                    nRounded = nRounded + 1
                else
                    log(string.format("  FAILED %s: %s", name, tostring(err)))
                    nFailed = nFailed + 1
                end
            end
        end
    end

    log(string.format("\nDone — %d rounded, %d skipped, %d failed.", nRounded, nSkipped, nFailed))
end

win.On.RunBtn.Clicked = function(ev)
    logContent = ""
    itm.Log.Text = ""
    log("Scanning media pool root...")
    local ok, err = pcall(roundAllFPS)
    if not ok then
        log("FATAL: " .. tostring(err))
    end
end

win.On.RoundClipFPS.Close = function(ev)
    disp:ExitLoop()
end

win:Show()
disp:RunLoop()
win:Hide()
