-- Runs exclusively on the normal game's Lua/Unity main-thread lifecycle.
local M = {phase="absent", keys={}, pending={}, settings=nil}
local U = CS.UnityEngine
local V, Q = U.Vector3, U.Quaternion
local ID = "motorcycle"
local LEGACY_DISMOUNT="F7" -- ZML_KEYBIND_DEFAULT
local keyActions
local function ensureKeys()
    if keyActions then return end
    require_ex("Common/Utils/UIUtils")
    if not rawget(_G,"ZMLKeybinds") then require_ex("UI/Panels/GameSetting/GameSettingCtrl") end
    local K=assert(rawget(_G,"ZMLKeybinds"),"keybinds library unavailable")
    if K._attachGate then K._attachGate() end
    assert(K.api==1 and K.version~="0.1.0","keybinds continuous input API unavailable")
    local defs={{"dismount","摩托车 · 下车",LEGACY_DISMOUNT},{"jump","摩托车 · 跳跃","Space"},
        {"forward","摩托车 · 前进","W"},{"reverse","摩托车 · 倒车","S"},
        {"left","摩托车 · 左转","A"},{"right","摩托车 · 右转","D"},{"brake","摩托车 · 刹车","LeftControl"}}
    local actions={}
    for _,d in ipairs(defs) do
        actions[d[1]]=K.find(ID,d[1]) or assert(K.register(ID,{id=d[1],name=d[2],primary=d[3],migrate=d[1]=="dismount"}))
        assert(type(actions[d[1]].down)=="function" and type(actions[d[1]].pressed)=="function","keybinds API mismatch")
    end
    keyActions=actions
end
-- ZML_WHEEL_GEOMETRY_BEGIN
-- Derived from our licensed model by tools/calibrate-bike.py, not game assets.
local BIKE={rearRadius=.3189637154,frontRadius=.3189681663,
    rear=V(-.0255573198,.318983692,-.7003807752),front=V(.0255573198,.3189881429,.7810290642),
    steerPivot=V(.0114865946,.8442755938,.4628484249)}
-- ZML_WHEEL_GEOMETRY_END
-- Steering rotates around inclined headstock axis
local STEER_AXIS=V(0,BIKE.steerPivot.y-BIKE.front.y,BIKE.steerPivot.z-BIKE.front.z).normalized
local function forkRotation(angle) return Q.AngleAxis(angle,STEER_AXIS) end
local function turnGeometry(scale,angle)
    local front=BIKE.steerPivot+forkRotation(angle)*(BIKE.front-BIKE.steerPivot)
    local axis=forkRotation(angle)*V(1,0,0)
    local road=math.atan(-axis.z,axis.x)
    local length=(front.z-BIKE.rear.z)*scale
    local lateral=(front.x-BIKE.rear.x)*scale
    local k=math.sin(road)/(length*math.cos(road)+lateral*math.sin(road))
    local ahead,side=-BIKE.rear.z*scale,-BIKE.rear.x*scale
    local factor=math.sqrt((ahead*k)^2+(1-side*k)^2)
    return {curvature=k/factor,rearFactor=1/factor,
        frontFactor=math.sqrt((k*length)^2+(1-k*lateral)^2)/factor,
        beta=math.atan(ahead*k,1-side*k),roadAngle=math.deg(road),length=length}
end
-- ZML_ASSET_DATA
local PREFAB = "assets/beyond/arts/environment/sceneassets/map01/prop/prop_map01_motorcycle+1_001/prefabs/p_prop_map01_motorcycle+2_001_01.prefab"
local MATERIAL = "assets/beyond/arts/environment/sceneassets/map01/prop/prop_map01_motorcycle+1_001/materials/m_prop_map01_motorcycle+2_001_01.mat"
local function copy(v) return V(v.x,v.y,v.z) end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function dot(a,b) return V.Dot(a,b) end
local function distance(a,b) return V.Distance(a,b) end
local function damp(current,target,dt,rate) return current+(target-current)*(1-math.exp(-dt*rate)) end
-- Exact critically damped spring: frame-rate independent, stores angular momentum.
local function spring(value,velocity,target,dt,frequency)
    local error=value-target
    local impulse=velocity+error*frequency
    local decay=math.exp(-frequency*dt)
    return target+(error+impulse*dt)*decay,(velocity-impulse*frequency*dt)*decay
end
local function live(object) return object ~= nil and not object:Equals(nil) end
local function notice(text) pcall(function() Notify(MessageConst.SHOW_TOAST,text) end) end
local function report(event) if M.api then pcall(M.api.report,ID,event) end end
local function warnEvent(event,err)
    report(event)
    -- Report internal exception
    local detail=err and (": "..tostring(err):gsub("[%c]"," "):sub(1,512)) or ""
    -- Native logger exposes error/warn, not warning. warn is disabled in release.
    pcall(function() logger.error("ZML Motorcycle: "..event..detail) end)
end
local function api()
    if M.api then return M.api end
    local fn=assert(loadstring(LuaManagerInst:LoadLua("ZML/Api"),"@ZML/Api"))
    M.api=fn()
    return M.api
end
local function config()
    local v=assert(api().get(ID))
    local c={enabled=v.enabled=="true",scale=tonumber(v.scale),speed=tonumber(v.speed),
        acceleration=tonumber(v.acceleration),max_steer=tonumber(v.max_steer),speed_steer_reduction=tonumber(v.speed_steer_reduction),seat_height=tonumber(v.seat_height),model_yaw=tonumber(v.model_yaw),
        }
    for _,key in ipairs({"terrain_grace","terrain_drop","jump_cooldown","jump_base_speed","jump_speed_boost","jump_pitch","jump_gravity","speed_fx_threshold","speed_fx_intensity","ride_fov","fov_blend"}) do
        c[key]=assert(tonumber(v[key]),"riding configuration unavailable")
    end
    c.jump_enabled=v.jump_enabled=="true";c.speed_fx=v.speed_fx=="true"
    assert(c.scale and c.speed and c.acceleration and c.max_steer and c.max_steer>=10 and c.max_steer<=50 and c.speed_steer_reduction and c.speed_steer_reduction>=0 and c.speed_steer_reduction<=1 and c.seat_height and c.model_yaw,"configuration unavailable")
    return c
end
local function character()
    local pc=GameInstance.playerController
    if pc==nil then return nil end
    local ch=pc.mainCharacter
    if ch==nil or not ch:IsValid() or not ch.alive or ch.inCinematic then return nil end
    local mover,root=ch.movementComponent,ch.rootCom
    if mover==nil or root==nil or not mover.enabled or not live(root.transform) then return nil end
    return ch,pc,mover,root
end
local function groundAllowed(mover)
    local Mode=CS.Beyond.Gameplay.Core.MovementComponent.MoveMode
    return mover.moveMode==Mode.Grounded or mover.moveMode==Mode.StepClimbing or
        mover.moveMode==Mode.Pivot or mover.moveMode==Mode.TurnStart
end
local function gameAllowed(pc)
    return U.Application.isFocused and GameInstance.isInGameplay and
        not pc.blockPlayerInput and not pc.castingNormalAttack and not Utils.isInFight() and
        not Utils.isInThrowMode() and not Utils.isInCustomAbility()
end
-- Advance airborne timer in Tick
local Flight
local function rideTerrain(l,mover,dt)
    if l.flight then return Flight.allowed(l,dt) end
    local mode=CS.Beyond.Gameplay.Core.MovementComponent.MoveMode
    local y=l.root.transform.position.y
    if groundAllowed(mover) or (M.settings.terrain_grace>0 and mover.moveMode==mode.Landing) then
        l.airTime=0;l.groundY=y;l.airborne=false;return true
    end
    local jumping=mover.moveMode==mode.Jumping and M.settings.jump_enabled
    if not jumping and mover.moveMode~=mode.Falling then return false end
    l.airborne=true;l.airTime=(l.airTime or 0)+(dt or 0)
    return M.settings.terrain_grace>0 and l.airTime<=M.settings.terrain_grace and
        (l.groundY or y)-y<=M.settings.terrain_drop
end
local function typing()
    local es=U.EventSystems.EventSystem.current
    if es==nil or not live(es.currentSelectedGameObject) then return false end
    local go=es.currentSelectedGameObject
    return go:GetComponent(typeof(CS.TMPro.TMP_InputField))~=nil or
        go:GetComponent(typeof(U.UI.InputField))~=nil
end
local function setScale()
    if not M.visual then return end
    local c=M.settings
    local scale=M.lease and M.lease.ridingConfig and M.lease.ridingConfig.scale or c.scale
    M.visual.transform.localScale=V(scale,scale,scale)
    M.visual.transform.localRotation=Q.Euler(0,c.model_yaw,0)
    M.visual.transform.localPosition=V(0,0,0)
    if M.collisionScale~=scale then M.collisionScale=scale;M.collisionArmed=nil end
    M.syncCollision()
end
local function own(object)
    assert(object,"owned model resource unavailable")
    M.owned=M.owned or {}; M.owned[#M.owned+1]=object
    return object
end
local function newObject(name)
    local object=U.GameObject(name)
    M.objects=M.objects or {};M.objects[#M.objects+1]=object
    return object
end
-- ZML_NATIVE_ACTIONS
local function destroyVehicle()
    M.removeInteraction();M.stopEffects(true);M.renderHelper=nil;M.effectAssets=nil;M.effectNames=nil
    M.renderTemplate=nil
    if live(M.bodyCollider) then M.bodyCollider.enabled=false end
    M.bodyCollider,M.collisionHits,M.collisionOverlaps=nil,nil,nil
    M.collisionArmed=nil
    M.collisionScale=nil
    -- Track even objects whose SetParent subsequently failed; no orphaned partial model.
    for i=#(M.objects or {}),1,-1 do pcall(U.Object.Destroy,M.objects[i]) end
    -- Dynamic mesh/texture/material clones
    for i=#(M.owned or {}),1,-1 do pcall(U.Object.Destroy,M.owned[i]) end
    M.objects,M.owned,M.parts,M.renderers,M.vehicle,M.visual,M.mesh=nil,nil,nil,nil,nil,nil,nil
    M.groundHits=nil
    M.groundQueryReported,M.rootGroundReported=nil,nil
    if M.loader then pcall(function() M.loader:DisposeAllHandles() end) end
    M.loader=nil
    M.phase="absent"
end
local function visualTemplate()
    local prefab=assert(M.loader:LoadGameObject(PREFAB),"native visual prefab unavailable")
    local candidates=prefab:GetComponentsInChildren(typeof(U.MeshRenderer),true)
    local selected
    for i=0,candidates.Length-1 do
        local go=candidates[i].gameObject
        if go.name=="S_prop_map01_motorcycle+1_001_01_lod0" then
            assert(not selected,"ambiguous native LOD0")
            selected=go
        end
    end
    assert(selected,"native LOD0 branch unavailable")
    -- Inspect the asset BEFORE cloning: only Transform/MeshFilter/MeshRenderer,
    -- no child, collision, LOD controller, or user/game behaviour may execute.
    local filter=selected:GetComponent(typeof(U.MeshFilter))
    local renderer=selected:GetComponent(typeof(U.MeshRenderer))
    assert(selected.transform.childCount==0 and filter and renderer and
        selected:GetComponents(typeof(U.Component)).Length==3,"native visual branch contract changed")
    assert(filter.sharedMesh and renderer.sharedMaterial and renderer.enabled,"native visual assets unavailable")
    report("native_visual_template_ready")
    return selected
end
local function cloneVisual(template,name)
    local object=assert(U.Object.Instantiate(template),"native visual clone unavailable")
    M.objects=M.objects or {};M.objects[#M.objects+1]=object
    object.name=name
    object.layer=M.vehicle.layer
    object.transform.localRotation=Q.identity
    object.transform.localScale=V(1,1,1)
    return object
end
local function buildModel(template,visual)
    local bytes=CS.System.Convert.FromBase64String(BIKE_MESH_BASE64)
    -- XLua binary string return
    local byteLength=type(bytes)=="string" and #bytes or bytes.Length
    assert(byteLength and byteLength>12,"motorcycle bytes unavailable")
    local at=8
    local function read(method,n)
        assert(at+n<=byteLength,"truncated motorcycle asset")
        local a,b,c,d
        if type(bytes)=="string" then a,b,c,d=string.byte(bytes,at+1,at+n)
        else a,b=bytes[at],bytes[at+1];if n==4 then c,d=bytes[at+2],bytes[at+3] end end
        at=at+n
        local value=a+b*256+(c or 0)*65536+(d or 0)*16777216
        if method=="ToInt16" then return value>=32768 and value-65536 or value end
        if method=="ToSingle" then
            local sign=value>=2147483648 and -1 or 1
            local exponent=math.floor(value/8388608)%256
            local mantissa=value%8388608
            assert(exponent~=255,"non-finite motorcycle float")
            if exponent==0 then return sign*2^-126*(mantissa/8388608) end
            return sign*2^(exponent-127)*(1+mantissa/8388608)
        end
        -- Decode binary payload directly in Lua
        return value
    end
    local function u32()return read("ToUInt32",4)end
    local function f32()return read("ToSingle",4)end
    local function v3()local x,y,z=f32(),f32(),f32();return V(x,y,z)end
    local function array(kind,n) return CS.System.Array.CreateInstance(typeof(kind),n) end
    -- Geometry UVs select these solid industrial paint/material swatches.
    -- Keep the original source PNG unchanged; this palette is entirely owned.
    local texture=own(U.Texture2D(8,1));texture.name="ZML_Bike_EndfieldPalette"
    local palette={{49,49,49},{166,170,173},{96,96,96},{229,232,230},
        {255,239,0},{28,28,28},{247,247,242},{247,247,242}}
    for i,c in ipairs(palette) do texture:SetPixel(i-1,0,U.Color(c[1]/255,c[2]/255,c[3]/255,1)) end
    texture:Apply(false,false)
    texture.filterMode=U.FilterMode.Point
    texture.wrapMode=U.TextureWrapMode.Clamp
    local function pixel(name,color)
        local t=own(U.Texture2D(1,1));t.name=name;t:SetPixel(0,0,color);t:Apply(false,false);return t
    end
    local white=pixel("ZML_Bike_White",U.Color(1,1,1,1))
    local flat=pixel("ZML_Bike_Normal",U.Color(.5,.5,1,1))
    local mro=pixel("ZML_Bike_MRO",U.Color(0,.65,1,1))
    local materials={}
    local function material(textured,r,g,b,a)
        local key=table.concat({textured,r,g,b,a},",")
        if materials[key] then return materials[key] end
        local mat=own(U.Material(template));mat.name="ZML_Bike_Material"
        local function tex(name,t) if mat:HasProperty(name) then mat:SetTexture(name,t) end end
        local function number(name,value) if mat:HasProperty(name) then mat:SetFloat(name,value) end end
        assert(mat:HasProperty("_BaseColorMap") and mat:HasProperty("_BaseColor"),"native shader contract changed")
        -- Configure GBuffer deferred rendering parameters
        assert(mat:FindPass("HGBuffer")>=0,"native color pass unavailable")
        assert(mat:GetFloat("_UseDeferredRendering")==1,"native deferred contract changed")
        mat:SetShaderPassEnabled("HGBuffer",true)
        tex("_BaseColorMap",textured==1 and texture or white)
        mat:SetTextureScale("_BaseColorMap",U.Vector2(1,1));mat:SetTextureOffset("_BaseColorMap",U.Vector2(0,0))
        mat:SetColor("_BaseColor",U.Color(r,g,b,a))
        tex("_NormalMap",flat);tex("_MacroNormalMap",flat);tex("_MROMap",mro)
        for _,name in ipairs({"_DetailMap","_MaskMap","_EmissiveMap","_ParallaxMap"}) do tex(name,nil) end
        for _,name in ipairs({"_NormalScale","_DetailNormalIntensity","_Layer1BaseNormalIntensity","_UseMacroNormalMap","_UseParallaxMask","_EnableUVAnimation","_UseVertexColorMask"}) do number(name,0) end
        number("_Metallic",0);number("_RoughnessMin",0);number("_RoughnessMax",1)
        if mat:HasProperty("_EmissiveColor") then mat:SetColor("_EmissiveColor",U.Color(0,0,0,1)) end
        materials[key]=mat;return mat
    end
    M.parts={};M.renderers={}
    local branches={}
    local count=u32();assert(count>0 and count<=32,"motorcycle part count")
    for part=1,count do
        local role,nv,ni,textured=u32(),u32(),u32(),u32()
        assert(nv>0 and nv<65536 and ni>0 and ni<=150000 and ni%3==0,"motorcycle mesh counts")
        local pivot,center,extent=v3(),v3(),v3()
        local ux,uy,uw,uh=f32(),f32(),f32(),f32()
        local r,g,b,a=f32(),f32(),f32(),f32()
        local positions,normals,uvs=array(U.Vector3,nv),array(U.Vector3,nv),array(U.Vector2,nv)
        local colors,tangents=array(U.Color,nv),array(U.Vector4,nv)
        local firstPosition,lastPosition
        local tire={}
        for i=0,nv-1 do
            local px,py,pz=read("ToInt16",2),read("ToInt16",2),read("ToInt16",2)
            local packed=read("ToUInt16",2)
            local nx,ny=(packed%256)/255*2-1,math.floor(packed/256)/255*2-1
            local nz=1-math.abs(nx)-math.abs(ny)
            if nz<0 then local ox=nx;nx=(1-math.abs(ny))*(ox>=0 and 1 or -1);ny=(1-math.abs(ox))*(ny>=0 and 1 or -1) end
            local tu,tv=read("ToUInt16",2),read("ToUInt16",2)
            local position=V(center.x+extent.x*px/32767,center.y+extent.y*py/32767,center.z+extent.z*pz/32767)
            positions[i]=position
            if (role==1 or role==2) and textured==1 then
                -- Deduplicate CPU vertices for wheel ground contact tests
                local key=px..":"..py..":"..pz
                tire[key]={x=position.x,y=position.y,z=position.z}
            end
            if i==0 then firstPosition=position end;lastPosition=position
            local normal=V(nx,ny,nz).normalized
            normals[i]=normal
            uvs[i]=U.Vector2(ux+uw*tu/65535,uy+uh*tv/65535)
            colors[i]=U.Color(1,1,1,1)
            -- Generate orthogonal tangents for flat normal mapping
            local reference=math.abs(normal.y)<.9 and V(0,1,0) or V(1,0,0)
            local tangent=V.Cross(reference,normal).normalized
            tangents[i]=U.Vector4(tangent.x,tangent.y,tangent.z,1)
        end
        local indices=array(CS.System.Int32,ni)
        for i=0,ni-1 do local ix=read("ToUInt16",2);assert(ix<nv,"motorcycle index bounds");indices[i]=ix end
        local mesh=own(U.Mesh());mesh.name="ZML_Bike_Mesh_"..part
        mesh.vertices=positions;mesh.normals=normals;mesh.uv=uvs;mesh.uv2=uvs
        mesh.colors=colors;mesh.tangents=tangents
        mesh:SetTriangles(indices,0);mesh:RecalculateBounds()
        assert(mesh.vertexCount==nv and mesh.bounds.size.magnitude>.01,"native mesh upload is empty")
        local vertices=mesh.vertices
        assert(vertices.Length==nv and distance(vertices[0],firstPosition)<.0001 and
            distance(vertices[nv-1],lastPosition)<.0001,"native vertex array write/read mismatch")
        assert(mesh.triangles.Length==ni,"native triangle upload mismatch")
        -- Explicitly submit mesh data to GPU
        mesh:UploadMeshData(false)
        local parent=M.visual.transform
        local localPivot=pivot
        if role>0 then
            local branch=branches[role]
            if not branch then
                local go=newObject("ZML_Bike_Part_"..role);go.layer=M.vehicle.layer
                local bp=M.visual.transform
                if role==2 and branches[3] then bp=branches[3].transform;localPivot=pivot-branches[3].pivot end
                go.transform:SetParent(bp,false);go.transform.localPosition=localPivot
                branch={role=role,transform=go.transform,pivot=pivot,restPosition=copy(localPivot)};branches[role]=branch;M.parts[#M.parts+1]=branch
            end
            parent=branch.transform;localPivot=V(0,0,0)
            if next(tire) then
                branch.tire={};for _,sample in pairs(tire) do branch.tire[#branch.tire+1]=sample end
            end
        end
        local go=cloneVisual(visual,"ZML_Bike_Mesh_"..part)
        go.transform:SetParent(parent,false);go.transform.localPosition=localPivot
        go:GetComponent(typeof(U.MeshFilter)).sharedMesh=mesh
        local renderer=go:GetComponent(typeof(U.MeshRenderer))
        renderer.sharedMaterial=material(textured,r,g,b,a)
        renderer.enabled=true
        M.renderers[#M.renderers+1]=renderer
    end
    assert(at==byteLength,"motorcycle asset trailing bytes")
    report("bundled_model_ready")
end

local function removeSpeeds(lease)
    local remaining={}
    if lease.char==nil or not lease.char:IsValid() then lease.handles={} return end
    for _,h in ipairs(lease.handles) do
        local ok=pcall(function() lease.mover:RemoveOverrideSpeed(h) end)
        if not ok then remaining[#remaining+1]=h end
    end
    lease.handles=remaining
end
local function optionalVector(value)
    if value==nil then return nil end
    -- Nullable<Vector3> value unpack
    local ok,has=pcall(function()return value.HasValue end)
    if ok and has~=nil then return has and value.Value or nil end
    return value
end
-- Cache MoveInput reflection metadata
local function drivePort(input)
    local t=assert(input:GetType(),"native drive type unavailable")
    assert(t.FullName=="Beyond.Gameplay.Core.MoveInput" and not t.IsValueType,"unexpected native movement input type")
    local flags=CS.System.Enum.Parse(typeof(CS.System.Reflection.BindingFlags),"Instance, Public, NonPublic")
    local available=t:GetFields(flags)
    local indexed={}
    for i=0,available.Length-1 do
        local field=available[i]
        indexed[field.Name]=field
    end
    local fields={}
    for _,name in ipairs({"navMoveVector","navMoveClampTarget","pendingNoManualMove","noManualMove"}) do
        local field=assert(t:GetField(name,flags) or indexed[name],"native drive field missing: "..name)
        assert(not field.IsStatic and not field.IsInitOnly and not field.IsLiteral and
            field.DeclaringType.FullName==t.FullName,"invalid drive field: "..name)
        report("drive_field_"..name:lower().."_"..(field.IsPublic and "public" or "nonpublic"))
        local ft=field.FieldType
        assert(ft.IsGenericType and ft:GetGenericTypeDefinition().FullName=="System.Nullable`1",
            "drive field is not nullable: "..name)
        local ga=ft:GetGenericArguments()
        assert(ga.Length==1 and ga[0].FullName=="UnityEngine.Vector3","drive field type drift: "..name)
        fields[name]=field
    end
    local method=assert(t:GetMethod("NavMove",flags),"public NavMove unavailable")
    assert(not method.IsStatic and method.IsPublic and method.ReturnType.FullName=="System.Void","invalid NavMove method")
    local ps=method:GetParameters()
    assert(ps.Length==3 and ps[0].ParameterType.FullName=="UnityEngine.Vector3" and
        ps[1].ParameterType.FullName=="System.Boolean" and ps[2].ParameterType.FullName==fields.navMoveClampTarget.FieldType.FullName,
        "NavMove signature drift")
    assert(ps[2].IsOptional and ps[2].HasDefaultValue,"NavMove requires optional clamp target")
    local nav=assert(input.NavMove,"direct NavMove binding unavailable")
    local port={}
    port.read=function(name) return optionalVector(fields[name]:GetValue(input)) end
    port.clear=function() fields.navMoveVector:SetValue(input,nil) end
    port.nav=function(direction)
        -- Direct NavMove call
        nav(input,direction,false)
    end
    report("drive_direct_nav_ready")
    return port
end
local function sameVector(a,b)
    a=optionalVector(a)
    return a and b and distance(a,b)<.00001
end
local function releaseDrive(lease)
    if not lease.driveOwned then return end
    if not lease.char:IsValid() then lease.driveOwned=false return end
    local ok=pcall(function()
        local port=lease.drivePort
        -- Skip when foreign navigation is active
        if (sameVector(port.read("navMoveVector"),lease.lastCommand) or sameVector(port.read("navMoveVector"),lease.previousCommand)) and
            port.read("navMoveClampTarget")==nil then
            port.clear()
            assert(port.read("navMoveVector")==nil,"native drive release rejected")
        end
        lease.driveOwned=false
    end)
    return ok
end
local function driveFree(port)
    return port.read("pendingNoManualMove")==nil and port.read("noManualMove")==nil
end
local function queueDrive(lease,direction)
    local port=lease.drivePort
    assert(driveFree(port),"scripted movement owns the input")
    if lease.driveOwned then
        assert(sameVector(port.read("navMoveVector"),lease.lastCommand) and port.read("navMoveClampTarget")==nil,
            "foreign navigation owns the input")
    else
        assert(port.read("navMoveVector")==nil and port.read("navMoveClampTarget")==nil,
            "navigation input already in use")
    end
    -- Track lease before invocation
    lease.previousCommand=lease.lastCommand
    lease.driveOwned=true;lease.lastCommand=copy(direction)
    port.nav(direction)
    assert(sameVector(port.read("navMoveVector"),direction) and port.read("navMoveClampTarget")==nil,
        "native drive write/read mismatch")
    lease.previousCommand=nil
end
-- ZML_VEHICLE_FLIGHT
local function releaseCamera(l)
    local cam=l.camera
    if not cam then return end
    local ok=pcall(function()
        -- Restore camera FOV offset
        if live(cam.node) and math.abs(cam.node.runtimeFOVOffset-cam.last)<.001 then
            cam.node.runtimeFOVOffset=cam.original
        end
    end)
    if ok then l.camera=nil end
end
local function clearSpeedFX(l)
    for _,fx in ipairs(l.speedFX or {}) do
        pcall(function() fx.ps:Stop(false,U.ParticleSystemStopBehavior.StopEmittingAndClear) end)
        pcall(function() fx.go:SetActive(false) end)
        pcall(function() fx.go.transform:SetParent(nil,false) end)
        pcall(U.Object.Destroy,fx.go)
    end
    l.speedFX=nil
end
local function ridingCamera(l,dt)
    if M.settings.ride_fov==0 then releaseCamera(l);return end
    if l.cameraBlocked then return end
    local manager=assert(GameInstance.cameraManager,"camera manager unavailable")
    local ctrl=manager:GetMainLevelCameraController()
    if not ctrl or manager.curActiveController~=ctrl then
        releaseCamera(l);return
    end
    local node=assert(ctrl.levelVirtualCamera,"level camera unavailable")
    if l.camera and l.camera.node~=node then releaseCamera(l);if l.camera then return end end
    if not l.camera then
        local original=node.runtimeFOVOffset
        assert(type(original)=="number","native FOV offset unavailable")
        l.camera={node=node,original=original,last=original}
    end
    local cam=l.camera
    if math.abs(node.runtimeFOVOffset-cam.last)>.001 then
        l.camera=nil;l.cameraBlocked=true;report("camera_foreign_change_preserved");return
    end
    local nextValue=damp(cam.last,cam.original+M.settings.ride_fov,dt,3/M.settings.fov_blend)
    -- Track lease state
    cam.last=nextValue;node.runtimeFOVOffset=nextValue
end
local FX_ROOT="assets/beyond/"
local FX_SOURCES={
    {path=FX_ROOT.."dynamicassets/gameplay/effects/prefabs/p_fxmap_common_rollingdust_2101.prefab",name="Smoke_Tuci_01",dust=true,scale=.6},
    {path=FX_ROOT.."arts/effects/map/prefab/decorate/common/p_fxmap_common_windline_01.prefab",name="feng1_di01",scale=.35}}
local function speedFX(l,dt)
    local c=M.settings
    local amount=c.speed_fx and c.speed_fx_intensity*clamp((math.abs(l.velocity or 0)-c.speed_fx_threshold)/3,0,1) or 0
    if amount>0 and not l.speedFX then
        l.speedFX={}
        for _,spec in ipairs(FX_SOURCES) do
            local prefab=assert(M.loader:LoadGameObject(spec.path),"speed effect resource unavailable")
            local all=prefab:GetComponentsInChildren(typeof(U.ParticleSystem),true)
            local source
            for i=0,all.Length-1 do if all[i].gameObject.name==spec.name then
                assert(not source,"ambiguous speed effect branch");source=all[i].gameObject
            end end
            assert(source and source.transform.childCount==0 and source:GetComponents(typeof(U.Component)).Length==3 and
                source:GetComponent(typeof(U.Transform)) and source:GetComponent(typeof(U.ParticleSystemRenderer)),"unsafe speed effect branch")
            for _,point in ipairs({BIKE.rear,BIKE.front}) do
                local go=U.Object.Instantiate(source)
                local fx={go=go,role=point==BIKE.rear and 1 or 2,dust=spec.dust,rotation=source.transform.localRotation,credit=0}
                l.speedFX[#l.speedFX+1]=fx -- Track active particle effect
                go.name="ZML_Bike_SpeedFX";go.layer=M.visual.layer
                go.transform:SetParent(M.visual.transform,false)
                go.transform.localScale=V(spec.scale,spec.scale,spec.scale)
                fx.ps=assert(go:GetComponent(typeof(U.ParticleSystem)),"cloned particles unavailable")
                fx.ps:Stop(false,U.ParticleSystemStopBehavior.StopEmittingAndClear)
                local main=fx.ps.main
                main.playOnAwake=false;main.loop=true;main.maxParticles=64
                main.simulationSpace=spec.dust and U.ParticleSystemSimulationSpace.World or U.ParticleSystemSimulationSpace.Local
                main.scalingMode=U.ParticleSystemScalingMode.Local
                main.startLifetimeMultiplier=spec.dust and .7 or .3
                main.startSpeedMultiplier=spec.dust and .1 or 0
                main.startSizeMultiplier=spec.dust and .9 or 1
                local shape=fx.ps.shape;shape.enabled=false
                -- Configure particle emitters
                local renderer=go:GetComponent(typeof(U.ParticleSystemRenderer));renderer.pivot=V(0,0,0)
                if not spec.dust then renderer.alignment=U.ParticleSystemRenderSpace.Local end
                local emission=fx.ps.emission;emission.enabled=false
                fx.ps:Play(false)
            end
        end
        report("speed_effects_ready")
    end
    for _,fx in ipairs(l.speedFX or {}) do
        local wheel
        for _,part in ipairs(M.parts) do if part.role==fx.role then wheel=part end end
        assert(wheel,"speed effect wheel unavailable")
        local point=wheel.transform.position
        if fx.dust then
            local plane=l.contactPlanes and l.contactPlanes[fx.role]
            local normal=Q.Inverse(wheel.transform.rotation)*(plane and plane.normal or V(0,1,0))
            local support,best=math.huge
            for _,sample in ipairs(wheel.tire) do
                local height=sample.x*normal.x+sample.y*normal.y+sample.z*normal.z
                if height<support then support=height;best=sample end
            end
            assert(best,"speed effect tread unavailable")
            point=wheel.transform:TransformPoint(V(best.x,best.y,best.z))+(plane and plane.normal or V(0,1,0))*.04
        end
        fx.go.transform.position=point
        local yaw=l.bikeYaw+(fx.role==2 and l.geometry.roadAngle or 0)+(l.velocity<0 and 180 or 0)
        fx.go.transform.rotation=Q.Euler(0,yaw,0)*fx.rotation
        local rate=amount*(fx.dust and not l.airborne and 24 or not fx.dust and 16 or 0)
        fx.credit=rate>0 and math.min(4,fx.credit+rate*dt) or 0
        local count=math.floor(fx.credit)
        if count>0 then fx.ps:Emit(count);fx.credit=fx.credit-count end
    end
end
local function ridingExtras(l,dt)
    if l.cameraFailed then releaseCamera(l) end
    if not l.cameraFailed then
        local ok,err=pcall(ridingCamera,l,dt)
        if not ok then l.cameraFailed=true;releaseCamera(l);warnEvent("riding_camera_unavailable",err) end
    end
    if not l.speedFXFailed then
        local ok,err=pcall(speedFX,l,dt)
        if not ok then clearSpeedFX(l);l.speedFXFailed=true;warnEvent("speed_effect_unavailable",err) end
    end
end
local function restore(lease)
    if not lease then return end
    -- Restore captured bones
    for _,b in ipairs(lease.bones) do
        pcall(function()
            if live(b.node) then b.node.localPosition=b.position; b.node.localRotation=b.rotation end
        end)
    end
    pcall(function() if live(lease.grounder) then lease.grounder.enabled=lease.grounderEnabled end end)
    pcall(Flight.release,lease)
    removeSpeeds(lease)
    releaseDrive(lease)
    releaseCamera(lease);clearSpeedFX(lease)
    if #lease.handles>0 or lease.driveOwned or lease.camera or lease.flight then M.pending[#M.pending+1]=lease; warnEvent("cleanup_retry") end
end
local function retryCleanup()
    for i=#M.pending,1,-1 do
        pcall(Flight.release,M.pending[i])
        removeSpeeds(M.pending[i])
        releaseDrive(M.pending[i])
        releaseCamera(M.pending[i])
        if #M.pending[i].handles==0 and not M.pending[i].driveOwned and not M.pending[i].camera and not M.pending[i].flight then table.remove(M.pending,i) end
    end
end
local function wheelParts()
    local rear,front
    for _,part in ipairs(M.parts or {}) do
        if part.role==1 then rear=part elseif part.role==2 then front=part end
    end
    assert(rear and front and rear.tire and front.tire,"owned tyre contact unavailable")
    return rear,front
end
local function floorPlane(mover,pos)
    local ok,point,normal=pcall(function()
        local floor=mover.currentFloor
        if floor and floor.isHit and floor.walkableFloor then return floor.floorHit.point,floor.floorHit.normal end
    end)
    if ok and point and normal and normal.y>.45 and math.abs(point.y-pos.y)<.65 then
        return {point=copy(point),normal=normal.normalized}
    end
    return {point=copy(pos),normal=V(0,1,0),rootFallback=true}
end
local function groundPlane(mover,pos,wheel,fallback)
    local ok,plane=pcall(function()
        M.groundHits=M.groundHits or CS.System.Array.CreateInstance(typeof(U.RaycastHit),8)
        local origin=wheel.transform.position
        origin=V(origin.x,pos.y+.8,origin.z)
        local count=U.Physics.RaycastNonAlloc(origin,V(0,-1,0),M.groundHits,1.45,
            mover:GetFloorLayerMask().value,U.QueryTriggerInteraction.Ignore)
        -- Fallback to native floor when buffer is saturated
        if count>=8 then return nil end
        local best
        for i=0,count-1 do
            local hit=M.groundHits[i]
            local point,normal=hit.point,hit.normal
            if (not hit.collider or foreignCollider(hit.collider)) and normal.y>.45 and math.abs(point.y-pos.y)<.65 and
                (not best or point.y>best.point.y) then best={point=copy(point),normal=normal.normalized} end
        end
        return best
    end)
    if not ok and not M.groundQueryReported then
        M.groundQueryReported=true;report("ground_query_unavailable_native_floor_fallback")
    end
    local selected=ok and plane or fallback
    if selected.rootFallback and not M.rootGroundReported then
        M.rootGroundReported=true;report("ground_root_plane_fallback")
    end
    return selected
end
local function tireGap(part,plane,scale)
    local normal=Q.Inverse(part.transform.rotation)*plane.normal
    local support=math.huge
    for _,sample in ipairs(part.tire) do
        support=math.min(support,sample.x*normal.x+sample.y*normal.y+sample.z*normal.z)
    end
    return (dot(part.transform.position-plane.point,plane.normal)+support*scale)/plane.normal.y
end
local function seatVehicle(mover,pos,heading,bank,pitch,bob)
    local rear,front=wheelParts()
    rear.transform.localPosition=rear.restPosition;front.transform.localPosition=front.restPosition
    M.visual.transform.localPosition=V(0,0,0)
    local frame=heading*Q.Euler(0,M.settings.model_yaw,0)
    local undo=Q.Euler(0,-M.settings.model_yaw,0)
    if M.lease and M.lease.airborne then
        -- Follow native jump/fall trajectory
        M.vehicle.transform:SetPositionAndRotation(pos+V(0,M.lease.rideHeight or 0,0),frame*Q.Euler(pitch,0,bank)*undo)
        return 0,{}
    end
    M.vehicle.transform:SetPositionAndRotation(pos,frame*Q.Euler(0,0,bank)*undo)
    local fallback=floorPlane(mover,pos)
    local rp=groundPlane(mover,pos,rear,fallback)
    local fp=groundPlane(mover,pos,front,fallback)
    if M.lease then M.lease.contactPlanes={rp,fp} end
    local terrainPitch=0
    -- Calculate ground contact plane for both tyres
    for i=1,3 do
        local rg,fg=tireGap(rear,rp,M.settings.scale),tireGap(front,fp,M.settings.scale)
        local span=math.max(.5,(front.transform.position-rear.transform.position).magnitude)
        terrainPitch=clamp(terrainPitch+math.deg(math.atan((fg-rg)/span)),-28,28)
        M.vehicle.transform.rotation=frame*Q.Euler(terrainPitch,0,bank)*undo
    end
    M.vehicle.transform.rotation=frame*Q.Euler(terrainPitch+pitch,0,bank)*undo
    local rg,fg=tireGap(rear,rp,M.settings.scale),tireGap(front,fp,M.settings.scale)
    M.vehicle.transform.position=pos+V(0,-(rg+fg)*.5+(bob or 0),0)
    -- Suspension stroke adjustment
    for _,item in ipairs({{rear,rp},{front,fp}}) do
        local part,plane=item[1],item[2]
        local gap=tireGap(part,plane,M.settings.scale)
        part.transform.position=part.transform.position+V(0,clamp(-gap,-.16,.16),0)
    end
    if M.lease then M.lease.rideHeight=M.vehicle.transform.position.y-pos.y end
    return terrainPitch,{rear=tireGap(rear,rp,M.settings.scale),front=tireGap(front,fp,M.settings.scale)}
end
local function settleParked()
    if not M.vehicle or M.lease then return end
    local ch,pc,mover=character()
    if ch and groundAllowed(mover) then
        seatVehicle(mover,M.vehicle.transform.position,M.vehicle.transform.rotation,0,0,0)
    end
end
function M.unmount()
    local lease=M.lease
    M.lease=nil
    if lease then M.collisionArmed=nil end
    if M.vehicle then M.phase="parked" else M.phase="absent" end
    for _,part in ipairs(M.parts or {}) do
        pcall(function() if live(part.transform) then part.transform.localRotation=Q.identity end end)
    end
    if lease and live(M.vehicle) and live(lease.root.transform) then
        pcall(function()
            M.vehicle.transform:SetPositionAndRotation(lease.root.transform.position,lease.root.transform.rotation)
            setScale()
            seatVehicle(lease.mover,lease.root.transform.position,lease.root.transform.rotation,0,0,0)
        end)
    end
    if lease then restore(lease); report("dismounted") end
end
function M.dismiss()
    M.unmount(true)
    destroyVehicle()
    report("dismissed")
end
local function fail(event,err)
    M.faulted=true -- Mark faulted state
    M.unmount(true)
    M.removeInteraction();M.finishPresentation();M.requestedToggle=nil
    warnEvent(event,err)
    notice("摩托车操作异常，已恢复角色状态")
end
function M.summon()
    if M.presentation then return end
    if M.phase=="mounted" then return end
    local ch,pc,mover,root=character()
    if not ch or not gameAllowed(pc) or not groundAllowed(mover) or #M.pending>0 then
        report("summon_blocked") return
    end
    -- Spawn vehicle at player position
    if M.vehicle then
        M.vehicle.transform:SetPositionAndRotation(root.transform.position,root.transform.rotation)
        setScale();seatVehicle(mover,root.transform.position,root.transform.rotation,0,0,0);M.beginPresentation(false);return
    end
    local ok,err=pcall(function()
        M.loader=require_ex("Common/Utils/LuaResourceLoader").LuaResourceLoader()
        report("model_loader_ready")
        local material=assert(M.loader:LoadMaterial(MATERIAL),"native shader template unavailable")
        report("model_material_loaded")
        M.vehicle=newObject("ZML_Motorcycle")
        -- Place visual mesh on default world layer
        local layer=CS.Beyond.Gameplay.LayerDef.DEFAULT_LAYER
        assert(type(layer)=="number" and layer>=0 and layer<32,"native world layer unavailable")
        M.vehicle.layer=layer
        U.SceneManagement.SceneManager.MoveGameObjectToScene(M.vehicle,root.gameObject.scene)
        M.visual=newObject("ZML_Bike_Model")
        M.visual.layer=M.vehicle.layer
        M.visual.transform:SetParent(M.vehicle.transform,false)
        M.renderTemplate=visualTemplate()
        buildModel(material,M.renderTemplate)
        M.createCollision()
        setScale()
        M.vehicle.transform:SetPositionAndRotation(root.transform.position,root.transform.rotation)
        seatVehicle(mover,root.transform.position,root.transform.rotation,0,0,0)
        report("model_world_layer_"..layer)
        M.phase="parked"
    end)
    if not ok then destroyVehicle();warnEvent("model_load_failed",err);notice("摩托车模型加载失败") return end
    M.beginPresentation(false)
    report("summoned")
end
local boneNames={"pelvis","leftThigh","leftCalf","leftFoot","rightThigh","rightCalf","rightFoot",
    "leftUpperArm","leftForearm","leftHand","rightUpperArm","rightForearm","rightHand","head"}
local humanNames={pelvis="Hips",leftThigh="LeftUpperLeg",leftCalf="LeftLowerLeg",leftFoot="LeftFoot",
    rightThigh="RightUpperLeg",rightCalf="RightLowerLeg",rightFoot="RightFoot",
    leftUpperArm="LeftUpperArm",leftForearm="LeftLowerArm",leftHand="LeftHand",
    rightUpperArm="RightUpperArm",rightForearm="RightLowerArm",rightHand="RightHand",head="Head"}
local function captureRig(ch,mover,root)
    local anim=assert(ch.animatorCom and ch.animatorCom.animator,"character animator unavailable")
    assert(live(anim),"character animator destroyed")
    local grounder=ch.characterAnimCom and ch.characterAnimCom.grounderIK
    local refs=grounder and grounder.ik and grounder.ik.references
    local lease={char=ch,mover=mover,root=root,animator=anim,
        grounder=grounder,grounderEnabled=grounder and grounder.enabled,bones={},rig={},handles={},braking=false,
        spines={},base={},segments={},hipOffsets={},handAxes={},footPads={},fingers={}}
    local seen={}
    local function snapshot(name,node)
        assert(live(node),"rider rig contract incomplete")
        lease.rig[name]=node
        if not seen[node] then
            seen[node]=true
            lease.bones[#lease.bones+1]={node=node,position=copy(node.localPosition),rotation=node.localRotation}
        end
        lease.base[name]=Q.Inverse(root.transform.rotation)*node.rotation
    end
    for _,name in ipairs(boneNames) do
        local node=refs and refs[name]
        if not live(node) and anim.isHuman then node=anim:GetBoneTransform(U.HumanBodyBones[humanNames[name]]) end
        snapshot(name,node)
    end
    local spine=refs and refs.spine
    if spine and spine.Length>0 then
        assert(spine.Length<=8,"unexpected spine chain")
        for i=0,spine.Length-1 do snapshot("spine"..i,spine[i]);lease.spines[#lease.spines+1]=spine[i] end
    elseif anim.isHuman then
        for _,name in ipairs({"Spine","Chest","UpperChest"}) do
            local node=anim:GetBoneTransform(U.HumanBodyBones[name])
            if live(node) then snapshot("spine"..#lease.spines,node);lease.spines[#lease.spines+1]=node end
        end
    end
    assert(#lease.spines>0,"rider spine unavailable")
    lease.rig.spine=lease.spines[1]
    -- Capture clavicle and neck transforms
    for _,side in ipairs({"left","right"}) do
        local node=lease.rig[side.."UpperArm"].parent
        if live(node) and not seen[node] then snapshot(side.."Clavicle",node) end
    end
    local neck=lease.rig.head.parent
    if live(neck) and not seen[neck] then snapshot("neck",neck) end
    local r=lease.rig
    lease.hipRelative=Q.Inverse(root.transform.rotation)*r.pelvis.rotation
    for _,side in ipairs({"left","right"}) do
        for _,limb in ipairs({{"Thigh","Calf","Foot","Leg"},{"UpperArm","Forearm","Hand","Arm"}}) do
            local a,b,c=r[side..limb[1]],r[side..limb[2]],r[side..limb[3]]
            local l1,l2=distance(a.position,b.position),distance(b.position,c.position)
            assert(l1>0.02 and l2>0.02 and l1<2 and l2<2,"rider proportions invalid")
            lease[side..limb[4]]={a=a,b=b,c=c,l1=l1,l2=l2}
        end
        local inv=Q.Inverse(root.transform.rotation)
        lease.handAxes[side]=inv*(r[side.."Hand"].position-r[side.."Forearm"].position).normalized
        lease.footPads[side]=clamp((inv*(r[side.."Foot"].position-root.transform.position)).y,.07,.18)
        local delta=inv*(r[side.."Thigh"].position-r.pelvis.position)
        lease.hipOffsets[side]={delta.x,delta.y,delta.z}
        local previous=r.pelvis.position
        local segments={}
        for i,node in ipairs(lease.spines) do
            delta=inv*(node.position-previous)
            segments[#segments+1]={delta.x,delta.y,delta.z,.25+.75*(i-1)/#lease.spines}
            previous=node.position
        end
        delta=inv*(r[side.."UpperArm"].position-previous)
        segments[#segments+1]={delta.x,delta.y,delta.z,1}
        lease.segments[side]=segments
        local hand=r[side.."Hand"]
        local chains={}
        assert(hand.childCount<=32,"unexpected hand hierarchy")
        for i=0,hand.childCount-1 do
            local node=hand:GetChild(i)
            local number=tonumber(tostring(node.name):match("[Ff]inger([0-4])$"))
            if number then
                local chain={};local current=node
                for index=1,3 do
                    local nextNode
                    for k=0,current.childCount-1 do
                        local child=current:GetChild(k)
                        if tostring(child.name):find("[Ff]inger") then nextNode=child break end
                    end
                    if not nextNode then break end
                    local direction=nextNode.position-current.position
                    if direction.sqrMagnitude<.000001 then break end
                    snapshot(side.."Finger"..number.."_"..index,current)
                    local down=root.transform.rotation*V(0,-1,0)
                    local axis=V.Cross(direction,down)
                    if axis.sqrMagnitude>.000001 then
                        chain[#chain+1]={node=current,rotation=current.localRotation,
                            axis=Q.Inverse(current.rotation)*axis.normalized,
                            angle=number==0 and ({25,35,20})[index] or ({35,65,50})[index]}
                    end
                    current=nextNode
                end
                if #chain>0 then chains[#chains+1]=chain end
            end
        end
        lease.fingers[side]=chains
    end
    lease.previousPosition=copy(root.transform.position)
    return lease
end
-- Calculate rider seat offset based on torso and shoulder dimensions
local function rotateOffset(v,angle,yaw,roll)
    local a,y=math.rad(angle),math.rad(yaw)
    local r=math.rad(roll or 0)
    local vx,vy=v[1]*math.cos(r)-v[2]*math.sin(r),v[1]*math.sin(r)+v[2]*math.cos(r)
    local cy,sy=math.cos(y),math.sin(y)
    local yy=vy*math.cos(a)-v[3]*math.sin(a)
    local zz=vy*math.sin(a)+v[3]*math.cos(a)
    return vx*cy+zz*sy,yy,-vx*sy+zz*cy
end
local function contactPoints(l,c,steer)
    local points={}
    local pivot=BIKE.steerPivot
    local rotation=forkRotation(steer)
    for _,side in ipairs({"left","right"}) do
        local sign=side=="left" and -1 or 1
        local arm=l[side.."Arm"];local leg=l[side.."Leg"]
        -- Align wrist target with handlebar grip
        local width=.32+.055*clamp((arm.l1+arm.l2-.37)/.19,0,1)
        local point=pivot+rotation*(V(sign*width,1.065,.34)-pivot)
        points[side.."Arm"]={point.x*c.scale,point.y*c.scale,point.z*c.scale}
        -- Foot placement relative to footpeg coordinates
        points[side.."Leg"]={sign*.28*c.scale,.32*c.scale+l.footPads[side],-.245*c.scale}
    end
    return points
end
local function planPose(l,c,steer,drive,neutral,corner)
    local points=contactPoints(l,c,steer)
    local legs=(l.leftLeg.l1+l.leftLeg.l2+l.rightLeg.l1+l.rightLeg.l2)*.5
    local arms=(l.leftArm.l1+l.leftArm.l2+l.rightArm.l1+l.rightArm.l2)*.5
    local preferZ=neutral and neutral.z or clamp(-.11-(legs-.71)*.55,-.245,-.065)
    local preferAngle=(neutral and neutral.angle or clamp(30+(.56-arms)*155,30,64))+drive
    -- Counter-twist the shoulders toward the farther grip; turning the whole
    -- forward-bent torso with the fork pulls short arms away from that grip.
    local yaw=-steer*.8
    -- Move the hips INSIDE the corner and lean the upper body independently.
    -- Scale hang-off distance with arm length
    local roll=(corner or 0)*clamp((arms-.35)/.25,.2,1)
    local shift=-roll/5*.035
    local lowZ,highZ=neutral and math.max(-.27,preferZ-.10) or -.27,neutral and math.min(.04,preferZ+.14) or .04
    local lowA,highA=neutral and math.max(20,preferAngle-20) or 20,neutral and math.min(82,preferAngle+40) or 82
    local best
    local function candidate(z,angle)
        local surface=math.max(c.seat_height,.812+math.max(0,-z-.25)*.90)
        local height=surface*c.scale+clamp(.11+(legs-.84)*.16,.085,.15)
        local score=((z-preferZ)/.07)^2+((angle-preferAngle)/14)^2
        local error=0
        for _,side in ipairs({"left","right"}) do
            local sx,sy,sz=0,0,0
            for _,v in ipairs(l.segments[side]) do
                local x,y,zz=rotateOffset(v,angle*v[4],yaw*v[4],roll*v[4])
                sx,sy,sz=sx+x,sy+y,sz+zz
            end
            local hx,hy,hz=rotateOffset(l.hipOffsets[side],angle*.25,yaw*.25,roll*.25)
            for _,limb in ipairs({{"Arm",sx,sy,sz},{"Leg",hx,hy,hz}}) do
                local chain=l[side..limb[1]];local target=points[side..limb[1]]
                local x,y,zz=shift+limb[2]-target[1],height+limb[3]-target[2],z*c.scale+limb[4]-target[3]
                local d=math.sqrt(x*x+y*y+zz*zz)
                local maxLength=(chain.l1+chain.l2)*.965
                local e=math.max(0,d-maxLength,math.abs(chain.l1-chain.l2)+.005-d)
                score=score+(e/.01)^2*1000;error=math.max(error,e)
            end
        end
        if not best or score<best.score then best={x=shift,roll=roll,z=z,angle=angle,height=height,yaw=yaw,score=score,error=error,points=points} end
    end
    for z=lowZ,highZ,.015 do for a=lowA,highA,3 do candidate(z,a) end end
    -- Refine seating posture
    for _,step in ipairs({.0075,.00375,.001875}) do
        local z,angle=best.z,best.angle
        for dz=-1,1 do for da=-1,1 do candidate(clamp(z+dz*step,lowZ,highZ),clamp(angle+da*step*160,lowA,highA)) end end
    end
    return best
end
local function fitConfiguration(l,c)
    local adjusted={}
    for key,value in pairs(c) do adjusted[key]=value end
    -- Adapt rider seat position and torso lean angle to vehicle scale
    local plan=planPose(l,adjusted,0,0)
    assert(plan.error<.001,"configured bike outside rider reach; adjust model scale")
    local function steeringReach(angle)
        local reach=0
        for _,steer in ipairs({-angle,angle}) do
            for _,drive in ipairs({0,8}) do
                for _,corner in ipairs({-5,0,5}) do
                    reach=math.max(reach,planPose(l,adjusted,steer,drive,plan,corner).error)
                end
            end
        end
        return reach<.001
    end
    -- Clamp fork angle within reachable range for short arms
    local limit=c.max_steer
    if not steeringReach(limit) then
        local low,high=0,limit
        assert(steeringReach(0),"configured bike outside dynamic rider reach")
        for i=1,7 do
            local mid=(low+high)*.5
            if steeringReach(mid) then low=mid else high=mid end
        end
        limit=low*.98
    end
    l.maxSteer=limit
    local previous=l.steer or 0
    l.steer=clamp(previous,-limit,limit)
    if l.steer~=previous then l.steerVelocity=0 end
    l.geometry=turnGeometry(c.scale,l.steer)
    l.ridingConfig=adjusted;l.neutral=plan
    l.configScale=c.scale;l.configSeat=c.seat_height;l.configSteer=c.max_steer
end
local function speed(lease,braking)
    lease.braking=braking
    local c=M.settings
    local desired=braking and 0 or (lease.throttle or 0)<0 and math.min(c.speed,3) or c.speed
    local accel=lease.collisionBlocked and 96 or braking and math.max(12,c.acceleration) or c.acceleration
    if lease.speed==desired and lease.speedAccel==accel then return end
    -- Update speed override handle
    local h=lease.mover:SetOverrideSpeed(desired,accel)
    lease.handles[#lease.handles+1]=h
    local old={}
    for i=1,#lease.handles-1 do old[#old+1]=lease.handles[i] end
    for _,key in ipairs(old) do
        lease.mover:RemoveOverrideSpeed(key)
        for i=#lease.handles,1,-1 do if lease.handles[i]==key then table.remove(lease.handles,i) break end end
    end
    lease.speed,lease.speedAccel=desired,accel
end
local function control(lease,pc,dt)
    if lease.flight then Flight.step(lease,dt);return end
    if lease.airborne then queueDrive(lease,V(0,0,0));return end
    local c=lease.ridingConfig
    local raw=assert(pc.rawMoveAxis,"native raw move axis unavailable")
    local x,y=clamp(raw.x,-1,1),clamp(raw.y,-1,1)
    if not (M.owner and M.owner.isControllerPanel) then
        x=(keyActions.right.down() and 1 or 0)-(keyActions.left.down() and 1 or 0)
        y=(keyActions.forward.down() and 1 or 0)-(keyActions.reverse.down() and 1 or 0)
    end
    if math.abs(x)<.08 then x=0 end;if math.abs(y)<.08 then y=0 end
    lease.throttle=y
    -- Scale high-speed steering budget based on fork travel
    local lateralBudget=3*lease.maxSteer/22
    local speedLimit=math.min(lease.maxSteer,math.deg(math.atan((BIKE.front.z-BIKE.rear.z)*c.scale*lateralBudget/
        math.max((lease.velocity or 0)^2,1))))
    -- Apply speed steer reduction
    local limit=lease.maxSteer+(speedLimit-lease.maxSteer)*M.settings.speed_steer_reduction
    lease.steer,lease.steerVelocity=spring(lease.steer or 0,lease.steerVelocity or 0,x*limit,dt,12)
    lease.steer=clamp(lease.steer,-lease.maxSteer,lease.maxSteer)
    lease.geometry=turnGeometry(c.scale,lease.steer)
    -- Dispatch root motion tangent vector to native navigation
    local predictor=(lease.velocity or 0)*lease.geometry.curvature*dt*.5
    local yaw=lease.bikeYaw+math.deg(lease.geometry.beta+predictor)
    lease.motionDirection=Q.Euler(0,yaw,0)*V(0,0,1)
    y=M.collisionThrottle(lease,y,dt)
    speed(lease,lease.collisionBlocked or keyActions.brake.down())
    queueDrive(lease,lease.motionDirection*(lease.braking and 0 or y))
end
function M.mount()
    if M.phase=="mounted" then M.unmount(false) return end
    if not M.vehicle then return end
    if M.phase~="parked" or M.presentation then return end
    local ch,pc,mover,root=character()
    if not ch or not gameAllowed(pc) or not groundAllowed(mover) or #M.pending>0 then
        report("mount_blocked") return
    end
    if distance(root.transform.position,M.vehicle.transform.position)>3.5 then return end
    local lease
    local ok,err=pcall(function()
        lease=captureRig(ch,mover,root) -- Capture character rig
        fitConfiguration(lease,M.settings)
        lease.input=assert(mover.input,"native movement input unavailable")
        lease.drivePort=drivePort(lease.input)
        assert(driveFree(lease.drivePort),"scripted movement input occupied")
        assert(lease.drivePort.read("navMoveVector")==nil and lease.drivePort.read("navMoveClampTarget")==nil,
            "navigation input already in use")
        -- Verify navigation field cleanup binding
        lease.drivePort.clear()
        assert(lease.drivePort.read("navMoveVector")==nil,"native empty drive release rejected")
        report("drive_release_preflight_ready")
        lease.bikeYaw=root.transform.rotation.eulerAngles.y+M.settings.model_yaw
        lease.configModelYaw=M.settings.model_yaw
        lease.groundY=root.transform.position.y;lease.airTime=0;lease.airborne=false
        lease.geometry=turnGeometry(lease.ridingConfig.scale,0)
        lease.motionDirection=Q.Euler(0,lease.bikeYaw,0)*V(0,0,1)
        M.lease=lease
        queueDrive(lease,V(0,0,0))
        M.vehicle.transform:SetPositionAndRotation(root.transform.position,root.transform.rotation)
        -- Adapt final rendered skeleton pose in TailTick
        if live(lease.grounder) then lease.grounder.enabled=false end
        speed(lease,false)
        M.phase="mounted"
        M.removeInteraction();M.syncCollision()
        setScale()
    end)
    if not ok then fail("mount_failed",err) return end
    report("mounted")
end
-- Analytic two-bone IK solver for limbs
local function solve(chain,target,pole)
    local a,b,c=chain.a,chain.b,chain.c
    local delta=target-a.position
    local d=delta.magnitude
    if d<0.0001 then return end
    local dir=delta/d
    local length=clamp(d,math.abs(chain.l1-chain.l2)+0.001,chain.l1+chain.l2-0.001)
    local reachable=a.position+dir*length
    local projected=pole-dir*dot(pole,dir)
    if projected.sqrMagnitude<0.00001 then projected=V.Cross(dir,V(0,0,1)) end
    if projected.sqrMagnitude<0.00001 then projected=V.Cross(dir,V(1,0,0)) end
    projected=projected.normalized
    local x=(chain.l1*chain.l1-chain.l2*chain.l2+length*length)/(2*length)
    local height=math.sqrt(math.max(0,chain.l1*chain.l1-x*x))
    local knee=a.position+dir*x+projected*height
    a.rotation=Q.FromToRotation(b.position-a.position,knee-a.position)*a.rotation
    b.rotation=Q.FromToRotation(c.position-b.position,reachable-b.position)*b.rotation
end
local function visual(dt)
    local l=M.lease
    if not l then return end
    local ch,pc,mover,root=character()
    if ch~=l.char or not ch or not gameAllowed(pc) or not rideTerrain(l,mover,0) or not live(M.vehicle) then M.unmount(true) return end
    dt=clamp(dt,0,.1)
    for _,b in ipairs(l.bones) do b.node.localPosition=b.position; b.node.localRotation=b.rotation end
    if l.configScale~=M.settings.scale or l.configSeat~=M.settings.seat_height or l.configSteer~=M.settings.max_steer then
        fitConfiguration(l,M.settings)
        setScale()
    end
    local c=l.ridingConfig
    c.speed=M.settings.speed
    if l.configModelYaw~=M.settings.model_yaw then
        l.bikeYaw=l.bikeYaw+U.Mathf.DeltaAngle(l.configModelYaw,M.settings.model_yaw)
        l.configModelYaw=M.settings.model_yaw
    end
    local pos=root.transform.position
    local delta=pos-(l.previousPosition or pos)
    local vertical=delta.y/math.max(dt,.008)
    delta=V(delta.x,0,delta.z)
    l.previousPosition=copy(pos)
    local travel=delta.magnitude
    -- Compute travel distance from collision-resolved movement
    local discontinuity=travel>math.max(.5,c.speed*dt*3)
    if discontinuity then
        travel=0;delta=V(0,0,0)
        l.lean,l.leanVelocity,l.steer,l.steerVelocity=0,0,0,0
        l.velocity,l.accel,l.pitch,l.drive=0,0,0,0
        vertical=0;l.jumpPitch,l.jumpPitchVelocity=0,0
        l.groundSamples={};l.groundMomentum=V(0,0,0)
    end
    if not l.airborne and dt>.001 then
        l.groundSamples=l.groundSamples or {}
        local samples=l.groundSamples;samples[#samples+1]={delta=delta,dt=dt}
        local total,elapsed=V(0,0,0),0
        for _,sample in ipairs(samples) do total=total+sample.delta;elapsed=elapsed+sample.dt end
        while #samples>1 and elapsed-samples[1].dt>=.1 do
            total=total-samples[1].delta;elapsed=elapsed-samples[1].dt;table.remove(samples,1)
        end
        l.groundMomentum=total/math.max(elapsed,.001)
    end
    -- Project displacement onto motion tangent
    local signed=dot(delta,l.motionDirection)
    local g=l.geometry or turnGeometry(c.scale,l.steer or 0)
    -- Maintain momentum during vehicle flight
    local yawStep=l.airborne and 0 or signed*g.curvature
    l.bikeYaw=U.Mathf.DeltaAngle(0,l.bikeYaw+math.deg(yawStep))
    l.yawRate=yawStep/math.max(dt,.008)
    local measured=signed/math.max(dt,.008)
    local oldVelocity=l.velocity or 0
    l.velocity=damp(oldVelocity,measured,dt,10)
    l.accel=damp(l.accel or 0,clamp((l.velocity-oldVelocity)/math.max(dt,.008),-16,16),dt,7)
    -- Centripetal roll banking in turns
    local desired=-clamp(math.deg(math.atan(l.velocity*l.yawRate/9.81)),-20,20)
    l.lean,l.leanVelocity=spring(l.lean or 0,l.leanVelocity or 0,desired,dt,9)
    l.lean=clamp(l.lean,-20,20)
    l.pitch=damp(l.pitch or 0,clamp(-l.accel*.22,-2.5,2.5),dt,6)
    local jumpTarget=l.airborne and -M.settings.jump_pitch*clamp(vertical/(l.jumpUp or 6),-1,1) or 0
    l.jumpPitch,l.jumpPitchVelocity=spring(l.jumpPitch or 0,l.jumpPitchVelocity or 0,jumpTarget,dt,10)
    if not l.airborne then
        -- Smooth suspension landing recovery
        l.jumpPitch=clamp(l.jumpPitch,-2,2)
    end
    l.drive=damp(l.drive or 0,clamp(math.abs(l.velocity)/10*4+math.abs(l.accel)*.32,0,8),dt,5)
    -- Update body yaw from resolved displacement curvature
    local heading=Q.Euler(0,l.bikeYaw-M.settings.model_yaw,0)
    l.travel=(l.travel or 0)+travel
    l.rearAngle=((l.rearAngle or 0)+signed*g.rearFactor/(BIKE.rearRadius*c.scale)*180/math.pi)%360
    l.frontAngle=((l.frontAngle or 0)+signed*g.frontFactor/(BIKE.frontRadius*c.scale)*180/math.pi)%360
    for _,part in ipairs(M.parts or {}) do
        if part.role==1 then part.transform.localRotation=Q.AngleAxis(l.rearAngle,V(1,0,0))
        elseif part.role==2 then part.transform.localRotation=Q.AngleAxis(l.frontAngle,V(1,0,0))
        elseif part.role==3 then part.transform.localRotation=forkRotation(l.steer or 0)
        elseif part.role==4 then part.transform.localRotation=Q.Euler(0,0,70) end
    end
    local t=M.visual.transform
    local bob=clamp(math.abs(l.velocity)/10,0,1)*.002*math.sin(l.travel*7)
    l.terrainPitch,l.groundGaps=seatVehicle(mover,pos,heading,l.lean,l.pitch+l.jumpPitch,bob)
    local pose=planPose(l,c,l.steer or 0,l.drive,l.neutral,clamp(l.lean*.25,-5,5))
    assert(pose.error<.025,"dynamic rider reach unavailable")
    l.pose=pose
    local function target(x,y,z) return t:TransformPoint(V(x,y,z)) end
    local r=l.rig
    -- Planner numbers are metres; TransformPoint on the already-scaled visual
    -- requires conversion back to model space (no double-scaling body lengths).
    r.pelvis.position=target(pose.x/c.scale,pose.height/c.scale,pose.z)
    r.pelvis.rotation=t.rotation*Q.Euler(pose.angle*.25,pose.yaw*.25,pose.roll*.25)*l.base.pelvis
    for i,node in ipairs(l.spines) do
        local weight=.25+.75*i/#l.spines
        node.rotation=t.rotation*Q.Euler(pose.angle*weight,pose.yaw*weight,pose.roll*weight)*l.base["spine"..(i-1)]
    end
    r.head.rotation=t.rotation*Q.Euler(-pose.angle*.05,pose.yaw*.25+(l.steer or 0)*.35,-pose.roll*.4)*l.base.head
    l.targets={}
    for _,side in ipairs({"left","right"}) do
        local sign=side=="left" and -1 or 1
        for _,kind in ipairs({"Leg","Arm"}) do
            local v=pose.points[side..kind];local point=target(v[1]/c.scale,v[2]/c.scale,v[3]/c.scale)
            l.targets[side..kind]=point
            -- Align knee pole target forward along the tank
            local pole=kind=="Leg" and (t.forward+t.right*(sign*.12)) or (-t.forward*.45+t.right*(sign*.8)-t.up*.3)
            solve(l[side..kind],point,pole)
        end
        r[side.."Foot"].rotation=t.rotation*l.base[side.."Foot"]
        -- Rotate wrist rotation to align with handlebar grip
        local barRotation=t.rotation*forkRotation(l.steer or 0)
        r[side.."Hand"].rotation=Q.FromToRotation(barRotation*l.handAxes[side],barRotation*V(0,0,1))*barRotation*l.base[side.."Hand"]
        for _,chain in ipairs(l.fingers[side]) do for _,finger in ipairs(chain) do
            finger.node.localRotation=finger.rotation*Q.AngleAxis(finger.angle,finger.axis)
        end end
    end
    ridingExtras(l,dt)
end
local function tick(dt)
    dt=clamp(dt or 1/60,0,.1)
    retryCleanup()
    if M.interactRemovalPending then M.removeInteraction() end
    if M.faulted or not M.settings or not M.settings.enabled or #M.pending>0 then return end
    if not M.tickSeen then M.tickSeen=true;report("tick_active") end
    if not U.Application.isFocused or typing() then M.removeInteraction();M.unmount(true);M.finishPresentation();M.requestedToggle=nil;return end
    local dismount=keyActions.dismount.pressed()
    local jump=keyActions.jump.pressed()
    local action
    -- Keybind and interaction handling
    if M.phase=="mounted" and dismount then action="dismount" end
    M.nativeUpdate(dt)
    local ch,pc,mover=character()
    if not ch or not gameAllowed(pc) then
        M.removeInteraction();M.unmount(true);M.finishPresentation()
        if action then
            report(ch and "hotkey_blocked_game" or "hotkey_blocked_character")
        end
        return
    end
    if M.lease and (ch~=M.lease.char or not rideTerrain(M.lease,mover,dt)) then M.unmount(true) end
    if action=="dismount" then M.unmount(false) end
    if M.lease then
        local l=M.lease
        local nativeJump=CS.Beyond.Gameplay.Core.MovementComponent.MoveMode.Jumping
        if M.settings.jump_enabled and not l.flight and jump and
            (groundAllowed(mover) or (mover.moveMode==nativeJump and l.airTime<.1)) and U.Time.unscaledTime>=(l.nextJump or 0) then
            l.nextJump=U.Time.unscaledTime+M.settings.jump_cooldown
            local ok,err=pcall(Flight.request,l)
            if not ok then pcall(Flight.release,l);warnEvent("vehicle_jump_unavailable",err);notice("当前状态无法起跳") end
        end
        control(l,pc,dt)
    end
end
local function guarded(fn,event,...)
    local ok,err=pcall(fn,...)
    if not ok then fail(event,err) end
end
local function removeUpdates()
    for _,key in ipairs(M.keys) do pcall(function() LuaUpdate:Remove(key) end) end
    M.keys={}
end
local function ensureCleanupUpdate()
    if #M.pending==0 and not M.interactRemovalPending then return end
    if M.cleanupKey then return end
    M.cleanupKey=LuaUpdate:Add("Tick",function()
        local ok=pcall(retryCleanup)
        if not ok then warnEvent("cleanup_failed") end
        if M.interactRemovalPending then M.removeInteraction() end
        if #M.pending==0 and not M.interactRemovalPending then M.cleanupKey=nil return true end
    end)
end
function M.show(ctrl)
    -- Check panel prefab variant
    if not (ctrl.isPCPanel or ctrl.isControllerPanel or ctrl.isDefaultPanel) then return end
    if M.owner and M.owner~=ctrl then M.hide(M.owner) end
    M.owner=ctrl
    M.lastOwner=ctrl
    removeUpdates()
    local ok,err=pcall(function()
        ensureKeys()
        M.settings=config()
        M.faulted=false
        M.tickSeen=false
        if not M.settings.enabled then M.dismiss(true) else setScale();settleParked() end
        if not M.unsub then
            M.unsub=api().subscribe(ID,function()
                guarded(function()
                    M.settings=config()
                    M.faulted=false
                    if not M.settings.enabled then M.dismiss(true) else setScale();settleParked() end
                    if M.lease and not M.lease.airborne then speed(M.lease,M.lease.braking) end
                end,"config_failed")
            end)
        end
        M.keys[#M.keys+1]=LuaUpdate:Add("Tick",function(dt) guarded(tick,"tick_failed",dt) end)
        M.keys[#M.keys+1]=LuaUpdate:Add("TailTick",function(dt) guarded(visual,"pose_failed",clamp(dt,0,0.1)) end)
        report(ctrl.isPCPanel and "ready_pc" or ctrl.isControllerPanel and "ready_controller" or "ready_default")
    end)
    if not ok then
        M.hide(ctrl);warnEvent("initialization_failed",err)
        notice("摩托车初始化失败")
    end
end
function M.hide(ctrl)
    if M.owner~=ctrl then return end
    removeUpdates();M.removeInteraction();M.unmount(true);M.finishPresentation()
    if M.unsub then pcall(M.unsub);M.unsub=nil end
    M.owner=nil
    M.syncCollision()
    ensureCleanupUpdate()
end
function M.close(ctrl)
    -- Verify vehicle ownership before cleanup
    if M.owner~=ctrl and (M.owner~=nil or M.lastOwner~=ctrl) then return end
    M.hide(ctrl);M.dismiss(true);M.requestedToggle=nil
    M.lastOwner=nil
    ensureCleanupUpdate()
end
-- Module state bridge
local bridgeName="ZML/Motorcycle"
assert(not hg.loadedModules[bridgeName],"motorcycle namespace already occupied")
hg.loadedModules[bridgeName]={name=bridgeName,env={Motorcycle=M}}
hg.loadedModuleNameList[#hg.loadedModuleNameList+1]=bridgeName
return M
