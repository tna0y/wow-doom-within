-- Initializes and returns a frame object for rendering and handling input.
-- @return A frame object with rendering and input handling capabilities.
function _DW_GetFrame()
    
    local frame = CreateFrame("Frame", "DoomWithin", UIParent, "BackdropTemplate")
    frame:SetSize(640 + 46, 400 + 46)
    frame:SetPoint("CENTER")
    
    frame:SetBackdrop({
        edgeFile = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder",
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        tile = true,
        tileSize = 32,
        edgeSize = 64,
        tileEdge = true,
    })
    
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", frame.StopMovingOrSizing)
    
    local close = CreateFrame("Button", "YourCloseButtonName", frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    frame.close = close
    
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("CENTER")
    frame.text = text

    frame.pixels = {}

    local FrameBufferTestMixin = {}

    function FrameBufferTestMixin:OnLoad()
        self.ScreenWidth = 320
        self.ScreenHeight = 50
    
        self:SetToplevel(true)
        self:SetAlpha(1)
        self:SetSize(self.ScreenWidth * 2, self.ScreenHeight * 2)
    
        self.framebuffer = {}

        for i = 0, self.ScreenHeight-1 do
            for j = 0, self.ScreenWidth-1 do
                local pixel = self:CreateTexture()
                -- Each pixel refers to a line colormap and recoloring the pixel
                -- is the same as changing the texture coordinates underneath.
                -- It's faster than changing the texture itself.
                
                -- Default palette (palette.blp) is https://doomwiki.org/wiki/PLAYPAL palette 0.
                -- Texture is upscaled to 1024x4 to prevent texture bleeding.
                pixel:SetTexture("Interface\\Addons\\DoomWithin\\palette.blp")
                pixel:SetTexCoord(0,1/256,0,1)
                pixel:SetAllPoints(self)
                pixel:SetSize(2, 2)
                pixel:SetDrawLayer("ARTWORK", 1)
                pixel.color = 0
                self.framebuffer[#self.framebuffer + 1] = pixel
                frame.pixels[#frame.pixels + 1] = pixel
            end
        end

        local initialAnchor = AnchorUtil.CreateAnchor("TOPLEFT", self, "TOPLEFT", 0, 0)
        local layout = AnchorUtil.CreateGridLayout(GridLayoutMixin.Direction.TopLeftToBottomRight, self.ScreenWidth, 0, 0)
        AnchorUtil.GridLayout(self.framebuffer, initialAnchor, layout)
    end

    frame.framefuffer_parts = {}

    -- Without splitting it into parts WoW crashes.
    for i = 4, 1, -1 do
        local part_frame = Mixin(CreateFrame("Frame", nil, frame), FrameBufferTestMixin)
        part_frame:OnLoad()
        part_frame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 23, 23 + (i - 1) * 100);

        --part_frame:SetPoint("TOPLEFT", 0,  i * 100)
        part_frame:Hide()
        table.insert(frame.framefuffer_parts, part_frame)
    end


    frame.opened = false

    -- Renders the frame from the given framebuffer address.
    -- @param framebuffer_addr The address of the framebuffer to render.
    function frame:RenderFrame(framebuffer)
        for offset = 0, 63999 do
            local data = framebuffer[offset]

            local pixel = self.pixels[offset + 1]
            if data ~= pixel.color then
                local tex_pos = data / 256
                pixel:SetTexCoord(tex_pos + 0.0009765625, tex_pos + 0.001953125--[[1/512]],0,1)
                pixel.color = data
            end
        end
    end

    function frame:ShowGameView()
        for i = 1, 4 do
            self.framefuffer_parts[i]:Show()
        end
        self.opened = true
    end

    function frame:HideGameView()
        for i = 1, 4 do
            self.framefuffer_parts[i]:Hide()
        end
        self.opened = false
    end

    function frame:ShowStatusText()
        self.text:Show()
    end

    function frame:HideStatusText()
        self.text:Hide()
    end

    function frame:SetStatusText(text)
        self.text:SetText(text)
    end

    function frame:OnClose(handler)
        self.close:SetScript("OnClick", handler)
    end

    return frame
end
