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

-- Fixed five-play schedule: four center stems, then one quarter-width stem.
-- Geometry and observed contests can override it; the ratio is a preference.
function Policy.chooseScheduledRoute(input,Config,Field,RouteMath)
    input=input or {}
    if not validField(Field) or type(RouteMath)~="table" or type(RouteMath.Sanitize)~="function"
        or type(RouteMath.Plan)~="function" or input.mode=="Team" then
        return nil,"Scheduled routes require a valid 1v1 field and native route math"
    end
    local yd,width=Field.YD,Field.MaxX-Field.MinX
    local mid=(Field.MinX+Field.MaxX)*.5
    local offset=offsetOf(input)
    local los=clamp(finite(input.LOS) and input.LOS or Field.LOSZ,Field.BackZ+1,Field.GoalZ-yd)
    local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
    local run,sprint=math.max(1,Config.RunSpeed),math.max(1,Config.SprintSpeed)
    local drain=math.max(.01,Config.SprintDrain or 25)
    local reserve,dispatch=10,.12
    local index=finite(input.routeCycle) and math.floor(input.routeCycle)%20
        or finite(input.selectionIndex) and math.max(0,math.floor(input.selectionIndex)) or 0
    local desired=index%5==4 and "quarter_stem" or "middle_stem"
    local opponent=projectedOpponent(input,Config,.2)
    local history=type(input.recentRoutes)=="table" and input.recentRoutes or {}
    local recentFailure={middle_stem=0,quarter_stem=0}
    for i=#history,math.max(1,#history-3),-1 do
        local item=history[i]
        if type(item)=="table" and recentFailure[item.routeFamily]~=nil and item.success==false
            and (item.result=="Swatted" or item.result=="Intercepted") then
            recentFailure[item.routeFamily]=recentFailure[item.routeFamily]+1
        end
    end
    local edge=math.max(1,Config.RouteEdgeMargin or 1)
    local startMargin=math.max(0,Config.SidelineMarginYards or 2)*yd
    local goalDepth=(Field.GoalZ-los)/yd
    local depths,seen={},{ }
    for _,depth in ipairs({goalDepth+1,goalDepth-1,24,20,16}) do
        depth=math.min(depth,(Field.EndZ-edge-los)/yd)
        local key=math.floor(depth*100+.5)
        if depth>=12 and not seen[key] then depths[#depths+1]=depth;seen[key]=true end
    end
    local pool={middle_stem={},quarter_stem={}}
    for _,family in ipairs({"middle_stem","quarter_stem"}) do
        local starts=family=="middle_stem" and {mid}
            or {Field.MinX+width*.25,Field.MinX+width*.75}
        for _,startX in ipairs(starts) do
            if startX>=Field.MinX+startMargin and startX<=Field.MaxX-startMargin then
                for _,side in ipairs({-1,1}) do
                    local endX=side<0 and Field.MinX+edge or Field.MaxX-edge
                    for _,depth in ipairs(depths) do
                        for _,stemYards in ipairs({2,4,6,8,10,12,14,16,18,20}) do
                            if stemYards<depth-2 and math.abs(endX-startX)>=2*yd then
                                local raw={Vector2.new(startX,los),Vector2.new(startX,los+stemYards*yd),
                                    Vector2.new(endX,los+depth*yd)}
                                local points=RouteMath.Sanitize(raw,startX,los)
                                if #points==3 and (points[1]-raw[1]).Magnitude<.01
                                    and (points[2]-raw[2]).Magnitude<.01 and (points[3]-raw[3]).Magnitude<.05 then
                                    for _,pass in ipairs({"Floater","Bullet"}) do
                                        local plan=RouteMath.Plan(points,pass)
                                        local finishDistance=(plan.Target-points[2]).Magnitude
                                        -- Reach the catch area close to arrival. Charge stamina
                                        -- through arrival + dispatch, never assume regeneration.
                                        local sprintDuration=finishDistance/sprint+dispatch
                                        local cutAt=plan.Arrival-finishDistance/sprint
                                        local stemSpeed=cutAt>0 and stemYards*yd/cutAt or INF
                                        local remaining=stamina-sprintDuration*drain
                                        -- The real Throw event hands control to catch assist.
                                        -- Complete the stem before that handoff, not after it.
                                        if cutAt>=.15 and cutAt<=plan.Launch+.015 and stemSpeed>=run*.25
                                            and stemSpeed<=run and remaining>=reserve then
                                            local endpoint=worldPoint(plan.Target,offset,input.position and input.position.Y or 3)
                                            local cut=worldPoint(points[2],offset,endpoint.Y)
                                            local separation=opponent and flatDistance(endpoint,opponent) or 0
                                            local reach=opponent and (Config.SprintSpeed*(plan.Arrival+.1)
                                                +(Config.HikeTime or 3)*(Config.PreSnapDBSpeed or 12)) or 0
                                            local margin=opponent and separation-reach or 0
                                            local waiting=false
                                            local stemBlocked=false
                                            if opponent then
                                                local segment=(endpoint-cut)*FLAT
                                                local along=((opponent-cut)*FLAT):Dot(segment)/math.max(.001,segment:Dot(segment))
                                                local nearest=cut+segment*clamp(along,0,1)
                                                waiting=along>=.2 and along<=1.15
                                                    and flatDistance(nearest,opponent)<3*yd
                                                    and boundedVelocity(input.opponentVelocity,sprint).Magnitude<run*.6
                                                local localZ=opponent.Z-offset.Z
                                                -- Occupying the projected center stem is ordinary DB
                                                -- coverage, not proof of a jam. Override the family
                                                -- only for an observed close body obstruction; normal
                                                -- spacing is handled by pacing and live avoidance.
                                                local observed=vec(input.opponentPosition) and input.opponentPosition or opponent
                                                stemBlocked=vec(input.position) and flatDistance(observed,input.position)<1.4*yd
                                                    and math.abs(opponent.X-offset.X-startX)<1.4*yd
                                                    and localZ>los and localZ<points[2].Y+yd
                                            end
                                            local turn=side*(startX-mid)>0 and "same_side" or "opposite_side"
                                            if family=="middle_stem" then turn=side<0 and "left" or "right" end
                                            local shape=family.."_"..turn
                                            local routeKey,signature=routeKeys(pass,shape,depth,side)
                                            local preferredSide=(math.floor(index/5)%2==0) and -1 or 1
                                            local preferredTurn=(math.floor(index/10)%2==0) and "opposite_side" or "same_side"
                                            local score=math.min(depth,goalDepth+2)*.65+clamp(margin/yd,-30,20)*.35
                                                +(pass=="Floater" and .4 or 0)+(side==preferredSide and .4 or 0)
                                                +(turn==preferredTurn and .6 or 0)-(waiting and 12 or 0)
                                                -(stemBlocked and 6 or 0)-recentFailure[family]*8
                                            local candidate={payload={Points=points,StartX=startX,Pass=pass},plan=plan,
                                                side=side,depth=depth,shape=shape,family=routeKey,signature=signature,
                                                routeFamily=family,cutDirection=turn,scheduledFamily=desired,
                                                score=score,reachable=true,finishReachable=true,
                                                middleStemDeep=true,slowStem=true,slowStemTime=cutAt,slowStemSpeed=stemSpeed,
                                                stemYards=stemYards,cutAt=cutAt,startSprintAt=cutAt,cutCount=1,lastCutAt=cutAt,
                                                finalSprint=true,finalSprintDuration=sprintDuration,finalSprintReserve=reserve,
                                                finalSprintStamina=remaining,finishDistance=finishDistance,
                                                estimatedCatchAt=plan.Arrival,estimatedCatchZ=plan.Target.Y,
                                                estimatedCatchStamina=remaining,estimatedSeparation=separation,
                                                defenderEnvelopeMargin=margin,runTime=cutAt+finishDistance/sprint,
                                                anticipatedLane=waiting,stemBlocked=stemBlocked,
                                                requireDive=false,preferAirborne=true,preferJumpDive=true,
                                                finishMode="airborne_required",requireAirborne=true,routeStrategy="scheduled_stem_cut"}
                                            pool[family][#pool[family]+1]=candidate
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
    local function bestOf(family)
        local best
        for _,candidate in ipairs(pool[family]) do
            if not best or candidate.score>best.score then best=candidate end
        end
        if family=="quarter_stem" and best then
            local turn=math.floor(index/10)%2==0 and "opposite_side" or "same_side"
            local alternate
            for _,candidate in ipairs(pool[family]) do
                if candidate.cutDirection==turn and candidate.defenderEnvelopeMargin>=best.defenderEnvelopeMargin-yd
                    and not candidate.anticipatedLane and not candidate.stemBlocked
                    and (not alternate or candidate.score>alternate.score) then alternate=candidate end
            end
            if alternate then best=alternate end
        end
        return best
    end
    local chosen,other=bestOf(desired),bestOf(desired=="middle_stem" and "quarter_stem" or "middle_stem")
    local override
    if not chosen then chosen=other;override="scheduled_family_unreachable"
    elseif other and (recentFailure[desired]>=2 or chosen.anticipatedLane or chosen.stemBlocked)
        and (other.score>chosen.score+1 or recentFailure[desired]>=2 and not other.anticipatedLane and not other.stemBlocked) then
        chosen=other;override=recentFailure[desired]>=2 and "recent_contests" or "observed_lane_coverage"
    end
    if chosen then
        chosen.scheduleOverride=override
        return chosen
    end
    return nil,"No cut route meets the observed native timing and final sprint reserve"

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
    if type(input)~="table" or not vec(input.position) or not validField(Field)
        or input.mode=="Team" or input.ballActive
        or input.phase=="Live" and input.passStarted==true then return nil end
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
    if input.enemyCarrier and opponent and (phase=="RAC" or phase=="Live" or phase=="Run") then
        local distance=flatDistance(position,opponent)
        local lead=math.min(.45,distance/math.max(1,Config.SprintSpeed)*.3)
        local target=opponent+boundedVelocity(input.opponentVelocity,Config.SprintSpeed)*lead
        local reserve=role=="DB" and 40 or 10
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
            if slowStem and not finalSprint and index==2 and finite(plan.Arrival) then
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
                if slowStem and not finalSprint then
                    speed=math.min(run,speed)
                    -- Slow before close body contact instead of burning sprint
                    -- into a jam. The collision controller chooses the detour;
                    -- the unchanged cut deadline prevents waiting indefinitely.
                    if opponent then
                        local toTarget=(target-position)*FLAT
                        local relative=(opponent-position)*FLAT
                        local along=toTarget.Magnitude>.01 and relative:Dot(toTarget.Unit) or -1
                        local lateral=toTarget.Magnitude>.01 and (relative-toTarget.Unit*along).Magnitude or INF
                        if along>0 and along<2*yd and lateral<1.4*yd then
                            speed=math.min(speed,math.max(run*.35,along))
                        end
                    end
                end
                local feint=false
                if slowStem and not finalSprint and input.routeFamily and opponent
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
                    sprint=stamina>10+math.max(1,(Config.SprintDrain or 25)*.1)
                    speed=sprint and sprintSpeed or run
                end
                local request=result(target,"route",sprint,.1)
                request.routeWaypoint=index
                request.moveSpeed=speed
                request.moveScale=speed/(sprint and sprintSpeed or run)
                request.routeDeadline=deadline
                request.finalSprintCommitted=finalSprint
                request.stemFeint=feint
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
            local lateralDelta=position.X-observed.X
            local targetX=position.X
            if math.abs(lateralDelta)>2*yd then
                targetX=observed.X+(lateralDelta>0 and 2*yd or -2*yd)
            end
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
        local targetX=position.X
        local lateralBuffer=2*yd
        local lookahead=.25
        if lateral>lateralBuffer then
            targetX=observed.X+(lateralDelta>0 and lateralBuffer or -lateralBuffer)
        end
        local velocity=boundedVelocity(input.opponentVelocity,Config.SprintSpeed)
        -- A clear crossing can leave the receiver inside the lateral deadband
        -- just as forward motion stops. Walk toward the observed crossing's
        -- short lead instead of freezing until a full yard has opened.
        if phase=="Live" and velocity.X*(observed.X-position.X)>0
            and math.abs(velocity.X)>Config.RunSpeed*.5 and lateral>1.5*yd then
            local side=velocity.X>0 and 1 or -1
            targetX=observed.X-side*1.5*yd+velocity.X*lookahead
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
        local retreatingSafe=velocity.Z < -2
        -- Allow a brief trail or a modest lead without restoring fixed spacing.
        -- Use observed positions so projection does not erase that free band.
        -- Walk routine recovery; save sprint for real separation or a goal-line
        -- threat, retaining a lateral buffer instead of copying every cut.
        local needsSprint=phase=="Live" and not retreatingSafe
            and (urgent or forwardThreat or lateralThreat or downfieldRecovery or deepRunRecovery)
        local stamina=finite(input.stamina) and math.max(0,input.stamina) or 0
        local startAt,stopAt=urgent and 75 or 85,urgent and 60 or 70
        local sprint=needsSprint and (input.sprintOn==true and stamina>stopAt
            or input.sprintOn~=true and stamina>=startAt)
        return result(target,"shadow",sprint,1.5)
    end
    return nil
end

return Policy
