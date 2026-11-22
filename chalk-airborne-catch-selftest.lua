-- Authored geometry/controller gates only. No native input or server catch claim.
return function(Planner,source)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function fixture()
        return {now=100,launchAt=100,role="WR",arc={P0=Vector3.new(0,6,-30),
            P1=Vector3.new(20,3.5,20),Flight=.9,Apex=0},position=Vector3.new(0,3,0),
            velocity=Vector3.zero,lookDirection=Vector3.new(0,0,1),grounded=true,
            jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            groundRootY=3,turfY=0,diveDistance=14.7,canJump=true,canDive=true,maxHorizon=2.2,
            wrDiveGoalZ=-100,
            margin=.4,preferAirborne=true,requireAirborne=true,preferJumpDive=true,chase=true,allowHold=false,
            config={CatchRadius=3.75,DiveCatchRadius=2.5,WaistDrop=1,HandOffset=.5,
                HandUpOffset=3.5,DiveReach=2.4,Moves={Dive={Time=.35,Tip=.5,Ground=.75,GetUp=.35}}}}
    end
    local function diveFixture()
        local s=fixture()
        -- This longer lateral finish needs a robust airborne dive even with
        -- separate jump and dive dispatch jitter. The shorter fixture now
        -- correctly prefers its less timing-sensitive jump-only witness.
        s.arc.P1=Vector3.new(30,3.5,20)
        return s
    end
    local function dispatch(s,p)
        local cf,air,vy=Planner.pose(s,p,p.diveAt-.000001)
        local fresh={}for k,v in pairs(s)do fresh[k]=v end
        fresh.now=p.diveAt;fresh.position=cf.Position
        fresh.velocity=p.direction*27+Vector3.new(0,vy,0)
        fresh.grounded=false;fresh.canJump=false
        assert(air)
        return fresh
    end
    test("WR times jump and dive for airborne first contact, not early prone arrival",function()
        local s=diveFixture();local p,why=Planner.solve(s)
        assert(p and p.kind=="jumpDive" and p.airborneFinish=="jumpDive",why)
        assert(p.jumpAt>s.now+.05 and p.diveAt>p.jumpAt+.095)
        assert(p.firstTouchAt>=p.diveAt+.03 and p.margin>=s.margin and not p.risk)
        local cf,air=Planner.pose(s,p,p.firstTouchAt)
        assert(air and cf.Position.Y>s.turfY+.75)
        assert(Planner.airborneFinish(s,p)=="jumpDive")
    end)
    test("unavailable dive retains an airborne jump catch",function()
        local s=fixture();s.canDive=false
        local p,why=Planner.solve(s)
        assert(p and p.airborneFinish=="jump" and not p.diveAt and p.jumpAt,why)
    end)
    test("receiving with distance to carry prefers a robust upright jump over an optional dive",function()
        local s=fixture();s.passType="Bullet";s.preferJumpDive=false
        local p,why=Planner.solve(s)
        assert(p and p.airborneFinish=="jump" and not p.diveAt and p.jumpAt,why)
        assert(p.margin>=s.margin and not p.risk)
    end)
    test("explicit counter-camping Bullet keeps moving through an airborne catch before goal",function()
        local s=fixture();s.passType="Bullet";s.preferJumpDive=false;s.canDive=false
        s.wrDiveGoalZ=30;s.continuousBulletCatch=true
        local p,why=Planner.solve(s)
        assert(p and p.kind=="jump" and p.continuousCatch and not p.diveAt,why)
        assert(p.movementScale>=.45 and p.movementScale<=1 and p.stopAt>=p.contactAt+.012)
        local first,air=Planner.pose(s,p,p.firstTouchAt)
        assert(air and first.Position.Z<s.wrDiveGoalZ and p.margin>=s.margin)
        local before=Planner.pose(s,p,p.contactAt-.012).Position
        local after=Planner.pose(s,p,p.contactAt+.012).Position
        assert(((after-before)*Vector3.new(1,0,1)):Dot(p.direction)>.1)
        s.continuousBulletCatch=false
        local ordinary=assert(Planner.solve(s))
        assert(not ordinary.continuousCatch,"ordinary Bullets must not silently opt into the new approach")
    end)
    local function advanceToJump(s,p,late)
        local fresh={}for key,value in pairs(s)do fresh[key]=value end
        fresh.now=p.jumpAt+late
        local cf=Planner.pose(s,p,fresh.now)
        fresh.position=Vector3.new(cf.Position.X,s.groundRootY,cf.Position.Z)
        fresh.velocity=p.direction*s.walkSpeed
        fresh.grounded=true;fresh.canJump=true;fresh.reactionDelay=0
        p.approachTarget=p.diveAt and Planner.pose(s,p,p.diveAt-.000001).Position or p.rootTarget
        return fresh
    end
    local function disconnectedFloater(index)
        -- Numeric observations only, from two failed receiving dives. Both
        -- had an upright overlap followed by a tilt-induced gap before the
        -- later contact window. No player identity or native source is stored.
        local d=index==8 and {
            now=102.34921598434448,position=Vector3.new(54.97901916503906,4.636867523193359,93.6631851196289),
            velocity=Vector3.new(14.703125,0.0000260655160673,22.645488739013672),staminaTime=.72,targetX=66.99998474121094,
            direction=Vector3.new(.3794228434562683,0,.9252234697341919),
            approach=Vector3.new(59.32286834716797,8.7846040725708,104.25567626953125),
            jumpAt=102.6633369922638,diveAt=102.7733371257782,contactAt=102.96333718299866}
            or {
            now=102.44028210639954,position=Vector3.new(-16.397777557373047,4.636867046356201,102.65338134765625),
            velocity=Vector3.new(-15.22146987915039,0.0000390609275200,22.300378799438477),staminaTime=.76,targetX=-29.212129592895508,
            direction=Vector3.new(-.5637038350105286,0,.8259770274162292),
            approach=Vector3.new(-21.68922233581543,8.784605026245117,110.40676879882812),
            jumpAt=102.6780457496643,diveAt=102.78804588317871,contactAt=102.97804570198059}
        local s=fixture();s.now=d.now;s.passType="Floater";s.position=d.position;s.velocity=d.velocity
        s.lookDirection=d.direction;s.steeringDirection=d.direction;s.groundRootY=d.position.Y
        s.arc={P0=Vector3.new(18.893924713134766,7.636868476867676,-53.83334732055664),
            P1=Vector3.new(d.targetX,5.136868476867676,125.72048950195312),Flight=3.1,Apex=42}
        s.turfY=1.63686865568161;s.diveTurfY=s.turfY;s.wrDiveGoalZ=103.30604553222656
        s.sprintSeconds=d.staminaTime;s.reactionDelay=0;s.preferJumpDive=false;s.requireEndzoneCatch=true
        s.diveDistance=14.731816774606706;s.gravity=196.1999969482422;s.jumpSpeed=48.52215950860912
        s.bounds={minX=-29.7121302485466,maxX=67.49998158216476,minZ=-43.512135207653046,maxZ=151.9120985865593}
        local p={kind="jumpDive",direction=d.direction,jumpAt=d.jumpAt,diveAt=d.diveAt,contactAt=d.contactAt,
            approachTarget=d.approach,_jumpDelay=d.jumpAt-s.now,_diveDelay=d.diveAt-s.now,
            _aimDistance=((d.approach-d.position)*Vector3.new(1,0,1)).Magnitude,
            _speed=27,_runSpeed=20,_sprintSeconds=d.staminaTime,_reaction=0}
        return s,p
    end
    local function denseConnected(s,p)
        local start=math.max(s.now,s.launchAt+.1201)
        local finish=p.contactAt+.012
        local first
        for i=0,math.ceil((finish-start)/.001) do
            local at=math.min(finish,start+i*.001)
            local cf,air=Planner.pose(s,p,at);local a,b,r=Planner.capsule(s,cf,air)
            local margin=r-Planner.segmentDistance(Planner.ballAt(s.arc,at-s.launchAt),a,b)
            if margin>=0 then first=first or at
            elseif first and margin<-.00001 then return false,first,at end
        end
        return first~=nil,first
    end
    test("failed Floater replay chooses a connected first catch instead of bridging a dive-tip gap",function()
        for _,index in ipairs({8,33}) do
            local s,old=disconnectedFloater(index)
            assert(not denseConnected(s,old),"Recorded fixture lost its two disconnected windows")
            local p,why=Planner.solve(s)
            -- The final WR8 snapshot can already be too late for a robust
            -- replacement. WR33 still has a valid alternate airborne dive.
            if index==33 then assert(p and p.reachable and p.airborneFinish,
                why or "Rejected every catch instead of finding an alternative") end
            if p then
                assert(denseConnected(s,p),"Selected a brief first claim separated from its robust contact")
                assert(p.margin>=s.margin and not p.risk and p.firstTouchAt<=p.contactAt)
                for ji=0,(p.jumpAt and 2 or 0) do for di=0,(p.diveAt and 2 or 0) do
                    local q={}for k,v in pairs(p)do q[k]=v end
                    if p.jumpAt then q._jumpDelay=p._jumpDelay+.0175*ji;q.jumpAt=p.jumpAt+.0175*ji end
                    if p.diveAt then q._diveDelay=p._diveDelay+.01*di;q.diveAt=p.diveAt+.01*di;q._diveDistance=nil end
                    assert(denseConnected(s,q),"Dispatch variant reopened a first-contact gap")
                end end
            end
        end
    end)
    test("DB first contact includes the brief upright overlap before a dive tips",function()
        for _,index in ipairs({8,33}) do
            local s,p=disconnectedFloater(index);s.role="DB";s.requireAirborne=false;s.requireEndzoneCatch=false
            local _,first=denseConnected(s,p)
            local touch=Planner.firstTouch(s,p)
            assert(not touch.uncertain and math.abs(touch.at-first)<.001,
                "DB coarse scan skipped the first native claim pocket")
        end
    end)
    test("the earlier WR8 snapshot retains a connected airborne dive",function()
        local s=disconnectedFloater(8)
        s.now=102.19874882698059;s.position=Vector3.new(51.98614501953125,4.636867523193359,90.96587371826172)
        s.velocity=Vector3.new(20.538305282592773,.0000260655160673,17.52649688720703)
        s.lookDirection=Vector3.new(.7672805786132812,0,.6413116455078125)
        s.steeringDirection=Vector3.new(.7606779932975769,0,.6491295099258423);s.sprintSeconds=.88
        local p,why=Planner.solve(s)
        assert(p and p.diveAt and p.airborneFinish=="jumpDive",why or "Earlier dive opportunity was erased")
        assert(denseConnected(s,p),"Earlier chosen dive still bridges a first-contact gap")
    end)
    test("fresh jump and dive validators reject a disconnected first claim for WR and DB",function()
        for _,role in ipairs({"WR","DB"}) do
            local s,p=disconnectedFloater(33);s.role=role
            assert(not Planner.validateJump(advanceToJump(s,p,0),p),"Fresh jump retained a disconnected dive claim")
            local actual=dispatch(s,p)
            assert(not Planner.validateAirborneDive(actual,p),"Fresh dive retained a disconnected first claim")
        end
    end)
    test("WR dive starts inside the endzone rather than merely finishing there",function()
        local s=diveFixture();local old=assert(Planner.solve(s))
        local origin=Planner.pose(s,old,old.diveAt).Position
        assert(old.rootTarget.Z>origin.Z+.2,"Fixture needs contact beyond dive origin")
        s.wrDiveGoalZ=origin.Z+.1
        assert(old.rootTarget.Z>s.wrDiveGoalZ)
        for _,timingEnvelope in ipairs({true,false}) do
            s.actionTimingEnvelope=timingEnvelope
            local p=Planner.solve(s)
            assert(not p or not p.diveAt or Planner.pose(s,p,p.diveAt).Position.Z>=s.wrDiveGoalZ,
                "A catch beyond goal must not authorize a pre-goal dive")
        end
        local actual=advanceToJump(s,old,0)
        assert(not Planner.validateJump(actual,old),"Stale pre-goal dive must not survive jump validation")
    end)
    test("inside-endzone airborne dives remain available and world translation preserves the boundary",function()
        local s=diveFixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        fresh.wrDiveGoalZ=fresh.position.Z
        assert(Planner.validateAirborneDive(fresh,p),"Goal-line equality is inside")
        local offset=Vector3.new(50,0,-200)
        fresh.position=fresh.position+offset;fresh.wrDiveGoalZ=fresh.wrDiveGoalZ+offset.Z
        fresh.arc={P0=s.arc.P0+offset,P1=s.arc.P1+offset,Flight=s.arc.Flight,Apex=s.arc.Apex}
        local q={}for k,v in pairs(p)do q[k]=v end
        q.rootTarget=p.rootTarget+offset;q.contactPosition=p.contactPosition+offset
        assert(Planner.validateAirborneDive(fresh,q))
    end)
    test("missing or nonfinite WR endzone forbids dives while preserving ordinary jump catches",function()
        for _,value in ipairs({false,0/0,math.huge}) do
            local s=diveFixture();s.wrDiveGoalZ=value
            local p=Planner.solve(s)
            assert(not p or not p.diveAt)
            s=fixture();s.wrDiveGoalZ=value;s.canDive=false
            local jump=assert(Planner.solve(s));assert(jump.jumpAt and not jump.diveAt)
        end
        local s=diveFixture();local p=assert(Planner.solve(s));local actual=dispatch(s,p)
        actual.wrDiveGoalZ=nil
        assert(not Planner.validateAirborneDive(actual,p))
    end)
    test("actual airborne dive origin must remain inside both goal and provided field bounds",function()
        local s=diveFixture();local p=assert(Planner.solve(s));local actual=dispatch(s,p)
        actual.wrDiveGoalZ=actual.position.Z+.001
        assert(not Planner.validateAirborneDive(actual,p),"Fresh position short of goal cannot use old plan")
        actual.wrDiveGoalZ=-100
        actual.bounds={minX=actual.position.X+.001,maxX=100,minZ=-100,maxZ=100}
        assert(not Planner.validateAirborneDive(actual,p),"Out-of-bounds origin cannot dive into an in-bounds contact")
    end)
    test("scheduled dive delays cannot carry a backward-moving WR outside the endzone",function()
        local s=diveFixture()
        local old=assert(Planner.solve(s));assert(old.diveAt)
        local function mirror(v)return Vector3.new(v.X,v.Y,-v.Z)end
        old.direction=mirror(old.direction);old.rootTarget=mirror(old.rootTarget)
        old.contactPosition=mirror(old.contactPosition);old._timingFirstTouch=nil
        s.arc={P0=Vector3.new(0,6,30),P1=Vector3.new(30,3.5,-20),Flight=.9,Apex=0}
        s.lookDirection=Vector3.new(0,0,-1)
        assert(old.direction.Z<0 and Planner.airborneFinish(s,old)=="jumpDive")
        local origin=Planner.pose(s,old,old.diveAt).Position
        s.wrDiveGoalZ=origin.Z-.05
        local delayed={}for k,v in pairs(old)do delayed[k]=v end
        delayed._diveDelay=old._diveDelay+.02;delayed.diveAt=old.diveAt+.02
        assert(Planner.pose(s,delayed,delayed.diveAt).Position.Z<s.wrDiveGoalZ,
            "Fixture must cross the boundary under delayed backward movement")
        local p=Planner.solve(s)
        if p and p.diveAt then
            for ji=0,2 do for di=0,2 do
                local q={}for k,v in pairs(p)do q[k]=v end
                if q._jumpDelay then q._jumpDelay=p._jumpDelay+.0175*ji;q.jumpAt=s.now+q._jumpDelay end
                q._diveDelay=p._diveDelay+.01*di;q.diveAt=s.now+q._diveDelay
                assert(Planner.pose(s,q,q.diveAt).Position.Z>=s.wrDiveGoalZ)
            end end
        end
    end)
    test("WR dive boundary does not change DB earliest interception or dive validation",function()
        local s=diveFixture();s.role="DB";s.requireAirborne=false;s.preferAirborne=false
        local first=assert(Planner.solve(s));s.wrDiveGoalZ=10000
        local after=assert(Planner.solve(s))
        assert(first.kind==after.kind and first.contactAt==after.contactAt and first.diveAt==after.diveAt)
        s=diveFixture();local wr=assert(Planner.solve(s));local actual=dispatch(s,wr)
        actual.role="DB";actual.wrDiveGoalZ=nil
        assert(Planner.validateAirborneDive(actual,wr))
    end)
    local function lateFloater()
        local s=fixture();s.now=102.3420808;s.launchAt=100;s.passType="Floater"
        s.position=Vector3.new(-18.8274899,3,54.8122864)
        s.velocity=Vector3.new(-15.1739159,0,22.3327656)
        s.arc={P0=Vector3.new(18.8939247,6,-53.8333473),
            P1=Vector3.new(-29.2121296,3.5,74.3265305),Flight=3.1,Apex=42}
        s.sprintSeconds=1.08;s.reactionDelay=0;s.preferJumpDive=false
        return s
    end
    local function minimumContactZ(s,p)
        local touch=Planner.firstTouch(s,p)
        local z=math.huge
        for _,at in ipairs({touch.at,p.contactAt-.012,p.contactAt,p.contactAt+.012}) do
            z=math.min(z,Planner.pose(s,p,at).Position.Z)
        end
        return z
    end
    local function continuousFloater()
        local s=fixture();s.passType="Floater";s.now=100.4;s.maxHorizon=3.5;s.canDive=false
        s.arc={P0=Vector3.new(0,6,-30),P1=Vector3.new(20,3.5,45),Flight=3.1,Apex=42}
        s.velocity=Vector3.new(10,0,25);s.requireEndzoneCatch=true;s.wrDiveGoalZ=20
        return s
    end
    test("grounded WR Floater paces a continuous airborne contact instead of stopping in midair",function()
        local s=continuousFloater();local p=assert(Planner.solve(s))
        assert(p.kind=="jump" and p.continuousCatch and not p.diveAt)
        assert(p.movementScale>=.45 and p.movementScale<.9 and p.stopAt>=p.contactAt+.012)
        assert(p.firstTouchAt<p.stopAt and minimumContactZ(s,p)>=s.wrDiveGoalZ+.25)
        local before=Planner.pose(s,p,p.contactAt-.03).Position
        local after=Planner.pose(s,p,p.contactAt+.03).Position
        assert(((after-before)*Vector3.new(1,0,1)):Dot(p.direction)>.3,
            "Contact must preserve forward motion, not a parked root")
        for _,late in ipairs({0,.0175,.035}) do
            local q={}for key,value in pairs(p)do q[key]=value end
            q._jumpDelay=p._jumpDelay+late;q.jumpAt=p.jumpAt+late
            assert(Planner.airborneFinish(s,q)=="jump")
            for _,delta in ipairs({-.012,0,.012}) do
                local at=p.contactAt+delta;local cf,air=Planner.pose(s,q,at)
                local a,b,r=Planner.capsule(s,cf,air)
                assert(r-Planner.segmentDistance(Planner.ballAt(s.arc,at-s.launchAt),a,b)>=s.margin-1e-7)
            end
        end
    end)
    test("fresh continuous jump validation keeps scaled movement and rejects a displaced actual root",function()
        local s=continuousFloater();local p=assert(Planner.solve(s))
        local actual=advanceToJump(s,p,.015)
        assert(Planner.validateJump(actual,p))
        local scale,speed=p.movementScale,p._speed
        assert(actual.walkSpeed==27 and speed==27*scale,"Pacing must scale native input, not native speed")
        actual.position=actual.position+Vector3.new(10,0,0)
        assert(not Planner.validateJump(actual,p),"Continuous motion cannot hide an actual position error")
        assert(p.movementScale==scale and p._speed==speed,"Fresh validation must not mutate the original trajectory")
        actual=advanceToJump(s,p,0);p.movementScale=1.1
        assert(not Planner.validateJump(actual,p),"Continuous catch cannot extrapolate above native input")
        p.movementScale=.44
        assert(not Planner.validateJump(actual,p),"Continuous catch cannot silently turn into creeping")
    end)
    test("continuous Floater pacing leaves DB Bullet and airborne-start action models unchanged",function()
        local s=continuousFloater();s.role="DB";s.requireAirborne=false;s.preferAirborne=false
        local db=assert(Planner.solve(s));assert(not db.continuousCatch and db.movementScale==nil)
        s=fixture();s.passType="Bullet"
        local bullet=assert(Planner.solve(s));assert(not bullet.continuousCatch and bullet.movementScale==nil)
        s=continuousFloater();local p=assert(Planner.solve(s));local at=p.jumpAt+.08
        local cf,air,vy=Planner.pose(s,p,at)
        s.now=at;s.position=cf.Position;s.velocity=p.direction*p._speed+Vector3.new(0,vy,0)
        s.grounded=false;s.canJump=false
        local airborne=Planner.solve(s)
        assert(air and (not airborne or not airborne.continuousCatch))
    end)
    test("fresh continuous jump rejects a small sideline shift despite valid ball overlap",function()
        local s=continuousFloater();local p=assert(Planner.solve(s))
        local last=Planner.pose(s,p,p.contactAt+.012).Position
        s.bounds={minX=-100,maxX=last.X+.005,minZ=-100,maxZ=200}
        assert(Planner.airborneFinish(s,p)=="jump","Original moving contact must remain in bounds")
        local actual=advanceToJump(s,p,0);actual.position=actual.position+Vector3.new(.02,0,0)
        local bounds=actual.bounds;actual.bounds=nil
        assert(Planner.validateJump(actual,p),"Shift must retain geometric overlap before checking the sideline")
        actual.bounds=bounds
        local valid,why=Planner.validateJump(actual,p)
        assert(not valid and why=="Continuous airborne contact leaves field bounds",
            "Fresh position cannot use an in-bounds stale forecast to cross the sideline")
    end)
    test("continuous catch preserves explicit zero small and sufficient movement limits",function()
        for _,cap in ipairs({0,1}) do
            local s=continuousFloater();s.maxMoveDistance=cap
            assert(not Planner.solve(s),"Pacing must not overwrite a restricted movement distance")
            s.maxMoveDistance=nil;s.range=cap
            assert(not Planner.solve(s),"Continuous movement must retain an explicit range restriction")
        end
        local s=continuousFloater();s.maxMoveDistance=100;s.range=100
        local p=assert(Planner.solve(s));assert(p.continuousCatch and p._aimDistance<=100)
        local actual=advanceToJump(s,p,0);actual.maxMoveDistance=0
        local valid,why=Planner.validateJump(actual,p)
        assert(not valid and why=="Continuous catch exceeds movement limit")
    end)
    test("endzone Floater rejects a pre-goal first touch despite later in-zone central contact",function()
        local s=fixture();s.canDive=false;s.passType="Floater";s.now=100.5;s.maxHorizon=3.5
        s.arc={P0=Vector3.new(0,6,-30),P1=Vector3.new(30,3.5,65),Flight=3.1,Apex=42}
        local old=assert(Planner.solve(s));local first=Planner.firstTouch(s,old)
        local firstZ=Planner.pose(s,old,first.at).Position.Z
        local centralZ=Planner.pose(s,old,old.contactAt).Position.Z
        assert(centralZ>firstZ+.01,"Fixture must separate first touch from central contact")
        s.wrDiveGoalZ=(firstZ+centralZ)/2-.25;s.requireEndzoneCatch=true
        assert(centralZ>=s.wrDiveGoalZ+.25 and firstZ<s.wrDiveGoalZ+.25)
        assert(not Planner.airborneFinish(s,old),"Central contact cannot hide an earlier pre-goal catch")
        local nextPlan=Planner.solve(s)
        assert(not nextPlan or minimumContactZ(s,nextPlan)>=s.wrDiveGoalZ+.25)
    end)
    test("honest in-zone Floater keeps its jump witness and all contact-window samples",function()
        local s=lateFloater();s.canDive=false;local old=assert(Planner.solve(s))
        s.wrDiveGoalZ=minimumContactZ(s,old)-.75;s.requireEndzoneCatch=true
        local p=assert(Planner.solve(s));assert(p.jumpAt and not p.diveAt)
        assert(Planner.airborneFinish(s,p)=="jump")
        assert(minimumContactZ(s,p)>=s.wrDiveGoalZ+.25)
        assert(Planner.validateJump(advanceToJump(s,p,0),p))
    end)
    local function shallowDiveWitness()
        local s=diveFixture();local p=assert(Planner.solve(s))
        -- Rotate an existing valid 3-D catch, preserving all physical margins,
        -- so a delayed dive changes forward progress near the goal boundary.
        local angle=math.atan2(p.direction.Z,p.direction.X)-math.asin(.01)
        local function rotate(v)
            return Vector3.new(v.X*math.cos(angle)+v.Z*math.sin(angle),v.Y,
                -v.X*math.sin(angle)+v.Z*math.cos(angle))
        end
        s.arc={P0=rotate(s.arc.P0),P1=rotate(s.arc.P1),Flight=s.arc.Flight,Apex=s.arc.Apex}
        s.lookDirection=rotate(s.lookDirection);s.passType="Floater"
        p.direction=rotate(p.direction);p.rootTarget=rotate(p.rootTarget)
        p.contactPosition=rotate(p.contactPosition);p._timingFirstTouch=nil
        assert(Planner.airborneFinish(s,p)=="jumpDive")
        return s,p
    end
    test("a delayed dive variant cannot move a nominal endzone catch back outside",function()
        local s,p=shallowDiveWitness();local q={}for k,v in pairs(p)do q[k]=v end
        q.diveAt=p.diveAt+.02;q._diveDelay=p._diveDelay+.02;q._diveDistance=nil
        local nominal,delayed=minimumContactZ(s,p),minimumContactZ(s,q)
        assert(nominal>delayed+.001 and Planner.airborneFinish(s,q)=="jumpDive")
        s.wrDiveGoalZ=(nominal+delayed)/2-.25;s.requireEndzoneCatch=true
        assert(Planner.canDiveFrom(s,Planner.pose(s,p,p.diveAt).Position))
        assert(Planner.airborneFinish(s,p)=="jumpDive")
        assert(not Planner.airborneFinish(s,q),"Delayed physical contact crossed the reserved boundary")
        local selected=Planner.solve(s)
        if selected then
            for ji=0,selected.jumpAt and 2 or 0 do for di=0,selected.diveAt and 2 or 0 do
                local v={}for k,value in pairs(selected)do v[k]=value end
                if v.jumpAt then v.jumpAt=selected.jumpAt+.0175*ji;v._jumpDelay=selected._jumpDelay+.0175*ji end
                if v.diveAt then v.diveAt=selected.diveAt+.01*di;v._diveDelay=selected._diveDelay+.01*di;v._diveDistance=nil end
                assert(minimumContactZ(s,v)>=s.wrDiveGoalZ+.25)
            end end
        end
    end)
    test("fresh jump validation rejects the old pre-goal Floater witness",function()
        local s=lateFloater();s.canDive=false;local p=assert(Planner.solve(s))
        local actual=advanceToJump(s,p,0)
        assert(Planner.validateJump(actual,p))
        actual.wrDiveGoalZ=p.rootTarget.Z;actual.requireEndzoneCatch=true
        assert(not Planner.validateJump(actual,p))
    end)
    test("fresh airborne dive needs in-zone contact in addition to an in-zone dive start",function()
        local s,p=shallowDiveWitness();local actual=dispatch(s,p)
        actual.wrDiveGoalZ=actual.position.Z-.001
        assert(Planner.canDiveFrom(actual,actual.position) and Planner.validateAirborneDive(actual,p))
        actual.requireEndzoneCatch=true
        assert(not Planner.validateAirborneDive(actual,p),"Legal dive origin cannot authorize a short catch")
        actual.wrDiveGoalZ=-100
        assert(Planner.validateAirborneDive(actual,p),"An honest in-zone dive contact must remain available")
    end)
    test("required endzone catch fails closed on missing or invalid goal without changing Bullet or DB",function()
        local s=lateFloater();s.canDive=false;local p=assert(Planner.solve(s))
        for _,goal in ipairs({false,0/0,math.huge}) do
            s.wrDiveGoalZ=goal;s.requireEndzoneCatch=true
            assert(not Planner.airborneFinish(s,p) and not Planner.solve(s))
        end
        s.wrDiveGoalZ=nil
        assert(not Planner.airborneFinish(s,p) and not Planner.solve(s))
        s.requireEndzoneCatch=false;s.passType="Bullet"
        assert(Planner.airborneFinish(s,p)=="jump" and Planner.solve(s))
        s.role="DB";s.requireEndzoneCatch=true
        assert(Planner.airborneFinish(s,p)=="jump")
    end)
    test("earliest Floater reserves real jump dispatch slack instead of a submillisecond frontier",function()
        local s=lateFloater();s.actionTimingEnvelope=false
        local fragile=assert(Planner.solve(s))
        assert(fragile.kind=="jump" and fragile.margin>=s.margin)
        assert(Planner.validateJump(advanceToJump(s,fragile,0),fragile))
        assert(not Planner.validateJump(advanceToJump(s,fragile,.0006),fragile),
            "Fixture must reproduce the old near-zero action slack")
        s.actionTimingEnvelope=nil
        local robust=assert(Planner.solve(s))
        assert(robust.jumpAt<fragile.jumpAt-.03)
        assert(robust.contactAt>=fragile.contactAt and robust.contactAt<fragile.contactAt+.01)
        assert(robust.jumpTimingBudget==.035 and robust.margin>=s.margin)
        for _,late in ipairs({0,.0006,.008,.016,.025,.035}) do
            assert(Planner.validateJump(advanceToJump(s,robust,late),robust),
                "Moving receiver lost the planned jump reserve")
        end
    end)
    test("DB jumps keep contact margin through a 60 ms takeoff delay and fresh movement",function()
        local s=lateFloater();s.role="DB";s.requireAirborne=false;s.preferAirborne=false;s.canDive=false
        local p=assert(Planner.solve(s))
        assert(p.jumpAt and p.jumpTimingBudget==.060 and p.margin>=s.margin)
        for _,late in ipairs({0,.016,.035,.046721,.060}) do
            local delayed={}for key,value in pairs(p)do delayed[key]=value end
            delayed._jumpDelay=p._jumpDelay+late;delayed.jumpAt=p.jumpAt+late
            for _,delta in ipairs({-.012,0,.012})do
                local at=p.contactAt+delta
                local cf,air=Planner.pose(s,delayed,at)
                local a,b,r=Planner.capsule(s,cf,air)
                assert(r-Planner.segmentDistance(Planner.ballAt(s.arc,at-s.launchAt),a,b)>=s.margin-1e-7,
                    "The advertised DB delay lost the actual contact-volume margin")
            end
            local fresh=advanceToJump(s,p,late)
            assert((fresh.position-s.position).Magnitude>.1,"Fixture must advance the receiver, not just the clock")
            assert(Planner.validateJump(fresh,p),"Fresh DB dispatch must retain the funded delayed contact")
        end
    end)
    test("larger DB takeoff reserve leaves WR jump and dive timing budgets unchanged",function()
        local wr=diveFixture();local p=assert(Planner.solve(wr))
        assert(p.jumpAt and p.diveAt and p.jumpTimingBudget==.035 and p.diveTimingBudget==.020)
        local delayed={}for key,value in pairs(p)do delayed[key]=value end
        delayed._jumpDelay=p._jumpDelay+.035;delayed.jumpAt=p.jumpAt+.035
        delayed._diveDelay=p._diveDelay+.020;delayed.diveAt=p.diveAt+.020;delayed._diveDistance=nil
        assert(Planner.airborneFinish(wr,delayed)=="jumpDive")
        assert(Planner.validateJump(advanceToJump(wr,p,.035),p))
    end)
    test("DB chooses a later valid contact when 35 ms reserve would miss an overhead ball",function()
        local s=fixture();s.role="DB";s.requireAirborne=false;s.preferAirborne=false;s.canDive=false
        s.walkSpeed=0;s.runSpeed=0;s.velocity=Vector3.zero;s.reactionDelay=0
        s.launchAt=99.8;s.maxHorizon=.65
        s.arc={P0=Vector3.new(0,13,0),P1=Vector3.new(0,13,0),Flight=1000,Apex=0}
        local p=assert(Planner.solve(s));assert(p.jumpAt==s.now and p.jumpTimingBudget==.060)
        -- Solve the rising root-height threshold directly. The earliest
        -- contact sample must still have radius-minus-distance >= .4.
        local rise=13-s.config.CatchRadius+s.margin-s.groundRootY-s.config.HandUpOffset
        local ascent=(s.jumpSpeed-math.sqrt(s.jumpSpeed*s.jumpSpeed-2*s.gravity*rise))/s.gravity
        assert(p.contactAt>=p.jumpAt+.060+ascent+.012-1e-7)
        local oldFrontier={}for key,value in pairs(p)do oldFrontier[key]=value end
        oldFrontier.contactAt=p.jumpAt+.035+ascent+.012
        local actual={}for key,value in pairs(s)do actual[key]=value end
        actual.now=p.jumpAt+.046721
        assert(not Planner.validateJump(actual,oldFrontier),"35 ms frontier must reproduce the missed overhead contact")
        assert(Planner.validateJump(actual,p),"New contact must survive the same observed delay")
        actual.now=p.jumpAt+.060
        assert(Planner.validateJump(actual,p),"The advertised full reserve must remain geometrically valid")
    end)
    test("jump dive witnesses survive separate action delays and preserve takeoff time",function()
        local s=diveFixture();local p=assert(Planner.solve(s))
        assert(p.diveAt and p.jumpTimingBudget==.035 and p.diveTimingBudget==.020)
        assert(p.diveAt-p.jumpAt>=.095)
        for ji=0,2 do for di=0,2 do
            local q={}for key,value in pairs(p)do q[key]=value end
            q._jumpDelay=p._jumpDelay+ji*.0175;q.jumpAt=s.now+q._jumpDelay
            q._diveDelay=p._diveDelay+di*.010;q.diveAt=s.now+q._diveDelay;q._diveDistance=nil
            assert(q.diveAt-q.jumpAt>=.06)
            assert(Planner.airborneFinish(s,q)=="jumpDive")
            for _,delta in ipairs({-.012,0,.012})do
                local at=q.contactAt+delta;local cf,air=Planner.pose(s,q,at)
                local a,b,r=Planner.capsule(s,cf,air)
                assert(r-Planner.segmentDistance(Planner.ballAt(s.arc,at-s.launchAt),a,b)>=s.margin-1e-7)
            end
        end end
        assert(Planner.validateJump(advanceToJump(s,p,.035),p))
        local compressed={}for key,value in pairs(p)do compressed[key]=value end
        compressed.diveAt=compressed.jumpAt+.06
        local valid,why=Planner.validateJump(advanceToJump(s,compressed,.0006),compressed)
        assert(not valid and why=="Insufficient takeoff time before dive")
    end)
    test("already airborne dive reserves dive dispatch time without inventing a new jump",function()
        local original=diveFixture();local jumpDive=assert(Planner.solve(original))
        local s=dispatch(original,jumpDive);s.now=s.now-.04
        local cf,air,vy=Planner.pose(original,jumpDive,s.now)
        s.position=cf.Position;s.velocity=jumpDive.direction*27+Vector3.new(0,vy,0)
        s.grounded=false;s.canJump=false;s.reactionDelay=0;s.canDive=true
        local p=assert(Planner.solve(s))
        assert(air and p.diveAt and not p.jumpAt and p.jumpTimingBudget==0 and p.diveTimingBudget==.020)
        assert(p.margin>=s.margin)
    end)
    test("opponent possible reach is not delayed by the own action timing reserve",function()
        local s=lateFloater();s.opponent={position=Vector3.new(-27,3,70),velocity=Vector3.zero,
            grounded=true,walkSpeed=27,runSpeed=20,sprintSeconds=4,canJump=true,canDive=true}
        s.actionTimingEnvelope=false;local old=assert(Planner.solve(s))
        s.actionTimingEnvelope=nil;local new=assert(Planner.solve(s))
        assert(old.defenderAt and new.defenderAt==old.defenderAt)
    end)
    test("already grounded overlap has no deliberate catch plan and reports that limitation",function()
        local s=fixture();s.launchAt=s.now-.2
        s.arc={P0=Vector3.new(0,4,0),P1=Vector3.new(0,4,0),Flight=100,Apex=0}
        local p,why=Planner.solve(s)
        assert(p==nil and why=="No robust airborne WR contact available")
    end)
    test("grounded dive recovery is never called an airborne catch",function()
        local s=fixture();s.canJump=false;s.walkSpeed=0;s.runSpeed=0
        local p={kind="dive",direction=Vector3.new(1,0,0),_speed=0,_runSpeed=0,_sprintSeconds=0,
            _reaction=0,_aimDistance=0,_diveDelay=.1,diveAt=100.1,contactAt=101,
            contactPosition=Vector3.new(14.7,1,0),rootTarget=Vector3.new(14.7,.6,0)}
        assert(Planner.airborneFinish(s,p,{at=100.8})==nil)
    end)
    test("later airborne pose cannot hide contact before the dive",function()
        local s=diveFixture();local p=assert(Planner.solve(s))
        local finish,why=Planner.airborneFinish(s,p,{at=p.diveAt-.001})
        assert(finish==nil and why=="Contact precedes the dive")
    end)
    test("dispatch check uses observed current position and rejects changed trajectory",function()
        local s=diveFixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        assert(Planner.validateAirborneDive(fresh,p))
        fresh.position=fresh.position+Vector3.new(40,0,0)
        assert(not Planner.validateAirborneDive(fresh,p))
    end)
    test("dispatch check refuses grounded or shortened native-air reach",function()
        local s=diveFixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        fresh.grounded=true;assert(not Planner.validateAirborneDive(fresh,p))
        fresh.grounded=false;fresh.reachAirborne=false
        assert(not Planner.validateAirborneDive(fresh,p))
    end)
    test("WR aerial flags leave DB earliest-contact selection unchanged",function()
        local s=fixture();s.role="DB";s.requireAirborne=false;s.preferAirborne=false;s.preferJumpDive=false
        local before=assert(Planner.solve(s));s.preferAirborne=true;s.requireAirborne=true;s.preferJumpDive=true
        local after=assert(Planner.solve(s))
        assert(after.kind==before.kind and after.contactAt==before.contactAt)
        assert(after.jumpAt==before.jumpAt and after.diveAt==before.diveAt and after.margin==before.margin)
        assert(after.airborneFinish==nil)
    end)
    test("no arc and unreachable pursuit never invent a jump or dive",function()
        local s=fixture();s.arc=nil;assert(Planner.solve(s)==nil and Planner.pursuit(s)==nil)
        s=fixture();s.arc.P0=s.arc.P0+Vector3.new(200,0,0);s.arc.P1=s.arc.P1+Vector3.new(200,0,0)
        assert(Planner.solve(s)==nil)
        local p=assert(Planner.pursuit(s));assert(p.reachable==false and not p.jumpAt and not p.diveAt)
    end)
    test("floater takes earlier robust airborne contact instead of later downfield contact",function()
        local s=fixture();s.arc.P1=Vector3.new(30,3.5,35);s.arc.Apex=10;s.arc.Flight=1.5
        s.passType="Bullet";local later=assert(Planner.solve(s))
        s.passType="Floater";local early=assert(Planner.solve(s))
        assert(early.airborneFinish and early.contactAt<later.contactAt-.1)
        assert(early.margin>=s.margin and not early.risk and early.earliestAirborne)
        local current=Planner.pose(s,early,early.firstTouchAt)
        assert(current.Position.Y>s.turfY+.75)
    end)
    test("late dispatch is rejected instead of chasing a missed airborne contact",function()
        local s=diveFixture();local p=assert(Planner.solve(s));local fresh=dispatch(s,p)
        fresh.now=p.contactAt+.02
        assert(not Planner.validateAirborneDive(fresh,p))
    end)
    test("adaptive first contact finds short grounded bullet overlap before a later jump",function()
        local s=fixture();s.arc={P0=Vector3.new(-9.49,7.2,0),P1=Vector3.new(90.51,7.2,0),Flight=1,Apex=0}
        s.timingMargin=.001
        local p={kind="jump",direction=Vector3.new(1,0,0),_speed=27,_runSpeed=27,_sprintSeconds=4,
            _reaction=0,_aimDistance=100,_jumpDelay=.16,jumpAt=100.16,contactAt=100.174}
        p.contactPosition=Planner.ballAt(s.arc,.174);p.rootTarget=Planner.pose(s,p,p.contactAt).Position
        for _,at in ipairs({100.173,100.174,100.175}) do
            local cf,air=Planner.pose(s,p,at);local a,b,r=Planner.capsule(s,cf,air)
            assert(r-Planner.segmentDistance(Planner.ballAt(s.arc,at-s.launchAt),a,b)>=s.margin)
        end
        s.requireAirborne=false;local coarse=Planner.firstTouch(s,p)
        assert(coarse.at>=p.jumpAt,"Fixture no longer reproduces the 40 ms alias")
        s.requireAirborne=true;local fine=Planner.firstTouch(s,p)
        assert(fine.at<100.14 and fine.at>100.12 and not fine.uncertain)
        local _,air=Planner.pose(s,p,fine.at);assert(not air)
        assert(Planner.airborneFinish(s,p,fine)==nil)
    end)
    test("first-contact sampling budget fails closed",function()
        local s=fixture();local p=assert(Planner.solve(s));p.contactAt=110
        local touch=Planner.firstTouch(s,p)
        assert(touch.uncertain and Planner.airborneFinish(s,p,touch)==nil)
    end)
    local staleGuard=assert(source:match("(    local function cancelStaleAction.-)    local walls"))
    local actionSection=assert(source:match("(        local actionNow=workspace:GetServerTimeNow%(%).-)        message=plan.reachable==false"))
    local dispatchFixture=assert(loadstring([[
        return function(realPlanner)
        return function(input,clocks,role,options)
            options=options or {}
            local result={jumps=0,dives=0,cancels=0,finished=false,dbChecks=0}
            local plan=input
            local now=100
            local nextSolve=0
            local jumped,dived=options.jumped==true,false
            local jumpRequest,lastSnapshot,lastJump,lastDive=options.jumpRequest,{},options.lastJump or 0,0
            local reachAirborne,message,motion=options.reachAirborne,nil,nil
            local atTarget,parkedPosition=false,nil
            local counters={dives=0}
            local clockIndex=0
            local workspace={GetServerTimeNow=function()
                clockIndex=math.min(clockIndex+1,#clocks)
                return clocks[clockIndex]
            end}
            local s={role=role}
            local root={Position=options.position or Vector3.new(0,5,0),AssemblyLinearVelocity=Vector3.zero}
            local h={FloorMaterial=options.floorMaterial or "Air",PlatformStand=false}
            function h:Move()end
            function h:ChangeState()result.jumps=result.jumps+1 end
            local Enum={HumanoidStateType={Jumping="Jumping"},Material={Air="Air"}}
            local Config={Moves={Dive={Cooldown=1.6}}}
            local Moves={Upright=function()return true end}
            local function motionState()return options.motion or {grounded=true,diveModeMatchesMotion=true}end
            local function log()end
            local function xyz()return {}end
            local function snapshot()
                local goal=options.goalZ
                if goal==nil and not options.missingGoal then goal=-100 end
                return {role=role,wrDiveGoalZ=goal,position=root.Position,bounds=options.bounds,
                    nativeAirborne=options.nativeAirborne,physicalAirborne=options.nativeAirborne,
                    grounded=options.nativeAirborne~=true,canDive=true}
            end
            local function solveActual()return nil end
            local function divePermitted()return true end
            local function releaseSprint()end
            local function nativeDive()result.dives=result.dives+1;h.PlatformStand=true end
            local function cancel()result.cancels=result.cancels+1;plan=nil;jumpRequest=nil end
            local Planner={validateAirborneDive=function()
                    if options.validationPosition then root.Position=options.validationPosition end
                    return true
                end,
                canDiveFrom=realPlanner.canDiveFrom,
                rejectUnreachableDBAirborneDive=function()
                    result.dbChecks=result.dbChecks+1
                    return options.rejectDB==true,"checked DB trajectory",10,2
                end,
                validateJump=function()return true end,
                pose=function()return {Position=root.Position}end}
    ]]..staleGuard..[[
            local function tick()
    ]]..actionSection..[[
                result.finished=true
            end
            tick()
            result.nextSolve=nextSolve;result.jumpRequested=h.Jump==true
            return result
        end
        end
    ]]))()(Planner)
    test("slow planning cancels overdue jump and dive before inputs for both roles",function()
        for _,role in ipairs({"WR","DB"})do
            for _,kind in ipairs({"jump","dive"})do
                local p={kind=kind,contactAt=100.5,direction=Vector3.new(1,0,0)}
                p[kind=="jump" and "jumpAt" or "diveAt"]=100.025
                local r=dispatchFixture(p,{100.12},role)
                assert(r.cancels==1 and r.jumps==0 and r.dives==0 and not r.jumpRequested)
                assert(not r.finished and math.abs(r.nextSolve-100.165)<.000001)
            end
        end
    end)
    test("elapsed contact blocks an action even inside its 75 ms action grace",function()
        local r=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.04},{100.05},"DB")
        assert(r.cancels==1 and r.jumps==0 and not r.finished)
    end)
    test("clock delay during pre-jump native checks is caught at actual dispatch",function()
        local r=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.5},{100.03,100.12},"WR")
        assert(r.cancels==1 and r.jumps==0 and not r.jumpRequested and not r.finished)
    end)
    test("clock delay during pre-dive validation is caught at actual dispatch",function()
        local r=dispatchFixture({kind="dive",diveAt=100.02,contactAt=100.5,
            airborneFinish="jumpDive",direction=Vector3.new(1,0,0)},{100.03,100.03,100.12},"WR")
        assert(r.cancels==1 and r.dives==0 and not r.finished)
    end)
    test("future and timely actions retain their original dispatch behavior",function()
        local wait=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.5},{100.01},"WR")
        assert(wait.finished and wait.cancels==0 and wait.jumps==0)
        local jump=dispatchFixture({kind="jump",jumpAt=100.02,contactAt=100.5},{100.03},"DB")
        assert(jump.finished and jump.cancels==0 and jump.jumps==1 and jump.jumpRequested)
        local dive=dispatchFixture({kind="dive",diveAt=100.02,contactAt=100.5,
            direction=Vector3.new(1,0,0)},{100.03},"DB")
        assert(dive.finished and dive.cancels==0 and dive.dives==1)
    end)
    test("live WR dive dispatch uses actual origin instead of stale plan or in-goal contact",function()
        local function plan()
            return {kind="dive",diveAt=100.02,contactAt=100.5,airborneFinish="jumpDive",
                direction=Vector3.new(0,0,1),rootTarget=Vector3.new(0,5,10)}
        end
        for _,options in ipairs({{goalZ=.001},{missingGoal=true},
            {goalZ=0,validationPosition=Vector3.new(0,5,-.001)},
            {goalZ=0,bounds={minX=.001,maxX=10,minZ=0,maxZ=20}}}) do
            local r=dispatchFixture(plan(),{100.03},"WR",options)
            assert(r.cancels==1 and r.dives==0 and not r.finished,
                "A permitted stale plan bypassed the final actual-origin gate")
        end
        local inside=dispatchFixture(plan(),{100.03},"WR",{goalZ=0})
        assert(inside.dives==1 and inside.cancels==0 and inside.finished)
        local db=dispatchFixture(plan(),{100.03},"DB",{goalZ=1000})
        assert(db.dives==1 and db.cancels==0 and db.finished)
    end)
    local confirmation=assert(source:match('        h.Jump=jumpRequest~=nil\n(        if jumpRequest then.-)        if h.PlatformStand and not dived then'))
    local pendingFixture=assert(loadstring([[
        return function(options)
            local result={retries=0,cancels=0,confirmed=0,finished=false}
            local now=options.now
            local plan={kind="jump",jumpAt=100.025,contactAt=options.contactAt or 100.5}
            local lastSnapshot={jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,now=100}
            local jumpRequest={time=100,dispatchedAt=100.03,y=3}
            local jumped,dived=true,false
            local s={role=options.role}
            local root={Position=Vector3.new(0,3+(options.rise or 0),0),
                AssemblyLinearVelocity=Vector3.new(0,options.velocity or 0,0)}
            local Enum={Material={Air="Air"},HumanoidStateType={Jumping="Jumping",Freefall="Freefall"}}
            local h={FloorMaterial=options.airborne and "Air" or "Ground",Jump=true,
                GetState=function()return "Running" end}
            function h:ChangeState()result.retries=result.retries+1 end
            local workspace={GetServerTimeNow=function()return options.clock or now end}
            local function log()end
            local function xyz()return {}end
            local function cancel()result.cancels=result.cancels+1;plan=nil;jumpRequest=nil end
            local lastJump,confirmedCatchJump,groundedReachSince,reachAirborne
            local nextSolve,message=0,nil
            local counters={jumps=0}
    ]]..staleGuard..[[
            local function tick()
    ]]..confirmation..[[
                result.finished=true
            end
            tick()
            result.confirmed=counters.jumps;result.nextSolve=nextSolve
            result.held=h.Jump;result.pending=jumpRequest~=nil;result.lastJump=lastJump
            return result
        end
    ]]))()
    test("unconfirmed jump cannot retry or remain held after contact for either role",function()
        for _,role in ipairs({"WR","DB"})do
            local r=pendingFixture({role=role,now=100.08,contactAt=100.06})
            assert(r.cancels==1 and r.retries==0 and not r.held and not r.pending and not r.finished)
            assert(math.abs(r.nextSolve-100.125)<.000001)
        end
    end)
    test("unconfirmed jump beyond action grace cancels even with contact still future",function()
        for _,role in ipairs({"WR","DB"})do
            local r=pendingFixture({role=role,now=100.11})
            assert(r.cancels==1 and r.retries==0 and not r.held and not r.pending)
        end
    end)
    test("unconfirmed retry uses fresh clock instead of old frame time",function()
        local r=pendingFixture({role="DB",now=100.08,clock=100.11})
        assert(r.cancels==1 and r.retries==0 and not r.held)
        assert(math.abs(r.nextSolve-100.155)<.000001)
    end)
    test("timely pending native request may retry once while contact remains future",function()
        for _,role in ipairs({"WR","DB"})do
            local r=pendingFixture({role=role,now=100.08})
            assert(r.finished and r.cancels==0 and r.retries==1 and r.held and r.pending)
        end
    end)
    test("observed timely takeoff confirms even when confirmation frame comes later",function()
        local elapsed=.08
        local rise=math.sqrt(2*196.2*6)*elapsed-.5*196.2*elapsed*elapsed
        for _,role in ipairs({"WR","DB"})do
            local r=pendingFixture({role=role,now=100.11,rise=rise,velocity=30,airborne=true})
            assert(r.finished and r.cancels==0 and r.retries==0 and r.confirmed==1)
            assert(not r.held and not r.pending and math.abs(r.lastJump-100.03)<.000001)
        end
    end)
    local function jumpWitness(role)
        local s=fixture();s.role=role;s.canDive=false;s.walkSpeed=0;s.runSpeed=0
        s.arc={P0=Vector3.new(0,13,0),P1=Vector3.new(0,13,0),Flight=1000,Apex=0}
        s.launchAt=99.8;s.maxHorizon=.65
        s.requireAirborne=role=="WR";s.preferAirborne=role=="WR"
        local p=assert(Planner.solve(s))
        local actual={}for key,value in pairs(s)do actual[key]=value end
        actual.now=p.jumpAt
        return s,p,actual
    end
    test("fresh jump check accepts timely native contact for both roles",function()
        for _,role in ipairs({"DB","WR"})do
            local s,p,actual=jumpWitness(role)
            assert(Planner.validateJump(actual,p))
            assert(p.jumpAt==actual.now and s.now==100,"Validation mutated the plan or snapshot")
        end
    end)
    test("50 ms late jump within blanket deadline still fails its real contact geometry",function()
        for _,role in ipairs({"DB","WR"})do
            local _,p,actual=jumpWitness(role)
            -- Use a real early robust witness, even when WR normally chooses a later one.
            p.contactAt=p.jumpAt+.0888671875
            actual.now=p.jumpAt+.05
            assert(actual.now<p.contactAt)
            local valid,why=Planner.validateJump(actual,p)
            assert(not valid and why=="Jump no longer reaches the planned ball contact")
        end
    end)
    test("late but geometrically valid jump is accepted instead of tightening every deadline",function()
        local _,p,actual=jumpWitness("DB")
        p.contactAt=p.jumpAt+.23;actual.now=p.jumpAt+.05
        assert(Planner.validateJump(actual,p))
    end)
    test("fresh jump rejects displaced position or unavailable native jump",function()
        local _,p,actual=jumpWitness("DB")
        actual.position=actual.position+Vector3.new(8,0,0)
        assert(not Planner.validateJump(actual,p))
        actual.position=Vector3.new(0,3,0);actual.canJump=false
        assert(not Planner.validateJump(actual,p))
    end)
    test("jump check preserves future dive time and refuses compressed takeoff interval",function()
        local s=diveFixture();local p=assert(Planner.solve(s))
        p.approachTarget=Planner.pose(s,p,p.diveAt-.000001).Position
        local cf=Planner.pose(s,p,p.jumpAt-.000001)
        local actual={}for key,value in pairs(s)do actual[key]=value end
        actual.now=p.jumpAt;actual.position=cf.Position;actual.velocity=p.direction*27
        assert(Planner.validateJump(actual,p))
        actual.now=p.diveAt-.04
        local valid,why=Planner.validateJump(actual,p)
        assert(not valid and why=="Insufficient takeoff time before dive")
    end)
    test("jump validation projects only remaining travel after reaching the target",function()
        local s=fixture();s.role="DB";s.requireAirborne=false;s.preferAirborne=false
        s.now=100.1;s.launchAt=99.8;s.position=Vector3.new(10,3,0);s.velocity=Vector3.zero
        s.arc={P0=Vector3.new(10,13,0),P1=Vector3.new(10,13,0),Flight=1000,Apex=0}
        local p={kind="jump",direction=Vector3.new(1,0,0),jumpAt=100.1,contactAt=100.3,
            rootTarget=Vector3.new(10,8,0),_aimDistance=10,_speed=27,_runSpeed=20,
            _sprintSeconds=4,_reaction=.025,_jumpDelay=.1}
        assert(Planner.validateJump(s,p))
        assert(p._aimDistance==10,"Original anchor was mutated instead of making a validation copy")
    end)
    test("controller exits catch actions outside live ball phase",function()
        local gate=assert(source:match('(        if s.phase~="Live" or not s.arc or not s.launchAt then.-)        navigation=false\n        if tackleAssist'))
        local factory=assert(loadstring([[
            local calls=0
            local function cancel()end
            local function healthyCharacter()return nil,nil end
            local function updateFullplay()return false end
            local function release()end
            local dt,now=0.016,100
            local function run(s)
        ]]..gate..[[
                calls=calls+1
            end
            return run,function()return calls end
        ]]))
        local run,calls=factory()
        for _,s in ipairs({{phase="Hike",arc={},launchAt=100},{phase="Live",launchAt=100},
            {phase="Live",arc={}}}) do run(s)end
        assert(calls()==0)
        run({phase="Live",arc={},launchAt=100});assert(calls()==1)
    end)
    local function recordedDBAirborneStop()
        local s=fixture()
        s.role="DB";s.requireAirborne=false;s.preferAirborne=false;s.preferJumpDive=false
        s.now=100;s.launchAt=97.560481
        s.arc={P0=Vector3.new(18.893924713134766,7.636868476867676,-53.83334732055664),
            P1=Vector3.new(59.323341369628906,5.136868476867676,114.45716857910156),Flight=3.1,Apex=42}
        s.position=Vector3.new(52.1050910949707,4.636868000030518,98.02066040039062)
        s.velocity=Vector3.new(19.359466552734375,0,18.82049560546875)
        s.lookDirection=s.velocity.Unit;s.steeringDirection=s.velocity.Unit
        s.jumpSpeed=48.52215950860912;s.gravity=196.1999969482422
        s.groundRootY=s.position.Y;s.turfY=1.63686865568161;s.diveTurfY=s.turfY
        s.diveDistance=14.731816774606706;s.sprintSeconds=1.56;s.reactionDelay=0
        s.maxHorizon=1.060481
        s.config.Pass={Floater={Flight=3.1,Apex=42},Bullet={Flight=.9,Apex=0}}
        s.bounds={minX=-29.7121302485466,maxX=67.49998158216476,
            minZ=-43.512135207653046,maxZ=151.9120985865593}
        return s
    end
    test("recorded DB floater keeps moving through contact instead of stopping during its jump",function()
        local s=recordedDBAirborneStop();local p=assert(Planner.solve(s))
        -- The recorded old plan stopped 214 ms before contact while airborne;
        -- native momentum moved 1.816 studs beyond it before repeated reversals.
        local oldJump,oldStop,oldContact=100.1340624,100.2202789,100.4340624
        assert(oldStop>oldJump and oldStop<oldContact)
        assert(p.kind=="jump" and not p.diveAt and p.continuousCatch)
        assert(p.margin>=.4 and p.jumpTimingBudget==.06 and not p.risk)
        assert(math.abs(p.contactAt-oldContact)<.003 and p.stopAt>=p.contactAt+.012)
        local before=Planner.pose(s,p,p.contactAt-.012).Position
        local after=Planner.pose(s,p,p.contactAt+.012).Position
        assert(((after-before)*Vector3.new(1,0,1)).Magnitude>.1)
        local fresh=advanceToJump(s,p,0)
        assert(Planner.validateJump(fresh,p),"Paced DB witness failed fresh takeoff validation")
    end)
    test("fresh paced DB jump rejects a shifted remaining path outside the field",function()
        local s=recordedDBAirborneStop();local p=assert(Planner.solve(s))
        local fresh=advanceToJump(s,p,0)
        local final=Planner.pose(s,p,p.stopAt).Position
        fresh.bounds={minX=s.bounds.minX,maxX=final.X-.1,
            minZ=s.bounds.minZ,maxZ=s.bounds.maxZ}
        local valid,why=Planner.validateJump(fresh,p)
        assert(not valid and why=="Continuous DB catch leaves field bounds",tostring(why))
        local translated=recordedDBAirborneStop();local shift=Vector3.new(100,0,200)
        translated.position=translated.position+shift
        translated.arc={P0=translated.arc.P0+shift,P1=translated.arc.P1+shift,Flight=3.1,Apex=42}
        translated.bounds={minX=s.bounds.minX+100,maxX=s.bounds.maxX+100,
            minZ=s.bounds.minZ+200,maxZ=s.bounds.maxZ+200}
        local moved=assert(Planner.solve(translated))
        assert(moved.continuousCatch and math.abs(moved.contactAt-p.contactAt)<.00001)
        assert(Planner.validateJump(advanceToJump(translated,moved,0),moved))
    end)
    test("DB pacing excludes stationary holds bullet arcs dives and optimistic opponent envelopes",function()
        local s=fixture();s.role="DB";s.requireAirborne=false;s.preferAirborne=false
        s.config.Pass={Floater={Flight=3.1,Apex=42},Bullet={Flight=.9,Apex=0}}
        local bullet=assert(Planner.solve(s));assert(not bullet.continuousCatch)
        local parked=recordedDBAirborneStop();parked.walkSpeed=0;parked.runSpeed=0
        parked.velocity=Vector3.zero;parked.canDive=false
        parked.position=Vector3.new(56.37,parked.position.Y,102.16)
        local stationary=assert(Planner.solve(parked));assert(not stationary.continuousCatch)
        local enemy=recordedDBAirborneStop();enemy.optimisticReachEnvelope=true
        local possible=assert(Planner.solve(enemy));assert(not possible.continuousCatch)
        local diving=fixture();diving.role="DB";diving.requireAirborne=false;diving.preferAirborne=false
        diving.config.Pass=s.config.Pass;diving.canJump=false
        local reach=Planner.solve(diving)
        if reach and reach.diveAt then assert(not reach.continuousCatch) end
    end)
    local function recordedStaleDBDive()
        local s=fixture()
        s.role="DB";s.preferAirborne=false;s.requireAirborne=false
        s.now=100;s.launchAt=99.422016
        s.position=Vector3.new(33.546302795410156,7.789941310882568,49.895320892333984)
        s.velocity=Vector3.new(-7.677981853485107,45.2568473815918,-25.846139907836914)
        s.arc={P0=Vector3.new(18.893924713134766,7.636868476867676,-53.83334732055664),
            P1=Vector3.new(34.86635971069336,5.136868476867676,56.308685302734375),Flight=1.05,Apex=6}
        s.grounded=false;s.nativeAirborne=true;s.physicalAirborne=true;s.reachAirborne=true
        s.canJump=false;s.canDive=true;s.gravity=196.1999969482422
        s.jumpSpeed=48.52215950860912;s.diveDistance=14.731816774606706
        s.turfY=1.63686865568161;s.diveTurfY=s.turfY;s.groundRootY=s.turfY+3
        local p={kind="jumpDive",jumpAt=99.867423,diveAt=99.996593,contactAt=100.246593,
            direction=Vector3.new(-.10895305126905441,0,-.9940468668937683),
            _speed=27,_runSpeed=20,_sprintSeconds=2.44,_reaction=0,_aimDistance=0}
        return s,p
    end
    test("recorded delayed DB takeoff rejects a dive with no modeled contact remaining",function()
        local s,p=recordedStaleDBDive()
        local rejected,why,checks,gap=Planner.rejectUnreachableDBAirborneDive(s,p)
        assert(rejected and why=="Observed DB dive has no modeled contact before turf")
        assert(checks>1 and checks<=320 and gap>.9)
        assert(p.kind=="jumpDive" and p.jumpAt==99.867423 and p.diveAt==99.996593,
            "Checking fresh motion must not mutate the existing plan")
        assert(s.reachAirborne==true and s.now==100)
    end)
    test("DB no-contact check preserves a legitimate grounded finish",function()
        local s=fixture();s.role="DB";s.now=100;s.launchAt=99.9
        s.grounded=false;s.nativeAirborne=true;s.physicalAirborne=true;s.reachAirborne=nil
        s.position=Vector3.new(0,4,0);s.velocity=Vector3.zero
        s.arc={P0=Vector3.new(0,12,16),P1=Vector3.new(0,0,16),Flight=.6,Apex=0}
        local p={kind="dive",diveAt=100,contactAt=100.4,direction=Vector3.new(0,0,1),
            _diveDelay=0,_speed=27,_runSpeed=20,_sprintSeconds=4,_reaction=0,_aimDistance=0}
        local cf,air=Planner.pose(s,p,p.contactAt)
        local w,h,r=Planner.capsule(s,cf,air)
        assert(not air and r-Planner.segmentDistance(Planner.ballAt(s.arc,.5),w,h)>.4)
        assert(not Planner.rejectUnreachableDBAirborneDive(s,p),"DB finish must not use WR airborne-only policy")
    end)
    test("DB no-contact check retains near intervals and unbounded horizons",function()
        local s,p=recordedStaleDBDive()
        local actual={}for k,v in pairs(p)do actual[k]=v end
        actual.kind="dive";actual.jumpAt=nil;actual._jumpDelay=nil
        actual.diveAt=s.now;actual._diveDelay=0
        local at=.08137;local cf,air=Planner.pose(s,actual,s.now+at)
        local _,hands,r=Planner.capsule(s,cf,air)
        local contact=hands+Vector3.new(0,r-.0001,0)
        local velocity=Vector3.new(900,-40,0);local elapsed=s.now+at-s.launchAt
        s.arc={P0=contact-velocity*elapsed,P1=contact+velocity*(1.05-elapsed),Flight=1.05,Apex=0}
        local rejected=Planner.rejectUnreachableDBAirborneDive(s,p)
        assert(not rejected,"A narrow contact between scan centers must remain possible")
        s,p=recordedStaleDBDive();s.arc.Flight=10
        assert(not Planner.rejectUnreachableDBAirborneDive(s,p),"A bounded check cannot rule out unexamined later contact")
    end)
    test("DB motion bound includes the fixed one-stud tipped waist with small configured offsets",function()
        local s=fixture();s.role="DB";s.now=100;s.launchAt=99.8
        s.position=Vector3.new(0,6.1,0);s.velocity=Vector3.zero
        s.grounded=false;s.nativeAirborne=true;s.physicalAirborne=true;s.reachAirborne=true
        s.gravity=.01;s.jumpSpeed=0;s.walkSpeed=0;s.runSpeed=0;s.sprintSeconds=0
        s.turfY=3;s.diveTurfY=3;s.groundRootY=6;s.diveDistance=0
        s.config.CatchRadius=.00001;s.config.DiveCatchRadius=.00001
        s.config.WaistDrop=.05;s.config.HandOffset=.05;s.config.HandUpOffset=.05;s.config.DiveReach=.05
        s.arc={P0=Vector3.new(0,6.7767162880057,-.8263047945345675),
            P1=Vector3.new(0,2.5767162880056995,-.8263047945345675),Flight=1.05,Apex=0}
        local p={kind="dive",diveAt=100,contactAt=100.4,direction=Vector3.new(0,0,1),
            _diveDelay=0,_aimDistance=0,_reaction=0,_speed=0,_runSpeed=0,_sprintSeconds=0}
        local cf,air=Planner.pose(s,p,100.11);local w,h,r=Planner.capsule(s,cf,air)
        assert(r-Planner.segmentDistance(Planner.ballAt(s.arc,.31),w,h)>0,
            "The authored narrow tipped-waist contact must exist")
        assert(not Planner.rejectUnreachableDBAirborneDive(s,p),
            "Fixed waist extent must bound rotation even when configured offsets are smaller")
    end)
    test("DB no-contact check never grants native state or changes other roles",function()
        for _,gate in ipairs({"grounded","native","reach","cooldown","WR"})do
            local s,p=recordedStaleDBDive()
            if gate=="grounded" then s.grounded=true elseif gate=="native" then s.nativeAirborne=false
            elseif gate=="reach" then s.reachAirborne=false elseif gate=="cooldown" then s.canDive=false
            else s.role="WR" end
            assert(not Planner.rejectUnreachableDBAirborneDive(s,p),gate)
        end
    end)
    test("live DB impossible-contact check replans before diving and retains uncertain dives",function()
        local function plan()return {kind="dive",diveAt=100.02,contactAt=100.5,
            direction=Vector3.new(1,0,0)}end
        local motion={grounded=false,nativeAirborne=true,physicalAirborne=true,diveModeMatchesMotion=true}
        local blocked=dispatchFixture(plan(),{100.03},"DB",{rejectDB=true,nativeAirborne=true,motion=motion})
        assert(blocked.dbChecks==1 and blocked.cancels==1 and blocked.dives==0 and not blocked.finished)
        local retained=dispatchFixture(plan(),{100.03},"DB",{rejectDB=false,nativeAirborne=true,motion=motion})
        assert(retained.dbChecks==1 and retained.cancels==0 and retained.dives==1 and retained.finished)
    end)
    test("native dive guards precede the DB model check and grounded dives remain available",function()
        local function plan()return {kind="dive",diveAt=100.02,contactAt=100.5,
            direction=Vector3.new(1,0,0)}end
        local wrongMode=dispatchFixture(plan(),{100.03},"DB",{rejectDB=true,nativeAirborne=false,
            motion={grounded=false,physicalAirborne=true,nativeAirborne=false,diveModeMatchesMotion=false}})
        assert(wrongMode.cancels==1 and wrongMode.dbChecks==0 and wrongMode.dives==0)
        local awaiting=plan();awaiting.jumpAt=99.9
        local waiting=dispatchFixture(awaiting,{100.03},"DB",{rejectDB=true,jumped=true,jumpRequest={},
            nativeAirborne=true,motion={grounded=false,nativeAirborne=true,diveModeMatchesMotion=true}})
        assert(waiting.dbChecks==0 and waiting.dives==0)
        local ground=dispatchFixture(plan(),{100.03},"DB",{floorMaterial="Ground",nativeAirborne=false,
            motion={grounded=true,nativeAirborne=false,physicalAirborne=false,diveModeMatchesMotion=true}})
        assert(ground.cancels==0 and ground.dives==1)
    end)
    return report
end
