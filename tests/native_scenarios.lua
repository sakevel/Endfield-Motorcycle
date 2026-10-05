local U=CS.UnityEngine
-- Handle assert return values
local bad,ctorError=pcall(function() U.Material(assert({borrowedGlow=true},'glow missing')) end)
assert(not bad and ctorError:find('invalid arguments to .ctor',1,true),'strict ctor rejects extra argument XLua error')
local ctrl={isPCPanel=true}
local ch=GameInstance.playerController.mainCharacter
local position=ch.rootCom.transform.position
local function settle() for i=1,21 do MOCK.run('Tick',.1) end end
local function row() return MOCK.interact.m_optionInfoMap['zml.motorcycle.mount'] end
local function empty() assert(not row() and MOCK.interact.m_optionInfoMap.foreign,'native foreign row preserved') end
assert(hg.loadedModules['ZML/Motorcycle'].env.Motorcycle==M)
assert(PUBLIC.get('motorcycle').summon_key==nil and PUBLIC.get('motorcycle').dismiss_key==nil,'old summon hotkeys absent from schema')
local routineNotices=#MOCK.notices
M.show(ctrl)
MOCK.press('F6');MOCK.press('F8');MOCK.press('F7')
assert(M.phase=='absent','removed hotkeys do not summon or board')
M.requestToggle();MOCK.run('Tick')
assert(M.phase=='deploying' and not row() and M.presentation.time==0,table.concat(MOCK.errors,';'))
MOCK.interactClosed=true
local helper=M.renderHelper
assert(helper.sampleMode and #helper.samples>0 and not helper.fallbackLoads)
for i,a in ipairs(M.effectAssets) do
    assert(a.assetName==M.effectNames[i] and helper.assets[M.effectNames[i]]==a,
        'sample the exact cached key registered for each owned effect')
end
assert(#M.glowObjects==#M.renderers,'one primary native shell draw per owned model part')
local shells=M.glowObjects
for i,shell in ipairs(shells) do
    local r=shell:GetComponent('MeshRenderer')
    assert(r.sharedMaterials.Length==1 and r.sharedMaterials[0]==helper.glow,'same animated native material, no unsampled template')
    assert(r.shadowCastingMode=='Off' and not r.receiveShadows,'temporary shell cannot cast shadows')
    assert(shell:GetComponent('MeshFilter').sharedMesh==M.renderers[i].gameObject:GetComponent('MeshFilter').sharedMesh,'reuse GPU-uploaded owned geometry')
    assert(shell.transform.parent==M.renderers[i].gameObject.transform.parent,'same articulated parent')
end
for i=1,6 do MOCK.run('Tick',.1) end
assert(M.presentation.checked and M.presentation.glow:GetFloat('_CutOffPosY')~=M.presentation.glowStart,'native controller actually advances shared primary material')
settle();assert(M.phase=='parked' and row().text=='骑乘摩托车')
assert(not M.glowObjects)
for _,shell in ipairs(shells) do assert(shell.destroyed and not shell.activeSelf and shell.transform.parent==nil,'disable/detach before native Reset, no reinit contamination') end
assert(helper.inited and not helper.releases and not helper.silentNoOps,'finish preserves initialized native controllers')
-- Reproduce the old name mismatch without changing any borrowed game asset.
local clone=U.Object.Instantiate(MOCK.borrowedEffects[1])
assert(clone.name:sub(-7)=='(Clone)' and clone.assetName==clone.name)
clone.data.useCutoffPosYAutoBounds=true
local probe=U.GameObject('ZML_Bike_Model')
local port=probe:AddComponent(typeof(CS.Beyond.Gameplay.View.EntityRenderHelper))
port:InitAll();port:SetSampleMode(true);port:AddTimelineEffect(clone)
port:SampleVFX(MOCK.borrowedEffects[1].name,true,0,false)
assert(port.fallbackLoads==1 and #port.samples==0,'old name silently falls back to unmodified asset')
port:SampleVFX(clone.assetName,true,0,false)
assert(#port.samples==1 and port.fallbackLoads==1,'registered cached key avoids fallback')
port:ResetAll();U.Object.Destroy(clone);U.Object.Destroy(probe)
local initialSamples=#helper.samples
assert(MOCK.interact.visibleOwn==row() and MOCK.interact.hintUpdated,'dirty native list flushes without a trigger transition')
assert(not M.bodyCollider.enabled,'summon overlap cannot trap the player')
local placed=M.vehicle
row().action();assert(M.phase=='mounted' and not row(),'no permanent dismount row')
MOCK.press('F7');assert(M.phase=='parked' and not M.lease)
MOCK.run('Tick');assert(row().text=='骑乘摩托车')
-- Move away: remove only our option. Recall reuses the same model at native root.
ch.rootCom.transform.position=position+U.Vector3(12,0,0)
MOCK.run('Tick');empty()
M.requestToggle();MOCK.run('Tick')
assert(M.vehicle==placed and M.phase=='deploying' and U.Vector3.Distance(placed.transform.position,ch.rootCom.transform.position)<.0001)
settle();assert(row())
assert(#helper.samples>initialSamples and M.renderHelper==helper and not helper.silentNoOps,'recall really samples the reused initialized helper')
local recallSamples=#helper.samples
M.requestToggle();MOCK.run('Tick');assert(M.phase=='retracting');empty()
assert(M.vehicle==placed and #helper.samples>0,'retract stays visible during native animation')
settle();assert(M.phase=='absent' and placed.destroyed);empty()
assert(#MOCK.notices==routineNotices,'native wheel summon/recall, interaction mount, dismount and retract are silent')
assert(#helper.samples>recallSamples and not helper.silentNoOps and helper.releases==1 and not helper.inited,
    'retract samples before final controller release')
for _,a in ipairs(MOCK.borrowedEffects) do
    assert(not a.data.useCutoffPosYAutoBounds,'borrowed asset never modified')
    if a.data.material then assert(a.data.material.borrowedGlow and a.data.material.FACTORY_ECS==1 and
        a.data.material.FACTORY_ECS_ON,'borrowed glow material never modified') end
end
-- Wheel selection during asynchronous clear-screen is consumed after HUD return.
M.hide(ctrl);M.requestToggle();assert(M.requestedToggle and not M.vehicle)
M.show(ctrl);MOCK.run('Tick');assert(M.presentation);M.finishPresentation();MOCK.run('Tick')
assert(row());local stale=row().action
MOCK.fight=true;MOCK.run('Tick');empty();stale();assert(not M.lease)
MOCK.fight=false;MOCK.run('Tick');assert(row())
-- Engine can clear native rows on scene change; a valid owner re-registers.
MOCK.interact.m_optionInfoMap['zml.motorcycle.mount']=nil
MOCK.run('Tick');assert(row())
MOCK.interactClosed=true;MOCK.run('Tick');assert(row() and MOCK.interactAutoOpens,'lazy native panel opens immediately')
-- Cancel expired requests
M.dismiss(true);M.requestToggle();U.Time.unscaledTime=U.Time.unscaledTime+4
MOCK.run('Tick');assert(not M.vehicle and not M.requestedToggle)
M.requestToggle();GameInstance.playerController.mainCharacter=MOCK.newCharacter()
MOCK.run('Tick');assert(not M.vehicle and not M.requestedToggle)
GameInstance.playerController.mainCharacter=ch
-- Exit/disable during presentation rolls back owned effects and native rows.
M.requestToggle();MOCK.run('Tick');assert(M.presentation)
M.hide(ctrl);assert(M.phase=='parked' and not M.presentation);empty()
M.show(ctrl);MOCK.run('Tick');assert(row())
assert(PUBLIC.set('motorcycle','enabled',false));assert(M.phase=='absent');empty()
assert(PUBLIC.set('motorcycle','enabled',true))
-- Check cached asset name
-- a key from the renamed Object.name or write the native private cache field.
M.close(ctrl);MOCK.cachedEffectNames=true;M.show(ctrl);M.summon()
assert(M.presentation and not M.renderHelper.fallbackLoads)
for i,a in ipairs(M.effectAssets) do
    assert(a.assetName=='cached_'..a.name and M.effectNames[i]==a.assetName)
end
settle();M.beginPresentation(true);assert(M.presentation)
local cachedHelper=M.renderHelper
settle();assert(M.phase=='absent' and not cachedHelper.fallbackLoads,'cached names work for deploy and retract')
M.close(ctrl);MOCK.cachedEffectNames=nil
-- Contract failure is reported, native resources still release and cycling works.
for _,flag in ipairs({'failEffectAsset','failEffectInit','failEffectSample','failEffectMaterial','missingNativeGlow','failGlowClone'}) do
    M.show(ctrl);MOCK[flag]=true;M.summon();assert(M.phase=='parked' and not M.presentation)
    MOCK[flag]=nil;M.close(ctrl)
    for _,r in ipairs(MOCK.resources) do assert(r.destroyed,'effect allocation cleanup '..flag) end
    assert(not M.glowObjects,'partial native shell cleanup '..flag)
end
M.show(ctrl);MOCK.shellCloneAttempts=0;MOCK.failGlowCloneAt=3
M.summon();assert(M.phase=='parked' and not M.presentation and not M.glowObjects)
for _,go in ipairs(MOCK.objects) do
    if go.name:find('ZML_Bike_FactoryShell_',1,true) then assert(go.destroyed,'partial shell allocation rollback') end
end
MOCK.failGlowCloneAt=nil;M.close(ctrl)
M.show(ctrl);MOCK.stalledNativeGlow=true;M.summon()
local beforeStall=#MOCK.errors
for i=1,6 do MOCK.run('Tick',.1) end
assert(M.presentation and #MOCK.errors==beforeStall+1 and MOCK.errors[#MOCK.errors]:find('factory_shell_curve_stalled',1,true),'CPU stalled curve diagnosed, not claimed rendered')
MOCK.stalledNativeGlow=nil;M.close(ctrl)
M.show(ctrl);M.summon();M.finishPresentation();MOCK.run('Tick');assert(row())
-- Recover an explicitly released owned helper without allocating duplicate assets.
local reinitHelper=M.renderHelper
local resources=#MOCK.resources
reinitHelper:ResetAll();assert(not reinitHelper.inited)
M.beginPresentation(false);assert(M.presentation and reinitHelper.inited and M.renderHelper==reinitHelper)
assert(#MOCK.resources==resources,'reinit reuses owned assets and glow clones')
M.finishPresentation();MOCK.run('Tick');assert(row())
for i=1,3 do
    local samples=#reinitHelper.samples
    M.beginPresentation(false);settle()
    assert(#reinitHelper.samples>samples and not reinitHelper.fallbackLoads and not reinitHelper.silentNoOps,'repeated deployment really samples')
end
MOCK.failInteractionRemove=true;M.hide(ctrl);assert(M.interactRemovalPending and MOCK.countUpdates()==1)
local errors=#MOCK.errors
MOCK.run('Tick');assert(#MOCK.errors==errors,'bounded pending cleanup diagnosis')
MOCK.failInteractionRemove=nil;MOCK.run('Tick');empty();assert(MOCK.countUpdates()==0)
M.close(ctrl)

-- Native wheel model: preserve all normal entries AND temporary slot 8.
local wheel={m_abilityDataList={},m_abilityDataMap={}}
for i=1,5 do local d={type=i,name='native'..i};wheel.m_abilityDataList[i]=d;wheel.m_abilityDataMap[i]=d end
local temporary={type=8,name='temporary'};wheel.m_abilityDataList[8]=temporary
W.register(wheel);assert(wheel.m_abilityDataList[6].type==W.id and wheel.m_abilityDataList[8]==temporary)
W.register(wheel);assert(wheel.m_abilityDataList[6].type==W.id and not wheel.m_abilityDataList[7],'no duplicates')
local refreshed={}
wheel.m_abilityCells={GetItem=function(_,index)return {index=index}end}
wheel._UpdateSelectorCellInfo=function(_,cell,index)assert(cell.index==index);refreshed[#refreshed+1]=index end
W.refresh(wheel);assert(#refreshed==1 and refreshed[1]==6,'opening refreshes only our slot, not all native tools')
assert(not W.select(1) and not M.requestedToggle,'native selection untouched')
assert(W.select(W.id) and M.requestedToggle);M.requestedToggle=nil
assert(PUBLIC.set('motorcycle','enabled',false));W.register(wheel);assert(not wheel.m_abilityDataList[6])
assert(PUBLIC.set('motorcycle','enabled',true));W.register(wheel)
wheel.m_abilityDataList[6]={type=6};wheel.m_abilityDataList[7]={type=7}
W.register(wheel);assert(not wheel.m_abilityDataMap[W.id] and wheel.m_abilityDataList[6].type==6 and wheel.m_abilityDataList[8]==temporary,'full wheel never overwrites native slots')
wheel.m_abilityDataList[6]=nil;W.register(wheel)
local function obj() return {activeSelf=true,SetActive=function(self,b)self.activeSelf=b end} end
local function widget()
    local v={gameObject=obj(),config={NORMAL_COLOR='native-white'},normalNodeCanvasGroup={}}
    for _,name in ipairs({'lockedNode','normalNode','cdNode','itemCountNode','icon'}) do v[name]={gameObject=obj()} end
    return {view=v,InitGeneralAbilityCell=function(_,kind)assert(kind==nil)end,
        _ClearCoroutine=function()return nil end,m_abilityRuntimeData={staleNative=true}}
end
U.Rect=function(x,y,w,h)return {x=x,y=y,w=w,h=h} end
U.Sprite={Create=function(tex,rect,pivot,ppu)
    assert(rect.w==tex.width and ppu==100 and pivot.x==.5)
    local s={ownedResource=true,Equals=function(self) return self.destroyed end}
    MOCK.resources[#MOCK.resources+1]=s;return s
end}
local cell={ability=widget(),shadowAbility=widget(),gameObject=obj(),button={},
    uiStateCtrl={SetState=function(self,s)self.state=s end},animationWrapper={PlayWithTween=function(self,s)self.animation=s end}}
assert(W.cell(wheel,cell,6) and cell.button.enabled and cell.ability.view.icon.sprite)
assert(cell.ability.m_abilityRuntimeData==nil and cell.shadowAbility.ignoreStateChangeEvent)
assert(not cell.ability.view.cdNode.gameObject.activeSelf and not cell.ability.view.itemCountNode.gameObject.activeSelf)
local icon=cell.ability.view.icon.sprite
W.release({});assert(not icon.destroyed,'stale owner close ignored')
W.release(wheel);assert(icon.destroyed)
M.close(ctrl);ch.rootCom.transform.position=position
assert(not M.requestedToggle and MOCK.countUpdates()==0);empty()
print('PASS: native wheel free-slot registration, no native enum/state writes, deferred summon/recall/retract, native interaction ownership and VFX lifecycle')
