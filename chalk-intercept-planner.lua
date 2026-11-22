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
local function diveTipBoundary(s,p)
    if not p.diveAt then return nil end
    local duration=diveCfg(s,"Time",0.35)
    local tip=math.max(0.001,diveCfg(s,"Tip",0.5))
    -- Invert the same cosine easing as pose(): this is the discontinuity
    -- where the upright catch capsule becomes the narrower tipped capsule.
    local fraction=tip*math.acos(1-2*math.acos(0.6)/math.rad(80))/math.pi
    if duration<=0 or fraction>1 then return nil end
    return p.diveAt+duration*fraction
end
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
    if s.requireAirborne or p.diveAt then
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
    local boundary=diveTipBoundary(s,p)
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
        local nextAt=math.min(last,at+stride)
        if boundary then
            for _,edge in ipairs({boundary-.00001,boundary+.00001}) do
                if edge>at and edge<nextAt then nextAt=edge end
            end
        end
        at=nextAt
    end
    return {at=last,root=p.rootTarget,position=p.contactPosition,progress=p.contactPosition.Z}
end

-- Native contact may be claimed at the FIRST overlap. A later robust contact
-- window does not repair a brief earlier overlap that disappears as the dive
-- tips. Keep those windows connected, including both sides of the capsule
-- discontinuity. This is a bounded geometric check, not server acceptance.
function Planner.connectedContact(s,p,touch,window)
    if not p or not finite(p.contactAt) then return false,"Missing contact witness" end
    if not p.diveAt then return true end
    touch=touch or Planner.firstTouch(s,p)
    if touch.uncertain then return false,touch.reason end
    if not finite(touch.at) or touch.at>p.contactAt then return false,"Invalid first-contact witness" end
    local last=p.contactAt+(window or p.timingMargin or s.timingMargin or .012)
    local stride=.006
    local count=math.ceil(math.max(0,last-touch.at)/stride)
    if count>128 then return false,"Connected-contact sampling budget exceeded" end
    local function overlaps(at)
        local cf,airborne=Planner.pose(s,p,at)
        local a,b,r=Planner.capsule(s,cf,airborne)
        local ball=Planner.ballAt(s.arc,at-s.launchAt)
        return r-Planner.segmentDistance(ball,a,b)>=-.00001
    end
    local boundary=diveTipBoundary(s,p)
    if boundary and boundary>touch.at and boundary<last then
        if not overlaps(math.max(touch.at,boundary-.00001))
            or not overlaps(math.min(last,boundary+.00001)) then
            return false,"First dive contact is disconnected by tipping"
        end
    end
    for i=0,count do
        local at=math.min(last,touch.at+i*stride)
        if not overlaps(at) then return false,"First dive contact does not persist to the robust window" end
    end
    return true
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
    local connected,connectionReason=Planner.connectedContact(s,witness)
    if not connected then return false,connectionReason end
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
        if s.role=="DB" and not inBounds(s,Planner.pose(s,actual,actual.stopAt).Position) then
            return false,"Continuous DB catch leaves field bounds"
        end
    end
    if p.diveAt then
        actual._diveDelay=p.diveAt-s.now
        actual._diveDistance=nil
        if actual._diveDelay<0.06 then return false,"Insufficient takeoff time before dive" end
    end
    local witness=contact(s,actual,p.contactAt-s.now,p.requiredMargin,p.timingMargin)
    if not witness then return false,"Jump no longer reaches the planned ball contact" end
    local connected,connectionReason=Planner.connectedContact(s,witness)
    if not connected then return false,connectionReason end
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
    if not base then return nil,miss end
    -- DB action/time scoring can discard most otherwise valid candidates.
    -- Defer their first-contact path scans until a candidate can improve it.
    local connectionNow=s.role~="DB" and not s.optimisticReachEnvelope
    if p.diveAt and connectionNow then
        if s.role=="WR" and (s.requireAirborne or s.requireEndzoneCatch)
            and not Planner.airborneFinish(s,base,{at=base.contactAt}) then return nil,-.01 end
        local touch=Planner.firstTouch(s,base)
        if not Planner.connectedContact(s,base,touch,window) then return nil,-.01 end
        base._timingFirstTouch=touch
    end
    if s.actionTimingEnvelope==false or not (p._jumpDelay or p._diveDelay) then return base,miss end
    local jumpBudget,diveBudget=p._jumpDelay and (s.role=="DB" and not relaxed and 0.060 or 0.035) or 0,p._diveDelay and 0.020 or 0
    local minimumMargin=base.margin
    local sharedUntil
    if s.role=="WR" and (s.requireAirborne or s.requireEndzoneCatch) then
        if not Planner.airborneFinish(s,base,{at=base.contactAt}) then return nil,-0.01 end
        local first=base._timingFirstTouch or Planner.firstTouch(s,base)
        if not Planner.airborneFinish(s,base,first) then return nil,-0.01 end
        base._timingFirstTouch=first
        -- All delayed variants have exactly the same pose before the first
        -- nominal action. Check this often-long Floater prefix only once.
        sharedUntil=math.min(p.jumpAt or INF,p.diveAt or INF)
    end
    if base._timingFirstTouch then sharedUntil=math.min(p.jumpAt or INF,p.diveAt or INF) end
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
                local touch
                if actual.diveAt and connectionNow then
                    touch=sharedUntil and base._timingFirstTouch.at<=sharedUntil and base._timingFirstTouch
                        or Planner.firstTouch(s,witness,sharedUntil)
                    if not Planner.connectedContact(s,witness,touch,window) then return nil,-.01 end
                end
                if s.role=="WR" and (s.requireAirborne or s.requireEndzoneCatch) and sharedUntil then
                    if not Planner.airborneFinish(s,witness,{at=witness.contactAt}) then return nil,-0.01 end
                    touch=touch or Planner.firstTouch(s,witness,sharedUntil)
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

local function connectedSchedule(s,p,window)
    if not p.diveAt or s.optimisticReachEnvelope then return true end
    local first=Planner.firstTouch(s,p)
    if not Planner.connectedContact(s,p,first,window) then return false end
    local sharedUntil=math.min(p.jumpAt or INF,p.diveAt)
    local jumpBudget,diveBudget=p.jumpTimingBudget or 0,p.diveTimingBudget or 0
    for ji=0,(jumpBudget>0 and 2 or 0) do for di=0,(diveBudget>0 and 2 or 0) do
        if ji~=0 or di~=0 then
            local actual={}for k,v in pairs(p)do actual[k]=v end
            if p._jumpDelay then
                actual._jumpDelay=p._jumpDelay+jumpBudget*ji/2;actual.jumpAt=s.now+actual._jumpDelay
            end
            actual._diveDelay=p._diveDelay+diveBudget*di/2;actual.diveAt=s.now+actual._diveDelay
            actual._diveDistance=nil
            local touch=first.at<=sharedUntil and first or Planner.firstTouch(s,actual,sharedUntil)
            if not Planner.connectedContact(s,actual,touch,window) then return false end
        end
    end end
    p._timingFirstTouch=first
    return true
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
    -- Unknown opponents retain an optimistic possible-reach envelope. Our
    -- execution/first-claim requirements must not make their reach look worse.
    o.optimisticReachEnvelope=true
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
        if not wr and best then
            -- Margin is capped at two in the existing score. Its best possible
            -- value supplies a safe bound before any expensive path scan.
            local lower=chase and (t+costs[p.kind]/0.18*.005-.0004)
                or (t+costs[p.kind]-.05)
            if lower>=bestScore then return end
        end
        local floater=s.config and s.config.Pass and s.config.Pass.Floater
        local dbAirborneStop=s.role=="DB" and floater
            and s.arc.Flight==floater.Flight and s.arc.Apex==floater.Apex
            and not s.optimisticReachEnvelope and p.kind=="jump" and p.jumpAt
            and p.stopAt>p.jumpAt and p.stopAt<s.now+t
        if (s.role=="WR" and (s.passType=="Floater"
            or s.passType=="Bullet" and s.continuousBulletCatch==true) or dbAirborneStop)
            and s.grounded and not p.diveAt
            and (p.kind=="jump" or p.kind=="move") and t>p._reaction+.06 then
            -- A moving player cannot stop instantly while airborne. Pace
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
                    if dbAirborneStop and not inBounds(s,s.position+drift+p.direction*extent) then return end
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
        if score < bestScore then
            if not connectedSchedule(s,candidate,relaxed and .004 or nil) then
                rememberNearMiss(t,-.01,dbNearMisses)
                if p._diveDelay then rememberNearMiss(t,-.01) end
                return
            end
            best,bestScore=candidate,score
        end
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
