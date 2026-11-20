-- Exercises the actual movement helper with a mock Humanoid; no game physics.
return function(source)
    local smooth=assert(source:match("(    local function smoothDirection.-)    local function moveWRApproach"))
    local navigate=assert(source:match("(    local function updateFullplay.-)    local function updateWRReturn"))
    local compile=loadstring or load
    local factory=assert(compile([[
return function(fixture)
    local steering,navigation,controlledHumanoid,ownsSprint
    local ctx={fullplay=function() return fixture.directive end}
    local me={GetAttribute=function(_,key)
        return key=="Stamina" and 100 or key=="SprintOn" and fixture.sprinting
    end}
    local Moves={Upright=function() return true end,
        HoldSprint=function(value) fixture.sprinting=value end}
    local function ownInput() end
    local function releaseSprint() fixture.sprinting=false end
    local function sprintBudget() return {canSprint=fixture.canSprint~=false} end
    local carrierAssist=fixture.carrier
]]..smooth..navigate..[[
    return function(dt) return updateFullplay({},fixture.root,fixture.humanoid,0,dt) end
end
]],"fullplay-steering-fixture"))()
    local report={total=0,passed=0,failed=0,results={}}
    local function harness(carrier)
        local f={root={},moves={},carrier=carrier}
        f.humanoid={Move=function(_,direction,relative)
            assert(relative==false)
            f.moves[#f.moves+1]=direction
        end}
        f.tick=factory(f)
        function f:move(direction,preserve)
            self.directive={direction=direction,sprint=true,preserveDepth=preserve}
            assert(self.tick(1/60))
            return self.moves[#self.moves]
        end
        return f
    end
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function reversal(start,goal)
        local f=harness()
        local last=f:move(start,true)
        for _=1,25 do
            local current=f:move(goal,true)
            assert(current.Z>=-1e-12,"coverage turn moved backward")
            assert(last:Dot(current)>=math.cos(9/60)-1e-9,"direction changed faster than turn limit")
            last=current
        end
        assert(last:Dot(goal.Unit)>.999999,"turn never reached requested heading")
    end
    test("left-to-right coverage reversal keeps depth smoothly",function()
        reversal(Vector3.new(-1,0,0),Vector3.new(1,0,0))
    end)
    test("right-to-left coverage reversal keeps depth smoothly",function()
        reversal(Vector3.new(1,0,0),Vector3.new(-1,0,0))
    end)
    test("forward diagonal coverage reversal keeps depth smoothly",function()
        reversal(Vector3.new(-1,0,.1),Vector3.new(1,0,.1))
    end)
    test("tiny negative lateral components do not choose a backward coverage semicircle",function()
        for _,side in ipairs({-1,1}) do
            for _,epsilon in ipairs({1e-12,1e-7,5e-7}) do
                local f=harness()
                local last=f:move(Vector3.new(side,0,-epsilon),true)
                for _=1,25 do
                    local current=f:move(Vector3.new(-side,0,-epsilon),true)
                    assert(current.Z>=-1e-6,"rounded lateral coverage heading turned backward")
                    assert(last:Dot(current)>=math.cos(9/60)-1e-9,"rounding fix bypassed turn limit")
                    last=current
                end
                assert(last:Dot(Vector3.new(-side,0,-epsilon).Unit)>.999999)
            end
        end
    end)
    test("real backward components and ordinary near-lateral steering retain their semantics",function()
        for _,side in ipairs({-1,1}) do
            for _,epsilon in ipairs({2e-6,.005,.1}) do
                local a,b=harness(),harness()
                local start=Vector3.new(side,0,-epsilon)
                local goal=Vector3.new(-side,0,-epsilon)
                a:move(start,true);b:move(start,false)
                for _=1,25 do
                    assert((a:move(goal,true)-b:move(goal,false)).Magnitude<1e-10)
                end
            end
            local f=harness();f:move(Vector3.new(side,0,-1e-7),false)
            assert(f:move(Vector3.new(-side,0,-1e-7),false).Z<0,
                "ordinary steering inherited the coverage tolerance")
        end
    end)
    test("ordinary catch and pursuit steering preserves wrapped baseline",function()
        local f=harness();f:move(Vector3.new(-1,0,0),false)
        local next=f:move(Vector3.new(1,0,0),false)
        assert(next.Z<0 and next.X<0,"ordinary steering was changed")
    end)
    test("explicit backward target retains ordinary turn semantics",function()
        local a,b=harness(),harness()
        a:move(Vector3.new(-1,0,0),true);b:move(Vector3.new(-1,0,0),false)
        local goal=Vector3.new(1,0,-.1)
        for _=1,25 do
            local av,bv=a:move(goal,true),b:move(goal,false)
            assert((av-bv).Magnitude<1e-10)
        end
    end)
    test("carrier move cannot run when full auto has no movement directive",function()
        local called=0
        local f=harness({update=function() called=called+1;return true,"juke" end})
        assert(not f.tick(1/60) and called==0)
    end)
    test("confirmed carrier burst owns movement without another navigation input",function()
        local called=0
        local f=harness({update=function() called=called+1;return true,"juke" end})
        f.directive={direction=Vector3.new(0,0,1),sprint=true}
        f.sprinting=true
        local active,note=f.tick(1/60)
        assert(active and note=="juke" and called==1 and #f.moves==0 and not f.sprinting)
    end)
    test("declined carrier action preserves ordinary navigation",function()
        local f=harness({update=function() return false end})
        local direction=f:move(Vector3.new(0,0,1),false)
        assert(direction.Z>.999 and f.sprinting)
    end)
    test("reserve blocks a requested sprint without blocking movement",function()
        local f=harness();f.canSprint=false
        local direction=f:move(Vector3.new(0,0,1),false)
        assert(direction.Z>.999 and not f.sprinting)
    end)
    return report
end
