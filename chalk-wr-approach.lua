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
