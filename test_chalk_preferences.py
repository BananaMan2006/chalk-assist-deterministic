"""Real local preference journal and extracted UI/lifecycle integration; no game/network."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, '/private/tmp/chalk-replay-deps')
from lupa import LuaRuntime


class PreferencesTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(r'''
            files={};tokens={};writes={};serial=0
            function copy(v) if type(v)~="table" then return v end
                local o={};for k,x in pairs(v)do o[k]=copy(x)end;return o end
            http={JSONEncode=function(_,v)serial=serial+1;local k="json-"..serial;tokens[k]=copy(v);return k end,
                JSONDecode=function(_,k)assert(tokens[k],"Invalid JSON");return copy(tokens[k])end}
            services={http=http,exists=function(path)return files[path]~=nil end,
                read=function(path)assert(files[path],"file not found");return files[path]end,
                write=function(path,body)
                    writes[#writes+1]={path=path,body=body}
                    if writeFailure then error("disk unavailable")end
                    files[path]=tornWrite and "broken" or body
                end}
            function saveOld(path,v)files[path]=http:JSONEncode(v)end
            function fresh(ctx)return create(ctx or {},services)end
        ''')
        lua.globals().create = lua.execute((ROOT / 'chalk-preferences.lua').read_text())
        return lua

    def test_fresh_defaults_and_all_values_survive_full_runtime_restart(self):
        lua = self.runtime()
        lua.execute(r'''
            p=fresh();local v=p.get();assert(v.master and v.matchAlerts)
            for _,k in ipairs({"assist","fullAuto","autoplay","wrRepeat","autoLeave"})do assert(v[k]==false)end
            assert(p.update({assist=true,fullAuto=true,autoplay=true,autoLeave=true,selectedMode="1v1",
                usernames="one, two",matchAlerts=false,ui={visible=false,minimized=true,x=38,y=92}}))
            p=nil;q=fresh();v=q.get();assert(v.master and v.assist and v.fullAuto and v.autoplay and v.autoLeave)
            assert(v.usernames=="one, two" and v.selectedMode=="1v1" and not v.matchAlerts)
            assert(not v.ui.visible and v.ui.minimized and v.ui.x==38 and v.ui.y==92)
            v.fullAuto=false;assert(q.get().fullAuto)
        ''')

    def test_interrupted_write_keeps_previous_complete_revision_and_reports_failure(self):
        lua = self.runtime()
        lua.execute(r'''
            p=fresh();assert(p.update({fullAuto=true,assist=true}))
            tornWrite=true;assert(not p.update({fullAuto=false}));assert(p.status().saveError)
            q=fresh();assert(q.get().fullAuto and q.status().recoveryWarning)
            tornWrite=false;assert(p.update({fullAuto=false}));q=fresh();assert(not q.get().fullAuto)
        ''')

    def test_explicit_failed_off_survives_same_job_reload_but_not_unrelated_snapshot(self):
        lua = self.runtime()
        lua.execute(r'''
            p=fresh();assert(p.update({autoplay=true}));writeFailure=true;p.update({autoplay=false})
            local prior={product="deterministic",preferences=p.status()}
            q=fresh({sameJob=true,previousState=prior});assert(q.get().autoplay==false and q.status().saveError)
            r=fresh({sameJob=false,previousState=prior});assert(r.get().autoplay==true)
            writeFailure=false;assert(q.update({autoplay=false}));assert(not fresh().get().autoplay)
        ''')

    def test_both_corrupt_slots_do_not_resurrect_legacy_on_or_write_defaults(self):
        lua = self.runtime()
        lua.execute(r'''
            files["ciu_deterministic_preferences_v1.a.json"]="bad"
            files["ciu_deterministic_preferences_v1.b.json"]="bad"
            saveOld("ciu_deterministic_autoplay_v1.json",{enabled=true,selectedMode="1v1"})
            p=fresh();assert(not p.get().autoplay and p.status().saveError and p.status().source=="invalid")
            assert(#writes==0)
            assert(p.update({autoplay=true}));assert(fresh().get().autoplay)
        ''')

    def test_legacy_current_choice_migration_is_product_scoped(self):
        lua = self.runtime()
        lua.execute(r'''
            saveOld("ciu_deterministic_autoplay_v1.json",{enabled=true,selectedMode="Ranked1v1"})
            saveOld("ciu_deterministic_match_skip_v1.json",{version=2,enabled=false,usernames={"authored_one"}})
            local prior={product="deterministic",enabled=true,auto={enabled=true},fullplay={enabled=true},
                autoplay={enabled=true},matchSkip={enabled=false},wrRepeat={enabled=false}}
            p=fresh({previousState=prior});local v=p.get()
            assert(v.assist and v.fullAuto and v.autoplay and not v.autoLeave)
            assert(v.usernames=="authored_one" and v.selectedMode=="Ranked1v1")
            assert(fresh().get().fullAuto)
        ''')

    def test_invalid_patch_and_equal_revision_conflict_fail_closed(self):
        lua = self.runtime()
        lua.execute(r'''
            p=fresh();local count=#writes
            for _,patch in ipairs({{autoplay=true,wrRepeat=true},{assist="yes"},{unknown=true},
                {ui={visible=true,minimized=false,x=0/0,y=0}}})do assert(not p.update(patch))end
            assert(#writes==count)
            local a={schemaVersion=1,revision=5,values=p.get()};local b=copy(a);b.values.assist=true
            saveOld("ciu_deterministic_preferences_v1.a.json",a)
            saveOld("ciu_deterministic_preferences_v1.b.json",b)
            q=fresh();assert(not q.get().assist and q.status().saveError)
        ''')

    def core(self):
        lua = self.runtime()
        lua.execute(r'''
            preferences=fresh();restoringPreferences=false;testing=false;alive=true;enabled=true
            api={};sessionContinuity=nil;previousState=nil;previousContext=nil;game={JobId="job"}
            function savePreferences(patch)if not restoringPreferences and not testing then return preferences.update(patch)end end
            function choice()end
            function hide()end
            toggle={};alertSettings={};savedUI={}
            updateFullplayUI=function()end;updateAutoplayUI=function()end;updateWRRepeatUI=function()end;updateAlertsUI=function()end
            function feature(initial)
                local s={enabled=initial,selectedMode="1v1",username="authored_one"};local n=0
                return {status=function()return s end,setEnabled=function(v,transient)s.enabled=v==true;n=n+1;return v==true end,
                    selectMode=function(v)if v=="removed" then return false,"Unavailable"end;s.selectedMode=v;return true end,
                    modes=function()return {{key="1v1",available=true}}end,
                    count=function()return n end,unload=function()s.enabled=false end,release=function()end}
            end
            assist=feature(false);autoplay=feature(false);repeatWR=feature(false);fullplay=feature(false);matchSkip=feature(false)
            fullplay.setEnabled=function(v)fullplay.status().enabled=v==true;return true end
            repeatWR.setEnabled=function(v)repeatWR.status().enabled=v==true;if v then api.setAutoplay(false)end;return v==true end
            api.setMatchSkip=function(v)matchSkip.status().enabled=v==true;savePreferences({autoLeave=v==true});return true end
            api.setMatchSkipUsernames=function(v)matchSkip.status().username=v;return true end
            api.setWindowVisible=function(v)savedUI.visible=v end;api.setMinimized=function(v)savedUI.minimized=v end
            placeWindow=function(x,y)savedUI.x=x;savedUI.y=y end
        ''')
        source = (ROOT / 'chalk-overlay-core.lua').read_text()
        lua.execute(source[source.index('function api.setEnabled(value)'):source.index('function api.status()')])
        lua.execute(source[source.index('function api.setAuto(value)'):source.index('function api.initializeSessionContinuity')])
        return lua

    def test_actual_restore_preserves_independent_saved_switches_without_rewriting(self):
        lua = self.core()
        lua.execute(r'''
            preferences.update({master=false,assist=false,fullAuto=true,autoplay=true,autoLeave=true,
                selectedMode="1v1",usernames="authored_one"})
            local count=#writes
            api.restorePreferences()
            assert(not enabled and not assist.status().enabled and fullplay.status().enabled)
            assert(autoplay.status().enabled and matchSkip.status().enabled)
            assert(#writes==count and preferences.get().master==false)
            assert(autoplay.count()==1)
            api.setFullplay(true);assert(enabled and assist.status().enabled)
            local v=preferences.get();assert(v.master and v.assist and v.fullAuto)
            api.setWRRepeat(true);v=preferences.get();assert(v.wrRepeat and not v.autoplay)
            api.setAutoplay(true);v=preferences.get();assert(v.autoplay and not v.wrRepeat)
        ''')

    def test_removed_mode_pauses_without_changing_saved_mode_or_on_choice(self):
        lua = self.core()
        lua.execute(r'''
            preferences.update({autoplay=true,selectedMode="removed",usernames="authored_one"})
            api.restorePreferences();assert(not autoplay.status().enabled)
            assert(preferences.get().autoplay and preferences.get().selectedMode=="removed")
            assert(preferences.status().restoreError)
        ''')

    def test_actual_unload_stops_runtime_without_erasing_preferences(self):
        lua = self.core()
        source = (ROOT / 'chalk-overlay-core.lua').read_text()
        lua.execute(source[source.index('function api.unload('):source.index('function api.setEnabled(value)')])
        lua.execute(r'''
            cancelDrag=function()end;connections={};folder={Destroy=function()end};gui=folder;env={ChalkDB=api};testToken=0
            preferences.update({assist=true,fullAuto=true,autoplay=true,selectedMode="1v1",usernames="authored_one"})
            api.restorePreferences();local count=#writes
            api.unload();assert(not alive and not autoplay.status().enabled and not assist.status().enabled)
            assert(#writes==count and preferences.get().autoplay and preferences.get().fullAuto)
            assert(fresh().get().autoplay)
        ''')

    def test_actual_session_adapter_only_adopts_ownership_for_matching_saved_choices(self):
        lua = self.core()
        source = (ROOT / 'chalk-overlay-core.lua').read_text()
        lua.execute(source[source.index('function api.initializeSessionContinuity'):source.index('function api.history()')])
        lua.execute(r'''
            launchOptions={};workspace={GetAttribute=function()return true end}
            preferences.update({assist=true,fullAuto=true,autoplay=true,selectedMode="1v1",usernames="authored_one"})
            api.restorePreferences();local n=autoplay.count();local w=#writes
            api.initializeSessionContinuity(function(ctx)sessionContext=ctx;return {}end)
            local ticket={fullAuto=true,selectedMode="1v1"}
            assert(sessionContext.canResume(ticket) and sessionContext.apply(true,"1v1"))
            assert(autoplay.count()==n and #writes==w) -- no second enable/queue request
            for _,patch in ipairs({{autoplay=false},{autoplay=true,master=false},
                {master=true,assist=false},{assist=true,fullAuto=false},
                {fullAuto=true,selectedMode="Ranked1v1"}})do
                preferences.update(patch);assert(not sessionContext.canResume(ticket))
            end
            preferences.update({selectedMode="1v1"});assert(sessionContext.canResume(ticket))
            sessionContext.stop();assert(preferences.get().autoplay and preferences.get().fullAuto)
        ''')


if __name__ == '__main__':
    unittest.main()
