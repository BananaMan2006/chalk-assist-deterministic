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
    local sideComparison
    local function decision(direction,sprint,active,blocked,reason,extra)
        local result=extra or {}
        if sideComparison then result.passingComparison=sideComparison end
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
    -- The caller may already encode a requested walking speed in its vector
    -- while native sprint is still active (20/27, for example). Cap that
    -- physical request once; multiplying by the walking ratio again would
    -- turn a checked 20-stud request into 14.8-stud movement.
    local walkSpeed=math.min(speed*strength,run)
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
    -- Only the controller's bounded opening window looks farther ahead. This
    -- starts a shallow bypass before a defender can burst into the normal
    -- collision band; later route/catch steering keeps its existing horizon.
    local horizon=clamp(finite(input.lookahead) and input.lookahead or .25,.1,
        input.openingContactWindow==true and .45 or .3)
    local height=clamp(finite(input.verticalClearance) and input.verticalClearance or 5,2,8)
    local turnRate=clamp(finite(input.turnRate) and input.turnRate or 8,2,12)
    -- Catch approaches may have only a small travel margin. This optional
    -- deadline never relaxes collision checks; it only avoids spending that
    -- margin on a needlessly wide angle or a clear-path debounce hold.
    local catchPath=vec(input.targetPosition) and finite(input.arriveBy)
    -- Losing a reachable catch does not justify a coarser route to the same
    -- observed ball. A pursuit may keep fine detour choices without gaining
    -- an arrival deadline, extra speed, or a reachable-contact claim.
    local precisePath=catchPath or input.precisePath==true
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
        if not sprintEligible or blocked then return false end
        -- Test the actual bounded heading, not the final candidate heading.
        -- A path safe only at walking speed cannot spend sprint while turning
        -- around the other player.
        local actualSafe,actualGap=evaluate(direction,speed*strength)
        local futureSafe,futureGap=evaluate(direction,sprintSpeed*strength)
        if touching then
            -- A moving player can follow just behind us while we already make
            -- normal native progress. Walking forever inside that contact band
            -- needlessly prevents a separating sprint. This exception needs
            -- measured travel, not reported velocity, and cannot help a jammed
            -- or stationary body. Both native-speed paths must strictly move
            -- away from every near body throughout the prediction interval.
            if not actualSafe or not futureSafe or not finite(measured)
                or measured<run*.75 or measured>math.max(speed,sprintSpeed)*1.25
                or speed<run*.95 then return false end
            for _,moveSpeed in ipairs({speed*strength,sprintSpeed*strength}) do
                for _,other in ipairs(obstacles) do
                    local initial=other.relative.Magnitude
                    local rv=other.velocity-direction*moveSpeed
                    local gap,ending=clearance(other.relative,rv,horizon)
                    if initial<=sprintClearance then
                        if other.velocity.Magnitude<math.max(2,run*.2)
                            or other.relative:Dot(rv)<=.05 or ending<initial+.25 then return false end
                    elseif gap<sprintClearance then return false end
                end
            end
            return true
        end
        return actualSafe and actualGap>=sprintClearance
            and futureSafe and futureGap>=sprintClearance
    end

    if not threat and not blocked then
        local old=state.active and state.heading or nil
        if vec(old) and old.Magnitude>.001 and old:Dot(heading)<.9999 then
            state.clearSince=state.clearSince or now
            local amount=speed>0 and walkSpeed/speed or strength
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
        local angles=precisePath and {5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90}
            or {35,55,75,90}
        for _,degrees in ipairs(angles) do
            local direction=rotate(heading,side*math.rad(degrees))
            local safe,gap,bounded=evaluate(direction,walkSpeed)
            if safe then
                -- A shallow walking-only bypass can repeatedly release sprint
                -- even when a slightly wider same-side path is safe at both
                -- native speeds and makes more forward progress. Compare that
                -- progress only for the caller's explicit sprint opt-in. The
                -- bounded turn below still has to pass both speed checks.
                local alignment=direction:Dot(heading)
                local score=alignment+(precisePath and 0 or math.min(gap,radius+3)*.015)
                if sprintEligible then
                    local usableSpeed=keepSprint(direction) and sprintSpeed*strength or walkSpeed
                    score=alignment*usableSpeed/math.max(.001,walkSpeed)
                end
                if not best or score>best.score then best={direction=direction,score=score,side=side} end
            elseif bounded and nearest<radius then
                -- Once overlapping, a sideways exit may initially touch the
                -- same capsule. Prefer increasing final separation to pushing.
                local improves=true
                for _,other in ipairs(obstacles) do
                    if other.relative.Magnitude<radius+.5 then
                        local ending=(other.relative+(other.velocity-direction*walkSpeed)*horizon).Magnitude
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
    -- Compare only a new, explicitly enabled live catch encounter. Existing
    -- passing sides stay locked, and unknown projections retain the old choice.
    if input.comparePassingSides==true and input._sideProbe~=true
        and input.precisePath==true and catchPath and input.arriveBy>now
        and finite(input.walkSpeed) and heading:Dot(goalHeading)>=1-.000001
        and state.side~=1 and state.side~=-1 and not touching and chosen and chosen.score>0 then
        local alternate=candidate(-preferred)
        if alternate and alternate.score>0 then
            local function projectedSide(side)
                local probeState={}
                for k,value in pairs(state) do probeState[k]=value end
                probeState.side=side
                local probePosition=position
                local probeSpeed=speed
                local probeBodies={}
                for _,other in ipairs(input.opponents or {}) do
                    if type(other)=="table" and vec(other.position) then
                        if not vec(other.velocity) then return nil end
                        local velocity=other.velocity*FLAT
                        if velocity.Magnitude>40 then velocity=velocity.Unit*40 end
                        probeBodies[#probeBodies+1]={position=other.position,velocity=velocity}
                    end
                end
                local minimum=math.huge
                local duration=math.min(.25,horizon,remaining)
                local count=math.min(15,math.max(1,math.ceil(duration/(1/60))))
                local step=duration/count
                for index=1,count do
                    local probeInput={}
                    for key,value in pairs(input) do probeInput[key]=value end
                    local delta=(input.targetPosition-probePosition)*FLAT
                    if delta.Magnitude<.001 or delta:Dot(goalHeading)<=0 then return nil end
                    probeInput._sideProbe=true
                    probeInput.now=now+(index-1)*step
                    probeInput.dt=index==1 and dt or step
                    probeInput.position=probePosition
                    probeInput.currentDirection=index==1 and current or probeState.heading or current
                    probeInput.desiredDirection=index==1 and desired or delta.Unit*strength
                    probeInput.walkSpeed=probeSpeed
                    probeInput.opponents=probeBodies
                    local result
                    probeState,result=Avoidance.update(probeState,probeInput)
                    if not result.active then return nil end
                    -- The returned vector already includes any walking scale.
                    -- Interpret it at this dispatch speed; cap the next sample below.
                    local movement=result.direction*probeSpeed
                    for _,other in ipairs(probeBodies) do
                        if math.abs(other.position.Y-probePosition.Y)<=height then
                            local gap=clearance((other.position-probePosition)*FLAT,
                                other.velocity-movement,step)
                            if gap<radius then return nil end
                            minimum=math.min(minimum,gap)
                        end
                    end
                    probePosition=probePosition+movement*step
                    if not inside(probePosition,input.bounds) then return nil end
                    for _,other in ipairs(probeBodies) do
                        other.position=other.position+other.velocity*step
                    end
                    -- Do not credit a future sprint acknowledgement. Once a
                    -- checked step releases sprint, use at most walking speed.
                    if not result.sprint then probeSpeed=math.min(probeSpeed,run) end
                end
                if ((input.targetPosition-probePosition)*FLAT):Dot(goalHeading)<=0 then return nil end
                return {progress=goalDelta.Magnitude-((input.targetPosition-probePosition)*FLAT).Magnitude,
                    clearance=minimum,steps=count,position=probePosition}
            end
            local retained=projectedSide(preferred)
            local other=projectedSide(-preferred)
            sideComparison={retainedSide=preferred,chosenSide=preferred,
                retainedScore=chosen.score,alternateScore=alternate.score,
                retainedProgress=retained and retained.progress,
                alternateProgress=other and other.progress,
                retainedClearance=retained and retained.clearance,
                alternateClearance=other and other.clearance,
                duration=math.min(.25,horizon,remaining),maximumStepsPerSide=15}
            if retained and other and other.progress>=retained.progress+.1 then
                chosen=alternate;sideComparison.chosenSide=-preferred
            end
        end
    end
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
    local amount=speed>0 and walkSpeed/speed or strength
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
