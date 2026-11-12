local MaidHubAPI = { Config = Config, State = State, Util = Util }
env.MaidHubAPI = MaidHubAPI

MaidHubAPI.hopToServer = hopToServer

MaidHubAPI.travelToSea = travelToSea

local Tabs = {
    Info     = Window:MakeTab({ Title = "Info",          Icon = CONFIG.Icons.Info }),
    Farm     = Window:MakeTab({ Title = "Auto Farm",     Icon = CONFIG.Icons.Main }),
    Combat   = Window:MakeTab({ Title = "Combat",        Icon = CONFIG.Icons.Main }),
    Race     = Window:MakeTab({ Title = "Race & Sea",    Icon = CONFIG.Icons.Main }),
    Config   = Window:MakeTab({ Title = "Config",        Icon = CONFIG.Icons.Config }),
    Settings = Window:MakeTab({ Title = "Settings",      Icon = CONFIG.Icons.Settings }),
    About    = Window:MakeTab({ Title = "About",         Icon = CONFIG.Icons.About }),
}

local ENGINE = {
    Url = "https://raw.githubusercontent.com/hungd8722-cmd/Maid-hub/refs/heads/main/maid-hub.lua",
    PlaceIds = {
        [2753915549] = true,
        [4442272183] = true,
        [7449423635] = true,
        [79091703265657] = true,
        [100117331123089] = true,
    },
}

local EngineLoading = false

local function getAPI()
    local api = GlobalEnv.MaidHubAPI
    if type(api) == "table" and type(api.Config) == "table" then
        return api
    end
    return nil
end

local function pushValue(key, value)
    local api = getAPI()
    if not api then return false end
    api.Config[key] = value
    return true
end

local MATERIALS = {
    "Fish Tail", "Magma Ore", "Mystic Droplet", "Dragon Scale", "Bones", "Ectoplasm",
    "Conjured Cocoa", "Demonic Wisp", "Mini Tusk", "Vampire Fang", "Radioactive Material",
    "Gunpowder", "Scrap Metal", "Leather", "Angel Wings", "Nightmare Catcher",
    "Mirror Fractal", "Meteorite", "Yeti Fur",
}

local FEATURE_GROUPS = {
    { Tab = "Farm", Title = "Auto Farm Cơ Bản", Items = {
        { Type = "Toggle", Key = "AutoFarmLevel",  Default = false, Stop = true,
          Name = "Auto Farm Level", Desc = "Tự nhận nhiệm vụ và đánh quái theo level" },
        { Type = "Toggle", Key = "AutoGodhuman",   Default = false, Stop = true,
          Name = "Auto Godhuman", Desc = "Tự chuẩn bị và mua võ Godhuman" },
        { Type = "Toggle", Key = "AutoFarmKata",   Default = false, Stop = true,
          Name = "Auto Farm Katakuri", Desc = "Tự farm boss Katakuri / Dough King ở Cake Island" },
        { Type = "Toggle", Key = "AutoSummonKata", Default = false, Stop = true,
          Name = "Auto Gọi Katakuri", Desc = "Tự triệu hồi cổng boss khi đủ điều kiện" },
        { Type = "Toggle", Key = "AutoRandomBones", Default = true,
          Name = "Auto Quay Xương", Desc = "Tự đổi Bones lấy phần thưởng" },
    }},
    { Tab = "Farm", Title = "Farm Nguyên Liệu", Items = {
        { Type = "Toggle", Key = "AutoMaterial", Default = false, Stop = true,
          Name = "Auto Farm Nguyên Liệu", Desc = "Farm nguyên liệu đã chọn ở bên dưới" },
        { Type = "Dropdown", Key = "SelectedMaterial", Default = "Fish Tail", Options = MATERIALS,
          Name = "Chọn Nguyên Liệu", Desc = "Loại nguyên liệu muốn farm" },
    }},
    { Tab = "Farm", Title = "Hop Server", Items = {
        { Type = "Toggle", Key = "AutoHopWhenEmpty", Default = true,
          Name = "Tự Đổi Server Khi Hết Quái", Desc = "Hop server nếu không còn quái trong thời gian chờ" },
        { Type = "Slider", Key = "EmptyMobTimeout", Default = 25, Min = 10, Max = 120, Increase = 5,
          Name = "Thời Gian Chờ Hết Quái (giây)", Desc = "Sau bao lâu không thấy quái thì đổi server" },
        { Type = "Toggle", Key = "AutoHopNearFullMoon", Default = false, Stop = true,
          Name = "Hop Tìm Trăng Gần Full Moon", Desc = "Tự đổi server cho đến khi gặp trăng phù hợp" },
    }},

    { Tab = "Combat", Title = "Vũ Khí & Tấn Công", Items = {
        { Type = "Dropdown", Key = "SelectWeapon", Default = "Melee", Options = { "Melee", "Sword", "Blox Fruit" },
          Name = "Chọn Vũ Khí", Desc = "Loại vũ khí tự trang bị khi đánh" },
        { Type = "Toggle", Key = "FastAttack", Default = true,
          Name = "Đánh Nhanh (Fast Attack)", Desc = "Bật tốc độ đánh nhanh theo chế độ bên dưới" },
        { Type = "Dropdown", Key = "FastAttackMode", Default = "SuperFast", Options = { "SuperFast", "HyperBurst", "SafeHuman" },
          Name = "Chế Độ Đánh Nhanh", Desc = "SuperFast x2 / HyperBurst x3 / SafeHuman (nhịp tự nhiên)" },
        { Type = "Toggle", Key = "BringMob", Default = true,
          Name = "Gom Quái", Desc = "Kéo quái xung quanh về một điểm khi farm" },
        { Type = "Slider", Key = "BringRadius", Default = 340, Min = 100, Max = 500, Increase = 10,
          Name = "Bán Kính Gom Quái", Desc = "Phạm vi gom quái (studs)" },
        { Type = "Toggle", Key = "AutoBuso", Default = true,
          Name = "Tự Bật Haki Vũ Trang", Desc = "Tự bật Buso Haki khi cần" },
        { Type = "Toggle", Key = "NoStun", Default = true,
          Name = "Chống Choáng", Desc = "Gỡ các lực làm choáng/đẩy lên nhân vật" },
    }},
    { Tab = "Combat", Title = "Di Chuyển", Items = {
        { Type = "Slider", Key = "TweenSpeed", Default = 250, Min = 50, Max = 400, Increase = 10,
          Name = "Tốc Độ Bay", Desc = "Tốc độ di chuyển giữa các điểm" },
        { Type = "Slider", Key = "FarmDistance", Default = 14, Min = 5, Max = 30, Increase = 1,
          Name = "Khoảng Cách Đánh", Desc = "Độ cao/khoảng cách đứng so với quái" },
    }},

    { Tab = "Race", Title = "Tộc (Race)", Items = {
        { Type = "Toggle", Key = "AutoRaceV3", Default = false,
          Name = "Tự Dùng Skill Tộc V3", Desc = "Tự kích hoạt kỹ năng tộc V3" },
        { Type = "Toggle", Key = "AutoRaceV4", Default = false,
          Name = "Tự Biến Hình Tộc V4", Desc = "Tự kích hoạt Awakening khi đầy năng lượng" },
        { Type = "Toggle", Key = "AutoTrainRaceV4", Default = false, Stop = true,
          Name = "Auto Train Tộc V4", Desc = "Tự luyện tiến trình Race V4" },
        { Type = "Toggle", Key = "AutoTrialRaceV4", Default = false, Stop = true,
          Name = "Auto Trial Tộc V4", Desc = "Tự làm thử thách Race V4" },
        { Type = "Toggle", Key = "AutoFlyBuyGear", Default = false, Stop = true,
          Name = "Auto Mua Gear", Desc = "Tự bay tới và mua Gear" },
    }},
    { Tab = "Race", Title = "Biển (Sea)", Items = {
        { Type = "Toggle", Key = "AutoFindLeviathan", Default = false, Stop = true,
          Name = "Auto Tìm Leviathan", Desc = "Tự đi thuyền tìm Leviathan" },
        { Type = "Toggle", Key = "AutoAttackLeviathan", Default = false, Stop = true,
          Name = "Auto Đánh Leviathan", Desc = "Tự tấn công Leviathan khi gặp" },
    }},
    { Tab = "Race", Title = "Tiện Ích Game", Items = {
        { Type = "Button", Name = "🌊 Sang Sea 1", Desc = "Dịch chuyển sang First Sea",
          Action = function(api) if api.travelToSea then api.travelToSea(1) end end },
        { Type = "Button", Name = "🌊 Sang Sea 2", Desc = "Dịch chuyển sang Second Sea",
          Action = function(api) if api.travelToSea then api.travelToSea(2) end end },
        { Type = "Button", Name = "🌊 Sang Sea 3", Desc = "Dịch chuyển sang Third Sea",
          Action = function(api) if api.travelToSea then api.travelToSea(3) end end },
        { Type = "Button", Name = "🌐 Hop Server (Engine)", Desc = "Đổi server bằng bộ tìm server của engine",
          Action = function(api) if api.hopToServer then api.hopToServer("Normal", "Thủ công") end end },
    }},
}

for _, group in ipairs(FEATURE_GROUPS) do
    for _, it in ipairs(group.Items) do
        if it.Key then
            DEFAULT_STATE[it.Key] = it.Default
            if CurrentState[it.Key] == nil then
                CurrentState[it.Key] = it.Default
            end
        end
    end
end

local function pushAllToEngine()
    local api = getAPI()
    if not api then return end
    for _, group in ipairs(FEATURE_GROUPS) do
        for _, it in ipairs(group.Items) do
            if it.Key and CurrentState[it.Key] ~= nil then
                api.Config[it.Key] = CurrentState[it.Key]
            end
        end
    end
end

local function loadEngine(silent)
    if getAPI() then return true end
    if EngineLoading then return false end

    if not ENGINE.PlaceIds[game.PlaceId] then
        if not silent then
            Notify("Engine", "Game hiện tại không phải Blox Fruits nên không nạp engine.", "Warning", 4)
        end
        return false
    end

    EngineLoading = true
    local ok, err = pcall(function()
        local source = game:HttpGet(ENGINE.Url)
        local fn, compileErr = loadstring(source)
        if not fn then error(compileErr) end
        task.spawn(fn)
    end)

    if not ok then
        EngineLoading = false
        Notify("Engine Lỗi", "Không nạp được engine: " .. tostring(err), "Error", 5)
        return false
    end

    local t0 = os.clock()
    while running and not getAPI() and (os.clock() - t0) < 20 do
        task.wait(0.25)
    end
    EngineLoading = false

    if getAPI() then
        pushAllToEngine()
        Notify("Engine", "Đã kết nối engine. Các công tắc đã sẵn sàng!", "Success", 3)
        return true
    end

    Notify("Engine Lỗi", "Engine không xuất API (kiểm tra đã dán PHẦN 1 chưa).", "Error", 5)
    return false
end

local function StopAllAutomation()
    for _, group in ipairs(FEATURE_GROUPS) do
        for _, it in ipairs(group.Items) do
            if it.Type == "Toggle" and it.Stop then
                CurrentState[it.Key] = false
                pushValue(it.Key, false)
                local ctrl = UIControls[it.Key]
                if ctrl then
                    pcall(function()
                        if type(ctrl.Set) == "function" then ctrl:Set(false) end
                    end)
                end
            end
        end
    end
    local api = getAPI()
    if api then
        pcall(function()
            api.State.MoveTargetPos = nil
            api.State.PosMon = nil
            api.State.LockedMob = nil
        end)
    end
    if CurrentState.AutoSave then SaveConfig(true) end
    Notify("Maid Hub", "Đã tắt toàn bộ tính năng tự động.", "Warning", 2.5)
end

local function BuildGroup(tab, group)
    SafeAddSection(tab, group.Title)
    for _, it in ipairs(group.Items) do
        if it.Type == "Toggle" then
            UIControls[it.Key] = SafeAddToggle(tab, {
                Name        = it.Name,
                Description = it.Desc,
                Default     = CurrentState[it.Key],
                Callback    = function(value)
                    OnSettingChanged(it.Key, value)
                    if not pushValue(it.Key, value) and value and not isApplyingConfig then
                        Notify("Engine", "Engine chưa được nạp. Vào tab Auto Farm bấm 'Nạp Engine'.", "Warning", 3.5)
                    end
                end
            })
        elseif it.Type == "Slider" then
            UIControls[it.Key] = SafeAddSlider(tab, {
                Name        = it.Name,
                Description = it.Desc,
                Min         = it.Min,
                Max         = it.Max,
                Increase    = it.Increase,
                Default     = CurrentState[it.Key],
                Callback    = function(value)
                    OnSettingChanged(it.Key, value)
                    pushValue(it.Key, value)
                end
            })
        elseif it.Type == "Dropdown" then
            UIControls[it.Key] = SafeAddDropdown(tab, {
                Name        = it.Name,
                Description = it.Desc,
                Options     = it.Options,
                Default     = CurrentState[it.Key],
                MultiSelect = false,
                Callback    = function(selected)
                    OnSettingChanged(it.Key, selected)
                    pushValue(it.Key, selected)
                end
            })
        elseif it.Type == "Button" then
            SafeAddButton(tab, {
                Name        = it.Name,
                Description = it.Desc,
                Callback    = function()
                    local api = getAPI()
                    if not api then
                        Notify("Engine", "Engine chưa được nạp!", "Warning", 3)
                        return
                    end
                    task.spawn(function()
                        local ok, err = pcall(it.Action, api)
                        if not ok then
                            Notify("Lỗi", tostring(err), "Error", 4)
                        end
                    end)
                end
            })
        end
    end
end

SafeAddSection(Tabs.Farm, "Điều Khiển Engine")
local EngineStatusParagraph = SafeAddParagraph(Tabs.Farm, "Trạng Thái", "Engine: chưa nạp")

SafeAddButton(Tabs.Farm, {
    Name        = "🔌 Nạp Engine",
    Description = "Tải và kết nối engine nếu chưa tự nạp",
    Callback    = function()
        task.spawn(loadEngine, false)
    end
})

SafeAddButton(Tabs.Farm, {
    Name        = "⛔ Dừng Tất Cả",
    Description = "Tắt mọi tính năng tự động đang chạy",
    Callback    = StopAllAutomation
})

local TAB_BY_NAME = { Farm = Tabs.Farm, Combat = Tabs.Combat, Race = Tabs.Race }
for _, group in ipairs(FEATURE_GROUPS) do
    local tab = TAB_BY_NAME[group.Tab]
    if tab then BuildGroup(tab, group) end
end

task.spawn(function()
    while running do
        pcall(function()
            local api = getAPI()
            if not api then
                SafeSetDesc(EngineStatusParagraph, "Engine: chưa nạp")
                return
            end
            local active = {}
            for _, group in ipairs(FEATURE_GROUPS) do
                for _, it in ipairs(group.Items) do
                    if it.Type == "Toggle" and it.Stop and api.Config[it.Key] then
                        table.insert(active, it.Name)
                    end
                end
            end
            local level = "?"
            pcall(function() level = LocalPlayer.Data.Level.Value end)
            SafeSetDesc(EngineStatusParagraph, string.format(
                "Engine: đã kết nối\nLevel: %s\nĐang chạy: %s",
                tostring(level),
                #active > 0 and table.concat(active, ", ") or "không có"
            ))
        end)
        task.wait(1)
    end
end)

task.spawn(function()
    task.wait(1.5)
    if running then loadEngine(true) end
end)

pcall(function()
    if GlobalEnv.__MaidHubCleanup then GlobalEnv.__MaidHubCleanup() end
    GlobalEnv.MaidHubAPI = nil
end)
