"""Offline assembly/startup checks; no executor, Roblox, or network is used."""
import importlib.util
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, '/private/tmp/chalk-replay-deps')
from lupa import LuaRuntime

spec = importlib.util.spec_from_file_location('chalk_builder', ROOT / 'build-chalk-script.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class DeterministicBuildTests(unittest.TestCase):
    def test_import_and_assembly_do_not_write_release_files(self):
        before = {p.name: p.read_bytes() for p in (ROOT / 'chalk-it-up-1v1.lua', ROOT / 'chalk-autoexec-public.lua') if p.exists()}
        artifacts = builder.assemble()
        self.assertEqual(set(artifacts), {'chalk-it-up-1v1.lua', 'chalk-autoexec-public.lua'})
        for name, data in before.items():
            self.assertEqual((ROOT / name).read_bytes(), data)
        self.assertEqual(artifacts, builder.assemble())

    def test_product_identity_is_separate_from_learning_client(self):
        source = builder.assemble()['chalk-it-up-1v1.lua']
        version = (ROOT / 'VERSION').read_text().strip()
        self.assertTrue(source.startswith(f'-- Chalk-Release: {version}\n-- Chalk-Product: deterministic\n'))
        self.assertIn('product="deterministic"', (ROOT / 'chalk-overlay-core.lua').read_text())
        for _, filename in builder.MODULES:
            module = (ROOT / filename).read_text()
            self.assertNotRegex(module, r'math\.random|Random\.new', filename)

    def test_only_explicit_rule_modules_are_bundled(self):
        names = [name for name, _ in builder.MODULES]
        self.assertEqual(names, ['Planner', 'createTackle', 'WRApproach', 'Motion', 'PlayerAvoidance',
            'createCarrierMoves', 'createAssist', 'AutoplayPolicy', 'createAutoplay', 'createWRRepeat',
            'createIdleGuard', 'FullplayPolicy', 'createFullplay', 'createMatchSkip',
            'createSessionContinuity', 'createAutoload'])
        self.assertNotRegex('\n'.join(path for _, path in builder.MODULES),
                            r'(rl-|skill-|performance-|generator|exploration|audit|results)')
        self.assertIn('},FullplayPolicy)', builder.INITIALIZE)

    def test_client_has_no_learning_transport_or_learning_api(self):
        source = builder.assemble()['chalk-it-up-1v1.lua']
        for forbidden in ('createLearning', 'createNeural', 'LearningSync', 'RLSync', 'startLearningAudit',
                          'setSharedLearning', 'setLearning', 'setPolicyMode', 'learningCandidates',
                          'learningActionExecuted', '/v3/rollouts', '/v4/rollouts', '/v5/rollouts',
                          '/v3/outcomes', '/v3/performance', 'ciu_rl_v', 'ciu_skill_'):
            self.assertNotIn(forbidden, source)
        # The embedded GitHub bootstrap is deliberately the only HTTP client.
        modules = '\n'.join((ROOT / path).read_text() for _, path in builder.MODULES)
        core = (ROOT / 'chalk-overlay-core.lua').read_text()
        self.assertNotRegex(modules + core, r'HttpGet|HttpPost|RequestAsync|http_request|syn\.request')
        self.assertNotRegex(modules + core, r'\brequest\s*\(\s*\{')

    def test_learning_ui_and_audits_are_removed_but_window_controls_remain(self):
        core = (ROOT / 'chalk-overlay-core.lua').read_text()
        for removed in ('LearningToggle', 'SharedLearningToggle', 'LearningStatus', 'PolicyMode',
                        'ResultsToggle', 'resultsPanel', 'auditMatch', 'auditRunId', 'ciu_match_audit',
                        'learningKey', 'SHARE PLAYS', 'POLICY: NEURAL'):
            self.assertNotIn(removed, core)
        for kept in ('RightShift', 'setWindowVisible', 'setMinimized', 'InputChanged',
                     'MatchSkipToggle', 'FullPlayToggle', 'AutoplayToggle', 'MatchAlertsToggle'):
            self.assertTrue(kept in core, "Missing retained control: " + kept)
        self.assertIn('local expandedHeight=480', core)
        self.assertIn('button("ASSIST OFF · V"', core)
        self.assertIn('button("AUTO LEAVE OFF"', core)

    def test_assembled_lua_compiles_without_executing_game_code(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_only = lua.eval('function(s) local fn,err=load(s,"deterministic-client"); return fn~=nil,err end')
        for name, source in builder.assemble().items():
            ok, error = compile_only(source)
            self.assertTrue(ok, f'{name}: {error}')

    def test_native_result_preserves_self_other_and_unknown_catcher(self):
        source = (ROOT / 'chalk-intercept-controller.lua').read_text()
        start = source.index('    function controller.onFx(data)')
        stop = source.index('    local touchedConnection=', start)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            controller={};events={};throwRole="WR"
            me={Character={Name="self",instance=true}}
            opponent={Name="other",instance=true}
            counters={intercepted=0,lostToInterception=0,incomplete=0,breakups=0,catches=0,opponentCatches=0}
            typeof=function(v)return type(v)=="table" and v.instance and "Instance" or type(v)end
            xyz=function()return nil end
            log=function(kind,data)data.kind=kind;events[#events+1]=data end
            saveFailure=function()end
            cancel=function()end
        ''')
        lua.execute(source[start:stop])
        lua.execute(r'''
            throwKey=1;controller.onFx({Type="BallResult",Result="Catch",Catcher=me.Character})
            assert(events[#events].caughtByMe==true)
            throwKey=2;controller.onFx({Type="BallResult",Result="Catch",Catcher=opponent})
            assert(events[#events].caughtByMe==false)
            throwKey=3;controller.onFx({Type="BallResult",Result="Catch"})
            assert(events[#events].caughtByMe==nil)
        ''')

    def test_coverage_reserve_unlock_requires_observed_live_ball(self):
        source = (ROOT / 'chalk-overlay-core.lua').read_text()
        start = source.index('function api.context()')
        stop = source.index('function api.syncFromGame()', start)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            api={}
            carrierContext=function()return nil,false,nil end
            characterOf=function()return nil end
            enemyCharacters=function()return {} end
            fullplay={movementBudget=function(airborne)
                return {dbReserve=airborne==true and 2 or 40}
            end}
        ''')
        lua.execute(source[start:stop])
        lua.execute(r'''
            phase="Live";arc=nil
            assert(api.context().playBudget.dbReserve==40)
            arc={P0={},P1={}}
            assert(api.context().playBudget.dbReserve==2)
            for _,value in ipairs({"PreSnap","Hike","RAC","Result","Lobby"}) do
                phase=value
                assert(api.context().playBudget.dbReserve==40)
            end
            fullplay=nil
            assert(api.context().playBudget==nil)
        ''')

    def test_autoplay_constructor_stays_off_with_saved_on_until_user_enables(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            requests,reads,writes={},{},{}
            now=100
            local function signal()
                local s={listeners={}}
                function s:Connect(fn)
                    self.listeners[#self.listeners+1]=fn
                    return {Disconnect=function()end}
                end
                function s:Fire(...)for _,fn in ipairs(self.listeners)do fn(...)end end
                return s
            end
            heartbeat=signal();queue={OnClientEvent=signal()}
            function queue:FireServer(command,mode)requests[#requests+1]={command,mode}end
            local player={PlayerGui={}}
            function player:GetAttribute()return true end
            function player:FindFirstChild()return nil end
            local http={}
            function http:JSONDecode()return {enabled=true,selectedMode="1v1"}end
            function http:JSONEncode(value)return tostring(value.enabled)..":"..value.selectedMode end
            local remotes={WaitForChild=function()return queue end}
            local config={Queue={Modes={"1v1"},Live={["1v1"]=true}}}
            local rs={Shared={Config=config},WaitForChild=function()return remotes end}
            local services={Players={LocalPlayer=player},ReplicatedStorage=rs,
                RunService={Heartbeat=heartbeat},HttpService=http}
            game={JobId="current",GetService=function(_,name)return services[name]end}
            workspace={GetServerTimeNow=function()return now end,GetAttribute=function()return false end}
            require=function(value)return value end
            readfile=function(path)reads[#reads+1]=path;return "saved-on" end
            writefile=function(path,value)writes[#writes+1]={path,value}end
            context={startDisabled=true,previousState={jobId="current",enabled=true,
                selectedMode="1v1",queueStatus="Searching",owned=true,pending="Join",cancelWanted=true},
                snapshot=function()return {alive=true,enabled=true,phase="Lobby"}end}
        ''')
        policy = lua.execute((ROOT / 'chalk-autoplay-policy.lua').read_text())
        constructor = lua.execute((ROOT / 'chalk-autoplay-controller.lua').read_text())
        lua.globals().subject = constructor(lua.globals().context, policy)
        lua.execute(r'''
            assert(not subject.status().enabled and not subject.status().owned)
            assert(subject.status().pending==nil and not subject.status().cancelWanted)
            assert(reads[1]=="ciu_deterministic_autoplay_v1.json")
            queue.OnClientEvent:Fire({Status="Idle"})
            now=102;heartbeat:Fire(.25);assert(#requests==0)
            assert(subject.setEnabled(true)==true)
            now=104;heartbeat:Fire(.25);assert(#requests==1 and requests[1][1]=="Join" and requests[1][2]=="1v1")
            subject.setEnabled(false)
            assert(#requests==2 and requests[2][1]=="Leave")
        ''')

    def test_enabled_previous_snapshot_cannot_enable_new_automation(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            alive,enabled=true,true
            RELEASE_VERSION="authored-release"
            previousState={enabled=true,auto={enabled=true},autoplay={enabled=true},
                wrRepeat={enabled=true},fullplay={enabled=true},matchSkip={enabled=true}}
            api={context=function()return {}end,setAutoplay=function()error("No startup queue request")end,
                initializeSessionContinuity=function()end}
            created={};idleStarts,idleStops=0,0
            local function feature(name,initial)
                local state={enabled=initial}
                local obj={status=function()return state end,setEnabled=function(value)state.enabled=value==true end,
                    releaseFullplay=function()end,navigate=function()end}
                created[name]=obj
                return obj
            end
            createAssist=function(ctx)
                assert(ctx.learningCandidates==nil and ctx.learningActionExecuted==nil)
                assert(ctx.version=="authored-release" and ctx.buildId=="CHALK_BUNDLED_BUILD_ID")
                return feature("assist",true)
            end
            createAutoplay=function(ctx)
                assert(ctx.startDisabled==true and ctx.previousState==nil)
                return feature("autoplay",false)
            end
            createWRRepeat=function(ctx)
                assert(ctx.previousState==nil)
                return feature("repeatWR",false)
            end
            createFullplay=function(ctx,policy,services)
                assert(ctx.previousState==nil and services==nil)
                assert(ctx.version=="authored-release" and ctx.buildId=="CHALK_BUNDLED_BUILD_ID")
                return feature("fullplay",true)
            end
            createMatchSkip=function(ctx)
                assert(ctx.startDisabled==true and ctx.previousState==nil)
                return feature("matchSkip",false)
            end
            createIdleGuard=function()
                idleStarts=idleStarts+1
                return {unload=function()idleStops=idleStops+1 end}
            end
            createAutoload=function(ctx)
                assert(ctx.bootstrapSource=="fixture")
                return {status=function()return {}end}
            end
        ''')
        lua.execute(builder.INITIALIZE.replace('BOOTSTRAP_SOURCE', '"fixture"'))
        lua.execute(r'''
            for _,feature in pairs(created)do assert(feature.status().enabled==false)end
            assert(idleStarts==0)
            api.updateIdleGuard();assert(idleStarts==0)
            assist.setEnabled(true);api.updateIdleGuard();assert(idleStarts==1)
            api.updateIdleGuard();assert(idleStarts==1)
            enabled=false;api.updateIdleGuard();assert(idleStops==1 and idleGuard==nil)
            enabled=true;assist.setEnabled(false);api.updateIdleGuard();assert(idleStarts==1)
            autoplay.setEnabled(true);api.updateIdleGuard();assert(idleStarts==2)
            alive=false;api.updateIdleGuard();assert(idleStops==2 and idleGuard==nil)
        ''')


if __name__ == '__main__':
    unittest.main()
