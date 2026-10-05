-- Inserted in motorcycle.lua's lexical scope, main thread only.
local OPTION_SOURCE="zml.motorcycle.mount"
local EFFECT_ROOT="assets/beyond/dynamicassets/gameplay/effects/vfx/"
local EFFECT_NAMES={"P_factory_appear_cutoff","P_factory_appear_add",
    "P_factory_disappear_cutoff","P_factory_disappear_add"}
local NEAR_DISTANCE=3.5
-- Model dimensions: 0.83 x 1.286 x 2.2 meters.
local BODY_CENTER=V(.012,.74,0)
local BODY_HALF=V(.44,.54,1.12)
function M.createCollision()
    local go=newObject("ZML_Bike_Collision")
    local layer=CS.Beyond.Gameplay.LayerDef.WALKABLE_LAYER
    assert(type(layer)=="number" and layer>=0 and layer<32,"collision layer unavailable")
    go.layer=layer;go.transform:SetParent(M.visual.transform,false)
    local box=assert(go:AddComponent(typeof(U.BoxCollider)),"box collider unavailable")
    box.center=BODY_CENTER;box.size=BODY_HALF*2;box.isTrigger=false;box.enabled=false
    M.bodyCollider=box
    M.collisionHits=CS.System.Array.CreateInstance(typeof(U.RaycastHit),16)
    M.collisionOverlaps=CS.System.Array.CreateInstance(typeof(U.Collider),16)
    report("collision_volume_ready")
end
local function foreignCollider(collider,root)
    if not live(collider) then return false end
    local t=collider.transform
    return not t:IsChildOf(M.vehicle.transform) and not (root and t:IsChildOf(root))
end
function M.syncCollision()
    if not live(M.bodyCollider) then return end
    local _,_,_,root=character()
    local enable=M.owner~=nil and M.settings.enabled and M.phase=="parked" and not M.presentation
    -- Enable solid collision box once player steps clear
    if root and not M.collisionArmed then
        local p=M.visual.transform:InverseTransformPoint(root.transform.position)-BODY_CENTER
        local pad=.4/M.settings.scale
        if math.abs(p.x)<BODY_HALF.x+pad and math.abs(p.z)<BODY_HALF.z+pad and
            p.y>-BODY_HALF.y-1 and p.y<BODY_HALF.y+1 then enable=false
        elseif enable then M.collisionArmed=true end
    end
    M.bodyCollider.enabled=enable==true
end
local function volumeAt(lease,pos,rotation)
    local s=lease.ridingConfig.scale
    local offset=M.visual.transform.position-M.vehicle.transform.position
    return pos+offset+rotation*(BODY_CENTER*s),BODY_HALF*s
end
local function collisionMask()
    local mask=CS.Beyond.Gameplay.LayerDef.ALL_STATIC_SCENE_WITH_TERRAIN_LAYER_MASK
    assert(type(mask)=="number" and mask~=0,"static scene collision mask unavailable")
    return mask
end
-- Sweep vehicle box and capsule in flight
function M.sweepFlight(lease,pos,delta)
    local length=delta.magnitude
    if length<.000001 then return delta end
    local rotation=M.visual.transform.rotation
    local center,half=volumeAt(lease,pos,rotation)
    local direction=delta/length
    local count=U.Physics.BoxCastNonAlloc(center,half,direction,M.collisionHits,rotation,
        length+.02,collisionMask(),U.QueryTriggerInteraction.Ignore)
    assert(count<16,"vehicle flight sweep saturated")
    local reach,normal=length,nil
    for i=0,count-1 do
        local hit=M.collisionHits[i]
        if foreignCollider(hit.collider,lease.root.transform) and dot(hit.normal,direction)<-.02 and hit.distance-.02<reach then
            reach=math.max(0,hit.distance-.02);normal=hit.normal
        end
    end
    return direction*reach,normal
end
function M.collisionThrottle(lease,throttle,dt)
    if throttle==0 then lease.collisionBlocked=false;return 0 end
    local sign=throttle<0 and -1 or 1
    local direction=lease.motionDirection*sign
    local velocity=math.abs(lease.velocity or 0)
    local reach=.08+math.max(M.settings.speed,velocity)*dt*2+velocity*velocity/192
    local rotation=M.visual.transform.rotation
    local pos=lease.root.transform.position
    local center,half=volumeAt(lease,pos,rotation)
    local count=U.Physics.BoxCastNonAlloc(center,half,direction,M.collisionHits,rotation,
        reach,collisionMask(),U.QueryTriggerInteraction.Ignore)
    local blocked=count>=16
    for i=0,(blocked and 0 or count)-1 do
        local h=M.collisionHits[i]
        -- Exclude self visual and character hierarchy from obstacle sweep
        if foreignCollider(h.collider,lease.root.transform) and dot(h.normal,direction)<-.02 then blocked=true end
    end
    if not blocked then
        local angle=math.deg(reach*sign*lease.geometry.curvature)
        local nextRotation=Q.AngleAxis(angle,V(0,1,0))*rotation
        local nextCenter=volumeAt(lease,pos+direction*reach,nextRotation)
        count=U.Physics.OverlapBoxNonAlloc(nextCenter,half,M.collisionOverlaps,nextRotation,
            collisionMask(),U.QueryTriggerInteraction.Ignore)
        blocked=count>=16
        for i=0,(blocked and 0 or count)-1 do
            if foreignCollider(M.collisionOverlaps[i],lease.root.transform) then blocked=true end
        end
    end
    if blocked and not lease.collisionBlocked then report("collision_braked") end
    lease.collisionBlocked=blocked
    return blocked and 0 or throttle
end
function M.isNear()
    local _,_,_,root=character()
    return root and live(M.vehicle) and distance(root.transform.position,M.vehicle.transform.position)<=NEAR_DISTANCE
end
function M.wheelAvailable()
    local ok,c=pcall(config)
    return ok and c.enabled and not M.faulted
end
function M.requestToggle()
    -- Deferred summon after wheel closes
    if M.wheelAvailable() then
        M.requestedToggle={character=GameInstance.playerController.mainCharacter,deadline=U.Time.unscaledTime+3}
        report("wheel_requested")
    end
end
function M.removeInteraction()
    local ctrl=M.interactOwner
    M.interactOwner=nil
    if ctrl and ctrl.m_isClosed~=true then
        local ok,err=pcall(function()
            ctrl:RemoveInteractOption({type=CS.Beyond.Gameplay.Core.InteractOptionType.Interactive,
                sourceId=OPTION_SOURCE,subIndex=0})
        end)
        if not ok then
            M.interactOwner=ctrl
            if not M.interactRemovalPending then warnEvent("interact_remove_failed",err) end
            M.interactRemovalPending=true;return
        end
    end
    M.interactRemovalPending=nil
end
local function interactionWanted()
    local ch,pc,mover=character()
    return M.owner and M.settings and M.settings.enabled and not M.faulted and not M.presentation and
        M.phase=="parked" and ch and gameAllowed(pc) and
        groundAllowed(mover) and not typing() and M.isNear() and #M.pending==0
end
function M.syncInteraction()
    local open,ctrl=UIManager:IsOpen(PanelId.InteractOption)
    if M.interactOwner and (not open or ctrl~=M.interactOwner or not interactionWanted()) then
        M.removeInteraction()
    end
    if M.interactRemovalPending then return end
    if not interactionWanted() then return end
    -- Open interaction panel via UIManager
    if not open then ctrl=UIManager:AutoOpen(PanelId.InteractOption) end
    if not ctrl or ctrl.m_isClosed then return end
    local map=ctrl.m_optionInfoMap
    local exists=false
    for _,info in pairs(map or {}) do
        if info.identifier and info.identifier.sourceId==OPTION_SOURCE and info.identifier.subIndex==0 then
            exists=true;break
        end
    end
    if M.interactOwner==ctrl and exists then return end
    -- Register InteractOption row
    ctrl:AddInteractOption({type=CS.Beyond.Gameplay.Core.InteractOptionType.Interactive,
        sourceId=OPTION_SOURCE,subIndex=0,text="骑乘摩托车",
        icon="btn_common_exchange_icon",sortId=0,action=function()
            if not interactionWanted() then M.removeInteraction();return end
            M.mount();M.syncInteraction()
        end})
    M.interactOwner=ctrl
    -- Trigger native interact list update
    ctrl:_TryUpdateShowingList()
    ctrl:_UpdateBtnHint()
    report("interact_mount")
end
function M.stopEffects(release)
    -- Clean up temporary visual shell renderers
    for _,go in ipairs(M.glowObjects or {}) do
        pcall(function() go:SetActive(false);go.transform:SetParent(nil,false) end)
        pcall(U.Object.Destroy,go)
    end
    M.glowObjects=nil
    if M.renderHelper and live(M.renderHelper) then
        -- Full reset on destruction
        local ok,err=pcall(function()
            if release then M.renderHelper:ResetAll() else M.renderHelper:Reset() end
        end)
        if not ok then warnEvent("effect_reset_failed",err) end
    end
    M.presentation=nil
end
local function showFactoryShell()
    -- Apply native controller material to visual shell
    M.glowObjects={}
    for i,source in ipairs(M.renderers) do
        local materials=source.sharedMaterials
        local glow
        for j=0,materials.Length-1 do
            local mat=materials[j]
            if live(mat) and mat.shader.name=="HGRP/Factory/UnlitFactoryBuildingGrowing" then
                assert(not glow,"ambiguous native factory shell material")
                glow=mat
            end
        end
        assert(glow,"native factory controller did not attach shell material")
        if i==1 then
            M.presentation.glow=glow
            M.presentation.glowStart=glow:GetFloat("_CutOffPosY")
        end
        local go=assert(U.Object.Instantiate(M.renderTemplate),"factory shell clone unavailable")
        M.glowObjects[#M.glowObjects+1]=go
        go:SetActive(false);go.name="ZML_Bike_FactoryShell_"..i;go.layer=M.vehicle.layer
        local target=go.transform;local origin=source.gameObject.transform
        target:SetParent(origin.parent,false)
        target.localPosition=origin.localPosition;target.localRotation=origin.localRotation;target.localScale=origin.localScale
        go:GetComponent(typeof(U.MeshFilter)).sharedMesh=source.gameObject:GetComponent(typeof(U.MeshFilter)).sharedMesh
        local renderer=go:GetComponent(typeof(U.MeshRenderer))
        local primary=CS.System.Array.CreateInstance(typeof(U.Material),1);primary[0]=glow
        renderer.sharedMaterials=primary
        renderer.shadowCastingMode=CS.UnityEngine.Rendering.ShadowCastingMode.Off
        renderer.receiveShadows=false;renderer.enabled=true
        go:SetActive(true)
    end
    report("factory_shell_primary_ready")
end
local function effectHelper()
    if M.renderHelper and live(M.renderHelper) and M.renderHelper.inited then return M.renderHelper end
    if not M.effectAssets then
    local assets,names,seen={},{},{}
    for _,name in ipairs(EFFECT_NAMES) do
        local borrowed=assert(M.loader:LoadScriptableObject(EFFECT_ROOT..name:lower()..".asset"),"native factory VFX unavailable")
        local asset=own(U.Object.Instantiate(borrowed))
        -- Register VFX timeline effects using cached asset name
        asset.name=name
        local key=asset.assetName
        assert(type(key)=="string" and #key>0 and not seen[key],"factory VFX key unavailable/duplicate")
        seen[key]=true;names[#names+1]=key
        assert(asset.data and not asset.useECSRenderer,"factory VFX contract changed")
        -- Scale dissolve curves to vehicle bounds
        asset.data.useCutoffPosYAutoBounds=true
        if name:sub(-4)=="_add" then
            -- Configure non-ECS material parameters for MeshRenderer
            local source=assert(asset.data.material,"factory glow material unavailable")
            local mat=own(U.Material(source))
            mat.name="ZML_Bike_FactoryGlow"
            assert(mat:HasProperty("FACTORY_ECS"),"factory glow shader contract changed")
            mat:SetFloat("FACTORY_ECS",0);mat:DisableKeyword("FACTORY_ECS_ON")
            assert(not mat:IsKeywordEnabled("FACTORY_ECS_ON"),"factory glow ECS keyword still enabled")
            asset.data.material=mat
        end
        assets[#assets+1]=asset
    end
    M.effectAssets,M.effectNames=assets,names
    end
    if not M.renderHelper or not live(M.renderHelper) then
        M.renderHelper=M.visual:AddComponent(typeof(CS.Beyond.Gameplay.View.EntityRenderHelper))
    end
    local helper=assert(M.renderHelper,"native renderer helper unavailable")
    helper:InitAll();helper:SetSampleMode(true)
    assert(helper.inited,"native renderer helper did not initialize")
    for _,asset in ipairs(M.effectAssets) do helper:AddTimelineEffect(asset) end
    report("factory_effects_ready")
    return helper
end
function M.beginPresentation(removing)
    M.collisionArmed=nil
    M.removeInteraction();M.stopEffects()
    local ok,err=pcall(function()
        local helper=effectHelper()
        local keys=M.effectNames
        local names=removing and {keys[3],keys[4]} or {keys[1],keys[2]}
        M.presentation={removing=removing,time=0,names=names}
        M.phase=removing and "retracting" or "deploying"
        for _,name in ipairs(names) do helper:SampleVFX(name,true,0,false) end
        showFactoryShell()
    end)
    if not ok then
        M.stopEffects();warnEvent("factory_effect_failed",err)
        if removing then M.dismiss(true) else M.phase="parked" end
        -- Effect skipped on failure
        return
    end
    report(removing and "retract_started" or "deploy_started")
end
function M.finishPresentation()
    local p=M.presentation
    if not p then return end
    M.stopEffects()
    if p.removing then M.dismiss(true) else M.phase="parked" end
    report(p.removing and "retract_finished" or "deploy_finished")
end
function M.nativeUpdate(dt)
    if M.presentation then
        local p=M.presentation
        p.time=math.min(2,p.time+dt)
        for _,name in ipairs(p.names) do M.renderHelper:SampleVFX(name,true,p.time,false) end
        if not p.checked and p.time>=.5 then
            p.checked=true
            local ok,changed=pcall(function() return math.abs(p.glow:GetFloat("_CutOffPosY")-p.glowStart)>.001 end)
            if ok and changed then report("factory_shell_curve_advanced")
            else warnEvent("factory_shell_curve_stalled",ok and "native material cutoff did not advance" or changed) end
        end
        if p.time>=2 then M.finishPresentation() end
    end
    if M.requestedToggle and M.owner then
        local ch,pc,mover=character()
        if not ch or ch~=M.requestedToggle.character or U.Time.unscaledTime>M.requestedToggle.deadline or
            not M.settings or not M.settings.enabled or M.faulted or not U.Application.isFocused or typing() then
            M.requestedToggle=nil
        elseif gameAllowed(pc) then
            M.requestedToggle=nil
            if M.presentation or #M.pending>0 or not groundAllowed(mover) then
            elseif M.isNear() then
                M.unmount(true);M.beginPresentation(true)
            else
                M.summon()
            end
        end
    end
    M.syncCollision();M.syncInteraction()
end
