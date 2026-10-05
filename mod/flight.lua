-- Vehicle ballistic motion controller.
-- TryMoveCapsule performs the native sweep and updates logicPos.
Flight={}
local function mode(l) return l.mover.moveMode end
local function external() return CS.Beyond.Gameplay.Core.MovementComponent.MoveMode.External end
local function method(t,name,flags,ret,n)
    local m=assert(t:GetMethod(name,flags),"flight method missing: "..name)
    assert(m.IsPublic and not m.IsStatic and m.ReturnType.FullName==ret,"flight method drift: "..name)
    local p=m:GetParameters();assert(p.Length==n,"flight parameters drift: "..name)
    return p
end
function Flight.prepare(l)
    if l.flightPort then return end
    local mover=l.mover
    local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),"Instance, Public, NonPublic")
    local t=mover:GetType()
    assert(t.FullName=="Beyond.Gameplay.Core.MovementComponent","flight movement type drift")
    method(t,"EnterExternal",flags,"System.Void",0);method(t,"LeaveExternal",flags,"System.Void",0)
    local p=method(t,"TryMoveCapsule",flags,"System.Boolean",7)
    assert(p[0].ParameterType.FullName=="UnityEngine.Vector3" and p[1].ParameterType.FullName=="UnityEngine.Quaternion" and
        p[2].ParameterType.FullName=="System.Boolean" and p[3].IsOut and p[3].ParameterType.IsByRef and
        p[3].ParameterType:GetElementType().FullName=="UnityEngine.RaycastHit","flight capsule signature drift")
    for i=4,6 do assert(p[i].IsOptional and p[i].HasDefaultValue,"flight capsule defaults unavailable") end
    method(l.input:GetType(),"ConsumeJump",flags,"System.Void",0)
    local port={enter=assert(mover.EnterExternal),leave=assert(mover.LeaveExternal),
        move=assert(mover.TryMoveCapsule),consume=assert(l.input.ConsumeJump)}
    local hit,info=port.move(mover,V(0,0,0),l.root.transform.rotation,true)
    assert(type(hit)=="boolean" and info and info.normal,"flight capsule out binding unavailable")
    assert(mover.logicPos,"flight native position unavailable")
    l.flightPort=port;report("vehicle_flight_ready")
end
function Flight.request(l)
    assert(M.settings.terrain_grace>0,"jump requires nonzero terrain grace")
    Flight.prepare(l)
    assert(not l.input.passiveJumpTrigger and not l.input.aiJumpTrigger,"foreign jump pending")
    local horizontal=copy(l.groundMomentum or V(0,0,0))
    local magnitude=horizontal.magnitude
    assert(magnitude==magnitude and magnitude<=M.settings.speed*3+5,"unsafe vehicle momentum")
    local up=clamp(M.settings.jump_base_speed+magnitude*M.settings.jump_speed_boost,2,12)
    queueDrive(l,V(0,0,0))
    l.flight={horizontal=horizontal,vy=up,gravity=M.settings.jump_gravity,elapsed=0,last=copy(l.mover.logicPos)}
    l.jumpUp=up;l.airborne=true;l.groundSamples={}
    l.flightPort.consume(l.input) -- Consume space jump request
    l.flightPort.enter(l.mover)
    assert(mode(l)==external(),"native external movement refused")
    report("vehicle_jump_started")
end
function Flight.release(l)
    local f=l.flight;if not f then return end
    if not l.char:IsValid() or mode(l)~=external() then l.flight=nil;return end
    if not f.leaving then
        l.flightPort.leave(l.mover);f.leaving=true
        report("vehicle_flight_releasing")
    end
    -- Wait for asynchronous exit from External mode
end
function Flight.allowed(l,dt)
    local f=l.flight;if not f then return false end
    if mode(l)~=external() then
        if f.leaving then l.flight=nil;return rideTerrain(l,l.mover,dt) end
        return false
    end
    l.airborne=true
    return M.settings.jump_enabled and M.settings.terrain_grace>0 and f.elapsed<=M.settings.terrain_grace and
        (l.groundY or f.last.y)-l.mover.logicPos.y<=M.settings.terrain_drop
end
function Flight.step(l,dt)
    local f=l.flight;if not f then return end
    if f.leaving then Flight.release(l);return end
    assert(mode(l)==external(),"vehicle flight interrupted")
    assert(distance(l.mover.logicPos,f.last)<.4,"foreign flight displacement")
    queueDrive(l,V(0,0,0))
    f.elapsed=f.elapsed+dt
    local count=math.max(1,math.ceil(dt*120));local h=dt/count
    for i=1,count do
        local before=copy(l.mover.logicPos)
        local delta=f.horizontal*h+V(0,f.vy*h-f.gravity*h*h*.5,0)
        f.vy=f.vy-f.gravity*h
        local swept,normal=M.sweepFlight(l,before,delta)
        local hit,info=l.flightPort.move(l.mover,swept,l.root.transform.rotation,true)
        assert(type(hit)=="boolean" and info and info.normal,"vehicle capsule result drift")
        local after=copy(l.mover.logicPos);f.last=after
        assert(distance(after,before)<=delta.magnitude+.05,"unsafe native flight displacement")
        if hit and info.normal.magnitude>.1 then normal=info.normal end
        if not normal and swept.magnitude>.005 then
            assert(distance(after,before)>.00001,"native flight movement rejected")
        end
        if normal then
            if f.vy<=0 and normal.y>.45 then Flight.release(l);report("vehicle_jump_landed");break end
            if normal.y<-.45 then f.vy=math.min(0,f.vy) end
            local wall=V(normal.x,0,normal.z).normalized
            local into=dot(f.horizontal,wall)
            if into<0 then f.horizontal=f.horizontal-wall*into end
        end
    end
end
