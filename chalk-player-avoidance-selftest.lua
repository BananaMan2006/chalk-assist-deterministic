-- Deterministic geometry/lifecycle tests; no game services or native inputs.
return function(Avoidance)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,reason=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(reason) or nil}
    end
    local function fixture(extra)
        local input={now=0,dt=.025,position=Vector3.zero,velocity=Vector3.new(0,0,27),
            desiredDirection=Vector3.new(0,0,1),currentDirection=Vector3.new(0,0,1),
            requestedSprint=true,walkSpeed=27,runSpeed=20,canDetour=true,opponents={},
            bounds={minX=-30,maxX=30,minZ=-30,maxZ=50}}
        for k,v in pairs(extra or {}) do input[k]=v end
        return input
    end
    local function same(a,b) assert((a-b).Magnitude<1e-7,"direction changed") end
    local function legal(input,direction)
        local point=input.position+direction*input.walkSpeed*input.dt
        local b=input.bounds
        assert(point.X>=b.minX-1e-7 and point.X<=b.maxX+1e-7
            and point.Z>=b.minZ-1e-7 and point.Z<=b.maxZ+1e-7,"steering left legal bounds")
    end

    test("fresh clear movement retains the exact vector magnitude and sprint request",function()
        for _,strength in ipairs({.1,.6,1}) do
            for _,sprint in ipairs({false,true}) do
                local p=fixture({desiredDirection=Vector3.new(.3,0,.4)*strength,requestedSprint=sprint})
                local _,d=Avoidance.update(nil,p)
                assert(d.direction==p.desiredDirection and d.sprint==sprint)
                assert(not d.active and not d.blocked and not d.changed)
            end
        end
    end)
    test("far behind departing and vertically separated players preserve clear movement",function()
        for _,other in ipairs({
            {position=Vector3.new(0,0,40),velocity=Vector3.zero},
            {position=Vector3.new(0,0,-5),velocity=Vector3.zero},
            {position=Vector3.new(0,0,5),velocity=Vector3.new(0,0,30)},
            {position=Vector3.new(0,8,4),velocity=Vector3.zero},
            {position=Vector3.new(0,-8,4),velocity=Vector3.zero},
        }) do
            local p=fixture({opponents={other}});local _,d=Avoidance.update(nil,p)
            same(d.direction,p.desiredDirection);assert(not d.active and d.sprint)
        end
    end)
    test("moving crossing capsule triggers avoidance before physical contact",function()
        local p=fixture({opponents={{position=Vector3.new(5,0,3),velocity=Vector3.new(-20,0,0)}}})
        assert(p.opponents[1].position.Magnitude>4.25)
        local state,d=Avoidance.update(nil,p)
        assert(d.active and d.changed and not d.sprint and not d.blocked and state.side)
        assert(d.direction.Magnitude<=p.desiredDirection.Magnitude);legal(p,d.direction)
    end)
    test("proactive walk bypass clears a stationary blocker without touching or side chatter",function()
        local state,side,minDistance=nil,nil,math.huge
        local p=fixture({opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
        local goal=Vector3.new(0,0,35)
        local sawActive,sawClear=false,false
        for _=1,200 do
            p.desiredDirection=(goal-p.position).Unit
            local d;state,d=Avoidance.update(state,p)
            if d.active then
                sawActive=true;assert(not d.sprint)
                if d.side then
                    side=side or d.side;assert(d.side==side,"bypass side flipped")
                end
            elseif sawActive then sawClear=true end
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt
            minDistance=math.min(minDistance,(p.position-p.opponents[1].position).Magnitude)
            p.now=p.now+p.dt;p.walkSpeed=d.sprint and 27 or 20
            p.currentDirection=state.heading or p.desiredDirection
            if p.position.Z>16 and sawClear then break end
        end
        assert(sawActive and sawClear and p.position.Z>16,"bypass never resumed normal movement")
        assert(minDistance>=3.6,"proactive bypass entered the collision capsule")
    end)
    test("overlapping forward turn waits when every checked movement speed worsens contact",function()
        for _,side in ipairs({-1,1}) do
            local p=fixture({dt=1/60,walkSpeed=20,
                opponents={{position=Vector3.new(side*.25,0,3.1),velocity=Vector3.zero}}})
            local state,d=Avoidance.update(nil,p)
            assert(d.active and not d.sprint and d.direction.Magnitude==0,
                "failed clearance checks were bypassed by the overlapping full-walk fallback")
            assert(state.heading:Dot(p.desiredDirection)<1 and state.heading.Z>0,
                "waiting discarded the bounded turn")
            local firstHeading=state.heading
            p.now=p.now+p.dt
            state,d=Avoidance.update(state,p)
            assert(d.direction.Magnitude==0 and state.heading:Dot(p.desiredDirection)<firstHeading.Z,
                "zero movement restarted the turn instead of retaining progress")
        end
    end)
    test("centered and mirrored overlap escapes resume after a bounded turn without permanent holding",function()
        for _,offset in ipairs({-.25,0,.25}) do
            local obstacle=Vector3.new(offset,0,3.1)
            local p=fixture({dt=1/60,walkSpeed=20,
                opponents={{position=obstacle,velocity=Vector3.zero}}})
            local state,firstMotion,cleared,side=nil,nil,false,nil
            local initialGap=obstacle.Magnitude
            for _=1,90 do
                local oldHeading=state and state.heading or p.currentDirection
                local d;state,d=Avoidance.update(state,p)
                if d.active then
                    assert(not d.sprint,"overlapping escape spent sprint")
                    if d.side then
                        side=side or d.side
                        assert(d.side==side,"waiting changed the chosen passing side")
                    end
                    local angle=math.acos(math.max(-1,math.min(1,oldHeading.Unit:Dot(state.heading.Unit))))
                    assert(angle<=8*p.dt+1e-7,"escape bypassed the bounded turn")
                end
                if d.direction.Magnitude>.001 then
                    firstMotion=firstMotion or p.now
                    p.currentDirection=d.direction.Unit
                end
                legal(p,d.direction)
                p.position=p.position+d.direction*p.walkSpeed*p.dt
                assert((p.position-obstacle).Magnitude>=initialGap-.16,
                    "escape substantially deepened the initial overlap")
                assert(math.abs(p.position.X)<6,"escape took an unnecessarily wide side path")
                if not d.active and p.position.Z>7 then cleared=true;break end
                p.now=p.now+p.dt
            end
            assert(firstMotion and firstMotion>0 and firstMotion<.25,
                "safe translation did not resume after the short bounded turn")
            assert(cleared and p.now<1,"overlap escape remained held instead of restoring forward movement")
        end
    end)
    test("already safe sideways overlap escapes still move immediately",function()
        for _,side in ipairs({-1,1}) do
            local p=fixture({dt=1/60,walkSpeed=20,currentDirection=Vector3.new(side,0,0),
                opponents={{position=Vector3.new(-side*.25,0,3.1),velocity=Vector3.zero}}})
            local _,d=Avoidance.update(nil,p)
            assert(d.active and not d.sprint and d.direction.Magnitude>.99,
                "safe contact escape was unnecessarily held")
            local ending=(p.opponents[1].position-d.direction*p.walkSpeed*.25).Magnitude
            assert(ending>p.opponents[1].position.Magnitude+.25)
            legal(p,d.direction)
        end
    end)
    test("retained side is stable across small opponent jitter and roster reordering",function()
        local p=fixture({opponents={{position=Vector3.new(0,0,6),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p);local side=state.side;assert(side)
        for i=1,12 do
            p.now=p.now+.025;p.currentDirection=state.heading
            local threat={position=Vector3.new(i%2==0 and .08 or -.08,0,6),velocity=Vector3.zero}
            local far={position=Vector3.new(20,0,20),velocity=Vector3.zero}
            p.opponents=i%2==0 and {threat,far} or {far,threat}
            state,d=Avoidance.update(state,p)
            assert(d.active and state.side==side)
        end
    end)
    test("oscillating clearance boundary cannot alternate bypass and return headings every frame",function()
        local bypass=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({walkSpeed=20,currentDirection=bypass})
        local state={active=true,side=-1,heading=bypass}
        for i=1,12 do
            p.now=i*.025
            -- Direct-path clearance crosses the3.75stud capsule boundary;
            -- the already chosen left bypass remains physically clear.
            p.opponents={{position=Vector3.new(i%2==1 and 3.8 or 3.7,0,4),velocity=Vector3.zero}}
            local d;state,d=Avoidance.update(state,p)
            same(state.heading,bypass)
            assert(d.active and not d.sprint and state.side==-1)
            p.currentDirection=state.heading
        end
        p.opponents={{position=Vector3.new(3.8,0,4),velocity=Vector3.zero}}
        for i=1,5 do
            p.now=.3+i*.025
            local d;state,d=Avoidance.update(state,p)
            same(state.heading,bypass);assert(d.reason=="holding passing side")
            p.currentDirection=state.heading
        end
        p.now=.45
        local d;state,d=Avoidance.update(state,p)
        assert(d.reason=="returning to path" and state.heading.X>bypass.X)
        for _=1,12 do
            p.now=p.now+.025;p.currentDirection=state.heading
            state,d=Avoidance.update(state,p)
        end
        assert(not d.active and d.sprint);same(d.direction,p.desiredDirection)
    end)
    test("release hysteresis never holds an old bypass into a sideline",function()
        local p=fixture({now=.05,position=Vector3.new(9.5,0,0),
            bounds={minX=-10,maxX=10,minZ=-10,maxZ=30},currentDirection=Vector3.new(1,0,0)})
        local state={active=true,heading=Vector3.new(1,0,0),side=1,clearSince=.04}
        local _,d=Avoidance.update(state,p)
        assert(d.reason~="holding passing side","hysteresis overrode the bounds check")
        legal(p,d.direction)
    end)
    test("material catch-target change starts a bounded return without the old clear-frame hold",function()
        local old=Vector3.new(.988,0,.157).Unit
        local previousDesired=Vector3.new(.75,0,-.66).Unit
        local goal=Vector3.new(-.22,0,.975).Unit
        local p=fixture({now=.05,dt=.025,desiredDirection=goal,currentDirection=old,
            allowSprintDetour=true,sprintSpeed=27})
        local state={active=true,heading=old,side=1,desiredHeading=previousDesired,clearSince=.04}
        local firstDot=old:Dot(goal)
        local d;state,d=Avoidance.update(state,p)
        assert(d.reason=="returning to path" and state.returningToChangedGoal,
            "new catch direction retained the previous target's passing hold")
        assert(state.heading:Dot(goal)>firstDot and d.sprint)
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        -- The next frames are still inside the old .12-second debounce. The
        -- change exemption must survive rather than produce one turn then hold.
        for _=1,3 do
            local before=state.heading
            p.now=p.now+p.dt;p.currentDirection=before
            state,d=Avoidance.update(state,p)
            assert(d.reason=="returning to path" and state.returningToChangedGoal)
            assert(state.heading:Dot(goal)>before:Dot(goal))
            assert(math.acos(math.clamp(state.heading:Dot(before),-1,1))<=8*p.dt+1e-6)
        end
        for _=1,20 do
            p.now=p.now+p.dt;p.currentDirection=state.heading
            state,d=Avoidance.update(state,p)
            if not d.active then break end
        end
        assert(not d.active and state.returningToChangedGoal==nil)
        same(d.direction,goal);same(state.desiredHeading,goal)
    end)
    test("changed goal still checks the bounded return heading for player collisions",function()
        local old=Vector3.new(1,0,0)
        local p=fixture({now=.05,desiredDirection=Vector3.new(0,0,1),currentDirection=old,
            allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(4.5,0,0),velocity=Vector3.zero}}})
        local previous={active=true,heading=old,side=-1,desiredHeading=Vector3.new(0,0,-1),clearSince=.04}
        local state,d=Avoidance.update(previous,p)
        assert(d.active and not d.sprint,"changed goal bypassed current-path collision safety")
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        local relative=p.opponents[1].position-p.position
        local velocity=-d.direction*p.walkSpeed
        local time=velocity:Dot(velocity)>.000001
            and math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,.25) or 0
        assert((relative+velocity*time).Magnitude>=3.75-1e-6,
            "return turn was allowed to cross the collision capsule")
        legal(p,d.direction)
    end)
    test("small requested-heading jitter preserves ordinary passing-side hysteresis",function()
        local bypass=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({walkSpeed=20,currentDirection=bypass})
        local state={active=true,side=-1,heading=bypass,desiredHeading=Vector3.new(0,0,1)}
        for i=1,4 do
            p.now=i*.025
            p.desiredDirection=Vector3.new(i%2==0 and .02 or -.02,0,1).Unit
            local d;state,d=Avoidance.update(state,p)
            assert(d.reason=="holding passing side" and not state.returningToChangedGoal)
            same(state.heading,bypass)
        end
    end)
    test("sideline bypass selects the open side and remains bounded",function()
        local p=fixture({bounds={minX=-20,maxX=2,minZ=-20,maxZ=30},
            opponents={{position=Vector3.new(0,0,5),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and state.side==-1,"bypass chose the closed sideline")
        for _=1,12 do
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt;p.now=p.now+p.dt
            p.currentDirection=state.heading
            state,d=Avoidance.update(state,p)
            assert(d.direction.X<=.00001)
        end
    end)
    test("no bounded bypass releases sprint and does not push into the obstacle",function()
        local p=fixture({bounds={minX=-1,maxX=1,minZ=-10,maxZ=20},
            opponents={{position=Vector3.new(0,0,3.5),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint);same(d.direction,Vector3.zero)
        for _=1,8 do p.now=p.now+.025;state,d=Avoidance.update(state,p) end
        assert(d.blocked and d.reason=="no room to pass" and not d.sprint)
    end)
    test("recorded-style low displacement detects blocking despite reported velocity27",function()
        local p=fixture();local state,d
        for i=0,9 do
            p.now=i*.05;p.dt=.05;p.position=Vector3.new(0,0,p.now*(.77/.43))
            p.velocity=Vector3.new(0,0,27)
            p.opponents={{position=p.position+Vector3.new(0,0,3.7),velocity=Vector3.zero}}
            state,d=Avoidance.update(state,p)
        end
        assert(d.blocked and not d.sprint and d.progressSpeed<2,
            "reported velocity concealed physical blocking")
    end)
    test("real positional progress prevents false blocking even when reported velocity is zero",function()
        local p=fixture({velocity=Vector3.zero,walkSpeed=20});local state,d
        for i=0,10 do
            p.now=i*.025;p.position=Vector3.new(0,0,20*p.now)
            p.opponents={{position=p.position+Vector3.new(3.9,0,0),velocity=Vector3.new(0,0,20)}}
            state,d=Avoidance.update(state,p)
            assert(not d.blocked)
        end
        assert(d.progressSpeed and d.progressSpeed>19)
    end)
    test("brief contact does not claim prolonged blocking before its observation window",function()
        local p=fixture({opponents={{position=Vector3.new(0,0,3.7),velocity=Vector3.zero}}})
        local state,d
        for i=0,4 do p.now=i*.025;state,d=Avoidance.update(state,p);assert(not d.blocked) end
        p.now=.2;state,d=Avoidance.update(state,p);assert(d.blocked)
    end)
    test("committed movement bypass clears detour and progress state without changing input",function()
        local p=fixture({opponents={{position=Vector3.new(0,0,3.7),velocity=Vector3.zero}}})
        local state,d
        for i=0,8 do p.now=i*.025;state,d=Avoidance.update(state,p) end
        assert(d.active and d.blocked)
        p.canDetour=false;state,d=Avoidance.update(state,p)
        assert(next(state)==nil and not d.active and not d.blocked and d.sprint)
        same(d.direction,p.desiredDirection)
        p.canDetour=true;p.now=p.now+.025;state,d=Avoidance.update(state,p)
        assert(not d.blocked,"old contact timer survived priority handoff")
    end)
    test("zero movement resets stale state and never fabricates a detour",function()
        local p=fixture({desiredDirection=Vector3.zero})
        local state,d=Avoidance.update({active=true,side=-1,blocked=true},p)
        assert(next(state)==nil and not d.active and not d.blocked)
        same(d.direction,Vector3.zero);assert(d.sprint)
    end)
    test("first detour starts from actual current heading with a bounded turn",function()
        local p=fixture({currentDirection=Vector3.new(1,0,0),
            opponents={{position=Vector3.new(0,0,6),velocity=Vector3.zero}}})
        local previous={active=false,heading=Vector3.new(-1,0,0)}
        local state,d=Avoidance.update(previous,p)
        assert(d.active)
        local angle=math.acos(math.clamp(state.heading:Dot(p.currentDirection),-1,1))
        assert(angle<=8*p.dt+.000001,"detour jumped to desired goal or stale heading")
    end)
    test("turning away from an opponent still protects the actual current travel direction",function()
        local p=fixture({currentDirection=Vector3.new(0,0,-1),
            opponents={{position=Vector3.new(0,0,-5),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"desired clear goal hid an imminent collision on the current heading")
        local angle=math.acos(math.clamp(state.heading:Dot(p.currentDirection),-1,1))
        assert(angle<=8*p.dt+.000001)
        local projected=p.position+d.direction*p.walkSpeed*.25
        assert((projected-p.opponents[1].position).Magnitude>=3.75)
    end)
    test("smoothed return to a clear path remains bounds-safe beside a sideline",function()
        local p=fixture({position=Vector3.new(9.5,0,0),bounds={minX=-10,maxX=10,minZ=-10,maxZ=30},
            currentDirection=Vector3.new(1,0,0)})
        local state={active=true,heading=Vector3.new(1,0,0),side=1}
        local sawClear=false
        for _=1,20 do
            local d;state,d=Avoidance.update(state,p)
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt
            p.now=p.now+p.dt;p.currentDirection=state.heading
            if not d.active then sawClear=true;assert(d.sprint);same(d.direction,p.desiredDirection);break end
        end
        assert(sawClear,"safe return never restored normal movement")
    end)
    test("active detours never increase requested movement strength or enable unrequested sprint",function()
        local p=fixture({desiredDirection=Vector3.new(0,0,.6),requestedSprint=false,
            opponents={{position=Vector3.new(0,0,4.5),velocity=Vector3.zero}}})
        local state,d
        for i=0,12 do
            p.now=i*.025;state,d=Avoidance.update(state,p)
            assert(not d.sprint and d.direction.Magnitude<=.6+.000001)
        end
    end)
    test("invalid inputs are contained and cannot produce nonfinite steering",function()
        for _,p in ipairs({{},fixture({desiredDirection=false}),fixture({desiredDirection=Vector3.new(0/0,0,1)})}) do
            local _,d=Avoidance.update(nil,p);same(d.direction,Vector3.zero);assert(not d.sprint and not d.active)
        end
        local p=fixture({position=false});local _,d=Avoidance.update(nil,p)
        same(d.direction,p.desiredDirection);assert(not d.active)
        p=fixture({opponents={{position=false},{position=Vector3.new(0/0,0,4)},{position=Vector3.new(0,0,50)}}})
        _,d=Avoidance.update(nil,p);assert(not d.active and d.sprint)
    end)
    test("malformed bounds cannot authorize a new sideways path",function()
        local p=fixture({bounds={minX=10,maxX=-10},
            opponents={{position=Vector3.new(0,0,4),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint);same(d.direction,Vector3.zero)
    end)
    test("state updates are pure and sample history remains bounded",function()
        local sample={time=0,position=Vector3.zero}
        local previous={samples={sample},side=-1,active=false}
        local p=fixture({now=.1})
        local state=Avoidance.update(previous,p)
        assert(state~=previous and state.samples~=previous.samples and #previous.samples==1)
        assert(previous.samples[1]==sample and sample.time==0 and previous.now==nil)
        for i=1,200 do p.now=.1+i*.005;p.position=Vector3.new(0,0,p.now*20);state=Avoidance.update(state,p) end
        assert(#state.samples<=32)
    end)
    test("clock rollback discards stale contact history",function()
        local p=fixture({now=10,opponents={{position=Vector3.new(0,0,3.7),velocity=Vector3.zero}}})
        local state,d
        for i=0,8 do p.now=10+i*.025;state,d=Avoidance.update(state,p) end
        assert(d.blocked)
        p.now=1;state,d=Avoidance.update(state,p);assert(not d.blocked and #state.samples==1)
    end)
    test("recorded8892 clear passing heading retains an explicitly requested native sprint",function()
        local bypass=Vector3.new(.837928056716919,0,.5457807183265686).Unit
        for _,speed in ipairs({20,27}) do
            local p=fixture({now=.2,walkSpeed=speed,allowSprintDetour=true,sprintSpeed=27,
                position=Vector3.new(35.56631088256836,4.636868,42.002105712890625),
                desiredDirection=Vector3.new(.3488311767578125,0,.9371855854988098).Unit,
                currentDirection=bypass,bounds={minX=-29.712,maxX=67.5,minZ=-43.512,maxZ=151.912},
                opponents={{position=Vector3.new(30.28558921813965,4.636789,42.14754867553711),
                    velocity=Vector3.new(19.106891632080078,0,-5.664046287536621)}}})
            local old={active=true,heading=bypass,side=1,clearSince=.18}
            local state,d=Avoidance.update(old,p)
            assert(d.active and d.sprint and not d.blocked and d.reason=="holding passing side")
            same(d.direction,bypass);same(state.heading,bypass)
            p.allowSprintDetour=false
            local _,default=Avoidance.update(old,p)
            assert(default.active and not default.sprint)
            same(default.direction,bypass*(20/speed))
        end
    end)
    test("explicit opt out is identical to default across a moving detour",function()
        local a,b
        local p=fixture({opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
        for _=1,50 do
            p.allowSprintDetour=nil
            local da;a,da=Avoidance.update(a,p)
            p.allowSprintDetour=false;p.sprintSpeed=27
            local db;b,db=Avoidance.update(b,p)
            same(da.direction,db.direction)
            assert(da.sprint==db.sprint and da.active==db.active and da.blocked==db.blocked
                and da.reason==db.reason and a.side==b.side)
            p.position=p.position+da.direction*p.walkSpeed*p.dt
            p.now=p.now+p.dt;p.currentDirection=a.heading or p.desiredDirection
        end
    end)
    test("prospective27 collision slows a path that is clear at current20",function()
        local p=fixture({walkSpeed=20,allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(0,0,10),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"sprint safety reused walking-only clearance")
        assert(d.direction.Magnitude<=1);legal(p,d.direction)
    end)
    test("actual20 crossing still slows even when prospective27 would escape",function()
        local p=fixture({dt=.004,walkSpeed=20,allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(-6,0,1),velocity=Vector3.new(20,0,0)}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"prospective clearance hid the current-speed collision")
    end)
    test("prospective lookahead includes obstacles beyond slowed native speed shortlist",function()
        local p=fixture({walkSpeed=8,allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(0,0,9.6),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        assert(d.active and not d.sprint,"future sprint obstacle was excluded by current slow speed")
    end)
    test("sprint option never spends sprint during contact or measured physical blocking",function()
        local p=fixture({allowSprintDetour=true,sprintSpeed=27});local state,d
        for i=0,9 do
            p.now=i*.05;p.dt=.05;p.position=Vector3.new(0,0,p.now*(.77/.43))
            p.velocity=Vector3.new(0,0,27)
            p.opponents={{position=p.position+Vector3.new(0,0,3.7),velocity=Vector3.zero}}
            state,d=Avoidance.update(state,p)
            assert(d.active and not d.sprint,"contact escape retained sprint")
        end
        assert(d.blocked and d.progressSpeed<2)
    end)
    test("held sprint heading is rejected when only prospective speed leaves bounds",function()
        local heading=Vector3.new(1,0,1).Unit
        local p=fixture({now=.2,position=Vector3.new(5,0,0),walkSpeed=20,
            currentDirection=heading,allowSprintDetour=true,sprintSpeed=27,
            bounds={minX=-20,maxX=9.5,minZ=-20,maxZ=50}})
        local _,d=Avoidance.update({active=true,heading=heading,side=1,clearSince=.18},p)
        assert(d.active and not d.sprint and d.reason=="holding passing side")
        same(d.direction,heading);legal(p,d.direction)
    end)
    test("safe sprint return keeps bounded turns and original analog strength",function()
        local old=Vector3.new(1,0,1).Unit
        local p=fixture({now=.2,walkSpeed=20,desiredDirection=Vector3.new(0,0,.6),
            currentDirection=old,allowSprintDetour=true,sprintSpeed=27})
        local state,d=Avoidance.update({active=true,heading=old,side=1,clearSince=0},p)
        assert(d.active and d.sprint and d.reason=="returning to path")
        assert(math.abs(d.direction.Magnitude-.6)<1e-6)
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        p.requestedSprint=false
        local _,off=Avoidance.update({active=true,heading=old,side=1,clearSince=0},p)
        assert(not off.sprint and off.direction.Magnitude<=.6+1e-6)
    end)
    test("sprint exception requires an explicit valid native speed and preserves action priority",function()
        local heading=Vector3.new(1,0,1).Unit
        local p=fixture({now=.2,currentDirection=heading,allowSprintDetour=true})
        local state={active=true,heading=heading,side=1,clearSince=.18}
        for _,speed in ipairs({false,0,0/0,19}) do
            p.sprintSpeed=speed
            local _,d=Avoidance.update(state,p);assert(d.active and not d.sprint)
        end
        p.sprintSpeed=27;p.canDetour=false
        local reset,d=Avoidance.update(state,p)
        assert(next(reset)==nil and not d.active and d.sprint)
        same(d.direction,p.desiredDirection)
    end)
    test("opted in sprint bypass clears blocker without entering capsule or switching sides",function()
        local p=fixture({allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
        local goal=Vector3.new(0,0,35)
        local state,side,minDistance=nil,nil,math.huge
        local sprintDetour,slowTurn,clear=false,false,false
        for _=1,160 do
            p.desiredDirection=(goal-p.position).Unit
            local d;state,d=Avoidance.update(state,p)
            if d.active then
                if d.sprint then sprintDetour=true else slowTurn=true end
                if d.side then side=side or d.side;assert(d.side==side) end
            elseif sprintDetour then clear=true end
            legal(p,d.direction)
            p.position=p.position+d.direction*p.walkSpeed*p.dt
            minDistance=math.min(minDistance,(p.position-p.opponents[1].position).Magnitude)
            p.walkSpeed=d.sprint and 27 or 20
            p.currentDirection=state.heading or p.desiredDirection;p.now=p.now+p.dt
            if clear and p.position.Z>16 then break end
        end
        assert(sprintDetour and slowTurn and clear,"did not exercise slow turn and safe sprint bypass")
        assert(minDistance>=3.6,"retaining sprint entered the physical capsule")
    end)
    test("timed catch takes a small clear bypass instead of the first coarse35degree angle",function()
        local p=fixture({dt=.1,walkSpeed=20,requestedSprint=false,
            opponents={{position=Vector3.new(3.6,0,4),velocity=Vector3.zero}}})
        local _,ordinary=Avoidance.update(nil,p)
        p.targetPosition=Vector3.new(0,0,30);p.arriveBy=1.5
        local state,d=Avoidance.update(nil,p)
        assert(d.active and state.side==-1 and not d.sprint)
        local angle=math.acos(math.clamp(d.direction.Unit:Dot(p.desiredDirection),-1,1))
        assert(angle<=math.rad(10)+1e-6 and angle>0,"small safe passing angle was skipped")
        assert(d.direction.Z>ordinary.direction.Z,"refinement did not reduce sideways travel")
        local relative=p.opponents[1].position-p.position
        local velocity=-d.direction*p.walkSpeed
        local at=math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,.25)
        assert((relative+velocity*at).Magnitude>=3.75-1e-6,"shorter path crossed the capsule")
        legal(p,d.direction)
    end)
    test("catch with no travel slack returns without spending the clearpath hold",function()
        local old=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({now=.05,walkSpeed=20,requestedSprint=false,currentDirection=old,
            targetPosition=Vector3.new(0,0,30),arriveBy=1.55})
        local previous={active=true,heading=old,side=-1,desiredHeading=p.desiredDirection,clearSince=.04}
        local state,d=Avoidance.update(previous,p)
        assert(d.reason=="returning to path" and state.returningForDeadline)
        assert(state.heading:Dot(p.desiredDirection)>old:Dot(p.desiredDirection))
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        assert(previous.returningForDeadline==nil,"deadline decision mutated prior state")
        for _=1,3 do
            p.now=p.now+p.dt;p.currentDirection=state.heading
            local before=state.heading
            state,d=Avoidance.update(state,p)
            assert(d.reason~="holding passing side","deadline return restarted the old hold")
            assert(state.heading:Dot(p.desiredDirection)>=before:Dot(p.desiredDirection)-1e-6)
            legal(p,d.direction)
        end
    end)
    test("funded catch path retains ordinary boundary hysteresis",function()
        local old=Vector3.new(-math.sin(math.rad(35)),0,math.cos(math.rad(35)))
        local p=fixture({now=.05,walkSpeed=20,requestedSprint=false,currentDirection=old,
            targetPosition=Vector3.new(0,0,10),arriveBy=2})
        local state,d=Avoidance.update({active=true,heading=old,side=-1,clearSince=.04},p)
        assert(d.reason=="holding passing side" and not state.returningForDeadline)
        same(d.direction,old)
    end)
    test("expired catch deadline cannot bypass collision or field bounds",function()
        local p=fixture({now=1,targetPosition=Vector3.new(0,0,20),arriveBy=.9,
            allowSprintDetour=true,sprintSpeed=27,bounds={minX=-1,maxX=1,minZ=-10,maxZ=30},
            opponents={{position=Vector3.new(0,0,3.5),velocity=Vector3.zero}}})
        local _,d=Avoidance.update(nil,p)
        same(d.direction,Vector3.zero);assert(d.active and not d.sprint)
        legal(p,d.direction)
    end)
    test("deadline return still checks the bounded currentheading collision",function()
        local old=Vector3.new(1,0,0)
        local p=fixture({now=.05,currentDirection=old,targetPosition=Vector3.new(0,0,30),arriveBy=.5,
            allowSprintDetour=true,sprintSpeed=27,
            opponents={{position=Vector3.new(4.5,0,0),velocity=Vector3.zero}}})
        local state,d=Avoidance.update({active=true,heading=old,side=-1,clearSince=.04},p)
        assert(d.active and not d.sprint)
        local relative=p.opponents[1].position-p.position
        local velocity=-d.direction*p.walkSpeed
        local at=velocity:Dot(velocity)>.000001
            and math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,.25) or 0
        assert((relative+velocity*at).Magnitude>=3.75-1e-6)
        assert(math.acos(math.clamp(state.heading:Dot(old),-1,1))<=8*p.dt+1e-6)
        legal(p,d.direction)
    end)
    test("malformed optional deadlines preserve default avoidance",function()
        local p=fixture({now=.05,walkSpeed=20,currentDirection=Vector3.new(1,0,1).Unit})
        local previous={active=true,heading=p.currentDirection,side=1,clearSince=.04}
        local _,expected=Avoidance.update(previous,p)
        for _,deadline in ipairs({false,0/0,math.huge}) do
            p.targetPosition=Vector3.new(0,0,20);p.arriveBy=deadline
            local _,d=Avoidance.update(previous,p)
            same(d.direction,expected.direction);assert(d.reason==expected.reason and d.sprint==expected.sprint)
        end
        p.arriveBy=1;p.targetPosition=Vector3.new(0/0,0,20)
        local _,d=Avoidance.update(previous,p);same(d.direction,expected.direction)
    end)
    test("timed bypass keeps one side and reduces lateral distance in authored movement",function()
        local function run(timed)
            local p=fixture({allowSprintDetour=true,sprintSpeed=27,
                opponents={{position=Vector3.new(0,0,8),velocity=Vector3.zero}}})
            local goal=Vector3.new(0,0,35)
            if timed then p.targetPosition=goal;p.arriveBy=1.3 end
            local state,side,path,minimum=nil,nil,0,math.huge
            for _=1,200 do
                p.desiredDirection=(goal-p.position).Unit
                local d;state,d=Avoidance.update(state,p)
                if d.side then side=side or d.side;assert(d.side==side,"timed bypass switched sides") end
                legal(p,d.direction)
                local step=d.direction*p.walkSpeed*p.dt
                p.position=p.position+step;path=path+step.Magnitude
                minimum=math.min(minimum,(p.position-p.opponents[1].position).Magnitude)
                p.walkSpeed=d.sprint and 27 or 20
                p.currentDirection=state.heading or p.desiredDirection;p.now=p.now+p.dt
                if not d.active and p.position.Z>16 then return path,minimum end
            end
            error("timed bypass never returned to the path")
        end
        local ordinary=run(false)
        local timed,minimum=run(true)
        assert(timed<ordinary-.3,"shorter safe angles did not reduce the detour")
        assert(minimum>=3.75-1e-6,"deadline spent physical capsule clearance")
        -- This fixture integrates requested movement directly. It does not
        -- claim Roblox inertia, latency, or a catch outcome is reproduced.
    end)
    local function projectedGap(relative,velocity,direction,speed)
        local v=velocity-direction*speed
        local t=v:Dot(v)>.000001 and math.clamp(-relative:Dot(v)/v:Dot(v),0,.25) or 0
        return (relative+v*t).Magnitude
    end
    test("timed sprint bypass selects a slightly wider faster safe path",function()
        local p=fixture({dt=.1,walkSpeed=27,allowSprintDetour=true,sprintSpeed=27,
            targetPosition=Vector3.new(0,0,30),arriveBy=1.2,
            opponents={{position=Vector3.new(0,0,10),velocity=Vector3.zero}}})
        local state,d=Avoidance.update(nil,p)
        assert(d.active and d.sprint and state.side==1)
        local angle=math.acos(math.clamp(d.direction.Unit:Dot(p.desiredDirection),-1,1))
        assert(angle<=math.rad(25)+1e-6,
            "safe sprint bypass added an unnecessarily wide turn")
        local narrower=Vector3.new(math.sin(angle-math.rad(5)),0,math.cos(angle-math.rad(5)))
        assert(projectedGap(p.opponents[1].position,Vector3.zero,narrower,27)<4.25,
            "a smaller tested angle also preserved the sprint contact band")
        for _,speed in ipairs({20,27}) do
            assert(projectedGap(p.opponents[1].position,Vector3.zero,d.direction,speed)>=4.25-1e-6)
        end
        p.allowSprintDetour=false
        local _,walking=Avoidance.update(nil,p)
        assert(not walking.sprint and d.direction.Z*27>walking.direction.Z*27+5,
            "wider sprint path did not improve progress over walking")
        assert(math.abs(math.acos(walking.direction.Unit.Z)-math.rad(5))<1e-6,
            "opt-out changed the original shortest walking path")
    end)
    test("sprint ranking does not choose a wide slow sideways path just to sprint",function()
        local relative,velocity=Vector3.new(-1,0,5),Vector3.new(20,0,10)
        local p=fixture({dt=.1,walkSpeed=20,allowSprintDetour=true,sprintSpeed=27,
            targetPosition=Vector3.new(0,0,30),arriveBy=1.2,
            opponents={{position=relative,velocity=velocity}}})
        local _,d=Avoidance.update(nil,p)
        local wide=Vector3.new(math.sin(math.rad(55)),0,math.cos(math.rad(55)))
        assert(projectedGap(relative,velocity,wide,20)>=3.75
            and projectedGap(relative,velocity,wide,27)>=3.75,
            "fixture did not offer a safe wide sprint")
        assert(d.active and not d.sprint and math.abs(math.acos(d.direction.Unit.Z)-math.rad(5))<1e-6)
        assert(d.direction.Z*20>wide.Z*27+.5,"walking was not the faster forward choice")
    end)
    test("recorded floater detour brackets admit a faster checked same-side heading",function()
        -- Relative observations bracket the historical decision by -17/+53ms.
        -- These are separate geometry fixtures, not a replay of unlogged
        -- per-frame opponent state or proof of a recovered interception.
        local heading=Vector3.new(-.051954127848148346,0,.9986494779586792).Unit
        local oldHeading=Vector3.new(.03528160974383354,0,.999377429485321).Unit
        for _,observed in ipairs({
            {position=Vector3.new(-2.810562133789063,0,3.3375396728515625),
                velocity=Vector3.new(5.512195587158203,0,19.231538772583008)},
            {position=Vector3.new(-2.423643112182617,0,4.6597137451171875),
                velocity=Vector3.new(5.627748012542725,0,19.19687271118164)},
        }) do
            local p=fixture({walkSpeed=20,allowSprintDetour=true,sprintSpeed=27,
                desiredDirection=heading,currentDirection=oldHeading,
                targetPosition=Vector3.new(-.786735534667969,0,15.1224365234375),arriveBy=.540291,
                opponents={observed}})
            local state={active=true,heading=oldHeading,side=1,desiredHeading=heading}
            local d
            for _=1,3 do
                local before=state.heading
                state,d=Avoidance.update(state,p)
                assert(state.side==1 and math.acos(math.clamp(before:Dot(state.heading),-1,1))<=8*p.dt+1e-6,
                    "ranking skipped the bounded same-side turn")
                if d.sprint then
                    for _,speed in ipairs({20,27}) do
                        assert(projectedGap(observed.position,observed.velocity,d.direction,speed)>=4.25-1e-6,
                            "ranked sprint bypass failed actual-heading clearance")
                    end
                end
                p.now=p.now+p.dt;p.currentDirection=state.heading
            end
            assert(d.sprint and math.acos(math.clamp(d.direction.Unit:Dot(heading),-1,1))<=math.rad(30)+1e-6,
                "recorded bracket used an unnecessarily wide sprint bypass")
            assert(d.direction:Dot(heading)*27>20,
                "recorded bracket failed to retain better forward progress")
        end
    end)
    test("sprint forecast preserves its own near-contact gate across mirrored moving bypasses",function()
        -- Exact, constant-velocity geometry, not a native physics/catch replay.
        -- The old 3.75 forecast admitted the 4.25 band, then toggled sprint off
        -- for 22 frames despite a safe same-side route around the moving body.
        for _,mirror in ipairs({-1,1}) do
            local other={position=Vector3.new(mirror*6,0,2),velocity=Vector3.new(0,0,25)}
            local p=fixture({dt=1/60,position=Vector3.new(mirror*10,0,0),walkSpeed=27,
                currentDirection=Vector3.new(-mirror*.2,0,math.sqrt(.96)),
                allowSprintDetour=true,sprintSpeed=27,opponents={other},
                targetPosition=Vector3.new(0,0,80),arriveBy=3,
                bounds={minX=-50,maxX=50,minZ=-20,maxZ=100}})
            local state,side,walkFrames=nil,nil,0
            for _=1,120 do
                p.desiredDirection=(p.targetPosition-p.position).Unit
                local previousHeading=state and state.active and state.heading or p.currentDirection
                local d;state,d=Avoidance.update(state,p)
                if d.active then
                    local angle=math.acos(math.clamp(previousHeading.Unit:Dot(state.heading.Unit),-1,1))
                    assert(angle<=8*p.dt+1e-6,"near-contact forecast skipped the bounded turn")
                end
                if d.side then
                    side=side or d.side;assert(side==d.side,"near-contact forecast flipped passing side")
                end
                if d.sprint then
                    for _,speed in ipairs({p.walkSpeed,27}) do
                        assert(projectedGap(other.position-p.position,other.velocity,d.direction,speed)>=4.25-1e-6,
                            "approved sprint enters the same band that releases sprint next frame")
                    end
                else walkFrames=walkFrames+1 end
                legal(p,d.direction)
                p.position=p.position+d.direction*p.walkSpeed*p.dt
                other.position=other.position+other.velocity*p.dt
                if d.direction.Magnitude>.001 then p.currentDirection=d.direction.Unit end
                p.walkSpeed=d.sprint and 27 or 20;p.now=p.now+p.dt
                assert((p.position-other.position).Magnitude>=4.25-1e-6,
                    "safe sprint forecast drifted into the forced-release band")
                assert(math.abs(p.position.X-mirror*10)<.8,
                    "near-contact forecast spent the deadline on a wide lateral detour")
            end
            assert(walkFrames<=1 and p.position.Z>53.5,
                "near-contact bypass repeatedly toggled sprint or lost avoidable forward progress")
        end
    end)
    test("near-contact sprint anticipation remains an explicit opt-in",function()
        -- A clear walking forecast may pass through the sprint-only band.
        -- Ordinary movement and a funded-but-not-requested sprint keep the
        -- exact original direction; neither gets a wider avoidance radius.
        for _,options in ipairs({
            {allowSprintDetour=false,requestedSprint=true},
            {allowSprintDetour=true,requestedSprint=false},
        }) do
            local p=fixture({walkSpeed=20,sprintSpeed=27,
                allowSprintDetour=options.allowSprintDetour,requestedSprint=options.requestedSprint,
                opponents={{position=Vector3.new(4,0,2),velocity=Vector3.new(0,0,20)}}})
            local _,d=Avoidance.update(nil,p)
            assert(not d.active and not d.changed and d.sprint==options.requestedSprint)
            same(d.direction,p.desiredDirection)
        end
    end)
    local function movingEscapeFixture(mirror,angle,offset)
        mirror,angle,offset=mirror or 1,angle or 0,offset or Vector3.zero
        local function transform(v)
            local x,z=v.X*mirror,v.Z
            return Vector3.new(x*math.cos(angle)+z*math.sin(angle),v.Y,z*math.cos(angle)-x*math.sin(angle))
        end
        local heading=transform(Vector3.new(-.06792052835226059,0,.997690737247467)).Unit
        local desired=transform(Vector3.new(.6574468016624451,0,.7535009384155273)).Unit
        local other={position=offset+transform(Vector3.new(2.074424743652344,0,-1.802398681640625)),
            velocity=transform(Vector3.new(.1613544076681137,0,19.984384536743164))}
        local p=fixture({position=offset,walkSpeed=20,currentDirection=heading,desiredDirection=desired,
            dt=1/60,allowSprintDetour=true,sprintSpeed=27,opponents={other},
            targetPosition=offset+desired*30,arriveBy=1.3,
            bounds={minX=-100,maxX=100,minZ=-100,maxZ=100}})
        local state={active=true,side=-mirror,heading=heading,desiredHeading=desired,
            samples={{time=-.2,position=offset-heading*4}},contactSince=-.2}
        return p,state,other
    end
    test("measured moving overlap keeps only a monotonically separating sprint at both native speeds",function()
        -- Recorded before/after obstacle brackets are geometry witnesses, not
        -- exact heartbeat replay or proof that a different catch would win.
        for _,mirror in ipairs({-1,1}) do
            for _,angle in ipairs({0,math.rad(37)}) do
                local p,state,other=movingEscapeFixture(mirror,angle,Vector3.new(27,0,-30))
                local before=state.heading
                local nextState,d=Avoidance.update(state,p)
                assert(d.active and d.sprint and not d.blocked,"normal moving escape unnecessarily released sprint")
                assert(nextState.side==state.side,"moving escape changed passing side")
                assert(math.acos(math.clamp(before:Dot(nextState.heading),-1,1))<=8*p.dt+1e-6,
                    "moving escape skipped the bounded turn")
                local relative=other.position-p.position
                local initial=relative.Magnitude
                for _,speed in ipairs({20,27}) do
                    local rv=other.velocity-d.direction*speed
                    assert(relative:Dot(rv)>.05,"escape can initially close at a checked speed")
                    assert((relative+rv*.25).Magnitude>=initial+.25,"escape has no meaningful separation gain")
                    for step=0,25 do
                        assert((relative+rv*step/100).Magnitude>=initial-1e-6,"escape deepened an existing overlap")
                    end
                end
                assert(d.direction:Dot(p.desiredDirection)*27>14,
                    "moving escape sacrificed too much forward progress")
                legal(p,d.direction)
            end
        end
        -- The later sample places the moving body slightly ahead; the same
        -- bounded path must still separate at both native speeds to qualify.
        local p,state,other=movingEscapeFixture()
        other.position=Vector3.new(2.194639205932617,0,.24544525146484375)
        other.velocity=Vector3.new(1.5266423225402832,0,19.936634063720703)
        local _,d=Avoidance.update(state,p)
        assert(d.sprint,"second recorded bracket lost a strictly separating path")
        for _,speed in ipairs({20,27}) do
            local rv=other.velocity-d.direction*speed
            assert(other.position:Dot(rv)>.05 and (other.position+rv*.25).Magnitude>=other.position.Magnitude+.25)
        end
    end)
    test("moving overlap exception rejects unmeasured stationary jammed approaching and unfunded cases",function()
        for _,gate in ipairs({"no measurement","zero movement","implausible movement","jammed",
            "stationary body","approaching body","not requested","not opted in"}) do
            local p,state,other=movingEscapeFixture()
            if gate=="no measurement" then state.samples={}
            elseif gate=="zero movement" then state.samples={{time=-.2,position=p.position}}
            elseif gate=="implausible movement" then state.samples={{time=-.2,position=p.position-p.currentDirection*20}}
            elseif gate=="jammed" then p.walkSpeed=9
            elseif gate=="stationary body" then other.velocity=Vector3.zero
            elseif gate=="approaching body" then other.velocity=p.currentDirection*20-other.position.Unit*10
            elseif gate=="not requested" then p.requestedSprint=false
            else p.allowSprintDetour=false end
            local _,d=Avoidance.update(state,p)
            assert(not d.sprint,gate.." unlocked the moving escape exception")
            legal(p,d.direction)
        end
    end)
    test("moving overlap cannot sacrifice another body clearance or field bounds",function()
        for _,gate in ipairs({"crossing body","stationary near body","boundary"}) do
            local p,state=movingEscapeFixture()
            if gate=="crossing body" then
                p.opponents[2]={position=Vector3.new(-4,0,6),velocity=Vector3.new(16,0,0)}
            elseif gate=="stationary near body" then
                p.opponents[2]={position=Vector3.new(-3,0,1),velocity=Vector3.zero}
            else p.bounds.maxZ=1 end
            local _,d=Avoidance.update(state,p)
            assert(not d.sprint,gate.." was ignored by the moving escape exception")
            legal(p,d.direction)
        end
    end)
    return report
end
