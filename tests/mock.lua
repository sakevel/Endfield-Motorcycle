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
    if k=='IsChildOf' then return function(self,parent)
        while self do if self==parent then return true end;self=self.parent end;return false
    end end
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
        if kind=='BoxCollider' then
            assert(self.name=='ZML_Bike_Collision','owned collider only')
            if MOCK.failCollider then error('native collider unavailable') end
            local c={gameObject=self,transform=self.transform,Equals=equals,enabled=true}
            self.components[kind]=c;return c
        end
        if kind=='EntityRenderHelper' then
            assert(self.name=='ZML_Bike_Model','native VFX only on owned visual root')
            local h={Equals=equals,assets={},samples={},gameObject=self}
            h.InitAll=function()
                if MOCK.failEffectInit then error('native VFX init failure') end
                h.renderers={}
                local function collect(t)
                    local r=t.gameObject and t.gameObject.components.MeshRenderer
                    if r then h.renderers[#h.renderers+1]=r end
                    for _,child in ipairs(t._children) do collect(child) end
                end
                collect(self.transform);h.inited=true
            end
            h.SetSampleMode=function(_,value) assert(value==true);h.sampleMode=true end
            h.AddTimelineEffect=function(_,a)
                if not h.inited then return end -- native released helper silently ignores this
                assert(a.ownedResource and a.data.useCutoffPosYAutoBounds)
                if a.name:sub(-4)=='_add' then
                    assert(a.data.material.ownedResource and not a.data.material:IsKeywordEnabled('FACTORY_ECS_ON') and
                        a.data.material:GetFloat('FACTORY_ECS')==0,'non-ECS glow material required')
                end
                h.assets[a.assetName]=a
            end
            h.SampleVFX=function(_,name,playing,time,ending)
                if not h.inited then h.silentNoOps=(h.silentNoOps or 0)+1;return end
                assert(h.sampleMode and time>=0 and time<=2 and ending==false)
                if not h.assets[name] then
                    -- Native SampleVFX silently loads the unmodified original on
                    -- Handle dictionary miss
                    h.fallbackLoads=(h.fallbackLoads or 0)+1;return
                end
                if MOCK.failEffectSample then error('native VFX sample failure') end
                h.samples[#h.samples+1]={name=name,time=time,playing=playing}
                if name:sub(-4)=='_add' and not MOCK.missingNativeGlow then
                    if not h.glow then
                        h.glow={Equals=equals,shader={name='HGRP/Factory/UnlitFactoryBuildingGrowing'},floats={}}
                        h.glow.GetFloat=function(_,key)assert(key=='_CutOffPosY');return h.glow.floats[key]end
                        for _,r in ipairs(h.renderers) do r.sharedMaterials={Length=2,[0]=r.sharedMaterial,[1]=h.glow} end
                    end
                    h.glow.floats._CutOffPosY=MOCK.stalledNativeGlow and 0 or (name:find('disappear',1,true) and 1-time/2 or time/2)
                end
            end
            h.Reset=function()
                h.resets=(h.resets or 0)+1
                for _,r in ipairs(h.renderers or {}) do r.sharedMaterials={Length=1,[0]=r.sharedMaterial} end
                if h.glow then h.glow.destroyed=true;h.glow=nil end
            end
            h.ResetAll=function() h:Reset();h.releases=(h.releases or 0)+1;h.inited=false;h.sampleMode=false;h.assets={} end
            self.components[kind]=h;return h
        end
        assert(kind=='MeshFilter' or kind=='MeshRenderer','only renderer/owned VFX allowed')
        local c={Equals=equals,gameObject=self,forceRenderingOff=false}
        if kind=='MeshRenderer' then
            setmetatable(c,{__index=function(_,key)
                if key=='sharedMaterials' then return {Length=1,[0]=c.sharedMaterial} end
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
u.Transform='Transform';u.ParticleSystem='ParticleSystem';u.ParticleSystemRenderer='ParticleSystemRenderer'
u.ParticleSystemSimulationSpace={World='World',Local='Local'}
u.ParticleSystemScalingMode={Local='Local'};u.ParticleSystemRenderSpace={Local='Local'}
u.ParticleSystemStopBehavior={StopEmittingAndClear='Clear'}
local function particleBranch(name,borrowed)
    local g=go(name)
    g.particleSource=borrowed;g.transform._childCount=0
    if borrowed then table.remove(MOCK.objects) end
    local ps={gameObject=g,main={},emission={},shape={enabled=true},emitted=0}
    ps.Stop=function(_,children,behavior)assert(children==false and behavior=='Clear');ps.cleared=true;ps.playing=false end
    ps.Play=function(_,children)assert(not children);ps.playing=true end
    ps.Emit=function(_,count)
        assert(not g.particleSource and ps.playing and (ps.main.simulationSpace=='World' or ps.main.simulationSpace=='Local') and ps.emission.enabled==false)
        assert(ps.shape.enabled==false and ps.main.startSizeMultiplier>=.9 and ps.main.scalingMode=='Local')
        assert(g.components.ParticleSystemRenderer.pivot.magnitude==0,'owned renderer pivot centered')
        assert(count>0 and count<=4 and count%1==0 and ps.main.maxParticles==64)
        ps.emitted=ps.emitted+count
    end
    g.components={Transform=g.transform,ParticleSystem=ps,ParticleSystemRenderer={alignment=g.name=='Smoke_Tuci_01' and 'View' or 'Local'}}
    g.GetComponents=function(_,kind)assert(kind=='Component');return {Length=MOCK.unsafeSpeedFX and 4 or 3}end
    return g
end
u.RaycastHit='RaycastHit'
u.QueryTriggerInteraction={Ignore='Ignore'}
u.BoxCollider='BoxCollider';u.Collider='Collider'
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
u.Physics.BoxCastNonAlloc=function(center,half,direction,hits,rotation,reach,mask,triggers)
    assert(half.z>half.x and half.y>0 and mask==256 and triggers=='Ignore' and reach>0)
    if MOCK.failCollisionQuery then error('stripped box cast') end
    MOCK.lastCast={center=center,half=half,direction=direction,reach=reach,rotation=rotation}
    if MOCK.collisionSaturated then return 16 end
    if MOCK.castOwn then
        hits[0]={collider=M.bodyCollider,normal=-direction,point=center,distance=0};return 1
    end
    if MOCK.collisionWall then
        hits[0]={collider={Equals=equals,transform=transform()},normal=MOCK.contactNormal or -direction,point=center,distance=.05}
        return 1
    end
    return 0
end
u.Physics.OverlapBoxNonAlloc=function(center,half,colliders,rotation,mask,triggers)
    assert(half.z>half.x and mask==256 and triggers=='Ignore')
    MOCK.lastOverlap={center=center,rotation=rotation}
    if MOCK.overlapWall then colliders[0]={Equals=equals,transform=transform()};return 1 end
    return 0
end
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
    if template.particleSource then
        MOCK.speedFXClones=(MOCK.speedFXClones or 0)+1
        if MOCK.failSpeedFXClone or MOCK.failSpeedFXCloneAt==MOCK.speedFXClones then error('speed FX clone failure') end
        return particleBranch(template.name,false)
    end
    if M and M.presentation and template==MOCK.template then
        MOCK.shellCloneAttempts=(MOCK.shellCloneAttempts or 0)+1
        if MOCK.failGlowClone or MOCK.failGlowCloneAt==MOCK.shellCloneAttempts then error('factory shell clone failure') end
    end
    if template.borrowedEffect then
        assert(template.useECSRenderer==false and template.data.useCutoffPosYAutoBounds==false)
        local a={name=template.name..'(Clone)',_assetName=template._assetName,useECSRenderer=false,data={useCutoffPosYAutoBounds=false,material=template.data.material},ownedResource=true,Equals=equals}
        setmetatable(a,{__index=function(self,key)
            if key=='assetName' then
                if not self._assetName then self._assetName=self.name end
                return self._assetName
            end
        end})
        MOCK.resources[#MOCK.resources+1]=a;return a
    end
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
local mode={Grounded='Grounded',StepClimbing='StepClimbing',Pivot='Pivot',TurnStart='TurnStart',Jumping='Jumping',AIJumping='AIJumping',Falling='Falling',Landing='Landing'}
mode.External='External'
CS={UnityEngine=u,TMPro={TMP_InputField='TMP_InputField'},Beyond={Gameplay={LayerDef={DEFAULT_LAYER=8,WALKABLE_LAYER=8,ALL_STATIC_SCENE_WITH_TERRAIN_LAYER_MASK=256},Core={MovementComponent={MoveMode=mode}}}}}
u.Rendering={ShadowCastingMode={Off='Off'}}
CS.Beyond.Gameplay.View={EntityRenderHelper='EntityRenderHelper'}
CS.Beyond.Gameplay.Core.InteractOptionType={Interactive='Interactive'}
u.Time={unscaledTime=0}
hg={loadedModules={},loadedModuleNameList={}}
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
    assert(kind==vec or kind==u.Vector2 or kind==u.Vector4 or kind==u.Color or kind==u.Material or kind=='Int32' or kind=='RaycastHit' or kind=='Collider' or kind=='Object')
    return setmetatable({Length=n,kind=kind},{__newindex=function(self,i,value)
        assert(type(i)=='number' and i>=0 and i<n and i%1==0)
        if kind=='Collider' then assert(value.transform and value.Equals)
        elseif kind==u.Material then assert(value.shader,'material array takes actual controller material')
        elseif kind=='Object' then -- public object[] accepts boxed values or nil
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
u.Material=function(template,...)
    assert(select('#',...)==0,'invalid arguments to .ctor: Material takes one source, not assert message')
    if template.borrowedGlow then
        if MOCK.failEffectMaterial then error('factory glow clone failure') end
        local r=resource();r.floats={FACTORY_ECS=1};r.keywords={FACTORY_ECS_ON=true}
        r.HasProperty=function(_,k)return k=='FACTORY_ECS' end
        r.SetFloat=function(_,k,v)assert(k=='FACTORY_ECS');r.floats[k]=v end
        r.GetFloat=function(_,k)return r.floats[k]end
        r.DisableKeyword=function(_,k)assert(k=='FACTORY_ECS_ON');r.keywords[k]=nil end
        r.IsKeywordEnabled=function(_,k)return r.keywords[k]==true end
        return r
    end
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
    local mover=GameInstance.playerController.mainCharacter.movementComponent
    if mover.pendingExternalLeave then mover.pendingExternalLeave=nil;mover.moveMode='Grounded' end
    if name=='Tick' then u.Time.unscaledTime=u.Time.unscaledTime+(dt or 1/60) end
    local entries={};for key,entry in pairs(MOCK.updates)do if entry.name==name then entries[#entries+1]={key,entry.fn} end end
    for _,entry in ipairs(entries) do if MOCK.updates[entry[1]] and entry[2](dt or 1/60) then MOCK.updates[entry[1]]=nil end end
    if name=='Tick' then MOCK.keysDown={} end -- Unity key-down lasts one frame even when not polled.
end
function MOCK.press(key) MOCK.keysDown[key]=true;MOCK.run('Tick') end
function MOCK.countUpdates() local n=0;for _ in pairs(MOCK.updates) do n=n+1 end return n end
function MOCK.newCharacter()
    local rootGo=go('ORIGINAL_CHARACTER')
    -- Root layer template check
    rootGo.layer=8;rootGo.scene={handle=9}
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
    mover.velocity=v()
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
        if name=='ConsumeJump' then return {IsPublic=true,IsStatic=false,ReturnType={FullName='System.Void'},GetParameters=function()return {Length=0}end} end
        if name=='AIJump' then
            if MOCK.missingJumpMethod then return nil end
            return {IsStatic=false,IsPublic=true,ReturnType={FullName='System.Void'},
                GetParameters=function()return {Length=2,[0]={ParameterType=vectorType},
                    [1]={ParameterType={IsGenericType=true,
                        GetGenericTypeDefinition=function()return {FullName='System.Nullable`1'}end,
                        GetGenericArguments=function()return {Length=1,[0]={FullName='System.Single'}}end},
                        IsOptional=not MOCK.nonoptionalJump,HasDefaultValue=true}}end}
        end
        assert(name=='NavMove');MOCK.methodResolves=(MOCK.methodResolves or 0)+1
        if MOCK.missingDriveMethod then return nil end
        return {IsStatic=false,IsPublic=true,ReturnType={FullName='System.Void'},
            GetParameters=function()return {Length=3,[0]={ParameterType=vectorType},
                [1]={ParameterType={FullName='System.Boolean'},IsOptional=true,HasDefaultValue=true},[2]={ParameterType=nullableType,IsOptional=true,HasDefaultValue=true}}end,
            Invoke=function(_,obj,args)
                error('invalid arguments to Invoke')
            end}
    end
    mover.input=setmetatable({}, {
        __index=function(_,key)
            if key=='GetType' then return function()return inputType end end
            if MOCK.throwDirectDrive and (key=='navMoveVector' or key=='navMoveClampTarget' or key=='noManualMove' or key=='pendingNoManualMove') then error('direct XLua getter unavailable') end
            if key=='NavMove' then return not MOCK.hideDirectNav and nav or nil end
            if key=='ConsumeJump' then return function()MOCK.consumeJumpCalls=(MOCK.consumeJumpCalls or 0)+1;fields.jumpTrigger=false end end
            if key=='AIJump' then return not MOCK.hideDirectJump and function(_,velocity,...)
                assert(select('#',...)==0,'omit nullable up speed; do not pass guessed float')
                if MOCK.failJump then error('native jump unavailable') end
                mover.velocity=v(velocity.x,velocity.y,velocity.z)
                MOCK.jumpCalls=(MOCK.jumpCalls or 0)+1;MOCK.jumpVelocity=velocity
                mover.moveMode='AIJumping'
            end or nil end
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
    local movementType={FullName='Beyond.Gameplay.Core.MovementComponent'}
    movementType.GetMethod=function(_,name,flags)
        assert(checkFlags(flags))
        if MOCK.missingFlightMethod==name then return nil end
        local p={Length=0}
        if name=='TryMoveCapsule' then
            p={Length=7,[0]={ParameterType=vectorType},[1]={ParameterType={FullName='UnityEngine.Quaternion'}},
                [2]={ParameterType={FullName='System.Boolean'}},[3]={IsOut=not MOCK.badFlightOut,ParameterType={IsByRef=true,
                    GetElementType=function()return {FullName='UnityEngine.RaycastHit'}end}}}
            for i=4,6 do p[i]={IsOptional=not MOCK.badFlightOptional,HasDefaultValue=true} end
        else assert(name=='EnterExternal' or name=='LeaveExternal') end
        return {IsPublic=true,IsStatic=false,ReturnType={FullName=name=='TryMoveCapsule' and 'System.Boolean' or 'System.Void'},GetParameters=function()return p end}
    end
    mover.GetType=function()return movementType end
    mover.EnterExternal=function()
        mover.moveMode='External';MOCK.externalEnters=(MOCK.externalEnters or 0)+1
        if MOCK.failFlightEnter then error('external enter partial failure') end
    end
    mover.LeaveExternal=function()
        if MOCK.failFlightLeave then error('external leave retry required') end
        if mover.moveMode=='External' then mover.pendingExternalLeave=true end
    end
    mover.TryMoveCapsule=function(_,delta,rotation,requireExit,...)
        assert(select('#',...)==0 and requireExit==true,'out hit/default parameters omitted in direct capsule binding')
        if MOCK.failFlightCapsule then error('native capsule binding unavailable') end
        local from=root.transform.position;local after=from+delta;local normal=v();local hit=false
        local ground=MOCK.groundY or 0
        if after.y<ground then after=v(after.x,ground,after.z);normal=v(0,1,0);hit=true end
        if MOCK.flightCeiling and after.y>MOCK.flightCeiling then after=v(after.x,MOCK.flightCeiling,after.z);normal=v(0,-1,0);hit=true end
        if MOCK.flightWall and after.x>MOCK.flightWall then after=v(MOCK.flightWall,after.y,after.z);normal=v(-1,0,0);hit=true end
        root.transform.position=after
        MOCK.capsuleSteps=MOCK.capsuleSteps or {};MOCK.capsuleSteps[#MOCK.capsuleSteps+1]=delta
        if MOCK.failFlightAfterMove then error('native capsule partial write') end
        return hit,{normal=normal,distance=(after-from).magnitude}
    end
    setmetatable(mover,{__index=function(_,key)if key=='logicPos' then return root.transform.position end end})
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
pc.Jump=function()
    error('character jump must not be used')
    MOCK.jumpCalls=(MOCK.jumpCalls or 0)+1
    pc.mainCharacter.movementComponent.moveMode='Jumping'
end
MOCK.cameraOffset=0
MOCK.levelCamera={Equals=equals}
setmetatable(MOCK.levelCamera,{
    __index=function(_,key)if key=='runtimeFOVOffset' then return MOCK.cameraOffset end end,
    __newindex=function(_,key,value)
        assert(key=='runtimeFOVOffset')
        if MOCK.failCameraSet then error('camera setter unavailable') end
        MOCK.cameraOffset=value
    end})
MOCK.cameraController={levelVirtualCamera=MOCK.levelCamera}
GameInstance.cameraManager={curActiveController=MOCK.cameraController,
    GetMainLevelCameraController=function()return MOCK.cameraController end}
Utils={isInFight=function()return MOCK.fight or false end,isInThrowMode=function()return false end,isInCustomAbility=function()return MOCK.skill or false end}
Notify=function(_,text) MOCK.notices[#MOCK.notices+1]=text end
MessageConst={SHOW_TOAST=1}
PanelId={InteractOption=10}
MOCK.interact={m_optionInfoMap={foreign={identifier={sourceId='native.foreign',subIndex=0}}}}
MOCK.interact.AddInteractOption=function(self,data)
    assert(data.type=='Interactive' and data.sourceId=='zml.motorcycle.mount' and data.subIndex==0)
    self.m_optionInfoMap[data.sourceId]={identifier={sourceId=data.sourceId,subIndex=0},action=data.action,text=data.text}
    self.m_needUpdateList=true
end
MOCK.interact._TryUpdateShowingList=function(self)
    if self.m_needUpdateList then self.visibleOwn=self.m_optionInfoMap['zml.motorcycle.mount'];self.m_needUpdateList=false;return true end
    return false
end
MOCK.interact._UpdateBtnHint=function(self) self.hintUpdated=true end
MOCK.interact.RemoveInteractOption=function(self,data)
    assert(data.type=='Interactive' and data.sourceId=='zml.motorcycle.mount' and data.subIndex==0)
    if MOCK.failInteractionRemove then error('native removal unavailable') end
    self.m_optionInfoMap[data.sourceId]=nil
end
UIManager={IsOpen=function(_,id)
    assert(id==PanelId.InteractOption);return not MOCK.interactClosed,MOCK.interactClosed and nil or MOCK.interact
end,AutoOpen=function(_,id)
    assert(id==PanelId.InteractOption);MOCK.interactClosed=false;MOCK.interactAutoOpens=(MOCK.interactAutoOpens or 0)+1
    return MOCK.interact
end}
MOCK.errors={}
-- Match native release API: no warning member; warn is disabled, error remains active.
logger={warn=function(_) end,error=function(message) MOCK.errors[#MOCK.errors+1]=message end}
require_ex=function(path)
    if path=='Common/Utils/UIUtils' then return {} end
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
        loader.LoadScriptableObject=function(self,path)
            assert(path:find('/effects/vfx/p_factory_',1,true) and path:sub(-6)=='.asset')
            MOCK.loads[#MOCK.loads+1]=path
            if MOCK.failEffectAsset then return nil end
            local name=path:match('/([^/]+)%.asset$'):gsub('^p_','P_')
            local glow=name:sub(-4)=='_add' and {borrowedGlow=true,FACTORY_ECS=1,FACTORY_ECS_ON=true} or nil
            local a={borrowedEffect=true,name=name,_assetName=MOCK.cachedEffectNames and ('cached_'..name) or nil,useECSRenderer=false,data={useCutoffPosYAutoBounds=false,material=glow}}
            MOCK.borrowedEffects=MOCK.borrowedEffects or {};MOCK.borrowedEffects[#MOCK.borrowedEffects+1]=a
            return a,4
        end
        loader.LoadGameObject=function(self,path)
            if path:find('rollingdust_2101',1,true) or path:find('windline_01',1,true) then
                if MOCK.failSpeedFXLoad then return nil end
                local g=particleBranch(path:find('rollingdust',1,true) and 'Smoke_Tuci_01' or 'feng1_di01',true)
                return {GetComponentsInChildren=function(_,kind,inactive)
                    assert(kind=='ParticleSystem' and inactive==true)
                    return {Length=1,[0]=g.components.ParticleSystem}
                end}
            end
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

-- Simulated collision step for test
-- Simulated physics environment.
function MOCK.setAxes(x,y) pc.rawMoveAxis=v(x,y,0) end
function MOCK.nativeStep(dt,signedSpeed)
    local ch=pc.mainCharacter;local input=ch.movementComponent.input
    if ch.movementComponent.moveMode=='External' then return v() end
    local direction=input.moveVector
    if MOCK.nullableWrapped then direction=direction.Value or direction end
    local directionLength=direction.magnitude
    local magnitude=math.abs(signedSpeed or ch.movementComponent.speed or 0)
    local mode=ch.movementComponent.moveMode
    if mode=='AIJumping' or mode=='Falling' then
        local velocity=ch.movementComponent.velocity
        direction=v(velocity.x,0,velocity.z);directionLength=direction.magnitude;magnitude=directionLength
    end
    ch.movementComponent.velocity=directionLength>0 and not MOCK.wall and direction.normalized*magnitude or v()
    if directionLength>0 and not MOCK.wall then
        ch.rootCom.transform.position=ch.rootCom.transform.position+direction.normalized*(magnitude*dt)
    end
    return direction
end
