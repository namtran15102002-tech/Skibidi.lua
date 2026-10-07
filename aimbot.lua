-- Chờ game tải hoàn tất dữ liệu
if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Đợi PlayerGui sẵn sàng
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ====================================================================
-- BIẾN CẤU HÌNH & TRẠNG THÁI HỆ THỐNG
-- ====================================================================
local AimlockEnabled = false
local HardLockEnabled = false
local FOV_RADIUS = 75
local UNLOCK_RADIUS = 35 -- Vuốt màn hình lệch quá 35 pixel sẽ tự unlock
local TARGET_PART = "Head"
local LockedTarget = nil -- Giữ chặt mục tiêu duy nhất khi dính hardlock

-- Các tính năng bổ sung
local Config = {
    SpeedEnabled = false,
    SpeedValue = 16,
    JumpEnabled = false,
    JumpValue = 50,
    TeleportDistance = 10,
    NoclipEnabled = false,
    RotationalShift = false,
    ESPEnabled = false,
    ESPDistanceLimit = 500
}

-- Khởi tạo vòng tròn FOV (Drawing API)
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1.5
FOVCircle.Color = Color3.fromRGB(0, 255, 0)
FOVCircle.Filled = false
FOVCircle.Radius = FOV_RADIUS
FOVCircle.Visible = false

-- Phục vụ cho tính năng Rotational Shift (Xoay quanh mục tiêu)
local rotateAngle = 0

-- ====================================================================
-- HÀM BỔ TRỢ & KIỂM TRA TIA QUÉT (LINE OF SIGHT)
-- ====================================================================
local function getClosestPlayerToCenter()
    if HardLockEnabled and LockedTarget then
        -- Nếu đang hardlock và mục tiêu vẫn hợp lệ thì giữ nguyên không đổi
        if LockedTarget.Character and LockedTarget.Character:FindFirstChild(TARGET_PART) and LockedTarget.Character:FindFirstChildOfClass("Humanoid") then
            if LockedTarget.Character:FindFirstChildOfClass("Humanoid").Health > 0 then
                return LockedTarget
            end
        end
        LockedTarget = nil
    end

    local closestPlayer = nil
    local shortestDistance = math.huge
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild(TARGET_PART) and player.Character:FindFirstChildOfClass("Humanoid") then
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if humanoid.Health > 0 then
                local targetPart = player.Character[TARGET_PART]
                
                -- Khởi tạo Raycast kiểm tra vật cản ẩn khuất tường
                local raycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {LocalPlayer.Character, player.Character}
                
                local origin = Camera.CFrame.Position
                local direction = targetPart.Position - origin
                local raycastResult = workspace:Raycast(origin, direction, raycastParams)
                
                if not raycastResult then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        local targetPos2D = Vector2.new(screenPos.X, screenPos.Y)
                        local distanceToCenter = (targetPos2D - screenCenter).Magnitude
                        
                        if distanceToCenter <= FOV_RADIUS and distanceToCenter < shortestDistance then
                            closestPlayer = player
                            shortestDistance = distanceToCenter
                        end
                    end
                end
            end
        end
    end
    return closestPlayer
end

-- ====================================================================
-- VÒNG LẶP LOGIC CHÍNH (RENDERSTEPPED & STEPPED)
-- ====================================================================

-- Quản lý ESP Drawing cache để tránh rác bộ nhớ
local espCache = {}

local function clearESP()
    for _, storage in pairs(espCache) do
        if storage.Box then storage.Box.Visible = false; storage.Box:Remove() end
        if storage.Tracer then storage.Tracer.Visible = false; storage.Tracer:Remove() end
        if storage.Text then storage.Text.Visible = false; storage.Text:Remove() end
    end
    table.clear(espCache)
end

RunService.RenderStepped:Connect(function(dt)
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    FOVCircle.Position = screenCenter
    FOVCircle.Visible = AimlockEnabled

    -- 1. XỬ LÝ AIMLOCK & HARD AIMLOCK CHUYÊN NGHIỆP TRÊN MOBILE
    if AimlockEnabled then
        local target = getClosestPlayerToCenter()
        if target and target.Character and target.Character:FindFirstChild(TARGET_PART) then
            if HardLockEnabled then LockedTarget = target end
            
            local head = target.Character[TARGET_PART]
            local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
            local targetPos2D = Vector2.new(screenPos.X, screenPos.Y)
            local distFromCenter = (targetPos2D - screenCenter).Magnitude

            -- Tự động hủy theo dõi (Unlock) khi vuốt màn hình kéo tâm lệch quá 35 pixels
            if distFromCenter > UNLOCK_RADIUS and UserInputService:GetPanGestureThreshold() > 0 then
                LockedTarget = nil
            else
                -- Giải pháp lookAt hoàn hảo ép buộc camera xoay kể cả góc nhìn thứ nhất
                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, head.Position)
            end
        else
            LockedTarget = nil
        end
    else
        LockedTarget = nil
    end

    -- 2. XỬ LÝ KHẢ BẢNH VÒNG TRÒN (ROTATIONAL SHIFT)
    if Config.RotationalShift and AimlockEnabled and (LockedTarget or getClosestPlayerToCenter()) then
        local currentTarget = LockedTarget or getClosestPlayerToCenter()
        if currentTarget and currentTarget.Character and currentTarget.Character:FindFirstChild("HumanoidRootPart") then
            local rootPart = currentTarget.Character.HumanoidRootPart
            rotateAngle = rotateAngle + (math.rad(180) * dt) -- Tốc độ xoay vòng quanh
            local offset = Vector3.new(math.cos(rotateAngle), 0, math.sin(rotateAngle)) * Config.TeleportDistance
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(rootPart.Position + offset + Vector3.new(0, 2, 0), rootPart.Position)
            end
        end
    end

    -- 3. XỬ LÝ HỆ THỐNG ESP (KHOẢNG CÁCH, MÁU, KHUNG XƯƠNG ROOTPART, DÂY CO GIÃN)
    if Config.ESPEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Character:FindFirstChildOfClass("Humanoid") then
                local root = p.Character.HumanoidRootPart
                local hum = p.Character:FindFirstChildOfClass("Humanoid")
                
                if hum.Health > 0 then
                    local pPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                    local distance = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and (LocalPlayer.Character.HumanoidRootPart.Position - root.Position).Magnitude or 0
                    
                    if onScreen and distance <= Config.ESPDistanceLimit then
                        if not espCache[p.Name] then
                            espCache[p.Name] = {
                                Box = Drawing.new("Square"),
                                Tracer = Drawing.new("Line"),
                                Text = Drawing.new("Text")
                            }
                        end
                        
                        local cache = espCache[p.Name]
                        
                        -- Cấu hình Khung xương rút gọn (Box RootPart)
                        cache.Box.Size = Vector2.new(50, 50)
                        cache.Box.Position = Vector2.new(pPos.X - 25, pPos.Y - 25)
                        cache.Box.Color = Color3.fromRGB(255, 0, 0)
                        cache.Box.Thickness = 1
                        cache.Box.Filled = false
                        cache.Box.Visible = true
                        
                        -- Cấu hình chữ thông tin Máu và Khoảng cách cm (1 Stud tương ứng ~28cm)
                        cache.Text.Text = string.format("HP: %d | Dis: %.1f cm", math.floor(hum.Health), distance * 28)
                        cache.Text.Position = Vector2.new(pPos.X - 40, pPos.Y - 45)
                        cache.Text.Size = 14
                        cache.Text.Color = Color3.fromRGB(255, 255, 255)
                        cache.Text.Center = true
                        cache.Text.Outline = true
                        cache.Text.Visible = true
                        
                        -- Cấu hình sợi dây màn hình tự co giãn theo khoảng cách
                        cache.Tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        cache.Tracer.To = Vector2.new(pPos.X, pPos.Y)
                        cache.Tracer.Color = Color3.fromRGB(255, 255, 0)
                        cache.Tracer.Thickness = math.clamp(5 - (distance / 100), 1, 4) -- Càng gần dây càng to, xa càng mảnh
                        cache.Tracer.Visible = true
                        continue
                    end
                end
        end
            if espCache[p.Name] then
                espCache[p.Name].Box.Visible = false
                espCache[p.Name].Tracer.Visible = false
                espCache[p.Name].Text.Visible = false
            end
        end
    else
        clearESP()
    end
end)

-- Vòng lặp quản lý vật lý: Speed bằng lực, Noclip, và Nhảy cao
RunService.Stepped:Connect(function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
        local root = LocalPlayer.Character.HumanoidRootPart
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        
        -- 1. Cơ chế Noclip triệt tiêu va chạm vật lý
        if Config.NoclipEnabled then
            for _, part in pairs(LocalPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end

        -- 2. Tăng Tốc Độ bằng lực đẩy bổ sung (Không triệt tiêu trọng lực rơi tự do)
        if Config.SpeedEnabled and hum.MoveDirection.Magnitude > 0 then
            local extraSpeed = Config.SpeedValue - 16
            if extraSpeed > 0 then
                root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + (hum.MoveDirection * extraSpeed * 0.15)
            end
        end

        -- 3. Cập nhật lực Nhảy cao tùy chỉnh
        if Config.JumpEnabled then
            hum.JumpPower = Config.JumpValue
            hum.UseJumpPower = true
        else
            hum.UseJumpPower = false
        end
    end
end)

-- ====================================================================
-- GIAO DIỆN MENU PHÁT TRIỂN CHUYÊN NGHIỆP TRÊN MOBILE (DELTA)
-- ====================================================================
if PlayerGui:FindFirstChild("MobileMegaMenuGui") then
    PlayerGui.MobileMegaMenuGui:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MobileMegaMenuGui"
ScreenGui.Parent = PlayerGui
ScreenGui.ResetOnSpawn = false

-- NÚT MỞ/ĐÓNG MENU CHÍNH (TOGGLE MENU BUTTON)
local MenuToggleButton = Instance.new("TextButton")
MenuToggleButton.Name = "MenuToggleButton"
MenuToggleButton.Parent = ScreenGui
MenuToggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MenuToggleButton.Position = UDim2.new(0.05, 0, 0.15, 0)
MenuToggleButton.Size = UDim2.new(0, 90, 0, 40)
MenuToggleButton.Font = Enum.Font.SourceSansBold
MenuToggleButton.Text = "📜 MENU"
MenuToggleButton.TextColor3 = Color3.fromRGB(0, 255, 150)
MenuToggleButton.TextSize = 14
local MenuCorner = Instance.new("UICorner")
MenuCorner.CornerRadius = UDim.new(0, 8)
MenuCorner.Parent = MenuToggleButton

-- KHUNG MENU CHÍNH (MAIN MENU FRAME)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.Position = UDim2.new(0.25, 0, 0.2, 0)
MainFrame.Size = UDim2.new(0, 320, 0, 340)
MainFrame.Visible = false
local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 12)
FrameCorner.Parent = MainFrame

-- Thanh tiêu đề kéo thả
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 0, 35)
TitleLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
TitleLabel.Text = "   CAMERA LOCK-ON PRO MENU"
TitleLabel.Font = Enum.Font.SourceSansBold
TitleLabel.TextSize = 14
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame
local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 12)
TitleCorner.Parent = TitleLabel

local Container = Instance.new("ScrollingFrame")
Container.Size = UDim2.new(1, -10, 1, -45)
Container.Position = UDim2.new(0, 5, 0, 40)
Container.BackgroundTransparency = 1
Container.CanvasSize = UDim2.new(0, 0, 0, 480)
Container.ScrollBarThickness = 4
Container.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = Container
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 6)

-- THIẾT LẬP KÉO THẢ (DRAGGABLE) CHO MENU VÀ NÚT BẤM
local function makeDraggable(guiObject)
    local dragging, dragInput, dragStart, startPos
    guiObject.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    guiObject.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end
makeDraggable(MenuToggleButton)
makeDraggable(MainFrame)

MenuToggleButton.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- HÀM TẠO NÚT BẤM TOGGLE TRONG MENU
local function createToggleButton(text, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 35)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(50, 50, 50)
    btn.Font = Enum.Font.SourceSansBold
    btn.Text = text .. (defaultState and ": ON" or ": OFF")
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 14
    btn.Parent = Container
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = btn
    
    local state = defaultState
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(50, 50, 50)
        btn.Text = text .. (state and ": ON" or ": OFF")
        callback(state)
    end)
    return btn
end

-- HÀM TẠO KHUNG NHẬP DỮ LIỆU (BOX INPUT)
local function createTextBoxElement(placeholder, defaultValue, callback)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -10, 0, 35)
    box.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    box.Font = Enum.Font.SourceSans
    box.PlaceholderText = placeholder
    box.Text = tostring(defaultValue)
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 14
    box.ClipsDescendants = true
    box.Parent = Container
    local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = box
    
    box.FocusLost:Connect(function(enterPressed)
        local num = tonumber(box.Text)
        if num then
            callback(num)
        end
    end)
end

-- ====================================================================
-- KẾT NỐI TOÀN BỘ CHỨC NĂNG VÀO MENU
-- ====================================================================

-- 1. Nút điều khiển Hệ thống Aimlock chính
createToggleButton("Hệ Thống Aimlock Base", AimlockEnabled, function(val)
    AimlockEnabled = val
end)

-- 2. Nút Hard Aimlock (Giữ chặt 1 mục tiêu không đổi)
createToggleButton("Chế độ Hard Aimlock", HardLockEnabled, function(val)
    HardLockEnabled = val
    if not val then LockedTarget = nil end
end)

-- 3. Nhóm tính năng SPEED (Tốc độ)
createToggleButton("Kích hoạt Speed (Lực)", Config.SpeedEnabled, function(val)
    Config.SpeedEnabled = val
end)
createTextBoxElement("Gõ Tốc độ mong muốn (Max: 666)", Config.SpeedValue, function(val)
    Config.SpeedValue = math.clamp(val, 1, 666)
end)

-- 4. Nhóm tính năng JUMP (Nhảy cao)
createToggleButton("Kích hoạt Nhảy Cao", Config.JumpEnabled, function(val)
    Config.JumpEnabled = val
end)
createTextBoxElement("Gõ Lực nhảy mong muốn (Max: 200)", Config.JumpValue, function(val)
    Config.JumpValue = math.clamp(val, 1, 200)
end)

-- 5. Tính năng Dịch chuyển ra sau lưng (Move Behind)
local TeleportButton = Instance.new("TextButton")
TeleportButton.Size = UDim2.new(1, -10, 0, 35)
TeleportButton.BackgroundColor3 = Color3.fromRGB(130, 80, 0)
TeleportButton.Font = Enum.Font.SourceSansBold
TeleportButton.Text = "⚡ DỊCH CHUYỂN SAU LƯNG TARGET"
TeleportButton.TextColor3 = Color3.fromRGB(255, 255, 255)
TeleportButton.TextSize = 14
TeleportButton.Parent = Container
local tc = Instance.new("UICorner") tc.CornerRadius = UDim.new(0, 6) tc.Parent = TeleportButton

TeleportButton.MouseButton1Click:Connect(function()
    local target = LockedTarget or getClosestPlayerToCenter()
    if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
        local rootPart = target.Character.HumanoidRootPart
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            -- Tính toán vị trí cách sau lưng 1 khoảng cố định được cấu hình
            local backPosition = rootPart.CFrame * CFrame.new(0, 0, Config.TeleportDistance)
            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(backPosition.Position, rootPart.Position)
        end
    end
end)

createTextBoxElement("Khoảng cách Tele/Xoay Stud", Config.TeleportDistance, function(val)
    Config.TeleportDistance = val
end)

-- 6. Tính năng Noclip (Đi xuyên tường vật lý)
createToggleButton("Kích hoạt Noclip Xuyên Tường", Config.NoclipEnabled, function(val)
    Config.NoclipEnabled = val
end)

-- 7. Tính năng Khả bảnh vòng tròn (Rotational Shift)
createToggleButton("Xoay Vòng Tròn Khả Bảnh", Config.RotationalShift, function(val)
    Config.RotationalShift = val
end)

-- 8. Nhóm tính năng ESP Tổng hợp
createToggleButton("Kích hoạt ESP Thần Nhãn", Config.ESPEnabled, function(val)
    Config.ESPEnabled = val
end)
createTextBoxElement("Giới hạn khoảng cách hiển thị ESP", Config.ESPDistanceLimit, function(val)
Config.ESPDistanceLimit = val
end)
