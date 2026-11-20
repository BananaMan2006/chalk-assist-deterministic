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
    local pendingClaimMotion,lastCatchMotion
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
        pendingClaimMotion,lastCatchMotion=nil,nil
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
        pendingClaimMotion,lastCatchMotion=nil,nil
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
        -- A funded route can also retain a sprint it already requested before
        -- the throw. Its observed round/snap and deadline must still be current.
        -- Prethrow DB coverage and ordinary walking conserve their reserve.
        local function finite(value)
            return type(value)=="number" and value==value and math.abs(value)<math.huge
        end
        local target=arrival and arrival.targetPosition
        local routeIdentity=s.roundKey or s.preSnapEnds
        local fundedRouteSprint=s.role=="WR" and requestedSprint==true and not s.arc and not s.passStarted
            and routeIdentity~=nil and arrival~=nil and arrival.routeRoundKey==tostring(routeIdentity)
            and finite(s.snapAt) and arrival.snapAt==s.snapAt and s.snapAt<=now
            and finite(arrival.arriveBy) and arrival.arriveBy>now
            and typeof(target)=="Vector3" and finite(target.X) and finite(target.Y) and finite(target.Z)
        local allowSprintDetour=s.phase=="Live" and (fundedRouteSprint
            or s.role=="WR" and s.catchIntent~=nil
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
    local function claimFinite(value)
        return type(value)=="number" and value==value and math.abs(value)<math.huge
    end
    local function checkedClaimMotion(record,s,now)
        if not alive or not auto or not s.enabled or s.testing or not inputOwned or not s.playBudget
            or UIS:GetFocusedTextBox() or GuiService.MenuIsOpen
            or s.phase~="Live" or s.role~="WR" or s.launchAt~=record.launchAt or s.arc~=record.arc
            or not claimFinite(now) or now<record.started or now>=record.stopAt then return nil,"ownership or deadline" end
        local root,h=healthyCharacter()
        if root~=record.root or h~=record.h or h.PlatformStand or h.FloorMaterial~=Enum.Material.Air
            or not Moves.Upright() then return nil,"native motion" end
        if not claimFinite(h.WalkSpeed) or math.abs(h.WalkSpeed-record.speed)>.05
            or (me:GetAttribute("SprintOn")==true)~=record.sprint
            or record.sprint and not sprintBudget(s).canSprint then return nil,"native speed or reserve" end
        local fresh=snapshot(s,root,h,now)
        if not fresh.physicalAirborne or fresh.reachAirborne==false then return nil,"airborne reach" end
        local remaining=record.stopAt-now
        local endpoint=root.Position+record.direction*h.WalkSpeed*remaining
        local bounds=fresh.bounds
        local function inside(p)
            return bounds and claimFinite(p.X) and claimFinite(p.Y) and claimFinite(p.Z)
                and claimFinite(bounds.minX) and claimFinite(bounds.maxX)
                and claimFinite(bounds.minZ) and claimFinite(bounds.maxZ)
                and p.X>=bounds.minX and p.X<=bounds.maxX and p.Z>=bounds.minZ and p.Z<=bounds.maxZ
        end
        if not inside(root.Position) or not inside(endpoint) then return nil,"field bounds" end
        if record.requireGoal and (not claimFinite(fresh.wrDiveGoalZ)
            or root.Position.Z<fresh.wrDiveGoalZ or endpoint.Z<fresh.wrDiveGoalZ) then return nil,"goal boundary" end
        local distance=(endpoint-root.Position).Magnitude
        if clippedDistance(root.Position,record.direction.Unit,distance)<distance-.001 then return nil,"wall" end
        if not PlayerAvoidance then return nil,"clearance unavailable" end
        -- Check a fresh path without modifying the live avoidance state. Any
        -- detour aborts; only the exact already-issued command may continue.
        local _,decision=PlayerAvoidance.update(nil,{now=now,dt=1/60,position=root.Position,
            velocity=root.AssemblyLinearVelocity,desiredDirection=record.direction,
            currentDirection=record.direction.Unit,
            opponents=fresh.opponents or (fresh.opponent and {fresh.opponent} or {}),bounds=bounds,
            requestedSprint=record.sprint,walkSpeed=h.WalkSpeed,runSpeed=Config.RunSpeed,
            sprintSpeed=Config.SprintSpeed,allowSprintDetour=record.sprint,canDetour=true,
            targetPosition=endpoint,arriveBy=record.stopAt})
        if not decision or decision.sprint~=record.sprint
            or typeof(decision.direction)~="Vector3" or (decision.direction-record.direction).Magnitude>.00001 then
            return nil,"clearance changed"
        end
        return root,h
    end
    local function beginClaimMotion(s,root,h,now,nativeTouchAge)
        local command=lastCatchMotion
        if not claimFinite(nativeTouchAge) or nativeTouchAge<0 or nativeTouchAge>.05
            or not plan or plan.kind~="jump" or plan.continuousCatch~=true or plan.reachable==false
            or plan.diveAt or dived or not jumped or jumpRequest or not lastSnapshot
            or not command or command.root~=root or command.h~=h or command.launchAt~=s.launchAt
            or not claimFinite(command.at) or now-command.at<0 or now-command.at>.05
            or not claimFinite(plan.stopAt) or plan.stopAt<=now or plan.stopAt-now>.15
            or typeof(command.direction)~="Vector3" or not claimFinite(command.direction.Magnitude)
            or command.direction.Magnitude<.001 or command.direction.Magnitude>1.000001
            or typeof(plan.direction)~="Vector3" or not claimFinite(plan.direction.Magnitude)
            or plan.direction.Magnitude<.001
            or command.direction.Unit:Dot(plan.direction.Unit)<math.cos(.1) then return false end
        local record={root=root,h=h,launchAt=s.launchAt,arc=s.arc,started=now,stopAt=plan.stopAt,
            direction=command.direction,speed=h.WalkSpeed,sprint=me:GetAttribute("SprintOn")==true,
            requireGoal=lastSnapshot.requireEndzoneCatch==true}
        local valid=checkedClaimMotion(record,s,now)
        if not valid then return false end
        cancel(true)
        pendingClaimMotion=record
        log("claimMovementContinue",{role=s.role,claimOnly=true,authoritative=false,
            stopAt=record.stopAt,remaining=record.stopAt-now,direction=xyz(record.direction)})
        return true
    end
    local function updateClaimMotion(s,now)
        local record=pendingClaimMotion
        if not record then return end
        local root,h=checkedClaimMotion(record,s,now)
        if not root then
            log("claimMovementStop",{role=s.role,claimOnly=true,authoritative=false,
                elapsed=math.max(0,now-record.started),reason=h,stopAt=record.stopAt})
            cancel();return
        end
        -- No fresh action, speed request, target, or native catch claim.
        h:Move(record.direction,false)
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
            local preserveMovement=not pendingClaimMotion and s.playBudget and ownsSprint and me:GetAttribute("SprintOn")==true
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
            updateClaimMotion(s,now)
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
                local command=avoid.active and avoid.direction
                    or smoothDirection(avoid.direction,root,h,dt)*math.min(1,avoid.direction.Magnitude)
                h:Move(command,false)
                lastCatchMotion={root=root,h=h,launchAt=s.launchAt,at=now,direction=command}
                if avoid.active then nextReplan=math.min(nextReplan,now+.1) end
            else
                lastCatchMotion=nil
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
        if pendingClaimMotion and data.Phase~="Live" then cancel() end
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
            if not beginClaimMotion(s,root,h,claimObservedAt,touchNumber and touchClock-touchNumber) then cancel() end
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
