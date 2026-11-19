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
