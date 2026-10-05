-- Real public configuration + production Lua, simulated native contracts.
local U=CS.UnityEngine
local pc=GameInstance.playerController
local ctrl={isPCPanel=true}
local function start()
    MOCK.groundY=0;MOCK.groundSlope=nil;MOCK.setAxes(0,0)
    pc.mainCharacter=MOCK.newCharacter()
    M.show(ctrl);M.summon();if M.presentation then M.finishPresentation() end
    M.mount();assert(M.lease and M.phase=='mounted')
    MOCK.run('Tick');MOCK.run('TailTick')
    return M.lease,pc.mainCharacter.movementComponent
end
local function finish()
    M.close(ctrl);MOCK.run("Tick");MOCK.run("Tick");assert(not M.lease and #M.pending==0)
end
local function set(k,v)assert(PUBLIC.set('motorcycle',k,v))end
for key,values in pairs({terrain_grace={-.1,5.1,1.05},terrain_drop={.5,12.5,2.25},
    jump_cooldown={.1,3.1,.25},jump_base_speed={2.5,8.5,3.25},jump_speed_boost={-.05,1.05,.03},jump_pitch={-1,31,.5},jump_gravity={5.5,30.5,14.25},speed_fx_threshold={.5,18.5,2.25},
    speed_fx_intensity={-.1,2.1,.05},ride_fov={-1,31,.5},fov_blend={0,2.1,.15}}) do
    for _,v in ipairs(values) do assert(not PUBLIC.set('motorcycle',key,v),'reject '..key) end
end
local l,mover=start()
local y=pc.mainCharacter.rootCom.transform.position.y
mover.moveMode='Falling'
for i=1,20 do MOCK.run('Tick',.1);MOCK.run('TailTick',.1);assert(M.lease==l,'terrain grace') end
assert(math.abs(l.airTime-2)<1e-6,'TailTick must not double-charge timer')
mover.moveMode='Landing';MOCK.run('Tick');assert(l.airTime==0 and not l.airborne)
mover.moveMode='Falling'
for i=1,31 do MOCK.run('Tick',.1) end
assert(not M.lease,'bounded air timeout');finish()
l,mover=start();mover.moveMode='Falling'
pc.mainCharacter.rootCom.transform.position=U.Vector3(0,-6.1,0)
MOCK.run('Tick');assert(not M.lease,'bounded drop');finish()
l,mover=start();set('terrain_grace',0);mover.moveMode='Falling';MOCK.run('Tick')
assert(not M.lease,'strict mode hot applied');set('terrain_grace',3);finish()

-- Real production flight controller, simulated native collision/async external exit.
local height={}
for _,momentum in ipairs({U.Vector3(0,0,0),U.Vector3(4,0,8),U.Vector3(-2,0,-3)}) do
    l,mover=start();l.groundMomentum=momentum;l.velocity=0;mover.velocity=U.Vector3(0,0,0)
    local nativeJumps=MOCK.jumpCalls or 0
    local from=pc.mainCharacter.rootCom.transform.position
    MOCK.press('Space');assert(l.flight and mover.moveMode=='External',table.concat(MOCK.errors,' | '))
    assert((MOCK.jumpCalls or 0)==nativeJumps,'never call a character jump')
    assert((l.flight.horizontal-momentum).magnitude<1e-8,'momentum '..l.flight.horizontal.x..','..l.flight.horizontal.z)
    local f=l.flight;local up=4+momentum.magnitude*.4
    assert(math.abs(l.jumpUp-up)<1e-6)
    local time=1/60;local apex=0;local raised,lowered=false,false;local speed=l.speed
    for frame=1,180 do
        MOCK.setAxes(-1,-1);MOCK.keysHeld.LeftControl=true
        if frame==2 then MOCK.keysDown.Space=true end
        MOCK.run('Tick');MOCK.run('TailTick')
        assert(M.lease==l,'flight retains rider')
        local pos=pc.mainCharacter.rootCom.transform.position
        apex=math.max(apex,pos.y-from.y)
        if l.flight and not l.flight.leaving then
            assert(l.speed==speed,'no ground brake/reverse cap in flight')
            assert(math.abs(pos.x-from.x-momentum.x*f.elapsed)<1e-5 and math.abs(pos.z-from.z-momentum.z*f.elapsed)<1e-5,'actual horizontal distance')
            if f.vy>2 and l.jumpPitch<-.3 then raised=true end
            if f.vy< -2 and l.jumpPitch>.3 then lowered=true end
        end
        for _,side in ipairs({'left','right'}) do for _,kind in ipairs({'Arm','Leg'}) do
            local chain=l[side..kind];assert((chain.c.position-l.targets[side..kind]).magnitude<.015,'flight rider contacts')
        end end
        if not l.flight then break end
        time=time+1/60
    end
    assert(not l.flight and mover.moveMode=='Grounded','normal landing releases external mode')
    assert(raised and lowered,'flight pitch rise/fall')
    assert(math.abs(apex-up*up/(2*14))<.01,'own gravity yields configured apex')
    height[#height+1]=apex;MOCK.keysHeld.LeftControl=nil;finish()
end
assert(height[2]>height[1]*3,'speed increases own flight height')
-- Native getters deliberately remain zero; sample real resolved ground displacement.
l,mover=start();MOCK.setAxes(0,1)
for i=1,8 do MOCK.run('Tick',.02);MOCK.nativeStep(.02,10);MOCK.run('TailTick',.02) end
assert(math.abs(l.groundMomentum.z-10)<1e-5)
mover.velocity=U.Vector3(0,0,0);MOCK.press('Space');assert(math.abs(l.flight.horizontal.z-10)<1e-5,'not native zero velocity');finish()
for _,fault in ipairs({'badFlightOut','badFlightOptional','failFlightCapsule'}) do
    l,mover=start();MOCK[fault]=true;MOCK.press('Space')
    assert(M.lease==l and not l.flight and mover.moveMode=='Grounded','safe flight binding refusal '..fault)
    MOCK[fault]=nil;finish()
end
l,mover=start();MOCK.missingFlightMethod='EnterExternal';MOCK.press('Space');assert(not l.flight)
MOCK.missingFlightMethod=nil;finish()
l,mover=start();MOCK.failFlightEnter=true;MOCK.press('Space');MOCK.failFlightEnter=nil
MOCK.run('Tick');assert(not l.flight and mover.moveMode=='Grounded','partial enter rollback');finish()
l,mover=start();l.groundMomentum=U.Vector3(4,0,0);MOCK.press('Space')
MOCK.flightWall=pc.mainCharacter.rootCom.transform.position.x+.08
for i=1,12 do MOCK.run('Tick');MOCK.run('TailTick');assert(pc.mainCharacter.rootCom.transform.position.x<=MOCK.flightWall+.00001) end
assert(l.flight.horizontal.x==0,'wall removes blocked momentum');MOCK.flightWall=nil;finish()
l,mover=start();MOCK.flightCeiling=.15;MOCK.press('Space');for i=1,4 do MOCK.run('Tick');MOCK.run('TailTick') end;assert(l.flight.vy<=0,'ceiling prevents further ascent')
MOCK.flightCeiling=nil;finish()
l,mover=start();MOCK.press('Space');MOCK.failFlightLeave=true;MOCK.fight=true;MOCK.run('Tick')
assert(not M.lease and #M.pending==1,'fight forces exit even if mode cleanup delayed')
MOCK.failFlightLeave=nil;MOCK.fight=nil;MOCK.run('Tick');MOCK.run('Tick')
assert(#M.pending==0 and mover.moveMode=='Grounded','async leave/retry');finish()
for _,mode in ipairs({'Blown','Plunge','PassiveJumping','AIJumping','Teleport','Spline','ManualMoveInSkill','External'}) do
    l,mover=start();mover.moveMode=mode;MOCK.run('Tick');assert(not M.lease,'foreign/unsafe mode '..mode);finish()
end
l,mover=start();MOCK.press('Space');mover.moveMode='Blown';MOCK.run('Tick')
assert(not M.lease and mover.moveMode=='Blown','foreign mode never overwritten');finish()
l,mover=start();set('jump_gravity',20);set('jump_speed_boost',0);l.groundMomentum=U.Vector3(0,0,10)
MOCK.press('Space');assert(l.flight.gravity==20 and l.jumpUp==4,'hot flight settings captured')
set('jump_gravity',14);set('jump_speed_boost',.4);finish()

l,mover=start();MOCK.press('Space');MOCK.failFlightAfterMove=true;MOCK.run('Tick')
assert(not M.lease,'partial movement failure stops controller');MOCK.failFlightAfterMove=nil;finish()
l,mover=start();MOCK.press('Space');MOCK.collisionSaturated=true;MOCK.run('Tick')
assert(not M.lease,'saturated full-bike sweep fails closed');MOCK.collisionSaturated=nil;finish()
l,mover=start();MOCK.press('Space');set('jump_enabled',false);MOCK.run('Tick')
assert(not M.lease,'hot disabled flight releases owner');set('jump_enabled',true);finish()
l,mover=start();MOCK.press('Space');mover.input.NavMove(mover.input,U.Vector3(1,0,0),false);MOCK.run('Tick')
assert(not M.lease and mover.input.navMoveVector.x==1,'foreign navigation preserved in flight');finish()
-- Fixed-timestep substeps
for _,dt in ipairs({1/30,1/60,.1}) do
    l,mover=start();l.groundMomentum=U.Vector3(0,0,5);MOCK.press('Space')
    local f=l.flight
    for i=1,math.floor(.2/dt+.001) do MOCK.run('Tick',dt);MOCK.run('TailTick',dt) end
    local pos=pc.mainCharacter.rootCom.transform.position
    assert(math.abs(pos.z-5*f.elapsed)<1e-5 and math.abs(pos.y-(4+2)*f.elapsed+7*f.elapsed*f.elapsed)<1e-5,'frame independent vehicle integration')
    finish()
end

MOCK.cameraOffset=2
l,mover=start()
for i=1,12 do MOCK.run('TailTick',.1) end
assert(math.abs(MOCK.cameraOffset-14)<.01,'native camera widened relative to snapshot')
set('ride_fov',20);MOCK.run('TailTick',.1);assert(MOCK.cameraOffset>14,'hot FOV')
set('ride_fov',0);MOCK.run('TailTick');assert(MOCK.cameraOffset==2,'disable restores own offset')
set('ride_fov',12);MOCK.run('TailTick');assert(MOCK.cameraOffset>2)
MOCK.cameraOffset=7;MOCK.run('TailTick');assert(l.cameraBlocked and not l.camera)
finish();assert(MOCK.cameraOffset==7,'foreign camera change preserved')
MOCK.cameraOffset=0
l,mover=start();GameInstance.cameraManager.curActiveController={}
MOCK.run('TailTick');assert(MOCK.cameraOffset==0 and not l.camera,'camera switch restores old only')
GameInstance.cameraManager.curActiveController=MOCK.cameraController;finish()
l,mover=start();MOCK.failCameraSet=true;M.unmount(true)
assert(#M.pending==1,'camera restoration retained for retry')
MOCK.failCameraSet=nil;MOCK.run('Tick');assert(#M.pending==0 and MOCK.cameraOffset==0);finish()

l,mover=start()
assert(not l.speedFX,'no particles while stationary')
local function moving()
    MOCK.setAxes(0,1);MOCK.run('Tick',.1);MOCK.nativeStep(.1,10);MOCK.run('TailTick',.1)
end
moving();assert(l.speedFX and #l.speedFX==4,table.concat(MOCK.errors,' | '))
local fx=l.speedFX;local before={}
local function anchored()
    for _,item in ipairs(fx) do
        local part
        for _,p in ipairs(M.parts) do if p.role==item.role then part=p end end
        assert(part)
        if item.dust then
            local plane=l.contactPlanes[item.role]
            local minimum=math.huge
            for _,s in ipairs(part.tire) do
                local p=part.transform:TransformPoint(U.Vector3(s.x,s.y,s.z))
                minimum=math.min(minimum,U.Vector3.Dot(p-plane.point,plane.normal))
            end
            local actual=U.Vector3.Dot(item.go.transform.position-plane.point,plane.normal)
            assert(math.abs(actual-minimum-.04)<1e-6,'dust emitted at actual tread contact, not sphere approximation')
            assert(item.ps.main.simulationSpace=='World')
        else
            assert((item.go.transform.position-part.transform.position).magnitude<1e-6,'wind on actual wheel center')
            assert(item.ps.main.simulationSpace=='Local','wind follows wheel rather than lingering far behind')
        end
        assert(item.go.components.ParticleSystemRenderer.pivot.magnitude==0)
        local main=item.ps.main
        local size=main.startSizeMultiplier*item.go.transform.localScale.x
        assert(size>=.3 and main.startLifetimeMultiplier>=.3,'visible size/lifetime budget')
        assert(item.dust and item.go.components.ParticleSystemRenderer.alignment=='View' or
            not item.dust and item.go.components.ParticleSystemRenderer.alignment=='Local','preserve native dust facing')
    end
end
anchored()
for i,item in ipairs(fx) do before[i]=item.ps.emitted end
-- Pin measured native velocity high across repeated real-tail frames.
for i=1,8 do moving() end
anchored()
MOCK.groundSlope=U.Vector3(.08,0,.18);MOCK.setAxes(1,1);MOCK.run('Tick',.1);MOCK.nativeStep(.1,10);MOCK.run('TailTick',.1);anchored()
MOCK.groundSlope=nil
for i,item in ipairs(fx) do assert(item.ps.emitted>before[i],'both tyre effect types emit') end
mover.moveMode='Falling';MOCK.run('Tick')
for i,item in ipairs(fx) do before[i]=item.ps.emitted end
for i=1,4 do moving() end
for i,item in ipairs(fx) do if item.dust then assert(item.ps.emitted==before[i],'no dust in air')
    else assert(item.ps.emitted>before[i],'wind remains in air') end end
set('speed_fx',false)
for i,item in ipairs(fx) do before[i]=item.ps.emitted end
moving()
for i,item in ipairs(fx) do assert(item.ps.emitted==before[i],'hot disable') end
set('speed_fx',true);set('speed_fx_intensity',0);moving()
for i,item in ipairs(fx) do assert(item.ps.emitted==before[i],'zero intensity') end
set('speed_fx_intensity',1);finish()
for _,item in ipairs(fx) do assert(item.go.destroyed and item.ps.cleared,'owned FX cleared on exit') end
for _,fault in ipairs({'failSpeedFXLoad','failSpeedFXClone','unsafeSpeedFX'}) do
    l,mover=start();MOCK[fault]=true;moving()
    assert(M.lease==l and l.speedFXFailed and not l.speedFX,'optional visual failure isolated '..fault)
    MOCK[fault]=nil;finish()
end
-- Failure after the first clone/configuration must also destroy partial effects.
l,mover=start();local prior=MOCK.speedFXClones or 0
MOCK.failSpeedFXCloneAt=prior+2;moving()
assert(M.lease==l and l.speedFXFailed and not l.speedFX)
for _,go in ipairs(MOCK.objects) do if go.name=='ZML_Bike_SpeedFX' then assert(go.destroyed) end end
MOCK.failSpeedFXCloneAt=nil;finish()
MOCK.groundY=nil;MOCK.cameraOffset=0
print('PASS: bounded terrain grace/drop, owned ballistic flight/native capsule sweep/landing/forced exits, owned FOV hot apply/foreign ownership/retry and two-wheel native particles/air suppression/cleanup')
