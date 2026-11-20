-- Mock-only checks: no real matchmaking, account lookup, or teleport requests.
return function(create)
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,body)
        report.total=report.total+1
        local ok,reason=pcall(body)
        report[ok and "passed" or "failed"]=report[ok and "passed" or "failed"]+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(reason) or nil}
    end
    local PLACE,GAME,FILE=116097127629859,10770281752,"ciu_deterministic_match_skip_v1.json"
    local function harness()
        local h={time=100,storage={},writes=0,reads=0,requests={},listeners={},playersByCharacter={}}
        local function signal()
            local s={listeners={}}
            function s:Connect(callback)
                local entry={callback=callback,connected=true}
                function entry:Disconnect() self.connected=false end
                self.listeners[#self.listeners+1]=entry
                h.listeners[#h.listeners+1]=entry
                return entry
            end
            function s:Fire(...)
                for _,entry in ipairs(self.listeners) do if entry.connected then entry.callback(...) end end
            end
            return s
        end
        h.heartbeat,h.failure=signal(),signal()
        h.player={Name="LocalAccount",UserId=100,Character={}}
        h.enemy={Name="stupieddaniel",DisplayName="OtherDisplay",UserId=200,Character={}}
        h.other={Name="SomebodyElse",DisplayName="stupieddaniel",UserId=300,Character={}}
        h.teammate={Name="stupieddaniel",UserId=400,Character={}}
        for _,p in ipairs({h.player,h.enemy,h.other,h.teammate}) do h.playersByCharacter[p.Character]=p end
        h.players={LocalPlayer=h.player}
        function h.players:GetPlayerFromCharacter(character)
            if h.resolveError then error(h.resolveError) end
            return h.playersByCharacter[character]
        end
        function h.players:GetPlayers() error("Must never scan lobby players") end
        h.teleport={TeleportInitFailed=h.failure}
        function h.teleport:Teleport(place,player)
            h.requests[#h.requests+1]={placeId=place,player=player,time=h.time}
            if h.onTeleport then h.onTeleport() end
            if h.teleportError then error(h.teleportError) end
        end
        h.http={}
        function h.http:JSONEncode(value)
            if h.encodeError then error(h.encodeError) end
            if value.version==1 then
                return string.format('{"version":%d,"enabled":%s,"username":"%s"}',value.version,tostring(value.enabled),value.username)
            end
            local names={}
            for _,name in ipairs(value.usernames or {}) do
                names[#names+1]=type(name)=="string" and ('"'..name..'"') or tostring(name)
            end
            return string.format('{"version":%d,"enabled":%s,"usernames":[%s]}',value.version,tostring(value.enabled),table.concat(names,","))
        end
        function h.http:JSONDecode(value)
            if value=="{}" then return {} end
            local version,on,name=string.match(value,'^{"version":(%d+),"enabled":(%a+),"username":"([^"]*)"}$')
            if version then
                assert(on=="true" or on=="false","Invalid JSON fixture")
                return {version=tonumber(version),enabled=on=="true",username=name}
            end
            local raw
            version,on,raw=string.match(value,'^{"version":(%d+),"enabled":(%a+),"usernames":(%b[])}$')
            assert(version and (on=="true" or on=="false"),"Invalid JSON fixture")
            local names={}
            for item in string.gmatch(string.sub(raw,2,-2),"[^,]+") do
                local text=string.match(item,'^"([^"]*)"$')
                if text~=nil then names[#names+1]=text
                elseif item=="true" or item=="false" then names[#names+1]=item=="true"
                else names[#names+1]=assert(tonumber(item),"Unsupported JSON fixture item") end
            end
            return {version=tonumber(version),enabled=on=="true",usernames=names}
        end
        h.snapshot={alive=true,enabled=true,testing=false,phase="Live",mode="1v1",role="DB",
            modeSource="match",matchIdentityVerified=true,opponent=h.enemy.Character,opponents={h.enemy.Character}}
        h.services={players=h.players,player=h.player,teleportService=h.teleport,runService={Heartbeat=h.heartbeat},
            http=h.http,now=function() return h.time end,gameId=GAME,placeId=PLACE,jobId="job-a",
            exists=function(path) if h.existsError then error(h.existsError) end;return h.storage[path]~=nil end,
            read=function(path)
                h.reads=h.reads+1
                if h.readError then error(h.readError) end
                assert(h.storage[path]~=nil,"file not found")
                return h.storage[path]
            end,
            write=function(path,value)
                h.writes=h.writes+1
                if h.writeError then error(h.writeError) end
                if not h.ignoreWrite then h.storage[path]=value end
            end}
        function h:load(previous,startDisabled,preferencesManaged)
            self.api=create({previousState=previous,startDisabled=startDisabled,preferencesManaged=preferencesManaged,snapshot=function()
                if self.snapshotError then error(self.snapshotError) end
                return self.snapshot
            end},self.services)
            return self.api
        end
        function h:step(seconds) self.time=self.time+(seconds or .25);self.heartbeat:Fire(seconds or .25) end
        function h:fail(player,place)
            self.failure:Fire(player or self.player,"Failure","mock teleport failed",place or PLACE)
        end
        function h:settings(on,name)
            local names=type(name)=="table" and name or (name=="" and {} or {name})
            self.storage[FILE]=self.http:JSONEncode({version=2,enabled=on,usernames=names})
        end
        function h:legacySettings(on,name)
            self.storage[FILE]=self.http:JSONEncode({version=1,enabled=on,username=name})
        end
        function h:reload(job)
            local previous=self.api.status()
            self.api.unload()
            if job then self.services.jobId=job end
            return self:load(previous)
        end
        function h:connected()
            local count=0
            for _,listener in ipairs(self.listeners) do if listener.connected then count=count+1 end end
            return count
        end
        return h
    end

    test("deterministic startup preserves names but ignores saved enabled and retry state",function()
        local h=harness();h:settings(true,{"stupieddaniel","AnotherAccount"})
        h:load({jobId="job-a",enabled=true,usernames={"stupieddaniel"},attempts=1,
            requestState="retry",nextRetryAt=99,requestedUsername="stupieddaniel"},true)
        assert(not h.api.status().enabled and #h.api.status().usernames==2)
        assert(h.api.status().requestState=="idle" and h.api.status().attempts==0)
        h:step(10);assert(#h.requests==0)
        assert(not h.http:JSONDecode(h.storage[FILE]).enabled)
        h.api.setEnabled(true);h:step();assert(#h.requests==1)
    end)
    test("deterministic first startup keeps default target disabled",function()
        local h=harness();h:load(nil,true);h:step(10)
        assert(not h.api.status().enabled and h.api.status().username=="stupieddaniel")
        assert(#h.requests==0)
    end)
    test("managed startup keeps saved ON intact until a single preference restoration",function()
        local h=harness();h:settings(true,{"stupieddaniel","AnotherAccount"})
        h:load(nil,true,true);h:step(.25)
        assert(not h.api.status().enabled and #h.requests==0 and h.writes==0)
        assert(h.http:JSONDecode(h.storage[FILE]).enabled)
        h.api.setEnabled(true);h:step(.25);assert(#h.requests==1)
        local previous=h.api.status();h.api.unload()
        h:load(previous,true,true);h.api.setEnabled(true);h:step(.25)
        assert(#h.requests==1 and h.api.status().attempts==1,"same-job pending rejoin must not duplicate")
        h.api.setEnabled(false);assert(not h.http:JSONDecode(h.storage[FILE]).enabled)
    end)
    test("managed missing preference defaults OFF and retains the username box",function()
        local h=harness();h:load(nil,true,true);h:step(.25)
        assert(not h.api.status().enabled and h.api.status().username=="stupieddaniel")
        assert(not h.http:JSONDecode(h.storage[FILE]).enabled and #h.requests==0)
    end)

    test("missing settings initialize enabled exact target and verify saved version",function()
        local h=harness();h:load()
        local s=h.api.status()
        assert(s.enabled and s.username=="stupieddaniel" and s.attempts==0 and s.saveError==nil)
        assert(s.jobId=="job-a" and s.placeId==PLACE and h.writes==1 and h.reads==1)
        local saved=h.http:JSONDecode(h.storage[FILE]);assert(saved.version==2 and saved.enabled)
        assert(#saved.usernames==1 and saved.usernames[1]=="stupieddaniel")
        assert(#h.requests==0,"load must wait for observation")
    end)
    test("saved disabled and blank settings survive reload without defaults",function()
        local h=harness();h:settings(false,"");h:load();h:step()
        local s=h.api.status();assert(not s.enabled and s.username=="" and #h.requests==0 and h.writes==0)
        h:reload("job-b");h:step();s=h.api.status()
        assert(not s.enabled and s.username=="" and s.attempts==0 and #h.requests==0)
    end)
    test("saved custom username is loaded without being replaced",function()
        local h=harness();h:settings(true,"Another_User");h:load();h:step()
        assert(h.api.status().username=="Another_User" and h.writes==0 and #h.requests==0)
    end)
    test("list input accepts separators optional at-signs and case-insensitive duplicates",function()
        local h=harness();h:load()
        assert(h.api.setUsernames("  @Alpha_One, @BetaTwo; Third_3\nALPHA_ONE\t@betatwo  "))
        local s=h.api.status()
        assert(s.username=="Alpha_One, BetaTwo, Third_3" and #s.usernames==3)
        assert(s.usernames[1]=="Alpha_One" and s.usernames[2]=="BetaTwo" and s.usernames[3]=="Third_3")
        local saved=h.http:JSONDecode(h.storage[FILE])
        assert(saved.version==2 and #saved.usernames==3 and saved.usernames[2]=="BetaTwo")
        assert(h.api.setUsername("@BetaTwo @Third_3"),"legacy setter must accept the same list syntax")
        assert(h.api.status().username=="BetaTwo, Third_3")
    end)
    test("second and third configured accounts each trigger exact actual-opponent matches",function()
        for _,name in ipairs({"BetaTwo","Third_3"}) do
            local h=harness();h.enemy.Name=name;h:load()
            assert(h.api.setUsernames("Alpha_One, BetaTwo, Third_3"));h:step()
            local s=h.api.status()
            assert(#h.requests==1 and s.matchedUsername==name and s.matchedUserId==h.enemy.UserId)
            assert(s.requestedUsername==string.lower(name))
        end
    end)
    test("multiple names never turn display names substrings lobby presence or teammates into matches",function()
        local names="Alpha_One, BetaTwo, Third_3"
        for _,name in ipairs({"BetaTwoExtra","PrefixThird_3","SomebodyElse"}) do
            local h=harness();h.other.Name=name;h.other.DisplayName="BetaTwo"
            h.snapshot.opponent=h.other.Character;h.snapshot.opponents={h.other.Character}
            h:load();h.api.setUsernames(names);h:step();assert(#h.requests==0,name)
        end
        local h=harness();h.enemy.Name="Third_3";h.snapshot.phase="Lobby"
        h:load();h.api.setUsernames(names);h:step();assert(#h.requests==0)
        h.snapshot.phase="Live";h.snapshot.opponent=nil;h.snapshot.opponents={};h:step()
        assert(#h.requests==0,"a configured account present elsewhere must remain ignored")
        h.snapshot.mode="Team";h.teammate.Name="BetaTwo";h.snapshot.opponent=h.teammate.Character
        h.snapshot.opponents={h.other.Character};h:step();assert(#h.requests==0)
    end)
    test("legacy v1 settings migrate to v2 without changing toggle username or blank choice",function()
        for _,on in ipairs({false,true}) do
            for _,name in ipairs({"Legacy_Name",""}) do
                local h=harness();h:legacySettings(on,name);h:load()
                local s=h.api.status();local saved=h.http:JSONDecode(h.storage[FILE])
                assert(s.enabled==on and s.username==name and s.saveError==nil)
                assert(saved.version==2 and saved.enabled==on and h.writes==1)
                assert(#saved.usernames==(name=="" and 0 or 1))
                if name~="" then assert(saved.usernames[1]==name) end
                local writes=h.writes;h:reload("job-b")
                assert(h.api.status().enabled==on and h.api.status().username==name and h.writes==writes)
            end
        end
    end)
    test("v2 list order and toggle persist across same and different job reloads",function()
        local h=harness();h:load();h.api.setUsernames("First_User, @Second_User; Third_User")
        h.api.setEnabled(false)
        for _,job in ipairs({"job-a","job-b"}) do
            h:reload(job);local s=h.api.status()
            assert(not s.enabled and s.username=="First_User, Second_User, Third_User")
            assert(#s.usernames==3 and s.usernames[3]=="Third_User")
            h:step();assert(#h.requests==0)
        end
    end)
    test("status returns a defensive copy of the configured usernames",function()
        local h=harness();h:load();h.api.setUsernames("First_User, stupieddaniel")
        local s=h.api.status();s.usernames[1]="Changed_User";s.usernames[2]=nil
        local actual=h.api.status()
        assert(actual.username=="First_User, stupieddaniel" and #actual.usernames==2)
        h:step();assert(#h.requests==1 and h.api.status().matchedUserId==200)
    end)
    test("invalid list rejects the entire draft without partial mutation or save",function()
        local h=harness();h:load();h.api.setUsernames("Keep_One, Keep_Two")
        local before=h.storage[FILE];local writes=h.writes
        for _,value in ipairs({"New_One, bad-name","New_One; ab","New_One @",
            "New_One, @@Other_Name","New_One abcdefghijklmnopqrstu",123,{"New_One"}}) do
            local ok,reason=h.api.setUsernames(value)
            assert(not ok and type(reason)=="string")
            assert(h.api.status().username=="Keep_One, Keep_Two" and h.writes==writes and h.storage[FILE]==before)
        end
        assert(not h.api.setUsernames(nil))
    end)
    test("empty separator-only input clears all names while retaining the enabled toggle",function()
        local h=harness();h:load();h.api.setUsernames("Another_User; stupieddaniel")
        assert(h.api.setUsernames(" , ; \n\t , "));h:step(30)
        local s=h.api.status();assert(s.enabled and #s.usernames==0 and s.username=="" and #h.requests==0)
        assert(#h.http:JSONDecode(h.storage[FILE]).usernames==0)
        h:reload("job-b");h:step();assert(h.api.status().enabled and #h.api.status().usernames==0 and #h.requests==0)
    end)
    test("invalid stored v2 list fails as a whole instead of loading its valid prefix",function()
        for _,names in ipairs({{"stupieddaniel","bad-name"},{"stupieddaniel",3},{"stupieddaniel",false}}) do
            local h=harness();h:settings(true,names);h:load();h:step()
            local s=h.api.status()
            assert(not s.enabled and #s.usernames==0 and s.saveError and #h.requests==0 and h.writes==0)
        end
    end)
    test("normalization trims optional at-sign and exact name ignores account case",function()
        local h=harness();h:load()
        assert(h.api.setUsername("  @StUpIeDdAnIeL  "))
        assert(h.api.status().username=="StUpIeDdAnIeL")
        h:step();assert(#h.requests==1 and h.requests[1].placeId==PLACE and h.requests[1].player==h.player)
        assert(h.api.status().matchedUserId==200 and h.api.status().requestedUsername=="stupieddaniel")
    end)
    test("blank disables matching without disabling its saved toggle",function()
        local h=harness();h:load();assert(h.api.setUsername("  "));h:step(30)
        local s=h.api.status();assert(s.enabled and s.username=="" and #h.requests==0)
        assert(type(s.message)=="string" and #s.message>0)
        h:reload();h:step();assert(h.api.status().username=="" and #h.requests==0)
    end)
    test("invalid drafts leave prior settings unchanged and unsaved",function()
        local h=harness();h:load();local writes=h.writes
        for _,value in ipairs({"ab","abcdefghijklmnopqrstu","validname bad-name","x-y","@@stupieddaniel","@ bad","na.me",123}) do
            local ok,reason=h.api.setUsername(value)
            assert(not ok and type(reason)=="string")
            assert(h.api.status().username=="stupieddaniel" and h.writes==writes)
        end
        assert(not h.api.setUsername(nil));assert(not h.api.setEnabled("true"))
        assert(h.api.setUsername("a_3"));assert(h.api.setUsername("abcdefghijklmnopqrst"))
    end)
    test("toggle off persists and prevents an otherwise exact match",function()
        local h=harness();h:load();assert(h.api.setEnabled(false));h:step(30)
        assert(#h.requests==0 and not h.api.status().enabled)
        h:reload();h:step();assert(#h.requests==0 and not h.api.status().enabled)
    end)
    test("active phase and role whitelist includes verified Team offense pick",function()
        for _,phase in ipairs({"Pick","PreSnap","Hike","Live","RAC","Run"}) do
            for _,role in ipairs({"WR","DB","QB"}) do
                local h=harness();h.snapshot.phase,h.snapshot.role=phase,role;h:load();h:step()
                assert(#h.requests==1,phase.."/"..role)
            end
        end
        local h=harness();h.snapshot.mode,h.snapshot.role,h.snapshot.phase="Team","O","Pick";h:load();h:step()
        assert(#h.requests==1)
        local nonTeam=harness();nonTeam.snapshot.role="O";nonTeam:load();nonTeam:step();assert(#nonTeam.requests==0)
    end)
    test("lobby result waiting unknown phases and unrelated roles never act",function()
        for _,phase in ipairs({"Lobby","Result","Waiting","Searching","Found","Unknown"}) do
            local h=harness();h.snapshot.phase=phase;h:load();h:step(40);assert(#h.requests==0,phase)
        end
        for _,role in ipairs({"Spectator","None","RUSH","D"}) do
            local h=harness();h.snapshot.role=role;h:load();h:step();assert(#h.requests==0,role)
        end
        local h=harness();h.snapshot.role=nil;h:load();h:step();assert(#h.requests==0)
    end)
    test("wrong game place mode testing dead context or disabled master never act",function()
        local h=harness();h.services.gameId=1;h:load();h:step();assert(#h.requests==0)
        h=harness();h.services.placeId=PLACE+1;h:load();h:step();assert(#h.requests==0)
        h=harness();h.snapshot.mode="Unknown";h:load();h:step();assert(#h.requests==0)
        for _,case in ipairs({{"testing",true},{"alive",false},{"enabled",false}}) do
            h=harness();h.snapshot[case[1]]=case[2];h:load();h:step();assert(#h.requests==0,case[1])
        end
    end)
    test("explicit fresh identity proof is mandatory and mode source can veto it",function()
        for _,proof in ipairs({false,"true",1}) do
            local h=harness();h.snapshot.matchIdentityVerified=proof;h:load();h:step();assert(#h.requests==0)
        end
        local h=harness();h.snapshot.matchIdentityVerified=nil;h:load();h:step();assert(#h.requests==0)
        for _,source in ipairs({"unconfirmed","lobby"}) do
            h=harness();h.snapshot.modeSource=source;h:load();h:step();assert(#h.requests==0)
        end
    end)
    test("DisplayName collision and substring account names never match",function()
        local h=harness();h.snapshot.opponent=h.other.Character;h.snapshot.opponents={h.other.Character}
        h:load();h:step();assert(#h.requests==0)
        h.other.Name="stupieddaniel2";h:step();assert(#h.requests==0)
        h.other.Name="xstupieddaniel";h:step();assert(#h.requests==0)
    end)
    test("nil unknown enemy and lobby bystanders are not searched",function()
        local h=harness();h.snapshot.opponent=nil;h.snapshot.opponents={};h:load();h:step()
        assert(#h.requests==0,"known Players elsewhere must not be considered")
        h.snapshot.opponent={Name="stupieddaniel"};h:step();assert(#h.requests==0)
        h.resolveError="character no longer valid";h.snapshot.opponent=h.enemy.Character;h:step();assert(#h.requests==0)
    end)
    test("local player and stale teammate fallback never match",function()
        local h=harness();h.player.Name="stupieddaniel";h.snapshot.opponent=h.player.Character
        h.snapshot.opponents={h.player.Character};h:load();h:step();assert(#h.requests==0)
        h=harness();h.snapshot.mode="Team"
        h.snapshot.opponent=h.teammate.Character;h.snapshot.opponents={h.other.Character};h:load();h:step()
        assert(#h.requests==0)
    end)
    test("native enemy identity does not depend on unrelated Roblox Team membership",function()
        local h=harness();h.player.Team={};h.enemy.Team=h.player.Team
        h.snapshot.mode="Team";h:load();h:step();assert(#h.requests==1)
    end)
    test("stale character mapping cannot authorize a departed character",function()
        local h=harness();h.enemy.Character={};h:load();h:step();assert(#h.requests==0)
    end)
    test("Team checks only enemy roster and never cached single opponent",function()
        local h=harness();h.snapshot.mode="Team";h.snapshot.opponents={h.other.Character};h:load();h:step()
        assert(#h.requests==0,"cached target must not override enemy roster")
        h.snapshot.opponents={};h:step();assert(#h.requests==0)
        h.snapshot.opponents=nil;h:step();assert(#h.requests==0)
        h.snapshot.opponents={h.other.Character,h.enemy.Character};h:step();assert(#h.requests==1)
    end)
    test("pending request never repeats and silence becomes blocked after twenty seconds",function()
        local h=harness();h:load();h:step()
        for i=1,39 do h:step(.5) end
        assert(#h.requests==1 and h.api.status().pending)
        h:step(.5);local s=h.api.status()
        assert(not s.pending and s.requestState=="blocked" and string.find(s.message,"timed out",1,true))
        h:step(120);h:fail();h:step(20);assert(#h.requests==1)
        h.api.setEnabled(false);h.api.setEnabled(true);h.api.setUsername("stupieddaniel");h:step(50)
        assert(#h.requests==1,"settings cannot reset dedupe")
    end)
    test("same-job reload keeps pending request original deadline and dedupe",function()
        local h=harness();h:load();h:step();local pendingAt=h.api.status().pendingSince
        h:step(8);h:reload();h:step(11.75)
        assert(#h.requests==1 and h.api.status().pending and h.api.status().pendingSince==pendingAt)
        h:step(.25);assert(h.api.status().requestState=="blocked" and #h.requests==1)
        h:reload();h:step(50);assert(#h.requests==1 and h.api.status().attempts==1)
    end)
    test("different-job reload restores settings but no request ownership",function()
        local h=harness();h:load();h:step();h:reload("job-b")
        local s=h.api.status();assert(s.enabled and s.username=="stupieddaniel" and s.attempts==0 and not s.pending)
        h:step();assert(#h.requests==2 and h.api.status().jobId=="job-b")
    end)
    test("different-job stale runtime settings cannot replace current disk preferences",function()
        local h=harness();h:load();h.api.setUsername("Another_User")
        local old=h.api.status();h.api.unload();h.services.jobId="job-b"
        h:settings(false,"");h:load(old)
        assert(not h.api.status().enabled and h.api.status().username=="")
        h.api.unload();h.storage[FILE]="broken";h:load(old)
        assert(not h.api.status().enabled and h.api.status().username=="" and h.api.status().saveError)
    end)
    test("failure signal filters foreign player place and unowned failures",function()
        local h=harness();h:load();h:fail();assert(h.api.status().requestState=="idle")
        h:step();h:fail(h.other,PLACE);h:fail(h.player,PLACE+1)
        assert(h.api.status().pending and h.api.status().nextRetryAt==nil)
        h:fail();local retryAt=h.api.status().nextRetryAt
        h:step(1);h:fail();assert(h.api.status().nextRetryAt==retryAt and #h.requests==1)
    end)
    test("verified failures retry at five then ten seconds and stop at three attempts",function()
        local h=harness();h:load();h:step();h:fail();h:step(4.75);assert(#h.requests==1)
        h:step(.25);assert(#h.requests==2 and h.api.status().pending)
        h:fail();h:step(9.75);assert(#h.requests==2)
        h:step(.25);assert(#h.requests==3)
        h:fail();h:step(100);assert(#h.requests==3 and h.api.status().requestState=="blocked")
        assert(h.api.status().attempts==3 and string.find(h.api.status().message,"3 attempts",1,true))
        h:reload();h:step(100);assert(#h.requests==3)
    end)
    test("pcall teleport failures use the same bounded retry schedule",function()
        local h=harness();h.teleportError="mock exception";h:load();h:step()
        assert(h.api.status().requestState=="retry" and string.find(h.api.status().error,"mock exception",1,true))
        h:step(5);h:step(10);h:step(50)
        assert(#h.requests==3 and h.api.status().requestState=="blocked")
    end)
    test("synchronous failure signal and thrown error cannot schedule twice",function()
        local h=harness();h.teleportError="mock throw";h.onTeleport=function() h:fail() end
        h:load();h:step();assert(h.api.status().attempts==1 and h.api.status().nextRetryAt==h.time+5)
        h:step(5);assert(#h.requests==2 and h.api.status().nextRetryAt==h.time+10)
    end)
    test("same-job reload retains retry time count and last failure",function()
        local h=harness();h:load();h:step();h:fail();local nextAt=h.api.status().nextRetryAt
        h:step(2);h:reload();assert(h.api.status().nextRetryAt==nextAt and h.api.status().attempts==1)
        assert(h.api.status().error~=nil);h:step(2.75);assert(#h.requests==1)
        h:step(.25);assert(#h.requests==2)
    end)
    test("retry revalidates active phase identity account settings and master",function()
        for _,change in ipairs({
            function(h) h.snapshot.phase="Result" end,
            function(h) h.snapshot.matchIdentityVerified=false end,
            function(h) h.snapshot.opponents={h.other.Character};h.snapshot.opponent=h.other.Character end,
            function(h) h.snapshot.testing=true end,
            function(h) h.snapshot.enabled=false end,
            function(h) h.api.setUsername("Another_User") end,
            function(h) h.api.setUsername("") end,
        }) do
            local h=harness();h:load();h:step();h:fail();change(h);h:step(5);h:step(20)
            assert(#h.requests==1 and h.api.status().requestState=="blocked")
        end
    end)
    test("retry remains on its original account after list and enemy-roster reordering",function()
        local h=harness();h.other.Name="Another_User";h.snapshot.mode="Team"
        h.snapshot.opponents={h.enemy.Character,h.other.Character};h:load()
        h.api.setUsernames("stupieddaniel, Another_User");h:step();h:fail()
        assert(h.api.status().matchedUserId==h.enemy.UserId)
        h.api.setUsernames("Third_User; Another_User; @STUPIEDDANIEL")
        h.snapshot.opponents={h.other.Character,h.enemy.Character}
        h:step(5)
        local s=h.api.status()
        assert(#h.requests==2 and s.requestedUsername=="stupieddaniel" and s.matchedUserId==h.enemy.UserId)
        h:fail();h:reload();h:step(10)
        s=h.api.status()
        assert(#h.requests==3 and s.requestedUsername=="stupieddaniel" and s.matchedUserId==h.enemy.UserId)
    end)
    test("another configured enemy cannot inherit a retry when original opponent disappears",function()
        local h=harness();h.other.Name="Another_User";h.snapshot.mode="Team";h:load()
        h.api.setUsernames("stupieddaniel, Another_User");h:step();h:fail()
        h.snapshot.opponents={h.other.Character};h.snapshot.opponent=h.other.Character
        h:step(5);h:step(30)
        assert(#h.requests==1 and h.api.status().requestState=="blocked")
        assert(h.api.status().matchedUserId==h.enemy.UserId)
    end)
    test("removing only the requested target cancels retry despite other configured matches",function()
        for _,removeWhilePending in ipairs({false,true}) do
            local h=harness();h.other.Name="Another_User";h.snapshot.mode="Team";h:load()
            h.api.setUsernames("stupieddaniel, Another_User");h:step()
            if not removeWhilePending then h:fail() end
            h.api.setUsernames("Another_User, Third_User")
            h.snapshot.opponents={h.other.Character,h.enemy.Character}
            if removeWhilePending then
                assert(h.api.status().pending,"changing settings cannot cancel an in-flight teleport")
                h:fail()
            end
            h:step(20)
            assert(#h.requests==1 and h.api.status().requestState=="blocked")
            assert(h.api.status().requestedUsername=="stupieddaniel")
        end
    end)
    test("adding names while pending preserves original ownership and later retry",function()
        local h=harness();h.other.Name="Another_User";h.snapshot.mode="Team";h:load();h:step()
        h.api.setUsernames("Another_User, stupieddaniel, Third_User")
        h.snapshot.opponents={h.other.Character,h.enemy.Character}
        assert(h.api.status().pending and h.api.status().matchedUserId==h.enemy.UserId)
        h:fail();h:step(5)
        assert(#h.requests==2 and h.api.status().matchedUserId==h.enemy.UserId)
    end)
    test("same name on a different resolved account cannot inherit retry ownership",function()
        local h=harness();h:load();h:step();h:fail();h.enemy.UserId=999;h:step(5)
        assert(#h.requests==1 and h.api.status().requestState=="blocked")
    end)
    test("off stops retries without pretending to cancel a pending teleport",function()
        local h=harness();h:load();h:step();h.api.setEnabled(false)
        assert(h.api.status().pending and not h.api.status().enabled)
        h:fail();h:step(10);assert(#h.requests==1 and h.api.status().requestState=="blocked")
        h=harness();h:load();h:step();h:fail();h.api.setEnabled(false);h.api.setEnabled(true);h:step(10)
        assert(#h.requests==1 and h.api.status().requestState=="blocked")
    end)
    test("editing suspends new work and retries until a valid draft is committed",function()
        local h=harness();h:load();h.api.setEditing(true);h:step(30)
        assert(#h.requests==0 and h.api.status().editing)
        assert(not h.api.setUsername("valid_name invalid-draft"));h:step(30);assert(#h.requests==0)
        assert(h.api.setUsername("@STUPIEDDANIEL"));h.api.setEditing(false);h:step();assert(#h.requests==1)
        h.api.setEditing(true);assert(h.api.status().pending,"focus cannot cancel an existing teleport")
        h:fail();h:step(10);assert(#h.requests==1 and h.api.status().requestState=="retry")
        h.api.setEditing(false);h:step();assert(#h.requests==2)
    end)
    test("setting changes during pending preserve ownership and cancel later retry",function()
        local h=harness();h:load();h:step();h.api.setUsername("Another_User")
        assert(h.api.status().pending and h.api.status().requestedUsername=="stupieddaniel")
        h:fail();h:step(5);assert(#h.requests==1 and h.api.status().requestState=="blocked")
    end)
    test("write failure remains visible while accepted runtime settings survive reload",function()
        local h=harness();h:load();h.writeError="disk full"
        local ok,reason=h.api.setUsername("Another_User")
        assert(ok and string.find(reason,"disk full",1,true))
        assert(h.api.status().username=="Another_User" and h.api.status().saveError~=nil)
        h:reload();assert(h.api.status().username=="Another_User" and h.api.status().saveError~=nil)
        local writes=h.writes;h:step(30);assert(h.writes==writes,"failed save must not heartbeat-loop")
        h.writeError=nil;h:reload();assert(h.api.status().saveError==nil)
        local saved=h.http:JSONDecode(h.storage[FILE]);assert(saved.version==2 and saved.usernames[1]=="Another_User")
    end)
    test("unsaved multi-name settings survive same-job reload and repair as a complete v2 list",function()
        local h=harness();h:load();h.writeError="disk full"
        assert(h.api.setUsernames("First_User, Second_User, Third_User"))
        h:reload();local s=h.api.status()
        assert(s.saveError and s.username=="First_User, Second_User, Third_User" and #s.usernames==3)
        h.writeError=nil;h:reload()
        local saved=h.http:JSONDecode(h.storage[FILE])
        assert(h.api.status().saveError==nil and saved.version==2 and #saved.usernames==3)
        assert(saved.usernames[1]=="First_User" and saved.usernames[3]=="Third_User")
    end)
    test("write readback mismatch is reported and retry can repair it",function()
        local h=harness();h:load();h.ignoreWrite=true
        assert(h.api.setEnabled(false));assert(h.api.status().saveError~=nil)
        assert(h.http:JSONDecode(h.storage[FILE]).enabled==true)
        h.ignoreWrite=false;h.api.setEnabled(false)
        assert(h.api.status().saveError==nil and not h.http:JSONDecode(h.storage[FILE]).enabled)
    end)
    test("corrupt or unreadable saved preferences never enable the initial target",function()
        for _,raw in ipairs({"broken","{}",'{"version":2,"enabled":true,"username":"stupieddaniel"}',
            '{"version":1,"enabled":true,"username":"bad name"}'}) do
            local h=harness();h.storage[FILE]=raw;h:load();h:step()
            local s=h.api.status();assert(not s.enabled and s.username=="" and s.saveError and #h.requests==0 and h.writes==0)
        end
        local h=harness();h:settings(true,"stupieddaniel");h.readError="permission denied";h:load();h:step()
        assert(not h.api.status().enabled and h.api.status().saveError and h.writes==0 and #h.requests==0)
    end)
    test("unavailable IO is visible and write-only saving follows available capability",function()
        local h=harness();h.services.write=false;h:load()
        assert(h.api.status().enabled and h.api.status().saveError~=nil)
        h=harness();h.services.read=false;h:load()
        assert(h.api.status().enabled and h.api.status().saveError==nil and h.writes==1)
        h=harness();h.services.read=false;h.services.exists=false;h:load();h:step()
        assert(not h.api.status().enabled and h.api.status().saveError~=nil and #h.requests==0)
    end)
    test("missing-file read fallback initializes defaults but arbitrary read error does not",function()
        local h=harness();h.services.exists=false;h:load();assert(h.api.status().enabled and h.writes==1)
        h=harness();h.services.exists=false;h.readError="permission denied";h:load();h:step()
        assert(not h.api.status().enabled and h.api.status().saveError~=nil and h.writes==0 and #h.requests==0)
    end)
    test("unload disconnects both listeners and stale callbacks cannot send",function()
        local h=harness();h:load();local heartbeat=h.heartbeat.listeners[1].callback;local failure=h.failure.listeners[1].callback
        assert(h:connected()==2);h.api.unload();h.api.unload();assert(h:connected()==0 and not h.api.status().alive)
        h:step(30);heartbeat(30);failure(h.player,"Failure","late",PLACE)
        assert(#h.requests==0 and not h.api.setUsername("Another_User") and not h.api.setEnabled(true))
        assert(not h.api.setEditing(true))
    end)
    test("unload during pending retry prevents stale work but replacement retains ownership",function()
        local h=harness();h:load();h:step();h:fail();local callback=h.failure.listeners[1].callback
        h:reload();assert(h:connected()==2)
        callback(h.player,"Failure","stale",PLACE);h:step(5);assert(#h.requests==2)
        h.api.unload();h:step(30);assert(#h.requests==2 and h:connected()==0)
    end)
    test("temporary snapshot failure is contained without issuing any request",function()
        local h=harness();h.snapshotError="not ready";h:load();h:step()
        assert(#h.requests==0 and string.find(h.api.status().error,"not ready",1,true))
        h.snapshotError=nil;h:step();assert(#h.requests==1)
    end)
    return report
end
