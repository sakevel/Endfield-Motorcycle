-- Runs exclusively on the normal game's Lua/Unity main-thread lifecycle.
local M = {phase="absent", keys={}, pending={}, settings=nil}
local U = CS.UnityEngine
local V, Q = U.Vector3, U.Quaternion
local ID = "motorcycle"
-- ZML_WHEEL_GEOMETRY_BEGIN
-- Derived from our licensed model by tools/calibrate-bike.py, not game assets.
local BIKE={rearRadius=.3189637154,frontRadius=.3189681663,
    rear=V(-.0255573198,.318983692,-.7003807752),front=V(.0255573198,.3189881429,.7810290642),
    steerPivot=V(.0114865946,.8442755938,.4628484249)}
-- ZML_WHEEL_GEOMETRY_END
-- Steering follows the fork's inclined headstock, not a vertical yaw pivot.
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
    -- Own exception only, never player/config values or general account logs.
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
        acceleration=tonumber(v.acceleration),max_steer=tonumber(v.max_steer),seat_height=tonumber(v.seat_height),model_yaw=tonumber(v.model_yaw),render_comparison=v.render_comparison=="true",
        summon_key=v.summon_key,mount_key=v.mount_key,dismiss_key=v.dismiss_key}
    assert(c.scale and c.speed and c.acceleration and c.max_steer and c.max_steer>=10 and c.max_steer<=50 and c.seat_height and c.model_yaw,"configuration unavailable")
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
local function typing()
    local es=U.EventSystems.EventSystem.current
    if es==nil or not live(es.currentSelectedGameObject) then return false end
    local go=es.currentSelectedGameObject
    return go:GetComponent(typeof(CS.TMPro.TMP_InputField))~=nil or
        go:GetComponent(typeof(U.UI.InputField))~=nil
end
local function syncProbes()
    local visible=M.settings and M.settings.render_comparison and M.phase~="mounted" and M.owner~=nil
    for _,go in ipairs(M.probeRoots or {}) do go:SetActive(visible==true) end
end
local function setScale()
    if not M.visual then return end
    local c=M.settings
    local scale=M.lease and M.lease.ridingConfig and M.lease.ridingConfig.scale or c.scale
    M.visual.transform.localScale=V(scale,scale,scale)
    M.visual.transform.localRotation=Q.Euler(0,c.model_yaw,0)
    M.visual.transform.localPosition=V(0,0,0)
    syncProbes()
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
local function destroyVehicle()
    -- Track even objects whose SetParent subsequently failed; no orphaned partial model.
    for i=#(M.objects or {}),1,-1 do pcall(U.Object.Destroy,M.objects[i]) end
    -- Runtime-generated meshes/textures/material clones are not loader handles.
    for i=#(M.owned or {}),1,-1 do pcall(U.Object.Destroy,M.owned[i]) end
    M.objects,M.owned,M.parts,M.renderers,M.vehicle,M.visual,M.mesh=nil,nil,nil,nil,nil,nil,nil
    M.groundHits=nil
    M.groundQueryReported,M.rootGroundReported=nil,nil
    M.visibilityFrames=nil
    M.probeRoots,M.probeRenderers,M.probeCheck=nil,nil,nil
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
-- Diagnostic handles are wrappers for a borrowed GPU allocation, not owned Meshes.
-- Unity's GetVertexBuffer example disposes this wrapper; never Destroy the asset.
local function meshBufferState(name,mesh)
    if not M.settings.render_comparison then return end
    local buffer
    local ok=pcall(function()
        buffer=assert(mesh:GetVertexBuffer(0),"vertex buffer unavailable")
        local count,stride=buffer.count,buffer.stride
        assert(count>0 and stride>0,"empty GPU vertex buffer")
        report("probe_"..name.."_gpu_count_"..count)
        report("probe_"..name.."_gpu_stride_"..stride)
    end)
    if buffer then
        local released=pcall(function() buffer:Dispose() end)
        if not released then report("probe_"..name.."_gpu_wrapper_release_failed") end
    end
    if not ok then report("probe_"..name.."_gpu_unavailable") end
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
    -- XLua optimizes byte[] returns into a binary Lua string on this client.
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
        -- Decode directly: converting a 489KiB Lua byte string back to C# for
        -- each BitConverter read would allocate/copy the entire buffer per vertex.
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
        -- Current native shader dump: HGRP/Lit has HGBuffer (GBuffer), NOT
        -- ForwardOnly. Preserve native deferred/depth/stencil settings; guessing
        -- an absent forward pass cannot make a runtime model draw.
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
    M.parts={};M.renderers={};M.probeRoots={};M.probeRenderers={}
    local borrowedMaterial=visual:GetComponent(typeof(U.MeshRenderer)).sharedMaterial
    local function probe(name,offset)
        local go=cloneVisual(visual,"ZML_Bike_Probe_"..name)
        go.transform:SetParent(M.visual.transform,false);go.transform.localPosition=offset
        go:SetActive(false)
        M.probeRoots[#M.probeRoots+1]=go
        return go,go:GetComponent(typeof(U.MeshRenderer))
    end
    -- 2x2 controlled comparison: same scene/layer/scale, no business/physics.
    local native,nativeRenderer=probe("Native",V(-2.4,0,2.4))
    M.probeRenderers.native={nativeRenderer}
    meshBufferState("native",native:GetComponent(typeof(U.MeshFilter)).sharedMesh)
    local nativeOwned,nativeOwnedRenderer=probe("NativeOwned",V(2.4,0,2.4))
    M.probeRenderers.native_owned={nativeOwnedRenderer}
    local customNative=newObject("ZML_Bike_Probe_CustomNative")
    customNative.layer=M.vehicle.layer
    customNative.transform:SetParent(M.visual.transform,false)
    customNative.transform.localPosition=V(-2.4,0,-2.4)
    customNative:SetActive(false);M.probeRoots[#M.probeRoots+1]=customNative
    M.probeRenderers.custom_native={}
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
                -- Exact low-poly tread, including width and rotating facets.
                -- Deduplicate CPU vertices once; scalar support tests below avoid
                -- thousands of Lua->C# TransformPoint calls on every frame.
                local key=px..":"..py..":"..pz
                tire[key]={x=position.x,y=position.y,z=position.z}
            end
            if i==0 then firstPosition=position end;lastPosition=position
            local normal=V(nx,ny,nz).normalized
            normals[i]=normal
            uvs[i]=U.Vector2(ux+uw*tu/65535,uy+uh*tv/65535)
            colors[i]=U.Color(1,1,1,1)
            -- Palette UVs often have zero triangle area: UV-derived tangents can
            -- degenerate. A finite normal-orthogonal tangent is sufficient for
            -- our flat normal map and is deterministic for every vertex.
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
        -- CPU setter/readback is not proof of a GPU allocation in this custom SRP.
        -- Explicitly submit once, after all attributes/indices/bounds are final.
        -- false keeps our readable CPU copy; no borrowed Mesh is uploaded/modified.
        mesh:UploadMeshData(false)
        if part==1 then meshBufferState("custom",mesh) end
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
        if part==1 then nativeOwnedRenderer.sharedMaterial=renderer.sharedMaterial end
        local comparison=cloneVisual(visual,"ZML_Bike_Probe_Custom_"..part)
        comparison.transform:SetParent(customNative.transform,false)
        comparison.transform.localPosition=pivot
        -- Reuse the very same uploaded Mesh; no second decoder or geometry copy.
        comparison:GetComponent(typeof(U.MeshFilter)).sharedMesh=mesh
        local comparisonRenderer=comparison:GetComponent(typeof(U.MeshRenderer))
        comparisonRenderer.sharedMaterial=borrowedMaterial
        comparisonRenderer.enabled=true
        M.probeRenderers.custom_native[#M.probeRenderers.custom_native+1]=comparisonRenderer
    end
    assert(at==byteLength,"motorcycle asset trailing bytes")
    report("bundled_model_ready")
end

local function probeState()
    if not M.settings.render_comparison or not M.probeRenderers then return end
    local groups={custom_owned=M.renderers,native=M.probeRenderers.native,
        native_owned=M.probeRenderers.native_owned,custom_native=M.probeRenderers.custom_native}
    for name,renderers in pairs(groups) do
        local ok=pcall(function()
            local r=renderers[1]
            local mat=r.sharedMaterial
            report("probe_"..name.."_force_off_"..(r.forceRenderingOff and "1" or "0"))
            report("probe_"..name.."_shader_supported_"..(mat.shader.isSupported and "1" or "0"))
            report("probe_"..name.."_hgbuffer_query_"..(mat:GetShaderPassEnabledAndExisted("HGBuffer") and "1" or "0"))
        end)
        if not ok then report("probe_"..name.."_state_unavailable") end
    end
end
local function visibilityCheck()
    if M.probeCheck and M.settings.render_comparison and M.phase=="parked" then
        M.probeCheck=M.probeCheck+1
        if M.probeCheck>=30 then
            for name,renderers in pairs(M.probeRenderers or {}) do
                local any=false
                for _,renderer in ipairs(renderers) do if renderer.isVisible then any=true break end end
                report("probe_"..name.."_camera_"..(any and "1" or "0"))
            end
            M.probeCheck=nil -- bounds diagnosis only, NOT color visibility acceptance
        end
    end
    if not M.vehicle or not M.visibilityFrames then return end
    local visible=0
    for _,renderer in ipairs(M.renderers or {}) do
        if live(renderer) and renderer.enabled and renderer.isVisible then visible=visible+1 end
    end
    if visible>0 then
        report("model_camera_visible");M.visibilityFrames=nil
    else
        M.visibilityFrames=M.visibilityFrames+1
        if M.visibilityFrames>=45 then
            report("model_camera_not_visible")
            pcall(function() logger.error("ZML Motorcycle diagnostic: no owned renderer marked visible; layer="..M.vehicle.layer) end)
            M.visibilityFrames=nil -- bounded once per summon, not a per-frame log
        end
    end
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
    -- XLua may unbox Nullable<Vector3> directly, or expose the struct wrapper.
    local ok,has=pcall(function()return value.HasValue end)
    if ok and has~=nil then return has and value.Value or nil end
    return value
end
-- Explicit reflection flags avoid ambiguous/default lookup at the Lua bridge.
-- Cache metadata/direct method once per lease. Only these four MoveInput fields; no RVAs.
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
        -- Use the confirmed direct binding. Omit the OPTIONAL null clamp target:
        -- no MethodInfo.Invoke/object[] (real XLua rejects that call signature).
        nav(input,direction,false)
    end
    -- No vectors/keys/player values in diagnosis, only binding/empty-state flags.
    report("drive_reflection_ready")
    for _,name in ipairs({"navMoveVector","pendingNoManualMove","noManualMove"}) do
        local ok,direct=pcall(function()return optionalVector(input[name])end)
        report("drive_"..name:lower().."_direct_"..(not ok and "unavailable" or direct~=nil and "set" or "empty")..
            "_boxed_"..(port.read(name)~=nil and "set" or "empty"))
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
        -- A foreign navigation/scripted move wins; never clear its command.
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
    -- Track BEFORE calling: a binding throwing after a partial write must roll back.
    lease.previousCommand=lease.lastCommand
    lease.driveOwned=true;lease.lastCommand=copy(direction)
    port.nav(direction)
    assert(sameVector(port.read("navMoveVector"),direction) and port.read("navMoveClampTarget")==nil,
        "native drive write/read mismatch")
    lease.previousCommand=nil
end
local function restore(lease)
    if not lease then return end
    -- Independently restore every captured field: one destroyed node must not skip the rest.
    for _,b in ipairs(lease.bones) do
        pcall(function()
            if live(b.node) then b.node.localPosition=b.position; b.node.localRotation=b.rotation end
        end)
    end
    pcall(function() if live(lease.grounder) then lease.grounder.enabled=lease.grounderEnabled end end)
    removeSpeeds(lease)
    releaseDrive(lease)
    if #lease.handles>0 or lease.driveOwned then M.pending[#M.pending+1]=lease; warnEvent("cleanup_retry") end
end
local function retryCleanup()
    for i=#M.pending,1,-1 do
        removeSpeeds(M.pending[i])
        releaseDrive(M.pending[i])
        if #M.pending[i].handles==0 and not M.pending[i].driveOwned then table.remove(M.pending,i) end
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
        -- A saturated buffer has unspecified nearest hit; use the native floor.
        if count>=8 then return nil end
        local best
        for i=0,count-1 do
            local hit=M.groundHits[i]
            local point,normal=hit.point,hit.normal
            if normal.y>.45 and math.abs(point.y-pos.y)<.65 and
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
    M.vehicle.transform:SetPositionAndRotation(pos,frame*Q.Euler(0,0,bank)*undo)
    local fallback=floorPlane(mover,pos)
    local rp=groundPlane(mover,pos,rear,fallback)
    local fp=groundPlane(mover,pos,front,fallback)
    local terrainPitch=0
    -- Fit BOTH tyres, including tread width, not max(0,-lowest rim bottom).
    for i=1,3 do
        local rg,fg=tireGap(rear,rp,M.settings.scale),tireGap(front,fp,M.settings.scale)
        local span=math.max(.5,(front.transform.position-rear.transform.position).magnitude)
        terrainPitch=clamp(terrainPitch+math.deg(math.atan((fg-rg)/span)),-28,28)
        M.vehicle.transform.rotation=frame*Q.Euler(terrainPitch,0,bank)*undo
    end
    M.vehicle.transform.rotation=frame*Q.Euler(terrainPitch+pitch,0,bank)*undo
    local rg,fg=tireGap(rear,rp,M.settings.scale),tireGap(front,fp,M.settings.scale)
    M.vehicle.transform.position=pos+V(0,-(rg+fg)*.5+(bob or 0),0)
    -- Small owned visual suspension stroke keeps each tyre on its contact plane
    -- while the chassis pitches/bobs. Native collision/root are untouched.
    for _,item in ipairs({{rear,rp},{front,fp}}) do
        local part,plane=item[1],item[2]
        local gap=tireGap(part,plane,M.settings.scale)
        part.transform.position=part.transform.position+V(0,clamp(-gap,-.16,.16),0)
    end
    return terrainPitch,{rear=tireGap(rear,rp,M.settings.scale),front=tireGap(front,fp,M.settings.scale)}
end
local function settleParked()
    if not M.vehicle or M.lease then return end
    local ch,pc,mover=character()
    if ch and groundAllowed(mover) then
        seatVehicle(mover,M.vehicle.transform.position,M.vehicle.transform.rotation,0,0,0)
    end
end
function M.unmount(quiet)
    local lease=M.lease
    M.lease=nil
    if M.vehicle then M.phase="parked" else M.phase="absent" end
    syncProbes()
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
    if lease then restore(lease); report("dismounted"); if not quiet then notice("已下车") end end
end
function M.dismiss(quiet)
    M.unmount(true)
    destroyVehicle()
    report("dismissed")
    if not quiet then notice("摩托车已收回") end
end
local function fail(event,err)
    M.faulted=true -- A contract failure must not produce a toast/error every frame.
    M.unmount(true)
    warnEvent(event,err)
    notice("摩托车操作失败，已恢复角色；请查看模组日志")
end
function M.summon()
    if M.phase=="mounted" then notice("请先下车") return end
    local ch,pc,mover,root=character()
    if not ch or not gameAllowed(pc) or not groundAllowed(mover) or #M.pending>0 then
        report("summon_blocked");notice("当前不能召唤：请在普通地面、非战斗且可操作时重试") return
    end
    -- Park at the player's current, known-walkable position. No teleport or business entity is spawned.
    if M.vehicle then
        M.vehicle.transform:SetPositionAndRotation(root.transform.position,root.transform.rotation)
        M.visibilityFrames=0;M.probeCheck=0
        setScale();seatVehicle(mover,root.transform.position,root.transform.rotation,0,0,0);probeState();notice(M.settings.render_comparison and "渲染对照已重定位：先不要上车，请截图四个位置" or "摩托车已移到身边");return
    end
    local ok,err=pcall(function()
        M.loader=require_ex("Common/Utils/LuaResourceLoader").LuaResourceLoader()
        report("model_loader_ready")
        local material=assert(M.loader:LoadMaterial(MATERIAL),"native shader template unavailable")
        report("model_material_loaded")
        M.vehicle=newObject("ZML_Motorcycle")
        -- The character control/collider root may be on a non-rendering layer.
        -- Use the client's public default world layer for an ordinary scene mesh,
        -- not a copied logic/HIDE/UI/physics layer, and the actual gameplay scene.
        local layer=CS.Beyond.Gameplay.LayerDef.DEFAULT_LAYER
        assert(type(layer)=="number" and layer>=0 and layer<32,"native world layer unavailable")
        M.vehicle.layer=layer
        U.SceneManagement.SceneManager.MoveGameObjectToScene(M.vehicle,root.gameObject.scene)
        M.visual=newObject("ZML_Bike_Model")
        M.visual.layer=M.vehicle.layer
        M.visual.transform:SetParent(M.vehicle.transform,false)
        buildModel(material,visualTemplate())
        setScale()
        M.vehicle.transform:SetPositionAndRotation(root.transform.position,root.transform.rotation)
        seatVehicle(mover,root.transform.position,root.transform.rotation,0,0,0)
        M.visibilityFrames=0
        report("model_world_layer_"..layer)
        M.phase="parked"
        syncProbes();M.probeCheck=0;probeState()
        if M.settings.render_comparison then report("render_comparison_ready") end
    end)
    if not ok then destroyVehicle();warnEvent("model_load_failed",err);notice("自带摩托车模型加载失败，未修改角色") return end
    report("summoned");notice(M.settings.render_comparison and "渲染对照：前左原生/原材质，前右原生/自材质，后左自带/原材质，脚边自带/自材质；请先截图" or "摩托车已召唤；按 "..M.settings.mount_key.." 上车")
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
    -- Capture optional intervening nodes too: don't mix animated clavicles/neck
    -- from one frame with the frozen rest of the adapted skeleton.
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
-- Scalar planner shared verbatim with the extracted-Avatar offline harness.
-- A seat surface is NOT the pelvis bone: allow a proportionate tissue clearance.
-- No per-character names/presets or bone length changes; the actual torso
-- segments/shoulder span determine fore-aft placement and forward flexion.
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
        -- Short riders use the inner end of the existing rubber grips, never
        -- an imaginary narrower handlebar. Wrist targets sit above the surface.
        local width=.32+.055*clamp((arm.l1+arm.l2-.37)/.19,0,1)
        local point=pivot+rotation*(V(sign*width,1.065,.34)-pivot)
        points[side.."Arm"]={point.x*c.scale,point.y*c.scale,point.z*c.scale}
        -- Ankle is above the sole, not on the peg. Actual model pegs sit near
        -- (+/-.25,.32,-.175); neutral standing foot clearance preserves heels.
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
    -- Short arms get less hang-off, never imaginary grip targets or stretched bones.
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
    -- Continuous local refinement avoids a visibly quantized body-size preset.
    for _,step in ipairs({.0075,.00375,.001875}) do
        local z,angle=best.z,best.angle
        for dz=-1,1 do for da=-1,1 do candidate(clamp(z+dz*step,lowZ,highZ),clamp(angle+da*step*160,lowA,highA)) end end
    end
    return best
end
local function fitConfiguration(l,c)
    local adjusted={}
    for key,value in pairs(c) do adjusted[key]=value end
    -- Vehicle size is exactly the user's setting, parked AND mounted. Fit the
    -- rider's seat position and forward lean, never shrink a normal motorcycle
    -- into a toy or stretch character bones to obtain a contact-only metric.
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
    -- If a very short arm cannot follow full-lock steering, limit ONLY the fork
    -- travel to its reachable range. Keep the chassis size and grip contact.
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
    local accel=braking and math.max(12,c.acceleration) or c.acceleration
    if lease.speed==desired and lease.speedAccel==accel then return end
    -- Acquire before dropping the old handle; on exception all our handles are still tracked.
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
    local c=lease.ridingConfig
    local raw=assert(pc.rawMoveAxis,"native raw move axis unavailable")
    local x,y=clamp(raw.x,-1,1),clamp(raw.y,-1,1)
    if math.abs(x)<.08 then x=0 end;if math.abs(y)<.08 then y=0 end
    lease.throttle=y
    -- Configured full-lock fork travel also scales the high-speed steering
    -- budget from the old 22-degree/3 m/s² baseline. Merely increasing the
    -- stationary lock would leave the old huge moving turning radius intact.
    -- This is a kinematic bicycle, not a full tyre/slip/dynamic balance simulator.
    local lateralBudget=3*lease.maxSteer/22
    local limit=math.min(lease.maxSteer,math.deg(math.atan((BIKE.front.z-BIKE.rear.z)*c.scale*lateralBudget/
        math.max((lease.velocity or 0)^2,1))))
    lease.steer,lease.steerVelocity=spring(lease.steer or 0,lease.steerVelocity or 0,x*limit,dt,12)
    lease.steer=clamp(lease.steer,-lease.maxSteer,lease.maxSteer)
    lease.geometry=turnGeometry(c.scale,lease.steer)
    -- Send a tangent for the rider/root reference point, including its offset
    -- ahead of the rear axle. Native acceleration, ground checks and collision
    -- resolve all movement; no Transform.position/teleport/delta injection.
    local predictor=(lease.velocity or 0)*lease.geometry.curvature*dt*.5
    local yaw=lease.bikeYaw+math.deg(lease.geometry.beta+predictor)
    lease.motionDirection=Q.Euler(0,yaw,0)*V(0,0,1)
    speed(lease,U.Input.GetKey(U.KeyCode.LeftControl))
    queueDrive(lease,lease.motionDirection*(lease.braking and 0 or y))
end
function M.mount()
    if M.phase=="mounted" then M.unmount(false) return end
    if not M.vehicle then notice("先按 "..M.settings.summon_key.." 召唤摩托车") return end
    local ch,pc,mover,root=character()
    if not ch or not gameAllowed(pc) or not groundAllowed(mover) or #M.pending>0 then
        report("mount_blocked");notice("当前不能骑乘：请在普通地面、非战斗且可操作时重试") return
    end
    if distance(root.transform.position,M.vehicle.transform.position)>3.5*M.settings.scale then notice("请靠近摩托车") return end
    local lease
    local ok,err=pcall(function()
        lease=captureRig(ch,mover,root) -- All validation happens before any character mutation.
        fitConfiguration(lease,M.settings)
        lease.input=assert(mover.input,"native movement input unavailable")
        lease.drivePort=drivePort(lease.input)
        assert(driveFree(lease.drivePort),"scripted movement input occupied")
        assert(lease.drivePort.read("navMoveVector")==nil and lease.drivePort.read("navMoveClampTarget")==nil,
            "navigation input already in use")
        -- Verify the null setter on an ALREADY EMPTY field before acquiring a
        -- persistent command. A broken cleanup binding must not freeze normal movement.
        lease.drivePort.clear()
        assert(lease.drivePort.read("navMoveVector")==nil,"native empty drive release rejected")
        report("drive_release_preflight_ready")
        lease.bikeYaw=root.transform.rotation.eulerAngles.y+M.settings.model_yaw
        lease.configModelYaw=M.settings.model_yaw
        lease.geometry=turnGeometry(lease.ridingConfig.scale,0)
        lease.motionDirection=Q.Euler(0,lease.bikeYaw,0)*V(0,0,1)
        M.lease=lease
        queueDrive(lease,V(0,0,0))
        M.vehicle.transform:SetPositionAndRotation(root.transform.position,root.transform.rotation)
        -- Keep the native animator ticking: its root-motion/skill callbacks must remain normal.
        -- Only the final rendered skeleton pose is adapted in TailTick.
        if live(lease.grounder) then lease.grounder.enabled=false end
        speed(lease,false)
        M.phase="mounted"
        setScale()
        syncProbes()
    end)
    if not ok then fail("mount_failed",err) return end
    report("mounted");notice("已上车：W/S 前进/倒车，A/D 转动车把，左 Ctrl 刹车，"..M.settings.mount_key.." 下车")
end
-- Analytic two-bone IK: preserve skeleton lengths and derive rotation from the current bone axes.
-- No assumed character names, bind-axis angles, teleport, or real gameplay transforms.
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
    if ch~=l.char or not ch or not gameAllowed(pc) or not groundAllowed(mover) or not live(M.vehicle) then M.unmount(true) return end
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
    local delta=pos-(l.previousPosition or pos);delta=V(delta.x,0,delta.z)
    l.previousPosition=copy(pos)
    local travel=delta.magnitude
    -- Never spin or lurch across scene/root discontinuities, or from requested
    -- speed while blocked by a wall. Use actual collision-resolved travel.
    local discontinuity=travel>math.max(.5,c.speed*dt*3)
    if discontinuity then
        travel=0;delta=V(0,0,0)
        l.lean,l.leanVelocity,l.steer,l.steerVelocity=0,0,0,0
        l.velocity,l.accel,l.pitch,l.drive=0,0,0,0
    end
    -- Project collision-resolved travel onto the commanded longitudinal tangent.
    -- Pushing into a wall/sideways depenetration cannot create phantom yaw/spin.
    local signed=dot(delta,l.motionDirection)
    local g=l.geometry or turnGeometry(c.scale,l.steer or 0)
    local yawStep=signed*g.curvature
    l.bikeYaw=U.Mathf.DeltaAngle(0,l.bikeYaw+math.deg(yawStep))
    l.yawRate=yawStep/math.max(dt,.008)
    local measured=signed/math.max(dt,.008)
    local oldVelocity=l.velocity or 0
    l.velocity=damp(oldVelocity,measured,dt,10)
    l.accel=damp(l.accel or 0,clamp((l.velocity-oldVelocity)/math.max(dt,.008),-16,16),dt,7)
    -- Centripetal bank: slow turning does not lean like a fast corner.
    local desired=-clamp(math.deg(math.atan(l.velocity*l.yawRate/9.81)),-20,20)
    l.lean,l.leanVelocity=spring(l.lean or 0,l.leanVelocity or 0,desired,dt,9)
    l.lean=clamp(l.lean,-20,20)
    l.pitch=damp(l.pitch or 0,clamp(-l.accel*.22,-2.5,2.5),dt,6)
    l.drive=damp(l.drive or 0,clamp(math.abs(l.velocity)/10*4+math.abs(l.accel)*.32,0,8),dt,5)
    -- Body yaw comes ONLY from travel * curvature, never native actor facing.
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
    l.terrainPitch,l.groundGaps=seatVehicle(mover,pos,heading,l.lean,l.pitch,bob)
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
            -- Bend knees mainly forward beside the tank, not sideways into a frog stance.
            local pole=kind=="Leg" and (t.forward+t.right*(sign*.12)) or (-t.forward*.45+t.right*(sign*.8)-t.up*.3)
            solve(l[side..kind],point,pole)
        end
        r[side.."Foot"].rotation=t.rotation*l.base[side.."Foot"]
        -- Rotate the neutral hand longitudinal axis down around the bar rather
        -- than letting forearm IK leave wrists in a standing T-pose orientation.
        local barRotation=t.rotation*forkRotation(l.steer or 0)
        r[side.."Hand"].rotation=Q.FromToRotation(barRotation*l.handAxes[side],barRotation*V(0,0,1))*barRotation*l.base[side.."Hand"]
        for _,chain in ipairs(l.fingers[side]) do for _,finger in ipairs(chain) do
            finger.node.localRotation=finger.rotation*Q.AngleAxis(finger.angle,finger.axis)
        end end
    end
end
local function tick(dt)
    dt=clamp(dt or 1/60,0,.1)
    retryCleanup()
    visibilityCheck()
    if M.faulted or not M.settings or not M.settings.enabled or #M.pending>0 then return end
    if not M.tickSeen then M.tickSeen=true;report("tick_active") end
    if not U.Application.isFocused or typing() then M.unmount(true) return end
    local input=U.Input
    local action
    if input.GetKeyDown(U.KeyCode[M.settings.dismiss_key]) then action="dismiss"
    elseif input.GetKeyDown(U.KeyCode[M.settings.summon_key]) then action="summon"
    elseif input.GetKeyDown(U.KeyCode[M.settings.mount_key]) then action="mount" end
    if action then report("hotkey_"..action) end
    local ch,pc,mover=character()
    if not ch or not gameAllowed(pc) then
        M.unmount(true)
        if action then
            report(ch and "hotkey_blocked_game" or "hotkey_blocked_character")
            notice("当前不能操作摩托车：请返回普通探索界面并脱离战斗")
        end
        return
    end
    if not M.driveProbed then
        M.driveProbed=true
        local ok,err=pcall(drivePort,mover.input) -- read-only, no NavMove/field write/speed change
        if not ok then warnEvent("drive_probe_failed",err) end
    end
    if M.lease and (ch~=M.lease.char or not groundAllowed(mover)) then M.unmount(true) end
    if action=="dismiss" then M.dismiss(false)
    elseif action=="summon" then M.summon()
    elseif action=="mount" then M.mount() end
    if M.lease then control(M.lease,pc,dt) end
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
    if #M.pending==0 then return end
    if M.cleanupKey then return end
    M.cleanupKey=LuaUpdate:Add("Tick",function()
        local ok=pcall(retryCleanup)
        if not ok then warnEvent("cleanup_failed") end
        if #M.pending==0 then M.cleanupKey=nil return true end
    end)
end
function M.show(ctrl)
    -- UICtrl distinguishes PC, controller and default prefabs. PC is not default.
    if not (ctrl.isPCPanel or ctrl.isControllerPanel or ctrl.isDefaultPanel) then return end
    if M.owner and M.owner~=ctrl then M.hide(M.owner) end
    M.owner=ctrl
    M.lastOwner=ctrl
    removeUpdates()
    local ok,err=pcall(function()
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
                    if M.lease then speed(M.lease,M.lease.braking) end
                end,"config_failed")
            end)
        end
        M.keys[#M.keys+1]=LuaUpdate:Add("Tick",function(dt) guarded(tick,"tick_failed",dt) end)
        M.keys[#M.keys+1]=LuaUpdate:Add("TailTick",function(dt) guarded(visual,"pose_failed",clamp(dt,0,0.1)) end)
        report(ctrl.isPCPanel and "ready_pc" or ctrl.isControllerPanel and "ready_controller" or "ready_default")
    end)
    if not ok then
        M.hide(ctrl);warnEvent("initialization_failed",err)
        notice("摩托车模组初始化失败，请查看模组日志")
    end
end
function M.hide(ctrl)
    if M.owner~=ctrl then return end
    removeUpdates();M.unmount(true)
    if M.unsub then pcall(M.unsub);M.unsub=nil end
    M.owner=nil
    syncProbes()
    ensureCleanupUpdate()
end
function M.close(ctrl)
    -- A hidden/non-owner prefab must not destroy the active owner's vehicle.
    if M.owner~=ctrl and (M.owner~=nil or M.lastOwner~=ctrl) then return end
    M.hide(ctrl);M.dismiss(true)
    M.lastOwner=nil
    ensureCleanupUpdate()
end
return M
