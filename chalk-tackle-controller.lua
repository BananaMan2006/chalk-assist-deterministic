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
