-- Executes the actual tracking/reset/refresh blocks with isolated data fixtures.
return function(Motion,source)
    local observe=assert(source:match("(    local function locomotionState.-)    local function motionState"))
    local release=assert(source:match("(    local function releaseSprint.-)    local function release%("))
    local refresh=assert(source:match("(        if plan and lastSnapshot then.-)        if wrReturn and"))
    local budget=assert(source:match("(    local function sprintBudget.-)    local function snapshot"))
    local compile=loadstring or load
    local reserve=assert(compile([[
return function(Motion,f)
    local trackedSprintRoot,sprintTracking,ownsSprint={},{},false
    local Config={SprintDrain=25}
    local me={GetAttribute=function(_,key) return f.attrs[key] end}
    local Moves={HoldSprint=function(value) f.attrs.SprintOn=value;f.calls=(f.calls or 0)+1 end}
]]..budget..[[
    return enforceSprintReserve(f.context),trackedSprintRoot,sprintTracking
end]],"sprint-reserve-fixture"))()
    local tracking=assert(compile([[
return function(Motion,f)
    local trackedSprintRoot,sprintTracking,ownsSprint
    local Config={RunSpeed=20,SprintSpeed=27,SprintDrain=25}
    local me={GetAttribute=function(_,key) return f.attrs[key] end}
    local UIS={IsKeyDown=function() return f.manualSprint==true end}
    local Enum={KeyCode={LeftShift="left",RightShift="right"}}
    local Moves={HoldSprint=function(value) f.attrs.SprintOn=value end}
]]..release..observe..[[
    return {
        observe=function(now) return locomotionState(f.root,f.h,now) end,
        release=function() ownsSprint=true;releaseSprint() end,
    }
end]],"pending-sprint-tracking-fixture"))()
    local refreshPlan=assert(compile([[
return function(Motion,f)
    local plan,lastSnapshot={kind="move"},f.previous
    local currentLocomotion=f.current
    local jumped,dived,jumpRequest=f.jumped,f.dived,f.jumpRequest
    local h={PlatformStand=f.platformStand,WalkSpeed=20}
    local atTarget=f.atTarget
    local motion={grounded=f.grounded~=false}
    local root={Position=Vector3.zero}
    local now,nextSolve=10,0
    local s={role="DB"}
    local function xyz() return {} end
    local function log() f.logged=true end
]]..refresh..[[
    return plan,lastSnapshot,nextSolve
end]],"pending-sprint-refresh-fixture"))()
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,err=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function fixture()
        local f={attrs={SprintOn=true,Stamina=100},root={},h={WalkSpeed=20}}
        f.api=tracking(Motion,f)
        return f
    end
    test("controller keeps a requested sprint pending across repeated snapshots",function()
        local f=fixture()
        assert(f.api.observe(0).walkSpeed==20)
        assert(f.api.observe(.16).walkSpeed==20)
        local speed=f.api.observe(.46)
        assert(speed.sprintPending and speed.sprintPendingAge==.46 and speed.speedScale==1)
    end)
    test("replacing the character resets old pending sprint history",function()
        local f=fixture();f.api.observe(0);assert(f.api.observe(.3).sprintPending)
        f.root={}
        local replaced=f.api.observe(.31)
        assert(replaced.sprintPending and replaced.sprintPendingAge==0)
        assert(f.api.observe(.5).sprintPending)
    end)
    test("release resets tracking even when a manual sprint key keeps the request on",function()
        local f=fixture();f.api.observe(0);assert(f.api.observe(.3).sprintPending)
        f.manualSprint=true;f.api.release()
        local renewed=f.api.observe(.31)
        assert(f.attrs.SprintOn and renewed.sprintPending and renewed.sprintPendingAge==0)
        f.manualSprint=false;f.api.release()
        assert(not f.attrs.SprintOn and not f.api.observe(.5).sprintPending)
    end)
    test("observed sprint off and confirmed speed clear a pending forecast",function()
        local f=fixture();f.api.observe(0);assert(f.api.observe(.3).sprintPending)
        f.attrs.SprintOn=false;assert(not f.api.observe(.31).sprintPending)
        f.attrs.SprintOn=true;assert(f.api.observe(.32).sprintPending)
        assert(f.api.observe(.6).sprintPending)
        f.h.WalkSpeed=27;assert(f.api.observe(.61).walkSpeed==27)
    end)
    test("controller refreshes once when pending starts or native sprint arrives",function()
        local normal,pending={speedScale=1,sprintPending=false},{speedScale=1,sprintPending=true}
        for _,pair in ipairs({{normal,pending},{pending,normal}}) do
            local f={previous=pair[1],current=pair[2]}
            local plan,snapshot,nextSolve=refreshPlan(Motion,f)
            assert(plan==nil and snapshot==nil and nextSolve==10 and f.logged)
        end
        local f={previous=pending,current=pending}
        assert(refreshPlan(Motion,f)~=nil and not f.logged)
    end)
    test("committed jump dive and parked catch ownership survive speed transitions",function()
        for _,key in ipairs({"jumped","dived","jumpRequest","platformStand","atTarget"}) do
            local f={previous={speedScale=1,sprintPending=true},current={speedScale=1}}
            f[key]=true
            assert(refreshPlan(Motion,f)~=nil and not f.logged,key.." lost committed ownership")
        end
        local f={previous={speedScale=1},current={speedScale=1,sprintPending=true},grounded=false}
        assert(refreshPlan(Motion,f)~=nil and not f.logged,"airborne action was interrupted")
    end)
    test("Full Auto reserve releases sprint even when it did not own the request",function()
        local f={attrs={SprintOn=true,Stamina=43},context={role="DB",playBudget={dbReserve=40}}}
        local budget,root,tracking=reserve(Motion,f)
        assert(not budget.canSprint and not f.attrs.SprintOn and f.calls==1)
        assert(root==nil and tracking==nil,"old sprint tracking survived forced release")
    end)
    test("manual catch control does not force off the user's sprint",function()
        local f={attrs={SprintOn=true,Stamina=1},context={role="WR"}}
        local budget=reserve(Motion,f)
        assert(not budget.enforced and f.attrs.SprintOn and f.calls==nil)
    end)
    test("WR reserve permits the final sprint above its dispatch floor",function()
        local f={attrs={SprintOn=true,Stamina=14},context={role="WR",playBudget={wrReserve=10}}}
        local budget=reserve(Motion,f)
        assert(budget.canSprint and budget.seconds==.04 and f.attrs.SprintOn)
        f.attrs.Stamina=13;budget=reserve(Motion,f)
        assert(not budget.canSprint and not f.attrs.SprintOn)
    end)
    return report
end
