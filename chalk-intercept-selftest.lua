-- Local math tests only: no characters, services, inputs or remote calls.
-- Usage: loadstring(testSource)()(Planner)
return function(Planner)
    local results,failed={},0
    local benchmark
    local function check(condition,message)
        assert(condition,message or "check failed")
    end
    local function near(a,b,tolerance)
        check(math.abs(a-b)<=(tolerance or 0.0001),string.format("expected %.6f, got %.6f",b,a))
    end
    local function nearVector(a,b,tolerance)
        check((a-b).Magnitude<=(tolerance or 0.0001),"expected "..tostring(b)..", got "..tostring(a))
    end
    local function test(name,fn)
        local ok,err=pcall(fn)
        table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
        if not ok then failed=failed+1 end
        print("[ChalkDB planner] "..(ok and "PASS " or "FAIL ")..name..(ok and "" or ": "..tostring(err)))
    end
    local config={CatchRadius=3.75,DiveCatchRadius=2.5,WaistDrop=1,
        HandOffset=0.5,HandUpOffset=3.5,DiveReach=2.4,
        Moves={Dive={Time=0.35,Tip=0.5,Ground=0.75,GetUp=0.35}}}
    local function snapshot(ball)
        return {now=1800000000,launchAt=1800000000-0.2,
            arc={P0=ball or Vector3.new(0,4,0),P1=ball or Vector3.new(0,4,0),Flight=1000,Apex=0},
            position=Vector3.new(0,3,0),velocity=Vector3.zero,
            lookDirection=Vector3.new(1,0,0),grounded=true,
            jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,walkSpeed=0,
            groundRootY=3,turfY=0,config=config,diveDistance=9,
            canJump=false,canDive=false,maxHorizon=0.65,margin=0.3}
    end
    local function posePlan(s,jumpDelay,diveDelay)
        return {kind=jumpDelay and "jumpDive" or "dive",direction=Vector3.new(1,0,0),
            jumpAt=jumpDelay and s.now+jumpDelay or nil,
            diveAt=diveDelay and s.now+diveDelay or nil,
            _jumpDelay=jumpDelay,_diveDelay=diveDelay,
            _speed=0,_aimDistance=0,_reaction=0}
    end

    test("ball endpoints and midpoint",function()
        local arc={P0=Vector3.new(0,6,0),P1=Vector3.new(20,3.5,0),Flight=1,Apex=6}
        nearVector(Planner.ballAt(arc,0),arc.P0)
        nearVector(Planner.ballAt(arc,1),arc.P1)
        nearVector(Planner.ballAt(arc,0.5),Vector3.new(10,10.75,0))
    end)
    test("capsule checks segment ends and interior",function()
        near(Planner.segmentDistance(Vector3.new(3,1,0),Vector3.zero,Vector3.new(0,2,0)),3)
        near(Planner.segmentDistance(Vector3.new(0,5,0),Vector3.zero,Vector3.new(0,2,0)),3)
        near(Planner.segmentDistance(Vector3.new(0,3,4),Vector3.zero,Vector3.zero),5)
    end)
    test("ground dive halfway has exact eased position and tilt",function()
        local s=snapshot()
        local cf=Planner.pose(s,posePlan(s,nil,0),s.now+0.175)
        nearVector(cf.Position,Vector3.new(6.75,1.8,0),0.00002)
        near(cf.UpVector.Y,math.cos(math.rad(80)),0.00002)
        check(cf.UpVector.X>0.98,"dive must tip toward travel direction")
    end)
    test("ground dive recovers only after ground hold",function()
        local s=snapshot()
        local p=posePlan(s,nil,0)
        local cf=Planner.pose(s,p,s.now+1.1)
        nearVector(cf.Position,Vector3.new(9,0.6,0),0.00002)
        near(cf.UpVector.Y,math.cos(math.rad(80)),0.00002)
        cf=Planner.pose(s,p,s.now+1.275)
        nearVector(cf.Position,Vector3.new(9,1.8,0),0.00002)
        near(cf.UpVector.Y,math.cos(math.rad(40)),0.00002)
        cf=Planner.pose(s,p,s.now+1.45)
        nearVector(cf.Position,Vector3.new(9,3,0),0.00002)
        near(cf.UpVector.Y,1,0.00002)
    end)
    test("air dive holds horizontal endpoint while still airborne",function()
        local s=snapshot()
        s.position=Vector3.new(0,7,0)
        s.velocity=Vector3.new(0,30,0)
        s.grounded=false
        local cf=Planner.pose(s,posePlan(s,nil,0),s.now+0.4)
        nearVector(cf.Position,Vector3.new(9,3.304,0),0.00002)
    end)
    test("falling dive clamps initial downward velocity to zero",function()
        local s=snapshot()
        s.position=Vector3.new(0,7,0)
        s.velocity=Vector3.new(0,-20,0)
        s.grounded=false
        local cf=Planner.pose(s,posePlan(s,nil,0),s.now+0.1)
        near(cf.Position.Y,6.019,0.00002)
    end)
    test("jump then dive retains upward ballistic trajectory",function()
        local s=snapshot()
        local cf=Planner.pose(s,posePlan(s,0.025,0.15),s.now+0.25)
        -- Jump has run for .225 seconds; dive starts during its ascent.
        local expectedY=3+math.sqrt(2354.4)*0.225-98.1*0.225^2
        near(cf.Position.Y,expectedY,0.00003)
        near(cf.Position.X,9*(1-(1-0.1/0.35)^2),0.00003)
    end)
    test("standing and diving use different native catch radii",function()
        local s=snapshot()
        local waist,hands,radius=Planner.capsule(s,CFrame.new(0,3,0),false)
        nearVector(waist,Vector3.new(0,2,0))
        nearVector(hands,Vector3.new(0,3.5,0))
        near(radius,3.75)
        local cf=Planner.pose(s,posePlan(s,nil,0),s.now+0.175)
        waist,hands,radius=Planner.capsule(s,cf,true)
        near(radius,2.5)
        near((hands-waist).Magnitude,3.4)
    end)
    test("already catchable ball requires no action",function()
        local s=snapshot()
        local p,why=Planner.solve(s)
        check(p and p.kind=="hold",why)
        check(not p.jumpAt and not p.diveAt,"hold must not request jump/dive")
    end)
    test("nearby high ball selects a reachable jump",function()
        local s=snapshot(Vector3.new(0,13,0))
        s.canJump=true
        local p,why=Planner.solve(s)
        check(p and p.kind=="jump",why)
        check(p.jumpAt>=s.now and p.contactAt>p.jumpAt,"invalid jump timing")
        check(p.margin>=s.margin,"contact lacks requested safety margin")
    end)
    test("low forward ball selects a reachable dive",function()
        local s=snapshot(Vector3.new(10,1.4,0))
        s.canDive=true
        local p,why=Planner.solve(s)
        check(p and p.kind=="dive",why)
        check(p.diveAt>=s.now and p.contactAt>p.diveAt,"invalid dive timing")
        check(p.requiresWallCheck,"unclipped dive must flag missing wall check")
    end)
    test("nearby ordinary contact selects movement without jump",function()
        local s=snapshot(Vector3.new(7,3,0))
        s.walkSpeed=20
        local p,why=Planner.solve(s)
        check(p and p.kind=="move",why)
        check(not p.jumpAt and not p.diveAt,"movement plan requested unnecessary action")
    end)
    test("wall-limited dive is rejected",function()
        local s=snapshot(Vector3.new(10,1.4,0))
        s.canDive=true
        s.clipDiveDistance=function() return 1 end
        local p=Planner.solve(s)
        check(p==nil,"planner attempted contact beyond clipped dive reach")
    end)
    test("distant ball does not cause whole-field steering",function()
        local s=snapshot(Vector3.new(100,3,0))
        s.walkSpeed=27
        s.canJump,s.canDive=true,true
        local p=Planner.solve(s)
        check(p==nil,"distant ball incorrectly considered locally reachable")
    end)
    test("disabled actions cannot reach high stationary ball",function()
        local p=Planner.solve(snapshot(Vector3.new(0,13,0)))
        check(p==nil,"planner used an unavailable action")
    end)
    test("invalid flight is rejected",function()
        local s=snapshot()
        s.arc.Flight=0
        local p=Planner.solve(s)
        check(p==nil,"zero-duration flight was accepted")
    end)
    test("chase reaches a farther contact outside local overlay range",function()
        local s=snapshot(Vector3.new(40,3,0))
        s.walkSpeed=20
        s.maxHorizon=3
        check(Planner.solve(s)==nil,"old local mode unexpectedly chased across field")
        s.chase=true
        local p,why=Planner.solve(s)
        check(p and p.kind=="move",why)
        check(p.contactAt>s.now+1 and p.contactAt<s.now+2.1,"far contact timing is implausible")
    end)
    test("chase chooses earlier jump instead of later grounded contact",function()
        local s=snapshot()
        s.arc={P0=Vector3.new(8,13,0),P1=Vector3.new(8,3,0),Flight=2,Apex=0}
        s.walkSpeed=20
        s.chase=true
        s.maxHorizon=2
        local grounded,why=Planner.solve(s)
        check(grounded~=nil,why)
        s.canJump=true
        local jumping,whyJump=Planner.solve(s)
        check(jumping and jumping.kind=="jump",whyJump)
        check(jumping.contactAt<grounded.contactAt-0.3,"action preference delayed an earlier jump contact")
    end)
    test("sprint exhaustion changes exact movement and stop time",function()
        local s=snapshot(Vector3.new(20,3,0))
        s.chase=true
        s.walkSpeed=27
        s.runSpeed=20
        s.sprintSeconds=0.5
        s.maxHorizon=2
        local p,why=Planner.solve(s)
        check(p and p.kind=="move",why)
        local cf=Planner.pose(s,p,s.now+0.625)
        -- .025 reaction, .5 seconds at 27, then .1 seconds at 20.
        near(cf.Position.X,15.5,0.00003)
        near(p.stopAt-s.now,0.025+0.5+(20-13.5)/20,0.000002)
    end)
    test("exhausted sprint cannot claim constant sprint reach",function()
        local s=snapshot(Vector3.new(60,3,0))
        s.chase=true
        s.walkSpeed=27
        s.runSpeed=20
        s.sprintSeconds=0.1
        s.maxHorizon=2.4
        check(Planner.solve(s)==nil,"planner assumed sprint continued after stamina exhaustion")
        s.sprintSeconds=10
        local p,why=Planner.solve(s)
        check(p and p.kind=="move",why)
    end)
    test("WR chooses upright catch even when DB can dive earlier",function()
        local s=snapshot(Vector3.new(10,3,0))
        s.chase=true
        s.walkSpeed=20
        s.canDive=true
        s.role="DB"
        local db,whyDB=Planner.solve(s)
        check(db and db.kind=="dive",whyDB)
        s.role="WR"
        local wr,whyWR=Planner.solve(s)
        check(wr and wr.kind=="move",whyWR)
        check(not wr.diveAt,"WR requested a needless dive")
        check(wr.contactAt>db.contactAt,"test did not exercise the WR/DB timing tradeoff")
    end)
    test("WR still dives when every upright action is unreachable",function()
        local s=snapshot(Vector3.new(10,1.4,0))
        s.role="WR"
        s.canDive=true
        local p,why=Planner.solve(s)
        check(p and p.kind=="dive",why)
        check(p.reachable==true,"robust dive must be marked reachable")
    end)
    test("WR low bullet prefers running over a needless late jump",function()
        -- Reconstructs the 8944.866819 throw at its 8945.208613 replan.
        -- The old ranking jumped to delay first touch into the low arc tail.
        local s=snapshot()
        s.role,s.chase,s.allowHold="WR",true,false
        s.launchAt=s.now-0.341794
        s.arc={P0=Vector3.new(18.893931,7.636868,-53.833427),
            P1=Vector3.new(-12.542292,5.136868,69.539421),Flight=1.05,Apex=6}
        s.position=Vector3.new(4.286910,4.636868,78.000832)
        s.groundRootY,s.turfY=4.636868,1.636868
        s.walkSpeed,s.runSpeed,s.sprintSeconds=27,20,2
        s.maxHorizon,s.reactionDelay,s.margin=1.108206,0,0.4
        s.diveDistance=14.731817
        s.canJump,s.canDive=true,true
        local p,why=Planner.solve(s)
        check(p and p.kind=="move",why)
        check(not p.jumpAt and not p.diveAt,"low bullet requested an unnecessary action")
        s.canJump,s.canDive=false,false
        local ordinary,whyOrdinary=Planner.solve(s)
        check(ordinary~=nil,whyOrdinary)
        near(p.effectiveProgress,ordinary.effectiveProgress,0.001)
    end)
    test("WR still jumps when ordinary movement cannot reach a high ball",function()
        local s=snapshot(Vector3.new(0,13,0))
        s.role,s.allowHold,s.canJump="WR",false,true
        local p,why=Planner.solve(s)
        check(p and p.kind=="jump",why)
        check(p.jumpAt and not p.diveAt,"high WR catch needs an ordinary jump")
        s.canJump=false
        check(Planner.solve(s)==nil,"high-ball fixture was reachable without jumping")
    end)
    test("unreachable fallback pursues future ball without claiming a catch",function()
        local s=snapshot()
        s.chase=true
        s.walkSpeed=20
        s.maxHorizon=2
        s.arc={P0=Vector3.new(100,3,0),P1=Vector3.new(150,3,0),Flight=5,Apex=0}
        check(Planner.solve(s)==nil,"fixture was unexpectedly reachable")
        local p,why=Planner.pursuit(s)
        check(p and p.kind=="pursue",why)
        check(p.reachable==false and p.predictedMiss>0,"pursuit falsely claimed a reachable catch")
        check(not p.jumpAt and not p.diveAt,"pursuit must not invent jump/dive actions")
        check(p.contactAt>s.now,"pursuit chose a past ball position")
        local current=Planner.ballAt(s.arc,s.now-s.launchAt)
        check(p.contactPosition.X>current.X,"pursuit chased where the ball already was")
        check((p.rootTarget-s.position).Magnitude<=40.01,"pursuit exceeded ordinary movement reach")
        check(p.stopAt<=p.contactAt,"pursuit continued beyond its future target time")
    end)
    test("pursuit stops when the trajectory has already hit turf",function()
        local s=snapshot()
        s.arc={P0=Vector3.new(0,6,0),P1=Vector3.new(20,3.5,0),Flight=1,Apex=6}
        s.launchAt=s.now-2
        s.walkSpeed=27
        local p=Planner.pursuit(s)
        check(p==nil,"fallback chased a ball after the arc hit turf")
    end)
    test("active steering can disable hold without losing reachable catch",function()
        local s=snapshot()
        local baseline,why=Planner.solve(s)
        check(baseline and baseline.kind=="hold",why)
        s.allowHold=false
        local p,whyNoHold=Planner.solve(s)
        check(p and p.kind=="move",whyNoHold)
        check(p.reachable==true,"disabling hold lost an ordinary reachable catch")
    end)
    local function downfieldFixture()
        local s=snapshot()
        s.arc={P0=Vector3.new(0,20,-20),P1=Vector3.new(0,12,40),Flight=2,Apex=0}
        s.chase=true
        s.walkSpeed=27
        s.runSpeed=27
        s.sprintSeconds=4
        s.canJump=true
        s.maxHorizon=1.7
        return s
    end
    test("WR maximizes effective downfield touch rather than early DB contact",function()
        local s=downfieldFixture()
        s.role="DB"
        local db,whyDB=Planner.solve(s)
        check(db~=nil,whyDB)
        s.role="WR"
        local wr,whyWR=Planner.solve(s)
        check(wr~=nil,whyWR)
        check(wr.effectiveProgress>db.contactPosition.Z+5,"WR still cut the route at the early DB catch")
        check(wr.safety=="unknown","missing opponent was incorrectly treated as known safe")
        near(wr.effectiveProgress,wr.firstTouchPosition.Z)
    end)
    test("full approach scan detects a premature native catch",function()
        local s=snapshot()
        s.arc={P0=Vector3.new(0,3,5),P1=Vector3.new(0,3,45),Flight=2,Apex=0}
        local p={kind="move",direction=Vector3.new(0,0,1),_speed=27,_runSpeed=27,
            _sprintSeconds=4,_reaction=0.025,_aimDistance=100,
            contactAt=s.now+1.6,contactPosition=Planner.ballAt(s.arc,1.8),
            rootTarget=Vector3.new(0,3,42.525)}
        local touch=Planner.firstTouch(s,p)
        check(touch.at<p.contactAt-0.3,"path scan missed earlier automatic contact")
        check(touch.progress<p.contactPosition.Z-5,"path scan credited unearned downfield progress")
    end)
    test("possible earlier defender reach selects honest contested fallback",function()
        local s=downfieldFixture()
        s.role="WR"
        local unopposed,why=Planner.solve(s)
        check(unopposed~=nil,why)
        s.opponent={position=s.position,velocity=Vector3.zero,grounded=true,
            jumpSpeed=s.jumpSpeed,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            canJump=true,canDive=true,groundRootY=3,diveDistance=9}
        local contested,whyContested=Planner.solve(s)
        check(contested~=nil,whyContested)
        check(contested.safety=="contested" and contested.defenderAt~=nil,"defender risk was hidden")
        check(contested.contactAt<unopposed.contactAt-0.2,"contested fallback waited for unnecessary late yards")
    end)
    test("contested WR floater jumps before a later ordinary catch",function()
        local s=snapshot()
        s.role,s.chase,s.allowHold="WR",true,false
        s.arc={P0=Vector3.new(0,6,0),P1=Vector3.new(0,3.5,0),Flight=3.1,Apex=42}
        s.maxHorizon=3.1
        s.opponent={position=s.position,velocity=Vector3.zero,grounded=true,
            jumpSpeed=s.jumpSpeed,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            canJump=true,canDive=true,groundRootY=3,diveDistance=9}
        local ordinary,whyOrdinary=Planner.solve(s)
        check(ordinary and ordinary.kind=="move",whyOrdinary)
        s.canJump=true
        local jumping,whyJump=Planner.solve(s)
        check(jumping and jumping.kind=="jump",whyJump)
        check(jumping.contactAt<ordinary.contactAt-0.15,
            "ordinary preference still delayed a contested floater catch")
        check(jumping.safety=="contested" and jumping.defenderAt~=nil,
            "earlier contested jump was incorrectly called clear")
        s.opponent.position=Vector3.new(1000,3,1000)
        local clear,whyClear=Planner.solve(s)
        check(clear and clear.kind=="move" and clear.safety=="clear",whyClear)
    end)
    test("WR never replaces reachable upright catches with contested dives",function()
        for _,apex in ipairs({6,42}) do
            for _,distance in ipairs({0,10,25}) do
                local s=snapshot()
                s.role,s.chase,s.allowHold="WR",true,false
                s.walkSpeed,s.runSpeed,s.sprintSeconds=27,20,4
                s.canJump=true
                s.arc={P0=Vector3.new(0,6,-20),P1=Vector3.new(0,3.5,distance),
                    Flight=apex==6 and 1.05 or 3.1,Apex=apex}
                s.maxHorizon=3.1
                s.opponent={position=s.position,velocity=Vector3.zero,grounded=true,
                    jumpSpeed=s.jumpSpeed,walkSpeed=27,runSpeed=20,sprintSeconds=4,
                    canJump=true,canDive=true,groundRootY=3,diveDistance=9}
                local upright=Planner.solve(s)
                check(upright~=nil,"fixture must have an upright catch")
                s.canDive=true
                local p=Planner.solve(s)
                check(p and not p.diveAt,"WR chose a dive despite reachable upright contact")
                near(p.contactAt,upright.contactAt)
            end
        end
    end)
    test("WR still dives when no upright catch is reachable",function()
        local s=snapshot(Vector3.new(10,1.4,0))
        s.role,s.chase,s.canDive="WR",true,true
        s.maxHorizon=0.65
        local p,why=Planner.solve(s)
        check(p and p.diveAt and p.diveReason=="No reachable upright catch",why)
    end)
    local function pacedWRFixture()
        local s=snapshot()
        s.role,s.chase,s.allowHold="WR",true,false
        s.walkSpeed,s.runSpeed,s.sprintSeconds=27,20,4
        s.canJump,s.canDive,s.continuousApproach=true,true,true
        s.arc={P0=Vector3.new(0,6,-20),P1=Vector3.new(0,3.5,40),Flight=3.1,Apex=42}
        s.maxHorizon=3.1
        return s
    end
    test("timed WR arrival keeps moving until the catch without delaying contact",function()
        local s=pacedWRFixture()
        local original=assert(Planner.solve(s))
        local paced=assert(Planner.timeArrival(s,original),"early arrival was not paced")
        check(paced.timedArrival and paced.movementScale>=.45 and paced.movementScale<1)
        check(paced.stopAt>original.stopAt+1,"receiver still parks more than a second early")
        check(paced.firstTouchAt-paced.stopAt<=.06,"paced arrival still waits at destination")
        check(paced.firstTouchAt<=original.firstTouchAt+.015,"pacing delayed the catch")
        check(paced.effectiveProgress>=original.effectiveProgress-.5,"pacing lost catch progress")
        local before=Planner.pose(s,paced,paced.stopAt-.15)
        local arrival=Planner.pose(s,paced,paced.stopAt)
        check((arrival.Position-before.Position).Magnitude>1,"timed approach is stationary")
        check(original.movementScale==nil,"pacing changed the original candidate")
    end)
    test("timed arrival remains opt-in and does not pace DB interception",function()
        local s=pacedWRFixture();local p=assert(Planner.solve(s))
        s.continuousApproach=false;check(Planner.timeArrival(s,p)==nil)
        s.continuousApproach=true;s.role="DB";check(Planner.timeArrival(s,p)==nil)
    end)
    test("timed arrival never alters a dive launch or last-chance catch",function()
        local s=pacedWRFixture();local p=assert(Planner.solve(s))
        p.diveAt=p.contactAt-.2;check(Planner.timeArrival(s,p)==nil)
        p.diveAt=nil;p.risk="last-resort";check(Planner.timeArrival(s,p)==nil)
    end)
    test("timed arrival rejects creeping and invalidated contact geometry",function()
        local s=pacedWRFixture();s.position=Vector3.new(0,3,20)
        check(Planner.timeArrival(s,assert(Planner.solve(s)))==nil,"very slow pacing was allowed")
        s=pacedWRFixture();local p=assert(Planner.solve(s));s.arc.P1=Vector3.new(100,3.5,40)
        check(Planner.timeArrival(s,p)==nil,"lost contact witness was retained")
    end)
    test("deep scoring intent keeps an available upright goal catch",function()
        local s=pacedWRFixture();s.preferGoalZ=38
        local p=assert(Planner.solve(s))
        check(p.scoringCatch and p.firstTouchRoot.Z>=38,"goal-line contact was not verified")
        check(not p.diveAt,"scoring route dived when its upright goal catch was available")
        local paced=assert(Planner.timeArrival(s,p))
        check(paced.firstTouchRoot.Z>=38,"pacing lost the scoring catch")
    end)
    test("WR respects supplied field root bounds",function()
        local s=downfieldFixture()
        s.role="WR"
        s.bounds={minX=-20,maxX=20,minZ=-20,maxZ=15}
        local p,why=Planner.solve(s)
        check(p~=nil,why)
        check(p.rootTarget.Z<=15 and p.firstTouchRoot.Z<=15,"WR catch left supplied field bounds")
    end)
    test("a second closer defender changes team catch risk",function()
        local s=downfieldFixture()
        s.role="WR"
        local far={position=Vector3.new(1000,3,1000),velocity=Vector3.zero,grounded=true,
            jumpSpeed=s.jumpSpeed,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            canJump=true,canDive=true,groundRootY=3,diveDistance=9}
        local close={position=s.position,velocity=Vector3.zero,grounded=true,
            jumpSpeed=s.jumpSpeed,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            canJump=true,canDive=true,groundRootY=3,diveDistance=9}
        s.opponents={far}
        local clear,whyClear=Planner.solve(s)
        check(clear and clear.safety=="clear",whyClear)
        s.opponents={far,close}
        local contested,whyContested=Planner.solve(s)
        check(contested and contested.safety=="contested",whyContested)
        check(contested.defenderAt~=nil,"second defender was ignored")
        check(contested.contactAt<clear.contactAt-0.2,"team risk did not alter late-catch selection")
    end)
    test("DB refines the first reachable timing cell",function()
        local s=snapshot()
        s.role,s.chase,s.allowHold="DB",true,false
        s.arc={P0=Vector3.new(0,20,0),P1=Vector3.new(0,0,0),Flight=2,Apex=0}
        s.maxHorizon,s.margin=1.5,0.4
        local p,why=Planner.solve(s)
        check(p~=nil,why)
        -- At now the ball is y=18, falling at 10 studs/s. The earlier
        -- robustness sample must enter handsY + radius - required margin.
        local expected=(18-(3+0.5+3.75-0.4))/10+0.012
        near(p.contactAt-s.now,expected,0.0002)
        check(p.margin>=s.margin,"refinement weakened the required catch margin")
        check(p.contactAt-s.now<1.145-0.01,"contact still waits for the coarse grid")
    end)
    test("grounded catch reach preserves ballistic jump motion",function()
        local s=snapshot()
        s.position,s.velocity=Vector3.new(0,10,0),Vector3.new(0,-5,0)
        s.grounded,s.reachAirborne=false,false
        local p={kind="hold",direction=Vector3.new(1,0,0)}
        local cf,airborne=Planner.pose(s,p,s.now+0.1)
        near(cf.Position.Y,10-0.5-0.5*s.gravity*0.1^2,0.00003)
        check(airborne,"reach override invented an elevated floor")
        local _,hands=Planner.capsule(s,cf,airborne)
        near(hands.Y-cf.Position.Y,0.5)
        s.reachAirborne=nil
        _,hands=Planner.capsule(s,cf,airborne)
        near(hands.Y-cf.Position.Y,3.5)
    end)
    test("shortened native reach rejects an airborne-only catch",function()
        local s=snapshot(Vector3.new(0,16,0))
        s.position=Vector3.new(0,10,0)
        s.grounded,s.chase,s.allowHold=false,true,false
        s.maxHorizon=0.1
        check(Planner.solve(s)~=nil,"airborne fixture should be reachable")
        s.reachAirborne=false
        check(Planner.solve(s)==nil,"solver ignored shortened native catch reach")
        s.reachAirborne=nil
        check(Planner.solve(s)~=nil,"restored airborne reach was not usable")
    end)
    test("required WR finish commits a real dive before first contact",function()
        local s=snapshot(Vector3.new(10,1.4,0))
        s.role,s.requireDive,s.chase,s.canDive="WR",true,true,true
        s.walkSpeed,s.runSpeed,s.sprintSeconds=27,20,4
        local p,why=Planner.solve(s)
        check(p and p.diveAt,why)
        local touch=Planner.firstTouch(s,p)
        check(touch and touch.at>=p.diveAt+.03,"upright contact was mislabeled as diving")
    end)
    test("required WR dive does not silently fall back to an upright catch",function()
        local s=snapshot(Vector3.new(10,1.4,0))
        s.role,s.requireDive,s.chase="WR",true,true
        s.walkSpeed,s.runSpeed,s.sprintSeconds=27,20,4
        check(Planner.solve(s)==nil,"unavailable dive became an upright finish")
    end)
    test("already touching the ball cannot be called a future diving catch",function()
        local s=snapshot(Vector3.new(1,3.5,0))
        s.role,s.requireDive,s.chase,s.canDive="WR",true,true,true
        s.walkSpeed,s.runSpeed,s.sprintSeconds=27,20,4
        check(Planner.solve(s)==nil,"pre-dive contact was accepted")
    end)
    test("DB ignores WR-only required dive preference",function()
        local s=snapshot()
        s.role,s.requireDive="DB",true
        local p,why=Planner.solve(s)
        check(p and not p.diveAt,why)
    end)
    -- Anonymous numerical fixtures: no services, player identities, or live data.
    local function finishFixture(kind)
        local s={now=1000.115,launchAt=1000,role="WR",chase=true,allowHold=false,
            arc={P0=Vector3.new(0,6,-53.833),P1=Vector3.new(48.106,3.5,126.359),Flight=3.1,Apex=42},
            position=Vector3.new(7.613,3,48.338),velocity=Vector3.new(14.003,0,23.085),
            steeringDirection=Vector3.new(.519,0,.855).Unit,grounded=true,
            jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,walkSpeed=27,runSpeed=20,sprintSeconds=3.04,
            groundRootY=3,turfY=0,diveTurfY=0,config=config,diveDistance=14.732,
            canJump=true,canDive=true,reactionDelay=0,margin=.4,continuousSprint=true,
            requireDive=true,preferGoalZ=103.306,
            bounds={minX=-48.606,maxX=48.606,minZ=-43.512,maxZ=151.912},
            opponent={position=Vector3.new(1000,3,1000),velocity=Vector3.zero,grounded=true,
                jumpSpeed=math.sqrt(2*196.2*6),gravity=196.2,walkSpeed=27,runSpeed=20,
                sprintSeconds=4,groundRootY=3,diveDistance=14.732,canJump=true,canDive=true}}
        if kind=="leftDive" then
            s.now,s.position,s.velocity,s.sprintSeconds=1000.087,Vector3.new(-4.409,3,35.211),Vector3.new(-13.931,0,23.129),3.12
            s.arc.P1=Vector3.new(-48.106,3.5,118.522)
        elseif kind=="rightDive" then
            s.now,s.position,s.velocity,s.sprintSeconds=1000.073,Vector3.new(4.239,3,39.405),Vector3.new(13.866,0,23.168),3.08
            s.arc.P1=Vector3.new(48.106,3.5,123.677)
        elseif kind=="contested" then
            s.now,s.position,s.velocity,s.sprintSeconds=1000.069,Vector3.new(-6.065,3,51.256),Vector3.new(-14.911,0,22.509),3.12
            s.arc.P1=Vector3.new(-48.106,3.5,126.359)
            s.defenderDeadline=1002.798
        elseif kind=="late" then
            s.now,s.position,s.velocity,s.sprintSeconds=1001.457,Vector3.new(23.286,3,78.735),Vector3.new(12.435,0,23.966),1.8
        end
        s.lookDirection,s.steeringDirection=s.velocity.Unit,s.velocity.Unit
        s.maxHorizon=3.5-(s.now-s.launchAt)
        return s
    end
    test("upright finish exception is explicit and keeps strict default",function()
        local s=finishFixture();local strict=assert(Planner.solve(s))
        check(strict.diveAt and not strict.uprightFinishOverride)
        s.allowUprightFinish=false;local disabled=assert(Planner.solve(s))
        near(disabled.contactAt,strict.contactAt);near(disabled.diveAt,strict.diveAt)
        s.allowUprightFinish=true;local p=assert(Planner.solve(s))
        check(not p.diveAt and not p.risk and p.uprightFinishOverride)
        check(p.safety=="clear" and p.scoringCatch and p.firstTouchRoot.Z>=s.preferGoalZ)
        check(p.margin>=s.margin and p.diveReason==nil,"normal catch margins/description changed")
        check(s.requireDive and s.canDive and s.margin==.4,"caller intent or geometry mutated")
    end)
    test("normal contested upright finish beats artificial late dive without hiding risk",function()
        local s=finishFixture("contested");local strict=assert(Planner.solve(s))
        s.allowUprightFinish=true;local p,why,threat=Planner.solve(s)
        check(p and not p.diveAt and p.uprightFinishOverride and not p.risk,why)
        check(p.contactAt<strict.contactAt-.06 and p.firstTouchAt<strict.firstTouchAt-.1)
        check(p.safety=="contested" and p.margin>=s.margin)
        check(p.defenderDeadline==s.defenderDeadline and threat.defenderDeadline==s.defenderDeadline)
        check(p.firstTouchAt>s.defenderDeadline,"fixture must remain an estimated lost race")
    end)
    test("upright finish keeps dives that have no normal upright goal witness",function()
        for _,kind in ipairs({"leftDive","rightDive"}) do
            local s=finishFixture(kind);local strict=assert(Planner.solve(s))
            s.allowUprightFinish=true;local p=assert(Planner.solve(s))
            check(p.diveAt and not p.uprightFinishOverride and not p.risk)
            near(p.contactAt,strict.contactAt);near(p.diveAt,strict.diveAt)
        end
    end)
    test("upright finish cannot replace a normal dive with late weak upright contact",function()
        local s=finishFixture("late");s.allowUprightFinish=true
        local p=assert(Planner.solve(s))
        check(p.diveAt and not p.uprightFinishOverride and not p.risk)
        s.requireDive,s.canDive=false,false
        local weak=assert(Planner.solve(s))
        check(weak.risk=="last-resort","fixture must exercise excluded weak upright contact")
    end)
    test("upright finish still requires known coverage and a finite scoring goal",function()
        for _,reason in ipairs({"unknown","missing","unreachable","invalid"}) do
            local s=finishFixture();s.allowUprightFinish=true
            if reason=="unknown" then s.opponent=nil
            elseif reason=="missing" then s.preferGoalZ=nil
            elseif reason=="unreachable" then s.preferGoalZ=200
            else s.preferGoalZ=math.huge end
            local p=Planner.solve(s)
            check(not p or p.diveAt and not p.uprightFinishOverride,reason.." gained an upright exception")
        end
    end)
    test("upright finish preserves field bounds and exhausted sprint budget",function()
        local s=finishFixture();s.allowUprightFinish=true;s.bounds.maxZ=103
        local p=Planner.solve(s)
        check(not p or not p.uprightFinishOverride,"goal outside field was accepted")
        s=finishFixture();s.allowUprightFinish=true;s.walkSpeed,s.sprintSeconds=20,0
        p=Planner.solve(s)
        check(not p or not p.uprightFinishOverride,"exhausted sprint was invented")
        s=finishFixture();s.allowUprightFinish=true;p=assert(Planner.solve(s))
        local touch=Planner.firstTouch(s,p)
        check(touch.root.X>=s.bounds.minX and touch.root.X<=s.bounds.maxX
            and touch.root.Z>=s.bounds.minZ and touch.root.Z<=s.bounds.maxZ)
    end)
    test("upright finish flag leaves DB and ordinary WR selection unchanged",function()
        for _,role in ipairs({"DB","WR"}) do
            local s=finishFixture();s.role=role
            if role=="WR" then s.requireDive=false end
            local before=assert(Planner.solve(s));s.allowUprightFinish=true
            local after=assert(Planner.solve(s))
            check(before.kind==after.kind and not after.uprightFinishOverride)
            near(before.contactAt,after.contactAt)
        end
    end)
    -- Informational benchmark only; no timing-dependent pass/fail threshold.
    do
        local s=snapshot()
        s.arc={P0=Vector3.new(0,6,-20),P1=Vector3.new(0,3.5,60),Flight=3.1,Apex=42}
        s.role="WR"
        s.chase=true
        s.walkSpeed=27
        s.runSpeed=20
        s.sprintSeconds=4
        s.canJump,s.canDive=true,true
        s.maxHorizon=3.1
        s.opponent={position=Vector3.new(45,3,60),velocity=Vector3.zero,grounded=true,
            jumpSpeed=s.jumpSpeed,walkSpeed=27,runSpeed=20,sprintSeconds=4,
            canJump=true,canDive=true,groundRootY=3,diveDistance=9}
        local started=os.clock()
        local p=Planner.solve(s)
        benchmark={seconds=os.clock()-started,result=p and p.kind or "none"}
        print(string.format("[ChalkDB planner] BENCH WR floater %.4fs, result=%s",
            benchmark.seconds,benchmark.result))
    end
    print(string.format("[ChalkDB planner] %d/%d tests passed",#results-failed,#results))
    return {passed=#results-failed,failed=failed,total=#results,results=results,benchmark=benchmark}
end
