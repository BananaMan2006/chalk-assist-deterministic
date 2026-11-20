-- Read-only decision replays of observed scalar states; no physical catch claim.
return function(Policy)
    local report={total=0,passed=0,failed=0,results={}}
    local Config={RunSpeed=20,SprintSpeed=27,SprintDrain=25}
    local Field={MinX=-30.2121302485466,MaxX=67.99998158216476,MidX=18.8939256668,
        BackZ=-44.012135207653046,EndZ=152.4120985865593,LOSZ=-19.45910851670435,
        GoalZ=103.3060463,YD=4.9106056}
    local function test(name,body)
        report.total=report.total+1
        local ok,why=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(why) or nil}
    end
    local function input(extra)
        local p={role="DB",phase="Live",mode="1v1",LOS=Field.LOSZ,offset=Vector3.zero,
            position=Vector3.new(48.050617218,3,76.211990356),velocity=Vector3.new(0,0,20),
            opponentPosition=Vector3.new(40.715572357,3,80.495193481),
            opponentVelocity=Vector3.new(-23.905550003,0,9.069954872),elapsed=4.994219,
            stamina=100,sprintOn=false}
        for k,v in pairs(extra or {}) do p[k]=v end
        return p
    end
    local function move(p) return assert(Policy.movement(p,Config,Field,{})) end
    local function openingRun(extra)
        -- Observed before a Bullet: neither lateral speed nor trailing depth
        -- crossed the previous per-axis recovery gates, despite opening range.
        local p=input({position=Vector3.new(16.0177268982,3,25.2981948853),
            velocity=Vector3.new(-7.9868826866,0,18.3312606812),
            opponentPosition=Vector3.new(11.6258020401,3,32.5192794800),
            opponentVelocity=Vector3.new(-5.4518866539,0,26.2624912262),elapsed=2.5338449478})
        for k,v in pairs(extra or {}) do p[k]=v end
        return p
    end
    test("DB recorded sideways release recovers alignment after the receiver turns upfield",function()
        local f,r=Field,{}
        for _,side in ipairs({-1,1}) do
            for _,offset in ipairs({Vector3.zero,Vector3.new(130,0,-240)}) do
                local function reflected(x) return f.MidX+side*(x-f.MidX) end
                local p=input({role="DB",phase="Live",elapsed=.566566,LOS=f.LOSZ,offset=offset,
                    position=Vector3.new(reflected(27.000877),4.636868,-8.983637)+offset,
                    velocity=Vector3.new(side*-20,0,0),
                    opponentPosition=Vector3.new(reflected(6.681392),4.636789,-13.701223)+offset,
                    opponentVelocity=Vector3.new(side*5.477962,0,19.226883),
                    stamina=100,sprintOn=false})
                local d=Policy.movement(p,Config,f,r)
                assert(d.sprint,"recorded twenty-stud alignment gap was left at walking speed")
                assert((d.target.X-p.position.X)*side<0 and d.target.Z>p.position.Z,
                    "alignment recovery changed the existing coverage target")
                for _,case in ipairs({{84,false,false},{85,false,true},{71,true,true},{70,true,false}}) do
                    p.stamina=case[1];p.sprintOn=case[2]
                    assert(Policy.movement(p,Config,f,r).sprint==case[3],"alignment burst bypassed ordinary reserve")
                end
            end
        end
    end)
    test("DB opening alignment burst has spatial hysteresis and a bounded live window",function()
        -- Integer yard units and a zero-centered receiver make the exact
        -- strict boundaries representable, independent of translation ulps.
        local f,r=table.clone(Field),{}
        f.MinX,f.MaxX,f.MidX,f.YD=-30,30,0,3
        local p=input({role="DB",phase="Live",elapsed=.6,LOS=f.LOSZ,
            opponentPosition=Vector3.new(f.MidX,4.636868,10),
            opponentVelocity=Vector3.new(0,0,20),velocity=Vector3.new(-20,0,0),
            stamina=100,sprintOn=false})
        local function at(lateral,depth)
            p.position=p.opponentPosition+Vector3.new(lateral*f.YD,0,depth*f.YD)
            return Policy.movement(p,Config,f,r)
        end
        assert(at(3.01,1).sprint and not at(3,1).sprint)
        p.sprintOn=true
        assert(at(2.99,1).sprint and at(1.51,1).sprint and not at(1.5,1).sprint)
        p.sprintOn=false
        assert(not at(1.51,1).sprint,"release edge restarted the alignment burst")
        assert(not at(4,2).sprint,"large goal-side cushion spent sprint")
        at(4,1)
        for _,elapsed in ipairs({0,.399,1.501,5}) do
            p.elapsed=elapsed;assert(not Policy.movement(p,Config,f,r).sprint)
        end
        p.elapsed=nil;assert(not Policy.movement(p,Config,f,r).sprint)
        for _,elapsed in ipairs({.4,1.5}) do
            p.elapsed=elapsed;assert(Policy.movement(p,Config,f,r).sprint)
        end
        p.elapsed=.6
        for _,phase in ipairs({"PreSnap","Hike"}) do
            p.phase=phase;assert(not Policy.movement(p,Config,f,r).sprint)
        end
        p.phase="Live"
        for _,forward in ipairs({-20,0,2,10}) do
            p.opponentVelocity=Vector3.new(0,0,forward)
            assert(not Policy.movement(p,Config,f,r).sprint,"idle/retreating receiver triggered alignment sprint")
        end
        p.opponentVelocity=Vector3.new(0,0,20)
        p.opponentPosition=Vector3.new(f.MidX,4.636868,f.GoalZ-5*f.YD)
        assert(not at(4,1).sprint,"opening alignment rule changed near-goal urgency")
    end)
    test("recorded opening diagonal sprint gets a burst before the old three-yard forecast gate",function()
        local p=openingRun();local c=move(p)
        local gap=(p.opponentPosition-p.position).Magnitude
        assert(gap>1.25*Field.YD and gap<2*Field.YD)
        assert(math.abs(p.opponentVelocity.X)<Config.RunSpeed+2)
        assert(p.position.Z-p.opponentPosition.Z>-2*Field.YD)
        assert(c.sprint,"opening diagonal sprint remained at walking speed")
        assert(c.target.Z>p.position.Z,"burst did not preserve forward tracking")
    end)
    test("nearby opening coverage and walking matched or retreating runs do not start a range burst",function()
        local nearby=openingRun({position=Vector3.new(16.420358658,3,8.325592995),
            velocity=Vector3.new(3.713122606,0,19.652296066),
            opponentPosition=Vector3.new(12.438441277,3,9.279882431),
            opponentVelocity=Vector3.new(4.502198219,0,26.622373581),elapsed=1.714122057})
        assert(not move(nearby).sprint,"a close receiver caused body-press sprinting")
        for _,v in ipairs({Vector3.zero,Vector3.new(-4,0,19),Vector3.new(-5,0,-26)}) do
            assert(not move(openingRun({opponentVelocity=v})).sprint)
        end
        local p=openingRun();p.velocity=p.opponentVelocity
        assert(not move(p).sprint,"matching speed without opening range caused a new burst")
        p=openingRun({velocity=false})
        assert(not move(p).sprint,"unknown local velocity was treated as measured separation")
        p=openingRun({phase="PreSnap"});assert(not move(p).sprint)
        p.phase="Hike";assert(not move(p).sprint)
    end)
    test("range recovery retains85-start70-stop and does not stop merely because speed matches",function()
        local p=openingRun()
        for _,stamina in ipairs({0,40,70,84.9}) do p.stamina=stamina;assert(not move(p).sprint) end
        p.stamina=85;assert(move(p).sprint)
        p.sprintOn=true;p.velocity=p.opponentVelocity
        p.stamina=70.1;assert(move(p).sprint,"matched sprint speed caused immediate on-off chatter")
        p.stamina=70;assert(not move(p).sprint,"range recovery spent the reserved stamina")
        p.stamina=100;p.position=p.opponentPosition-Vector3.new(0,0,.9*Field.YD)
        assert(not move(p).sprint,"range recovery chased a fixed offset inside the release band")
    end)
    test("range recovery releases when the receiver slows or runs back toward the defender",function()
        local p=openingRun({sprintOn=true})
        p.opponentVelocity=Vector3.new(0,0,20);assert(not move(p).sprint)
        p.opponentVelocity=Vector3.new(26,0,3);assert(not move(p).sprint)
        p.opponentVelocity=Vector3.new(0,0,-27);assert(not move(p).sprint)
    end)
    test("range recovery is symmetric and unchanged by translated field coordinates",function()
        local p=openingRun();local a=move(p);local mirror=table.clone(p)
        mirror.position=Vector3.new(2*Field.MidX-p.position.X,3,p.position.Z)
        mirror.opponentPosition=Vector3.new(2*Field.MidX-p.opponentPosition.X,3,p.opponentPosition.Z)
        mirror.velocity=Vector3.new(-p.velocity.X,0,p.velocity.Z)
        mirror.opponentVelocity=Vector3.new(-p.opponentVelocity.X,0,p.opponentVelocity.Z)
        local b=move(mirror);assert(a.sprint and b.sprint)
        assert(math.abs(a.target.X+b.target.X-2*Field.MidX)<1e-6)
        local offset=Vector3.new(200,0,-300)
        p.offset=offset;p.position=p.position+offset;p.opponentPosition=p.opponentPosition+offset
        local c=move(p);assert(c.sprint and (c.target-a.target-offset).Magnitude<1e-6)
    end)
    test("recorded outward cut starts lateral follow before the old1.5-yard gate",function()
        local early=input({position=Vector3.new(48.050617218,3,72.211868286),
            opponentPosition=Vector3.new(45.089633941,3,78.445381165),
            opponentVelocity=Vector3.new(-21.526256561,0,10.808526993),elapsed=4.793788})
        local a=move(early)
        assert(a.target.X<early.position.X-Field.YD,"early side cut still leaves X unchanged")
        assert(not a.sprint,"early walking correction spent sprint before the fast-cut trigger")
        local p=input();local b=move(p)
        assert(b.target.X<p.opponentPosition.X and b.sprint,"recorded fast outward cut did not receive recovery burst")
    end)
    test("mirrored and translated cuts receive symmetric coverage",function()
        local p=input();local a=move(p)
        local mirror=table.clone(p);local mid=Field.MidX
        mirror.position=Vector3.new(2*mid-p.position.X,3,p.position.Z)
        mirror.opponentPosition=Vector3.new(2*mid-p.opponentPosition.X,3,p.opponentPosition.Z)
        mirror.opponentVelocity=Vector3.new(-p.opponentVelocity.X,0,p.opponentVelocity.Z)
        local b=move(mirror)
        assert(a.sprint==b.sprint and math.abs(a.target.X+b.target.X-2*mid)<1e-6)
        local offset=Vector3.new(200,0,-300)
        p.offset=offset;p.position=p.position+offset;p.opponentPosition=p.opponentPosition+offset
        local c=move(p)
        assert(c.sprint==a.sprint and (c.target-a.target-offset).Magnitude<1e-6)
    end)
    test("lateral recovery retains85-start70-stop stamina hysteresis",function()
        local p=input()
        for _,stamina in ipairs({0,40,70,84.9}) do p.stamina=stamina;assert(not move(p).sprint) end
        p.stamina=85;assert(move(p).sprint)
        p.sprintOn=true;p.stamina=70;assert(not move(p).sprint)
        p.stamina=70.1;assert(move(p).sprint)
    end)
    test("inward slow idle and safely retreating motion do not cause new side bursts",function()
        local p=input()
        for _,v in ipairs({Vector3.zero,Vector3.new(-15,0,0),Vector3.new(25,0,0),Vector3.new(-15,0,-5)}) do
            p.opponentVelocity=v;assert(not move(p).sprint)
        end
    end)
    test("closing the lateral gap releases the burst rather than maintaining a fixed offset",function()
        local p=input({sprintOn=true,position=Vector3.new(42.5,3,78),velocity=Vector3.new(-27,0,0)})
        assert(not move(p).sprint)
        p=input({velocity=Vector3.new(-27,0,0)})
        assert(not move(p).sprint,"already-closing lateral gap triggered a fresh burst")
    end)
    test("routine alignment follows directly behind with only a small open-field shade",function()
        for _,x in ipairs({Field.MinX+5,Field.MidX,Field.MaxX-5}) do
            local p=input({position=Vector3.new(x+5,3,30),opponentPosition=Vector3.new(x,3,32),
                opponentVelocity=Vector3.zero,velocity=Vector3.zero})
            local c=move(p)
            assert(not c.sprint and math.abs(c.target.X-x)<=.21*Field.YD)
            if x<Field.MidX then assert(c.target.X>=x) elseif x>Field.MidX then assert(c.target.X<=x) end
        end
    end)
    test("lineup retains non-crowding unsprinted behavior",function()
        local p=input({phase="PreSnap",position=Vector3.new(30,3,0),
            opponentPosition=Vector3.new(20,3,0),opponentVelocity=Vector3.new(-27,0,0)})
        local c=move(p)
        assert(not c.sprint and c.target.Z-p.opponentPosition.Z>=Field.YD)
        assert(math.abs(c.target.X-p.opponentPosition.X)<=.21*Field.YD)
        p.phase="Hike";p.position=Vector3.new(10,3,0)
        c=move(p);assert(not c.sprint and math.abs(c.target.X-p.opponentPosition.X)<=.21*Field.YD)
        p.position=Vector3.new(c.target.X+.1*Field.YD,3,c.target.Z)
        assert(move(p).target.X==p.position.X,"minor lineup jitter caused offset chasing")
    end)
    local function retreatingSideCut(extra)
        local p=input({position=Vector3.new(-1.341536522,3,56.32739258),velocity=Vector3.new(20.17902374,0,0),
            opponentPosition=Vector3.new(4.594630241,3,48.19269562),
            opponentVelocity=Vector3.new(26.20711136,0,-6.492323875),elapsed=4.740035057,stamina=98})
        for k,v in pairs(extra or {}) do p[k]=v end
        return p
    end
    test("fast outward sideways retreat preserves lateral recovery on both sides without changing depth",function()
        local p=retreatingSideCut();local a=move(p)
        assert(a.sprint and a.target.X>p.opponentPosition.X,"negative depth velocity hid a fast outward cut")
        assert(a.target.Z==p.position.Z,"lateral recovery moved the depth target")
        local mirror=table.clone(p)
        mirror.position=Vector3.new(2*Field.MidX-p.position.X,3,p.position.Z)
        mirror.opponentPosition=Vector3.new(2*Field.MidX-p.opponentPosition.X,3,p.opponentPosition.Z)
        mirror.velocity=Vector3.new(-p.velocity.X,0,p.velocity.Z)
        mirror.opponentVelocity=Vector3.new(-p.opponentVelocity.X,0,p.opponentVelocity.Z)
        local b=move(mirror)
        assert(b.sprint and math.abs(a.target.X+b.target.X-2*Field.MidX)<1e-6)
        assert(b.target.Z==mirror.position.Z)
    end)
    test("retreating lateral recovery retains85-start70-stop and releases for safe motion or small gaps",function()
        local p=retreatingSideCut()
        for _,stamina in ipairs({0,40,70,84.9}) do p.stamina=stamina;assert(not move(p).sprint) end
        p.stamina=85;assert(move(p).sprint)
        p.sprintOn=true;p.stamina=70.1;assert(move(p).sprint)
        p.stamina=70;assert(not move(p).sprint)
        for _,velocity in ipairs({Vector3.new(0,0,-27),Vector3.new(15,0,-6),Vector3.new(-26,0,-6)}) do
            p=retreatingSideCut({sprintOn=true,opponentVelocity=velocity})
            assert(not move(p).sprint,"pure/slow/inward retreat prolonged a side burst")
        end
        for _,phase in ipairs({"PreSnap","Hike"}) do
            assert(not move(retreatingSideCut({phase=phase})).sprint)
        end
        p=retreatingSideCut({sprintOn=true})
        p.position=Vector3.new(p.opponentPosition.X-.5*Field.YD,3,p.position.Z)
        assert(not move(p).sprint,"continued sprint inside the lateral release band")
        p=retreatingSideCut({sprintOn=true})
        p.position=Vector3.new(p.position.X,3,p.opponentPosition.Z+3.01*Field.YD)
        assert(not move(p).sprint,"lateral recovery crossed the unchanged depth band")
    end)
    test("confirmed opposing possession funds the DB chase without spending the native sprint floor",function()
        for _,phase in ipairs({"RAC","Run"}) do
            local p=input({phase=phase,enemyCarrier=true,stamina=42})
            local original=p.stamina
            local c=move(p)
            assert(c.kind=="pursue" and c.sprint,"confirmed carrier chase retained the prethrow reserve")
            assert(p.stamina==original and c.target.Z>=p.opponentPosition.Z)
            for _,stamina in ipairs({0,2,5.75}) do
                p.stamina=stamina;assert(not move(p).sprint,"chase spent the reserve and native input allowance")
            end
            p.stamina=5.76;assert(move(p).sprint)
            p.stamina=nil;assert(not move(p).sprint,"unknown stamina funded a chase")
        end
    end)
    test("low pursuit reserve requires known enemy possession and keeps Live and WR reserves",function()
        for _,phase in ipairs({"RAC","Run"}) do
            local p=input({phase=phase,enemyCarrier=false,stamina=42})
            assert(Policy.movement(p,Config,Field,{})==nil)
            p.enemyCarrier=nil;assert(Policy.movement(p,Config,Field,{})==nil)
            p.enemyCarrier="unknown";assert(Policy.movement(p,Config,Field,{})==nil)
            p.enemyCarrier=true;p.opponentPosition=nil
            assert(Policy.movement(p,Config,Field,{})==nil,"missing carrier position enabled pursuit")
        end
        local p=input({phase="Live",enemyCarrier=true,stamina=42})
        assert(not move(p).sprint,"Live reserve was relaxed without the confirmed catch phase")
        p.stamina=43.75;assert(not move(p).sprint)
        p.stamina=43.76;assert(move(p).sprint)
        p.phase="RAC";p.role="WR";p.stamina=13.75
        assert(not move(p).sprint,"WR reserve changed with the DB chase fix")
        p.stamina=13.76;assert(move(p).sprint)
        p.phase=nil;assert(Policy.movement(p,Config,Field,{})==nil)
    end)
    return report
end
