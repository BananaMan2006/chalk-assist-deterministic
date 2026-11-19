-- Pure recorded-geometry tests; no input, characters, services or remotes.
-- Usage: loadstring(source)()(Planner). Works with native Vector3/CFrame or
-- the explicitly limited offline Roblox math shim.
return function(Planner)
    local V=Vector3.new
    local config={CatchRadius=3.75,DiveCatchRadius=2.5,WaistDrop=1,
        HandOffset=.5,HandUpOffset=3.5,DiveReach=2.4,
        Moves={Dive={Time=.35,Tip=.5,Ground=.75,GetUp=.35}}}
    local launch=1794796662.108106
    local arc={P0=V(18.893924713134766,7.636868476867676,-53.83334732055664),
        P1=V(51.839202880859375,5.136868476867676,65.37759399414062),Flight=1.05,Apex=6}
    local records={
        {now=1794796662.425912,position=V(20.647743225097656,4.636867046356201,66.94390106201172),
            velocity=V(.9999371767,0,.0112083424)*27,stamina=98},
        {now=1794796662.675734,position=V(27.38953971862793,4.636867046356201,67.27587127685547),
            velocity=V(.9987717271,0,.0495479852)*27,stamina=91},
        {now=1794796662.926447,position=V(34.1314811706543,4.636867046356201,67.60505676269531),
            velocity=V(.9988099337,0,.0487724058)*27,stamina=86},
    }
    local function snapshot(index)
        local r=records[index]
        return {now=r.now,launchAt=launch,arc=arc,role="WR",chase=true,
            position=r.position,velocity=r.velocity,lookDirection=V(1,0,0),
            grounded=true,jumpSpeed=48.52215950860912,gravity=196.2,
            walkSpeed=27,runSpeed=20,sprintSeconds=(r.stamina-2)/25,
            groundRootY=r.position.Y,turfY=1.636868476867676,diveTurfY=1.636868476867676,
            config=config,diveDistance=14.731816774606706,canJump=true,canDive=true,
            allowHold=false,maxHorizon=1.45-(r.now-launch),margin=.4,timingMargin=.012,reactionDelay=0}
    end
    local results,failed,benchmarks={},0,{}
    local function test(name,fn)
        local started=os.clock()
        local ok,err=pcall(fn)
        results[#results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil,
            seconds=os.clock()-started}
        if not ok then failed=failed+1 end
        print("[Chalk risky catch] "..(ok and "PASS " or "FAIL ")..name..(ok and "" or ": "..tostring(err)))
    end
    local function measuredMargin(s,p,half)
        local margin=math.huge
        for _,delta in ipairs({-half,0,half}) do
            local when=p.contactAt+delta
            local cf,air=Planner.pose(s,p,when)
            local waist,hands,radius=Planner.capsule(s,cf,air)
            margin=math.min(margin,radius-Planner.segmentDistance(
                Planner.ballAt(s.arc,when-s.launchAt),waist,hands))
        end
        return margin
    end
    local function measuredSolve(s)
        local original,calls=Planner.pose,0
        Planner.pose=function(...) calls=calls+1;return original(...) end
        local started=os.clock()
        local ok,p,reason=pcall(Planner.solve,s)
        local elapsed=os.clock()-started
        Planner.pose=original
        assert(ok,p)
        return p,reason,{seconds=elapsed,poseCalls=calls}
    end
    for index=1,2 do
        test("actual replan "..index.." ideal narrow contact does not survive execution delay",function()
            local s=snapshot(index)
            s.actionTimingEnvelope=false
            s.allowLastResort=false
            local normal=Planner.solve(s)
            assert(not normal,"Recorded replan must fail normal robustness")
            s.allowLastResort=true
            local p,reason,benchmark=measuredSolve(s)
            assert(p and p.risk=="last-resort",reason)
            assert(p.kind=="jumpDive" and p.robust==false,"Must explicitly label the risky jump-dive")
            assert(p.requiredMargin==.05 and p.timingMargin==.004,"Wrong risky criteria")
            assert(p.jumpAt>=s.now and p.diveAt-p.jumpAt>=.06,"Action deadlines must remain executable")
            local narrow,normalMargin=measuredMargin(s,p,.004),measuredMargin(s,p,.012)
            assert(narrow>=.05,"No native capsule overlap at +/-4ms")
            assert(normalMargin<.4,"Fixture must exercise a non-robust contact")
            assert(s.margin==.4 and s.timingMargin==.012,"Solve must not mutate caller criteria")
            local delayed={}for key,value in pairs(p)do delayed[key]=value end
            delayed.jumpAt=p.jumpAt+.035;delayed._jumpDelay=p._jumpDelay+.035
            delayed._diveDistance=nil
            assert(delayed.diveAt-delayed.jumpAt<.06 or measuredMargin(s,delayed,.004)<.05,
                "Fixture must demonstrate a real delayed-action failure")
            s.actionTimingEnvelope=nil
            assert(not Planner.solve(s),"A fragile ideal overlap must not be called executable")
            benchmark.margin,benchmark.normalMargin=narrow,normalMargin
            benchmark.contactAt,benchmark.jumpAt,benchmark.diveAt=p.contactAt,p.jumpAt,p.diveAt
            benchmarks[index]=benchmark
        end)
    end
    test("late actual replan remains unreachable",function()
        local s=snapshot(3)
        local p=Planner.solve(s)
        assert(not p,"Last-resort fallback must not invent a contact after the chance has passed")
    end)
    test("DB normal-only policy remains available",function()
        local s=snapshot(1)
        s.role="DB"
        s.allowLastResort=false
        assert(not Planner.solve(s),"An explicit normal-only solve must not relax DB catches")
    end)
    local function recordedDB()
        local s=snapshot(1)
        s.role="DB"
        s.now,s.launchAt=1794863876.037038,1794863875.698995
        s.arc={P0=V(18.893924713134766,7.636868476867676,-53.83334732055664),
            P1=V(56.69063186645508,5.136868476867676,-10.45356273651123),Flight=1.05,Apex=6}
        s.position=V(25.60566520690918,4.636868000030518,-10.254096031188965)
        s.velocity=V(26.797082901000977,1.303443332290044e-05,-3.303987741470337)
        s.lookDirection=V(.979606568813324,-2.0850601245570033e-08,-.2009253352880478)
        s.groundRootY,s.turfY,s.diveTurfY=s.position.Y,1.63686865568161,1.63686865568161
        s.gravity,s.sprintSeconds,s.maxHorizon=196.1999969482422,3.76,1.45-(s.now-s.launchAt)
        s.bounds={minX=-29.7121302485466,maxX=67.49998158216476,
            minZ=-43.512135207653046,maxZ=151.9120985865593}
        return s
    end
    test("recorded DB 3875 takes a bounded narrow interception before pursuit",function()
        local s=recordedDB()
        s.allowLastResort=false
        assert(not Planner.solve(s),"Recorded snapshot must fail normal robustness")
        s.allowLastResort=true
        local p,reason,benchmark=measuredSolve(s)
        assert(p and p.reachable and p.risk=="last-resort" and p.robust==false,reason)
        assert(p.kind=="jumpDive","Recorded chance requires the native jump-dive capsule")
        assert(p.requiredMargin==.05 and p.timingMargin==.004,"Wrong last-chance criteria")
        assert(p.jumpAt>=s.now and p.diveAt-p.jumpAt>=.06,"Actions must remain executable")
        assert(p.contactAt<=1794863876.674539,"Chronological DB search must not delay the known witness")
        benchmark.margin=measuredMargin(s,p,.004)
        benchmark.normalMargin=measuredMargin(s,p,.012)
        assert(benchmark.margin>=.05,"No native overlap across the claimed timing window")
        assert(benchmark.normalMargin<.4,"Fixture must retain its narrow-contact risk")
        assert(s.margin==.4 and s.timingMargin==.012,"Caller robustness must not be mutated")
        assert(config.CatchRadius==3.75 and config.DiveCatchRadius==2.5,
            "Native catch geometry must not be enlarged")
        benchmark.contactAt,benchmark.jumpAt,benchmark.diveAt=p.contactAt,p.jumpAt,p.diveAt
        benchmarks.recordedDB3875=benchmark
    end)
    test("late recorded DB 3875 remains unreachable",function()
        local s=recordedDB()
        s.now=1794863876.537096
        s.position=V(38.935646057128906,4.636868000030518,-12.389606475830078)
        s.velocity=V(26.661849975585938,1.303443332290044e-05,-4.259782314300537)
        s.sprintSeconds=3.24
        assert(not Planner.solve(s),"An expired action opportunity must remain a pursuit, not a catch claim")
    end)
    local function recordedWR9478()
        return {now=1795039479.435339,launchAt=1795039478.073213,role="WR",chase=true,
            arc={P0=V(18.893924713134766,7.636868476867676,-53.83334732055664),
                P1=V(-29.212129592895508,5.136868476867676,123.6769027709961),Flight=3.1,Apex=42},
            position=V(-2.1225719451904297,4.636868000030518,68.60313415527344),
            velocity=V(-12.515046119689941,1.3046006642980501e-05,23.924331665039062),
            lookDirection=V(-.4635207951068878,0,.8860860466957092),
            steeringDirection=V(-.46352022886276245,0,.8860863447189331),
            grounded=true,jumpSpeed=48.52215950860912,gravity=196.1999969482422,
            walkSpeed=27,runSpeed=20,sprintSeconds=1.92,
            groundRootY=4.636868000030518,turfY=1.63686865568161,diveTurfY=1.63686865568161,
            config=config,diveDistance=14.731816774606706,canJump=true,canDive=true,
            allowHold=false,maxHorizon=3.5-(1795039479.435339-1795039478.073213),
            margin=.4,timingMargin=.012,reactionDelay=0,requireDive=true,continuousSprint=true,
            preferGoalZ=103.3059,
            bounds={minX=-29.7121302485466,maxX=67.49998158216476,
                minZ=-43.512135207653046,maxZ=151.9120985865593},
            opponent={position=V(3.4473087787628174,4.636789321899414,64.33389282226562),
                velocity=V(-23.028833389282227,0,14.097099304199219),
                lookDirection=V(.36914995312690735,0,-.9293698668479919),
                groundRootY=4.63686865568161,gravity=196.1999969482422,grounded=true,
                jumpSpeed=48.52215950860912,walkSpeed=27,runSpeed=20,sprintSeconds=4,
                diveDistance=14.731816774606706,canDive=true,canJump=true}}
    end
    test("recorded WR9478 retains a narrow normal-age jump-dive after small drift",function()
        local s=recordedWR9478()
        s.allowLastResort=false
        assert(not Planner.solve(s),"Recorded replan must still fail normal robustness")
        s.allowLastResort=true
        local p,reason,benchmark=measuredSolve(s)
        assert(p and p.kind=="jumpDive" and p.risk=="last-resort" and p.robust==false,reason)
        assert(p.contactAt-p.jumpAt<.38,"Regression must exercise the omitted normal jump age")
        assert(p.jumpAt>=s.now and p.diveAt-p.jumpAt>=.06)
        assert(p.requiredMargin==.05 and p.timingMargin==.004)
        assert(measuredMargin(s,p,.004)>=.05,"Narrow retry needs a real native capsule witness")
        assert(measuredMargin(s,p,.012)<.4,"Do not turn this fixture into a robust catch claim")
        local touch=Planner.firstTouch(s,p)
        assert(touch.at>=p.diveAt+.03,"Required-dive route must not claim an earlier upright catch")
        for _,at in ipairs({touch.at,p.contactAt,p.diveAt+.35}) do
            local pose=Planner.pose(s,p,at)
            assert(pose.Position.X>=s.bounds.minX and pose.Position.X<=s.bounds.maxX
                and pose.Position.Z>=s.bounds.minZ and pose.Position.Z<=s.bounds.maxZ,
                "Witness/dive continuation must remain within native field bounds")
        end
        assert(s.walkSpeed==27 and s.runSpeed==20 and s.sprintSeconds==1.92)
        assert(s.margin==.4 and s.timingMargin==.012 and s.requireDive==true)
        assert(config.CatchRadius==3.75 and config.DiveCatchRadius==2.5)
        assert(benchmark.poseCalls<10000,"Bounded retry became an unnecessarily dense search")
        benchmark.margin=measuredMargin(s,p,.004)
        benchmark.contactAt,benchmark.jumpAt,benchmark.diveAt=p.contactAt,p.jumpAt,p.diveAt
        benchmarks.recordedWR9478=benchmark
    end)
    test("recorded WR9478 narrow retry respects required dive and field bounds",function()
        local s=recordedWR9478();s.canDive=false
        assert(not Planner.solve(s),"Required dive must not silently become an upright catch")
        s=recordedWR9478();s.bounds.minX=-5
        assert(not Planner.solve(s),"Narrow normal-age retry cannot ignore catch bounds")
    end)
    test("recorded WR9478 narrow retry retains an earlier defender deadline",function()
        local s=recordedWR9478();s.defenderDeadline=1795039480.9
        local p,reason,threat=Planner.solve(s)
        assert(p and p.risk=="last-resort" and p.safety=="contested",reason)
        assert(p.defenderDeadline==s.defenderDeadline and threat.defenderDeadline==s.defenderDeadline)
        assert(p.contactAt>s.defenderDeadline,"Fixture must remain a lost estimated race, not a clear claim")
    end)
    local function stationary(height)
        local s=snapshot(1)
        s.position,s.velocity=V(0,3,0),Vector3.zero
        s.groundRootY,s.turfY,s.diveTurfY=3,0,0
        s.launchAt=s.now-.2
        s.arc={P0=V(0,height,0),P1=V(0,height,0),Flight=1000,Apex=0}
        s.walkSpeed,s.runSpeed,s.sprintSeconds=0,0,0
        s.canJump=false
        s.maxHorizon=.65
        return s
    end
    test("last-resort upright catch stays ahead of diving",function()
        local s=stationary(7.05)
        local p,reason=Planner.solve(s)
        assert(p and p.risk=="last-resort",reason)
        assert(p.kind=="move" and not p.diveAt and not p.jumpAt,"Narrow upright catch must not cause a dive")
        assert(measuredMargin(s,p,.004)>=.05,"Upright fallback needs native overlap")
    end)
    test("last-resort upright catch does not require an available dive",function()
        local s=stationary(7.05)
        s.canDive=false
        local p,reason=Planner.solve(s)
        assert(p and p.risk=="last-resort" and p.robust==false,reason)
        assert(p.kind=="move" and not p.diveAt and not p.jumpAt,
            "Unavailable actions must not be required for the upright fallback")
        assert(measuredMargin(s,p,.004)>=.05,"Upright fallback needs native overlap")
        s.allowLastResort=false
        assert(not Planner.solve(s),"Normal-only snapshots must still reject narrow contact")
    end)
    test("last-resort upright catch keeps field bounds when diving is unavailable",function()
        local s=stationary(7.05)
        s.canDive=false
        s.bounds={minX=1,maxX=10,minZ=-10,maxZ=10}
        assert(not Planner.solve(s),"Narrow overlap cannot bypass field root bounds")
    end)
    test("ordinary reachable catch never enters risk search",function()
        local s=stationary(5)
        local p,reason=Planner.solve(s)
        assert(p and not p.risk and not p.diveAt,reason)
        assert(p.margin>=.4,"Normal margin must be preserved")
    end)
    test("DB normal catch keeps priority over last-chance search",function()
        local s=stationary(5)
        s.role="DB"
        local p,reason=Planner.solve(s)
        assert(p and not p.risk and not p.diveAt,reason)
        assert(p.margin>=.4,"A normal DB catch must retain normal robustness")
    end)
    test("unreachable distant ball stays unreachable",function()
        local s=stationary(5)
        s.arc={P0=V(1000,5,0),P1=V(1000,5,0),Flight=1000,Apex=0}
        assert(not Planner.solve(s),"Risk label cannot substitute for geometric reach")
    end)
    return {total=#results,passed=#results-failed,failed=failed,results=results,benchmarks=benchmarks,
        limitations="Recorded velocities are estimated; no walls/opponent snapshot, engine latency or server outcomes are simulated."}
end
