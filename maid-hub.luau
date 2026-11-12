if not game:IsLoaded() then
    game.Loaded:Wait()
end

local CONFIG = {
    HubName          = "Maid Hub",
    SubTitle         = "make by skibidi Razen and Long",
    Version          = "BETA",
    SaveFolder       = "maidhub.json",
    ConfigFile       = "MaidHub_Config.json",
    DiscordLink      = "https://discord.gg/9KhYDxXMQP",
    DefaultKeybind   = Enum.KeyCode.LeftControl,
    DefaultTheme     = "Dark",
    MobileIcon       = "rbxassetid://104140373842031",
    MobileThumb      = "rbxthumb://type=Asset&id=104140373842031&w=420&h=420",
    LibraryUrls      = {
        "https://raw.githubusercontent.com/hungd8722-cmd/Maid-hub/refs/heads/main/maidhub-main.luau",
        "https://raw.githubusercontent.com/REDzHUB/RedzLibV5/main/Source.Lua",
    },
    Icons            = {
        Information  = "Info",
        Status       = "Activity",
        FarmSettings = "rbxassetid://10723415903",
        MainFarm     = "rbxassetid://10723407389",
        ItemFarm     = "Package",
        QuestsFarm   = "Scroll",
        Race         = "Zap",
        SeaEvent     = "Anchor",
        RaidFarm     = "Flame",
        Teleport     = "MapPin",
        Fruit        = "Apple",
        Visual       = "Eye",
        Shop         = "ShoppingCart",
        Misc         = "rbxassetid://7734053495",
    }
}

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
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

local function invokeCommF(...)
    local args = { ... }
    local ok, res = pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF and commF:IsA("RemoteFunction") then
            return commF:InvokeServer(unpack(args))
        end
        return nil
    end)
    return ok, res
end

local DEFAULT_STATE = {
    AutoSave           = true,
    -- Farm Settings
    SelectedWeapon     = "Melee",
    FarmDistance       = 15,
    FastAttack         = true,
    BringMob           = true,
    AutoBuso           = true,
    AutoObserve        = false,
    -- Main Farm
    AutoFarmLevel      = false,
    AutoFarmNearest    = false,
    AutoFarmBone       = false,
    AutoFarmKatakuri   = false,
    AutoMasteryFruit   = false,
    AutoMasteryGun     = false,
    -- Item Farm
    AutoGodhuman       = false,
    AutoCDK            = false,
    AutoSoulGuitar     = false,
    AutoYamaTushita    = false,
    SelectedMaterial   = "Conjured Cocoa",
    AutoFarmMaterial   = false,
    -- Quests Farm
    AutoEliteHunter    = false,
    AutoFarmBoss       = false,
    AutoBartiloQuest   = false,
    AutoCitizenQuest   = false,
    AutoUnlockSea      = false,
    -- Race
    AutoRaceV3         = false,
    AutoRaceV4         = false,
    AutoTrainRaceV4    = false,
    AutoCompleteTrial  = false,
    -- Sea Event
    SeaDangerLevel     = "Level 6 (???)",
    AutoSailSeaEvent   = false,
    AutoKillSeaBeast   = false,
    AutoKillShark      = false,
    AutoKillGhostShip  = false,
    AutoFindMirage     = false,
    -- Raid Farm
    SelectedRaidChip   = "Flame",
    AutoBuyRaidChip    = false,
    AutoFarmRaid       = false,
    AutoNextIsland     = false,
    AutoAwakenFruit    = false,
    -- Teleport
    SelectedIsland     = "Cafe (Sea 2)",
    TweenSpeed         = 250,
    -- Fruit
    SelectedSniperFruit = "Kitsune",
    AutoBuySniperFruit = false,
    AutoGrabFruit      = false,
    AutoStoreFruit     = true,
    AutoRandomFruit    = false,
    -- Visual
    EspPlayer          = false,
    EspFruit           = false,
    EspChest           = false,
    EspIsland          = false,
    FullBright         = false,
    -- Misc / UI
    MenuKeybind        = CONFIG.DefaultKeybind.Name,
    Theme              = CONFIG.DefaultTheme,
    ShowMobileButton   = true,
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

-- ============================================================================
-- KHỞI TẠO LOCAL TAB THEO ĐÚNG TRÌNH TỰ YÊU CẦU:
-- Information, Status, Farm Settings, Main Farm, Item Farm, Quests Farm,
-- Race, Sea Event, Raid Farm, Teleport, Fruit, Visual, Shop, Misc
-- ============================================================================
local Tabs = {}
Tabs.Information  = Window:MakeTab({ Title = "Information",   Icon = CONFIG.Icons.Information })
Tabs.Status       = Window:MakeTab({ Title = "Status",        Icon = CONFIG.Icons.Status })
Tabs.FarmSettings = Window:MakeTab({ Title = "Farm Settings", Icon = CONFIG.Icons.FarmSettings })
Tabs.MainFarm     = Window:MakeTab({ Title = "Main Farm",     Icon = CONFIG.Icons.MainFarm })
Tabs.ItemFarm     = Window:MakeTab({ Title = "Item Farm",     Icon = CONFIG.Icons.ItemFarm })
Tabs.QuestsFarm   = Window:MakeTab({ Title = "Quests Farm",   Icon = CONFIG.Icons.QuestsFarm })
Tabs.Race         = Window:MakeTab({ Title = "Race",          Icon = CONFIG.Icons.Race })
Tabs.SeaEvent     = Window:MakeTab({ Title = "Sea Event",     Icon = CONFIG.Icons.SeaEvent })
Tabs.RaidFarm     = Window:MakeTab({ Title = "Raid Farm",     Icon = CONFIG.Icons.RaidFarm })
Tabs.Teleport     = Window:MakeTab({ Title = "Teleport",      Icon = CONFIG.Icons.Teleport })
Tabs.Fruit        = Window:MakeTab({ Title = "Fruit",         Icon = CONFIG.Icons.Fruit })
Tabs.Visual       = Window:MakeTab({ Title = "Visual",        Icon = CONFIG.Icons.Visual })
Tabs.Shop         = Window:MakeTab({ Title = "Shop",          Icon = CONFIG.Icons.Shop })
Tabs.Misc         = Window:MakeTab({ Title = "Misc",          Icon = CONFIG.Icons.Misc })

-- ============================================================================
-- 1. TAB: INFORMATION
-- ============================================================================
SafeAddSection(Tabs.Information, "Giới Thiệu " .. CONFIG.HubName)

SafeAddParagraph(
    Tabs.Information,
    CONFIG.HubName .. " — " .. CONFIG.SubTitle,
    string.format(
        "Phiên bản: %s\nUI Framework: RedzLib V5 Remake\nTương thích: PC & Mobile Executors",
        CONFIG.Version
    )
)

SafeAddSection(Tabs.Information, "Thông Tin Người Chơi")

local PlayerName = LocalPlayer and LocalPlayer.DisplayName or "Player"
local PlayerUser = LocalPlayer and LocalPlayer.Name or "Unknown"
local PlayerId   = LocalPlayer and tostring(LocalPlayer.UserId) or "0"
local JobIdText  = (game.JobId ~= "" and game.JobId) or "Private / Studio Server"

SafeAddParagraph(
    Tabs.Information,
    "Tài Khoản Hiện Tại",
    string.format("%s (@%s)\nUserId: %s", PlayerName, PlayerUser, PlayerId)
)

SafeAddSection(Tabs.Information, "Cộng Đồng & Liên Kết")

SafeAddButton(Tabs.Information, {
    Name        = "📋 Sao Chép Discord Link (Copy Discord)",
    Description = "Sao chép liên kết máy chủ Discord chính thức của " .. CONFIG.HubName,
    Callback    = function()
        if safeCopyClipboard(CONFIG.DiscordLink) then
            Notify("Discord", "Đã sao chép link Discord: " .. CONFIG.DiscordLink, "Success", 3.5)
        end
    end
})

SafeAddButton(Tabs.Information, {
    Name        = "📋 Sao Chép Server JobId (Copy JobId)",
    Description = "Sao chép mã phòng (JobId) hiện tại vào bộ nhớ tạm",
    Callback    = function()
        if safeCopyClipboard(JobIdText) then
            Notify("JobId", "Đã lưu Server JobId vào Clipboard!", "Success", 3)
        end
    end
})

SafeAddButton(Tabs.Information, {
    Name        = "👤 Sao Chép Thông Tin Tài Khoản (Copy Profile)",
    Description = "Sao chép Username và UserId của bạn vào bộ nhớ tạm",
    Callback    = function()
        local profileStr = string.format("%s (@%s) - UserId: %s", PlayerName, PlayerUser, PlayerId)
        if safeCopyClipboard(profileStr) then
            Notify("Information", "Đã sao chép thông tin tài khoản!", "Success", 3)
        end
    end
})

-- ============================================================================
-- 2. TAB: STATUS
-- ============================================================================
SafeAddSection(Tabs.Status, "Trạng Thái Máy Chủ & Hiệu Năng")

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

local GameInfoParagraph   = SafeAddParagraph(Tabs.Status, "Trò Chơi & Máy Chủ", "Đang tải thông tin...")
local ClientStatParagraph = SafeAddParagraph(Tabs.Status, "Hiệu Năng & Mạng", "FPS: 60 | Ping: 0 ms")
local TimeParagraph       = SafeAddParagraph(Tabs.Status, "Thời Gian Hoạt Động", "Đang tính toán...")
local WorldStatParagraph  = SafeAddParagraph(Tabs.Status, "Sự Kiện Thế Giới (World Status)", "Moon: Đang kiểm tra... | Mirage: Không")

SafeAddSection(Tabs.Status, "Công Cụ Kiểm Tra Trạng Thái")

SafeAddButton(Tabs.Status, {
    Name        = "🔄 Làm Mới Trạng Thái Máy Chủ (Refresh Status)",
    Description = "Cập nhật ngay lập tức thông số FPS, Ping, số người chơi và thời gian",
    Callback    = function()
        Notify("Status", "Đã làm mới toàn bộ thông số trạng thái máy chủ!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Status, {
    Name        = "🌕 Kiểm Tra Chu Kỳ Trăng & Mirage (Check Moon & Mirage)",
    Description = "Kiểm tra trạng thái Full Moon và Đảo Bí Ẩn (Mirage Island) trong server",
    Callback    = function()
        local hasMirage = false
        pcall(function()
            local locs = workspace:FindFirstChild("_WorldOrigin") and workspace._WorldOrigin:FindFirstChild("Locations")
            if locs and locs:FindFirstChild("Mirage Island") then
                hasMirage = true
            end
        end)
        local clockTime = Lighting.ClockTime
        SafeSetDesc(WorldStatParagraph, string.format(
            "Giờ trong game: %.1fh | Mirage Island: %s",
            clockTime,
            hasMirage and "Đang xuất hiện ✅" or "Chưa xuất hiện ❌"
        ))
        Notify("World Status", string.format("Giờ Server: %.1fh | Mirage: %s", clockTime, hasMirage and "Có ✅" or "Không ❌"), "Info", 3.5)
    end
})

SafeAddButton(Tabs.Status, {
    Name        = "📋 Sao Chép Báo Cáo Trạng Thái (Copy Server Report)",
    Description = "Sao chép tóm tắt trạng thái máy chủ hiện tại vào Clipboard",
    Callback    = function()
        local report = string.format(
            "[%s] PlaceId: %d | JobId: %s | Players: %d/%d",
            CONFIG.HubName, game.PlaceId, JobIdText, #Players:GetPlayers(), Players.MaxPlayers
        )
        if safeCopyClipboard(report) then
            Notify("Status", "Đã sao chép báo cáo máy chủ vào Clipboard!", "Success", 3)
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

-- ============================================================================
-- 3. TAB: FARM SETTINGS
-- ============================================================================
SafeAddSection(Tabs.FarmSettings, "Thiết Lập Vũ Khí & Khoảng Cách")

UIControls.SelectedWeapon = SafeAddDropdown(Tabs.FarmSettings, {
    Name        = "Chọn Nhóm Vũ Khí (Select Weapon)",
    Description = "Loại vũ khí ưu tiên trang bị khi tự động farm",
    Options     = { "Melee", "Sword", "Fruit", "Gun" },
    Default     = CurrentState.SelectedWeapon,
    MultiSelect = false,
    Callback    = function(val)
        OnSettingChanged("SelectedWeapon", val)
    end
})

UIControls.FarmDistance = SafeAddSlider(Tabs.FarmSettings, {
    Name        = "Khoảng Cách Đứng Trên Quái (Farm Distance)",
    Description = "Độ cao nhân vật lơ lửng phía trên mục tiêu khi farm",
    Min         = 5,
    Max         = 50,
    Increase    = 1,
    Default     = CurrentState.FarmDistance,
    Callback    = function(val)
        OnSettingChanged("FarmDistance", val)
    end
})

SafeAddSection(Tabs.FarmSettings, "Tối Ưu Đòn Đánh & Haki")

UIControls.FastAttack = SafeAddToggle(Tabs.FarmSettings, {
    Name        = "Đánh Nhanh (Fast Attack)",
    Description = "Tăng tốc độ ra đòn khi sử dụng Melee hoặc Sword",
    Default     = CurrentState.FastAttack,
    Callback    = function(val)
        OnSettingChanged("FastAttack", val)
    end
})

UIControls.BringMob = SafeAddToggle(Tabs.FarmSettings, {
    Name        = "Gom Quái Lại Gần (Bring Mob)",
    Description = "Tự động gom quái cùng tên về vị trí nhân vật đang đánh",
    Default     = CurrentState.BringMob,
    Callback    = function(val)
        OnSettingChanged("BringMob", val)
    end
})

UIControls.AutoBuso = SafeAddToggle(Tabs.FarmSettings, {
    Name        = "Tự Động Bật Buso Haki (Auto Aura)",
    Description = "Tự động kích hoạt Haki Vũ Trang khi vào trận",
    Default     = CurrentState.AutoBuso,
    Callback    = function(val)
        OnSettingChanged("AutoBuso", val)
    end
})

UIControls.AutoObserve = SafeAddToggle(Tabs.FarmSettings, {
    Name        = "Tự Động Bật Ken Haki (Auto Observation)",
    Description = "Tự động bật Haki Quan Sát để né đòn và luyện né",
    Default     = CurrentState.AutoObserve,
    Callback    = function(val)
        OnSettingChanged("AutoObserve", val)
    end
})

SafeAddSection(Tabs.FarmSettings, "Thao Tác Nhanh (Quick Actions)")

SafeAddButton(Tabs.FarmSettings, {
    Name        = "⚔️ Trang Bị Ngay Vũ Khí Đã Chọn (Equip Selected Weapon)",
    Description = "Tìm trong Balo và cầm ngay vũ khí thuộc nhóm " .. tostring(CurrentState.SelectedWeapon),
    Callback    = function()
        Notify("Farm Settings", "Đang kiểm tra và trang bị vũ khí nhóm: " .. tostring(CurrentState.SelectedWeapon), "Info", 2.5)
    end
})

SafeAddButton(Tabs.FarmSettings, {
    Name        = "🛡️ Kích Hoạt Ngay Buso Haki (Activate Buso Haki)",
    Description = "Gọi sự kiện bật Haki Vũ Trang ngay lập tức",
    Callback    = function()
        invokeCommF("Buso")
        Notify("Farm Settings", "Đã gửi lệnh bật Buso Haki!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.FarmSettings, {
    Name        = "🔄 Đặt Lại Thiết Lập Farm (Reset Farm Settings)",
    Description = "Đưa khoảng cách farm (15) và vũ khí (Melee) về mặc định",
    Callback    = function()
        OnSettingChanged("SelectedWeapon", "Melee")
        OnSettingChanged("FarmDistance", 15)
        OnSettingChanged("FastAttack", true)
        OnSettingChanged("BringMob", true)
        ApplyStateToUI()
        Notify("Farm Settings", "Đã khôi phục thiết lập Farm về mặc định!", "Info", 3)
    end
})

-- ============================================================================
-- 4. TAB: MAIN FARM
-- ============================================================================
SafeAddSection(Tabs.MainFarm, "Tự Động Cày Cấp & Quái Chính")

UIControls.AutoFarmLevel = SafeAddToggle(Tabs.MainFarm, {
    Name        = "Tự Động Cày Cấp (Auto Farm Level)",
    Description = "Tự động nhận nhiệm vụ phù hợp cấp độ và tiêu diệt quái",
    Default     = CurrentState.AutoFarmLevel,
    Callback    = function(val)
        OnSettingChanged("AutoFarmLevel", val)
        Notify("Main Farm", "Auto Farm Level: " .. (val and "Đang Bật ✅" or "Đã Tắt ❌"), "Info", 2.5)
    end
})

UIControls.AutoFarmNearest = SafeAddToggle(Tabs.MainFarm, {
    Name        = "Tự Động Đánh Quái Gần Nhất (Auto Farm Nearest)",
    Description = "Tấn công mọi quái vật ở gần nhân vật không cần nhận nhiệm vụ",
    Default     = CurrentState.AutoFarmNearest,
    Callback    = function(val)
        OnSettingChanged("AutoFarmNearest", val)
    end
})

UIControls.AutoFarmBone = SafeAddToggle(Tabs.MainFarm, {
    Name        = "Tự Động Farm Xương (Auto Farm Bone - Haunted Castle)",
    Description = "Tự động đánh quái tại Lâu Đài Ma để thu thập Bones",
    Default     = CurrentState.AutoFarmBone,
    Callback    = function(val)
        OnSettingChanged("AutoFarmBone", val)
    end
})

UIControls.AutoFarmKatakuri = SafeAddToggle(Tabs.MainFarm, {
    Name        = "Tự Động Farm Katakuri / Cake Prince",
    Description = "Đánh đủ 500 quái tại Đảo Bánh và tự động triệu hồi Cake Prince",
    Default     = CurrentState.AutoFarmKatakuri,
    Callback    = function(val)
        OnSettingChanged("AutoFarmKatakuri", val)
    end
})

SafeAddSection(Tabs.MainFarm, "Tự Động Cày Thông Thạo (Mastery Farm)")

UIControls.AutoMasteryFruit = SafeAddToggle(Tabs.MainFarm, {
    Name        = "Tự Động Cày Mastery Trái Ác Quỷ (Auto Fruit Mastery)",
    Description = "Dùng Melee kéo máu quái xuống thấp rồi kết liễu bằng Trái Ác Quỷ",
    Default     = CurrentState.AutoMasteryFruit,
    Callback    = function(val)
        OnSettingChanged("AutoMasteryFruit", val)
    end
})

UIControls.AutoMasteryGun = SafeAddToggle(Tabs.MainFarm, {
    Name        = "Tự Động Cày Mastery Súng (Auto Gun Mastery)",
    Description = "Dùng Melee kéo máu quái xuống thấp rồi kết liễu bằng Súng",
    Default     = CurrentState.AutoMasteryGun,
    Callback    = function(val)
        OnSettingChanged("AutoMasteryGun", val)
    end
})

SafeAddSection(Tabs.MainFarm, "Điều Khiển Farm & Sự Kiện (Buttons)")

SafeAddButton(Tabs.MainFarm, {
    Name        = "🍩 Mở Cổng Triệu Hồi Cake Prince / Dough King",
    Description = "Gửi yêu cầu mở cổng chiều không gian tại Đảo Bánh",
    Callback    = function()
        invokeCommF("CakePrinceSpawner", true)
        Notify("Main Farm", "Đã gửi lệnh kiểm tra / mở cổng Cake Prince!", "Info", 3)
    end
})

SafeAddButton(Tabs.MainFarm, {
    Name        = "🦴 Đổi Xương Ngẫu Nhiên (Roll Bones - Death King)",
    Description = "Đổi 50 Bones tại NPC Death King để nhận phần thưởng ngẫu nhiên",
    Callback    = function()
        invokeCommF("Bones", "Buy", 1, 1)
        Notify("Main Farm", "Đã thực hiện đổi thưởng 50 Bones tại Death King!", "Success", 3)
    end
})

SafeAddButton(Tabs.MainFarm, {
    Name        = "🗑️ Hủy Nhiệm Vụ Hiện Tại (Abandon Quest)",
    Description = "Hủy bỏ nhiệm vụ đang nhận để làm mới trạng thái cày cấp",
    Callback    = function()
        invokeCommF("AbandonQuest")
        Notify("Main Farm", "Đã hủy nhiệm vụ hiện tại!", "Warning", 2.5)
    end
})

SafeAddButton(Tabs.MainFarm, {
    Name        = "🛑 Dừng Toàn Bộ Chế Độ Main Farm (Stop All Main Farm)",
    Description = "Tắt tất cả công tắc trong mục Main Farm ngay lập tức",
    Callback    = function()
        OnSettingChanged("AutoFarmLevel", false)
        OnSettingChanged("AutoFarmNearest", false)
        OnSettingChanged("AutoFarmBone", false)
        OnSettingChanged("AutoFarmKatakuri", false)
        OnSettingChanged("AutoMasteryFruit", false)
        OnSettingChanged("AutoMasteryGun", false)
        ApplyStateToUI()
        Notify("Main Farm", "Đã tắt toàn bộ tiến trình Main Farm!", "Warning", 3)
    end
})

-- ============================================================================
-- 5. TAB: ITEM FARM
-- ============================================================================
SafeAddSection(Tabs.ItemFarm, "Săn Võ Thuật & Vũ Khí Huyền Thoại")

UIControls.AutoGodhuman = SafeAddToggle(Tabs.ItemFarm, {
    Name        = "Tự Động Lấy Godhuman (Auto Godhuman)",
    Description = "Tự động cày đủ Mastery các võ và thu thập nguyên liệu lên Godhuman",
    Default     = CurrentState.AutoGodhuman,
    Callback    = function(val)
        OnSettingChanged("AutoGodhuman", val)
    end
})

UIControls.AutoCDK = SafeAddToggle(Tabs.ItemFarm, {
    Name        = "Tự Động Lấy Cursed Dual Katana (Auto CDK)",
    Description = "Tự động làm nhiệm vụ cuộn giấy Yama & Tushita để rèn Song Kiếm Oden",
    Default     = CurrentState.AutoCDK,
    Callback    = function(val)
        OnSettingChanged("AutoCDK", val)
    end
})

UIControls.AutoSoulGuitar = SafeAddToggle(Tabs.ItemFarm, {
    Name        = "Tự Động Lấy Soul Guitar (Auto Soul Guitar)",
    Description = "Tự động giải đố tại Haunted Castle vào đêm Full Moon và chế tạo Soul Guitar",
    Default     = CurrentState.AutoSoulGuitar,
    Callback    = function(val)
        OnSettingChanged("AutoSoulGuitar", val)
    end
})

UIControls.AutoYamaTushita = SafeAddToggle(Tabs.ItemFarm, {
    Name        = "Tự Động Rút Kiếm Yama / Làm Nhiệm Vụ Tushita",
    Description = "Tự động rút kiếm Yama khi đủ 30 Elite và thắp đuốc Tushita",
    Default     = CurrentState.AutoYamaTushita,
    Callback    = function(val)
        OnSettingChanged("AutoYamaTushita", val)
    end
})

SafeAddSection(Tabs.ItemFarm, "Tự Động Thu Thập Nguyên Liệu (Material Farm)")

UIControls.SelectedMaterial = SafeAddDropdown(Tabs.ItemFarm, {
    Name        = "Chọn Nguyên Liệu Cần Farm (Select Material)",
    Description = "Chọn nguyên liệu nâng cấp kiếm / súng hoặc đổi võ",
    Options     = { "Conjured Cocoa", "Dragon Scale", "Fish Tail", "Magma Ore", "Mystic Droplet", "Leather", "Scrap Metal", "Demonic Wisp", "Mini Tusk" },
    Default     = CurrentState.SelectedMaterial,
    MultiSelect = false,
    Callback    = function(val)
        OnSettingChanged("SelectedMaterial", val)
    end
})

UIControls.AutoFarmMaterial = SafeAddToggle(Tabs.ItemFarm, {
    Name        = "Tự Động Farm Nguyên Liệu Đã Chọn (Auto Material)",
    Description = "Di chuyển đến bãi quái rơi nguyên liệu đã chọn và tự động đánh",
    Default     = CurrentState.AutoFarmMaterial,
    Callback    = function(val)
        OnSettingChanged("AutoFarmMaterial", val)
    end
})

SafeAddSection(Tabs.ItemFarm, "Thao Tác Vật Phẩm Nhanh (Item Buttons)")

SafeAddButton(Tabs.ItemFarm, {
    Name        = "🗡️ Mua Kiếm Huyền Thoại (Buy Legendary Sword - Dealer)",
    Description = "Mua kiếm Shisui / Saddi / Wando từ Legendary Sword Dealer nếu đang xuất hiện",
    Callback    = function()
        invokeCommF("LegendarySwordDealer", "2")
        Notify("Item Farm", "Đã gửi lệnh mua kiếm tại Legendary Sword Dealer!", "Info", 3)
    end
})

SafeAddButton(Tabs.ItemFarm, {
    Name        = "🎨 Mua Màu Haki Hiếm (Buy Enhancer Color - Dealer)",
    Description = "Mua màu Haki đang bán tại Master of Aura",
    Callback    = function()
        invokeCommF("ColorsDealer", "2")
        Notify("Item Farm", "Đã gửi lệnh mua màu Haki tại Master of Aura!", "Info", 3)
    end
})

SafeAddButton(Tabs.ItemFarm, {
    Name        = "🔥 Đổi Võ Godhuman Ngay (Buy Godhuman)",
    Description = "Tương tác với NPC Ancient Monk để học Godhuman",
    Callback    = function()
        invokeCommF("BuyGodhuman")
        Notify("Item Farm", "Đã gửi lệnh học võ Godhuman!", "Success", 3)
    end
})

-- ============================================================================
-- 6. TAB: QUESTS FARM
-- ============================================================================
SafeAddSection(Tabs.QuestsFarm, "Nhiệm Vụ Đặc Biệt & Săn Boss")

UIControls.AutoEliteHunter = SafeAddToggle(Tabs.QuestsFarm, {
    Name        = "Tự Động Săn Elite Hunter (Diablo / Deandre / Urban)",
    Description = "Tự động nhận nhiệm vụ tại Castle on the Sea và tiêu diệt quái Elite",
    Default     = CurrentState.AutoEliteHunter,
    Callback    = function(val)
        OnSettingChanged("AutoEliteHunter", val)
    end
})

UIControls.AutoFarmBoss = SafeAddToggle(Tabs.QuestsFarm, {
    Name        = "Tự Động Săn Tất Cả Boss Đang Xuất Hiện (Auto All Bosses)",
    Description = "Quét và tiêu diệt lần lượt các Boss đang có mặt trong máy chủ",
    Default     = CurrentState.AutoFarmBoss,
    Callback    = function(val)
        OnSettingChanged("AutoFarmBoss", val)
    end
})

UIControls.AutoBartiloQuest = SafeAddToggle(Tabs.QuestsFarm, {
    Name        = "Tự Động Làm Nhiệm Vụ Bartilo (Sea 2)",
    Description = "Đánh 50 Swan Pirates, Jeremy và giải mã bảng chữ cái tại Đấu Trường",
    Default     = CurrentState.AutoBartiloQuest,
    Callback    = function(val)
        OnSettingChanged("AutoBartiloQuest", val)
    end
})

UIControls.AutoCitizenQuest = SafeAddToggle(Tabs.QuestsFarm, {
    Name        = "Tự Động Làm Nhiệm Vụ Citizen (Mũ Musketeer Hat)",
    Description = "Đánh 50 Forest Pirates, Captain Elephant và lấy mũ Musketeer",
    Default     = CurrentState.AutoCitizenQuest,
    Callback    = function(val)
        OnSettingChanged("AutoCitizenQuest", val)
    end
})

UIControls.AutoUnlockSea = SafeAddToggle(Tabs.QuestsFarm, {
    Name        = "Tự Động Làm Nhiệm Vụ Qua Sea 2 / Sea 3 (Auto Unlock Sea)",
    Description = "Tự động làm chuỗi nhiệm vụ Ice Admiral (Sea 1) hoặc Rip_Indra (Sea 2)",
    Default     = CurrentState.AutoUnlockSea,
    Callback    = function(val)
        OnSettingChanged("AutoUnlockSea", val)
    end
})

SafeAddSection(Tabs.QuestsFarm, "Thao Tác Nhiệm Vụ (Quest Buttons)")

SafeAddButton(Tabs.QuestsFarm, {
    Name        = "🎯 Kiểm Tra Số Lượng Elite Đã Hạ (Check Elite Progress)",
    Description = "Xem tổng số Elite Hunter bạn đã tiêu diệt trong tài khoản",
    Callback    = function()
        local ok, progress = invokeCommF("EliteHunter", "Progress")
        Notify("Elite Hunter", "Tiến độ Elite đã hạ: " .. tostring((ok and progress) or "Không xác định"), "Info", 3.5)
    end
})

SafeAddButton(Tabs.QuestsFarm, {
    Name        = "📜 Nhận Nhiệm Vụ Elite Hunter Ngay (Accept Elite Quest)",
    Description = "Nhận nhiệm vụ săn Elite từ xa không cần về Castle on the Sea",
    Callback    = function()
        invokeCommF("EliteHunter")
        Notify("Elite Hunter", "Đã gửi yêu cầu nhận nhiệm vụ Elite Hunter!", "Success", 3)
    end
})

SafeAddButton(Tabs.QuestsFarm, {
    Name        = "🌈 Nhận Nhiệm Vụ Haki Cầu Vồng (Rainbow Haki Quest)",
    Description = "Tương tác với Horned Man tại Floating Turtle để làm nhiệm vụ Rainbow Saviour",
    Callback    = function()
        invokeCommF("HornedMan", "Bet")
        Notify("Quests Farm", "Đã gửi yêu cầu nhận nhiệm vụ Rainbow Haki!", "Info", 3)
    end
})

-- ============================================================================
-- 7. TAB: RACE
-- ============================================================================
SafeAddSection(Tabs.Race, "Thức Tỉnh Tộc V3 & V4 (Race Awakening)")

UIControls.AutoRaceV3 = SafeAddToggle(Tabs.Race, {
    Name        = "Tự Động Bật Kỹ Năng Tộc V3 (Auto Activate Race V3)",
    Description = "Tự động kích hoạt kỹ năng Tộc V3 ngay khi hồi chiêu xong",
    Default     = CurrentState.AutoRaceV3,
    Callback    = function(val)
        OnSettingChanged("AutoRaceV3", val)
    end
})

UIControls.AutoRaceV4 = SafeAddToggle(Tabs.Race, {
    Name        = "Tự Động Bật Thức Tỉnh Tộc V4 (Auto Awaken Race V4)",
    Description = "Tự động biến hình V4 ngay khi thanh nộ (Awakening Meter) đầy",
    Default     = CurrentState.AutoRaceV4,
    Callback    = function(val)
        OnSettingChanged("AutoRaceV4", val)
    end
})

UIControls.AutoTrainRaceV4 = SafeAddToggle(Tabs.Race, {
    Name        = "Tự Động Luyện Tộc V4 Tại Đảo Cacao (Auto Train V4)",
    Description = "Farm quái tại Đảo Cacao, bật V4 để cày thời gian biến hình và mua Gear",
    Default     = CurrentState.AutoTrainRaceV4,
    Callback    = function(val)
        OnSettingChanged("AutoTrainRaceV4", val)
    end
})

UIControls.AutoCompleteTrial = SafeAddToggle(Tabs.Race, {
    Name        = "Tự Động Hoàn Thành Ải Thử Thách Tộc (Auto Complete Trial)",
    Description = "Tự động vượt ải Trial tương ứng với tộc của bạn tại Temple of Time",
    Default     = CurrentState.AutoCompleteTrial,
    Callback    = function(val)
        OnSettingChanged("AutoCompleteTrial", val)
    end
})

SafeAddSection(Tabs.Race, "Dịch Chuyển & Nâng Cấp Tộc (Race Buttons)")

SafeAddButton(Tabs.Race, {
    Name        = "🌳 Dịch Chuyển Tới Đỉnh Great Tree (Teleport Great Tree NPC)",
    Description = "Bay lên đỉnh Đại Thụ để nói chuyện với NPC Misc / vào Temple of Time",
    Callback    = function()
        Notify("Race", "Đang khởi tạo đường bay tới đỉnh Great Tree...", "Info", 3)
    end
})

SafeAddButton(Tabs.Race, {
    Name        = "🏛️ Dịch Chuyển Vào Temple of Time",
    Description = "Chuyển nhân vật vào bên trong Đền Thời Gian để gạt cần / vào phòng Trial",
    Callback    = function()
        Notify("Race", "Đang dịch chuyển vào Temple of Time...", "Info", 3)
    end
})

SafeAddButton(Tabs.Race, {
    Name        = "🚪 Dịch Chuyển Tới Cửa Tộc Hiện Tại (Teleport To Race Door)",
    Description = "Di chuyển thẳng tới trước cửa phòng Trial tương ứng với Tộc của bạn",
    Callback    = function()
        Notify("Race", "Đang di chuyển tới cửa phòng Trial của Tộc hiện tại!", "Info", 3)
    end
})

SafeAddButton(Tabs.Race, {
    Name        = "⚙️ Mua Nâng Cấp Gear Tộc V4 (Buy Ancient One Upgrade)",
    Description = "Tương tác với Ancient Clock để mua nâng cấp giai đoạn luyện Tộc V4",
    Callback    = function()
        invokeCommF("UpgradeRace", "Buy")
        Notify("Race", "Đã gửi yêu cầu nâng cấp Tộc V4 tại Ancient Clock!", "Success", 3)
    end
})

-- ============================================================================
-- 8. TAB: SEA EVENT
-- ============================================================================
SafeAddSection(Tabs.SeaEvent, "Cấu Hình Đi Săn Sự Kiện Biển (Sea Expedition)")

UIControls.SeaDangerLevel = SafeAddDropdown(Tabs.SeaEvent, {
    Name        = "Chọn Mức Nguy Hiểm Biển (Sea Danger Level)",
    Description = "Khu vực vùng biển từ Level 1 đến Level 6 (Kitsune / Mirage / Leviathan)",
    Options     = { "Level 1", "Level 2", "Level 3", "Level 4", "Level 5", "Level 6 (???)" },
    Default     = CurrentState.SeaDangerLevel,
    MultiSelect = false,
    Callback    = function(val)
        OnSettingChanged("SeaDangerLevel", val)
    end
})

UIControls.AutoSailSeaEvent = SafeAddToggle(Tabs.SeaEvent, {
    Name        = "Tự Động Lái Thuyền Ra Khơi (Auto Sail Sea Event)",
    Description = "Tự động mua thuyền và di chuyển đến vùng biển nguy hiểm đã chọn",
    Default     = CurrentState.AutoSailSeaEvent,
    Callback    = function(val)
        OnSettingChanged("AutoSailSeaEvent", val)
    end
})

UIControls.AutoKillSeaBeast = SafeAddToggle(Tabs.SeaEvent, {
    Name        = "Tự Động Đánh Sea Beast (Auto Kill Sea Beast)",
    Description = "Tự động né tia nước và dùng kỹ năng tiêu diệt Vua Biển",
    Default     = CurrentState.AutoKillSeaBeast,
    Callback    = function(val)
        OnSettingChanged("AutoKillSeaBeast", val)
    end
})

UIControls.AutoKillShark = SafeAddToggle(Tabs.SeaEvent, {
    Name        = "Tự Động Đánh Terrorshark & Cá Mập (Auto Kill Terrorshark)",
    Description = "Tự động bay lên cao né đòn cắn và tiêu diệt Terrorshark / Piranha",
    Default     = CurrentState.AutoKillShark,
    Callback    = function(val)
        OnSettingChanged("AutoKillShark", val)
    end
})

UIControls.AutoKillGhostShip = SafeAddToggle(Tabs.SeaEvent, {
    Name        = "Tự Động Phá Thuyền Hải Tặc / Thuyền Ma (Auto Ship Raid)",
    Description = "Sử dụng kỹ năng phá hủy tàu địch để nhận trái ác quỷ và Fragments",
    Default     = CurrentState.AutoKillGhostShip,
    Callback    = function(val)
        OnSettingChanged("AutoKillGhostShip", val)
    end
})

UIControls.AutoFindMirage = SafeAddToggle(Tabs.SeaEvent, {
    Name        = "Tự Động Dừng Khi Gặp Đảo Bí Ẩn (Auto Stop On Mirage)",
    Description = "Dừng thuyền và thông báo ngay khi phát hiện Mirage Island xuất hiện",
    Default     = CurrentState.AutoFindMirage,
    Callback    = function(val)
        OnSettingChanged("AutoFindMirage", val)
    end
})

SafeAddSection(Tabs.SeaEvent, "Thao Tác Sự Kiện Biển (Sea Event Buttons)")

SafeAddButton(Tabs.SeaEvent, {
    Name        = "⛵ Mua Nhanh Thuyền Guardian / Miracle (Buy Boat)",
    Description = "Gọi sự kiện mua thuyền tốc độ cao tại bến cảng Tiki Outpost",
    Callback    = function()
        invokeCommF("BuyBoat", "Miracle")
        Notify("Sea Event", "Đã gửi lệnh mua thuyền tại bến cảng!", "Success", 3)
    end
})

SafeAddButton(Tabs.SeaEvent, {
    Name        = "🧭 Dịch Chuyển Về Ghế Lái Thuyền (Teleport To Boat Seat)",
    Description = "Đưa nhân vật quay trở lại ghế điều khiển thuyền của bạn",
    Callback    = function()
        Notify("Sea Event", "Đang tìm và dịch chuyển về thuyền của bạn...", "Info", 2.5)
    end
})

SafeAddButton(Tabs.SeaEvent, {
    Name        = "⚙️ Dịch Chuyển Tới Bánh Răng Xanh (Tween To Blue Gear)",
    Description = "Tự động quét và bay tới vị trí Blue Gear trên Mirage Island",
    Callback    = function()
        Notify("Sea Event", "Đang quét tọa độ Blue Gear trên Mirage Island...", "Info", 3)
    end
})

SafeAddButton(Tabs.SeaEvent, {
    Name        = "🐉 Mua Chuộc Spy Kiểm Tra Leviathan (Bribe Leviathan Spy)",
    Description = "Hỏi thông tin xuất hiện của Leviathan từ NPC Spy tại Tiki Outpost",
    Callback    = function()
        invokeCommF("InfoLeviathan", "1")
        Notify("Sea Event", "Đã gửi yêu cầu kiểm tra thông tin Leviathan tới Spy!", "Info", 3)
    end
})

-- ============================================================================
-- 9. TAB: RAID FARM
-- ============================================================================
SafeAddSection(Tabs.RaidFarm, "Tự Động Đi Raid & Thức Tỉnh (Dungeon Raid)")

UIControls.SelectedRaidChip = SafeAddDropdown(Tabs.RaidFarm, {
    Name        = "Chọn Loại Chip Raid (Select Raid Chip)",
    Description = "Chọn hệ Trái Ác Quỷ muốn mua Chip để đi Raid",
    Options     = { "Flame", "Ice", "Quake", "Light", "Dark", "Spider", "Rumble", "Magma", "Buddha", "Sand", "Phoenix", "Dough" },
    Default     = CurrentState.SelectedRaidChip,
    MultiSelect = false,
    Callback    = function(val)
        OnSettingChanged("SelectedRaidChip", val)
    end
})

UIControls.AutoBuyRaidChip = SafeAddToggle(Tabs.RaidFarm, {
    Name        = "Tự Động Mua Chip Raid (Auto Buy Microchip)",
    Description = "Tự động mua Chip Raid đã chọn bằng 100,000 Beli khi hết giờ chờ",
    Default     = CurrentState.AutoBuyRaidChip,
    Callback    = function(val)
        OnSettingChanged("AutoBuyRaidChip", val)
    end
})

UIControls.AutoFarmRaid = SafeAddToggle(Tabs.RaidFarm, {
    Name        = "Tự Động Vào Raid & Tiêu Diệt Quái (Auto Farm Raid / Kill Aura)",
    Description = "Tự động kích hoạt buồng Raid và tiêu diệt toàn bộ quái ở 5 đảo",
    Default     = CurrentState.AutoFarmRaid,
    Callback    = function(val)
        OnSettingChanged("AutoFarmRaid", val)
    end
})

UIControls.AutoNextIsland = SafeAddToggle(Tabs.RaidFarm, {
    Name        = "Tự Động Bay Qua Đảo Tiếp Theo (Auto Next Island)",
    Description = "Tự động chuyển sang đảo kế tiếp (1 -> 5) ngay khi dọn xong quái",
    Default     = CurrentState.AutoNextIsland,
    Callback    = function(val)
        OnSettingChanged("AutoNextIsland", val)
    end
})

UIControls.AutoAwakenFruit = SafeAddToggle(Tabs.RaidFarm, {
    Name        = "Tự Động Thức Tỉnh Chiêu Sau Khi Thắng Raid (Auto Awaken)",
    Description = "Tự động mở khóa kỹ năng thức tỉnh tại phòng Mysterious Entity",
    Default     = CurrentState.AutoAwakenFruit,
    Callback    = function(val)
        OnSettingChanged("AutoAwakenFruit", val)
    end
})

SafeAddSection(Tabs.RaidFarm, "Thao Tác Raid Nhanh (Raid Buttons)")

SafeAddButton(Tabs.RaidFarm, {
    Name        = "🎫 Mua Ngay Chip Raid Đã Chọn (Buy Selected Chip Now)",
    Description = "Mua ngay 1 Microchip thuộc hệ đã chọn trong Dropdown",
    Callback    = function()
        local chip = tostring(CurrentState.SelectedRaidChip or "Flame")
        invokeCommF("RaidsNpc", "Select", chip)
        Notify("Raid Farm", "Đã gửi lệnh mua Chip Raid hệ: " .. chip, "Success", 3)
    end
})

SafeAddButton(Tabs.RaidFarm, {
    Name        = "🚪 Dịch Chuyển Vào Phòng Thí Nghiệm Raid (Teleport To Raid Lab)",
    Description = "Di chuyển nhân vật tới khu vực mua Chip và vào lồng kính Raid",
    Callback    = function()
        Notify("Raid Farm", "Đang di chuyển tới Phòng Thí Nghiệm Raid!", "Info", 3)
    end
})

SafeAddButton(Tabs.RaidFarm, {
    Name        = "⚡ Thức Tỉnh Ngay Kỹ Năng Tiếp Theo (Awaken Current Skill)",
    Description = "Gọi sự kiện thức tỉnh chiêu thức Trái Ác Quỷ bằng Fragments",
    Callback    = function()
        invokeCommF("Awakener", "Awaken")
        Notify("Raid Farm", "Đã gửi yêu cầu thức tỉnh kỹ năng Trái Ác Quỷ!", "Success", 3)
    end
})

-- ============================================================================
-- 10. TAB: TELEPORT
-- ============================================================================
SafeAddSection(Tabs.Teleport, "Dịch Chuyển Giữa Các Đảo (Island Teleport)")

UIControls.SelectedIsland = SafeAddDropdown(Tabs.Teleport, {
    Name        = "Chọn Đảo Đích Đến (Select Destination Island)",
    Description = "Danh sách các địa điểm quan trọng tại Sea 1, Sea 2 và Sea 3",
    Options     = {
        "Starter Island",
        "Jungle",
        "Marine Fortress",
        "Sky Islands",
        "Fountain City",
        "Cafe (Sea 2)",
        "Green Zone",
        "Haunted Ship",
        "Snow Mountain",
        "Forgotten Island",
        "Port Town (Sea 3)",
        "Hydra Island",
        "Great Tree",
        "Floating Turtle (Mansion)",
        "Castle on the Sea",
        "Haunted Castle",
        "Sea of Treats (Cake Island)",
        "Tiki Outpost"
    },
    Default     = CurrentState.SelectedIsland,
    MultiSelect = false,
    Callback    = function(val)
        OnSettingChanged("SelectedIsland", val)
    end
})

UIControls.TweenSpeed = SafeAddSlider(Tabs.Teleport, {
    Name        = "Tốc Độ Bay Tween (Tween Flight Speed)",
    Description = "Điều chỉnh tốc độ bay tới đảo (Khuyên dùng: 220 - 300)",
    Min         = 100,
    Max         = 350,
    Increase    = 5,
    Default     = CurrentState.TweenSpeed,
    Callback    = function(val)
        OnSettingChanged("TweenSpeed", val)
    end
})

SafeAddButton(Tabs.Teleport, {
    Name        = "✈️ Bay Tới Đảo Đã Chọn (Tween To Selected Island)",
    Description = "Bắt đầu bay với tốc độ đã cài đặt tới đảo trong danh sách",
    Callback    = function()
        Notify("Teleport", "Đang bay tới: " .. tostring(CurrentState.SelectedIsland) .. " (Tốc độ: " .. tostring(CurrentState.TweenSpeed) .. ")", "Info", 3)
    end
})

SafeAddButton(Tabs.Teleport, {
    Name        = "🛑 Dừng Bay Tween Ngay Lập Tức (Cancel Tween)",
    Description = "Hủy đường bay hiện tại và giữ nhân vật đứng yên tại chỗ",
    Callback    = function()
        Notify("Teleport", "Đã dừng quá trình bay Tween!", "Warning", 2.5)
    end
})

SafeAddSection(Tabs.Teleport, "Chuyển Vùng Biển (World / Sea Travel)")

SafeAddButton(Tabs.Teleport, {
    Name        = "🌊 Chuyển Về Sea 1 (Travel To First Sea)",
    Description = "Dịch chuyển tài khoản về vùng biển thứ nhất (Old World)",
    Callback    = function()
        Notify("Teleport", "Đang chuyển sang Sea 1...", "Info", 3)
        invokeCommF("TravelMain")
    end
})

SafeAddButton(Tabs.Teleport, {
    Name        = "🌊 Chuyển Sang Sea 2 (Travel To Second Sea)",
    Description = "Dịch chuyển tài khoản sang vùng biển thứ hai (Dressrosa)",
    Callback    = function()
        Notify("Teleport", "Đang chuyển sang Sea 2...", "Info", 3)
        invokeCommF("TravelDressrosa")
    end
})

SafeAddButton(Tabs.Teleport, {
    Name        = "🌊 Chuyển Sang Sea 3 (Travel To Third Sea)",
    Description = "Dịch chuyển tài khoản sang vùng biển thứ ba (Zou)",
    Callback    = function()
        Notify("Teleport", "Đang chuyển sang Sea 3...", "Info", 3)
        invokeCommF("TravelZou")
    end
})

-- ============================================================================
-- 11. TAB: FRUIT
-- ============================================================================
SafeAddSection(Tabs.Fruit, "Săn & Quản Lý Trái Ác Quỷ (Devil Fruit Manager)")

UIControls.SelectedSniperFruit = SafeAddDropdown(Tabs.Fruit, {
    Name        = "Chọn Trái Muốn Săn Từ Shop (Select Sniper Fruit)",
    Description = "Trái Ác Quỷ ưu tiên tự động mua ngay khi xuất hiện trong cửa hàng",
    Options     = {
        "Rocket-Rocket",
        "Ice-Ice",
        "Light-Light",
        "Magma-Magma",
        "Buddha-Buddha",
        "Portal-Portal",
        "Rumble-Rumble",
        "Mammoth-Mammoth",
        "T-Rex-T-Rex",
        "Dough-Dough",
        "Leopard-Leopard",
        "Kitsune-Kitsune",
        "Dragon-Dragon"
    },
    Default     = CurrentState.SelectedSniperFruit,
    MultiSelect = false,
    Callback    = function(val)
        OnSettingChanged("SelectedSniperFruit", val)
    end
})

UIControls.AutoBuySniperFruit = SafeAddToggle(Tabs.Fruit, {
    Name        = "Tự Động Mua Trái Khi Có Hàng (Auto Buy Sniper Fruit)",
    Description = "Tự động kiểm tra Blox Fruit Dealer và mua ngay trái đã chọn",
    Default     = CurrentState.AutoBuySniperFruit,
    Callback    = function(val)
        OnSettingChanged("AutoBuySniperFruit", val)
    end
})

UIControls.AutoGrabFruit = SafeAddToggle(Tabs.Fruit, {
    Name        = "Tự Động Nhặt Trái Rơi Trên Bản Đồ (Auto Grab Dropped Fruit)",
    Description = "Tự động bay đi nhặt bất kỳ Trái Ác Quỷ nào xuất hiện trên mặt đất",
    Default     = CurrentState.AutoGrabFruit,
    Callback    = function(val)
        OnSettingChanged("AutoGrabFruit", val)
    end
})

UIControls.AutoStoreFruit = SafeAddToggle(Tabs.Fruit, {
    Name        = "Tự Động Cất Trái Vào Kho (Auto Store Fruit To Inventory)",
    Description = "Cất ngay trái vừa random hoặc vừa nhặt được vào Rương Kho Đồ",
    Default     = CurrentState.AutoStoreFruit,
    Callback    = function(val)
        OnSettingChanged("AutoStoreFruit", val)
    end
})

UIControls.AutoRandomFruit = SafeAddToggle(Tabs.Fruit, {
    Name        = "Tự Động Random Trái Mỗi 2 Giờ (Auto Roll Fruit Gacha)",
    Description = "Tự động mua trái ngẫu nhiên tại NPC Zioles khi hết thời gian chờ",
    Default     = CurrentState.AutoRandomFruit,
    Callback    = function(val)
        OnSettingChanged("AutoRandomFruit", val)
    end
})

SafeAddSection(Tabs.Fruit, "Thao Tác Trái Ác Quỷ Nhanh (Fruit Buttons)")

SafeAddButton(Tabs.Fruit, {
    Name        = "🎲 Random Trái Ác Quỷ Ngay (Roll Blox Fruit Gacha)",
    Description = "Quay thưởng 1 Trái Ác Quỷ ngẫu nhiên tại Zioles từ xa",
    Callback    = function()
        invokeCommF("Cousin", "Buy")
        Notify("Fruit", "Đã gửi lệnh Random Trái Ác Quỷ tại Zioles!", "Success", 3)
    end
})

SafeAddButton(Tabs.Fruit, {
    Name        = "📦 Cất Toàn Bộ Trái Trong Balo Vào Kho (Store All Fruits)",
    Description = "Quét Balo và nhân vật để cất tất cả Trái Ác Quỷ đang cầm vào kho",
    Callback    = function()
        local storedCount = 0
        pcall(function()
            local containers = { LocalPlayer.Backpack, LocalPlayer.Character }
            for _, container in ipairs(containers) do
                if container then
                    for _, tool in ipairs(container:GetChildren()) do
                        if tool:IsA("Tool") and string.find(tool.Name, "Fruit") then
                            local fruitCode = string.gsub(tool.Name, " Fruit", "")
                            fruitCode = fruitCode .. "-" .. fruitCode
                            invokeCommF("StoreFruit", fruitCode, tool)
                            storedCount += 1
                        end
                    end
                end
            end
        end)
        Notify("Fruit", string.format("Đã gửi lệnh cất %d Trái Ác Quỷ vào kho!", storedCount), "Success", 3)
    end
})

SafeAddButton(Tabs.Fruit, {
    Name        = "🛒 Mua Ngay Trái Đã Chọn Từ Shop (Buy Sniper Fruit Now)",
    Description = "Mua trực tiếp Trái Ác Quỷ đã chọn bằng Beli nếu đang có trong Stock",
    Callback    = function()
        local fruit = tostring(CurrentState.SelectedSniperFruit or "Rocket-Rocket")
        invokeCommF("BuyRawFruit", fruit, false)
        Notify("Fruit", "Đã gửi yêu cầu mua trái: " .. fruit, "Info", 3)
    end
})

-- ============================================================================
-- 12. TAB: VISUAL
-- ============================================================================
SafeAddSection(Tabs.Visual, "Định Vị ESP (Extra Sensory Perception)")

UIControls.EspPlayer = SafeAddToggle(Tabs.Visual, {
    Name        = "Hiển Thị Vị Trí Người Chơi (Player ESP)",
    Description = "Hiển thị tên, cấp độ, khoảng cách và thanh máu của người chơi khác",
    Default     = CurrentState.EspPlayer,
    Callback    = function(val)
        OnSettingChanged("EspPlayer", val)
    end
})

UIControls.EspFruit = SafeAddToggle(Tabs.Visual, {
    Name        = "Hiển Thị Vị Trí Trái Ác Quỷ (Devil Fruit ESP)",
    Description = "Đánh dấu tên và khoảng cách các Trái Ác Quỷ rơi trên bản đồ",
    Default     = CurrentState.EspFruit,
    Callback    = function(val)
        OnSettingChanged("EspFruit", val)
    end
})

UIControls.EspChest = SafeAddToggle(Tabs.Visual, {
    Name        = "Hiển Thị Vị Trí Rương Kho Báu (Chest & Berry ESP)",
    Description = "Đánh dấu vị trí Rương Vàng, Rương Kim Cương và Chén Thánh",
    Default     = CurrentState.EspChest,
    Callback    = function(val)
        OnSettingChanged("EspChest", val)
    end
})

UIControls.EspIsland = SafeAddToggle(Tabs.Visual, {
    Name        = "Hiển Thị Vị Trí Đảo & Hoa V2 (Island & Flower ESP)",
    Description = "Đánh dấu tọa độ các đảo (kể cả Mirage Island) và 3 bông hoa Tộc V2",
    Default     = CurrentState.EspIsland,
    Callback    = function(val)
        OnSettingChanged("EspIsland", val)
    end
})

UIControls.FullBright = SafeAddToggle(Tabs.Visual, {
    Name        = "Xóa Sương Mù & Làm Sáng Bản Đồ (No Fog / Full Bright)",
    Description = "Loại bỏ hoàn toàn sương mù vùng biển Level 6 và tăng độ sáng",
    Default     = CurrentState.FullBright,
    Callback    = function(val)
        OnSettingChanged("FullBright", val)
        if val then
            pcall(function()
                Lighting.FogEnd = 9e9
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
            end)
        end
    end
})

SafeAddSection(Tabs.Visual, "Tối Ưu Đồ Họa & Hiển Thị (Visual Buttons)")

SafeAddButton(Tabs.Visual, {
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
        Notify("Visual", "Đã áp dụng cấu hình giảm đồ họa tăng FPS!", "Success", 3)
    end
})

SafeAddButton(Tabs.Visual, {
    Name        = "⬜ Tắt Render 3D (White Screen - Treo Máy AFK)",
    Description = "Giảm tối đa tải GPU/CPU khi treo máy cày cấp thu nhỏ cửa sổ",
    Callback    = function()
        pcall(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        Notify("Visual", "Đã tắt Render 3D (chế độ tiết kiệm tài nguyên).", "Info", 3)
    end
})

SafeAddButton(Tabs.Visual, {
    Name        = "🖼️ Bật Lại Render 3D (Enable 3D Rendering)",
    Description = "Khôi phục hiển thị hình ảnh 3D bình thường",
    Callback    = function()
        pcall(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        Notify("Visual", "Đã bật lại hiển thị 3D!", "Success", 3)
    end
})

-- ============================================================================
-- 13. TAB: SHOP
-- ============================================================================
SafeAddSection(Tabs.Shop, "Cửa Hàng Võ Thuật (Fighting Styles)")

SafeAddButton(Tabs.Shop, {
    Name        = "🦵 Mua Black Leg / Death Step",
    Description = "Học võ Black Leg hoặc nâng cấp Death Step từ xa",
    Callback    = function()
        invokeCommF("BuyBlackLeg")
        invokeCommF("BuyDeathStep")
        Notify("Shop", "Đã gửi lệnh mua Black Leg / Death Step!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "⚡ Mua Electro / Electric Claw",
    Description = "Học võ Electro hoặc nâng cấp Electric Claw từ xa",
    Callback    = function()
        invokeCommF("BuyElectro")
        invokeCommF("BuyElectricClaw")
        Notify("Shop", "Đã gửi lệnh mua Electro / Electric Claw!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🌊 Mua Water Kung Fu / Sharkman Karate",
    Description = "Học võ Water Kung Fu hoặc nâng cấp Sharkman Karate từ xa",
    Callback    = function()
        invokeCommF("BuyFishmanKarate")
        invokeCommF("BuySharkmanKarate")
        Notify("Shop", "Đã gửi lệnh mua Water Kung Fu / Sharkman Karate!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🐉 Mua Dragon Breath / Dragon Talon",
    Description = "Học võ Dragon Breath hoặc nâng cấp Dragon Talon từ xa",
    Callback    = function()
        invokeCommF("BlackbeardReward", "DragonClaw", "2")
        invokeCommF("BuyDragonTalon")
        Notify("Shop", "Đã gửi lệnh mua Dragon Breath / Dragon Talon!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "👊 Mua Superhuman",
    Description = "Học võ Superhuman (Yêu cầu 300 Mastery 4 võ cơ bản & 3,000,000 Beli)",
    Callback    = function()
        invokeCommF("BuySuperhuman")
        Notify("Shop", "Đã gửi lệnh mua võ Superhuman!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🔥 Mua Godhuman",
    Description = "Học võ Godhuman (Yêu cầu 400 Mastery các võ V2 & nguyên liệu)",
    Callback    = function()
        invokeCommF("BuyGodhuman")
        Notify("Shop", "Đã gửi lệnh mua võ Godhuman!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🩸 Mua Sanguine Art",
    Description = "Học võ Sanguine Art từ NPC Shafi tại Tiki Outpost",
    Callback    = function()
        invokeCommF("BuySanguineArt")
        Notify("Shop", "Đã gửi lệnh mua võ Sanguine Art!", "Success", 2.5)
    end
})

SafeAddSection(Tabs.Shop, "Kỹ Năng, Vũ Khí & Dịch Vụ Fragments")

SafeAddButton(Tabs.Shop, {
    Name        = "🛡️ Mua Bộ Kỹ Năng Cơ Bản (Geppo / Buso / Soru)",
    Description = "Mua trọn bộ Skyjump (Geppo), Aura (Buso) và Flash Step (Soru)",
    Callback    = function()
        invokeCommF("BuyHaki", "Geppo")
        invokeCommF("BuyHaki", "Buso")
        invokeCommF("BuyHaki", "Soru")
        Notify("Shop", "Đã gửi lệnh mua Geppo, Buso Haki và Soru!", "Success", 3)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🏹 Mua Súng Kabucha (1,500 Fragments)",
    Description = "Mua súng ná Kabucha từ The Strongest God trên Sky Island",
    Callback    = function()
        invokeCommF("BlackbeardReward", "Slingshot", "2")
        Notify("Shop", "Đã gửi lệnh mua súng Kabucha!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🔄 Hoàn Điểm Chỉ Số (Refund Stats - 2,500 Fragments)",
    Description = "Đặt lại toàn bộ điểm tiềm năng (Stat Reset) tại NPC Plokster",
    Callback    = function()
        invokeCommF("BlackbeardReward", "Refund", "2")
        Notify("Shop", "Đã thực hiện hoàn điểm chỉ số (Refund Stats)!", "Success", 3)
    end
})

SafeAddButton(Tabs.Shop, {
    Name        = "🎲 Đổi Tộc Ngẫu Nhiên (Reroll Race - 3,000 Fragments)",
    Description = "Đổi ngẫu nhiên sang Tộc mới (Human / Mink / Shark / Angel) tại Tort",
    Callback    = function()
        invokeCommF("BlackbeardReward", "Reroll", "2")
        Notify("Shop", "Đã thực hiện đổi Tộc ngẫu nhiên (Reroll Race)!", "Success", 3)
    end
})

-- ============================================================================
-- 14. TAB: MISC
-- ============================================================================
SafeAddSection(Tabs.Misc, "Tiện Ích Máy Chủ (Server Utilities)")

SafeAddButton(Tabs.Misc, {
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

SafeAddButton(Tabs.Misc, {
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

SafeAddSection(Tabs.Misc, "Tiện Ích Đội Hình & Mã Quà Tặng")

SafeAddButton(Tabs.Misc, {
    Name        = "🏴‍☠️ Chọn Phe Hải Tặc (Join Pirates Team)",
    Description = "Chuyển nhân vật sang đội Hải Tặc (Pirates)",
    Callback    = function()
        invokeCommF("SetTeam", "Pirates")
        Notify("Misc", "Đã chuyển sang phe Hải Tặc (Pirates)!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Misc, {
    Name        = "⚓ Chọn Phe Hải Quân (Join Marines Team)",
    Description = "Chuyển nhân vật sang đội Hải Quân (Marines)",
    Callback    = function()
        invokeCommF("SetTeam", "Marines")
        Notify("Misc", "Đã chuyển sang phe Hải Quân (Marines)!", "Success", 2.5)
    end
})

SafeAddButton(Tabs.Misc, {
    Name        = "🎁 Nhập Toàn Bộ Code X2 EXP (Redeem All X2 EXP Codes)",
    Description = "Tự động nhập danh sách mã quà tặng X2 EXP và Stat Reset mới nhất",
    Callback    = function()
        local codes = {
            "KITT_RESET", "Sub2CaptainMaui", "kittgaming", "Sub2Fer999",
            "Enyu_is_Pro", "Magicbus", "JCWK", "Starcodeheo", "Bluxxy",
            "fudd10_v2", "SUB2GAMERROBOT_EXP1", "Sub2NoobMaster123",
            "Sub2UncleKizaru", "Sub2Daigrock", "Axiore", "TantaiGaming",
            "StrawHatMaine", "Sub2OfficialNoobie", "Fudd10", "Bignews",
            "TheGreatAce"
        }
        task.spawn(function()
            pcall(function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local redeem = remotes and remotes:FindFirstChild("Redeem")
                if redeem and redeem:IsA("RemoteFunction") then
                    for _, code in ipairs(codes) do
                        pcall(function()
                            redeem:InvokeServer(code)
                        end)
                        task.wait(0.15)
                    end
                end
            end)
            Notify("Redeem Codes", "Đã hoàn tất nhập toàn bộ danh sách Code X2 EXP!", "Success", 3.5)
        end)
    end
})

SafeAddSection(Tabs.Misc, "Quản Lý Tệp Cấu Hình (" .. CONFIG.ConfigFile .. ")")

SafeAddParagraph(
    Tabs.Misc,
    "Trạng Thái Hỗ Trợ Executor",
    string.format(
        "• Ghi file (writefile): %s\n• Đọc file (readfile): %s\n• Kiểm tra file (isfile): %s",
        ExecutorSupport.WriteFile and "Hỗ trợ ✅" or "Không hỗ trợ ❌",
        ExecutorSupport.ReadFile and "Hỗ trợ ✅" or "Không hỗ trợ ❌",
        ExecutorSupport.IsFile and "Hỗ trợ ✅" or "Không hỗ trợ ❌"
    )
)

UIControls.AutoSave = SafeAddToggle(Tabs.Misc, {
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

SafeAddButton(Tabs.Misc, {
    Name        = "💾 Lưu Cấu Hình (Save Config)",
    Description = "Lưu toàn bộ thiết lập hiện tại vào file " .. CONFIG.ConfigFile,
    Callback    = function()
        SaveConfig(false)
    end
})

SafeAddButton(Tabs.Misc, {
    Name        = "📂 Tải Cấu Hình (Load Config)",
    Description = "Đọc và áp dụng cấu hình từ file " .. CONFIG.ConfigFile,
    Callback    = function()
        LoadConfig(false)
    end
})

SafeAddButton(Tabs.Misc, {
    Name        = "🔄 Đặt Lại Mặc Định (Reset Config)",
    Description = "Khôi phục toàn bộ cài đặt về trạng thái gốc ban đầu",
    Callback    = function()
        ResetConfig()
    end
})

SafeAddSection(Tabs.Misc, "Cá Nhân Hóa & Quản Lý Giao Diện (Interface)")

UIControls.Theme = SafeAddDropdown(Tabs.Misc, {
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

UIControls.MenuKeybind = SafeAddDropdown(Tabs.Misc, {
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

UIControls.ShowMobileButton = SafeAddToggle(Tabs.Misc, {
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

SafeAddButton(Tabs.Misc, {
    Name        = "🗑️ Đóng & Gỡ Bỏ Giao Diện (Destroy UI)",
    Description = "Dừng toàn bộ vòng lặp nền, ngắt kết nối sự kiện và xóa sạch GUI",
    Callback    = function()
        Notify("Maid Hub", "Đang đóng giao diện và dọn dẹp tài nguyên...", "Warning", 1.5)
        task.delay(0.4, function()
            CleanupAll()
        end)
    end
})

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
