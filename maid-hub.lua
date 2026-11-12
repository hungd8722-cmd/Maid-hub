if not game:IsLoaded() then
    game.Loaded:Wait()
end

local CONFIG = {
    HubName          = "Maid Hub",
    SubTitle         = "v5.8",
    Version          = "5.8",
    SaveFolder       = "maidhub.json",
    ConfigFile       = "MaidHub_Config.json",
    DiscordLink      = "https://discord.gg/9KhYDxXMQP",
    DefaultKeybind   = Enum.KeyCode.LeftControl,
    DefaultTheme     = "Dark",
    MobileIcon       = "rbxassetid://104140373842031",
    MobileThumb      = "rbxthumb://type=Asset&id=104140373842031&w=420&h=420",
    LibraryUrls      = {
        "https://raw.githubusercontent.com/tlredz/Library/refs/heads/main/redz-V5-remake/main.luau",
        "https://raw.githubusercontent.com/REDzHUB/RedzLibV5/main/Source.Lua",
    },
    Icons            = {
        Info     = "Info",
        Main     = "rbxassetid://10723407389",
        Config   = "rbxassetid://10723415903",
        Settings = "rbxassetid://7734053495",
        About    = "rbxassetid://10709783577",
    }
}

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")
local CoreGui            = game:GetService("CoreGui")
local Stats              = game:GetService("Stats")
local Lighting           = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local StartTime   = os.clock()
local running     = true

local function getSafeGuiParent()
    local ok, hui = pcall(function()
        return type(gethui) == "function" and gethui() or nil
    end)
    if ok and hui then return hui end

    local okCore, _ = pcall(function()
        return CoreGui.Name
    end)
    if okCore then return CoreGui end

    return LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local GlobalEnv = (type(getgenv) == "function" and getgenv()) or _G

if GlobalEnv.MaidHub_Cleanup then
    pcall(GlobalEnv.MaidHub_Cleanup)
end

local MaidHub_Connections = {}
local MaidHub_Instances   = {}
local Window              = nil

local function trackConnection(conn)
    if conn then
        table.insert(MaidHub_Connections, conn)
    end
    return conn
end

local function trackInstance(inst)
    if inst then
        table.insert(MaidHub_Instances, inst)
    end
    return inst
end

local function CleanupAll()
    running = false

    for _, conn in ipairs(MaidHub_Connections) do
        pcall(function()
            if typeof(conn) == "RBXScriptConnection" or type(conn) == "table" then
                if conn.Disconnect then
                    conn:Disconnect()
                end
            end
        end)
    end
    table.clear(MaidHub_Connections)

    if Window then
        pcall(function()
            if type(Window.Destroy) == "function" then
                Window:Destroy()
            elseif type(Window.Delete) == "function" then
                Window:Delete()
            end
        end)
    end

    for _, inst in ipairs(MaidHub_Instances) do
        pcall(function()
            if inst and inst.Destroy then
                inst:Destroy()
            end
        end)
    end
    table.clear(MaidHub_Instances)

    local parents = { getSafeGuiParent(), CoreGui, LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui") }
    for _, parent in ipairs(parents) do
        if parent then
            pcall(function()
                for _, gui in ipairs(parent:GetChildren()) do
                    if gui:IsA("ScreenGui") then
                        if gui.Name == "MaidHub_ToastGui" or gui:GetAttribute("MaidHubManaged") then
                            gui:Destroy()
                        else
                            for _, desc in ipairs(gui:GetDescendants()) do
                                if desc:GetAttribute("MaidHubMinimizer") or (desc:IsA("TextLabel") and desc.Text == CONFIG.HubName) then
                                    gui:Destroy()
                                    break
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end

GlobalEnv.MaidHub_Connections = MaidHub_Connections
GlobalEnv.MaidHub_Cleanup     = CleanupAll

local redzlib = nil
local ToastScreenGui = nil
local ToastContainer = nil

local NOTIFY_COLORS = {
    Info    = Color3.fromRGB(56, 189, 248),
    Success = Color3.fromRGB(74, 222, 128),
    Warning = Color3.fromRGB(250, 204, 21),
    Error   = Color3.fromRGB(248, 113, 113),
}

local NOTIFY_PREFIX = {
    Info    = "ℹ️",
    Success = "✅",
    Warning = "⚠️",
    Error   = "❌",
}

local function ensureToastGui()
    if ToastScreenGui and ToastScreenGui.Parent then
        return ToastContainer
    end
    local parent = getSafeGuiParent()
    if not parent then return nil end

    ToastScreenGui = trackInstance(Instance.new("ScreenGui"))
    ToastScreenGui.Name = "MaidHub_ToastGui"
    ToastScreenGui.ResetOnSpawn = false
    ToastScreenGui.IgnoreGuiInset = true
    ToastScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ToastScreenGui:SetAttribute("MaidHubManaged", true)
    ToastScreenGui.Parent = parent

    ToastContainer = Instance.new("Frame")
    ToastContainer.Name = "ToastContainer"
    ToastContainer.Parent = ToastScreenGui
    ToastContainer.AnchorPoint = Vector2.new(1, 1)
    ToastContainer.Position = UDim2.new(1, -18, 1, -18)
    ToastContainer.Size = UDim2.new(0, 290, 1, -36)
    ToastContainer.BackgroundTransparency = 1

    local layout = Instance.new("UIListLayout")
    layout.Parent = ToastContainer
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.Padding = UDim.new(0, 8)

    return ToastContainer
end

local function Notify(title, content, notifyType, duration)
    if not running then return end
    title      = tostring(title or CONFIG.HubName)
    content    = tostring(content or "")
    notifyType = notifyType or "Info"
    duration   = tonumber(duration) or 3.5

    local prefix = NOTIFY_PREFIX[notifyType] or NOTIFY_PREFIX.Info
    local accent = NOTIFY_COLORS[notifyType] or NOTIFY_COLORS.Info
    local fullTitle = prefix .. " " .. title

    local usedNative = false
    if redzlib then
        pcall(function()
            local notifyFn = redzlib.Notify or redzlib.MakeNotify or redzlib.MakeNotifi or (Window and (Window.Notify or Window.MakeNotify))
            if type(notifyFn) == "function" then
                notifyFn(redzlib, {
                    Title = fullTitle,
                    Text = content,
                    Content = content,
                    Description = content,
                    Time = duration,
                    Duration = duration,
                })
                usedNative = true
            end
        end)
    end
    if usedNative then return end

    pcall(function()
        local container = ensureToastGui()
        if not container then return end

        local card = Instance.new("Frame")
        card.Name = "ToastCard"
        card.Parent = container
        card.Size = UDim2.new(1, 0, 0, 66)
        card.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
        card.BackgroundTransparency = 0.06
        card.BorderSizePixel = 0
        card.ClipsDescendants = true

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Color = accent
        stroke.Thickness = 1.2
        stroke.Transparency = 0.25
        stroke.Parent = card

        local bar = Instance.new("Frame")
        bar.Name = "AccentBar"
        bar.Parent = card
        bar.Size = UDim2.new(0, 4, 1, 0)
        bar.BackgroundColor3 = accent
        bar.BorderSizePixel = 0

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Parent = card
        titleLbl.BackgroundTransparency = 1
        titleLbl.Position = UDim2.new(0, 14, 0, 7)
        titleLbl.Size = UDim2.new(1, -22, 0, 20)
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Text = fullTitle
        titleLbl.TextColor3 = Color3.fromRGB(245, 245, 250)
        titleLbl.TextSize = 13
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.TextTruncate = Enum.TextTruncate.AtEnd

        local bodyLbl = Instance.new("TextLabel")
        bodyLbl.Parent = card
        bodyLbl.BackgroundTransparency = 1
        bodyLbl.Position = UDim2.new(0, 14, 0, 28)
        bodyLbl.Size = UDim2.new(1, -22, 0, 32)
        bodyLbl.Font = Enum.Font.Gotham
        bodyLbl.Text = content
        bodyLbl.TextColor3 = Color3.fromRGB(200, 200, 210)
        bodyLbl.TextSize = 12
        bodyLbl.TextWrapped = true
        bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
        bodyLbl.TextYAlignment = Enum.TextYAlignment.Top

        card.Position = UDim2.new(1, 40, 0, 0)
        TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 0, 0, 0)
        }):Play()

        task.delay(duration, function()
            if not card or not card.Parent then return end
            local fadeOut = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 0)
            })
            fadeOut:Play()
            task.wait(0.26)
            if card and card.Parent then
                card:Destroy()
            end
        end)
    end)
end

local ExecutorSupport = {
    Clipboard = type(setclipboard) == "function" or type(toclipboard) == "function",
    WriteFile = type(writefile) == "function",
    ReadFile  = type(readfile) == "function",
    IsFile    = type(isfile) == "function",
    DelFile   = type(delfile) == "function",
}

local function safeCopyClipboard(text)
    if not ExecutorSupport.Clipboard then
        Notify("Clipboard", "Executor của bạn không hỗ trợ setclipboard!", "Warning", 3.5)
        return false
    end
    local ok, err = pcall(function()
        if type(setclipboard) == "function" then
            setclipboard(tostring(text))
        elseif type(toclipboard) == "function" then
            toclipboard(tostring(text))
        end
    end)
    if ok then
        return true
    else
        Notify("Clipboard", "Lỗi khi sao chép: " .. tostring(err), "Error", 3.5)
        return false
    end
end

local DEFAULT_STATE = {
    AutoSave         = true,
    ExampleToggle    = false,
    ExampleSlider    = 50,
    SingleDropdown   = "Chế độ A",
    MultiDropdown    = { ["Tùy chọn 1"] = true },
    ExampleText      = "",
    FeatureKeybind   = "E",
    MenuKeybind      = CONFIG.DefaultKeybind.Name,
    Theme            = CONFIG.DefaultTheme,
    ShowMobileButton = true,
}

local function cloneTable(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = cloneTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local CurrentState = cloneTable(DEFAULT_STATE)
local UIControls   = {}
local isApplyingConfig = false

local function SaveConfig(silent)
    if not (ExecutorSupport.WriteFile and HttpService) then
        if not silent then
            Notify("Config", "Executor không hỗ trợ writefile để lưu cấu hình!", "Warning", 4)
        end
        return false
    end

    local ok, err = pcall(function()
        local encoded = HttpService:JSONEncode(CurrentState)
        writefile(CONFIG.ConfigFile, encoded)
    end)

    if ok then
        if not silent then
            Notify("Config", "Đã lưu cấu hình vào " .. CONFIG.ConfigFile, "Success", 3)
        end
        return true
    else
        if not silent then
            Notify("Config", "Lỗi khi lưu cấu hình: " .. tostring(err), "Error", 4)
        end
        return false
    end
end

local function ApplyStateToUI()
    isApplyingConfig = true
    pcall(function()
        for key, ctrl in pairs(UIControls) do
            local val = CurrentState[key]
            if val ~= nil and type(ctrl) == "table" then
                if type(ctrl.Set) == "function" then
                    pcall(ctrl.Set, ctrl, val)
                elseif type(ctrl.SetValue) == "function" then
                    pcall(ctrl.SetValue, ctrl, val)
                end
            end
        end
    end)
    isApplyingConfig = false
end

local function LoadConfig(silent)
    if not (ExecutorSupport.ReadFile and ExecutorSupport.IsFile) then
        if not silent then
            Notify("Config", "Executor không hỗ trợ readfile / isfile!", "Warning", 4)
        end
        return false
    end

    local existsOk, exists = pcall(isfile, CONFIG.ConfigFile)
    if not existsOk or not exists then
        if not silent then
            Notify("Config", "Chưa có file cấu hình (" .. CONFIG.ConfigFile .. ")!", "Info", 3.5)
        end
        return false
    end

    local ok, decoded = pcall(function()
        local raw = readfile(CONFIG.ConfigFile)
        return HttpService:JSONDecode(raw)
    end)

    if ok and type(decoded) == "table" then
        for k, defaultVal in pairs(DEFAULT_STATE) do
            if decoded[k] ~= nil and type(decoded[k]) == type(defaultVal) then
                CurrentState[k] = decoded[k]
            end
        end
        ApplyStateToUI()
        if not silent then
            Notify("Config", "Đã tải cấu hình thành công!", "Success", 3)
        end
        return true
    else
        if not silent then
            Notify("Config", "File cấu hình bị hỏng hoặc không hợp lệ!", "Error", 4)
        end
        return false
    end
end

local function ResetConfig()
    CurrentState = cloneTable(DEFAULT_STATE)
    ApplyStateToUI()
    if ExecutorSupport.DelFile and ExecutorSupport.IsFile then
        pcall(function()
            if isfile(CONFIG.ConfigFile) then
                delfile(CONFIG.ConfigFile)
            end
        end)
    elseif ExecutorSupport.WriteFile then
        SaveConfig(true)
    end
    Notify("Config", "Đã khôi phục toàn bộ cài đặt về mặc định!", "Info", 3.5)
end

local function OnSettingChanged(key, value)
    CurrentState[key] = value
    if not isApplyingConfig and CurrentState.AutoSave then
        SaveConfig(true)
    end
end

for _, url in ipairs(CONFIG.LibraryUrls) do
    local ok, lib = pcall(function()
        local source = game:HttpGet(url)
        local fn = loadstring(source)
        return fn and fn() or nil
    end)
    if ok and type(lib) == "table" then
        redzlib = lib
        break
    else
        warn("[MaidHub] Thử tải RedzLib thất bại từ URL: " .. tostring(url))
    end
end

if not redzlib then
    warn("[MaidHub] Không thể tải thư viện RedzLib từ tất cả các nguồn!")
    Notify("Maid Hub - Lỗi tải UI", "Không thể tải thư viện RedzLib! Vui lòng kiểm tra kết nối mạng.", "Error", 6)
    return
end

local winOk, winResult = pcall(function()
    return redzlib:MakeWindow({
        Title      = CONFIG.HubName,
        SubTitle   = CONFIG.SubTitle,
        SaveFolder = CONFIG.SaveFolder
    })
end)

if not winOk or not winResult then
    warn("[MaidHub] Khởi tạo cửa sổ MakeWindow thất bại: " .. tostring(winResult))
    Notify("Maid Hub", "Không thể khởi tạo cửa sổ giao diện!", "Error", 5)
    return
end
Window = winResult

pcall(function()
    local parent = getSafeGuiParent()
    if parent then
        for _, gui in ipairs(parent:GetChildren()) do
            if gui:IsA("ScreenGui") then
                for _, desc in ipairs(gui:GetDescendants()) do
                    if desc:IsA("TextLabel") and desc.Text == CONFIG.HubName then
                        gui:SetAttribute("MaidHubManaged", true)
                        trackInstance(gui)
                        break
                    end
                end
            end
        end
    end
end)

local Minimizer = nil
local MobileButton = nil

pcall(function()
    if type(Window.NewMinimizer) == "function" then
        Minimizer = Window:NewMinimizer({
            KeyCode = CONFIG.DefaultKeybind
        })
    end
end)

if Minimizer and type(Minimizer.CreateMobileMinimizer) == "function" then
    pcall(function()
        MobileButton = Minimizer:CreateMobileMinimizer({
            Image                  = CONFIG.MobileIcon,
            BackgroundColor3       = Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 0.15
        })
    end)
end

if MobileButton and typeof(MobileButton) == "Instance" and MobileButton:IsA("GuiObject") then
    trackInstance(MobileButton)

    local isUpdatingIcon = false
    local function applyMobileStyle(target)
        if not running or not target or not target:IsA("GuiObject") then return end
        target:SetAttribute("MaidHubMinimizer", true)
        target.BorderSizePixel = 0
        if target == MobileButton then
            target.BackgroundTransparency = 0.15
        else
            target.BackgroundTransparency = 1
        end
        if target:IsA("ImageButton") or target:IsA("ImageLabel") then
            target.Image = CONFIG.MobileIcon
            target.ImageTransparency = 0
            target.ImageColor3 = Color3.fromRGB(255, 255, 255)
            target.ScaleType = Enum.ScaleType.Fit
        end
    end

    local function setupMobileOverlayOnce()
        if not running or isUpdatingIcon or not MobileButton or not MobileButton.Parent then return end
        isUpdatingIcon = true
        pcall(function()
            applyMobileStyle(MobileButton)
            for _, child in ipairs(MobileButton:GetDescendants()) do
                if child.Name ~= "MaidHubIcon" then
                    applyMobileStyle(child)
                end
            end

            local overlay = MobileButton:FindFirstChild("MaidHubIcon")
            if not overlay then
                overlay = Instance.new("ImageLabel")
                overlay.Name = "MaidHubIcon"
                overlay.Parent = MobileButton
                overlay.AnchorPoint = Vector2.new(0.5, 0.5)
                overlay.Position = UDim2.fromScale(0.5, 0.5)
                overlay.Size = UDim2.fromScale(1, 1)
                overlay.BackgroundTransparency = 1
                overlay.BorderSizePixel = 0
                overlay.ZIndex = MobileButton.ZIndex + 2
                overlay.ScaleType = Enum.ScaleType.Fit
            end
            overlay.Visible = true
            overlay.Image = CONFIG.MobileThumb
            overlay.ImageTransparency = 0
            overlay.ImageColor3 = Color3.fromRGB(255, 255, 255)
        end)
        isUpdatingIcon = false
    end

    setupMobileOverlayOnce()

    trackConnection(MobileButton.DescendantAdded:Connect(function(desc)
        if not running or desc.Name == "MaidHubIcon" then return end
        task.defer(setupMobileOverlayOnce)
    end))
end

local function SafeSetDesc(paragraphObj, text)
    if not paragraphObj then return end
    pcall(function()
        if type(paragraphObj.SetDesc) == "function" then
            paragraphObj:SetDesc(text)
        elseif type(paragraphObj.Set) == "function" then
            paragraphObj:Set(text)
        end
    end)
end

local function SafeAddSection(tab, title)
    local res = nil
    pcall(function()
        res = tab:AddSection(title)
    end)
    if not res then
        pcall(function()
            res = tab:AddSection({ title })
        end)
    end
    return res
end

local function SafeAddParagraph(tab, title, desc)
    local res = nil
    pcall(function()
        res = tab:AddParagraph(title, desc)
    end)
    if not res then
        pcall(function()
            res = tab:AddParagraph({ title, desc })
        end)
    end
    return res
end

local function SafeAddButton(tab, opts)
    local res = nil
    pcall(function()
        res = tab:AddButton(opts)
    end)
    return res
end

local function SafeAddToggle(tab, opts)
    local res = nil
    pcall(function()
        res = tab:AddToggle(opts)
    end)
    return res
end

local function SafeAddSlider(tab, opts)
    local res = nil
    pcall(function()
        res = tab:AddSlider({
            Name        = opts.Name,
            Description = opts.Description or "",
            Min         = opts.Min,
            Max         = opts.Max,
            MinValue    = opts.Min,
            MaxValue    = opts.Max,
            Increase    = opts.Increase or 1,
            Default     = opts.Default,
            Callback    = opts.Callback
        })
    end)
    return res
end

local function SafeAddDropdown(tab, opts)
    local res = nil
    pcall(function()
        res = tab:AddDropdown({
            Name        = opts.Name,
            Description = opts.Description or "",
            Options     = opts.Options or {},
            Default     = opts.Default,
            MultiSelect = opts.MultiSelect or false,
            Callback    = opts.Callback
        })
    end)
    return res
end

local function SafeAddTextBox(tab, opts)
    local res = nil
    pcall(function()
        if type(tab.AddTextBox) == "function" then
            res = tab:AddTextBox({
                Name            = opts.Name,
                Description     = opts.Description or "",
                Default         = opts.Default or "",
                PlaceholderText = opts.PlaceholderText or "Nhập nội dung...",
                ClearText       = opts.ClearText or false,
                Callback        = opts.Callback
            })
        end
    end)
    if not res then
        SafeAddParagraph(tab, opts.Name, "Phiên bản RedzLib hiện tại không hỗ trợ TextBox trực tiếp.")
    end
    return res
end

local KEYBIND_LIST = { "RightControl", "LeftControl", "RightShift", "Insert", "Delete", "F", "E", "Q", "R", "Z", "X", "C", "V" }

local function SafeAddKeybind(tab, opts)
    local currentKeyName = opts.Default or "E"
    local callback = opts.Callback
    local control = nil

    local hasNativeKeybind = false
    pcall(function()
        if type(tab.AddKeybind) == "function" then
            control = tab:AddKeybind({
                Name     = opts.Name,
                KeyCode  = currentKeyName,
                Default  = currentKeyName,
                Callback = function(val)
                    if type(val) == "string" then
                        currentKeyName = val
                    elseif typeof(val) == "EnumItem" then
                        currentKeyName = val.Name
                    end
                    if callback then callback(currentKeyName, true) end
                end
            })
            hasNativeKeybind = (control ~= nil)
        end
    end)

    if not hasNativeKeybind then
        control = SafeAddDropdown(tab, {
            Name        = opts.Name,
            Description = opts.Description or "Chọn phím tắt kích hoạt",
            Options     = opts.Options or KEYBIND_LIST,
            Default     = currentKeyName,
            MultiSelect = false,
            Callback    = function(selectedKey)
                if type(selectedKey) == "string" and selectedKey ~= "" then
                    currentKeyName = selectedKey
                    if opts.OnKeyChanged then
                        opts.OnKeyChanged(currentKeyName)
                    end
                end
            end
        })

        if callback then
            trackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
                if not running or gameProcessed then return end
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    if input.KeyCode.Name == currentKeyName then
                        pcall(callback, currentKeyName, false)
                    end
                end
            end))
        end
    end

    return control
end

local Tabs = {
    Info     = Window:MakeTab({ Title = "Info",          Icon = CONFIG.Icons.Info }),
    Main     = Window:MakeTab({ Title = "Main/Features", Icon = CONFIG.Icons.Main }),
    Config   = Window:MakeTab({ Title = "Config",        Icon = CONFIG.Icons.Config }),
    Settings = Window:MakeTab({ Title = "Settings",      Icon = CONFIG.Icons.Settings }),
    About    = Window:MakeTab({ Title = "About",         Icon = CONFIG.Icons.About }),
}

SafeAddSection(Tabs.Info, "Thông Tin Người Chơi")

local PlayerName = LocalPlayer and LocalPlayer.DisplayName or "Player"
local PlayerUser = LocalPlayer and LocalPlayer.Name or "Unknown"
local PlayerId   = LocalPlayer and tostring(LocalPlayer.UserId) or "0"

SafeAddParagraph(Tabs.Info, "Tài Khoản", string.format("%s (@%s)\nUserId: %s", PlayerName, PlayerUser, PlayerId))

SafeAddSection(Tabs.Info, "Thông Tin Máy Chủ (Server Status)")

local PlaceName = "Đang tải..."
task.spawn(function()
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok and info and info.Name then
        PlaceName = info.Name
    else
        PlaceName = tostring(game.Name or "Unknown Game")
    end
end)

local GameInfoParagraph   = SafeAddParagraph(Tabs.Info, "Trò Chơi & Máy Chủ", "Đang tải thông tin...")
local ClientStatParagraph = SafeAddParagraph(Tabs.Info, "Hiệu Năng & Mạng", "FPS: 60 | Ping: 0 ms")
local TimeParagraph       = SafeAddParagraph(Tabs.Info, "Thời Gian Hoạt Động", "Đang tính toán...")
local JobIdText           = (game.JobId ~= "" and game.JobId) or "Private / Studio Server"
SafeAddParagraph(Tabs.Info, "Server JobId", JobIdText)

SafeAddButton(Tabs.Info, {
    Name = "📋 Copy Server JobId",
    Description = "Sao chép mã phòng (JobId) hiện tại vào bộ nhớ tạm",
    Callback = function()
        if safeCopyClipboard(JobIdText) then
            Notify("Đã sao chép", "Đã lưu JobId vào Clipboard!", "Success", 3)
        end
    end
})

SafeAddSection(Tabs.Info, "Cộng Đồng")

SafeAddButton(Tabs.Info, {
    Name = "📋 Copy Discord Link",
    Description = "Sao chép liên kết máy chủ Discord chính thức của " .. CONFIG.HubName,
    Callback = function()
        if safeCopyClipboard(CONFIG.DiscordLink) then
            Notify("Discord", "Đã sao chép link Discord: " .. CONFIG.DiscordLink, "Success", 3.5)
        end
    end
})

local currentFPS = 60
local frameCount = 0
local lastFpsMeasure = os.clock()

trackConnection(RunService.RenderStepped:Connect(function()
    if not running then return end
    frameCount += 1
    local now = os.clock()
    local elapsed = now - lastFpsMeasure
    if elapsed >= 0.5 then
        currentFPS = math.clamp(math.floor((frameCount / elapsed) + 0.5), 1, 999)
        frameCount = 0
        lastFpsMeasure = now
    end
end))

task.spawn(function()
    while running do
        pcall(function()
            local curPlayers = #Players:GetPlayers()
            local maxPlayers = Players.MaxPlayers
            SafeSetDesc(GameInfoParagraph, string.format(
                "Tên Game: %s\nPlaceId: %d\nNgười chơi: %d / %d",
                PlaceName, game.PlaceId, curPlayers, maxPlayers
            ))

            local ping = 0
            local networkStats = Stats:FindFirstChild("Network")
            if networkStats and networkStats:FindFirstChild("ServerStatsItem") then
                local pingStat = networkStats.ServerStatsItem:FindFirstChild("Data Ping")
                if pingStat then
                    ping = math.floor(pingStat:GetValue())
                end
            end
            SafeSetDesc(ClientStatParagraph, string.format("FPS: %d | Ping: %d ms", currentFPS, ping))

            local uptimeSec = math.max(0, math.floor(os.clock() - StartTime))
            local uHours    = math.floor(uptimeSec / 3600)
            local uMins     = math.floor((uptimeSec % 3600) / 60)
            local uSecs     = uptimeSec % 60
            local uptimeStr = string.format("%02d:%02d:%02d", uHours, uMins, uSecs)

            local date    = os.date("*t")
            local hour    = date.hour % 24
            local ampm    = hour < 12 and "AM" or "PM"
            local timeStr = string.format("%02i:%02i:%02i %s", ((hour - 1) % 12) + 1, date.min, date.sec, ampm)
            local dateStr = string.format("%02d/%02d/%04d", date.day, date.month, date.year)

            SafeSetDesc(TimeParagraph, string.format(
                "Đã chạy (Uptime): %s\nGiờ hệ thống: %s • %s",
                uptimeStr, dateStr, timeStr
            ))
        end)
        task.wait(1)
    end
end)

SafeAddSection(Tabs.Main, "Công Tắc & Thanh Trượt (Toggle & Slider)")

UIControls.ExampleToggle = SafeAddToggle(Tabs.Main, {
    Name        = "Kích Hoạt Tính Năng Mẫu (Toggle)",
    Description = "Bật / tắt trạng thái mẫu và tự động lưu vào cấu hình",
    Default     = CurrentState.ExampleToggle,
    Callback    = function(state)
        OnSettingChanged("ExampleToggle", state)
    end
})

UIControls.ExampleSlider = SafeAddSlider(Tabs.Main, {
    Name        = "Thông Số Tùy Chỉnh (Slider)",
    Description = "Kéo để điều chỉnh giá trị từ Min (1) đến Max (200)",
    Min         = 1,
    Max         = 200,
    Increase    = 1,
    Default     = CurrentState.ExampleSlider,
    Callback    = function(value)
        OnSettingChanged("ExampleSlider", value)
    end
})

SafeAddSection(Tabs.Main, "Danh Sách Lựa Chọn (Dropdown Đơn & Đa Chọn)")

UIControls.SingleDropdown = SafeAddDropdown(Tabs.Main, {
    Name        = "Chế Độ Hoạt Động (Chọn Một)",
    Description = "Dropdown cho phép chọn duy nhất 1 mục",
    Options     = { "Chế độ A", "Chế độ B", "Chế độ C", "Chế độ D" },
    Default     = CurrentState.SingleDropdown,
    MultiSelect = false,
    Callback    = function(selected)
        OnSettingChanged("SingleDropdown", selected)
    end
})

UIControls.MultiDropdown = SafeAddDropdown(Tabs.Main, {
    Name        = "Danh Sách Mục Tiêu (Chọn Nhiều)",
    Description = "Dropdown hỗ trợ chọn nhiều mục cùng lúc (MultiSelect)",
    Options     = { "Tùy chọn 1", "Tùy chọn 2", "Tùy chọn 3", "Tùy chọn 4" },
    Default     = { "Tùy chọn 1" },
    MultiSelect = true,
    Callback    = function(selectedTable)
        OnSettingChanged("MultiDropdown", selectedTable)
    end
})

SafeAddSection(Tabs.Main, "Nhập Liệu & Phím Tắt (TextBox & Keybind)")

UIControls.ExampleText = SafeAddTextBox(Tabs.Main, {
    Name            = "Nhập Tham Số Tùy Chỉnh (TextBox)",
    Description     = "Nhập chuỗi ký tự hoặc thông số rồi nhấn Enter",
    Default         = CurrentState.ExampleText,
    PlaceholderText = "Nhập nội dung tại đây...",
    ClearText       = false,
    Callback        = function(text)
        OnSettingChanged("ExampleText", text)
    end
})

UIControls.FeatureKeybind = SafeAddKeybind(Tabs.Main, {
    Name         = "Phím Tắt Kích Hoạt Nhanh (Keybind)",
    Description  = "Nhấn phím đã chọn trên bàn phím để gọi nhanh sự kiện",
    Default      = CurrentState.FeatureKeybind,
    OnKeyChanged = function(newKey)
        OnSettingChanged("FeatureKeybind", newKey)
        Notify("Keybind", "Đã đổi phím tắt tính năng sang: " .. tostring(newKey), "Info", 2.5)
    end,
    Callback     = function(keyName)
        Notify("Phím tắt", "Bạn vừa kích hoạt phím tắt [" .. tostring(keyName) .. "]!", "Info", 2)
    end
})

SafeAddButton(Tabs.Main, {
    Name        = "⚡ Thực Thi Tác Vụ Mẫu (Button)",
    Description = "Nút bấm thực thi 1 lần",
    Callback    = function()
        Notify("Maid Hub", "Đã kích hoạt nút tác vụ mẫu thành công!", "Success", 2.5)
    end
})

SafeAddSection(Tabs.Config, "Quản Lý Tệp Cấu Hình (" .. CONFIG.ConfigFile .. ")")

SafeAddParagraph(
    Tabs.Config,
    "Trạng Thái Hỗ Trợ Executor",
    string.format(
        "• Ghi file (writefile): %s\n• Đọc file (readfile): %s\n• Kiểm tra file (isfile): %s",
        ExecutorSupport.WriteFile and "Hỗ trợ ✅" or "Không hỗ trợ ❌",
        ExecutorSupport.ReadFile and "Hỗ trợ ✅" or "Không hỗ trợ ❌",
        ExecutorSupport.IsFile and "Hỗ trợ ✅" or "Không hỗ trợ ❌"
    )
)

UIControls.AutoSave = SafeAddToggle(Tabs.Config, {
    Name        = "Tự Động Lưu Khi Thay Đổi (Auto-Save)",
    Description = "Tự động ghi lại file JSON mỗi khi bạn bật/tắt hoặc chỉnh thông số",
    Default     = CurrentState.AutoSave,
    Callback    = function(val)
        CurrentState.AutoSave = val
        if val then
            SaveConfig(true)
            Notify("Auto-Save", "Đã bật tự động lưu cấu hình!", "Info", 2.5)
        end
    end
})

SafeAddButton(Tabs.Config, {
    Name        = "💾 Lưu Cấu Hình (Save Config)",
    Description = "Lưu toàn bộ thiết lập hiện tại vào file " .. CONFIG.ConfigFile,
    Callback    = function()
        SaveConfig(false)
    end
})

SafeAddButton(Tabs.Config, {
    Name        = "📂 Tải Cấu Hình (Load Config)",
    Description = "Đọc và áp dụng cấu hình từ file " .. CONFIG.ConfigFile,
    Callback    = function()
        LoadConfig(false)
    end
})

SafeAddButton(Tabs.Config, {
    Name        = "🔄 Đặt Lại Mặc Định (Reset Config)",
    Description = "Khôi phục toàn bộ cài đặt về trạng thái gốc ban đầu",
    Callback    = function()
        ResetConfig()
    end
})

SafeAddSection(Tabs.Settings, "Cá Nhân Hóa Giao Diện (Interface)")

UIControls.Theme = SafeAddDropdown(Tabs.Settings, {
    Name        = "Chủ Đề Giao Diện (Theme)",
    Description = "Thay đổi tông màu chủ đạo của cửa sổ RedzLib",
    Options     = { "Dark", "Darker", "Purple" },
    Default     = CurrentState.Theme,
    MultiSelect = false,
    Callback    = function(themeName)
        OnSettingChanged("Theme", themeName)
        local applied = false
        pcall(function()
            if type(redzlib.SetTheme) == "function" then
                redzlib:SetTheme(themeName)
                applied = true
            elseif Window and type(Window.SetTheme) == "function" then
                Window:SetTheme(themeName)
                applied = true
            end
        end)
        if applied then
            Notify("Theme", "Đã chuyển sang giao diện: " .. tostring(themeName), "Info", 2.5)
        else
            Notify("Theme", "Phiên bản RedzLib hiện tại không hỗ trợ đổi Theme động.", "Warning", 3)
        end
    end
})

UIControls.MenuKeybind = SafeAddDropdown(Tabs.Settings, {
    Name        = "Phím Ẩn / Hiện Menu (PC Toggle Key)",
    Description = "Chọn phím tắt đóng/mở giao diện trên máy tính",
    Options     = { "LeftControl", "RightControl", "RightShift", "Insert", "Delete", "End", "F4", "F8" },
    Default     = CurrentState.MenuKeybind,
    MultiSelect = false,
    Callback    = function(keyName)
        OnSettingChanged("MenuKeybind", keyName)
        local newKeyCode = Enum.KeyCode[keyName]
        if newKeyCode then
            pcall(function()
                if Minimizer then
                    if type(Minimizer.SetKeyCode) == "function" then
                        Minimizer:SetKeyCode(newKeyCode)
                    elseif Minimizer.KeyCode ~= nil then
                        Minimizer.KeyCode = newKeyCode
                    end
                end
            end)
            Notify("Phím Menu", "Đã đổi phím ẩn/hiện giao diện thành: " .. keyName, "Success", 2.5)
        end
    end
})

UIControls.ShowMobileButton = SafeAddToggle(Tabs.Settings, {
    Name        = "Hiển Thị Nút Thu Nhỏ Mobile",
    Description = "Bật hoặc ẩn nút tròn nổi trên màn hình cảm ứng",
    Default     = CurrentState.ShowMobileButton,
    Callback    = function(val)
        OnSettingChanged("ShowMobileButton", val)
        if MobileButton then
            MobileButton.Visible = val
        end
    end
})

SafeAddSection(Tabs.Settings, "Tiện Ích Máy Chủ (Server Utilities)")

SafeAddButton(Tabs.Settings, {
    Name        = "🔁 Kết Nối Lại (Rejoin Server)",
    Description = "Vào lại đúng máy chủ (phòng) hiện tại",
    Callback    = function()
        Notify("Rejoin", "Đang kết nối lại máy chủ hiện tại...", "Info", 3)
        local ok, err = pcall(function()
            if #Players:GetPlayers() <= 1 then
                LocalPlayer:Kick("\n[Maid Hub] Đang kết nối lại máy chủ...")
                task.wait(0.5)
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
        if not ok then
            Notify("Rejoin Lỗi", "Không thể Rejoin: " .. tostring(err), "Error", 4)
        end
    end
})

SafeAddButton(Tabs.Settings, {
    Name        = "🌐 Đổi Máy Chủ Khác (Server Hop)",
    Description = "Tìm và chuyển sang một máy chủ công cộng khác còn chỗ trống",
    Callback    = function()
        Notify("Server Hop", "Đang tìm kiếm máy chủ mới...", "Info", 3)
        task.spawn(function()
            local ok, err = pcall(function()
                local apiUrl = string.format(
                    "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
                    game.PlaceId
                )
                local raw = game:HttpGet(apiUrl)
                local decoded = HttpService:JSONDecode(raw)
                local targetJobId = nil

                if decoded and type(decoded.data) == "table" then
                    for _, srv in ipairs(decoded.data) do
                        if type(srv) == "table"
                            and srv.id ~= game.JobId
                            and tonumber(srv.playing)
                            and tonumber(srv.maxPlayers)
                            and srv.playing < srv.maxPlayers
                        then
                            targetJobId = srv.id
                            break
                        end
                    end
                end

                if targetJobId then
                    Notify("Server Hop", "Đã tìm thấy server! Đang dịch chuyển...", "Success", 3)
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, LocalPlayer)
                else
                    Notify("Server Hop", "Không tìm thấy server trống phù hợp, chuyển ngẫu nhiên...", "Warning", 3)
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                end
            end)
            if not ok then
                Notify("Server Hop Lỗi", "Lỗi khi đổi máy chủ: " .. tostring(err), "Error", 4)
            end
        end)
    end
})

SafeAddSection(Tabs.Settings, "Tối Ưu Hiệu Năng (Performance)")

SafeAddButton(Tabs.Settings, {
    Name        = "🚀 Tối Ưu FPS (Boost FPS / Giảm Đồ Họa)",
    Description = "Tắt bóng đổ, hiệu ứng ánh sáng và làm phẳng mặt nước để tăng FPS",
    Callback    = function()
        pcall(function()
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
                terrain.WaterTransparency = 0
            end
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
            for _, v in ipairs(Lighting:GetDescendants()) do
                if v:IsA("PostProcessEffect") or v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") then
                    v.Enabled = false
                end
            end
        end)
        Notify("Boost FPS", "Đã áp dụng cấu hình giảm đồ họa tăng FPS!", "Success", 3)
    end
})

SafeAddButton(Tabs.Settings, {
    Name        = "⬜ Tắt Render 3D (White Screen - Treo Máy AFK)",
    Description = "Giảm tối đa GPU/CPU khi treo máy thu nhỏ cửa sổ",
    Callback    = function()
        pcall(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        Notify("3D Rendering", "Đã tắt Render 3D (chế độ tiết kiệm tài nguyên).", "Info", 3)
    end
})

SafeAddButton(Tabs.Settings, {
    Name        = "🖼️ Bật Lại Render 3D (Enable 3D Rendering)",
    Description = "Khôi phục hiển thị hình ảnh 3D bình thường",
    Callback    = function()
        pcall(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        Notify("3D Rendering", "Đã bật lại hiển thị 3D!", "Success", 3)
    end
})

SafeAddSection(Tabs.Settings, "Quản Lý Hệ Thống")

SafeAddButton(Tabs.Settings, {
    Name        = "🗑️ Đóng & Gỡ Bỏ Giao Diện (Destroy UI)",
    Description = "Dừng toàn bộ vòng lặp nền, ngắt kết nối sự kiện và xóa sạch GUI",
    Callback    = function()
        Notify("Maid Hub", "Đang đóng giao diện và dọn dẹp tài nguyên...", "Warning", 1.5)
        task.delay(0.4, function()
            CleanupAll()
        end)
    end
})

SafeAddSection(Tabs.About, CONFIG.HubName)
SafeAddParagraph(
    Tabs.About,
    CONFIG.HubName .. " — " .. CONFIG.SubTitle,
    string.format(
        "Phiên bản: %s\nTrạng thái: Clean UI Template (Full Components)\nSẵn sàng để tích hợp các tính năng tùy chỉnh.",
        CONFIG.Version
    )
)

SafeAddSection(Tabs.About, "Tác Giả & Thư Viện (Credits)")
SafeAddParagraph(
    Tabs.About,
    "Credits",
    "• UI Framework: RedzLib V5 Remake\n• Phát triển cho: " .. CONFIG.HubName .. "\n• Tương thích: PC & Mobile Executors"
)

task.defer(function()
    if ExecutorSupport.IsFile and ExecutorSupport.ReadFile then
        local ok, exists = pcall(isfile, CONFIG.ConfigFile)
        if ok and exists then
            LoadConfig(true)
        end
    end
    Notify(CONFIG.HubName, "Giao diện " .. CONFIG.HubName .. " (" .. CONFIG.SubTitle .. ") đã sẵn sàng!", "Success", 3.5)
end)

print(string.format("[%s] Clean UI %s loaded successfully!", CONFIG.HubName, CONFIG.SubTitle))
