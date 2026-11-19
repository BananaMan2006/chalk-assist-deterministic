-- Executes the actual core Match handler and identity helpers with isolated
-- account/character fixtures. No Roblox service, teleport, or native action runs.
return function(coreSource)
    local function extract(pattern,label)
        return assert(coreSource:match(pattern),label.." source was not found")
    end
    local normalize=extract("(local function normalizeRole%(value%).-)\nif previousState then","normalizeRole")
    local characters=extract("(local function characterOf%(value%).-)\n%-%- MODE_POLICY_BEGIN","characterOf")
    local geometry=extract("(local function validGeo%(value%).-)\nlocal function selectBootstrapMode","validGeo")
    local enemies=extract("(local function enemyCharacters%(receiversOnly%).-)\nlocal function carrierContext","enemyCharacters/chooseTeamReceiver")
    local handler=extract("(local function onMatch%(data%).-)\nlocal function onFx","onMatch")
    local factory=assert(loadstring([[
        local deps=...
        local Players,me,typeof=deps.Players,deps.me,deps.typeof
        local workspace={GetServerTimeNow=function() return 100 end}
        local Vector3={zero=deps.offset}
        local function vector(v) return type(v)=='table' and v.isVector==true end
        local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
        local function clearMotion() end
        local function auditMatch() end
        local assist,repeatWR,fullplay
        local role,rawRole,phase,mode,modeSource=nil,nil,'Lobby',nil,'lobby'
        local opponent,carrier,teamGeo,localTeam,offense,currentLOS
        local roster={}
        local offset=Vector3.zero
        local route,arc,launchAt,snapAt,passType,preSnapEnds
        local passStarted=false
        local matchIdentityVerified=false
    ]]..normalize.."\n"..characters.."\n"..geometry.."\n"..enemies.."\n"..handler..[[
        return {onMatch=onMatch,snapshot=function()
            return {verified=matchIdentityVerified,mode=mode,modeSource=modeSource,
                role=role,phase=phase,opponent=characterOf(opponent),opponents=enemyCharacters(false),
                team=localTeam,roster=roster}
        end}
    ]]))
    local report={total=0,passed=0,failed=0,results={}}
    local function test(name,fn)
        report.total=report.total+1
        local ok,err=pcall(fn)
        report[ok and 'passed' or 'failed']=report[ok and 'passed' or 'failed']+1
        report.results[#report.results+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
    end
    local function instance(class,name)
        return {_class=class,Name=name,IsA=function(self,wanted) return self._class==wanted end}
    end
    local function harness()
        local h={offset={X=0,Y=0,Z=0,isVector=true},players={}}
        for i,name in ipairs({'LocalAccount','TargetAccount','TeammateAccount','PreviousAccount'}) do
            local p=instance('Player',name)
            p.UserId=i;p.DisplayName='SharedDisplayName';p.Character=instance('Model',name)
            h.players[i]=p
        end
        h.me,h.target,h.teammate,h.previous=table.unpack(h.players)
        local Players={}
        function Players:GetPlayerByUserId(id)
            for _,p in ipairs(h.players) do if p.UserId==id then return p end end
        end
        function Players:FindFirstChild(name)
            for _,p in ipairs(h.players) do if p.Name==name then return p end end
        end
        h.api=factory({Players=Players,me=h.me,offset=h.offset,typeof=function(value)
            return type(value)=='table' and value._class and 'Instance' or type(value)
        end})
        function h:send(data) self.api.onMatch(data);return self.api.snapshot() end
        function h:one(opponent)
            return self:send({Phase='PreSnap',Role='WR',Offset=self.offset,Opp=opponent or self.target.Character})
        end
        function h:teamRoster()
            return {{Char=self.me.Character,Team='A',Role='DB'},
                {Char=self.teammate.Character,Team='A',Role='WR'},
                {Char=self.previous.Character,Team='B',Role='WR'}}
        end
        function h:team(data)
            return self:send(data or {Phase='Pick',Mode='Team',Role='D',Team='A',Roster=self:teamRoster()})
        end
        return h
    end
    test('fresh native nil-mode 1v1 Opp establishes actual opponent proof',function()
        local h=harness();local s=h:one()
        assert(s.verified and s.mode==nil and s.modeSource=='match')
        assert(s.opponent==h.target.Character and #s.opponents==1 and s.opponents[1]==h.target.Character)
    end)
    test('Team to native 1v1 clears stale roster before selecting fresh Opp',function()
        local h=harness();assert(h:team().opponent==h.previous.Character)
        local s=h:send({Phase='PreSnap',Role='DB',Offset=h.offset,Opp=h.target.Character})
        assert(s.verified and s.mode==nil and s.team==nil and next(s.roster)==nil)
        assert(s.opponent==h.target.Character and #s.opponents==1 and s.opponents[1]==h.target.Character)
    end)
    test('new Pick or PreSnap cannot inherit prior opponent proof without fresh identity',function()
        for _,phase in ipairs({'Pick','PreSnap'}) do
            local h=harness();assert(h:one().verified)
            h:send({Phase='Result',Result='Incomplete'})
            local s=h:send({Phase=phase,Role='DB',Offset=h.offset})
            assert(not s.verified,'stale identity accepted for '..phase)
        end
    end)
    test('Lobby clears proof and opponent even when the packet includes old Opp',function()
        local h=harness();h:one()
        local s=h:send({Phase='Lobby',Opp=h.target.Character})
        assert(not s.verified and s.opponent==nil and #s.opponents==0 and s.role==nil)
    end)
    test('MatchOver invalidates proof despite included identity and stays invalid in Live',function()
        local h=harness();h:one()
        local s=h:send({Phase='Result',MatchOver=true,Opp=h.target.Character})
        assert(not s.verified)
        assert(not h:send({Phase='Live',Role='DB'}).verified)
    end)
    test('ordinary within-match Live keeps fresh identity until next round reset',function()
        local h=harness();h:one()
        local s=h:send({Phase='Live',Role='DB'})
        assert(s.verified and s.opponent==h.target.Character)
        assert(not h:send({Phase='PreSnap',Role='DB',Offset=h.offset}).verified)
        assert(h:one(h.previous.Character).verified)
    end)
    test('Team roster proves local membership and excludes self and teammates',function()
        local h=harness();local s=h:team()
        assert(s.verified and s.mode=='Team' and s.role=='DB')
        assert(#s.opponents==1 and s.opponents[1]==h.previous.Character)
        local entries=h:teamRoster();entries[2].Char=h.target.Character
        s=h:team({Phase='Pick',Mode='Team',Role='O',Team='A',Roster=entries})
        assert(s.verified and s.role=='O' and #s.opponents==1 and s.opponents[1]~=h.target.Character)
    end)
    test('Team roster missing local account or putting it on another team fails closed',function()
        for _,wrongTeam in ipairs({false,true}) do
            local h=harness();h:team();local entries=h:teamRoster()
            if wrongTeam then entries[1].Team='B' else table.remove(entries,1) end
            assert(not h:team({Phase='PreSnap',Mode='Team',Role='DB',Team='A',Roster=entries}).verified)
        end
    end)
    test('empty fresh Team roster revokes proof without reusing stale opponent as enemy',function()
        local h=harness();h:team()
        local s=h:team({Phase='Pick',Mode='Team',Role='DB',Team='A',Roster={}})
        assert(not s.verified and #s.opponents==0)
        -- The core retains this auxiliary receiver; consumers must use the roster list.
        assert(s.opponent==h.previous.Character)
    end)
    test('new Team round requires both fresh roster and Team rather than cached halves',function()
        for _,onlyRoster in ipairs({false,true}) do
            local h=harness();h:team()
            local packet={Phase='PreSnap',Mode='Team',Role='DB'}
            if onlyRoster then packet.Roster=h:teamRoster() else packet.Team='A' end
            assert(not h:send(packet).verified)
        end
    end)
    test('account and user-id references resolve but DisplayName and unknown references do not',function()
        for _,reference in ipairs({'TargetAccount',2}) do
            local h=harness();local s=h:one(reference)
            assert(s.verified and s.opponent==h.target.Character)
        end
        for _,reference in ipairs({'SharedDisplayName','UnknownAccount',999,{}}) do
            local h=harness();h:one();local s=h:one(reference)
            assert(not s.verified and #s.opponents==0)
        end
    end)
    test('fresh Team membership cannot revive a terminal match proof',function()
        local h=harness();h:team()
        local s=h:send({Phase='Result',Mode='Team',Team='A',Roster=h:teamRoster(),MatchOver=true})
        assert(not s.verified)
    end)
    test('changed local Team outside round setup cannot reinterpret cached teammate as verified enemy',function()
        local h=harness();local entries=h:teamRoster();entries[2].Char=h.target.Character
        assert(h:team({Phase='Pick',Mode='Team',Role='DB',Team='A',Roster=entries}).verified)
        local s=h:send({Phase='Live',Mode='Team',Team='B'})
        assert(not s.verified,'old Team A membership must not prove a new Team B opponent list')
    end)
    test('mode changes outside round setup require new opponent proof',function()
        local h=harness();assert(h:team().verified)
        local s=h:send({Phase='Live',Mode='1v1',Role='DB'})
        assert(not s.verified,'old Team receiver must not become a verified 1v1 opponent')
    end)
    test('fresh identity in the same changed-scope packet can establish proof again',function()
        local h=harness();h:team()
        local s=h:send({Phase='Live',Mode='1v1',Role='DB',Opp=h.target.Character})
        assert(s.verified and s.opponent==h.target.Character)
        h:team();local entries=h:teamRoster();entries[1].Team='B'
        s=h:send({Phase='Live',Mode='Team',Team='B',Roster=entries})
        assert(s.verified and #s.opponents==1 and s.opponents[1]==h.teammate.Character)
    end)
    return report
end
