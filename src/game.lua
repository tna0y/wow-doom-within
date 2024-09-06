local DW_KEYMAP = {
    W = 0,
    A = 1,
    S = 2,
    D = 3,
    R = 4,
    F = 5,
    LCTRL = 6,
    LSHIFT = 7,
    SPACE = 8,
    LALT = 9,
    ENTER = 10,
    ESCAPE = 11,
    UP = 12,
    LEFT = 13,
    DOWN = 14,
    RIGHT = 15,
    Y = 16,
    N = 17,
    [","] = 18,
    ["."] = 19,
    ["0"] = 20,
    ["1"] = 21,
    ["2"] = 22,
    ["3"] = 23,
    ["4"] = 24,
    ["5"] = 25,
    ["6"] = 26,
    ["7"] = 27,
    ["8"] = 28,
    ["9"] = 29
}

function _DW_Game() 
    local dw_game = {
        cpu = nil,
        frame = nil,
        is_running = false,
        profiling_enabled = false,
        pressed_keys = {},
        sticky_keys = {},
        frame_start_time = 0,
        frame_cnt = 0,
        last_stats_time = 0,  -- Track when we last printed stats
        framebuffer = {}
    }
    for i = 0, 320 * 200 - 1 do
        dw_game.framebuffer[i] = 0
    end

    function dw_game:bindControls(frame)
        frame:EnableKeyboard(true)
        frame:SetScript("OnKeyDown", function(_, key)
            if DW_KEYMAP[key] ~= nil then
                self.pressed_keys[DW_KEYMAP[key]] = true
                self.sticky_keys[DW_KEYMAP[key]] = true
            end
        end)

        frame:SetScript("OnKeyUp", function(_, key)
            if DW_KEYMAP[key] ~= nil then
                self.pressed_keys[DW_KEYMAP[key]] = false
            end
        end)
    end

    function dw_game:loadChunkChain(cur_idx, text) 
        if cur_idx > #_DW_DoomLoadFuncs then
            RunNextFrame(function()                
                self.frame_start_time = GetTime()
                self.cpu:Run()
            end)
            self.frame:HideStatusText()
            self.frame:ShowGameView() 
            return
        end
        self.frame:SetStatusText("Loading memory chunk " .. cur_idx .. " of " .. #_DW_DoomLoadFuncs)
        
        _DW_DoomLoadFuncs[cur_idx](self.cpu)
        RunNextFrame(function() self:loadChunkChain(cur_idx + 1, text) end)
    end

    function dw_game:Start()
        if self.is_running then
            print("Doom is already running.")
            return
        end
        -- set up UI
        local frame = _DW_GetFrame()
        self:bindControls(frame)
        frame:OnClose(function() self:Stop() end)

        frame:Show()
        
        -- set up CPU
        local cpu = RVEMU_GetCore()
        
        self.cpu = cpu
        self.frame = frame
        self.frame:ShowStatusText()
        self.frame:SetStatusText("Initializing Emulator")

        self.is_running = true
        self.frame_start_time = GetTime()  -- Initialize start time
        self.last_stats_time = GetTime()   -- Initialize last stats time
        self.frame_cnt = 0                 -- Reset frame counter

        RunNextFrame(function() 
            cpu:InitCPU(_DW_Init_doom, _DW_HandleEcall(self))

            if self.profiling_enabled then
                cpu:EnableProfiling(ProfilingSamplingRate)
            end

            self:loadChunkChain(1, text)
        end)
    end

    function dw_game:UpdateFrameStats()
        self.frame_cnt = self.frame_cnt + 1
        local current_time = GetTime()
        
        -- Print stats every 10 seconds
        if current_time - self.last_stats_time >= 10 then
            local total_time = current_time - self.frame_start_time
            print(string.format("Frames rendered: %d, Time elapsed: %.2f seconds, Average FPS: %.2f", 
                self.frame_cnt, 
                total_time,
                self.frame_cnt / total_time))
            self.last_stats_time = current_time
        end
    end

    function dw_game:Stop()
        if not self.is_running then
            print("Doom is not running.")
            return
        end
        self.is_running = false
        DW_IsRunning = false

        self.cpu:Stop()
        self.frame:Hide()
    end
    return dw_game
end