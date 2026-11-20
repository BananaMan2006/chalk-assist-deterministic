-- Chalk-Release: 5.1.18
-- Chalk-Product: deterministic
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
local RELEASE_VERSION="5.1.18"
local loadedGameId,loadedPlaceId,loadedJobId=game.GameId,game.PlaceId,game.JobId
env.ChalkDB = api
local alive, enabled = true, true
local assist,autoplay,repeatWR,idleGuard,fullplay,matchSkip,autoload,sessionContinuity
local preferences,restoringPreferences
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
local function savePreferences(patch)
    if preferences and not restoringPreferences and not testing then return preferences.update(patch) end
    return true
end
local function choice(kind,value)
    if sessionContinuity and not restoringPreferences and not testing then sessionContinuity.onChoice(kind,value) end
end
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
local function saveWindow()
    savePreferences({ui={visible=windowVisible,minimized=minimized,x=panel.Position.X.Offset,y=panel.Position.Y.Offset}})
end
function api.setWindowVisible(value)
    windowVisible=value==true
    cancelDrag()
    modeMenu.Visible=false
    gui.Enabled=windowVisible
    saveWindow()
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
    saveWindow()
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
        saveWindow()
        cancelDrag()
    end
end)
connect(UIS.WindowFocusReleased,function() if dragInput then saveWindow() end;cancelDrag() end)
connect(bounds:GetPropertyChangedSignal("AbsoluteSize"),function()
    cancelDrag()
    placeWindow(panel.Position.X.Offset,panel.Position.Y.Offset)
    saveWindow()
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
        savePreferences({usernames=matchSkip.status().username})
    else matchSkipInputError=reason end
    updateMatchSkipUI()
    return ok,reason
end
api.setMatchSkipUsername=api.setMatchSkipUsernames
function api.setMatchSkip(value)
    if not matchSkip then return false,"Auto leave is starting" end
    local ok,reason=matchSkip.setEnabled(value)
    if ok then savePreferences({autoLeave=value==true}) end
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
    if good then alertSettings.enabled=wanted;alertSettings.saveError=nil;savePreferences({matchAlerts=wanted})
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
            api.setAutoplayMode(key)
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
    local settingsStatus=preferences and preferences.status()
    if settingsStatus and (settingsStatus.saveError or settingsStatus.restoreError or settingsStatus.recoveryWarning) then
        text.Text=text.Text.."\nSettings: "..(settingsStatus.saveError or settingsStatus.restoreError or settingsStatus.recoveryWarning)
    end
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
    if dragInput then saveWindow() end
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
        if preserveAutoplay~=true then autoplay.setEnabled(false,true) end
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
    savePreferences({master=enabled})
    choice("master",enabled)
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
    return {product="deterministic",version=RELEASE_VERSION,buildId="965226d3d58be1a6d2168b13b5f3dd176906cc9c236d5e74008f986a008b3d9f",policyMode="deterministic", enabled=enabled, role=role or "unknown",rawRole=rawRole or "unknown", phase=phase,
        ui={visible=windowVisible,minimized=minimized,x=panel.Position.X.Offset,y=panel.Position.Y.Offset},
        matchAlerts={enabled=alertSettings.enabled,saveError=alertSettings.saveError},
        preferences=preferences and preferences.status() or nil,
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
        -- Preserve the coverage reserve before the throw. An observed live
        -- ball or a verified opposing carrier after the catch can spend it.
        -- A forecast, stale carrier or unknown team alone cannot unlock it.
        playBudget=fullplay and fullplay.movementBudget and fullplay.movementBudget(
            arc~=nil and phase=="Live"
            or holder~=nil and isEnemy==true and (phase=="RAC" or phase=="Run")) or nil,
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
    savePreferences({assist=value==true})
    choice("assist",value==true)
    if api.updateIdleGuard then api.updateIdleGuard() end
end
function api.setFullplay(value)
    if not fullplay then return false,"Full auto is starting" end
    if value==true and not restoringPreferences then
        api.setEnabled(true)
        if assist then assist.setEnabled(true) end
    end
    local ok,reason=fullplay.setEnabled(value)
    if ok then
        local patch={fullAuto=value==true}
        if value==true and not restoringPreferences then patch.master=true;patch.assist=true end
        savePreferences(patch)
    end
    choice("fullplay",value==true and ok==true)
    updateFullplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.setAutoplay(value)
    if not autoplay then return false,"Autoplay is starting" end
    if value==true and repeatWR then repeatWR.setEnabled(false);updateWRRepeatUI() end
    local ok,reason=autoplay.setEnabled(value)
    if value~=true or ok==true then savePreferences({autoplay=value==true,wrRepeat=value==true and false or repeatWR.status().enabled==true}) end
    choice("autoplay",ok==true)
    updateAutoplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.setWRRepeat(value)
    if not repeatWR then return false,"WR repeat is starting" end
    local ok,reason=repeatWR.setEnabled(value)
    if value~=true or ok==true then savePreferences({wrRepeat=value==true,autoplay=value==true and false or autoplay.status().enabled==true}) end
    updateWRRepeatUI()
    updateAutoplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.setAutoplayMode(value)
    if not autoplay then return false,"Autoplay is starting" end
    local ok,reason=autoplay.selectMode(value)
    if ok then savePreferences({selectedMode=value}) end
    choice("mode",ok==true)
    updateAutoplayUI()
    if api.updateIdleGuard then api.updateIdleGuard() end
    return ok,reason
end
function api.autoplayModes() return autoplay and autoplay.modes() or {} end
function api.initializePreferences(create)
    preferences=create({previousState=previousState,
        sameJob=previousContext and previousContext.jobId==game.JobId})
    -- No input-producing feature may run while the others are being built.
    restoringPreferences=true
    enabled=false
end
function api.restorePreferences()
    if not preferences then return end
    restoringPreferences=true
    local saved=preferences.get()
    local failures={}
    local function apply(label,fn)
        local ok,result,reason=pcall(fn)
        if not ok or result==false and reason~=nil then failures[#failures+1]=label..": "..tostring(ok and reason or result) end
        return ok and result~=false
    end
    local modeOK=true
    if saved.selectedMode then modeOK=apply("Mode",function() return api.setAutoplayMode(saved.selectedMode) end) end
    if saved.usernames~=nil then apply("Auto leave names",function() return api.setMatchSkipUsernames(saved.usernames) end) end
    alertSettings.enabled=saved.matchAlerts
    updateAlertsUI()
    savedUI=saved.ui
    api.setWindowVisible(saved.ui.visible)
    api.setMinimized(saved.ui.minimized)
    placeWindow(saved.ui.x,saved.ui.y)
    api.setEnabled(saved.master)
    api.setAuto(saved.assist)
    apply("Full auto",function() return api.setFullplay(saved.fullAuto) end)
    apply("Win farm",function() return api.setWRRepeat(saved.wrRepeat) end)
    if modeOK then apply("Autoplay",function() return api.setAutoplay(saved.autoplay) end)
    else autoplay.setEnabled(false,true);updateAutoplayUI() end
    apply("Auto leave",function() return api.setMatchSkip(saved.autoLeave) end)
    restoringPreferences=false
    preferences.setRestoreError(#failures>0 and table.concat(failures,"; ") or nil)
    -- Complete optional selector/name defaults once, without taking runtime
    -- pauses or constructor OFF values as a replacement for saved switches.
    local patch={}
    if not saved.selectedMode then patch.selectedMode=autoplay.status().selectedMode end
    if saved.usernames==nil then patch.usernames=matchSkip.status().username end
    if next(patch) and preferences.status().source~="invalid" then preferences.update(patch) end
    if api.updateIdleGuard then api.updateIdleGuard() end
end
function api.initializeSessionContinuity(createSession)
    local function modeAvailable(key)
        for _,entry in ipairs(api.autoplayModes()) do
            if entry.key==key then return entry.available==true end
        end
        return false
    end
    sessionContinuity=createSession({entry=launchOptions,modeAvailable=modeAvailable,
        canResume=function(ticket)
            local wanted=preferences and preferences.get()
            return wanted and wanted.master and wanted.autoplay and not wanted.wrRepeat
                and wanted.selectedMode==ticket.selectedMode
                and (not ticket.fullAuto or wanted.fullAuto and wanted.assist)
        end,
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
            -- Preferences were restored already. A one-hop lease transfers
            -- queue ownership, never overrides an explicit saved OFF/mode.
            local a=autoplay.status()
            return enabled and a.enabled and a.selectedMode==selectedMode
                and (not fullAuto or fullplay.status().enabled and assist.status().enabled)
        end,
        stop=function()
            fullplay.setEnabled(false);assist.setEnabled(false);autoplay.setEnabled(false,true)
        end})
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
local createPreferences = (function()
-- Local deterministic preferences. Alternating verified slots retain the last
-- complete revision if a write is interrupted. No gameplay, services or network.
return function(ctx,services)
    ctx=ctx or {};services=services or {}
    local http=services.http or game:GetService("HttpService")
    local read=services.read or readfile
    local write=services.write or writefile
    local exists=services.exists or isfile
    local paths={"ciu_deterministic_preferences_v1.a.json","ciu_deterministic_preferences_v1.b.json"}
    local switches={master=true,assist=true,fullAuto=true,autoplay=true,wrRepeat=true,autoLeave=true,matchAlerts=true}
    local function copy(v)
        if type(v)~="table" then return v end
        local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
    end
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<100000 end
    local function defaults()
        return {master=true,assist=false,fullAuto=false,autoplay=false,wrRepeat=false,autoLeave=false,
            matchAlerts=true,ui={visible=true,minimized=false,x=110,y=110}}
    end
    local function valid(v)
        if type(v)~="table" then return false end
        for k in pairs(switches) do if type(v[k])~="boolean" then return false end end
        for k in pairs(v) do
            if not switches[k] and k~="ui" and k~="selectedMode" and k~="usernames" then return false end
        end
        if v.autoplay and v.wrRepeat then return false end
        if v.selectedMode~=nil and (type(v.selectedMode)~="string" or #v.selectedMode<1 or #v.selectedMode>64) then return false end
        if v.usernames~=nil and (type(v.usernames)~="string" or #v.usernames>4096) then return false end
        local u=v.ui
        if type(u)~="table" or type(u.visible)~="boolean" or type(u.minimized)~="boolean"
            or not finite(u.x) or not finite(u.y) then return false end
        for k in pairs(u) do if k~="visible" and k~="minimized" and k~="x" and k~="y" then return false end end
        return true
    end
    local function equal(a,b)
        if type(a)~=type(b) then return false end
        if type(a)~="table" then return a==b end
        for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    local function decode(path)
        if type(exists)=="function" then
            local ok,present=pcall(exists,path)
            if not ok then return nil,false end
            if present==false then return nil,true end
        end
        if type(read)~="function" then return nil,false end
        local ok,raw=pcall(read,path)
        if not ok then
            local message=string.lower(tostring(raw))
            local missing=string.find(message,"no such file",1,true) or string.find(message,"not found",1,true)
                or string.find(message,"does not exist",1,true)
            return nil,missing~=nil
        end
        if type(raw)~="string" or #raw>32768 then return nil,false end
        local good,value=pcall(function() return http:JSONDecode(raw) end)
        return good and value or nil,false
    end
    local function record(v)
        return type(v)=="table" and v.schemaVersion==1 and type(v.revision)=="number"
            and v.revision>=1 and v.revision<1000000000 and v.revision==math.floor(v.revision) and valid(v.values)
    end
    local values,revision,slot=defaults(),0,nil
    local saveError,source,restoreError,recoveryWarning=nil,"fresh",nil,nil
    local pendingChoice=false
    local a,missingA=decode(paths[1]);local b,missingB=decode(paths[2])
    local va,vb=record(a),record(b)
    if va and vb and a.revision==b.revision and not equal(a.values,b.values) then
        saveError="Saved settings disagree; switches remain off";source="invalid"
    elseif va or vb then
        slot=va and (not vb or a.revision>=b.revision) and 1 or 2
        local saved=slot==1 and a or b
        values,revision,source=copy(saved.values),saved.revision,"saved"
        if (not va and not missingA) or (not vb and not missingB) then
            recoveryWarning="Recovered the last complete settings copy"
        end
    elseif not missingA or not missingB then
        saveError="Saved settings could not be read; switches remain off";source="invalid"
    else
        -- Migrate only this product's explicit settings. Missing files never
        -- invent an ON choice, and corrupt new journals never revive old ONs.
        local autoplay=decode("ciu_deterministic_autoplay_v1.json")
        if type(autoplay)=="table" then
            if type(autoplay.enabled)=="boolean" then values.autoplay=autoplay.enabled end
            if type(autoplay.selectedMode)=="string" and #autoplay.selectedMode>0 and #autoplay.selectedMode<=64 then
                values.selectedMode=autoplay.selectedMode
            end
        end
        local fullplay=decode("ciu_deterministic_fullplay_v1.json")
        if type(fullplay)=="table" and fullplay.schemaVersion==1 and fullplay.policyMode=="deterministic"
            and type(fullplay.lastRequestedEnabled)=="boolean" then values.fullAuto=fullplay.lastRequestedEnabled end
        local skip=decode("ciu_deterministic_match_skip_v1.json")
        if type(skip)=="table" and (skip.version==1 or skip.version==2) then
            if type(skip.enabled)=="boolean" then values.autoLeave=skip.enabled end
            if skip.version==1 and type(skip.username)=="string" then values.usernames=skip.username
            elseif skip.version==2 and type(skip.usernames)=="table" then
                local names={};for _,name in ipairs(skip.usernames) do
                    if type(name)~="string" then names=nil;break end;names[#names+1]=name
                end
                if names then values.usernames=table.concat(names,", ") end
            end
        end
        local alerts=decode("ciu_match_alert_settings.json")
        if type(alerts)=="table" and type(alerts.enabled)=="boolean" then values.matchAlerts=alerts.enabled end
        if values.fullAuto then values.master,values.assist=true,true
        elseif values.autoplay then values.master=true end
        local prior=ctx.previousState
        if type(prior)=="table" and prior.product=="deterministic" and prior.testing~=true then
            local map={assist="auto",fullAuto="fullplay",autoplay="autoplay",wrRepeat="wrRepeat",autoLeave="matchSkip",matchAlerts="matchAlerts"}
            if type(prior.enabled)=="boolean" then values.master=prior.enabled end
            for key,field in pairs(map) do
                if type(prior[field])=="table" and type(prior[field].enabled)=="boolean" then values[key]=prior[field].enabled end
            end
            if type(prior.ui)=="table" then
                for k in pairs(values.ui) do if type(prior.ui[k])==type(values.ui[k]) then values.ui[k]=prior.ui[k] end end
            end
        end
        if values.wrRepeat then values.autoplay=false end
        if not valid(values) then values=defaults();saveError="Previous settings were invalid; switches remain off" end
        source="migrated"
    end
    local api={}
    local function persist()
        if type(write)~="function" or type(read)~="function" then saveError="Settings cannot be saved on this executor";return false,saveError end
        local target=slot==1 and 2 or 1
        local nextRevision=revision+1
        local payload={schemaVersion=1,revision=nextRevision,values=copy(values)}
        local ok,err=pcall(function()
            write(paths[target],http:JSONEncode(payload))
            local actual=decode(paths[target])
            assert(record(actual) and actual.revision==nextRevision and equal(actual.values,values),"Settings readback did not match")
        end)
        if not ok then saveError="Settings were not saved: "..tostring(err);return false,saveError end
        slot,revision,saveError,source,recoveryWarning=target,nextRevision,nil,"saved",nil
        pendingChoice=false
        return true
    end
    function api.get() return copy(values) end
    function api.update(patch)
        if type(patch)~="table" then return false,"Invalid settings change" end
        local nextValues=copy(values)
        for k,v in pairs(patch) do nextValues[k]=copy(v) end
        if not valid(nextValues) then return false,"Invalid settings change" end
        if equal(values,nextValues) and not saveError and revision>0 then return true end
        values=nextValues
        pendingChoice=true
        return persist()
    end
    function api.setRestoreError(reason) restoreError=reason end
    function api.status()
        return {schemaVersion=1,revision=revision,source=source,saveError=saveError,restoreError=restoreError,
            recoveryWarning=recoveryWarning,pendingChoice=pendingChoice,values=copy(values)}
    end
    local prior=ctx.previousState
    if ctx.sameJob==true and type(prior)=="table" and prior.product=="deterministic"
        and type(prior.preferences)=="table" and type(prior.preferences.saveError)=="string"
        and prior.preferences.pendingChoice==true
        and valid(prior.preferences.values) then
        values=copy(prior.preferences.values);source="migrated";saveError=nil;pendingChoice=true
    end
    if source=="migrated" and not saveError then persist() end
    return api
end

end)()
local Planner = (function()
-- Pure Chalk It Up interception planner. No services, input, remotes or mutations.
-- solve(snapshot) returns absolute server-time action deadlines, or nil + reason.
-- Caller must enforce role, phase, health, input focus, cooldown and test-mode gates.
local Planner = {}
local ZERO = Vector3.zero
local UP = Vector3.new(0, 1, 0)
local FLAT = Vector3.new(1, 0, 1)
local INF = math.huge

local function finite(v)
    return type(v) == "number" and v == v and v ~= INF and v ~= -INF
end
local function vec(v)
    return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function inBounds(s,p)
    local b=s.bounds
    if type(b)~="table" then return true end
    return (not finite(b.minX) or p.X>=b.minX) and (not finite(b.maxX) or p.X<=b.maxX)
        and (not finite(b.minZ) or p.Z>=b.minZ) and (not finite(b.maxZ) or p.Z<=b.maxZ)
end
local function explicitMoveCap(s)
    local cap=finite(s.maxMoveDistance) and math.max(0,s.maxMoveDistance) or INF
    return finite(s.range) and math.min(cap,math.max(0,s.range)) or cap
end
local function smooth(t) return (1-math.cos(math.pi*clamp(t, 0, 1)))*0.5 end
local function flatUnit(v, fallback)
    local f = v*FLAT
    if f.Magnitude > 0.001 then return f.Unit end
    f = (fallback or Vector3.new(0, 0, -1))*FLAT
    return f.Magnitude > 0.001 and f.Unit or Vector3.new(0, 0, -1)
end
local function cfg(s, name, default)
    local v = s.config and s.config[name]
    return finite(v) and v or default
end
local function diveCfg(s, name, default)
    local d = s.config and s.config.Moves and s.config.Moves.Dive
    local v = d and d[name]
    return finite(v) and v or default
end
local function travel(seconds, speed, runSpeed, sprintSeconds)
    seconds=math.max(0,seconds)
    local fast=math.min(seconds,sprintSeconds)
    return speed*fast+runSpeed*math.max(0,seconds-fast)
end
local function travelTime(distance,speed,runSpeed,sprintSeconds)
    if distance<=0 then return 0 end
    if speed<=0 and sprintSeconds==INF then return INF end
    local fastDistance=speed*sprintSeconds
    if speed>0 and distance<=fastDistance then return distance/speed end
    if runSpeed<=0 then return INF end
    return sprintSeconds+(distance-fastDistance)/runSpeed
end
function Planner.ballAt(arc, elapsed)
    local u = elapsed/arc.Flight
    return arc.P0+(arc.P1-arc.P0)*u+UP*(4*arc.Apex*u*(1-u))
end
function Planner.segmentDistance(point, a, b)
    local ab = b-a
    local d = ab:Dot(ab)
    local f = d > 0.000001 and clamp((point-a):Dot(ab)/d, 0, 1) or 0
    return (point-(a+ab*f)).Magnitude
end
function Planner.capsule(s, cf, airborne)
    local up, pos = cf.UpVector, cf.Position
    if up.Y < 0.6 then
        return pos-up, pos+up*cfg(s,"DiveReach",2.4), cfg(s,"DiveCatchRadius",2.5)
    end
    -- Native FloorMaterial can shorten hand reach during an otherwise
    -- ballistic jump. Keep that catch geometry separate from motion physics.
    if s.reachAirborne~=nil then airborne=s.reachAirborne==true end
    return pos-UP*cfg(s,"WaistDrop",1),
        pos+UP*cfg(s,airborne and "HandUpOffset" or "HandOffset",airborne and 3.5 or 0.5),
        cfg(s,"CatchRadius",3.75)
end

-- Ordinary motion before a dive. Steering starts after reactionDelay; vertical
-- motion uses the real jump speed/gravity supplied by the caller.
local function normalPose(s, p, t)
    t = math.max(0,t)
    local velocity = s.velocity or ZERO
    local horizontal
    if p.kind == "hold" then
        horizontal = s.position+velocity*FLAT*t
    else
        local reaction = p._reaction
        local drift = velocity*FLAT*math.min(t,reaction)
        local run = math.min(p._aimDistance,travel(t-reaction,p._speed,
            p._runSpeed or p._speed,p._sprintSeconds or INF))
        horizontal = s.position+drift+p.direction*run
    end
    local floor = s.groundRootY or (s.grounded and s.position.Y or nil)
    local y, vy, airborne = s.position.Y, velocity.Y, not s.grounded
    local g = s.gravity
    if not s.grounded then
        y = y+vy*t-0.5*g*t*t
        vy = vy-g*t
        if floor and y <= floor and vy <= 0 then y,vy,airborne=floor,0,false end
    else
        vy = 0
    end
    if p._jumpDelay and t >= p._jumpDelay then
        local jt = t-p._jumpDelay
        local baseY = floor or s.position.Y
        y = baseY+s.jumpSpeed*jt-0.5*g*jt*jt
        vy = s.jumpSpeed-g*jt
        airborne = true
        if y <= baseY and vy <= 0 then y,vy,airborne=baseY,0,false end
    end
    local position = Vector3.new(horizontal.X,y,horizontal.Z)
    local direction = p.kind == "hold" and flatUnit(s.lookDirection or p.direction) or p.direction
    return CFrame.lookAt(position,position+direction), airborne, vy
end

-- Matches the inspected DivePath.Run: quadratic horizontal easing, cosine
-- ground descent, ballistic airborne descent and 80-degree smooth tipping.
-- The caller may supply a read-only clipDiveDistance callback for field Walls.
function Planner.pose(s, p, absoluteTime)
    local t = math.max(0,absoluteTime-s.now)
    if not p._diveDelay or t < p._diveDelay then return normalPose(s,p,t) end
    local origin, wasAirborne, verticalSpeed = normalPose(s,p,p._diveDelay)
    local start = origin.Position
    local direction = p.direction
    local dt = t-p._diveDelay
    local duration = diveCfg(s,"Time",0.35)
    local tip = math.max(0.001,diveCfg(s,"Tip",0.5))
    local distance = p._diveDistance or s.diveDistance
    if p._diveDistance == nil and type(s.clipDiveDistance) == "function" then
        local clipped = s.clipDiveDistance(start,direction,distance)
        if finite(clipped) then distance=clamp(clipped,0,distance) end
        p._diveDistance = distance
    end
    local base = wasAirborne and (s.diveTurfY or s.turfY) or start.Y-3
    local lowY = base+0.6
    local initialVY = wasAirborne and math.max(0,verticalSpeed) or 0
    local flightEnd = duration
    if wasAirborne then
        local discriminant = initialVY*initialVY+2*s.gravity*math.max(0,start.Y-lowY)
        flightEnd = math.max(duration,(initialVY+math.sqrt(discriminant))/s.gravity)
    end
    local f = clamp(dt/duration,0,1)
    local position = start+direction*distance*(1-(1-f)^2)
    local y = wasAirborne
        and math.max(lowY,start.Y+initialVY*dt-0.5*s.gravity*dt*dt)
        or start.Y+(lowY-start.Y)*smooth(f)
    local angle = -math.rad(80)*smooth(f/tip)
    local airborne = wasAirborne
    if dt >= flightEnd then
        local recovery = smooth((dt-flightEnd-diveCfg(s,"Ground",0.75))
            /math.max(0.001,diveCfg(s,"GetUp",0.35)))
        y = lowY+(base+3-lowY)*recovery
        angle = -math.rad(80)*(1-recovery)
        airborne = false
    end
    position = Vector3.new(position.X,y,position.Z)
    return CFrame.lookAt(position,position+direction)*CFrame.Angles(angle,0,0),airborne,0
end

local function makePlan(s,kind,direction,target,jumpDelay,diveDelay,horizon)
    local distance = ((target-s.position)*FLAT).Magnitude
    local speed = math.max(0,s.walkSpeed)
    local runSpeed=math.max(0,s.runSpeed or speed)
    local sprintSeconds=math.max(0,s.sprintSeconds or INF)
    local reaction = math.max(0,s.reactionDelay or 0.025)
    local maxMove = s.maxMoveDistance or ((s.chase or s.role=="WR" or kind=="pursue")
        and travel((horizon or 4)-reaction,speed,runSpeed,sprintSeconds)
        or (s.diveDistance*0.65+3))
    local aimDistance = math.min(distance,maxMove)
    local stopDelay = reaction+travelTime(aimDistance,speed,runSpeed,sprintSeconds)
    if diveDelay then stopDelay=math.min(stopDelay,diveDelay) end
    return {kind=kind,direction=direction,
        jumpAt=jumpDelay and s.now+jumpDelay or nil,
        diveAt=diveDelay and s.now+diveDelay or nil,
        stopAt=s.now+stopDelay,
        _jumpDelay=jumpDelay,_diveDelay=diveDelay,
        _aimDistance=aimDistance,_speed=speed,_reaction=reaction,
        _runSpeed=runSpeed,_sprintSeconds=sprintSeconds}
end

local function contact(s,p,t,requiredMargin,timingMargin)
    if p._diveDelay then
        local origin=normalPose(s,p,p._diveDelay)
        if not Planner.canDiveFrom(s,origin.Position) then return nil,-INF end
    end
    local minMargin, maxDistance = INF,0
    local halfWindow = timingMargin or s.timingMargin or 0.012
    -- Requiring nearby samples reduces one-frame edge-of-capsule triggers.
    for _,delta in ipairs({-halfWindow,0,halfWindow}) do
        local when = s.now+t+delta
        local elapsed = when-s.launchAt
        if elapsed <= 0.12 then return nil end -- native BallView eligibility
        local ball = Planner.ballAt(s.arc,elapsed)
        if ball.Y < s.turfY+0.05 then return nil end
        local cf,airborne = Planner.pose(s,p,when)
        local waist,hands,radius = Planner.capsule(s,cf,airborne)
        local distance = Planner.segmentDistance(ball,waist,hands)
        minMargin = math.min(minMargin,radius-distance)
        maxDistance = math.max(maxDistance,distance)
    end
    if minMargin < (requiredMargin or s.margin or 0.3) then return nil,minMargin end
    local cf = Planner.pose(s,p,s.now+t)
    p.contactAt=s.now+t
    p.contactPosition=Planner.ballAt(s.arc,s.now+t-s.launchAt)
    p.rootTarget=cf.Position
    p.margin=minMargin
    p.distance=maxDistance
    p.reachable=true
    p.requiresWallCheck=p._diveDelay ~= nil and type(s.clipDiveDistance) ~= "function"
    return p,minMargin
end

local costs={hold=0,move=0.035,jump=0.08,dive=0.12,jumpDive=0.18}
local function validSnapshot(s)
    if type(s) ~= "table" or type(s.arc) ~= "table" or not vec(s.position)
        or not vec(s.arc.P0) or not vec(s.arc.P1) or not finite(s.now)
        or not finite(s.launchAt) or not finite(s.arc.Flight) or s.arc.Flight <= 0
        or not finite(s.arc.Apex) or not finite(s.gravity) or s.gravity <= 0
        or not finite(s.walkSpeed) or not finite(s.jumpSpeed)
        or not finite(s.turfY) or not finite(s.diveDistance) then
        return false
    end
    return true
end
local function flightHorizon(s,fullFlight)
    local horizon
    if fullFlight then
        local remaining=s.arc.Flight-(s.now-s.launchAt)
        -- The intended endpoint is catch height; include the remaining arc down
        -- to turf when computing the full remaining flight window.
        local h=s.arc.P0.Y-s.turfY
        local dy=s.arc.P1.Y-s.arc.P0.Y
        if s.arc.Apex>0 then
            local b=dy+4*s.arc.Apex
            local d=b*b+16*s.arc.Apex*h
            if d>=0 then
                remaining=s.arc.Flight*(b+math.sqrt(d))/(8*s.arc.Apex)-(s.now-s.launchAt)
            end
        elseif dy<0 then
            remaining=s.arc.Flight*(-h/dy)-(s.now-s.launchAt)
        end
        if remaining<=0 then return nil,"Flight has reached turf" end
        horizon=clamp(math.min(s.maxHorizon or 4,remaining),0.06,4)
    else
        horizon=clamp(s.maxHorizon or 0.85,0.1,1.5)
    end
    return horizon
end

-- Find the first native capsule overlap along the whole proposed approach.
-- A later intended catch must not be credited with yards after an earlier touch.
function Planner.firstTouch(s,p,checkedThrough)
    -- The optional lower bound is used only after an identical shared prefix
    -- has already been checked. It never skips an unexamined approach.
    local first=math.max(s.now,s.launchAt+0.1201,checkedThrough or -INF)
    local last=p.contactAt
    local function overlap(at)
        local cf,airborne=Planner.pose(s,p,at)
        local ball=Planner.ballAt(s.arc,at-s.launchAt)
        local waist,hands,radius=Planner.capsule(s,cf,airborne)
        return Planner.segmentDistance(ball,waist,hands)<=radius,cf.Position,ball
    end
    local stride=0.04
    local sampleBudget=512
    if s.requireAirborne then
        -- Fast bullets can cross an entire catch volume between 40 ms samples.
        -- Bound sampled travel by a catch radius using observed arc speed and
        -- the proposed root motion. This remains a sampled geometric witness,
        -- not a continuous/server collision guarantee for grazing contacts.
        local function ballSpeed(at)
            local u=(at-s.launchAt)/s.arc.Flight
            return ((s.arc.P1-s.arc.P0)/s.arc.Flight
                +UP*(4*s.arc.Apex/s.arc.Flight*(1-2*u))).Magnitude
        end
        local horizontal=math.max(p._speed or 0,p._runSpeed or 0,
            ((s.velocity or ZERO)*FLAT).Magnitude,
            p.diveAt and 2*s.diveDistance/diveCfg(s,"Time",0.35) or 0)
        local vertical=math.max(math.abs((s.velocity or ZERO).Y),s.jumpSpeed or 0)
        local speed=math.max(ballSpeed(first),ballSpeed(last))+horizontal+vertical
        local radius=math.min(cfg(s,"CatchRadius",3.75),cfg(s,"DiveCatchRadius",2.5))
        stride=math.min(stride,radius/math.max(1,speed))
        if stride<0.001 or (last-first)/stride>sampleBudget then
            return {at=first,root=s.position,position=Planner.ballAt(s.arc,first-s.launchAt),
                progress=-INF,uncertain=true,reason="First-contact sampling budget exceeded"}
        end
    end
    local previous=first
    local at=first
    while at<=last do
        local hit=overlap(at)
        if hit then
            local lo,hi=previous,at
            for _=1,5 do
                local mid=(lo+hi)*0.5
                if overlap(mid) then hi=mid else lo=mid end
            end
            local _,root,ball=overlap(hi)
            return {at=hi,root=root,position=ball,progress=ball.Z}
        end
        if at==last then break end
        previous=at
        at=math.min(last,at+stride)
    end
    return {at=last,root=p.rootTarget,position=p.contactPosition,progress=p.contactPosition.Z}
end

-- An aerial finish is based on the first catch-volume overlap, not a later
-- intended target after the character has already touched the ball on turf.
-- Clearance checks the root against the appropriate landing pose; the hands
-- or catch volume may legitimately extend down toward the ground.
function Planner.airborneFinish(s,p,touch)
    if not p or not finite(p.contactAt) then return nil,"Missing contact witness" end
    touch=touch or Planner.firstTouch(s,p)
    if touch.uncertain then return nil,touch.reason end
    local requireGoal=s.role=="WR" and s.requireEndzoneCatch==true
    if requireGoal and not finite(s.wrDiveGoalZ) then return nil,"WR endzone catch boundary unavailable" end
    local diving=p.diveAt~=nil
    if diving and touch.at<p.diveAt+0.03 then return nil,"Contact precedes the dive" end
    local window=p.timingMargin or s.timingMargin or 0.012
    local floor=diving and (s.diveTurfY or s.turfY)+0.6
        or (s.groundRootY or s.turfY+3)
    for _,at in ipairs({touch.at,p.contactAt-window,p.contactAt,p.contactAt+window}) do
        local cf,airborne=Planner.pose(s,p,at)
        if p.continuousCatch and not inBounds(s,cf.Position) then
            return nil,"Continuous airborne contact leaves field bounds"
        end
        if requireGoal and cf.Position.Z<s.wrDiveGoalZ+.25 then
            return nil,"Floater first contact must be inside the end zone"
        end
        if not airborne or cf.Position.Y<=floor+0.15 then
            return nil,"Contact reaches the landing or recovery pose"
        end
    end
    return diving and "jumpDive" or "jump"
end

-- Recheck a scheduled aerial dive from the character's observed airborne
-- position immediately before dispatch. No new jump or future takeoff is assumed.
function Planner.validateAirborneDive(s,p)
    if not validSnapshot(s) or not p or not p.diveAt or s.grounded
        or s.reachAirborne==false or not finite(p.contactAt) or p.contactAt<=s.now then
        return false,"No current airborne dive window"
    end
    if not Planner.canDiveFrom(s,s.position) then
        return false,"WR dive must start inside the end zone"
    end
    local actual={}
    for key,value in pairs(p) do actual[key]=value end
    actual.kind,actual.jumpAt,actual._jumpDelay="dive",nil,nil
    actual.diveAt,actual._diveDelay=s.now,0
    actual._diveDistance=nil
    actual._reaction,actual._aimDistance=0,0
    local witness=contact(s,actual,p.contactAt-s.now,p.requiredMargin,p.timingMargin)
    if not witness then return false,"Observed dive no longer reaches the ball" end
    local finish,reason=Planner.airborneFinish(s,witness)
    return finish=="jumpDive",reason or "Observed airborne contact remains reachable"
end

-- Validate the existing contact after shifting takeoff to this actual input
-- instant. Three contact samples are enough to reject a late jump without a
-- new strategy search. WR additionally retains its sampled first-contact rule.
function Planner.validateJump(s,p)
    if not validSnapshot(s) or not p or not p.jumpAt or not s.grounded
        or s.canJump~=true or not finite(p.contactAt) or p.contactAt<=s.now then
        return false,"No current jump contact window"
    end
    local actual={}
    for key,value in pairs(p) do actual[key]=value end
    actual.jumpAt,actual._jumpDelay=s.now,0
    actual._reaction=0
    actual._speed,actual._runSpeed=math.max(0,s.walkSpeed),math.max(0,s.runSpeed or s.walkSpeed)
    actual._sprintSeconds=math.max(0,s.sprintSeconds or INF)
    local target=p.approachTarget or p.rootTarget
    if not vec(target) or not vec(p.direction) then return false,"Jump movement target unavailable" end
    actual._aimDistance=math.max(0,((target-s.position)*FLAT):Dot(p.direction))
    if p.continuousCatch then
        if not finite(p.movementScale) or p.movementScale<.45 or p.movementScale>1 then
            return false,"Invalid continuous catch movement"
        end
        actual._speed=actual._speed*p.movementScale
        actual._runSpeed=actual._runSpeed*p.movementScale
        -- Rebase from the actual root without inventing an instantaneous
        -- airborne stop at the old target. Keep the current native speed and
        -- remaining stamina, scaled by the same input the controller sends.
        actual._aimDistance=travel(p.contactAt-s.now+.08,actual._speed,
            actual._runSpeed,actual._sprintSeconds)
        if actual._aimDistance>explicitMoveCap(s) then return false,"Continuous catch exceeds movement limit" end
        actual.stopAt=p.contactAt+.08
    end
    if p.diveAt then
        actual._diveDelay=p.diveAt-s.now
        actual._diveDistance=nil
        if actual._diveDelay<0.06 then return false,"Insufficient takeoff time before dive" end
    end
    local witness=contact(s,actual,p.contactAt-s.now,p.requiredMargin,p.timingMargin)
    if not witness then return false,"Jump no longer reaches the planned ball contact" end
    if s.role=="WR" and (s.requireAirborne or s.requireEndzoneCatch or p.continuousCatch) then
        local finish,reason=Planner.airborneFinish(s,witness)
        if not finish then return false,reason or "Jump no longer has airborne first contact" end
    end
    return true,"Observed jump contact remains reachable"
end

-- Contact-time sampling does not cover late action dispatch. In recent native
-- traces requests arrived up to 16 ms after their deadline and takeoff was
-- observed up to 18 ms after the request (including observation latency).
-- Reserve 35 ms for a WR jump, 60 ms for a normal DB jump, and 20 ms for a dive.
-- A recorded DB request preceded estimated takeoff by about47 ms after body
-- displacement; this budget preserves geometric margin, not the server result.
-- Only after normal DB search fails, the explicitly risky search may use the
-- previous 35 ms reserve. It remains an opportunistic attempt, not 60 ms robust.
-- Keep the independent fresh-position checks without weakening
-- the geometric margin used again at dispatch. These bounded samples are not
-- a guarantee against longer stalls or unknown server catch arbitration.
local function scheduledContact(s,p,t,margin,window,relaxed)
    local base,miss=contact(s,p,t,margin,window)
    if not base or s.actionTimingEnvelope==false or not (p._jumpDelay or p._diveDelay) then return base,miss end
    local jumpBudget,diveBudget=p._jumpDelay and (s.role=="DB" and not relaxed and 0.060 or 0.035) or 0,p._diveDelay and 0.020 or 0
    local minimumMargin=base.margin
    local sharedUntil
    if s.role=="WR" and (s.requireAirborne or s.requireEndzoneCatch) then
        if not Planner.airborneFinish(s,base,{at=base.contactAt}) then return nil,-0.01 end
        local first=Planner.firstTouch(s,base)
        if not Planner.airborneFinish(s,base,first) then return nil,-0.01 end
        base._timingFirstTouch=first
        -- All delayed variants have exactly the same pose before the first
        -- nominal action. Check this often-long Floater prefix only once.
        sharedUntil=math.min(p.jumpAt or INF,p.diveAt or INF)
    end
    for ji=0,(p._jumpDelay and 2 or 0) do
        for di=0,(p._diveDelay and 2 or 0) do
            if ji~=0 or di~=0 then
                local actual={}
                for key,value in pairs(p) do actual[key]=value end
                if p._jumpDelay then
                    actual._jumpDelay=p._jumpDelay+jumpBudget*ji/2
                    actual.jumpAt=s.now+actual._jumpDelay
                end
                if p._diveDelay then
                    actual._diveDelay=p._diveDelay+diveBudget*di/2
                    actual.diveAt=s.now+actual._diveDelay
                    actual._diveDistance=nil
                    -- The fresh jump validator needs this takeoff interval;
                    -- do not select a plan it must reject after ordinary jitter.
                    if actual._jumpDelay and actual._diveDelay-actual._jumpDelay<0.06 then return nil,-0.01 end
                end
                local witness,delayedMargin=contact(s,actual,t,margin,window)
                if not witness then return nil,delayedMargin end
                if sharedUntil then
                    if not Planner.airborneFinish(s,witness,{at=witness.contactAt}) then return nil,-0.01 end
                    local touch=Planner.firstTouch(s,witness,sharedUntil)
                    if not Planner.airborneFinish(s,witness,touch) then return nil,-0.01 end
                end
                minimumMargin=math.min(minimumMargin,witness.margin)
            end
        end
    end
    base.margin=minimumMargin
    base.jumpTimingBudget,base.diveTimingBudget=jumpBudget,diveBudget
    return base
end

local function oneDefenderDeadline(s,horizon,source)
    if type(source)~="table" or not vec(source.position) then return nil,false end
    local o={}
    for k,v in pairs(source) do o[k]=v end
    o.now,o.arc,o.launchAt=s.now,s.arc,s.launchAt
    o.config,o.turfY=s.config,s.turfY
    o.diveTurfY=s.diveTurfY
    o.role,o.chase="DB",true
    o.position=source.position
    o.velocity=vec(source.velocity) and source.velocity or ZERO
    o.lookDirection=source.lookDirection or Vector3.new(0,0,1)
    o.gravity=source.gravity or s.gravity
    o.jumpSpeed=source.jumpSpeed or s.jumpSpeed
    o.groundRootY=source.groundRootY or s.turfY+3
    o.grounded=source.grounded~=false
    o.walkSpeed=math.max(source.walkSpeed or 0,cfg(s,"SprintSpeed",27))
    o.runSpeed=source.runSpeed or cfg(s,"RunSpeed",20)
    o.sprintSeconds=source.sprintSeconds~=nil and source.sprintSeconds or 4
    o.diveDistance=source.diveDistance or s.diveDistance
    o.canJump=source.canJump~=false
    o.canDive=source.canDive~=false
    o.maxHorizon=horizon
    o.reactionDelay=0
    o.timeStep=0.04
    o.margin=-0.5 -- possible reach envelope, not a promise of a clean catch
    o.timingMargin=0
    -- An opponent's possible reach remains optimistic. Our own execution
    -- budget must not make an unknown defender look artificially slower.
    o.actionTimingEnvelope=false
    o.allowHold=true
    o.allowLastResort=false -- already widened; keep opponent forecasts bounded
    o.opponent=nil
    o.clipDiveDistance=s.clipDiveDistance
    local possible=Planner.solve(o)
    local earliest=possible and possible.contactAt or nil
    if not o.grounded and o.canJump then
        -- Unknown landing/recovery timing: overestimate rather than assume the
        -- defender can never jump again during the remaining flight.
        o.grounded=true
        o.position=Vector3.new(o.position.X,math.max(o.position.Y,o.groundRootY),o.position.Z)
        o.groundRootY=o.position.Y
        o.velocity=o.velocity*FLAT
        local envelope=Planner.solve(o)
        if envelope and (not earliest or envelope.contactAt<earliest) then earliest=envelope.contactAt end
    end
    return earliest and math.max(s.now,earliest-o.timeStep) or nil,true
end
local function defenderDeadline(s,horizon)
    if type(s.opponents)~="table" then
        return oneDefenderDeadline(s,horizon,s.opponent)
    end
    local earliest,known=nil,false
    for _,source in ipairs(s.opponents) do
        local at,valid=oneDefenderDeadline(s,horizon,source)
        known=known or valid
        if at and (not earliest or at<earliest) then earliest=at end
    end
    return earliest,known
end
-- Apply to the root at dive START, not the later ball-contact position.
-- Unknown WR field geometry fails closed; DB interception is unaffected.
function Planner.canDiveFrom(s,position)
    if s.role~="WR" then return true end
    return finite(s.wrDiveGoalZ) and vec(position)
        and position.Z>=s.wrDiveGoalZ and inBounds(s,position)
end
function Planner.solve(s)
    if not validSnapshot(s) then return nil,"Invalid interception snapshot" end
    local chase=s.chase or s.role=="WR"
    local horizon,why=flightHorizon(s,chase)
    if not horizon then return nil,why end
    local step=clamp(s.timeStep or 0.035,0.015,0.08)
    local reaction=math.max(0,s.reactionDelay or 0.025)
    local range=s.range or (chase and INF or (s.diveDistance+cfg(s,"CatchRadius",3.75)+3))
    local best,bestScore=nil,INF
    local canJump=s.canJump and s.grounded
    local canDive=s.canDive
    -- Conservative vertical ceiling, independent of steering/action timing.
    -- No candidate can reach above its highest possible root apex plus the
    -- largest hand extension and catch radius. Prune high floater samples
    -- before constructing action combinations or scanning approach paths.
    local upward=math.max(0,(s.velocity or ZERO).Y)
    local apexGain=math.max(canJump and s.jumpSpeed*s.jumpSpeed/(2*s.gravity) or 0,
        upward*upward/(2*s.gravity))
    local verticalCeiling=math.max(s.position.Y,s.groundRootY or s.position.Y)+apexGain
        +math.max(cfg(s,"HandUpOffset",3.5),cfg(s,"HandOffset",0.5),cfg(s,"DiveReach",2.4))
        +math.max(cfg(s,"CatchRadius",3.75),cfg(s,"DiveCatchRadius",2.5))
        +math.max(0,-(s.margin or 0.3))
    local wr=s.role=="WR"
    local requireAirborne=wr and (s.requireAirborne==true or s.requireEndzoneCatch==true)
    local preferAirborne=wr and (s.preferAirborne==true or requireAirborne)
    local earliestAirborne=preferAirborne and s.passType=="Floater"
    local preferJumpDive=preferAirborne and s.preferJumpDive~=false
    local requireDive=wr and s.requireDive==true and not preferAirborne
    local scoringIntent=wr and finite(s.preferGoalZ)
    local uprightFinish=requireDive and scoringIntent and s.allowUprightFinish==true
    local defenderAt,defenderKnown,observedDefenderAt
    local retainedDeadline=wr and finite(s.defenderDeadline)
        and s.defenderDeadline>=s.launchAt+0.12 and s.defenderDeadline or nil
    if wr then
        observedDefenderAt,defenderKnown=defenderDeadline(s,horizon)
        defenderAt=observedDefenderAt
        if retainedDeadline then
            -- A later replicated pose cannot erase an already credible race
            -- for this pass. The caller resets this memory on a new throw.
            defenderAt=observedDefenderAt and math.min(retainedDeadline,observedDefenderAt)
                or retainedDeadline
            defenderKnown=true
        end
    end
    local bestTier,bestProgress=INF,-INF
    local nearMisses,dbNearMisses,refining,relaxed={},{},false,false
    local uprightNearMiss=false
    local function rememberNearMiss(t,margin,cells)
        if refining or not finite(margin) or margin < -3 then return end
        cells=cells or nearMisses
        local weakest
        for i,item in ipairs(cells) do
            if item.t==t then
                item.margin=math.max(item.margin,margin)
                return
            end
            if not weakest or item.margin<cells[weakest].margin then weakest=i end
        end
        if #cells<3 then
            cells[#cells+1]={t=t,margin=margin}
        elseif margin>cells[weakest].margin then
            cells[weakest]={t=t,margin=margin}
        end
    end
    local function consider(p,t)
        if s.role=="WR" and (s.passType=="Floater"
            or s.passType=="Bullet" and s.continuousBulletCatch==true) and s.grounded and not p.diveAt
            and (p.kind=="jump" or p.kind=="move") and t>p._reaction+.06 then
            -- A moving receiver cannot stop instantly while airborne. Pace
            -- the approach before takeoff and keep ordinary input through the
            -- contact window, then validate that trajectory normally below.
            local drift=(s.velocity or ZERO)*FLAT*math.min(t,p._reaction)
            local delta=(Planner.ballAt(s.arc,s.now+t-s.launchAt)-s.position-drift)*FLAT
            local capacity=travel(t-p._reaction,p._speed,p._runSpeed,p._sprintSeconds)
            if capacity>0 then
                local scale=math.min(1,delta.Magnitude/capacity)
                if scale<.45 then
                    -- Do not replace a moving approach with near-zero input.
                    -- A root already stationary at its target can still jump.
                    if ((s.velocity or ZERO)*FLAT).Magnitude>.5 or delta.Magnitude>.05 then return end
                else
                    local extent=travel(t+.08-p._reaction,p._speed*scale,p._runSpeed*scale,p._sprintSeconds)
                    if extent>explicitMoveCap(s) then return end
                    p.direction=flatUnit(delta,p.direction)
                    p._speed=p._speed*scale;p._runSpeed=p._runSpeed*scale
                    p._aimDistance=extent
                    p.stopAt=s.now+t+.08;p.movementScale=scale;p.continuousCatch=true
                end
            end
        end
        -- The explicit finish exception still needs normal contact and known
        -- coverage. Contested options retain the ordinary action/time ranking.
        if uprightFinish and not p.diveAt and (relaxed or not defenderKnown) then return end
        -- This is the same >60 ms advantage test used below, before the
        -- expensive native contact scan. Clear diving catches remain eligible.
        if uprightFinish and p.diveAt and best and not best.diveAt
            and best.safety=="contested" and defenderAt
            and s.now+t+(s.contestBuffer or 0.08)>=defenderAt
            and best.contactAt-(s.now+t)<=0.06 then return end
        local candidate,missMargin=scheduledContact(s,p,t,relaxed and 0.05 or nil,
            relaxed and 0.004 or nil,relaxed)
        if not candidate then
            if s.role=="DB" and s.allowLastResort~=false then
                rememberNearMiss(t,missMargin,dbNearMisses)
            end
            if p._diveDelay then rememberNearMiss(t,missMargin)
            elseif not refining and finite(missMargin) and missMargin>=-3 then
                -- A narrow standing/jumping window can exist while diving is
                -- unavailable. Do not require a failed dive to try that window.
                -- Keep dive refinement's three contact cells unchanged.
                uprightNearMiss=true
            end
            return
        end
        if relaxed and not inBounds(s,candidate.rootTarget) then return end
        if wr then
            if not inBounds(s,candidate.rootTarget) then return end
            local contested=defenderAt and candidate.contactAt+(s.contestBuffer or 0.08)>=defenderAt
            -- Clear catches keep ordinary movement ahead of jumps and dives.
            -- Once contested, waiting for a grounded catch can hand the ball
            -- to the defender: compare time instead, with small action biases.
            local actionTier=p.diveAt and 2 or (p.jumpAt and 1 or 0)
            -- Reject grounded contact windows before scanning their approach.
            -- This avoids spending first-contact work on impossible aerial plans.
            local nominalAir=preferAirborne and Planner.airborneFinish(s,candidate,{at=candidate.contactAt}) or nil
            if requireAirborne and not nominalAir then return end
            local aerialTouch=preferAirborne and (candidate._timingFirstTouch or Planner.firstTouch(s,candidate)) or nil
            local aerialFinish=preferAirborne and Planner.airborneFinish(s,candidate,aerialTouch) or nil
            if requireAirborne and not aerialFinish then return end
            if preferAirborne then
                actionTier=aerialFinish=="jumpDive" and (preferJumpDive and 0 or 1)
                    or aerialFinish=="jump" and (preferJumpDive and 1 or 0)
                    or (p.diveAt and 3 or 2)
            end
            local intentTouch=scoringIntent and (candidate.rootTarget.Z>=s.preferGoalZ
                or s.position.Z>=s.preferGoalZ) and Planner.firstTouch(s,candidate) or nil
            local scoringCatch=intentTouch and intentTouch.root.Z>=s.preferGoalZ
            local tier=earliestAirborne and 0 or preferAirborne and (contested and 8
                or actionTier+(scoringIntent and not scoringCatch and 4 or 0))
                or (contested and (scoringIntent and 6 or 3)
                or actionTier+(scoringIntent and not scoringCatch and 3 or 0))
            if tier>bestTier then return end
            local contestedOrder
            if tier==bestTier and contested and best and not earliestAirborne then
                local diving,bestDiving=p.diveAt~=nil,best.diveAt~=nil
                if diving~=bestDiving then
                    -- Going prone is justified only by a meaningful timing
                    -- advantage over the best available upright catch.
                    local advantage=best.contactAt-candidate.contactAt
                    contestedOrder=diving and (advantage>0.06 and -1 or 1)
                        or (advantage>=-0.06 and -1 or 1)
                else
                    local bias=not diving and p.jumpAt and 0.025 or 0
                    local bestBias=not bestDiving and best.jumpAt and 0.025 or 0
                    local difference=(candidate.contactAt+ bias)-(best.contactAt+bestBias)
                    contestedOrder=difference < -0.0001 and -1
                        or (difference > 0.0001 and 1 or 0)
                end
                if contestedOrder>0 then return end
            end
            -- On forward passes intended contact is an upper bound for first
            -- touch progress; avoid path scans that cannot improve the result.
            if not earliestAirborne and tier==bestTier and not contested and s.arc.P1.Z>=s.arc.P0.Z
                and candidate.contactPosition.Z<bestProgress-0.03 then return end
            local touch=aerialTouch or intentTouch or Planner.firstTouch(s,candidate)
            if requireDive and (not candidate.diveAt or touch.at<candidate.diveAt+.03) then
                if not (uprightFinish and not candidate.diveAt and not relaxed
                    and defenderKnown and (contested or scoringCatch)) then return end
                candidate.uprightFinishOverride=true
                candidate.uprightFinishReason=contested and "Earlier normal contested upright catch"
                    or "Normal clear upright goal catch"
            end
            if not inBounds(s,touch.root) then return end
            local better=tier<bestTier or not best
            if not better and tier==bestTier then
                if earliestAirborne then
                    local earlier=candidate.contactAt<best.contactAt-0.000001
                    local same=math.abs(candidate.contactAt-best.contactAt)<=0.000001
                    better=earlier or same and ((not candidate.diveAt and best.diveAt~=nil)
                        or (candidate.diveAt~=nil)==(best.diveAt~=nil) and candidate.margin>best.margin)
                elseif contested then
                    better=contestedOrder<0 or (contestedOrder==0 and touch.progress>bestProgress)
                else
                    better=touch.progress>bestProgress+0.03
                        or (math.abs(touch.progress-bestProgress)<=0.03 and candidate.contactAt<best.contactAt)
                end
            end
            if better then
                candidate.firstTouchAt,candidate.firstTouchRoot,candidate.firstTouchPosition=
                    touch.at,touch.root,touch.position
                candidate.effectiveProgress=touch.progress
                candidate.defenderAt=defenderAt
                candidate.safety=not defenderKnown and "unknown" or (contested and "contested" or "clear")
                candidate.safetyBasis="Possible defender reach estimate; server outcome is not guaranteed"
                candidate.prematureContact=touch.at<candidate.contactAt-0.06
                candidate.scoringCatch=scoringCatch==true
                candidate.airborneFinish=aerialFinish
                candidate.airborneRequested=preferAirborne
                candidate.airborneRequired=requireAirborne
                candidate.earliestAirborne=earliestAirborne
                candidate.airborneFallbackReason=preferAirborne and not aerialFinish
                    and "No comparably safe airborne contact; using reachable fallback" or nil
                best,bestTier,bestProgress=candidate,tier,touch.progress
            end
            return
        end
        local score=chase
            and (t+costs[p.kind]/0.18*0.005-math.min(candidate.margin,2)*0.0002)
            or (t+costs[p.kind]-math.min(candidate.margin,2)*0.025)
        if score < bestScore then best,bestScore=candidate,score end
    end
    local function delayChoices(t,ages)
        local result={}
        for _,age in ipairs(ages) do
            local delay=t-age
            if delay >= reaction and delay <= horizon then table.insert(result,delay) end
        end
        -- Also evaluate an action at the next possible input instant.
        if t-reaction >= 0.035 then table.insert(result,reaction) end
        return result
    end
    local function evaluateTime(t,allowUpright,allowDive,lateDive)
        local elapsed=s.now+t-s.launchAt
        if elapsed > 0.12 then
            local target=Planner.ballAt(s.arc,elapsed)
            local horizontal=((target-s.position)*FLAT).Magnitude
            local reachableRange=range
            if chase then
                local speed=math.max(0,s.walkSpeed)
                local runSpeed=math.max(0,s.runSpeed or speed)
                local sprintSeconds=math.max(0,s.sprintSeconds or INF)
                local drift=(s.velocity or ZERO).Magnitude*math.min(t,reaction)
                local ordinaryReach=math.max(travel(t-reaction,speed,runSpeed,sprintSeconds),
                    ((s.velocity or ZERO)*FLAT).Magnitude*t)
                reachableRange=math.min(range,ordinaryReach
                    +drift+(allowDive and canDive and s.diveDistance+cfg(s,"DiveReach",2.4) or 0)
                    +cfg(s,"CatchRadius",3.75))
            end
            if target.Y >= s.turfY+0.05 and target.Y <= verticalCeiling
                and horizontal <= reachableRange then
                local direction=flatUnit(target-s.position,s.lookDirection)
                if allowUpright then
                    if s.allowHold~=false then
                        consider(makePlan(s,"hold",direction,target,nil,nil,horizon),t)
                        if relaxed and best then return end
                    end
                    consider(makePlan(s,"move",direction,target,nil,nil,horizon),t)
                    if relaxed and best then return end
                end
                local jumps=canJump and delayChoices(t,lateDive
                    and {0.38,0.46,0.49,0.52,0.56,0.60,0.64}
                    or {0.09,0.16,0.23,0.30,0.38,0.46}) or {}
                local dives=allowDive and canDive and delayChoices(t,lateDive
                    and {0.13,0.19,0.22,0.235,0.245,0.28,0.32,0.42}
                    or {0.07,0.13,0.19,0.25,0.32,0.42}) or {}
                if allowUpright then
                    for _,j in ipairs(jumps) do
                        consider(makePlan(s,"jump",direction,target,j,nil,horizon),t)
                        if relaxed and best then return end
                    end
                end
                for _,d in ipairs(dives) do
                    consider(makePlan(s,"dive",direction,target,nil,d,horizon),t)
                    if relaxed and best then return end
                end
                if allowDive and canJump and canDive then
                    for _,j in ipairs(jumps) do
                        for _,d in ipairs(dives) do
                            -- Give the native humanoid time to enter Air before diving.
                            if d-j >= 0.06 then
                                consider(makePlan(s,"jumpDive",direction,target,j,d,horizon),t)
                                if relaxed and best then return end
                            end
                        end
                    end
                end
            end
        end
    end
    local function search(allowUpright,allowDive)
      local first=math.max(0.06,reaction+0.03)
      for t=first,horizon,step do
        evaluateTime(t,allowUpright,allowDive)
        if relaxed and best then return end
        if chase and best and (not wr or earliestAirborne) then
            -- The coarse grid only locates a reachable cell. A 35 ms wait on a
            -- descending floater can decide a contested catch, so search inside
            -- that cell with the same action candidates and robustness checks.
            -- WR yardage ranking intentionally retains its existing search.
            local lo,hi=math.max(first,t-step),t
            local earliest,earliestScore=best,bestScore
            local width=hi-lo
            if width>0.0001 then
                local cellStart=lo
                for i=1,7 do
                    local at=cellStart+width*i/8
                    best,bestScore=nil,INF
                    evaluateTime(at,allowUpright,allowDive)
                    if best then
                        hi,earliest,earliestScore=at,best,bestScore
                        break
                    end
                    lo=at
                end
                for _=1,6 do
                    local mid=(lo+hi)*0.5
                    best,bestScore=nil,INF
                    evaluateTime(mid,allowUpright,allowDive)
                    if best then
                        hi,earliest,earliestScore=mid,best,bestScore
                    else
                        lo=mid
                    end
                end
            end
            best,bestScore=earliest,earliestScore
            break
        end
      end
    end
    if s.role=="WR" then
        if preferAirborne then search(true,true)
        elseif not requireDive or uprightFinish then search(true,false) end
        -- Ordinary WR assistance remains upright-first. A submitted deep
        -- scoring route may use a clear diving goal-line catch over a shorter
        -- upright catch; contested deep windows never outrank clear catches.
        if not preferAirborne and ((requireDive and not (uprightFinish and best and best.safety=="clear" and best.scoringCatch))
            or not best or scoringIntent and not best.scoringCatch and best.safety~="contested") then
            search(false,true)
            if best and best.diveAt then
                best.diveReason=scoringIntent and "Timed full-auto deep catch" or "No reachable upright catch"
            end
        end
        if scoringIntent and best and best.diveAt then
            best.diveReason="Timed full-auto deep catch"
        end
        if requireDive and best and best.diveAt then best.diveReason="Planned sideline dive finish" end
    else
        search(true,true)
    end
    local function refinementTimes(cells)
        local times,visited={},{}
        local first=math.max(0.06,reaction+0.03)
        for _,cell in ipairs(cells) do
            for i=-4,4 do
                local at=clamp(cell.t+step*i/8,first,horizon)
                local key=math.floor(at*100000+0.5)
                if not visited[key] then
                    visited[key]=true
                    times[#times+1]=at
                end
            end
        end
        return times
    end
    local refinedTimes
    local function refine(allowUpright,allowDive,lateDive)
        refining=true
        if not refinedTimes then refinedTimes=refinementTimes(nearMisses) end
        for _,at in ipairs(refinedTimes) do
            evaluateTime(at,allowUpright,allowDive,lateDive)
            if relaxed and best then return end
        end
    end
    if not best and chase and canDive and #nearMisses>0 then
        -- A dive during jump descent resets downward speed in native DivePath.
        -- Its useful contact age can exceed the ordinary jump's flight time.
        -- Only refine the three closest failed contact cells, keeping this
        -- fallback bounded instead of densely scanning every action deadline.
        refine(false,true,true)
        if best then
            best.searchRefinement="Late jump-dive near failed contact cells"
            if wr then best.diveReason="No reachable upright catch" end
        end
    end
    if not best and wr and not requireAirborne and s.allowLastResort~=false and (uprightNearMiss or #nearMisses>0) then
        -- A WR may attempt a narrow real capsule overlap after every normal
        -- option fails. Keep the native capsule and physics; relax only the
        -- time/margin buffer, and still exhaust upright options before diving.
        relaxed,refining=true,true
        if not requireDive then search(true,false) end
        if not best and not requireDive then refine(true,false,false) end
        -- A normal-age jump-dive can miss only the robustness buffer. Keep
        -- those action ages in the bounded near-miss retry before considering
        -- longer descent dives; otherwise a valid narrow witness is omitted.
        if not best and canDive then refine(false,true,false) end
        if not best and canDive then refine(false,true,true) end
        if best and best.diveAt then best.diveReason="No normal or last-resort upright catch" end
    end
    if not best and s.role=="DB" and s.allowLastResort~=false and #dbNearMisses>0 then
        -- A failed robust search can still contain a real, narrow interception.
        -- Revisit at most three failed cells (27 times), in time order, with
        -- unchanged movement/capsule geometry. DB races for the first witness;
        -- unlike WR it does not postpone that chance to stay upright.
        relaxed,refining=true,true
        local times=refinementTimes(dbNearMisses)
        table.sort(times)
        for _,at in ipairs(times) do
            evaluateTime(at,true,true,false)
            if not best and canDive then evaluateTime(at,false,true,true) end
            if best then break end
        end
    end
    if best and relaxed then
        best.risk="last-resort"
        best.robust=false
        best.requiredMargin,best.timingMargin=0.05,0.004
        best.riskReason="Only a narrow native contact window remains"
        if s.role=="DB" and best.jumpAt and best.jumpTimingBudget==0.035 then
            best.riskReason="Narrow contact; 35 ms takeoff reserve instead of normal 60 ms"
        end
        best.searchRefinement="Bounded last-resort native contact search"
    end
    if best and requireDive and best.diveAt then best.diveReason="Planned sideline dive finish" end
    if best and best.airborneFinish=="jumpDive" then best.diveReason="Timed airborne first contact" end
    local threat
    if wr then
        local committed=retainedDeadline and defenderAt or nil
        if best and best.safety=="contested" then committed=defenderAt end
        threat={observedDefenderAt=observedDefenderAt,defenderDeadline=committed,
            defenderKnown=defenderKnown,retained=retainedDeadline~=nil}
        if best then
            best.defenderDeadline,best.observedDefenderAt=committed,observedDefenderAt
            best.threatRetained=retainedDeadline~=nil
        end
    end
    return best,best and (best.risk and "Last-resort native contact attempt"
        or (chase and "Earliest reachable contact" or "Reachable local contact"))
        or (requireAirborne and "No robust airborne WR contact available"
            or chase and "No reachable interception predicted" or "No safe local interception predicted"),threat
end

-- Pace an otherwise early upright arrival while preserving its real contact
-- witness. This uses ordinary analog movement, never a speed increase. Unsafe
-- or very slow pacing falls back to the original catch/route approach.
function Planner.timeArrival(s,p)
    if not s.continuousApproach or s.role~="WR" or not p or not p.reachable
        or p.risk or p.diveAt or p.kind=="hold" or not s.grounded
        or not finite(p.contactAt) or not finite(p.stopAt)
        or not finite(p._aimDistance) or p._aimDistance<1.5 then return nil end
    local touchAt=p.firstTouchAt or p.contactAt
    if touchAt-p.stopAt<=0.12 then return nil end
    local duration=touchAt-s.now-0.035-(p._reaction or 0)
    if duration<=0.05 then return nil end
    local originalTravel=travel(duration,p._speed,p._runSpeed or p._speed,p._sprintSeconds or INF)
    if originalTravel<=0 then return nil end
    local scale=p._aimDistance/originalTravel
    if scale<0.45 or scale>=0.99 then return nil end
    local paced={};for key,value in pairs(p) do paced[key]=value end
    paced._speed=p._speed*scale
    paced._runSpeed=(p._runSpeed or p._speed)*scale
    paced.stopAt=touchAt-0.035
    paced.movementScale, paced.timedArrival=scale,true
    if not contact(s,paced,p.contactAt-s.now) then return nil end
    local touch=Planner.firstTouch(s,paced)
    if s.requireEndzoneCatch and not Planner.airborneFinish(s,paced,touch) then return nil end
    if not inBounds(s,touch.root) or touch.at>touchAt+0.015
        or p.effectiveProgress and touch.progress<p.effectiveProgress-0.5
        or p.scoringCatch and finite(s.preferGoalZ) and touch.root.Z<s.preferGoalZ
        or p.safety=="clear" and finite(p.defenderAt)
            and paced.contactAt+(s.contestBuffer or 0.08)>=p.defenderAt then return nil end
    paced.firstTouchAt,paced.firstTouchRoot,paced.firstTouchPosition=touch.at,touch.root,touch.position
    paced.effectiveProgress=touch.progress
    return paced
end

-- A pursuit is explicitly NOT a reachable-interception claim. It keeps the
-- player moving toward the least-missed future ball position until a new solve
-- finds a real catch window. Callers should refresh it continuously.
function Planner.pursuit(s)
    if not validSnapshot(s) then return nil,"Invalid pursuit snapshot" end
    local horizon,why=flightHorizon(s,true)
    if not horizon then return nil,why end
    local reaction=math.max(0,s.reactionDelay or 0.025)
    local step=clamp(s.timeStep or 0.05,0.02,0.1)
    local best,bestScore=nil,INF
    for t=math.max(0.06,reaction+0.03),horizon,step do
        local elapsed=s.now+t-s.launchAt
        if elapsed>0.12 then
            local target=Planner.ballAt(s.arc,elapsed)
            local endzone=s.role=="WR" and s.requireEndzoneCatch==true
            if target.Y>=s.turfY+0.05 and (not endzone
                or finite(s.wrDiveGoalZ) and target.Z>=s.wrDiveGoalZ+.25) then
                local direction=flatUnit(target-s.position,s.lookDirection)
                local p=makePlan(s,"pursue",direction,target,nil,nil,horizon)
                local cf,airborne=Planner.pose(s,p,s.now+t)
                local waist,hands,radius=Planner.capsule(s,cf,airborne)
                local miss=math.max(0,Planner.segmentDistance(target,waist,hands)-radius)
                local score=miss+t*0.04
                if score<bestScore then
                    p.contactAt=s.now+t
                    p.contactPosition=target
                    p.rootTarget=cf.Position
                    p.stopAt=math.min(p.stopAt,p.contactAt)
                    p.predictedMiss=miss
                    p.reachable=false
                    p.reason="Best-effort pursuit only"
                    best,bestScore=p,score
                end
            end
        end
    end
    return best,best and "Best-effort pursuit only" or "No future ball position above turf"
end
-- A deep middle route can reach its cut after native launch. Keep that stage
-- only while observed motion/stamina still fund a jump-only catch afterward.
-- This predicts our path, not an opponent's future actions or server outcome.
-- Union of the scheduled late sprint and an already-active recovery burst.
-- Recovery may end before the late burst starts; never charge or predict the
-- intervening walk as sprint. Times are absolute server times.
function Planner.stemSprintSeconds(now,untilAt,lateStart,recoveryUntil)
    if not finite(now) or not finite(untilAt) or not finite(lateStart)
        or recoveryUntil~=nil and not finite(recoveryUntil) then return nil end
    local duration=math.max(0,untilAt-now)
    local late=clamp(untilAt-math.max(now,lateStart),0,duration)
    local recovery=recoveryUntil and math.max(0,math.min(untilAt,lateStart,recoveryUntil)-now) or 0
    return math.min(duration,late+recovery)
end
function Planner.forecastStem(s,stage,stamina)
    if not validSnapshot(s) or s.role~="WR" or not s.grounded or s.canJump~=true
        or type(stage)~="table" or not vec(stage.point) or not finite(stage.untilAt)
        or not finite(stage.sprintStartAt) or not finite(stamina)
        or not finite(stage.sprintDrain) or stage.sprintDrain<=0
        or not finite(stage.reserve) or stage.reserve<0 then return nil,"Invalid middle-stem state" end
    local remaining=stage.untilAt-s.now
    if remaining<=.04 or remaining>2 or stage.untilAt>=s.launchAt+s.arc.Flight-.12
        or not inBounds(s,stage.point) then return nil,"Middle-stem deadline reached" end
    local delta=(stage.point-s.position)*FLAT
    local distance=delta.Magnitude
    local sprint=Planner.stemSprintSeconds(s.now,stage.untilAt,stage.sprintStartAt,stage.recoveryUntilAt)
    if sprint==nil or stage.stemRunSpeed~=nil and (not finite(stage.stemRunSpeed) or stage.stemRunSpeed<=0) then
        return nil,"Invalid middle-stem movement budget"
    end
    local stemRun=math.min(s.runSpeed or s.walkSpeed,stage.stemRunSpeed or INF)
    local normal=remaining-sprint
    local capacity=normal*math.max(0,stemRun)+sprint*math.max(0,s.walkSpeed)
    if distance<.15 or capacity<distance+.15 then return nil,"Middle stem is behind schedule" end
    local after=stamina-sprint*stage.sprintDrain
    local available=math.max(0,(after-stage.reserve)/stage.sprintDrain-.12)
    if available<=0 then return nil,"Final sprint reserve unavailable" end
    local direction=delta.Unit
    -- Reject an ordinary standing contact during this extension. Catch control
    -- must get ownership now if the ball is approaching the current stem.
    for i=1,math.ceil(remaining/.04) do
        local dt=math.min(remaining,i*.04)
        local fast=Planner.stemSprintSeconds(s.now,s.now+dt,stage.sprintStartAt,stage.recoveryUntilAt)
        local progress=((dt-fast)*stemRun+fast*s.walkSpeed)*distance/capacity
        local point=s.position+direction*math.min(distance,progress)
        local elapsed=s.now+dt-s.launchAt
        if elapsed>.12 then
            local ball=Planner.ballAt(s.arc,elapsed)
            local a,b,r=Planner.capsule(s,CFrame.lookAt(point,point+direction),false)
            if Planner.segmentDistance(ball,a,b)<=r+.5 then return nil,"Ball requires catching control now" end
        end
    end
    local projected={}
    for k,v in pairs(s) do projected[k]=v end
    projected.now=stage.untilAt
    projected.position=Vector3.new(stage.point.X,s.position.Y,stage.point.Z)
    projected.velocity=direction*math.max(0,stemRun)
    projected.lookDirection,projected.steeringDirection=direction,direction
    projected.sprintSeconds=available
    projected.canDive=false
    projected.requireDive=false
    projected.requireAirborne,projected.preferAirborne=true,true
    projected.allowHold,projected.allowLastResort=false,false
    projected.continuousApproach,projected.continuousSprint=false,true
    projected.opponent,projected.opponents,projected.defenderDeadline=nil,nil,nil
    -- The controller issues one sudden directional input at this handoff.
    -- Retain .12 seconds for input/physical response; later corrections smooth.
    projected.reactionDelay=.12
    local witness,why=Planner.solve(projected)
    if not witness or witness.reachable==false or witness.diveAt
        or witness.airborneFinish~="jump" or not finite(witness.contactAt)
        or witness.contactAt-stage.untilAt+.12>available then
        return nil,why or "No funded jump catch after middle stem"
    end
    return {plan=witness,projected=projected,remaining=remaining,
        staminaAtCut=after,staminaAfterCatch=after-(witness.contactAt-stage.untilAt+.12)*stage.sprintDrain}
end
return Planner

end)()
local createTackle = (function()
-- Uses only the game's existing grab/dive controls against a confirmed carrier.
return function(Planner, runtime)
    local Config, Field, Moves = runtime.Config, runtime.Field, runtime.Moves
    local FLAT = Vector3.new(1,0,1)
    local owns, pending, aligning = false, nil, nil
    local diveTrace
    local defensiveFake,fakeCarrier,fakeUsed,fakeStartZ=nil,nil,false,nil
    local retryAt, messageUntil, lastMessage = 0, 0, nil
    local grab = Config.Tackle
    local diveConfig = Config.Moves.Dive
    local getUps = (debug and debug.getupvalues) or getupvalues
    local function xyz(v) return {x=v.X,y=v.Y,z=v.Z} end

    local function release()
        if owns then
            owns=false
            runtime.release()
        end
    end
    local function hold(h,direction)
        owns=true
        runtime.hold(h,direction)
    end
    local function endFake(reason,distance)
        local fake=defensiveFake
        if not fake then return end
        defensiveFake=nil
        runtime.log("defensiveFakeEnd",{target=fake.carrier.Name,reason=reason,
            distance=distance or fake.distance,direction=xyz(fake.direction)})
        release()
    end
    local function cancel(reason)
        endFake(reason or "cancelled")
        release()
        pending,aligning=nil,nil
        messageUntil,lastMessage=0,nil
    end
    local function unit(v,fallback)
        v=v*FLAT
        if v.Magnitude>0.001 then return v.Unit end
        fallback=(fallback or Vector3.new(0,0,-1))*FLAT
        return fallback.Magnitude>0.001 and fallback.Unit or Vector3.new(0,0,-1)
    end
    local function sameNativeOpponent(character)
        if type(getUps)~="function" or type(Moves.SetOpponent)~="function" then return false end
        local ok,values=pcall(getUps,Moves.SetOpponent)
        if not ok or type(values)~="table" then return false end
        for _,v in pairs(values) do if v==character then return true end end
        return false
    end
    local function characterParts(s)
        local ch=s.carrier
        if typeof(ch)~="Instance" or not ch:IsA("Model") or not ch.Parent
            or ch==runtime.me.Character then return end
        local root=ch:FindFirstChild("HumanoidRootPart")
        local h=ch:FindFirstChildOfClass("Humanoid")
        if root and h and h.Health>0 then return ch,root,h end
    end
    local function targetAt(root,h,t,turf)
        local velocity=root.AssemblyLinearVelocity
        local horizontal=velocity*FLAT
        if horizontal.Magnitude>80 then horizontal=horizontal.Unit*80 end
        local pos=root.Position+horizontal*t
        local y=root.Position.Y
        if h.FloorMaterial==Enum.Material.Air then
            y=math.max(turf+3,y+velocity.Y*t-0.5*workspace.Gravity*t*t)
        end
        return Vector3.new(pos.X,y,pos.Z)
    end
    local function snapshot(s,root,h,now)
        local g=workspace.Gravity
        local turf=s.geo and s.geo.TurfY or Field.TurfY
        local jumpSpeed=h.UseJumpPower and h.JumpPower or math.sqrt(2*g*math.max(0,h.JumpHeight))
        return {now=now,position=root.Position,velocity=root.AssemblyLinearVelocity,
            lookDirection=root.CFrame.LookVector,grounded=h.FloorMaterial~=Enum.Material.Air,
            jumpSpeed=jumpSpeed,gravity=g,walkSpeed=math.max(0,h.WalkSpeed),
            groundRootY=h.FloorMaterial~=Enum.Material.Air and root.Position.Y or turf+3,
            turfY=turf,diveTurfY=Field.TurfY,config=Config,
            diveDistance=diveConfig.Yards*Field.YD,clipDiveDistance=runtime.clippedDistance}
    end
    local function divePlan(s,root,h,target,targetHum,now,jumpFirst,jumpDelay)
        local snap=snapshot(s,root,h,now)
        local delay=jumpFirst and (jumpDelay or 0.08) or 0
        local requiredMargin=math.min(1.5,0.75+(target.AssemblyLinearVelocity*FLAT).Magnitude*0.025)
        local choices={unit(target.Position-root.Position,root.CFrame.LookVector)}
        for _,lead in ipairs({0.12,0.24,0.36}) do
            table.insert(choices,unit(targetAt(target,targetHum,lead+delay,snap.turfY)-root.Position,
                root.CFrame.LookVector))
        end
        local best
        for _,requested in ipairs(choices) do
            local p={kind=jumpFirst and "jumpDive" or "dive",direction=requested,
                _reaction=0,_speed=snap.walkSpeed,_runSpeed=snap.walkSpeed,
                _sprintSeconds=math.huge,_aimDistance=snap.walkSpeed*delay,
                _jumpDelay=jumpFirst and 0 or nil}
            -- Native DB/RAC dives snap toward the current carrier when the
            -- requested direction is within their aim cone. Model that snap.
            local originCF,originAir,originVY=Planner.pose(snap,p,now+delay)
            local origin=originCF.Position
            local toCarrier=unit(targetAt(target,targetHum,delay,snap.turfY)-origin,requested)
            local actual=toCarrier:Dot(requested)>0.7 and toCarrier or requested
            local flight=table.clone(snap)
            flight.now,flight.position,flight.grounded=now+delay,origin,not originAir
            flight.velocity=requested*snap.walkSpeed+Vector3.new(0,originVY,0)
            local flightPlan={kind="dive",direction=actual,_reaction=0,_speed=0,
                _aimDistance=0,_diveDelay=0}
            local start=math.max(diveConfig.Time*(diveConfig.MinFrac or 0.15)+0.015,0.065)
            local consecutive,windowStart,windowMargin=0,nil,math.huge
            for age=start,diveConfig.Time-0.005,0.02 do
                local t=delay+age
                local cf=Planner.pose(flight,flightPlan,now+t)
                local q=targetAt(target,targetHum,t,snap.turfY)
                local delta=(q-cf.Position)*FLAT
                local forward=delta:Dot(actual)
                local lateral=(delta-actual*forward).Magnitude
                local vertical=math.abs(q.Y-cf.Position.Y)
                local margin=math.min(diveConfig.Reach-forward,forward+diveConfig.Range,
                    diveConfig.Range-lateral,4-vertical)
                if margin>=requiredMargin then
                    consecutive=consecutive+1
                    windowStart=windowStart or t
                    windowMargin=math.min(windowMargin,margin)
                    -- Demand sustained contact through three native scan
                    -- samples, rather than a single grazing prediction.
                    if consecutive>=3 then
                        local candidate={direction=requested,actualDirection=actual,
                            contactDelay=windowStart,contactWindow=t-windowStart,
                            margin=windowMargin,requiredMargin=requiredMargin,jumpFirst=jumpFirst,
                            jumpDelay=delay}
                        if not best or windowStart<best.contactDelay then
                            best=candidate
                        end
                        break
                    end
                else
                    consecutive,windowStart,windowMargin=0,nil,math.huge
                end
            end
        end
        return best
    end
    local function selectDive(s,root,h,target,targetHum,now)
        -- Preserve the earliest robust ground opportunity. Jump only when the
        -- carrier has no reachable ground-dive witness.
        local best=divePlan(s,root,h,target,targetHum,now,false)
        if best then return best end
        if runtime.canJump(h,now) then
            return divePlan(s,root,h,target,targetHum,now,true,.08)
        end
    end
    local function logPlan(s,root,h,target,candidate,action)
        runtime.log("tacklePlan",{action=action,role=s.role,phase=s.phase,
            target=target.Parent.Name,targetPosition=xyz(target.Position),
            targetVelocity=xyz(target.AssemblyLinearVelocity),position=xyz(root.Position),
            velocity=xyz(root.AssemblyLinearVelocity),direction=xyz(candidate.direction),
            actualDirection=candidate.actualDirection and xyz(candidate.actualDirection) or nil,
            contactIn=candidate.contactDelay,contactWindow=candidate.contactWindow,
            margin=candidate.margin,requiredMargin=candidate.requiredMargin,
            grounded=h.FloorMaterial~=Enum.Material.Air,jump=action=="jumpDive" or action=="grabJump"})
    end
    local function traceDive(s,root,h,target,now)
        diveTrace={root=root,humanoid=h,target=target,started=now,nextAt=now+0.075,
            expires=now+0.4,role=s.role,phase=s.phase}
    end
    local function sampleDive(now)
        local trace=diveTrace
        if not trace then return end
        if now>trace.expires or not trace.target.Parent then diveTrace=nil;return end
        if now<trace.nextAt then return end
        trace.nextAt=now+0.075
        local delta=trace.target.Position-trace.root.Position
        runtime.log("tackleSample",{role=trace.role,phase=trace.phase,age=now-trace.started,
            target=trace.target.Parent.Name,targetPosition=xyz(trace.target.Position),
            targetVelocity=xyz(trace.target.AssemblyLinearVelocity),position=xyz(trace.root.Position),
            velocity=xyz(trace.root.AssemblyLinearVelocity),horizontal=(delta*FLAT).Magnitude,
            vertical=delta.Y,diving=trace.humanoid.PlatformStand,
            grounded=trace.humanoid.FloorMaterial~=Enum.Material.Air})
    end
    local function finishAttempt(now,text)
        release()
        pending,aligning=nil,nil
        lastMessage,messageUntil=text,now+0.25
        return true,text
    end
    local function jumpGrabWindow(s,root,h,target,targetHum,now)
        local snap=snapshot(s,root,h,now)
        local direction=unit(target.Position-root.Position,root.CFrame.LookVector)
        local initialDistance=((target.Position-root.Position)*FLAT).Magnitude
        for t=0.06,0.3,0.02 do
            local travel=math.min(math.max(0,initialDistance-0.3),snap.walkSpeed*t)
            local pos=root.Position+direction*travel
            pos=Vector3.new(pos.X,root.Position.Y+snap.jumpSpeed*t-0.5*snap.gravity*t*t,pos.Z)
            local q=targetAt(target,targetHum,t,snap.turfY)
            if ((q-pos)*FLAT).Magnitude<=grab.GrabRange-0.15 and math.abs(q.Y-pos.Y)<=3.6 then
                return direction,t
            end
        end
    end
    local function fieldRoom(s,position)
        local g=s.geo
        local offset=s.offset or Vector3.zero
        local minX=g and g.MinX or Field.MinX+offset.X
        local maxX=g and g.MaxX or Field.MaxX+offset.X
        local minZ=g and g.BackZ or Field.BackZ+offset.Z
        local maxZ=g and g.EndZ or Field.EndZ+offset.Z
        return math.min(position.X-minX,maxX-position.X,position.Z-minZ,maxZ-position.Z)
    end
    local function clearFakePath(s,root,direction,distance)
        if fieldRoom(s,root.Position+direction*distance)<1.5 then return false end
        if type(runtime.clippedDistance)~="function" then return true end
        local ok,clipped=pcall(runtime.clippedDistance,root.Position,direction,distance)
        return ok and type(clipped)=="number" and clipped>=distance-0.01
    end
    local function earlyRun(s,target)
        local yards=s.geo and s.geo.YD or Field.YD
        local goal=s.geo and s.geo.GoalZ or Field.GoalZ+(s.offset or Vector3.zero).Z
        local remaining=goal-target.Position.Z
        local advanced=target.Position.Z-(fakeStartZ or target.Position.Z)
        return remaining>12*yards and advanced<8*yards,remaining/yards,advanced/yards
    end
    local function chooseDefensiveFake(s,root,h,target,distance,stopRange)
        if h.FloorMaterial==Enum.Material.Air or h.WalkSpeed<=0 then return end
        local toward=unit(target.Position-root.Position,root.CFrame.LookVector)
        local velocity=target.AssemblyLinearVelocity*FLAT
        local speed=velocity.Magnitude
        if speed<8 then return end
        local closing=velocity:Dot(-toward)
        local lane=((root.Position-target.Position)*FLAT
            -velocity.Unit*((root.Position-target.Position)*FLAT):Dot(velocity.Unit)).Magnitude
        if closing<8 or closing/speed<0.75 or lane>math.max(7,distance*0.2) then return end
        local duration=math.min(0.45,(distance-stopRange-2)/(closing+h.WalkSpeed*0.65))
        if duration<0.25 then return end
        local lateral=Vector3.new(-toward.Z,0,toward.X)
        local facing=unit(target.CFrame.LookVector,velocity)
        local best,bestScore
        for _,sign in ipairs({1,-1}) do
            local direction=(toward*0.65+lateral*(0.76*sign)).Unit
            local endpoint=root.Position+direction*h.WalkSpeed*duration
            if clearFakePath(s,root,direction,h.WalkSpeed*duration) then
                local fromLine=(endpoint-target.Position)*FLAT
                local sideDistance=(fromLine-facing*fromLine:Dot(facing)).Magnitude
                local score=sideDistance+math.min(20,fieldRoom(s,endpoint))*0.2
                if not bestScore or score>bestScore then
                    best,bestScore={direction=direction,duration=duration},score
                end
            end
        end
        return best
    end

    local api={cancel=function(resetPossession)
        cancel("phase or control changed")
        if resetPossession then fakeCarrier,fakeUsed,fakeStartZ=nil,false,nil end
    end}
    function api.update(s,root,h,now,dt)
        -- Diagnostic sampling owns no input and can finish after native dive
        -- movement makes Upright false and clears the action state below.
        sampleDive(now)
        local running=s.phase=="RAC" or s.phase=="Run"
        local qbLive=s.mode=="Team" and s.phase=="Live" and s.carrierRole=="QB"
        if not s.enabled or s.testing or s.alive==false or s.arc or s.role~="DB"
            or not s.enemyCarrier or not s.defending or not (running or qbLive) then
            cancel("phase or possession changed");fakeCarrier,fakeUsed,fakeStartZ=nil,false,nil;return false
        end
        local ch,target,targetHum=characterParts(s)
        if not ch or not root or not h or h.Health<=0 or h.Sit or root.Anchored then
            cancel("character unavailable");fakeCarrier,fakeUsed,fakeStartZ=nil,false,nil;return false
        end
        if fakeCarrier~=ch then
            cancel("carrier changed");fakeCarrier,fakeUsed,fakeStartZ=ch,false,target.Position.Z
        end
        if pending and pending.carrier~=ch then cancel() end
        local delta=target.Position-root.Position
        local distance=(delta*FLAT).Magnitude
        local vertical=math.abs(delta.Y)
        local upright=Moves.Upright()
        if now<messageUntil then return true,lastMessage end
        if not upright then
            cancel(); return false
        end
        local diveReach=diveConfig.Yards*Field.YD+diveConfig.Reach
        local fakeStopRange=diveReach+3
        local early,goalYards,advancedYards=earlyRun(s,target)
        if not early then fakeUsed=true end
        if defensiveFake then
            local reason
            if not running then reason="running phase ended"
            elseif not early then reason="committing downfield"
            elseif distance<=fakeStopRange then reason="entered tackle range"
            elseif now>=defensiveFake.deadline then reason="completed"
            elseif h.FloorMaterial==Enum.Material.Air then reason="left ground"
            elseif not clearFakePath(s,root,defensiveFake.direction,
                h.WalkSpeed*math.max(0,defensiveFake.deadline-now)) then reason="path blocked" end
            if reason then endFake(reason,distance)
            else
                hold(h,defensiveFake.direction)
                return true,"Defensive sidestep"
            end
        end

        -- Check the game's actual grab target immediately before invoking its
        -- native tackle callback. A nil target would otherwise trigger a dive.
        local validGrab=false
        if distance<=grab.GrabRange and vertical<=4 and type(runtime.nativeGrabTarget)=="function" then
            local ok,current=pcall(runtime.nativeGrabTarget)
            validGrab=ok and current==target
        end
        if validGrab and now>=retryAt and type(runtime.nativeTackle)=="function" then
            logPlan(s,root,h,target,{direction=unit(delta,root.CFrame.LookVector),contactDelay=0},"grab")
            runtime.nativeTackle()
            retryAt=now+(grab.GrabCooldown or 0.6)
            runtime.log("tackleGrabAttempt",{target=ch.Name,distance=distance,vertical=vertical})
            return finishAttempt(now,"Close tackle attempted")
        end

        if pending then
            if now>pending.expires or not sameNativeOpponent(ch) then
                cancel(); retryAt=now+0.12; return false
            end
            if pending.kind=="grabJump" then
                if distance>grab.GrabRange+0.8 then
                    cancel(); retryAt=now+0.12; return false
                end
                hold(h,distance>0.4 and unit(delta,root.CFrame.LookVector) or Vector3.zero)
                return true,"Jumping for close tackle"
            end
            hold(h,pending.direction)
            if now<pending.diveAt then return true,"Jumping toward ball carrier" end
            if h.FloorMaterial~=Enum.Material.Air then
                return true,"Waiting for tackle jump"
            end
            local fresh=divePlan(s,root,h,target,targetHum,now,false)
            if fresh and runtime.canDive(now) then
                hold(h,fresh.direction)
                logPlan(s,root,h,target,fresh,"jumpDive")
                if runtime.dive(h,fresh.direction,now,"tackleDive") then
                    traceDive(s,root,h,target,now)
                    retryAt=now+0.2
                    return finishAttempt(now,"Jump-dive tackle attempted")
                end
            end
            cancel(); retryAt=now+0.12; return false
        end
        if now<retryAt then release(); return false end

        -- A close higher carrier can be grabbed after an ordinary jump. This
        -- also works for a live QB while native diving is still disabled.
        if distance<=grab.GrabRange and delta.Y>4 and sameNativeOpponent(ch)
            and runtime.canJump(h,now) then
            local direction,contact=jumpGrabWindow(s,root,h,target,targetHum,now)
            if direction then
                hold(h,direction)
                logPlan(s,root,h,target,{direction=direction,contactDelay=contact},"grabJump")
                runtime.jump(h,now,"tackleJump")
                pending={kind="grabJump",carrier=ch,direction=direction,expires=now+0.3}
                runtime.log("tackleJumpPlan",{target=ch.Name,action="grab",contactIn=contact,
                    position=xyz(root.Position)})
                return true,"Jumping for close tackle"
            end
        end

        -- Only a short alignment step inside actual grab range is allowed.
        -- Manual movement remains untouched while the carrier is farther away.
        if distance<=grab.GrabRange and vertical<=4 and sameNativeOpponent(ch) then
            if not aligning or aligning.carrier~=ch then
                aligning={carrier=ch,expires=now+0.16}
            end
            if now<aligning.expires then
                hold(h,distance>0.3 and unit(delta,root.CFrame.LookVector) or Vector3.zero)
                return true,"Aligning close tackle"
            end
            cancel(); retryAt=now+0.15; return false
        end
        if aligning then cancel() end

        if running and early and not fakeUsed and distance>=math.max(35,2*diveReach)
            and sameNativeOpponent(ch) then
            local fake=chooseDefensiveFake(s,root,h,target,distance,fakeStopRange)
            if fake then
                fakeUsed=true
                defensiveFake={carrier=ch,direction=fake.direction,deadline=now+fake.duration,distance=distance}
                hold(h,fake.direction)
                runtime.log("defensiveFakeStart",{target=ch.Name,distance=distance,
                    direction=xyz(fake.direction),duration=fake.duration,position=xyz(root.Position),
                    targetPosition=xyz(target.Position),targetVelocity=xyz(target.AssemblyLinearVelocity),
                    goalYards=goalYards,advancedYards=advancedYards})
                return true,"Defensive sidestep"
            end
        end
        local maxRange=diveConfig.Yards*Field.YD+diveConfig.Reach-0.4
        if not running or distance>maxRange or not sameNativeOpponent(ch)
            or not runtime.canDive(now) then
            release(); return false
        end
        local candidate=selectDive(s,root,h,target,targetHum,now)
        if candidate and not candidate.jumpFirst then
            hold(h,candidate.direction)
            logPlan(s,root,h,target,candidate,"dive")
            if runtime.dive(h,candidate.direction,now,"tackleDive") then
                traceDive(s,root,h,target,now)
                retryAt=now+0.2
                return finishAttempt(now,"Dive tackle attempted")
            end
            release(); retryAt=now+0.12; return false
        end
        if candidate and candidate.jumpFirst then
            if runtime.canJump(h,now) then
                hold(h,candidate.direction)
                logPlan(s,root,h,target,candidate,"jumpDive")
                runtime.jump(h,now,"tackleJump")
                pending={kind="jumpDive",carrier=ch,direction=candidate.direction,
                    diveAt=now+(candidate.jumpDelay or .08),expires=now+math.max(.24,(candidate.jumpDelay or .08)+.16)}
                runtime.log("tackleJumpPlan",{target=ch.Name,position=xyz(root.Position),
                    contactIn=candidate.contactDelay,margin=candidate.margin})
                return true,"Jumping toward ball carrier"
            end
        end
        release(); return false
    end
    return api
end

end)()
local WRApproach = (function()
-- Pure WR fake/return selection. The caller owns input and permits one fake per throw.
local Approach={}
local FLAT=Vector3.new(1,0,1)
local INF=math.huge
local RATE=9
local SLACK=0.125
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<INF end
local function vec(v) return typeof(v)=="Vector3" end
local function copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local function flatUnit(v,fallback)
    v=(v or Vector3.zero)*FLAT
    if v.Magnitude>0.001 then return v.Unit end
    return fallback or Vector3.new(0,0,1)
end
local function heading(s,fallback)
    if vec(s.steeringDirection) and (s.steeringDirection*FLAT).Magnitude>0.001 then
        return flatUnit(s.steeringDirection)
    end
    if vec(s.velocity) and (s.velocity*FLAT).Magnitude>1 then return flatUnit(s.velocity) end
    return flatUnit(s.lookDirection,fallback)
end
local function angle(a,b)
    local x,y=math.atan2(a.X,a.Z),math.atan2(b.X,b.Z)
    return (y-x+math.pi)%(2*math.pi)-math.pi
end
local function tier(p) return p.diveAt and 2 or (p.jumpAt and 1 or 0) end
local function risk(safety) return safety=="clear" and 0 or (safety=="contested" and 2 or 1) end
local function inBounds(s,p)
    local b=s.bounds
    return type(b)=="table" and (not finite(b.minX) or p.X>=b.minX)
        and (not finite(b.maxX) or p.X<=b.maxX)
        and (not finite(b.minZ) or p.Z>=b.minZ)
        and (not finite(b.maxZ) or p.Z<=b.maxZ)
end
local function clearSegment(s,a,b)
    local delta=(b-a)*FLAT
    if delta.Magnitude<0.001 or type(s.clipDiveDistance)~="function" then return true end
    local ok,n=pcall(s.clipDiveDistance,a,delta.Unit,delta.Magnitude)
    return ok and finite(n) and n>=delta.Magnitude-0.01
end
local function speedAt(s,t)
    return math.max(0,t<(s.sprintSeconds or INF) and s.walkSpeed or (s.runSpeed or s.walkSpeed))
end
local function advanceOpponent(source,t,s)
    if type(source)~="table" or not vec(source.position) then return source end
    local o=copy(source)
    local v=vec(o.velocity) and o.velocity or Vector3.zero
    local p=o.position+v*FLAT*t
    if o.grounded==false then
        local g=o.gravity or s.gravity
        local y=o.position.Y+v.Y*t-0.5*g*t*t
        local floor=o.groundRootY or s.turfY+3
        if y<=floor and v.Y-g*t<=0 then y=floor;o.grounded=true;v=v*FLAT
        else v=Vector3.new(v.X,v.Y-g*t,v.Z) end
        p=Vector3.new(p.X,y,p.Z)
    end
    o.position,o.velocity=p,v
    return o
end
local function advance(s,motion)
    local f=copy(s)
    f.allowLastResort=false
    f.now=s.now+motion.duration
    f.position=motion.position
    f.sprintSeconds=math.max(0,(s.sprintSeconds or INF)-motion.duration)
    f.walkSpeed=f.sprintSeconds>0 and s.walkSpeed or (s.runSpeed or s.walkSpeed)
    f.velocity=motion.heading*f.walkSpeed
    f.lookDirection,f.steeringDirection=motion.heading,motion.heading
    f.reactionDelay=0
    f.maxHorizon=math.max(0.01,(s.maxHorizon or 4)-motion.duration)
    f.opponent=advanceOpponent(s.opponent,motion.duration,s)
    if type(s.opponents)=="table" then
        f.opponents={}
        for _,o in ipairs(s.opponents) do table.insert(f.opponents,advanceOpponent(o,motion.duration,s)) end
    end
    return f
end
local function overlaps(Planner,s,p,direction,t)
    if not s.arc or s.now+t-s.launchAt<=0.12 then return false end
    local ball=Planner.ballAt(s.arc,s.now+t-s.launchAt)
    local cf=CFrame.lookAt(p,p+direction)
    local waist,hands,radius=Planner.capsule(s,cf,false)
    return Planner.segmentDistance(ball,waist,hands)<=radius+0.05
end
-- Integrate the same bounded heading rotation used by the controller. Small
-- steps also check the actual curved path, rather than only its endpoint.
local function moveFor(Planner,s,direction,duration)
    local initial=heading(s,direction)
    local current=initial
    local p=s.position
    local reaction=math.max(0,s.reactionDelay or 0)
    local t=0
    if not inBounds(s,p) then return nil,"field boundary" end
    if overlaps(Planner,s,p,current,0) then return nil,"ball already in catch range" end
    while t<duration-0.000001 do
        local step=math.min(0.02,duration-t)
        if t<reaction then step=math.min(step,reaction-t) end
        local a=math.atan2(current.X,current.Z)
        local turn=t<reaction and 0 or math.clamp(angle(current,direction),-RATE*step,RATE*step)
        local midpoint=Vector3.new(math.sin(a+turn*0.5),0,math.cos(a+turn*0.5))
        local nextP=p+midpoint*speedAt(s,t+step*0.5)*step
        current=Vector3.new(math.sin(a+turn),0,math.cos(a+turn))
        if not inBounds(s,nextP) then return nil,"field boundary" end
        if not clearSegment(s,p,nextP) then return nil,"wall" end
        t=t+step;p=nextP
        if overlaps(Planner,s,p,current,t) then return nil,"catch during detour" end
    end
    return {position=p,heading=current,duration=duration,entryDirection=initial}
end
local function baselineOf(p)
    local catchAt=p.firstTouchAt or p.contactAt
    return {safety=p.safety or "unknown",risk=risk(p.safety),actionTier=tier(p),
        catchAt=catchAt,latestAllowedContactAt=catchAt+0.015,defenderAt=p.defenderAt,
        target=p.approachTarget or p.rootTarget,effectiveProgress=p.effectiveProgress}
end
function Approach.checkReturn(Planner,s,fake)
    local b=fake and fake.baseline
    if not b or not s.grounded or not vec(s.position) or not vec(b.target) then
        return nil,"No grounded return forecast"
    end
    local direction=flatUnit(b.target-s.position,heading(s))
    local initial=heading(s,direction)
    local duration=math.max(0,s.reactionDelay or 0)+math.abs(angle(initial,direction))/RATE
    local motion,why=moveFor(Planner,s,direction,duration)
    if not motion then return nil,why end
    local future=advance(s,motion)
    local p=Planner.solve(future)
    if not p or not p.reachable or p.risk then return nil,"Return catch is unreachable" end
    local catchAt=p.firstTouchAt or p.contactAt
    if not finite(catchAt) or not finite(p.contactAt) then return nil,"Invalid contact timing" end
    if risk(p.safety)>b.risk then return nil,"Defender risk increased" end
    if tier(p)>b.actionTier then return nil,"Return needs an additional action" end
    if catchAt>b.latestAllowedContactAt then return nil,"Return would delay the catch" end
    if b.safety=="clear" and finite(b.defenderAt)
        and p.contactAt+(s.contestBuffer or 0.08)>=b.defenderAt then
        return nil,"Original defender deadline reached"
    end
    local loss=b.effectiveProgress and p.effectiveProgress and b.effectiveProgress-p.effectiveProgress or 0
    if loss>1 then return nil,"Return sacrifices catch progress" end
    local arrivalAt=math.max(future.now,p.stopAt or catchAt)
    local slack=catchAt-arrivalAt
    return p,slack,{snapshot=future,turnDuration=duration,direction=direction,
        targetDirection=direction,position=motion.position,catchAt=catchAt,
        arrivalAt=arrivalAt,slack=slack,progressLoss=loss,entryDirection=initial}
end
function Approach.choose(Planner,s,p)
    if type(p)=="table" and p.risk then return nil,"Last-chance catch needs a direct approach" end
    if type(s)~="table" or type(p)~="table" or s.role~="WR" or not s.grounded
        or not p.reachable or not finite(s.now) or not finite(s.walkSpeed)
        or s.walkSpeed<=0 or not vec(s.position) or not vec(p.rootTarget)
        or not finite(p.contactAt) then return nil,"No grounded WR approach" end
    local b=baselineOf(p)
    local spare=b.catchAt-math.max(s.now,p.stopAt or b.catchAt)
    if spare<=SLACK or b.catchAt-s.now<=0.2 then return nil,"No spare approach time" end
    local direct=flatUnit(b.target-s.position,flatUnit(s.lookDirection))
    local away=-direct
    local lateral=Vector3.new(-direct.Z,0,direct.X)
    local nearest,nearestDistance
    for _,o in ipairs(s.opponents or (s.opponent and {s.opponent}) or {}) do
        if vec(o.position) then
            local distance=((o.position-s.position)*FLAT).Magnitude
            if not nearestDistance or distance<nearestDistance then nearest,nearestDistance=o,distance end
        end
    end
    if nearest and lateral:Dot(s.position-nearest.position)<0 then lateral=-lateral end
    local choices={away,(away+lateral*0.85).Unit,(away-lateral*0.85).Unit}
    local best,blockedStraight
    local maxDuration=math.min(2,b.catchAt-s.now-SLACK)
    for index,direction in ipairs(choices) do
        if index>1 and not blockedStraight then break end
        local initial=heading(s,direction)
        local minimum=math.max(0.08,math.max(0,s.reactionDelay or 0)+math.abs(angle(initial,direction))/RATE+0.06)
        local blocked=false
        -- A backward diagonal can initially carry forward through its curved
        -- entry. Find the first genuinely-away endpoint before solver probes.
        while minimum<=maxDuration do
            local entry,reason=moveFor(Planner,s,direction,minimum)
            if not entry then
                blocked=reason=="field boundary" or reason=="wall"
                minimum=maxDuration+1
                break
            end
            if (entry.position-s.position):Dot(direct)<=-0.35 then break end
            minimum=minimum+0.04
        end
        local function evaluate(duration)
            local motion,reason=moveFor(Planner,s,direction,duration)
            if not motion then
                if reason=="field boundary" or reason=="wall" then blocked=true end
                return nil
            end
            if (motion.position-s.position):Dot(direct)>-0.35 then return nil end
            local f={baseline=b}
            local nextPlan,slack,forecast=Approach.checkReturn(Planner,advance(s,motion),f)
            if not nextPlan or slack<SLACK then return nil end
            return {direction=direction,duration=duration,waypoint=motion.position,
                entryDirection=initial,followupPlan=nextPlan,deadline=s.now+duration,
                commitBy=forecast.catchAt-SLACK,spareTime=spare,baseline=b,
                baselineSafety=b.safety,latestAllowedContactAt=b.latestAllowedContactAt,
                followupActionTier=b.actionTier,catchAt=forecast.catchAt,arrivalAt=forecast.arrivalAt,
                slack=slack,remainingArrivalSlack=slack,turnBudget=forecast.turnDuration,
                turnForecast=forecast,progressLoss=forecast.progressLoss}
        end
        if minimum<=maxDuration then
            -- Two endpoint probes plus eight refinements: at most ten normal
            -- planner calls for the preferred direction, with cheap path pruning.
            local low=evaluate(minimum)
            local high=evaluate(maxDuration)
            local chosen=high or low
            if low and not high then
                local lo,hi=minimum,maxDuration
                for _=1,8 do
                    local middle=(lo+hi)*0.5
                    local candidate=evaluate(middle)
                    if candidate then lo=middle;chosen=candidate else hi=middle end
                end
            end
            if chosen and (not best or chosen.slack<best.slack-0.005
                or (math.abs(chosen.slack-best.slack)<=0.005 and chosen.duration>best.duration)) then best=chosen end
        end
        if index==1 then
            blockedStraight=blocked
            if best and best.slack<=0.16 then return best end
        end
    end
    if best then return best end
    return nil,"Detour would compromise the catch"
end
return Approach

end)()
local Motion = (function()
-- Pure motion classification. No services, character mutation, or game inputs.
-- groundRootY, when supplied, MUST be a trusted standing/pre-takeoff reference;
-- do not derive it from the current elevated root merely because FloorMaterial
-- still reports ground. Without that reference use the normal field turf+3.
local Motion={}
local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end
-- Full-auto reserves are excluded from both reach prediction and dispatch.
-- A short dispatch allowance covers the next frame/native sprint-off delay.
function Motion.sprintBudget(role,stamina,drain,policy)
    stamina=finite(stamina) and math.max(0,stamina) or 0
    drain=finite(drain) and math.max(1,drain) or 25
    local requested=type(policy)=="table" and (role=="DB" and policy.dbReserve
        or role=="WR" and policy.wrReserve) or nil
    local reserved=finite(requested)
    local reserve=reserved and math.max(0,math.min(95,requested)) or 2
    local dispatch=reserved and drain*.12 or 0
    local available=math.max(0,stamina-reserve-dispatch)
    return {seconds=available/drain,canSprint=available>0,
        reserve=reserve,cutoff=reserve+dispatch,enforced=reserved}
end
-- SprintOn acknowledges the local request, not the server's actual speed.
-- Keep this observation across replans; callers clear it when ownership or the
-- character changes. Penalties and confirmed sprint use their own forecasts.
function Motion.sprintState(previous,now,actualSpeed,sprinting,runSpeed,sprintSpeed)
    if not sprinting or not finite(now) or not finite(actualSpeed)
        or actualSpeed<runSpeed*.95 or actualSpeed>=sprintSpeed*.95 then return nil end
    local since=type(previous)=="table" and previous.since or nil
    if not finite(since) or since>now then since=now end
    local age=math.max(0,now-since)
    -- The local acknowledgement can lead native speed by several frames.
    -- Even the first forecast must use the speed actually observed.
    return {since=since,age=age,pending=true}
end
-- A live movement penalty must affect the forecast. A delayed sprint request
-- instead uses observed normal speed with scale1 until sprint is confirmed.
function Motion.locomotion(actualSpeed,sprinting,runSpeed,sprintSpeed,sprintSeconds,sprintState)
    local scale=1
    if finite(actualSpeed) and actualSpeed>=0 and actualSpeed<runSpeed*.95 then
        local expected=sprinting and sprintSpeed or runSpeed
        scale=math.max(0,math.min(1,actualSpeed/math.max(1,expected)))
    end
    local pending=scale==1 and sprinting and sprintSeconds>0
        and finite(actualSpeed) and actualSpeed>=runSpeed*.95 and actualSpeed<sprintSpeed*.95
    local speed=pending and math.min(sprintSpeed,actualSpeed)
        or (sprintSeconds>0 and sprintSpeed or runSpeed)*scale
    return {walkSpeed=speed,runSpeed=pending and math.min(runSpeed,speed) or runSpeed*scale,
        speedScale=scale,sprintPending=pending==true,
        sprintPendingAge=type(sprintState)=="table" and sprintState.age or nil}
end
function Motion.shouldRefreshLocomotion(previous,current,blocked)
    return not blocked and type(previous)=="table" and type(current)=="table"
        and ((previous.sprintPending==true)~=(current.sprintPending==true)
            or math.abs((current.speedScale or 1)-(previous.speedScale or 1))>.08)
end
function Motion.classify(s)
    s=type(s)=="table" and s or {}
    local nativeAirborne=s.floorAirborne==true
    local base=finite(s.groundRootY) and s.groundRootY
        or (finite(s.turfY) and s.turfY+3 or nil)
    local valid=finite(s.rootY) and finite(s.verticalSpeed) and base~=nil
    local elevation=valid and s.rootY-base or nil
    local elevated=valid and elevation>0.15
    local ascent=elevated and s.verticalSpeed>5 or false
    local descent=elevated and s.verticalSpeed < -5 or false
    -- Optional already-confirmed airborne state keeps an apex from looking
    -- grounded. A stationary elevated character with no such history is NOT
    -- classified as ascending or airborne from height alone.
    local knownAloft=elevated and s.knownAirborne==true or false
    local physicalAirborne=nativeAirborne or ascent or descent or knownAloft
    local reason=nativeAirborne and "native airborne"
        or ascent and "rising despite ground flag"
        or descent and "falling despite ground flag"
        or knownAloft and "confirmed flight above ground"
        or not valid and "invalid motion snapshot"
        or "grounded"
    return {
        valid=valid,
        grounded=valid and not physicalAirborne,
        physicalAirborne=physicalAirborne,
        nativeAirborne=nativeAirborne,
        -- Catching and DivePath read the native floor flag themselves. This
        -- helper must never grant their airborne reach/momentum prematurely.
        reachAirborne=nativeAirborne,
        diveModeMatchesMotion=valid and physicalAirborne==nativeAirborne,
        ascendingDespiteGround=not nativeAirborne and ascent,
        fallingDespiteGround=not nativeAirborne and descent,
        elevation=elevation,
        groundRootY=base,
        reason=reason,
    }
end
-- A pursuit solved while the native floor flag lagged behind takeoff had
-- neither airborne catch reach nor a legal dive. Revisit that restricted
-- forecast as soon as native airborne actions are available, without
-- interrupting a healthy jump/dive plan or an action still being confirmed.
function Motion.shouldRefreshPursuit(plan,previous,current,blocked)
    return not blocked and type(plan)=="table" and plan.kind=="pursue"
        and plan.reachable==false and type(previous)=="table"
        and previous.physicalAirborne==true and previous.nativeAirborne==false
        and previous.reachAirborne==false and previous.canDive==false
        and type(current)=="table" and current.nativeAirborne==true
        and current.diveModeMatchesMotion==true
end
return Motion

end)()
local PlayerAvoidance = (function()
-- Pure, local movement arbitration for physical player collisions only.
-- No character properties, input bindings, timers, or game services are changed.
local Avoidance={}
local FLAT=Vector3.new(1,0,1)
local ZERO=Vector3.zero
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vec(v) return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function rotate(v,angle)
    local c,s=math.cos(angle),math.sin(angle)
    return Vector3.new(v.X*c+v.Z*s,0,v.Z*c-v.X*s)
end
local function turn(from,to,limit,side)
    if not vec(from) or from.Magnitude<.001 then return to end
    local angle=math.acos(clamp(from:Dot(to),-1,1))
    if angle<=limit then return to end
    local cross=from.Z*to.X-from.X*to.Z
    local sign=math.abs(cross)>.00001 and (cross>0 and 1 or -1) or side or 1
    return rotate(from,sign*limit)
end
local function inside(point,bounds)
    if bounds==nil then return true end
    if type(bounds)~="table" or not finite(bounds.minX) or not finite(bounds.maxX)
        or not finite(bounds.minZ) or not finite(bounds.maxZ)
        or bounds.minX>=bounds.maxX or bounds.minZ>=bounds.maxZ then return false end
    return point.X>=bounds.minX and point.X<=bounds.maxX
        and point.Z>=bounds.minZ and point.Z<=bounds.maxZ
end
local function clearance(relative,relativeVelocity,horizon)
    local speed2=relativeVelocity:Dot(relativeVelocity)
    local at=speed2>.00001 and clamp(-relative:Dot(relativeVelocity)/speed2,0,horizon) or 0
    return (relative+relativeVelocity*at).Magnitude,(relative+relativeVelocity*horizon).Magnitude,at
end

function Avoidance.update(previous,input)
    input=type(input)=="table" and input or {}
    local desired=vec(input.desiredDirection) and input.desiredDirection or ZERO
    local requested=input.requestedSprint==true
    local function decision(direction,sprint,active,blocked,reason,extra)
        local result=extra or {}
        result.direction,result.sprint,result.active,result.blocked,result.reason=direction,sprint,active,blocked,reason
        result.changed=(direction-desired).Magnitude>.000001 or sprint~=requested
        return result
    end
    if not vec(input.desiredDirection) then
        return {},decision(ZERO,false,false,false,"invalid movement")
    end
    local flat=desired*FLAT
    if input.canDetour==false or flat.Magnitude<.001 or not vec(input.position) then
        return {},decision(desired,requested,false,false,
            input.canDetour==false and "movement owns priority" or "no avoidance needed")
    end
    local now=finite(input.now) and input.now or 0
    local dt=clamp(finite(input.dt) and input.dt or .016,.004,.1)
    local state={}
    if type(previous)=="table" and (not finite(previous.now) or now>=previous.now) then
        for k,v in pairs(previous) do state[k]=v end
    end
    state.now=now
    local position=input.position
    local heading=flat.Unit
    -- A new catch/pursuit target can reverse the requested path while the old
    -- passing side is still active. Its clear-frame debounce belongs to the
    -- old path; start the bounded return immediately for a material change.
    -- Keep this exemption through subsequent frames until the return finishes,
    -- rather than reinstating the old hold after one small turn.
    local priorDesired=state.desiredHeading
    if state.active and vec(priorDesired) and priorDesired.Magnitude>.001
        and priorDesired.Unit:Dot(heading)<math.cos(math.rad(45)) then
        state.returningToChangedGoal=true
    end
    state.desiredHeading=heading
    local current=vec(input.currentDirection) and input.currentDirection*FLAT or ZERO
    current=current.Magnitude>.001 and current.Unit or heading
    local strength=math.min(1,flat.Magnitude)
    local speed=clamp(finite(input.walkSpeed) and input.walkSpeed or 20,0,60)
    local run=clamp(finite(input.runSpeed) and input.runSpeed or 20,1,60)
    local walkSpeed=math.min(speed,run)
    -- Only an explicitly opted-in final sprint can retain sprint on a detour.
    -- The caller still owns stamina, role, and committed-action priorities.
    local sprintSpeed=finite(input.sprintSpeed) and clamp(input.sprintSpeed,0,60) or nil
    local sprintEligible=input.allowSprintDetour==true and requested and speed>0
        and sprintSpeed~=nil and sprintSpeed>=run
    local lookupSpeed=sprintEligible and math.max(speed,sprintSpeed) or speed
    local radius=clamp(finite(input.clearance) and input.clearance or 3.75,2,6)
    -- Sprint already stops inside this near-contact band. Forecasting only
    -- the smaller collision capsule can approve a heading that immediately
    -- enters the band and turns sprint off on the following frame. Anticipate
    -- the same boundary, without widening ordinary walking avoidance.
    local sprintClearance=radius+.5
    local threatRadius=sprintEligible and sprintClearance or radius
    local horizon=clamp(finite(input.lookahead) and input.lookahead or .25,.1,.3)
    local height=clamp(finite(input.verticalClearance) and input.verticalClearance or 5,2,8)
    local turnRate=clamp(finite(input.turnRate) and input.turnRate or 8,2,12)
    -- Catch approaches may have only a small travel margin. This optional
    -- deadline never relaxes collision checks; it only avoids spending that
    -- margin on a needlessly wide angle or a clear-path debounce hold.
    local catchPath=vec(input.targetPosition) and finite(input.arriveBy)
    local goalDelta=catchPath and (input.targetPosition-position)*FLAT or ZERO
    local goalHeading=goalDelta.Magnitude>.001 and goalDelta.Unit or heading
    local remaining=catchPath and math.max(0,input.arriveBy-now) or 0
    local travelSlack=catchPath and math.max(0,remaining*speed*strength-goalDelta.Magnitude-.15) or nil
    if not catchPath then state.returningForDeadline=nil end

    -- Position changes are authoritative for progress. Reported velocity can
    -- remain at 20/27 while another character physically stops our movement.
    local samples={}
    for _,sample in ipairs(type(state.samples)=="table" and state.samples or {}) do
        if type(sample)=="table" and finite(sample.time) and vec(sample.position)
            and sample.time<=now and now-sample.time<=.24 then
            samples[#samples+1]={time=sample.time,position=sample.position}
        end
    end
    if #samples==0 or now>samples[#samples].time then samples[#samples+1]={time=now,position=position} end
    while #samples>32 do table.remove(samples,1) end
    state.samples=samples
    local first=samples[1]
    local measured=first and now-first.time>=.15
        and ((position-first.position)*FLAT).Magnitude/(now-first.time) or nil

    local obstacles={}
    local nearest=math.huge
    for _,other in ipairs(type(input.opponents)=="table" and input.opponents or {}) do
        if type(other)=="table" and vec(other.position) and math.abs(other.position.Y-position.Y)<=height then
            local relative=(other.position-position)*FLAT
            local velocity=vec(other.velocity) and other.velocity*FLAT or ZERO
            if velocity.Magnitude>40 then velocity=velocity.Unit*40 end
            if relative.Magnitude<=radius+(lookupSpeed+velocity.Magnitude)*horizon+3 then
                obstacles[#obstacles+1]={relative=relative,velocity=velocity}
                nearest=math.min(nearest,relative.Magnitude)
            end
        end
    end
    local touching=nearest<=sprintClearance
    if not touching then state.contactSince=nil
    elseif not finite(state.contactSince) then state.contactSince=now end
    local blocked=touching and measured~=nil and measured<math.max(1,speed*strength*.2)
        and now-state.contactSince>=.12
    state.blocked=blocked
    state.progressSpeed=measured

    local threat=false
    local closestThreat,closestDistance
    for _,other in ipairs(obstacles) do
        local rv=other.velocity-heading*(speed*strength)
        local gap=clearance(other.relative,rv,horizon)
        local approaching=other.relative:Dot(rv)<-.001
        local approachHeading=heading
        if current:Dot(heading)<.98 then
            local currentVelocity=other.velocity-current*(speed*strength)
            local currentGap=clearance(other.relative,currentVelocity,horizon)
            if currentGap<gap and other.relative:Dot(currentVelocity)<-.001 then
                gap,approaching,approachHeading=currentGap,true,current
            end
        end
        if sprintEligible then
            -- A currently walking character may receive native sprint speed
            -- on the next frame; that prospective path must also be clear.
            for _,direction in ipairs({heading,current}) do
                local futureVelocity=other.velocity-direction*(sprintSpeed*strength)
                local futureGap=clearance(other.relative,futureVelocity,horizon)
                if futureGap<gap and other.relative:Dot(futureVelocity)<-.001 then
                    gap,approaching,approachHeading=futureGap,true,direction
                end
            end
        end
        if gap<threatRadius and approaching and other.relative:Dot(approachHeading)>=-radius*.4 then
            threat=true
            if not closestDistance or gap<closestDistance then closestThreat,closestDistance=other,gap end
        end
    end

    local function evaluate(direction,moveSpeed)
        local endpoint=position+direction*math.max(radius,moveSpeed*horizon)
        if not inside(endpoint,input.bounds) then return false,-math.huge,false end
        local minimum=math.huge
        local escaping=true
        for _,other in ipairs(obstacles) do
            local initial=other.relative.Magnitude
            local gap,ending=clearance(other.relative,other.velocity-direction*moveSpeed,horizon)
            minimum=math.min(minimum,gap)
            if initial<radius then
                if gap<initial-.15 or ending<initial+.25 then escaping=false end
            elseif gap<radius then escaping=false end
        end
        return escaping,minimum,true
    end
    local function keepSprint(direction)
        if not sprintEligible or blocked or touching then return false end
        -- Test the actual bounded heading, not the final candidate heading.
        -- Neither an overlapping escape nor a path safe only at walking
        -- speed can spend sprint while turning around the other player.
        local actualSafe,actualGap=evaluate(direction,speed*strength)
        local futureSafe,futureGap=evaluate(direction,sprintSpeed*strength)
        return actualSafe and actualGap>=sprintClearance
            and futureSafe and futureGap>=sprintClearance
    end

    if not threat and not blocked then
        local old=state.active and state.heading or nil
        if vec(old) and old.Magnitude>.001 and old:Dot(heading)<.9999 then
            state.clearSince=state.clearSince or now
            local amount=speed>0 and strength*walkSpeed/speed or strength
            -- A single clear frame near the capsule boundary is not an exit.
            -- Retain the checked passing heading briefly so alternating clear/
            -- threatened frames cannot reverse the turn on every heartbeat.
            local holdTime=math.max(0,.12-(now-state.clearSince))
            local heldSprint=keepSprint(old.Unit)
            local heldSpeed=heldSprint and speed*strength or speed*amount
            local lostProgress=math.max(0,speed*strength*heading:Dot(goalHeading)
                -heldSpeed*old.Unit:Dot(goalHeading))*holdTime
            if catchPath and lostProgress>travelSlack+.000001 then
                state.returningForDeadline=true
            end
            if not state.returningToChangedGoal and not state.returningForDeadline and now-state.clearSince<.12 then
                local safe=evaluate(old.Unit,speed*amount)
                local sprint=heldSprint
                if safe or sprint then
                    state.heading,state.active=old.Unit,true
                    return state,decision(old.Unit*(sprint and strength or amount),sprint,true,false,"holding passing side",
                        {side=state.side,progressSpeed=measured})
                end
            end
            local returning=turn(old.Unit,heading,turnRate*dt,state.side)
            state.heading,state.active=returning,true
            if keepSprint(returning) then
                return state,decision(returning*strength,true,true,false,"returning to path",
                    {side=state.side,progressSpeed=measured})
            end
            local safeAmount=0
            for _,fraction in ipairs({1,.75,.5,.25,.125}) do
                local safe=evaluate(returning,speed*amount*fraction)
                if safe then safeAmount=amount*fraction;break end
            end
            return state,decision(returning*safeAmount,false,true,false,"returning to path",
                {side=state.side,progressSpeed=measured})
        end
        state.active,state.heading=false,current
        state.returningToChangedGoal=nil
        state.returningForDeadline=nil
        state.clearSince=state.clearSince or now
        if now-state.clearSince>=.35 then state.side=nil end
        return state,decision(desired,requested,false,false,"clear",{progressSpeed=measured})
    end
    state.clearSince=nil

    local preferred=state.side
    if preferred~=1 and preferred~=-1 then
        local lateral=closestThreat and (heading.Z*closestThreat.relative.X-heading.X*closestThreat.relative.Z) or 0
        preferred=lateral>.05 and -1 or 1
    end
    local function candidate(side)
        local best
        local angles=catchPath and {5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90}
            or {35,55,75,90}
        for _,degrees in ipairs(angles) do
            local direction=rotate(heading,side*math.rad(degrees))
            local safe,gap,bounded=evaluate(direction,walkSpeed*strength)
            if safe then
                -- A shallow walking-only bypass can repeatedly release sprint
                -- even when a slightly wider same-side path is safe at both
                -- native speeds and makes more forward progress. Compare that
                -- progress only for the caller's explicit sprint opt-in. The
                -- bounded turn below still has to pass both speed checks.
                local alignment=direction:Dot(heading)
                local score=alignment+(catchPath and 0 or math.min(gap,radius+3)*.015)
                if sprintEligible then
                    local usableSpeed=keepSprint(direction) and sprintSpeed or walkSpeed
                    score=alignment*usableSpeed/math.max(.001,walkSpeed)
                end
                if not best or score>best.score then best={direction=direction,score=score,side=side} end
            elseif bounded and nearest<radius then
                -- Once overlapping, a sideways exit may initially touch the
                -- same capsule. Prefer increasing final separation to pushing.
                local improves=true
                for _,other in ipairs(obstacles) do
                    if other.relative.Magnitude<radius+.5 then
                        local ending=(other.relative+(other.velocity-direction*walkSpeed*strength)*horizon).Magnitude
                        if ending<other.relative.Magnitude+.4 then improves=false end
                    end
                end
                if improves then
                    local score=-10+gap*.1+direction:Dot(heading)*.05
                    if not best or score>best.score then best={direction=direction,score=score,side=side} end
                end
            end
        end
        return best
    end
    local chosen=candidate(preferred)
    -- Retain the selected passing side while it remains usable; small opponent
    -- movements or roster order changes must not flip the character repeatedly.
    if not chosen then chosen=candidate(-preferred) end
    if not chosen then
        state.active=true
        state.heading=vec(state.heading) and state.heading or heading
        return state,decision(ZERO,false,true,blocked,"no room to pass",
            {side=state.side,progressSpeed=measured})
    end
    state.side=chosen.side
    local from=state.active and vec(state.heading) and state.heading.Magnitude>.001 and state.heading.Unit or current
    local steered=turn(from,chosen.direction,turnRate*dt,state.side)
    if keepSprint(steered) then
        state.heading,state.active=steered,true
        return state,decision(steered*strength,true,true,false,"passing player",
            {side=state.side,progressSpeed=measured})
    end
    local amount=speed>0 and strength*walkSpeed/speed or strength
    local safeAmount
    for _,fraction in ipairs({1,.75,.5,.25,.125}) do
        local safe=evaluate(steered,speed*amount*fraction)
        if safe then safeAmount=amount*fraction;break end
    end
    if not safeAmount then
        -- An overlap does not make a rejected forward step safe. Keep the
        -- bounded heading turning below, but wait to translate until one of
        -- its checked speeds can escape without deepening the overlap.
        safeAmount=0
    end
    if not inside(position+steered*math.max(radius,speed*safeAmount*horizon),input.bounds) then safeAmount=0 end
    state.heading,state.active=steered,true
    return state,decision(steered*safeAmount,false,true,blocked,
        blocked and "walking out of contact" or "passing player",
        {side=state.side,progressSpeed=measured})
end

return Avoidance

end)()
local createCarrierMoves = (function()
-- Native WR juke requests after confirmed possession. Geometry is an estimate;
-- only the game decides whether a move is accepted and avoids a tackle.
return function(runtime)
    local Config,Field,Moves=runtime.Config,runtime.Field,runtime.Moves
    local player=runtime.player
    local FLAT=Vector3.new(1,0,1)
    local alive,active,nextAttempt=true,nil,0
    local attempts,observedBursts,lastOutcome,lastError=0,0,nil,nil
    local pendingJump,observedJumps=nil,0
    local observedFinishDives=0
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
    local function vector(v)
        return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
    end
    local function flat(v) return v*FLAT end
    local function xyz(v) return {x=v.X,y=v.Y,z=v.Z} end
    local function log(kind,data)
        if type(runtime.log)=="function" then pcall(runtime.log,kind,data) end
    end
    local function namedUpvalue(fn,name)
        local getUps=(debug and debug.getupvalues) or getupvalues
        if type(fn)~="function" or type(getUps)~="function" then return nil end
        local ok,values=pcall(getUps,fn)
        if not ok or type(values)~="table" then return nil end
        for _,value in pairs(values) do
            if type(value)=="function" and debug and type(debug.info)=="function" then
                local good,actual=pcall(debug.info,value,"n")
                if good and actual==name then return value end
            end
        end
    end
    local nativeJuke=runtime.nativeJuke or namedUpvalue(Moves and Moves.SetPhase,"juke")
    local nativeSpin=runtime.nativeSpin or namedUpvalue(Moves and Moves.SetPhase,"spin")
    local nativeTruck=runtime.nativeTruck or namedUpvalue(Moves and Moves.SetPhase,"truck")
    local function bounds(input)
        local g=input.geo
        local offset=vector(input.offset) and input.offset or Vector3.zero
        local b={minX=g and g.MinX or Field.MinX+offset.X,
            maxX=g and g.MaxX or Field.MaxX+offset.X,
            minZ=g and g.BackZ or Field.BackZ+offset.Z,
            maxZ=g and g.EndZ or Field.EndZ+offset.Z}
        if not finite(b.minX) or not finite(b.maxX) or not finite(b.minZ) or not finite(b.maxZ)
            or b.minX>=b.maxX or b.minZ>=b.maxZ then return nil end
        return b
    end
    local function room(p,b)
        return math.min(p.X-b.minX,b.maxX-p.X,p.Z-b.minZ,b.maxZ-p.Z)
    end
    -- Carrier dives across the goal line used to start outside the end zone.
    -- WR dives now require an already in-zone start; carrying has no reason to
    -- spend control on a scoring dive after crossing. Retain the query for API
    -- compatibility, but never dispatch this former finish move.
    local function finishDive(input) return nil end
    local function decide(input,extended)
        if type(input)~="table" or input.role~="WR" or input.phase~="RAC"
            or input.mode~=nil and input.mode~="1v1" or input.carrierIsMe~=true or input.upright~=true
            or input.grounded~=true or input.healthy~=true or input.enemyCarrier==true
            or input.ballActive or input.testing or input.enabled==false
            or not finite(input.now) or input.now<(input.nextAttempt or 0)
            or not vector(input.position) or not vector(input.velocity)
            or not vector(input.rightDirection) or not vector(input.opponentPosition)
            or not vector(input.opponentVelocity) then return nil end
        local juke=Config.Moves and Config.Moves.Juke
        if type(juke)~="table" or not finite(juke.Cost) or not finite(juke.Speed)
            or not finite(juke.Time) or not finite(juke.Cooldown)
            or juke.Speed<=0 or juke.Time<=0 or juke.Cooldown<=0 then return nil end
        -- Retain a small sprint reserve instead of spending the final stamina.
        if not finite(input.stamina) or input.stamina<10 then return nil end
        local ownVelocity,enemyVelocity=flat(input.velocity),flat(input.opponentVelocity)
        if ownVelocity.Magnitude>Config.SprintSpeed*1.5 then return nil end
        if enemyVelocity.Magnitude>80 then enemyVelocity=enemyVelocity.Unit*80 end
        local right=flat(input.rightDirection)
        if right.Magnitude<.9 or right.Magnitude>1.01 then return nil end
        local delta=flat(input.opponentPosition-input.position)
        local distance=delta.Magnitude
        if distance<2 or distance>18 or math.abs(input.opponentPosition.Y-input.position.Y)>4 then return nil end
        local relative=enemyVelocity-ownVelocity
        local closing=-relative:Dot(delta.Unit)
        if closing<6 then return nil end
        local tackle=Config.Tackle or {}
        local contactRange=(tackle.GrabRange or 3.5)+math.min(tackle.GrabSlack or 2,2)
        local contactIn=math.max(0,distance-contactRange)/closing
        if contactIn>.45 then return nil end
        local closestTime=math.max(0,math.min(.5,-delta:Dot(relative)/math.max(.001,relative:Dot(relative))))
        if (delta+relative*closestTime).Magnitude>contactRange+1 then return nil end
        local b=bounds(input)
        if not b then return nil end
        local pad=math.max(1.5,(Field.YD or 3)*.4)
        if room(input.position,b)<pad then return nil end
        local best,bestScore
        local candidates={}
        for _,sign in ipairs({-1,1}) do
            -- This is the native Juke expression, used only to reject unsafe
            -- paths. The native function alone applies the actual movement.
            local burstVelocity=right*(sign*juke.Speed)+ownVelocity*.6000000238418579
            local displacement=burstVelocity*juke.Time
            local endpoint=input.position+displacement
            local paddedEnd=input.position+burstVelocity*(juke.Time+.04)
            local clear=room(paddedEnd,b)>=pad and endpoint.Z>=input.position.Z-2
            if clear and type(input.clipDistance)=="function" and displacement.Magnitude>.001 then
                local ok,available=pcall(input.clipDistance,input.position,displacement.Unit,
                    burstVelocity.Magnitude*(juke.Time+.04))
                clear=ok and finite(available) and available>=burstVelocity.Magnitude*(juke.Time+.04)-.01
            end
            if clear and input.stamina>=juke.Cost+10 then
                local minimum=math.huge
                for step=1,6 do
                    local t=juke.Time*step/6
                    minimum=math.min(minimum,(delta+(enemyVelocity-burstVelocity)*t).Magnitude)
                end
                local endSeparation=flat(input.opponentPosition+enemyVelocity*juke.Time-endpoint).Magnitude
                local normalSeparation=(delta+relative*juke.Time).Magnitude
                if minimum>contactRange+.25 and endSeparation>normalSeparation+1 then
                    local score=minimum*2+endSeparation*.4+(endpoint.Z-input.position.Z)*.15+room(paddedEnd,b)*.03
                    local candidate={action="juke",sign=sign,duration=juke.Time,cooldown=juke.Cooldown,
                        endpoint=endpoint,direction=displacement.Unit,distance=distance,closing=closing,
                        contactIn=contactIn,minClearance=minimum,estimatedSeparation=endSeparation}
                    candidates[#candidates+1]=candidate
                    if not best or score>bestScore then
                        bestScore=score
                        best=candidate
                    end
                end
            end
        end
        if extended and vector(input.lookDirection) then
            local forward=flat(input.lookDirection)
            if forward.Magnitude>=.9 and forward.Magnitude<=1.01 then
                forward=forward.Unit
                local function safePath(velocity,duration)
                    local displacement=velocity*(duration+.04)
                    if room(input.position+displacement,b)<pad or displacement.Z< -2 then return false end
                    if displacement.Magnitude>.001 and type(input.clipDistance)=="function" then
                        local ok,available=pcall(input.clipDistance,input.position,displacement.Unit,displacement.Magnitude)
                        if not ok or not finite(available) or available<displacement.Magnitude-.01 then return false end
                    end
                    return true
                end
                local spin=Config.Moves.Spin
                if type(spin)=="table" and finite(spin.Cost) and finite(spin.Forward) and finite(spin.Side)
                    and finite(spin.Time) and spin.Time>0 and finite(spin.Cooldown) and spin.Cooldown>0
                    and input.stamina>=spin.Cost+10 then
                    local safe,minimum,separation=true,math.huge,math.huge
                    for _,sign in ipairs({-1,1}) do
                        -- Native Spin chooses its own random side. Both paths
                        -- must pass; this controller does not choose that random sign.
                        local burst=forward*spin.Forward+right*(sign*spin.Side)
                        safe=safe and safePath(burst,spin.Time)
                        for i=1,8 do
                            minimum=math.min(minimum,(delta+(enemyVelocity-burst)*(spin.Time*i/8)).Magnitude)
                        end
                        separation=math.min(separation,(delta+(enemyVelocity-burst)*spin.Time).Magnitude)
                    end
                    if safe and minimum>contactRange+.25
                        and separation>(delta+relative*spin.Time).Magnitude+1 then
                        candidates[#candidates+1]={action="spin",duration=spin.Time,cooldown=spin.Cooldown,
                            direction=forward,endpoint=input.position+forward*spin.Forward*spin.Time,
                            distance=distance,closing=closing,contactIn=contactIn,minClearance=minimum,
                            estimatedSeparation=separation,randomSide=true}
                    end
                end
                local truck=Config.Moves.Truck
                if type(truck)=="table" and finite(truck.Cost) and finite(truck.Lunge) and truck.Lunge>0
                    and finite(truck.LungeTime) and truck.LungeTime>0 and finite(truck.Cooldown)
                    and truck.Cooldown>0 and finite(truck.LiveRange) and input.stamina>=truck.Cost+10
                    and distance<=truck.LiveRange and delta.Unit:Dot(forward)>.8
                    and contactIn<=truck.LungeTime and safePath(forward*truck.Lunge,truck.LungeTime) then
                    candidates[#candidates+1]={action="truck",duration=truck.LungeTime,cooldown=truck.Cooldown,
                        direction=forward,endpoint=input.position+forward*truck.Lunge*truck.LungeTime,
                        distance=distance,closing=closing,contactIn=contactIn,minClearance=0,
                        estimatedSeparation=(delta+(enemyVelocity-forward*truck.Lunge)*truck.LungeTime).Magnitude,
                        contactAttempt=true}
                end
                if input.canJump==true and finite(input.jumpSpeed) and input.jumpSpeed>0
                    and finite(input.gravity) and input.gravity>0 and contactIn>=.12 and contactIn<=.40 then
                    local airtime=2*input.jumpSpeed/input.gravity
                    local clear=safePath(ownVelocity,math.min(airtime,.6))
                    local minimum=math.huge
                    for _,dt in ipairs({-.03,0,.03}) do
                        local t=contactIn+dt
                        local ownY=input.position.Y+input.jumpSpeed*t-.5*input.gravity*t*t
                        local otherY=input.opponentPosition.Y
                        if input.opponentGrounded==false then
                            otherY=math.max(input.opponentPosition.Y,otherY+input.opponentVelocity.Y*t
                                -.5*input.gravity*t*t)
                        end
                        minimum=math.min(minimum,ownY-otherY)
                    end
                    if clear and minimum>4.5 then
                        candidates[#candidates+1]={action="jump",duration=airtime,cooldown=.65,
                            direction=ownVelocity.Magnitude>.01 and ownVelocity.Unit or forward,
                            endpoint=input.position+ownVelocity*airtime,distance=distance,closing=closing,
                            contactIn=contactIn,minClearance=minimum,estimatedSeparation=distance,
                            jumpSpeed=input.jumpSpeed}
                    end
                end
            end
        end
        return best,candidates
    end
    local function burstOf(root)
        if not root or type(root.FindFirstChild)~="function" then return nil end
        local ok,burst=pcall(root.FindFirstChild,root,"Burst")
        return ok and burst or nil
    end
    local function cancel()
        active=nil
        if pendingJump and pendingJump.h then pendingJump.h.Jump=false end
        pendingJump=nil
    end
    local function eligible(s,root,h)
        return alive and type(s)=="table" and s.enabled~=false and not s.testing and not s.arc
            and (s.mode==nil or s.mode=="1v1") and s.role=="WR" and s.phase=="RAC"
            and player and player.Character and s.carrier==player.Character
            and s.enemyCarrier~=true and root and h and h.Health>0 and not h.PlatformStand
    end
    local api={decide=decide,finishDive=finishDive,cancel=cancel,candidates=function(input)
        local _,candidates=decide(input,true);return candidates or {}
    end}
    local function update(s,root,h,now)
        if not finite(now) or not eligible(s,root,h) then cancel();return false end
        if pendingJump then
            local pending=pendingJump
            local rise=root.Position.Y-pending.y
            local tookOff=pending.root==root and rise>.12
                and (root.AssemblyLinearVelocity.Y>5 or h.FloorMaterial==Enum.Material.Air)
            if tookOff or now-pending.started>.18 or pending.root~=root then
                h.Jump=false;pendingJump=nil
                if tookOff then
                    observedJumps=observedJumps+1;lastOutcome="jumpObserved"
                    log("carrierMove",{action="jump",outcome="takeoffObserved",position=xyz(root.Position),
                        delay=now-pending.started,estimateOnly=true})
                else lastOutcome="jumpUnconfirmed" end
            else return false end
        end
        if active then
            if active.root==root and now<active.expires and burstOf(root)==active.marker then
                return true,active.message
            end
            log("carrierMoveEnd",{action=active.action,age=now-active.started,
                staminaBefore=active.staminaBefore,staminaAfter=tonumber(player:GetAttribute("Stamina")),
                reason=now>=active.expires and "duration" or "burstEnded"})
            active=nil
        end
        if now<nextAttempt or burstOf(root)
            or h.FloorMaterial==Enum.Material.Air or h.WalkSpeed<=0 then return false end
        if not Moves or type(Moves.Upright)~="function" or Moves.Upright()~=true then return false end
        local opponent=s.opponent
        if not opponent or opponent==player.Character then return false end
        local otherRoot=opponent:FindFirstChild("HumanoidRootPart")
        local otherHum=opponent:FindFirstChildOfClass("Humanoid")
        if not otherRoot or not otherHum or otherHum.Health<=0 then return false end
        -- Native DivePath sets PlatformStand while DB/RAC dive tackles remain
        -- active. A moving diver is a threat; only ignore a downed defender
        -- who is effectively stationary. Closing/path checks still apply.
        local opponentDown=otherHum.PlatformStand and flat(otherRoot.AssemblyLinearVelocity).Magnitude<6
        local staminaBefore=tonumber(player:GetAttribute("Stamina"))
        local gravity=workspace.Gravity
        local jumpSpeed=h.UseJumpPower and h.JumpPower
            or math.sqrt(2*gravity*math.max(0,h.JumpHeight or 0))
        local canJump=type(h.GetStateEnabled)=="function" and type(h.ChangeState)=="function"
            and h:GetStateEnabled(Enum.HumanoidStateType.Jumping) and jumpSpeed>0
        local observation={role=s.role,phase=s.phase,mode=s.mode or "1v1",carrierIsMe=true,upright=true,
            grounded=true,healthy=true,now=now,nextAttempt=nextAttempt,position=root.Position,
            velocity=root.AssemblyLinearVelocity,rightDirection=root.CFrame.RightVector,
            lookDirection=root.CFrame.LookVector,
            opponentPosition=otherRoot.Position,opponentVelocity=otherRoot.AssemblyLinearVelocity,
            opponentGrounded=otherHum.FloorMaterial~=Enum.Material.Air,
            gravity=gravity,jumpSpeed=jumpSpeed,canJump=canJump,
            stamina=staminaBefore,geo=s.geo,offset=s.offset,
            clipDistance=runtime.clippedDistance}
        if opponentDown then return false end
        local choice,candidates=decide(observation,true)
        local native={juke=nativeJuke,spin=nativeSpin,truck=nativeTruck}
        if choice and type(native[choice.action])~="function" then choice=nil end
        -- The established geometric juke score remains first choice. Other
        -- already validated native moves are deterministic fallbacks, in a
        -- fixed order; no stored weights or random selector influence them.
        if not choice then
            for _,action in ipairs({"jump","spin","truck"}) do
                if action=="jump" and canJump or type(native[action])=="function" then
                    for _,candidate in ipairs(candidates or {}) do
                        if candidate.action==action then choice=candidate;break end
                    end
                end
                if choice then break end
            end
        end
        if not choice then return false end
        attempts=attempts+1
        -- Even a rejected native request is rate limited. Never call can() as
        -- a probe: it consumes the game's own cooldown before the real action.
        nextAttempt=now+choice.cooldown+.1
        if choice.action=="jump" then
            local ok=pcall(function() h.Jump=true;h:ChangeState(Enum.HumanoidStateType.Jumping) end)
            lastOutcome=ok and "jumpRequested" or "error"
            if ok then pendingJump={root=root,h=h,y=root.Position.Y,started=now}
            else h.Jump=false end
            -- Ordinary route motion continues during the normal jump; no
            -- fabricated Burst, velocity write or immediate execution credit.
            return false
        end
        local ok,err=pcall(native[choice.action],choice.sign)
        local marker=ok and burstOf(root) or nil
        lastOutcome=not ok and "error" or marker and "burstObserved" or "unconfirmed"
        lastError=not ok and tostring(err) or nil
        log("carrierMove",{action=choice.action,sign=choice.sign,outcome=lastOutcome,error=lastError,
            position=xyz(root.Position),opponentPosition=xyz(otherRoot.Position),
            velocity=xyz(root.AssemblyLinearVelocity),opponentVelocity=xyz(otherRoot.AssemblyLinearVelocity),
            opponentPlatformStand=otherHum.PlatformStand==true,
            distance=choice.distance,closing=choice.closing,contactIn=choice.contactIn,
            minClearance=choice.minClearance,estimatedSeparation=choice.estimatedSeparation,
            stamina=staminaBefore,staminaBefore=staminaBefore,
            staminaAfter=tonumber(player:GetAttribute("Stamina")),staminaAfterImmediate=true,estimateOnly=true})
        if not marker then return false end
        observedBursts=observedBursts+1
        active={root=root,marker=marker,action=choice.action,started=now,staminaBefore=staminaBefore,expires=now+choice.duration+.04,
            message="Full auto · "..choice.action..(choice.sign and (choice.sign<0 and " left" or " right") or "")}
        return true,active.message
    end
    function api.update(s,root,h,now)
        local ok,taken,message=pcall(update,s,root,h,now)
        if not ok then
            active=nil;lastError=tostring(taken);lastOutcome="error"
            if finite(now) then nextAttempt=math.max(nextAttempt,now+1) end
            log("carrierMoveError",{error=lastError})
            return false
        end
        return taken,message
    end
    function api.status()
        return {available=type(nativeJuke)=="function" or type(nativeSpin)=="function" or type(nativeTruck)=="function"
               ,
            availableMoves={juke=type(nativeJuke)=="function",spin=type(nativeSpin)=="function",truck=type(nativeTruck)=="function",
                finishDive=false},
            active=active~=nil,attempts=attempts,
            observedBursts=observedBursts,observedJumps=observedJumps,observedFinishDives=observedFinishDives,jumpPending=pendingJump~=nil,
            lastOutcome=lastOutcome,error=lastError,nextAttempt=nextAttempt}
    end
    function api.unload() alive=false;cancel() end
    return api
end

end)()
local createAssist = (function()
-- Factory bundled into chalk-it-up-1v1.lua. Uses normal character controls.
return function(ctx, Planner, createTackle, WRApproach, Motion, createCarrierMoves, PlayerAvoidance)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local GuiService = game:GetService("GuiService")
    local CAS = game:GetService("ContextActionService")
    local Http = game:GetService("HttpService")
    local RS = game:GetService("ReplicatedStorage")
    local me = Players.LocalPlayer
    local Config = require(RS.Shared.Config)
    local Field = require(RS.Shared.Field)
    local Moves = require(me.PlayerScripts.Game.Moves)
    local controller = {}
    local auto, alive = false, true
    local plan, throwKey, throwRole, claimedKey, lastSnapshot, controlledHumanoid
    local claimObservedAt,claimTraceCount,claimTraceNext=nil,0,0
    local steering, atTarget, parkedPosition = nil, false, nil
    local nextSolve, nextCheck, nextReplan, lastDive, lastJump = 0, 0, 0, -math.huge, -math.huge
    local ownsSprint = false
    local jumped, dived = false, false
    local jumpRequest
    local confirmedCatchJump,groundedReachSince,reachAirborne
    local wrFake,wrReturn,wrFakeUsed,nextWRFakeCheck,nextWRFakeSample=nil,nil,false,0,0
    local lastWRSkipReason
    local lastPauseReason
    local wrDefenderDeadline
    local stemFinished,stemForecast,nextStemCheck,stemLastSpeed,stemLastSprint=false,nil,0,nil,nil
    local stemLastRun,stemLastStage
    local stemWasActive=false
    local trackedMotionRoot,trackedAirborne=nil,false
    local trackedSprintRoot,sprintTracking
    local message, lastError = "Auto OFF", nil
    local counters = {throws=0, jumps=0, dives=0, intercepted=0, incomplete=0,
        catches=0,opponentCatches=0,lostToInterception=0,breakups=0}
    local history, lastLogTime, lastResult = {}, 0, nil
    local nativeTackle,nativeDive,nativeGrabTarget,controls,inputOwned
    local tackleAssist,catching,navigation=false,false,false
    local carrierAssist
    local avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason
    local navigationIdleSince,navigationIdleRoot
    local avoidanceStatus={active=false,blocked=false}
    local lastAvoidanceLog=0
    pcall(function()
        local module=me.PlayerScripts:FindFirstChild("PlayerModule")
        if module then controls=require(module):GetControls() end
    end)
    local ups = (debug and debug.getupvalues) or getupvalues
    local function namedUpvalue(f, name)
        if type(ups) ~= "function" then return nil end
        local ok, values = pcall(ups, f)
        if not ok or type(values) ~= "table" then return nil end
        for _, value in pairs(values) do
            if type(value) == "function" then
                local good, actual = pcall(debug.info, value, "n")
                if good and actual == name then return value end
            end
        end
    end
    local candidate = namedUpvalue(Moves.SetPhase, "tackle")
    if candidate and namedUpvalue(candidate, "dive") then
        nativeTackle,nativeDive=candidate,namedUpvalue(candidate,"dive")
        nativeGrabTarget=namedUpvalue(candidate,"grabTarget")
    end
    local function divePermitted()
        if not nativeDive then return false end
        local good,values=pcall(ups,nativeTackle)
        if not good then return false end
        for _,v in pairs(values) do
            if type(v)=="boolean" and v then return false end -- native NoDive
        end
        return true
    end
    local function ownInput()
        if inputOwned then return end
        inputOwned=true
        if controls then controls:Disable() end
        CAS:BindActionAtPriority("ChalkAssistMovement",function() return Enum.ContextActionResult.Sink end,
            false,10000,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,
            Enum.KeyCode.Up,Enum.KeyCode.Down,Enum.KeyCode.Left,Enum.KeyCode.Right,
            Enum.KeyCode.Space,Enum.KeyCode.LeftShift,Enum.KeyCode.RightShift,
            Enum.KeyCode.E,Enum.KeyCode.Q,Enum.KeyCode.X,Enum.KeyCode.Z,Enum.KeyCode.C,
            Enum.KeyCode.R,Enum.KeyCode.F,Enum.KeyCode.Thumbstick1,Enum.KeyCode.ButtonA,
            Enum.KeyCode.ButtonB,Enum.KeyCode.ButtonX,Enum.KeyCode.ButtonY)
    end
    local function releaseInput()
        if not inputOwned then return end
        inputOwned=false
        CAS:UnbindAction("ChalkAssistMovement")
        if controls then controls:Enable() end
    end

    local function xyz(v)
        return v and {x=v.X,y=v.Y,z=v.Z} or nil
    end
    local function humanoidState(h)
        if not h then return nil end
        local ok,state=pcall(function() return h:GetState().Name end)
        return ok and state or nil
    end
    local function networkPing()
        local ok,value=pcall(function() return me:GetNetworkPing() end)
        if ok and type(value)=="number" and value==value and value>=0 and value<math.huge then
            return value
        end
    end
    local function traceOpponent(o)
        if not o then return nil end
        return {position=xyz(o.position),velocity=xyz(o.velocity),lookDirection=xyz(o.lookDirection),
            grounded=o.grounded,jumpSpeed=o.jumpSpeed,gravity=o.gravity,
            walkSpeed=o.walkSpeed,runSpeed=o.runSpeed,sprintSeconds=o.sprintSeconds,
            groundRootY=o.groundRootY,diveDistance=o.diveDistance,canJump=o.canJump,canDive=o.canDive}
    end
    local function traceOpponents(opponents)
        if type(opponents)~="table" then return nil end
        local items={}
        for _,o in ipairs(opponents) do items[#items+1]=traceOpponent(o) end
        return items
    end
    local function log(kind, fields)
        fields = fields or {}
        if fields.defenderAt==math.huge or fields.defenderAt==-math.huge then fields.defenderAt=nil end
        fields.kind, fields.time = kind, workspace:GetServerTimeNow()
        fields.version=type(ctx.version)=="string" and ctx.version or "unversioned"
        fields.buildId=ctx.buildId
        fields.launchAt=fields.launchAt or throwKey
        table.insert(history, fields)
        if #history > 80 then table.remove(history, 1) end
        if type(appendfile) == "function" then
            pcall(function()
                appendfile("ciu_auto_events.jsonl", Http:JSONEncode(fields)..string.char(10))
            end)
        end
    end
    local function saveFailure(reason,result,catcher)
        if type(appendfile)~="function" then return end
        pcall(function()
            local s=ctx.snapshot()
            appendfile("ciu_failures.jsonl",Http:JSONEncode({time=workspace:GetServerTimeNow(),
                reason=reason,result=result,catcher=catcher,role=throwRole or s.role,
                mode=s.mode or "1v1",phase=s.phase,history=table.clone(history)})..string.char(10))
        end)
    end
    local function releaseSprint()
        if ownsSprint then
            if not UIS:IsKeyDown(Enum.KeyCode.LeftShift) and not UIS:IsKeyDown(Enum.KeyCode.RightShift) then
                Moves.HoldSprint(false)
            end
            ownsSprint=false
        end
        trackedSprintRoot,sprintTracking=nil,nil
    end
    local function release()
        navigation=false
        navigationIdleSince,navigationIdleRoot=nil,nil
        avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason=nil,nil,nil,nil
        avoidanceStatus={active=false,blocked=false}
        if carrierAssist then carrierAssist.cancel() end
        if controlledHumanoid and controlledHumanoid.Parent then
            controlledHumanoid:Move(Vector3.zero, false)
        end
        controlledHumanoid = nil
        steering,atTarget,parkedPosition=nil,false,nil
        releaseSprint()
        releaseInput()
    end
    local function cancel(preserveMovement)
        navigationIdleSince,navigationIdleRoot=nil,nil
        if preserveMovement then
            -- A running Full Auto route hands its existing native sprint to
            -- ball pursuit. Do not send a false/true sprint pair at the throw.
            navigation=false
            if carrierAssist then carrierAssist.cancel() end
            atTarget,parkedPosition=false,nil
        else release() end
        plan, lastSnapshot = nil, nil
        jumped, dived = false, false
        jumpRequest=nil
        confirmedCatchJump,groundedReachSince,reachAirborne=nil,nil,nil
        wrFake,wrReturn=nil,nil
    end
    -- A synchronous solve or native-state check can outlast the input window.
    -- Recheck the live clock before dispatch, not only the frame's old timestamp.
    local function cancelStaleAction(at)
        if not plan then return false end
        local pendingJump=plan.jumpAt and (not jumped or jumpRequest~=nil)
        local pendingDive=plan.diveAt and not dived
        if not pendingJump and not pendingDive then return false end
        local reason=plan.contactAt and at>=plan.contactAt and "Contact window elapsed after planning"
            or pendingJump and at-plan.jumpAt>0.075 and "Jump deadline elapsed after planning"
            or pendingDive and at-plan.diveAt>0.075 and "Dive deadline elapsed after planning"
        if not reason then return false end
        log("replan",{reason=reason,action=plan.kind,scheduledJump=plan.jumpAt,
            scheduledDive=plan.diveAt,contactAt=plan.contactAt,checkedAt=at})
        cancel()
        nextSolve=at+0.045
        message="Action window elapsed · recalculating"
        return true
    end
    local walls = {}
    local fields = workspace:FindFirstChild("Fields")
    if fields then
        for _, f in ipairs(fields:GetChildren()) do
            local wall = f:FindFirstChild("Walls")
            if wall then table.insert(walls, wall) end
        end
    end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Include
    rayParams.FilterDescendantsInstances = walls
    local function clippedDistance(origin, direction, distance)
        if #walls == 0 or distance <= 0 then return distance end
        local hit = workspace:Raycast(origin, direction*distance, rayParams)
        return hit and math.max(0,(hit.Position-origin).Magnitude-2) or distance
    end
    local function healthyCharacter()
        local ch = me.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local h = ch and ch:FindFirstChildOfClass("Humanoid")
        if root and h and h.Health > 0 and not root.Anchored and not h.Sit then
            return root, h
        end
    end
    local function observePendingClaim(s,now)
        -- BallTouched is a local request, not server confirmation. Record a
        -- few actual poses while awaiting that result without changing inputs.
        if not claimObservedAt or claimTraceCount>=4 or now<claimTraceNext
            or now-claimObservedAt>.3 then return end
        claimTraceCount=claimTraceCount+1;claimTraceNext=now+.05
        local root,h=healthyCharacter()
        if not root then return end
        local waist,hands,radius=Planner.capsule({config=Config},root.CFrame,
            h.FloorMaterial==Enum.Material.Air)
        log("pendingCatchPose",{role=s.role,claimOnly=true,authoritative=false,
            sinceClaim=now-claimObservedAt,position=xyz(root.Position),
            velocity=xyz(root.AssemblyLinearVelocity),up=xyz(root.CFrame.UpVector),
            waist=xyz(waist),hands=xyz(hands),radius=radius,
            airborne=h.FloorMaterial==Enum.Material.Air,diving=h.PlatformStand,
            ball=xyz(Planner.ballAt(s.arc,now-s.launchAt))})
    end
    local function locomotionState(root,h,now,sprintSeconds)
        if trackedSprintRoot~=root then trackedSprintRoot,sprintTracking=root,nil end
        local sprinting=me:GetAttribute("SprintOn")==true
        sprintTracking=Motion.sprintState(sprintTracking,now,h.WalkSpeed,sprinting,
            Config.RunSpeed,Config.SprintSpeed)
        if sprintSeconds==nil then
            local stamina=math.max(0,tonumber(me:GetAttribute("Stamina")) or 0)
            sprintSeconds=math.max(0,(stamina-2)/math.max(1,Config.SprintDrain))
        end
        return Motion.locomotion(h.WalkSpeed,sprinting,Config.RunSpeed,Config.SprintSpeed,
            sprintSeconds,sprintTracking)
    end
    local function motionState(s,root,h)
        if trackedMotionRoot~=root then trackedMotionRoot,trackedAirborne=root,false end
        local motion=Motion.classify({floorAirborne=h.FloorMaterial==Enum.Material.Air,
            rootY=root.Position.Y,verticalSpeed=root.AssemblyLinearVelocity.Y,
            turfY=s.geo and s.geo.TurfY or Field.TurfY,knownAirborne=trackedAirborne})
        if motion.nativeAirborne or motion.ascendingDespiteGround or motion.fallingDespiteGround then
            trackedAirborne=true
        elseif motion.grounded then trackedAirborne=false end
        return motion
    end
    local function sprintBudget(s)
        return Motion.sprintBudget(s.role,tonumber(me:GetAttribute("Stamina")),Config.SprintDrain,s.playBudget)
    end
    local function enforceSprintReserve(s)
        local budget=sprintBudget(s)
        if budget.enforced and not budget.canSprint and me:GetAttribute("SprintOn")==true then
            Moves.HoldSprint(false)
            ownsSprint=false
            trackedSprintRoot,sprintTracking=nil,nil
        end
        return budget
    end
    local function snapshot(s, root, h, now)
        local g = workspace.Gravity
        local turf=s.geo and s.geo.TurfY or Field.TurfY
        local bounds=s.geo and {minX=s.geo.MinX+0.5,maxX=s.geo.MaxX-0.5,
            minZ=s.geo.BackZ+0.5,maxZ=s.geo.EndZ-0.5}
            or {minX=Field.MinX+s.offset.X+0.5,maxX=Field.MaxX+s.offset.X-0.5,
                minZ=Field.BackZ+s.offset.Z+0.5,maxZ=Field.EndZ+s.offset.Z-0.5}
        local jumpSpeed = h.UseJumpPower and h.JumpPower or math.sqrt(2*g*h.JumpHeight)
        local motion=motionState(s,root,h)
        local grounded = motion.grounded and reachAirborne~=false
        local reachOverride=reachAirborne
        if motion.physicalAirborne and not motion.nativeAirborne then reachOverride=false end
        local budget=sprintBudget(s)
        local sprintSeconds=budget.seconds
        local locomotion=locomotionState(root,h,now,sprintSeconds)
        local function inspectOpponent(opponent)
        local otherRoot=opponent and opponent:FindFirstChild("HumanoidRootPart")
        local otherHumanoid=opponent and opponent:FindFirstChildOfClass("Humanoid")
        if otherRoot and otherHumanoid and otherHumanoid.Health>0 then
            return {position=otherRoot.Position,
                velocity=otherRoot.AssemblyLinearVelocity,
                grounded=otherHumanoid.FloorMaterial~=Enum.Material.Air,
                lookDirection=otherRoot.CFrame.LookVector,
                jumpSpeed=otherHumanoid.UseJumpPower and otherHumanoid.JumpPower
                    or math.sqrt(2*g*otherHumanoid.JumpHeight),
                gravity=g,walkSpeed=math.max(Config.SprintSpeed,otherHumanoid.WalkSpeed),runSpeed=Config.RunSpeed,
                sprintSeconds=4,groundRootY=turf+3,
                diveDistance=Config.Moves.Dive.Yards*Field.YD,
                canJump=otherHumanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),canDive=true}
        end
        end
        local opponentSnapshot=inspectOpponent(s.opponent)
        local opponentSnapshots
        if s.mode=="Team" then
            opponentSnapshots={}
            for _,ch in ipairs(s.opponents or {}) do
                local item=inspectOpponent(ch)
                if item then table.insert(opponentSnapshots,item) end
            end
        end
        local finishGoal
        if s.role=="WR" and s.catchIntent and s.catchIntent.deepFinish==true then
            local goal=s.catchIntent.goalZ
            if type(goal)=="number" and goal==goal and math.abs(goal)<math.huge then
                finishGoal=goal+(s.offset and s.offset.Z or 0)
            end
        end
        local directCut=s.catchIntent and (s.catchIntent.routeStrategy=="deep_middle_floater"
            or s.catchIntent.routeStrategy=="deep_middle_bullet")
        return {now=now, arc=s.arc, launchAt=s.launchAt,role=s.role,
            continuousApproach=not directCut and s.role=="WR" and s.catchIntent and s.catchIntent.deepFinish==true
                and s.catchIntent.continuousSprint~=true,
            continuousSprint=s.role=="WR" and (directCut or s.catchIntent and s.catchIntent.continuousSprint==true),
            preferAirborne=s.role=="WR",
            requireAirborne=s.role=="WR",
            requireEndzoneCatch=s.role=="WR" and (s.passType or s.catchIntent and s.catchIntent.pass)=="Floater",
            continuousBulletCatch=s.role=="WR" and s.catchIntent and s.catchIntent.continuousBulletCatch==true,
            -- Keep an upright aerial catch when the pass still needs a run
            -- after possession. Floater selection still races for its earliest
            -- robust airborne contact; a meaningful contested advantage may
            -- still justify diving on a Bullet.
            preferJumpDive=s.role=="WR" and finishGoal~=nil
                and s.arc.P1.Z>=finishGoal,
            passType=s.passType or (s.catchIntent and s.catchIntent.pass),
            requireDive=s.role=="WR" and s.catchIntent and s.catchIntent.requireDive==true,
            allowUprightFinish=s.playBudget~=nil and finishGoal~=nil
                and s.catchIntent.requireDive==true,
            sprintReserve=budget.reserve,
            preferGoalZ=finishGoal,
            wrDiveGoalZ=s.geo and s.geo.GoalZ or (Field.GoalZ and Field.GoalZ+(s.offset and s.offset.Z or 0)),
            defenderDeadline=s.role=="WR" and wrDefenderDeadline or nil,
            opponent=opponentSnapshot,opponents=opponentSnapshots,bounds=bounds,
            position=root.Position, velocity=root.AssemblyLinearVelocity,
            lookDirection=root.CFrame.LookVector, steeringDirection=steering, grounded=grounded,
            reachAirborne=reachOverride,
            physicalAirborne=motion.physicalAirborne,nativeAirborne=motion.nativeAirborne,
            motionReason=motion.reason,
            jumpSpeed=jumpSpeed, gravity=g,
            walkSpeed=locomotion.walkSpeed,runSpeed=locomotion.runSpeed,
            speedScale=locomotion.speedScale,sprintSeconds=sprintSeconds,chase=true,
            sprintPending=locomotion.sprintPending,sprintPendingAge=locomotion.sprintPendingAge,
            allowHold=false,
            groundRootY=grounded and root.Position.Y or turf+3,
            turfY=turf,diveTurfY=Field.TurfY,config=Config,
            diveDistance=Config.Moves.Dive.Yards*Field.YD,
            canJump=grounded and jumpSpeed>0 and now-lastJump>0.55
                and h:GetStateEnabled(Enum.HumanoidStateType.Jumping),
            canDive=motion.diveModeMatchesMotion and (grounded or motion.nativeAirborne) and divePermitted()
                and now-lastDive>=Config.Moves.Dive.Cooldown,
            maxHorizon=math.max(0.1,math.min(3.5,s.arc.Flight+0.4-(now-s.launchAt))),
            reactionDelay=controlledHumanoid and 0 or 0.035, margin=0.4,
            clipDiveDistance=clippedDistance}
    end
    local function solveActual(current)
        local result,reason,threat=Planner.solve(current)
        if current.role=="WR" and threat and threat.defenderDeadline then
            wrDefenderDeadline=threat.defenderDeadline
            current.defenderDeadline=wrDefenderDeadline
        end
        return result,reason,threat
    end
    local function stationaryPlan(s,root,h,now)
        local still=snapshot(s,root,h,now)
        still.walkSpeed,still.runSpeed,still.sprintSeconds=0,0,0
        still.velocity=Vector3.new(0,root.AssemblyLinearVelocity.Y,0)
        still.canDive,still.allowHold=false,false
        still.allowLastResort=false
        still.reactionDelay,still.margin=0,s.role=="DB" and 0.4 or 0.75
        return solveActual(still),still
    end
    local function preservesStationary(original,candidate,role)
        if not candidate or original.risk or candidate.risk then return false end
        local timing=(role~="DB" and original.safety~="contested")
            or candidate.contactAt<=original.contactAt+0.015
        if role=="WR" and original.safety=="contested" then
            timing=(candidate.firstTouchAt or candidate.contactAt)
                <=(original.firstTouchAt or original.contactAt)+0.015
        end
        local safety=role~="WR" or original.safety~="clear" or candidate.safety=="clear"
        local addsJump=role=="WR" and not original.jumpAt and candidate.jumpAt
        local preservesAir=not original.airborneFinish or candidate.airborneFinish~=nil
        return timing and safety and not addsJump and preservesAir
    end
    local function smoothDirection(desired, root, h, dt, preferForward)
        local flat=Vector3.new(desired.X,0,desired.Z)
        if flat.Magnitude<0.001 then return Vector3.zero end
        flat=flat.Unit
        if not steering then
            -- Commit the first movement input immediately. Native character
            -- rotation stays intact; later corrections remain smooth.
            steering=flat
        end
        local a=math.atan2(steering.X,steering.Z)
        local b=math.atan2(flat.X,flat.Z)
        local delta=(b-a+math.pi)%(2*math.pi)-math.pi
        -- Coverage targets remain goal-side. For lateral reversals, turn
        -- through that forward semicircle rather than the wrapped rear arc.
        if preferForward and flat.Z>=0 and steering.Z>=0 then delta=b-a end
        local turn=math.clamp(delta,-9*dt,9*dt)
        steering=Vector3.new(math.sin(a+turn),0,math.cos(a+turn))
        return steering
    end
    local function avoidPlayers(s,root,h,now,dt,direction,requestedSprint,canDetour,arrival)
        if not PlayerAvoidance or not s.playBudget then
            avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason=nil,nil,nil,nil
            avoidanceStatus={active=false,blocked=false}
            return {direction=direction,sprint=requestedSprint,active=false,blocked=false}
        end
        if avoidanceRoot~=root or avoidancePhase~=s.phase then
            avoidanceState=nil;avoidanceRoot=root;avoidancePhase=s.phase
        end
        local opponents,seen={},{}
        local function inspect(character)
            if not character or seen[character] then return end
            seen[character]=true
            local other=character:FindFirstChild("HumanoidRootPart")
            local otherH=character:FindFirstChildOfClass("Humanoid")
            if other and otherH and otherH.Health>0 then
                opponents[#opponents+1]={position=other.Position,velocity=other.AssemblyLinearVelocity}
            end
        end
        inspect(s.opponent)
        for _,character in ipairs(s.opponents or {}) do inspect(character) end
        local offset=s.offset or Vector3.zero
        local geo=s.geo
        local bounds=geo and {minX=geo.MinX+.5,maxX=geo.MaxX-.5,minZ=geo.BackZ+.5,maxZ=geo.EndZ-.5}
            or {minX=Field.MinX+offset.X+.5,maxX=Field.MaxX+offset.X-.5,
                minZ=Field.BackZ+offset.Z+.5,maxZ=Field.EndZ+offset.Z-.5}
        -- Live-ball pursuit may retain a collision-checked sprint even
        -- while native sprint speed is pending and no catch is reachable.
        -- WR route intent survives an abandoned postthrow stem; a missing
        -- arrival witness must not cancel its already requested safe sprint.
        -- A catch deadline is supplied only when a real witness exists.
        -- Prethrow coverage still conserves its reserve.
        local allowSprintDetour=s.phase=="Live" and (
            s.role=="WR" and s.catchIntent~=nil
                and (s.catchIntent.continuousSprint==true or s.arc~=nil)
            or s.role=="DB" and s.arc~=nil)
        local decision
        avoidanceState,decision=PlayerAvoidance.update(avoidanceState,{now=now,dt=dt,
            position=root.Position,velocity=root.AssemblyLinearVelocity,desiredDirection=direction,
            opponents=opponents,bounds=bounds,requestedSprint=requestedSprint,walkSpeed=h.WalkSpeed,
            targetPosition=arrival and arrival.targetPosition,arriveBy=arrival and arrival.arriveBy,
            runSpeed=Config.RunSpeed,currentDirection=steering,
            sprintSpeed=Config.SprintSpeed,
            -- The helper checks the actual turn at both movement speeds.
            allowSprintDetour=allowSprintDetour,
            canDetour=canDetour and h.FloorMaterial~=Enum.Material.Air and not h.PlatformStand})
        -- The avoidance helper already limits its turns and checks that path.
        -- A second smoother could turn back inside the checked clearance.
        if decision.active then
            local heading=avoidanceState and avoidanceState.heading
            if typeof(heading)=="Vector3" and heading.Magnitude>.001 then steering=heading.Unit
            elseif decision.direction.Magnitude>.001 then steering=decision.direction.Unit end
        end
        avoidanceStatus={active=decision.active,blocked=decision.blocked,reason=decision.reason}
        if decision.active and (decision.reason~=lastAvoidanceReason or now-lastAvoidanceLog>.3)
            or not decision.active and lastAvoidanceReason then
            log("playerAvoidance",{active=decision.active,blocked=decision.blocked,reason=decision.reason,
                role=s.role,phase=s.phase,position=xyz(root.Position),velocity=xyz(root.AssemblyLinearVelocity),
                requestedDirection=xyz(direction),direction=xyz(decision.direction),
                allowSprintDetour=allowSprintDetour,walkSpeed=h.WalkSpeed,
                approachTarget=arrival and xyz(arrival.targetPosition),arriveBy=arrival and arrival.arriveBy,
                requestedSprint=requestedSprint,sprint=decision.sprint,stamina=me:GetAttribute("Stamina")})
            lastAvoidanceLog=now
        end
        lastAvoidanceReason=decision.active and decision.reason or nil
        return decision
    end
    local function moveWRApproach(root,h,direction,dt)
        ownInput();controlledHumanoid=h
        if (tonumber(me:GetAttribute("Stamina")) or 0)>2 and me:GetAttribute("SprintOn")~=true then
            ownsSprint=true;Moves.HoldSprint(true)
        end
        h:Move(smoothDirection(direction,root,h,dt),false)
    end
    local function updateFullplay(s,root,h,now,dt)
        if type(ctx.fullplay)~="function" or not root or not h
            or h.PlatformStand or not Moves.Upright() then
            navigationIdleSince,navigationIdleRoot=nil,nil
            return false
        end
        local directive=ctx.fullplay(s,root,h,now,dt)
        local direction=type(directive)=="table" and directive.direction or nil
        if typeof(direction)~="Vector3" then
            navigationIdleSince,navigationIdleRoot=nil,nil
            return false
        end
        for _,component in ipairs({direction.X,direction.Y,direction.Z}) do
            if component~=component or math.abs(component)==math.huge then
                navigationIdleSince,navigationIdleRoot=nil,nil
                return false
            end
        end
        local flat=direction*Vector3.new(1,0,1)
        local strength=math.min(flat.Magnitude,1)
        navigation=true
        ownInput();controlledHumanoid=h
        if carrierAssist then
            local active,note=carrierAssist.update(s,root,h,now)
            if active then
                navigationIdleSince,navigationIdleRoot=nil,nil
                releaseSprint()
                return true,note
            end
        end
        local velocity=root.AssemblyLinearVelocity
        local stopped=s.playBudget~=nil and not s.arc and not jumped and not jumpRequest and not dived
            and h.FloorMaterial~=Enum.Material.Air and strength<.001
            and typeof(velocity)=="Vector3" and (velocity*Vector3.new(1,0,1)).Magnitude<1
        if stopped then
            if navigationIdleRoot~=root or not navigationIdleSince or now<navigationIdleSince then
                navigationIdleRoot,navigationIdleSince=root,now
            elseif now-navigationIdleSince>=.15 then
                -- A settled stop has no previous travel direction. Retaining
                -- one can restart forward coverage by walking backward first.
                -- Moving reversals and committed catch actions keep smoothing.
                steering=nil
                avoidanceState,avoidanceRoot,avoidancePhase,lastAvoidanceReason=nil,nil,nil,nil
                avoidanceStatus={active=false,blocked=false}
            end
        else
            navigationIdleSince,navigationIdleRoot=nil,nil
        end
        local budget=sprintBudget(s)
        local avoid=avoidPlayers(s,root,h,now,dt,flat,strength>0.001 and directive.sprint==true and budget.canSprint,true,
            s.role=="WR" and directive.avoidanceArrival or nil)
        flat=avoid.direction*Vector3.new(1,0,1)
        strength=math.min(flat.Magnitude,1)
        if strength>0.001 and avoid.sprint==true then
            ownsSprint=true
            if me:GetAttribute("SprintOn")~=true then Moves.HoldSprint(true) end
        else
            -- Full-play owns this movement decision, including an upright stop.
            if ownsSprint or me:GetAttribute("SprintOn")==true then Moves.HoldSprint(false) end
            ownsSprint=false
        end
        if directive.hardCut==true and s.role=="WR" and not h.PlatformStand
            and motionState(s,root,h).grounded and not jumped and not jumpRequest and not dived
            and not avoid.active then
            log("wrHardCut",{phase="route",position=xyz(root.Position),
                fromDirection=xyz(steering),direction=xyz(flat)})
            steering=nil
        end
        h:Move(strength>0.001 and (avoid.active and flat
            or smoothDirection(flat,root,h,dt,directive.preserveDepth==true)*strength) or Vector3.zero,false)
        return true,avoid.active and (avoid.blocked and "Blocked · saving sprint and moving clear"
            or "Moving around opponent") or directive.message or "Automatic play"
    end
    local function updatePostThrowStem(s,root,h,now,dt)
        if stemFinished then return false end
        local function finishStem(reason)
            if stemWasActive and s.role=="WR" and not h.PlatformStand
                and not plan and not jumped and not jumpRequest and not dived and motionState(s,root,h).grounded then
                -- One sharp handoff command; later corrections still smooth.
                -- Avoidance state is deliberately retained and has priority.
                log("wrHardCut",{phase="postThrow",position=xyz(root.Position),
                    fromDirection=xyz(steering),reason=reason})
                steering=nil
            end
            stemFinished=true;stemForecast=nil;nextSolve=0;stemWasActive=false
        end
        local requested=s.role=="WR" and s.catchIntent and s.catchIntent.postThrowStem
        if type(requested)~="table" or plan or jumped or jumpRequest or dived or h.PlatformStand then
            finishStem("Stem ended or an action owns movement");return false
        end
        local stage={}
        for k,v in pairs(requested) do stage[k]=v end
        if typeof(stage.point)~="Vector2" then finishStem("Invalid stem point");return false end
        local offset=s.offset or Vector3.zero
        stage.point=Vector3.new(stage.point.X+offset.X,root.Position.Y,stage.point.Y+offset.Z)
        local fresh=snapshot(s,root,h,now)
        local stamina=tonumber(me:GetAttribute("Stamina"))
        local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
        local remaining=finite(stage.untilAt) and stage.untilAt-now or -1
        local valid=fresh.grounded and fresh.canJump==true and finite(stamina)
            and finite(stage.sprintStartAt) and finite(stage.sprintDrain) and stage.sprintDrain>0
            and finite(stage.reserve) and stage.reserve>=0 and remaining>.04 and remaining<=2
        valid=valid and (stage.stemRunSpeed==nil or finite(stage.stemRunSpeed) and stage.stemRunSpeed>0)
            and (stage.recoveryUntilAt==nil or finite(stage.recoveryUntilAt))
        local fast=valid and Planner.stemSprintSeconds(now,stage.untilAt,stage.sprintStartAt,stage.recoveryUntilAt) or 0
        local stemRun=valid and math.min(fresh.runSpeed,stage.stemRunSpeed or math.huge) or 0
        local distance=((stage.point-root.Position)*Vector3.new(1,0,1)).Magnitude
        local capacity=valid and (remaining-fast)*stemRun+fast*fresh.walkSpeed or 0
        local needed=valid and stemForecast and (stemForecast.plan.contactAt-stage.untilAt+.24)*stage.sprintDrain or 0
        if not valid or distance~=distance or capacity<distance+.15
            or stamina-fast*stage.sprintDrain-needed<stage.reserve then
            finishStem("Current middle-stem movement or sprint budget changed")
            log("wrStemRelease",{reason="Current middle-stem movement or sprint budget changed",position=xyz(root.Position),
                remaining=remaining,distance=distance,capacity=capacity,stamina=stamina,
                grounded=fresh.grounded,canJump=fresh.canJump,lateSprintSeconds=fast,
                finalSprintCost=needed,reserve=stage.reserve,walkSpeed=fresh.walkSpeed,runSpeed=fresh.runSpeed})
            return false
        end
        local signature=string.format("%.6f/%.6f/%.6f/%.6f/%.6f/%.6f/%.6f/%.6f",
            stage.point.X,stage.point.Z,stage.untilAt,stage.sprintStartAt,stage.reserve,stage.sprintDrain,
            stemRun,stage.recoveryUntilAt or 0)
        local check=now>=nextStemCheck or fresh.walkSpeed~=stemLastSpeed or fresh.runSpeed~=stemLastRun
            or fresh.sprintPending~=stemLastSprint or signature~=stemLastStage
        local reason,immediateSolveMs
        if check then
            stemForecast,reason=Planner.forecastStem(fresh,stage,stamina)
            nextStemCheck=now+.10
            stemLastSpeed,stemLastSprint=fresh.walkSpeed,fresh.sprintPending
            stemLastRun,stemLastStage=fresh.runSpeed,signature
            if stemForecast and fresh.requireEndzoneCatch==true then
                -- A funded route extension is not permission to delay an
                -- already reachable catch. Compare first contact using the
                -- same actual motion/stamina snapshot and normal safety gates.
                -- Ten milliseconds is a numerical tie allowance, not a new
                -- waiting budget. Normal catch control solves again on handoff.
                local solveStarted=os.clock()
                local immediate=Planner.solve(fresh)
                immediateSolveMs=(os.clock()-solveStarted)*1000
                local first=immediate and immediate.firstTouchAt
                local later=stemForecast.plan.firstTouchAt
                local origin=immediate and immediate.firstTouchRoot
                if immediate and immediate.reachable~=false and not immediate.risk and immediate.robust~=false
                    and (immediate.airborneFinish=="jump" or immediate.airborneFinish=="jumpDive")
                    and finite(immediate.margin) and immediate.margin>=(fresh.margin or .4)
                    and finite(first) and first>fresh.now and finite(later) and later-first>.010001
                    and finite(fresh.wrDiveGoalZ) and typeof(origin)=="Vector3"
                    and finite(origin.Z) and origin.Z>=fresh.wrDiveGoalZ+.25 then
                    log("wrStemRelease",{reason="Earlier airborne catch available now",position=xyz(root.Position),
                        immediateFirstTouchAt=first,continuedFirstTouchAt=later,earlierBy=later-first,
                        immediateAction=immediate.kind,immediateSolveMs=immediateSolveMs})
                    finishStem("Earlier airborne catch available now")
                    return false
                end
            end
        end
        local current=workspace:GetServerTimeNow()
        if not stemForecast or current>=stage.untilAt-.04 or not fresh.grounded then
            log("wrStemRelease",{reason=reason or "Cut deadline reached",position=xyz(root.Position),
                cutAt=stage.untilAt,remaining=stage.untilAt-current})
            finishStem(reason or "Cut deadline reached")
            -- Final catch steering issues one sudden directional input.
            return false
        end
        local state={}
        for k,v in pairs(s) do state[k]=v end
        state.allowPostThrowStem=true
        local active,note=updateFullplay(state,root,h,current,dt)
        if not active then
            finishStem("Middle route no longer owns movement")
            log("wrStemRelease",{reason="Middle route no longer owns movement",position=xyz(root.Position)})
            return false
        end
        stemWasActive=true
        if check then log("wrPostThrowStem",{position=xyz(root.Position),cutAt=stage.untilAt,
            contactAt=stemForecast.plan.contactAt,staminaAfterCatch=stemForecast.staminaAfterCatch,
            sprint=me:GetAttribute("SprintOn")==true,immediateSolveMs=immediateSolveMs}) end
        message=note or "WR · deep middle stem before sharp cut"
        return true
    end
    local function updateWRReturn(s,root,h,now,dt)
        if not wrReturn then return false end
        if now>=wrReturn.deadline or motionState(s,root,h).physicalAirborne or not Moves.Upright() then
            log("wrApproachTurnEnd",{position=xyz(root.Position),elapsed=now-wrReturn.started})
            wrReturn=nil;plan,lastSnapshot=nil,nil;nextSolve=now
            atTarget,parkedPosition=false,nil
            return false
        end
        moveWRApproach(root,h,wrReturn.direction,dt)
        message="WR · turning back for timed catch"
        return true
    end
    local function updateWRFake(s,root,h,now,dt)
        if not wrFake then return false end
        local fake=wrFake
        local reason,candidate,slack,forecast
        if now>=fake.deadline then reason="commit time"
        elseif motionState(s,root,h).physicalAirborne or not Moves.Upright() then reason="movement changed"
        elseif now>=nextWRFakeCheck then
            nextWRFakeCheck=now+0.06
            local current=snapshot(s,root,h,now)
            candidate,slack,forecast=WRApproach.checkReturn(Planner,current,fake)
            if not candidate then reason=tostring(slack or "catch becoming urgent")
            elseif slack<=0.12 then reason="latest return time" end
        end
        if reason then
            if not candidate and reason=="commit time" then
                candidate,slack,forecast=WRApproach.checkReturn(Planner,snapshot(s,root,h,now),fake)
            end
            log("wrApproachCommit",{reason=reason,position=xyz(root.Position),elapsed=now-fake.started,
                arrivalSlack=candidate and slack or nil,catchAt=candidate and candidate.contactAt or nil,
                turnTime=forecast and forecast.turnDuration or nil})
            wrFake=nil;plan,lastSnapshot=nil,nil;nextSolve=now
            atTarget,parkedPosition=false,nil
            if candidate and forecast and forecast.turnDuration>0.001 then
                wrReturn={started=now,deadline=now+forecast.turnDuration,direction=forecast.direction}
                return updateWRReturn(s,root,h,now,dt)
            end
            return false
        end
        moveWRApproach(root,h,fake.direction,dt)
        message="WR · moving away · returning just before catch"
        if now>=nextWRFakeSample then
            nextWRFakeSample=now+0.15
            log("wrApproachSample",{position=xyz(root.Position),deadline=fake.deadline,
                direction=xyz(fake.direction),stamina=me:GetAttribute("Stamina"),arrivalSlack=slack})
        end
        return true
    end
    local function tick(dt)
        local s = ctx.snapshot()
        local supportedRole=s.role=="DB" or s.role=="WR"
        local pauseReason=not alive and "unloaded" or not auto and "auto disabled"
            or not s.enabled and "assist disabled" or s.testing and "visual test"
            or not supportedRole and "unsupported role"
            or UIS:GetFocusedTextBox() and "text input" or GuiService.MenuIsOpen and "game menu"
        if pauseReason then
            if pauseReason~=lastPauseReason then
                log("paused",{reason=pauseReason,phase=s.phase,role=s.role})
                lastPauseReason=pauseReason
            end
            if tackleAssist then tackleAssist.cancel() end
            catching=false
            cancel()
            message = not auto and "Auto OFF" or (s.testing and "Visual test · no movement"
                or (not supportedRole and "Waiting for WR/DB turn" or "Waiting for throw"))
            return
        end
        if lastPauseReason then
            log("resumed",{reason=lastPauseReason,phase=s.phase,role=s.role})
            lastPauseReason=nil
        end
        local now = workspace:GetServerTimeNow()
        enforceSprintReserve(s)
        if s.phase~="Live" or not s.arc or not s.launchAt then
            wrDefenderDeadline=nil
            trackedMotionRoot,trackedAirborne=nil,false
            if catching then cancel(); catching=false end
            local root,h=healthyCharacter()
            if root then locomotionState(root,h,now) end
            local active,note
            -- Tackle attempts take ownership before navigation is considered.
            navigation=false
            if tackleAssist and root then active,note=tackleAssist.update(s,root,h,now,dt) end
            if not active then active,note=updateFullplay(s,root,h,now,dt) end
            if not active then release() end
            message=note or (s.enemyCarrier and s.role=="DB"
                and "TACKLE · waiting for carrier in range" or "Waiting for throw")
            return
        end
        navigation=false
        if tackleAssist then tackleAssist.cancel(true) end
        catching=true
        if throwKey~=s.launchAt then
            local preserveMovement=s.playBudget and ownsSprint and me:GetAttribute("SprintOn")==true
                and controlledHumanoid and controlledHumanoid.Parent and not controlledHumanoid.PlatformStand
            cancel(preserveMovement)
            wrDefenderDeadline=nil
            trackedMotionRoot,trackedAirborne=nil,false
            throwKey, nextSolve = s.launchAt, 0
            stemFinished,stemForecast,nextStemCheck,stemLastSpeed,stemLastSprint=false,nil,0,nil,nil
            stemLastRun,stemLastStage=nil,nil
            stemWasActive=false
            wrFakeUsed=false;lastWRSkipReason=nil
            throwRole=s.role
            if claimedKey~=s.launchAt then
                claimedKey=nil;claimObservedAt,claimTraceCount,claimTraceNext=nil,0,0
            end
            counters.throws = counters.throws+1
            log("throw", {launchAt=s.launchAt, flight=s.arc.Flight, apex=s.arc.Apex,
                networkPing=networkPing(),
                origin=xyz(s.arc.P0),target=xyz(s.arc.P1),role=s.role,mode=s.mode or "1v1"})
        end
        if claimedKey==s.launchAt then
            observePendingClaim(s,now)
            message="Catch attempt sent · awaiting result"; return
        end
        ownInput()
        local root, h = healthyCharacter()
        if not root then cancel(); message="Waiting for character"; return end
        local currentLocomotion=locomotionState(root,h,now,sprintBudget(s).seconds)
        local motion=motionState(s,root,h)
        if updatePostThrowStem(s,root,h,now,dt) then return end
        h.Jump=jumpRequest~=nil
        if jumpRequest then
            local rise=root.Position.Y-jumpRequest.y
            local rising=(root.AssemblyLinearVelocity.Y>5 and rise>0.12)
                or (h.FloorMaterial==Enum.Material.Air and rise>0.15)
            if rising then
                local disc=math.max(0,lastSnapshot.jumpSpeed*lastSnapshot.jumpSpeed
                    -2*lastSnapshot.gravity*math.max(0,rise))
                local elapsed=math.clamp((lastSnapshot.jumpSpeed-math.sqrt(disc))
                    /lastSnapshot.gravity,0,0.15)
                lastJump=math.clamp(now-elapsed,jumpRequest.time-0.02,now)
                if plan then plan.jumpAt=lastJump;plan._jumpDelay=lastJump-lastSnapshot.now end
                if s.role=="DB" then confirmedCatchJump={at=lastJump,baseY=jumpRequest.y} end
                counters.jumps=counters.jumps+1
                log("jump",{position=xyz(root.Position),takeoffDelay=lastJump-jumpRequest.time,
                    estimatedTakeoffAt=lastJump,dispatchAt=jumpRequest.dispatchedAt,
                    dispatchToConfirmation=now-(jumpRequest.dispatchedAt or jumpRequest.time)})
                jumpRequest=nil;h.Jump=false
            elseif now-(jumpRequest.dispatchedAt or jumpRequest.time)<0.12 then
                -- Sending Jump is not takeoff confirmation. The ball may have
                -- passed while the native request was still waiting to start.
                local requestNow=workspace:GetServerTimeNow()
                if cancelStaleAction(requestNow) then h.Jump=false;return end
                h.Jump=true
                if requestNow-(jumpRequest.dispatchedAt or jumpRequest.time)>0.045 and not jumpRequest.retried
                    and h:GetState()~=Enum.HumanoidStateType.Jumping
                    and h:GetState()~=Enum.HumanoidStateType.Freefall then
                    local retryAt=workspace:GetServerTimeNow()
                    if cancelStaleAction(retryAt) then h.Jump=false;return end
                    jumpRequest.retried=true
                    h:ChangeState(Enum.HumanoidStateType.Jumping)
                    log("jumpRetry",{dispatchAt=jumpRequest.dispatchedAt,
                        age=now-(jumpRequest.dispatchedAt or jumpRequest.time)})
                end
            else
                log("actionRejected",{action="jump",reason="no takeoff observed",role=s.role,
                    position=xyz(root.Position),jumpHeight=h.JumpHeight})
                cancel();nextSolve=now
                message="Jump did not start · retrying reachable catch"
                return
            end
        end
        if h.PlatformStand and not dived then
            cancel(); message="Waiting for current move"; return
        end
        local previousReach=reachAirborne
        local nativeAir=motion.nativeAirborne
        local turf=s.geo and s.geo.TurfY or Field.TurfY
        local aloft=confirmedCatchJump and root.Position.Y>
            math.max(confirmedCatchJump.baseY,turf+3)+1
        if motion.physicalAirborne and not nativeAir and not jumped and not jumpRequest
            and not dived and not h.PlatformStand then
            groundedReachSince,reachAirborne=nil,false
        elseif s.role=="DB" and confirmedCatchJump and not dived and not h.PlatformStand
            and now-confirmedCatchJump.at>0.10 and aloft then
            if nativeAir then
                groundedReachSince,reachAirborne=nil,nil
            else
                groundedReachSince=groundedReachSince or now
                if now-groundedReachSince>=0.04 then reachAirborne=false end
            end
        else
            groundedReachSince,reachAirborne=nil,nil
            if confirmedCatchJump and now-confirmedCatchJump.at>0.10 and not aloft then
                confirmedCatchJump=nil
            end
        end
        if previousReach~=reachAirborne and plan and not dived then
            log("replan",{action=plan.kind,role=s.role,position=xyz(root.Position),
                reason=reachAirborne==false and "native catch reach shortened"
                    or (nativeAir and "native airborne reach restored" or "jump returning to ground"),
                parked=atTarget,jumped=jumped})
            plan,lastSnapshot=nil,nil
            jumped=false
            atTarget,parkedPosition=false,nil
            nextSolve=now
        end
        if Motion.shouldRefreshPursuit(plan,lastSnapshot,motion,
            jumpRequest~=nil or dived or h.PlatformStand) then
            log("replan",{action=plan.kind,role=s.role,position=xyz(root.Position),
                reason="airborne dive available after restricted pursuit",jumped=jumped})
            plan,lastSnapshot=nil,nil
            jumped=false
            atTarget,parkedPosition=false,nil
            nextSolve=now
        end
        if plan and lastSnapshot then
            local committed=jumped or dived or jumpRequest~=nil or h.PlatformStand
                or atTarget or not motion.grounded
            if Motion.shouldRefreshLocomotion(lastSnapshot,currentLocomotion,committed) then
                log("replan",{action=plan.kind,role=s.role,position=xyz(root.Position),
                    reason=currentLocomotion.sprintPending and "sprint awaiting native speed"
                        or lastSnapshot.sprintPending and "native sprint forecast restored"
                        or "native movement speed changed",
                    speedScale=currentLocomotion.speedScale,currentSpeed=h.WalkSpeed,
                    walkSpeed=currentLocomotion.walkSpeed,sprintPending=currentLocomotion.sprintPending,
                    sprintPendingAge=currentLocomotion.sprintPendingAge})
                plan,lastSnapshot=nil,nil
                nextSolve=now
            end
        end
        if wrReturn and updateWRReturn(s,root,h,now,dt) then return end
        if wrFake and updateWRFake(s,root,h,now,dt) then return end
        if plan and not dived and not jumpRequest and now>=nextCheck then
            nextCheck=now+0.045
            local sampleAt=now
            if plan.jumpAt and not jumped then sampleAt=math.min(sampleAt,plan.jumpAt) end
            if plan.diveAt and not dived then sampleAt=math.min(sampleAt,plan.diveAt) end
            local predicted=Planner.pose(lastSnapshot,plan,sampleAt)
            local missedJump=plan.jumpAt and not jumped and now-plan.jumpAt>0.075
            local missedDive=plan.diveAt and not dived and now-plan.diveAt>0.075
            local actionAt=math.min(plan.jumpAt or math.huge,plan.diveAt or math.huge)
            local refresh=plan.kind=="pursue" and now>=nextReplan
                or (not jumped and not atTarget and now>=nextReplan and actionAt-now>0.12
                    and plan.contactAt-now>0.16)
            local displaced
            local lostJumpHeight=s.role=="DB" and atTarget and confirmedCatchJump
                and now-confirmedCatchJump.at>0.10
                and predicted.Position.Y-root.Position.Y>0.6
            if atTarget and parkedPosition and not plan.diveAt then
                local tolerance=math.max(0.5,math.min(1.2,(plan.margin or 0.9)-0.15))
                displaced=((root.Position-parkedPosition)*Vector3.new(1,0,1)).Magnitude>tolerance
                    or lostJumpHeight
                if displaced and not jumped and motion.grounded
                    and reachAirborne~=false then
                    local adjusted,still=stationaryPlan(s,root,h,now)
                    if preservesStationary(plan,adjusted,s.role) then
                        plan,lastSnapshot=adjusted,still
                        plan.approachTarget=root.Position
                        parkedPosition=root.Position
                        jumped,dived=false,false
                        nextReplan=math.huge
                        displaced,missedJump,missedDive,refresh=false,false,false,false
                    end
                end
            else displaced=(root.Position-predicted.Position).Magnitude>1.3 end
            if displaced or missedJump or missedDive or refresh then
                log("replan",{action=plan.kind,role=s.role,
                    reason=lostJumpHeight and "jump height changed" or displaced and "position drift" or missedJump and "missed jump"
                        or missedDive and "missed dive" or "refresh",
                    position=xyz(root.Position),expected=xyz(predicted.Position),
                    diveIn=plan.diveAt and plan.diveAt-now or nil,
                    parked=atTarget,jumped=jumped})
                plan,lastSnapshot=nil,nil
                jumped,dived=false,false
                atTarget,parkedPosition=false,nil
                nextSolve=now
            end
        end
        if not plan and now>=nextSolve then
            nextSolve = now+0.045
            if not Moves.Upright() then message="Waiting for current move"; return end
            lastSnapshot = snapshot(s, root, h, now)
            local solveStarted=os.clock()
            local planReason
            plan,planReason = solveActual(lastSnapshot)
            if not plan then
                plan=Planner.pursuit(lastSnapshot)
                if plan and s.role=="WR" then plan.airborneUnavailable=planReason end
            end
            local solveMs=(os.clock()-solveStarted)*1000
            if plan then
                nextReplan=now+0.24
                jumped, dived = false, false
                if plan.kind=="pursue" then
                    plan.approachTarget=plan.contactPosition
                elseif plan.diveAt then
                    local approach=Planner.pose(lastSnapshot,plan,plan.diveAt-0.0001)
                    plan.approachTarget=approach.Position
                else plan.approachTarget=plan.rootTarget end
                local distance=((plan.approachTarget-root.Position)*Vector3.new(1,0,1)).Magnitude
                if distance>2.5 or plan.continuousCatch then atTarget,parkedPosition=false,nil end
                log("plan", {action=plan.kind, contactAt=plan.contactAt,
                    approachTarget=xyz(plan.approachTarget),
                    jumpAt=plan.jumpAt, diveAt=plan.diveAt,
                    jumpTimingBudget=plan.jumpTimingBudget,diveTimingBudget=plan.diveTimingBudget,
                    continuousCatch=plan.continuousCatch,movementScale=plan.movementScale,stopAt=plan.stopAt,
                    margin=plan.margin,reachable=plan.reachable,role=s.role,
                    uprightFinishOverride=plan.uprightFinishOverride,
                    uprightFinishReason=plan.uprightFinishReason,
                    allowUprightFinish=lastSnapshot.allowUprightFinish,
                    risk=plan.risk,riskReason=plan.riskReason,
                    requiredMargin=plan.requiredMargin,timingMargin=plan.timingMargin,
                    canJump=lastSnapshot.canJump,canDive=lastSnapshot.canDive,
                    snapshotNow=lastSnapshot.now,grounded=lastSnapshot.grounded,
                    physicalAirborne=lastSnapshot.physicalAirborne,nativeAirborne=lastSnapshot.nativeAirborne,
                    motionReason=lastSnapshot.motionReason,
                    airborneFinish=plan.airborneFinish,airborneRequired=plan.airborneRequired,
                    earliestAirborne=plan.earliestAirborne,passType=lastSnapshot.passType,
                    requireEndzoneCatch=lastSnapshot.requireEndzoneCatch,wrDiveGoalZ=lastSnapshot.wrDiveGoalZ,
                    solveMs=solveMs,
                    velocity=xyz(lastSnapshot.velocity),currentSpeed=h.WalkSpeed,
                    lookDirection=xyz(lastSnapshot.lookDirection),steeringDirection=xyz(lastSnapshot.steeringDirection),
                    walkSpeed=lastSnapshot.walkSpeed,runSpeed=lastSnapshot.runSpeed,
                    speedScale=lastSnapshot.speedScale,
                    sprintPending=lastSnapshot.sprintPending,sprintPendingAge=lastSnapshot.sprintPendingAge,
                    sprintSeconds=lastSnapshot.sprintSeconds,gravity=lastSnapshot.gravity,
                    groundRootY=lastSnapshot.groundRootY,turfY=lastSnapshot.turfY,diveTurfY=lastSnapshot.diveTurfY,
                    sprintOn=me:GetAttribute("SprintOn"),reactionDelay=lastSnapshot.reactionDelay,
                    bounds=lastSnapshot.bounds,
                    opponent=traceOpponent(lastSnapshot.opponent),opponents=traceOpponents(lastSnapshot.opponents),
                    reachAirborne=lastSnapshot.reachAirborne,
                    jumpSpeed=lastSnapshot.jumpSpeed,diveDistance=lastSnapshot.diveDistance,
                    predictedMiss=plan.predictedMiss,position=xyz(root.Position),
                    firstTouchAt=plan.firstTouchAt,firstTouch=xyz(plan.firstTouchPosition),
                    effectiveProgress=plan.effectiveProgress,safety=plan.safety,
                    defenderAt=plan.defenderAt,
                    defenderDeadline=wrDefenderDeadline,observedDefenderAt=plan.observedDefenderAt,
                    contact=xyz(plan.contactPosition), direction=xyz(plan.direction)})
                if WRApproach and s.role=="WR" and not plan.continuousCatch
                    and not lastSnapshot.continuousSprint and not lastSnapshot.requireDive
                    and not wrFakeUsed and not jumpRequest then
                    local fake,whyFake=WRApproach.choose(Planner,lastSnapshot,plan)
                    if fake then
                        wrFakeUsed=true;wrFake=fake;fake.started=now
                        if fake.entryDirection then steering=fake.entryDirection end
                        nextWRFakeCheck=now+0.06;nextWRFakeSample=0
                        log("wrApproachStart",{position=xyz(root.Position),waypoint=xyz(fake.waypoint),
                            direction=xyz(fake.direction),duration=fake.duration,
                            spareTime=fake.spareTime,commitBy=fake.commitBy,
                            arrivalAt=fake.arrivalAt,catchAt=fake.catchAt,arrivalSlack=fake.remainingArrivalSlack})
                    elseif whyFake~=lastWRSkipReason then
                        lastWRSkipReason=whyFake
                        log("wrApproachSkipped",{reason=whyFake,action=plan.kind,safety=plan.safety,
                            catchAt=plan.contactAt,arrivalAt=plan.stopAt,position=xyz(root.Position)})
                    end
                end
            else release(); message="Throw finished · awaiting result" end
        end
        if wrFake and updateWRFake(s,root,h,now,dt) then return end
        if not plan then return end
        if not plan.timedArrival and not plan.continuousCatch and lastSnapshot and lastSnapshot.continuousApproach then
            local paced=Planner.timeArrival(lastSnapshot,plan)
            if paced then
                plan=paced
                atTarget,parkedPosition=false,nil
                log("wrTimedArrival",{contactAt=plan.contactAt,stopAt=plan.stopAt,
                    movementScale=plan.movementScale,position=xyz(root.Position)})
            end
        end
        if not atTarget and plan.reachable~=false and not plan.diveAt and not jumped
            and not plan.timedArrival and not plan.continuousCatch and motion.grounded and reachAirborne~=false then
            local distance=((plan.approachTarget-root.Position)*Vector3.new(1,0,1)).Magnitude
            if distance<3 or now>=plan.stopAt then
                local stationary,still=stationaryPlan(s,root,h,now)
                if preservesStationary(plan,stationary,s.role) then
                    plan,lastSnapshot=stationary,still
                    plan.approachTarget=root.Position
                    atTarget,parkedPosition=true,root.Position
                    jumped,dived=false,false
                    nextReplan=math.huge
                    controlledHumanoid=h
                    h:Move(Vector3.zero,false)
                    releaseSprint()
                    log("park",{role=s.role,position=xyz(root.Position),
                        contactAt=plan.contactAt,jumpAt=plan.jumpAt,
                        firstTouch=xyz(plan.firstTouchPosition),safety=plan.safety,
                        defenderAt=plan.defenderAt})
                end
            end
        end
        if plan.kind=="hold" then releaseSprint() end
        if plan.kind~="pursue" and now>plan.contactAt+0.14 then
            plan,lastSnapshot=nil,nil
            jumped,dived=false,false
            message="Attempt complete · checking remaining flight"
            nextSolve=now
            return
        end
        -- The forecast's startup allowance covers native input/sprint latency.
        -- Send movement immediately; waiting that allowance here adds it twice.
        if plan.kind~="hold" and not dived and not h.PlatformStand then
            controlledHumanoid = h
            local delta=(plan.approachTarget-root.Position)*Vector3.new(1,0,1)
            if plan.diveAt or plan.continuousCatch then
                -- A continuous catch crosses its target with native momentum.
                -- Never replace that checked trajectory with a parked plan.
                -- A dive approach is a launch point, not a stationary catch.
                -- Airborne momentum must never replace it with a parked plan.
                atTarget,parkedPosition=false,nil
            elseif delta.Magnitude<0.65 and not atTarget and not jumped
                and (not plan.timedArrival or now>=plan.stopAt)
                and motion.grounded and reachAirborne~=false then
                atTarget,parkedPosition=true,root.Position
            elseif delta.Magnitude>2.5 then atTarget,parkedPosition=false,nil end
            local moving=not atTarget and (plan.kind=="pursue" or plan.diveAt~=nil or now<plan.stopAt)
            if moving then
                local desired=plan.continuousCatch and plan.direction
                    or (plan.diveAt or plan.timedArrival) and delta:Dot(plan.direction)<=0 and plan.direction
                    or (delta.Magnitude>0.1 and delta.Unit or plan.direction)
                local actionAt=math.min(plan.jumpAt or math.huge,plan.diveAt or math.huge,plan.contactAt or math.huge)
                local arrival=plan.kind~="pursue" and {targetPosition=plan.approachTarget,
                    arriveBy=math.min(plan.stopAt or math.huge,plan.diveAt or math.huge,plan.contactAt or math.huge)} or nil
                local avoid=avoidPlayers(s,root,h,now,dt,desired*(plan.movementScale or 1),sprintBudget(s).canSprint,
                    not jumped and not jumpRequest and not dived and actionAt-now>.35,arrival)
                if avoid.sprint and me:GetAttribute("SprintOn")~=true then
                    ownsSprint=true;Moves.HoldSprint(true)
                    log("sprint",{position=xyz(root.Position),stamina=me:GetAttribute("Stamina")})
                elseif not avoid.sprint and s.playBudget and me:GetAttribute("SprintOn")==true then
                    Moves.HoldSprint(false);ownsSprint=false
                    trackedSprintRoot,sprintTracking=nil,nil
                end
                h:Move(avoid.active and avoid.direction
                    or smoothDirection(avoid.direction,root,h,dt)*math.min(1,avoid.direction.Magnitude),false)
                if avoid.active then nextReplan=math.min(nextReplan,now+.1) end
            else
                h:Move(Vector3.zero,false)
                releaseSprint()
            end
        end
        -- Planning can consume part of a frame. Keep its timestamp as the
        -- motion-model anchor, but start action grace periods at dispatch.
        local actionNow=workspace:GetServerTimeNow()
        if cancelStaleAction(actionNow) then h.Jump=false;return end
        if plan.jumpAt and not jumped and actionNow>=plan.jumpAt then
            motion=motionState(s,root,h)
            if motion.grounded and reachAirborne~=false and Moves.Upright() then
                local actual=snapshot(s,root,h,workspace:GetServerTimeNow())
                actual.now=workspace:GetServerTimeNow()
                actual.position,actual.velocity=root.Position,root.AssemblyLinearVelocity
                local valid,why=Planner.validateJump(actual,plan)
                if not valid then
                    log("replan",{role=s.role,reason=why,action="jump",
                        checkedAt=actual.now,scheduledJump=plan.jumpAt,contactAt=plan.contactAt,
                        position=xyz(actual.position),velocity=xyz(actual.velocity),
                        speed=actual.walkSpeed,canJump=actual.canJump,
                        grounded=actual.grounded,reachAirborne=actual.reachAirborne,
                        jumpTimingBudget=plan.jumpTimingBudget,diveTimingBudget=plan.diveTimingBudget})
                    cancel();h.Jump=false;nextSolve=workspace:GetServerTimeNow()+0.045
                    message="Jump contact changed · recalculating"
                    return
                end
                local dispatchAt=workspace:GetServerTimeNow()
                if cancelStaleAction(dispatchAt) then h.Jump=false;return end
                h.Jump = true
                h:ChangeState(Enum.HumanoidStateType.Jumping)
                jumped=true
                jumpRequest={time=now,dispatchedAt=dispatchAt,y=root.Position.Y}
                log("jumpRequest", {position=xyz(root.Position),delay=dispatchAt-plan.jumpAt,
                    dispatchAt=dispatchAt,frameAt=now,scheduledAt=plan.jumpAt})
            else
                cancel(); message="Jump window changed · recalculating"; return
            end
        end
        actionNow=workspace:GetServerTimeNow()
        if cancelStaleAction(actionNow) then h.Jump=false;return end
        if plan.diveAt and not dived and actionNow>=plan.diveAt then
            motion=motionState(s,root,h)
            if not motion.diveModeMatchesMotion or reachAirborne==false then
                log("replan",{role=s.role,reason="native dive mode disagrees with motion",
                    position=xyz(root.Position),velocity=xyz(root.AssemblyLinearVelocity)})
                cancel();nextSolve=now
                message="Jump started · recalculating from airborne position"
                return
            end
            if plan.jumpAt and (not jumped or jumpRequest or actionNow-lastJump<0.045
                or h.FloorMaterial~=Enum.Material.Air) then return end
            if s.role=="WR" and plan.airborneFinish=="jumpDive" then
                local actual=snapshot(s,root,h,actionNow)
                local valid,why=Planner.validateAirborneDive(actual,plan)
                if not valid then
                    local expected=lastSnapshot and Planner.pose(lastSnapshot,plan,actual.now)
                    log("replan",{role=s.role,reason=why,action="airborneDive",
                        checkedAt=actual.now,scheduledJump=plan.jumpAt,scheduledDive=plan.diveAt,
                        contactAt=plan.contactAt,position=xyz(actual.position),velocity=xyz(actual.velocity),
                        expected=expected and xyz(expected.Position),direction=xyz(plan.direction),
                        speed=actual.walkSpeed,runSpeed=actual.runSpeed,sprintSeconds=actual.sprintSeconds,
                        grounded=actual.grounded,nativeAirborne=actual.nativeAirborne,
                        physicalAirborne=actual.physicalAirborne,reachAirborne=actual.reachAirborne,
                        canDive=actual.canDive,wrDiveGoalZ=actual.wrDiveGoalZ,bounds=actual.bounds,
                        jumpSpeed=actual.jumpSpeed,gravity=actual.gravity,
                        groundRootY=actual.groundRootY,turfY=actual.turfY,diveTurfY=actual.diveTurfY,
                        requiredMargin=plan.requiredMargin,timingMargin=plan.timingMargin,
                        jumpTimingBudget=plan.jumpTimingBudget,diveTimingBudget=plan.diveTimingBudget})
                    cancel();nextSolve=now
                    message="Aerial catch window changed · recalculating"
                    return
                end
            end
            if s.role=="WR" and not plan.airborneFinish
                and not (s.catchIntent and s.catchIntent.requireDive) then
                local uprightSnapshot=snapshot(s,root,h,actionNow)
                uprightSnapshot.canDive=false
                uprightSnapshot.allowLastResort=plan.risk~=nil
                local upright=solveActual(uprightSnapshot)
                if upright and not (plan.scoringCatch and plan.safety~="contested"
                    and upright.scoringCatch~=true) then
                    log("diveAvoided",{role=s.role,reason="Upright catch now reachable",
                        action=upright.kind,contactAt=upright.contactAt,position=xyz(root.Position)})
                    plan,lastSnapshot=nil,nil
                    atTarget,parkedPosition=false,nil
                    nextSolve=now
                    message="WR · staying upright for reachable catch"
                    return
                end
            end
            local dispatchAt=workspace:GetServerTimeNow()
            if cancelStaleAction(dispatchAt) then h.Jump=false;return end
            local diveSnapshot=snapshot(s,root,h,dispatchAt)
            if not Planner.canDiveFrom(diveSnapshot,root.Position) then
                log("diveAvoided",{role=s.role,reason="WR dive must start inside the end zone",
                    position=xyz(root.Position)})
                cancel();nextSolve=dispatchAt
                message="WR · staying upright outside the end zone"
                return
            end
            if divePermitted() and Moves.Upright()
                and dispatchAt-lastDive>=Config.Moves.Dive.Cooldown then
                -- The native move reads MoveDirection before falling back to facing.
                h:Move(plan.direction,false)
                local expectedDive=Planner.pose(lastSnapshot,plan,dispatchAt)
                log("diveAttempt",{role=s.role,position=xyz(root.Position),wrDiveGoalZ=diveSnapshot.wrDiveGoalZ,
                    expected=xyz(expectedDive.Position),velocity=xyz(root.AssemblyLinearVelocity),
                    diveIn=plan.diveAt-dispatchAt,dispatchAt=dispatchAt,frameAt=now,scheduledAt=plan.diveAt,
                    airborne=h.FloorMaterial==Enum.Material.Air})
                nativeDive()
                if h.PlatformStand then
                    dived, lastDive = true, dispatchAt
                    releaseSprint()
                    counters.dives=counters.dives+1
                    log("dive", {position=xyz(root.Position),role=s.role,wrDiveGoalZ=diveSnapshot.wrDiveGoalZ,delay=dispatchAt-plan.diveAt,
                        dispatchAt=dispatchAt,scheduledAt=plan.diveAt,
                        direction=xyz(plan.direction)})
                else
                    log("actionRejected",{action="dive",reason="native move declined",role=s.role,
                        upright=Moves.Upright(),permitted=divePermitted(),position=xyz(root.Position)})
                    cancel(); nextSolve=now+0.18
                    message="Native dive unavailable · recalculating"; return
                end
            else
                log("actionRejected",{action="dive",reason="move gate changed",role=s.role,
                    upright=Moves.Upright(),permitted=divePermitted(),position=xyz(root.Position)})
                cancel(); message="Dive window changed · recalculating"; return
            end
        end
        message=plan.reachable==false and (plan.airborneUnavailable
            and "WR · no airborne catch window · pursuing" or "SPRINT · pursuing beyond predicted reach") or string.format("%s%s · contact %.2fs",
            me:GetAttribute("SprintOn") and "SPRINT · " or "Earliest ",
            plan.kind,math.max(0,plan.contactAt-now))
        if s.role=="WR" and plan.reachable~=false then
            message=string.format("WR · %s · %.2fs",
                plan.risk and "last-chance catch" or
                    (plan.safety=="contested" and "early catch / contest risk"
                    or plan.airborneFinish=="jumpDive" and "timed jump + dive"
                    or plan.airborneFinish=="jump" and "timed airborne catch"
                    or plan.airborneFallbackReason and "reachable catch · no safe aerial window"
                    or "downfield catch"),
                math.max(0,plan.contactAt-now))
        elseif s.role=="DB" and plan.risk then
            message=string.format("DB · last-chance intercept · %.2fs",math.max(0,plan.contactAt-now))
        end
        if now-lastLogTime>=0.09 then
            lastLogTime=now
            local ball=Planner.ballAt(s.arc,now-s.launchAt)
            local opponents={}
            for _,other in ipairs(s.opponents or (s.opponent and {s.opponent} or {})) do
                local otherRoot=other:FindFirstChild("HumanoidRootPart")
                if otherRoot then
                    table.insert(opponents,{name=other.Name,position=xyz(otherRoot.Position),
                        velocity=xyz(otherRoot.AssemblyLinearVelocity),look=xyz(otherRoot.CFrame.LookVector)})
                end
            end
            log("sample",{position=xyz(root.Position),ball=xyz(ball),
                velocity=xyz(root.AssemblyLinearVelocity),up=xyz(root.CFrame.UpVector),
                moveDirection=xyz(h.MoveDirection),opponents=opponents,
                airborne=h.FloorMaterial==Enum.Material.Air,diving=h.PlatformStand,
                humanoidState=humanoidState(h),jumpHeld=h.Jump,
                motionReason=motion.reason,physicalAirborne=motion.physicalAirborne,
                action=plan.kind,role=s.role,reachable=plan.reachable,
                speed=h.WalkSpeed,sprint=me:GetAttribute("SprintOn"),
                stamina=me:GetAttribute("Stamina"),parked=atTarget,
                steering=xyz(steering)})
        end
    end
    if createTackle then
        tackleAssist=createTackle(Planner,{
            Config=Config,Field=Field,Moves=Moves,me=me,
            nativeTackle=nativeTackle,nativeGrabTarget=nativeGrabTarget,
            clippedDistance=clippedDistance,log=log,
            canDive=function(now)
                return divePermitted() and Moves.Upright()
                    and now-lastDive>=Config.Moves.Dive.Cooldown
            end,
            canJump=function(h,now)
                return now-lastJump>0.55 and h.FloorMaterial~=Enum.Material.Air
                    and (h.UseJumpPower and h.JumpPower>0 or not h.UseJumpPower and h.JumpHeight>0)
                    and h:GetStateEnabled(Enum.HumanoidStateType.Jumping) and Moves.Upright()
            end,
            hold=function(h,direction)
                ownInput();controlledHumanoid=h;h:Move(direction,false)
            end,
            release=release,
            jump=function(h,now,kind)
                h.Jump=true;h:ChangeState(Enum.HumanoidStateType.Jumping)
                lastJump=now;counters.jumps=counters.jumps+1
                log(kind or "tackleJump",{})
            end,
            dive=function(h,direction,now,kind)
                if not divePermitted() or not Moves.Upright()
                    or now-lastDive<Config.Moves.Dive.Cooldown then return false end
                ownInput();controlledHumanoid=h;h:Move(direction,false)
                nativeDive()
                local success=h.PlatformStand
                if success then
                    lastDive=now;counters.dives=counters.dives+1
                    releaseSprint()
                end
                log(kind or "tackleDive",{started=success,direction=xyz(direction)})
                return success
            end})
    end
    if createCarrierMoves then
        carrierAssist=createCarrierMoves({Config=Config,Field=Field,Moves=Moves,player=me,
            nativeJuke=namedUpvalue(Moves.SetPhase,"juke"),
            log=log,clippedDistance=clippedDistance})
    end
    local bindName="ChalkDB_Interception"
    RunService:BindToRenderStep(bindName,Enum.RenderPriority.Character.Value+1,function(dt)
        local ok,err=pcall(tick,math.clamp(dt,0.001,0.1))
        if not ok then
            lastError=tostring(err)
            auto=false
            cancel()
            message="Auto paused: "..lastError
            log("error",{error=lastError})
        end
    end)
    function controller.setEnabled(value)
        auto=value==true
        if not auto then
            if tackleAssist then tackleAssist.cancel() end
            catching=false;cancel()
        end
        message=auto and "Waiting for throw" or "Auto OFF"
    end
    function controller.releaseFullplay()
        -- Turning off full-play must not cancel an active catch or tackle.
        if not navigation then return false end
        release()
        message="Waiting for throw"
        return true
    end
    function controller.status()
        return {enabled=auto,nativeDive=nativeTackle~=nil,message=message,error=lastError,
            navigation=navigation,
            playerAvoidance=avoidanceStatus,
            carrierMoves=carrierAssist and carrierAssist.status() or nil,
            plan=plan and plan.kind or nil,contactAt=plan and plan.contactAt or nil,
            risk=plan and plan.risk or nil,
            airborneFinish=plan and plan.airborneFinish or nil,
            airborneRequired=plan and plan.airborneRequired or nil,
            counters=table.clone(counters),lastResult=lastResult}
    end
    function controller.target()
        return plan and plan.contactPosition
    end
    function controller.onMatch(data)
        if type(data)~="table" or not data.Phase then return end
        local holder=typeof(data.Carrier)=="Instance" and data.Carrier.Name or nil
        log("match",{phase=data.Phase,role=data.Role,result=data.Result,
            point=data.Point,carrier=holder,scorerIsYou=data.ScorerIsYou})
        if data.Phase=="Result" and data.Result=="Touchdown"
            and (data.Point=="Them" or data.Point=="Opp"
                or (data.Point==nil and data.ScorerIsYou==false)) then
            saveFailure("Opponent touchdown",data.Result,holder)
        end
    end
    function controller.onFx(data)
        if type(data)~="table" then return end
        if data.Type=="Throw" then
            local received=workspace:GetServerTimeNow()
            log("throwReceived",{launchAt=data.LaunchAt,
                deliveryDelay=type(data.LaunchAt)=="number" and received-data.LaunchAt or nil,
                pauseReason=lastPauseReason})
        end
        if data.Type=="BallStop" or data.Type=="BallResult" then
            wrDefenderDeadline=nil
            if data.Type=="BallResult" and throwKey then
                lastResult=data.Result
                if data.Result=="Intercepted" and throwRole=="DB" then counters.intercepted=counters.intercepted+1
                elseif data.Result=="Intercepted" then counters.lostToInterception=counters.lostToInterception+1
                elseif data.Result=="Incomplete" then counters.incomplete=counters.incomplete+1
                elseif data.Result=="Swatted" and throwRole=="DB" then counters.breakups=counters.breakups+1
                elseif data.Result=="Catch" and throwRole=="WR" then counters.catches=counters.catches+1
                elseif data.Result=="Catch" then counters.opponentCatches=counters.opponentCatches+1 end
                local catcher=typeof(data.Catcher)=="Instance" and data.Catcher.Name or nil
                local mine=data.Catcher==me.Character or data.Catcher==me
                local desired=(throwRole=="DB" and (data.Result=="Intercepted" or data.Result=="Swatted"))
                    or (throwRole=="WR" and data.Result=="Catch")
                if catcher and not mine then desired=false end
                local caughtByMe
                if catcher then caughtByMe=mine end
                log("result",{result=data.Result,role=throwRole,position=xyz(data.Pos),catcher=catcher,
                    caughtByMe=caughtByMe})
                if not desired then saveFailure("Catch/interception not secured",data.Result,catcher) end
                throwKey=nil
            end
            cancel()
        end
    end
    local touchedConnection=me:GetAttributeChangedSignal("BallTouched"):Connect(function()
        local s=ctx.snapshot()
        if alive and s.phase=="Live" and s.arc and s.launchAt
            and (s.role=="WR" or s.role=="DB") then
            -- Observe the native signal itself as well as contact geometry.
            -- A changed attribute is not proof that the server accepted it.
            local touchValue=me:GetAttribute("BallTouched")
            local touchClock=os.clock()
            local touchNumber=type(touchValue)=="number" and touchValue==touchValue
                and math.abs(touchValue)<math.huge and touchValue or nil
            claimedKey=s.launchAt
            claimObservedAt=workspace:GetServerTimeNow();claimTraceCount=0;claimTraceNext=claimObservedAt+.05
            local root,h=healthyCharacter()
            local waist,hands,radius
            local opponents={}
            for _,other in ipairs(s.opponents or (s.opponent and {s.opponent} or {})) do
                local otherRoot=other:FindFirstChild("HumanoidRootPart")
                local otherHumanoid=other:FindFirstChildOfClass("Humanoid")
                if otherRoot then
                    opponents[#opponents+1]={name=other.Name,position=xyz(otherRoot.Position),
                        velocity=xyz(otherRoot.AssemblyLinearVelocity),up=xyz(otherRoot.CFrame.UpVector),
                        humanoidState=humanoidState(otherHumanoid),
                        airborne=otherHumanoid and otherHumanoid.FloorMaterial==Enum.Material.Air,
                        diving=otherHumanoid and otherHumanoid.PlatformStand}
                end
            end
            if root then
                waist,hands,radius=Planner.capsule({config=Config},root.CFrame,
                    h.FloorMaterial==Enum.Material.Air)
            end
            log("localCatch",{role=s.role,claimOnly=true,authoritative=false,
                touchType=type(touchValue),touchValue=touchNumber,
                touchClock=touchClock,touchAge=touchNumber and touchClock-touchNumber,
                networkPing=networkPing(),
                opponents=opponents,
                position=root and xyz(root.Position),velocity=root and xyz(root.AssemblyLinearVelocity),
                up=root and xyz(root.CFrame.UpVector),waist=xyz(waist),hands=xyz(hands),radius=radius,
                humanoidState=humanoidState(h),airborne=h and h.FloorMaterial==Enum.Material.Air,
                jumpHeld=h and h.Jump,diving=h and h.PlatformStand,lastJumpAt=lastJump,
                ball=xyz(Planner.ballAt(s.arc,workspace:GetServerTimeNow()-s.launchAt))})
            cancel()
        end
    end)
    function controller.history() return table.clone(history) end
    function controller.unload()
        alive=false
        wrDefenderDeadline=nil
        trackedMotionRoot,trackedAirborne=nil,false
        if tackleAssist then tackleAssist.cancel() end
        if carrierAssist then carrierAssist.unload() end
        RunService:UnbindFromRenderStep(bindName)
        touchedConnection:Disconnect()
        cancel()
    end
    log("loaded",{version="3.1",nativeDive=nativeDive~=nil,nativeGrab=nativeGrabTarget~=nil})
    return controller
end

end)()
local AutoplayPolicy = (function()
-- Pure, clock-driven matchmaking policy. Only native Join/Leave commands leave it.
local Policy={}
local activePhases={Pick=true,PreSnap=true,Hike=true,Live=true,RAC=true,Run=true,Result=true}
local queueStates={Searching=true,Found=true,Idle=true,Error=true,Leaving=true}

function Policy.modes(config)
    local result,seen={},{}
    local queue=type(config.Queue)=="table" and config.Queue or {}
    local live=type(queue.Live)=="table" and queue.Live or {}
    local function add(key,label)
        if type(key)=="string" and not seen[key] then
            seen[key]=true
            result[#result+1]={key=key,label=label or key,available=live[key]==true}
        end
    end
    for _,key in ipairs(type(queue.Modes)=="table" and queue.Modes or {}) do add(key) end
    local ranked=type(config.Ranked)=="table" and config.Ranked.Modes or {}
    local keys={}
    for key in pairs(type(ranked)=="table" and ranked or {}) do
        if type(key)=="string" then keys[#keys+1]=key end
    end
    table.sort(keys)
    for _,key in ipairs(keys) do add(key,"Ranked "..tostring(ranked[key])) end
    return result
end

function Policy.new(modes,settings)
    settings=type(settings)=="table" and settings or {}
    local self={modes=modes,allowed={},labels={},enabled=false,selectedMode=nil,
        queueStatus="Unknown",owned=false,failures=0,retryAt=0,activeSeen=false,
        cancelWanted=false,foundNotified=false,message="Autoplay off"}
    for _,entry in ipairs(modes) do
        self.labels[entry.key]=entry.label
        if entry.available then self.allowed[entry.key]=true;self.selectedMode=self.selectedMode or entry.key end
    end
    if self.allowed[settings.selectedMode] then self.selectedMode=settings.selectedMode end
    -- A removed/unavailable saved selection must not silently start a
    -- different mode. The fallback is only for the disabled selector.
    self.enabled=settings.enabled==true and self.allowed[settings.selectedMode]==true
    if self.enabled then self.message="Waiting for lobby" end
    return setmetatable(self,{__index=Policy})
end

function Policy:selectMode(key)
    if not self.allowed[key] then return false,"This mode is not available" end
    if key~=self.selectedMode then
        self.selectedMode=key
        if self.owned and (self.queueStatus=="Searching" or self.pending=="Join") then
            self.cancelWanted=true
        end
    end
    return true
end
function Policy:setEnabled(value)
    if value==true and self.queueStatus=="Blocked" then return false end
    self.enabled=value==true and self.allowed[self.selectedMode]==true
    if self.enabled then
        self.failures=0
        self.message="Waiting for lobby"
    else
        if self.owned and (self.queueStatus=="Searching" or self.pending=="Join") then
            self.cancelWanted=true
        end
        self.message="Autoplay off"
    end
    return self.enabled
end
function Policy:fail(reason,now)
    self.failures=self.failures+1
    self.retryAt=now+math.min(30,5*2^(self.failures-1))
    self.message=reason or "Queue request failed"
    if self.failures>=3 then
        self.enabled=false
        self.message="Autoplay paused after three queue failures"
    end
end
function Policy:observeQueue(packet,now,bootstrap)
    if type(packet)~="table" or not queueStates[packet.Status] then return false end
    local status=packet.Status
    local previous,pending,owned=self.queueStatus,self.pending,self.owned
    if type(packet.Mode)=="string" then self.queuedMode=packet.Mode end
    if bootstrap then self.owned=false end
    self.queueStatus=status
    if status=="Searching" then
        if pending=="Leave" then
            -- A delayed/repeated search acknowledgement cannot undo an
            -- outstanding cancellation or cause another Leave each frame.
            self.queueStatus="Cancelling"
            self.message="Cancelling previous search"
            return false
        end
        self.pending=nil
        self.foundNotified=false
        if owned and not bootstrap then self.failures=0 end
        self.message=(self.owned and "Autoplay searching · " or "Searching · ")
            ..(self.labels[self.queuedMode] or self.queuedMode or "selected mode")
    elseif status=="Found" then
        self.pending=nil
        self.owned=false
        self.cancelWanted=false
        self.message="Game found"
        if not self.foundNotified then self.foundNotified=true;return true end
    elseif status=="Leaving" then
        self.pending=nil
        self.owned=false
        self.cancelWanted=false
        self.message="Returning to lobby"
    elseif status=="Idle" then
        self.pending=nil
        self.owned=false
        self.foundNotified=false
        self.cancelWanted=false
        -- A user cancelling an accepted queue is respected instead of being
        -- immediately put back in it. Our own Leave has a pending marker.
        if owned and previous=="Searching" and pending~="Leave" then
            self.enabled=false
            self.message="Queue stopped · autoplay paused"
        else self.message=self.enabled and "Ready to find next game" or "Autoplay off" end
        self.retryAt=math.max(self.retryAt,now+1)
    else
        if pending=="Leave" then
            self.pending=nil;self.enabled=false;self.cancelWanted=false
            self.queueStatus="Blocked"
            self.message="Autoplay paused · queue cancellation failed"
            return false
        end
        self.pending=nil
        self.owned=false
        self.cancelWanted=false
        self.foundNotified=false
        if owned and not bootstrap then self:fail(packet.Message or "Queue request failed",now)
        else self.retryAt=math.max(self.retryAt,now+5);self.message=packet.Message or "Queue unavailable" end
    end
    return false
end
function Policy:bootstrap(status,mode,now)
    if self.queueStatus~="Unknown" or self.pending or self.owned then return false end
    return self:observeQueue({Status=status,Mode=mode},now,true)
end

function Policy:step(snapshot,now)
    local s=type(snapshot)=="table" and snapshot or {}
    local phase=s.phase
    if phase~="Lobby" then
        self.lobbySince=nil
        if activePhases[phase] then
            self.activeSeen=true
            self.owned=false;self.pending=nil;self.cancelWanted=false
            self.queueStatus="Match"
            self.message=self.enabled and "Next game: "..(self.labels[self.selectedMode] or "select a mode") or "Autoplay off"
        end
        self.lastPhase=phase
        return nil
    end
    if self.activeSeen then
        self.activeSeen=false
        self.queueStatus=s.matchServer and "Leaving" or "Unknown"
        self.owned=false;self.pending=nil;self.cancelWanted=false
        self.foundNotified=false
    end
    self.lastPhase=phase
    self.lobbySince=self.lobbySince or now
    if s.testing or s.alive==false or s.matchServer or s.dataLoaded~=true then return nil end
    if self.pending=="Join" and self.cancelWanted then self.pending=nil end
    if self.pending then
        if now-self.requestAt<10 then return nil end
        if self.pending=="Leave" then
            self.pending=nil;self.cancelWanted=false;self.enabled=false;self.queueStatus="Blocked"
            self.message="Autoplay paused · queue cancellation was not confirmed"
            return nil
        end
        self:fail("Queue did not respond · cancelling before retry",now)
        self.pending=nil;self.cancelWanted=true
    end
    if self.cancelWanted and self.owned and self.queueStatus~="Found" and self.queueStatus~="Leaving" then
        self.pending="Leave";self.requestAt=now;self.queueStatus="Cancelling"
        self.message="Cancelling previous search"
        return {command="Leave"}
    end
    if not self.enabled then return nil end
    if not self.allowed[self.selectedMode] then self.enabled=false;self.message="Selected mode is unavailable";return nil end
    if now-self.lobbySince<1.25 or now<self.retryAt then return nil end
    if self.queueStatus~="Idle" and self.queueStatus~="Error" then return nil end
    self.pending="Join";self.requestAt=now;self.owned=true;self.queuedMode=self.selectedMode
    self.queueStatus="Requesting";self.message="Finding "..self.labels[self.selectedMode]
    return {command="Join",mode=self.selectedMode}
end
function Policy:status()
    return {enabled=self.enabled,selectedMode=self.selectedMode,label=self.labels[self.selectedMode],
        queueStatus=self.queueStatus,queuedMode=self.queuedMode,owned=self.owned,
        pending=self.pending,requestAt=self.requestAt,retryAt=self.retryAt,failures=self.failures,
        cancelWanted=self.cancelWanted,activeSeen=self.activeSeen,lastPhase=self.lastPhase,
        foundNotified=self.foundNotified,message=self.message}
end
function Policy:restore(runtime,now)
    if type(runtime)~="table" then return end
    local accepted={Unknown=true,Idle=true,Error=true,Requesting=true,Searching=true,Found=true,
        Leaving=true,Match=true,Cancelling=true,Blocked=true}
    if not accepted[runtime.queueStatus] then return end
    self.queueStatus=runtime.queueStatus
    self.queuedMode=type(runtime.queuedMode)=="string" and runtime.queuedMode or nil
    self.owned=runtime.owned==true
    self.pending=(runtime.pending=="Join" or runtime.pending=="Leave") and runtime.pending or nil
    self.requestAt=type(runtime.requestAt)=="number" and runtime.requestAt or (self.pending and now or nil)
    self.retryAt=type(runtime.retryAt)=="number" and runtime.retryAt or now
    self.failures=math.max(0,math.min(3,tonumber(runtime.failures) or 0))
    self.cancelWanted=runtime.cancelWanted==true
    self.activeSeen=runtime.activeSeen==true
    self.lastPhase=runtime.lastPhase
    self.foundNotified=runtime.foundNotified==true
    self.message=type(runtime.message)=="string" and runtime.message or self.message
end
return Policy

end)()
local createAutoplay = (function()
-- Matchmaking uses the same Join/Leave remote as the game's Play menu.
return function(ctx,Policy)
    local Players=game:GetService("Players")
    local RS=game:GetService("ReplicatedStorage")
    local RunService=game:GetService("RunService")
    local Http=game:GetService("HttpService")
    local player=Players.LocalPlayer
    local Config=require(RS.Shared.Config)
    local queue=RS:WaitForChild("Remotes"):WaitForChild("Queue")
    local SettingsFile="ciu_deterministic_autoplay_v1.json"
    local alive=true
    local connections={}
    local settings={}
    if type(readfile)=="function" then
        local good,value=pcall(function() return Http:JSONDecode(readfile(SettingsFile)) end)
        if good and type(value)=="table" then settings=value end
    end
    local modes=Policy.modes(Config)
    local previous=ctx.previousState
    local sameJob=type(previous)=="table" and previous.jobId==game.JobId
    local state=Policy.new(modes,sameJob and previous or settings)
    local managed=ctx.preferencesManaged==true
    local preferredEnabled=state.enabled
    local ready=not managed
    if sameJob then
        state:restore(previous,workspace:GetServerTimeNow())
    end
    if ctx.startDisabled==true then
        -- Keep the selected mode, but never inherit input/queue ownership.
        state.enabled=false
        if not (managed and sameJob) then
            state.owned=false
            state.pending=nil
            state.cancelWanted=false
        end
        state.message="Autoplay off"
    end
    local lastMatchFoundId,lastMatchFoundAt,lastMatchFoundMode
    if sameJob then
        lastMatchFoundId,lastMatchFoundAt,lastMatchFoundMode=
            previous.lastMatchFoundId,previous.lastMatchFoundAt,previous.lastMatchFoundMode
    end
    local saveError,lastSaved
    local function save()
        local savedEnabled=state.enabled
        if managed then savedEnabled=preferredEnabled end
        local encoded=Http:JSONEncode({enabled=savedEnabled,selectedMode=state.selectedMode})
        if encoded==lastSaved then return end
        if type(writefile)~="function" then saveError="Settings cannot be saved on this executor";return end
        local ok,err=pcall(writefile,SettingsFile,encoded)
        if ok then lastSaved=encoded;saveError=nil else saveError=tostring(err) end
    end
    local function found(mode)
        lastMatchFoundId=Http:GenerateGUID(false)
        lastMatchFoundAt=workspace:GetServerTimeNow()
        lastMatchFoundMode=mode or state.queuedMode or state.selectedMode
        if type(writefile)=="function" then
            local ok,err=pcall(function()
                writefile("ciu_match_alert.json",Http:JSONEncode({id=lastMatchFoundId,time=lastMatchFoundAt,
                    gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,mode=lastMatchFoundMode}))
            end)
            if not ok then saveError="Match alert could not be saved: "..tostring(err) end
        end
    end
    connections[#connections+1]=queue.OnClientEvent:Connect(function(packet)
        if not alive then return end
        if type(ctx.onQueue)=="function" then pcall(ctx.onQueue,packet,state:status()) end
        if state:observeQueue(packet,workspace:GetServerTimeNow()) then found(packet.Mode) end
        save()
        if type(ctx.onStateChanged)=="function" then pcall(ctx.onStateChanged) end
    end)
    local function visible(object)
        local node=object
        while node and node~=player.PlayerGui do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node=node.Parent
        end
        return node==player.PlayerGui
    end
    local function bootstrap()
        local playerGui=player:FindFirstChild("PlayerGui")
        local gui=playerGui and playerGui:FindFirstChild("PlayMenu")
        local play=gui and gui:FindFirstChild("Play",true)
        if not play or not visible(play) then return end
        local idle,searching,foundState,leaving=false,false,false,false
        for _,object in ipairs(play:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton")) and visible(object) then
                local value=string.upper(object.Text)
                idle=idle or value=="PLAY"
                searching=searching or string.find(value,"SEARCHING",1,true)==1
                foundState=foundState or value=="MATCH FOUND!" or value=="GET READY"
                leaving=leaving or value=="GG!" or string.find(value,"HEADING BACK",1,true)==1
            end
        end
        local status=leaving and "Leaving" or foundState and "Found" or searching and "Searching" or idle and "Idle"
        if status and state:bootstrap(status,nil,workspace:GetServerTimeNow())
            and workspace:GetAttribute("MatchServer")~=true then
            -- GET READY after teleport describes the same game that already
            -- emitted Found in the lobby; its durable alert survives the hop.
            found()
        end
    end
    local function tick()
        if not ready then return end
        local current=ctx.snapshot()
        current.matchServer=workspace:GetAttribute("MatchServer")==true
        current.dataLoaded=player:GetAttribute("DataLoaded")==true
        local now=workspace:GetServerTimeNow()
        -- Observe an existing native queue before making any request. This also
        -- covers reloads where its Searching/Found event already happened.
        if state.queueStatus=="Unknown" then bootstrap() end
        local action=state:step(current,now)
        if action then
            local ok,err=pcall(function()
                if action.command=="Join" then queue:FireServer("Join",action.mode)
                else queue:FireServer("Leave") end
            end)
            if not ok then state:observeQueue({Status="Error",Message=tostring(err)},now) end
        end
        save()
        if type(ctx.onStateChanged)=="function" then pcall(ctx.onStateChanged) end
    end
    local accumulator=0
    connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
        if not alive then return end
        accumulator=accumulator+dt
        if accumulator<0.25 then return end
        accumulator=0
        local ok,err=pcall(tick)
        if not ok then
            state.enabled=false;state.message="Autoplay paused: "..tostring(err);save()
            if type(ctx.onStateChanged)=="function" then pcall(ctx.onStateChanged) end
        end
    end)
    local api={}
    function api.modes()
        local result={}
        for _,entry in ipairs(modes) do result[#result+1]={key=entry.key,label=entry.label,available=entry.available} end
        return result
    end
    function api.selectMode(key)
        local ok,reason=state:selectMode(key);if ok then save() end;return ok,reason
    end
    function api.setEnabled(value,transient)
        ready=true
        local result=state:setEnabled(value)
        if managed and transient~=true then preferredEnabled=value==true end
        -- OFF must cancel an owned lobby search before an F8 unload can
        -- disconnect the periodic tick. Active matches still fail the gate.
        if not result then pcall(tick) end
        save()
        return result
    end
    function api.status()
        local result=state:status()
        result.jobId=game.JobId
        result.lastMatchFoundId,result.lastMatchFoundAt,result.lastMatchFoundMode=
            lastMatchFoundId,lastMatchFoundAt,lastMatchFoundMode
        result.saveError=saveError
        result.preferredEnabled=state.enabled
        if managed then result.preferredEnabled=preferredEnabled end
        return result
    end
    function api.unload()
        if not alive then return end
        alive=false
        for _,connection in ipairs(connections) do connection:Disconnect() end
        -- Reloads preserve queue ownership through api.status; do not cancel
        -- a legitimate search simply because the assist is being updated.
    end
    save()
    return api
end

end)()
local createWRRepeat = (function()
-- Walk back onto a local field's WR pad after the server returns us to Lobby.
-- Only ordinary Humanoid movement is used; match controls retain their priority.
return function(ctx,services)
    services=services or {}
    local world=services.world or workspace
    local player=services.player or game:GetService("Players").LocalPlayer
    local RunService=services.runService or game:GetService("RunService")
    local UIS=services.uis or game:GetService("UserInputService")
    local GuiService=services.guiService or game:GetService("GuiService")
    local jobId=services.jobId or game.JobId
    local function fieldNumber(value)
        return type(value)=="number" and value==value and value>=1 and value<=10000
            and value%1==0 and value or nil
    end
    local previous=ctx.previousState
    local sameJob=type(previous)=="table" and previous.jobId==jobId
    local enabled=sameJob and previous.enabled==true or false
    local field
    local alive=true
    local pad,character,controlledHumanoid,phase
    local lobbySince,nextFindAt,unavailableSince,farSince=nil,0,nil,nil
    local walkSince,progressAt,bestDistance,distance
    local moving,holding=false,false
    local errorMessage,message=nil,enabled and "Win farm · waiting for lobby" or "Win farm off"
    local completedSeen=false
    local counters={walks=0,arrivals=0,matchStarts=0,completedMatches=0,pauses=0}
    local api={}
    local function now() return world:GetServerTimeNow() end
    local function releaseMotion()
        if controlledHumanoid and controlledHumanoid.Parent then
            controlledHumanoid:Move(Vector3.zero,false)
        end
        controlledHumanoid=nil
        moving=false
        walkSince,progressAt,bestDistance=nil,nil,nil
    end
    local function resetLobby()
        releaseMotion()
        holding=false
        lobbySince,unavailableSince,farSince=nil,nil,nil
        field,pad,distance,nextFindAt=nil,nil,nil,0
    end
    local function pause(reason)
        enabled=false
        errorMessage=reason
        message="Win farm paused · "..reason
        counters.pauses=counters.pauses+1
        resetLobby()
    end
    local function changePhase(value,time)
        if value==phase then return end
        local before=phase
        phase=value
        resetLobby()
        if phase=="Lobby" then lobbySince=time
        elseif (phase=="PreSnap" or phase=="Pick") and before=="Lobby" then
            completedSeen=false
            if enabled then counters.matchStarts=counters.matchStarts+1 end
        end
    end
    local function validPad(candidate)
        if not candidate or not candidate.Parent or not candidate:IsA("BasePart") then return false end
        local lobby=world:FindFirstChild("Lobby")
        local model=lobby and field and lobby:FindFirstChild("Field"..field)
        return model~=nil and candidate.Parent==model and candidate.Name=="WRPad"
    end
    local function horizontal(from,to)
        local delta=to-from
        return Vector3.new(delta.X,0,delta.Z)
    end
    local function findPad(root,time)
        if time<nextFindAt then return validPad(pad) and pad or nil end
        nextFindAt=time+0.5
        local lobby=world:FindFirstChild("Lobby")
        if not lobby then return nil end
        local nearest,bestField,bestPad=math.huge,nil,nil
        for _,model in ipairs(lobby:GetChildren()) do
            local number=fieldNumber(tonumber(string.match(model.Name,"^Field(%d+)$")))
            local candidate=number and model:FindFirstChild("WRPad")
            if candidate and candidate:IsA("BasePart")
                and math.abs(root.Position.Y-candidate.Position.Y)<=12 then
                local span=horizontal(root.Position,candidate.Position).Magnitude
                if span<nearest-0.000001 or (math.abs(span-nearest)<=0.000001
                    and (not bestField or number<bestField)) then
                    bestField,bestPad,nearest=number,candidate,span
                end
            end
        end
        if bestPad~=pad then
            releaseMotion()
            holding=false
            distance,unavailableSince,farSince=nil,nil,nil
        end
        field,pad=bestField,bestPad
        return pad
    end
    local function queueBusy()
        local state=ctx.autoplay and ctx.autoplay()
        if type(state)~="table" then return false end
        local q=state.queueStatus
        return state.enabled==true or state.pending~=nil or q=="Searching" or q=="Requesting"
            or q=="Found" or q=="Cancelling" or q=="Leaving"
    end
    local function tick(dt)
        if not alive then return end
        local s=ctx.snapshot()
        local time=now()
        changePhase(s.phase,time)
        if not enabled then releaseMotion();return end
        if s.alive==false then releaseMotion();return end
        if world:GetAttribute("MatchServer")==true then pause("Local field pads only");return end
        if phase~="Lobby" then
            releaseMotion()
            message="Win farm · waiting for match to finish"
            return
        end
        if not s.enabled or s.testing or UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then
            resetLobby()
            message=s.testing and "Win farm · paused for test"
                or not s.enabled and "Win farm · assist is off" or "Win farm · waiting for controls"
            return
        end
        if queueBusy() then
            resetLobby()
            message="Win farm · waiting for matchmaking to stop"
            return
        end
        local ch=player.Character
        if character and ch~=character then pause("Character changed · turn on again");character=ch;return end
        local root=ch and ch:FindFirstChild("HumanoidRootPart")
        local h=ch and ch:FindFirstChildOfClass("Humanoid")
        if not root or not h or h.Health<=0 or root.Anchored or h.Sit or h.PlatformStand then
            resetLobby()
            message="Win farm · waiting for character"
            return
        end
        character=ch
        lobbySince=lobbySince or time
        if time-lobbySince<0.35 then
            releaseMotion();message="Win farm · returning to lobby";return
        end
        local target=findPad(root,time)
        if not target then
            releaseMotion()
            unavailableSince=unavailableSince or time
            message=field and ("Win farm · waiting for Field "..field.." WR pad")
                or "Win farm · move near a WR pad"
            if time-unavailableSince>12 then pause("No nearby WR pad · turn on beside your field") end
            return
        end
        unavailableSince=nil
        local direction=horizontal(root.Position,target.Position)
        distance=direction.Magnitude
        if distance>40 or math.abs(root.Position.Y-target.Position.Y)>12 then
            releaseMotion();holding=false
            farSince=farSince or time
            message="Win farm · waiting beside Field "..field
            if time-farSince>12 then pause("Too far from Field "..field.." WR pad") end
            return
        end
        farSince=nil
        if distance<=1.2 or (holding and distance<=2.5) then
            if not holding then counters.arrivals=counters.arrivals+1 end
            holding=true
            releaseMotion()
            message="Win farm · on Field "..field.." WR pad"
            return
        end
        holding=false
        if not moving then
            counters.walks=counters.walks+1
            walkSince,progressAt,bestDistance=time,time,distance
        end
        if distance<bestDistance-0.25 then bestDistance,progressAt=distance,time end
        if time-progressAt>2.5 then pause("Path blocked · turn on again when clear");return end
        if time-walkSince>10 then pause("WR pad walk timed out · turn on again");return end
        moving=true
        controlledHumanoid=h
        -- Reduce input near the pad when background rendering slows down.
        -- This never raises the game's WalkSpeed or forces the character position.
        local horizon=math.max(tonumber(dt) or 0,0.06)
        local amount=math.min(1,math.max(0.05,(distance-0.6)/(math.max(1,h.WalkSpeed)*horizon)))
        h:Move(direction.Unit*amount,false)
        message="Win farm · walking to Field "..field.." WR"
    end
    function api.release()
        resetLobby()
    end
    function api.setEnabled(value)
        if not alive then return false,"Win farm is unloaded" end
        resetLobby()
        errorMessage=nil
        enabled=value==true
        if not enabled then message="Win farm off";return false end
        if world:GetAttribute("MatchServer")==true then pause("Local field pads only");return false,errorMessage end
        character=player.Character
        nextFindAt=0
        local ok,reason=pcall(function() if ctx.disableAutoplay then ctx.disableAutoplay() end end)
        if not ok then pause("Could not stop matchmaking: "..tostring(reason));return false,errorMessage end
        message="Win farm · waiting for lobby"
        return true
    end
    function api.onMatch(data)
        if not alive or type(data)~="table" then return end
        if ctx.snapshot().testing then resetLobby();return end
        -- Match packets describe the field that just played, not the WR pad
        -- nearest to the character after the return teleport.
        if data.MatchOver==true and not completedSeen then
            completedSeen=true
            if enabled then counters.completedMatches=counters.completedMatches+1 end
        end
        if type(data.Phase)=="string" then changePhase(data.Phase,now()) end
    end
    function api.status()
        return {enabled=enabled,field=field,selection="nearest",jobId=jobId,phase=phase,moving=moving,
            onPad=holding,distance=distance,message=message,error=errorMessage,
            counters={walks=counters.walks,arrivals=counters.arrivals,matchStarts=counters.matchStarts,
                completedMatches=counters.completedMatches,pauses=counters.pauses}}
    end
    local bindName="ChalkDB_WRRepeat"
    function api.unload()
        if not alive then return end
        alive,enabled=false,false
        resetLobby()
        RunService:UnbindFromRenderStep(bindName)
    end
    RunService:BindToRenderStep(bindName,Enum.RenderPriority.Character.Value+2,function(dt)
        local ok,reason=pcall(tick,dt)
        if not ok then pause(tostring(reason)) end
    end)
    return api
end

end)()
local createIdleGuard = (function()
-- Owns one idle listener and one delayed keep-alive, independently of gameplay.
-- Successful input delivery is recorded; it is not proof of a server timer reset.
return function(services)
    services=services or {}
    local player=services.player or game:GetService("Players").LocalPlayer
    local now=services.now or os.clock
    local delay=services.delay or task.delay
    local cancel=services.cancel or task.cancel
    local keepAlive=services.keepAlive or function()
        local camera=workspace.CurrentCamera
        assert(camera,"Camera unavailable for idle keep-alive")
        local virtualUser=game:GetService("VirtualUser")
        virtualUser:CaptureController()
        -- Atomic click: no movement keys, delayed release, or held mouse button.
        virtualUser:ClickButton2(Vector2.zero,camera.CFrame)
    end
    local alive=true
    local connection,timer
    local lastAttempt,lastSuccess,lastReason,lastError,idleSeconds
    local attempts,successes,idleEvents=0,0,0
    local interval,cooldown=60,45
    local api={}

    local function pulse(reason)
        if not alive then return false,"unloaded" end
        local time=now()
        if lastAttempt and time-lastAttempt<cooldown then return false,"cooldown" end
        lastAttempt,lastReason=time,reason
        attempts=attempts+1
        local ok,err=pcall(keepAlive)
        if ok then
            successes=successes+1
            lastSuccess,lastError=time,nil
        else
            lastError=tostring(err)
        end
        return ok,lastError
    end
    local function schedule()
        timer=delay(interval,function()
            timer=nil
            if not alive then return end
            pulse("interval")
            if alive then schedule() end
        end)
    end
    function api.status()
        return {enabled=alive,interval=interval,listener=connection~=nil,
            attempts=attempts,successes=successes,idleEvents=idleEvents,
            lastAttempt=lastAttempt,lastSuccess=lastSuccess,lastReason=lastReason,
            idleSeconds=idleSeconds,error=lastError}
    end
    function api.unload()
        if not alive then return end
        alive=false
        if connection then connection:Disconnect();connection=nil end
        if timer then pcall(cancel,timer);timer=nil end
    end
    connection=player.Idled:Connect(function(seconds)
        if not alive then return end
        idleEvents=idleEvents+1
        idleSeconds=tonumber(seconds)
        pulse("idle")
    end)
    pulse("startup")
    schedule()
    return api
end

end)()
local FullplayPolicy = (function()
-- Fixed geometry/stamina rules. Identical state and session history produce identical choices.
-- Pure 1v1 decisions. Every opponent forecast uses observed position/velocity;
-- scores are heuristics, never claims about an opponent's hidden selected route.
local Policy={}
local UNDERNEATH_MIN_YARDS,UNDERNEATH_BUFFER_YARDS=8,4
function Policy.underneathTriggerYards()
    return UNDERNEATH_MIN_YARDS+UNDERNEATH_BUFFER_YARDS
end
local FLAT=Vector3.new(1,0,1)
local INF=math.huge
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<INF end
local function vec(v) return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
local function flatDistance(a,b) return ((a-b)*FLAT).Magnitude end
local function offsetOf(input) return vec(input.offset) and input.offset or Vector3.zero end
local function boundedVelocity(v,maxSpeed)
    if not vec(v) then return Vector3.zero end
    v=v*FLAT
    return v.Magnitude>maxSpeed and v.Unit*maxSpeed or v
end
local function projectedOpponent(input,Config,seconds)
    if not vec(input.opponentPosition) then return nil end
    return input.opponentPosition+boundedVelocity(input.opponentVelocity,Config.SprintSpeed)*math.min(seconds,.25)
end
local function worldPoint(p,offset,y) return Vector3.new(p.X+offset.X,y,p.Y+offset.Z) end
-- Live-start samples can be lower than the setup HUD. This empirical setup
-- allowance is conservative planning, not an asserted hidden server cost.
-- Current/observed lower stamina always wins; refill never raises this cap.
function Policy.setupStaminaBudget(current,Config,observedStart)
    local maximum=finite(Config.Stamina) and math.max(0,Config.Stamina) or 0
    local budget=math.min(finite(current) and math.max(0,current) or 0,maximum*.75)
    if finite(observedStart) and observedStart>=0 then budget=math.min(budget,observedStart) end
    return budget
end
local function stemRegeneration(stamina,openingCost,rest,Config)
    local maximum=finite(Config.Stamina) and math.max(0,Config.Stamina) or 0
    local rate=finite(Config.StaminaRegen) and math.max(0,Config.StaminaRegen) or 0
    local delay=finite(Config.RegenDelay) and math.max(0,Config.RegenDelay)+.2 or INF
    local capacity=math.max(0,maximum-stamina)+math.max(0,openingCost)
    return math.min(capacity,math.max(0,rest-delay)*rate)
end
local function validField(Field)
    return type(Field)=="table" and finite(Field.MinX) and finite(Field.MaxX)
        and finite(Field.BackZ) and finite(Field.EndZ) and finite(Field.GoalZ)
        and finite(Field.LOSZ) and finite(Field.YD) and Field.YD>0
        and Field.MinX<Field.MaxX and Field.BackZ<Field.EndZ
end
local function worldBounds(Field,offset,margin)
    local minX,maxX=Field.MinX+offset.X+margin,Field.MaxX+offset.X-margin
    local minZ,maxZ=Field.BackZ+offset.Z+margin,Field.EndZ+offset.Z-margin
    return minX,maxX,minZ,maxZ
end
local function clampWorld(point,Field,offset,margin,y)
    local minX,maxX,minZ,maxZ=worldBounds(Field,offset,margin)
    return Vector3.new(clamp(point.X,minX,maxX),y,clamp(point.Z,minZ,maxZ))
end
local function travelTime(distance,Config,stamina)
    local run=math.max(1,Config.RunSpeed)
    local sprint=math.max(run,Config.SprintSpeed)
    local seconds=math.max(0,stamina)/(math.max(.01,Config.SprintDrain))
    local sprintDistance=sprint*seconds
    return math.min(distance,sprintDistance)/sprint+math.max(0,distance-sprintDistance)/run
end
local function uprightFloaterWindow(plan,los,receiverDistance,Config,Field,stamina)
    if plan.Pass~="Floater" then return nil end
    local height=3+(Config.HandUpOffset or 3.5)+(Config.JumpHeight or 6)
        +(Config.CatchRadius or 3.75)-.4
    local low,high=.5,1
    for _=1,24 do
        local u=(low+high)*.5
        local y=Config.ReleaseHeight+(Config.CatchHeight-Config.ReleaseHeight)*u+4*plan.Apex*u*(1-u)
        if y>height then low=u else high=u end
    end
    local origin=Vector2.new((Field.MinX+Field.MaxX)*.5,los-Config.QBBackYards*Field.YD)
    local point=origin:Lerp(plan.Target,high)
    -- Approximate distance already covered along the submitted route. The
    -- final ball-to-target segment is not distance the receiver must still run.
    local distance=math.max(0,receiverDistance-(plan.Target-point).Magnitude)
    local at=plan.Launch+plan.Flight*high
    local remainingStamina=math.max(0,stamina-math.min(distance/Config.SprintSpeed,
        stamina/math.max(.01,Config.SprintDrain))*Config.SprintDrain)
    -- Eligibility uses the entire native path plus lead, not the shorter
    -- distance estimate used only for the remaining-stamina diagnostic.
    return {point=point,at=at,reachable=travelTime(receiverDistance,Config,stamina)<=at+.05,
        remaining=math.max(0,Field.GoalZ-point.Y),stamina=remainingStamina}
end
local function routeKeys(pass,shape,depth,side)
    local family=pass..":"..shape..":"..tostring(math.floor(depth+.5))
    return family,family..":"..tostring(side)
end
local function adaptation(input,pass,shape,depth,side,arrival)
    local history=type(input.recentRoutes)=="table" and input.recentRoutes or {}
    local family,signature=routeKeys(pass,shape,depth,side)
    local penalty,failures=0,0
    -- Only the latest outcome for a family applies: a later successful catch
    -- clears an earlier failure of that family. Mirroring never clears it.
    local seen={}
    for i=#history,math.max(1,#history-5),-1 do
        local old=history[i]
        if type(old)=="table" and (old.pass=="Bullet" or old.pass=="Floater")
            and type(old.shape)=="string" and finite(old.depth) then
            local oldFamily=routeKeys(old.pass,old.shape,old.depth,old.side or 1)
            if not seen[oldFamily] then
                seen[oldFamily]=true
                local weight=.85^(#history-i)
                if old.success==false then
                    failures=failures+1
                    if oldFamily==family then penalty=penalty+36*weight end
                    if old.signature==signature then penalty=penalty+5*weight end
                    -- A nearby defender beat the old long descending window.
                    -- Prefer trying a different flight/shape, rather than the
                    -- identical long floater on the opposite sideline.
                    if old.pass=="Floater" and old.depth>=16
                        and pass=="Floater" and arrival>=4 then
                        penalty=penalty+8*weight
                    end
                elseif old.success==true and oldFamily==family then
                    penalty=penalty-2*weight
                end
            end
        end
    end
    return penalty,failures,family,signature
end
local function repetition(input,candidate)
    local history=type(input.recentSelections)=="table" and input.recentSelections
        or type(input.recentRoutes)=="table" and input.recentRoutes or {}
    local penalty,straightRecent=0,0
    for i=#history,math.max(1,#history-5),-1 do
        local old=history[i]
        if type(old)=="table" and (old.pass=="Bullet" or old.pass=="Floater")
            and type(old.shape)=="string" and finite(old.depth) then
            local family,signature=routeKeys(old.pass,old.shape,old.depth,old.side or 1)
            local weight=.65^(#history-i)
            if old.cutCount==0 or old.cutCount==nil and (old.shape=="go" or old.shape=="slant") then
                straightRecent=straightRecent+weight
            end
            penalty=penalty+weight*((family==candidate.family and 2.6 or 0)
                +(signature==candidate.signature and 1.4 or 0)
                +(math.abs(old.depth-candidate.depth)<1 and 1.5 or 0)
                +(old.shape==candidate.shape and .6 or 0)
                +(old.pass==candidate.payload.Pass and .25 or 0)
                +(old.side==candidate.side and .3 or 0))
        end
    end
    -- A small, reproducible tie-break varies equivalent choices. Selection is
    -- still limited to reachable routes near the best observed quality below.
    local sequence=finite(input.selectionIndex) and math.max(0,math.floor(input.selectionIndex)) or #history
    local hash=sequence*37
    for i=1,#candidate.signature do hash=(hash*17+string.byte(candidate.signature,i))%101 end
    local cutBonus=(candidate.cutCount or 0)>0 and 1.25+math.min(1.5,straightRecent) or 0
    return math.min(8.5,penalty),#history>0 and hash/100*.35 or 0,cutBonus
end
local function lateBendTrigger(input)
    local history=type(input.recentRoutes)=="table" and input.recentRoutes or {}
    local failures={}
    for i=#history,math.max(1,#history-5),-1 do
        local old=history[i]
        if type(old)=="table" then
            if old.shape=="late_bend" or old.experimentalAttempt=="late-bend" then break end
            local straight=old.pass=="Floater" and (old.cutCount==0
                or old.cutCount==nil and (old.shape=="go" or old.shape=="slant"))
            if straight and old.success==true then break end
            if straight and old.success==false
                and (old.result=="Swatted" or old.result=="Intercepted") then
                failures[#failures+1]=tostring(old.roundKey or old.time or i)..":"
                    ..tostring(old.signature or old.family or old.shape)..":"..old.result
                if #failures==2 then break end
            end
        end
    end
    if #failures<2 then return nil end
    local token=failures[2].."|"..failures[1]
    local function consumedFailure(previous)
        if type(previous)~="string" then return false end
        local marked="|"..previous.."|"
        return marked:find("|"..failures[1].."|",1,true)
            or marked:find("|"..failures[2].."|",1,true)
    end
    -- Missing result packets must not recycle one of the two failures that
    -- already bought a trial. Both qualifying failures must be fresh.
    if consumedFailure(input.lastLateBendTrialTrigger) then return nil end
    for _,old in ipairs(type(input.recentSelections)=="table" and input.recentSelections or {}) do
        if consumedFailure(old.trialTrigger) then return nil end
    end
    return token
end

local function sidelineDiveWitness(plan,launchPoint,outgoing,los,Config,Field)
    -- A continuous final run can overshoot a sideline during a full native
    -- dive even when the simple distance budget passes. Require one ordinary
    -- grounded-dive witness on the same coarse timing grid used by the live
    -- planner. This only establishes own geometry, not a defender-free catch.
    local dive=Config.Moves.Dive
    local reaction,age,step=.035,.42,.035
    if (dive.Time or .35)>.408 then return nil end
    local origin=Vector3.new((Field.MinX+Field.MaxX)*.5,Config.ReleaseHeight,
        los-Config.QBBackYards*Field.YD)
    local target=Vector3.new(plan.Target.X,Config.CatchHeight,plan.Target.Y)
    local position=Vector3.new(launchPoint.X,3,launchPoint.Y)
    local velocity=Vector3.new(outgoing.X,0,outgoing.Y)*Config.SprintSpeed
    local upY,upForward=math.cos(math.rad(80)),math.sin(math.rad(80))
    local radius,reach=Config.DiveCatchRadius or 2.5,Config.DiveReach or 2.4
    local function ballAt(t)
        local u=t/plan.Flight
        return origin:Lerp(target,u)+Vector3.new(0,4*plan.Apex*u*(1-u),0)
    end
    local function segmentDistance(point,a,b)
        local ab=b-a
        return (point-a-ab*clamp((point-a):Dot(ab)/math.max(1e-8,ab:Dot(ab)),0,1)).Magnitude
    end
    for t=.065,plan.Flight+.06,step do
        if t>=plan.Flight-.1 then
            local ball=ballAt(t)
            local flat=(ball-position)*FLAT
            if flat.Magnitude>1e-5 then
                local direction=flat.Unit
                local root=position+velocity*reaction+direction*(Config.SprintSpeed
                    *math.max(0,t-age-reaction)+dive.Yards*Field.YD)
                root=Vector3.new(root.X,.6,root.Z)
                local up=Vector3.new(direction.X*upForward,upY,direction.Z*upForward)
                local margin=INF
                for _,dt in ipairs({-.012,0,.012}) do
                    local at=ballAt(t+dt)
                    if at.Y<.05 then margin=-INF;break end
                    margin=math.min(margin,radius-segmentDistance(at,root-up,root+up*reach))
                end
                if margin>=.4 and root.X>=Field.MinX+.5 and root.X<=Field.MaxX-.5
                    and root.Z>=Field.GoalZ and root.Z<=Field.EndZ-.5 then
                    return {elapsed=t,root=root,margin=margin,diveAge=age}
                end
            end
        end
    end
    return nil
end

local function middleStemRoutes(input,Config,Field,RouteMath,los,stamina,opponent,favored,offset)
    local yd,mid=Field.YD,(Field.MinX+Field.MaxX)*.5
    local edge=math.max(.5,Config.RouteEdgeMargin or 1)
    local setupReach=math.max(0,tonumber(Config.HikeTime) or 0)
        *math.max(0,tonumber(Config.PreSnapDBSpeed) or 0)
    local dive=Config.Moves and Config.Moves.Dive
    local diveDistance=dive and finite(dive.Yards) and math.max(0,dive.Yards*yd) or 0
    local diveTime=dive and finite(dive.Time) and math.max(0,dive.Time) or 0
    if diveDistance<=0 or diveTime<=0 then return {} end
    local run,sprint=math.max(1,Config.RunSpeed),math.max(1,Config.SprintSpeed)
    local drain=math.max(.01,Config.SprintDrain)
    local dispatch,staminaReserve=.12,10
    local goalDepth=(Field.GoalZ-los)/yd
    local candidates={}
    -- The receiver walks the center stem at the native run speed, conserving
    -- current stamina. No unverified regeneration is credited. The throw still
    -- follows the unchanged native FillSpeed clock, so these two clocks must
    -- be modeled separately rather than placing us at PointAt(Launch).
    for _,insetYards in ipairs({0,1,2,3}) do
        for _,side in ipairs({favored,-favored}) do
            for _,goalBeyond in ipairs({-1,0,1,1.5,2}) do
                local depth=goalDepth+goalBeyond
                local endZ=los+depth*yd
                local endX=side<0 and Field.MinX+edge+insetYards*yd
                    or Field.MaxX-edge-insetYards*yd
                for _,tailYards in ipairs({11,11.5,12,12.5,13,13.5,14,14.5}) do
                    local stem=depth-tailYards
                    if stem>=4 and depth>=16 and endZ<=Field.EndZ-edge
                        and math.abs(endX-mid)>=3*yd then
                        local raw={Vector2.new(mid,los),Vector2.new(mid,los+stem*yd),Vector2.new(endX,endZ)}
                        local points=RouteMath.Sanitize(raw,mid,los)
                        if #points==3 and math.abs(points[2].X-mid)<1e-5
                            and (points[3]-raw[3]).Magnitude<.05 then
                            local plan=RouteMath.Plan(points,"Floater")
                            local incoming,outgoing=points[2]-points[1],points[3]-points[2]
                            local angle=math.deg(math.acos(clamp(incoming.Unit:Dot(outgoing.Unit),-1,1)))
                            local cutAt=incoming.Magnitude/run
                            local cutLead=plan.Launch-cutAt
                            local sprintDuration=plan.Arrival-cutAt+dispatch
                            local finalStamina=stamina-sprintDuration*drain
                            local fraction=.98
                            local finishAt=plan.Launch+plan.Flight*fraction
                            local origin=Vector2.new(mid,los-Config.QBBackYards*yd)
                            local finish=origin:Lerp(plan.Target,fraction)
                            -- Startup slack reduces estimated progress, while the
                            -- stamina budget charges the earlier ideal cut plus a
                            -- dispatch allowance after arrival. This is deliberately
                            -- conservative about both distance and retained stamina.
                            local sprintBeforeThrow=math.max(0,cutLead-dispatch)
                            local launchPoint=points[2]+outgoing.Unit*math.min(outgoing.Magnitude,
                                sprint*sprintBeforeThrow)
                            local launchStamina=math.max(0,stamina-math.max(0,cutLead)*drain)
                            local finishDistance=(finish-launchPoint).Magnitude
                            local finishWindow=plan.Flight*fraction
                            local diveRun=math.max(0,finishDistance-diveDistance)/sprint+diveTime
                            local uprightTime=finishDistance/sprint
                            local finishReachable=diveRun+dispatch<=finishWindow
                            if angle>=20 and cutLead>=dispatch+.01 and cutLead<=.5
                                and finalStamina>=staminaReserve and finishReachable
                                and finish.Y>=Field.GoalZ+yd then
                                local witness=sidelineDiveWitness(plan,launchPoint,outgoing.Unit,los,Config,Field)
                                if witness then
                                local worst,endpointDistance=0,0
                                if opponent then
                                    worst=INF
                                    local p0=Vector3.new(mid+offset.X,Config.ReleaseHeight,
                                        los-Config.QBBackYards*yd+offset.Z)
                                    local target=worldPoint(plan.Target,offset,Config.CatchHeight)
                                    endpointDistance=flatDistance(target,opponent)
                                    local height=3+(Config.HandUpOffset or 3.5)
                                        +(Config.JumpHeight or 6)+(Config.CatchRadius or 3.75)
                                    for sample=1,10 do
                                        local u=sample/10
                                        local at=p0:Lerp(target,u)+Vector3.new(0,4*plan.Apex*u*(1-u),0)
                                        if at.Y<=height then
                                            local reach=setupReach+sprint
                                                *math.max(0,plan.Launch+plan.Flight*u-.15)+(Config.CatchRadius or 3.75)
                                            worst=math.min(worst,flatDistance(at,opponent)-reach)
                                        end
                                    end
                                    if worst==INF then worst=0 end
                                end
                                local shape=cutLead>=.29 and "sideline_cut_early"
                                    or cutLead>=.21 and "sideline_cut_mid" or "sideline_cut_late"
                                local penalty,failures,family,signature=adaptation(input,"Floater",shape,
                                    depth,side,plan.Arrival)
                                local progress=(math.min(finish.Y,Field.GoalZ+5*yd)-los)/yd
                                local score=progress+clamp(worst/yd,-20,10)*1.7
                                    +clamp(endpointDistance/yd,0,30)*.15-plan.Flight*.55-.85
                                    +(side==favored and .15 or 0)-penalty
                                local release=type(input.release)=="string" and input.release~=""
                                    and Config.ReleaseDefs and Config.ReleaseDefs[input.release] and input.release or nil
                                local distance=RouteMath.Length(points)+(plan.LeadTime or 0)*Config.FillSpeed
                                local groundTime=travelTime(distance,Config,stamina)
                                candidates[#candidates+1]={payload={Points=points,StartX=mid,Pass="Floater",Release=release},
                                    plan=plan,score=score,reachable=true,runTime=groundTime,groundRunTime=groundTime,
                                    estimatedSeparation=endpointDistance,defenderEnvelopeMargin=worst,
                                    side=side,depth=depth,shape=shape,family=family,signature=signature,
                                    cutCount=1,lastCutAt=cutAt,hikeTime=Config.HikeTime,setupDefenderReach=setupReach,
                                    estimatedCatchZ=finish.Y,estimatedCatchAt=finishAt,estimatedRACDistance=0,
                                    estimatedCatchStamina=finalStamina,uprightCatchReachable=uprightTime+dispatch<=finishWindow,
                                    adaptationPenalty=penalty,recentFailureCount=failures,
                                    middleStemDeep=true,stemYards=stem,cutLeadTime=cutLead,finishMode="jumpDive",
                                    finishReachable=true,estimatedFinishAt=finishAt,estimatedFinishZ=finish.Y,
                                    finishFraction=fraction,finishDistance=finishDistance,finishReserve=dispatch,
                                    finishWindow=finishWindow,fullRouteDistance=distance,
                                    estimatedLaunchStamina=launchStamina,estimatedLaunchX=launchPoint.X,
                                    estimatedLaunchZ=launchPoint.Y,finishTravelTime=diveRun,
                                    slowStem=true,slowStemTime=cutAt,slowStemSpeed=run,slowStemStartupSlack=dispatch,
                                    forceDiveFinish=true,requireDive=true,finalSprint=true,startSprintAt=cutAt,cutAt=cutAt,
                                    finalSprintDuration=sprintDuration,finalSprintReserve=staminaReserve,
                                    finalSprintStamina=finalStamina,sidelineInset=edge+insetYards*yd,
                                    sidelineFallback=insetYards>0,
                                    diveWitnessElapsed=witness.elapsed,diveWitnessX=witness.root.X,
                                    diveWitnessZ=witness.root.Z,diveWitnessMargin=witness.margin,
                                    model="observed-opponent-envelope",routeStrategy="sideline-dive"}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return candidates
end

local function campingGate(input,Config,Field)
    local history=type(input.recentRoutes)=="table" and input.recentRoutes or {}
    local gate={eligible=false,evidenceCount=0,currentKnown=false,currentCamping=false}
    local offset=offsetOf(input)
    if vec(input.opponentPosition) and vec(input.opponentVelocity) then
        gate.currentKnown=true
        gate.currentCamping=input.opponentPosition.Z>=Field.GoalZ+offset.Z-Field.YD
            and input.opponentPosition.Z<=Field.EndZ+offset.Z
            and (input.opponentVelocity*FLAT).Magnitude<=Config.RunSpeed*.4
    end
    local previousKey,confirmed=nil,#history>=2
    for i=math.max(1,#history-1),#history do
        local item=history[i]
        if type(item)~="table" or item.campingObservationKnown~=true or item.observedEndzoneCamping~=true
            or type(item.roundKey)~="string" or item.roundKey=="" or item.roundKey=="current"
            or item.roundKey==previousKey then confirmed=false
        else gate.evidenceCount=gate.evidenceCount+1 end
        previousKey=type(item)=="table" and item.roundKey or nil
    end
    if input.role~="WR" then gate.reason="not_wr"
    elseif input.campingCounterUsed==true then gate.reason="already_attempted"
    elseif input.campingCounterUsed~=false then gate.reason="counter_state_unknown"
    elseif not confirmed then gate.reason="need_two_confirmed_plays"
    elseif not gate.currentKnown then gate.reason="current_defender_unknown"
    elseif not gate.currentCamping then gate.reason="defender_not_waiting_deep"
    else gate.eligible=true;gate.reason="eligible" end
    return gate
end
local function attachCampingGate(choice,gate,reason)
    choice.campingGateReason=reason or gate.reason
    choice.campingEvidenceCount=gate.evidenceCount
    choice.campingCurrentKnown=gate.currentKnown
    choice.campingCurrentWaiting=gate.currentCamping
    return choice
end

-- A rare response to observed camping, not a default Bullet rotation. Keep
-- the real Bullet arc and require a moving jump catch before the goal line.
local function campingBullet(input,Config,Field,RouteMath,Planner,base)
    local offset=offsetOf(input);local yd=Field.YD
    local los=input.LOS or Field.LOSZ;local goal=Field.GoalZ+offset.Z
    local mid=(Field.MinX+Field.MaxX)*.5
    local run,sprint,drain=Config.RunSpeed,Config.SprintSpeed,Config.SprintDrain or 25
    local moveCost=math.huge
    for _,name in ipairs({"Juke","Spin"}) do
        local move=Config.Moves and Config.Moves[name]
        if move and finite(move.Cost) and move.Cost>0 then moveCost=math.min(moveCost,move.Cost) end
    end
    if not finite(moveCost) or not vec(input.position) or not finite(input.stamina) then return nil end
    local reserve=10+moveCost
    local rootY=input.position.Y;local turf=Field.TurfY or 0
    local gravity=finite(input.gravity) and input.gravity>0 and input.gravity or 196.2
    local jumpHeight=Config.JumpHeight or 6
    local edge=math.max(1,Config.RouteEdgeMargin or 1)
    local best,bestClearance;local forecasts=0
    -- At most five yards before goal: the familiar deep stem remains intact.
    for _,back in ipairs({3,4,5}) do
        local stemYards=(Field.GoalZ-los)/yd-back
        if stemYards>=10 then
            for _,side in ipairs({base.side,-base.side}) do
                for _,targetBack in ipairs({1,2}) do
                    for _,width in ipairs({.8,1}) do
                        local raw={Vector2.new(mid,los),Vector2.new(mid,Field.GoalZ-back*yd),
                            Vector2.new(mid+side*((Field.MaxX-Field.MinX)*.5-edge)*width,Field.GoalZ-targetBack*yd)}
                        local points=RouteMath.Sanitize(raw,mid,los)
                        if #points==3 and (points[1]-raw[1]).Magnitude<.01 and (points[2]-raw[2]).Magnitude<.01 then
                            local leg=points[3]-points[2]
                            local angle=math.deg(math.acos(clamp(leg.Y/math.max(.001,leg.Magnitude),-1,1)))
                            local plan=RouteMath.Plan(points,"Bullet")
                            if angle>=60 and angle<=115 and side*leg.X>=2*yd and plan.Target.Y<Field.GoalZ-.25 then
                                local cut=worldPoint(points[2],offset,rootY)
                                for _,total in ipairs({1.2,1.6,2}) do
                                    local early=math.min(.9,total)
                                    local cutAt=(flatDistance(input.position,cut)-(sprint-run)*total)/run+.15
                                    local late=cutAt-(total-early)
                                    local regen=stemRegeneration(input.stamina,early*drain,late-early,Config)
                                    local stamina=input.stamina-total*drain+regen
                                    -- A direct pre-cut forecast is sufficient only when the
                                    -- whole stem precedes the actual Bullet launch.
                                    if input.stamina>=early*drain+reserve
                                        and cutAt>=total+.15 and cutAt<=plan.Launch and stamina>reserve then
                                        local snap={now=cutAt,launchAt=plan.Launch,role="WR",passType="Bullet",config=Config,
                                            arc={P0=Vector3.new(mid+offset.X,turf+Config.ReleaseHeight,los-Config.QBBackYards*yd+offset.Z),
                                                P1=worldPoint(plan.Target,offset,turf+Config.CatchHeight),Flight=plan.Flight,Apex=plan.Apex},
                                            position=cut,velocity=Vector3.new(0,0,run),lookDirection=Vector3.new(0,0,1),
                                            steeringDirection=Vector3.new(0,0,1),grounded=true,canJump=true,canDive=false,
                                            gravity=gravity,jumpSpeed=math.sqrt(2*gravity*jumpHeight),groundRootY=rootY,
                                            turfY=turf,diveTurfY=turf,diveDistance=0,walkSpeed=sprint,runSpeed=run,
                                            sprintSeconds=math.max(0,(stamina-reserve)/drain-.12),chase=true,allowHold=false,
                                            margin=.6,requireAirborne=true,preferAirborne=true,preferJumpDive=false,
                                            continuousSprint=true,continuousBulletCatch=true,reactionDelay=.12,maxHorizon=3.5,
                                            bounds={minX=Field.MinX+offset.X+.5,maxX=Field.MaxX+offset.X-.5,
                                                minZ=Field.BackZ+offset.Z+.5,maxZ=Field.EndZ+offset.Z-.5}}
                                        forecasts=forecasts+1
                                        local witness=Planner.solve(snap)
                                        if witness and witness.kind=="jump" and witness.airborneFinish=="jump"
                                            and witness.continuousCatch==true and not witness.diveAt
                                            and finite(witness.firstTouchAt) and finite(witness.stopAt)
                                            and witness.stopAt>=witness.contactAt+(witness.timingMargin or .012) then
                                            local firstPose=Planner.pose(snap,witness,witness.firstTouchAt)
                                            local catch=firstPose and firstPose.Position
                                            local beforeGoal=catch and catch.Z<goal-.25 and catch.Z>=goal-6*yd
                                            for _,at in ipairs({witness.contactAt-.012,witness.contactAt,witness.contactAt+.012}) do
                                                local cf,air=Planner.pose(snap,witness,at)
                                                if not cf or not air or cf.Position.Z>=goal-.25 then beforeGoal=false end
                                            end
                                            local duration=witness.contactAt-cutAt+.12
                                            local remaining=stamina-duration*drain
                                            if beforeGoal and remaining>=reserve then
                                                local exit=Vector3.new(catch.X,catch.Y,goal+.5)
                                                local lane=(exit-catch)*FLAT
                                                local relative=(input.opponentPosition-catch)*FLAT
                                                local closest=catch+lane*clamp(relative:Dot(lane)/math.max(.001,lane:Dot(lane)),0,1)
                                                local clearance=flatDistance(closest,input.opponentPosition)
                                                local separation=flatDistance(catch,input.opponentPosition)
                                                -- This is a known-position corridor check. It
                                                -- does not assume the defender cannot react.
                                                if clearance>=2.5*yd and separation>=5*yd
                                                    and (not best or clearance>bestClearance+.05
                                                        or math.abs(clearance-bestClearance)<=.05 and witness.firstTouchAt<best.estimatedFirstTouchAt) then
                                                    local shape=side<0 and "middle_stem_left" or "middle_stem_right"
                                                    local depth=(points[3].Y-los)/yd
                                                    local family,signature=routeKeys("Bullet",shape,depth,side)
                                                    best={payload={Points=points,StartX=mid,Pass="Bullet"},plan=plan,side=side,shape=shape,
                                                        depth=depth,family=family,signature=signature,routeFamily="middle_stem",
                                                        scheduledFamily="middle_stem",scheduledPass="Bullet",routeStrategy="deep_middle_bullet",
                                                        rareBullet=true,rareCampingBullet=true,continuousBulletCatch=true,
                                                        reachable=true,finishReachable=true,middleStemDeep=true,slowStem=true,
                                                        slowStemTime=cutAt,slowStemSpeed=run,cutAt=cutAt,startSprintAt=cutAt,
                                                        cutCount=1,lastCutAt=cutAt,stemYards=stemYards,stemRunSpeed=run,
                                                        earlyStemSprintSeconds=early,stemSprintSeconds=total,stemSprintStart=late,
                                                        estimatedStemRegeneration=regen,stemTravelDistance=flatDistance(input.position,cut),
                                                        postThrowStem=false,finalSprint=true,finalSprintDuration=duration,
                                                        finalSprintReserve=reserve,finalSprintStamina=remaining,carryReserve=reserve,
                                                        carryMoveReserve=moveCost,carryClearance=clearance,estimatedSeparation=separation,
                                                        estimatedCatchAt=witness.contactAt,estimatedFirstTouchAt=witness.firstTouchAt,
                                                        estimatedStopAt=witness.stopAt,estimatedCatchZ=catch.Z-offset.Z,
                                                        estimatedCatchStamina=remaining,estimatedContactMargin=witness.margin,
                                                        estimatedCatchInsideGoal=false,ballTargetZ=plan.Target.Y,cutAngle=angle,
                                                        requireDive=false,requireAirborne=true,preferAirborne=true,preferJumpDive=false,
                                                        finishMode="airborne_required",cutDirection=side<0 and "left" or "right"}
                                                    bestClearance=clearance
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if best then best.forecastCount=(base.forecastCount or 0)+forecasts end
    return best
end

-- Deep middle Floaters with alternating candidate sides. Observed coverage
-- chooses among funded routes; one confirmed camper response is allowed per
-- opponent session, independently of the cosmetic left/right route cycle.
function Policy.chooseScheduledRoute(input,Config,Field,RouteMath,Planner)
    input=input or {}
    if not validField(Field) or type(RouteMath)~="table" or type(RouteMath.Sanitize)~="function"
        or type(RouteMath.Plan)~="function" or input.mode=="Team" then
        return nil,"Deep middle routes require a valid 1v1 field and native route math"
    end
    if type(Planner)~="table" or type(Planner.solve)~="function" or type(Planner.pose)~="function" then
        return nil,"Airborne route forecast is unavailable"
    end
    local yd=Field.YD
    local mid=(Field.MinX+Field.MaxX)*.5
    local offset=offsetOf(input)
    local los=clamp(finite(input.LOS) and input.LOS or Field.LOSZ,Field.BackZ+1,Field.GoalZ-.05)
    local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
    local run,sprint=math.max(1,Config.RunSpeed),math.max(1,Config.SprintSpeed)
    local drain=math.max(.01,Config.SprintDrain or 25)
    local reserve,dispatch=10,.12
    if sprint<=run then return nil,"Invalid native sprint speeds" end
    local index=finite(input.routeCycle) and math.floor(input.routeCycle)%20
        or finite(input.selectionIndex) and math.max(0,math.floor(input.selectionIndex)) or 0
    local counterGate=campingGate(input,Config,Field)
    local preferredSide=index%2==0 and -1 or 1
    local opponent=projectedOpponent(input,Config,.2)
    local failures={[-1]=0,[1]=0}
    local history=type(input.recentRoutes)=="table" and input.recentRoutes or {}
    for i=#history,math.max(1,#history-3),-1 do
        local item=history[i]
        if type(item)=="table" and item.success==false and (item.side==-1 or item.side==1)
            and (item.result=="Incomplete" or item.result=="Intercepted" or item.result=="Swatted") then
            failures[item.side]=failures[item.side]+1
        end
    end
    local edge=math.max(1,Config.RouteEdgeMargin or 1)
    local goalDepth=(Field.GoalZ-los)/yd
    local shortField=goalDepth<=6
    local maximumStem=shortField and math.min(goalDepth+4,(Field.EndZ-edge-los)/yd-1) or goalDepth-.5
    local stems,seen={},{}
    local function addStem(n)
        n=clamp(n,1,math.max(1,maximumStem))
        local key=math.floor(n*100+.5)
        if n>=math.max(1,goalDepth*.5) and not seen[key] then
            stems[#stems+1]=n;seen[key]=true
        end
    end
    if shortField then
        -- A remaining short down can cut within the endzone instead of
        -- timing out on an impossible one-yard pre-goal opening burst.
        for _,beyond in ipairs({4,3,2,1}) do addStem(goalDepth+beyond) end
    else
        for _,back in ipairs({1,3,5,7,9,11}) do addStem(goalDepth-back) end
    end
    addStem(goalDepth*.7);addStem(goalDepth*.55)
    table.sort(stems,function(a,b)return a>b end)
    local gravity=finite(input.gravity) and input.gravity>0 and input.gravity or 196.2
    local jumpHeight=finite(Config.JumpHeight) and Config.JumpHeight or 6
    local turf=finite(Field.TurfY) and Field.TurfY or 0
    local rootY=vec(input.position) and input.position.Y or turf+3
    local start=Vector3.new(mid+offset.X,rootY,los+offset.Z)
    local observedStart=vec(input.position) and input.position or start
    local forecastCount=0
    local preferredDeep,deepestFeasible,bestEffort
    for _,stemYards in ipairs(stems) do
        local best,bestClear,bestInside,bestInsideClear
        for _,side in ipairs({preferredSide,-preferredSide}) do
            local sideDone=false
            for _,beyond in ipairs(shortField and {5,4,3,2,1} or {1,2,3,4,5,6}) do
                if sideDone then break end
                for _,widthFraction in ipairs({1,.8,.6,.4}) do
                    if sideDone then break end
                    local endX=mid+side*((Field.MaxX-Field.MinX)*.5-edge)*widthFraction
                    local endZ=clamp(los+(goalDepth+beyond)*yd,los+yd,Field.EndZ-edge)
                    local raw={Vector2.new(mid,los),Vector2.new(mid,los+stemYards*yd),Vector2.new(endX,endZ)}
                    local points=RouteMath.Sanitize(raw,mid,los)
                    -- Native ink/lead sanitation may pull the last point inward.
                    -- The actual center stem and a sharp legal cut must survive.
                    if #points==3 and (points[1]-raw[1]).Magnitude<.01 and (points[2]-raw[2]).Magnitude<.01 then
                        local outgoing=points[3]-points[2]
                        local lateral=side*outgoing.X
                        local angle=outgoing.Magnitude>.01 and math.deg(math.acos(clamp(outgoing.Y/outgoing.Magnitude,-1,1))) or 0
                        if lateral>=2*yd and angle>=40 and angle<=115 and (not shortField or outgoing.Y>=0) then
                            local plan=RouteMath.Plan(points,"Floater")
                            local cut=worldPoint(points[2],offset,rootY)
                            if plan.Target.Y>=Field.GoalZ+4*yd then
                                local effortScore=stemYards+(side==preferredSide and .2 or 0)-failures[side]*2
                                if not bestEffort or effortScore>bestEffort.score then
                                    local shape=side<0 and "middle_stem_left" or "middle_stem_right"
                                    local depth=(points[3].Y-los)/yd
                                    local family,signature=routeKeys("Floater",shape,depth,side)
                                    bestEffort={payload={Points=points,StartX=mid,Pass="Floater"},plan=plan,
                                        side=side,depth=depth,shape=shape,family=family,signature=signature,
                                        routeFamily="middle_stem",scheduledFamily="middle_stem",scheduledPass="Floater",
                                        routeStrategy="deep_middle_floater",middleStemDeep=true,stemYards=stemYards,
                                        cutAngle=angle,ballTargetZ=plan.Target.Y,shortField=shortField,score=effortScore,
                                        bestEffort=true,reachable=false,finishReachable=false,
                                        bestEffortReason="No funded airborne contact forecast; legal deep Floater only",
                                        postThrowStem=false,slowStem=true,slowStemTime=plan.Launch,cutAt=plan.Launch,
                                        stemSprintStart=plan.Launch,earlyStemSprintSeconds=0,stemSprintSeconds=0,
                                        stemRunSpeed=run,slowStemSpeed=run,requireAirborne=true,preferAirborne=true,
                                        requireDive=false,preferJumpDive=false,finishMode="unverified_airborne_attempt"}
                                end
                            end
                            local distance=flatDistance(observedStart,cut)
                            local detourDistance=distance
                            local bodyOnStem=false
                            if opponent then
                                local axis=(cut-observedStart)*FLAT
                                local along=axis.Magnitude>.01 and ((opponent-observedStart)*FLAT):Dot(axis.Unit) or -1
                                local lateralBody=axis.Magnitude>.01 and ((opponent-observedStart)*FLAT-axis.Unit*along).Magnitude or INF
                                if along>0 and along<axis.Magnitude and lateralBody<1.4*yd then
                                    local aroundDistance=INF
                                    for _,around in ipairs({-1,1}) do
                                        local x=opponent.X+around*1.6*yd
                                        if x>=Field.MinX+offset.X+edge and x<=Field.MaxX+offset.X-edge then
                                            local via=Vector3.new(x,rootY,opponent.Z)
                                            aroundDistance=math.min(aroundDistance,flatDistance(observedStart,via)+flatDistance(via,cut))
                                        end
                                    end
                                    if aroundDistance<INF then detourDistance=math.max(distance,aroundDistance);bodyOnStem=true end
                                end
                            end
                            for _,stemSprint in ipairs({.4,.6,.8,1,1.2,1.4,1.6,1.8,2}) do
                                local cutAt=(detourDistance-(sprint-run)*stemSprint)/run+.15+(shortField and .1 or 0)
                                if shortField then cutAt=math.max(1.5,cutAt) end
                                -- Reallocate the same bounded stem sprint earlier;
                                -- the late burst shrinks by the same amount.
                                local earlySprint=math.min(.9,stemSprint)
                                local lateSprint=stemSprint-earlySprint
                                local lateStart=cutAt-lateSprint
                                local stemRun=shortField and clamp((detourDistance-sprint*stemSprint)
                                    /math.max(.01,cutAt-.15-stemSprint),run*.2,run) or run
                                local at=cutAt
                                -- Recovery can refill an observed initial deficit
                                -- as well as this opening burst, after the native
                                -- delay plus an off-input margin and up to capacity.
                                -- Catch handoff rechecks actual current stamina.
                                local regenRate=finite(Config.StaminaRegen) and math.max(0,Config.StaminaRegen) or 0
                                local regenDelay=finite(Config.RegenDelay) and math.max(0,Config.RegenDelay)+.2 or INF
                                local regenerated=stemRegeneration(stamina,earlySprint*drain,
                                    lateStart-earlySprint,Config)
                                local afterStem=stamina-stemSprint*drain+regenerated
                                if stamina>=earlySprint*drain+reserve
                                    and cutAt>=stemSprint+.15 and at<plan.Arrival-.12 and afterStem>reserve then
                                    local endpoint=worldPoint(plan.Target,offset,turf+Config.CatchHeight)
                                    local arc={P0=Vector3.new(mid+offset.X,turf+Config.ReleaseHeight,
                                        los-Config.QBBackYards*yd+offset.Z),P1=endpoint,Flight=plan.Flight,Apex=plan.Apex}
                                    local available=plan.Arrival-at
                                    local optimistic=false
                                    for sample=0,32 do
                                        local u=.75+.25*sample/32
                                        local contactAt=plan.Launch+plan.Flight*u
                                        local ball=arc.P0:Lerp(arc.P1,u)+Vector3.new(0,4*plan.Apex*u*(1-u),0)
                                        local maxHeight=rootY+jumpHeight+(Config.HandUpOffset or 3.5)+(Config.CatchRadius or 3.75)
                                        local reach=(Config.CatchRadius or 3.75)+(Config.HandOffset or .5)+.2
                                        if ball.Y<=maxHeight and contactAt>cutAt+.12
                                            and flatDistance(cut,ball)-reach<=sprint*(contactAt-cutAt-.12)
                                            and afterStem-(contactAt-cutAt+.24)*drain>=reserve then
                                            optimistic=true;break
                                        end
                                    end
                                    -- Cheap optimistic rejection only; admission still requires
                                    -- the full jump-only robust contact planner below.
                                    if optimistic and plan.Target.Y>=Field.GoalZ+4*yd
                                        and flatDistance(cut,endpoint)<=sprint*available+(Config.CatchRadius or 3.75)+2 then
                                        forecastCount=forecastCount+1
                                        local snap={now=at,launchAt=plan.Launch,role="WR",passType="Floater",
                                            config=Config,arc=arc,position=cut,velocity=Vector3.new(0,0,run),
                                            lookDirection=Vector3.new(0,0,1),steeringDirection=Vector3.new(0,0,1),
                                            grounded=true,jumpSpeed=math.sqrt(2*gravity*jumpHeight),gravity=gravity,
                                            walkSpeed=sprint,runSpeed=run,sprintSeconds=math.max(0,(afterStem-reserve)/drain),
                                            groundRootY=rootY,turfY=turf,diveTurfY=turf,canJump=true,canDive=false,
                                            diveDistance=0,chase=true,allowHold=false,margin=.6,requireAirborne=true,
                                            requireEndzoneCatch=true,wrDiveGoalZ=Field.GoalZ+offset.Z,
                                            preferAirborne=true,preferJumpDive=false,continuousSprint=true,reactionDelay=.12,
                                            maxHorizon=math.min(3.5,plan.Arrival-at+.4),
                                            bounds={minX=Field.MinX+offset.X+.5,maxX=Field.MaxX+offset.X-.5,
                                                minZ=Field.BackZ+offset.Z+.5,maxZ=Field.EndZ+offset.Z-.5}}
                                        local contact
                                        if cutAt>plan.Launch then
                                            -- Use the same gate as live catch control. This also
                                            -- prevents advertising a post-throw stem which the
                                            -- handoff owner would immediately reject.
                                            -- The live stage describes only the late burst.
                                            -- Do not omit an opening burst still in progress
                                            -- on an unusually short native launch clock.
                                            if type(Planner.forecastStem)=="function" and plan.Launch+.1>=earlySprint then
                                                local handoffAt=plan.Launch+.1
                                                local priorSprint=clamp(handoffAt,0,earlySprint)+clamp(handoffAt-lateStart,0,lateSprint)
                                                local travelled=stemRun*math.max(0,handoffAt-.12)+(sprint-stemRun)*priorSprint
                                                local progress=clamp(travelled/math.max(.001,detourDistance),0,1)
                                                local incoming=(cut-observedStart)*FLAT
                                                incoming=incoming.Magnitude>.001 and incoming.Unit or Vector3.new(0,0,1)
                                                local handoff={}
                                                for k,v in pairs(snap) do handoff[k]=v end
                                                handoff.now=handoffAt
                                                handoff.position=observedStart:Lerp(cut,progress)
                                                handoff.velocity=incoming*((handoffAt<earlySprint or handoffAt>=lateStart) and sprint or stemRun)
                                                handoff.lookDirection,handoff.steeringDirection=incoming,incoming
                                                local checked=Planner.forecastStem(handoff,{point=cut,untilAt=cutAt,
                                                    sprintStartAt=lateStart,reserve=reserve,sprintDrain=drain,stemRunSpeed=stemRun},
                                                    stamina-priorSprint*drain+math.min(regenerated,
                                                        math.max(0,math.min(handoffAt,lateStart)-earlySprint-regenDelay)*regenRate))
                                                if checked then contact,snap=checked.plan,checked.projected else contact=nil end
                                            end
                                        else contact=Planner.solve(snap) end
                                        if contact and contact.kind=="jump" and finite(contact.contactAt)
                                            and contact.airborneFinish=="jump"
                                            and finite(contact.firstTouchAt) and finite(contact.stopAt)
                                            and contact.stopAt>=contact.firstTouchAt then
                                            local finalSeconds=contact.contactAt-cutAt+dispatch
                                            local remaining=afterStem-finalSeconds*drain
                                            if remaining>=reserve then
                                                local pose,airborne=Planner.pose(snap,contact,contact.contactAt)
                                                if pose and airborne then
                                                    -- The first overlap is the catch opportunity;
                                                    -- a later robust-window center can cross the
                                                    -- goal after an earlier catch outside it.
                                                    local firstAt=finite(contact.firstTouchAt) and contact.firstTouchAt or contact.contactAt
                                                    local firstPose=Planner.pose(snap,contact,firstAt)
                                                    local catchPoint=firstPose and firstPose.Position or pose.Position
                                                    local separation=opponent and flatDistance(catchPoint,opponent) or 0
                                                    local defenderReach=sprint*(contact.contactAt+.1)
                                                        +(Config.HikeTime or 3)*(Config.PreSnapDBSpeed or 12)
                                                    local margin=opponent and separation-defenderReach or 0
                                                    local waiting=false
                                                    if opponent then
                                                        local leg=(catchPoint-cut)*FLAT
                                                        local u=((opponent-cut)*FLAT):Dot(leg)/math.max(.001,leg:Dot(leg))
                                                        waiting=u>=.15 and u<=1.1 and flatDistance(cut+leg*clamp(u,0,1),opponent)<2*yd
                                                            and boundedVelocity(input.opponentVelocity,sprint).Magnitude<run*.6
                                                    end
                                                    local shape=side<0 and "middle_stem_left" or "middle_stem_right"
                                                    local depth=(points[3].Y-los)/yd
                                                    local family,signature=routeKeys("Floater",shape,depth,side)
                                                    local insideGoal=catchPoint.Z>=Field.GoalZ+offset.Z
                                                    local score=clamp(margin/yd,-30,20)*.5+remaining*.04-stemSprint
                                                        +math.min(angle,90)*.08+(insideGoal and 12 or 0)
                                                        +(side==preferredSide and .3 or 0)-failures[side]*12-(waiting and 15 or 0)
                                                    local c={payload={Points=points,StartX=mid,Pass="Floater"},plan=plan,
                                                        side=side,depth=depth,shape=shape,family=family,signature=signature,
                                                        routeFamily="middle_stem",cutDirection=side<0 and "left" or "right",
                                                        scheduledFamily="middle_stem",scheduledPass="Floater",score=score,
                                                        reachable=true,finishReachable=true,middleStemDeep=true,slowStem=true,
                                                        slowStemTime=cutAt,slowStemSpeed=run,stemYards=stemYards,
                                                        cutAt=cutAt,startSprintAt=cutAt,cutCount=1,lastCutAt=cutAt,
                                                        stemSprintSeconds=stemSprint,stemSprintStart=lateStart,
                                                        earlyStemSprintSeconds=earlySprint,shortField=shortField,stemRunSpeed=stemRun,
                                                        estimatedStemRegeneration=regenerated,ballTargetZ=plan.Target.Y,
                                                        stemTravelDistance=detourDistance,postThrowStem=cutAt>plan.Launch,
                                                        estimatedCatchAt=contact.contactAt,estimatedCatchZ=catchPoint.Z-offset.Z,
                                                        estimatedFirstTouchAt=firstAt,estimatedStopAt=contact.stopAt,
                                                        estimatedCatchStamina=remaining,estimatedContactMargin=contact.margin,
                                                        finalSprint=true,finalSprintDuration=finalSeconds,finalSprintReserve=reserve,
                                                        finalSprintStamina=remaining,finishDistance=flatDistance(cut,catchPoint),
                                                        cutAngle=angle,estimatedCatchInsideGoal=insideGoal,
                                                        estimatedSeparation=separation,defenderEnvelopeMargin=margin,
                                                        anticipatedLane=waiting,stemBlocked=false,stemDetour=bodyOnStem,
                                                        requireDive=false,preferAirborne=true,preferJumpDive=false,requireAirborne=true,
                                                        finishMode="airborne_required",routeStrategy="deep_middle_floater",
                                                        forecastCount=forecastCount,runTime=contact.contactAt,
                                                        _contactSnapshot=snap,_staminaAtCut=afterStem}
                                                    if not best or c.score>best.score then best=c end
                                                    if not waiting and (not bestClear or c.score>bestClear.score) then bestClear=c end
                                                    if insideGoal and (not bestInside or c.score>bestInside.score) then bestInside=c end
                                                    if insideGoal and not waiting and (not bestInsideClear or c.score>bestInsideClear.score) then bestInsideClear=c end
                                                    if not waiting and insideGoal and angle>=60 then sideDone=true end
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Compare at most two yards of depth below the first funded candidate
        -- so a meaningfully sharper turn can beat a slightly deeper slant.
        -- Every Floater witness already requires an endzone first contact.
        local c=bestInsideClear or bestClear or bestInside or best
        if c and not preferredDeep then preferredDeep,deepestFeasible=c,stemYards
        elseif c and stemYards>=deepestFeasible-2 and
            (c.cutAngle>=preferredDeep.cutAngle+5 and not (c.anticipatedLane and not preferredDeep.anticipatedLane)
                or preferredDeep.anticipatedLane and not c.anticipatedLane) then preferredDeep=c end
        c=preferredDeep and (shortField or preferredDeep.cutAngle>=60 or stemYards<=deepestFeasible-2
            or stemYards==stems[#stems]) and preferredDeep or nil
        if c then
            c.forecastCount=forecastCount
            -- Respond at the first qualified opportunity, rather than waiting
            -- for a fixed cycle slot that can fall after this match has ended.
            -- A failed counter-route remains the original funded Floater.
            local gateReason
            if counterGate.eligible then
                local counter=campingBullet(input,Config,Field,RouteMath,Planner,c)
                if counter then return attachCampingGate(counter,counterGate,"counter_selected") end
                gateReason="no_funded_counter"
            end
            c._contactSnapshot,c._staminaAtCut=nil,nil
            return attachCampingGate(c,counterGate,gateReason)
        end
    end
    if bestEffort then
        bestEffort.forecastCount=forecastCount
        return attachCampingGate(bestEffort,counterGate,counterGate.eligible and "no_funded_floater" or nil)
    end
    return nil,"No deep middle Floater has a funded airborne catch forecast"
end

-- input: LOS (field coordinates), world position/opponentPosition, offset,
-- opponentVelocity, stamina, release (already checked owned by the caller).
-- result.payload exactly matches the native RouteBoard submission schema.
function Policy.chooseRoute(input,Config,Field,RouteMath)
    input=input or {}
    if not validField(Field) then return nil,"Invalid 1v1 field" end
    if type(RouteMath)~="table" or type(RouteMath.Sanitize)~="function"
        or type(RouteMath.Plan)~="function" then return nil,"Route math unavailable" end
    if input.mode=="Team" then return nil,"1v1 route policy only" end
    local offset=offsetOf(input)
    local yd=Field.YD
    local los=finite(input.LOS) and input.LOS or Field.LOSZ
    los=clamp(los,Field.BackZ+1,Field.GoalZ-yd)
    local edge=math.max(Config.RouteEdgeMargin or 1,1.5)
    local startMargin=Config.SidelineMarginYards*yd
    local minStart,maxStart=Field.MinX+startMargin,Field.MaxX-startMargin
    local mid=(Field.MinX+Field.MaxX)*.5
    local opponent=projectedOpponent(input,Config,.2)
    local opponentX=opponent and opponent.X-offset.X or mid
    local favored=opponentX>=mid and -1 or 1
    local stamina=finite(input.stamina) and input.stamina or Config.Stamina
    local observedDepth=vec(input.opponentPosition) and (input.opponentPosition.Z-offset.Z-los)/yd or nil
    local underneathTrigger=Policy.underneathTriggerYards()
    local underneath=input.adaptiveRoutes~=false and observedDepth and observedDepth>=underneathTrigger
    local underneathLimit=underneath and input.opponentPosition.Z-offset.Z-UNDERNEATH_BUFFER_YARDS*yd or nil
    local juke=Config.Moves and Config.Moves.Juke
    local carryReserve=10+(juke and finite(juke.Cost) and math.max(0,juke.Cost) or 20)
    local hikeTime=math.max(0,tonumber(Config.HikeTime) or 0)
    local setupReach=hikeTime*math.max(0,tonumber(Config.PreSnapDBSpeed) or 0)
    local floaterMinimum=math.min(16,math.max(0,(Field.EndZ-edge-los)/yd))
    local trialTrigger=lateBendTrigger(input)
    local shapes={"go","bend","slant","corner","cross","double"}
    if trialTrigger then shapes[#shapes+1]="late_bend" end
    local best,candidates,trialCandidates=nil,{},{}
    local underneathCandidates={}
    local underneathCarryCandidates={}
    local slantMixCandidates={}
    local recentChoices=type(input.recentSelections)=="table" and input.recentSelections or {}
    local previousChoice=recentChoices[#recentChoices]
    local trySlantMix=input.adaptiveRoutes~=false and input.middleStemDeep~=false
        and observedDepth and observedDepth>=0 and observedDepth<underneathTrigger
        and type(previousChoice)=="table" and previousChoice.pass=="Floater"
    local depths=underneath and {UNDERNEATH_MIN_YARDS,10,12,14,16,18,20,22,23,24,27}
        or {16,18,20,22,23,24,27}
    for _,side in ipairs({favored,-favored}) do
        local startX=side<0 and minStart or maxStart
        local outside=side<0 and Field.MinX+edge+yd or Field.MaxX-edge-yd
        for _,depth in ipairs(depths) do
            local z=math.min(los+depth*yd,Field.EndZ-edge)
            if z>los+yd then
                for shape,shapeName in ipairs(shapes) do
                    local raw={Vector2.new(startX,los)}
                    if shape==2 then
                        -- One shallow inside break, then return to the outside.
                        raw[#raw+1]=Vector2.new(clamp(startX-side*3*yd,minStart,maxStart),
                            math.min(z-yd,los+5*yd))
                    end
                    local endpointX=outside
                    if shape==3 then
                        -- A legal inside slant offers a quicker Bullet flight;
                        -- the pass constraints below retain the requested depth.
                        endpointX=clamp(startX-side*math.min(7,depth*.5)*yd,
                            Field.MinX+edge,Field.MaxX-edge)
                    elseif shape==4 then
                        -- Step inside first, then make an actual outside turn.
                        -- The early lateral leg can complete before short throws.
                        raw[#raw+1]=Vector2.new(startX-side*.6*yd,los)
                    elseif shape==5 then
                        raw[#raw+1]=Vector2.new(startX,los+.8*yd)
                        raw[#raw+1]=Vector2.new(startX-side*3*yd,los+1.5*yd)
                        endpointX=clamp(startX-side*math.min(9,depth*.6)*yd,
                            Field.MinX+edge,Field.MaxX-edge)
                    elseif shape==6 then
                        raw[#raw+1]=Vector2.new(startX-side*1.2*yd,los+.6*yd)
                        raw[#raw+1]=Vector2.new(startX+side*.3*yd,los+1.5*yd)
                        endpointX=clamp(startX-side*math.min(4,depth*.5)*yd,
                            Field.MinX+edge,Field.MaxX-edge)
                    elseif shape==7 then
                        -- A bounded trial moves the existing inside break later;
                        -- it does not assume the defender follows that first leg.
                        raw[#raw+1]=Vector2.new(clamp(startX-side*3*yd,minStart,maxStart),
                            math.min(z-yd,los+11*yd))
                    end
                    raw[#raw+1]=Vector2.new(endpointX,z)
                    local points=RouteMath.Sanitize(raw,startX,los)
                    local length=RouteMath.Length(points)
                    local actualDepth=(points[#points].Y-los)/yd
                    for _,pass in ipairs({"Bullet","Floater"}) do
                        local plan=RouteMath.Plan(points,pass)
                        local arrival=plan.Arrival
                        local belowDefender=underneath and pass=="Bullet" and actualDepth>=UNDERNEATH_MIN_YARDS-1e-5
                            and actualDepth<=16+1e-5 and plan.Target.Y<=underneathLimit
                        local cutCount,lastCutAt=0,nil
                        for index=2,#points-1 do
                            local incoming=points[index]-points[index-1]
                            local outgoing=points[index+1]-points[index]
                            local turn=math.deg(math.acos(clamp(incoming.Unit:Dot(outgoing.Unit),-1,1)))
                            if turn>=20 and plan.Times[index]+.12<=plan.Launch then
                                cutCount=cutCount+1;lastCutAt=plan.Times[index]
                            end
                        end
                        local receiverDistance=length+(plan.LeadTime or 0)*Config.FillSpeed
                        local ownBudget=belowDefender and math.max(0,stamina-10-.12*Config.SprintDrain) or stamina
                        local ownTime=travelTime(receiverDistance,Config,ownBudget)
                        local catchStamina=stamina-arrival*Config.SprintDrain
                        local reachable=belowDefender and ownTime+.12<=arrival
                            and catchStamina>=10+.12*Config.SprintDrain
                            or not belowDefender and ownTime<=arrival+.05
                        local catchWindow=uprightFloaterWindow(plan,los,receiverDistance,Config,Field,stamina)
                        local target=worldPoint(plan.Target,offset,0)
                        local endpointDistance=opponent and flatDistance(target,opponent) or 0
                        local worstMargin=0
                        if opponent then
                            worstMargin=INF
                            local p0=Vector3.new(mid+offset.X,Config.ReleaseHeight,
                                los-Config.QBBackYards*yd+offset.Z)
                            local p1=Vector3.new(target.X,Config.CatchHeight,target.Z)
                            -- Conservative envelope, sampled only where a normal
                            -- jump could reach the ball. This is not a prediction
                            -- of a defender committing to a particular direction.
                            local jumpReach=3+(Config.HandUpOffset or 3.5)
                                +(Config.JumpHeight or 6)+(Config.CatchRadius or 3.75)
                            for sample=1,10 do
                                local u=sample/10
                                local at=p0:Lerp(p1,u)+Vector3.new(0,4*plan.Apex*u*(1-u),0)
                                if at.Y<=jumpReach then
                                    local elapsed=plan.Launch+plan.Flight*u
                                    local reach=setupReach+Config.SprintSpeed*math.max(0,elapsed-.15)
                                        +(Config.CatchRadius or 3.75)
                                    worstMargin=math.min(worstMargin,flatDistance(at,opponent)-reach)
                                end
                            end
                            if worstMargin==INF then worstMargin=0 end
                        end
                        local progress=(math.min(plan.Target.Y,Field.GoalZ+yd)-los)/yd
                        local score=progress+clamp(worstMargin/yd,-20,10)*1.7
                            +clamp(endpointDistance/yd,0,30)*.15
                            -plan.Flight*.55-math.max(0,#points-2)*.25-(shape==3 and .5 or 0)
                            +(side==favored and .15 or 0)
                            -(reachable and 0 or 100+math.max(0,ownTime-arrival)*20)
                        local penalty,failures,family,signature=adaptation(input,pass,shapeName,
                            actualDepth,side,arrival)
                        score=score-penalty
                        local release=type(input.release)=="string" and input.release~=""
                            and Config.ReleaseDefs and Config.ReleaseDefs[input.release] and input.release or nil
                        local candidate={payload={Points=points,StartX=startX,Pass=pass,Release=release},
                                plan=plan,score=score,reachable=reachable,runTime=ownTime,
                                estimatedSeparation=endpointDistance,defenderEnvelopeMargin=worstMargin,
                                side=side,depth=actualDepth,shape=shapeName,family=family,signature=signature,
                                cutCount=cutCount,lastCutAt=lastCutAt,
                                hikeTime=hikeTime,setupDefenderReach=setupReach,
                                estimatedCatchZ=catchWindow and catchWindow.point.Y,
                                estimatedCatchAt=catchWindow and catchWindow.at,
                                estimatedRACDistance=catchWindow and catchWindow.remaining,
                                estimatedCatchStamina=catchWindow and catchWindow.stamina,
                                uprightCatchReachable=catchWindow and catchWindow.reachable,
                                adaptationPenalty=penalty,recentFailureCount=failures,
                                model="observed-opponent-envelope"}
                        if belowDefender then
                            candidate.routeStrategy="underneath"
                            candidate.adaptiveUnderneath=true
                            candidate.observedDefenderDepthYards=observedDepth
                            candidate.underneathDepthLimit=(underneathLimit-los)/yd
                            candidate.requireDive=false
                            candidate.forceDiveFinish=false
                            candidate.middleStemDeep=false
                            candidate.finalSprint=false
                            candidate.estimatedCatchZ=plan.Target.Y
                            candidate.estimatedCatchAt=arrival
                            candidate.estimatedRACDistance=math.max(0,Field.GoalZ-plan.Target.Y)
                            candidate.estimatedCatchStamina=catchStamina
                            candidate.carryReserve=carryReserve
                            candidate.carryMoveReady=catchStamina>=carryReserve+.12*Config.SprintDrain
                            candidate.uprightCatchReachable=reachable
                        end
                        -- New cut routes must retain every real turn before the
                        -- native throw; after Throw the catch controller owns input.
                        local passAllowed=pass=="Bullet" and actualDepth>=16-1e-5 and actualDepth<=22+1e-5
                            and math.abs(points[#points].X-startX)>=3*yd-1e-5
                            and plan.Target.Y<=Field.GoalZ-2*yd+1e-5
                            or pass=="Floater" and actualDepth>=floaterMinimum-1e-5
                            or belowDefender
                        if trySlantMix and passAllowed and pass=="Bullet" and shapeName=="slant"
                            and actualDepth>=16-1e-5 and actualDepth<=18+1e-5 and penalty<=0
                            and Config.SprintSpeed>Config.RunSpeed then
                            -- Spend the beginning of a straight slant walking,
                            -- then keep native sprint for the final approach.
                            -- This is an explicit pass-mix trial, not a claim
                            -- that a defender cannot abandon deep coverage.
                            local walkUntil=(Config.SprintSpeed*(arrival-.12)-receiverDistance)
                                /(Config.SprintSpeed-Config.RunSpeed)
                            local sprintDuration=arrival-walkUntil
                            local reserve=stamina-sprintDuration*Config.SprintDrain
                            if walkUntil>=.15 and walkUntil<plan.Launch-.12
                                and reserve>=carryReserve+.12*Config.SprintDrain then
                                local mix=table.clone(candidate)
                                mix.routeStrategy="long-slant-mix";mix.pacedSlant=true
                                mix.slantWalkUntil=walkUntil;mix.slantSprintDuration=sprintDuration
                                mix.requireDive=false;mix.forceDiveFinish=false;mix.finalSprint=true
                                mix.middleStemDeep=false;mix.reachable=true;mix.uprightCatchReachable=true
                                mix.estimatedCatchAt=arrival;mix.estimatedCatchZ=plan.Target.Y
                                mix.estimatedCatchStamina=reserve;mix.carryReserve=carryReserve;mix.carryMoveReady=true
                                mix.observedDefenderDepthYards=observedDepth
                                mix.experimentalAttempt="bounded-pass-mix"
                                slantMixCandidates[#slantMixCandidates+1]=mix
                            end
                        end
                        if shape==7 then
                            if trialTrigger and depth==24 and math.abs(actualDepth-24)<1e-5
                                and pass=="Floater" and passAllowed and cutCount==1
                                and #points==3 and lastCutAt and plan.Launch-lastCutAt>=.2 then
                                trialCandidates[#trialCandidates+1]=candidate
                            end
                        elseif passAllowed and (not belowDefender or reachable)
                            and (shape<=3 or cutCount>0 and cutCount==#points-2) then
                            candidates[#candidates+1]=candidate
                            if belowDefender and reachable then
                                underneathCandidates[#underneathCandidates+1]=candidate
                                if candidate.carryMoveReady then underneathCarryCandidates[#underneathCarryCandidates+1]=candidate end
                            end
                            if not best or reachable and not best.reachable
                                or reachable==best.reachable and score>best.score then best=candidate end
                        end
                    end
                end
            end
        end
    end
    -- Prefer the nearest feasible legal sideline before comparing timing/depth
    -- variants. A positive ordinary clearance option still prevents switching
    -- to a contested sideline route; a requested dive is not a safety guarantee.
    local sidelineFallbackReason
    if #underneathCandidates>0 then
        -- A visibly deep defender leaves an underneath option. Compare only
        -- legal, reachable catches in front of that observed position; the
        -- usual conservative pressure and history gates still apply below.
        candidates=#underneathCarryCandidates>0 and underneathCarryCandidates or underneathCandidates
        best=nil;trialCandidates={};trialTrigger=nil
        for _,candidate in ipairs(candidates) do
            if not best or candidate.score>best.score then best=candidate end
        end
    elseif input.middleStemDeep~=false then
        local middle=middleStemRoutes(input,Config,Field,RouteMath,los,stamina,opponent,favored,offset)
        local ordinaryClear=false
        for _,candidate in ipairs(candidates) do
            if opponent and candidate.reachable and candidate.defenderEnvelopeMargin>0 then ordinaryClear=true;break end
        end
        local accepted={}
        local closestInset=INF
        for _,candidate in ipairs(middle) do
            if not ordinaryClear or candidate.defenderEnvelopeMargin>0 then
                closestInset=math.min(closestInset,candidate.sidelineInset)
            end
        end
        for _,candidate in ipairs(middle) do
            if (not ordinaryClear or candidate.defenderEnvelopeMargin>0)
                and candidate.sidelineInset<=closestInset+1e-5 then
                accepted[#accepted+1]=candidate
            end
        end
        local clearDeep=false
        for _,candidate in ipairs(candidates) do
            if candidate.payload.Pass=="Floater" and candidate.reachable
                and candidate.defenderEnvelopeMargin>0 then clearDeep=true;break end
        end
        for _,candidate in ipairs(middle) do
            if candidate.defenderEnvelopeMargin>0 then clearDeep=true;break end
        end
        if #slantMixCandidates>0 and not clearDeep and not ordinaryClear then
            candidates=slantMixCandidates;best=nil;trialCandidates={};trialTrigger=nil
            for _,candidate in ipairs(candidates) do
                if not best or candidate.score>best.score then best=candidate end
            end
        elseif #accepted>0 then
            candidates=accepted;best=nil;trialCandidates={};trialTrigger=nil
            for _,candidate in ipairs(candidates) do
                if not best or candidate.score>best.score then best=candidate end
            end
        else
            sidelineFallbackReason=#middle==0 and "No legal deep sideline dive meets the stamina and timing reserve"
                or "Positive-clearance route retained over contested sideline dives"
        end
    end
    if best then
        local bestClearance=-INF
        local hasClearance=false
        for _,candidate in ipairs(candidates) do
            if candidate.reachable then
                bestClearance=math.max(bestClearance,candidate.defenderEnvelopeMargin)
                if candidate.defenderEnvelopeMargin>0 then hasClearance=true end
            end
        end
        local pressureMode=not opponent and "unobserved"
            or hasClearance and "clearance" or "contested"
        local function pressureEligible(candidate)
            if not candidate.reachable then return false end
            if not opponent then return true end
            if hasClearance then return candidate.defenderEnvelopeMargin>0 end
            return candidate.defenderEnvelopeMargin>=bestClearance-2*yd
        end
        local referenceScore=-INF
        for _,candidate in ipairs(candidates) do
            if pressureEligible(candidate) then referenceScore=math.max(referenceScore,candidate.score) end
        end
        local function insideGoalEligible(candidate)
            if not candidate.reachable or candidate.payload.Pass~="Floater"
                or not (candidate.uprightCatchReachable or candidate.middleStemDeep and candidate.finishReachable)
                or candidate.estimatedCatchZ<Field.GoalZ
                or candidate.score<referenceScore-5 then return false end
            if pressureEligible(candidate) then return true end
            -- Only an upright catch already across the goal may use this small
            -- geometric tolerance. A contested route never enters a positive-
            -- clearance group, and ordinary routes retain the original bound.
            return opponent~=nil and not hasClearance
                and candidate.defenderEnvelopeMargin>=bestClearance-2*yd-.5
        end
        local insideGoalFloater=false
        for _,candidate in ipairs(candidates) do
            if insideGoalEligible(candidate) then insideGoalFloater=true;break end
        end
        local nearGoalFloater=false
        for _,candidate in ipairs(candidates) do
            if pressureEligible(candidate) and candidate.payload.Pass=="Floater"
                and candidate.uprightCatchReachable and candidate.estimatedRACDistance<=yd
                and candidate.score>=referenceScore-5 then
                nearGoalFloater=true;break
            end
        end
        local function scoringEligible(candidate)
            if referenceScore>-INF and candidate.score<referenceScore-5 then return false end
            if insideGoalFloater and candidate.payload.Pass=="Floater" then
                return insideGoalEligible(candidate)
            end
            return pressureEligible(candidate) and (not nearGoalFloater
                or candidate.payload.Pass~="Floater"
                or candidate.uprightCatchReachable and candidate.estimatedRACDistance<=yd
                    and candidate.score>=referenceScore-5)
        end
        local pressureBest,eligibleCount=nil,0
        for _,candidate in ipairs(candidates) do
            if scoringEligible(candidate) then
                eligibleCount=eligibleCount+1
                if not pressureBest or candidate.score>pressureBest.score then pressureBest=candidate end
            end
        end
        -- Progress and previous successes cannot cancel a defender's estimated
        -- access to the catch. First choose the better-clearance group, then
        -- rank legal routes inside it. This is a conservative geometry estimate,
        -- not a promise about the defender's decisions or the server's result.
        if pressureBest then best=pressureBest end
        local choice=best
        local bestSelection=-INF
        local function varietyEligible(candidate)
            return candidate==best or scoringEligible(candidate) and best.reachable
                and best.score-candidate.score<=5
                and candidate.defenderEnvelopeMargin>=best.defenderEnvelopeMargin-2*yd
        end
        local choices=type(input.recentSelections)=="table" and input.recentSelections or {}
        local previous=choices[#choices]
        local varySide,varyCut=false,false
        if best.middleStemDeep and type(previous)=="table"
            and (previous.side==-1 or previous.side==1) then
            for _,candidate in ipairs(candidates) do
                if varietyEligible(candidate) and candidate.side~=previous.side then
                    varySide=true
                    if candidate.shape~=previous.shape then varyCut=true end
                end
            end
        end
        for _,candidate in ipairs(candidates) do
            local gap=best.score-candidate.score
            -- Variety never justifies an unreachable route or a large drop in
            -- the estimated quality/clearance. If every route is unreachable,
            -- keep the best original fallback rather than rotating blindly.
            if varietyEligible(candidate) and (not varySide or candidate.side~=previous.side)
                and (not varyCut or candidate.shape~=previous.shape) then
                local repeatPenalty,mixBonus,cutBonus=repetition(input,candidate)
                local selectionScore=candidate.score-repeatPenalty+mixBonus+cutBonus
                candidate.baseScore=candidate.score
                candidate.repeatPenalty=repeatPenalty;candidate.mixBonus=mixBonus
                candidate.cutBonus=cutBonus
                candidate.selectionScore=selectionScore;candidate.qualityGap=math.max(0,gap)
                if selectionScore>bestSelection then choice=candidate;bestSelection=selectionScore end
            end
        end
        choice.pressureMode=pressureMode
        choice.bestDefenderEnvelopeMargin=bestClearance>-INF and bestClearance or nil
        choice.eligibleRouteCount=eligibleCount
        choice.nearGoalFloaterAvailable=nearGoalFloater or insideGoalFloater
        choice.insideGoalFloaterAvailable=insideGoalFloater
        choice.goalCatchPreference=insideGoalFloater and "inside" or nearGoalFloater and "near" or "none"
        choice.goalReferenceScore=referenceScore>-INF and referenceScore or nil
        choice.variedSide=varySide;choice.variedCutTiming=varyCut
        choice.sidelineFallbackReason=sidelineFallbackReason
            or choice.sidelineFallback and "Closest feasible inset retains the final sprint reserve" or nil
        choice.goalClearanceToleranceUsed=insideGoalEligible(choice) and not pressureEligible(choice)
            and math.max(0,bestClearance-2*yd-choice.defenderEnvelopeMargin) or 0
        if trialTrigger and opponent and not hasClearance and referenceScore>-INF then
            local trial
            for _,candidate in ipairs(trialCandidates or {}) do
                if candidate.reachable and candidate.uprightCatchReachable
                    and candidate.estimatedCatchZ>=Field.GoalZ and candidate.score>=referenceScore-5
                    and candidate.defenderEnvelopeMargin>=bestClearance-2*yd-.5-4
                    and (not trial or candidate.score>trial.score) then trial=candidate end
            end
            if trial then
                -- Explicit, one-off model tradeoff after repeated straight-route
                -- contests. The ordinary strategy supplies every comparison bound.
                trial.baseScore=trial.score;trial.selectionScore=trial.score
                trial.qualityGap=math.max(0,referenceScore-trial.score)
                trial.repeatPenalty=0;trial.mixBonus=0;trial.cutBonus=0
                trial.pressureMode=pressureMode;trial.bestDefenderEnvelopeMargin=bestClearance
                trial.eligibleRouteCount=eligibleCount
                trial.nearGoalFloaterAvailable=true;trial.insideGoalFloaterAvailable=true
                trial.goalCatchPreference="inside";trial.goalReferenceScore=referenceScore
                trial.goalClearanceToleranceUsed=math.min(.5,
                    math.max(0,bestClearance-2*yd-trial.defenderEnvelopeMargin))
                trial.experimentalAttempt="late-bend";trial.trialTrigger=trialTrigger
                trial.experimentalClearanceGap=math.max(0,
                    bestClearance-2*yd-.5-trial.defenderEnvelopeMargin)
                choice=trial
            end
        end
        return choice
    end
    return nil,"No legal forward route"
end

function Policy.routeTarget(plan,elapsed,offset,rootY,RouteMath,position,nextWaypoint)
    if type(plan)~="table" or type(plan.Points)~="table" or #plan.Points<2
        or type(RouteMath)~="table" or type(RouteMath.PointAt)~="function" then return nil end
    offset=vec(offset) and offset or Vector3.zero
    elapsed=finite(elapsed) and math.max(0,elapsed) or 0
    if #plan.Points>=3 and vec(position) then
        local index=clamp(finite(nextWaypoint) and math.floor(nextWaypoint) or 2,2,#plan.Points)
        -- A late frame or a slower runner must visit a cut before steering to
        -- its outgoing leg. Elapsed time alone is not proof it was reached.
        while index<#plan.Points and flatDistance(position,worldPoint(plan.Points[index],offset,rootY or 0))<=1.5 do
            index=index+1
        end
        return worldPoint(plan.Points[index],offset,rootY or 0),index
    end
    -- Short look-ahead follows the polyline; the flight controller takes over
    -- when the real Throw event arrives, rather than assuming a hidden launch.
    local point=RouteMath.PointAt(plan,elapsed+.18)
    return point and worldPoint(point,offset,rootY or 0) or nil
end

-- Movement is a target request only. Caller owns input, smoothing, actual speed,
-- collision handling, and arbitration with the catch/tackle controllers.
function Policy.movement(input,Config,Field,RouteMath)
    local flightStem=type(input)=="table" and input.allowPostThrowStem==true
        and input.role=="WR" and input.routeStrategy=="deep_middle_floater"
        and input.postThrowStem==true and finite(input.elapsed) and finite(input.slowStemTime)
        and input.elapsed<input.slowStemTime and input.finalSprintCommitted~=true
    if type(input)~="table" or not vec(input.position) or not validField(Field)
        or input.mode=="Team" or (input.ballActive or input.phase=="Live" and input.passStarted==true)
            and not flightStem then return nil end
    local position=input.position
    local offset=offsetOf(input)
    local yd=Field.YD
    local opponent=projectedOpponent(input,Config,.2)
    local margin=math.max(2,yd*.75)
    local phase,role=input.phase,input.role
    local function result(target,kind,sprint,stop,lane)
        return {target=clampWorld(target,Field,offset,margin,position.Y),kind=kind,
            sprint=sprint,stopDistance=stop,laneSide=lane}
    end
    if role=="WR" and (phase=="PreSnap" or phase=="Hike") and finite(input.startX) then
        -- Submit.StartX is the native starting-position request. Normal input
        -- also converges to it when setup movement is unlocked; never warp.
        local los=finite(input.LOS) and input.LOS or Field.LOSZ
        return result(Vector3.new(input.startX+offset.X,position.Y,los+offset.Z),"lineup",false,.5)
    end
    if input.enemyCarrier==true and opponent and (phase=="RAC" or phase=="Live" or phase=="Run") then
        local distance=flatDistance(position,opponent)
        local lead=math.min(.45,distance/math.max(1,Config.SprintSpeed)*.3)
        local target=opponent+boundedVelocity(input.opponentVelocity,Config.SprintSpeed)*lead
        local committedPursuit=role=="DB" and (phase=="RAC" or phase=="Run")
        local reserve=role=="DB" and (committedPursuit and 2 or 40) or 10
        local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
        local sprint=stamina>reserve+math.max(1,(Config.SprintDrain or 25)*.15)
        return result(target,"pursue",sprint,.8)
    end
    if role=="WR" and input.carrierIsMe and (phase=="RAC" or phase=="Run") then
        local minX,maxX=worldBounds(Field,offset,margin)
        local x=position.X
        local lane=input.laneSide
        local threat=opponent and opponent.Z>position.Z-2
            and opponent.Z-position.Z<math.max(18,7*yd)
            and flatDistance(position,opponent)<math.max(24,10*yd)
        if threat then
            if lane~=-1 and lane~=1 then
                local left,right=opponent.X-minX,maxX-opponent.X
                if math.abs(position.X-opponent.X)>2 then lane=position.X<opponent.X and -1 or 1
                else lane=left>=right and -1 or 1 end
            end
            x=clamp(opponent.X+lane*math.max(8,3*yd),minX,maxX)
        else lane=nil end
        if vec(input.priorTarget) then
            local dt=clamp(finite(input.dt) and input.dt or .05,.001,.15)
            local step=Config.SprintSpeed*dt*.8
            x=clamp(x,input.priorTarget.X-step,input.priorTarget.X+step)
        end
        -- Keep advancing even after crossing the goal line, until the server
        -- sends Result. Never stop at an estimated scoring threshold.
        local advance=position.Z+math.max(12,5*yd)
        local targetZ=math.min(Field.EndZ+offset.Z-margin,
            threat and advance or math.max(advance,Field.GoalZ+offset.Z+2*yd))
        return result(Vector3.new(x,position.Y,targetZ),"carry",true,.25,lane)
    end
    if role=="WR" and phase=="Live" then
        -- A reload may not know this play's snap time. Await the real ball
        -- instead of treating an already-running route as newly snapped.
        if not finite(input.elapsed) then return nil end
        local plan=input.routePlan
        local deepStrategy=input.routeStrategy=="deep_middle_floater" or input.routeStrategy=="deep_middle_bullet"
        local routeReserve=10
        if input.routeStrategy=="deep_middle_bullet" then
            routeReserve=finite(input.finalSprintReserve) and math.max(10,input.finalSprintReserve) or INF
        end
        if input.pacedSlant==true and finite(input.slantWalkUntil)
            and type(plan)=="table" and type(plan.Points)=="table" and #plan.Points==2 then
            local committed=input.finalSprintCommitted==true or input.elapsed>=input.slantWalkUntil
            local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
            local sprint=committed and stamina>10+math.max(1,(Config.SprintDrain or 25)*.1)
            local request=result(worldPoint(plan.Points[2],offset,position.Y),"route",sprint,.1)
            request.moveSpeed=sprint and Config.SprintSpeed or Config.RunSpeed
            request.routeWaypoint=2;request.routeDeadline=input.slantWalkUntil
            request.finalSprintCommitted=committed
            return request
        end
        if input.middleStemDeep==true and type(plan)=="table" and type(plan.Points)=="table"
            and #plan.Points>=3 and type(plan.Times)=="table" then
            local index=clamp(finite(input.routeWaypoint) and math.floor(input.routeWaypoint) or 2,2,#plan.Points)
            local slowStem=input.slowStem==true and finite(input.slowStemTime)
            -- The native throw clock keeps running through a jam or detour.
            -- At the selected cut time, take the final diagonal from here;
            -- walking to a missed stem waypoint spends the catch window.
            local finalSprint=slowStem and (input.finalSprintCommitted==true
                or input.elapsed>=input.slowStemTime)
            if slowStem and not finalSprint and index==2 and finite(plan.Arrival)
                and not deepStrategy then
                local remaining=input.slowStemTime-input.elapsed
                local stem=worldPoint(plan.Points[2],offset,position.Y)
                local origin=worldPoint(plan.Points[1],offset,position.Y)
                local axis=(stem-origin)*FLAT
                local run=math.max(1,Config.RunSpeed)
                local drain=finite(Config.SprintDrain) and math.max(.01,Config.SprintDrain) or 25
                local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
                -- Recover only a small, measured delay. Current stamina must
                -- fund uninterrupted sprint through native arrival plus the
                -- same .12-second dispatch allowance, with ten left over.
                local behind=axis.Magnitude>.01 and ((position-stem)*FLAT):Dot(axis.Unit)<-1.5
                    and flatDistance(position,stem)>run*remaining+run*.12+1.5
                if remaining>0 and remaining<=.21 and behind and plan.Arrival>=input.elapsed
                    and stamina-(plan.Arrival-input.elapsed+.12)*drain>=10 then
                    finalSprint=true
                end
            end
            if finalSprint then index=math.max(3,index) end
            local target,previous,delta,inbound,distance,deadline
            local function measure()
                target=worldPoint(plan.Points[index],offset,position.Y)
                previous=worldPoint(plan.Points[index-1],offset,position.Y)
                delta=(position-target)*FLAT
                inbound=(target-previous)*FLAT
                inbound=inbound.Magnitude>.01 and inbound.Unit or Vector3.new(0,0,1)
                distance=delta.Magnitude
                deadline=slowStem and index==2 and input.slowStemTime or plan.Times[index]
            end
            measure()
            while index<#plan.Points and finite(deadline) and input.elapsed>=deadline do
                local along=delta:Dot(inbound)
                local crossed=along>=0 and (delta-inbound*along).Magnitude<=1.5
                if distance>1.5 and not crossed then break end
                index=index+1;measure()
            end
            if slowStem and index>=3 then finalSprint=true end
            if finite(deadline) then
                local run=math.max(1,Config.RunSpeed)
                local sprintSpeed=math.max(run,Config.SprintSpeed)
                local minimum=math.max(2,run*.2)
                local remaining=deadline-input.elapsed
                local speed=clamp(distance/math.max(.05,remaining+.05),minimum,sprintSpeed)
                local scheduleCapacity,recoveryUntil,recoverySeconds
                if slowStem and not finalSprint then
                    speed=math.min(run,speed)
                    if deepStrategy then
                        -- A short opening burst, normal running, then any
                        -- separately funded late burst. All later sprint is
                        -- reserved before spending the current burst.
                        local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
                        local finish=finite(input.estimatedCatchAt) and input.estimatedCatchAt or plan.Arrival
                        local early=finite(input.earlyStemSprintSeconds) and input.earlyStemSprintSeconds or 0
                        local late=finite(input.stemSprintStart) and input.stemSprintStart or deadline
                        local stemRun=finite(input.stemRunSpeed) and clamp(input.stemRunSpeed,run*.2,run) or run
                        local remainingBurst=math.max(0,early-input.elapsed)+math.max(0,deadline-math.max(input.elapsed,late))
                        scheduleCapacity=stemRun*math.max(0,remaining)+(sprintSpeed-stemRun)*remainingBurst
                        local finalSeconds=math.max(0,finish-math.max(input.elapsed,deadline))+.12
                        local drain=Config.SprintDrain or 25
                        local required=(remainingBurst+finalSeconds)*drain+routeReserve
                        local openingCredit=0
                        if input.elapsed<early and finite(input.estimatedStemRegeneration) then
                            local maximum=finite(Config.Stamina) and math.max(0,Config.Stamina) or 0
                            local capacity=math.max(0,maximum-stamina)+math.max(0,early-input.elapsed)*drain
                            openingCredit=clamp(input.estimatedStemRegeneration,0,capacity)
                        end
                        local existingUntil=finite(input.stemRecoveryUntil) and input.stemRecoveryUntil or 0
                        local spent=finite(input.stemRecoverySpent) and clamp(input.stemRecoverySpent,0,.6) or 0
                        local recoveryActive=existingUntil>input.elapsed
                        local extraRemaining=recoveryActive and math.min(existingUntil,late)-input.elapsed or 0
                        local debt=distance+.15-scheduleCapacity
                        -- Correct only observed schedule debt; a bounded burst
                        -- never advances the cut or bypasses player avoidance.
                        if not recoveryActive and input.elapsed>=early and input.elapsed<late-.12
                            and not input.ballActive and not input.passStarted
                            and debt>.75 and sprintSpeed>stemRun and spent<.6 then
                            local duration=math.min(.6-spent,late-input.elapsed,(debt+.15)/(sprintSpeed-stemRun)+.12)
                            local fundedSeconds=math.max(0,(stamina-required)/drain)
                            if duration>fundedSeconds then
                                -- A smaller correction can be affordable even when
                                -- the entire requested burst is not. Keep an extra
                                -- input-duration allowance; never borrow regeneration.
                                duration=finite(input.currentWalkSpeed) and input.currentWalkSpeed>=run
                                    and math.min(duration,math.max(0,fundedSeconds-.12)) or 0
                            end
                            if duration>=.12 and stamina>=(remainingBurst+duration+finalSeconds)*drain+routeReserve then
                                recoveryUntil=input.elapsed+duration;recoverySeconds=duration
                                recoveryActive=true;extraRemaining=duration
                            end
                        end
                        if (input.elapsed<early or input.elapsed>=late or recoveryActive)
                            and stamina+openingCredit>=required+math.max(0,extraRemaining)*drain
                            and (input.elapsed>=early or stamina>=math.max(0,early-input.elapsed)*drain+routeReserve)
                            then speed=sprintSpeed
                        else speed=stemRun end
                        scheduleCapacity=scheduleCapacity+(sprintSpeed-stemRun)*math.max(0,extraRemaining)
                    end
                    -- Slowing before a body is only affordable with real spare
                    -- time. A jam never pauses the native throw clock; retain
                    -- normal avoidance without spending an already missed stem.
                    if opponent then
                        local toTarget=(target-position)*FLAT
                        local relative=(opponent-position)*FLAT
                        local along=toTarget.Magnitude>.01 and relative:Dot(toTarget.Unit) or -1
                        local lateral=toTarget.Magnitude>.01 and (relative-toTarget.Unit*along).Magnitude or INF
                        if along>0 and along<2*yd and lateral<1.4*yd then
                            local paced=math.max(run*.35,along)
                            if distance<=paced*math.max(0,remaining-.12) then
                                speed=math.min(speed,paced)
                            end
                        end
                    end
                end
                local feint=false
                if slowStem and not finalSprint and not deepStrategy and input.routeFamily and opponent
                    and (input.routeSide==-1 or input.routeSide==1) and remaining>.5
                    and input.elapsed<input.slowStemTime*.5 and flatDistance(position,opponent)<5*yd then
                    -- A small running feint uses spare walking time, never the
                    -- final sprint reserve. Return-to-cut distance is included.
                    local side=-input.routeSide
                    local candidate=position+Vector3.new(side*.6*yd,0,math.min(2*yd,distance*.4))
                    local detour=flatDistance(position,candidate)+flatDistance(candidate,target)
                    local leg=(candidate-position)*FLAT
                    local closest=position+leg*clamp(((opponent-position)*FLAT):Dot(leg)/math.max(.001,leg:Dot(leg)),0,1)
                    if detour<=run*math.max(0,remaining-.12)
                        and flatDistance(closest,opponent)>1.5*yd then
                        target=candidate;speed=math.min(run,math.max(speed,run*.7));feint=true
                    end
                end
                local along=delta:Dot(inbound)
                local atOrBeyond=along>=-1.5 and (delta-inbound*along).Magnitude<=1.5
                if atOrBeyond and (remaining>0 or index==#plan.Points) then
                    -- An unexpectedly early arrival continues along the stem
                    -- gently, including after passing the waypoint plane. It
                    -- never reverses to that point or makes the cut early.
                    target=position+inbound*math.max(3,yd)
                    speed=minimum
                end
                local sprint=speed>run+.05
                if finalSprint then
                    local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
                    sprint=stamina>routeReserve+math.max(1,(Config.SprintDrain or 25)*.1)
                    speed=sprint and sprintSpeed or run
                end
                local request=result(target,"route",sprint,.1)
                request.routeWaypoint=index
                request.moveSpeed=speed
                request.moveScale=speed/(sprint and sprintSpeed or run)
                request.routeDeadline=deadline
                request.finalSprintCommitted=finalSprint
                request.hardCut=deepStrategy and finalSprint
                    and input.finalSprintCommitted~=true
                request.stemFeint=feint
                request.stemRecoveryUntil=recoveryUntil
                request.stemRecoverySeconds=recoverySeconds
                request.routeScheduleCapacity=scheduleCapacity
                request.routeTimingDebt=slowStem and not finalSprint
                    and distance+.15>(scheduleCapacity or run*math.max(0,remaining-.12))
                if request.routeTimingDebt then request.routeTimingReason="observed_stem_delay" end
                return request
            end
        end
        local target,waypoint=Policy.routeTarget(input.routePlan,input.elapsed,offset,position.Y,
            RouteMath,position,input.routeWaypoint)
        local request=target and result(target,"route",true,.7) or nil
        if request then request.routeWaypoint=waypoint end
        return request
    end
    if role=="DB" and opponent and (phase=="PreSnap" or phase=="Hike" or phase=="Live") then
        local goal=Field.GoalZ+offset.Z
        local observed=vec(input.opponentPosition) and input.opponentPosition or opponent
        local observedDepth=position.Z-observed.Z
        local nearGoal=goal-observed.Z<=6*yd
        local profile=type(input.defenseProfile)=="table" and input.defenseProfile or {}
        local bias=clamp(finite(profile.depthBiasYards) and profile.depthBiasYards or 0,0,2.5)*yd
        if phase=="PreSnap" or phase=="Hike" then
            -- Start on the goal side of the receiver and line of scrimmage.
            -- The old shallow target drove into the receiver/line before hike.
            -- Leave a free band so small receiver movements do not cause press.
            -- The visible receiver moves to the selected starting side during
            -- Hike. Native DB walking remains available during this countdown.
            local los=(finite(input.LOS) and input.LOS
                or finite(Field.LOSZ) and Field.LOSZ or observed.Z-offset.Z)+offset.Z
            local base=math.max(observed.Z,los)
            local targetZ=position.Z
            if targetZ<base+yd+bias or targetZ>base+3*yd+bias then
                targetZ=base+2*yd+bias
            end
            local mid=(Field.MinX+Field.MaxX)*.5+offset.X
            local openSide=observed.X<mid-yd*.5 and 1 or observed.X>mid+yd*.5 and -1 or 0
            local lateralAim=observed.X+openSide*.2*yd
            local targetX=math.abs(position.X-lateralAim)>.6*yd and lateralAim or position.X
            return result(Vector3.new(targetX,position.Y,math.min(goal+yd,targetZ)),"shadow",false,1.5)
        end
        -- Keep a small live trail within a flexible band. A nearby legal lead
        -- is also acceptable; do not manufacture a large gap or follow every
        -- lateral twitch. Session deep-pass observations only add a bounded shade.
        local lossBias=bias
        local patternShade=clamp(finite(profile.deepAttemptShadeYards) and profile.deepAttemptShadeYards or 0,0,0.75)*yd
        -- Confirmed deep attempts can start walking with the receiver earlier.
        -- This does not deepen setup, widen the existing goal-side hold band,
        -- or spend sprint sooner. It is a floor, never an added spacing offset.
        bias=math.max(lossBias,patternShade)
        local geometricOpening=clamp(((goal-observed.Z)/yd-8)/8,0,1)
        -- A small flexible trail, not a fixed offset to chase. Keep a nearby
        -- lead when already there; spend sprint only on measured threats below.
        local preferred=-.5*yd+bias
        local minDepth=preferred-.75*yd
        local maxDepth=preferred+1.5*yd
        -- Moving the desired walking target is not a new sprint emergency.
        -- Keep sprint thresholds on the original geometric spacing, including
        -- its fixed session bias and existing near-goal floor.
        local sprintMinDepth=(-.75-3.25*geometricOpening)*yd+lossBias
            -(.75+.25*geometricOpening)*yd
        if nearGoal then
            minDepth=math.max(minDepth,-.5*yd)
            preferred=math.max(preferred,minDepth)
            sprintMinDepth=math.max(sprintMinDepth,-.5*yd)
        end
        local targetZ=position.Z
        if observedDepth<minDepth or observedDepth>maxDepth then targetZ=observed.Z+preferred end
        -- Once play starts, retain a nearby goal-side position. Do not erase
        -- the legal opening cushion by walking backward through a stationary
        -- receiver or a velocity sample that has not arrived yet.
        local holdDepth=3*yd+lossBias
        if finite(input.elapsed) and input.elapsed>=0 and input.elapsed<.4 then
            local los=(finite(input.LOS) and input.LOS
                or finite(Field.LOSZ) and Field.LOSZ or observed.Z-offset.Z)+offset.Z
            -- WR can spawn slightly behind LOS. Keep the same opening band
            -- through hike instead of briefly backing out of the legal setup.
            holdDepth=holdDepth+math.max(0,los-observed.Z)
        end
        if observedDepth>=0 and observedDepth<=holdDepth then
            targetZ=math.max(targetZ,position.Z)
        end
        local lateralDelta=position.X-observed.X
        local lateral=math.abs(lateralDelta)
        local fieldMiddle=(Field.MinX+Field.MaxX)*.5+offset.X
        local openSide=observed.X<fieldMiddle-yd*.5 and 1 or observed.X>fieldMiddle+yd*.5 and -1 or 0
        local lateralAim=observed.X+openSide*.2*yd
        -- Stay mostly behind the receiver, with only a small shade toward
        -- the greater open field. Routine alignment is walking, not sprint.
        local lateralBuffer=.6*yd
        local targetX=math.abs(position.X-lateralAim)>lateralBuffer and lateralAim or position.X
        local lookahead=.25
        local velocity=boundedVelocity(input.opponentVelocity,Config.SprintSpeed)
        local selfVelocity=boundedVelocity(input.velocity,Config.SprintSpeed)
        local side=observed.X>position.X and 1 or observed.X<position.X and -1 or 0
        local outward=side~=0 and velocity.X*side>Config.RunSpeed*.5
        local openingSpeed=math.max(0,(velocity.X-selfVelocity.X)*side)
        local forecastLateral=lateral+openingSpeed*.35
        -- The old 1.5-yard steering gate ignored a fast cut until the throw.
        -- Use only observed direction/velocity and a short forecast; a turn
        -- back toward us or an idle receiver does not trigger this lead.
        if phase=="Live" and outward and (lateral>.5*yd or forecastLateral>yd) then
            targetX=lateralAim+velocity.X*lookahead
        end
        -- Walk with clear forward movement before a persistent gap develops.
        -- The velocity lead is measured from the chosen shallow/deep shade,
        -- rather than continually pulling a default DB ahead of the receiver.
        if phase=="Live" and velocity.Z>Config.RunSpeed*.5 and observedDepth<preferred+.75*yd then
            targetZ=math.max(targetZ,observed.Z+preferred+velocity.Z*lookahead)
        end
        -- Walk with visible forward progress as the receiver reaches the
        -- nearby cushion; do not wait until they have already run past us.
        if phase=="Live" and velocity.Z>Config.RunSpeed*.5 and observedDepth<=yd+bias then
            targetZ=math.max(targetZ,position.Z+velocity.Z*lookahead)
        end
        -- A retreating receiver is leaving the goal. Do not walk farther
        -- downfield merely to restore the goal-side guard during that retreat.
        if phase=="Live" and nearGoal and velocity.Z < -2 then
            targetZ=math.min(targetZ,position.Z)
        end
        local target=Vector3.new(targetX,position.Y,math.min(goal+yd,targetZ))
        local urgent=velocity.Z>2 and (observedDepth < sprintMinDepth-2*yd
            or nearGoal and observedDepth<sprintMinDepth-yd)
        local forwardThreat=velocity.Z>Config.RunSpeed*.5 and observedDepth < sprintMinDepth-yd
        local lateralThreat=lateral>6*yd and observedDepth<3*yd and velocity.Z>=-2
        -- Backward depth motion does not make a fast outward side escape safe.
        -- Preserve the same depth/lateral bands and stamina hysteresis; slower
        -- retreating motion still releases recovery rather than chasing it.
        local lateralCutRecovery=outward and observedDepth<3*yd
            and (velocity.Z>=-2 or math.abs(velocity.X)>Config.RunSpeed+2)
            and (input.sprintOn==true and lateral>.65*yd and forecastLateral>yd
                or input.sprintOn~=true and math.abs(velocity.X)>Config.RunSpeed+2
                    and lateral>.6*yd and forecastLateral>1.5*yd)
        local downfieldRecovery=not nearGoal and goal-observed.Z<=12*yd
            and velocity.Z>Config.RunSpeed*.5
            and observedDepth<(input.sprintOn==true and sprintMinDepth or sprintMinDepth-yd)
        -- A visibly faster deep run can leave walking speed before the old
        -- six-yard emergency. Forecast only .4 seconds, require real trailing
        -- separation, and release the burst at two yards instead of body press.
        local forecastGap=-observedDepth+math.max(0,velocity.Z-Config.RunSpeed)*.4
        local deepRunRecovery=not nearGoal and finite(input.elapsed) and input.elapsed>=.4
            and observedDepth < -2*yd
            and (input.sprintOn==true and velocity.Z>Config.RunSpeed*.5
                or velocity.Z>Config.RunSpeed+2 and forecastGap>3*yd)
        -- A diagonal sprint can open real separation without either axis
        -- reaching the older emergency thresholds. Use observed relative
        -- velocity and a short range forecast, not a desired spacing offset.
        local separation=(observed-position)*FLAT
        local range=separation.Magnitude
        local away=range>.01 and separation/range or Vector3.zero
        local rangeOpening=(velocity-selfVelocity):Dot(away)
        local forecastRange=range+math.max(0,rangeOpening)*.35
        local separationRecovery=vec(input.velocity) and finite(input.elapsed) and input.elapsed>=.4
            and observedDepth<0 and velocity.Z>2 and velocity.Magnitude>Config.RunSpeed+2
            and (input.sprintOn==true and range>yd and velocity:Dot(away)>Config.RunSpeed*.5
                or input.sprintOn~=true and range>1.25*yd and rangeOpening>2 and forecastRange>2*yd)
        local retreatingSafe=velocity.Z < -2
        -- Allow a brief trail or a modest lead without restoring fixed spacing.
        -- Use observed positions so projection does not erase that free band.
        -- Walk routine recovery; save sprint for real separation or a goal-line
        -- threat, retaining a lateral buffer instead of copying every cut.
        local needsSprint=phase=="Live" and (lateralCutRecovery or not retreatingSafe
            and (urgent or forwardThreat or lateralThreat or downfieldRecovery or deepRunRecovery
                or separationRecovery))
        local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
        local startAt,stopAt=urgent and 75 or 85,urgent and 60 or 70
        local sprint=needsSprint and (input.sprintOn==true and stamina>stopAt
            or input.sprintOn~=true and stamina>=startAt)
        return result(target,"shadow",sprint,1.5)
    end
    return nil
end

return Policy

end)()
local createFullplay = (function()
-- Deterministic 1v1 setup/navigation. Fixed rules use bounded session observations.
-- No model, training, random selection, or shared service. Catch/tackle retain priority.
return function(ctx,Policy,services)
    services=services or {}
    local player=services.player or game:GetService("Players").LocalPlayer
    local world=services.world or workspace
    local rs=services.rs or game:GetService("ReplicatedStorage")
    local Config=services.Config or require(rs.Shared.Config)
    local Field=services.Field or require(rs.Shared.Field)
    local RouteMath=services.RouteMath or require(rs.Shared.RouteMath)
    local Planner=ctx.Planner or services.Planner
    local board=services.board or require(player.PlayerScripts.Game.RouteBoard)
    local submit=services.submit or function(payload) rs.Remotes.Submit:FireServer(payload) end
    local uis=services.uis or game:GetService("UserInputService")
    local guiService=services.guiService or game:GetService("GuiService")
    local run=services.runService or game:GetService("RunService")
    local http=services.http or game:GetService("HttpService")
    local read=services.read or readfile
    local write=services.write or writefile
    local append=services.append or appendfile
    local jobId=services.jobId or (game and game.JobId) or ""
    local settingsFile="ciu_deterministic_fullplay_v1.json"
    -- A reload, teleport, or prior saved ON preference must not resume control.
    -- This product never opens the former settings, route history, or journals.
    local enabled=false
    local routeCycle=0
    -- This counter is a fixed schedule preference, not an outcome/model. Only
    -- the new product's file is read; a saved ON flag never resumes control.
    if type(read)=="function" then
        local ok,saved=pcall(function() return http:JSONDecode(read(settingsFile)) end)
        local value=ok and type(saved)=="table" and saved.schemaVersion==1 and saved.routeCycle
        if type(value)=="number" and value==value and value>=0 and value<20 and value==math.floor(value) then
            routeCycle=value
        end
    end
    local alive=true
    local selected,routePlan,routeSource,planPass
    local routeWaypoint=2
    local lastLoggedWaypoint
    local roundKey,submitted,nextSubmit,submitTries=nil,false,0,0
    local laneSide,priorTarget,lastPhase,lastKind,lastSample=nil,nil,nil,nil,0
    local finalSprintCommitted=false
    local hardCutIssued=false
    local stemRecoveryUntil,stemRecoverySpent=0,0
    local recoveryObservedAt,recoveryObservedSprint
    local observedStartStamina,staminaObservedRound
    local observedSnapAt
    local message,errorMessage,saveError="Full auto off",nil,nil
    local navigationError
    local recentRoutes,memoryOpponent,activeRoute={},nil,nil
    local recentDefense,activeDefense={},nil
    local memoryOpponentId,memorySavedAt
    local recentSelections,selectionIndex={},0
    local lastLateBendTrialTrigger
    local observationStarted
    local campingObservation
    local ownPossessionObserved=false
    local campingCounterUsed=false
    local counters={routeRequests=0,rounds=0,pointsWon=0,pointsLost=0}
    local contactFxTimes={}
    local api={}
    local function log(kind,data)
        if type(append)~="function" then return end
        data=data or {};data.kind=kind;data.time=world:GetServerTimeNow()
        data.version=type(ctx.version)=="string" and ctx.version or "unversioned"
        data.buildId=ctx.buildId;data.policyMode="deterministic";data.fullAuto=enabled
        pcall(function() append("ciu_deterministic_events.jsonl",http:JSONEncode(data)..string.char(10)) end)
    end
    local function savePreferences()
        if type(write)~="function" then saveError="Saving full auto setting is unavailable";return end
        local ok,err=pcall(function()
            write(settingsFile,http:JSONEncode({schemaVersion=1,policyMode="deterministic",
                lastRequestedEnabled=enabled,autoResume=false,routeCycle=routeCycle}))
        end)
        saveError=not ok and tostring(err) or nil
    end
    local function pauseReason(s)
        if not alive or not enabled then return "Full auto off" end
        if not s.enabled or ctx.assistEnabled and not ctx.assistEnabled() then return "Full auto paused · assist off" end
        if s.testing then return "Full auto paused · local test" end
        if s.mode=="Team" or (s.mode and s.mode~="1v1") then return "Full auto · 1v1 only" end
        if uis:GetFocusedTextBox() or guiService.MenuIsOpen then return "Full auto paused · menu or text input" end
    end
    local function rootOf(character)
        return character and character:FindFirstChild("HumanoidRootPart")
    end
    local function coordinates(point)
        if typeof(point)=="Vector3" then return {x=point.X,y=point.Y,z=point.Z} end
    end
    local function descriptor(value)
        if type(value)~="table" or (value.pass~="Bullet" and value.pass~="Floater")
            or type(value.shape)~="string" or #value.shape>32 or type(value.depth)~="number"
            or value.depth~=value.depth or value.depth<0 or value.depth>100 then return nil end
        local out={}
        for _,key in ipairs({"pass","side","depth","shape","family","signature","success",
            "contested","result","time","roundKey","arrival","catchSuccess",
            "terminalResult","terminalAt","terminalPointLost","cutCount","lastCutAt","experimentalAttempt",
            "trialTrigger","experimentalClearanceGap","middleStemDeep","stemYards","cutLeadTime",
            "finishMode","estimatedFinishAt","estimatedFinishZ","finishReachable","finishDistance",
            "finishTravelTime","finishReserve","finishFraction","routeStrategy","slowStem",
            "slowStemTime","slowStemSpeed","slowStemStartupSlack","cutAt","startSprintAt","forceDiveFinish",
            "requireDive","finalSprint","finalSprintDuration","finalSprintReserve","finalSprintStamina",
            "sidelineInset","sidelineFallback","sidelineFallbackReason","diveWitnessElapsed",
            "diveWitnessX","diveWitnessZ","diveWitnessMargin","adaptiveUnderneath",
            "observedDefenderDepthYards","underneathDepthLimit","carryReserve","carryMoveReady","estimatedCatchStamina",
            "pacedSlant","slantWalkUntil","slantSprintDuration","routeFamily","cutDirection",
            "scheduledFamily","scheduleOverride","scheduledPass","passPreferenceOverride",
            "anticipatedLane","stemBlocked","preferAirborne","preferJumpDive","requireAirborne",
            "bestEffort","bestEffortReason","reachable","campingGateReason"}) do
            local v=value[key]
            if type(v)=="boolean" or type(v)=="string" and #v<=512
                or type(v)=="number" and v==v and math.abs(v)<math.huge then out[key]=v end
        end
        for _,key in ipairs({"estimatedCatchAt","estimatedCatchZ","estimatedFirstTouchAt","estimatedStopAt","estimatedContactMargin","stemSprintSeconds","stemSprintStart",
            "earlyStemSprintSeconds","stemRunSpeed","estimatedStemRegeneration","ballTargetZ","shortField",
            "stemTravelDistance","postThrowStem","stemDetour","forecastCount","cutAngle","estimatedCatchInsideGoal","rareBullet",
            "rareCampingBullet","continuousBulletCatch","carryMoveReserve","observedEndzoneCamping","campingObservationKnown",
            "campingEvidenceCount","campingCurrentKnown","campingCurrentWaiting","campingCounterUsed",
            "campingObservationSeconds","campingOwnProgressYards","campingDefenderDisplacementYards"}) do
            local v=value[key]
            if type(v)=="boolean" or type(v)=="number" and v==v and math.abs(v)<math.huge then out[key]=v end
        end
        return out
    end
    local function copyRecent()
        local result={}
        for _,item in ipairs(recentRoutes) do result[#result+1]=descriptor(item) end
        return result
    end
    local function copySelections()
        local result={}
        for _,item in ipairs(recentSelections) do result[#result+1]=descriptor(item) end
        return result
    end
    local function finite(value)
        return type(value)=="number" and value==value and math.abs(value)<math.huge
    end
    local function observeStartStamina(s)
        if s.mode and s.mode~="1v1" then
            observedStartStamina,staminaObservedRound=nil,nil
            return
        end
        if not enabled or s.testing or s.role~="WR" or s.phase~="Live" or s.arc or not finite(s.snapAt) then return end
        local elapsed=world:GetServerTimeNow()-s.snapAt
        local key=tostring(s.roundKey or s.preSnapEnds or s.snapAt)
        if key==staminaObservedRound or elapsed<0 or elapsed>.25 then return end
        local value=tonumber(player:GetAttribute("Stamina"))
        if not finite(value) or value<0 or not finite(Config.Stamina) or value>Config.Stamina then return end
        staminaObservedRound=key
        observedStartStamina=observedStartStamina and math.min(observedStartStamina,value) or value
        log("startStamina",{observed=value,elapsed=elapsed,matchMinimum=observedStartStamina,
            planningBudget=Policy.setupStaminaBudget(value,Config,observedStartStamina),
            setupAllowanceFraction=.25,empiricalAllowance=true})
    end
    local function accountStemRecovery(input)
        local at=input.elapsed
        local confirmed=input.role=="WR" and input.phase=="Live" and not input.ballActive
            and not input.passStarted and input.sprintOn==true
            and finite(input.currentWalkSpeed) and input.currentWalkSpeed>Config.RunSpeed+.05
        if finite(at) and finite(recoveryObservedAt) and confirmed and recoveryObservedSprint
            and at>recoveryObservedAt then
            local last=math.min(at,stemRecoveryUntil,
                finite(input.stemSprintStart) and input.stemSprintStart or stemRecoveryUntil)
            local spent=math.min(.1,math.max(0,last-recoveryObservedAt))
            stemRecoverySpent=math.min(.6,stemRecoverySpent+spent)
        end
        -- An allocated burst is an outstanding request, not observed spending.
        -- Walking/denied requests cannot consume the cap. Long observations
        -- contribute at most100ms rather than erasing every low-FPS interval.
        recoveryObservedAt=finite(at) and at or nil
        recoveryObservedSprint=confirmed and finite(at) and at<stemRecoveryUntil
        input.stemRecoverySpent=stemRecoverySpent
    end
    local function defenseDescriptor(value)
        if type(value)~="table" or (value.pass~="Bullet" and value.pass~="Floater")
            or not finite(value.launchAt) or not finite(value.depthAtThrow)
            or not finite(value.targetDepthYards) or not finite(value.goalDistanceYards)
            or type(value.deepEndzone)~="boolean" or type(value.playKey)~="string"
            or #value.playKey>256 then return nil end
        local out={}
        for _,key in ipairs({"pass","launchAt","depthAtThrow","targetDepthYards","goalDistanceYards",
            "deepEndzone","playKey","roundKey","result","opponentCaught","time"}) do
            local v=value[key]
            if type(v)=="boolean" or type(v)=="string" and #v<=256 or finite(v) then out[key]=v end
        end
        return out
    end
    local function copyDefense()
        local result={}
        for _,item in ipairs(recentDefense) do result[#result+1]=defenseDescriptor(item) end
        return result
    end
    local function defenseProfile()
        local bias,losses=0,0
        for _,item in ipairs(recentDefense) do
            if item.pass=="Floater" and item.deepEndzone then
                if item.opponentCaught and item.depthAtThrow<=.5 then
                    bias=math.min(2.5,bias+1.25);losses=losses+1
                elseif item.result=="Swatted" or item.result=="Intercepted" then
                    bias=math.max(0,bias-.25)
                end
            elseif item.pass=="Bullet" and not item.deepEndzone and item.opponentCaught then
                bias=math.max(0,bias-.5)
            end
        end
        local attempts=0
        for i=math.max(1,#recentDefense-2),#recentDefense do
            local item=recentDefense[i]
            if item.pass=="Floater" and item.deepEndzone then attempts=attempts+1 end
        end
        local latest=recentDefense[#recentDefense]
        -- Repeated observed deep throws describe the opponent's current play
        -- selection even when stopped. A newly short pass removes this shade;
        -- the fixed outcome-response rules above remain unchanged.
        local shortLatest=latest and latest.targetDepthYards<8
        return {depthBiasYards=bias,samples=#recentDefense,deepFloaterLosses=losses,
            recentDeepAttempts=attempts,deepAttemptShadeYards=attempts>=2 and not shortLatest and 0.75 or 0}
    end
    local function validId(value)
        return type(value)=="number" and value==value and value>0 and value<math.huge
            and value==math.floor(value)
    end
    local function opponentIdentity(s)
        local key=s.opponent and s.opponent.Name
        if type(key)~="string" or key=="" or #key>128 then return nil end
        local ok,id=pcall(function()
            local players=services.players or game:GetService("Players")
            local account=players:GetPlayerFromCharacter(s.opponent)
            return account and account.UserId
        end)
        return key,ok and validId(id) and id or nil
    end
    local function sameOpponent(memory,key,id)
        if type(memory)~="table" then return false end
        if validId(memory.opponentUserId) and validId(id) then return memory.opponentUserId==id end
        return memory.opponentKey==key
    end
    local function sessionRecord()
        return {schema=1,scope="current_opponent_session",persisted=false,
            opponentKnown=memoryOpponent~=nil,updatedAt=memorySavedAt,
            recentRoutes=copyRecent(),recentSelections=copySelections(),
            recentDefense=copyDefense(),selectionIndex=selectionIndex,
            campingCounterUsed=campingCounterUsed,
            lastLateBendTrialTrigger=lastLateBendTrialTrigger}
    end
    local function updateSessionHistory()
        memorySavedAt=world:GetServerTimeNow()
    end
    local campingFields={"observedEndzoneCamping","campingObservationKnown","campingObservationSeconds",
        "campingOwnProgressYards","campingDefenderDisplacementYards"}
    local function clearCampingEvidence()
        -- Explicit OFF/unload revokes this observation, including evidence from
        -- completed plays. Ordinary route failures remain session-local.
        for _,list in ipairs({recentRoutes,recentSelections}) do
            for _,item in ipairs(list) do
                for _,key in ipairs(campingFields) do item[key]=nil end
            end
        end
        if activeRoute then
            for _,key in ipairs(campingFields) do activeRoute[key]=nil end
        end
        campingObservation=activeRoute and {key=activeRoute.roundKey,invalid=true,frozen=true} or nil
    end
    local function clearSessionHistory()
        campingObservation=nil
        ownPossessionObserved=false
        campingCounterUsed=false
        recentRoutes,activeRoute={},nil
        recentDefense,activeDefense={},nil
        recentSelections,selectionIndex={},0
        memoryOpponent,memoryOpponentId,memorySavedAt=nil,nil,nil
        lastLateBendTrialTrigger=nil
        finalSprintCommitted=false
        hardCutIssued=false
        stemRecoveryUntil,stemRecoverySpent=0,0
        recoveryObservedAt,recoveryObservedSprint=nil,nil
        observedStartStamina,staminaObservedRound=nil,nil
        selected,routePlan,routeSource,planPass=nil,nil,nil,nil
        submitted=false;roundKey=nil;submitTries=0;nextSubmit=0;observedSnapAt=nil
        routeWaypoint=2;lastLoggedWaypoint=nil
        laneSide,priorTarget,lastKind=nil,nil,nil
    end
    local function syncOpponent(s)
        if s.phase=="Lobby" then
            if memoryOpponent or selected or #recentSelections>0 or #recentRoutes>0 then clearSessionHistory() end
            return
        end
        local key,id=opponentIdentity(s)
        if not key then return end
        if memoryOpponent and sameOpponent({opponentKey=memoryOpponent,opponentUserId=memoryOpponentId},key,id) then
            memoryOpponent=key;memoryOpponentId=id or memoryOpponentId
            return
        end
        clearSessionHistory()
        memoryOpponent,memoryOpponentId=key,id
        updateSessionHistory()
    end
    local function roundIdentity(s)
        return tostring(s.roundKey or s.preSnapEnds or "current")
    end
    local function freezeCampingObservation()
        local o=campingObservation
        if not o or o.frozen then return end
        local now=world:GetServerTimeNow()
        if not finite(now) or not o.lastAt or now<o.lastAt or now-o.lastAt>.35 then o.invalid=true end
        o.frozen=true
    end
    local function observeCamping(s,paused)
        if not activeRoute then return end
        local o=campingObservation
        if not o or o.key~=activeRoute.roundKey then
            o={key=activeRoute.roundKey};campingObservation=o
        end
        if o.frozen then return end
        if s.arc~=nil or s.passStarted==true or s.phase=="RAC" or s.phase=="Run" or s.phase=="Result" then
            freezeCampingObservation();return
        end
        if paused or s.alive==false or s.role~="WR" or not memoryOpponent
            or roundIdentity(s)~=o.key then o.invalid=true;return end
        if s.phase~="Live" then
            if o.lastAt then o.invalid=true end
            return
        end
        local root,opponent=rootOf(player.Character),rootOf(s.opponent)
        local position,other=root and root.Position,opponent and opponent.Position
        local velocity=opponent and opponent.AssemblyLinearVelocity
        local offset=s.offset or Vector3.zero
        local now,yd=world:GetServerTimeNow(),Field.YD
        local function validPoint(p)
            return typeof(p)=="Vector3" and finite(p.X) and finite(p.Y) and finite(p.Z)
        end
        if not validPoint(position) or not validPoint(other) or not validPoint(velocity)
            or not validPoint(offset) or not finite(now) or not finite(yd) or yd<=0
            or not finite(Field.GoalZ) or not finite(Config.RunSpeed) or Config.RunSpeed<=0 then
            o.invalid=true;return
        end
        if o.lastAt then
            local dt=now-o.lastAt
            if dt<0 or dt>.35 then o.invalid=true end
            if dt<=0 then return end
            o.seconds=o.seconds+dt
            o.distance=o.distance+((other-o.lastOpponent)*Vector3.new(1,0,1)).Magnitude
        else
            o.seconds=0;o.distance=0;o.startZ=position.Z;o.yd=yd;o.allCamping=true
        end
        if o.yd~=yd then o.invalid=true end
        local speed=(velocity*Vector3.new(1,0,1)).Magnitude
        local separation=((other-position)*Vector3.new(1,0,1)).Magnitude
        -- This labels an observed stationary deep defender, never intention or
        -- future behavior. Accumulated path rejects out-and-back movement.
        o.allCamping=o.allCamping and other.Z>=Field.GoalZ+offset.Z-yd
            and speed<=Config.RunSpeed*.4 and separation>=4*yd
        o.progress=(position.Z-o.startZ)/yd
        o.lastAt,o.lastOpponent=now,other
    end
    local function attachCampingObservation(item)
        freezeCampingObservation()
        local o=campingObservation
        local known=o and o.key==item.roundKey and not o.invalid
            and (o.seconds or 0)>=1-1e-6 and (o.progress or 0)>=3-1e-6
        item.campingObservationKnown=known==true
        item.observedEndzoneCamping=known==true and o.allCamping==true and o.distance<=o.yd+1e-6
        if o and o.key==item.roundKey and o.lastAt then
            item.campingObservationSeconds=o.seconds
            item.campingOwnProgressYards=o.progress
            item.campingDefenderDisplacementYards=o.distance/o.yd
        end
    end
    local function recordOutcome(result,success)
        if not activeRoute then return end
        local item=descriptor(activeRoute)
        if item then attachCampingObservation(item) end
        activeRoute=nil
        campingObservation=nil
        finalSprintCommitted=false
        if not item then return end
        item.success=success;item.contested=result=="Swatted" or result=="Intercepted"
        if result=="Catch" and success then item.catchSuccess=true;ownPossessionObserved=true end
        item.result=result;item.time=world:GetServerTimeNow()
        recentRoutes[#recentRoutes+1]=item
        while #recentRoutes>6 do table.remove(recentRoutes,1) end
        updateSessionHistory()
        log("routeOutcome",item)
    end
    local function defenseContext(s)
        return s.role=="DB" and (s.mode==nil or s.mode=="1v1") and not s.testing and s.alive~=false
    end
    local function observeDefenseThrow(s,data)
        if not enabled or not defenseContext(s) or not memoryOpponent
            or (s.phase~="Live" and s.phase~="Hike") then return end
        local arc=type(data.Arc)=="table" and data.Arc or s.arc
        local pass=(data.Pass=="Bullet" or data.Pass=="Floater") and data.Pass
            or (s.passType=="Bullet" or s.passType=="Floater") and s.passType or nil
        local launch=finite(data.LaunchAt) and data.LaunchAt or s.launchAt
        if type(arc)~="table"
            or typeof(arc.P0)~="Vector3" or typeof(arc.P1)~="Vector3"
            or not finite(arc.P0.X) or not finite(arc.P0.Y) or not finite(arc.P0.Z)
            or not finite(arc.P1.X) or not finite(arc.P1.Y) or not finite(arc.P1.Z)
            or not finite(arc.Flight) or arc.Flight<=0
            or not finite(arc.Apex) or arc.Apex<0 or not finite(launch) then return end
        if not pass then
            -- Native Throw packets can omit the pass label. Classify only an
            -- exact, unique match to the visible configured arc; unknown or
            -- ambiguous arcs must not change the defensive session rules.
            for _,name in ipairs({"Bullet","Floater"}) do
                local definition=type(Config.Pass)=="table" and Config.Pass[name]
                if type(definition)=="table" and finite(definition.Flight) and finite(definition.Apex)
                    and arc.Flight==definition.Flight and arc.Apex==definition.Apex then
                    if pass then return end
                    pass=name
                end
            end
            if not pass then return end
        end
        local root,opponent=rootOf(player.Character),rootOf(s.opponent)
        if not root or not opponent or not finite(root.Position.Z) or not finite(opponent.Position.Z) then return end
        local playKey=jobId..":"..tostring(launch)
        if activeDefense and activeDefense.playKey==playKey then return end
        for _,item in ipairs(recentDefense) do if item.playKey==playKey then return end end
        local offset=typeof(s.offset)=="Vector3" and s.offset or Vector3.zero
        local los=finite(s.LOS) and s.LOS or Field.LOSZ
        local remaining=(Field.GoalZ+offset.Z-arc.P1.Z)/Field.YD
        local depth=(arc.P1.Z-offset.Z-los)/Field.YD
        activeDefense=defenseDescriptor({pass=pass,launchAt=launch,playKey=playKey,
            roundKey=roundIdentity(s),
            depthAtThrow=(root.Position.Z-opponent.Position.Z)/Field.YD,
            targetDepthYards=depth,goalDistanceYards=remaining,
            deepEndzone=depth>=12 and remaining<=3 and arc.P1.Z<=Field.EndZ+offset.Z,
            time=world:GetServerTimeNow()})
    end
    local function recordDefense(result,opponentCaught)
        if not activeDefense then return end
        local item=defenseDescriptor(activeDefense);activeDefense=nil
        if not item then return end
        item.result=result;item.opponentCaught=opponentCaught==true;item.time=world:GetServerTimeNow()
        recentDefense[#recentDefense+1]=item
        while #recentDefense>6 do table.remove(recentDefense,1) end
        updateSessionHistory()
        local profile=defenseProfile()
        log("defenseOutcome",{pass=item.pass,result=result,opponentCaught=item.opponentCaught,
            deepEndzone=item.deepEndzone,depthAtThrow=item.depthAtThrow,targetDepthYards=item.targetDepthYards,
            goalDistanceYards=item.goalDistanceYards,depthBiasYards=profile.depthBiasYards,
            deepAttemptShadeYards=profile.deepAttemptShadeYards,recentDeepAttempts=profile.recentDeepAttempts,
            samples=profile.samples,playKey=item.playKey})
    end
    local function enemyCaught(s,catcher)
        if catcher==player or catcher==player.Character then return false end
        if catcher~=nil then
            if catcher==s.opponent then return true end
            local ok,character=pcall(function() return catcher.Character end)
            if ok and character~=nil and character==s.opponent then return true end
            return false
        end
        return s.enemyCarrier==true and s.carrier==s.opponent
    end
    local function inputFor(s,root)
        local opponent=rootOf(s.enemyCarrier and s.carrier or s.opponent)
        local choice=selected or activeRoute
        return {LOS=s.LOS,offset=s.offset or Vector3.zero,position=root.Position,velocity=root.AssemblyLinearVelocity,
            opponentPosition=opponent and opponent.Position,
            opponentVelocity=opponent and opponent.AssemblyLinearVelocity,
            stamina=tonumber(player:GetAttribute("Stamina")) or 0,
            sprintOn=player:GetAttribute("SprintOn")==true,
            role=s.role,phase=s.phase,mode=s.mode,ballActive=s.arc~=nil,passStarted=s.passStarted==true,
            carrierIsMe=s.carrier~=nil and s.carrier==player.Character,
            enemyCarrier=s.enemyCarrier==true,routePlan=routePlan,
            elapsed=s.snapAt and math.max(0,world:GetServerTimeNow()-s.snapAt) or nil,
            setupSeconds=math.max(0,(s.snapAt or s.preSnapEnds and (s.preSnapEnds+(Config.HikeTime or 3))
                or world:GetServerTimeNow())-world:GetServerTimeNow()),
            laneSide=laneSide,priorTarget=priorTarget,recentRoutes=recentRoutes,
            campingCounterUsed=campingCounterUsed,
            recentSelections=recentSelections,selectionIndex=selectionIndex,routeCycle=routeCycle,routeWaypoint=routeWaypoint,
            lastLateBendTrialTrigger=lastLateBendTrialTrigger,defenseProfile=defenseProfile(),
            middleStemDeep=choice and choice.middleStemDeep==true,
            slowStem=choice and choice.slowStem==true,slowStemTime=choice and choice.slowStemTime,
            routeStrategy=choice and choice.routeStrategy,postThrowStem=choice and choice.postThrowStem==true,
            stemSprintStart=choice and choice.stemSprintStart,estimatedCatchAt=choice and choice.estimatedCatchAt,
            earlyStemSprintSeconds=choice and choice.earlyStemSprintSeconds,
            stemRunSpeed=choice and choice.stemRunSpeed,
            finalSprintReserve=choice and choice.finalSprintReserve,
            estimatedStemRegeneration=choice and choice.estimatedStemRegeneration,
            stemRecoveryUntil=stemRecoveryUntil,stemRecoverySpent=stemRecoverySpent,
            allowPostThrowStem=s.allowPostThrowStem==true,gravity=world.Gravity,
            pacedSlant=choice and choice.pacedSlant==true,slantWalkUntil=choice and choice.slantWalkUntil,
            passType=s.passType,startX=selected and selected.payload.StartX,
            routeFamily=choice and choice.routeFamily,routeSide=choice and choice.side,
            finalSprintCommitted=finalSprintCommitted}
    end
    local function resetRound(key)
        local pending=activeRoute and activeRoute.roundKey==key and activeRoute or nil
        if not pending then campingObservation=nil end
        ownPossessionObserved=false
        roundKey=key;submitted=pending~=nil;nextSubmit=0;submitTries=0;observedSnapAt=nil
        observationStarted=world:GetServerTimeNow()
        hardCutIssued=false
        stemRecoveryUntil,stemRecoverySpent=0,0
        recoveryObservedAt,recoveryObservedSprint=nil,nil
        staminaObservedRound=nil
        activeRoute=pending
        if not pending then finalSprintCommitted=false end
        if not activeDefense or activeDefense.roundKey~=key then activeDefense=nil end
        routeWaypoint=2
        selected,routePlan,routeSource,planPass=nil,nil,nil,nil
        laneSide,priorTarget,lastKind=nil,nil,nil
        errorMessage=nil
    end
    local function setup()
        local s=ctx.snapshot()
        syncOpponent(s)
        observeStartStamina(s)
        if (s.phase=="RAC" or s.phase=="Run") and s.carrier==player.Character and s.carrier~=nil then
            ownPossessionObserved=true
        end
        if s.phase~=lastPhase then
            if s.phase=="PreSnap" then resetRound(roundIdentity(s)) end
            if s.phase=="Lobby" or s.phase=="Result" then
                laneSide,priorTarget,lastKind=nil,nil,nil
            end
            lastPhase=s.phase
        end
        if finite(s.snapAt) then observedSnapAt=s.snapAt end
        local paused=pauseReason(s)
        observeCamping(s,paused)
        if paused then message=paused;return end
        if s.phase=="Lobby" then message="Full auto · waiting for match";return end
        if s.phase=="Result" then message="Full auto · waiting for next round";return end
        if s.arc then message="Full auto · catch/intercept assist";return end
        if s.phase~="PreSnap" or s.role~="WR" then return end
        local key=roundIdentity(s)
        if key~=roundKey then resetRound(key) end
        if submitted then
            local choice=selected or activeRoute
            message=choice and choice.bestEffort and "Full auto · Floater best effort (no funded catch forecast)"
                or choice and choice.adaptiveUnderneath and "Full auto · Underneath: defender deep"
                or "Full auto · route submitted"
            return
        end
        local now=world:GetServerTimeNow()
        if submitTries>=3 or now<nextSubmit then return end
        -- Do not submit over an already closed/manual-submitted board.
        if not board.IsOpen() then message="Full auto · waiting for route board";return end
        local remaining=type(s.preSnapEnds)=="number" and s.preSnapEnds-now or math.huge
        local observation=1
        local defender=rootOf(s.opponent)
        if defender then
            local velocity=defender.AssemblyLinearVelocity
            local depth=defender.Position.Z-(s.offset and s.offset.Z or 0)-(s.LOS or Field.LOSZ)
            if velocity and velocity.Z>math.max(2,(Config.PreSnapDBSpeed or 12)*.5)
                and depth>=0 and depth<Policy.underneathTriggerYards()*Field.YD then observation=3 end
        end
        if now-(observationStarted or now)<observation and remaining>.5 then
            message="Full auto · reading defender position";return
        end
        local root=rootOf(player.Character)
        if not root then message="Full auto · waiting for character";return end
        submitTries=submitTries+1;nextSubmit=now+1
        local input=inputFor(s,root)
        local setupStamina=input.stamina
        input.stamina=Policy.setupStaminaBudget(setupStamina,Config,observedStartStamina)
        -- These automatic candidates are forecast without a release prefix.
        -- Equipped/owned releases remain available to the native manual menu;
        -- do not silently add their cost, motion or timing to this forecast.
        input.release=nil
        local solveStarted=os.clock()
        local chosen,reason=Policy.chooseScheduledRoute(input,Config,Field,RouteMath,Planner)
        local solveMs=(os.clock()-solveStarted)*1000
        if not chosen then
            local failure=tostring(reason or "No feasible cut route")
            if errorMessage~=failure then
                log("routeUnavailable",{reason=failure:sub(1,180),stamina=input.stamina,routeCycle=routeCycle})
            end
            errorMessage=failure
            message="Full auto · "..errorMessage
            return
        end
        assert(chosen.payload and chosen.plan,"Invalid route plan")
        -- Do not mutate the selected candidate or native manual payload.
        local payload=table.clone(chosen.payload)
        payload.Release=nil
        submit(payload)
        -- A failed selection or native submit must not spend the one session
        -- counter. Explicit OFF clears observations, not a completed attempt.
        if chosen.rareCampingBullet==true then campingCounterUsed=true end
        selected,routePlan=chosen,chosen.plan
        activeRoute=descriptor({pass=chosen.payload.Pass,side=chosen.side,depth=chosen.depth,
            shape=chosen.shape,family=chosen.family,signature=chosen.signature,
            routeFamily=chosen.routeFamily,cutDirection=chosen.cutDirection,scheduledFamily=chosen.scheduledFamily,
            scheduleOverride=chosen.scheduleOverride,anticipatedLane=chosen.anticipatedLane,stemBlocked=chosen.stemBlocked,
            scheduledPass=chosen.scheduledPass,passPreferenceOverride=chosen.passPreferenceOverride,
            preferAirborne=chosen.preferAirborne,preferJumpDive=chosen.preferJumpDive,requireAirborne=true,
            bestEffort=chosen.bestEffort,bestEffortReason=chosen.bestEffortReason,reachable=chosen.reachable,
            roundKey=roundKey,time=now,arrival=chosen.plan.Arrival,cutCount=chosen.cutCount,lastCutAt=chosen.lastCutAt,
            experimentalAttempt=chosen.experimentalAttempt,trialTrigger=chosen.trialTrigger,
            experimentalClearanceGap=chosen.experimentalClearanceGap,middleStemDeep=chosen.middleStemDeep,
            stemYards=chosen.stemYards,cutLeadTime=chosen.cutLeadTime,finishMode=chosen.finishMode,
            estimatedFinishAt=chosen.estimatedFinishAt,estimatedFinishZ=chosen.estimatedFinishZ,
            finishReachable=chosen.finishReachable,finishDistance=chosen.finishDistance,
            finishTravelTime=chosen.finishTravelTime,finishReserve=chosen.finishReserve,
            finishFraction=chosen.finishFraction,routeStrategy=chosen.routeStrategy,
            slowStem=chosen.slowStem,slowStemTime=chosen.slowStemTime,cutAt=chosen.cutAt,
            slowStemStartupSlack=chosen.slowStemStartupSlack,
            startSprintAt=chosen.startSprintAt,forceDiveFinish=chosen.forceDiveFinish,
            requireDive=chosen.requireDive,finalSprint=chosen.finalSprint,slowStemSpeed=chosen.slowStemSpeed,
            finalSprintDuration=chosen.finalSprintDuration,finalSprintReserve=chosen.finalSprintReserve,
            finalSprintStamina=chosen.finalSprintStamina,sidelineInset=chosen.sidelineInset,
            adaptiveUnderneath=chosen.adaptiveUnderneath,observedDefenderDepthYards=chosen.observedDefenderDepthYards,
            underneathDepthLimit=chosen.underneathDepthLimit,carryReserve=chosen.carryReserve,carryMoveReady=chosen.carryMoveReady,
            estimatedCatchStamina=chosen.estimatedCatchStamina,
            estimatedCatchAt=chosen.estimatedCatchAt,estimatedContactMargin=chosen.estimatedContactMargin,
            estimatedCatchZ=chosen.estimatedCatchZ,estimatedFirstTouchAt=chosen.estimatedFirstTouchAt,
            estimatedStopAt=chosen.estimatedStopAt,
            stemSprintSeconds=chosen.stemSprintSeconds,stemSprintStart=chosen.stemSprintStart,
            earlyStemSprintSeconds=chosen.earlyStemSprintSeconds,
            stemRunSpeed=chosen.stemRunSpeed,estimatedStemRegeneration=chosen.estimatedStemRegeneration,
            ballTargetZ=chosen.ballTargetZ,shortField=chosen.shortField,
            stemTravelDistance=chosen.stemTravelDistance,postThrowStem=chosen.postThrowStem,
            stemDetour=chosen.stemDetour,forecastCount=chosen.forecastCount,
            cutAngle=chosen.cutAngle,estimatedCatchInsideGoal=chosen.estimatedCatchInsideGoal,rareBullet=chosen.rareBullet,
            rareCampingBullet=chosen.rareCampingBullet,continuousBulletCatch=chosen.continuousBulletCatch,
            carryMoveReserve=chosen.carryMoveReserve,
            campingGateReason=chosen.campingGateReason,campingEvidenceCount=chosen.campingEvidenceCount,
            campingCurrentKnown=chosen.campingCurrentKnown,campingCurrentWaiting=chosen.campingCurrentWaiting,
            campingCounterUsed=campingCounterUsed,
            pacedSlant=chosen.pacedSlant,slantWalkUntil=chosen.slantWalkUntil,slantSprintDuration=chosen.slantSprintDuration,
            sidelineFallback=chosen.sidelineFallback,sidelineFallbackReason=chosen.sidelineFallbackReason,
            diveWitnessElapsed=chosen.diveWitnessElapsed,diveWitnessX=chosen.diveWitnessX,
            diveWitnessZ=chosen.diveWitnessZ,diveWitnessMargin=chosen.diveWitnessMargin})
        if chosen.trialTrigger then lastLateBendTrialTrigger=chosen.trialTrigger end
        routeWaypoint=2
        recentSelections[#recentSelections+1]=descriptor(activeRoute)
        while #recentSelections>6 do table.remove(recentSelections,1) end
        selectionIndex=selectionIndex+1
        routeCycle=(routeCycle+1)%20
        savePreferences()
        updateSessionHistory()
        submitted=true;counters.routeRequests=counters.routeRequests+1
        -- Same close operation used when the normal route menu finishes.
        local closed,closeError=pcall(board.Close)
        errorMessage=not closed and tostring(closeError) or nil
        message=chosen.bestEffort and "Full auto · Floater best effort (no funded catch forecast)"
            or chosen.adaptiveUnderneath and "Full auto · Underneath: defender deep"
            or "Full auto · "..chosen.payload.Pass.." route submitted"
        log("routeRequested",{pass=chosen.payload.Pass,startX=chosen.payload.StartX,
            campingGateReason=chosen.campingGateReason,campingEvidenceCount=chosen.campingEvidenceCount,
            campingCurrentKnown=chosen.campingCurrentKnown,campingCurrentWaiting=chosen.campingCurrentWaiting,
            campingCounterUsed=campingCounterUsed,
            points=#chosen.payload.Points,arrival=chosen.plan.Arrival,launch=chosen.plan.Launch,
            estimatedSeparation=chosen.estimatedSeparation,estimateOnly=true,
            bestEffort=chosen.bestEffort,bestEffortReason=chosen.bestEffortReason,reachable=chosen.reachable,
            cutAngle=chosen.cutAngle,estimatedCatchInsideGoal=chosen.estimatedCatchInsideGoal,
            postThrowStem=chosen.postThrowStem,forecastCount=chosen.forecastCount,solveMs=solveMs,
            earlyStemSprintSeconds=chosen.earlyStemSprintSeconds,stemSprintSeconds=chosen.stemSprintSeconds,
            stemSprintStart=chosen.stemSprintStart,
            stemRunSpeed=chosen.stemRunSpeed,estimatedStemRegeneration=chosen.estimatedStemRegeneration,
            ballTargetZ=chosen.ballTargetZ,shortField=chosen.shortField,
            estimatedFirstTouchAt=chosen.estimatedFirstTouchAt,estimatedStopAt=chosen.estimatedStopAt,
            shape=chosen.shape,depth=chosen.depth,family=chosen.family,signature=chosen.signature,
            adaptationPenalty=chosen.adaptationPenalty,recentFailureCount=chosen.recentFailureCount,
            repeatPenalty=chosen.repeatPenalty,mixBonus=chosen.mixBonus,baseScore=chosen.baseScore,
            selectionScore=chosen.selectionScore,qualityGap=chosen.qualityGap,selectionIndex=selectionIndex,
            cutCount=chosen.cutCount,lastCutAt=chosen.lastCutAt,cutBonus=chosen.cutBonus,
            experimentalAttempt=chosen.experimentalAttempt,trialTrigger=chosen.trialTrigger,
            experimentalClearanceGap=chosen.experimentalClearanceGap,
            middleStemDeep=chosen.middleStemDeep,stemYards=chosen.stemYards,cutLeadTime=chosen.cutLeadTime,
            finishMode=chosen.finishMode,estimatedFinishAt=chosen.estimatedFinishAt,
            estimatedFinishZ=chosen.estimatedFinishZ,finishReachable=chosen.finishReachable,
            finishDistance=chosen.finishDistance,finishTravelTime=chosen.finishTravelTime,
            finishReserve=chosen.finishReserve,finishFraction=chosen.finishFraction,routeStrategy=chosen.routeStrategy,
            slowStem=chosen.slowStem,slowStemTime=chosen.slowStemTime,cutAt=chosen.cutAt,
            slowStemStartupSlack=chosen.slowStemStartupSlack,
            startSprintAt=chosen.startSprintAt,requireDive=chosen.requireDive,
            slowStemSpeed=chosen.slowStemSpeed,finalSprintDuration=chosen.finalSprintDuration,
            finalSprintReserve=chosen.finalSprintReserve,finalSprintStamina=chosen.finalSprintStamina,
            adaptiveUnderneath=chosen.adaptiveUnderneath,observedDefenderDepthYards=chosen.observedDefenderDepthYards,
            underneathDepthLimit=chosen.underneathDepthLimit,carryReserve=chosen.carryReserve,carryMoveReady=chosen.carryMoveReady,
            sidelineInset=chosen.sidelineInset,sidelineFallback=chosen.sidelineFallback,
            sidelineFallbackReason=chosen.sidelineFallbackReason,
            diveWitnessElapsed=chosen.diveWitnessElapsed,diveWitnessX=chosen.diveWitnessX,
            diveWitnessZ=chosen.diveWitnessZ,diveWitnessMargin=chosen.diveWitnessMargin,
            hikeTime=chosen.hikeTime,setupDefenderReach=chosen.setupDefenderReach,
            estimatedCatchZ=chosen.estimatedCatchZ,estimatedCatchAt=chosen.estimatedCatchAt,
            estimatedRACDistance=chosen.estimatedRACDistance,estimatedCatchStamina=chosen.estimatedCatchStamina,
            pacedSlant=chosen.pacedSlant,slantWalkUntil=chosen.slantWalkUntil,slantSprintDuration=chosen.slantSprintDuration,
            uprightCatchReachable=chosen.uprightCatchReachable,
            nearGoalFloaterAvailable=chosen.nearGoalFloaterAvailable,
            insideGoalFloaterAvailable=chosen.insideGoalFloaterAvailable,
            goalCatchPreference=chosen.goalCatchPreference,goalReferenceScore=chosen.goalReferenceScore,
            goalClearanceToleranceUsed=chosen.goalClearanceToleranceUsed,
            pressureMode=chosen.pressureMode,eligibleRouteCount=chosen.eligibleRouteCount,
            defenderEnvelopeMargin=chosen.defenderEnvelopeMargin,
            bestDefenderEnvelopeMargin=chosen.bestDefenderEnvelopeMargin,
            position=coordinates(input.position),opponentPosition=coordinates(input.opponentPosition),
            opponentVelocity=coordinates(input.opponentVelocity),offset=coordinates(input.offset),
            LOS=input.LOS,stamina=input.stamina,setupStamina=setupStamina,
            planningStamina=input.stamina,observedStartStamina=observedStartStamina,
            setupAllowanceFraction=.25,empiricalSetupAllowance=true})
    end
    local accumulator=0
    local connection=run.Heartbeat:Connect(function(dt)
        accumulator=accumulator+dt
        if accumulator<.15 then return end
        accumulator=0
        local ok,err=pcall(setup)
        if not ok then errorMessage=tostring(err);message="Full auto · "..errorMessage end
    end)
    local function navigate(s,root,h,now,dt)
        if pauseReason(s) or not root or not h or h.PlatformStand then return nil end
        if s.role=="WR" and (s.phase=="PreSnap" or s.phase=="Hike") and (tonumber(h.WalkSpeed) or 0)<=0 then return nil end
        if finite(s.snapAt) then observedSnapAt=s.snapAt end
        observeStartStamina(s)
        if s.route and #s.route>=2 and (routeSource~=s.route or planPass~=s.passType) then
            if routeSource~=nil then routeWaypoint=2 end
            routePlan=RouteMath.Plan(s.route,s.passType or selected and selected.payload.Pass or "Bullet")
            routeSource,planPass=s.route,s.passType
        end
        local input=inputFor(s,root);input.dt=dt
        input.currentWalkSpeed=tonumber(h.WalkSpeed)
        accountStemRecovery(input)
        if input.role=="WR" and input.carrierIsMe
            and (input.phase=="RAC" or input.phase=="Run") and lastKind~="carry" then
            -- Catch steering may finish far from the pre-throw route target.
            -- Start carry smoothing at the actual catch position, then retain
            -- only the subsequent carry targets and chosen escape side.
            input.priorTarget=root.Position
            input.laneSide=nil
        end
        local choice=Policy.movement(input,Config,Field,RouteMath)
        if not choice then return nil end
        if choice.routeWaypoint then routeWaypoint=choice.routeWaypoint end
        if choice.finalSprintCommitted==true then finalSprintCommitted=true end
        if finite(choice.stemRecoveryUntil) and finite(choice.stemRecoverySeconds) then
            stemRecoveryUntil=choice.stemRecoveryUntil
            recoveryObservedAt=input.elapsed
            recoveryObservedSprint=input.sprintOn==true and finite(input.currentWalkSpeed)
                and input.currentWalkSpeed>Config.RunSpeed+.05
        end
        local hardCut=choice.finalSprintCommitted==true
            and (input.routeStrategy=="deep_middle_floater" or input.routeStrategy=="deep_middle_bullet")
            and not hardCutIssued
        if hardCut then hardCutIssued=true end
        laneSide,priorTarget=choice.laneSide,choice.target
        local delta=(choice.target-root.Position)*Vector3.new(1,0,1)
        local distance=delta.Magnitude
        local moving=distance>(choice.stopDistance or .8)
        local direction=moving and delta.Unit or Vector3.zero
        if moving then
            -- Native movement only; taper close to a target at low frame rates.
            direction=direction*math.min(1,distance/math.max(1,h.WalkSpeed*math.max(dt,.016)))
            if type(choice.moveSpeed)=="number" then
                -- Account for native sprint on/off replication delay without
                -- changing WalkSpeed or moving faster than the current speed.
                direction=direction*math.min(1,math.max(0,choice.moveSpeed)/math.max(1,h.WalkSpeed))
            elseif type(choice.moveScale)=="number" then
                direction=direction*math.max(0,math.min(1,choice.moveScale))
            end
        end
        local routeChoice=selected or activeRoute
        message=choice.kind=="route" and routeChoice and routeChoice.bestEffort
            and "Full auto · Floater best effort (no funded catch forecast)"
            or choice.kind=="route" and routeChoice and routeChoice.adaptiveUnderneath
                and "Full auto · Underneath: defender deep" or "Full auto · "..choice.kind
        local sampleInterval=.2
        if lastKind~=choice.kind or choice.routeWaypoint~=lastLoggedWaypoint or now-lastSample>=sampleInterval then
            lastKind,lastSample=choice.kind,now
            lastLoggedWaypoint=choice.routeWaypoint
            local opponent,velocity=input.opponentPosition,input.opponentVelocity
            local localVelocity=root.AssemblyLinearVelocity
            log("navigate",{action=choice.kind,phase=s.phase,role=s.role,elapsed=input.elapsed,
                x=root.Position.X,z=root.Position.Z,targetX=choice.target.X,targetZ=choice.target.Z,
                velocityX=localVelocity and localVelocity.X,velocityZ=localVelocity and localVelocity.Z,
                directionX=direction.X,directionZ=direction.Z,
                sprintOn=input.sprintOn,requestedSprint=moving and choice.sprint==true,
                opponentX=opponent and opponent.X,opponentZ=opponent and opponent.Z,
                opponentVelocityX=velocity and velocity.X,opponentVelocityZ=velocity and velocity.Z,
                opponentDistance=opponent and ((opponent-root.Position)*Vector3.new(1,0,1)).Magnitude,
                stamina=input.stamina,laneSide=laneSide,speed=h.WalkSpeed,moving=moving,
                routeWaypoint=choice.routeWaypoint,defenseDepthBiasYards=input.defenseProfile.depthBiasYards,
                defenseAttemptShadeYards=input.defenseProfile.deepAttemptShadeYards,
                defenseSamples=input.defenseProfile.samples,routeMoveSpeed=choice.moveSpeed,
                routeDeadline=choice.routeDeadline,finalSprintCommitted=finalSprintCommitted,
                routeScheduleCapacity=choice.routeScheduleCapacity,stemRecoveryUntil=stemRecoveryUntil,
                stemRecoverySpent=stemRecoverySpent,
                routeTimingDebt=choice.routeTimingDebt,routeTimingReason=choice.routeTimingReason})
        end
        local avoidanceArrival
        if input.role=="WR" and choice.kind=="route" and finite(choice.routeDeadline) and finite(input.elapsed) then
            avoidanceArrival={targetPosition=choice.target,arriveBy=now+choice.routeDeadline-input.elapsed}
        end
        return {direction=direction,sprint=moving and choice.sprint==true,message=message,
            hardCut=hardCut,
            avoidanceArrival=avoidanceArrival,
            preserveDepth=choice.kind=="shadow"}
    end
    function api.navigate(s,root,h,now,dt)
        local ok,result=pcall(navigate,s,root,h,now,dt)
        if not ok then
            navigationError=tostring(result)
            errorMessage=navigationError
            message="Full auto navigation paused"
            return nil
        end
        if navigationError then
            if errorMessage==navigationError then errorMessage=nil end
            navigationError=nil
        end
        return result
    end
    function api.setEnabled(value)
        enabled=value==true
        errorMessage=nil
        laneSide,priorTarget,lastKind=nil,nil,nil
        if not enabled then finalSprintCommitted=false;clearCampingEvidence() end
        if not enabled and ctx.release then ctx.release() end
        message=enabled and "Full auto · ready" or "Full auto off"
        savePreferences()
        log("enabled",{enabled=enabled})
        return true,saveError
    end
    function api.onMatch(data)
        if not alive or type(data)~="table" then return end
        local s=ctx.snapshot();syncOpponent(s)
        if (data.Phase=="RAC" or data.Phase=="Run")
            and (data.Carrier==player or data.Carrier==player.Character and data.Carrier~=nil
                or s.carrier==player.Character and s.carrier~=nil) then ownPossessionObserved=true end
        if finite(s.snapAt) then observedSnapAt=s.snapAt end
        if defenseContext(s) then
            if data.Phase=="Result" and data.Result=="Touchdown"
                and (data.Point=="Opp" or data.Point=="Them" or data.ScorerIsYou==false) then
                recordDefense("Touchdown",true)
            elseif data.Phase=="Result" and (data.Result=="Swatted" or data.Result=="Intercepted"
                or data.Result=="Incomplete") then recordDefense(data.Result,false)
            elseif (data.Phase=="RAC" or data.Phase=="Run") and enemyCaught(s,data.Carrier) then
                recordDefense("Catch",true)
            end
        end
        if data.Phase=="PreSnap" or data.Phase=="Pick" or data.Phase=="Lobby" then activeDefense=nil end
        if activeRoute and s.role=="WR" and data.Phase=="Result" then
            -- Fallback when the server's terminal round packet arrives without
            -- the matching BallResult. A later duplicate cannot add twice.
            if data.Result=="Swatted" or data.Result=="Intercepted" or data.Result=="Incomplete" then
                recordOutcome(data.Result,false)
            elseif data.Result=="Touchdown" and (data.Point=="You" or data.ScorerIsYou==true) then
                recordOutcome("Catch",true)
            end
        end
        if s.role=="WR" and (s.mode==nil or s.mode=="1v1") and not s.testing and data.Phase=="Result"
            and data.Result=="Tackled" then
            local key=tostring(s.roundKey or s.preSnapEnds or roundKey or "current")
            -- An adaptive underneath/slant catch may deliberately advance the
            -- next down. Keep that progress separate from a lost point; a
            -- later duplicate without Point must never erase a confirmed loss.
            if activeRoute and activeRoute.roundKey==key then recordOutcome("Catch",true) end
            for i=#recentRoutes,1,-1 do
                local item=recentRoutes[i]
                if item.roundKey==key and (item.catchSuccess==true or item.result=="Catch" and item.success) then
                    local pointLost=item.terminalPointLost==true or data.Point=="Opp"
                        or data.Point=="Them" or data.ScorerIsYou==false
                    local progress=(item.adaptiveUnderneath==true or item.pacedSlant==true) and not pointLost
                    if item.terminalResult~="Tackled" or item.success~=progress
                        or item.terminalPointLost~=pointLost then
                        item.catchSuccess=true;item.success=progress;item.terminalPointLost=pointLost
                        item.terminalResult="Tackled";item.terminalAt=world:GetServerTimeNow()
                        updateSessionHistory()
                        log("routeOutcomeUpdated",descriptor(item))
                    end
                    break
                end
            end
        end
        if data.Phase=="Hike" then counters.rounds=counters.rounds+1 end
        if enabled and data.Phase=="Result" then
            if data.Point=="You" or data.ScorerIsYou==true then counters.pointsWon=counters.pointsWon+1
            elseif data.Point=="Them" or data.Point=="Opp" or data.ScorerIsYou==false then counters.pointsLost=counters.pointsLost+1 end
        end
        if enabled and (data.Phase=="Result" or data.MatchOver==true) then
            -- Keep supplied native scores; missing scores remain absent. A
            -- point, animation or requested action never invents a match win.
            log("result",{result=data.Result,point=data.Point,matchOver=data.MatchOver,
                scorerIsYou=data.ScorerIsYou,phase=data.Phase,role=s.role,mode=s.mode,
                you=finite(data.You) and data.You or nil,
                them=finite(data.Them) and data.Them or nil,
                toWin=finite(data.ToWin) and data.ToWin or nil,
                round=finite(data.Round) and data.Round or nil,
                down=finite(data.Down) and data.Down or nil})
        end
    end
    function api.onFx(data)
        if not alive or type(data)~="table" then return end
        local eventType=data.Type
        if eventType=="Jammed" or eventType=="Blocked" or eventType=="JamHit" or eventType=="JamWhiff" then
            local s=ctx.snapshot()
            local now=world:GetServerTimeNow()
            if s.testing or not finite(now) then return end
            local last=contactFxTimes[eventType]
            if last and now>=last and now-last<.1 then return end
            contactFxTimes[eventType]=now
            local character=player.Character
            local root=rootOf(character)
            local h=character and character:FindFirstChildOfClass("Humanoid")
            local point=root and root.Position
            local speed=h and h.WalkSpeed
            local stamina=tonumber(player:GetAttribute("Stamina"))
            -- These are recipient-local native notifications. Jammed/Blocked
            -- concern this client; JamHit/Whiff do not identify a local victim.
            -- Never copy packet fields, actors, identities or native payloads.
            local roles={WR=true,DB=true,QB=true,TWR=true,TDB=true,TQB=true,RUSH=true,D=true}
            local phases={Lobby=true,PreSnap=true,Pick=true,Hike=true,Live=true,RAC=true,Run=true,Result=true}
            log("nativeContactFx",{eventType=eventType,isLocalVictim=eventType=="Jammed" or eventType=="Blocked",
                role=roles[s.role] and s.role or nil,phase=phases[s.phase] and s.phase or nil,
                position=typeof(point)=="Vector3" and finite(point.X) and finite(point.Y) and finite(point.Z)
                    and coordinates(point) or nil,
                speed=finite(speed) and speed or nil,stamina=finite(stamina) and stamina or nil})
            return
        end
        if eventType~="BallResult" and eventType~="Throw" then return end
        local s=ctx.snapshot();syncOpponent(s)
        if data.Type=="Throw" then
            if activeRoute and s.role=="WR" then freezeCampingObservation() end
            observeDefenseThrow(s,data);return
        end
        if defenseContext(s) then
            if data.Result=="Catch" and enemyCaught(s,data.Catcher) then recordDefense("Catch",true)
            elseif data.Result=="Swatted" or data.Result=="Intercepted" or data.Result=="Incomplete" then
                recordDefense(data.Result,false)
            end
        end
        if not activeRoute or s.role~="WR" or s.mode=="Team" or s.testing then return end
        local result=data.Result
        if result=="Catch" then
            local mine=data.Catcher==player or data.Catcher==player.Character
                or data.Catcher==nil and s.carrier==player.Character
            if mine then recordOutcome(result,true)
            elseif enemyCaught(s,data.Catcher) then recordOutcome(result,false) end
        elseif result=="Swatted" or result=="Intercepted" or result=="Incomplete" then
            recordOutcome(result,false)
        end
    end
    function api.status()
        local snapshot=ctx.snapshot()
        syncOpponent(snapshot)
        local startX=selected and selected.payload.StartX
        local root=rootOf(player.Character)
        local offset=typeof(snapshot.offset)=="Vector3" and snapshot.offset or Vector3.zero
        local startObserved=startX and root and (snapshot.phase=="PreSnap" or snapshot.phase=="Hike")
            and math.abs(root.Position.X-offset.X-startX)<=Field.YD*.5 or false
        return {enabled=enabled,message=message,error=errorMessage,saveError=saveError,
            supportedMode="1v1",policyMode="deterministic",routeCycle=routeCycle,submitted=submitted,
            pass=selected and selected.payload.Pass or nil,startX=startX,startPositionObserved=startObserved,
            counters=table.clone(counters),
            sessionHistory=sessionRecord(),
            defenseProfile=defenseProfile(),activeDefense=defenseDescriptor(activeDefense),
            finalSprintCommitted=finalSprintCommitted,
            observedStartStamina=observedStartStamina,setupAllowanceFraction=.25,
            stemRecoverySpent=stemRecoverySpent,stemRecoveryUntil=stemRecoveryUntil,
            routeWaypoint=routeWaypoint,routeRoundKey=roundIdentity(ctx.snapshot()),
            activeRoute=descriptor(activeRoute)}
    end
    function api.catchIntent()
        -- Core context calls this; never recurse through ctx.snapshot/status.
        local choice=selected or activeRoute
        if not alive or not enabled or not submitted or not activeRoute or not choice then return nil end
        if finite(observedSnapAt) and choice.slowStem==true and finite(choice.slowStemTime)
            and world:GetServerTimeNow()>=observedSnapAt+choice.slowStemTime then
            finalSprintCommitted=true
        end
        local point=routePlan and type(routePlan.Points)=="table" and routePlan.Points[routeWaypoint]
        if typeof(point)~="Vector2" or not finite(point.X) or not finite(point.Y) then point=nil end
        local stage
        local cut=routePlan and routePlan.Points and routePlan.Points[2]
        if (choice.routeStrategy=="deep_middle_floater" or choice.routeStrategy=="deep_middle_bullet") and choice.postThrowStem==true
            and not finalSprintCommitted and finite(observedSnapAt) and finite(choice.cutAt)
            and finite(choice.stemSprintStart) and finite(choice.estimatedCatchAt)
            and typeof(cut)=="Vector2" and world:GetServerTimeNow()<observedSnapAt+choice.cutAt then
            stage={point=cut,untilAt=observedSnapAt+choice.cutAt,
                sprintStartAt=observedSnapAt+choice.stemSprintStart,
                contactAt=observedSnapAt+choice.estimatedCatchAt,reserve=10,
                sprintDrain=Config.SprintDrain or 25,finalSprintSeconds=choice.finalSprintDuration,
                plannedStemSprintSeconds=choice.stemSprintSeconds}
            stage.stemRunSpeed=choice.stemRunSpeed
            if stemRecoveryUntil>world:GetServerTimeNow()-observedSnapAt then
                stage.recoveryUntilAt=observedSnapAt+stemRecoveryUntil
            end
        end
        return {deepFinish=choice.middleStemDeep==true,side=choice.side,waypoint=point,goalZ=Field.GoalZ,endZ=Field.EndZ,
            routeStrategy=choice.routeStrategy,
            postThrowStem=stage,
            pass=selected and selected.payload.Pass or activeRoute.pass,
            continuousBulletCatch=choice.rareCampingBullet==true and choice.continuousBulletCatch==true
                and (selected and selected.payload.Pass or activeRoute.pass)=="Bullet",
            requireAirborne=true,requireDive=choice.requireDive==true,preferAirborne=true,
            preferJumpDive=choice.preferJumpDive==true,
            continuousSprint=finalSprintCommitted,finalSprint=finalSprintCommitted}
    end
    function api.movementBudget(committedPursuit)
        if not alive or not enabled then return nil end
        -- Called while the core builds its snapshot: never recurse into it.
        -- A rare short Bullet reserves one actual native carrier move until
        -- confirmed possession; normal carrier decisions may then spend it.
        local choice=selected or activeRoute
        local reserve=10
        if activeRoute and not ownPossessionObserved and choice and choice.rareCampingBullet==true
            and (selected and selected.payload.Pass or activeRoute.pass)=="Bullet"
            and finite(choice.carryReserve) and choice.carryReserve>=10
            and choice.carryReserve<=(Config.Stamina or 100) then reserve=choice.carryReserve end
        return {dbReserve=committedPursuit==true and 2 or 40,wrReserve=reserve}
    end
    function api.unload()
        if not alive then return end
        clearCampingEvidence()
        alive=false;connection:Disconnect()
        if ctx.release then ctx.release() end
    end
    return api
end

end)()
local createMatchSkip = (function()
-- Rejoin the verified public place only for an exact, current enemy account.
-- Queue cancellation cannot leave a match; this controller owns no queue remote.
return function(ctx,services)
    services=services or {}
    local Players=services.players or game:GetService("Players")
    local player=services.player or Players.LocalPlayer
    local TeleportService=services.teleportService or game:GetService("TeleportService")
    local RunService=services.runService or game:GetService("RunService")
    local Http=services.http or game:GetService("HttpService")
    local now=services.now or function() return workspace:GetServerTimeNow() end
    local gameId=services.gameId or game.GameId
    local placeId=services.placeId or game.PlaceId
    local jobId=services.jobId or game.JobId
    local function optional(key,fallback)
        if services[key]~=nil then return services[key] end
        return fallback
    end
    local read,write,exists=optional("read",readfile),optional("write",writefile),optional("exists",isfile)
    local SettingsFile="ciu_deterministic_match_skip_v1.json"
    local GameId,PlaceId=10770281752,116097127629859
    local activePhases={Pick=true,PreSnap=true,Hike=true,Live=true,RAC=true,Run=true}
    local roles={WR=true,DB=true,QB=true}
    local alive,editing=true,false
    local connections={}
    local enabled,usernames,username=false,{},""
    local managed,preferredEnabled=ctx.preferencesManaged==true,nil
    local configured={}
    local saveError,loadError,lastSaved,message,lastError
    local requestState,attempts="idle",0
    local pendingSince,nextRetryAt,requestedUsername,matchedUsername,matchedUserId,blockedReason
    local api={}

    local function cleanUsername(value)
        if type(value)~="string" then return nil,"Enter a Roblox username" end
        value=string.match(value,"^%s*(.-)%s*$")
        if string.sub(value,1,1)=="@" then value=string.sub(value,2) end
        if value=="" then return "" end
        if #value<3 or #value>20 or not string.match(value,"^[A-Za-z0-9_]+$") then
            return nil,"Use 3–20 letters, numbers, or underscores"
        end
        return value
    end
    local function cleanList(value)
        if type(value)~="string" then return nil,"Enter Roblox usernames separated by commas or spaces" end
        local result,seen={},{}
        for token in string.gmatch(value,"[^,;%s]+") do
            local name,reason=cleanUsername(token)
            if name==nil or name=="" then return nil,reason or "Each entry must contain a Roblox username" end
            local key=string.lower(name)
            if not seen[key] then result[#result+1]=name;seen[key]=true end
        end
        return result
    end
    local function cleanArray(value)
        if type(value)~="table" then return nil end
        local count=0
        for key in pairs(value) do
            if type(key)~="number" or key<1 or key%1~=0 then return nil end
            count=count+1
        end
        local result,seen={},{}
        for i=1,count do
            local name=cleanUsername(value[i])
            if name==nil or name=="" then return nil end
            local key=string.lower(name)
            if not seen[key] then result[#result+1]=name;seen[key]=true end
        end
        return result
    end
    local function useNames(value)
        usernames,configured={},{}
        for _,name in ipairs(value) do
            usernames[#usernames+1]=name
            configured[string.lower(name)]=true
        end
        username=table.concat(usernames,", ")
    end
    local function waitingMessage()
        if #usernames==0 then return "Enter a username to skip" end
        return #usernames==1 and "Waiting for @"..usernames[1] or "Waiting for a listed opponent"
    end
    local function validSettings(value)
        if type(value)~="table" or type(value.enabled)~="boolean" then return nil end
        local names
        if value.version==1 then
            local name=cleanUsername(value.username)
            if name==nil then return nil end
            names=name~="" and {name} or {}
        elseif value.version==2 then names=cleanArray(value.usernames)
        else return nil end
        if not names then return nil end
        return {version=value.version,enabled=value.enabled,usernames=names}
    end
    local previous=type(ctx.previousState)=="table" and ctx.previousState or nil
    local sameJob=previous and previous.jobId==jobId
    local previousSettings=previous and validSettings({version=previous.usernames~=nil and 2 or 1,
        enabled=previous.enabled,username=previous.username,usernames=previous.usernames})
    local function save()
        local savedEnabled=enabled
        if managed and preferredEnabled~=nil then savedEnabled=preferredEnabled end
        local fingerprint=tostring(savedEnabled)..":"..username
        if lastSaved==fingerprint and not saveError then return true end
        if type(write)~="function" then saveError="Saving match skip settings is unavailable";return false end
        local ok,err=pcall(function()
            write(SettingsFile,Http:JSONEncode({version=2,enabled=savedEnabled,usernames=usernames}))
            if type(read)=="function" then
                local saved=validSettings(Http:JSONDecode(read(SettingsFile)))
                assert(saved and saved.version==2 and saved.enabled==savedEnabled
                    and table.concat(saved.usernames,", ")==username,"Settings readback did not match")
            end
        end)
        if not ok then saveError=tostring(err);return false end
        lastSaved,saveError,loadError=fingerprint,nil,nil
        return true
    end
    local missing=false
    local settings
    if type(exists)=="function" then
        local ok,present=pcall(exists,SettingsFile)
        if ok and present==false then missing=true
        elseif not ok then loadError="Could not check saved match skip settings: "..tostring(present) end
    end
    if not missing and not loadError then
        if type(read)~="function" then loadError="Reading match skip settings is unavailable"
        else
            local ok,value=pcall(function() return Http:JSONDecode(read(SettingsFile)) end)
            if ok then
                settings=validSettings(value)
                if not settings then loadError="Saved match skip settings are invalid" end
            elseif type(exists)~="function" and (string.find(string.lower(tostring(value)),"no such file",1,true)
                or string.find(string.lower(tostring(value)),"file not found",1,true)
                or string.find(string.lower(tostring(value)),"does not exist",1,true)) then
                missing=true
            else loadError="Could not read match skip settings: "..tostring(value) end
        end
    end
    -- A failed prior save must retain the user's current choice across a reload.
    -- Corrupt/unreadable preferences never silently enable the initial target.
    if sameJob and previousSettings and type(previous.saveError)=="string" then
        enabled=previousSettings.enabled;useNames(previousSettings.usernames)
        saveError=previous.saveError
        save()
    elseif settings then
        enabled=settings.enabled;useNames(settings.usernames)
        if settings.version==1 then save() else lastSaved=tostring(enabled)..":"..username end
    elseif sameJob and previousSettings then
        enabled=previousSettings.enabled;useNames(previousSettings.usernames)
        saveError=loadError
        if missing then save() end
    elseif missing then
        enabled=not managed;useNames({"stupieddaniel"})
        save()
    else saveError=loadError end

    preferredEnabled=enabled
    if ctx.startDisabled==true then
        enabled=false
        if not managed then save() end
    end

    local function finite(value)
        return type(value)=="number" and value==value and math.abs(value)<math.huge
    end
    if sameJob and (ctx.startDisabled~=true or managed) then
        attempts=finite(previous.attempts) and math.max(0,math.min(3,math.floor(previous.attempts))) or 0
        if attempts>0 then
            requestedUsername=cleanUsername(previous.requestedUsername)
            if requestedUsername then requestedUsername=string.lower(requestedUsername) end
            matchedUsername=type(previous.matchedUsername)=="string" and previous.matchedUsername or nil
            matchedUserId=type(previous.matchedUserId)=="number" and previous.matchedUserId or nil
            lastError=type(previous.error)=="string" and previous.error or nil
            blockedReason=type(previous.blockedReason)=="string" and previous.blockedReason or nil
            if previous.requestState=="pending" and finite(previous.pendingSince) then
                requestState,pendingSince="pending",previous.pendingSince
            elseif previous.requestState=="retry" and attempts<3 and finite(previous.nextRetryAt) then
                requestState,nextRetryAt="retry",previous.nextRetryAt
            else
                requestState="blocked"
                blockedReason=blockedReason or "Previous rejoin request already handled"
            end
        end
    end

    local function match(s,requested)
        if gameId~=GameId or placeId~=PlaceId then return nil,"Available in the verified Chalk It Up place only" end
        if not enabled then return nil,"Match skip off" end
        if #usernames==0 then return nil,"Enter a username to skip" end
        if editing then return nil,"Editing match skip usernames" end
        if type(s)~="table" or s.alive==false then return nil,"Waiting for the match" end
        if s.enabled==false then return nil,"Match skip · assist is off" end
        if s.testing then return nil,"Match skip · paused for test" end
        if s.mode~=nil and s.mode~="1v1" and s.mode~="Team" then return nil,"Waiting for a supported match" end
        local activeRole=roles[s.role] or s.mode=="Team" and s.role=="O"
        if not activePhases[s.phase] or not activeRole then return nil,"Waiting for an active match" end
        if s.matchIdentityVerified~=true or s.modeSource=="unconfirmed" or s.modeSource=="lobby" then
            return nil,"Waiting for a verified opponent"
        end
        local function resolve(character)
            if not character or character==player.Character then return nil end
            local ok,enemy=pcall(function() return Players:GetPlayerFromCharacter(character) end)
            if not ok or not enemy or enemy==player or enemy.Character~=character then return nil end
            if type(enemy.Name)=="string" then
                local key=string.lower(enemy.Name)
                if configured[key] and (not requested or key==requested) then return enemy end
            end
        end
        -- Team opponents is the trusted enemy roster; its cached single
        -- receiver can belong to an earlier play and must never be a fallback.
        if type(s.opponents)=="table" then
            for _,character in ipairs(s.opponents) do
                local enemy=resolve(character)
                if enemy then return enemy end
            end
        end
        if s.mode~="Team" then
            local enemy=resolve(s.opponent)
            if enemy then return enemy end
        end
        return nil,waitingMessage()
    end
    local function block(reason)
        requestState,blockedReason="blocked",reason
        pendingSince,nextRetryAt=nil,nil
        message="Match skip · "..reason
    end
    local function failed(reason)
        if not alive or requestState~="pending" then return end
        lastError=tostring(reason)
        pendingSince=nil
        if not enabled then block("Rejoin failed; retries stopped while off")
        elseif not configured[requestedUsername] then block("Original opponent removed; retry cancelled")
        elseif attempts>=3 then block("Rejoin failed after 3 attempts")
        else
            requestState="retry"
            nextRetryAt=now()+(attempts==1 and 5 or 10)
            message="Rejoin failed · retry "..(attempts+1).." of 3 scheduled"
        end
    end
    local function request(enemy)
        if not alive or requestState=="pending" or attempts>=3 then return end
        attempts=attempts+1
        requestedUsername=requestedUsername or string.lower(enemy.Name)
        matchedUsername,matchedUserId=enemy.Name,enemy.UserId
        requestState,pendingSince,nextRetryAt="pending",now(),nil
        blockedReason,lastError=nil,nil
        message="Skipping @"..enemy.Name.." · rejoining public lobby"
        -- Mark pending first: synchronous failure callbacks cannot double-send.
        local ok,err=pcall(function() TeleportService:Teleport(PlaceId,player) end)
        if not ok then failed(err) end
    end
    local function tick()
        if not alive then return end
        if requestState=="pending" then
            if now()-pendingSince>=20 then block("Rejoin timed out; no duplicate request sent") end
            return
        end
        if requestState=="blocked" then
            message="Match skip · "..(blockedReason or "Rejoin already requested")
            return
        end
        local enemy,reason=match(ctx.snapshot(),requestState=="retry" and requestedUsername or nil)
        if requestState=="retry" then
            if not enabled then block("Retries stopped while off");return end
            if not configured[requestedUsername] then block("Original opponent removed; retry cancelled");return end
            if editing then message=reason;return end
            if now()<nextRetryAt then return end
            if not enemy or (matchedUserId and enemy.UserId~=matchedUserId) then
                block("Opponent or match changed; retry cancelled")
                return
            end
        end
        if enemy then request(enemy) else message=reason end
    end
    function api.status()
        local names={};for _,name in ipairs(usernames) do names[#names+1]=name end
        return {enabled=enabled,usernames=names,username=username,displayText=username,editing=editing,alive=alive,message=message,
            saveError=saveError,loadError=loadError,error=lastError,attempts=attempts,jobId=jobId,
            placeId=PlaceId,requestState=requestState,pending=requestState=="pending",
            pendingSince=pendingSince,nextRetryAt=nextRetryAt,requestedUsername=requestedUsername,
            matchedUsername=matchedUsername,matchedUserId=matchedUserId,blockedReason=blockedReason}
    end
    function api.setEnabled(value)
        if not alive then return false,"Match skip is unloaded" end
        if type(value)~="boolean" then return false,"Enabled must be true or false" end
        enabled=value
        if managed then preferredEnabled=value end
        if not enabled and requestState=="retry" then block("Retries stopped while off") end
        if requestState=="idle" then message=enabled and "Waiting for an active match" or "Match skip off" end
        save()
        return true,saveError
    end
    function api.setUsernames(value)
        if not alive then return false,"Match skip is unloaded" end
        local cleaned,reason=cleanList(value)
        if cleaned==nil then return false,reason end
        useNames(cleaned)
        if requestState=="retry" and not configured[requestedUsername] then
            block("Original opponent removed; retry cancelled")
        end
        if requestState=="idle" then message=waitingMessage() end
        save()
        return true,saveError
    end
    api.setUsername=api.setUsernames
    function api.setEditing(value)
        if not alive then return false,"Match skip is unloaded" end
        if type(value)~="boolean" then return false,"Editing must be true or false" end
        editing=value
        if editing and requestState=="idle" then message="Editing match skip usernames" end
        return true
    end
    function api.unload()
        if not alive then return end
        alive=false
        for _,connection in ipairs(connections) do connection:Disconnect() end
        -- Do not clear dedupe: status is the same-job reload handoff.
    end
    connections[#connections+1]=TeleportService.TeleportInitFailed:Connect(function(failedPlayer,result,reason,placeId)
        if alive and failedPlayer==player and placeId==PlaceId then
            failed(tostring(result)..": "..tostring(reason))
        end
    end)
    local accumulator=0
    connections[#connections+1]=RunService.Heartbeat:Connect(function(dt)
        if not alive then return end
        accumulator=accumulator+dt
        if accumulator<0.25 then return end
        accumulator=0
        local ok,err=pcall(tick)
        if not ok then lastError=tostring(err);message="Match skip paused · "..lastError end
    end)
    message=requestState=="pending" and "Rejoin already requested · waiting"
        or requestState=="retry" and "Rejoin retry scheduled"
        or requestState=="blocked" and ("Match skip · "..blockedReason)
        or not enabled and "Match skip off"
        or waitingMessage()
    return api
end

end)()
local createSessionContinuity = (function()
-- One-hop client-session handoff. No files, learned state, or enabled preferences.
-- Teleport settings expire when the client leaves this Roblox universe.
return function(ctx,services)
    ctx=ctx or {};services=services or {}
    local runtime=services.game or game
    local originJob=runtime.JobId
    local now=services.now or os.time
    local settingKey="ChalkDeterministicSessionV1"
    local entry=type(ctx.entry)=="table" and ctx.entry or {}
    local automatic=entry.entryKind=="autoexec" or entry.entryKind=="teleport"
    local supported=runtime.GameId==10770281752 and runtime.PlaceId==116097127629859
    local alive,untouched,applying=true,true,false
    local ownedMatch,outbound,completed=false,nil,false
    local status={available=false,resumed=false,message="Saved settings control automation"}
    local transport=services.teleport
    if not transport then pcall(function() transport=runtime:GetService("TeleportService") end) end
    local function text(v) return type(v)=="string" and #v>0 and #v<=128 end
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
    local function read()
        if not supported or not transport then return nil end
        local ok,v=pcall(function() return transport:GetTeleportSetting(settingKey) end)
        if not ok then status.message="Session handoff unavailable";return nil end
        return v
    end
    local function write(v)
        if not supported or not transport then return false end
        local ok=pcall(function() transport:SetTeleportSetting(settingKey,v) end)
        status.available=ok
        if not ok then status.message="Session handoff unavailable" end
        return ok
    end
    local function snapshot()
        local ok,s=pcall(ctx.snapshot)
        if not ok or type(s)~="table" then return nil end
        return s
    end
    local function eligible(s)
        return s and s.enabled==true and s.autoplay==true and text(s.selectedMode)
            and s.modeAvailable==true and s.testing~=true and s.alive~=false
    end
    local function revoke(reason)
        outbound=nil
        local revoked=write(false)
        status.revocationFailed=not revoked
        status.message=revoked and (reason or "Session continuation cancelled")
            or "Session cancellation failed; automation may resume after teleport"
    end
    local function arm(kind)
        local s=snapshot()
        if not alive or not eligible(s) then revoke();return false end
        local t=now()
        if not finite(t) then revoke();return false end
        local nonce
        if type(services.uuid)=="function" then nonce=services.uuid()
        else pcall(function() nonce=runtime:GetService("HttpService"):GenerateGUID(false) end) end
        if not text(nonce) then revoke("Session token unavailable");return false end
        outbound={schemaVersion=1,nonce=nonce,sourceJob=originJob,
            gameId=runtime.GameId,placeId=runtime.PlaceId,issuedAt=t,expiresAt=t+120,
            destination=kind,fullAuto=s.fullAuto==true,autoplay=true,selectedMode=s.selectedMode}
        if not write(outbound) then outbound=nil;return false end
        status.revocationFailed=false
        status.message="Session continuation ready for "..kind
        return true
    end
    local api={}
    function api.refresh()
        if not alive or applying then return end
        local s=snapshot()
        if not eligible(s) then
            if outbound or ownedMatch then ownedMatch=false;completed=false;revoke() end
            return
        end
        if not outbound then return end
        -- Never extend an old handoff simply because a heartbeat ran.
        if now()>outbound.expiresAt then revoke("Session continuation expired");return end
        outbound.fullAuto=s.fullAuto==true;outbound.selectedMode=s.selectedMode
        if not write(outbound) then outbound=nil end
    end
    function api.onChoice(kind,value)
        if not alive or applying then return end
        untouched=false
        if kind=="master" and value~=true or kind=="autoplay" and value~=true
            or kind=="assist" and value~=true then
            ownedMatch=false;completed=false;revoke();return
        end
        api.refresh()
    end
    function api.onQueue(packet,before)
        if not alive or type(packet)~="table" or type(before)~="table" then return end
        if packet.Status=="Found" and before.enabled==true and before.owned==true
            and before.pending~="Leave" and before.cancelWanted~=true
            and text(before.queuedMode) and (packet.Mode==nil or packet.Mode==before.queuedMode) then
            ownedMatch=false;completed=false;arm("match")
        elseif packet.Status=="Idle" or packet.Status=="Error" then
            -- A pending outbound match handoff cannot survive cancellation.
            if outbound and outbound.destination=="match" then revoke("Queue handoff cancelled") end
        elseif packet.Status=="Leaving" and ownedMatch and completed then
            arm("lobby")
        end
    end
    function api.onMatch(data)
        if not alive or type(data)~="table" then return end
        local s=snapshot()
        if s and s.testing then return end
        if ownedMatch and not completed and data.MatchOver==true then
            completed=true;arm("lobby")
        end
    end
    function api.onTeleport(state,placeId)
        if not alive then return end
        if placeId~=nil and placeId~=runtime.PlaceId then
            ownedMatch=false;completed=false;revoke("Unrelated destination");return
        end
        local name=tostring(state):match("([^%.]+)$")
        if name=="Failed" or name=="Cancelled" then
            ownedMatch=false;completed=false;revoke("Teleport did not complete")
        elseif name=="Started" or name=="InProgress" then
            -- An owned match can be aborted before any round or MatchOver.
            -- Only its explicit same-place teleport may create this return
            -- lease; the destination must still prove it is a lobby.
            if ownedMatch and not outbound and placeId==runtime.PlaceId then
                local s=snapshot()
                if eligible(s) and s.matchServer==true then arm("lobby") end
            end
            api.refresh()
        end
    end
    function api.resume(sourceJob)
        if not alive or not automatic or not untouched or status.resumed
            or not text(sourceJob) or sourceJob==originJob then return false end
        local v=read();local s=snapshot();local t=now()
        local valid=type(v)=="table" and v.schemaVersion==1 and text(v.nonce)
            and v.sourceJob==sourceJob and v.gameId==runtime.GameId and v.placeId==runtime.PlaceId
            and finite(v.issuedAt) and finite(v.expiresAt) and finite(t)
            and v.issuedAt<=t+2 and v.expiresAt>=t and v.expiresAt-v.issuedAt==120
            and type(v.fullAuto)=="boolean" and v.autoplay==true and text(v.selectedMode)
            and (v.destination=="match" or v.destination=="lobby")
            and s and s.alive~=false and s.testing~=true
            and type(s.matchServer)=="boolean"
            and ((v.destination=="match") == s.matchServer)
        if not valid then
            if type(v)=="table" and v.sourceJob==sourceJob then revoke("No valid session handoff")
            else status.message="No valid session handoff" end
            return false
        end
        local good,allowed=pcall(ctx.modeAvailable,v.selectedMode)
        if not good or allowed~=true then revoke("Previous queue mode is unavailable");return false end
        if type(ctx.canResume)=="function" then
            local checked,accepted=pcall(ctx.canResume,v)
            if not checked or accepted~=true then revoke("Saved settings take priority over session handoff");return false end
        end
        -- If consumption cannot be recorded, do not enable anything.
        if not write(false) then return false end
        applying=true
        local ok,result=pcall(ctx.apply,v.fullAuto,v.selectedMode)
        applying=false;untouched=false
        if not ok or result~=true then
            if type(ctx.stop)=="function" then pcall(ctx.stop) end
            status.message="Session handoff could not be applied";return false
        end
        ownedMatch=v.destination=="match";completed=false
        status.resumed=true;status.message="Continued this play session"
        return true
    end
    function api.cancel(reason)
        untouched=false;ownedMatch=false;completed=false;revoke(reason)
    end
    function api.status()
        return {available=status.available,resumed=status.resumed,ownedMatch=ownedMatch,
            revocationFailed=status.revocationFailed==true,
            armed=outbound~=nil,destination=outbound and outbound.destination or nil,message=status.message}
    end
    function api.unload(automaticDestinationJob)
        if not alive then return end
        if text(automaticDestinationJob) and automaticDestinationJob~=originJob then
            -- An inherited old API may be disposed by automatic startup in
            -- the next job. Its one-hop handoff belongs to that destination.
            alive=false;outbound=nil;return
        end
        api.cancel("Session continuation cancelled by unload");alive=false
    end
    if not automatic then revoke("Manual launch · previous handoff cleared") end
    return api
end

end)()
local createAutoload = (function()
-- Portable teleport registration; never attaches an executor or installs OS files.
-- ctx.bootstrapSource is embedded by the builder from chalk-bootstrap.lua.
return function(ctx,services)
    ctx=ctx or {};services=services or {}
    local runtimeGame=services.game or game
    local env=services.env or (type(getgenv)=="function" and getgenv() or _G)
    local global=services.globals or env
    local GAME_ID,PLACE_ID=10770281752,116097127629859
    local BOOT,QUEUE="__ChalkDeterministicAutoBoot","__ChalkDeterministicTeleportQueue"
    local alive=true
    local connection
    local retried=false
    local status={supported=false,queued=false,queueAvailable=false,attempts=0,
        message="Executor attachment is required; use its autoexec option for fresh launches."}
    local function sameJob(value)
        return type(value)=="table" and value.gameId==runtimeGame.GameId
            and value.placeId==runtimeGame.PlaceId and value.jobId==runtimeGame.JobId
    end
    local function identity(state)
        return {gameId=runtimeGame.GameId,placeId=runtimeGame.PlaceId,jobId=runtimeGame.JobId,state=state}
    end
    local function candidates()
        local result,seen={},{}
        local function add(value,name)
            if type(value)=="function" and not seen[value] then
                seen[value]=true;result[#result+1]={fn=value,name=name}
            end
        end
        add(global.queue_on_teleport or queue_on_teleport,"queue_on_teleport")
        add(global.queueonteleport or queueonteleport,"queueonteleport")
        local nativeSyn=global.syn or syn
        add(type(nativeSyn)=="table" and nativeSyn.queue_on_teleport,"syn.queue_on_teleport")
        return result
    end
    local function queue()
        if not alive or not status.supported then return false end
        if sameJob(env[QUEUE]) and env[QUEUE].queued and env[QUEUE].sessionProtocol==1 then
            status.queued=true;status.queueAvailable=true
            status.message="Automatic loading is queued for the next teleport."
            return true
        end
        local choices=candidates()
        status.queueAvailable=#choices>0
        if #choices==0 then
            status.message="This executor has no teleport queue; use its autoexec folder for automatic loading."
            return false
        end
        if type(ctx.bootstrapSource)~="string" or ctx.bootstrapSource=="" then
            status.message="Automatic loader source is missing from this build."
            return false
        end
        local payload="(function(...)\n"..ctx.bootstrapSource.."\nend)({automatic=true,teleportSourceJob="
            ..string.format("%q",runtimeGame.JobId).."})"
        for _,choice in ipairs(choices) do
            status.attempts=status.attempts+1
            local ok,result=pcall(choice.fn,payload)
            if ok and result~=false then
                local marker=identity("queued");marker.queued=true;marker.sessionProtocol=1
                env[QUEUE]=marker
                status.queued=true;status.provider=choice.name
                status.message="Automatic loading is queued for the next teleport."
                return true
            end
        end
        status.message="The executor rejected the teleport queue; one retry is allowed when teleporting."
        return false
    end
    local api={}
    function api.status()
        local copy={};for key,value in pairs(status) do copy[key]=value end
        return copy
    end
    function api.unload(preserve)
        if not alive then return end
        alive=false
        if connection then connection:Disconnect();connection=nil end
        if preserve~=true and status.supported and sameJob(env[BOOT]) then env[BOOT].state="unloaded" end
        -- A successful executor queue cannot generally be revoked. It only
        -- runs after a future teleport; same-job automatic restarts stay blocked.
    end
    if runtimeGame.GameId~=GAME_ID or runtimeGame.PlaceId~=PLACE_ID then
        status.message="Automatic loading is limited to the supported Chalk It Up place."
        return api
    end
    status.supported=true
    local boot=env[BOOT]
    if sameJob(boot) then boot.state="loaded" else env[BOOT]=identity("loaded") end
    queue()
    local connected=pcall(function()
        local me=services.player or runtimeGame:GetService("Players").LocalPlayer
        if not me or not me.OnTeleport then return end
        connection=me.OnTeleport:Connect(function(state,placeId)
            if not alive then return end
            if type(ctx.onTeleport)=="function" then pcall(ctx.onTeleport,state,placeId) end
            if status.queued or retried then return end
            local name=tostring(state)
            if name=="Started" or name=="InProgress" or name:match("%.Started$") or name:match("%.InProgress$") then
                retried=true;queue()
            end
        end)
    end)
    status.retryCallback=connected and connection~=nil
    return api
end

end)()

api.initializePreferences(createPreferences)
assist = createAssist({snapshot=api.context,version=RELEASE_VERSION,buildId="965226d3d58be1a6d2168b13b5f3dd176906cc9c236d5e74008f986a008b3d9f",fullplay=function(s,root,h,now,dt)
    if fullplay then return fullplay.navigate(s,root,h,now,dt) end
end},Planner,createTackle,WRApproach,Motion,createCarrierMoves,PlayerAvoidance)
assist.setEnabled(false)
autoplay = createAutoplay({snapshot=api.context,startDisabled=true,preferencesManaged=true,
    previousState=previousState and previousState.autoplay,
    onQueue=function(packet,before)
        if sessionContinuity then sessionContinuity.onQueue(packet,before) end
    end,
    onStateChanged=function()
        if sessionContinuity then sessionContinuity.refresh() end
    end},AutoplayPolicy)
repeatWR = createWRRepeat({snapshot=api.context,
    autoplay=function() return autoplay.status() end,
    disableAutoplay=function() return api.setAutoplay(false) end})
repeatWR.setEnabled(false)
fullplay = createFullplay({Planner=Planner,snapshot=api.context,version=RELEASE_VERSION,buildId="965226d3d58be1a6d2168b13b5f3dd176906cc9c236d5e74008f986a008b3d9f",
    assistEnabled=function() return assist.status().enabled end,
    release=function() if assist.releaseFullplay then assist.releaseFullplay() end end},FullplayPolicy)
matchSkip = createMatchSkip({snapshot=api.context,startDisabled=true,preferencesManaged=true,
    previousState=previousState and previousState.matchSkip})
-- Idle protection sends input. Start it only after the user enables gameplay.
function api.updateIdleGuard()
    local active = alive and enabled and (
        assist.status().enabled or fullplay.status().enabled
        or autoplay.status().enabled or repeatWR.status().enabled)
    if active and not idleGuard then idleGuard=createIdleGuard()
    elseif not active and idleGuard then idleGuard.unload();idleGuard=nil end
end
api.restorePreferences()
api.initializeSessionContinuity(createSessionContinuity)
autoload = createAutoload({bootstrapSource=[====[-- Portable Chalk Assist startup. Executor attachment is still required.
-- Automatic callers pass {automatic=true}; a manual run can restart after F8.
local options=(...)
options=type(options)=="table" and options or {}
local GAME_ID,PLACE_ID=10770281752,116097127629859
local MAIN_URL="https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua"
local CACHE_FILE="chalk-deterministic-cache.lua"
local MAIN_FILE="chalk-it-up-1v1.lua"
local MIN_RELEASE="5.1.18"
local MARKER="__ChalkDeterministicAutoBoot"
local env=type(getgenv)=="function" and getgenv() or _G
local boot
local deadline=os.clock()+90
local teleportSource=options.automatic==true and type(options.teleportSourceJob)=="string"
    and #options.teleportSourceJob>0 and #options.teleportSourceJob<=128 and options.teleportSourceJob or nil
local function revokeHandoff()
    pcall(function() game:GetService("TeleportService"):SetTeleportSetting("ChalkDeterministicSessionV1",false) end)
end
local function report(message)
    if type(writefile)=="function" then pcall(writefile,"ciu_autoload_status.txt",message) end
end
local function running()
    local api=env.ChalkDB
    if type(api)~="table" or type(api.status)~="function" then return false end
    if type(api.context)=="function" then
        local good,current=pcall(api.context)
        if good and type(current)=="table" and current.jobId and current.jobId~=game.JobId then return false end
    end
    local ok,s=pcall(api.status)
    return ok and type(s)=="table" and type(s.auto)=="table" and s.product=="deterministic"
end
local function sameJob(value)
    return type(value)=="table" and value.gameId==game.GameId
        and value.placeId==game.PlaceId and value.jobId==game.JobId
end
local function settleRunning()
    if not running() then return false end
    local api=env.ChalkDB
    if teleportSource and type(api.resumeTeleportSession)=="function" then
        local ready,s=pcall(api.status)
        if not ready or type(s)~="table" or type(s.sessionContinuity)~="table" then return false end
        pcall(api.resumeTeleportSession,teleportSource)
    elseif options.automatic~=true then
        if type(api.cancelTeleportSession)=="function" then pcall(api.cancelTeleportSession,"Manual reload") end
        for _,name in ipairs({"setFullplay","setAuto","setAutoplay"}) do
            if type(api[name])=="function" then pcall(api[name],false) end
        end
    end
    return true
end
local function interrupted()
    if env[MARKER]~=boot then return "superseded" end
    if boot.state=="unloaded" then return "unloaded" end
    if settleRunning() then boot.state="loaded";return "already-running" end
end
local function waitFor(read,name)
    repeat
        local value=read()
        if value then return value end
        if os.clock()>=deadline then error("Timed out waiting for "..name,0) end
        task.wait(.1)
    until false
end
local function child(parent,name)
    return waitFor(function() return parent:FindFirstChild(name) end,name)
end
local function release(value)
    if type(value)~="string" then return end
    local a,b,c=value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then return end
    local parts={a,b,c}
    for i,part in ipairs(parts) do
        if #part>6 or (#part>1 and part:sub(1,1)=="0") then return end
        parts[i]=tonumber(part)
    end
    return parts
end
local function compare(a,b)
    for i=1,3 do
        if a[i]~=b[i] then return a[i]>b[i] and 1 or -1 end
    end
    return 0
end
local function sourceRelease(source)
    if type(source)~="string" or #source==0 or #source>2*1024*1024 then return end
    -- The builder stamps the first line. Do not accept an unversioned or
    -- malformed CDN response as a replacement for an installed release.
    return release(source:match("^%-%- Chalk%-Release: ([^\r\n]+)\r?\n%-%- Chalk%-Product: deterministic\r?\n"))
end
local function compile(source)
    local ok,chunk=pcall(loadstring,source,"Chalk Assist")
    if ok and type(chunk)=="function" then return chunk end
end
local function download()
    -- A new join should revalidate the public build instead of reusing an
    -- executor's in-process URL cache. No installation identity is sent.
    local url=MAIN_URL.."?chalk_boot="..tostring(os.time())
    local available,httpGet=pcall(function() return game.HttpGet end)
    if available and type(httpGet)=="function" then
        local ok,body=pcall(httpGet,game,url)
        if ok and type(body)=="string" then return body end
    end
    local send=type(request)=="function" and request
        or type(http_request)=="function" and http_request
        or type(syn)=="table" and type(syn.request)=="function" and syn.request
    if send then
        local ok,response=pcall(send,{Url=url,Method="GET",Headers={["Cache-Control"]="no-cache"}})
        if ok and type(response)=="table" and tonumber(response.StatusCode)==200 then return response.Body end
    end
end
local ok,result=pcall(function()
    waitFor(function() return game:IsLoaded() end,"Roblox")
    if game.GameId~=GAME_ID or game.PlaceId~=PLACE_ID then
        if teleportSource then revokeHandoff() end
        return "unsupported-game"
    end
    if options.automatic~=true then revokeHandoff() end
    local previous=env[MARKER]
    if sameJob(previous) then
        if previous.state=="waiting" or previous.state=="starting" then
            if teleportSource then
                -- Local autoexec may win the loading race. Wait for its OFF
                -- runtime, then let that runtime validate the one-hop lease.
                repeat
                    if settleRunning() then return "already-running" end
                    local current=env[MARKER]
                    if sameJob(current) and current.state=="unloaded" then return "already-started" end
                    task.wait(.1)
                until os.clock()>=deadline
            end
            return "already-starting"
        end
        if settleRunning() then return "already-running" end
        if options.automatic then return "already-started" end -- F8 stays unloaded in this server.
    elseif previous==nil and settleRunning() then
        env[MARKER]={gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,state="loaded"}
        return "already-running"
    end
    boot={gameId=game.GameId,placeId=game.PlaceId,jobId=game.JobId,state="waiting"}
    env[MARKER]=boot
    local me=waitFor(function() return game:GetService("Players").LocalPlayer end,"LocalPlayer")
    child(me,"PlayerGui")
    local moves=child(child(child(me,"PlayerScripts"),"Game"),"Moves")
    assert(moves:IsA("ModuleScript"),"Game.Moves is unavailable")
    local rs=game:GetService("ReplicatedStorage")
    local shared=child(rs,"Shared")
    for _,name in ipairs({"Config","Field","DivePath"}) do child(shared,name) end
    local remotes=child(rs,"Remotes")
    child(remotes,"Match");child(remotes,"Fx")
    local field=child(child(workspace,"Fields"),"Field1")
    local lines=child(field,"Lines")
    for _,name in ipairs({"Sideline_L","Sideline_R","BackLine","EndLine","GoalLine"}) do child(lines,name) end
    child(field,"Endzone")
    local stopped=interrupted()
    if stopped then return stopped end
    assert(type(loadstring)=="function","Executor loadstring is unavailable")
    local minimum=assert(release(MIN_RELEASE),"Bootstrap release metadata is unavailable")
    local source=download()
    local chunk,downloaded
    local floor=minimum
    local localSource,localChunk
    -- Read both candidates after HTTP returns: a manual update may have
    -- installed a newer release while the network request was in flight.
    if type(readfile)=="function" then
        for _,path in ipairs({CACHE_FILE,MAIN_FILE}) do
            local readOK,cached=pcall(readfile,path)
            if readOK then
                local version=sourceRelease(cached)
                if version and compare(version,floor)>=0 then
                    local cachedChunk=compile(cached)
                    if cachedChunk then
                        floor,localSource,localChunk=version,cached,cachedChunk
                    end
                end
            end
        end
    end
    local downloadedVersion=sourceRelease(source)
    if downloadedVersion and compare(downloadedVersion,floor)>=0 then
        chunk=compile(source)
        downloaded=chunk~=nil
    end
    if not chunk then source,chunk=localSource,localChunk end
    stopped=interrupted() -- HTTP/file APIs can yield while a manual load or F8 runs.
    if stopped then return stopped end
    assert(chunk,"No valid Chalk Assist release at or above "..MIN_RELEASE.." is available; try again manually")
    boot.state="starting"
    chunk({entryKind=teleportSource and "teleport" or options.automatic==true and "autoexec" or "manual",
        teleportSourceJob=teleportSource})
    assert(running(),"Chalk Assist did not finish starting")
    boot.state="loaded"
    if downloaded and type(writefile)=="function" then
        pcall(writefile,CACHE_FILE,source)
        pcall(writefile,MAIN_FILE,source)
    end
    report(downloaded and "Chalk Assist loaded from the public repository."
        or "Chalk Assist loaded from the newest valid local release; the public download was unavailable, invalid, or older.")
    return downloaded and "loaded-public" or "loaded-cache"
end)
if not ok then
    if teleportSource then revokeHandoff() end
    if boot and env[MARKER]==boot then env[MARKER]=nil end
    report("Chalk Assist startup failed. Try the loader again manually.")
    if type(warn)=="function" then warn("Chalk Assist startup failed: "..tostring(result)) end
    return false,tostring(result)
end
return true,result
]====],
    onTeleport=function(state,placeId)
        if sessionContinuity then sessionContinuity.onTeleport(state,placeId) end
    end})

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
print("Chalk Assist "..RELEASE_VERSION.." loaded. Saved settings restored. Drag / minimize / Right Shift hide. V assist / B all / F8 unload.")
