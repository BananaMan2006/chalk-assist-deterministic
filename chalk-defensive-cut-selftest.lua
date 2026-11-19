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
        for _,v in ipairs({Vector3.zero,Vector3.new(-15,0,0),Vector3.new(25,0,0),Vector3.new(-25,0,-5)}) do
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
    return report
end
