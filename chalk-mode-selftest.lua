-- Pure tests of the exact bootstrap policy embedded in overlay-core source.
-- Usage: loadstring(testSource)()(overlayCoreSource). No game services or input.
return function(coreSource)
    local policy=assert(coreSource:match("%-%- MODE_POLICY_BEGIN[^\n]*\n(.-)%-%- MODE_POLICY_END"),"Mode policy missing")
    local helpers=assert(loadstring(policy.."\nreturn {mode=selectBootstrapMode,geo=selectTeamGeometry,valid=validGeo}"))()
    local results,failed={},0
    local function test(name,fn)
        local ok,err=pcall(fn)
        results[#results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
        if not ok then failed=failed+1 end
    end
    test("1v1 Live WR survives stale Team geometry on reload",function()
        assert(helpers.mode("Live","WR","1v1","reload")=="1v1")
    end)
    test("native plain Live role repairs a previously corrupted Team mode",function()
        assert(helpers.mode("Live","DB","Team","reload")=="1v1")
    end)
    test("native team Live role overrides an old 1v1 context",function()
        for _,role in ipairs({"TWR","TDB","TQB"}) do assert(helpers.mode("Live",role,"1v1")=="Team") end
    end)
    test("trusted Team survives ambiguous plain PreSnap roles",function()
        for _,role in ipairs({"WR","DB"}) do assert(helpers.mode("PreSnap",role,"Team","match")=="Team") end
    end)
    test("trusted Team survives native RAC roles after a catch",function()
        for _,role in ipairs({"WR","DB"}) do assert(helpers.mode("RAC",role,"Team","match")=="Team") end
    end)
    test("geometry without mode evidence cannot establish Team",function()
        assert(helpers.mode("PreSnap","WR",nil)==nil)
    end)
    test("known 1v1 survives ambiguous PreSnap roles",function()
        assert(helpers.mode("PreSnap","DB","1v1","match")=="1v1")
    end)
    test("Lobby clears old Team and native role evidence",function()
        assert(helpers.mode("Lobby","TDB","Team")==nil)
    end)
    local base={MinX=-50,MaxX=50,BackZ=-100,EndZ=100,TurfY=1.6}
    local current={MinX=500,MaxX=600,BackZ=100,EndZ=500,TurfY=1.6}
    local stale={MinX=-600,MaxX=-500,BackZ=100,EndZ=500,TurfY=1.6}
    test("base Field is never recovered as Team geometry",function()
        assert(helpers.geo(nil,{base},base)==nil)
    end)
    test("observed Team packet geometry outranks cached upvalues",function()
        assert(helpers.geo(current,{base,stale},base)==current)
    end)
    test("fresh native Team role can recover complete Team geometry",function()
        assert(helpers.geo(nil,{base,current},base)==current)
    end)
    test("incomplete or inverted geometry is not usable for catch bounds",function()
        assert(not helpers.valid({MinX=0,MaxX=10,TurfY=0}))
        assert(not helpers.valid({MinX=10,MaxX=0,BackZ=0,EndZ=10,TurfY=0}))
        assert(not helpers.valid({MinX=0,MaxX=10,BackZ=0,EndZ=math.huge,TurfY=0}))
    end)
    return {total=#results,passed=#results-failed,failed=failed,results=results}
end
