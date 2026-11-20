-- Local deterministic preferences. Alternating verified slots retain the last
-- complete revision if a write is interrupted. No gameplay, services or network.
return function(ctx,services)
    ctx=ctx or {};services=services or {}
    local http=services.http or game:GetService("HttpService")
    local read=services.read or readfile
    local write=services.write or writefile
    local exists=services.exists or isfile
    local paths={"ciu_deterministic_preferences_v1.a.json","ciu_deterministic_preferences_v1.b.json"}
    local switches={master=true,assist=true,fullAuto=true,autoplay=true,wrRepeat=true,autoLeave=true,matchAlerts=true}
    local function copy(v)
        if type(v)~="table" then return v end
        local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
    end
    local function finite(v) return type(v)=="number" and v==v and math.abs(v)<100000 end
    local function defaults()
        return {master=true,assist=false,fullAuto=false,autoplay=false,wrRepeat=false,autoLeave=false,
            matchAlerts=true,ui={visible=true,minimized=false,x=110,y=110}}
    end
    local function valid(v)
        if type(v)~="table" then return false end
        for k in pairs(switches) do if type(v[k])~="boolean" then return false end end
        for k in pairs(v) do
            if not switches[k] and k~="ui" and k~="selectedMode" and k~="usernames" then return false end
        end
        if v.autoplay and v.wrRepeat then return false end
        if v.selectedMode~=nil and (type(v.selectedMode)~="string" or #v.selectedMode<1 or #v.selectedMode>64) then return false end
        if v.usernames~=nil and (type(v.usernames)~="string" or #v.usernames>4096) then return false end
        local u=v.ui
        if type(u)~="table" or type(u.visible)~="boolean" or type(u.minimized)~="boolean"
            or not finite(u.x) or not finite(u.y) then return false end
        for k in pairs(u) do if k~="visible" and k~="minimized" and k~="x" and k~="y" then return false end end
        return true
    end
    local function equal(a,b)
        if type(a)~=type(b) then return false end
        if type(a)~="table" then return a==b end
        for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
        for k in pairs(b) do if a[k]==nil then return false end end
        return true
    end
    local function decode(path)
        if type(exists)=="function" then
            local ok,present=pcall(exists,path)
            if not ok then return nil,false end
            if present==false then return nil,true end
        end
        if type(read)~="function" then return nil,false end
        local ok,raw=pcall(read,path)
        if not ok then
            local message=string.lower(tostring(raw))
            local missing=string.find(message,"no such file",1,true) or string.find(message,"not found",1,true)
                or string.find(message,"does not exist",1,true)
            return nil,missing~=nil
        end
        if type(raw)~="string" or #raw>32768 then return nil,false end
        local good,value=pcall(function() return http:JSONDecode(raw) end)
        return good and value or nil,false
    end
    local function record(v)
        return type(v)=="table" and v.schemaVersion==1 and type(v.revision)=="number"
            and v.revision>=1 and v.revision<1000000000 and v.revision==math.floor(v.revision) and valid(v.values)
    end
    local values,revision,slot=defaults(),0,nil
    local saveError,source,restoreError,recoveryWarning=nil,"fresh",nil,nil
    local pendingChoice=false
    local a,missingA=decode(paths[1]);local b,missingB=decode(paths[2])
    local va,vb=record(a),record(b)
    if va and vb and a.revision==b.revision and not equal(a.values,b.values) then
        saveError="Saved settings disagree; switches remain off";source="invalid"
    elseif va or vb then
        slot=va and (not vb or a.revision>=b.revision) and 1 or 2
        local saved=slot==1 and a or b
        values,revision,source=copy(saved.values),saved.revision,"saved"
        if (not va and not missingA) or (not vb and not missingB) then
            recoveryWarning="Recovered the last complete settings copy"
        end
    elseif not missingA or not missingB then
        saveError="Saved settings could not be read; switches remain off";source="invalid"
    else
        -- Migrate only this product's explicit settings. Missing files never
        -- invent an ON choice, and corrupt new journals never revive old ONs.
        local autoplay=decode("ciu_deterministic_autoplay_v1.json")
        if type(autoplay)=="table" then
            if type(autoplay.enabled)=="boolean" then values.autoplay=autoplay.enabled end
            if type(autoplay.selectedMode)=="string" and #autoplay.selectedMode>0 and #autoplay.selectedMode<=64 then
                values.selectedMode=autoplay.selectedMode
            end
        end
        local fullplay=decode("ciu_deterministic_fullplay_v1.json")
        if type(fullplay)=="table" and fullplay.schemaVersion==1 and fullplay.policyMode=="deterministic"
            and type(fullplay.lastRequestedEnabled)=="boolean" then values.fullAuto=fullplay.lastRequestedEnabled end
        local skip=decode("ciu_deterministic_match_skip_v1.json")
        if type(skip)=="table" and (skip.version==1 or skip.version==2) then
            if type(skip.enabled)=="boolean" then values.autoLeave=skip.enabled end
            if skip.version==1 and type(skip.username)=="string" then values.usernames=skip.username
            elseif skip.version==2 and type(skip.usernames)=="table" then
                local names={};for _,name in ipairs(skip.usernames) do
                    if type(name)~="string" then names=nil;break end;names[#names+1]=name
                end
                if names then values.usernames=table.concat(names,", ") end
            end
        end
        local alerts=decode("ciu_match_alert_settings.json")
        if type(alerts)=="table" and type(alerts.enabled)=="boolean" then values.matchAlerts=alerts.enabled end
        if values.fullAuto then values.master,values.assist=true,true
        elseif values.autoplay then values.master=true end
        local prior=ctx.previousState
        if type(prior)=="table" and prior.product=="deterministic" and prior.testing~=true then
            local map={assist="auto",fullAuto="fullplay",autoplay="autoplay",wrRepeat="wrRepeat",autoLeave="matchSkip",matchAlerts="matchAlerts"}
            if type(prior.enabled)=="boolean" then values.master=prior.enabled end
            for key,field in pairs(map) do
                if type(prior[field])=="table" and type(prior[field].enabled)=="boolean" then values[key]=prior[field].enabled end
            end
            if type(prior.ui)=="table" then
                for k in pairs(values.ui) do if type(prior.ui[k])==type(values.ui[k]) then values.ui[k]=prior.ui[k] end end
            end
        end
        if values.wrRepeat then values.autoplay=false end
        if not valid(values) then values=defaults();saveError="Previous settings were invalid; switches remain off" end
        source="migrated"
    end
    local api={}
    local function persist()
        if type(write)~="function" or type(read)~="function" then saveError="Settings cannot be saved on this executor";return false,saveError end
        local target=slot==1 and 2 or 1
        local nextRevision=revision+1
        local payload={schemaVersion=1,revision=nextRevision,values=copy(values)}
        local ok,err=pcall(function()
            write(paths[target],http:JSONEncode(payload))
            local actual=decode(paths[target])
            assert(record(actual) and actual.revision==nextRevision and equal(actual.values,values),"Settings readback did not match")
        end)
        if not ok then saveError="Settings were not saved: "..tostring(err);return false,saveError end
        slot,revision,saveError,source,recoveryWarning=target,nextRevision,nil,"saved",nil
        pendingChoice=false
        return true
    end
    function api.get() return copy(values) end
    function api.update(patch)
        if type(patch)~="table" then return false,"Invalid settings change" end
        local nextValues=copy(values)
        for k,v in pairs(patch) do nextValues[k]=copy(v) end
        if not valid(nextValues) then return false,"Invalid settings change" end
        if equal(values,nextValues) and not saveError and revision>0 then return true end
        values=nextValues
        pendingChoice=true
        return persist()
    end
    function api.setRestoreError(reason) restoreError=reason end
    function api.status()
        return {schemaVersion=1,revision=revision,source=source,saveError=saveError,restoreError=restoreError,
            recoveryWarning=recoveryWarning,pendingChoice=pendingChoice,values=copy(values)}
    end
    local prior=ctx.previousState
    if ctx.sameJob==true and type(prior)=="table" and prior.product=="deterministic"
        and type(prior.preferences)=="table" and type(prior.preferences.saveError)=="string"
        and prior.preferences.pendingChoice==true
        and valid(prior.preferences.values) then
        values=copy(prior.preferences.values);source="migrated";saveError=nil;pendingChoice=true
    end
    if source=="migrated" and not saveError then persist() end
    return api
end
