local vec,quat={},{}
local vm,qm={},{}
local function v(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},vm) end
vm.__add=function(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
vm.__sub=function(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
vm.__unm=function(a) return v(-a.x,-a.y,-a.z) end
vm.__mul=function(a,b) if type(a)=='number' then a,b=b,a end return v(a.x*b,a.y*b,a.z*b) end
vm.__div=function(a,b) return v(a.x/b,a.y/b,a.z/b) end
vm.__index=function(a,k)
    if k=='magnitude' then return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
    if k=='sqrMagnitude' then return a.x*a.x+a.y*a.y+a.z*a.z end
    if k=='normalized' then return a.magnitude>1e-10 and a/a.magnitude or v() end
end
setmetatable(vec,{__call=function(_,...) return v(...) end})
vec.Dot=function(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
vec.Cross=function(a,b) return v(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
vec.Distance=function(a,b) return (a-b).magnitude end
local function q(x,y,z,w) return setmetatable({x=x or 0,y=y or 0,z=z or 0,w=w or 1},qm) end
local function normalized(a)
    local l=math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z+a.w*a.w)
    return q(a.x/l,a.y/l,a.z/l,a.w/l)
end
qm.__mul=function(a,b)
    if getmetatable(b)==vm then
        local u=v(a.x,a.y,a.z)
        return b+vec.Cross(u,b)*(2*a.w)+vec.Cross(u,vec.Cross(u,b))*2
    end
    return q(a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
        a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
        a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z)
end
qm.__index=function(a,k)
    if k=='eulerAngles' then return v(0,math.deg(math.atan(2*(a.w*a.y+a.x*a.z),1-2*(a.y*a.y+a.x*a.x))),0) end
end
quat.identity=q()
quat.Inverse=function(a) return q(-a.x,-a.y,-a.z,a.w) end
quat.AngleAxis=function(degrees,axis)
    axis=axis.normalized;local t=math.rad(degrees)/2
    return q(axis.x*math.sin(t),axis.y*math.sin(t),axis.z*math.sin(t),math.cos(t))
end
quat.Euler=function(x,y,z)
    return quat.AngleAxis(y,v(0,1,0))*quat.AngleAxis(x,v(1,0,0))*quat.AngleAxis(z,v(0,0,1))
end
quat.FromToRotation=function(a,b)
    a,b=a.normalized,b.normalized;local d=vec.Dot(a,b)
    if d<-0.99999 then
        local c=vec.Cross(a,v(0,1,0));if c.sqrMagnitude<0.00001 then c=vec.Cross(a,v(1,0,0)) end
        return quat.AngleAxis(180,c)
    end
    local c=vec.Cross(a,b);return normalized(q(c.x,c.y,c.z,1+d))
end
local tm={}
local function transform(parent,pos)
    local t=setmetatable({_parent=parent,_p=pos or v(),_q=q(),localScale=v(1,1,1),destroyed=false,_children={}},tm)
    if parent then parent._children[#parent._children+1]=t end
    return t
end
tm.__index=function(a,k)
    if k=='localPosition' then return a._p end
    if k=='localRotation' then return a._q end
    if k=='parent' then return a._parent end
    if k=='childCount' then return a._childCount or #a._children end
    if k=='GetChild' then return function(self,i) assert(i>=0 and i<#self._children);return self._children[i+1] end end
    if k=='position' then return a._parent and a._parent:TransformPoint(a._p) or a._p end
    if k=='rotation' then return a._parent and a._parent.rotation*a._q or a._q end
    if k=='forward' then return a.rotation*v(0,0,1) end
    if k=='right' then return a.rotation*v(1,0,0) end
    if k=='up' then return a.rotation*v(0,1,0) end
    if k=='lossyScale' then
        local s=a._parent and a._parent.lossyScale or v(1,1,1)
        return v(s.x*a.localScale.x,s.y*a.localScale.y,s.z*a.localScale.z)
    end
    if k=='Equals' then return function(self,other) return other==nil and self.destroyed end end
    if k=='SetParent' then return function(self,parent)
        if self._parent then for i,n in ipairs(self._parent._children) do if n==self then table.remove(self._parent._children,i) break end end end
        self._parent=parent
        if parent then parent._children[#parent._children+1]=self end
    end end
    if k=='SetPositionAndRotation' then return function(self,p,r) self.position=p;self.rotation=r end end
    if k=='TransformPoint' then return function(self,p)
        local scale=self.lossyScale
        return self.position+self.rotation*v(p.x*scale.x,p.y*scale.y,p.z*scale.z)
    end end
    if k=='InverseTransformPoint' then return function(self,p)
        local result=quat.Inverse(self.rotation)*(p-self.position)
        local scale=self.lossyScale
        return v(result.x/scale.x,result.y/scale.y,result.z/scale.z)
    end end
end
tm.__newindex=function(a,k,value)
    if k=='localPosition' then rawset(a,'_p',value)
    elseif k=='localRotation' then rawset(a,'_q',value)
    elseif k=='position' then rawset(a,'_p',a._parent and a._parent:InverseTransformPoint(value) or value)
    elseif k=='rotation' then rawset(a,'_q',a._parent and quat.Inverse(a._parent.rotation)*value or value)
    else rawset(a,k,value) end
end
typeof=function(t) return t end
MOCK={objects={},updates={},nextUpdate=0,events={},notices={},keysDown={},keysHeld={},loads={},disposals=0}
-- Local research harness drives the production solver with extracted Avatar poses.
MOCK.transform=transform
MOCK.quaternion=q
local function equals(self,other) return other==nil and self.destroyed end
local function go(name)
    local g={name=name,layer=0,Equals=equals,components={},scene={handle=5},activeSelf=true}
    g.transform=transform();g.transform.gameObject=g
    g.AddComponent=function(self,kind)
        assert(kind=='MeshFilter' or kind=='MeshRenderer','no gameplay scripts/physics added to original assets')
        local c={Equals=equals,gameObject=self,forceRenderingOff=false}
        if kind=='MeshRenderer' then
            setmetatable(c,{__index=function(_,key)
                if key=='isVisible' then
                    local parent=self.transform
                    if self.activeSelf==false then return false end
                    while parent.parent do
                        parent=parent.parent
                        if parent.gameObject and parent.gameObject.activeSelf==false then return false end
                    end
                    local scene=parent.gameObject.scene
                    local mesh=self.components.MeshFilter and self.components.MeshFilter.sharedMesh
                    return c.enabled and self.layer==8 and scene.handle==9 and
                        c.clonedNative and c.lightModeMask==4294967295 and
                        c.sharedMaterial and c.sharedMaterial.passes.HGBuffer and
                        mesh and (mesh.borrowedNative or (mesh.colors~=nil and mesh.tangents~=nil and mesh.uploaded))
                end
            end})
        end
        self.components[kind]=c;return c
    end
    g.SetActive=function(self,value)
        assert(type(value)=='boolean' and self~=MOCK.template,'do not change borrowed prefab')
        self.activeSelf=value
    end
    g.GetComponent=function(self,kind) return self.components[kind] end
    MOCK.objects[#MOCK.objects+1]=g
    return g
end
local u={Vector3=vec,Quaternion=quat,HumanBodyBones=setmetatable({},{__index=function(_,k)return k end}),
    Application={isFocused=true},Object={},Component='Component',MeshFilter='MeshFilter',MeshRenderer='MeshRenderer',
    UI={InputField='InputField'},EventSystems={EventSystem={current={}}},Input={},
    KeyCode=setmetatable({},{__index=function(_,k)return k end}),Mathf={}}
u.RaycastHit='RaycastHit'
u.QueryTriggerInteraction={Ignore='Ignore'}
u.Physics={RaycastNonAlloc=function(origin,direction,hits,maxDistance,mask,triggers)
    assert(direction.y==-1 and maxDistance==1.45 and mask==256 and triggers=='Ignore')
    if MOCK.failGroundQuery then error('simulated stripped physics binding') end
    MOCK.groundQueries=(MOCK.groundQueries or 0)+1
    if MOCK.groundSaturated then return 8 end
    if MOCK.groundMissing then return 0 end
    local slope=MOCK.groundSlope or v()
    local base=MOCK.groundY or GameInstance.playerController.mainCharacter.rootCom.transform.position.y
    local y=base+origin.x*slope.x+origin.z*slope.z
    if MOCK.groundStep and origin.z>0 then y=y+MOCK.groundStep end
    if y>origin.y or origin.y-y>maxDistance then return 0 end
    hits[0]={point=v(origin.x,y,origin.z),normal=v(-slope.x,1,-slope.z).normalized}
    if MOCK.groundWall then hits[0].normal=v(1,0,0) end
    return 1
end}
u.GameObject=setmetatable({},{__call=function(_,name)return go(name)end})
u.Object.Destroy=function(g)
    assert(g.name=='ZML_Motorcycle' or (g.name and g.name:find('ZML_Bike_',1,true)) or g.ownedResource,'never destroy original character/scene objects')
    g.destroyed=true
    if not g.transform then return end
    g.transform.destroyed=true
    for _,o in ipairs(MOCK.objects) do
        local parent=o.transform.parent
        while parent do if parent==g.transform then o.destroyed=true;o.transform.destroyed=true;break end;parent=parent.parent end
    end
end
u.Object.Instantiate=function(template)
    assert(template==MOCK.template and template.transform.childCount==0 and
        template:GetComponents('Component').Length==3,'only audited pure LOD0 branch may be cloned')
    if MOCK.failClone then error('simulated native visual clone failure') end
    local g=go(template.name)
    local filter=g:AddComponent('MeshFilter');filter.sharedMesh=template.components.MeshFilter.sharedMesh
    local r=g:AddComponent('MeshRenderer')
    r.clonedNative=true;r.lightModeMask=4294967295;r.renderingLayerMask=1
    r.sharedMaterial=template.components.MeshRenderer.sharedMaterial;r.enabled=true
    MOCK.cloneCount=(MOCK.cloneCount or 0)+1
    return g
end
u.Input.GetKeyDown=function(key)
    local result=MOCK.keysDown[key];MOCK.keysDown[key]=nil;return result or false
end
u.Input.GetKey=function(key) return MOCK.keysHeld[key] or false end
u.Mathf.DeltaAngle=function(a,b) return (b-a+180)%360-180 end
local mode={Grounded='Grounded',StepClimbing='StepClimbing',Pivot='Pivot',TurnStart='TurnStart',Jumping='Jumping',Falling='Falling'}
CS={UnityEngine=u,TMPro={TMP_InputField='TMP_InputField'},Beyond={Gameplay={LayerDef={DEFAULT_LAYER=8},Core={MovementComponent={MoveMode=mode}}}}}
u.SceneManagement={SceneManager={MoveGameObjectToScene=function(g,scene)
    assert(g.name=='ZML_Motorcycle' and g.transform.parent==nil and scene.handle==9)
    g.scene=scene
end}}
CS.System={Reflection={BindingFlags='BindingFlags'},Enum={Parse=function(kind,text)
    assert(kind=='BindingFlags' and text=='Instance, Public, NonPublic');return {enum='BindingFlags',value=52}
end},Object='Object',Int32='Int32',Convert={FromBase64String=function(s)return mock_decode_asset(s)end},BitConverter={},Array={}}
for _,method in ipairs({'ToInt16','ToUInt16','ToUInt32','ToSingle'}) do
    local format=({ToInt16='<i2',ToUInt16='<I2',ToUInt32='<I4',ToSingle='<f'})[method]
    CS.System.BitConverter[method]=function(data,offset)
        assert(type(data)=='string','match actual optimized byte[] bridge')
        local result=string.unpack(format,data,offset+1);return result
    end
end
CS.System.Array.CreateInstance=function(kind,n)
    assert(kind==vec or kind==u.Vector2 or kind==u.Vector4 or kind==u.Color or kind=='Int32' or kind=='RaycastHit' or kind=='Object')
    return setmetatable({Length=n,kind=kind},{__newindex=function(self,i,value)
        assert(type(i)=='number' and i>=0 and i<n and i%1==0)
        if kind=='Object' then -- public object[] accepts boxed values or nil
        elseif kind=='RaycastHit' then assert(value.point and value.normal)
        elseif kind=='Int32' then assert(type(value)=='number' and value%1==0)
        elseif kind==u.Color then assert(type(value)=='table' and value.r and value.g and value.b and value.a)
        else assert(type(value)=='table' and value.x and value.y) end
        rawset(self,i,value)
    end})
end
u.Vector2=function(x,y)return {x=x,y=y}end
u.Vector4=function(x,y,z,w)return {x=x,y=y,z=z,w=w}end
u.Color=function(r,g,b,a)return {r=r,g=g,b=b,a=a}end
u.FilterMode={Point=0};u.TextureWrapMode={Clamp=1}
MOCK.resources={}
local function vertexBuffer(mesh,native)
    if MOCK.failGpuQuery then error('simulated diagnostic query failure') end
    assert(native or mesh.uploaded,'explicit upload before GPU access')
    local b={stride=native and 16 or 80,disposed=false}
    setmetatable(b,{__index=function(_,key)
        if key=='count' then
            if MOCK.failGpuRead then error('simulated GPU descriptor read failure') end
            return native and 5388 or mesh.vertices.Length
        end
    end})
    b.Dispose=function()
        assert(not b.disposed,'dispose wrapper exactly once')
        b.disposed=true
    end
    MOCK.buffers=MOCK.buffers or {};MOCK.buffers[#MOCK.buffers+1]=b
    return b
end
local function resource()
    local r={ownedResource=true,Equals=equals};MOCK.resources[#MOCK.resources+1]=r;return r
end
u.Texture2D=function(w,h)
    local r=resource();r.width=w;r.height=h
    r.pixels={}
    r.SetPixel=function(_,x,y,c)
        assert(x>=0 and x<w and y>=0 and y<h)
        if MOCK.failTexture then error('simulated owned texture failure') end
        r.pixel=c;r.pixels[y*w+x]=c
    end
    r.Apply=function(_,a,b)assert(a==false and b==false)end
    return r
end
u.ImageConversion={LoadImage=function(t,bytes,nonReadable)
    assert(type(bytes)=='string' and #bytes>33 and nonReadable==false);return not MOCK.failTexture
end}
u.Mesh=function()
    if MOCK.failMesh then error('simulated owned mesh constructor failure') end
    local r=resource()
    setmetatable(r,{__index=function(_,key) if key=='vertexCount' then return r.vertices and r.vertices.Length or 0 end end})
    r.SetTriangles=function(_,array,submesh)
        assert(array.kind=='Int32' and array.Length%3==0 and submesh==0)
        for i=0,array.Length-1 do assert(array[i]>=0 and array[i]<r.vertices.Length)end
        r.triangles=array
    end
    r.RecalculateBounds=function()
        assert(r.vertices.kind==vec and r.normals.kind==vec and r.uv.kind==u.Vector2)
        assert(r.colors.kind==u.Color and r.tangents.kind==u.Vector4,'explicit complete native vertex attributes')
        local lo,hi=v(1e20,1e20,1e20),v(-1e20,-1e20,-1e20)
        for i=0,r.vertices.Length-1 do
            local p,n,c,t=r.vertices[i],r.normals[i],r.colors[i],r.tangents[i]
            assert(c.r==1 and c.g==1 and c.b==1 and c.a==1)
            assert(math.abs(vec.Dot(n,v(t.x,t.y,t.z)))<.0001 and math.abs(v(t.x,t.y,t.z).magnitude-1)<.0001)
            lo=v(math.min(lo.x,p.x),math.min(lo.y,p.y),math.min(lo.z,p.z));hi=v(math.max(hi.x,p.x),math.max(hi.y,p.y),math.max(hi.z,p.z))
        end
        r.bounds={size=MOCK.emptyUpload and v() or hi-lo}
        if MOCK.mismatchUpload then r.vertices[0]=v(999,999,999) end
    end
    r.UploadMeshData=function(_,unreadable)
        assert(unreadable==false and r.triangles and r.bounds,'upload after all final CPU writes, keep readable')
        assert(not r.uploaded,'upload each generated mesh only once')
        if MOCK.failGpuUpload then error('simulated GPU upload failure') end
        r.uploaded=true
    end
    r.GetVertexBuffer=function(_,stream)assert(stream==0);return vertexBuffer(r,false)end
    r.RecalculateTangents=function()error('palette UV-derived tangent generation is intentionally forbidden')end
    return r
end
u.Material=function(template)
    assert(template.normalGameMaterial,'clone native template, never edit original')
    local r=resource();r.textures={};r.colors={};r.floats={_UseDeferredRendering=1};r.passes={HGBuffer=true,DepthOnly=false};r.shader={isSupported=true}
    r.HasProperty=function()return true end
    r.SetTexture=function(_,k,v)r.textures[k]=v end
    r.SetTextureScale=function(_,k,v)assert(k=='_BaseColorMap' and v.x==1 and v.y==1)end
    r.SetTextureOffset=function(_,k,v)assert(k=='_BaseColorMap' and v.x==0 and v.y==0)end
    r.SetColor=function(_,k,v)r.colors[k]=v end
    r.SetFloat=function(_,k,v)r.floats[k]=v end
    r.FindPass=function(_,k) return not MOCK.missingColorPass and k=='HGBuffer' and 0 or -1 end
    r.GetFloat=function(_,k)return r.floats[k]end
    r.GetShaderPassEnabledAndExisted=function()return false end
    r.SetShaderPassEnabled=function(_,k,v)assert(k=='HGBuffer','ForwardOnly does NOT exist in native HGRP/Lit');r.passes[k]=v end
    return r
end
LuaUpdate={}
LuaUpdate.Add=function(self,name,fn)
    assert(name=='Tick' or name=='TailTick','verified update group only')
    if MOCK.failUpdate==name then error('simulated update registration failure') end
    MOCK.nextUpdate=MOCK.nextUpdate+1;MOCK.updates[MOCK.nextUpdate]={name=name,fn=fn};return MOCK.nextUpdate
end
LuaUpdate.Remove=function(self,key) MOCK.updates[key]=nil end
function MOCK.run(name,dt)
    local entries={};for key,entry in pairs(MOCK.updates)do if entry.name==name then entries[#entries+1]={key,entry.fn} end end
    for _,entry in ipairs(entries) do if MOCK.updates[entry[1]] and entry[2](dt or 1/60) then MOCK.updates[entry[1]]=nil end end
end
function MOCK.press(key) MOCK.keysDown[key]=true;MOCK.run('Tick') end
function MOCK.countUpdates() local n=0;for _ in pairs(MOCK.updates) do n=n+1 end return n end
function MOCK.newCharacter()
    local rootGo=go('ORIGINAL_CHARACTER')
    rootGo.layer=31;rootGo.scene={handle=9} -- Logic/HIDE root is not a render-layer template.
    local root={transform=rootGo.transform,gameObject=rootGo}
    local rig={pelvis=transform(root.transform,v(0,0.98,0))}
    rig.spine={[0]=transform(rig.pelvis,v(0,0.25,0)),Length=1}
    rig.head=transform(rig.spine[0],v(0,0.35,0))
    for _,s in ipairs({'left','right'}) do
        local x=s=='left' and -1 or 1
        rig[s..'Thigh']=transform(rig.pelvis,v(x*0.08,-0.04,0))
        rig[s..'Calf']=transform(rig[s..'Thigh'],v(0,-0.43,0))
        rig[s..'Foot']=transform(rig[s..'Calf'],v(0,-0.43,0))
        rig[s..'UpperArm']=transform(rig.spine[0],v(x*0.18,0.17,0))
        rig[s..'Forearm']=transform(rig[s..'UpperArm'],v(x*0.30,0,0))
        rig[s..'Hand']=transform(rig[s..'Forearm'],v(x*0.28,0,0))
    end
    local mover={enabled=true,moveMode='Grounded',speed=0,next=100,handles={[77]='FOREIGN'}}
    mover.GetFloorLayerMask=function()return {value=256}end
    mover.SetOverrideSpeed=function(self,speed,accel)
        if MOCK.failSpeed then error('simulated speed failure') end
        self.next=self.next+1;self.handles[self.next]={speed=speed,accel=accel};return self.next
    end
    mover.RemoveOverrideSpeed=function(self,key)
        assert(key~=77,'never remove foreign speed handle')
        if MOCK.failRemove and MOCK.failRemove>0 then MOCK.failRemove=MOCK.failRemove-1;error('simulated native remove failure') end
        self.handles[key]=nil
    end
    local fields={}
    local function nav(_,direction,clampToOne,...)
        assert(select("#",...)==0,"direct binding must omit optional Nullable target")
        local target=nil
        assert(clampToOne==false and target==nil and direction.magnitude<=1.00001)
        MOCK.navCalls=(MOCK.navCalls or 0)+1
        if MOCK.failNavBefore then error('native nav before write') end
        fields.navMoveVector=v(direction.x,direction.y,direction.z)
        fields.navMoveClampTarget=target
        if MOCK.failNavAfter then error('native nav after write') end
    end
    local vectorType={FullName='UnityEngine.Vector3'}
    local nullableType={FullName='System.Nullable`1[[UnityEngine.Vector3]]',IsGenericType=true,
        GetGenericTypeDefinition=function()return {FullName='System.Nullable`1'}end,
        GetGenericArguments=function()return {Length=1,[0]=vectorType}end}
    local inputType={FullName='Beyond.Gameplay.Core.MoveInput',IsValueType=false}
    local function fieldInfo(name)
        if MOCK.missingDriveField then return nil end
        return {Name=name,IsStatic=false,IsPublic=not MOCK.nonpublicDriveField,IsInitOnly=MOCK.readonlyDriveField,
            IsLiteral=false,DeclaringType=inputType,FieldType=nullableType,
            GetValue=function(_,obj)
                assert(obj==mover.input);return fields[name] -- CLR boxing of empty nullable is null
            end,
            SetValue=function(_,obj,value)assert(obj==mover.input and name=='navMoveVector');obj[name]=value end}
    end
    local function checkFlags(flags)
        return flags and flags.enum=='BindingFlags' and flags.value==52
    end
    inputType.GetField=function(_,name,flags)
        assert(name=='navMoveVector' or name=='navMoveClampTarget' or name=='noManualMove' or name=='pendingNoManualMove')
        MOCK.fieldResolves=(MOCK.fieldResolves or 0)+1
        if not checkFlags(flags) then return nil end -- reproduce live default lookup failure
        if MOCK.enumeratedFieldOnly then return nil end
        return fieldInfo(name)
    end
    inputType.GetFields=function(_,flags)
        assert(checkFlags(flags),'exact typed Instance|Public|NonPublic flags required')
        local result={Length=0}
        for _,name in ipairs({'navMoveVector','navMoveClampTarget','noManualMove','pendingNoManualMove'}) do
            local field=fieldInfo(name)
            if field then result[result.Length]=field;result.Length=result.Length+1 end
        end
        return result
    end
    inputType.GetMethod=function(_,name,flags)
        if not checkFlags(flags) then return nil end
        assert(name=='NavMove');MOCK.methodResolves=(MOCK.methodResolves or 0)+1
        if MOCK.missingDriveMethod then return nil end
        return {IsStatic=false,IsPublic=true,ReturnType={FullName='System.Void'},
            GetParameters=function()return {Length=3,[0]={ParameterType=vectorType},
                [1]={ParameterType={FullName='System.Boolean'},IsOptional=true,HasDefaultValue=true},[2]={ParameterType=nullableType,IsOptional=true,HasDefaultValue=true}}end,
            Invoke=function(_,obj,args)
                error('invalid arguments to Invoke') -- exact real-client 0.4.2 failure, no pretend reflection success
            end}
    end
    mover.input=setmetatable({}, {
        __index=function(_,key)
            if key=='GetType' then return function()return inputType end end
            if MOCK.throwDirectDrive and (key=='navMoveVector' or key=='navMoveClampTarget' or key=='noManualMove' or key=='pendingNoManualMove') then error('direct XLua getter unavailable') end
            if key=='NavMove' then return not MOCK.hideDirectNav and nav or nil end
            if key=='MoveMotion' then return function(_,direction) fields.manualMoveVector=direction end end
            if key=='ResetView' then return function()
                fields.noManualMove=fields.pendingNoManualMove;fields.pendingNoManualMove=nil
            end end
            if key=='moveVector' then return fields.noManualMove or fields.navMoveVector or fields.manualMoveVector or v() end
            local value=fields[key]
            if key=='navMoveVector' or key=='noManualMove' or key=='pendingNoManualMove' or key=='navMoveClampTarget' then
                -- Fault-injected direct XLua Nullable representation, without weakening CLR ownership checks.
                if value==nil and MOCK.opaqueEmptyNullable then return {opaqueNullable=true} end
                if value and MOCK.nullableWrapped then return {HasValue=true,Value=value} end
            end
            return value
        end,
        __newindex=function(_,key,value)
            if key=='navMoveVector' and value==nil and MOCK.failRelease and MOCK.failRelease>0 then
                MOCK.failRelease=MOCK.failRelease-1;error('native nullable clear failure')
            end
            fields[key]=value
        end
    })
    local animator={speed=0.7,isHuman=false,Equals=equals}
    local grounder={enabled=true,ik={references=rig},Equals=equals}
    local ch={alive=true,valid=true,inCinematic=false,rootCom=root,movementComponent=mover,
        animatorCom={animator=animator},characterAnimCom={grounderIK=grounder},rig=rig}
    ch.IsValid=function(self) return self.valid end
    setmetatable(ch,{__index=function(self,k)
        if k=='position' then return root.transform.position+(self.logicalOffset or v()) end
        if k=='rotation' then return root.transform.rotation end
    end})
    return ch
end
MOCK.character=MOCK.newCharacter()
local pc={mainCharacter=MOCK.character,blockPlayerInput=false,castingNormalAttack=false,rawMoveAxis=v()}
GameInstance={playerController=pc,isInGameplay=true}
Utils={isInFight=function()return MOCK.fight or false end,isInThrowMode=function()return false end,isInCustomAbility=function()return MOCK.skill or false end}
Notify=function(_,text) MOCK.notices[#MOCK.notices+1]=text end
MessageConst={SHOW_TOAST=1}
MOCK.errors={}
-- Match native release API: no warning member; warn is disabled, error remains active.
logger={warn=function(_) end,error=function(message) MOCK.errors[#MOCK.errors+1]=message end}
require_ex=function(path)
    assert(path=='Common/Utils/LuaResourceLoader')
    -- Native module has no `return Class`: require_ex returns its non-callable namespace.
    return {LuaResourceLoader=function()
        local loader={}
        loader.LoadMesh=function(self,path)
            error('the replacement must not load the old game mesh')
        end
        loader.LoadMaterial=function(self,path)
            assert(path:find('motorcycle',1,true) and path:sub(-4)=='.mat');MOCK.loads[#MOCK.loads+1]=path
            if MOCK.failMaterial then return nil end
            return {normalGameMaterial=true},2
        end
        loader.LoadGameObject=function(self,path)
            assert(path:find('motorcycle',1,true) and path:sub(-7)=='.prefab')
            MOCK.loads[#MOCK.loads+1]=path
            if MOCK.failPrefab then return nil end
            local g=go('S_prop_map01_motorcycle+1_001_01_lod0')
            table.remove(MOCK.objects) -- borrowed asset, not an owned runtime object
            local f=g:AddComponent('MeshFilter');f.sharedMesh={borrowedNative=true,
                UploadMeshData=function()error('never upload/modify borrowed native mesh')end,
                GetVertexBuffer=function(self,stream)assert(stream==0);return vertexBuffer(self,true)end}
            local r=g:AddComponent('MeshRenderer');r.sharedMaterial={borrowedNative=true,
                shader={isSupported=true},passes={HGBuffer=true,DepthOnly=false},
                GetShaderPassEnabledAndExisted=function()return false end};r.enabled=true
            g.GetComponents=function(self,kind)
                assert(kind=='Component')
                return {Length=MOCK.unsafePrefab and 4 or 3,[0]=g.transform,[1]=f,[2]=r}
            end
            g.transform._childCount=MOCK.prefabChild and 1 or 0
            MOCK.template=g
            return {GetComponentsInChildren=function(_,kind,inactive)
                assert(kind=='MeshRenderer' and inactive==true)
                return {Length=MOCK.ambiguousPrefab and 2 or 1,[0]=r,[1]=r}
            end},3
        end
        loader.DisposeAllHandles=function(self) MOCK.disposals=MOCK.disposals+1 end
        return loader
    end}
end

-- Test-only collision-resolved native step. Production never calls this or sets root position.
-- The fixture exposes input priority/persistence, not Unity physics acceptance.
function MOCK.setAxes(x,y) pc.rawMoveAxis=v(x,y,0) end
function MOCK.nativeStep(dt,signedSpeed)
    local ch=pc.mainCharacter;local input=ch.movementComponent.input
    local direction=input.moveVector
    if MOCK.nullableWrapped then direction=direction.Value or direction end
    local directionLength=direction.magnitude
    local magnitude=math.abs(signedSpeed or ch.movementComponent.speed or 0)
    if directionLength>0 and not MOCK.wall then
        ch.rootCom.transform.position=ch.rootCom.transform.position+direction.normalized*(magnitude*dt)
    end
    return direction
end
