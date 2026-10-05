local function near(a,b) return math.abs(a-b)<0.0001 end
local function vecNear(a,b) return near(a.x,b.x) and near(a.y,b.y) and near(a.z,b.z) end
local function quatNear(a,b) return near(a.x,b.x) and near(a.y,b.y) and near(a.z,b.z) and near(a.w,b.w) end
local function state(ch)
    local s={}
    for name,b in pairs(ch.rig) do if name~='spine' then s[name]={position=b.localPosition,rotation=b.localRotation} end end
    s.spine={position=ch.rig.spine[0].localPosition,rotation=ch.rig.spine[0].localRotation}
    return s
end
local function restored(ch,s)
    assert(ch.animatorCom.animator.speed==0.7 and ch.characterAnimCom.grounderIK.enabled)
    assert(ch.movementComponent.handles[77]=='FOREIGN')
    for k in pairs(ch.movementComponent.handles) do assert(k==77,'no leaked owned speed handle') end
    for name,value in pairs(s) do
        local bone=name=='spine' and ch.rig.spine[0] or ch.rig[name]
        assert(vecNear(bone.localPosition,value.position),'restore local position '..name)
        assert(quatNear(bone.localRotation,value.rotation),'restore local rotation '..name)
    end
end
local ctrl={isPCPanel=true,isDefaultPanel=false,isControllerPanel=false}
local ch=MOCK.character
local original=state(ch)
assert(PUBLIC.mod('motorcycle').config_menu=='standard' and not PUBLIC.mod('motorcycle').has_entry)
assert(PUBLIC.get('motorcycle').render_comparison=='false','diagnostic default off after visibility acceptance')
assert(PUBLIC.set('motorcycle','render_comparison',true),'exercise optional four-way probes explicitly')
assert(PUBLIC.get('motorcycle').max_steer=='35','larger fork lock default')
for _,value in ipairs({9,51,35.5,'invalid'}) do
    assert(not PUBLIC.set('motorcycle','max_steer',value),'steering schema rejects invalid values')
end
assert(not PUBLIC.set('motorcycle','scale',2.1))
assert(not PUBLIC.set('motorcycle','speed',9.3))
M.show({isDefaultPanel=false});assert(MOCK.countUpdates()==0)
M.show(ctrl);assert(MOCK.countUpdates()==2 and M.phase=='absent')
M.show(ctrl);assert(MOCK.countUpdates()==2,'idempotent show')
local beforeNotice=#MOCK.notices
GameInstance.playerController.blockPlayerInput=true;MOCK.press('F6')
assert(M.phase=='absent' and #MOCK.notices==beforeNotice+1,'blocked custom hotkey is diagnosed, no silent no-op')
GameInstance.playerController.blockPlayerInput=false
ch.movementComponent.moveMode='Jumping';MOCK.press('F6')
assert(M.phase=='absent' and #MOCK.notices==beforeNotice+2,'ground gate diagnoses only an actual hotkey')
ch.movementComponent.moveMode='Grounded'
MOCK.press('F7');assert(M.phase=='absent' and not M.lease)
MOCK.failMaterial=true;MOCK.press('F6');assert(M.phase=='absent' and M.loader==nil and M.vehicle==nil)
assert(MOCK.errors[#MOCK.errors]:find('ZML Motorcycle: model_load_failed: ',1,true) and
    MOCK.errors[#MOCK.errors]:find('native shader template unavailable',1,true),'release logging retains own resource exception')
assert(MOCK.disposals==1);MOCK.failMaterial=nil
MOCK.press('F6');assert(M.phase=='parked' and M.vehicle and M.visual and M.loader)
assert(#MOCK.loads==3 and MOCK.cloneCount==24 and #M.parts==4 and #M.owned==18,'own meshes/textures/materials replace the old game mesh')
local palette=M.renderers[1].sharedMaterial.textures._BaseColorMap
assert(palette.width==8 and palette.height==1 and palette.name=='ZML_Bike_EndfieldPalette')
assert(near(palette.pixels[4].r,1) and near(palette.pixels[4].g,239/255) and palette.pixels[4].b==0,
    'exact Endfield yellow accent, no original red/green palette')
local paint=M.renderers[2].sharedMaterial.colors._BaseColor
assert(near(paint.r,247/255) and near(paint.g,247/255) and near(paint.b,242/255),'off-white body paint')
assert(#M.probeRoots==3 and #M.probeRenderers.custom_native==11)
assert(M.probeRenderers.native[1].gameObject.components.MeshFilter.sharedMesh.borrowedNative)
assert(M.probeRenderers.native[1].sharedMaterial.borrowedNative,'native/native control unchanged')
assert(M.probeRenderers.native_owned[1].gameObject.components.MeshFilter.sharedMesh.borrowedNative)
assert(M.probeRenderers.native_owned[1].sharedMaterial==M.renderers[1].sharedMaterial,'native/owned reuses exact owned material')
for i,r in ipairs(M.probeRenderers.custom_native) do
    assert(r.sharedMaterial.borrowedNative)
    assert(r.gameObject.components.MeshFilter.sharedMesh==M.renderers[i].gameObject.components.MeshFilter.sharedMesh,
        'custom/native must reuse exactly the same uploaded Mesh, not another decoder')
end
for _,go in ipairs(M.probeRoots) do assert(go.activeSelf) end
assert(PUBLIC.set('motorcycle','render_comparison',false))
for _,go in ipairs(M.probeRoots) do assert(not go.activeSelf,'comparison hot disables only owned controls') end
assert(M.phase=='parked' and M.vehicle)
assert(PUBLIC.set('motorcycle','render_comparison',true))
for _,go in ipairs(M.probeRoots) do assert(go.activeSelf) end
local meshes,triangles=0,0
for _,r in ipairs(MOCK.resources) do if r.triangles and not r.destroyed then meshes=meshes+1;triangles=triangles+r.triangles.Length/3 end end
assert(meshes==11 and triangles==23016,'full selected motorcycle decoded, not placeholder geometry')
for _,r in ipairs(MOCK.resources) do if r.triangles and not r.destroyed then assert(r.uploaded) end end
assert(#MOCK.buffers==2,'bounded first custom/native GPU descriptor queries only')
for _,b in ipairs(MOCK.buffers) do assert(b.disposed,'GPU wrapper released immediately') end
assert(M.visual.transform.localScale.x==1.15)
assert(vecNear(M.vehicle.transform.position,ch.position))
assert(not M.vehicle.components.Collider and not M.vehicle.components.Rigidbody)
assert(M.vehicle.layer==8 and M.vehicle.scene.handle==9,'owned mesh belongs to the actual world scene/render layer, not control/UI layer')
for _,renderer in ipairs(M.renderers) do
    assert(renderer.isVisible and renderer.enabled,'fixture world camera sees complete renderer')
    assert(renderer.sharedMaterial.passes.HGBuffer and not renderer.sharedMaterial.passes.DepthOnly)
    assert(renderer.sharedMaterial.floats._UseDeferredRendering==1,'native deferred settings preserved')
    assert(renderer.clonedNative and renderer.renderingLayerMask==1 and renderer.lightModeMask==4294967295)
    assert(renderer.gameObject.components.MeshFilter.sharedMesh.uv2~=nil,'native second UV attribute populated')
    assert(renderer.sharedMaterial.floats._RoughnessMax>renderer.sharedMaterial.floats._RoughnessMin)
end
MOCK.run('Tick');assert(M.visibilityFrames==nil,'visible camera check completed')
assert(M.driveProbed and not MOCK.navCalls,'read-only startup probe must not invoke navigation')
MOCK.press('F7');assert(M.phase=='mounted' and M.lease and ch.animatorCom.animator.speed==0.7)
local lease=M.lease
for _,go in ipairs(M.probeRoots) do assert(not go.activeSelf,'probes hidden while mounted') end
assert(lease.mover.handles[lease.handles[1]].speed==10)
MOCK.run('TailTick')
assert(near(M.visual.transform:InverseTransformPoint(ch.rig.pelvis.position).y,lease.pose.height/lease.ridingConfig.scale),'pelvis clearance follows the fitted seat surface')
assert(lease.pose.height>0.8*lease.ridingConfig.scale,'seat surface is not the pelvis bone')
assert(vecNear(ch.position,CS.UnityEngine.Vector3()),'pose does not mutate gameplay root position')
for _,side in ipairs({'left','right'}) do
    local chain=lease[side..'Leg']
    assert(near((chain.b.position-chain.a.position).magnitude,chain.l1))
    assert(near((chain.c.position-chain.b.position).magnitude,chain.l2))
end
local firstPose=ch.rig.leftCalf.localRotation
MOCK.run('TailTick');assert(quatNear(firstPose,ch.rig.leftCalf.localRotation),'pose does not accumulate')
ch.rootCom.transform.position=CS.UnityEngine.Vector3(3,1,8)
ch.rootCom.transform.rotation=CS.UnityEngine.Quaternion.Euler(0,45,0)
ch.movementComponent.speed=6
MOCK.run('TailTick');assert(vecNear(M.vehicle.transform.position,ch.position),'vehicle follows collision-resolved native position')
MOCK.keysHeld.LeftControl=true;MOCK.run('Tick')
assert(M.lease.braking and M.lease.mover.handles[M.lease.handles[1]].speed==0)
assert(PUBLIC.set('motorcycle','speed',12));assert(M.lease.mover.handles[M.lease.handles[1]].speed==0,'hot speed retains brake')
MOCK.keysHeld.LeftControl=nil;MOCK.run('Tick');assert(M.lease.speed==12)
assert(PUBLIC.set('motorcycle','scale',1.25))
MOCK.run('TailTick');assert(M.visual.transform.localScale.x==lease.ridingConfig.scale and lease.ridingConfig.scale==1.25)
assert(vecNear(ch.rig.pelvis.position,M.visual.transform:TransformPoint(CS.UnityEngine.Vector3(0,lease.pose.height/lease.ridingConfig.scale,lease.pose.z))))
MOCK.press('F7');assert(M.phase=='parked' and not M.lease);restored(ch,original)
-- No distant teleport to bike or player.
ch.rootCom.transform.position=CS.UnityEngine.Vector3(100,1,8);MOCK.press('F7');assert(not M.lease)
local playerPos=ch.position;MOCK.press('F6');assert(vecNear(ch.position,playerPos));assert(vecNear(M.vehicle.transform.position,playerPos))
MOCK.press('F7');assert(M.lease)
-- Death, battle, cutscene, jump and skill interruption all revert precisely.
for _,test in ipairs({'fight','cutscene','jump','skill','death','blocked','unfocused'}) do
    if not M.lease then MOCK.press('F7') end
    assert(M.lease)
    if test=='fight' then MOCK.fight=true
    elseif test=='cutscene' then ch.inCinematic=true
    elseif test=='jump' then ch.movementComponent.moveMode='Jumping'
    elseif test=='skill' then MOCK.skill=true
    elseif test=='death' then ch.alive=false
    elseif test=='blocked' then GameInstance.playerController.blockPlayerInput=true
    else CS.UnityEngine.Application.isFocused=false end
    MOCK.run('Tick');MOCK.run('TailTick');assert(not M.lease,test..' cancels riding');restored(ch,original)
    MOCK.fight=false;ch.inCinematic=false;ch.movementComponent.moveMode='Grounded';MOCK.skill=false;ch.alive=true
    GameInstance.playerController.blockPlayerInput=false;CS.UnityEngine.Application.isFocused=true
end
-- Switching to a different entity restores the former entity, never writes the new one.
MOCK.press('F7');local other=MOCK.newCharacter();local otherOriginal=state(other)
GameInstance.playerController.mainCharacter=other;MOCK.run('Tick');assert(not M.lease);restored(ch,original);restored(other,otherOriginal)
GameInstance.playerController.mainCharacter=ch
-- Typing consumes no custom hotkey; no summon while game input is blocked or focus is lost.
local selected={Equals=function()return false end,GetComponent=function(_,kind)return kind=='TMP_InputField' and {} or nil end}
CS.UnityEngine.EventSystems.EventSystem.current.currentSelectedGameObject=selected
MOCK.press('F8');assert(M.vehicle);MOCK.keysDown={}
CS.UnityEngine.EventSystems.EventSystem.current.currentSelectedGameObject=nil
M.hide(ctrl);assert(MOCK.countUpdates()==0 and M.phase=='parked');restored(ch,original)
for _,go in ipairs(M.probeRoots) do assert(not go.activeSelf,'probes hidden with HUD') end
-- Config modified from the menu while HUD is hidden is read again on show.
assert(PUBLIC.set('motorcycle','enabled',false));M.show(ctrl);assert(M.phase=='absent' and not M.vehicle)
assert(PUBLIC.set('motorcycle','enabled',true));MOCK.press('F6');MOCK.press('F7');assert(M.lease)
assert(PUBLIC.set('motorcycle','enabled',false));assert(not M.lease and M.phase=='absent');restored(ch,original)
assert(PUBLIC.set('motorcycle','enabled',true))
-- Incomplete skeleton validation happens before mutation, and errors latch instead of spamming every tick.
MOCK.press('F6');local saved=ch.rig.rightHand;ch.rig.rightHand=nil
MOCK.press('F7');assert(not M.lease and M.faulted);restored(ch,{})
local messages=#MOCK.notices;for _=1,5 do MOCK.run('Tick') end;assert(#MOCK.notices==messages)
ch.rig.rightHand=saved;M.show(ctrl);assert(not M.faulted);MOCK.press('F7');assert(M.lease)
-- Track failed removals until retry succeeds, even if the panel closes.
MOCK.failRemove=1;M.close(ctrl);assert(not M.lease and M.phase=='absent' and #M.pending==1)
MOCK.run('Tick');assert(#M.pending==0 and MOCK.countUpdates()==0);restored(ch,original)
-- Partial update registration and speed application fail closed and unsubscribe.
MOCK.failUpdate='TailTick';M.show(ctrl);assert(MOCK.countUpdates()==0 and M.unsub==nil)
MOCK.failUpdate=nil;M.show(ctrl);MOCK.press('F6');MOCK.failSpeed=true;MOCK.press('F7')
assert(not M.lease);restored(ch,original);MOCK.failSpeed=nil
M.close(ctrl);assert(MOCK.countUpdates()==0 and M.unsub==nil and M.loader==nil)
-- Desktop and controller panels are not default panels; all native variants work.
-- Closing an unrelated prefab, even after the owner hides, cannot destroy its vehicle.
for _,variant in ipairs({
    {isPCPanel=true,isDefaultPanel=false,isControllerPanel=false},
    {isPCPanel=false,isDefaultPanel=false,isControllerPanel=true},
    {isPCPanel=false,isDefaultPanel=true,isControllerPanel=false},
}) do
    M.show(variant);assert(MOCK.countUpdates()==2,'non-default native HUD initializes')
    MOCK.press('F6');assert(M.phase=='parked','native HUD hotkeys reach summon')
    M.close({isDefaultPanel=true});assert(M.vehicle and MOCK.countUpdates()==2)
    M.hide(variant);assert(MOCK.countUpdates()==0 and M.vehicle)
    M.close({isPCPanel=true});assert(M.vehicle,'unrelated hidden panel close ignored')
    M.close(variant);assert(M.phase=='absent' and not M.vehicle and not M.unsub)
end
local desktop={isPCPanel=true};local controller={isControllerPanel=true}
M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
M.show(controller);assert(M.owner==controller and not M.lease and MOCK.countUpdates()==2)
M.hide(desktop);M.close(desktop);assert(M.vehicle and MOCK.countUpdates()==2,'stale owner cannot remove live owner')
M.close(controller);assert(not M.vehicle and MOCK.countUpdates()==0);restored(ch,original)
-- Entity logical coordinates may not equal Unity's displayed world frame.
ch.logicalOffset=CS.UnityEngine.Vector3(5000,0,2000)
M.show(desktop);MOCK.press('F6')
assert(vecNear(M.vehicle.transform.position,ch.rootCom.transform.position),'render in Unity world, not logical map coordinates')
MOCK.press('F7');assert(M.lease,'mount distance uses the same world frame')
MOCK.run('TailTick');assert(vecNear(M.vehicle.transform.position,ch.rootCom.transform.position))
M.close(desktop);ch.logicalOffset=nil;restored(ch,original)
-- Descriptor diagnostics must not prevent rendering, and must release even on read failure.
for _,failure in ipairs({'failGpuQuery','failGpuRead'}) do
    M.show(desktop);MOCK[failure]=true;MOCK.press('F6')
    assert(M.phase=='parked' and M.vehicle,'optional GPU diagnostics fail softly')
    for _,b in ipairs(MOCK.buffers) do assert(b.disposed,'release wrapper even when descriptor throws') end
    MOCK[failure]=nil;M.close(desktop)
end
-- Partial allocations must release every owned mesh/texture/material and native handle.
for _,failure in ipairs({'failTexture','failMesh','failGpuUpload','emptyUpload','mismatchUpload','failPrefab','unsafePrefab','prefabChild','ambiguousPrefab','failClone','missingColorPass'}) do
    local beforeClones=MOCK.cloneCount or 0
    M.show(desktop);MOCK[failure]=true;MOCK.press('F6')
    assert(not M.vehicle and not M.loader and not M.owned)
    for _,r in ipairs(MOCK.resources) do assert(r.destroyed,'no leaked asset on '..failure) end
    if failure=='unsafePrefab' or failure=='prefabChild' or failure=='ambiguousPrefab' then
        assert(MOCK.cloneCount==beforeClones,'unsafe native branch rejected BEFORE Instantiate')
    end
    if MOCK.template then
        assert(not MOCK.template.destroyed and MOCK.template.components.MeshFilter.sharedMesh.borrowedNative)
        assert(MOCK.template.components.MeshRenderer.sharedMaterial.borrowedNative,'never modify borrowed material')
    end
    MOCK[failure]=nil;M.close(desktop)
end
assert(PUBLIC.set('motorcycle','scale',1.15)) -- No callback remains on closed objects.
-- Continuous body-size adaptation, multi-spine/finger ownership, travel-based
-- wheel angles (including reverse), pitch/bank response, exact restoration.
local U=CS.UnityEngine
local forwardAngles={}
for _,size in ipairs({.78,.93,1.12,1.24}) do
    local rider=MOCK.newCharacter()
    local function scaleBones(t)
        for _,node in ipairs(t._children) do node.localPosition=node.localPosition*size;scaleBones(node) end
    end
    scaleBones(rider.rootCom.transform)
    local tracked={}
    for _,side in ipairs({'left','right'}) do
        local hand=rider.rig[side..'Hand'];local sign=side=='left' and -1 or 1
        local parent=hand
        for i,name in ipairs({'Finger1','Finger11','Finger12','Finger1Nub'}) do
            local node=MOCK.transform(parent,U.Vector3(sign*.025*size,0,0));node.name='Bip001_'..(sign<0 and 'L_' or 'R_')..name
            tracked[#tracked+1]={node=node,position=node.localPosition,rotation=node.localRotation};parent=node
        end
    end
    local originals=state(rider);GameInstance.playerController.mainCharacter=rider
    M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease,'fitted size '..size)
    local l=M.lease
    forwardAngles[#forwardAngles+1]=l.neutral.angle
    assert(l.maxSteer>0 and l.maxSteer<=35,'reachable fork range without changing vehicle scale')
    assert(l.ridingConfig.scale==1.15 and M.visual.transform.localScale.x==1.15,'rider size never shrinks the bike')
    MOCK.run('TailTick');local stillAngle=l.rearAngle
    for _,side in ipairs({'left','right'}) do
        local chain=l[side..'Leg'];local t=M.visual.transform
        local knee=t:InverseTransformPoint(chain.b.position);local foot=t:InverseTransformPoint(chain.c.position)
        assert((math.abs(knee.x)-math.abs(foot.x))*1.15<.04,'knees stay tucked beside the tank')
    end
    rider.movementComponent.speed=8
    for _=1,5 do MOCK.run('TailTick') end
    assert(near(stillAngle,l.rearAngle),'requested speed alone must not rotate a blocked wheel')
    rider.rootCom.transform.position=rider.rootCom.transform.position+U.Vector3(0,0,.10)
    MOCK.run('TailTick',.02)
    assert(l.rearAngle>stillAngle and l.accel>0 and l.pitch<0,'forward acceleration lifts nose')
    for i=1,30 do
        local dt=i%2==0 and 1/30 or 1/120
        MOCK.setAxes(1,1);MOCK.run('Tick',dt);MOCK.nativeStep(dt,6);MOCK.run('TailTick',dt)
        for _,side in ipairs({'left','right'}) do for _,kind in ipairs({'Leg','Arm'}) do
            local chain=l[side..kind]
            assert(near((chain.a.position-chain.b.position).magnitude,chain.l1),'upper limb length unchanged')
            assert(near((chain.b.position-chain.c.position).magnitude,chain.l2),'lower limb length unchanged')
            assert((chain.c.position-l.targets[side..kind]).magnitude<.015,'real grip/peg reach')
        end end
    end
    assert(l.lean<0 and l.steer>0,'turning banks bike and steers fork')
    local angle=l.rearAngle
    rider.rootCom.transform.position=rider.rootCom.transform.position-l.motionDirection*.03
    MOCK.run('TailTick',.02)
    local change=(l.rearAngle-angle+180)%360-180
    assert(change<0,'backward travel reverses wheels')
    assert(M.visual.transform.localScale.x==1.15,'turn/reverse never resizes the motorcycle')
    local before=l.rearAngle
    rider.rootCom.transform.position=rider.rootCom.transform.position+U.Vector3(500,0,500)
    MOCK.run('TailTick');assert(near(before,l.rearAngle),'root discontinuity is not wheel travel')
    M.close(desktop);restored(rider,originals);MOCK.setAxes(0,0)
    for _,b in ipairs(tracked) do assert(quatNear(b.node.localRotation,b.rotation) and vecNear(b.node.localPosition,b.position),'restore every finger') end
end
assert(forwardAngles[1]>forwardAngles[#forwardAngles]+10,'small bodies lean forward instead of using a toy-sized bike')
GameInstance.playerController.mainCharacter=ch
-- Unrealistically large configured bikes fail before any bone/speed mutation;
-- the chosen vehicle size is never silently reduced, and changing it recovers.
M.show(desktop);MOCK.press('F6');assert(PUBLIC.set('motorcycle','scale',2))
MOCK.press('F7');assert(not M.lease and M.faulted and M.visual.transform.localScale.x==2)
restored(ch,original)
assert(PUBLIC.set('motorcycle','scale',1.15));MOCK.press('F7');assert(M.lease)
MOCK.run('TailTick');assert(PUBLIC.set('motorcycle','scale',2));MOCK.run('TailTick')
assert(not M.lease and M.faulted and M.visual.transform.localScale.x==2,'impossible hot settings restore instead of stretching or shrinking')
restored(ch,original);assert(PUBLIC.set('motorcycle','scale',1.15));M.close(desktop)
-- Independent contact check on the ACTUAL decoded tyre/rim vertices, rather
-- than trusting the production envelope's own groundGaps result.
local function meshGroundGaps()
    local out={}
    for _,part in ipairs(M.parts) do if part.role==1 or part.role==2 then
        local gap=math.huge
        for _,renderer in ipairs(M.renderers) do
            local t=renderer.gameObject.transform
            if t.parent==part.transform then
                local vs=renderer.gameObject.components.MeshFilter.sharedMesh.vertices
                for i=0,vs.Length-1 do
                    local p=t:TransformPoint(vs[i]);local slope=MOCK.groundSlope or U.Vector3()
                    gap=math.min(gap,p.y-(MOCK.groundY or 0)-p.x*slope.x-p.z*slope.z)
                end
            end
        end
        out[part.role]=gap
    end end
    return out
end
-- Vehicle-style control: fork first, collision-resolved travel turns the chassis.
local yawByRate={}
for _,hz in ipairs({30,120}) do
    local rider=MOCK.newCharacter();GameInstance.playerController.mainCharacter=rider
    local baseline=state(rider)
    MOCK.groundY=0;MOCK.groundSlope=nil
    M.show(desktop);MOCK.press('F6');assert((MOCK.groundQueries or 0)>0)
    assert(not M.rootGroundReported)
    MOCK.press('F7');assert(M.lease)
    local l=M.lease;MOCK.run('TailTick',1/hz)
    local yaw=l.bikeYaw;local wheel=l.rearAngle
    MOCK.setAxes(1,0)
    for _=1,hz do MOCK.run('Tick',1/hz);MOCK.nativeStep(1/hz,0);MOCK.run('TailTick',1/hz) end
    assert(l.steer>10 and near(l.bikeYaw,yaw) and near(l.rearAngle,wheel),'A/D while stopped only turns the fork')
    rider.rootCom.transform.rotation=U.Quaternion.Euler(0,90,0);MOCK.run('TailTick',1/hz)
    assert(near(l.bikeYaw,yaw),'native walk-facing must not rotate the motorcycle')
    MOCK.setAxes(1,1)
    for _=1,hz do
        MOCK.run('Tick',1/hz)
        local before=l.bikeYaw;local curvature=l.geometry.curvature
        local dir=MOCK.nativeStep(1/hz,4)
        MOCK.run('TailTick',1/hz)
        assert(math.abs(U.Mathf.DeltaAngle(before,l.bikeYaw)-math.deg(4/hz*curvature))<1e-7,'yaw equals signed distance times curvature')
        assert(dir.x==dir.x and dir.z==dir.z,'finite tangent')
    end
    assert(l.bikeYaw>yaw+10 and l.lean<0 and l.steer>0,'forward right steering turns and banks inward')
    assert(l.geometry.frontFactor>l.geometry.rearFactor,'front tyre has longer corner path')
    assert(l.pose.x>0 and l.pose.roll<0,'hips and torso shift inside')
    yawByRate[#yawByRate+1]=l.bikeYaw
    for _,gap in pairs(meshGroundGaps()) do assert(math.abs(gap)<1e-5,'actual tread contacts with inclined fork and bank') end
    local before=l.bikeYaw;wheel=l.rearAngle
    MOCK.wall=true
    for _=1,20 do MOCK.run('Tick',1/hz);MOCK.nativeStep(1/hz,4);MOCK.run('TailTick',1/hz) end
    assert(near(l.bikeYaw,before) and near(l.rearAngle,wheel),'wall stop cannot produce yaw or wheel spin')
    MOCK.wall=nil
    MOCK.setAxes(1,-1);MOCK.run('Tick',1/hz)
    assert(l.speed==3,'reverse capped at 3 m/s')
    before=l.bikeYaw;wheel=l.rearAngle
    for _=1,hz do MOCK.run('Tick',1/hz);MOCK.nativeStep(1/hz,-2);MOCK.run('TailTick',1/hz) end
    assert(U.Mathf.DeltaAngle(before,l.bikeYaw)<-5,'same steering reverses yaw when reversing')
    local beforeCommand=rider.movementComponent.input.navMoveVector
    -- Native manual input changes and ResetView do not erase persistent NavMove.
    for _=1,5 do
        rider.movementComponent.input:MoveMotion(U.Vector3(1,0,0))
        rider.movementComponent.input:ResetView()
        assert(vecNear(rider.movementComponent.input.moveVector,beforeCommand))
    end
    MOCK.keysHeld.LeftControl=true;MOCK.run('Tick',1/hz)
    assert(l.speed==0 and rider.movementComponent.input.moveVector.magnitude==0)
    MOCK.keysHeld.LeftControl=nil
    MOCK.setAxes(0,0);M.close(desktop);restored(rider,baseline)
end
assert(math.abs(yawByRate[1]-yawByRate[2])<2,'30/120 Hz curvature integration consistent')
print(string.format('Forward corner 30/120Hz: %.6f / %.6f deg',yawByRate[1],yawByRate[2]))
-- Independent circle/tangent check using a settled bar, not native root-facing.
for _,hz in ipairs({30,120}) do
    local rider=MOCK.newCharacter();GameInstance.playerController.mainCharacter=rider
    local baseline=state(rider)
    M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
    local l=M.lease;MOCK.run('TailTick',1/hz);MOCK.setAxes(.4,0)
    for _=1,hz*2 do MOCK.run('Tick',1/hz);MOCK.run('TailTick',1/hz) end
    local g=l.geometry;local radius=1/g.curvature
    local origin=rider.rootCom.transform.position
    local center=origin+U.Vector3(math.cos(g.beta)*radius,0,-math.sin(g.beta)*radius)
    local rearTotal,frontTotal=0,0
    MOCK.setAxes(.4,1)
    local maxCircleError=0
    for _=1,hz*3 do
        local rearBefore,frontBefore=l.rearAngle,l.frontAngle
        MOCK.run('Tick',1/hz);MOCK.nativeStep(1/hz,2);MOCK.run('TailTick',1/hz)
        rearTotal=rearTotal+U.Mathf.DeltaAngle(rearBefore,l.rearAngle)
        frontTotal=frontTotal+U.Mathf.DeltaAngle(frontBefore,l.frontAngle)
        local offset=rider.rootCom.transform.position-center
        maxCircleError=math.max(maxCircleError,math.abs(offset.magnitude-radius))
        -- Projected actual front axle direction is orthogonal to wheel velocity.
        local fork
        for _,p in ipairs(M.parts) do if p.role==3 then fork=p.transform end end
        local axle=fork.localRotation*U.Vector3(1,0,0)
        local k=l.geometry.curvature/l.geometry.rearFactor
        local frontLocal=U.Vector3(.0114865946,.8442755938,.4628484249)+fork.localRotation*(U.Vector3(.0255573198,.3189881429,.7810290642)-U.Vector3(.0114865946,.8442755938,.4628484249))
        local lateral=(frontLocal.x+.0255573198)*1.15
        assert(math.abs(axle.x*k*l.geometry.length+axle.z*(1-k*lateral))<1e-6,'front tyre rolls along its actual steering plane')
    end
    assert(maxCircleError<.04,'CG follows settled steering circle, not in-place rotation: '..maxCircleError)
    assert(frontTotal>rearTotal,'travel integrates different front/rear path lengths')
    print(string.format('Circle %dHz: max radial error %.8fm, front/rear travel ratio %.6f',hz,maxCircleError,frontTotal/rearTotal))
    MOCK.setAxes(0,0);M.close(desktop);restored(rider,baseline)
end
-- Hot steering configuration: same native speed, tighter REAL curve and fork,
-- not just a cosmetic turn or bigger stationary lock. Both directions and
-- the full schema range preserve hand/peg contact, tyre support and cleanup.
do
    local rider=MOCK.newCharacter();GameInstance.playerController.mainCharacter=rider
    local baseline=state(rider)
    M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
    local l=M.lease;local radii={};local locks={}
    for _,angle in ipairs({10,22,35,50,10}) do
        assert(PUBLIC.set('motorcycle','max_steer',angle));MOCK.run('TailTick',1/60)
        assert(M.lease==l and l.configSteer==angle,'hot setting keeps the same mount lease')
        assert(l.maxSteer<=angle and l.ridingConfig.scale==1.15,'reach cap never scales chassis')
        if angle==10 then assert(math.abs(l.steer)<=10,'reduction clamps immediately') end
        for _,side in ipairs({-1,1}) do
            MOCK.setAxes(side,0)
            for _=1,45 do MOCK.run('Tick',1/60);MOCK.nativeStep(1/60,0);MOCK.run('TailTick',1/60) end
            locks[angle]=math.abs(l.steer)
            for _,speed in ipairs({2,10}) do
                MOCK.setAxes(side,1)
                for _=1,60 do
                    MOCK.run('Tick',1/60);MOCK.nativeStep(1/60,speed);MOCK.run('TailTick',1/60)
                    assert(M.lease==l and l.steer==l.steer and l.geometry.curvature==l.geometry.curvature,'finite hot control')
                    for _,hand in ipairs({'left','right'}) do for _,kind in ipairs({'Arm','Leg'}) do
                        local chain=l[hand..kind]
                        assert((chain.c.position-l.targets[hand..kind]).magnitude<.015,'hot full-range grip/peg contact')
                    end end
                end
                if side==1 and speed==10 then radii[angle]=1/math.abs(l.geometry.curvature) end
                for _,gap in pairs(meshGroundGaps()) do assert(math.abs(gap)<1e-5,'hot lock tread support') end
            end
        end
    end
    assert(locks[35]>locks[22]+5,'larger config visibly increases fork travel')
    assert(radii[35]<radii[22]*.8,'setting tightens moving radius, not only stationary steering')
    print(string.format('Steering 10m/s: 22deg radius %.3fm -> 35deg %.3fm; fitted locks %.2f / %.2f',radii[22],radii[35],locks[22],locks[35]))
    assert(PUBLIC.set('motorcycle','max_steer',35));MOCK.setAxes(0,0)
    M.close(desktop);restored(rider,baseline)
end

-- Public nullable wrappers and partial-write/cleanup failures, foreign ownership.
GameInstance.playerController.mainCharacter=ch;MOCK.groundY=nil
MOCK.nullableWrapped=true;M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
MOCK.run('Tick');M.close(desktop);restored(ch,original);MOCK.nullableWrapped=nil
-- Replay the real 0.4.1 default-field-lookup failure before accepting the repair.
local ctor=MOCK.character.movementComponent.input:GetType()
assert(ctor:GetField('navMoveVector')==nil,'actual default lookup miss captured')
for _,flag in ipairs({'nonpublicDriveField','enumeratedFieldOnly'}) do
    MOCK[flag]=true;M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease,'explicit visibility/enumerated lookup '..flag)
    MOCK.run('Tick');M.close(desktop);MOCK[flag]=nil;restored(ch,original)
end
MOCK.readonlyDriveField=true;M.show(desktop);MOCK.press('F6');MOCK.press('F7')
assert(not M.lease and M.faulted,'readonly drive field rejected before mutation')
MOCK.readonlyDriveField=nil;M.close(desktop);restored(ch,original)
-- A missing direct binding fails before mutation; no broken Invoke fallback.
MOCK.hideDirectNav=true;M.show(desktop);MOCK.press('F6');MOCK.press('F7')
assert(not M.lease and M.faulted,'unavailable direct method rejects safely')
MOCK.hideDirectNav=nil;M.close(desktop);restored(ch,original)
-- Exact old Invoke failure is present in the fixture; production must never use it.
local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),'Instance, Public, NonPublic')
local invoke=ctor:GetMethod('NavMove',flags)
local ok,err=pcall(function()invoke:Invoke(ch.movementComponent.input,CS.System.Array.CreateInstance(typeof(CS.System.Object),3))end)
assert(not ok and err:find('invalid arguments to Invoke',1,true),'capture exact live Invoke rejection')
MOCK.failRelease=1;M.show(desktop);MOCK.press('F6');local calls=MOCK.navCalls
MOCK.press('F7');assert(not M.lease and M.faulted and MOCK.navCalls==calls,'failed null setter before acquiring persistent input')
M.close(desktop);restored(ch,original)
MOCK.opaqueEmptyNullable=true
M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease,'direct call with reflected nullable reads')
local resolves=MOCK.fieldResolves;local methodResolves=MOCK.methodResolves
for _=1,5 do MOCK.run('Tick') end
assert(MOCK.fieldResolves==resolves and MOCK.methodResolves==methodResolves,'metadata cached per lease, no frame lookup')
M.close(desktop);MOCK.opaqueEmptyNullable=nil;restored(ch,original)
MOCK.throwDirectDrive=true
M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease,'diagnostic direct getters cannot break valid reflected control')
MOCK.run('Tick');M.close(desktop);MOCK.throwDirectDrive=nil;restored(ch,original)
for _,flag in ipairs({'missingDriveField','missingDriveMethod'}) do
    MOCK[flag]=true;M.show(desktop);MOCK.press('F6');MOCK.press('F7')
    assert(not M.lease and M.faulted,'public contract failure before navigation write')
    restored(ch,original);MOCK[flag]=nil;M.close(desktop)
end
for _,failure in ipairs({'failNavBefore','failNavAfter'}) do
    M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
    MOCK[failure]=true;MOCK.setAxes(1,1);MOCK.run('Tick')
    assert(not M.lease and M.faulted);restored(ch,original)
    MOCK[failure]=nil;MOCK.setAxes(0,0);M.close(desktop)
end
M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
MOCK.failRelease=1;M.close(desktop);assert(#M.pending==1,'keep failed nullable cleanup for retry')
MOCK.run('Tick');assert(#M.pending==0 and MOCK.countUpdates()==0);restored(ch,original)
for _,field in ipairs({'navMoveVector','pendingNoManualMove','noManualMove'}) do
    local input=ch.movementComponent.input;local foreign=U.Vector3(.1,0,.9)
    M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
    input[field]=foreign;MOCK.run('Tick');assert(not M.lease and M.faulted)
    assert(vecNear(input[field],foreign),'never erase foreign '..field)
    input[field]=nil;M.close(desktop);restored(ch,original)
end
local input=ch.movementComponent.input
input.navMoveVector=U.Vector3(1,0,0)
M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(not M.lease and M.faulted)
assert(vecNear(input.navMoveVector,U.Vector3(1,0,0)),'refuse occupied input before mutation')
input.navMoveVector=nil;M.close(desktop);restored(ch,original)
-- Grade + braking/pitch at model yaw 0 AND 180; no one-wheel lift solution.
for _,yaw in ipairs({0,180}) do
    local rider=MOCK.newCharacter();GameInstance.playerController.mainCharacter=rider
    local baseline=state(rider)
    MOCK.groundY=-.07;MOCK.groundSlope=U.Vector3(.08,0,.18)
    assert(PUBLIC.set('motorcycle','model_yaw',yaw))
    M.show(desktop);MOCK.press('F6');MOCK.press('F7');assert(M.lease)
    for i=1,45 do
        rider.rootCom.transform.position=U.Vector3(0,0,i*.012)
        MOCK.run('TailTick',1/60)
    end
    local l=M.lease
    assert(math.abs(l.terrainPitch)>2,'slope is fitted, not a root-height horizontal plane')
    local gaps=meshGroundGaps()
    for _,gap in pairs(gaps) do assert(math.abs(gap)<1e-5,'both actual tyres stay on sloping terrain while chassis pitches') end
    assert(vecNear(rider.rootCom.transform.position,U.Vector3(0,0,45*.012)),'native root untouched by contact fit')
    -- Missing/invalid/saturated or unavailable query: use current native floor
    -- plane. Stale hits are ignored, no lower storey / wall snap or error loop.
    l.mover.currentFloor={isHit=true,walkableFloor=true,floorHit={point=U.Vector3(0,-.07,0),normal=U.Vector3(-.08,1,-.18).normalized}}
    for _,flag in ipairs({'groundMissing','groundWall','groundSaturated','failGroundQuery'}) do
        MOCK[flag]=true;MOCK.run('TailTick',1/60);assert(M.lease and not M.faulted)
        local gaps=meshGroundGaps()
        for _,gap in pairs(gaps) do assert(math.abs(gap)<1e-5,'native floor fallback '..flag) end
        MOCK[flag]=nil
    end
    M.close(desktop);restored(rider,baseline)
end
MOCK.groundY,MOCK.groundSlope=nil,nil
GameInstance.playerController.mainCharacter=ch
assert(PUBLIC.set('motorcycle','model_yaw',0))
print('PASS: real schema/INI/API, ownership/rollback, fixed-size IK, vehicle control/curvature/native input ownership and actual tread contact/floor fallback')
