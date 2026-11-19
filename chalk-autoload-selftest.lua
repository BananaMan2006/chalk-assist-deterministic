-- Lifecycle/capability fixtures only. Executes the real loader/controller sources
-- in isolated environments; does not assert executor attachment or network behavior.
return function(bootstrapSource, controllerSource, localLoaderSource)
    bootstrapSource=bootstrapSource:gsub("CHALK_BOOTSTRAP_VERSION","4.2.0")
    local result={total=0,passed=0,failed=0,results={}}
    local nativeLoadstring,nativeLoad,nativeSetfenv=loadstring,load,setfenv
    local BOOT,QUEUE="__ChalkDeterministicAutoBoot","__ChalkDeterministicTeleportQueue"
    local MAIN,CACHE="chalk-it-up-1v1.lua","chalk-deterministic-cache.lua"
    local function build(version,body)
        return "-- Chalk-Release: "..version.."\n-- Chalk-Product: deterministic\n"..(body or "markExecuted('"..version.."')")
    end
    local function compile(source,env)
        local chunk,err
        if type(nativeSetfenv)=="function" and type(nativeLoadstring)=="function" then
            chunk,err=nativeLoadstring(source,"autoload fixture")
            if chunk then nativeSetfenv(chunk,env) end
        else
            chunk,err=nativeLoad(source,"autoload fixture","t",env)
        end
        return chunk,err
    end
    local function equal(actual,expected,message)
        assert(actual==expected,(message or "mismatch")..": expected "..tostring(expected)..", got "..tostring(actual))
    end
    local function test(name,body)
        result.total=result.total+1
        local ok,err=pcall(body)
        result.results[#result.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
        if ok then result.passed=result.passed+1 else result.failed=result.failed+1 end
    end
    local function node(name,children,class)
        local value={Name=name,children=children or {},class=class or "Folder"}
        function value:FindFirstChild(key) return self.children[key] end
        function value:IsA(kind) return self.class==kind end
        return value
    end
    local function harness()
        local h={clock=0,executions=0,downloads=0,reads=0,writes=0,waits=0,
            body=build("4.2.0"),files={},warnings={},loaded=true,compiledSources={}}
        local signal={listeners={},disconnected=0}
        function signal:Connect(callback)
            local slot={callback=callback,connected=true};self.listeners[#self.listeners+1]=slot
            return {Disconnect=function()
                if slot.connected then slot.connected=false;signal.disconnected=signal.disconnected+1 end
            end}
        end
        function signal:fire(state)
            for _,slot in ipairs(self.listeners) do if slot.connected then slot.callback(state) end end
        end
        h.signal=signal
        h.moves=node("Moves",{},"ModuleScript")
        h.gameScripts=node("Game",{Moves=h.moves})
        h.player=node("Player",{PlayerGui=node("PlayerGui"),
            PlayerScripts=node("PlayerScripts",{Game=h.gameScripts})})
        h.player.OnTeleport=signal
        h.shared=node("Shared",{Config=node("Config"),Field=node("Field"),DivePath=node("DivePath")})
        h.rs=node("ReplicatedStorage",{Shared=h.shared,
            Remotes=node("Remotes",{Match=node("Match"),Fx=node("Fx")})})
        local lines=node("Lines")
        for _,name in ipairs({"Sideline_L","Sideline_R","BackLine","EndLine","GoalLine"}) do
            lines.children[name]=node(name)
        end
        h.world=node("Workspace",{Fields=node("Fields",{
            Field1=node("Field1",{Lines=lines,Endzone=node("Endzone")})})})
        h.game={GameId=10770281752,PlaceId=116097127629859,JobId="job-a"}
        function h.game:IsLoaded() return h.loaded end
        function h.game:GetService(name)
            if name=="Players" then return {LocalPlayer=h.player} end
            if name=="ReplicatedStorage" then return h.rs end
            error("Unexpected service: "..tostring(name))
        end
        function h.game:HttpGet(url)
            h.downloads=h.downloads+1
            assert(url=="https://raw.githubusercontent.com/BananaMan2006/chalk-assist-deterministic/main/chalk-it-up-1v1.lua?chalk_boot="..tostring(1795000000+math.floor(h.clock)))
            if h.httpError then error("HTTP unavailable") end
            return h.body
        end
        local env=setmetatable({game=h.game,workspace=h.world,
            queue_on_teleport=false,queueonteleport=false,syn=false,
            request=false,http_request=false}, {__index=_G})
        h.env=env;env._G=env;env.getgenv=function() return env end
        env.os={clock=function() return h.clock end,time=function() return 1795000000+math.floor(h.clock) end}
        env.task={wait=function(dt)
            h.clock=h.clock+(dt or .1);h.waits=h.waits+1
            if h.onWait then h.onWait() end
        end,spawn=function(fn) fn() end}
        env.warn=function(message) h.warnings[#h.warnings+1]=message end
        env.loadstring=function(source)
            h.compiledSources[#h.compiledSources+1]=source
            return compile(source,env)
        end
        env.readfile=function(path)
            h.reads=h.reads+1
            assert(path==MAIN or path==CACHE,"Unexpected file read")
            assert(h.files[path],"Missing fixture file")
            return h.files[path]
        end
        env.writefile=function(path,value)
            assert(path==MAIN or path==CACHE or path=="ciu_autoload_status.txt","Unexpected file write")
            h.writes=h.writes+1;h.files[path]=value
        end
        env.markExecuted=function(version)
            h.executions=h.executions+1
            h.executedRelease=version
            if h.startupError then error("Fixture startup failure") end
            local appJob=h.game.JobId
            env.ChalkDB={status=function() return {auto={},product="deterministic"} end,
                context=function() return {jobId=appJob} end}
        end
        function h:bootstrap(options)
            local chunk,err=compile(bootstrapSource,self.env);assert(chunk,err)
            return chunk(options)
        end
        function h:controller()
            local chunk,err=compile(controllerSource,self.env);assert(chunk,err)
            return chunk()({bootstrapSource=bootstrapSource},
                {game=self.game,env=self.env,globals=self.env,player=self.player})
        end
        function h:localLoader()
            local chunk,err=compile(localLoaderSource,self.env);assert(chunk,err);chunk()
        end
        return h
    end

    test("wrong game performs no HTTP or file operations",function()
        local h=harness();h.game.GameId=1
        local ok,state=h:bootstrap({automatic=true});equal(ok,true);equal(state,"unsupported-game")
        equal(h.downloads+h.reads+h.writes,0);equal(h.env[BOOT],nil)
    end)
    test("unverified place is guarded",function()
        local h=harness();h.game.PlaceId=1;h:bootstrap();equal(h.downloads+h.reads+h.writes,0)
    end)
    test("loaded and native dependencies are awaited before download",function()
        local h=harness();h.loaded=false;h.gameScripts.children.Moves=nil
        h.onWait=function()
            equal(h.downloads,0)
            if h.waits==2 then h.loaded=true end
            if h.waits==4 then h.gameScripts.children.Moves=h.moves end
        end
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-public")
        equal(h.waits,4);equal(h.executions,1);equal(h.files[CACHE],h.body)
        equal(h.files[MAIN],h.body)
    end)
    test("same server automatic startup is idempotent",function()
        local h=harness();h:bootstrap({automatic=true});h:bootstrap({automatic=true})
        equal(h.executions,1);equal(h.downloads,1)
    end)
    test("waiting marker blocks concurrent startup",function()
        local h=harness();h.env[BOOT]={gameId=h.game.GameId,placeId=h.game.PlaceId,jobId=h.game.JobId,state="waiting"}
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"already-starting");equal(h.downloads,0)
    end)
    test("F8 stays unloaded automatically; manual startup can resume",function()
        local h=harness();h:bootstrap();h.env[BOOT].state="unloaded";h.env.ChalkDB=nil
        local ok,state=h:bootstrap({automatic=true});equal(ok,true);equal(state,"already-started")
        equal(h.executions,1);h:bootstrap();equal(h.executions,2)
    end)
    test("new server reloads despite inherited old markers and app",function()
        local h=harness();h:bootstrap({automatic=true});h.game.JobId="job-b"
        h:bootstrap({automatic=true});equal(h.executions,2);equal(h.env[BOOT].jobId,"job-b")
    end)
    test("old app without marker cannot suppress a new server load",function()
        local h=harness();h:bootstrap();h.game.JobId="job-b";h.env[BOOT]=nil
        h:bootstrap({automatic=true});equal(h.executions,2)
    end)
    test("dependency timeout clears marker and permits retry",function()
        local h=harness();h.gameScripts.children.Moves=nil
        local ok=h:bootstrap({automatic=true});equal(ok,false);equal(h.env[BOOT],nil);equal(h.downloads,0)
        assert(h.clock>=90 and h.clock<91)
        h.gameScripts.children.Moves=h.moves;equal(h:bootstrap({automatic=true}),true);equal(h.executions,1)
    end)
    test("F8 during dependency wait cancels pending public startup",function()
        local h=harness();h.gameScripts.children.Moves=nil
        h.onWait=function()
            h.env.markExecuted();h:controller().unload()
            h.gameScripts.children.Moves=h.moves
        end
        local ok,state=h:bootstrap({automatic=true})
        equal(ok,true);equal(state,"unloaded");equal(h.downloads,0);equal(h.executions,1)
        equal(h.env[BOOT].state,"unloaded")
    end)
    test("manual main during dependency wait prevents duplicate startup",function()
        local h=harness();h.gameScripts.children.Moves=nil
        h.onWait=function()
            h.env.markExecuted();h:controller();h.gameScripts.children.Moves=h.moves
        end
        local ok,state=h:bootstrap({automatic=true})
        equal(ok,true);equal(state,"already-running");equal(h.downloads,0);equal(h.executions,1)
    end)
    test("F8 during HTTP prevents execution and cache writes",function()
        local h=harness()
        h.game.HttpGet=function()
            h.downloads=h.downloads+1;h.env.markExecuted();h:controller().unload();return h.body
        end
        local ok,state=h:bootstrap({automatic=true})
        equal(ok,true);equal(state,"unloaded");equal(h.executions,1);equal(h.files[CACHE],nil)
    end)
    test("download failure uses cached source",function()
        local h=harness();h.httpError=true;h.files[CACHE]=build("4.2.0")
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-cache");equal(h.executions,1)
    end)
    test("invalid download falls back to local installed main",function()
        local h=harness();h.body="this is not valid Lua";h.files[MAIN]=build("4.2.0")
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-cache");equal(h.executions,1)
    end)
    test("runtime failure neither poisons cache nor executes fallback",function()
        local h=harness();h.startupError=true;h.files[CACHE]="old cache";h.files[MAIN]="installed good build"
        equal(h:bootstrap(),false);equal(h.env[BOOT],nil);equal(h.files[CACHE],"old cache");equal(h.executions,1)
        equal(h.files[MAIN],"installed good build")
        h.startupError=false;equal(h:bootstrap(),true);equal(h.executions,2)
    end)
    test("online startup works without file APIs",function()
        local h=harness();h.env.readfile=false;h.env.writefile=false
        equal(h:bootstrap(),true);equal(h.executions,1);equal(h.reads+h.writes,0)
    end)
    test("request fallback works when HttpGet is unavailable",function()
        local h=harness();h.game.HttpGet=nil
        h.env.request=function(args)
            equal(args.Method,"GET");equal(args.Headers["Cache-Control"],"no-cache")
            assert(args.Url:find("?chalk_boot=",1,true))
            return {StatusCode=200,Body=h.body}
        end
        equal(h:bootstrap(),true);equal(h.executions,1)
    end)
    test("no valid download or cache fails without a sticky marker",function()
        local h=harness();h.httpError=true
        equal(h:bootstrap(),false);equal(h.env[BOOT],nil);equal(h.executions,0)
    end)
    test("stale public response cannot downgrade installed release",function()
        local h=harness();h.body=build("4.1.0");h.files[MAIN]=build("4.2.0")
        local installed=h.files[MAIN]
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-cache")
        equal(h.executedRelease,"4.2.0");equal(h.files[MAIN],installed);equal(h.files[CACHE],nil)
        for _,source in ipairs(h.compiledSources) do assert(source~=h.body,"Stale download was compiled") end
    end)
    test("newest valid local release sets floor above bootstrap minimum",function()
        local h=harness();h.body=build("4.3.0");h.files[MAIN]=build("4.9.0");h.files[CACHE]=build("4.10.0")
        local cache,main=h.files[CACHE],h.files[MAIN]
        equal(h:bootstrap(),true);equal(h.executedRelease,"4.10.0")
        equal(h.files[CACHE],cache);equal(h.files[MAIN],main)
    end)
    test("newer installed main wins over older valid cache",function()
        local h=harness();h.httpError=true;h.files[CACHE]=build("4.2.0");h.files[MAIN]=build("4.2.1")
        equal(h:bootstrap(),true);equal(h.executedRelease,"4.2.1")
    end)
    test("newer public release replaces local copies only after startup",function()
        local h=harness();h.body=build("5.0.0");h.files[MAIN]=build("4.9.9");h.files[CACHE]=build("4.2.0")
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-public")
        equal(h.executedRelease,"5.0.0");equal(h.files[MAIN],h.body);equal(h.files[CACHE],h.body)
    end)
    test("missing or malformed first-line release metadata is rejected",function()
        for _,body in ipairs({"markExecuted()",build("4.2"),build("4.2.0-beta"),build("04.2.0"),
            build("4.02.0"),build("4.2.00"),build("1000000.2.0"),build("4.2.0 "),
            "\n"..build("4.2.0"),"-- anything else\n"..build("4.2.0")}) do
            local h=harness();h.body=body
            equal(h:bootstrap(),false);equal(h.executions,0);equal(h.files[MAIN],nil);equal(h.files[CACHE],nil)
            equal(#h.compiledSources,0);equal(h.env[BOOT],nil)
        end
    end)
    test("below-minimum or unversioned local sources are not fallback candidates",function()
        local h=harness();h.body=build("4.1.9");h.files[MAIN]=build("4.1.99");h.files[CACHE]="markExecuted()"
        equal(h:bootstrap(),false);equal(h.executions,0);equal(#h.compiledSources,0)
    end)
    test("invalid higher-version local source does not raise floor",function()
        local h=harness();h.files[MAIN]=build("9.0.0","invalid Lua !");h.files[CACHE]=build("4.2.0")
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-public")
        equal(h.executedRelease,"4.2.0")
    end)
    test("valid metadata with invalid downloaded syntax falls back",function()
        local h=harness();h.body=build("5.0.0","invalid Lua !");h.files[MAIN]=build("4.2.0")
        local ok,state=h:bootstrap();equal(ok,true);equal(state,"loaded-cache");equal(h.executedRelease,"4.2.0")
    end)
    test("source limit applies to downloads and local fallback before compilation",function()
        local h=harness();h.body=build("5.0.0",string.rep(" ",2*1024*1024));h.files[CACHE]=h.body
        h.files[MAIN]=build("4.2.0");equal(h:bootstrap(),true);equal(h.executedRelease,"4.2.0")
        for _,source in ipairs(h.compiledSources) do assert(#source<=2*1024*1024) end
        equal(h.files[CACHE],h.body)
    end)
    test("local update during HTTP sets newest release floor",function()
        local h=harness();h.files[MAIN]=build("4.2.0")
        h.game.HttpGet=function()
            h.downloads=h.downloads+1;h.files[MAIN]=build("4.3.0");return build("4.2.0")
        end
        equal(h:bootstrap(),true);equal(h.executedRelease,"4.3.0");equal(h.files[MAIN],build("4.3.0"))
    end)
    test("failed newer startup preserves valid installed release and cache",function()
        local h=harness();h.body=build("4.3.0");h.files[MAIN]=build("4.2.1");h.files[CACHE]=build("4.2.0")
        local main,cache=h.files[MAIN],h.files[CACHE];h.startupError=true
        equal(h:bootstrap(),false);equal(h.executions,1);equal(h.env[BOOT],nil)
        equal(h.files[MAIN],main);equal(h.files[CACHE],cache)
    end)
    for _,provider in ipairs({"queue_on_teleport","queueonteleport","syn.queue_on_teleport"}) do
        test("capability "..provider,function()
            local h=harness();local calls=0
            local fn=function(payload) calls=calls+1;assert(payload:find("automatic=true",1,true)) end
            if provider=="syn.queue_on_teleport" then h.env.syn={queue_on_teleport=fn} else h.env[provider]=fn end
            local api=h:controller();equal(api.status().queued,true);equal(api.status().provider,provider);equal(calls,1)
        end)
    end
    test("missing queue capability reports a limitation without errors",function()
        local h=harness();local s=h:controller().status()
        equal(s.supported,true);equal(s.queueAvailable,false);equal(s.queued,false);equal(s.attempts,0)
    end)
    test("distinct capability fallback succeeds and duplicate aliases are not retried",function()
        local h=harness();local failed,good=0,0
        local broken=function() failed=failed+1;error("unsupported") end
        h.env.queue_on_teleport=broken;h.env.queueonteleport=broken
        h.env.syn={queue_on_teleport=function() good=good+1 end}
        local api=h:controller();equal(api.status().queued,true);equal(failed,1);equal(good,1)
    end)
    test("failed queue receives one bounded teleport retry",function()
        local h=harness();local count=0
        h.env.queue_on_teleport=function() count=count+1;return false end
        local api=h:controller();equal(count,1)
        h.signal:fire("Enum.TeleportState.Failed");equal(count,1)
        h.signal:fire("Enum.TeleportState.Started");h.signal:fire("InProgress");h.signal:fire("Started")
        equal(count,2);equal(api.status().queued,false)
    end)
    test("late queue availability is detected once on teleport",function()
        local h=harness();local count=0;local api=h:controller()
        h.env.queue_on_teleport=function() count=count+1 end
        h.signal:fire("Started");equal(count,1);equal(api.status().queued,true)
    end)
    test("F8 disconnects pending callback and marks only current job unloaded",function()
        local h=harness();local count=0;local api=h:controller();api.unload()
        h.env.queue_on_teleport=function() count=count+1 end
        h.signal:fire("Started");equal(count,0);equal(h.signal.disconnected,1);equal(h.env[BOOT].state,"unloaded")
    end)
    test("reload preserves boot state and deduplicates queue; new job queues again",function()
        local h=harness();local count=0;h.env.queue_on_teleport=function() count=count+1 end
        local api=h:controller();api.unload(true);equal(h.env[BOOT].state,"loaded")
        local nextApi=h:controller();equal(count,1);equal(nextApi.status().queued,true)
        nextApi.unload(true);h.game.JobId="job-b";h:controller();equal(count,2)
    end)
    test("wrong game controller never queues or mutates boot state",function()
        local h=harness();h.game.GameId=1
        h.env.queue_on_teleport=function() error("must not queue") end
        local api=h:controller();equal(api.status().supported,false);equal(h.env[BOOT],nil);equal(h.env[QUEUE],nil)
    end)
    test("actual queued bootstrap loads once after rejoin and respects F8 afterward",function()
        local h=harness();local payload
        h.env.queue_on_teleport=function(source) payload=source end
        h:controller();assert(payload);h.game.JobId="job-b"
        local chunk,err=compile(payload,h.env);assert(chunk,err);chunk()
        equal(h.executions,1);equal(h.env[BOOT].jobId,"job-b")
        h.env[BOOT].state="unloaded";h.env.ChalkDB=nil;chunk();equal(h.executions,1)
    end)
    test("optional teleport signal failure does not stop main startup",function()
        local h=harness();h.player.OnTeleport={Connect=function() error("signal unavailable") end}
        local api=h:controller();equal(api.status().supported,true);equal(api.status().retryCallback,false)
    end)
    test("local loader stays offline and respects same-job unload",function()
        local h=harness();h.files[MAIN]=build("4.2.0")
        h:localLoader();equal(h.executions,1);equal(h.downloads,0)
        h.env.ChalkDB=nil;h.env[BOOT].state="unloaded";h:localLoader();equal(h.executions,1)
        h.game.JobId="job-b";h:localLoader();equal(h.executions,2);equal(h.downloads,0)
    end)
    test("local loader failure permits retry and wrong game does nothing",function()
        local h=harness();h:localLoader();equal(h.env[BOOT],nil);equal(h.executions,0)
        h.files[MAIN]=build("4.2.0");h:localLoader();equal(h.executions,1)
        local other=harness();other.game.GameId=1;other:localLoader()
        equal(other.downloads+other.reads+other.writes,0);equal(other.env[BOOT],nil)
    end)
    test("F8 during dependency wait cancels pending local startup",function()
        local h=harness();h.files[MAIN]=build("4.2.0");h.gameScripts.children.Moves=nil
        h.onWait=function()
            h.env.markExecuted();h:controller().unload();h.gameScripts.children.Moves=h.moves
        end
        h:localLoader();equal(h.executions,1);equal(h.reads,0);equal(h.env[BOOT].state,"unloaded")
    end)
    test("legacy higher-version cache cannot restore learning",function()
        local h=harness();h.httpError=true
        h.files[CACHE]="-- Chalk-Release: 99.0.0\nmarkExecuted()"
        h.files[MAIN]=build("98.0.0"):gsub("Chalk%-Product: deterministic","Chalk-Product: neural")
        equal(h:bootstrap(),false);equal(h.executions,0);equal(#h.compiledSources,0)
    end)
    test("legacy running app does not suppress deterministic replacement",function()
        local h=harness()
        h.env.ChalkDB={status=function() return {auto={},product="neural"} end}
        h.env.__ChalkAssistAutoBoot={gameId=h.game.GameId,placeId=h.game.PlaceId,jobId=h.game.JobId,state="loaded"}
        equal(h:bootstrap(),true);equal(h.executions,1)
    end)
    test("local loader rejects old product before compiling",function()
        local h=harness();h.files[MAIN]="-- Chalk-Release: 99.0.0\nmarkExecuted()"
        h:localLoader();equal(h.executions,0);equal(#h.compiledSources,0);equal(h.env[BOOT],nil)
    end)
    return result
end
