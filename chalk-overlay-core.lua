-- Chalk It Up DB/WR ball assist using normal sprint/jump/dive controls.
-- Cyan: replicated route (when supplied). Yellow: movement estimate.
-- Gold: intended pass target. Pink: projected turf impact if untouched.
-- Re-run safely; getgenv().ChalkDB.status() inspects state.
-- getgenv().ChalkDB.test(12) temporarily renders a LOCAL demonstration.

local launchOptions=(...)
launchOptions=type(launchOptions)=="table" and launchOptions or {}
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local me = Players.LocalPlayer
local env = (type(getgenv) == "function" and getgenv()) or _G
if env.CIUWatch then
    env.CIUWatch.alive=false
    for _,c in ipairs(env.CIUWatch.connections or {}) do c:Disconnect() end
    env.CIUWatch=nil
end
local previousState, previousContext
if env.ChalkDB and type(env.ChalkDB.status)=="function" then
    local success,state=pcall(env.ChalkDB.status)
    if success and type(state)=="table" and not state.testing then previousState=state end
end
if env.ChalkDB and type(env.ChalkDB.context)=="function" then
    local success,state=pcall(env.ChalkDB.context)
    if success and type(state)=="table" and not state.testing then previousContext=state end
end
if env.ChalkDB and type(env.ChalkDB.unload) == "function" then
    local automatic=launchOptions.entryKind=="autoexec" or launchOptions.entryKind=="teleport"
    local destination=automatic and previousContext and previousContext.jobId~=game.JobId and game.JobId or nil
    pcall(env.ChalkDB.unload,true,destination)
end

local shared = RS:WaitForChild("Shared", 10)
local remotes = RS:WaitForChild("Remotes", 10)
assert(shared and remotes, "Chalk It Up Shared/Remotes were not found")
local fieldModule = shared:FindFirstChild("Field")
assert(fieldModule and fieldModule:IsA("ModuleScript"), "Shared.Field was not found")
local ok, Field = pcall(require, fieldModule)
assert(ok and type(Field) == "table" and type(Field.TurfY) == "number",
    "Could not read Chalk It Up field geometry")
local matchEvent, fxEvent = remotes:FindFirstChild("Match"), remotes:FindFirstChild("Fx")
assert(matchEvent and fxEvent and matchEvent:IsA("RemoteEvent") and fxEvent:IsA("RemoteEvent"),
    "Chalk It Up Match/Fx events were not found")

local api = {}
local RELEASE_VERSION="CHALK_RELEASE_VERSION"
local loadedGameId,loadedPlaceId,loadedJobId=game.GameId,game.PlaceId,game.JobId
env.ChalkDB = api
local alive, enabled = true, true
local assist,autoplay,repeatWR,idleGuard,fullplay,matchSkip,autoload,sessionContinuity
local alertSettingsFile="ciu_match_alert_settings.json"
local alertSettings={enabled=not (previousState and previousState.matchAlerts
    and previousState.matchAlerts.enabled==false)}
if type(readfile)=="function" then
    local good,saved=pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(alertSettingsFile))
    end)
    if good and type(saved)=="table" and type(saved.enabled)=="boolean" then
        alertSettings.enabled=saved.enabled
    end
end
local connections, pools, labels = {}, {}, {}
local role, phase, mode, opponent, carrier = nil, "Waiting", nil, nil, nil
local matchIdentityVerified=false
local modeSource
local rawRole, teamGeo, roster, localTeam, offense, currentLOS, solo = nil, nil, {}, nil, nil, nil, false
local function normalizeRole(value)
    if value=="WR" or value=="TWR" then return "WR" end
    if value=="DB" or value=="D" or value=="RUSH" or value=="TDB" then return "DB" end
    if value=="QB" or value=="TQB" then return "QB" end
    return value
end
if previousState then
    rawRole=previousState.rawRole or (previousState.role~="unknown" and previousState.role or nil)
    role=normalizeRole(rawRole)
    phase=previousState.phase or "Waiting"
    mode=previousState.mode~="1v1" and previousState.mode or nil
    modeSource=previousState.modeSource
    opponent=previousState.opponent~="unknown" and previousState.opponent or nil
end
local offset, route, arc, launchAt = Vector3.zero, nil, nil, nil
local snapAt,passType,preSnapEnds
local passStarted=false
if previousContext then
    rawRole=previousContext.rawRole or previousContext.role
    role=normalizeRole(rawRole)
    phase,mode=previousContext.phase or phase,previousContext.mode or mode
    modeSource=previousContext.modeSource or modeSource
    opponent=previousContext.opponent or opponent
    carrier=previousContext.carrier
    teamGeo,roster,localTeam,offense=previousContext.geo,previousContext.roster or {},
        previousContext.team,previousContext.offense
    currentLOS=previousContext.LOS
    solo=previousContext.solo==true
    offset=previousContext.offset or offset
    arc,launchAt=previousContext.arc,previousContext.launchAt
    route,snapAt,passType,preSnapEnds=previousContext.route,previousContext.snapAt,
        previousContext.passType,previousContext.preSnapEnds
    passStarted=previousContext.passStarted==true or previousContext.arc~=nil
    if previousContext.jobId==game.JobId then
        matchIdentityVerified=previousContext.matchIdentityVerified==true
    end
end
local trail, previousPosition, previousTime, smoothVelocity = {}, nil, nil, Vector3.zero
local lastError, routeKind, drawnCount = nil, "Waiting for next round", 0
local testing, testToken, restoreTest = false, 0, nil
local cyan = Color3.fromRGB(66, 230, 235)
local yellow = Color3.fromRGB(255, 208, 69)
local pink = Color3.fromRGB(255, 110, 198)
local white = Color3.fromRGB(240, 245, 255)

local folder = Instance.new("Folder")
folder.Name = "ChalkDB_LocalOverlay"
folder.Parent = workspace
local gui = Instance.new("ScreenGui")
gui.Name = "ChalkDB_Controls"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = me:WaitForChild("PlayerGui")
local bounds = Instance.new("Frame")
bounds.Name = "WindowBounds"
bounds.Size = UDim2.fromScale(1,1)
bounds.BackgroundTransparency = 1
bounds.Active = false
bounds.Parent = gui
local savedUI = previousState and previousState.ui or {}
local expandedHeight=480
local windowVisible = savedUI.visible~=false
local minimized = savedUI.minimized==true
local panel = Instance.new("Frame")
panel.Name = "Window"
panel.Size = UDim2.fromOffset(390, minimized and 36 or expandedHeight)
panel.Position = UDim2.fromOffset(110,110)
panel.BackgroundColor3 = Color3.fromRGB(16, 22, 32)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = bounds
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel
local titleBar = Instance.new("TextButton")
titleBar.Name = "DragBar"
titleBar.Size = UDim2.new(1,-118,0,36)
titleBar.BackgroundTransparency = 1
titleBar.AutoButtonColor = false
titleBar.Text = "   CHALK ASSIST · RIGHT SHIFT HIDE"
titleBar.Font = Enum.Font.GothamBold
titleBar.TextSize = 12
titleBar.TextColor3 = white
titleBar.TextXAlignment = Enum.TextXAlignment.Left
titleBar.Parent = panel
local versionBadge=Instance.new("TextLabel")
versionBadge.Name="VersionBadge"
versionBadge.Text="v"..RELEASE_VERSION
versionBadge.Position=UDim2.fromOffset(276,8)
versionBadge.Size=UDim2.fromOffset(64,20)
versionBadge.BackgroundTransparency=1
versionBadge.Font=Enum.Font.GothamBold
versionBadge.TextSize=13
versionBadge.TextColor3=Color3.fromRGB(130,213,220)
versionBadge.Parent=panel
local minimizeButton = Instance.new("TextButton")
minimizeButton.Name = "Minimize"
minimizeButton.Position = UDim2.new(1,-40,0,4)
minimizeButton.Size = UDim2.fromOffset(32,28)
minimizeButton.BackgroundColor3 = Color3.fromRGB(39,54,70)
minimizeButton.TextColor3 = white
minimizeButton.TextSize = 20
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.Text = minimized and "+" or "−"
minimizeButton.Parent = panel
local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0,6)
minimizeCorner.Parent = minimizeButton
local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(0,36)
content.Size = UDim2.fromOffset(390,expandedHeight-36)
content.BackgroundTransparency = 1
content.Visible = not minimized
content.Parent = panel
gui.Enabled = windowVisible
local text = Instance.new("TextLabel")
text.Position = UDim2.fromOffset(12, 8)
text.Size = UDim2.fromOffset(366, 96)
text.BackgroundTransparency = 1
text.Font = Enum.Font.GothamMedium
text.TextSize = 13
text.TextColor3 = white
text.TextXAlignment = Enum.TextXAlignment.Left
text.TextYAlignment = Enum.TextYAlignment.Top
text.TextWrapped = true
text.Parent = content
local function button(caption, x, width)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, 115)
    b.Size = UDim2.fromOffset(width, 26)
    b.BackgroundColor3 = Color3.fromRGB(39, 54, 70)
    b.TextColor3 = white
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.Text = caption
    b.Parent = content
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = b
    return b
end
local toggle = button("ON · B", 12, 98)
local autoButton = button("ASSIST OFF · V", 120, 122)
local unloadButton = button("UNLOAD · F8", 252, 126)
local modeButton = button("Mode: 1v1 ▾", 12, 230)
modeButton.Position = UDim2.fromOffset(12,153)
local autoplayButton = button("AUTOPLAY OFF", 252,126)
autoplayButton.Name = "AutoplayToggle"
autoplayButton.Position = UDim2.fromOffset(252,153)
local autoplayHint = Instance.new("TextLabel")
autoplayHint.Position = UDim2.fromOffset(12,184)
autoplayHint.Size = UDim2.fromOffset(366,30)
autoplayHint.BackgroundTransparency = 1
autoplayHint.TextColor3 = Color3.fromRGB(184,199,215)
autoplayHint.TextSize = 12
autoplayHint.Font = Enum.Font.Gotham
autoplayHint.TextXAlignment = Enum.TextXAlignment.Left
autoplayHint.TextWrapped = true
autoplayHint.Text = "Choose a mode for the next match."
autoplayHint.Parent = content
local repeatWRButton = button("WIN FARM OFF",12,150)
repeatWRButton.Name = "WinFarmToggle"
repeatWRButton.Position = UDim2.fromOffset(12,222)
local alertsButton = button("MATCH ALERTS ON",174,204)
alertsButton.Name = "MatchAlertsToggle"
alertsButton.Position = UDim2.fromOffset(174,222)
local repeatWRHint = Instance.new("TextLabel")
repeatWRHint.Position = UDim2.fromOffset(12,252)
repeatWRHint.Size = UDim2.fromOffset(366,24)
repeatWRHint.BackgroundTransparency = 1
repeatWRHint.TextColor3 = Color3.fromRGB(184,199,215)
repeatWRHint.TextSize = 12
repeatWRHint.Font = Enum.Font.Gotham
repeatWRHint.TextXAlignment = Enum.TextXAlignment.Left
repeatWRHint.TextWrapped = true
repeatWRHint.Text = "Return to the nearest WR pad after each match."
repeatWRHint.Parent = content
local fullplayButton = button("FULL AUTO OFF",12,366)
fullplayButton.Name = "FullPlayToggle"
fullplayButton.Position = UDim2.fromOffset(12,282)
local fullplayHint = Instance.new("TextLabel")
fullplayHint.Position = UDim2.fromOffset(12,312)
fullplayHint.Size = UDim2.fromOffset(366,26)
fullplayHint.BackgroundTransparency = 1
fullplayHint.TextColor3 = Color3.fromRGB(184,199,215)
fullplayHint.TextSize = 12
fullplayHint.Font = Enum.Font.Gotham
fullplayHint.TextXAlignment = Enum.TextXAlignment.Left
fullplayHint.TextWrapped = true
fullplayHint.Text = "1v1: routes, coverage, catches, tackles and running."
fullplayHint.Parent = content
local matchSkipLabel=Instance.new("TextLabel")
matchSkipLabel.Name="MatchSkipLabel"
matchSkipLabel.Position=UDim2.fromOffset(12,344)
matchSkipLabel.Size=UDim2.fromOffset(366,20)
matchSkipLabel.BackgroundTransparency=1
matchSkipLabel.Text="Auto-leave usernames (separate with commas)"
matchSkipLabel.TextColor3=white
matchSkipLabel.Font=Enum.Font.GothamMedium
matchSkipLabel.TextSize=12
matchSkipLabel.TextXAlignment=Enum.TextXAlignment.Left
matchSkipLabel.Parent=content
local matchSkipBox=Instance.new("TextBox")
matchSkipBox.Name="MatchSkipUsername"
matchSkipBox.Position=UDim2.fromOffset(12,369)
matchSkipBox.Size=UDim2.fromOffset(230,28)
matchSkipBox.BackgroundColor3=Color3.fromRGB(29,40,55)
matchSkipBox.TextColor3=white
matchSkipBox.PlaceholderColor3=Color3.fromRGB(139,154,175)
matchSkipBox.PlaceholderText="@name1, @name2, @name3"
matchSkipBox.Text=""
matchSkipBox.ClearTextOnFocus=false
matchSkipBox.MultiLine=false
matchSkipBox.Font=Enum.Font.Gotham
matchSkipBox.TextSize=13
matchSkipBox.TextXAlignment=Enum.TextXAlignment.Left
matchSkipBox.Parent=content
local matchSkipPadding=Instance.new("UIPadding")
matchSkipPadding.PaddingLeft=UDim.new(0,8)
matchSkipPadding.PaddingRight=UDim.new(0,8)
matchSkipPadding.Parent=matchSkipBox
local matchSkipCorner=Instance.new("UICorner")
matchSkipCorner.CornerRadius=UDim.new(0,6)
matchSkipCorner.Parent=matchSkipBox
local matchSkipButton=button("AUTO LEAVE OFF",252,126)
matchSkipButton.Name="MatchSkipToggle"
matchSkipButton.Position=UDim2.fromOffset(252,370)
local matchSkipHint=Instance.new("TextLabel")
matchSkipHint.Name="MatchSkipHint"
matchSkipHint.Position=UDim2.fromOffset(12,403)
matchSkipHint.Size=UDim2.fromOffset(366,30)
matchSkipHint.BackgroundTransparency=1
matchSkipHint.TextColor3=Color3.fromRGB(184,199,215)
matchSkipHint.Font=Enum.Font.Gotham
matchSkipHint.TextSize=12
matchSkipHint.TextXAlignment=Enum.TextXAlignment.Left
matchSkipHint.TextWrapped=true
matchSkipHint.Text="Leaves and rejoins; may count as a forfeit."
matchSkipHint.Parent=content
local matchSkipEditing=false
local matchSkipInputError
local modeMenu = Instance.new("Frame")
modeMenu.Name = "AutoplayModes"
modeMenu.Position = UDim2.fromOffset(12,184)
modeMenu.Size = UDim2.fromOffset(230,174)
modeMenu.BackgroundColor3 = Color3.fromRGB(22,31,44)
modeMenu.BorderSizePixel = 0
modeMenu.ZIndex = 20
modeMenu.Visible = false
modeMenu.Parent = content
local menuCorner = Instance.new("UICorner")
menuCorner.CornerRadius = UDim.new(0,8)
menuCorner.Parent = modeMenu

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end
local dragInput,dragStart,dragOrigin
local function cancelDrag()
    dragInput,dragStart,dragOrigin=nil,nil,nil
end
local function placeWindow(x,y)
    local size=bounds.AbsoluteSize
    if size.X<1 or size.Y<1 then return end
    local height=minimized and 36 or expandedHeight
    panel.Position=UDim2.fromOffset(
        math.clamp(x,0,math.max(0,size.X-390)),
        math.clamp(y,0,math.max(0,size.Y-height)))
end
function api.setWindowVisible(value)
    windowVisible=value==true
    cancelDrag()
    modeMenu.Visible=false
    gui.Enabled=windowVisible
    return windowVisible
end
function api.setMinimized(value)
    minimized=value==true
    cancelDrag()
    modeMenu.Visible=false
    content.Visible=not minimized
    minimizeButton.Text=minimized and "+" or "−"
    panel.Size=UDim2.fromOffset(390,minimized and 36 or expandedHeight)
    placeWindow(panel.Position.X.Offset,panel.Position.Y.Offset)
    return minimized
end
connect(minimizeButton.Activated,function() api.setMinimized(not minimized) end)
connect(titleBar.InputBegan,function(input)
    if not windowVisible then return end
    if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then
        dragInput,dragStart,dragOrigin=input,input.Position,panel.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if not dragInput or not windowVisible then return end
    local mouse=dragInput.UserInputType==Enum.UserInputType.MouseButton1
    if (mouse and input.UserInputType==Enum.UserInputType.MouseMovement)
        or (not mouse and input==dragInput) then
        local delta=input.Position-dragStart
        placeWindow(dragOrigin.X.Offset+delta.X,dragOrigin.Y.Offset+delta.Y)
    end
end)
connect(UIS.InputEnded,function(input)
    if input==dragInput or (dragInput and input.UserInputType==Enum.UserInputType.MouseButton1) then
        cancelDrag()
    end
end)
connect(UIS.WindowFocusReleased,cancelDrag)
connect(bounds:GetPropertyChangedSignal("AbsoluteSize"),function()
    cancelDrag()
    placeWindow(panel.Position.X.Offset,panel.Position.Y.Offset)
end)
task.defer(function()
    if not alive then return end
    local function savedNumber(value,fallback)
        return type(value)=="number" and value==value and math.abs(value)<100000 and value or fallback
    end
    placeWindow(savedNumber(savedUI.x,110),savedNumber(savedUI.y,110))
end)
local function updateAutoplayUI()
    if not autoplay then return end
    local state=autoplay.status()
    modeButton.Text="Mode: "..(state.label or state.selectedMode or "Choose").." ▾"
    autoplayButton.Text=state.enabled and "AUTOPLAY ON" or "AUTOPLAY OFF"
    autoplayButton.BackgroundColor3=state.enabled and Color3.fromRGB(32,93,67)
        or Color3.fromRGB(39,54,70)
    autoplayHint.Text=state.message or "Choose a mode for the next match."
end
local function updateWRRepeatUI()
    if not repeatWR then return end
    local state=repeatWR.status()
    repeatWRButton.Text=state.enabled and "WIN FARM ON" or "WIN FARM OFF"
    repeatWRButton.BackgroundColor3=state.enabled and Color3.fromRGB(32,93,67)
        or Color3.fromRGB(39,54,70)
    repeatWRHint.Text=state.message or "Return to the nearest WR pad after each match."
end
local function updateFullplayUI()
    if not fullplay then return end
    local state=fullplay.status()
    fullplayButton.Text=state.enabled and "FULL AUTO ON" or "FULL AUTO OFF"
    fullplayButton.BackgroundColor3=state.enabled and Color3.fromRGB(32,93,67)
        or Color3.fromRGB(39,54,70)
    fullplayHint.Text=state.error or state.saveError or state.message
end
local function updateMatchSkipUI()
    if not matchSkip then return end
    local state=matchSkip.status()
    matchSkipButton.Text=state.enabled and "AUTO LEAVE ON" or "AUTO LEAVE OFF"
    matchSkipButton.BackgroundColor3=state.enabled and Color3.fromRGB(32,93,67)
        or Color3.fromRGB(39,54,70)
    if not matchSkipEditing and not matchSkipBox:IsFocused() then
        local displayNames={}
        for _,name in ipairs(state.usernames or {}) do
            displayNames[#displayNames+1]="@"..name
        end
        local value=table.concat(displayNames,", ")
        if matchSkipBox.Text~=value then matchSkipBox.Text=value end
    end
    matchSkipHint.Text=matchSkipInputError or state.saveError or state.message
        or "Leaves and rejoins; may count as a forfeit."
end
function api.setMatchSkipUsernames(value)
    if not matchSkip then return false,"Auto leave is starting" end
    local ok,reason=matchSkip.setUsernames(value)
    if ok then
        matchSkipEditing=false;matchSkipInputError=nil
        matchSkip.setEditing(false)
    else matchSkipInputError=reason end
    updateMatchSkipUI()
    return ok,reason
end
api.setMatchSkipUsername=api.setMatchSkipUsernames
function api.setMatchSkip(value)
    if not matchSkip then return false,"Auto leave is starting" end
    local ok,reason=matchSkip.setEnabled(value)
    updateMatchSkipUI()
    return ok,reason
end
local function updateAlertsUI()
    alertsButton.Text=alertSettings.saveError and "ALERTS: SAVE FAILED"
        or alertSettings.enabled and "MATCH ALERTS ON" or "MATCH ALERTS OFF"
    alertsButton.BackgroundColor3=alertSettings.saveError and Color3.fromRGB(130,77,32)
        or alertSettings.enabled and Color3.fromRGB(32,93,67) or Color3.fromRGB(39,54,70)
end
function api.setMatchAlerts(value)
    local wanted=value==true
    local good,err=pcall(function()
        assert(type(writefile)=="function","Saving settings is unavailable")
        local http=game:GetService("HttpService")
        writefile(alertSettingsFile,http:JSONEncode({version=1,enabled=wanted}))
        if type(readfile)=="function" then
            local saved=http:JSONDecode(readfile(alertSettingsFile))
            assert(type(saved)=="table" and saved.enabled==wanted,"Setting could not be verified")
        end
    end)
    if good then alertSettings.enabled=wanted;alertSettings.saveError=nil
    else alertSettings.saveError=tostring(err) end
    updateAlertsUI()
    return good,alertSettings.saveError
end
updateAlertsUI()
local function buildAutoplayOptions()
    if not autoplay then return end
    local options=autoplay.modes()
    modeMenu.Size=UDim2.fromOffset(230,#options*32+12)
    for index,item in ipairs(options) do
        local key,available=item.key,item.available~=false
        local choice=Instance.new("TextButton")
        choice.Name=key
        choice.Position=UDim2.fromOffset(6,6+(index-1)*32)
        choice.Size=UDim2.fromOffset(218,30)
        choice.BackgroundColor3=Color3.fromRGB(32,45,62)
        choice.TextColor3=available and white or Color3.fromRGB(113,125,140)
        choice.Font=Enum.Font.GothamMedium
        choice.TextSize=13
        choice.Text=(item.label or key)..(available and "" or " · unavailable")
        choice.ZIndex=21
        choice.AutoButtonColor=available
        choice.Parent=modeMenu
        local c=Instance.new("UICorner")
        c.CornerRadius=UDim.new(0,5)
        c.Parent=choice
        connect(choice.MouseButton1Click,function()
            if not available then return end
            autoplay.selectMode(key)
            modeMenu.Visible=false
            updateAutoplayUI()
        end)
    end
end
local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
local function vector(v)
    return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function makePart(name)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
    p.CastShadow = false
    p.Material = Enum.Material.Neon
    p.Transparency = 1
    p.Size = Vector3.new(0.1, 0.1, 0.1)
    p.Parent = folder
    return p
end
local function pooled(group, index)
    pools[group] = pools[group] or {}
    if not pools[group][index] then
        pools[group][index] = makePart(group .. tostring(index))
    end
    return pools[group][index]
end
local function line(group, index, a, b, color, width, transparency)
    local distance = (b-a).Magnitude
    if distance < 0.03 then return end
    local p = pooled(group, index)
    p.Shape = Enum.PartType.Block
    p.Size = Vector3.new(width or 0.24, 0.09, distance)
    p.CFrame = CFrame.lookAt((a+b)*0.5, b)
    p.Color, p.Transparency = color, transparency or 0.1
    drawnCount = drawnCount + 1
end
local function disc(group, position, color, diameter)
    local p = pooled(group, 1)
    p.Shape = Enum.PartType.Cylinder
    p.Size = Vector3.new(0.08, diameter, diameter)
    p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi/2)
    p.Color, p.Transparency = color, 0.35
    drawnCount = drawnCount + 1
end
local function label(key, position, caption, color)
    if not labels[key] then
        local anchor = makePart(key .. "LabelAnchor")
        local board = Instance.new("BillboardGui")
        board.Size = UDim2.fromOffset(270, 48)
        board.StudsOffset = Vector3.new(0, key == "Target" and 5 or (key == "Ground" and 1.3 or 2), 0)
        board.AlwaysOnTop = true
        board.Adornee = anchor
        board.Parent = gui
        local t = Instance.new("TextLabel")
        t.Size = UDim2.fromScale(1, 1)
        t.BackgroundTransparency = 1
        t.Font = Enum.Font.GothamBold
        t.TextSize = 13
        t.TextStrokeTransparency = 0.15
        t.Parent = board
        labels[key] = {anchor = anchor, board = board, text = t}
    end
    local l = labels[key]
    l.anchor.Position = position
    l.board.Enabled = true
    l.text.Text, l.text.TextColor3 = caption, color
end
local function hide()
    drawnCount = 0
    for _, pool in pairs(pools) do
        for _, p in ipairs(pool) do p.Transparency = 1 end
    end
    for _, l in pairs(labels) do l.board.Enabled = false end
end
local function clearMotion()
    trail, previousPosition, previousTime, smoothVelocity = {}, nil, nil, Vector3.zero
end
local function characterOf(value)
    if typeof(value) == "Instance" then
        if value:IsA("Player") then return value.Character end
        if value:IsA("Model") then return value end
    elseif type(value) == "number" then
        local p = Players:GetPlayerByUserId(value)
        return p and p.Character
    elseif type(value) == "string" then
        local p = Players:FindFirstChild(value)
        return p and p.Character
    end
end
-- MODE_POLICY_BEGIN: pure bootstrap rules, exercised by the mode regression test.
local function validGeo(value)
    local function coordinate(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
    return type(value)=="table" and coordinate(value.MinX) and coordinate(value.MaxX)
        and coordinate(value.BackZ) and coordinate(value.EndZ) and coordinate(value.TurfY)
        and value.MinX<value.MaxX and value.BackZ<value.EndZ
end
local function selectBootstrapMode(nativePhase,nativeRole,trustedMode,trustedSource)
    if nativePhase=="Lobby" then return nil,"lobby" end
    if nativeRole=="TWR" or nativeRole=="TDB" or nativeRole=="TQB" then return "Team","native-role" end
    -- TeamClient uses plain WR/DB in PreSnap and RAC, but T-prefixed roles
    -- throughout its Live phase. Only Live disambiguates those plain roles.
    if nativePhase=="Live" and (nativeRole=="WR" or nativeRole=="DB") then
        return "1v1","native-role"
    end
    if trustedMode=="Team" or trustedMode=="1v1" then return trustedMode,trustedSource or "reload" end
    return nil,"unconfirmed"
end
local function selectTeamGeometry(current,values,baseField)
    if current~=baseField and validGeo(current) then return current end
    for _,value in pairs(values or {}) do
        if value~=baseField and validGeo(value) then return value end
    end
end
-- MODE_POLICY_END
local function turfY()
    return mode=="Team" and validGeo(teamGeo) and teamGeo.TurfY or Field.TurfY
end
local function enemyCharacters(receiversOnly)
    local result,seen={},{}
    if mode=="Team" then
        if localTeam==nil then return result end
        for _,entry in pairs(roster) do
            if type(entry)=="table" and entry.Team~=nil and entry.Team~=localTeam
                and (not receiversOnly or normalizeRole(entry.Role)=="WR") then
                local ch=characterOf(entry.Char)
                if ch and ch~=me.Character and not seen[ch] then
                    seen[ch]=true
                    table.insert(result,ch)
                end
            end
        end
    else
        local ch=characterOf(opponent)
        if ch and ch~=me.Character then table.insert(result,ch) end
    end
    return result
end
local function chooseTeamReceiver()
    if mode~="Team" or role~="DB" then return end
    local candidates=enemyCharacters(true)
    local current=characterOf(opponent)
    for _,ch in ipairs(candidates) do if ch==current then return end end
    if candidates[1] then opponent=candidates[1]; clearMotion() end
end
local function carrierContext()
    if phase~="Live" and phase~="Run" and phase~="RAC" then return nil,false,nil end
    local ch=characterOf(carrier)
    if not ch or not ch.Parent then return nil,false,nil end
    if mode=="Team" then
        for _,entry in pairs(roster) do
            if type(entry)=="table" and characterOf(entry.Char)==ch then
                local enemy=ch~=me.Character and localTeam~=nil and entry.Team~=nil
                    and entry.Team~=localTeam
                return ch,enemy,entry.Role
            end
        end
        -- A holder without a known team is not an authorized tackle target.
        return ch,false,nil
    end
    local enemy=phase=="RAC" and role=="DB" and ch~=me.Character
        and ch==characterOf(opponent)
    return ch,enemy,"WR"
end
local function onMatch(data)
    if type(data) ~= "table" then return end
    local identityMode=mode=="Team" and "Team" or "1v1"
    local identityTeam=localTeam
    if data.Phase=="Pick" or data.Phase=="PreSnap" then matchIdentityVerified=false end
    if data.Role ~= nil then rawRole=data.Role; role=normalizeRole(rawRole) end
    if data.Mode ~= nil then mode = data.Mode;modeSource="match" end
    if validGeo(data.Geo) then teamGeo=data.Geo; mode="Team";modeSource="match" end
    if data.Team~=nil or data.TeamMode~=nil then mode="Team";modeSource="match" end
    if type(data.Roster)=="table" then roster=data.Roster end
    if data.Team~=nil then localTeam=data.Team end
    if data.Offense~=nil then offense=data.Offense end
    if data.Solo~=nil then solo=data.Solo==true end
    if finite(data.LOS) then currentLOS=data.LOS end
    if data.Opp ~= nil then opponent = data.Opp; clearMotion() end
    if vector(data.Offset) then offset = data.Offset end
    if data.Phase then phase = data.Phase end
    if phase == "PreSnap" or phase == "Pick" then
        route, arc, launchAt = nil, nil, nil
        snapAt,passType=nil,nil
        passStarted=false
        preSnapEnds=finite(data.EndsAt) and data.EndsAt or workspace:GetServerTimeNow()
        clearMotion()
        if data.Mode==nil and data.Team==nil and data.TeamMode==nil
            and vector(data.Offset) and not validGeo(data.Geo) then
            mode,teamGeo,roster,localTeam,offense=nil,nil,{},nil,nil
            modeSource="match"
        end
    elseif phase=="Hike" and type(data.Routes)=="table" then
        local target=role=="WR" and me.Character or characterOf(opponent)
        for _,entry in pairs(data.Routes) do
            if type(entry)=="table" and characterOf(entry.Char)==target
                and type(entry.Points)=="table" then route=entry.Points; break end
        end
    elseif phase == "Live" then
        if type(data.Points)=="table" then route=data.Points
        elseif mode~="Team" then route=nil end
    elseif phase == "RAC" or phase=="Run" or phase == "Result" or phase == "Lobby" then
        route, arc, launchAt = nil, nil, nil
        clearMotion()
        if phase == "Lobby" then
            snapAt,passType,preSnapEnds=nil,nil,nil
            passStarted=false
            role, rawRole, opponent, mode = nil, nil, nil, nil
            modeSource="lobby"
            teamGeo,roster,localTeam,offense,currentLOS=nil,{},nil,nil,nil
            solo=false
            offset = Vector3.zero
        end
    end
    chooseTeamReceiver()
    if identityMode~=(mode=="Team" and "Team" or "1v1") or identityTeam~=localTeam then
        matchIdentityVerified=false
    end
    if mode=="Team" then
        if type(data.Roster)=="table" and data.Team~=nil then
            matchIdentityVerified=false
            for _,entry in pairs(data.Roster) do
                if type(entry)=="table" and entry.Team==data.Team
                    and characterOf(entry.Char)==me.Character and me.Character~=nil then
                    matchIdentityVerified=true;break
                end
            end
        end
    elseif data.Opp~=nil then
        matchIdentityVerified=characterOf(data.Opp)~=nil
    end
    if phase=="Lobby" or data.MatchOver==true then matchIdentityVerified=false end
    if finite(data.SnapAt) then snapAt=data.SnapAt end
    if data.Pass=="Bullet" or data.Pass=="Floater" then passType=data.Pass end
    if phase=="Pick" or phase=="PreSnap" or phase=="Hike" or phase=="Result" or phase=="Lobby" then
        carrier=nil
    elseif data.Carrier~=nil then
        carrier=characterOf(data.Carrier)
    elseif mode~="Team" and phase=="RAC" then
        carrier=role=="DB" and characterOf(opponent) or (role=="WR" and me.Character or nil)
    end
    if assist and assist.onMatch then assist.onMatch(data) end
    if repeatWR then repeatWR.onMatch(data) end
    if fullplay then fullplay.onMatch(data) end
    if sessionContinuity then sessionContinuity.onMatch(data) end
end
local function onFx(data)
    if type(data) ~= "table" then return end
    if assist then assist.onFx(data) end
    if data.Type == "Throw" then
        if (not role or data.Team) and api.syncFromGame then api.syncFromGame() end
        if data.Team then
            if mode~="Team" then matchIdentityVerified=false end
            mode="Team";modeSource="throw"
        end
        -- The quarterback is no longer holding the ball once a pass is thrown.
        carrier=nil
        local a = data.Arc
        if type(a) == "table" and vector(a.P0) and vector(a.P1)
            and finite(a.Flight) and a.Flight > 0 and finite(a.Apex)
            and a.Apex >= 0 and finite(data.LaunchAt) then
            arc = {P0=a.P0, P1=a.P1, Flight=a.Flight, Apex=a.Apex}
            launchAt = data.LaunchAt
            passStarted=true
            if role then phase="Live" end
        end
    elseif data.Type=="TeamRoute" and type(data.Points)=="table" then
        local target=role=="WR" and me.Character or characterOf(opponent)
        if target and characterOf(data.Char)==target then route=data.Points end
    elseif data.Type == "BallStop" or data.Type == "BallResult" then
        arc, launchAt = nil, nil
        if data.Type == "BallResult" then
            route=nil
            if data.Result=="Catch" or data.Result=="Intercepted" then
                carrier=characterOf(data.Catcher)
                if not carrier and mode~="Team" then
                    local localCatch=(data.Result=="Catch" and role=="WR")
                        or (data.Result=="Intercepted" and role=="DB")
                    carrier=localCatch and me.Character or characterOf(opponent)
                end
            else carrier=nil end
        end
    end
    if fullplay and fullplay.onFx then fullplay.onFx(data) end
end
local function arcPosition(a, u)
    return a.P0 + (a.P1-a.P0)*u + Vector3.new(0, 4*a.Apex*u*(1-u), 0)
end
local function turfIntersection(a)
    local h = a.P0.Y-turfY()
    local dy = a.P1.Y-a.P0.Y
    if a.Apex < 0.00001 then
        if dy >= -0.00001 then return nil end
        local u = -h/dy
        return u > 0 and u or nil
    end
    local b = dy + 4*a.Apex
    local d = b*b + 16*a.Apex*h
    if d < 0 then return nil end
    local u = (b+math.sqrt(d))/(8*a.Apex)
    return u > 0 and u or nil
end

local function render()
    hide()
    local active = enabled and (role == "DB" or role == "WR")
        and (phase == "PreSnap" or phase == "Hike" or phase == "Live" or phase == "RAC" or phase=="Run")
    routeKind = "Waiting for next round"
    if role and role ~= "DB" and role ~= "WR" then routeKind = "Waiting for a receiver or defender turn"
    elseif not enabled then routeKind = "Paused"
    elseif phase == "Result" then routeKind = "Play finished" end
    if active then
        local groundY = turfY() + 0.13
        local ch = characterOf(opponent)
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local points = {}
        if route then
            for i = 1, math.min(#route, 200) do
                local p = route[i]
                if typeof(p) == "Vector2" and finite(p.X) and finite(p.Y) then
                    table.insert(points,mode=="Team" and Vector3.new(p.X,groundY,p.Y)
                        or Field.ToWorld(p,0.13)+offset)
                end
            end
        end
        if #points >= 2 then
            routeKind = role=="WR" and "Cyan: your selected route" or "Cyan: supplied WR route"
            for i = 2, #points do line("Route", i-1, points[i-1], points[i], cyan, 0.35) end
            label("Route", points[1],role=="WR" and "YOUR SELECTED ROUTE" or "SUPPLIED WR ROUTE",cyan)
        elseif role=="WR" then
            routeKind=(phase=="RAC" or phase=="Run") and "Running play · controls returned to you" or "WR · waiting for your route/throw"
        elseif root and root:IsA("BasePart") then
            routeKind = (phase == "RAC" or phase=="Run") and "After catch · yellow estimate · cyan trail"
                or "Yellow: movement estimate · cyan: trail"
            local now, position = os.clock(), root.Position
            local flat = Vector3.new(position.X, groundY, position.Z)
            if previousPosition and previousTime then
                local dt = now-previousTime
                if dt > 0.02 and dt < 0.5 then
                    local v = (position-previousPosition)/dt
                    v = Vector3.new(v.X, 0, v.Z)
                    if v.Magnitude < 100 then smoothVelocity = smoothVelocity:Lerp(v, 0.45)
                    else clearMotion() end
                end
            end
            previousPosition, previousTime = position, now
            table.insert(trail, {p=flat, t=now})
            while #trail > 18 or (#trail > 0 and now-trail[1].t > 1.4) do table.remove(trail, 1) end
            for i=2,#trail do
                line("Trail", i-1, trail[i-1].p, trail[i].p, cyan, 0.22, 0.45)
            end
            for i=1,8 do
                local ta, tb = (i-1)/8, (i-0.35)/8
                line("Estimate", i, flat+smoothVelocity*ta, flat+smoothVelocity*tb, yellow, 0.28)
            end
            label("Route", flat+smoothVelocity, "WR MOVEMENT ESTIMATE · 1s", yellow)
        else
            routeKind = "Waiting for WR/route data from next round"
        end
        if arc and launchAt then
            local now = workspace:GetServerTimeNow()
            local u = (now-launchAt)/arc.Flight
            local uGround = turfIntersection(arc)
            local endU = uGround or 1
            if u <= endU + 0.25 then
                local target = Vector3.new(arc.P1.X, groundY, arc.P1.Z)
                disc("Target", target, yellow, 3)
                local remaining = launchAt+arc.Flight-now
                label("Target", target, remaining >= 0
                    and string.format("PASS TARGET · %.1fs", remaining)
                    or "PASS TARGET · passed", yellow)
                local firstU = math.max(0, u)
                if firstU < endU then
                    for i=1,24 do
                        local a = firstU+(endU-firstU)*(i-1)/24
                        local b = firstU+(endU-firstU)*i/24
                        line("Arc", i, arcPosition(arc,a), arcPosition(arc,b), yellow, 0.12, 0.35)
                    end
                end
                if uGround then
                    local impact = arcPosition(arc, uGround)
                    impact = Vector3.new(impact.X, groundY+0.05, impact.Z)
                    disc("Ground", impact, pink, 2)
                    label("Ground", impact, string.format("TURF IF UNTOUCHED · %.1fs",
                        math.max(0, launchAt+arc.Flight*uGround-now)), pink)
                end
            else arc, launchAt = nil, nil end
        end
    end
    local autoStatus = assist and assist.status()
    local contact = assist and assist.target()
    if active and contact then
        local green = Color3.fromRGB(110,255,150)
        disc("Intercept",Vector3.new(contact.X,turfY()+0.25,contact.Z),green,2)
        label("Intercept",contact,role=="WR" and "CATCH AIM" or "INTERCEPTION AIM",green)
    end
    text.Text = string.format("CHALK ASSIST%s · %s · %s\n%s\n%s\n%s",
        testing and " [LOCAL TEST]" or "", role or "role unknown", phase,
        routeKind, lastError and ("Error: "..lastError) or "Gold: pass target · pink: turf if untouched",
        autoStatus and (autoStatus.error or autoStatus.message) or "Auto starting")
    if autoStatus then autoButton.Text=autoStatus.enabled and "ASSIST ON · V" or "ASSIST OFF · V" end
    updateAutoplayUI()
    updateWRRepeatUI()
    updateFullplayUI()
    updateMatchSkipUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
end

function api.unload(preserveAutoplay,automaticDestinationJob)
    if not alive then return end
    if sessionContinuity then sessionContinuity.unload(automaticDestinationJob) end
    cancelDrag()
    if autoload then autoload.unload(preserveAutoplay) end
    if matchSkip then
        if matchSkipEditing then api.setMatchSkipUsername(matchSkipBox.Text) end
        matchSkip.unload()
    end
    if fullplay then fullplay.unload() end
    if idleGuard then idleGuard.unload() end
    if repeatWR then repeatWR.unload() end
    if autoplay then
        if preserveAutoplay~=true then autoplay.setEnabled(false) end
        autoplay.unload()
    end
    alive = false
    if assist then assist.unload() end
    testToken = testToken+1
    for _, c in ipairs(connections) do c:Disconnect() end
    folder:Destroy()
    gui:Destroy()
    if env.ChalkDB == api then env.ChalkDB = nil end
end
function api.setEnabled(value)
    enabled = value == true
    if sessionContinuity then sessionContinuity.onChoice("master",enabled) end
    toggle.Text = enabled and "ON · B" or "OFF · B"
    if not enabled then
        hide()
        if repeatWR then repeatWR.release() end
    end
    if api.updateIdleGuard then api.updateIdleGuard() end
end
function api.status()
    local ch = characterOf(opponent)
    local holder,isEnemy,holderRole=carrierContext()
    return {product="deterministic",version=RELEASE_VERSION,buildId="CHALK_BUNDLED_BUILD_ID",policyMode="deterministic", enabled=enabled, role=role or "unknown",rawRole=rawRole or "unknown", phase=phase,
        ui={visible=windowVisible,minimized=minimized,x=panel.Position.X.Offset,y=panel.Position.Y.Offset},
        matchAlerts={enabled=alertSettings.enabled,saveError=alertSettings.saveError},
        idleGuard=idleGuard and idleGuard.status() or nil,
        fullplay=fullplay and fullplay.status() or nil,
        matchSkip=matchSkip and matchSkip.status() or nil,
        autoload=autoload and autoload.status() or nil,
        sessionContinuity=sessionContinuity and sessionContinuity.status() or nil,
        matchIdentityVerified=matchIdentityVerified,
        mode=mode or "1v1",modeSource=modeSource, opponent=ch and ch.Name or "unknown",
        team=localTeam,offense=offense,teamGeometry=validGeo(teamGeo),
        teamMode=mode=="Team" and teamGeo and teamGeo.Mode or nil,
        carrier=holder and holder.Name or nil,enemyCarrier=isEnemy,defending=isEnemy,carrierRole=holderRole,
        routePoints=route and #route or 0, routeStatus=routeKind,
        ballActive=arc ~= nil, visibleParts=drawnCount, testing=testing, error=lastError,
        auto=assist and assist.status() or nil,autoplay=autoplay and autoplay.status() or nil,
        wrRepeat=repeatWR and repeatWR.status() or nil}
end
function api.context()
    local holder,isEnemy,holderRole=carrierContext()
    return {role=role,phase=phase,mode=mode,modeSource=modeSource,arc=arc,launchAt=launchAt,
        route=route,snapAt=snapAt,passType=passType,preSnapEnds=preSnapEnds,
        roundKey=tostring(preSnapEnds or "current"),
        catchIntent=fullplay and fullplay.catchIntent and fullplay.catchIntent() or nil,
        -- Preserve the coverage reserve before the throw, then spend it in
        -- pursuit of the observed live ball. No forecast/route alone unlocks it.
        playBudget=fullplay and fullplay.movementBudget and fullplay.movementBudget(arc~=nil and phase=="Live") or nil,
        passStarted=passStarted,
        enabled=enabled,testing=testing,alive=alive,offset=offset,
        matchIdentityVerified=matchIdentityVerified,
        opponent=characterOf(opponent),geo=teamGeo,opponents=enemyCharacters(false),
        team=localTeam,rawRole=rawRole,roster=roster,offense=offense,LOS=currentLOS,solo=solo,
        carrier=holder,enemyCarrier=isEnemy,defending=isEnemy,carrierRole=holderRole,
        teamMode=mode=="Team" and teamGeo and teamGeo.Mode or nil,
        gameId=loadedGameId,placeId=loadedPlaceId,jobId=loadedJobId}
end
function api.syncFromGame()
    if testing then return api.status() end
    local identityOpponent=characterOf(opponent)
    local identityMode=mode=="Team" and "Team" or "1v1"
    local identityTeam=localTeam
    local getUps=(debug and debug.getupvalues) or getupvalues
    if type(getUps)~="function" then return api.status() end
    local scripts=me:FindFirstChild("PlayerScripts")
    local gameScripts=scripts and scripts:FindFirstChild("Game")
    local movesScript=gameScripts and gameScripts:FindFirstChild("Moves")
    if not movesScript then return api.status() end
    local good,Moves=pcall(require,movesScript)
    if not good or type(Moves)~="table" then return api.status() end
    local function upvalues(fn)
        if type(fn)~="function" then return {} end
        local success,values=pcall(getUps,fn)
        return success and type(values)=="table" and values or {}
    end
    local phases={Lobby=true,Pick=true,PreSnap=true,Hike=true,Live=true,RAC=true,Run=true,Result=true}
    local roles={WR=true,DB=true,QB=true,TWR=true,TDB=true,TQB=true,RUSH=true,O=true,D=true}
    local function selectTeamRole(values,native)
        local candidates={}
        local expected=normalizeRole(native)
        for key,value in pairs(values) do
            if type(value)=="string" and roles[value]
                and (not native or normalizeRole(value)==expected) then
                table.insert(candidates,key)
            end
        end
        -- OnMatch captures both its current role and a later pending-live role.
        -- Prefer native Moves' role, then the earlier current-role upvalue;
        -- table iteration order must never let the pending role win by chance.
        table.sort(candidates,function(a,b)
            if type(a)=="number" and type(b)=="number" then return a<b end
            if type(a)=="number" then return true end
            if type(b)=="number" then return false end
            return tostring(a)<tostring(b)
        end)
        return candidates[1] and values[candidates[1]] or nil
    end
    local nativeRole,nativePhase
    for _,value in pairs(upvalues(Moves.SetPhase)) do
        if type(value)=="string" then
            if phases[value] then nativePhase=value end
            if roles[value] then nativeRole=value end
        end
    end
    if nativePhase then phase=nativePhase end
    if nativeRole then rawRole=nativeRole; role=normalizeRole(rawRole) end
    for _,value in pairs(upvalues(Moves.SetOpponent)) do
        local ch=characterOf(value)
        if ch and ch~=me.Character then opponent=ch; break end
    end
    local trustedMode
    if modeSource and modeSource~="unconfirmed" and modeSource~="lobby" then
        trustedMode=mode=="Team" and "Team" or "1v1"
    elseif mode=="Team" and localTeam~=nil then
        trustedMode="Team" -- Legacy reload context backed by an observed team packet.
    elseif mode~="Team" and (previousContext or previousState) and phase~="Waiting" then
        trustedMode="1v1"
    end
    mode,modeSource=selectBootstrapMode(nativePhase or phase,nativeRole,trustedMode,modeSource)
    local teamScript=gameScripts:FindFirstChild("TeamClient")
    local detectedGeo,detectedRole
    if mode=="Team" and teamScript then
        local success,TeamClient=pcall(require,teamScript)
        if success and type(TeamClient)=="table" then
            local values=upvalues(TeamClient.OnMatch)
            detectedRole=selectTeamRole(values,nativeRole)
            detectedGeo=selectTeamGeometry(teamGeo,values,Field)
        end
    end
    if mode=="Team" then
        teamGeo=detectedGeo or (teamGeo~=Field and validGeo(teamGeo) and teamGeo or nil)
        if detectedRole then rawRole=detectedRole; role=normalizeRole(rawRole) end
        if role=="WR" or role=="QB" or rawRole=="O" then offense=true
        elseif role=="DB" then offense=false end
        if phase=="RAC" then phase="Run" end
        chooseTeamReceiver()
    elseif phase=="Lobby" then
        role,rawRole,mode,opponent=nil,nil,nil,nil
        teamGeo,roster,localTeam,offense,currentLOS=nil,{},nil,nil,nil
        arc,launchAt,route=nil,nil,nil
        carrier=nil
    else
        -- Stale/default TeamClient geometry must not affect 1v1 bounds or
        -- hide the 1v1 opponent behind an empty team roster after a reload.
        teamGeo,roster,localTeam,offense,currentLOS=nil,{},nil,nil,nil
        local root=me.Character and me.Character:FindFirstChild("HumanoidRootPart")
        local fields=workspace:FindFirstChild("Fields")
        local best=math.huge
        if root and fields then
            for _,f in ipairs(fields:GetChildren()) do
                if (f:GetAttribute("Mode")=="1v1" or f:GetAttribute("Mode")==nil)
                    and f:FindFirstChild("Endzone") then
                    local success,delta=pcall(Field.OffsetOf,f)
                    if success and vector(delta) then
                        local x=math.clamp(root.Position.X,Field.MinX+delta.X,Field.MaxX+delta.X)
                        local z=math.clamp(root.Position.Z,Field.BackZ+delta.Z,Field.EndZ+delta.Z)
                        local distance=(Vector3.new(x,root.Position.Y,z)-root.Position).Magnitude
                        if distance<best then best=distance; offset=delta end
                    end
                end
            end
        end
    end
    if mode~="Team" and phase=="RAC" then
        carrier=role=="DB" and characterOf(opponent) or (role=="WR" and me.Character or nil)
    end
    if phase=="Lobby" or identityOpponent~=characterOf(opponent)
        or identityMode~=(mode=="Team" and "Team" or "1v1") or identityTeam~=localTeam then
        matchIdentityVerified=false
    end
    return api.status()
end
function api.setAuto(value)
    if assist then assist.setEnabled(value) end
    if sessionContinuity then sessionContinuity.onChoice("assist",value==true) end
    if api.updateIdleGuard then api.updateIdleGuard() end
end
function api.setFullplay(value)
    if not fullplay then return false,"Full auto is starting" end
    if value==true then
        api.setEnabled(true)
        if assist then assist.setEnabled(true) end
    end
    local ok,reason=fullplay.setEnabled(value)
    if sessionContinuity then sessionContinuity.onChoice("fullplay",value==true and ok==true) end
    updateFullplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.setAutoplay(value)
    if not autoplay then return false,"Autoplay is starting" end
    if value==true and repeatWR then repeatWR.setEnabled(false);updateWRRepeatUI() end
    local ok,reason=autoplay.setEnabled(value)
    if sessionContinuity then sessionContinuity.onChoice("autoplay",ok==true) end
    updateAutoplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.setWRRepeat(value)
    if not repeatWR then return false,"WR repeat is starting" end
    local ok,reason=repeatWR.setEnabled(value)
    updateWRRepeatUI()
    updateAutoplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.setAutoplayMode(value)
    if not autoplay then return false,"Autoplay is starting" end
    local ok,reason=autoplay.selectMode(value)
    if sessionContinuity then sessionContinuity.onChoice("mode",ok==true) end
    updateAutoplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.autoplayModes() return autoplay and autoplay.modes() or {} end
function api.initializeSessionContinuity(createSession)
    local function modeAvailable(key)
        for _,entry in ipairs(api.autoplayModes()) do
            if entry.key==key then return entry.available==true end
        end
        return false
    end
    sessionContinuity=createSession({entry=launchOptions,modeAvailable=modeAvailable,
        snapshot=function()
            local a=autoplay and autoplay.status() or {}
            return {alive=alive,enabled=enabled,testing=testing,
                fullAuto=fullplay and fullplay.status().enabled==true
                    and assist and assist.status().enabled==true,
                autoplay=a.enabled==true,selectedMode=a.selectedMode,
                modeAvailable=modeAvailable(a.selectedMode),
                matchServer=workspace:GetAttribute("MatchServer")==true}
        end,
        apply=function(fullAuto,selectedMode)
            if not api.setAutoplayMode(selectedMode) then return false end
            if fullAuto and not api.setFullplay(true) then return false end
            return api.setAutoplay(true)==true
        end,
        stop=function() api.setFullplay(false);api.setAuto(false);api.setAutoplay(false) end})
    if launchOptions.entryKind=="teleport" then
        sessionContinuity.resume(launchOptions.teleportSourceJob)
    end
end
function api.resumeTeleportSession(sourceJob)
    return sessionContinuity and sessionContinuity.resume(sourceJob) or false
end
function api.cancelTeleportSession(reason)
    if sessionContinuity then sessionContinuity.cancel(reason) end
end
function api.history() return assist and assist.history() or {} end
local function finishTest()
    if not restoreTest then return end
    local s = restoreTest
    role, phase, mode, opponent, offset, route, arc, launchAt =
        s.role, s.phase, s.mode, s.opponent, s.offset, s.route, s.arc, s.launchAt
    modeSource=s.modeSource
    rawRole,teamGeo,roster,localTeam,offense,currentLOS=
        s.rawRole,s.geo,s.roster or {},s.team,s.offense,s.LOS
    carrier=s.carrier
    snapAt,passType,preSnapEnds,passStarted=s.snapAt,s.passType,s.preSnapEnds,s.passStarted==true
    api.setEnabled(s.enabled)
    restoreTest, testing = nil, false
    testToken = testToken+1
    clearMotion()
end
function api.test(seconds)
    finishTest()
    local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    assert(root, "Spawn your character before testing")
    restoreTest = {role=role,phase=phase,mode=mode,modeSource=modeSource,opponent=opponent,offset=offset,
        route=route,arc=arc,launchAt=launchAt,enabled=enabled,
        rawRole=rawRole,geo=teamGeo,roster=roster,team=localTeam,offense=offense,LOS=currentLOS,
        snapAt=snapAt,passType=passType,preSnapEnds=preSnapEnds,passStarted=passStarted,
        carrier=carrier}
    testing, testToken = true, testToken+1
    api.setEnabled(true)
    local token = testToken
    local origin = root.Position
    local duration = math.clamp(tonumber(seconds) or 12, 2, 20)
    onMatch({Phase="PreSnap",Role="DB",Opp=me,Offset=Vector3.zero})
    onMatch({Phase="Live",Points={Vector2.new(origin.X,origin.Z),
        Vector2.new(origin.X+8,origin.Z+10),Vector2.new(origin.X+18,origin.Z+10)}})
    onFx({Type="Throw",Arc={P0=Vector3.new(origin.X,Field.TurfY+6,origin.Z),
        P1=Vector3.new(origin.X+18,Field.TurfY+3.5,origin.Z+10),Flight=duration,Apex=8},
        LaunchAt=workspace:GetServerTimeNow()})
    task.delay(duration+0.5,function()
        if alive and token==testToken then finishTest() end
    end)
    return "Local visual test started; live state restores automatically."
end
connect(toggle.MouseButton1Click,function() api.setEnabled(not enabled) end)
connect(autoButton.MouseButton1Click,function()
    if assist then api.setAuto(not assist.status().enabled) end
end)
connect(modeButton.MouseButton1Click,function() modeMenu.Visible=not modeMenu.Visible end)
connect(autoplayButton.MouseButton1Click,function()
    if autoplay then api.setAutoplay(not autoplay.status().enabled) end
end)
connect(repeatWRButton.MouseButton1Click,function()
    if repeatWR then api.setWRRepeat(not repeatWR.status().enabled) end
end)
connect(alertsButton.MouseButton1Click,function() api.setMatchAlerts(not alertSettings.enabled) end)
connect(fullplayButton.MouseButton1Click,function()
    if fullplay then api.setFullplay(not fullplay.status().enabled) end
end)
connect(matchSkipBox.Focused,function()
    matchSkipEditing=true;matchSkipInputError=nil
    if matchSkip then matchSkip.setEditing(true) end
end)
connect(matchSkipBox.FocusLost,function()
    api.setMatchSkipUsername(matchSkipBox.Text)
end)
connect(matchSkipButton.MouseButton1Click,function()
    if matchSkip then api.setMatchSkip(not matchSkip.status().enabled) end
end)
connect(unloadButton.MouseButton1Click,api.unload)
connect(UIS.InputBegan,function(input,processed)
    if input.KeyCode==Enum.KeyCode.Escape then modeMenu.Visible=false end
    if input.KeyCode==Enum.KeyCode.RightShift and not UIS:GetFocusedTextBox() then
        api.setWindowVisible(not windowVisible)
        return
    end
    if processed or UIS:GetFocusedTextBox() then return end
    if input.KeyCode==Enum.KeyCode.B then api.setEnabled(not enabled)
    elseif input.KeyCode==Enum.KeyCode.V and assist then api.setAuto(not assist.status().enabled)
    elseif input.KeyCode==Enum.KeyCode.F8 then api.unload() end
end)
connect(matchEvent.OnClientEvent,function(data)
    if testing then finishTest() end
    onMatch(data)
end)
connect(fxEvent.OnClientEvent,function(data)
    if testing and type(data)=="table" and
        (data.Type=="Throw" or data.Type=="BallStop" or data.Type=="BallResult") then
        finishTest()
    end
    onFx(data)
end)
api.syncFromGame()
-- BUNDLED_INTERCEPT_INIT
buildAutoplayOptions()
local accumulator = 0
connect(RunService.Heartbeat,function(dt)
    accumulator = accumulator+dt
    if accumulator < 0.075 then return end
    accumulator = 0
    local success, err = pcall(render)
    if not success then
        lastError=tostring(err)
        hide()
        text.Text="CHALK DB · rendering error\n"..lastError
    end
end)
render()
if type(writefile)=="function" then
    task.spawn(function()
        local http=game:GetService("HttpService")
        while alive do
            pcall(function()
                local c=api.context()
                writefile("ciu_live_status.json",http:JSONEncode({time=workspace:GetServerTimeNow(),
                    gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,loaded=true,
                    status=api.status(),opponents=#c.opponents,hasArc=c.arc~=nil,
                    carrier=c.carrier and c.carrier.Name or nil,enemyCarrier=c.enemyCarrier}))
            end)
            task.wait(2)
        end
    end)
end
print("Chalk Assist "..RELEASE_VERSION.." loaded. Automation starts OFF. Drag / minimize / Right Shift hide. V assist / B all / F8 unload.")
