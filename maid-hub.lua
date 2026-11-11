local env = (getgenv and getgenv()) or _G
if env.__MaidHubCleanup then
    pcall(env.__MaidHubCleanup)
elseif env.__StarHubV4Cleanup then
    pcall(env.__StarHubV4Cleanup)
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local unpackFn = table.unpack or unpack

local function safeGetService(serviceName)
    local ok, svc = pcall(function()
        return game:GetService(serviceName)
    end)
    return ok and svc or nil
end

local Players = safeGetService("Players")
local ReplicatedStorage = safeGetService("ReplicatedStorage")
local RunService = safeGetService("RunService")
local TweenService = safeGetService("TweenService")
local TeleportService = safeGetService("TeleportService")
local HttpService = safeGetService("HttpService")
local VirtualUser = safeGetService("VirtualUser")
local UserInputService = safeGetService("UserInputService")
local CoreGui = safeGetService("CoreGui")
local GuiService = safeGetService("GuiService")
local Lighting = safeGetService("Lighting")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Util = {
    DebugLog = (env.MaidHubDebug ~= false),
    Shutdown = false,
    LogClock = {},
    LogCount = 0,
    RemoteCache = {},
    RemoteCacheCount = 0,
    RemoteNextSlot = 0,
    Threads = {},
    RealCommF = Remotes:WaitForChild("CommF_"),
    RemoteLimits = {
        getInventory = 0.9,
        CakePrinceSpawner = 1.0,
        Bones = 0.9,
        InfoLeviathan = 1.0,
        UpgradeRace = 0.8,
        RaceV4Progress = 0.4,
        requestEntrance = 1.0,
        StartQuest = 0.6,
        AbandonQuest = 0.6,
        BuyGodhuman = 1.0,
        BuyDragonTalon = 1.0,
        BuySharkmanKarate = 1.0,
        BuyElectricClaw = 1.0,
        BuyDeathStep = 1.0,
        BlackbeardReward = 0.8,
        OpenLeviathanGate = 1.0,
        FrozenDimension = 1.0,
        BuyBoat = 1.5,
        Buso = 0.5,
    },
    RemoteNoThrottle = { TravelMain = true, TravelDressrosa = true, TravelZou = true },
    RemoteDefaultGap = 0.25,
    RemoteGlobalGap = 0.12,
}

function Util.logWarn(tag, err)
    if not Util.DebugLog then return end
    local key = tostring(tag) .. "|" .. tostring(err)
    local now = os.clock()
    local last = Util.LogClock[key]
    if last and (now - last) < 8 then return end
    if Util.LogCount > 200 then
        Util.LogClock = {}
        Util.LogCount = 0
    end
    if not last then Util.LogCount = Util.LogCount + 1 end
    Util.LogClock[key] = now
    warn(string.format("[MaidHub][%s] %s", tostring(tag), tostring(err)))
end

function Util.safeCall(tag, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        Util.logWarn(tag, res)
    end
    return ok, res
end

local function buildRemoteSignature(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        local v = select(i, ...)
        parts[i] = (typeof(v) == "table") and ("tbl:" .. tostring(v)) or tostring(v)
    end
    return table.concat(parts, "|")
end

Util.CommF = {}
function Util.CommF:InvokeServer(...)
    local real = Util.RealCommF
    local cmdKey = tostring((...))
    if Util.RemoteNoThrottle[cmdKey] then
        return real:InvokeServer(...)
    end

    local sig = buildRemoteSignature(...)
    local now = os.clock()
    local gap = Util.RemoteLimits[cmdKey] or Util.RemoteDefaultGap
    local entry = Util.RemoteCache[sig]
    if entry and (now - entry.t) < gap then
        return unpackFn(entry.res, 1, entry.res.n)
    end

    local slot = math.max(now, Util.RemoteNextSlot)
    Util.RemoteNextSlot = slot + Util.RemoteGlobalGap
    if slot > now then
        task.wait(slot - now)
        if Util.Shutdown then return nil end
    end

    if not entry then
        Util.RemoteCacheCount = Util.RemoteCacheCount + 1
        if Util.RemoteCacheCount > 300 then
            Util.RemoteCache = {}
            Util.RemoteCacheCount = 1
        end
    end

    local placeholder = { t = os.clock(), res = { n = 0 } }
    Util.RemoteCache[sig] = placeholder

    local packed = table.pack(pcall(real.InvokeServer, real, ...))
    if not packed[1] then
        Util.RemoteCache[sig] = nil
        Util.logWarn("CommF_:" .. cmdKey, packed[2])
        error(packed[2], 0)
    end
    if cmdKey == "getInventory" and packed[2] == nil then
        Util.RemoteCache[sig] = nil
        return nil
    end
    placeholder.t = os.clock()
    placeholder.res = { n = packed.n - 1, unpackFn(packed, 2, packed.n) }
    return unpackFn(placeholder.res, 1, placeholder.res.n)
end
setmetatable(Util.CommF, {
    __index = function(_, k)
        local v = Util.RealCommF[k]
        if type(v) == "function" then
            return function(_, ...) return v(Util.RealCommF, ...) end
        end
        return v
    end
})

function Util.spawnTracked(tag, fn)
    local threads = Util.Threads
    if #threads >= 24 then
        for i = #threads, 1, -1 do
            if coroutine.status(threads[i]) == "dead" then
                table.remove(threads, i)
            end
        end
    end
    local th = task.spawn(function()
        local ok, err = pcall(fn)
        if not ok then Util.logWarn(tag, err) end
    end)
    threads[#threads + 1] = th
    return th
end

function Util.cancelAll()
    local me = coroutine.running()
    for _, th in ipairs(Util.Threads) do
        if th ~= me and coroutine.status(th) ~= "dead" then
            pcall(task.cancel, th)
        end
    end
    Util.Threads = {}
end

local CommF_ = Util.CommF

local PlaceId = game.PlaceId
local CurrentJobId = game.JobId
local CurrentSea = 1
if PlaceId == 4442272183 or PlaceId == 79091703265657 then
    CurrentSea = 2
elseif PlaceId == 7449423635 or PlaceId == 100117331123089 then
    CurrentSea = 3
end

local PlayerSafeName = tostring(LocalPlayer.Name or "Player"):gsub("[^%w_]", "")
local ConfigFileName = "MaidHub_V5_Config_" .. PlayerSafeName .. ".json"
local LegacyConfigFileName = "StarHub_V4_Config_" .. PlayerSafeName .. ".json"
local VisitedServersFile = "MaidHub_V5_VisitedServers.json"

local Config = {
    AutoSaveConfig = true,
    AutoFarmLevel = false,
    AutoGodhuman = false,
    AutoMaterial = false,
    AutoFarmKata = false,
    AutoSummonKata = false,
    AutoTrainRaceV4 = false,
    AutoFlyBuyGear = false,
    AutoTrialRaceV4 = false,
    AutoHopNearFullMoon = false,
    AutoFindLeviathan = false,
    AutoAttackLeviathan = false,
    Spoof5PlayersBoat = false,
    LeviathanTailDamagePercent = 0.15,
    ActiveMainMode = "None",
    SelectedMaterial = "Fish Tail",
    SelectWeapon = "Melee",
    FastAttack = true,
    FastAttackMode = "SuperFast",
    BringMob = true,
    AutoBuso = true,
    AutoRaceV3 = false,
    AutoRaceV4 = false,
    AutoRandomBones = true,
    NoStun = true,
    AutoHopWhenEmpty = true,
    EmptyMobTimeout = 25,
    TweenSpeed = 250,
    MinTweenSpeed = 50,
    MaxTweenSpeed = 400,
    FarmDistance = 14,
    BringRadius = 340,
    BringInterval = 0.12,
    FastAttackMaxTargets = 20,
    FastAttackDelay = 0.035,
    MasteryCache = {},
    ToggleKey = Enum.KeyCode.RightControl
}

local SavedConfigKeys = {
    "AutoSaveConfig",
    "AutoFarmLevel",
    "AutoGodhuman",
    "AutoMaterial",
    "AutoFarmKata",
    "AutoSummonKata",
    "AutoTrainRaceV4",
    "AutoFlyBuyGear",
    "AutoTrialRaceV4",
    "AutoHopNearFullMoon",
    "AutoFindLeviathan",
    "AutoAttackLeviathan",
    "Spoof5PlayersBoat",
    "ActiveMainMode",
    "SelectedMaterial",
    "SelectWeapon",
    "FastAttack",
    "FastAttackMode",
    "BringMob",
    "AutoBuso",
    "AutoRaceV3",
    "AutoRaceV4",
    "AutoRandomBones",
    "NoStun",
    "AutoHopWhenEmpty",
    "TweenSpeed",
    "MasteryCache"
}

local function saveConfig()
    if not Config.AutoSaveConfig then return false end
    if not writefile then return false end
    local ok, saveErr = pcall(function()
        local dataToSave = {}
        for _, key in ipairs(SavedConfigKeys) do
            dataToSave[key] = Config[key]
        end
        local encoded = HttpService:JSONEncode(dataToSave)
        writefile(ConfigFileName, encoded)
        writefile(LegacyConfigFileName, encoded)
    end)
    if not ok then Util.logWarn("SaveConfig", saveErr) end
    return ok
end

local function loadConfig()
    if not readfile or not isfile then return false end
    local targetFile = ConfigFileName
    local ok, exists = pcall(isfile, targetFile)
    if not ok or not exists then
        local okLegacy, existsLegacy = pcall(isfile, LegacyConfigFileName)
        if okLegacy and existsLegacy then
            targetFile = LegacyConfigFileName
        else
            return false
        end
    end

    local rOk, content = pcall(readfile, targetFile)
    if not rOk then Util.logWarn("LoadConfig.read", content) return false end
    if type(content) ~= "string" or #content == 0 then return false end

    local dOk, decoded = pcall(HttpService.JSONDecode, HttpService, content)
    if not dOk then Util.logWarn("LoadConfig.decode", decoded) return false end
    if type(decoded) ~= "table" then return false end

    for _, key in ipairs(SavedConfigKeys) do
        if decoded[key] ~= nil and type(decoded[key]) == type(Config[key]) then
            Config[key] = decoded[key]
        end
    end
    Config.TweenSpeed = math.floor(math.max(Config.MinTweenSpeed, math.min(Config.MaxTweenSpeed, tonumber(Config.TweenSpeed) or 250)))
    return true
end

loadConfig()

local State = {
    Running = true,
    IsHopping = false,
    MoveTargetPos = nil,
    LastCharacter = LocalPlayer.Character,
    NeedsMirrorPortalEntry = false,
    IsHoveringV4Sky = false,
    LastBossDamageClock = os.clock(),
    LastBossHealth = nil,
    LockedMob = nil,
    PosMon = nil,
    PosMonGroupKey = nil,
    CurrentMonFilter = nil,
    LastAcceptedQuestName = nil,
    LastAcceptedQuestId = nil,
    SpawnPointIndex = 1,
    LastSpawnSwitch = -999,
    LastMobSeenClock = os.clock(),
    HasGodhuman = false,
    MasteryCache = type(Config.MasteryCache) == "table" and Config.MasteryCache or {},
    ActiveMainMode = (Config.ActiveMainMode ~= "None" and Config.ActiveMainMode) or nil,
    InventoryCounts = {
        ["Fish Tail"] = 0,
        ["Magma Ore"] = 0,
        ["Mystic Droplet"] = 0,
        ["Dragon Scale"] = 0,
        ["Bones"] = 0,
        ["Ectoplasm"] = 0,
        ["Conjured Cocoa"] = 0,
        ["Demonic Wisp"] = 0,
        ["Mini Tusk"] = 0,
        ["Vampire Fang"] = 0,
        ["Radioactive Material"] = 0,
        ["Gunpowder"] = 0,
        ["Scrap Metal"] = 0,
        ["Leather"] = 0,
        ["Angel Wings"] = 0,
        ["Nightmare Catcher"] = 0,
        ["Mirror Fractal"] = 0,
        ["Meteorite"] = 0,
        ["Yeti Fur"] = 0,
        ["Dark Fragment"] = 0,
        ["Fire Essence"] = 0,
        ["Library Key"] = 0,
        ["Water Key"] = 0
    },
    VisitedServers = {},
    Connections = {}
}

local updateStatusUI
local updateDashboardUI

local function extractPosition(cfOrVec)
    if not cfOrVec then return Vector3.zero end
    if type(cfOrVec) == "table" then
        if cfOrVec.Position then return cfOrVec.Position end
        if cfOrVec.X and cfOrVec.Y and cfOrVec.Z then return Vector3.new(cfOrVec.X, cfOrVec.Y, cfOrVec.Z) end
    end
    local ok, pos = pcall(function()
        return cfOrVec.Position or Vector3.new(cfOrVec.X, cfOrVec.Y, cfOrVec.Z)
    end)
    if ok and pos then return pos end
    return cfOrVec
end

local function toFlatCFrame(cfOrVec, extraY)
    local p = extractPosition(cfOrVec)
    return CFrame.new(p.X, p.Y + (extraY or 0), p.Z)
end

local function loadVisitedServers()
    State.VisitedServers[CurrentJobId] = os.time()
    if readfile and isfile then
        local ok, exists = pcall(isfile, VisitedServersFile)
        if ok and exists then
            local rOk, content = pcall(readfile, VisitedServersFile)
            if rOk and type(content) == "string" and #content > 0 then
                local dOk, decoded = pcall(HttpService.JSONDecode, HttpService, content)
                if dOk and type(decoded) == "table" then
                    local now = os.time()
                    for jid, ts in pairs(decoded) do
                        if type(ts) == "number" and (now - ts) < 600 then
                            State.VisitedServers[jid] = ts
                        end
                    end
                end
            end
        end
    end
end

local function saveVisitedServers()
    State.VisitedServers[CurrentJobId] = os.time()
    if writefile then
        pcall(function()
            writefile(VisitedServersFile, HttpService:JSONEncode(State.VisitedServers))
        end)
    end
end

loadVisitedServers()
saveVisitedServers()

local function hookSingleErrorPrompt(v)
    pcall(function()
        if v and v.Name == "ErrorPrompt" then
            v.Visible = false
            if v.GetPropertyChangedSignal then
                table.insert(State.Connections, v:GetPropertyChangedSignal("Visible"):Connect(function()
                    if v.Visible then
                        v.Visible = false
                    end
                end))
            end
        end
    end)
end

local function dismissTeleportErrorPrompts()
    pcall(function()
        if GuiService and GuiService.ClearError then
            GuiService:ClearError()
        end
        local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
        local overlay = promptGui and promptGui:FindFirstChild("promptOverlay")
        if overlay then
            for _, v in ipairs(overlay:GetChildren()) do
                hookSingleErrorPrompt(v)
            end
        end
    end)
end

pcall(function()
    local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
    local overlay = promptGui and promptGui:FindFirstChild("promptOverlay")
    if overlay then
        for _, v in ipairs(overlay:GetChildren()) do
            hookSingleErrorPrompt(v)
        end
        table.insert(State.Connections, overlay.ChildAdded:Connect(function(child)
            hookSingleErrorPrompt(child)
            task.wait(0.05)
            if not State.Running then return end
            dismissTeleportErrorPrompts()
        end))
    end
end)

local function initBloxFruitsServerBrowser()
    pcall(function()
        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        local sbGui = pGui and pGui:FindFirstChild("ServerBrowser")
        if sbGui then
            if not sbGui.Enabled then
                sbGui.Enabled = true
            end
            local frame = sbGui:FindFirstChild("Frame")
            if frame then
                frame.Position = UDim2.new(3, 0, 3, 0)
                local filters = frame:FindFirstChild("Filters")
                local searchRegion = filters and filters:FindFirstChild("SearchRegion")
                local textBox = searchRegion and searchRegion:FindFirstChild("TextBox")
                if textBox then
                    textBox.Text = "Singapore"
                end
            end
        end
    end)
end

local function httpGetUrl(url)
    local ok, res = pcall(game.HttpGet, game, url)
    if ok and type(res) == "string" and #res > 0 then
        return res
    end
    local reqFn = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
    if reqFn then
        local rOk, resp = pcall(reqFn, { Url = url, Method = "GET" })
        if rOk and type(resp) == "table" and type(resp.Body) == "string" then
            return resp.Body
        end
    end
    return nil
end

local function fetchFromPublicApi(sortOrder)
    local list = {}
    local seen = {}
    local cursor = ""
    sortOrder = sortOrder or "Asc"

    for _ = 1, 3 do
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullGames=true%s",
            PlaceId, sortOrder,
            cursor ~= "" and ("&cursor=" .. HttpService:UrlEncode(cursor)) or ""
        )
        local raw = httpGetUrl(url)
        if raw then
            local dOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if dOk and type(data) == "table" and type(data.data) == "table" then
                for _, srv in ipairs(data.data) do
                    if type(srv) == "table" and type(srv.id) == "string" then
                        local count = tonumber(srv.playing) or 0
                        local maxP = tonumber(srv.maxPlayers) or 12
                        if srv.id ~= CurrentJobId
                            and not seen[srv.id]
                            and not State.VisitedServers[srv.id]
                            and count >= 2
                            and count <= (maxP - 2)
                        then
                            seen[srv.id] = true
                            table.insert(list, {
                                id = srv.id,
                                playing = count,
                                ping = tonumber(srv.ping) or 999
                            })
                        end
                    end
                end
                if #list >= 15 then break end
                if data.nextPageCursor and data.nextPageCursor ~= "" then
                    cursor = data.nextPageCursor
                    task.wait(0.15)
                    if not State.Running then break end
                else
                    break
                end
            else
                break
            end
        else
            break
        end
    end

    return list
end

local updateMoonButtonText

local function getMoonPhaseInfo()
    local tex = ""
    local clockTime = 18.0
    pcall(function()
        if not Lighting then
            Lighting = safeGetService("Lighting")
        end
        if Lighting then
            if Lighting.ClockTime ~= nil then
                clockTime = tonumber(Lighting.ClockTime) or 18.0
            end
            local sky = Lighting:FindFirstChildOfClass("Sky") or Lighting:FindFirstChild("Sky")
            if sky and sky.MoonTextureId then
                tex = tostring(sky.MoonTextureId)
            end
        end
    end)

    local h = math.floor(clockTime) % 24
    local m = math.floor((clockTime - math.floor(clockTime)) * 60)
    local timeStr = string.format("%02d:%02d", h, m)
    local isNight = (clockTime >= 18.0 or clockTime < 5.0)

    if string.find(tex, "9709149431", 1, true) then
        if clockTime >= 5.0 and clockTime < 12.0 then
            return {
                Phase = 1,
                Percent = 10,
                IsFullMoon = false,
                IsNearFullMoon = false,
                IsTargetMoon = false,
                TimeStr = timeStr,
                Name = "🌖 Full Moon Vừa Hết Sáng Nay",
                ShortName = "🌖 Vừa Hết FM"
            }
        elseif isNight then
            return {
                Phase = 5,
                Percent = 100,
                IsFullMoon = true,
                IsNearFullMoon = true,
                IsTargetMoon = true,
                TimeStr = timeStr,
                Name = "🌕 Đang Full Moon (5/5 - 100%)",
                ShortName = "🌕 5/5 (100%)"
            }
        else
            return {
                Phase = 5,
                Percent = 100,
                IsFullMoon = false,
                IsNearFullMoon = true,
                IsTargetMoon = true,
                TimeStr = timeStr,
                Name = "🌕 Sắp Lên Full Moon Tối Nay (5/5 - 100%)",
                ShortName = "🌕 Sắp FM 5/5"
            }
        end
    elseif string.find(tex, "9709149052", 1, true) then
        return {
            Phase = 4,
            Percent = 75,
            IsFullMoon = false,
            IsNearFullMoon = true,
            IsTargetMoon = true,
            TimeStr = timeStr,
            Name = "🌔 Gần Full Moon (4/5 - 75%)",
            ShortName = "🌔 4/5 (75%)"
        }
    elseif string.find(tex, "9709143733", 1, true) then
        return {
            Phase = 3,
            Percent = 50,
            IsFullMoon = false,
            IsNearFullMoon = false,
            IsTargetMoon = false,
            TimeStr = timeStr,
            Name = "🌓 Trăng Bán Nguyệt (3/5 - 50%)",
            ShortName = "🌓 3/5 (50%)"
        }
    elseif string.find(tex, "9709149680", 1, true) then
        return {
            Phase = 2,
            Percent = 25,
            IsFullMoon = false,
            IsNearFullMoon = false,
            IsTargetMoon = false,
            TimeStr = timeStr,
            Name = "🌒 Trăng Non (2/5 - 25%)",
            ShortName = "🌒 2/5 (25%)"
        }
    elseif string.find(tex, "9709135895", 1, true) then
        return {
            Phase = 0,
            Percent = 0,
            IsFullMoon = false,
            IsNearFullMoon = false,
            IsTargetMoon = false,
            TimeStr = timeStr,
            Name = "🌑 Không Trăng (0/5 - 0%)",
            ShortName = "🌑 0/5 (0%)"
        }
    elseif string.find(tex, "9709150401", 1, true)
        or string.find(tex, "9709150086", 1, true)
        or string.find(tex, "9709139597", 1, true)
    then
        return {
            Phase = 1,
            Percent = 15,
            IsFullMoon = false,
            IsNearFullMoon = false,
            IsTargetMoon = false,
            TimeStr = timeStr,
            Name = "🌘 Trăng Tàn (1/5 - 15%)",
            ShortName = "🌘 1/5 (15%)"
        }
    end

    return {
        Phase = 2,
        Percent = 25,
        IsFullMoon = false,
        IsNearFullMoon = false,
        IsTargetMoon = false,
        TimeStr = timeStr,
        Name = "🌓 Trăng Thường (Chưa Gần Full Moon)",
        ShortName = "🌓 Thường"
    }
end

local function hopToServer(mode, reason)
    if State.IsHopping then return end
    State.IsHopping = true
    mode = mode or "Normal"

    if updateStatusUI then
        updateStatusUI("🌐 Đang Hop Server (" .. tostring(reason or mode) .. ")...", Color3.fromRGB(255, 205, 85))
    end

    Util.spawnTracked("HopServer", function()
        dismissTeleportErrorPrompts()
        initBloxFruitsServerBrowser()

        pcall(function()
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                local highPos = Vector3.new(root.Position.X, math.max(root.Position.Y + 250, 350), root.Position.Z)
                State.MoveTargetPos = highPos
                root.CFrame = CFrame.new(highPos.X, highPos.Y, highPos.Z)
            end
        end)

        local serverBrowser = ReplicatedStorage:FindFirstChild("__ServerBrowser")

        if serverBrowser then
            for pass = 1, 2 do
                if not State.Running or not State.IsHopping then break end
                local maxPlayersAllowed = (mode == "LowPlayers") and 8 or 10
                if pass == 2 then
                    State.VisitedServers = { [CurrentJobId] = os.time() }
                    saveVisitedServers()
                    maxPlayersAllowed = 11
                end

                local triedAny = false
                for page = 1, 100 do
                    if not State.Running or not State.IsHopping then break end
                    local sbGap = os.clock() - (Util.LastServerBrowserClock or 0)
                    if sbGap < 0.3 then
                        task.wait(0.3 - sbGap)
                        if not State.Running then break end
                    end
                    Util.LastServerBrowserClock = os.clock()
                    local ok, servers = pcall(function()
                        return serverBrowser:InvokeServer(page)
                    end)
                    if not ok then Util.logWarn("ServerBrowser.page", servers) end

                    if ok and type(servers) == "table" then
                        local pageCandidates = {}
                        for jobId, info in pairs(servers) do
                            if type(jobId) == "string"
                                and jobId ~= CurrentJobId
                                and not State.VisitedServers[jobId]
                                and type(info) == "table"
                            then
                                local count = tonumber(info.Count or info["Count"] or info.playing) or 12
                                local ping = tonumber(info.Ping or info["Ping"] or info.ping) or 999
                                if count >= 1 and count <= maxPlayersAllowed then
                                    table.insert(pageCandidates, {
                                        id = jobId,
                                        playing = count,
                                        ping = ping
                                    })
                                end
                            end
                        end

                        if mode == "LowPlayers" then
                            table.sort(pageCandidates, function(a, b) return a.playing < b.playing end)
                        elseif mode == "LowPing" then
                            table.sort(pageCandidates, function(a, b) return a.ping < b.ping end)
                        end

                        for _, srv in ipairs(pageCandidates) do
                            if not State.Running or not State.IsHopping then break end
                            State.VisitedServers[srv.id] = os.time()
                            saveVisitedServers()
                            triedAny = true

                            if updateStatusUI then
                                updateStatusUI(
                                    string.format("🌐 Đang chuyển sang server [%d/12 người | Trang %d]...", srv.playing, page),
                                    Color3.fromRGB(115, 255, 160)
                                )
                            end

                            dismissTeleportErrorPrompts()
                            task.spawn(function()
                                Util.safeCall("ServerBrowser.teleport", function()
                                    serverBrowser:InvokeServer("teleport", tostring(srv.id))
                                end)
                            end)
                            task.wait(0.35)
                            if not State.Running then break end
                            dismissTeleportErrorPrompts()
                        end
                    elseif page == 1 then
                        break
                    end
                end

                if not triedAny then
                    local apiCandidates = fetchFromPublicApi((mode == "LowPlayers") and "Asc" or "Desc")
                    for _, srv in ipairs(apiCandidates) do
                        if not State.Running or not State.IsHopping then break end
                        State.VisitedServers[srv.id] = os.time()
                        saveVisitedServers()
                        triedAny = true

                        if updateStatusUI then
                            updateStatusUI(
                                string.format("🌐 Đang chuyển server qua __ServerBrowser [%d/12 người]...", srv.playing),
                                Color3.fromRGB(115, 255, 160)
                            )
                        end

                        dismissTeleportErrorPrompts()
                        task.spawn(function()
                            Util.safeCall("ServerBrowser.teleport", function()
                                serverBrowser:InvokeServer("teleport", tostring(srv.id))
                            end)
                        end)
                        task.wait(0.4)
                        if not State.Running then break end
                        dismissTeleportErrorPrompts()
                    end
                end
            end

            State.IsHopping = false
            return
        end

        local fallbackCandidates = fetchFromPublicApi((mode == "LowPlayers") and "Asc" or "Desc")
        for _, srv in ipairs(fallbackCandidates) do
            if not State.Running or not State.IsHopping then break end
            State.VisitedServers[srv.id] = os.time()
            saveVisitedServers()
            dismissTeleportErrorPrompts()
            Util.safeCall("TeleportToPlaceInstance", function()
                TeleportService:TeleportToPlaceInstance(PlaceId, tostring(srv.id), LocalPlayer)
            end)
            task.wait(1.0)
            if not State.Running then break end
        end

        State.IsHopping = false
    end)
end

table.insert(State.Connections, TeleportService.TeleportInitFailed:Connect(function(player)
    if player == LocalPlayer then
        dismissTeleportErrorPrompts()
    end
end))

local function travelToSea(targetSea)
    if CurrentSea == targetSea then return true end
    if updateStatusUI then
        updateStatusUI(string.format("🚢 Đang chuyển sang Sea %d...", targetSea), Color3.fromRGB(130, 210, 255))
    end
    Util.safeCall("travelToSea:L907", function()
        if targetSea == 1 then
            CommF_:InvokeServer("TravelMain")
        elseif targetSea == 2 then
            CommF_:InvokeServer("TravelDressrosa")
        elseif targetSea == 3 then
            CommF_:InvokeServer("TravelZou")
        end
    end)
    task.wait(3.5)
    if not State.Running then return false end
    return false
end

local CachedCombatCtrlTable = nil

local function onPlayerRespawned(newChar)
    State.LastCharacter = newChar
    State.LockedMob = nil
    State.PosMon = nil
    State.PosMonGroupKey = nil
    State.MoveTargetPos = nil
    State.NeedsMirrorPortalEntry = true
    State.IsHoveringV4Sky = false
    State.ElectricClawRunningToMansion = false
    CachedCombatCtrlTable = nil
    State.LastBossHealth = nil
    State.LastBossDamageClock = os.clock()
end

if LocalPlayer.CharacterAdded then
    table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function(newChar)
        onPlayerRespawned(newChar)
    end))
end

local function getCharacterRoot()
    local char = LocalPlayer.Character
    if not char then
        State.NeedsMirrorPortalEntry = true
        return nil, nil
    end
    if char ~= State.LastCharacter then
        onPlayerRespawned(char)
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if root and hum and hum.Health > 0 then
        return root, hum
    end
    if hum and hum.Health <= 0 then
        State.NeedsMirrorPortalEntry = true
        State.LockedMob = nil
        State.PosMon = nil
        State.MoveTargetPos = nil
    end
    return nil, nil
end

local function isAnyAutomationActive()
    return Config.AutoFarmLevel or Config.AutoGodhuman or Config.AutoMaterial or Config.AutoFarmKata or Config.AutoTrainRaceV4 or Config.AutoFlyBuyGear or Config.AutoTrialRaceV4 or Config.AutoFindLeviathan or Config.AutoAttackLeviathan
end

local function stopTween()
    State.MoveTargetPos = nil
end

local function setCharacterCollision(canCollide)
    local char = LocalPlayer.Character
    if not char then return end
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            if canCollide then
                if obj.Name == "HumanoidRootPart" or obj.Name == "Head" or obj.Name == "Torso" or obj.Name == "UpperTorso" or obj.Name == "LowerTorso" then
                    obj.CanCollide = true
                end
            else
                obj.CanCollide = false
            end
        end
    end
end

local function removeAntiFall()
    local char = LocalPlayer.Character
    if not char then return end
    setCharacterCollision(true)
    for _, partName in ipairs({ "Head", "HumanoidRootPart" }) do
        local p = char:FindFirstChild(partName)
        local bv = p and p:FindFirstChild("StarHubV4AntiFall")
        if bv then bv:Destroy() end
    end
end

local function moveToTarget(rawTargetCFrame)
    local root, hum = getCharacterRoot()
    if not root or not hum or not rawTargetCFrame then return end

    if hum.Sit then
        hum.Sit = false
    end

    local targetPos = extractPosition(rawTargetCFrame)
    State.MoveTargetPos = Vector3.new(targetPos.X, targetPos.Y, targetPos.Z)

    if (os.clock() - (State.LastHeartbeatFlightClock or -999)) > 0.08 then
        local currentPos = root.Position
        local diff = State.MoveTargetPos - currentPos
        local dist = diff.Magnitude
        if dist > 0.05 then
            local step = math.min(dist, math.max(Config.MinTweenSpeed, math.min(Config.MaxTweenSpeed, Config.TweenSpeed)) * 0.05)
            local dir = Vector3.new(diff.X / dist, diff.Y / dist, diff.Z / dist)
            local nextPos = Vector3.new(currentPos.X + dir.X * step, currentPos.Y + dir.Y * step, currentPos.Z + dir.Z * step)
            root.CFrame = CFrame.new(nextPos.X, nextPos.Y, nextPos.Z)
        end
    end
end

local function stepPureFlight(dt, isStepped)
    local char = LocalPlayer.Character
    if not char then return end

    local root = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health <= 0 then return end

    if root.Position.X > 27500 and root.Position.Y > 10000 and root.Position.Y < 14889.0 then
        root.CFrame = CFrame.new(root.Position.X, 14893.0, root.Position.Z)
        root.AssemblyLinearVelocity = Vector3.zero
        pcall(function() root.Velocity = Vector3.zero end)
        setCharacterCollision(true)
    end

    if not isAnyAutomationActive() then return end

    if State.TeleportingToTempleUntil and os.clock() < State.TeleportingToTempleUntil then
        removeAntiFall()
        return
    end

    if root.Position.Y >= 12000 and State.MoveTargetPos and State.MoveTargetPos.Y < 10000 then
        State.MoveTargetPos = nil
        return
    end

    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            if State.DisableNoClip then
                if obj.Name == "HumanoidRootPart" or obj.Name == "Head" or obj.Name == "Torso" or obj.Name == "UpperTorso" or obj.Name == "LowerTorso" then
                    obj.CanCollide = true
                end
            elseif obj.CanCollide then
                obj.CanCollide = false
            end
        elseif Config.NoStun and (obj.ClassName == "BodyGyro" or obj.ClassName == "BodyPosition") then
            pcall(function() obj:Destroy() end)
        end
    end

    if hum.PlatformStand then
        hum.PlatformStand = false
    end

    if State.MoveTargetPos or State.PosMon or State.IsHoveringV4Sky then
        local holdTarget = head or root
        if holdTarget then
            local bv = holdTarget:FindFirstChild("StarHubV4AntiFall")
            if not bv then
                bv = Instance.new("BodyVelocity")
                bv.Name = "StarHubV4AntiFall"
                bv.P = 1500
                bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                bv.Velocity = Vector3.zero
                bv.Parent = holdTarget
            else
                bv.Velocity = Vector3.zero
            end
        end
    else
        removeAntiFall()
    end

    if State.MoveTargetPos then
        local now = os.clock()
        local shouldStepPos = (not isStepped) or ((now - (State.LastHeartbeatFlightClock or -999)) > 0.05)
        if not isStepped then
            State.LastHeartbeatFlightClock = now
        end

        if shouldStepPos then
            local frameDt = tonumber(dt) or (1 / 60)
            if frameDt <= 0 or frameDt > 0.5 then
                frameDt = 1 / 60
            end

            local currentPos = root.Position
            local targetPos = State.MoveTargetPos
            local diff = targetPos - currentPos
            local dist = diff.Magnitude

            if dist > 1400 and (now - (State.LastStreamReqClock or 0)) >= 0.8 then
                State.LastStreamReqClock = now
                pcall(function()
                    LocalPlayer:RequestStreamAroundAsync(targetPos)
                end)
            end

            local speed = math.max(Config.MinTweenSpeed, math.min(Config.MaxTweenSpeed, tonumber(Config.TweenSpeed) or 250))
            local maxStep = speed * frameDt

            if dist <= maxStep or dist <= 0.5 then
                root.CFrame = CFrame.new(targetPos.X, targetPos.Y, targetPos.Z)
            else
                local nx = currentPos.X + (diff.X / dist) * maxStep
                local ny = currentPos.Y + (diff.Y / dist) * maxStep
                local nz = currentPos.Z + (diff.Z / dist) * maxStep
                root.CFrame = CFrame.new(nx, ny, nz)
            end
        end

        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

table.insert(State.Connections, RunService.Stepped:Connect(function(_, stepDt)
    stepPureFlight(stepDt or (1 / 60), true)
end))
table.insert(State.Connections, RunService.Heartbeat:Connect(function(dt)
    stepPureFlight(dt or (1 / 60), false)
end))

local QuestList = {
    [1] = {
        { Min = 1,   Max = 9,   Mon = "Bandit",              QName = "BanditQuest1",     QId = 1, QPos = CFrame.new(1059, 16, 1549),    MPos = CFrame.new(1145, 17, 1634) },
        { Min = 10,  Max = 14,  Mon = "Monkey",              QName = "JungleQuest",      QId = 1, QPos = CFrame.new(-1598, 36, 153),    MPos = CFrame.new(-1448, 50, 63) },
        { Min = 15,  Max = 29,  Mon = "Gorilla",             QName = "JungleQuest",      QId = 2, QPos = CFrame.new(-1598, 36, 153),    MPos = CFrame.new(-1142, 40, -515) },
        { Min = 30,  Max = 39,  Mon = "Pirate",              QName = "BuggyQuest1",      QId = 1, QPos = CFrame.new(-1140, 4, 3829),    MPos = CFrame.new(-1201, 40, 3857) },
        { Min = 40,  Max = 59,  Mon = "Brute",               QName = "BuggyQuest1",      QId = 2, QPos = CFrame.new(-1140, 4, 3829),    MPos = CFrame.new(-1387, 24, 4100) },
        { Min = 60,  Max = 74,  Mon = "Desert Bandit",       QName = "DesertQuest",      QId = 1, QPos = CFrame.new(894, 6, 4392),      MPos = CFrame.new(984, 16, 4417) },
        { Min = 75,  Max = 89,  Mon = "Desert Officer",      QName = "DesertQuest",      QId = 2, QPos = CFrame.new(894, 6, 4392),      MPos = CFrame.new(1547, 14, 4381) },
        { Min = 90,  Max = 99,  Mon = "Snow Bandit",         QName = "SnowQuest",        QId = 1, QPos = CFrame.new(1389, 87, -1298),   MPos = CFrame.new(1356, 106, -1328) },
        { Min = 100, Max = 119, Mon = "Snowman",             QName = "SnowQuest",        QId = 2, QPos = CFrame.new(1389, 87, -1298),   MPos = CFrame.new(1218, 138, -1488) },
        { Min = 120, Max = 149, Mon = "Chief Petty Officer", QName = "MarineQuest2",     QId = 1, QPos = CFrame.new(-5039, 28, 4324),   MPos = CFrame.new(-4931, 65, 4121) },
        { Min = 150, Max = 174, Mon = "Sky Bandit",          QName = "SkyQuest",         QId = 1, QPos = CFrame.new(-4839, 717, -2617),  MPos = CFrame.new(-4955, 365, -2908) },
        { Min = 175, Max = 189, Mon = "Dark Master",         QName = "SkyQuest",         QId = 2, QPos = CFrame.new(-4839, 717, -2617),  MPos = CFrame.new(-5148, 439, -2332) },
        { Min = 190, Max = 209, Mon = "Prisoner",            QName = "PrisonerQuest",    QId = 1, QPos = CFrame.new(5308, 2, 474),      MPos = CFrame.new(5098, 2, 474) },
        { Min = 210, Max = 249, Mon = "Dangerous Prisoner",  QName = "PrisonerQuest",    QId = 2, QPos = CFrame.new(5308, 2, 474),      MPos = CFrame.new(5654, 15, 866) },
        { Min = 250, Max = 274, Mon = "Toga Warrior",        QName = "ColosseumQuest",   QId = 1, QPos = CFrame.new(-1580, 7, -2986),   MPos = CFrame.new(-1820, 51, -2740) },
        { Min = 275, Max = 299, Mon = "Gladiator",           QName = "ColosseumQuest",   QId = 2, QPos = CFrame.new(-1580, 7, -2986),   MPos = CFrame.new(-1292, 56, -3339) },
        { Min = 300, Max = 324, Mon = "Military Soldier",    QName = "MagmaQuest",       QId = 1, QPos = CFrame.new(-5313, 12, 8515),   MPos = CFrame.new(-5369, 61, 8556) },
        { Min = 325, Max = 374, Mon = "Military Spy",        QName = "MagmaQuest",       QId = 2, QPos = CFrame.new(-5313, 12, 8515),   MPos = CFrame.new(-5787, 75, 8651) },
        { Min = 375, Max = 399, Mon = "Fishman Warrior",     QName = "FishmanQuest",     QId = 1, QPos = CFrame.new(61122, 18, 1569),   MPos = CFrame.new(60878, 50, 1543) },
        { Min = 400, Max = 449, Mon = "Fishman Commando",    QName = "FishmanQuest",     QId = 2, QPos = CFrame.new(61122, 18, 1569),   MPos = CFrame.new(61922, 50, 1493) },
        { Min = 450, Max = 474, Mon = "God's Guard",         QName = "SkyExp1Quest",     QId = 1, QPos = CFrame.new(-4721, 845, -1954),  MPos = CFrame.new(-4628, 866, -1931) },
        { Min = 475, Max = 524, Mon = "Shanda",              QName = "SkyExp1Quest",     QId = 2, QPos = CFrame.new(-7859, 5545, -381),  MPos = CFrame.new(-7678, 5566, -497) },
        { Min = 525, Max = 549, Mon = "Royal Squad",         QName = "SkyExp2Quest",     QId = 1, QPos = CFrame.new(-7906, 5634, -1411), MPos = CFrame.new(-7654, 5637, -1407) },
        { Min = 550, Max = 624, Mon = "Royal Soldier",       QName = "SkyExp2Quest",     QId = 2, QPos = CFrame.new(-7906, 5634, -1411), MPos = CFrame.new(-7836, 5650, -1750) },
        { Min = 625, Max = 649, Mon = "Galley Pirate",       QName = "FountainQuest",    QId = 1, QPos = CFrame.new(5259, 38, 4050),    MPos = CFrame.new(5551, 78, 3930) },
        { Min = 650, Max = 700, Mon = "Galley Captain",      QName = "FountainQuest",    QId = 2, QPos = CFrame.new(5259, 38, 4050),    MPos = CFrame.new(5677, 52, 4926) }
    },
    [2] = {
        { Min = 700,  Max = 724,  Mon = "Raider",            QName = "Area1Quest",       QId = 1, QPos = CFrame.new(-429, 72, 1836),    MPos = CFrame.new(-728, 52, 2345) },
        { Min = 725,  Max = 774,  Mon = "Mercenary",         QName = "Area1Quest",       QId = 2, QPos = CFrame.new(-429, 72, 1836),    MPos = CFrame.new(-1004, 80, 1424) },
        { Min = 775,  Max = 799,  Mon = "Swan Pirate",       QName = "Area2Quest",       QId = 1, QPos = CFrame.new(638, 73, 918),      MPos = CFrame.new(1068, 137, 1322) },
        { Min = 800,  Max = 874,  Mon = "Factory Staff",     QName = "Area2Quest",       QId = 2, QPos = CFrame.new(632, 73, 918),      MPos = CFrame.new(73, 81, -27) },
        { Min = 875,  Max = 899,  Mon = "Marine Lieutenant", QName = "MarineQuest3",     QId = 1, QPos = CFrame.new(-2440, 73, -3216),  MPos = CFrame.new(-2821, 73, -3070) },
        { Min = 900,  Max = 949,  Mon = "Marine Captain",    QName = "MarineQuest3",     QId = 2, QPos = CFrame.new(-2440, 73, -3216),  MPos = CFrame.new(-1861, 80, -3254) },
        { Min = 950,  Max = 974,  Mon = "Zombie",            QName = "ZombieQuest",      QId = 1, QPos = CFrame.new(-5497, 47, -795),   MPos = CFrame.new(-5657, 78, -928) },
        { Min = 975,  Max = 999,  Mon = "Vampire",           QName = "ZombieQuest",      QId = 2, QPos = CFrame.new(-5497, 47, -795),   MPos = CFrame.new(-6037, 32, -1340) },
        { Min = 1000, Max = 1049, Mon = "Snow Trooper",      QName = "SnowMountainQuest",QId = 1, QPos = CFrame.new(609, 400, -5372),   MPos = CFrame.new(549, 427, -5563) },
        { Min = 1050, Max = 1099, Mon = "Winter Warrior",    QName = "SnowMountainQuest",QId = 2, QPos = CFrame.new(609, 400, -5372),   MPos = CFrame.new(1142, 456, -5199) },
        { Min = 1100, Max = 1124, Mon = "Lab Subordinate",   QName = "IceSideQuest",     QId = 1, QPos = CFrame.new(-6064, 15, -4902),  MPos = CFrame.new(-5707, 15, -4513) },
        { Min = 1125, Max = 1174, Mon = "Horned Warrior",    QName = "IceSideQuest",     QId = 2, QPos = CFrame.new(-6064, 15, -4902),  MPos = CFrame.new(-6341, 15, -5723) },
        { Min = 1175, Max = 1199, Mon = "Magma Ninja",       QName = "FireSideQuest",    QId = 1, QPos = CFrame.new(-5428, 15, -5299),  MPos = CFrame.new(-5449, 76, -5808) },
        { Min = 1200, Max = 1249, Mon = "Lava Pirate",       QName = "FireSideQuest",    QId = 2, QPos = CFrame.new(-5428, 15, -5299),  MPos = CFrame.new(-5213, 49, -4701) },
        { Min = 1250, Max = 1274, Mon = "Ship Deckhand",     QName = "ShipQuest1",       QId = 1, QPos = CFrame.new(1037, 125, 32911),  MPos = CFrame.new(1212, 150, 33059) },
        { Min = 1275, Max = 1299, Mon = "Ship Engineer",     QName = "ShipQuest1",       QId = 2, QPos = CFrame.new(1037, 125, 32911),  MPos = CFrame.new(919, 43, 32779) },
        { Min = 1300, Max = 1324, Mon = "Ship Steward",      QName = "ShipQuest2",       QId = 1, QPos = CFrame.new(968, 125, 33244),   MPos = CFrame.new(919, 129, 33436) },
        { Min = 1325, Max = 1349, Mon = "Ship Officer",      QName = "ShipQuest2",       QId = 2, QPos = CFrame.new(968, 125, 33244),   MPos = CFrame.new(1036, 181, 33315) },
        { Min = 1350, Max = 1374, Mon = "Arctic Warrior",    QName = "FrostQuest",       QId = 1, QPos = CFrame.new(5667, 26, -6486),   MPos = CFrame.new(5966, 62, -6179) },
        { Min = 1375, Max = 1424, Mon = "Snow Lurker",       QName = "FrostQuest",       QId = 2, QPos = CFrame.new(5667, 26, -6486),   MPos = CFrame.new(5407, 69, -6880) },
        { Min = 1425, Max = 1449, Mon = "Sea Soldier",       QName = "ForgottenQuest",   QId = 1, QPos = CFrame.new(-3054, 235, -10142),MPos = CFrame.new(-3028, 64, -9775) },
        { Min = 1450, Max = 1500, Mon = "Water Fighter",     QName = "ForgottenQuest",   QId = 2, QPos = CFrame.new(-3054, 235, -10142),MPos = CFrame.new(-3352, 285, -10534) }
    },
    [3] = {
        { Min = 1500, Max = 1524, Mon = "Pirate Millionaire",QName = "PiratePortQuest",  QId = 1, QPos = CFrame.new(-290, 42, 5581),    MPos = CFrame.new(-245, 47, 5584) },
        { Min = 1525, Max = 1574, Mon = "Pistol Billionaire",QName = "PiratePortQuest",  QId = 2, QPos = CFrame.new(-290, 42, 5581),    MPos = CFrame.new(-187, 86, 6013) },
        { Min = 1575, Max = 1599, Mon = "Dragon Crew Warrior",QName = "AmazonQuest",     QId = 1, QPos = CFrame.new(5832, 51, -1101),   MPos = CFrame.new(6141, 51, -1340) },
        { Min = 1600, Max = 1624, Mon = "Dragon Crew Archer",QName = "AmazonQuest",      QId = 2, QPos = CFrame.new(5832, 51, -1101),   MPos = CFrame.new(6616, 378, 446) },
        { Min = 1625, Max = 1649, Mon = "Hydra Enforcer",    AltMons = { "Hydra Enforcer", "Female Islander" },   QName = "AmazonQuest2",     QId = 1, QPos = CFrame.new(5448, 601, 751),    MPos = CFrame.new(4685, 735, 815) },
        { Min = 1650, Max = 1699, Mon = "Venomous Assailant",AltMons = { "Venomous Assailant", "Giant Islander" },QName = "AmazonQuest2",     QId = 2, QPos = CFrame.new(5448, 601, 751),    MPos = CFrame.new(4729, 590, -36) },
        { Min = 1700, Max = 1724, Mon = "Marine Commodore",  QName = "MarineTreeIsland", QId = 1, QPos = CFrame.new(2180, 27, -6741),   MPos = CFrame.new(2286, 73, -7159) },
        { Min = 1725, Max = 1774, Mon = "Marine Rear Admiral",QName = "MarineTreeIsland",QId = 2, QPos = CFrame.new(2180, 27, -6741),   MPos = CFrame.new(3656, 160, -7001) },
        { Min = 1775, Max = 1799, Mon = "Fishman Raider",    QName = "DeepForestIsland3",QId = 1, QPos = CFrame.new(-10581, 330, -8761),MPos = CFrame.new(-10407, 331, -8368) },
        { Min = 1800, Max = 1824, Mon = "Fishman Captain",   QName = "DeepForestIsland3",QId = 2, QPos = CFrame.new(-10581, 330, -8761),MPos = CFrame.new(-10994, 352, -9002) },
        { Min = 1825, Max = 1849, Mon = "Forest Pirate",     QName = "DeepForestIsland", QId = 1, QPos = CFrame.new(-13234, 331, -7625),MPos = CFrame.new(-13479, 332, -7769) },
        { Min = 1850, Max = 1899, Mon = "Mythological Pirate",QName = "DeepForestIsland",QId = 2, QPos = CFrame.new(-13234, 331, -7625),MPos = CFrame.new(-13680, 501, -6991) },
        { Min = 1900, Max = 1924, Mon = "Jungle Pirate",     QName = "DeepForestIsland2",QId = 1, QPos = CFrame.new(-12680, 389, -9902),MPos = CFrame.new(-12256, 331, -10485) },
        { Min = 1925, Max = 1974, Mon = "Musketeer Pirate",  QName = "DeepForestIsland2",QId = 2, QPos = CFrame.new(-12680, 389, -9902),MPos = CFrame.new(-13457, 391, -9859) },
        { Min = 1975, Max = 1999, Mon = "Reborn Skeleton",   QName = "HauntedQuest1",    QId = 1, QPos = CFrame.new(-9479, 141, 5566),  MPos = CFrame.new(-8763, 165, 6159) },
        { Min = 2000, Max = 2024, Mon = "Living Zombie",     QName = "HauntedQuest1",    QId = 2, QPos = CFrame.new(-9479, 141, 5566),  MPos = CFrame.new(-10144, 138, 5838) },
        { Min = 2025, Max = 2049, Mon = "Demonic Soul",      QName = "HauntedQuest2",    QId = 1, QPos = CFrame.new(-9516, 172, 6078),  MPos = CFrame.new(-9505, 172, 6158) },
        { Min = 2050, Max = 2074, Mon = "Posessed Mummy",    QName = "HauntedQuest2",    QId = 2, QPos = CFrame.new(-9516, 172, 6078),  MPos = CFrame.new(-9582, 6, 6205) },
        { Min = 2075, Max = 2099, Mon = "Peanut Scout",      QName = "NutsIslandQuest",  QId = 1, QPos = CFrame.new(-2104, 38, -10194), MPos = CFrame.new(-2143, 47, -10029) },
        { Min = 2100, Max = 2124, Mon = "Peanut President",  QName = "NutsIslandQuest",  QId = 2, QPos = CFrame.new(-2104, 38, -10194), MPos = CFrame.new(-1859, 38, -10422) },
        { Min = 2125, Max = 2149, Mon = "Ice Cream Chef",    QName = "IceCreamIslandQuest",QId = 1, QPos = CFrame.new(-820, 65, -10965), MPos = CFrame.new(-789, 65, -10919) },
        { Min = 2150, Max = 2199, Mon = "Ice Cream Commander",QName = "IceCreamIslandQuest",QId = 2, QPos = CFrame.new(-820, 65, -10965),MPos = CFrame.new(-558, 112, -11290) },
        { Min = 2200, Max = 2224, Mon = "Cookie Crafter",    QName = "CakeQuest1",       QId = 1, QPos = CFrame.new(-2021, 37, -12028), MPos = CFrame.new(-2374, 37, -12125) },
        { Min = 2225, Max = 2249, Mon = "Cake Guard",        QName = "CakeQuest1",       QId = 2, QPos = CFrame.new(-2021, 37, -12028), MPos = CFrame.new(-1598, 43, -12244) },
        { Min = 2250, Max = 2274, Mon = "Baking Staff",      QName = "CakeQuest2",       QId = 1, QPos = CFrame.new(-1927, 37, -12842), MPos = CFrame.new(-1887, 77, -12998) },
        { Min = 2275, Max = 2299, Mon = "Head Baker",        QName = "CakeQuest2",       QId = 2, QPos = CFrame.new(-1927, 37, -12842), MPos = CFrame.new(-2216, 82, -12869) },
        { Min = 2300, Max = 2324, Mon = "Cocoa Warrior",     QName = "ChocQuest1",       QId = 1, QPos = CFrame.new(233, 29, -12200),   MPos = CFrame.new(-21, 80, -12352) },
        { Min = 2325, Max = 2349, Mon = "Chocolate Bar Battler",QName = "ChocQuest1",    QId = 2, QPos = CFrame.new(233, 29, -12200),   MPos = CFrame.new(582, 77, -12463) },
        { Min = 2350, Max = 2374, Mon = "Sweet Thief",       QName = "ChocQuest2",       QId = 1, QPos = CFrame.new(150, 30, -12774),   MPos = CFrame.new(165, 76, -12600) },
        { Min = 2375, Max = 2399, Mon = "Candy Rebel",       QName = "ChocQuest2",       QId = 2, QPos = CFrame.new(150, 30, -12774),   MPos = CFrame.new(134, 77, -12876) },
        { Min = 2400, Max = 2424, Mon = "Candy Pirate",      QName = "CandyQuest1",      QId = 1, QPos = CFrame.new(-1150, 20, -14446), MPos = CFrame.new(-1310, 26, -14562) },
        { Min = 2425, Max = 2449, Mon = "Snow Demon",        QName = "CandyQuest1",      QId = 2, QPos = CFrame.new(-1150, 20, -14446), MPos = CFrame.new(-880, 71, -14538) },
        { Min = 2450, Max = 2474, Mon = "Isle Outlaw",       QName = "TikiQuest1",       QId = 1, NPCName = "Tiki Quest Giver 1", QPos = CFrame.new(-16547, 55, -173),  MPos = { CFrame.new(-16442, 116, -264), CFrame.new(-16320, 116, -210) } },
        { Min = 2475, Max = 2499, Mon = "Island Boy",        QName = "TikiQuest1",       QId = 2, NPCName = "Tiki Quest Giver 1", QPos = CFrame.new(-16547, 55, -173),  MPos = { CFrame.new(-16901, 84, -192), CFrame.new(-16780, 84, -150) } },
        { Min = 2500, Max = 2524, Mon = "Sun-kissed Warrior",QName = "TikiQuest2",       QId = 1, NPCName = "Tiki Quest Giver 2", QPos = CFrame.new(-16539, 55, 1051),  MPos = { CFrame.new(-16349, 92, 1123), CFrame.new(-16250, 92, 1080) } },
        { Min = 2525, Max = 2549, Mon = "Isle Champion",     QName = "TikiQuest2",       QId = 2, NPCName = "Tiki Quest Giver 2", QPos = CFrame.new(-16539, 55, 1051),  MPos = { CFrame.new(-16641, 85, 1140), CFrame.new(-16750, 85, 1100) } },
        { Min = 2550, Max = 2574, Mon = "Serpent Hunter",    QName = "TikiQuest3",       QId = 1, NPCName = "Tiki Quest Giver 3", QPos = CFrame.new(-16665, 105, 1579), MPos = { CFrame.new(-16587, 106, 1468), CFrame.new(-16521, 106, 1612) }, RequirePresence = true },
        { Min = 2575, Max = 2599, Mon = "Skull Slayer",      QName = "TikiQuest3",       QId = 2, NPCName = "Tiki Quest Giver 3", QPos = CFrame.new(-16665, 105, 1579), MPos = { CFrame.new(-16838, 71, 1648), CFrame.new(-16752, 71, 1595) }, RequirePresence = true },
        { Min = 2600, Max = 2624, Mon = "Reef Bandit",       QName = "SubmergedQuest1",  QId = 1, NPCName = "Submerged Quest Giver 1", QPos = CFrame.new(-16539, -450, 1051), MPos = { CFrame.new(-16400, -440, 1150) }, RequirePresence = true },
        { Min = 2625, Max = 2649, Mon = "Coral Pirate",      QName = "SubmergedQuest1",  QId = 2, NPCName = "Submerged Quest Giver 1", QPos = CFrame.new(-16539, -450, 1051), MPos = { CFrame.new(-16650, -440, 1250) }, RequirePresence = true },
        { Min = 2650, Max = 2674, Mon = "Sea Chanter",       QName = "SubmergedQuest2",  QId = 1, NPCName = "Submerged Quest Giver 2", QPos = CFrame.new(-16800, -450, 1400), MPos = { CFrame.new(-16750, -440, 1550) }, RequirePresence = true },
        { Min = 2675, Max = 2699, Mon = "Ocean Prophet",     QName = "SubmergedQuest2",  QId = 2, NPCName = "Submerged Quest Giver 2", QPos = CFrame.new(-16800, -450, 1400), MPos = { CFrame.new(-16950, -440, 1600) }, RequirePresence = true },
        { Min = 2700, Max = 2724, Mon = "High Disciple",     QName = "SubmergedQuest3",  QId = 1, NPCName = "Submerged Quest Giver 3", QPos = CFrame.new(-17100, -450, 1750), MPos = { CFrame.new(-17050, -440, 1900) }, RequirePresence = true },
        { Min = 2725, Max = 9999, Mon = "Grand Devotee",     QName = "SubmergedQuest3",  QId = 2, NPCName = "Submerged Quest Giver 3", QPos = CFrame.new(-17100, -450, 1750), MPos = { CFrame.new(-17250, -440, 2000) }, RequirePresence = true }
    }
}

local function cleanMobName(name)
    if not name then return "" end
    local cleaned = string.gsub(tostring(name), "%s*%[Lv%.%s*%d+%]", "")
    return string.lower(cleaned)
end

local function isMobMatchingList(actualName, filterList)
    if not actualName or not filterList then return false end
    local cleanedActual = cleanMobName(actualName)
    for _, target in ipairs(filterList) do
        local cleanedTarget = cleanMobName(target)
        if cleanedActual == cleanedTarget or string.find(cleanedActual, cleanedTarget, 1, true) then
            return true
        end
    end
    return false
end

local function findDynamicQuestLocations(qInfo)
    local monList = qInfo.AltMons or { qInfo.Mon }
    local foundMobCFrames = {}
    local foundNpcCFrame = nil

    if qInfo.NPCName then
        local npcTargetLower = string.lower(qInfo.NPCName)
        for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), ReplicatedStorage:FindFirstChild("NPCs") }) do
            if folder then
                for _, npc in ipairs(folder:GetChildren()) do
                    if string.find(string.lower(tostring(npc.Name or "")), npcTargetLower, 1, true) then
                        local nRoot = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
                        if nRoot and nRoot.CFrame then
                            foundNpcCFrame = nRoot.CFrame
                            break
                        end
                    end
                end
            end
            if foundNpcCFrame then break end
        end
    end

    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawnsFolder = origin and origin:FindFirstChild("EnemySpawns")
    if spawnsFolder then
        for _, sp in ipairs(spawnsFolder:GetChildren()) do
            if sp:IsA("BasePart") and isMobMatchingList(sp.Name, monList) then
                table.insert(foundMobCFrames, sp.CFrame)
            end
        end
    end

    local enemies = workspace:FindFirstChild("Enemies")
    if enemies and #foundMobCFrames == 0 then
        for _, mob in ipairs(enemies:GetChildren()) do
            if isMobMatchingList(mob.Name, monList) then
                local mRoot = mob:FindFirstChild("HumanoidRootPart")
                if mRoot and mRoot.CFrame then
                    table.insert(foundMobCFrames, mRoot.CFrame)
                end
            end
        end
    end

    return foundNpcCFrame, foundMobCFrames
end

local function getQuestForPlayer()
    local level = 1
    pcall(function()
        level = LocalPlayer.Data.Level.Value
    end)

    local list = QuestList[CurrentSea] or QuestList[1]
    local matchedIdx = #list
    for i, q in ipairs(list) do
        if level >= q.Min and level <= q.Max then
            matchedIdx = i
            break
        end
    end

    local idx = matchedIdx
    while idx >= 1 do
        local candidate = list[idx]
        local dynNpcCF, dynMobCFs = findDynamicQuestLocations(candidate)
        if not candidate.RequirePresence or dynNpcCF ~= nil or #dynMobCFs > 0 then
            local resolved = {
                Min = candidate.Min,
                Max = candidate.Max,
                Mon = candidate.Mon,
                AltMons = candidate.AltMons,
                QName = candidate.QName,
                QId = candidate.QId,
                NPCName = candidate.NPCName,
                QPos = dynNpcCF or candidate.QPos,
                MPos = (#dynMobCFs > 0) and dynMobCFs or candidate.MPos
            }
            return resolved, level
        end
        idx = idx - 1
    end

    return list[1], level
end

local function checkQuestStatus(qInfo)
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local mainGui = pGui and pGui:FindFirstChild("Main")
    local questFrame = mainGui and mainGui:FindFirstChild("Quest")

    if questFrame and questFrame.Visible then
        State.QuestGuiWasVisible = true
        if State.LastAcceptedQuestName and (State.LastAcceptedQuestName ~= qInfo.QName or State.LastAcceptedQuestId ~= qInfo.QId) then
            return true, false
        end
        return true, true
    end

    if State.QuestGuiWasVisible then
        State.QuestGuiWasVisible = false
        State.QuestLatchUntilClock = nil
        return false, true
    end

    if State.QuestLatchUntilClock and os.clock() < State.QuestLatchUntilClock then
        if State.LastAcceptedQuestName == qInfo.QName and State.LastAcceptedQuestId == qInfo.QId then
            return true, true
        end
    end

    return false, true
end

local function getEnemySpawnPoints(mobNamesOrSingle, fallbackCFrameOrList)
    local points = {}
    local filterList = type(mobNamesOrSingle) == "table" and mobNamesOrSingle or { tostring(mobNamesOrSingle) }
    local origin = workspace:FindFirstChild("_WorldOrigin")
    local spawnsFolder = origin and origin:FindFirstChild("EnemySpawns")
    if spawnsFolder then
        for _, sp in ipairs(spawnsFolder:GetChildren()) do
            if sp:IsA("BasePart") and isMobMatchingList(sp.Name, filterList) then
                table.insert(points, sp.CFrame)
            end
        end
    end
    if type(fallbackCFrameOrList) == "table" and fallbackCFrameOrList.Position == nil then
        for _, cf in ipairs(fallbackCFrameOrList) do
            table.insert(points, cf)
        end
    elseif #points == 0 and fallbackCFrameOrList then
        table.insert(points, fallbackCFrameOrList)
    end
    return points
end

local RequiredMaterials = {
    { Name = "Fish Tail",      Required = 20 },
    { Name = "Dragon Scale",   Required = 10 },
    { Name = "Magma Ore",      Required = 20 },
    { Name = "Mystic Droplet", Required = 10 }
}

local FightingStylePipeline = {
    {
        ToolName = "Black Leg",
        AltNames = { "Black Leg", "Dark Step", "Hắc Cước", "Chân Đen", "Bước Chân Đen" },
        BuyArgs = { "BuyBlackLeg" },
        TargetMastery = 400
    },
    {
        ToolName = "Electro",
        AltNames = { "Electro", "Electric", "Điện", "Lôi Quyền", "Điện Quyền" },
        BuyArgs = { "BuyElectro" },
        TargetMastery = 400
    },
    {
        ToolName = "Fishman Karate",
        AltNames = { "Fishman Karate", "Water Kung Fu", "Karate Người Cá", "Kung Fu Nước", "Võ Người Cá" },
        BuyArgs = { "BuyFishmanKarate" },
        TargetMastery = 400
    },
    {
        ToolName = "Dragon Breath",
        AltNames = { "Dragon Breath", "Dragon Claw", "Hơi Thở Rồng", "Long Trảo" },
        BuyFunc = function()
            pcall(function() CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "1") end)
            local ok, r = pcall(function() return CommF_:InvokeServer("BlackbeardReward", "DragonClaw", "2") end)
            return ok and r or nil
        end,
        TargetMastery = 400
    },
    {
        ToolName = "Superhuman",
        AltNames = { "Superhuman", "Siêu Nhân", "Siêu Phàm", "Võ Siêu Nhân" },
        BuyArgs = { "BuySuperhuman" },
        TargetMastery = 400,
        ImpliesV1 = { "Black Leg", "Electro", "Fishman Karate", "Dragon Breath" }
    },
    {
        ToolName = "Death Step",
        AltNames = { "Death Step", "Tử Cước", "Bước Chân Tử Thần", "Bước Chân Chết Chóc", "Quỷ Cước" },
        BuyArgs = { "BuyDeathStep" },
        TargetMastery = 400,
        UnlockQuest = "DeathStepKey",
        ImpliesV1 = { "Black Leg" }
    },
    {
        ToolName = "Sharkman Karate",
        AltNames = { "Sharkman Karate", "Karate Cá Mập", "Karate Người Cá V2", "Người Cá V2", "Võ Người Cá V2", "Cá Mập" },
        BuyArgs = { "BuySharkmanKarate" },
        TargetMastery = 400,
        UnlockQuest = "SharkmanKey",
        ImpliesV1 = { "Fishman Karate" }
    },
    {
        ToolName = "Electric Claw",
        AltNames = { "Electric Claw", "Vuốt Điện", "Điện Trảo", "Móng Vuốt Điện", "Điện V2" },
        BuyArgs = { "BuyElectricClaw" },
        TargetMastery = 400,
        UnlockQuest = "ElectricClawHero",
        ImpliesV1 = { "Electro" }
    },
    {
        ToolName = "Dragon Talon",
        AltNames = { "Dragon Talon", "Vuốt Rồng", "Móng Vuốt Rồng", "Long Trảo V2", "Rồng V2" },
        BuyArgs = { "BuyDragonTalon" },
        TargetMastery = 400,
        UnlockQuest = "DragonTalonEssence",
        ImpliesV1 = { "Dragon Breath" }
    }
}

local KnownMeleeNames = {
    ["Combat"] = true, ["Black Leg"] = true, ["Dark Step"] = true, ["Hắc Cước"] = true, ["Chân Đen"] = true,
    ["Electro"] = true, ["Electric"] = true, ["Điện"] = true, ["Fishman Karate"] = true, ["Water Kung Fu"] = true,
    ["Karate Người Cá"] = true, ["Kung Fu Nước"] = true, ["Dragon Breath"] = true, ["Dragon Claw"] = true,
    ["Hơi Thở Rồng"] = true, ["Superhuman"] = true, ["Siêu Nhân"] = true, ["Death Step"] = true, ["Tử Cước"] = true,
    ["Bước Chân Tử Thần"] = true, ["Sharkman Karate"] = true, ["Karate Cá Mập"] = true, ["Electric Claw"] = true,
    ["Vuốt Điện"] = true, ["Dragon Talon"] = true, ["Vuốt Rồng"] = true, ["Móng Vuốt Rồng"] = true,
    ["Godhuman"] = true, ["Thần Quyền"] = true, ["Sanguine Art"] = true, ["Huyết Quyền"] = true
}

local MaterialVietnameseNames = {
    ["Fish Tail"]            = "Đuôi Cá (Sea 1/3)",
    ["Magma Ore"]            = "Quặng Magma (Sea 1/2)",
    ["Mystic Droplet"]       = "Giọt Nước Bí Ẩn (Sea 2)",
    ["Dragon Scale"]         = "Vảy Rồng (Sea 3)",
    ["Bones"]                = "Xương (Sea 3)",
    ["Ectoplasm"]            = "Linh Hồn Ma (Sea 2)",
    ["Conjured Cocoa"]       = "Ca Cao Phép Thuật (Sea 3)",
    ["Demonic Wisp"]         = "Đốm Lửa Quỷ (Sea 3)",
    ["Mini Tusk"]            = "Ngà Voi Nhỏ (Sea 3)",
    ["Vampire Fang"]         = "Nanh Ma Cà Rồng (Sea 2)",
    ["Radioactive Material"] = "Chất Phóng Xạ (Sea 2)",
    ["Gunpowder"]            = "Thuốc Súng (Sea 3)",
    ["Scrap Metal"]          = "Sắt Vụn (Sea 1/2/3)",
    ["Leather"]              = "Da Thú (Sea 1/2/3)",
    ["Angel Wings"]          = "Cánh Thiên Thần (Sea 1)",
    ["Nightmare Catcher"]    = "Bẫy Ác Mộng (Sea 3)",
    ["Mirror Fractal"]       = "Mảnh Gương / Đảo Bánh (Sea 3)",
    ["Meteorite"]            = "Thiên Thạch (Sea 2)",
    ["Yeti Fur"]             = "Lông Yeti (Sea 1)"
}

local MaterialAliasMap = {
    ["Fish Tail"] = "Fish Tail", ["FishTail"] = "Fish Tail", ["Đuôi Cá"] = "Fish Tail", ["Duoi Ca"] = "Fish Tail", ["Đuôi Người Cá"] = "Fish Tail",
    ["Magma Ore"] = "Magma Ore", ["MagmaOre"] = "Magma Ore", ["Quặng Dung Nham"] = "Magma Ore", ["Quặng Magma"] = "Magma Ore", ["Quang Magma"] = "Magma Ore", ["Quang Dung Nham"] = "Magma Ore", ["Đá Dung Nham"] = "Magma Ore",
    ["Mystic Droplet"] = "Mystic Droplet", ["MysticDroplet"] = "Mystic Droplet", ["Giọt Nước Huyền Bí"] = "Mystic Droplet", ["Giot Nuoc Huyen Bi"] = "Mystic Droplet", ["Giọt Nước Bí Ẩn"] = "Mystic Droplet",
    ["Dragon Scale"] = "Dragon Scale", ["DragonScale"] = "Dragon Scale", ["Vảy Rồng"] = "Dragon Scale", ["Vay Rong"] = "Dragon Scale", ["Vảy Của Rồng"] = "Dragon Scale",
    ["Bones"] = "Bones", ["Bone"] = "Bones", ["Xương"] = "Bones", ["Xuong"] = "Bones",
    ["Ectoplasm"] = "Ectoplasm", ["Chất Nguyên Sinh"] = "Ectoplasm", ["Chat Nguyen Sinh"] = "Ectoplasm", ["Linh Hồn Ma"] = "Ectoplasm", ["Ngoại Chất"] = "Ectoplasm",
    ["Conjured Cocoa"] = "Conjured Cocoa", ["ConjuredCocoa"] = "Conjured Cocoa", ["Ca Cao Phép Thuật"] = "Conjured Cocoa", ["Ca Cao Huyền Bí"] = "Conjured Cocoa", ["Ca Cao"] = "Conjured Cocoa", ["Cocoa"] = "Conjured Cocoa",
    ["Demonic Wisp"] = "Demonic Wisp", ["DemonicWisp"] = "Demonic Wisp", ["Đốm Lửa Quỷ"] = "Demonic Wisp", ["Dom Lua Quy"] = "Demonic Wisp", ["Linh Hồn Quỷ"] = "Demonic Wisp", ["Ma Trơi Quỷ"] = "Demonic Wisp",
    ["Mini Tusk"] = "Mini Tusk", ["MiniTusk"] = "Mini Tusk", ["Ngà Voi Nhỏ"] = "Mini Tusk", ["Nga Voi Nho"] = "Mini Tusk", ["Ngà Mini"] = "Mini Tusk", ["Ngà Nhỏ"] = "Mini Tusk",
    ["Vampire Fang"] = "Vampire Fang", ["VampireFang"] = "Vampire Fang", ["Nanh Ma Cà Rồng"] = "Vampire Fang", ["Nanh Ma Ca Rong"] = "Vampire Fang", ["Răng Ma Cà Rồng"] = "Vampire Fang",
    ["Radioactive Material"] = "Radioactive Material", ["RadioactiveMaterial"] = "Radioactive Material", ["Chất Phóng Xạ"] = "Radioactive Material", ["Chat Phong Xa"] = "Radioactive Material", ["Nguyên Liệu Phóng Xạ"] = "Radioactive Material", ["Phóng Xạ"] = "Radioactive Material",
    ["Gunpowder"] = "Gunpowder", ["Gun Powder"] = "Gunpowder", ["Thuốc Súng"] = "Gunpowder", ["Thuoc Sung"] = "Gunpowder", ["Bột Thuốc Súng"] = "Gunpowder",
    ["Scrap Metal"] = "Scrap Metal", ["ScrapMetal"] = "Scrap Metal", ["Sắt Vụn"] = "Scrap Metal", ["Sat Vun"] = "Scrap Metal", ["Kim Loại Vụn"] = "Scrap Metal", ["Phế Liệu"] = "Scrap Metal",
    ["Leather"] = "Leather", ["Da Thú"] = "Leather", ["Da Thu"] = "Leather", ["Da Thuộc"] = "Leather", ["Miếng Da"] = "Leather",
    ["Angel Wings"] = "Angel Wings", ["AngelWings"] = "Angel Wings", ["Cánh Thiên Thần"] = "Angel Wings", ["Canh Thien Than"] = "Angel Wings", ["Lông Vũ Thiên Thần"] = "Angel Wings",
    ["Nightmare Catcher"] = "Nightmare Catcher", ["NightmareCatcher"] = "Nightmare Catcher", ["Bẫy Ác Mộng"] = "Nightmare Catcher", ["Bay Ac Mong"] = "Nightmare Catcher", ["Lưới Bắt Ác Mộng"] = "Nightmare Catcher",
    ["Mirror Fractal"] = "Mirror Fractal", ["MirrorFractal"] = "Mirror Fractal", ["Mảnh Gương"] = "Mirror Fractal", ["Manh Guong"] = "Mirror Fractal", ["Mảnh Vỡ Gương"] = "Mirror Fractal",
    ["Meteorite"] = "Meteorite", ["Thiên Thạch"] = "Meteorite", ["Thien Thach"] = "Meteorite", ["Đá Thiên Thạch"] = "Meteorite",
    ["Yeti Fur"] = "Yeti Fur", ["YetiFur"] = "Yeti Fur", ["Lông Yeti"] = "Yeti Fur", ["Long Yeti"] = "Yeti Fur", ["Lông Người Tuyết"] = "Yeti Fur",
    ["Dark Fragment"] = "Dark Fragment", ["DarkFragment"] = "Dark Fragment", ["Mảnh Bóng Tối"] = "Dark Fragment", ["Manh Bong Toi"] = "Dark Fragment", ["Mảnh Tối"] = "Dark Fragment",
    ["Fire Essence"] = "Fire Essence", ["FireEssence"] = "Fire Essence", ["Tinh Hoa Lửa"] = "Fire Essence", ["Lửa Tinh Hoa"] = "Fire Essence", ["Tinh Chất Lửa"] = "Fire Essence",
    ["Library Key"] = "Library Key", ["Chìa Khóa Thư Viện"] = "Library Key", ["Chia Khoa Thu Vien"] = "Library Key",
    ["Water Key"] = "Water Key", ["Chìa Khóa Nước"] = "Water Key", ["Chia Khoa Nuoc"] = "Water Key"
}

local function resolveCanonicalMaterialName(rawName)
    if not rawName then return nil end
    if State.InventoryCounts[rawName] ~= nil then return rawName end
    if MaterialAliasMap[rawName] then return MaterialAliasMap[rawName] end
    local lower = string.lower(tostring(rawName))
    for alias, canonical in pairs(MaterialAliasMap) do
        if string.find(lower, string.lower(alias), 1, true) then
            return canonical
        end
    end
    return nil
end

local function extractItemNameAndCount(item)
    if type(item) ~= "table" then return nil, nil end
    local d = type(item.details) == "table" and item.details or nil
    local rawName = (d and (d.Name or d.name or d.DisplayName))
        or item.Name or item.name or item.DisplayName
    if not rawName then return nil, nil end

    local rawCount = (d and (d.Count or d.count or d.Value or d.value or d.Amount or d.amount or d.Quantity))
        or item.Count or item.count or item.Value or item.value or item.Amount or item.amount or item.Quantity
    local count = tonumber(rawCount)
    if count == nil then
        count = 1
    end
    return rawName, count
end

local function applySingleItemUpdate(item, targetTable)
    local rawName, count = extractItemNameAndCount(item)
    if not rawName then return false end
    local canonical = resolveCanonicalMaterialName(rawName)
    local tbl = targetTable or State.InventoryCounts
    if canonical and tbl[canonical] ~= nil then
        tbl[canonical] = count
        return true
    end
    return false
end

pcall(function()
    local commE = Remotes:FindFirstChild("CommE") or (ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommE"))
    if commE and commE.OnClientEvent then
        table.insert(State.Connections, commE.OnClientEvent:Connect(function(method, arg1, arg2)
            if method == "ItemChanged" or type(method) == "table" then
                local payload = (type(method) == "table") and method or arg1
                if applySingleItemUpdate(payload, State.InventoryCounts) then
                    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
                elseif type(arg1) == "string" and tonumber(arg2) then
                    local canonical = resolveCanonicalMaterialName(arg1)
                    if canonical and State.InventoryCounts[canonical] ~= nil then
                        State.InventoryCounts[canonical] = tonumber(arg2)
                        if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
                    end
                end
            end
        end))
    end
end)

local function readFromUIControllerInventory(targetTable)
    local foundAny = false
    pcall(function()
        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        local mainGui = pGui and pGui:FindFirstChild("Main")
        local uiCtrl = mainGui and mainGui:FindFirstChild("UIController")
        local invScript = uiCtrl and uiCtrl:FindFirstChild("Inventory")
        local getUpval = (debug and debug.getupvalue) or getupvalue
        if invScript and getUpval then
            local ok, invMod = pcall(require, invScript)
            if ok and type(invMod) == "table" and type(invMod.UpdateSort) == "function" then
                for idx = 1, 8 do
                    local uOk, upval = pcall(getUpval, invMod.UpdateSort, idx)
                    if uOk and type(upval) == "table" then
                        for _, item in pairs(upval) do
                            if applySingleItemUpdate(item, targetTable) then
                                foundAny = true
                            end
                        end
                    end
                end
            end
        end
    end)
    return foundAny
end

local function refreshInventoryCounts(forceNetwork)
    local now = os.clock()
    if forceNetwork or not State.LastInventoryFetchClock or (now - State.LastInventoryFetchClock) >= 1.0 then
        State.LastInventoryFetchClock = now
        local ok, inv = pcall(function()
            return CommF_:InvokeServer("getInventory")
        end)
        if not ok then Util.logWarn("getInventory", inv) end

        if ok and type(inv) == "table" then
            local freshCounts = {}
            for k in pairs(State.InventoryCounts) do
                freshCounts[k] = 0
            end
            for k, item in pairs(inv) do
                if type(item) == "table" then
                    if not item.Name and not (type(item.details) == "table" and item.details.Name) and type(k) == "string" then
                        item.Name = k
                    end
                    applySingleItemUpdate(item, freshCounts)
                elseif type(k) == "string" and tonumber(item) then
                    local canonical = resolveCanonicalMaterialName(k)
                    if canonical and freshCounts[canonical] ~= nil then
                        freshCounts[canonical] = tonumber(item)
                    end
                end
            end
            for k, v in pairs(freshCounts) do
                State.InventoryCounts[k] = v
            end
        end
    end

    readFromUIControllerInventory(State.InventoryCounts)

    local containers = { LocalPlayer:FindFirstChild("Backpack"), LocalPlayer.Character }
    for _, cont in ipairs(containers) do
        if cont then
            for _, tool in ipairs(cont:GetChildren()) do
                if tool:IsA("Tool") then
                    local canonical = resolveCanonicalMaterialName(tool.Name)
                    if canonical and State.InventoryCounts[canonical] ~= nil then
                        local toolCount = (tool:FindFirstChild("Count") and tonumber(tool.Count.Value)) or 1
                        State.InventoryCounts[canonical] = math.max(State.InventoryCounts[canonical], toolCount)
                    end
                end
            end
        end
    end
end

local function findAnyMeleeToolInPlayer()
    local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }
    for _, cont in ipairs(containers) do
        if cont then
            for _, item in ipairs(cont:GetChildren()) do
                if item:IsA("Tool") then
                    local tip = tostring(item.ToolTip or "")
                    if tip == "Melee" or string.find(tip, "Cận Chiến") or string.find(tip, "Võ") or KnownMeleeNames[item.Name] then
                        return item
                    end
                end
            end
        end
    end
    return nil
end

local function findStyleToolInPlayer(styleEntry)
    local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }
    for _, cont in ipairs(containers) do
        if cont then
            for _, item in ipairs(cont:GetChildren()) do
                if item:IsA("Tool") then
                    for _, candidateName in ipairs(styleEntry.AltNames) do
                        if item.Name == candidateName or string.find(string.lower(item.Name), string.lower(candidateName), 1, true) then
                            return item
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function recordStyleMastery(styleEntry, lvl)
    State.OwnedStyles = State.OwnedStyles or {}
    State.OwnedStyles[styleEntry.ToolName] = true
    local changed = (State.MasteryCache[styleEntry.ToolName] ~= lvl)
    State.MasteryCache[styleEntry.ToolName] = lvl

    if styleEntry.ImpliesV1 then
        for _, v1Name in ipairs(styleEntry.ImpliesV1) do
            State.OwnedStyles[v1Name] = true
            if (State.MasteryCache[v1Name] or 0) < 400 then
                State.MasteryCache[v1Name] = 400
                changed = true
            end
        end
    end

    local persisted = {}
    for k, v in pairs(State.MasteryCache) do
        if type(v) == "number" and v >= 400 then
            persisted[k] = v
        end
    end
    Config.MasteryCache = persisted
    if changed then
        saveConfig()
    end
end

local function updateMasteryFromEquipped()
    local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChild("Backpack") }
    for _, cont in ipairs(containers) do
        if cont then
            for _, item in ipairs(cont:GetChildren()) do
                if item:IsA("Tool") and item:FindFirstChild("Level") then
                    local lvl = tonumber(item.Level.Value) or 0
                    State.MasteryCache[item.Name] = lvl
                    for _, entry in ipairs(FightingStylePipeline) do
                        for _, alt in ipairs(entry.AltNames) do
                            if item.Name == alt or string.find(string.lower(item.Name), string.lower(alt), 1, true) then
                                recordStyleMastery(entry, lvl)
                            end
                        end
                    end
                    if item.Name == "Godhuman" or item.Name == "Thần Quyền" then
                        State.HasGodhuman = true
                    end
                end
            end
        end
    end
end

local function getCachedMastery(styleEntry)
    updateMasteryFromEquipped()
    if State.MasteryCache[styleEntry.ToolName] ~= nil then
        return State.MasteryCache[styleEntry.ToolName]
    end
    for _, name in ipairs(styleEntry.AltNames) do
        if State.MasteryCache[name] ~= nil then
            return State.MasteryCache[name]
        end
    end
    return nil
end

local NonWeaponTools = {
    ["Awakening"] = true, ["Thức Tỉnh"] = true, ["Giác Quan Nhạy Bén"] = true, ["Instinct"] = true,
    ["Library Key"] = true, ["Chìa Khóa Thư Viện"] = true, ["Water Key"] = true, ["Chìa Khóa Nước"] = true,
    ["Fire Essence"] = true, ["Tinh Hoa Lửa"] = true, ["Sweet Chalice"] = true, ["God's Chalice"] = true,
    ["Fist of Darkness"] = true, ["Hallow Essence"] = true, ["Microchip"] = true,
    ["Flower 1"] = true, ["Flower 2"] = true, ["Flower 3"] = true
}

local function isNonWeaponTool(tool)
    if not tool or not tool:IsA("Tool") then return true end
    local tName = tostring(tool.Name or "")
    if NonWeaponTools[tName] then return true end
    return false
end

local function isToolMatchingSpecificStyle(tool, targetStyleName)
    if not tool or not tool:IsA("Tool") or not targetStyleName then return false end
    local name = tostring(tool.Name or "")
    if name == targetStyleName then return true end
    for _, entry in ipairs(FightingStylePipeline) do
        if entry.ToolName == targetStyleName then
            for _, alt in ipairs(entry.AltNames) do
                if name == alt or string.find(string.lower(name), string.lower(alt), 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

local function isToolMatchingType(tool, weaponType)
    if not tool or not tool:IsA("Tool") then return false end
    local tip = tostring(tool.ToolTip or "")
    local name = tostring(tool.Name or "")

    if weaponType and weaponType ~= "Melee" and weaponType ~= "Sword" and weaponType ~= "Blox Fruit" then
        return isToolMatchingSpecificStyle(tool, weaponType)
    end

    if weaponType == "Melee" then
        if tip == "Melee" or string.find(tip, "Cận Chiến") or string.find(tip, "Võ") or KnownMeleeNames[name] then
            return true
        end
        for _, entry in ipairs(FightingStylePipeline) do
            for _, alt in ipairs(entry.AltNames) do
                if string.find(string.lower(name), string.lower(alt), 1, true) then
                    return true
                end
            end
        end
    elseif weaponType == "Sword" then
        if tip == "Sword" or string.find(tip, "Kiếm") then
            return true
        end
    elseif weaponType == "Blox Fruit" then
        if tip == "Blox Fruit" or string.find(tip, "Trái") or string.find(name, "-") then
            return true
        end
    end
    return false
end

local function forceEquipTool(hum, char, item)
    Util.safeCall("forceEquipTool:L1870", function()
        hum:EquipTool(item)
        if item.Parent ~= char then
            item.Parent = char
        end
    end)
end

local function equipWeapon(preferredType)
    local wType = preferredType or Config.SelectWeapon
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not char or not hum or not backpack then return end

    local heldTool = char:FindFirstChildOfClass("Tool")
    if heldTool and isToolMatchingType(heldTool, wType) then
        return
    end

    if wType ~= "Melee" and wType ~= "Sword" and wType ~= "Blox Fruit" then
        for _, item in ipairs(backpack:GetChildren()) do
            if isToolMatchingSpecificStyle(item, wType) then
                forceEquipTool(hum, char, item)
                return
            end
        end
        if heldTool and isToolMatchingType(heldTool, "Melee") then
            return
        end
        for _, item in ipairs(backpack:GetChildren()) do
            if isToolMatchingType(item, "Melee") then
                forceEquipTool(hum, char, item)
                return
            end
        end
    end

    local fallbackTool = nil
    for _, item in ipairs(backpack:GetChildren()) do
        if item:IsA("Tool") and not NonWeaponTools[tostring(item.Name or "")] and tostring(item.Name or "") ~= "Awakening" and tostring(item.Name or "") ~= "Thức Tỉnh" then
            if not fallbackTool then fallbackTool = item end
            if isToolMatchingType(item, wType) then
                forceEquipTool(hum, char, item)
                return
            end
        end
    end

    if not heldTool and fallbackTool then
        forceEquipTool(hum, char, fallbackTool)
    end
end

local function enableBusoHaki()
    if not Config.AutoBuso then return end
    local char = LocalPlayer.Character
    if char and not char:FindFirstChild("HasBuso") then
        pcall(function() CommF_:InvokeServer("Buso") end)
    end
end

local function executeRaceAbilities()
    if State.IsHopping then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    if Config.AutoRaceV3 and (os.clock() - (State.LastRaceV3Clock or 0)) >= 0.8 then
        State.LastRaceV3Clock = os.clock()
        Util.safeCall("executeRaceAbilities:L1946", function()
            local commE = Remotes:FindFirstChild("CommE") or (ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommE"))
            if commE then
                commE:FireServer("ActivateAbility")
            end
        end)
    end

    if (Config.AutoRaceV4 or Config.AutoTrainRaceV4) and (os.clock() - (State.LastRaceV4Clock or 0)) >= 0.35 then
        State.LastRaceV4Clock = os.clock()
        Util.safeCall("executeRaceAbilities:L1957", function()
            local raceTransformed = char:FindFirstChild("RaceTransformed")
            local raceEnergy = char:FindFirstChild("RaceEnergy")
            local isTransformed = raceTransformed and raceTransformed.Value == true
            local isEnergyFull = (not raceEnergy) or (tonumber(raceEnergy.Value) and tonumber(raceEnergy.Value) >= 1)

            if isEnergyFull and not isTransformed then
                local backpack = LocalPlayer:FindFirstChild("Backpack")
                local awkTool = (backpack and (backpack:FindFirstChild("Awakening") or backpack:FindFirstChild("Thức Tỉnh")))
                    or char:FindFirstChild("Awakening") or char:FindFirstChild("Thức Tỉnh")
                local awkRemote = awkTool and awkTool:FindFirstChild("RemoteFunction")
                if not awkRemote then
                    for _, cont in ipairs({ backpack, char }) do
                        if cont then
                            for _, item in ipairs(cont:GetChildren()) do
                                if item:IsA("Tool") and item:FindFirstChild("RemoteFunction") then
                                    awkRemote = item:FindFirstChild("RemoteFunction")
                                    break
                                end
                            end
                        end
                        if awkRemote then break end
                    end
                end
                if awkRemote then
                    awkRemote:InvokeServer(true)
                end
            end
        end)
    end
end

Util.spawnTracked("RaceAbilitiesLoop", function()
    while State.Running do
        task.wait(0.35)
        if not State.Running then break end
        if Config.AutoRaceV3 or Config.AutoRaceV4 then
            Util.safeCall("executeRaceAbilities", executeRaceAbilities)
        end
    end
end)

local BossKeywords = {
    "boss", "trùm", "cake prince", "dough king", "katakuri", "hoàng tử bột", "hoàng tử bánh",
    "vua bột", "cake queen", "nữ hoàng bánh", "island empress", "ice admiral", "tide keeper",
    "fajita", "orbitus", "yeti", "darkbeard", "soul reaper", "cursed captain"
}

local function isBossMob(mob)
    if not mob then return false end
    local lowerName = string.lower(tostring(mob.Name or ""))
    for _, kw in ipairs(BossKeywords) do
        if string.find(lowerName, kw, 1, true) then
            return true
        end
    end
    local mHum = mob:FindFirstChildOfClass("Humanoid")
    if mHum and mHum.MaxHealth and mHum.MaxHealth >= 500000 then
        return true
    end
    return false
end

do
    local BRING_SIZE = Vector3.new(60, 60, 60)
    local PLATFORM_STANDING = 14
    local bringElapsed = 0

    local function bringSingleMob(mRoot, mHum, posMon)
        if (mRoot.Position - posMon.Position).Magnitude > 0.75 then
            mRoot.CFrame = posMon
        end
        if mRoot.CanCollide then mRoot.CanCollide = false end
        if mRoot.Size ~= BRING_SIZE then mRoot.Size = BRING_SIZE end
        if mRoot.Transparency ~= 0.85 then mRoot.Transparency = 0.85 end
        if mRoot.AssemblyLinearVelocity.Magnitude > 0.1 then mRoot.AssemblyLinearVelocity = Vector3.zero end
        if mRoot.AssemblyAngularVelocity.Magnitude > 0.1 then mRoot.AssemblyAngularVelocity = Vector3.zero end
        if mHum.WalkSpeed ~= 0 then mHum.WalkSpeed = 0 end
        if mHum.JumpPower ~= 0 then mHum.JumpPower = 0 end
        local stOk, curState = pcall(mHum.GetState, mHum)
        if not stOk or (type(curState) == "table" and curState.Value ~= PLATFORM_STANDING) or (typeof and typeof(curState) == "EnumItem" and curState.Value ~= PLATFORM_STANDING) then
            pcall(mHum.ChangeState, mHum, PLATFORM_STANDING)
        end
        local animator = mHum:FindFirstChild("Animator")
        if animator then animator:Destroy() end
    end

    table.insert(State.Connections, RunService.Heartbeat:Connect(function(dt)
        if not State.Running then return end

        bringElapsed = bringElapsed + (dt or 0)
        local interval = math.clamp(tonumber(Config.BringInterval) or 0.12, 0.05, 0.5)
        if bringElapsed < interval then return end
        bringElapsed = 0

        if State.IsHopping or State.IsHoveringV4Sky or not isAnyAutomationActive() or not Config.BringMob or not State.PosMon then
            return
        end

        local posMon = State.PosMon
        if sethiddenproperty and (os.clock() - (State.LastSimRadiusClock or 0)) >= 1.5 then
            State.LastSimRadiusClock = os.clock()
            Util.safeCall("BringMob.SimulationRadius", sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge)
        end

        local enemies = workspace:FindFirstChild("Enemies")
        if not enemies then return end

        local radius = Config.BringRadius
        local filter = State.CurrentMonFilter
        for _, mob in ipairs(enemies:GetChildren()) do
            local mRoot = mob:FindFirstChild("HumanoidRootPart")
            local mHum = mRoot and mob:FindFirstChildOfClass("Humanoid")
            if mRoot and mHum and mHum.Health > 0
                and (mRoot.Position - posMon.Position).Magnitude <= radius
                and not isBossMob(mob)
                and (not filter or isMobMatchingList(mob.Name, filter)) then
                local ok, err = pcall(bringSingleMob, mRoot, mHum, posMon)
                if not ok then Util.logWarn("BringMob", err) end
            end
        end
    end))
end

local NetRegisterAttack, NetRegisterHit = nil, nil
local CameraShakerStopped = false

local function stopCameraShakeOnce()
    if CameraShakerStopped then return end
    CameraShakerStopped = true
    Util.safeCall("stopCameraShakeOnce:L2097", function()
        local util = ReplicatedStorage:FindFirstChild("Util")
        local shaker = util and util:FindFirstChild("CameraShaker")
        if shaker then
            local mod = require(shaker)
            if mod and mod.Stop then mod:Stop() end
        end
    end)
end

local function resolveNetRemotes()
    Util.safeCall("resolveNetRemotes:L2108", function()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local net = modules and modules:FindFirstChild("Net")
        if net then
            NetRegisterAttack = net:FindFirstChild("RE/RegisterAttack")
            NetRegisterHit = net:FindFirstChild("RE/RegisterHit")
        end
        if not NetRegisterAttack then
            for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
                if desc.Name == "RE/RegisterAttack" then
                    NetRegisterAttack = desc
                elseif desc.Name == "RE/RegisterHit" then
                    NetRegisterHit = desc
                end
            end
        end
    end)
end
resolveNetRemotes()
stopCameraShakeOnce()

local FastAttackModes = {
    ["SuperFast"]  = { Delay = 0.035, Bursts = 2, Jitter = 0.006, Label = "Siêu Nhanh X2 (Khuyên Dùng)" },
    ["HyperBurst"] = { Delay = 0.025, Bursts = 3, Jitter = 0.004, Label = "Cực Nhanh X3 (Săn Boss)" },
    ["SafeHuman"]  = { Delay = 0.060, Bursts = 1, Jitter = 0.012, Label = "An Toàn (Nhịp Tự Nhiên)" }
}

local function isHoldingValidWeapon(char)
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool or isNonWeaponTool(tool) then return nil end
    return tool
end

local function getActiveCombatController()
    local getUpvalues = (debug and debug.getupvalues) or getupvalues
    if not getUpvalues then return nil end
    if not CachedCombatCtrlTable then
        Util.safeCall("getActiveCombatController:L2147", function()
            local pScripts = LocalPlayer:FindFirstChild("PlayerScripts")
            local cfScript = pScripts and pScripts:FindFirstChild("CombatFramework")
            if cfScript then
                local upvals = getUpvalues(require(cfScript))
                if upvals and upvals[2] then
                    CachedCombatCtrlTable = upvals[2]
                end
            end
        end)
    end
    return CachedCombatCtrlTable and CachedCombatCtrlTable.activeController or nil
end

local function executeFastAttack()
    local gateCfg = FastAttackModes[Config.FastAttackMode] or FastAttackModes["SuperFast"]
    local gateNow = os.clock()
    if (gateNow - (State.LastFastAttackSend or 0)) < ((gateCfg.Delay or 0.035) * 0.8) then return end
    State.LastFastAttackSend = gateNow

    if State.IsHoveringV4Sky then return end
    if State.ActiveMainMode == "BuyGear" then return end
    if State.ActiveMainMode == "TrialV4" and not State.InCombatTrialRoom then return end
    if (Config.AutoTrialRaceV4 or Config.AutoFlyBuyGear) and not State.PosMon and not State.InCombatTrialRoom then return end
    local char = LocalPlayer.Character
    local root, hum = getCharacterRoot()
    local enemies = workspace:FindFirstChild("Enemies")
    if not char or not root or not hum or not enemies then return end

    local heldTool = isHoldingValidWeapon(char)
    if not heldTool then
        equipWeapon(Config.SelectWeapon)
        heldTool = isHoldingValidWeapon(char)
        if not heldTool then return end
    end

    local primaryHead = nil
    local primaryRoot = nil
    local primaryTorso = nil
    local netTargetsHead = {}
    local netTargetsRoot = {}
    local bladeHits = {}
    local seenModels = {}
    local seenRoots = {}
    local targetCount = 0
    local maxTargets = math.max(1, math.floor(tonumber(Config.FastAttackMaxTargets) or 20))

    local function addTargetMob(mob)
        if not mob or not mob.Parent or seenModels[mob] then return end
        if targetCount >= maxTargets then return end
        local mRoot = mob:FindFirstChild("HumanoidRootPart")
        local mHum = mob:FindFirstChildOfClass("Humanoid")
        if not mRoot or not mHum or mHum.Health <= 0 or seenRoots[mRoot] then return end
        local maxReach = (Config.AutoAttackLeviathan or Config.AutoFindLeviathan) and 160 or 75
        if (mRoot.Position - root.Position).Magnitude > maxReach then return end

        seenModels[mob] = true
        seenRoots[mRoot] = true
        targetCount = targetCount + 1
        local mHead = mob:FindFirstChild("Head") or mRoot
        local mTorso = mob:FindFirstChild("UpperTorso") or mob:FindFirstChild("Torso") or mRoot

        if not primaryRoot then
            primaryRoot = mRoot
            primaryHead = mHead
            primaryTorso = mTorso
        end

        table.insert(netTargetsHead, { mob, mHead })
        table.insert(netTargetsRoot, { mob, mRoot })
        table.insert(bladeHits, mRoot)
    end

    local seaBeasts = workspace:FindFirstChild("SeaBeasts")
    if State.LockedMob and (State.LockedMob.Parent == enemies or (seaBeasts and State.LockedMob.Parent == seaBeasts)) then
        addTargetMob(State.LockedMob)
    end

    for _, mob in ipairs(enemies:GetChildren()) do
        addTargetMob(mob)
    end

    if seaBeasts then
        for _, sb in ipairs(seaBeasts:GetChildren()) do
            addTargetMob(sb)
        end
    end

    if not primaryRoot or #netTargetsHead == 0 then return end

    local modeCfg = FastAttackModes[Config.FastAttackMode] or FastAttackModes["SuperFast"]
    local bursts = modeCfg.Bursts or 2

    if not NetRegisterAttack or not NetRegisterHit then resolveNetRemotes() end
    if NetRegisterAttack and NetRegisterHit then
        Util.safeCall("executeFastAttack:L2249", function()
            NetRegisterAttack:FireServer(0)
            NetRegisterHit:FireServer(primaryHead or primaryRoot, netTargetsHead)
            if bursts >= 2 then
                NetRegisterHit:FireServer(primaryRoot, netTargetsRoot)
            end
            if bursts >= 3 then
                NetRegisterAttack:FireServer(0)
                NetRegisterHit:FireServer(primaryTorso or primaryHead or primaryRoot, netTargetsHead)
            end
        end)
    end

    Util.safeCall("executeFastAttack:L2264", function()
        local ctrl = getActiveCombatController()
        if ctrl then
            ctrl.timeToNextAttack = 0
            ctrl.timeToNextBlock = 0
            ctrl.attacking = false
            ctrl.blocking = false
            ctrl.focusStart = 0
            ctrl.hitboxMagnitude = 65
            ctrl.increment = (bursts >= 2) and 4 or 3
            if ctrl.humanoid then
                ctrl.humanoid.AutoRotate = true
            end
            local rigEvent = ReplicatedStorage:FindFirstChild("RigControllerEvent")
            if rigEvent and heldTool and #bladeHits > 0 then
                rigEvent:FireServer("weaponChange", tostring(heldTool.Name))
                rigEvent:FireServer("hit", bladeHits, 1, "")
                if bursts >= 2 then
                    rigEvent:FireServer("hit", bladeHits, 2, "")
                end
            end
            if ctrl.attack then pcall(function() ctrl:attack() end) end
        end
    end)

    Util.safeCall("executeFastAttack:L2290", function()
        if heldTool then heldTool:Activate() end
    end)

    Util.safeCall("executeFastAttack:L2294", function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(Vector2.new(600, 400))
    end)
end

Util.spawnTracked("FastAttackLoop", function()
    while State.Running do
        local modeCfg = FastAttackModes[Config.FastAttackMode] or FastAttackModes["SuperFast"]
        local baseDelay = modeCfg.Delay or Config.FastAttackDelay or 0.035
        local jitter = (math.random(0, 100) / 100) * (modeCfg.Jitter or 0.005)
        task.wait(baseDelay + jitter)
        if not State.Running then break end
        if not State.IsHopping and isAnyAutomationActive() and Config.FastAttack then
            Util.safeCall("executeFastAttack", executeFastAttack)
        end
    end
end)

local MaterialSpots = {
    ["Fish Tail"] = {
        PreferredSea = 1,
        SpotsBySea = {
            [1] = {
                Mobs = { "Fishman Warrior", "Fishman Commando" },
                WaitCFrame = { CFrame.new(60878, 50, 1543), CFrame.new(61922, 50, 1493) },
                EntranceVec = Vector3.new(61163.8515625, 11.6796875, 1819.7841796875),
                EntranceDist = 4000
            },
            [3] = {
                Mobs = { "Fishman Raider", "Fishman Captain" },
                WaitCFrame = { CFrame.new(-10407, 331, -8368), CFrame.new(-10994, 352, -9002) }
            }
        }
    },
    ["Magma Ore"] = {
        PreferredSea = 2,
        SpotsBySea = {
            [2] = {
                Mobs = { "Magma Ninja", "Lava Pirate" },
                WaitCFrame = { CFrame.new(-5449, 76, -5808), CFrame.new(-5213, 49, -4701) }
            },
            [1] = {
                Mobs = { "Military Soldier", "Military Spy" },
                WaitCFrame = { CFrame.new(-5369, 61, 8556), CFrame.new(-5787, 75, 8651) }
            }
        }
    },
    ["Mystic Droplet"] = {
        PreferredSea = 2,
        SpotsBySea = {
            [2] = {
                Mobs = { "Sea Soldier", "Water Fighter" },
                WaitCFrame = { CFrame.new(-3028, 64, -9775), CFrame.new(-3352, 285, -10534) }
            }
        }
    },
    ["Dragon Scale"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Dragon Crew Warrior", "Dragon Crew Archer" },
                WaitCFrame = { CFrame.new(6141, 51, -1340), CFrame.new(6616, 378, 446) }
            }
        }
    },
    ["Bones"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" },
                WaitCFrame = {
                    CFrame.new(-9505, 172, 6158),
                    CFrame.new(-8763, 165, 6159),
                    CFrame.new(-10144, 138, 5838),
                    CFrame.new(-9582, 6, 6205)
                }
            }
        }
    },
    ["Ectoplasm"] = {
        PreferredSea = 2,
        SpotsBySea = {
            [2] = {
                Mobs = { "Ship Deckhand", "Ship Engineer", "Ship Steward", "Ship Officer" },
                WaitCFrame = {
                    CFrame.new(1212, 150, 33059),
                    CFrame.new(919, 43, 32779),
                    CFrame.new(919, 129, 33436),
                    CFrame.new(1036, 181, 33315)
                },
                EntranceVec = Vector3.new(923.21252441406, 126.9760055542, 32852.83203125),
                EntranceDist = 3000
            }
        }
    },
    ["Conjured Cocoa"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Cocoa Warrior", "Chocolate Bar Battler" },
                WaitCFrame = { CFrame.new(-21, 80, -12352), CFrame.new(582, 77, -12463) }
            }
        }
    },
    ["Demonic Wisp"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Demonic Soul" },
                WaitCFrame = { CFrame.new(-9505, 172, 6158) }
            }
        }
    },
    ["Mini Tusk"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Mythological Pirate" },
                WaitCFrame = { CFrame.new(-13680, 501, -6991) }
            }
        }
    },
    ["Vampire Fang"] = {
        PreferredSea = 2,
        SpotsBySea = {
            [2] = {
                Mobs = { "Vampire" },
                WaitCFrame = { CFrame.new(-6037, 32, -1340) }
            }
        }
    },
    ["Radioactive Material"] = {
        PreferredSea = 2,
        SpotsBySea = {
            [2] = {
                Mobs = { "Factory Staff" },
                WaitCFrame = { CFrame.new(73, 81, -27) }
            }
        }
    },
    ["Gunpowder"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Pistol Billionaire" },
                WaitCFrame = { CFrame.new(-187, 86, 6013) }
            }
        }
    },
    ["Scrap Metal"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [1] = {
                Mobs = { "Pirate", "Brute", "Gladiator" },
                WaitCFrame = { CFrame.new(-1201, 40, 3857), CFrame.new(-1387, 24, 4100), CFrame.new(-1292, 56, -3339) }
            },
            [2] = {
                Mobs = { "Mercenary", "Marine Captain", "Lab Subordinate" },
                WaitCFrame = { CFrame.new(-1004, 80, 1424), CFrame.new(-1861, 80, -3254), CFrame.new(-5707, 15, -4513) }
            },
            [3] = {
                Mobs = { "Pirate Millionaire", "Pistol Billionaire", "Forest Pirate", "Jungle Pirate" },
                WaitCFrame = { CFrame.new(-245, 47, 5584), CFrame.new(-187, 86, 6013), CFrame.new(-13479, 332, -7769), CFrame.new(-12256, 331, -10485) }
            }
        }
    },
    ["Leather"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [1] = {
                Mobs = { "Pirate", "Brute", "Gladiator" },
                WaitCFrame = { CFrame.new(-1201, 40, 3857), CFrame.new(-1387, 24, 4100), CFrame.new(-1292, 56, -3339) }
            },
            [2] = {
                Mobs = { "Mercenary", "Marine Captain", "Lab Subordinate" },
                WaitCFrame = { CFrame.new(-1004, 80, 1424), CFrame.new(-1861, 80, -3254), CFrame.new(-5707, 15, -4513) }
            },
            [3] = {
                Mobs = { "Pirate Millionaire", "Pistol Billionaire", "Forest Pirate", "Jungle Pirate" },
                WaitCFrame = { CFrame.new(-245, 47, 5584), CFrame.new(-187, 86, 6013), CFrame.new(-13479, 332, -7769), CFrame.new(-12256, 331, -10485) }
            }
        }
    },
    ["Angel Wings"] = {
        PreferredSea = 1,
        SpotsBySea = {
            [1] = {
                Mobs = { "Shanda", "Royal Squad", "Royal Soldier", "God's Guard" },
                WaitCFrame = {
                    CFrame.new(-7678, 5566, -497),
                    CFrame.new(-7654, 5637, -1407),
                    CFrame.new(-7836, 5650, -1750),
                    CFrame.new(-4628, 866, -1931)
                },
                EntranceVec = Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047),
                EntranceDist = 2500
            }
        }
    },
    ["Nightmare Catcher"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Reborn Skeleton", "Living Zombie" },
                WaitCFrame = { CFrame.new(-8763, 165, 6159), CFrame.new(-10144, 138, 5838) }
            }
        }
    },
    ["Mirror Fractal"] = {
        PreferredSea = 3,
        SpotsBySea = {
            [3] = {
                Mobs = { "Cookie Crafter", "Cake Guard", "Baking Staff", "Head Baker" },
                WaitCFrame = {
                    CFrame.new(-2374, 37, -12125),
                    CFrame.new(-1598, 43, -12244),
                    CFrame.new(-1887, 77, -12998),
                    CFrame.new(-2216, 82, -12869)
                },
                AutoCakeSpawner = true
            }
        }
    },
    ["Meteorite"] = {
        PreferredSea = 2,
        SpotsBySea = {
            [2] = {
                Mobs = { "Fajita", "Orbitus" },
                WaitCFrame = { CFrame.new(-2172, 103, -4015) }
            }
        }
    },
    ["Yeti Fur"] = {
        PreferredSea = 1,
        SpotsBySea = {
            [1] = {
                Mobs = { "Yeti" },
                WaitCFrame = { CFrame.new(1218, 138, -1488) }
            }
        }
    }
}

local CakeIslandSpawnHubs = {
    CFrame.new(-2374, 37, -12125),
    CFrame.new(-1598, 43, -12244),
    CFrame.new(-1887, 77, -12998),
    CFrame.new(-2216, 82, -12869)
}
local CakeIslandAllMobs = { "Cookie Crafter", "Cake Guard", "Baking Staff", "Head Baker" }
local CakeIslandBosses  = { "Dough King", "Cake Prince", "Katakuri", "Hoàng Tử Bột", "Hoàng Tử Bánh", "Vua Bột" }
local CakeQueenBosses   = { "Cake Queen", "Nữ Hoàng Bánh", "Island Empress" }

local CocoaIslandSpawnHubs = {
    CFrame.new(-21, 80, -12352),
    CFrame.new(582, 77, -12463),
    CFrame.new(165, 76, -12600),
    CFrame.new(134, 77, -12876)
}
local CocoaIslandAllMobs = { "Cocoa Warrior", "Chocolate Bar Battler", "Sweet Thief", "Candy Rebel" }
local CocoaIslandSkySafeCFrame = CFrame.new(165, 310, -12550)

local MasteryGrindSpots = {
    [1] = { Mobs = { "Galley Pirate", "Galley Captain" }, WaitCFrame = CFrame.new(5551, 78, 3930) },
    [2] = { Mobs = { "Sea Soldier", "Water Fighter" },    WaitCFrame = CFrame.new(-3180, 170, -10150) },
    [3] = { Mobs = CakeIslandAllMobs,                     WaitCFrame = CakeIslandSpawnHubs }
}

local function isMobAlive(mob)
    if not mob or not mob.Parent then return false, nil, nil end
    local mRoot = mob:FindFirstChild("HumanoidRootPart")
    local mHum = mob:FindFirstChildOfClass("Humanoid")
    if not mRoot or not mHum or mHum.Health <= 0 then return false, nil, nil end
    if mRoot.Position.Y < -100 then return false, nil, nil end
    return true, mRoot, mHum
end

local function findBestMob(mobNames, fallbackAreaCFrame, isBossSearch)
    local root = getCharacterRoot()
    local enemies = workspace:FindFirstChild("Enemies")
    local bestMob, bestRoot, bestDist = nil, nil, math.huge

    if enemies then
        for _, mob in ipairs(enemies:GetChildren()) do
            if isMobMatchingList(mob.Name, mobNames) then
                local alive, mRoot = isMobAlive(mob)
                if alive and mRoot then
                    local d = root and (mRoot.Position - root.Position).Magnitude or 0
                    if d < bestDist then
                        bestDist = d
                        bestMob = mob
                        bestRoot = mRoot
                    end
                end
            end
        end

        if not bestMob and fallbackAreaCFrame and not isBossSearch then
            local spots = (type(fallbackAreaCFrame) == "table" and fallbackAreaCFrame.Position == nil) and fallbackAreaCFrame or { fallbackAreaCFrame }
            for _, mob in ipairs(enemies:GetChildren()) do
                local alive, mRoot, mHum = isMobAlive(mob)
                if alive and mRoot and mHum and not isBossMob(mob) then
                    for _, sp in ipairs(spots) do
                        if sp and sp.Position and (mRoot.Position - sp.Position).Magnitude <= 280 then
                            local d = root and (mRoot.Position - root.Position).Magnitude or 0
                            if d < bestDist then
                                bestDist = d
                                bestMob = mob
                                bestRoot = mRoot
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    if bestMob and bestRoot then
        return bestMob, bestRoot, true
    end

    for _, obj in ipairs(ReplicatedStorage:GetChildren()) do
        if obj:IsA("Model") and isMobMatchingList(obj.Name, mobNames) then
            local alive, mRoot = isMobAlive(obj)
            if alive and mRoot and mRoot.Position.Magnitude > 50 then
                local distFromPlayer = root and (mRoot.Position - root.Position).Magnitude or 9999
                if isBossSearch or (not fallbackAreaCFrame and distFromPlayer > 180) then
                    return obj, mRoot, false
                end
            end
        end
    end

    return nil, nil, false
end

local function engageMobGroup(mobNames, waitCFrame, weaponOverride, statusPrefix, allowAutoHopOnEmpty)
    State.CurrentMonFilter = mobNames
    local groupKey = table.concat(mobNames, "|")
    enableBusoHaki()
    executeRaceAbilities()
    equipWeapon(weaponOverride)

    local locked = State.LockedMob
    local alive, lRoot, lHum = isMobAlive(locked)

    if not alive or not isMobMatchingList(locked.Name, mobNames) then
        local mob, mobRoot, inWorkspace = findBestMob(mobNames, waitCFrame)
        if mob and mobRoot then
            State.LastMobSeenClock = os.clock()
            State.ArrivedAtSpawnClock = nil
            if inWorkspace then
                State.LockedMob = mob
                locked = mob
                lRoot = mobRoot
                lHum = mob:FindFirstChildOfClass("Humanoid")
                State.PosMon = toFlatCFrame(mobRoot.CFrame, 0)
                State.PosMonGroupKey = groupKey
            else
                State.LockedMob = nil
                State.PosMon = nil
                if updateStatusUI then
                    updateStatusUI(statusPrefix .. " -> Đang bay tới: " .. mob.Name, Color3.fromRGB(135, 205, 255))
                end
                moveToTarget(toFlatCFrame(mobRoot.CFrame, Config.FarmDistance))
                return
            end
        else
            State.LockedMob = nil
            State.PosMon = nil

            local spawnPoints = getEnemySpawnPoints(mobNames, waitCFrame)
            if State.SpawnPointIndex > #spawnPoints or State.SpawnPointIndex < 1 then
                State.SpawnPointIndex = 1
            end
            local patrolCFrame = spawnPoints[State.SpawnPointIndex] or (type(waitCFrame) == "table" and waitCFrame[1]) or waitCFrame
            local targetFlightCF = toFlatCFrame(patrolCFrame, Config.FarmDistance)
            local root = getCharacterRoot()
            local distToSpawn = root and (root.Position - targetFlightCF.Position).Magnitude or 9999

            if distToSpawn <= 30 then
                if not State.ArrivedAtSpawnClock then
                    State.ArrivedAtSpawnClock = os.clock()
                elseif #spawnPoints > 1 and (os.clock() - State.ArrivedAtSpawnClock) >= 1.8 then
                    State.SpawnPointIndex = (State.SpawnPointIndex % #spawnPoints) + 1
                    State.ArrivedAtSpawnClock = nil
                    patrolCFrame = spawnPoints[State.SpawnPointIndex]
                    targetFlightCF = toFlatCFrame(patrolCFrame, Config.FarmDistance)
                end

                local elapsed = os.clock() - State.LastMobSeenClock
                if allowAutoHopOnEmpty and Config.AutoHopWhenEmpty and elapsed >= Config.EmptyMobTimeout then
                    State.LastMobSeenClock = os.clock()
                    hopToServer("Normal", "Hết quái quá " .. Config.EmptyMobTimeout .. "s")
                    return
                end
            else
                State.ArrivedAtSpawnClock = nil
                State.LastMobSeenClock = os.clock()
            end

            if updateStatusUI then
                updateStatusUI(
                    string.format("%s -> Đang bay tới bãi quái #%d (%dm)", statusPrefix, State.SpawnPointIndex, math.floor(distToSpawn)),
                    Color3.fromRGB(255, 215, 90)
                )
            end
            moveToTarget(targetFlightCF)
            return
        end
    end

    local fightingBoss = isBossMob(locked)
    if lRoot and (fightingBoss or not State.PosMon or State.PosMonGroupKey ~= groupKey or (lRoot.Position - State.PosMon.Position).Magnitude > 16) then
        State.PosMon = toFlatCFrame(lRoot.CFrame, 0)
        State.PosMonGroupKey = groupKey
    end

    if lHum and lRoot then
        local root = getCharacterRoot()
        if root and (root.Position - lRoot.Position).Magnitude <= 65 then
            if State.LastBossHealth ~= lHum.Health then
                State.LastBossHealth = lHum.Health
                State.LastBossDamageClock = os.clock()
            elseif (os.clock() - (State.LastBossDamageClock or 0)) >= 3.5 then
                State.LastBossDamageClock = os.clock()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function() hum:UnequipTools() end)
                    task.wait(0.05)
                    if not State.Running then return end
                    equipWeapon(weaponOverride)
                end
            end
        end
    end

    if State.PosMon then
        State.LastMobSeenClock = os.clock()
        if updateStatusUI then
            updateStatusUI(statusPrefix .. " -> ⚔️ Đang đánh: " .. tostring(locked and locked.Name or mobNames[1]), Color3.fromRGB(110, 255, 155))
        end
        moveToTarget(toFlatCFrame(State.PosMon, Config.FarmDistance))
        local root = getCharacterRoot()
        if root and lRoot and (root.Position - lRoot.Position).Magnitude <= 85 and Config.FastAttack then
            Util.safeCall("executeFastAttack", executeFastAttack)
        end
    end
end

local function executeLevelFarmStep(weaponOverride, customBanner)
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
    local root, hum = getCharacterRoot()
    if not root or not hum then return end

    local qInfo, playerLv = getQuestForPlayer()
    local hasQuest, isQuestValid = checkQuestStatus(qInfo)

    if hasQuest and not isQuestValid then
        stopTween()
        State.PosMon = nil
        State.LockedMob = nil
        State.LastAcceptedQuestName = nil
        State.QuestLatchUntilClock = nil
        State.QuestGuiWasVisible = false
        pcall(function() CommF_:InvokeServer("AbandonQuest") end)
        task.wait(0.3)
        if not State.Running then return end
        return
    end

    if not hasQuest then
        State.PosMon = nil
        State.LockedMob = nil
        local distToNpc = (root.Position - qInfo.QPos.Position).Magnitude
        if updateStatusUI then
            updateStatusUI(string.format("📜 [Lv.%d] Đang bay tới NPC (%dm): %s", playerLv, math.floor(distToNpc), qInfo.Mon), Color3.fromRGB(255, 215, 85))
        end

        moveToTarget(qInfo.QPos)

        if (root.Position - qInfo.QPos.Position).Magnitude <= 20 then
            Util.safeCall("executeLevelFarmStep:L2794", function()
                CommF_:InvokeServer("StartQuest", qInfo.QName, qInfo.QId)
            end)
            State.LastAcceptedQuestName = qInfo.QName
            State.LastAcceptedQuestId = qInfo.QId
            State.QuestLatchUntilClock = os.clock() + 38.0
            State.SpawnPointIndex = 1
            State.ArrivedAtSpawnClock = nil
        else
            return
        end
    end

    local targetMons = qInfo.AltMons or { qInfo.Mon }
    local banner = customBanner or string.format("🔥 [Lv.%d] Farm %s", playerLv, qInfo.Mon)
    engageMobGroup(targetMons, qInfo.MPos, weaponOverride or Config.SelectWeapon, banner, false)
end

local function findCurrentOwnedStyleEntry()
    local fallbackEntry, fallbackTool = nil, nil
    for _, entry in ipairs(FightingStylePipeline) do
        local tool = findStyleToolInPlayer(entry)
        if tool then
            if not fallbackEntry then
                fallbackEntry, fallbackTool = entry, tool
            end
            local mas = getCachedMastery(entry) or 0
            if mas < entry.TargetMastery then
                return entry, tool
            end
        end
    end
    return fallbackEntry, fallbackTool
end

local function tryBuyAndCheckStyle(styleEntry)
    local existing = findStyleToolInPlayer(styleEntry)
    if existing then
        local lvl = (existing:FindFirstChild("Level") and tonumber(existing.Level.Value)) or 400
        recordStyleMastery(styleEntry, lvl)
        return true
    end

    local prevMelee = findAnyMeleeToolInPlayer()
    local prevMeleeName = prevMelee and prevMelee.Name or nil
    local buyResponse = nil

    if updateStatusUI then
        updateStatusUI("🔍 Đang kiểm tra võ: " .. tostring(styleEntry.ToolName) .. "...", Color3.fromRGB(160, 225, 255))
    end

    if styleEntry.BuyFunc then
        buyResponse = styleEntry.BuyFunc()
    elseif styleEntry.BuyArgs then
        local ok, res = pcall(function()
            return CommF_:InvokeServer(unpackFn(styleEntry.BuyArgs))
        end)
        if ok then buyResponse = res end
    end

    for _ = 1, 5 do
        task.wait(0.2)
        if not State.Running then return false end
        local afterBuy = findStyleToolInPlayer(styleEntry)
        if afterBuy then
            local lvl = (afterBuy:FindFirstChild("Level") and tonumber(afterBuy.Level.Value)) or 400
            recordStyleMastery(styleEntry, lvl)
            return true
        end

        local currentMelee = findAnyMeleeToolInPlayer()
        if currentMelee and ((not prevMelee) or currentMelee ~= prevMelee or (prevMeleeName and currentMelee.Name ~= prevMeleeName)) then
            local lvl = (currentMelee:FindFirstChild("Level") and tonumber(currentMelee.Level.Value)) or 400
            recordStyleMastery(styleEntry, lvl)
            return true
        end
    end

    if buyResponse == 1 or buyResponse == true then
        local currentMelee = findStyleToolInPlayer(styleEntry) or findAnyMeleeToolInPlayer()
        local lvl = (currentMelee and currentMelee:FindFirstChild("Level") and tonumber(currentMelee.Level.Value)) or 400
        recordStyleMastery(styleEntry, lvl)
        return true
    end

    return false
end

local function trySummonKataPortal(intervalSec)
    if CurrentSea ~= 3 then return end
    local cooldown = intervalSec or 2.0
    if (os.clock() - (State.LastCakeSpawnerClock or 0)) >= cooldown then
        State.LastCakeSpawnerClock = os.clock()
        Util.safeCall("trySummonKataPortal:L2897", function()
            local r1 = CommF_:InvokeServer("CakePrinceSpawner", true)
            local r2 = CommF_:InvokeServer("CakePrinceSpawner")
            local msg = tostring(r1 or r2 or "")
            local rem = string.match(msg, "(%d+)")
            if rem then
                State.KataRemainingMobs = tonumber(rem)
            end
        end)
    end
end

local function enterMirrorOrFightKataBoss(weaponToUse, bannerText)
    local cakeBoss, bossRoot, bossInWorkspace = findBestMob(CakeIslandBosses, nil, true)
    if not cakeBoss or not bossRoot then
        return false
    end

    local root = getCharacterRoot()
    local distToBoss = root and (root.Position - bossRoot.Position).Magnitude or 9999

    if not bossInWorkspace or State.NeedsMirrorPortalEntry or distToBoss > 420 then
        local mirrorPortal = nil
        Util.safeCall("enterMirrorOrFightKataBoss:L2924", function()
            mirrorPortal = workspace.Map.CakeLoaf.BigMirror.Other
        end)
        if mirrorPortal and mirrorPortal:IsA("BasePart") then
            local distToPortal = root and (root.Position - mirrorPortal.Position).Magnitude or 9999
            if distToPortal <= 20 then
                Util.safeCall("enterMirrorOrFightKataBoss:L2931", function()
                    if firetouchinterest and root then
                        firetouchinterest(root, mirrorPortal, 0)
                        firetouchinterest(root, mirrorPortal, 1)
                    end
                end)
                if not State.PortalTouchedClock then
                    State.PortalTouchedClock = os.clock()
                    moveToTarget(mirrorPortal.CFrame)
                    return true
                elseif (os.clock() - State.PortalTouchedClock) >= 0.3 then
                    State.PortalTouchedClock = nil
                    State.NeedsMirrorPortalEntry = false
                else
                    moveToTarget(mirrorPortal.CFrame)
                    return true
                end
            else
                State.PortalTouchedClock = nil
                State.LockedMob = nil
                State.PosMon = nil
                if updateStatusUI then
                    updateStatusUI("🌀 Đang bay qua Cổng Gương để vào phòng đánh " .. tostring(cakeBoss.Name) .. "!", Color3.fromRGB(255, 195, 90))
                end
                moveToTarget(mirrorPortal.CFrame)
                return true
            end
        else
            State.NeedsMirrorPortalEntry = false
        end
    end

    engageMobGroup(
        CakeIslandBosses,
        CFrame.new(-2077, 252, -12373),
        weaponToUse,
        bannerText or ("👑 Đang đánh Kata (" .. tostring(cakeBoss.Name) .. ")"),
        false
    )
    return true
end

local function farmCakeIslandMastery(styleEntry, currentMas)
    if CurrentSea ~= 3 then
        travelToSea(3)
        return
    end

    trySummonKataPortal(3.5)

    if enterMirrorOrFightKataBoss(styleEntry.ToolName, string.format("👑 Săn Boss Đảo Bánh [%s: %d/%d]", styleEntry.ToolName, currentMas, styleEntry.TargetMastery)) then
        return
    end

    engageMobGroup(
        CakeIslandAllMobs,
        CakeIslandSpawnHubs,
        styleEntry.ToolName,
        string.format("🍰 Đảo Bánh [%s: %d/%d]", styleEntry.ToolName, currentMas, styleEntry.TargetMastery),
        true
    )
end

local function handleSpecialStyleUnlock(styleEntry)
    local uType = styleEntry.UnlockQuest

    if uType == "DeathStepKey" then
        if CurrentSea ~= 2 then travelToSea(2); return end
        refreshInventoryCounts()
        if State.InventoryCounts["Library Key"] > 0 then
            if updateStatusUI then
                updateStatusUI("🔑 Đã có Library Key -> Đang bay tới học Death Step!", Color3.fromRGB(110, 255, 160))
            end
            moveToTarget(CFrame.new(6373, 296, -6839))
            pcall(function() CommF_:InvokeServer("BuyDeathStep") end)
            return
        end
        local boss = findBestMob({ "Awakened Ice Admiral" }, nil, true)
        if boss then
            engageMobGroup({ "Awakened Ice Admiral" }, CFrame.new(5668, 28, -6484), "Melee", "🔑 Săn Awakened Ice Admiral", true)
        else
            hopToServer("Normal", "Tìm Boss Awakened Ice Admiral")
        end

    elseif uType == "SharkmanKey" then
        if CurrentSea ~= 2 then travelToSea(2); return end
        refreshInventoryCounts()
        if State.InventoryCounts["Water Key"] > 0 then
            if updateStatusUI then
                updateStatusUI("🔑 Đã có Water Key -> Học Sharkman Karate!", Color3.fromRGB(110, 255, 160))
            end
            pcall(function() CommF_:InvokeServer("BuySharkmanKarate", true) end)
            pcall(function() CommF_:InvokeServer("BuySharkmanKarate") end)
            return
        end
        local boss = findBestMob({ "Tide Keeper" }, nil, true)
        if boss then
            engageMobGroup({ "Tide Keeper" }, CFrame.new(-3570, 123, -11555), "Melee", "🔑 Săn Tide Keeper", true)
        else
            hopToServer("Normal", "Tìm Boss Tide Keeper")
        end

    elseif uType == "ElectricClawHero" then
        if CurrentSea ~= 3 then travelToSea(3); return end
        local root = getCharacterRoot()
        local heroCF = CFrame.new(-10371, 330, -10131)
        local mansionCF = CFrame.new(-12550, 337, -7480)
        if State.ElectricClawRunningToMansion and (os.clock() - (State.ElectricClawQuestStartClock or 0)) < 28 then
            if updateStatusUI then
                updateStatusUI("⚡ Đang bay tới Mansion hoàn thành nhiệm vụ Electric Claw...", Color3.fromRGB(130, 210, 255))
            end
            moveToTarget(mansionCF)
            if root and (root.Position - mansionCF.Position).Magnitude <= 25 then
                State.ElectricClawRunningToMansion = false
                pcall(function() CommF_:InvokeServer("BuyElectricClaw") end)
            end
            return
        end
        State.ElectricClawRunningToMansion = false
        if updateStatusUI then
            updateStatusUI("⚡ Đang bay làm nhiệm vụ Previous Hero mở Electric Claw...", Color3.fromRGB(130, 210, 255))
        end
        moveToTarget(heroCF)
        if root and (root.Position - heroCF.Position).Magnitude <= 20 then
            pcall(function() CommF_:InvokeServer("BuyElectricClaw", "Start") end)
            State.ElectricClawRunningToMansion = true
            State.ElectricClawQuestStartClock = os.clock()
            moveToTarget(mansionCF)
            pcall(function() CommF_:InvokeServer("BuyElectricClaw") end)
        end

    elseif uType == "DragonTalonEssence" then
        if CurrentSea ~= 3 then travelToSea(3); return end
        refreshInventoryCounts()

        if (os.clock() - (State.LastBonesRollClock or 0)) >= 1.0 then
            State.LastBonesRollClock = os.clock()
            Util.safeCall("handleSpecialStyleUnlock:L3060", function()
                CommF_:InvokeServer("Bones", "Buy", 1, 1)
            end)
        end

        if State.InventoryCounts["Fire Essence"] > 0 or (os.clock() - (State.LastUzothCheckClock or 0)) >= 2.0 then
            State.LastUzothCheckClock = os.clock()
            if State.InventoryCounts["Fire Essence"] > 0 and updateStatusUI then
                updateStatusUI("🔥 Đã có Fire Essence -> Giao cho Uzoth học Dragon Talon!", Color3.fromRGB(110, 255, 160))
            end
            pcall(function() CommF_:InvokeServer("BuyDragonTalon", true) end)
            local ok, res = pcall(function() return CommF_:InvokeServer("BuyDragonTalon") end)
            local boughtTool = findStyleToolInPlayer(styleEntry)
            if boughtTool or (ok and (res == 1 or res == true)) then
                local currentMelee = boughtTool or findAnyMeleeToolInPlayer()
                local lvl = (currentMelee and currentMelee:FindFirstChild("Level") and tonumber(currentMelee.Level.Value)) or 1
                recordStyleMastery(styleEntry, lvl)
                return
            end
        end

        local hauntedHubs = {
            CFrame.new(-9505, 172, 6158),
            CFrame.new(-8763, 165, 6159),
            CFrame.new(-10144, 138, 5838),
            CFrame.new(-9582, 6, 6205)
        }
        engageMobGroup(
            { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" },
            hauntedHubs,
            "Melee",
            string.format("🦴 Cày Xương (%d) & Auto Random Fire Essence", State.InventoryCounts["Bones"] or 0),
            true
        )
    end
end

local function executeGodhumanStep()
    updateMasteryFromEquipped()
    refreshInventoryCounts()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end

    if State.HasGodhuman then
        if Config.AutoFarmLevel then
            executeLevelFarmStep("Melee", "👑 Đã có Godhuman -> Cày Level")
        else
            stopTween()
            State.PosMon = nil
            if updateStatusUI then
                updateStatusUI("🎉 Đã sở hữu võ GODHUMAN thành công!", Color3.fromRGB(100, 255, 140))
            end
        end
        return
    end

    local PriorityCheckIndices = { 9, 8, 7, 6, 5, 4, 3, 2, 1 }
    State.LastUnownedStyleCheck = State.LastUnownedStyleCheck or {}
    State.OwnedStyles = State.OwnedStyles or {}

    local heldEntry = findCurrentOwnedStyleEntry()
    if heldEntry then
        local heldMas = getCachedMastery(heldEntry) or 0
        if heldMas < heldEntry.TargetMastery then
            farmCakeIslandMastery(heldEntry, heldMas)
            return
        end
    end

    for _, idx in ipairs(PriorityCheckIndices) do
        local styleEntry = FightingStylePipeline[idx]
        if styleEntry then
            local cachedMas = getCachedMastery(styleEntry)
            if not cachedMas or cachedMas < styleEntry.TargetMastery then
                local lastFailClock = State.LastUnownedStyleCheck[styleEntry.ToolName]
                local ownedAndEquipped = false

                if State.OwnedStyles[styleEntry.ToolName] or not lastFailClock or (os.clock() - lastFailClock) >= 8.0 then
                    ownedAndEquipped = tryBuyAndCheckStyle(styleEntry)
                    if not ownedAndEquipped then
                        State.LastUnownedStyleCheck[styleEntry.ToolName] = os.clock()
                    end
                else
                    ownedAndEquipped = (findStyleToolInPlayer(styleEntry) ~= nil)
                end

                if ownedAndEquipped then
                    State.LastUnownedStyleCheck[styleEntry.ToolName] = nil
                    local currentMas = getCachedMastery(styleEntry) or 0
                    if currentMas < styleEntry.TargetMastery then
                        farmCakeIslandMastery(styleEntry, currentMas)
                        return
                    end
                elseif not styleEntry.UnlockQuest then
                    State.MasteryCache[styleEntry.ToolName] = 400
                end
            end
        end
    end

    for _, styleEntry in ipairs(FightingStylePipeline) do
        local cachedMas = getCachedMastery(styleEntry)
        if (not cachedMas or cachedMas < styleEntry.TargetMastery) and styleEntry.UnlockQuest then
            handleSpecialStyleUnlock(styleEntry)
            return
        end
    end

    for _, mat in ipairs(RequiredMaterials) do
        local count = State.InventoryCounts[mat.Name] or 0
        if count < mat.Required then
            local matConfig = MaterialSpots[mat.Name]
            if matConfig then
                local targetSea = matConfig.PreferredSea
                local spotInCurrentSea = matConfig.SpotsBySea[CurrentSea]

                if mat.Name == "Fish Tail" and CurrentSea ~= 1 then
                    travelToSea(1)
                    return
                elseif not spotInCurrentSea then
                    travelToSea(targetSea)
                    return
                end

                if spotInCurrentSea.EntranceVec then
                    local root = getCharacterRoot()
                    local minEntranceDist = spotInCurrentSea.EntranceDist or 3000
                    if root and (root.Position - spotInCurrentSea.EntranceVec).Magnitude > minEntranceDist then
                        if (os.clock() - (State.LastEntranceRequestClock or 0)) >= 1.2 then
                            State.LastEntranceRequestClock = os.clock()
                            Util.safeCall("executeGodhumanStep:L3209", function()
                                CommF_:InvokeServer("requestEntrance", spotInCurrentSea.EntranceVec)
                            end)
                            task.wait(0.25)
                            if not State.Running then return end
                        end
                    end
                end

                engageMobGroup(
                    spotInCurrentSea.Mobs,
                    spotInCurrentSea.WaitCFrame,
                    "Melee",
                    string.format("🧪 Farm [%s: %d/%d]", mat.Name, count, mat.Required),
                    true
                )
                return
            end
        end
    end

    if CurrentSea ~= 3 then
        travelToSea(3)
        return
    end

    if updateStatusUI then
        updateStatusUI("⚡ Đang bay tới Ancient Monk mua GODHUMAN!", Color3.fromRGB(255, 220, 80))
    end
    moveToTarget(CFrame.new(-13774, 331, -9915))
    Util.safeCall("executeGodhumanStep:L3239", function()
        local res = CommF_:InvokeServer("BuyGodhuman", true)
        CommF_:InvokeServer("BuyGodhuman")
        if res == 1 then
            State.HasGodhuman = true
        end
    end)
end

local function executeSingleMaterialStep()
    refreshInventoryCounts()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end

    local matName = Config.SelectedMaterial
    local matConfig = MaterialSpots[matName]
    if not matConfig then
        matName = "Fish Tail"
        Config.SelectedMaterial = matName
        matConfig = MaterialSpots[matName]
    end
    if not matConfig then return end

    local spot = matConfig.SpotsBySea[CurrentSea]
    if not spot then
        travelToSea(matConfig.PreferredSea)
        return
    end

    if spot.EntranceVec then
        local root = getCharacterRoot()
        local minEntranceDist = spot.EntranceDist or 3000
        if root and (root.Position - spot.EntranceVec).Magnitude > minEntranceDist then
            if (os.clock() - (State.LastEntranceRequestClock or 0)) >= 1.2 then
                State.LastEntranceRequestClock = os.clock()
                Util.safeCall("executeSingleMaterialStep:L3277", function()
                    CommF_:InvokeServer("requestEntrance", spot.EntranceVec)
                end)
                task.wait(0.25)
                if not State.Running then return end
            end
        end
    end

    if matName == "Bones" and Config.AutoRandomBones and (os.clock() - (State.LastBonesRollClock or 0)) >= 1.0 then
        State.LastBonesRollClock = os.clock()
        Util.safeCall("executeSingleMaterialStep:L3289", function()
            CommF_:InvokeServer("Bones", "Buy", 1, 1)
        end)
    end

    local have = State.InventoryCounts[matName] or 0
    local vnDesc = MaterialVietnameseNames[matName] or matName
    if spot.AutoCakeSpawner then
        trySummonKataPortal(3.5)
        if enterMirrorOrFightKataBoss(Config.SelectWeapon, string.format("👑 Săn Boss [%s: %d]", matName, have)) then
            return
        end
    end

    engageMobGroup(
        spot.Mobs,
        spot.WaitCFrame,
        Config.SelectWeapon,
        string.format("🧪 Farm Lẻ [%s - %s: %d]", matName, vnDesc, have),
        true
    )
end

local function executeKataFarmStep()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
    if CurrentSea ~= 3 then
        travelToSea(3)
        return
    end

    if Config.AutoSummonKata then
        trySummonKataPortal(2.0)
    end

    if enterMirrorOrFightKataBoss(Config.SelectWeapon, "👑 Đang đánh Katakuri (Cake Prince / Dough King)") then
        return
    end

    local queenBoss, queenRoot = findBestMob(CakeQueenBosses, nil, true)
    if queenBoss and queenRoot then
        engageMobGroup(
            CakeQueenBosses,
            CFrame.new(-710, 382, -11150),
            Config.SelectWeapon,
            "👑 Đang đánh Boss Cake Queen",
            false
        )
        return
    end

    local summonStatus = Config.AutoSummonKata and "Auto Triệu Hồi: BẬT" or "Auto Triệu Hồi: TẮT"
    local remSuffix = State.KataRemainingMobs and (" | Còn: " .. tostring(State.KataRemainingMobs)) or ""
    engageMobGroup(
        CakeIslandAllMobs,
        CakeIslandSpawnHubs,
        Config.SelectWeapon,
        string.format("🍰 Farm Quái & Kata [%s%s]", summonStatus, remSuffix),
        true
    )
end

local function executeTrainRaceV4Step()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
    if CurrentSea ~= 3 then
        State.IsHoveringV4Sky = false
        travelToSea(3)
        return
    end

    local char = LocalPlayer.Character
    local root, hum = getCharacterRoot()
    if not char or not root or not hum then return end

    local raceTransformed = char:FindFirstChild("RaceTransformed")
    local raceEnergy = char:FindFirstChild("RaceEnergy")
    local isTransformed = (raceTransformed and raceTransformed.Value == true) or false
    local energyVal = (raceEnergy and tonumber(raceEnergy.Value)) or 0
    local isEnergyFull = (energyVal >= 1)

    if (os.clock() - (State.LastUpgradeRaceClock or 0)) >= 6.0 then
        State.LastUpgradeRaceClock = os.clock()
        Util.safeCall("executeTrainRaceV4Step:L3402", function()
            CommF_:InvokeServer("UpgradeRace", "Buy")
        end)
    end

    if isTransformed or isEnergyFull then
        State.IsHoveringV4Sky = true
        State.LockedMob = nil
        State.PosMon = nil

        if not isTransformed then
            Util.safeCall("executeRaceAbilities", executeRaceAbilities)
            Util.safeCall("executeTrainRaceV4Step:L3417", function()
                local commE = Remotes:FindFirstChild("CommE") or (ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommE"))
                if commE then commE:FireServer("ActivateAbility") end
            end)
        end

        local skyTarget = CFrame.new(CocoaIslandSkySafeCFrame.X, CocoaIslandSkySafeCFrame.Y, CocoaIslandSkySafeCFrame.Z)
        moveToTarget(skyTarget)

        if updateStatusUI then
            local pct = math.floor(math.max(0, math.min(1, energyVal)) * 100)
            if isTransformed then
                updateStatusUI(
                    string.format("🔥 Đang Bật TỘC V4 Trên Không (Nộ: %d%%) — Chờ hết nộ sẽ bay xuống đánh tiếp!", pct),
                    Color3.fromRGB(255, 145, 220)
                )
            else
                updateStatusUI(
                    "⚡ Đã Đủ 100% Nộ -> Đang Kích Hoạt TỘC V4 & Bay Lên Trên!",
                    Color3.fromRGB(255, 225, 90)
                )
            end
        end
        return
    end

    State.IsHoveringV4Sky = false
    local pct = math.floor(math.max(0, math.min(1, energyVal)) * 100)
    engageMobGroup(
        CocoaIslandAllMobs,
        CocoaIslandSpawnHubs,
        Config.SelectWeapon,
        string.format("🍫 Train Tộc V4 Đảo Cacao [Nộ: %d%%]", pct),
        true
    )
end

local GreatTreeTopNpcCFrame   = CFrame.new(2860.95, 2280.42, -7218.52)
local TempleOfTimeEntranceVec = Vector3.new(28286.35546875, 14895.3017578125, 102.62469482421875)
local AncientOneCFrame        = CFrame.new(28973.08, 14891.80, -120.29)

local RaceTrialDoorCFrames = {
    ["Human"]   = CFrame.new(29221.822265625, 14890.9755859375, -205.99114990234375),
    ["Skypiea"] = CFrame.new(28960.158203125, 14919.6240234375, 235.03948974609375),
    ["Angel"]   = CFrame.new(28960.158203125, 14919.6240234375, 235.03948974609375),
    ["Mink"]    = CFrame.new(29012.341796875, 14890.9755859375, -380.1492614746094),
    ["Cyborg"]  = CFrame.new(28502.681640625, 14895.9755859375, -423.7279357910156),
    ["Fishman"] = CFrame.new(28231.17578125, 14890.9755859375, -211.64173889160156),
    ["Shark"]   = CFrame.new(28231.17578125, 14890.9755859375, -211.64173889160156),
    ["Ghoul"]   = CFrame.new(28674.244140625, 14890.6767578125, 445.4310607910156)
}

local function getPlayerRaceName()
    local r = "Human"
    pcall(function()
        r = tostring(LocalPlayer.Data.Race.Value)
    end)
    return r
end

local function getObjectCFrame(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then
        return obj.CFrame
    end
    local root = obj:FindFirstChild("HumanoidRootPart")
        or obj:FindFirstChild("Head")
        or obj:FindFirstChild("RootPart")
        or obj:FindFirstChild("TalkPart")
        or obj.PrimaryPart
    if root and root.CFrame then
        return root.CFrame
    end
    for _, desc in ipairs(obj:GetDescendants()) do
        if desc:IsA("BasePart") and desc.CFrame then
            return desc.CFrame
        end
    end
    local ok, piv = pcall(function() return obj:GetPivot() end)
    if ok and piv and piv.Position then
        return piv
    end
    return nil
end

local function triggerGuiButton(btn)
    if not btn then return end
    pcall(function()
        if getconnections then
            for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated, btn.MouseButton1Down }) do
                if sig then
                    for _, conn in pairs(getconnections(sig)) do
                        if conn.Function then pcall(task.spawn, conn.Function) end
                        if conn.Fire then pcall(conn.Fire, conn) end
                    end
                end
            end
        end
        if firesignal then
            if btn.MouseButton1Click then pcall(firesignal, btn.MouseButton1Click) end
            if btn.Activated then pcall(firesignal, btn.Activated) end
            if btn.MouseButton1Down then pcall(firesignal, btn.MouseButton1Down) end
        end
        if btn.MouseButton1Click and type(btn.MouseButton1Click.Fire) == "function" then
            pcall(function() btn.MouseButton1Click:Fire() end)
        end
    end)
end

local function interactWithNpcOrObject(obj, targetCF)
    pcall(function()
        local root = getCharacterRoot()
        if root and targetCF and (root.Position - targetCF.Position).Magnitude <= 18 and (root.Position - targetCF.Position).Magnitude > 3.0 then
            root.CFrame = CFrame.new(targetCF.Position.X, targetCF.Position.Y, targetCF.Position.Z)
        end

        local function triggerPromptsAndDetectors(container)
            if not container then return end
            if container:IsA("BasePart") and firetouchinterest and root then
                pcall(firetouchinterest, root, container, 0)
                pcall(firetouchinterest, root, container, 1)
            end
            for _, desc in ipairs(container:GetDescendants()) do
                if desc.ClassName == "ProximityPrompt" and fireproximityprompt then
                    pcall(fireproximityprompt, desc)
                elseif desc.ClassName == "ClickDetector" and fireclickdetector then
                    pcall(fireclickdetector, desc)
                elseif desc:IsA("BasePart") and firetouchinterest and root and (desc.Position - root.Position).Magnitude <= 20 then
                    pcall(firetouchinterest, root, desc, 0)
                    pcall(firetouchinterest, root, desc, 1)
                end
            end
        end

        triggerPromptsAndDetectors(obj)

        local npcsFolder = workspace:FindFirstChild("NPCs")
        if npcsFolder and root then
            for _, nearNpc in ipairs(npcsFolder:GetChildren()) do
                local nCF = getObjectCFrame(nearNpc)
                if nCF and (nCF.Position - root.Position).Magnitude <= 30 then
                    triggerPromptsAndDetectors(nearNpc)
                end
            end
        end

        if VirtualUser then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton1(Vector2.new(500, 300))
            end)
        end

        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        if pGui then
            local mainGui = pGui:FindFirstChild("Main")
            local dialogue = mainGui and mainGui:FindFirstChild("Dialogue")
            if dialogue and dialogue.Visible then
                local opt1 = dialogue:FindFirstChild("Option1")
                if opt1 then
                    triggerGuiButton(opt1)
                end
            end
            for _, guiObj in ipairs(pGui:GetDescendants()) do
                if (guiObj.ClassName == "TextButton" or guiObj.ClassName == "ImageButton") and guiObj.Visible then
                    local tLower = string.lower(tostring(guiObj.Text or ""))
                    local nLower = string.lower(tostring(guiObj.Name or ""))
                    if string.find(tLower, "tương tác", 1, true)
                        or string.find(tLower, "interact", 1, true)
                        or nLower == "interact"
                    then
                        triggerGuiButton(guiObj)
                    end
                end
            end
        end
    end)
end

local function findGreatTreeNpcTarget()
    local foundCF, foundObj = nil, nil
    Util.safeCall("findGreatTreeNpcTarget:L3615", function()
        for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), ReplicatedStorage:FindFirstChild("NPCs") }) do
            if folder then
                for _, npc in ipairs(folder:GetChildren()) do
                    local nLower = string.lower(tostring(npc.Name or ""))
                    if nLower == "misc." or nLower == "misc"
                        or string.find(nLower, "mysterious force", 1, true)
                        or string.find(nLower, "mysteriousforce", 1, true)
                        or string.find(nLower, "temple of time", 1, true)
                        or string.find(nLower, "lực lượng bí ẩn", 1, true)
                        or string.find(nLower, "thế lực bí ẩn", 1, true)
                    then
                        local nCF = getObjectCFrame(npc)
                        if nCF and nCF.Position.Y >= 1400 and nCF.Position.Y < 10000 then
                            foundCF = nCF
                            foundObj = npc
                            break
                        end
                    end
                end
                if not foundCF then
                    for _, npc in ipairs(folder:GetChildren()) do
                        local nCF = getObjectCFrame(npc)
                        if nCF and nCF.Position.Y >= 1850 and nCF.Position.Y <= 5000 then
                            foundCF = nCF
                            foundObj = npc
                            break
                        end
                    end
                end
            end
            if foundCF then break end
        end
    end)
    return foundCF or GreatTreeTopNpcCFrame, foundObj
end

local function findGearNpcTarget()
    local gearNpcCF, gearNpcObj = AncientOneCFrame, nil

    Util.safeCall("findGearNpcTarget:L3658", function()
        for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), ReplicatedStorage:FindFirstChild("NPCs") }) do
            if folder then
                for _, npc in ipairs(folder:GetChildren()) do
                    local nLower = string.lower(tostring(npc.Name or ""))
                    local nCF = getObjectCFrame(npc)
                    if nCF and nCF.Position.Y > 12000 then
                        local distToStairs = (nCF.Position - AncientOneCFrame.Position).Magnitude
                        if string.find(nLower, "ancient one", 1, true)
                            or string.find(nLower, "ancientone", 1, true)
                            or string.find(nLower, "red orb", 1, true)
                            or string.find(nLower, "người xưa", 1, true)
                            or distToStairs <= 120
                        then
                            gearNpcCF = nCF
                            gearNpcObj = npc
                            break
                        end
                    end
                end
            end
            if gearNpcObj then break end
        end

        local map = workspace:FindFirstChild("Map")
        local tot = map and (map:FindFirstChild("Temple of Time") or map:FindFirstChild("TempleOfTime"))
        if tot and not gearNpcObj then
            local ao = tot:FindFirstChild("Ancient One") or tot:FindFirstChild("AncientOne") or tot:FindFirstChild("RedOrb") or tot:FindFirstChild("KHÁC") or tot:FindFirstChild("Misc.")
            if ao then
                gearNpcObj = ao
                local aoCF = getObjectCFrame(ao)
                if aoCF then
                    gearNpcCF = aoCF
                end
            end
        end
    end)

    return gearNpcCF, gearNpcObj
end

local function ensureInsideTempleOfTime()
    local root = getCharacterRoot()
    if not root then return false end

    if root.Position.Y >= 3500 or root.Position.X > 10000 then
        State.TeleportingToTempleUntil = nil
        return true
    end

    State.DisableNoClip = false

    local treeNpcCF, treeNpcObj = findGreatTreeNpcTarget()
    local distToTreeNpc = (root.Position - treeNpcCF.Position).Magnitude

    if distToTreeNpc > 15 then
        if updateStatusUI then
            updateStatusUI(
                string.format("🌳 [Bước 1] Đang bay lên NPC Đảo Great Tree (%dm)...", math.floor(distToTreeNpc)),
                Color3.fromRGB(160, 225, 255)
            )
        end
        moveToTarget(treeNpcCF)
        return false
    end

    if updateStatusUI then
        updateStatusUI(
            "🌀 [Bước 2] Đã tới NPC Đảo Great Tree -> Đang tương tác NPC vào Trial Temple...",
            Color3.fromRGB(255, 220, 95)
        )
    end

    stopTween()
    removeAntiFall()
    State.TeleportingToTempleUntil = os.clock() + 0.90

    interactWithNpcOrObject(treeNpcObj, treeNpcCF)

    if (os.clock() - (State.LastTempleEntranceClock or 0)) >= 0.45 then
        State.LastTempleEntranceClock = os.clock()
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Check") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Begin") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Teleport") end)
        pcall(function() CommF_:InvokeServer("RaceV4Progress", "Continue") end)
        pcall(function() CommF_:InvokeServer("requestEntrance", TempleOfTimeEntranceVec) end)
        task.wait(0.2)
        if not State.Running then return end
    end

    root = getCharacterRoot()
    if root and root.Position.Y >= 12000 then
        State.TeleportingToTempleUntil = nil
        return true
    end
    return false
end

local function executeFlyBuyGearStep()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
    if CurrentSea ~= 3 then
        travelToSea(3)
        return
    end

    local root, hum = getCharacterRoot()
    if not root or not hum then return end

    State.LockedMob = nil
    State.PosMon = nil

    if not ensureInsideTempleOfTime() then
        return
    end

    State.DisableNoClip = true
    setCharacterCollision(true)

    root = getCharacterRoot()
    if not root then return end

    local gearNpcCF, gearNpcObj = findGearNpcTarget()
    local safeGearCF = CFrame.new(gearNpcCF.Position.X, math.max(gearNpcCF.Position.Y, 14891.8), gearNpcCF.Position.Z)
    local distToGearNpc = (root.Position - safeGearCF.Position).Magnitude

    moveToTarget(safeGearCF)

    if distToGearNpc > 12 then
        if updateStatusUI then
            updateStatusUI(
                string.format("⚙️ [Bước 3] Đã vào Trial Temple -> Đang bay tới chỗ NPC Mua Gear (Ancient One - %dm)...", math.floor(distToGearNpc)),
                Color3.fromRGB(255, 215, 95)
            )
        end
        return
    end

    interactWithNpcOrObject(gearNpcObj, safeGearCF)

    if (os.clock() - (State.LastUpgradeRaceClock or 0)) >= 1.2 then
        State.LastUpgradeRaceClock = os.clock()
        pcall(function() CommF_:InvokeServer("UpgradeRace", "Check") end)
        pcall(function() CommF_:InvokeServer("UpgradeRace", "Buy") end)
    end

    if updateStatusUI then
        updateStatusUI(
            "⚙️ [Hoàn Tất] Đã đứng vững tại NPC Mua Gear (Ancient One) & Tự động tương tác Mua Gear!",
            Color3.fromRGB(115, 255, 165)
        )
    end
end

local executeAutoTrialRaceV4Step
do
    local function isPositionInTempleHallway(pos)
        return pos.X >= 28050 and pos.X <= 29350
            and pos.Y >= 14850 and pos.Y <= 15060
            and pos.Z >= -500 and pos.Z <= 500
    end

    local function isTrialTimerVisible()
        local visible = false
        Util.safeCall("executeFlyBuyGearStep:L3847", function()
            local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
            local main = pGui and pGui:FindFirstChild("Main")
            local timer = main and main:FindFirstChild("Timer")
            if timer and timer.Visible == true then
                local txt = tostring(timer.Text or "")
                if txt ~= "" and not string.find(txt, "00:00", 1, true) then
                    visible = true
                end
            end
        end)
        return visible
    end

    local function findMinkTrialFinish()
        local finishPart = nil
        Util.safeCall("executeFlyBuyGearStep:L3863", function()
            local map = workspace:FindFirstChild("Map")
            local minkTrial = map and map:FindFirstChild("MinkTrial")
            if minkTrial then
                finishPart = minkTrial:FindFirstChild("Ceiling")
                    or minkTrial:FindFirstChild("FinishPart")
                    or minkTrial:FindFirstChild("EndPoint")
                    or minkTrial:FindFirstChild("Finish")
                if not finishPart then
                    for _, d in ipairs(minkTrial:GetDescendants()) do
                        if d:IsA("BasePart") and (d.Name == "Ceiling" or d.Name == "FinishPart" or d.Name == "EndPoint") then
                            finishPart = d
                            break
                        end
                    end
                end
            end
            if not finishPart then
                local wo = workspace:FindFirstChild("_WorldOrigin")
                local locs = wo and wo:FindFirstChild("Locations")
                local tos = locs and locs:FindFirstChild("Trial of Speed")
                if tos and tos:IsA("BasePart") then
                    finishPart = tos
                end
            end
        end)
        return finishPart
    end

    local function findSkyTrialFinish()
        local finishPart = nil
        Util.safeCall("executeFlyBuyGearStep:L3894", function()
            local map = workspace:FindFirstChild("Map")
            local skyTrial = map and map:FindFirstChild("SkyTrial")
            if skyTrial then
                local model = skyTrial:FindFirstChild("Model")
                finishPart = (model and (model:FindFirstChild("FinishPart") or model:FindFirstChild("Finish")))
                    or skyTrial:FindFirstChild("FinishPart")
                    or skyTrial:FindFirstChild("Finish")
                if not finishPart then
                    for _, d in ipairs(skyTrial:GetDescendants()) do
                        if d:IsA("BasePart") and (d.Name == "FinishPart" or d.Name == "Finish" or d.Name == "EndPart") then
                            finishPart = d
                            break
                        end
                    end
                end
            end
            if not finishPart then
                local wo = workspace:FindFirstChild("_WorldOrigin")
                local locs = wo and wo:FindFirstChild("Locations")
                local tok = locs and (locs:FindFirstChild("Trial of the King") or locs:FindFirstChild("Trial of King"))
                if tok and tok:IsA("BasePart") then
                    finishPart = tok
                end
            end
        end)
        return finishPart
    end

    local function findTrialSeaBeast(rootPos)
        local bestSB, bestRoot = nil, nil
        local bestDist = math.huge
        local function scanFolder(folder)
            if not folder then return end
            for _, obj in ipairs(folder:GetChildren()) do
                local nLower = string.lower(tostring(obj.Name or ""))
                if string.find(nLower, "seabeast", 1, true)
                    or string.find(nLower, "sea beast", 1, true)
                    or string.find(nLower, "vua biển", 1, true)
                    or folder.Name == "SeaBeasts"
                then
                    if not string.find(nLower, "leviathan", 1, true) then
                        local r = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("RootPart") or obj:FindFirstChildWhichIsA("BasePart")
                        local h = obj:FindFirstChildOfClass("Humanoid")
                        local hp = (h and tonumber(h.Health)) or 1000
                        if r and hp > 0 then
                            local d = (r.Position - rootPos).Magnitude
                            if d <= 2500 and d < bestDist then
                                bestDist = d
                                bestSB = obj
                                bestRoot = r
                            end
                        end
                    end
                end
            end
        end
        scanFolder(workspace:FindFirstChild("SeaBeasts"))
        scanFolder(workspace:FindFirstChild("Enemies"))
        return bestSB, bestRoot
    end

    local function findTrialCombatMob(rootPos)
        local enemies = workspace:FindFirstChild("Enemies")
        if not enemies then return nil, nil end
        local bestBoss, bestBossRoot = nil, nil
        local bestBossDist = math.huge
        local bestMob, bestMobRoot = nil, nil
        local bestMobDist = math.huge

        for _, mob in ipairs(enemies:GetChildren()) do
            local mRoot = mob:FindFirstChild("HumanoidRootPart")
            local mHum = mob:FindFirstChildOfClass("Humanoid")
            if mRoot and mHum and mHum.Health > 0 then
                if mRoot.Position.Y >= 3500 or mRoot.Position.X > 10000 then
                    local d = (mRoot.Position - rootPos).Magnitude
                    if d <= 1800 then
                        if isBossMob(mob) then
                            if d < bestBossDist then
                                bestBossDist = d
                                bestBoss = mob
                                bestBossRoot = mRoot
                            end
                        else
                            if d < bestMobDist then
                                bestMobDist = d
                                bestMob = mob
                                bestMobRoot = mRoot
                            end
                        end
                    end
                end
            end
        end

        if bestBoss then return bestBoss, bestBossRoot end
        return bestMob, bestMobRoot
    end

    local function detectActiveTrialRoom(root, raceName)
        local pos = root.Position
        local inSkyOrTempleZone = (pos.Y >= 3500 or pos.X > 10000)

        if isTrialTimerVisible() then
            return true
        end

        local map = workspace:FindFirstChild("Map")
        if raceName == "Mink" then
            local finishPart = findMinkTrialFinish()
            if finishPart then
                return true
            end
        elseif raceName == "Skypiea" then
            local finishPart = findSkyTrialFinish()
            if finishPart then
                return true
            end
        elseif raceName == "Cyborg" then
            if map and map:FindFirstChild("CyborgTrial") then
                return true
            end
        elseif raceName == "Fishman" then
            if (map and map:FindFirstChild("FishmanTrial")) then
                return true
            end
            if inSkyOrTempleZone then
                local sb = findTrialSeaBeast(pos)
                if sb then return true end
            end
        elseif raceName == "Human" or raceName == "Ghoul" then
            if map and (map:FindFirstChild("HumanTrial") or map:FindFirstChild("GhoulTrial")) then
                return true
            end
        end

        if inSkyOrTempleZone and not isPositionInTempleHallway(pos) then
            return true
        end

        return false
    end

    executeAutoTrialRaceV4Step = function()
        if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
        if CurrentSea ~= 3 then
            travelToSea(3)
            return
        end

        local root, hum = getCharacterRoot()
        if not root or not hum then return end

        local raceName = getPlayerRaceName()

        if detectActiveTrialRoom(root, raceName) then
            State.TeleportingToTempleUntil = nil

            if raceName == "Mink" then
                State.InCombatTrialRoom = false
                State.DisableNoClip = false
                State.LockedMob = nil
                State.PosMon = nil
                local finishPart = findMinkTrialFinish()
                if finishPart then
                    local targetCF = getObjectCFrame(finishPart) or finishPart.CFrame
                    local dist = (root.Position - targetCF.Position).Magnitude
                    moveToTarget(targetCF)
                    if dist <= 30 then
                        Util.safeCall("executeFlyBuyGearStep:L4074", function()
                            if firetouchinterest then
                                firetouchinterest(root, finishPart, 0)
                                firetouchinterest(root, finishPart, 1)
                            end
                        end)
                    end
                    if updateStatusUI then
                        updateStatusUI(
                            string.format("⚡ [Trial Mink] Đang bay thẳng tới đích mê cung (%dm) để hoàn thành Trial!", math.floor(dist)),
                            Color3.fromRGB(115, 255, 175)
                        )
                    end
                else
                    moveToTarget(CFrame.new(root.Position.X, math.max(root.Position.Y, 14895), root.Position.Z))
                end
                return

            elseif raceName == "Skypiea" then
                State.InCombatTrialRoom = false
                State.DisableNoClip = false
                State.LockedMob = nil
                State.PosMon = nil
                local finishPart = findSkyTrialFinish()
                if finishPart then
                    local targetCF = getObjectCFrame(finishPart) or finishPart.CFrame
                    local dist = (root.Position - targetCF.Position).Magnitude
                    moveToTarget(targetCF)
                    if dist <= 30 then
                        Util.safeCall("executeFlyBuyGearStep:L4104", function()
                            if firetouchinterest then
                                firetouchinterest(root, finishPart, 0)
                                firetouchinterest(root, finishPart, 1)
                            end
                        end)
                    end
                    if updateStatusUI then
                        updateStatusUI(
                            string.format("☁️ [Trial Angel] Đang bay thẳng tới đám mây đích FinishPart (%dm)!", math.floor(dist)),
                            Color3.fromRGB(115, 255, 175)
                        )
                    end
                else
                    moveToTarget(CFrame.new(root.Position.X, math.max(root.Position.Y, 14920), root.Position.Z))
                end
                return

            elseif raceName == "Cyborg" then
                State.InCombatTrialRoom = false
                State.DisableNoClip = false
                State.LockedMob = nil
                State.PosMon = nil
                local safeSkyCF = CFrame.new(root.Position.X, math.max(root.Position.Y + 60, 15150), root.Position.Z)
                moveToTarget(safeSkyCF)
                if updateStatusUI then
                    updateStatusUI(
                        string.format("🤖 [Trial Cyborg] Đang giữ độ cao an toàn (Y=%d) né tên lửa chờ hết giờ hoàn thành Trial!", math.floor(root.Position.Y)),
                        Color3.fromRGB(115, 255, 175)
                    )
                end
                return

            elseif raceName == "Fishman" then
                State.InCombatTrialRoom = true
                State.DisableNoClip = false
                local sb, sbRoot = findTrialSeaBeast(root.Position)
                if sb and sbRoot then
                    State.LockedMob = sb
                    local sbPos = sbRoot.Position
                    local hoverCF = CFrame.new(sbPos.X, math.max(sbPos.Y + 24, 60), sbPos.Z)
                    State.PosMon = CFrame.new(sbPos.X, sbPos.Y, sbPos.Z)
                    equipWeapon(Config.SelectWeapon)
                    moveToTarget(hoverCF)
                    if (root.Position - sbPos).Magnitude <= 155 and Config.FastAttack then
                        Util.safeCall("executeFastAttack", executeFastAttack)
                    end
                    if updateStatusUI then
                        updateStatusUI(
                            "🦈 [Trial Shark] Đang tấn công SeaBeast trong phòng Trial để hoàn thành thử thách!",
                            Color3.fromRGB(115, 255, 175)
                        )
                    end
                else
                    moveToTarget(CFrame.new(root.Position.X, math.max(root.Position.Y, 14895), root.Position.Z))
                    if updateStatusUI then
                        updateStatusUI("🦈 [Trial Shark] Đang trong phòng Trial chờ SeaBeast xuất hiện...", Color3.fromRGB(165, 225, 255))
                    end
                end
                return

            else
                State.InCombatTrialRoom = true
                State.DisableNoClip = false
                State.CurrentMonFilter = nil
                local mob, mobRoot = findTrialCombatMob(root.Position)
                if mob and mobRoot then
                    State.LockedMob = mob
                    State.PosMon = toFlatCFrame(mobRoot.CFrame, 0)
                    equipWeapon(Config.SelectWeapon)
                    moveToTarget(toFlatCFrame(State.PosMon, Config.FarmDistance))
                    if (root.Position - mobRoot.Position).Magnitude <= 95 and Config.FastAttack then
                        Util.safeCall("executeFastAttack", executeFastAttack)
                    end
                    if updateStatusUI then
                        updateStatusUI(
                            string.format("⚔️ [Trial %s] Đang tiêu diệt %s trong phòng Trial!", raceName, tostring(mob.Name)),
                            Color3.fromRGB(115, 255, 175)
                        )
                    end
                else
                    moveToTarget(CFrame.new(root.Position.X, math.max(root.Position.Y, 14893), root.Position.Z))
                    if updateStatusUI then
                        updateStatusUI(
                            string.format("⚔️ [Trial %s] Đang trong phòng Trial chờ đợt quái / Boss tiếp theo...", raceName),
                            Color3.fromRGB(165, 225, 255)
                        )
                    end
                end
                return
            end
        end

        State.InCombatTrialRoom = false
        State.LockedMob = nil
        State.PosMon = nil

        if not ensureInsideTempleOfTime() then
            return
        end

        State.DisableNoClip = true
        setCharacterCollision(true)

        root = getCharacterRoot()
        if not root then return end

        local rawDoorCF = RaceTrialDoorCFrames[raceName] or RaceTrialDoorCFrames["Human"]
        local doorCF = CFrame.new(rawDoorCF.Position.X, math.max(rawDoorCF.Position.Y, 14891.5), rawDoorCF.Position.Z)
        local distToDoor = (root.Position - doorCF.Position).Magnitude

        moveToTarget(doorCF)

        if distToDoor > 12 then
            if updateStatusUI then
                updateStatusUI(
                    string.format("🚪 [Đã Tắt Xuyên Tường] Đang bay tới Cổng Trial Tộc [%s] (%dm)...", raceName, math.floor(distToDoor)),
                    Color3.fromRGB(165, 225, 255)
                )
            end
            return
        end

        if (os.clock() - (State.LastTrialDoorV3Clock or 0)) >= 1.5 then
            State.LastTrialDoorV3Clock = os.clock()
            Util.safeCall("executeFlyBuyGearStep:L4239", function()
                local commE = Remotes:FindFirstChild("CommE")
                if commE then
                    commE:FireServer("ActivateAbility")
                end
            end)
        end

        if updateStatusUI then
            updateStatusUI(
                string.format("🚪 Đã đứng tại Cổng Trial Tộc [%s] -> Tự bật Tộc V3 mở cửa & Sẵn sàng hoàn thành Trial!", raceName),
                Color3.fromRGB(115, 255, 165)
            )
        end
    end
end

local executeSpoof5PlayersBoatStep, cleanupSpoofedBoatPlayers, executeAttackLeviathanStep, executeFindLeviathanStep
do
local TikiSpyCFrame        = CFrame.new(-16471.4, 528.3, 439.8)
local TikiBoatDealerCFrame = CFrame.new(-16202.0, 9.2, 436.5)
local SeaLevel6Waypoints = {
    CFrame.new(-21500, 26, 4500),
    CFrame.new(-25500, 26, 6500),
    CFrame.new(-29500, 26, 8500),
    CFrame.new(-33500, 26, 10500)
}

State.LeviathanSegmentStartHP   = State.LeviathanSegmentStartHP or {}
State.LeviathanSegmentSwitched  = State.LeviathanSegmentSwitched or {}
State.LeviathanCurrentSegment   = nil
State.LeviathanSegmentSwitchLog = State.LeviathanSegmentSwitchLog or {}
State.LeviathanWaypointIdx      = 1
State.FakeBoatPlayers           = State.FakeBoatPlayers or {}
State.SpoofedSeatedCount        = 0

local function findBeastHunterBoat()
    local boatsFolder = workspace:FindFirstChild("Boats")
    if not boatsFolder then return nil end

    local bestBoat = nil
    for _, boat in ipairs(boatsFolder:GetChildren()) do
        local bName = string.lower(tostring(boat.Name or ""))
        if string.find(bName, "beast hunter", 1, true) or string.find(bName, "beasthunter", 1, true) or string.find(bName, "thợ săn quái thú", 1, true) then
            return boat
        end
        if not bestBoat then
            bestBoat = boat
        end
    end
    return bestBoat
end

local function buildSpoofed5PlayerParty()
    local party = { LocalPlayer }
    local seen = { [LocalPlayer] = true }

    Util.safeCall("buildSpoofed5PlayerParty:L4304", function()
        for _, plr in ipairs(Players:GetPlayers()) do
            if not seen[plr] and #party < 5 then
                seen[plr] = true
                table.insert(party, plr)
            end
        end
    end)

    for i = #party + 1, 5 do
        local fakeChar = State.FakeBoatPlayers[i]
        table.insert(party, {
            Name = "MaidHubCrew_" .. tostring(i),
            DisplayName = "MaidHubCrew_" .. tostring(i),
            UserId = (tonumber(LocalPlayer.UserId) or 100000) + i * 137,
            Character = fakeChar,
            ClassName = "Player"
        })
    end
    return party
end

executeSpoof5PlayersBoatStep = function()
    local boat = findBeastHunterBoat()
    if not boat then
        State.SpoofedSeatedCount = 0
        return 0, nil
    end

    local boatCF = getObjectCFrame(boat) or CFrame.new(-16210, 26, 450)
    local seats = {}

    Util.safeCall("executeSpoof5PlayersBoatStep:L4338", function()
        for _, desc in ipairs(boat:GetDescendants()) do
            if desc:IsA("VehicleSeat") or desc:IsA("Seat") or string.find(string.lower(tostring(desc.Name)), "seat", 1, true) then
                if desc:IsA("BasePart") then
                    table.insert(seats, desc)
                end
            end
        end
    end)

    while #seats < 5 do
        local idx = #seats + 1
        local newSeat = Instance.new(idx == 1 and "VehicleSeat" or "Seat")
        newSeat.Name = (idx == 1) and "VehicleSeat" or ("PassengerSeat_" .. tostring(idx - 1))
        newSeat.CFrame = CFrame.new(boatCF.Position.X + (idx - 1) * 4, boatCF.Position.Y + 3, boatCF.Position.Z)
        newSeat.Parent = boat
        table.insert(seats, newSeat)
    end

    local seatedCount = 1
    local char = LocalPlayer.Character
    local myHum = char and char:FindFirstChildOfClass("Humanoid")
    local myRoot = char and char:FindFirstChild("HumanoidRootPart")
    if seats[1] and myHum and myRoot then
        Util.safeCall("executeSpoof5PlayersBoatStep:L4364", function()
            if not seats[1]:FindFirstChild("MaidHubOwnerWeld") then
                local w = Instance.new("Weld")
                w.Name = "MaidHubOwnerWeld"
                w.Part0 = seats[1]
                w.Part1 = myRoot
                w.Parent = seats[1]
            end
        end)
    end

    local charsFolder = workspace:FindFirstChild("Characters") or workspace
    for i = 2, 5 do
        local seat = seats[i]
        if seat then
            local fakeModel = State.FakeBoatPlayers[i]
            if not fakeModel or not fakeModel.Parent then
                fakeModel = Instance.new("Model")
                fakeModel.Name = "MaidHubCrew_" .. tostring(i)

                local fRoot = Instance.new("Part")
                fRoot.Name = "HumanoidRootPart"
                fRoot.Size = Vector3.new(2, 2, 1)
                fRoot.Transparency = 0.65
                fRoot.CanCollide = false
                fRoot.Anchored = false
                fRoot.CFrame = seat.CFrame
                fRoot.Parent = fakeModel

                local fHead = Instance.new("Part")
                fHead.Name = "Head"
                fHead.Size = Vector3.new(1, 1, 1)
                fHead.Transparency = 0.65
                fHead.CanCollide = false
                fHead.CFrame = seat.CFrame
                fHead.Parent = fakeModel

                local fHum = Instance.new("Humanoid")
                fHum.Name = "Humanoid"
                fHum.Health = 14170
                fHum.MaxHealth = 14170
                fHum.Sit = true
                fHum.Parent = fakeModel

                fakeModel.Parent = charsFolder
                State.FakeBoatPlayers[i] = fakeModel
            end

            local fRoot = fakeModel:FindFirstChild("HumanoidRootPart")
            local fHum = fakeModel:FindFirstChildOfClass("Humanoid")
            if fRoot and fHum then
                fRoot.CFrame = seat.CFrame
                fHum.Sit = true
                Util.safeCall("executeSpoof5PlayersBoatStep:L4418", function()
                    if seat.Sit then
                        seat:Sit(fHum)
                    end
                    seat.Occupant = fHum
                end)
                local weld = seat:FindFirstChild("SeatWeld")
                if not weld then
                    weld = Instance.new("Weld")
                    weld.Name = "SeatWeld"
                    weld.Part0 = seat
                    weld.Part1 = fRoot
                    weld.Parent = seat
                end
                seatedCount = seatedCount + 1
            end
        end
    end

    State.SpoofedSeatedCount = seatedCount
    Util.safeCall("executeSpoof5PlayersBoatStep:L4438", function()
        local psVal = boat:FindFirstChild("PlayersSeated")
        if not psVal then
            psVal = Instance.new("IntValue")
            psVal.Name = "PlayersSeated"
            psVal.Parent = boat
        end
        psVal.Value = seatedCount
        if boat.SetAttribute then
            boat:SetAttribute("PlayersSeated", seatedCount)
            boat:SetAttribute("PassengerCount", seatedCount)
            boat:SetAttribute("SeaExplorationGroupSize", seatedCount)
        end
    end)

    return seatedCount, boat
end

cleanupSpoofedBoatPlayers = function()
    for i, fakeModel in pairs(State.FakeBoatPlayers) do
        Util.safeCall("cleanupSpoofedBoatPlayers:L4458", function()
            if fakeModel and fakeModel.Parent then
                fakeModel:Destroy()
            end
        end)
        State.FakeBoatPlayers[i] = nil
    end
    State.SpoofedSeatedCount = 0
end

local function findFrozenDimensionTarget()
    local fdCF, fdObj = nil, nil
    Util.safeCall("findFrozenDimensionTarget:L4471", function()
        local wo = workspace:FindFirstChild("_WorldOrigin")
        local locs = wo and wo:FindFirstChild("Locations")
        if locs then
            local fd = locs:FindFirstChild("Frozen Dimension") or locs:FindFirstChild("FrozenDimension") or locs:FindFirstChild("Chiều Không Gian Đóng Băng")
            if fd then
                fdObj = fd
                fdCF = getObjectCFrame(fd)
            end
        end

        local map = workspace:FindFirstChild("Map")
        if map and not fdCF then
            local gate = map:FindFirstChild("LeviathanGate") or map:FindFirstChild("FrozenDimension") or map:FindFirstChild("Frozen Dimension")
            if gate then
                fdObj = gate
                fdCF = getObjectCFrame(gate)
            end
        end

        for _, folder in ipairs({ workspace:FindFirstChild("NPCs"), ReplicatedStorage:FindFirstChild("NPCs") }) do
            if folder then
                local watcher = folder:FindFirstChild("Frozen Watcher") or folder:FindFirstChild("FrozenWatcher")
                if watcher then
                    fdObj = watcher
                    local wCF = getObjectCFrame(watcher)
                    if wCF then fdCF = wCF end
                    break
                end
            end
        end
    end)
    return fdCF, fdObj
end

local function scanLeviathanEntities()
    local segments = {}
    local mainBoss = nil
    local seen = {}

    local function inspectContainer(container)
        if not container then return end
        for _, obj in ipairs(container:GetChildren()) do
            if not seen[obj] then
                local nameLower = string.lower(tostring(obj.Name or ""))
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local root = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Head") or obj:FindFirstChildWhichIsA("BasePart")
                local curHP = (hum and tonumber(hum.Health)) or (obj.GetAttribute and tonumber(obj:GetAttribute("Health"))) or nil
                local maxHP = (hum and tonumber(hum.MaxHealth)) or (obj.GetAttribute and tonumber(obj:GetAttribute("MaxHealth"))) or curHP

                if root and curHP and curHP > 0 then
                    if string.find(nameLower, "leviathan segment", 1, true)
                        or string.find(nameLower, "leviathansegment", 1, true)
                        or string.find(nameLower, "đoạn leviathan", 1, true)
                        or string.find(nameLower, "đuôi leviathan", 1, true)
                        or (string.find(nameLower, "segment", 1, true) and string.find(nameLower, "leviathan", 1, true))
                    then
                        seen[obj] = true
                        if not State.LeviathanSegmentStartHP[obj] or curHP > State.LeviathanSegmentStartHP[obj] then
                            State.LeviathanSegmentStartHP[obj] = math.max(curHP, maxHP or curHP)
                        end
                        local startHP = State.LeviathanSegmentStartHP[obj]
                        local dmgDealt = math.max(0, startHP - curHP)
                        local dmgRatio = (startHP > 0) and (dmgDealt / startHP) or 0
                        table.insert(segments, {
                            Model = obj,
                            Root = root,
                            Humanoid = hum,
                            Health = curHP,
                            MaxHealth = startHP,
                            DamageDealt = dmgDealt,
                            DamageRatio = dmgRatio,
                            EnoughDamage = (dmgRatio >= (Config.LeviathanTailDamagePercent or 0.15))
                        })
                    elseif string.find(nameLower, "leviathan", 1, true)
                        and not string.find(nameLower, "heart", 1, true)
                        and not string.find(nameLower, "gate", 1, true)
                    then
                        seen[obj] = true
                        if not mainBoss then
                            mainBoss = {
                                Model = obj,
                                Root = root,
                                Humanoid = hum,
                                Health = curHP,
                                MaxHealth = math.max(curHP, maxHP or curHP)
                            }
                        end
                    end
                end
            end
        end
    end

    inspectContainer(workspace:FindFirstChild("SeaBeasts"))
    inspectContainer(workspace:FindFirstChild("Enemies"))
    return segments, mainBoss
end

executeAttackLeviathanStep = function()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
    if CurrentSea ~= 3 then
        travelToSea(3)
        return false
    end

    local root, hum = getCharacterRoot()
    if not root or not hum then return false end

    if Config.Spoof5PlayersBoat then
        Util.safeCall("executeSpoof5PlayersBoatStep", executeSpoof5PlayersBoatStep)
    end

    local segments, mainBoss = scanLeviathanEntities()
    if #segments == 0 and not mainBoss then
        State.LeviathanCurrentSegment = nil
        return false
    end

    local targetThreshold = Config.LeviathanTailDamagePercent or 0.15
    local chosenTarget = nil
    local chosenIndex = 1
    local phaseBanner = ""

    if #segments > 0 then
        local uncreditSegments = {}
        for idx, seg in ipairs(segments) do
            if not seg.EnoughDamage then
                table.insert(uncreditSegments, { Seg = seg, Index = idx })
            end
        end

        if #uncreditSegments > 0 then
            local picked = uncreditSegments[1]
            for _, item in ipairs(uncreditSegments) do
                if item.Seg.Model == State.LeviathanCurrentSegment then
                    picked = item
                    break
                end
            end

            if State.LeviathanCurrentSegment and State.LeviathanCurrentSegment ~= picked.Seg.Model then
                table.insert(State.LeviathanSegmentSwitchLog, {
                    From = State.LeviathanCurrentSegment,
                    To = picked.Seg.Model,
                    Clock = os.clock()
                })
            end

            State.LeviathanCurrentSegment = picked.Seg.Model
            chosenTarget = picked.Seg
            chosenIndex = picked.Index
            phaseBanner = string.format(
                "🐉 Đang đánh Đuôi Leviathan #%d/%d [Dame: %.0f%% / %.0f%% -> Đủ sẽ tự đổi đuôi!]",
                chosenIndex,
                #segments,
                picked.Seg.DamageRatio * 100,
                targetThreshold * 100
            )
        else
            chosenTarget = segments[1]
            chosenIndex = 1
            State.LeviathanCurrentSegment = chosenTarget.Model
            phaseBanner = string.format(
                "🔥 Tất cả %d Đuôi đã đủ Dame -> Đang kết liễu Đuôi #%d (HP: %d/%d)!",
                #segments,
                chosenIndex,
                math.floor(chosenTarget.Health),
                math.floor(chosenTarget.MaxHealth)
            )
        end
    elseif mainBoss then
        chosenTarget = mainBoss
        State.LeviathanCurrentSegment = mainBoss.Model
        phaseBanner = string.format(
            "👑 Đã phá hết Đuôi -> Đang đánh Đầu Chính LEVIATHAN (HP: %d/%d)!",
            math.floor(mainBoss.Health),
            math.floor(mainBoss.MaxHealth)
        )
    end

    if chosenTarget and chosenTarget.Root then
        State.LockedMob = chosenTarget.Model
        local tPos = chosenTarget.Root.Position
        local safeAttackY = math.max(tPos.Y + 18, 55)
        local attackCF = CFrame.new(tPos.X, safeAttackY, tPos.Z)
        State.PosMon = CFrame.new(tPos.X, tPos.Y, tPos.Z)

        if updateStatusUI then
            updateStatusUI(phaseBanner, Color3.fromRGB(115, 255, 175))
        end

        equipWeapon(Config.SelectWeapon)
        moveToTarget(attackCF)

        if (root.Position - tPos).Magnitude <= 155 and Config.FastAttack then
            Util.safeCall("executeFastAttack", executeFastAttack)
        end
        return true
    end

    return false
end

executeFindLeviathanStep = function()
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
    if CurrentSea ~= 3 then
        travelToSea(3)
        return
    end

    local root, hum = getCharacterRoot()
    if not root or not hum then return end

    local seatedCount = 1
    local boat = nil
    if Config.Spoof5PlayersBoat then
        seatedCount, boat = executeSpoof5PlayersBoatStep()
    else
        boat = findBeastHunterBoat()
    end

    local segments, mainBoss = scanLeviathanEntities()
    if #segments > 0 or mainBoss then
        executeAttackLeviathanStep()
        return
    end

    local fdCF, fdObj = findFrozenDimensionTarget()
    if fdCF then
        local distToFD = (root.Position - fdCF.Position).Magnitude
        if boat then
            Util.safeCall("executeFindLeviathanStep:L4715", function()
                local targetBoatCF = CFrame.new(fdCF.Position.X, math.max(fdCF.Position.Y, 26), fdCF.Position.Z)
                if type(boat.PivotTo) == "function" then
                    pcall(boat.PivotTo, boat, targetBoatCF)
                end
                for _, part in ipairs(boat:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CFrame = targetBoatCF
                    end
                end
            end)
        end

        moveToTarget(CFrame.new(fdCF.Position.X, math.max(fdCF.Position.Y + 4, 30), fdCF.Position.Z))

        if distToFD > 18 then
            if updateStatusUI then
                updateStatusUI(
                    string.format("❄️ ĐÃ TÌM THẤY FROZEN DIMENSION (%dm) -> Đang bay tới Frozen Watcher!", math.floor(distToFD)),
                    Color3.fromRGB(120, 240, 255)
                )
            end
            return
        end

        interactWithNpcOrObject(fdObj, fdCF)
        if (os.clock() - (State.LastFrozenWatcherInvokeClock or 0)) >= 0.8 then
            State.LastFrozenWatcherInvokeClock = os.clock()
            local spoofParty = Config.Spoof5PlayersBoat and buildSpoofed5PlayerParty() or nil
            pcall(function() CommF_:InvokeServer("InfoLeviathan", "2", spoofParty) end)
            pcall(function() CommF_:InvokeServer("OpenLeviathanGate", spoofParty or true) end)
            pcall(function() CommF_:InvokeServer("FrozenDimension", "Start", spoofParty) end)
        end

        if updateStatusUI then
            updateStatusUI(
                string.format("❄️ Đang mở cổng Frozen Dimension [Thuyền Beast Hunter: %d/5 người] -> Triệu hồi Leviathan!", seatedCount),
                Color3.fromRGB(115, 255, 175)
            )
        end
        return
    end

    if (os.clock() - (State.LastSpyBribeClock or 0)) >= 3.5 then
        State.LastSpyBribeClock = os.clock()
        Util.safeCall("executeFindLeviathanStep:L4758", function()
            local r1 = CommF_:InvokeServer("InfoLeviathan", "1")
            local r2 = CommF_:InvokeServer("InfoLeviathan", "2")
            State.LastSpyResponse = tostring(r2 or r1 or "")
        end)
    end

    if not boat then
        local distToDealer = (root.Position - TikiBoatDealerCFrame.Position).Magnitude
        if distToDealer <= 30 and (os.clock() - (State.LastBuyBoatClock or 0)) >= 2.0 then
            State.LastBuyBoatClock = os.clock()
            pcall(function() CommF_:InvokeServer("BuyBoat", "Beast Hunter") end)
            pcall(function() CommF_:InvokeServer("BuyBoat", "Sentinel") end)
            boat = findBeastHunterBoat()
        elseif distToDealer > 30 and root.Position.X > -18000 then
            if updateStatusUI then
                updateStatusUI(
                    string.format("🚢 Đang bay tới NPC Mua Thuyền Tiki Outpost (%dm) để lấy thuyền Beast Hunter...", math.floor(distToDealer)),
                    Color3.fromRGB(255, 215, 95)
                )
            end
            moveToTarget(TikiBoatDealerCFrame)
            return
        end
    end

    local wp = SeaLevel6Waypoints[State.LeviathanWaypointIdx] or SeaLevel6Waypoints[1]
    local distToWp = (root.Position - wp.Position).Magnitude
    if distToWp <= 35 then
        State.LeviathanWaypointIdx = (State.LeviathanWaypointIdx % #SeaLevel6Waypoints) + 1
        wp = SeaLevel6Waypoints[State.LeviathanWaypointIdx]
    end

    if boat then
        Util.safeCall("executeFindLeviathanStep:L4794", function()
            local targetBoatCF = CFrame.new(root.Position.X, 26, root.Position.Z)
            if type(boat.PivotTo) == "function" then
                pcall(boat.PivotTo, boat, targetBoatCF)
            end
            for _, part in ipairs(boat:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CFrame = targetBoatCF
                end
            end
        end)
    end

    moveToTarget(CFrame.new(wp.Position.X, 65, wp.Position.Z))
    if updateStatusUI then
        updateStatusUI(
            string.format(
                "🌊 Đang tìm đảo Leviathan (Frozen Dimension) tại Tầng Biển 6 [Điểm #%d | Thuyền: %d/5 người]...",
                State.LeviathanWaypointIdx,
                seatedCount
            ),
            Color3.fromRGB(140, 220, 255)
        )
    end
end
end

Util.spawnTracked("MainDispatcher", function()
    while State.Running do
        task.wait(0.12)
        if not State.Running then break end
        if not State.IsHopping then
            if updateMoonButtonText then Util.safeCall("updateMoonButtonText", updateMoonButtonText) end

            if Config.AutoHopNearFullMoon then
                local moon = getMoonPhaseInfo()
                if moon.IsTargetMoon then
                    Config.AutoHopNearFullMoon = false
                    saveConfig()
                    if updateMoonButtonText then Util.safeCall("updateMoonButtonText", updateMoonButtonText) end
                    if updateStatusUI then
                        updateStatusUI("🎉 ĐÃ VÀO ĐÚNG SERVER " .. moon.Name .. " (" .. moon.TimeStr .. ") -> Đã dừng Hop!", Color3.fromRGB(115, 255, 165))
                    end
                else
                    hopToServer("Normal", "Trăng " .. moon.ShortName .. " -> Tìm Server Gần Full Moon")
                end
            end
            if not State.IsHopping then

            if Config.AutoSummonKata and CurrentSea == 3 then
                Util.safeCall("trySummonKataPortal", trySummonKataPortal, 2.0)
            end

            if Config.Spoof5PlayersBoat and CurrentSea == 3 then
                Util.safeCall("executeSpoof5PlayersBoatStep", executeSpoof5PlayersBoatStep)
            end

            if not Config.AutoTrainRaceV4 or (State.ActiveMainMode and State.ActiveMainMode ~= "TrainV4") then
                State.IsHoveringV4Sky = false
            end
            if not Config.AutoTrialRaceV4 and not Config.AutoFlyBuyGear then
                State.DisableNoClip = false
            end

            if State.ActiveMainMode == "AttackLeviathan" and Config.AutoAttackLeviathan then
                if not executeAttackLeviathanStep() and Config.AutoFindLeviathan then
                    Util.safeCall("executeFindLeviathanStep", executeFindLeviathanStep)
                end
            elseif State.ActiveMainMode == "FindLeviathan" and Config.AutoFindLeviathan then
                Util.safeCall("executeFindLeviathanStep", executeFindLeviathanStep)
            elseif State.ActiveMainMode == "TrialV4" and Config.AutoTrialRaceV4 then
                Util.safeCall("executeAutoTrialRaceV4Step", executeAutoTrialRaceV4Step)
            elseif State.ActiveMainMode == "BuyGear" and Config.AutoFlyBuyGear then
                Util.safeCall("executeFlyBuyGearStep", executeFlyBuyGearStep)
            elseif State.ActiveMainMode == "TrainV4" and Config.AutoTrainRaceV4 then
                Util.safeCall("executeTrainRaceV4Step", executeTrainRaceV4Step)
            elseif State.ActiveMainMode == "Kata" and Config.AutoFarmKata then
                Util.safeCall("executeKataFarmStep", executeKataFarmStep)
            elseif State.ActiveMainMode == "Material" and Config.AutoMaterial then
                Util.safeCall("executeSingleMaterialStep", executeSingleMaterialStep)
            elseif State.ActiveMainMode == "Godhuman" and Config.AutoGodhuman then
                Util.safeCall("executeGodhumanStep", executeGodhumanStep)
            elseif State.ActiveMainMode == "Level" and Config.AutoFarmLevel then
                Util.safeCall("executeLevelFarmStep", executeLevelFarmStep)
            elseif Config.AutoAttackLeviathan then
                if not executeAttackLeviathanStep() and Config.AutoFindLeviathan then
                    Util.safeCall("executeFindLeviathanStep", executeFindLeviathanStep)
                end
            elseif Config.AutoFindLeviathan then
                Util.safeCall("executeFindLeviathanStep", executeFindLeviathanStep)
            elseif Config.AutoTrialRaceV4 then
                Util.safeCall("executeAutoTrialRaceV4Step", executeAutoTrialRaceV4Step)
            elseif Config.AutoFlyBuyGear then
                Util.safeCall("executeFlyBuyGearStep", executeFlyBuyGearStep)
            elseif Config.AutoTrainRaceV4 then
                Util.safeCall("executeTrainRaceV4Step", executeTrainRaceV4Step)
            elseif Config.AutoFarmKata then
                Util.safeCall("executeKataFarmStep", executeKataFarmStep)
            elseif Config.AutoGodhuman then
                Util.safeCall("executeGodhumanStep", executeGodhumanStep)
            elseif Config.AutoMaterial then
                Util.safeCall("executeSingleMaterialStep", executeSingleMaterialStep)
            elseif Config.AutoFarmLevel then
                Util.safeCall("executeLevelFarmStep", executeLevelFarmStep)
            else
                stopTween()
                removeAntiFall()
                State.PosMon = nil
                State.LockedMob = nil
            end
            end
        end
    end
end)


local function mountSafeScreenGui(gui)
    local target = nil
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then
            pcall(function() gui.Parent = hui end)
            if gui.Parent == hui then
                return hui
            end
        end
    end

    if syn and syn.protect_gui then
        pcall(function()
            syn.protect_gui(gui)
            gui.Parent = CoreGui
            target = CoreGui
        end)
        if gui.Parent == CoreGui then
            return CoreGui
        end
    end

    if CoreGui then
        local ok = pcall(function()
            gui.Parent = CoreGui
        end)
        if ok and gui.Parent == CoreGui then
            return CoreGui
        end
    end

    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        or LocalPlayer:FindFirstChild("PlayerGui")
        or LocalPlayer:WaitForChild("PlayerGui", 5)
    if pGui then
        pcall(function()
            gui.Parent = pGui
        end)
        return pGui
    end
    return nil
end

local MaidHubAvatarFileName = "MaidHub_Avatar_Circle.png"
local MaidHubAvatarBase64 = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAMAAAD04JH5AAADAFBMVEX9+vwAAADz6PLn2fEqKDiUwv6Qu/3SyOvU1vTOxtQZGTDGutS4tdHY1Ng2NEquyPb22dauqc6wt+v94d240/spKkauqeasprXX5PzyycjGuerpqqyRmdB/v/+YlrKUpNcVFRWQqOVFRUWqqv9MRVNEOkuMiaymmrHNp6sjHSuGi5SsuMsA//8mJiY1NTXhzPjOtrZ4dorttba3tLmq//80MD2Nh5I2NjZuZ3R3mNIeIDtmZpqlncsLDSZZV2pmWmlJSGi0lZkCN4Q5NzsCAjUzPGNVqv9zdHh4dXyGeo1kZWtra4ptuOzQm6RJW4aYlp2Zo7G1xNzJl5YFBQsbJEQMN3U6RGupiJAXZcc0NGdVVatbebBnZ2dteqtmmc1///+MdXmUnOIBKXUHRpAIVKwsZrZxc4xngrSIaG+Fi8yjq7q4xtpSVFRWZo9yh8mPl6IKCBhEJi5QhsmMkp3FrsXuvMEAAP8vLy8tLVcsV1c0aGg0Z5tBQUFAQIBXVlZAgMBlZ3t/f/92pduBgYGAgMCSmaqZmf+AwMD///8aGRweHSQETaMYYrkpec5JMj1YUVpFkttsU1yapMaUuNm1Z0ywenWvjand8/01KzI7OEAtM088VIQ3htNBPkRSVGlQbqRYg7hepNxYruRiS1Rra4J6foJ0e5h7gZN5hqx6s9uFh52EiqSEjbSKlLWYpLePo7arWT2nssIMDBQXFR8YFyIWFiQdHkECWcIlFB4oLEI+P1w9QFU5Q2Q5RmsxbMAxc7xGRFFTUVRSWoddtexiXGlzdH52f7V+go59gpB9jrJ8kLx/qOZ8xPODS0+HaHeAe6axXEChfImhneC0oJzUwL7in6LywbwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADlSQLCAAABAHRSTlP/AP/////+//7////+///9//7+//z//////////wT9/Rb+RQP///////+PygEqBf//////A///N////wX/////////RQX/A3T//W3////3/63a/zL//////wUE/AX+BQL///////+S/f//tvtS//+c////lv//AQYGBgUFBAQDBI4C/wQEsgUEASYq/////////9L//////0dJrv//SnL//////4t+rf/G/62szMjG//++Rf9Acv///4xj/7fX//9jY8n/coq+laW1/////6X//////////wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAupzCrwAAFoxJREFUeNq1m4V/G1fywJ/ek/ftW961pZVkWbIMshzHDLFTx5A0DTfQUCFt0iRN0pSu16Pfce96zFc4ZuYfMzPz7+/5zczuCgyx1OTeJ7YsOd75vpl5M/OIpTps73y87wF46e8fGBjYFTf4sb8fPnyg7/F3dvo81sl/vv/dfbtB9sD3T4319PS4bleXBq2ry3Xh7dip7w8Axe6+d9//6wG4//19IPyZ50/3uF0gFNvGF7fn9PPPAETf+++/5wATIH380FiPi9I0LRKoxS1CoE811/3F0XFgmLinAA8PpvqPkvRICvRVz3HO4sZ5Todfxmya5v7iL/tTgw/fM4BHBlPjb02ka66eYxuabXOmOAMMVBAyuO7fj6cGH7knAO8dTA38Zk/03K6eTcIZV8rjtqUYKYTnXC0i7Tl1IDX43rsGmJhLDYz1xI/kbHNTNn2qzOSXQsoY1x07kJqbuDsAUP4pFA9Py7GtmhLRqzSjHzjTpWAcbYF/9AoY4i4A3jeY2qXTk7bsPMkX0W+EKTnJ51KnT3IRt/63qcH3vVkA0L7rkni2TQPPiwk4qYBDQ28kFklacG+DHd4UwP19qVd60Jbbikf5jCMAR1f06Y2QIF+QL+jcpb//h1Tf/Z0D/EZqj0sjPretfGaT8nWBXVZyGV4FaAS+CzQF+ALTKWpae+BxHQIMpg5h9zWd3aGpSPkok5kF32LC5rYCJYBo08Tv4I4YKd2j2/riNgBz/U8ju8vvIN22bfJ8IZDAt1TcbBu+lCkSpyAlPN0/1wlA3/hpVH/PnXrPualLnVQAjgcSLeizENIqwAu8lRAZwCeg9SDB6fG+9gHm9ujoPbk7yqehZ+Ir9Do8srpS9atHTETgwpa6rmY9hvLRDPg0fc9cmwATgyj/DupXIbM9dDyphO9LwcOVTHro8KKTqYLlsc9cKj2nLKXTGGHcQn3qewYn2gGYeGAPmX/73lvTONjxwaaSpqkOp9NpZ8VJZ1anh1bBNFyH0ahQCVGc5qZkFBL2PDCxM8BE356encz/w1mddAtj3VShY6SjNjzkrC2QApQOlgAC3fRIvhQKO9WzZ3OZsAmgj/p/J/mMP6grHOsUfhYS8aCFzPCwSQBCgXAEkJYS4JyosB7SQd9OAH1k/zvKZ+zcbduD+AMWVkca8tNp8ARye/ABPSbQLd/3yWDCJT/ouzNA33gb8tlXn2W+wKirFpvlp9Oj09HAg1/pSVO+xNgslE0EG0djK8B9/ae1neXb00/qLy9JKdV0q/z0aBgDcL3RlAJtCQhbNsbW0/33bQ/wrt1P39n/4wxgPfnNb3/thqlKG+SnHYgB6ByiGUCHnK0ryNyKoQ6e3v2u7QAmBg/h/9hBPofi69yTf/65r32r5JDQJoAhlE8AIhaey+VgLIBsbusWY9i/Qy3hgLU4IHoq30kBHmfPPnn1xc99+urZdNrINMk3DscAiQpAeO6NnA6RC3xAAgCPBuPWAPelsP85tlOD55ee3H/9c5+6du2c0aIA42QCgE6Qo+6/8QbTb2O89k0LCyXUQeq+rQAe/uCpNgYAdAUQvKv7z12/9slrVw3HceIRiAAhawaAxuDl9hdzVLxB0GBRODj1wYe3AJgbgN+5O8qPUvCzT57b/8lrn7wKkh1ygwhDNQAEAeTY7V8eB61CxMCoiX8KhVrPwNxmgMgAO8qnIoQLsMH+/VevnsO+oxJiRSgsx2IECeJB9fqPu47DNArSsxyxyIKtRkgA3vPELgwTbQBAkDFN86v7sZ2lYRABgBHmsTjjiQ1APkTr3Bf/pev48ZxvSVn8JT0BQ92uJ96zAWBuvKctBTDLVAoARs7t33/ubDz6CQIo0rH2IwBKFrmcexxaF6Rt5VvRI9DVxudaAR6jEJRrA4DNSohtcsQ4t98YbQpBZATschQJYYJC5TKMhR8fP/7XS0FZ+uW4xMhROHqsBWAQPLDLZW21kxBXxPQLRrN8JBhGAJHIB/8nAF3/4neOf7scBKpYCWITQ7ndMzDYDPCh3WPtGQDb59OhkEOGsSEOO46x2gQAomksQFJ8+Tsgv1z0tQQAjTC2+0NNAB9GBfS0J98eNoxFK72pOenhM5I3DUN6g/EwWAoC+eKnisH1cvwMlDbw4QbAY6gArU0FnISA88JnNwOkjdd6sSyOCHIRAAVkKQFg6eL1R3//W8lDNFTBY3WAj467bSuADaWN0VFS/+gGgt5apIGo6UEdQNddvXzx2qcuvsgaKnDHP5oATOx+q7ZzEkriwBDUgBFA4gQRiHHTawGQQUtOrly8eP3iUiIEopH21t0TMcDj/W0F4aiFWAMTwGgCEL/W+EwDQG8GwPIo+PTF69derA90DMj9j8cAHzvabgwA9NnFRHZ9GEavQx7PK9GkgXILgPz0n1WuX6yHWowFRz8WAdyXGtPaHoNKrSYi68OQ3o1e4ADQMAG3irlmAP3FG5XyUkPPYIMxzAgMC9H2xyCbtYdI6N4mgKjNAIDZAMi9NNICIIRfCZoMjTKxQAWA3Ye62nZBABhO7N4CYKx63dwzqR4jH8iZGwGsslYJGrYEoYd2IwBZoN0gwGftSOlGmiLhfCx/Pr3OAACSfgKgv+1Ew/4oXxSKQdAAgFBANmCpvv4OLABT/6j/NBQz8/MxwdDQFPc8L89hqkoeAAA1EMzhS+gFApDFwLVYiw36+wDgiWfctscAs+2Tow0NzNcBbq5OTYXhf6+reBwgQG8dINCjYdECAOPAfeaJFHtH6vn2LQAAK7EGKBkhACDMD08dpgSQl2YMIKU3JQkAYnIEIMpaMwDa4PnUO9gjqdNtJ2IAmK274AsI4MzPYy22XltgYAHuTb6UAKjauh/6Cu2PAGgYv+LebnoWhP/TqUfYR9AF9HYB+GEq/tAHhl6gKsRx5kcX2ULIQHw+L8x4XqCUN6Obpq4sAHApMU0CgGp6lo5O8BH2wACQtOsCkIoWhqIROMUXYoB0+rJarJECAGASOwsK8Lz/U1MmlxaaQGCanLSuuM09zYHmBx5gbz/UfiYGDQxBOQAAxkr+hLcIBG95CyjkD0bT84vhVN7zVB4BODdhGgBv8vwlE3wwApDBUgsA5uRDb2epU+3HYYjEjiINGJffNlO7iXUYEKxU14bSo6PDU55n5qO5oWnybnjjiREEkBGAdSVoAYCen4JhONaBD4KtrUgDC97bem+mh5Fg+Fjx0qVLzx757ne97jxYAQBU3pyprV++fHlxBIRnEWASACoVnbd64ViKdRKGGIPRNk8A6zzfewGdYPgzwyvF0nT1mMkvYDDC9XOhvAufmYdo8dvpmyECSAQoWEG5BYBCEetoELDDjDmRBvhMb82JCFbBy90FmDRDOuCeEHmPXxiaPnZsxQxXR1dNGSCAFFkAaFn7o2HAOhoEvA4wlJ+ZqQ0NI0B66CVdtxRFom761s2PlfzqsRHhff5ffR2lF4ScBAC/xdg0DBBA423HoQUYiDQMIfvNzHz+szQMh/N5cDrudXdHJXl3t+fDVGzBYyOv1ZYFABRMAPCtwLrdLIprMUBX5wBAMM1nbq4OpTESguvlYQx6gAAQ8OUprvuKeb35CzApnRQBaECWLU22mICTBnZ1EgbQB6JRYGTOLnbXFhdxYji8vgnAs00YlPn8+uvY98lsYRIBKnqLE2Ig2MV2aV0dACxwtkKpaG/GMT7rXQ4pF1/ONwEAAf6IH+WnzpwwJ6H5CFAsV3IbALq0TgGskB1eoVScyaT3OQ7VZ8PrUx7JRwAYDDyRnz9zolqQKJsAKlAn3y0AO2mXFjAVZaCBHWiNanRqyvO8ugkYiwG82uvFoo/mvxVMQiC+JwBMHZ7FVOAQgENLM6MLvNZdt0CTCUYqFX8ZAArPZSdldkkL2D0AAB2s7jMWF41MZq8BGEgw1J1Xdfnd3bE6vHwxm12uYix+rjBZyEJFxlpD3psDmA1DAAgBIG1knIxz0Ekbl1ljBNQRukMEKEIY9J8ryEKlGEie2wKgo2EIoWDqJB82HO6cBRvgAtXBg6s3oSSNBHdzniDwfDWbzfoQiApXgCIolgOdt0YcGoYdBSLaKw7ZrGGok+AEeyOAld4pL5KrICSp2BNUCRSQLS5PFvwrvpTZYjbgrQC881DMoj0qtvDCtPnDTObsH6P882snemsRAfkfvvLu2X+qEEBBmssAUCiXpWStghqhONeBfHjGrODTjh0uns04i5nz588fXJ/pPaMoB3iRGbzZ0lIlApAFHynABaW+oaNRMuokHdt21AeY/5ycVrNrmbPTx5zzB5890dvbewLNAAA4QwvLRRBPANkCfN0qSFJA0vOWdNx2QYL7w7QLiKcFdGaOhAvOWcdaObjmr/diO/M/lI69qQtVmAVWliIAbLdkoSjjWRnHjdXmgqTdkszGPxTRTiTj4IvCL4WOsWivVc0jvRFBDaLBVK33QskHgjpAUCyKok8AIJ3TRmtTSdZuUYrUgqoO3BvX4SfLD4FgOrRUDACesH7if3t7/9OXpUqlnJigcMvX/UCTJB4ehDu7TUVpm2V5tAPJbdqQVtgJACiWwmNrfkG+DrIb7cSIaVpFrVxGgEIhK4u+KcuablPHUb5QTWV5mxMTO/YDgSQcV35VGPq+KvnSlOaJfG+ihN7aS9K0CmCEpWKQhXKwALmwADyWTSvItIahmiYm7U3NuN34CTcMVDE0oZ9mqYqbZ7I2QwQzM70nariba1nSL1ayQRZycSHIiivPWbS3Dn6ECoicIJ6atTc5tXnzGgE4QQi1twnyfQRQqgY1KpTJtZopcS3dAgIMhAFOB7LLfskHQ9FOcgRAZ37iyWl703N7wyqFRWc0/LBkknyJBLUa/EDyI4B/z2ZpQiTNEXAC3cY4JEKaPBNAPD1vb4FCtW4b0bkpbpasEbKAksyu4eo8TIrrAEeOFQo0I5RmyeS2F7H7NI4QIFmgaG+Jxm7smMXHJ+BnUGxIFpAstHSf0CIA0yxY0z6Uw0LAKABfTf7eNpGRAOpLNO0sUvE4BkfrP7hxRRtxVgzAwRes6ehISwwgwyopQATZQmgni/hcVUvFUtFCoPoiVTvLdAkAHRQS+I6TJ+BOkJQ8rILOSyGLTzShfLPq41kSXfoBUKpkGX0ks4JRAbSg15fp2lmojETGNhBRTjQ5AaD+SyMwyvyRuBMwPBQoIGuRB/pBuGzFS1c6HzGcg9UCHnBxGwuVbSzVcpVsxOB3EzMSZAPdCi0p2OyyH1qWbyZ7UqAm3aregumYwK0Cq2Qp1BMBYCXnVPFMgdZYqm1jsZrbjWIG8h0d3YIfJEy/WAiuABYITVVqDJPSpSJNx6TEAQF+gUdKUAP7YFLlVGXBbVqsbme5XglP0A6QMn0TWSKVwKAKfdPy0RiWOZIMVl4qVbN+AfoPDhH6FCjokBGvIoDhjOha83L9zhsWNiViW4EURQC2iowxq6DQhJBsqdDk+kiyp7C8fCuLMRIUoEoWOL+pbEuHZxwhgMya37JhsfOWTSMOgXlBJjPjYUXn2EC/dJaOhdH/g8C3fCUICEC3LUFp2DZN6ANutkFbW2rZstlx04onB0ZpKIPfK5HsT6JvwCfCpH1rUkFoCX/5ioULM1IJPYzyiGWaNitFS6yGgy7YtGm107YdjzXAwY/AmgrGAW9qCt1e4k6pGTKOZ4z8/yr6BGDx5LAp+KIYgUntXphZG5e6upYOfLiDjcsEAA+DKEtXolk+1jfc0mnTNpylA5V+1odUXCgU/OTQKbdkuILry3vT6cxBUMBftWxc7rR1qxqpADxRmc3yKVULm8UbpvSflgsyCAqBDBSLD7uK0qqxL9ptzWTAA577ncFONq9VPQjoMOZKpmgBiMJSsmWLbRn3KmE2YikeW4BnyP+x/5kHweH+ZMPm9Q7b93asR11B8AtLerMGKEyrlk8gPkg0QQAAifIi/ycF/LPW9ehDcx0dYJgNMfhBYLFKJeuIqm9Q4z88p4SVfhKosVlc+FCOujBkk0MVx2gA7AUn+GaXVvnDTQcY4iMc20SjaYdyDCQcH8ornmQmIjB1W8QzhnqDrO/LbODiUTZMCBIPHID/47rKeQh6D24+wgFGOIAEdtSU3VwFsqF9CwJyLFQAlHUbx+rxaAyWWGaLVZiyVSEIXASgwIHZyAECkO+8rHU991tzWx7j+QmwBfm8wuUdKJ0b4U9lMukRLPik5R9BT29kJkEljs1YqxOEhaBCABC1MEJBRFqIAG6AB35ly2M8oJUjoIILr/7qV//x6quvnVF112fTGcdYgDwEtd602SSfI6auINyIVhNwM1sOXN1VVIbTnEYoXNTCEdBsgA1HucYxR6yfWT9Tm5pSoq4BvuakFzikVNMKw+Y5Ps4zUMd2a/exYi5mA9y0F5YvkjoFAdABLj3Ut+1htqP1s0QYYesb5o6TDnU8PWOVNixy0DzJjIuVRrQS/i0XAAK8d6CiepiZaIKK1rX0u9seZku9a/cr8XE+3gywmHHSQzpWvyWbtQDwKAjxDVhCXvJdV9ctiFsinpOyaRiBS+gA2x/nS6qznijmJqX0LK6I7zsGjmTOslZRdLpdsY2D17aqKF/HcCCiWTkTjgE5SNP+NHXfHY90fjw60tmkAB03BQxj36rSww2SaJqtxKbgoawinaktC4EuQGfwq4bxKDrgQ31tHWoFgClVNwAC7N3nVM0NfbWj4nBT9rZsCwFkEQAgTdNnztbytzvW63I149GjTzqggQxG8X0ZvnHRBqa7QmwC0BWPAXTu4yl/+LvpfSj/0Yf62j3Y7K7P5GdAw2p4jQAgkO87slEBXInWiJlUsAQgZVnxEbr5YTrGjUj+RNtHuzVzagqKmxVnbYh2RwEgbAUA5UOwsrdY04eCHVvg+yI6wZfet0Ty2znaTYfb47sF3LNLi87wsIMr44axwQWo71sogFvMIwCYftiYJiGSvkz2b+9wOxUHZTqQHyl0zRkGAMhlavOMeQsXhMk7s2mrzvdliGNUPYi3LG48NNfBBYeP/0yLBwNlAnLDDQCk/K0soEPVjEV5YBX1qgWuWkaLjnVywQFv+PyEbrjoQk3jojSuzRvm5ijobVFAQPyxCMCvSvgX3XP5x86ueOAll6N0ySVY+z0nqqX2GuFGgC1dgOEyDQJk/WVllst0HfAbnV5ywWs+4yW6K/VgJq7mjBKPwlpTGNwKADNABOCbAT3CH+/8mg9ddPo3TM9dS+dxd2pvxpgWkjeSwbYagPyjsoEswNyALskFP3hTF53IEb5UoouVNxzaK10TOBUVyVLFNj7Alc4sAAiydEFQK3/5TV71ii67fSC6NnfjPM7ooLgTUfGTjEC647QBQIcADPVYpP3y9+7islt03e+V6Nrc0rOOMaKbyWIP1SHNazeNMAAFmV+Jeu/+4ON3dd0vuvB4IL7wqJVL0lQ63lbA+2VsFtOMzTYSgJNEttcqP7/7C4/Jlc/owimMSjwPQqtfOt3xoYmpEE33X3OUSPDf333pXlz5TC69fqAcXyXVAldSqhO0IkpFYewWTZdetcpTn7hXl17ja7+pv/i5piXXfjUXmmVZMNKxIgUceN+49qv96I9S9/Lab3Lx+RPf+FGg7XTxWQt+9jefuOcXnxtXv7/+1BcCTdv66jcoZmzXwK/p6nfz5fcDR3/6hSAItEYDAwRf+OnRA7/Wy++t1/8B48CBDzz11FPw9b0vH/g63v5/U9f//x9gP7b6lK39WgAAAABJRU5ErkJggg=="

local function decodeBase64(data)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #b do
        lookup[string.byte(b, i)] = i - 1
    end
    data = string.gsub(data, "[^" .. b .. "=]", "")
    local out = {}
    local n = #data
    for i = 1, n, 4 do
        local c1 = lookup[string.byte(data, i)] or 0
        local c2 = lookup[string.byte(data, i + 1)] or 0
        local b3 = string.byte(data, i + 2)
        local b4 = string.byte(data, i + 3)
        local c3 = (b3 and b3 ~= 61) and (lookup[b3] or 0) or 0
        local c4 = (b4 and b4 ~= 61) and (lookup[b4] or 0) or 0
        local triple = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        local byte1 = math.floor(triple / 65536) % 256
        local byte2 = math.floor(triple / 256) % 256
        local byte3 = triple % 256
        if b3 == 61 then
            out[#out + 1] = string.char(byte1)
        elseif b4 == 61 then
            out[#out + 1] = string.char(byte1, byte2)
        else
            out[#out + 1] = string.char(byte1, byte2, byte3)
        end
    end
    return table.concat(out)
end

local function loadMaidCircularAvatarAsset()
    local assetUrl = ""
    pcall(function()
        local pngBytes = decodeBase64(MaidHubAvatarBase64)
        State.MaidAvatarPngBytes = pngBytes
        if writefile then
            writefile(MaidHubAvatarFileName, pngBytes)
        end
        local customAssetFn = getcustomasset or getsynasset
        if customAssetFn then
            local ok, res = pcall(customAssetFn, MaidHubAvatarFileName)
            if ok and type(res) == "string" and #res > 0 then
                assetUrl = res
            end
        end
    end)
    State.MaidAvatarAssetUrl = assetUrl
    return assetUrl
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "MaidHub_V5_AllInOne"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 9999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.IgnoreGuiInset = true end)
mountSafeScreenGui(ScreenGui)

table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if ScreenGui and (not ScreenGui.Parent or not ScreenGui.Parent.Parent) then
        mountSafeScreenGui(ScreenGui)
    end
end))

do
local maidAvatarAsset = loadMaidCircularAvatarAsset()

local Theme = {
    Bg        = Color3.fromRGB(15, 13, 27),
    Sidebar   = Color3.fromRGB(22, 19, 38),
    SidebarHi = Color3.fromRGB(42, 35, 70),
    Card      = Color3.fromRGB(26, 22, 44),
    CardDark  = Color3.fromRGB(19, 16, 33),
    Topbar    = Color3.fromRGB(25, 21, 42),
    Accent    = Color3.fromRGB(135, 185, 255),
    Green     = Color3.fromRGB(90, 225, 145),
    Red       = Color3.fromRGB(255, 110, 130),
    Yellow    = Color3.fromRGB(255, 215, 95),
    Text      = Color3.fromRGB(240, 240, 255),
    Dim       = Color3.fromRGB(145, 140, 180),
    Muted     = Color3.fromRGB(95, 90, 125),
    Stroke    = Color3.fromRGB(55, 48, 92),
    TogOn     = Color3.fromRGB(80, 210, 140),
    TogOff    = Color3.fromRGB(50, 44, 78),
    Divider   = Color3.fromRGB(40, 35, 65)
}

-- Helpers
local function addCorner(parent, radius)
    local corner = Instance.new("UICorner", parent)
    corner.CornerRadius = UDim.new(0, radius or 8)
    return corner
end

local function addStroke(parent, color, thickness)
    local stroke = Instance.new("UIStroke", parent)
    stroke.Color = color or Theme.Stroke
    stroke.Thickness = thickness or 1
    return stroke
end

local function addPadding(parent, top, bottom, left, right)
    local pad = Instance.new("UIPadding", parent)
    pad.PaddingTop = UDim.new(0, top or 0)
    pad.PaddingBottom = UDim.new(0, bottom or 0)
    pad.PaddingLeft = UDim.new(0, left or 0)
    pad.PaddingRight = UDim.new(0, right or 0)
    return pad
end

local function addListLayout(parent, gap)
    local layout = Instance.new("UIListLayout", parent)
    layout.Padding = UDim.new(0, gap or 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    return layout
end

local function createSectionHeader(parent, title, order)
    local headerFrame = Instance.new("Frame")
    headerFrame.Size = UDim2.new(1, 0, 0, 20)
    headerFrame.BackgroundTransparency = 1
    headerFrame.LayoutOrder = order or 0
    headerFrame.Parent = parent

    local headerLabel = Instance.new("TextLabel", headerFrame)
    headerLabel.Size = UDim2.new(1, 0, 1, 0)
    headerLabel.BackgroundTransparency = 1
    headerLabel.Text = title
    headerLabel.TextColor3 = Theme.Accent
    headerLabel.Font = Enum.Font.GothamBold
    headerLabel.TextSize = 11
    headerLabel.TextXAlignment = Enum.TextXAlignment.Left
    return headerFrame
end

local function createToggleRow(parent, title, defaultValue, order, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 36)
    button.BackgroundColor3 = Theme.Card
    button.LayoutOrder = order or 0
    button.Text = ""
    button.AutoButtonColor = false
    button.Parent = parent
    addCorner(button, 8)
    local stroke = addStroke(button, defaultValue and Theme.Green or Theme.Stroke, 1)

    local label = Instance.new("TextLabel", button)
    label.Size = UDim2.new(1, -68, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd

    local pill = Instance.new("Frame", button)
    pill.Size = UDim2.new(0, 42, 0, 22)
    pill.Position = UDim2.new(1, -52, 0.5, -11)
    pill.BackgroundColor3 = defaultValue and Theme.TogOn or Theme.TogOff
    addCorner(pill, 11)

    local knob = Instance.new("Frame", pill)
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = defaultValue and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    addCorner(knob, 8)

    local currentValue = defaultValue

    local function setVisual(val)
        pill.BackgroundColor3 = val and Theme.TogOn or Theme.TogOff
        stroke.Color = val and Theme.Green or Theme.Stroke
        pcall(function()
            TweenService:Create(knob, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = val and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            }):Play()
        end)
    end

    button.MouseButton1Click:Connect(function()
        currentValue = not currentValue
        setVisual(currentValue)
        callback(currentValue)
        saveConfig()
    end)

    return button, function() return currentValue end, function(newVal)
        currentValue = newVal
        setVisual(currentValue)
    end
end

local function createActionRow(parent, title, buttonText, buttonColor, order, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundColor3 = Theme.Card
    row.LayoutOrder = order or 0
    row.Parent = parent
    addCorner(row, 8)
    addStroke(row, Theme.Stroke, 1)

    local label = Instance.new("TextLabel", row)
    label.Size = UDim2.new(1, -110, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = title
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd

    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0, 96, 0, 26)
    btn.Position = UDim2.new(1, -104, 0.5, -13)
    btn.BackgroundColor3 = buttonColor or Color3.fromRGB(55, 46, 88)
    btn.Text = buttonText or "Thực Hiện"
    btn.TextColor3 = Theme.Text
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    addCorner(btn, 6)

    btn.MouseButton1Click:Connect(function()
        callback()
    end)
    return row
end

local function createPage(parent, isVisible)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 5
    page.ScrollBarImageColor3 = Theme.Accent
    page.CanvasSize = UDim2.new(0, 0, 0, 900)
    page.Visible = (isVisible == true)
    page.Parent = parent

    local layout = addListLayout(page, 6)
    addPadding(page, 6, 10, 6, 6)

    if layout.GetPropertyChangedSignal then
        table.insert(State.Connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
        end))
    end
    return page
end

-- Main Window
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MaidHubMainWindow"
MainFrame.Size = UDim2.new(0, 520, 0, 395)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -197)
MainFrame.BackgroundColor3 = Theme.Bg
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 12)
addStroke(MainFrame, Theme.Accent, 1.8)

-- TopBar
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 38)
TopBar.BackgroundColor3 = Theme.Topbar
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame
addCorner(TopBar, 12)

local TopBarPatch = Instance.new("Frame")
TopBarPatch.Size = UDim2.new(1, 0, 0, 14)
TopBarPatch.Position = UDim2.new(0, 0, 1, -14)
TopBarPatch.BackgroundColor3 = Theme.Topbar
TopBarPatch.BorderSizePixel = 0
TopBarPatch.Parent = TopBar

local TopAvatar = Instance.new("ImageLabel")
TopAvatar.Size = UDim2.new(0, 26, 0, 26)
TopAvatar.Position = UDim2.new(0, 8, 0, 6)
TopAvatar.BackgroundColor3 = Theme.Bg
TopAvatar.Image = maidAvatarAsset
TopAvatar.ClipsDescendants = true
TopAvatar.Active = false
TopAvatar.Parent = TopBar
addCorner(TopAvatar, 13)
addStroke(TopAvatar, Theme.Accent, 1.2)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -90, 1, 0)
TitleLabel.Position = UDim2.new(0, 40, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "🌸 MAID HUB V5.8  |  RAZEN ENGINE"
TitleLabel.TextColor3 = Theme.Accent
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 28, 0, 26)
MinBtn.Position = UDim2.new(1, -36, 0, 6)
MinBtn.BackgroundColor3 = Color3.fromRGB(48, 40, 78)
MinBtn.Text = "—"
MinBtn.TextColor3 = Theme.Text
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 14
MinBtn.Parent = TopBar
addCorner(MinBtn, 6)

-- Sidebar
local SideBar = Instance.new("Frame")
SideBar.Name = "SideBar"
SideBar.Size = UDim2.new(0, 105, 1, -38)
SideBar.Position = UDim2.new(0, 0, 0, 38)
SideBar.BackgroundColor3 = Theme.Sidebar
SideBar.BorderSizePixel = 0
SideBar.Parent = MainFrame

local SideDivider = Instance.new("Frame")
SideDivider.Size = UDim2.new(0, 1, 1, 0)
SideDivider.Position = UDim2.new(1, 0, 0, 0)
SideDivider.BackgroundColor3 = Theme.Divider
SideDivider.BorderSizePixel = 0
SideDivider.Parent = SideBar

local SideScroll = Instance.new("ScrollingFrame")
SideScroll.Size = UDim2.new(1, 0, 1, 0)
SideScroll.BackgroundTransparency = 1
SideScroll.BorderSizePixel = 0
SideScroll.ScrollBarThickness = 2
SideScroll.ScrollBarImageColor3 = Theme.Accent
SideScroll.CanvasSize = UDim2.new(0, 0, 0, 340)
SideScroll.Parent = SideBar
addListLayout(SideScroll, 3)
addPadding(SideScroll, 6, 6, 4, 4)

-- Content Area
local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -106, 1, -38)
ContentArea.Position = UDim2.new(0, 106, 0, 38)
ContentArea.BackgroundTransparency = 1
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame

-- Tab Definitions
local tabDefs = {
    { key = "Home",      icon = "🏠", label = "Home" },
    { key = "Farming",   icon = "🌾", label = "Farming" },
    { key = "Gacha",     icon = "🎯", label = "Gacha" },
    { key = "Store",     icon = "🛒", label = "Store" },
    { key = "Teleports", icon = "📍", label = "Teleports" },
    { key = "Misc",      icon = "⚙️", label = "Misc" },
    { key = "Settings",  icon = "🔧", label = "Settings" },
    { key = "About",     icon = "ℹ️", label = "About" }
}

local pages = {}
local tabButtons = {}
local tabLabels = {}
local switchTab

for _, tab in ipairs(tabDefs) do
    pages[tab.key] = createPage(ContentArea, tab.key == "Home")
end

for idx, tab in ipairs(tabDefs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = (tab.key == "Home") and Theme.SidebarHi or Theme.Sidebar
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = idx
    btn.Parent = SideScroll
    addCorner(btn, 6)

    local ind = Instance.new("Frame", btn)
    ind.Name = "ActiveIndicator"
    ind.Size = UDim2.new(0, 3, 0.6, 0)
    ind.Position = UDim2.new(0, 0, 0.2, 0)
    ind.BackgroundColor3 = Theme.Accent
    ind.BorderSizePixel = 0
    ind.Visible = (tab.key == "Home")
    addCorner(ind, 2)

    local iconLabel = Instance.new("TextLabel", btn)
    iconLabel.Size = UDim2.new(0, 22, 1, 0)
    iconLabel.Position = UDim2.new(0, 6, 0, 0)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = tab.icon
    iconLabel.TextSize = 13
    iconLabel.Font = Enum.Font.GothamBold
    iconLabel.TextColor3 = Theme.Text

    local textLabel = Instance.new("TextLabel", btn)
    textLabel.Size = UDim2.new(1, -32, 1, 0)
    textLabel.Position = UDim2.new(0, 30, 0, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = tab.label
    textLabel.TextColor3 = (tab.key == "Home") and Theme.Text or Theme.Dim
    textLabel.Font = Enum.Font.GothamMedium
    textLabel.TextSize = 11
    textLabel.TextXAlignment = Enum.TextXAlignment.Left

    tabButtons[tab.key] = btn
    tabLabels[tab.key] = textLabel

    btn.MouseButton1Click:Connect(function()
        switchTab(tab.key)
    end)
end

switchTab = function(activeKey)
    for k, page in pairs(pages) do
        page.Visible = (k == activeKey)
    end
    for k, btn in pairs(tabButtons) do
        btn.BackgroundColor3 = (k == activeKey) and Theme.SidebarHi or Theme.Sidebar
        local ind = btn:FindFirstChild("ActiveIndicator")
        if ind then ind.Visible = (k == activeKey) end
        if tabLabels[k] then
            tabLabels[k].TextColor3 = (k == activeKey) and Theme.Text or Theme.Dim
        end
    end
end

-- =========================================================================
-- TAB 1: HOME (Branding, Hub Status, Quick Toggle, Thống kê nguyên liệu)
-- =========================================================================
local homePage = pages["Home"]

-- Hub Status Card
local StatusCard = Instance.new("Frame")
StatusCard.Size = UDim2.new(1, 0, 0, 78)
StatusCard.BackgroundColor3 = Theme.Card
StatusCard.LayoutOrder = 1
StatusCard.Parent = homePage
addCorner(StatusCard, 8)
addStroke(StatusCard, Theme.Stroke, 1)

local MatLine = Instance.new("TextLabel")
MatLine.Size = UDim2.new(1, -16, 0, 20)
MatLine.Position = UDim2.new(0, 8, 0, 4)
MatLine.BackgroundTransparency = 1
MatLine.Text = "🐟 Fish Tail: 0/20 | 🌋 Magma: 0/20 | 💧 Droplet: 0/10 | 🐉 Scale: 0/10"
MatLine.TextColor3 = Color3.fromRGB(185, 230, 255)
MatLine.Font = Enum.Font.GothamBold
MatLine.TextSize = 10
MatLine.TextXAlignment = Enum.TextXAlignment.Left
MatLine.Parent = StatusCard

local PlayerLine = Instance.new("TextLabel")
PlayerLine.Size = UDim2.new(1, -16, 0, 20)
PlayerLine.Position = UDim2.new(0, 8, 0, 26)
PlayerLine.BackgroundTransparency = 1
PlayerLine.Text = string.format("Sea: %d | Tốc bay: %d | Vũ khí: %s", CurrentSea, Config.TweenSpeed, Config.SelectWeapon)
PlayerLine.TextColor3 = Theme.Yellow
PlayerLine.Font = Enum.Font.GothamMedium
PlayerLine.TextSize = 10
PlayerLine.TextXAlignment = Enum.TextXAlignment.Left
PlayerLine.Parent = StatusCard

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -16, 0, 20)
StatusLabel.Position = UDim2.new(0, 8, 0, 50)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Trạng thái: Đã nạp cấu hình hệ thống"
StatusLabel.TextColor3 = Theme.Green
StatusLabel.Font = Enum.Font.GothamSemibold
StatusLabel.TextSize = 10
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = StatusCard

updateStatusUI = function(msg, col)
    StatusLabel.Text = "Trạng thái: " .. tostring(msg)
    StatusLabel.TextColor3 = col or Color3.fromRGB(220, 220, 255)
end

-- Quick Toggle
createSectionHeader(homePage, "⚡ QUICK TOGGLE (BẬT / TẮT NHANH)", 2)

local QuickGrid = Instance.new("Frame")
QuickGrid.Size = UDim2.new(1, 0, 0, 80)
QuickGrid.BackgroundTransparency = 1
QuickGrid.LayoutOrder = 3
QuickGrid.Parent = homePage

local qUIGrid = Instance.new("UIGridLayout", QuickGrid)
qUIGrid.CellSize = UDim2.new(0.32, -4, 0, 36)
qUIGrid.CellPadding = UDim2.new(0.02, 0, 0, 6)

local syncToggles = {}

local function createQuickButton(title, isDefaultOn, onClick)
    local qBtn = Instance.new("TextButton", QuickGrid)
    qBtn.BackgroundColor3 = isDefaultOn and Theme.TogOn or Theme.Card
    qBtn.Text = title
    qBtn.TextColor3 = isDefaultOn and Color3.fromRGB(15, 25, 15) or Theme.Text
    qBtn.Font = Enum.Font.GothamBold
    qBtn.TextSize = 10
    addCorner(qBtn, 6)
    local qStroke = addStroke(qBtn, isDefaultOn and Theme.Green or Theme.Stroke, 1)

    local stateVal = isDefaultOn
    qBtn.MouseButton1Click:Connect(function()
        stateVal = not stateVal
        qBtn.BackgroundColor3 = stateVal and Theme.TogOn or Theme.Card
        qBtn.TextColor3 = stateVal and Color3.fromRGB(15, 25, 15) or Theme.Text
        qStroke.Color = stateVal and Theme.Green or Theme.Stroke
        onClick(stateVal)
        saveConfig()
    end)
    return function(newVal)
        stateVal = newVal
        qBtn.BackgroundColor3 = stateVal and Theme.TogOn or Theme.Card
        qBtn.TextColor3 = stateVal and Color3.fromRGB(15, 25, 15) or Theme.Text
        qStroke.Color = stateVal and Theme.Green or Theme.Stroke
    end
end

-- 6 Quick Toggles
local updateQuickFarmLevel = createQuickButton("🌾 Farm Level", Config.AutoFarmLevel, function(v)
    Config.AutoFarmLevel = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Level"
        Config.ActiveMainMode = "Level"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Bắt đầu Auto Farm Level...", Theme.Green)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Farm Level", Theme.Yellow)
    end
    if syncToggles.FarmLevel then syncToggles.FarmLevel(v) end
end)

local updateQuickMaterial = createQuickButton("🧪 Farm NL", Config.AutoMaterial, function(v)
    Config.AutoMaterial = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Material"
        Config.ActiveMainMode = "Material"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        State.SpawnPointIndex = 1
        State.ArrivedAtSpawnClock = nil
        updateStatusUI("Farm nguyên liệu: " .. tostring(Config.SelectedMaterial), Theme.Accent)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã dừng Farm nguyên liệu", Theme.Yellow)
    end
    if syncToggles.Material then syncToggles.Material(v) end
end)

local updateQuickGodhuman = createQuickButton("👑 Godhuman", Config.AutoGodhuman, function(v)
    Config.AutoGodhuman = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Godhuman"
        Config.ActiveMainMode = "Godhuman"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Chu trình Auto Godhuman...", Theme.Yellow)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã dừng Auto Godhuman", Theme.Yellow)
    end
    if syncToggles.Godhuman then syncToggles.Godhuman(v) end
end)

local updateQuickKata = createQuickButton("🍰 Farm Kata", Config.AutoFarmKata, function(v)
    Config.AutoFarmKata = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Kata"
        Config.ActiveMainMode = "Kata"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        State.SpawnPointIndex = 1
        State.ArrivedAtSpawnClock = nil
        updateStatusUI("Farm Quái Đảo Bánh & Kata...", Theme.Yellow)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã dừng Farm Kata", Theme.Yellow)
    end
    if syncToggles.Kata then syncToggles.Kata(v) end
end)

local updateQuickLeviathan = createQuickButton("🐉 Leviathan", Config.AutoFindLeviathan, function(v)
    Config.AutoFindLeviathan = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "FindLeviathan"
        Config.ActiveMainMode = "FindLeviathan"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Auto Tìm Đảo Leviathan...", Theme.Accent)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã dừng Tìm Leviathan", Theme.Yellow)
    end
    if syncToggles.Leviathan then syncToggles.Leviathan(v) end
end)

local updateQuickFastAttack = createQuickButton("⚡ Fast Attack", Config.FastAttack, function(v)
    Config.FastAttack = v
    if syncToggles.FastAttack then syncToggles.FastAttack(v) end
end)

-- Material Inventory Detail
createSectionHeader(homePage, "📦 KHO NGUYÊN LIỆU CHI TIẾT", 4)

local MatBox = Instance.new("TextLabel")
MatBox.Size = UDim2.new(1, 0, 0, 70)
MatBox.BackgroundColor3 = Theme.CardDark
MatBox.LayoutOrder = 5
MatBox.TextColor3 = Theme.Text
MatBox.Font = Enum.Font.GothamMedium
MatBox.TextSize = 10
MatBox.TextXAlignment = Enum.TextXAlignment.Left
MatBox.TextYAlignment = Enum.TextYAlignment.Top
MatBox.TextWrapped = true
MatBox.Parent = homePage
addCorner(MatBox, 8)
addPadding(MatBox, 8, 8, 10, 10)

local function refreshMatBox()
    local list = {}
    for mName, count in pairs(State.InventoryCounts) do
        if count > 0 then
            table.insert(list, string.format("%s: %d", mName, count))
        end
    end
    if #list == 0 then
        MatBox.Text = "Chưa có nguyên liệu nào trong túi đồ (hoặc chưa quét xong Inventory)."
        MatBox.TextColor3 = Theme.Muted
    else
        table.sort(list)
        MatBox.Text = table.concat(list, "  •  ")
        MatBox.TextColor3 = Theme.Text
    end
end

local updateMaterialSelectorText

updateDashboardUI = function()
    local ft = State.InventoryCounts["Fish Tail"] or 0
    local mo = State.InventoryCounts["Magma Ore"] or 0
    local md = State.InventoryCounts["Mystic Droplet"] or 0
    local ds = State.InventoryCounts["Dragon Scale"] or 0
    local selMat = Config.SelectedMaterial or "Fish Tail"
    local selCount = State.InventoryCounts[selMat] or 0
    MatLine.Text = string.format("🐟 %d/20 | 🌋 %d/20 | 💧 %d/10 | 🐉 %d/10 | 📦 %s: %d", ft, mo, md, ds, selMat, selCount)

    local charTool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    local mas = charTool and charTool:FindFirstChild("Level") and charTool.Level.Value or "--"
    local tName = charTool and charTool.Name or "Chưa cầm"
    local moon = getMoonPhaseInfo()
    PlayerLine.Text = string.format("Sea: %d | %s | Bay: %d | %s (Mas: %s)", CurrentSea, moon.ShortName, Config.TweenSpeed, tName, tostring(mas))

    if updateMaterialSelectorText then Util.safeCall("updateMaterialSelectorText", updateMaterialSelectorText) end
    if updateMoonButtonText then Util.safeCall("updateMoonButtonText", updateMoonButtonText) end
    pcall(refreshMatBox)
end

-- =========================================================================
-- TAB 2: FARMING (Cày Level, Vũ khí, Bay, Farm Nguyên liệu, Kata, Xương)
-- =========================================================================
local farmPage = pages["Farming"]

createSectionHeader(farmPage, "🎯 CÀY CẤP & NHIỆM VỤ", 1)

local _, _, setFarmLevel = createToggleRow(farmPage, "🔥 Auto Farm Level (Sea 1 / Sea 2 / Sea 3)", Config.AutoFarmLevel, 2, function(v)
    Config.AutoFarmLevel = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Level"
        Config.ActiveMainMode = "Level"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Bắt đầu Auto Farm Level...", Theme.Green)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Auto Farm Level", Theme.Yellow)
    end
    updateQuickFarmLevel(v)
end)
syncToggles.FarmLevel = setFarmLevel

createToggleRow(farmPage, "🛡️ Auto Buso Haki (Tự Bật Khi Farm)", Config.AutoBuso, 3, function(v)
    Config.AutoBuso = v
end)

local Weapons = { "Melee", "Sword", "Blox Fruit" }
local WpIdx = 1
for i, w in ipairs(Weapons) do if w == Config.SelectWeapon then WpIdx = i; break end end

local WpBtn = Instance.new("TextButton")
WpBtn.LayoutOrder = 4
WpBtn.Size = UDim2.new(1, 0, 0, 36)
WpBtn.BackgroundColor3 = Theme.Card
WpBtn.Text = "🗡️ Vũ Khí Farm: " .. tostring(Config.SelectWeapon) .. "  —  [Nhấn Để Đổi]"
WpBtn.TextColor3 = Theme.Yellow
WpBtn.Font = Enum.Font.GothamBold
WpBtn.TextSize = 11
WpBtn.Parent = farmPage
addCorner(WpBtn, 8)
addStroke(WpBtn, Theme.Stroke, 1)

WpBtn.MouseButton1Click:Connect(function()
    WpIdx = (WpIdx % #Weapons) + 1
    Config.SelectWeapon = Weapons[WpIdx]
    WpBtn.Text = "🗡️ Vũ Khí Farm: " .. Config.SelectWeapon .. "  —  [Nhấn Để Đổi]"
    updateDashboardUI()
    saveConfig()
end)

createSectionHeader(farmPage, "✈️ ĐIỀU CHỈNH TỐC ĐỘ BAY (TWEEN SPEED)", 5)

local SpeedRow = Instance.new("Frame")
SpeedRow.LayoutOrder = 6
SpeedRow.Size = UDim2.new(1, 0, 0, 36)
SpeedRow.BackgroundColor3 = Theme.Card
SpeedRow.Parent = farmPage
addCorner(SpeedRow, 8)
addStroke(SpeedRow, Theme.Accent, 1)

local SM10 = Instance.new("TextButton", SpeedRow)
SM10.Size = UDim2.new(0, 36, 1, -8)
SM10.Position = UDim2.new(0, 4, 0, 4)
SM10.BackgroundColor3 = Color3.fromRGB(45, 36, 78)
SM10.Text = "-10"
SM10.TextColor3 = Theme.Yellow
SM10.Font = Enum.Font.GothamBold
SM10.TextSize = 10
addCorner(SM10, 6)

local SM1 = Instance.new("TextButton", SpeedRow)
SM1.Size = UDim2.new(0, 32, 1, -8)
SM1.Position = UDim2.new(0, 44, 0, 4)
SM1.BackgroundColor3 = Color3.fromRGB(52, 42, 88)
SM1.Text = "-1"
SM1.TextColor3 = Theme.Yellow
SM1.Font = Enum.Font.GothamBold
SM1.TextSize = 10
addCorner(SM1, 6)

local SpeedTitle = Instance.new("TextLabel", SpeedRow)
SpeedTitle.Size = UDim2.new(1, -160, 1, 0)
SpeedTitle.Position = UDim2.new(0, 80, 0, 0)
SpeedTitle.BackgroundTransparency = 1
SpeedTitle.Text = "✈️ Tốc Độ Bay: " .. tostring(Config.TweenSpeed)
SpeedTitle.TextColor3 = Color3.fromRGB(165, 230, 255)
SpeedTitle.Font = Enum.Font.GothamBold
SpeedTitle.TextSize = 12

local SP1 = Instance.new("TextButton", SpeedRow)
SP1.Size = UDim2.new(0, 32, 1, -8)
SP1.Position = UDim2.new(1, -78, 0, 4)
SP1.BackgroundColor3 = Color3.fromRGB(52, 42, 88)
SP1.Text = "+1"
SP1.TextColor3 = Theme.Green
SP1.Font = Enum.Font.GothamBold
SP1.TextSize = 10
addCorner(SP1, 6)

local SP10 = Instance.new("TextButton", SpeedRow)
SP10.Size = UDim2.new(0, 36, 1, -8)
SP10.Position = UDim2.new(1, -42, 0, 4)
SP10.BackgroundColor3 = Color3.fromRGB(45, 36, 78)
SP10.Text = "+10"
SP10.TextColor3 = Theme.Green
SP10.Font = Enum.Font.GothamBold
SP10.TextSize = 10
addCorner(SP10, 6)

local function adjSpeed(delta)
    Config.TweenSpeed = math.max(Config.MinTweenSpeed, math.min(Config.MaxTweenSpeed, Config.TweenSpeed + delta))
    SpeedTitle.Text = "✈️ Tốc Độ Bay: " .. tostring(Config.TweenSpeed)
    updateDashboardUI()
    saveConfig()
end
SM10.MouseButton1Click:Connect(function() adjSpeed(-10) end)
SM1.MouseButton1Click:Connect(function() adjSpeed(-1) end)
SP1.MouseButton1Click:Connect(function() adjSpeed(1) end)
SP10.MouseButton1Click:Connect(function() adjSpeed(10) end)

createSectionHeader(farmPage, "🧪 FARM NGUYÊN LIỆU (MATERIALS)", 7)

local _, _, setMaterial = createToggleRow(farmPage, "🧪 Auto Farm Nguyên Liệu Đang Chọn", Config.AutoMaterial, 8, function(v)
    Config.AutoMaterial = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Material"
        Config.ActiveMainMode = "Material"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        State.SpawnPointIndex = 1
        State.ArrivedAtSpawnClock = nil
        updateStatusUI("Farm nguyên liệu: " .. tostring(Config.SelectedMaterial), Theme.Accent)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Farm nguyên liệu", Theme.Yellow)
    end
    updateQuickMaterial(v)
end)
syncToggles.Material = setMaterial

local MatNames = {
    "Fish Tail", "Magma Ore", "Mystic Droplet", "Dragon Scale",
    "Bones", "Ectoplasm", "Conjured Cocoa", "Demonic Wisp",
    "Mini Tusk", "Vampire Fang", "Radioactive Material", "Gunpowder",
    "Scrap Metal", "Leather", "Angel Wings", "Nightmare Catcher",
    "Mirror Fractal", "Meteorite", "Yeti Fur"
}
local MatIdx = 1
for i, m in ipairs(MatNames) do
    if m == Config.SelectedMaterial then MatIdx = i; break end
end
Config.SelectedMaterial = MatNames[MatIdx]

local MatRow = Instance.new("Frame")
MatRow.Size = UDim2.new(1, 0, 0, 36)
MatRow.BackgroundColor3 = Theme.Card
MatRow.LayoutOrder = 9
MatRow.Parent = farmPage
addCorner(MatRow, 8)
addStroke(MatRow, Theme.Stroke, 1)

local MatPrev = Instance.new("TextButton", MatRow)
MatPrev.Size = UDim2.new(0, 32, 1, -8)
MatPrev.Position = UDim2.new(0, 4, 0, 4)
MatPrev.BackgroundColor3 = Color3.fromRGB(50, 42, 85)
MatPrev.Text = "◀"
MatPrev.TextColor3 = Theme.Yellow
MatPrev.Font = Enum.Font.GothamBold
MatPrev.TextSize = 11
addCorner(MatPrev, 6)

local MatNext = Instance.new("TextButton", MatRow)
MatNext.Size = UDim2.new(0, 32, 1, -8)
MatNext.Position = UDim2.new(1, -36, 0, 4)
MatNext.BackgroundColor3 = Color3.fromRGB(50, 42, 85)
MatNext.Text = "▶"
MatNext.TextColor3 = Theme.Green
MatNext.Font = Enum.Font.GothamBold
MatNext.TextSize = 11
addCorner(MatNext, 6)

local MatTitle = Instance.new("TextLabel", MatRow)
MatTitle.Size = UDim2.new(1, -80, 1, 0)
MatTitle.Position = UDim2.new(0, 40, 0, 0)
MatTitle.BackgroundTransparency = 1
MatTitle.TextColor3 = Theme.Text
MatTitle.Font = Enum.Font.GothamMedium
MatTitle.TextSize = 11
MatTitle.TextTruncate = Enum.TextTruncate.AtEnd

updateMaterialSelectorText = function()
    local curMat = Config.SelectedMaterial or "Fish Tail"
    local vnName = MaterialVietnameseNames[curMat] or curMat
    local curCount = State.InventoryCounts[curMat] or 0
    MatTitle.Text = string.format("[%d/%d] %s — %s [%d]", MatIdx, #MatNames, curMat, vnName, curCount)
end
updateMaterialSelectorText()

local function stepMat(delta)
    MatIdx = ((MatIdx - 1 + delta) % #MatNames) + 1
    Config.SelectedMaterial = MatNames[MatIdx]
    State.LockedMob = nil
    State.PosMon = nil
    State.SpawnPointIndex = 1
    State.ArrivedAtSpawnClock = nil
    State.LastMobSeenClock = os.clock()
    updateDashboardUI()
    if Config.AutoMaterial and updateStatusUI then
        updateStatusUI("Đổi nguyên liệu -> " .. Config.SelectedMaterial .. " (" .. (MaterialVietnameseNames[Config.SelectedMaterial] or "") .. ")", Theme.Accent)
    end
    saveConfig()
end
MatPrev.MouseButton1Click:Connect(function() stepMat(-1) end)
MatNext.MouseButton1Click:Connect(function() stepMat(1) end)

createSectionHeader(farmPage, "🍰 ĐẢO BÁNH & KATA", 10)

local _, _, setKata = createToggleRow(farmPage, "🍰 Auto Farm Cake Queen / Kata (Quái & Boss)", Config.AutoFarmKata, 11, function(v)
    Config.AutoFarmKata = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Kata"
        Config.ActiveMainMode = "Kata"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        State.SpawnPointIndex = 1
        State.ArrivedAtSpawnClock = nil
        updateStatusUI("Bắt đầu Farm Quái Đảo Bánh & Đánh Kata...", Theme.Yellow)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Auto Farm Kata", Theme.Yellow)
    end
    updateQuickKata(v)
end)
syncToggles.Kata = setKata

createToggleRow(farmPage, "🔔 Tự Động Triệu Hồi Kata (Mở Cổng Khi Đủ 500 Quái)", Config.AutoSummonKata, 12, function(v)
    Config.AutoSummonKata = v
    if v then
        Util.safeCall("trySummonKataPortal", trySummonKataPortal, 0)
        updateStatusUI("Đã BẬT Tự Động Triệu Hồi Kata", Theme.Green)
    else
        updateStatusUI("Đã TẮT Tự Động Triệu Hồi Kata", Theme.Yellow)
    end
end)

createSectionHeader(farmPage, "🦴 FARM XƯƠNG (BONES)", 13)

createToggleRow(farmPage, "🦴 Auto Đổi Xương Ngẫu Nhiên (Random Bones)", Config.AutoRandomBones, 14, function(v)
    Config.AutoRandomBones = v
end)

-- =========================================================================
-- TAB 3: GACHA (Gacha Trái, Xương Death King, Moon Phase Event)
-- =========================================================================
local gachaPage = pages["Gacha"]

createSectionHeader(gachaPage, "🎲 GACHA TRÁI ÁC QUỶ", 1)

createActionRow(gachaPage, "🍇 Mua Random Trái Ác Quỷ (Dealer Cousin)", "Quay Trái", Color3.fromRGB(115, 60, 185), 2, function()
    Util.spawnTracked("GachaFruit", function()
        updateStatusUI("Đang mua Trái Ác Quỷ ngẫu nhiên...", Theme.Yellow)
        local ok, res = pcall(function()
            return CommF_:InvokeServer("Cousin", "Buy")
        end)
        if ok then
            updateStatusUI("Đã quay Trái Ác Quỷ! Kiểm tra túi đồ.", Theme.Green)
        else
            updateStatusUI("Lỗi hoặc chưa đủ tiền/chưa hồi chiêu!", Theme.Red)
        end
    end)
end)

createSectionHeader(gachaPage, "🦴 GACHA XƯƠNG (DEATH KING)", 3)

createActionRow(gachaPage, "🦴 Đổi Xương Nhận Quà (Death King Random)", "Đổi Quà", Color3.fromRGB(80, 50, 140), 4, function()
    Util.spawnTracked("RollBones", function()
        updateStatusUI("Đang đổi 50 Xương tại Death King...", Theme.Yellow)
        local ok, res = pcall(function()
            return CommF_:InvokeServer("Bones", "Buy", 1, 1)
        end)
        if ok then
            updateStatusUI("Đã đổi Xương thành công!", Theme.Green)
            refreshInventoryCounts(true)
        else
            updateStatusUI("Chưa đủ 50 Xương hoặc đã hết lượt đổi!", Theme.Red)
        end
    end)
end)

createSectionHeader(gachaPage, "🌕 SỰ KIỆN MẶT TRĂNG (FULL MOON EVENT)", 5)

local HopMoonBtn = Instance.new("TextButton")
HopMoonBtn.LayoutOrder = 6
HopMoonBtn.Size = UDim2.new(1, 0, 0, 38)
HopMoonBtn.BackgroundColor3 = Color3.fromRGB(36, 28, 62)
HopMoonBtn.Text = "🌕 Vào Server Gần Full Moon (4/5 - 5/5) — [Bấm Vào]"
HopMoonBtn.TextColor3 = Theme.Yellow
HopMoonBtn.Font = Enum.Font.GothamBold
HopMoonBtn.TextSize = 11
HopMoonBtn.Parent = gachaPage
addCorner(HopMoonBtn, 8)
local MoonStroke = addStroke(HopMoonBtn, Theme.Yellow, 1.3)

updateMoonButtonText = function()
    local moon = getMoonPhaseInfo()
    if Config.AutoHopNearFullMoon then
        HopMoonBtn.Text = string.format("🌕 Đang Tìm Server FM... [%s | %s] — [Bấm Dừng]", moon.ShortName, moon.TimeStr)
        HopMoonBtn.TextColor3 = Theme.Green
        MoonStroke.Color = Theme.Green
    elseif moon.IsTargetMoon then
        HopMoonBtn.Text = string.format("🌕 Server FM [%s ✅ | %s] — [Bấm Vào]", moon.ShortName, moon.TimeStr)
        HopMoonBtn.TextColor3 = Theme.Green
        MoonStroke.Color = Theme.Green
    else
        HopMoonBtn.Text = string.format("🌕 Vào Server Gần Full Moon [%s | %s] — [Bấm Vào]", moon.ShortName, moon.TimeStr)
        HopMoonBtn.TextColor3 = Theme.Yellow
        MoonStroke.Color = Theme.Yellow
    end
end
updateMoonButtonText()

HopMoonBtn.MouseButton1Click:Connect(function()
    if Config.AutoHopNearFullMoon and State.IsHopping then
        Config.AutoHopNearFullMoon = false
        State.IsHopping = false
        saveConfig()
        updateMoonButtonText()
        if updateStatusUI then
            updateStatusUI("🛑 Đã dừng tìm Server Gần Full Moon", Theme.Yellow)
        end
        return
    end

    local moon = getMoonPhaseInfo()
    if moon.IsTargetMoon then
        if not State.LastGoodMoonClickClock or (os.clock() - State.LastGoodMoonClickClock) > 6.0 then
            State.LastGoodMoonClickClock = os.clock()
            Config.AutoHopNearFullMoon = false
            saveConfig()
            updateMoonButtonText()
            if updateStatusUI then
                updateStatusUI("🎉 Server hiện tại ĐÃ LÀ " .. moon.Name .. " (" .. moon.TimeStr .. ")!", Theme.Green)
            end
            return
        end
        State.LastGoodMoonClickClock = nil
    end

    Config.AutoHopNearFullMoon = true
    State.IsHopping = false
    saveConfig()
    updateMoonButtonText()
    hopToServer("Normal", "Tìm Server Gần Full Moon (" .. moon.ShortName .. ")")
end)

-- =========================================================================
-- TAB 4: STORE (Chu trình Godhuman, Mua Võ, Kỹ Năng, Haki, Gear V4)
-- =========================================================================
local storePage = pages["Store"]

createSectionHeader(storePage, "👑 CHU TRÌNH GODHUMAN (AUTO 9 VÕ + MASTERY + NL)", 1)

local _, _, setGodhuman = createToggleRow(storePage, "👑 Auto Get Godhuman (Full 9 Võ + 400 Mas + NL)", Config.AutoGodhuman, 2, function(v)
    Config.AutoGodhuman = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "Godhuman"
        Config.ActiveMainMode = "Godhuman"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Bắt đầu chu trình Auto Godhuman...", Theme.Yellow)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Auto Godhuman", Theme.Yellow)
    end
    updateQuickGodhuman(v)
end)
syncToggles.Godhuman = setGodhuman

createSectionHeader(storePage, "🥊 MUA CÁC MÔN VÕ (FIGHTING STYLES)", 3)

local function buyStyleButton(title, remoteName, order)
    createActionRow(storePage, title, "Mua Ngay", Color3.fromRGB(55, 45, 95), order, function()
        Util.spawnTracked("BuyStyle_" .. remoteName, function()
            updateStatusUI("Đang mua " .. remoteName .. "...", Theme.Yellow)
            local ok, res = pcall(function()
                return CommF_:InvokeServer(remoteName)
            end)
            if ok then
                updateStatusUI("Đã gửi yêu cầu mua " .. remoteName .. "!", Theme.Green)
            else
                updateStatusUI("Không mua được " .. remoteName .. "! (Thiếu tiền/Mastery/NL)", Theme.Red)
            end
        end)
    end)
end

buyStyleButton("🥋 Mua Superhuman (3M Beli / 400 Mas V1)", "BuySuperhuman", 4)
buyStyleButton("🔥 Mua Death Step (2.5M Beli + 5K F / Chân Đen 400)", "BuyDeathStep", 5)
buyStyleButton("💧 Mua Sharkman Karate (2.5M Beli + 5K F / Water 400)", "BuySharkmanKarate", 6)
buyStyleButton("⚡ Mua Electric Claw (3M Beli + 5K F / Electro 400)", "BuyElectricClaw", 7)
buyStyleButton("🐉 Mua Dragon Talon (3M Beli + 5K F / Dragon 400)", "BuyDragonTalon", 8)
buyStyleButton("👑 Mua Godhuman (5M Beli + 5K F / Full 400 Mas)", "BuyGodhuman", 9)

createSectionHeader(storePage, "⚔️ NÂNG CẤP KỸ NĂNG & HAKI", 10)

createActionRow(storePage, "🛡️ Mua Haki Vũ Trang (Buso Haki - 25K Beli)", "Mua Haki", Color3.fromRGB(45, 60, 95), 11, function()
    pcall(function() CommF_:InvokeServer("BuyHaki", "Buso") end)
end)

createActionRow(storePage, "🦘 Mua Nhảy Không Trung (Geppo / Air Jump - 10K Beli)", "Mua Geppo", Color3.fromRGB(45, 60, 95), 12, function()
    pcall(function() CommF_:InvokeServer("BuyHaki", "Geppo") end)
end)

createActionRow(storePage, "⚡ Mua Lướt Nhanh (Soru / Flash Step - 100K Beli)", "Mua Soru", Color3.fromRGB(45, 60, 95), 13, function()
    pcall(function() CommF_:InvokeServer("BuyHaki", "Soru") end)
end)

createSectionHeader(storePage, "🌳 GEAR TỘC V4 (TEMPLE OF TIME)", 14)

createToggleRow(storePage, "⚙️ Auto Bay Mua Gear V4 (NPC Ancient One)", Config.AutoFlyBuyGear, 15, function(v)
    Config.AutoFlyBuyGear = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "BuyGear"
        Config.ActiveMainMode = "BuyGear"
        State.IsHopping = false
        State.IsHoveringV4Sky = false
        State.VisitedAncientOneNpc = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Bay lên NPC Đảo Great Tree -> Vào Temple Mua Gear...", Theme.Green)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã dừng Auto Bay Mua Gear", Theme.Yellow)
    end
end)

-- =========================================================================
-- TAB 5: TELEPORTS (Chuyển Sea, Hop Server, Hop Ít Người)
-- =========================================================================
local tpPage = pages["Teleports"]

createSectionHeader(tpPage, "🚢 CHUYỂN SEA", 1)

local SeaRow = Instance.new("Frame")
SeaRow.Size = UDim2.new(1, 0, 0, 38)
SeaRow.BackgroundTransparency = 1
SeaRow.LayoutOrder = 2
SeaRow.Parent = tpPage

local seaColors = { Color3.fromRGB(210, 225, 255), Color3.fromRGB(150, 220, 255), Theme.Yellow }
for si = 1, 3 do
    local sb = Instance.new("TextButton", SeaRow)
    sb.Size = UDim2.new(0.32, -2, 1, 0)
    sb.Position = UDim2.new((si - 1) * 0.34, 0, 0, 0)
    sb.BackgroundColor3 = Color3.fromRGB(36, 30, 62)
    sb.Text = "🚢 Chuyển Sea " .. si
    sb.TextColor3 = seaColors[si]
    sb.Font = Enum.Font.GothamBold
    sb.TextSize = 11
    addCorner(sb, 8)
    addStroke(sb, Theme.Stroke, 1)

    sb.MouseButton1Click:Connect(function()
        travelToSea(si)
    end)
end

createSectionHeader(tpPage, "🌐 HOP SERVER", 3)

createActionRow(tpPage, "🌐 Hop Server Ngay (Tìm Server Ngẫu Nhiên)", "Hop Ngay", Color3.fromRGB(95, 65, 190), 4, function()
    State.IsHopping = false
    hopToServer("Normal", "Hop thủ công")
end)

createActionRow(tpPage, "👥 Hop Server Ít Người (Dưới 8 Người)", "Hop Vắng", Color3.fromRGB(75, 55, 160), 5, function()
    State.IsHopping = false
    hopToServer("LowPlayers", "Hop server ít người")
end)

createActionRow(tpPage, "📶 Hop Server Ping Thấp (Ưu Tiên Ping Nhỏ)", "Hop Ping", Color3.fromRGB(65, 50, 145), 6, function()
    State.IsHopping = false
    hopToServer("LowPing", "Hop server ping thấp")
end)

createToggleRow(tpPage, "🔄 Tự Hop Server Khi Trống Bãi / Hết Boss Key", Config.AutoHopWhenEmpty, 7, function(v)
    Config.AutoHopWhenEmpty = v
end)

-- =========================================================================
-- TAB 6: MISC (Tộc V3, V4, Leviathan, Spoof Thuyền, No Stun)
-- =========================================================================
local miscPage = pages["Misc"]

createSectionHeader(miscPage, "🧬 TỘC V3 & TỘC V4", 1)

createToggleRow(miscPage, "🧬 Auto Bật Tộc V3 (Tự Kích Hoạt Kỹ Năng Tộc)", Config.AutoRaceV3, 2, function(v)
    Config.AutoRaceV3 = v
    if v then Util.safeCall("executeRaceAbilities", executeRaceAbilities) end
end)

createToggleRow(miscPage, "🔥 Auto Bật Tộc V4 (Tự Thức Tỉnh Khi Đầy Nộ)", Config.AutoRaceV4, 3, function(v)
    Config.AutoRaceV4 = v
    if v then Util.safeCall("executeRaceAbilities", executeRaceAbilities) end
end)

createToggleRow(miscPage, "🍫 Auto Train Tộc V4 (Đảo Cacao: Đầy Nộ Bay Lên)", Config.AutoTrainRaceV4, 4, function(v)
    Config.AutoTrainRaceV4 = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "TrainV4"
        Config.ActiveMainMode = "TrainV4"
        State.IsHopping = false
        State.IsHoveringV4Sky = false
        State.LockedMob = nil
        State.PosMon = nil
        State.SpawnPointIndex = 1
        State.ArrivedAtSpawnClock = nil
        updateStatusUI("Bắt đầu Auto Train Tộc V4 tại Đảo Cacao...", Color3.fromRGB(255, 165, 235))
    else
        State.IsHoveringV4Sky = false
        if not isAnyAutomationActive() then
            stopTween()
            removeAntiFall()
            updateStatusUI("Đã tạm dừng Auto Train Tộc V4", Theme.Yellow)
        end
    end
end)

createToggleRow(miscPage, "🚪 Auto Cổng Trial Tộc V4 (Vào Phòng Trial Theo Tộc)", Config.AutoTrialRaceV4, 5, function(v)
    Config.AutoTrialRaceV4 = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "TrialV4"
        Config.ActiveMainMode = "TrialV4"
        State.IsHopping = false
        State.IsHoveringV4Sky = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Bắt đầu Auto Hoàn Thành Trial Tộc V4 (" .. getPlayerRaceName() .. ")...", Theme.Yellow)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Auto Hoàn Thành Trial Tộc V4", Theme.Yellow)
    end
end)

createSectionHeader(miscPage, "🐉 LEVIATHAN & BIỂN SÂU", 6)

local _, _, setLeviathan = createToggleRow(miscPage, "🐉 Auto Tìm Đảo Leviathan (Hối Lộ Spy + Ra Tầng 6)", Config.AutoFindLeviathan, 7, function(v)
    Config.AutoFindLeviathan = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "FindLeviathan"
        Config.ActiveMainMode = "FindLeviathan"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Auto Tìm Đảo Leviathan...", Theme.Accent)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Auto Tìm Đảo Leviathan", Theme.Yellow)
    end
    updateQuickLeviathan(v)
end)
syncToggles.Leviathan = setLeviathan

createToggleRow(miscPage, "⚔️ Auto Đánh Leviathan (Chia Đủ >=15% Dame Mỗi Đuôi)", Config.AutoAttackLeviathan, 8, function(v)
    Config.AutoAttackLeviathan = v
    State.LastMobSeenClock = os.clock()
    if v then
        State.ActiveMainMode = "AttackLeviathan"
        Config.ActiveMainMode = "AttackLeviathan"
        State.IsHopping = false
        State.LockedMob = nil
        State.PosMon = nil
        updateStatusUI("Bắt đầu Auto Đánh Leviathan...", Theme.Green)
    elseif not isAnyAutomationActive() then
        stopTween()
        removeAntiFall()
        updateStatusUI("Đã tạm dừng Auto Đánh Leviathan", Theme.Yellow)
    end
end)

createToggleRow(miscPage, "👥 Giả Lập 5 Player Thuyền Beast Hunter", Config.Spoof5PlayersBoat, 9, function(v)
    Config.Spoof5PlayersBoat = v
    if v then
        local cnt = executeSpoof5PlayersBoatStep()
        updateStatusUI(string.format("Đã bật Giả Lập 5 Player (%d/5 ghế)!", math.max(cnt, 5)), Theme.Yellow)
    else
        cleanupSpoofedBoatPlayers()
        updateStatusUI("Đã tắt Giả Lập 5 Player", Theme.Yellow)
    end
end)

createSectionHeader(miscPage, "🛡️ TIỆN ÍCH AN TOÀN", 10)

createToggleRow(miscPage, "🚫 No Stun (Chống Choáng / Xóa BodyGyro / BodyPosition)", Config.NoStun, 11, function(v)
    Config.NoStun = v
end)

-- =========================================================================
-- TAB 7: SETTINGS (Cấu hình Farm, Gacha, Store, Server, Lưu Config)
-- =========================================================================
local settingsPage = pages["Settings"]

createSectionHeader(settingsPage, "🌾 CẤU HÌNH COMBAT & FARM", 1)

local _, _, setFastAttack = createToggleRow(settingsPage, "⚡ Fast Attack Đa Nhịp (Đánh Nhanh & Chống Kẹt)", Config.FastAttack, 2, function(v)
    Config.FastAttack = v
    updateQuickFastAttack(v)
end)
syncToggles.FastAttack = setFastAttack

local FaModeOrder = { "SuperFast", "HyperBurst", "SafeHuman" }
local FaModeIdx = 1
for i, m in ipairs(FaModeOrder) do
    if m == Config.FastAttackMode then FaModeIdx = i; break end
end
Config.FastAttackMode = FaModeOrder[FaModeIdx]

local FaModeBtn = Instance.new("TextButton")
FaModeBtn.LayoutOrder = 3
FaModeBtn.Size = UDim2.new(1, 0, 0, 36)
FaModeBtn.BackgroundColor3 = Theme.Card
FaModeBtn.Text = "🚀 Chế Độ Fast Attack: " .. (FastAttackModes[Config.FastAttackMode] and FastAttackModes[Config.FastAttackMode].Label or Config.FastAttackMode) .. " — [Nhấn Đổi]"
FaModeBtn.TextColor3 = Theme.Green
FaModeBtn.Font = Enum.Font.GothamBold
FaModeBtn.TextSize = 11
FaModeBtn.Parent = settingsPage
addCorner(FaModeBtn, 8)
addStroke(FaModeBtn, Theme.Stroke, 1)

FaModeBtn.MouseButton1Click:Connect(function()
    FaModeIdx = (FaModeIdx % #FaModeOrder) + 1
    Config.FastAttackMode = FaModeOrder[FaModeIdx]
    local mInfo = FastAttackModes[Config.FastAttackMode]
    FaModeBtn.Text = "🚀 Chế Độ Fast Attack: " .. (mInfo and mInfo.Label or Config.FastAttackMode) .. " — [Nhấn Đổi]"
    if updateStatusUI then
        updateStatusUI("Đã chuyển Fast Attack -> " .. (mInfo and mInfo.Label or Config.FastAttackMode), Theme.Green)
    end
    saveConfig()
end)

createToggleRow(settingsPage, "🧲 Bring Mob (Gom Quái & Khóa Mỏ Neo Phẳng)", Config.BringMob, 4, function(v)
    Config.BringMob = v
end)

createSectionHeader(settingsPage, "🌐 CẤU HÌNH SERVER & HOP", 5)

createToggleRow(settingsPage, "🌐 Tự Động Hop Khi Trống Bãi Quái", Config.AutoHopWhenEmpty, 6, function(v)
    Config.AutoHopWhenEmpty = v
end)

createSectionHeader(settingsPage, "💾 CẤU HÌNH LƯU TRỮ & HỆ THỐNG", 7)

createToggleRow(settingsPage, "💾 Auto Lưu Config (Tự Động Lưu Mọi Cài Đặt)", Config.AutoSaveConfig, 8, function(v)
    Config.AutoSaveConfig = v
    if v then saveConfig() end
end)

createActionRow(settingsPage, "💾 Lưu Cấu Hình Ngay Lập Tức", "Lưu Ngay", Color3.fromRGB(50, 110, 80), 9, function()
    local ok = saveConfig()
    if ok then
        updateStatusUI("Đã lưu cấu hình vào " .. ConfigFileName, Theme.Green)
    else
        updateStatusUI("Lưu cấu hình thất bại!", Theme.Red)
    end
end)

local KeyInfoBox = Instance.new("TextLabel")
KeyInfoBox.Size = UDim2.new(1, 0, 0, 36)
KeyInfoBox.BackgroundColor3 = Theme.CardDark
KeyInfoBox.LayoutOrder = 10
KeyInfoBox.Text = "⌨️ Phím Đóng/Mở GUI: RightControl (PC)  |  Chạm nút tròn 🌸 (Mobile)"
KeyInfoBox.TextColor3 = Theme.Dim
KeyInfoBox.Font = Enum.Font.GothamMedium
KeyInfoBox.TextSize = 10
KeyInfoBox.Parent = settingsPage
addCorner(KeyInfoBox, 8)

-- =========================================================================
-- TAB 8: ABOUT (Logo Hub, Thông tin Hub, Bản quyền)
-- =========================================================================
local aboutPage = pages["About"]

local AboutCard = Instance.new("Frame")
AboutCard.Size = UDim2.new(1, 0, 0, 160)
AboutCard.BackgroundColor3 = Theme.Card
AboutCard.LayoutOrder = 1
AboutCard.Parent = aboutPage
addCorner(AboutCard, 10)
addStroke(AboutCard, Theme.Stroke, 1)

local BigLogo = Instance.new("ImageLabel", AboutCard)
BigLogo.Size = UDim2.new(0, 60, 0, 60)
BigLogo.Position = UDim2.new(0, 16, 0, 16)
BigLogo.BackgroundColor3 = Theme.Bg
BigLogo.Image = maidAvatarAsset
BigLogo.ClipsDescendants = true
BigLogo.Active = false
addCorner(BigLogo, 30)
addStroke(BigLogo, Theme.Accent, 2)

local AboutHubName = Instance.new("TextLabel", AboutCard)
AboutHubName.Size = UDim2.new(1, -96, 0, 24)
AboutHubName.Position = UDim2.new(0, 88, 0, 18)
AboutHubName.BackgroundTransparency = 1
AboutHubName.Text = "🌸 MAID HUB V5.8"
AboutHubName.TextColor3 = Theme.Accent
AboutHubName.Font = Enum.Font.GothamBold
AboutHubName.TextSize = 16
AboutHubName.TextXAlignment = Enum.TextXAlignment.Left

local AboutSubtitle = Instance.new("TextLabel", AboutCard)
AboutSubtitle.Size = UDim2.new(1, -96, 0, 18)
AboutSubtitle.Position = UDim2.new(0, 88, 0, 42)
AboutSubtitle.BackgroundTransparency = 1
AboutSubtitle.Text = "Next-Gen Blox Fruits Automation"
AboutSubtitle.TextColor3 = Theme.Yellow
AboutSubtitle.Font = Enum.Font.GothamMedium
AboutSubtitle.TextSize = 11
AboutSubtitle.TextXAlignment = Enum.TextXAlignment.Left

local AboutDivider = Instance.new("Frame", AboutCard)
AboutDivider.Size = UDim2.new(1, -32, 0, 1)
AboutDivider.Position = UDim2.new(0, 16, 0, 88)
AboutDivider.BackgroundColor3 = Theme.Divider
AboutDivider.BorderSizePixel = 0

local AboutDesc = Instance.new("TextLabel", AboutCard)
AboutDesc.Size = UDim2.new(1, -32, 0, 56)
AboutDesc.Position = UDim2.new(0, 16, 0, 96)
AboutDesc.BackgroundTransparency = 1
AboutDesc.Text = "• Nền tảng: Real Executor (PC) & Delta X (Mobile)\n• Tương thích hoàn toàn Sea 1, Sea 2, Sea 3\n• Tự động chống kẹt, Smooth Flight & An toàn tài khoản"
AboutDesc.TextColor3 = Theme.Dim
AboutDesc.Font = Enum.Font.GothamMedium
AboutDesc.TextSize = 10
AboutDesc.TextXAlignment = Enum.TextXAlignment.Left
AboutDesc.TextYAlignment = Enum.TextYAlignment.Top

-- =========================================================================
-- FLOATING TOGGLE BUTTON (Tối ưu cho cả PC và Mobile Delta X)
-- =========================================================================
local FloatBtn = Instance.new("TextButton")
FloatBtn.Name = "MaidHubToggleButton"
FloatBtn.Size = UDim2.new(0, 50, 0, 50)
FloatBtn.Position = UDim2.new(0, 16, 0.44, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(22, 19, 38)
FloatBtn.Text = (maidAvatarAsset ~= "" and "") or "🌸"
FloatBtn.TextColor3 = Theme.Accent
FloatBtn.TextSize = 22
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.ClipsDescendants = true
FloatBtn.Active = true
FloatBtn.Parent = ScreenGui
addCorner(FloatBtn, 25)
addStroke(FloatBtn, Theme.Accent, 2)

local FloatAvatar = Instance.new("ImageLabel")
FloatAvatar.Name = "MaidAvatarCircle"
FloatAvatar.Size = UDim2.new(1, 0, 1, 0)
FloatAvatar.Position = UDim2.new(0, 0, 0, 0)
FloatAvatar.BackgroundTransparency = 1
FloatAvatar.Image = maidAvatarAsset
FloatAvatar.Active = false
FloatAvatar.Parent = FloatBtn
addCorner(FloatAvatar, 25)

local function toggleUI()
    MainFrame.Visible = not MainFrame.Visible
end

local function makeDraggable(handle, frame, isToggleBtn)
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local hasMoved = false

    table.insert(State.Connections, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            hasMoved = false
            dragStart = input.Position
            startPos = frame.Position
        end
    end))

    table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then
                hasMoved = true
            end
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))

    table.insert(State.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if isToggleBtn and (not hasMoved) then
                toggleUI()
            end
            dragging = false
        end
    end))
end

makeDraggable(TopBar, MainFrame, false)
makeDraggable(FloatBtn, FloatBtn, true)

MinBtn.MouseButton1Click:Connect(toggleUI)
FloatBtn.MouseButton1Click:Connect(toggleUI)

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Config.ToggleKey then
        toggleUI()
    end
end))

task.spawn(function()
    Util.safeCall("refreshInventoryCounts", refreshInventoryCounts)
    Util.safeCall("updateMasteryFromEquipped", updateMasteryFromEquipped)
    if updateDashboardUI then Util.safeCall("updateDashboardUI", updateDashboardUI) end
end)

end


local function cleanupMaidHub()
    State.Running = false
    Util.Shutdown = true
    Util.cancelAll()
    Util.RemoteCache = {}
    Util.RemoteCacheCount = 0
    Config.AutoFarmLevel = false
    Config.AutoGodhuman = false
    Config.AutoMaterial = false
    Config.AutoFarmKata = false
    Config.AutoSummonKata = false
    Config.AutoTrainRaceV4 = false
    Config.AutoFlyBuyGear = false
    Config.AutoTrialRaceV4 = false
    Config.AutoFindLeviathan = false
    Config.AutoAttackLeviathan = false
    Config.Spoof5PlayersBoat = false
    Util.safeCall("cleanupSpoofedBoatPlayers", cleanupSpoofedBoatPlayers)
    State.IsHoveringV4Sky = false
    stopTween()
    removeAntiFall()
    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    pcall(function()
        if ScreenGui then
            ScreenGui:Destroy()
        end
    end)
end

env.__MaidHubCleanup = cleanupMaidHub
env.__StarHubV4Cleanup = cleanupMaidHub
