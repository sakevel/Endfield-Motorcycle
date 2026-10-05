"""Local-only Avatar/LOD0 linear skinning + actual production Lua pose preview.

Requires existing numpy/Pillow/Lupa. Never packages extracted game data. This is
Offline geometry preview.
"""
from pathlib import Path
import argparse, json, struct, sys, base64, math
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
PALETTE = np.array(((49,49,49),(166,170,173),(96,96,96),(229,232,230),
                    (255,239,0),(28,28,28),(247,247,242),(247,247,242)))

def qmatrix(q):
    x,y,z,w=q
    return np.array(((1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)),
                     (2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)),
                     (2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y))))

def matrix(t):
    p,q=t.position,t.rotation
    m=np.eye(4);m[:3,3]=[p[k]for k in ('x','y','z')]
    m[:3,:3]=qmatrix([q[k]for k in ('x','y','z','w')])
    return m

def model_parts():
    b=(ROOT/'mod/assets/sidra-bike.zmlmesh').read_bytes();p=12;out=[]
    for i in range(struct.unpack_from('<I',b,8)[0]):
        role,nv,ni,tex=struct.unpack_from('<4I',b,p);f=struct.unpack_from('<17f',b,p+16);p+=84
        dt=np.dtype([('p','<i2',3),('n','u1',2),('uv','<u2',2)])
        a=np.frombuffer(b,dtype=dt,count=nv,offset=p);p+=nv*12
        v=np.array(f[3:6])+a['p']/32767*np.array(f[6:9])
        ix=np.frombuffer(b,dtype='<u2',count=ni,offset=p).reshape(-1,3);p+=2*ni
        if tex:col=PALETTE[np.minimum(7,(a['uv'][:,0]/65535*8).astype(int))][ix].mean(1)
        else:col=np.tile(np.array(f[13:16])*255,(len(ix),1))
        out.append((role,np.array(f[:3]),v,ix,col))
    return out

def make_runtime(lupa_dir, helper):
    if lupa_dir:sys.path.insert(0,str(lupa_dir))
    from lupa.lua54 import LuaRuntime
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('loadstring=load')
    lua.execute((ROOT/'tests/mock.lua').read_text(encoding='utf8'))
    lua.globals().mock_decode_asset=lambda s:base64.b64decode(s)
    data='local BIKE_MESH_BASE64="'+base64.b64encode((ROOT/'mod/assets/sidra-bike.zmlmesh').read_bytes()).decode()+'"\nlocal BIKE_TEXTURE_BASE64=""'
    # Only expose local functions in the offline harness; run their original bodies.
    src=helper.replace('-- ZML_ASSET_DATA',data).replace('-- ZML_NATIVE_ACTIONS',(ROOT/'mod/native-actions.lua').read_text(encoding='utf8')).replace('return M\n','M._visual=visual; M._control=control; M._capture=captureRig; M._plan=planPose; return M\n')
    lua.globals().M=lua.execute(src)
    lua.execute('''M.api={report=function()end}; M.settings={enabled=true,scale=1.15,
        seat_height=.8,model_yaw=0,speed=10,acceleration=6,max_steer=35,render_comparison=false,
        summon_key="F6",mount_key="F7",dismiss_key="F8"}''')
    return lua

def extracted_rig(lua, directory):
    a=json.loads(next((directory/'json/Avatar').glob('*.json')).read_text())
    j=a['m_Avatar'];ids=j['m_AvatarSkeleton']['m_ID']
    paths=[a['m_TOS'].get(str(i),'')for i in ids]
    poses=j['m_DefaultPose']['m_X'];parents=[n['m_ParentId']for n in j['m_AvatarSkeleton']['m_Node']]
    g=lua.globals();nodes=[]
    for i,p in enumerate(poses):
        assert i==0 or parents[i]<i
        assert all(abs(p['s'][k]-1)<1e-4 for k in 'XYZ'),'non-unit hierarchy needs scale-aware mock'
        parent=nodes[parents[i]]if parents[i]>=0 else g.MOCK.character.rootCom.transform
        t=g.MOCK.transform(parent,g.CS.UnityEngine.Vector3(*[p['t'][k]for k in 'XYZ']))
        t.localRotation=g.MOCK.quaternion(*[p['q'][k]for k in 'XYZW']);nodes.append(t)
        t.name=paths[i].split('/')[-1]
    byname={path.split('/')[-1]:nodes[i]for i,path in enumerate(paths)if path}
    rig=lua.table()
    mapping={'pelvis':'Bip001_Pelvis','head':'Bip001_Head'}
    for side,letter in [('left','L'),('right','R')]:
        for limb in ('Thigh','Calf','Foot','UpperArm','Forearm','Hand'):
            mapping[side+limb]='Bip001_'+letter+'_'+limb
    for k,name in mapping.items():rig[k]=byname[name]
    spine=[byname[n]for n in ('Bip001_Spine','Bip001_Spine1','Bip001_Spine2')if n in byname]
    rig.spine=lua.table_from({**dict(enumerate(spine)),'Length':len(spine)})
    g.MOCK.character.characterAnimCom.grounderIK.ik.references=rig
    g.MOCK.character.rig=rig
    return nodes,ids,paths

def skins(directory, nodes, ids):
    lookup={h:i for i,h in enumerate(ids)};meshes=[]
    for path in sorted((directory/'json/Mesh').glob('*lod0.json')):
        if any(s in path.name for s in ('skill','vfx','hairshadow','shadowproxy')):continue
        m=json.loads(path.read_text());v=np.array(m['m_Vertices']).reshape(-1,3)
        if not len(m['m_Skin']):continue
        hashes=m['m_BoneNameHashes'];assert all(h in lookup for h in hashes),path.name
        # System.Numerics serialization transposes the Unity dump field names.
        bind=np.array([[[b['M'+str(col)+str(row)]for col in range(4)]for row in range(4)]for b in m['m_BindPose']])
        weights=np.array([s['weight']for s in m['m_Skin']]);indices=np.array([s['boneIndex']for s in m['m_Skin']])
        assert np.max(abs(weights.sum(1)-1))<.002
        meshes.append((path.name,v,np.array(m['m_Indices']).reshape(-1,3),weights,indices,bind,[lookup[h]for h in hashes]))
    return meshes

def deform(meshes,nodes):
    world=np.array([matrix(t)for t in nodes]);out=[]
    for name,v,tri,w,ix,bind,bones in meshes:
        matrices=world[bones]@bind;vh=np.c_[v,np.ones(len(v))]
        skinned=sum(np.einsum('nij,nj->ni',matrices[ix[:,k]],vh)*w[:,k,None]for k in range(4))[:,:3]
        color=(190,205,219)if 'body' in name or 'face' in name else (108,136,156)if 'hair' in name else (157,168,179)
        out.append((skinned,tri,np.tile(color,(len(tri),1))))
    return out

def bike(lua,parts):
    g=lua.globals();M=g.M;world=matrix(M.visual.transform);world[:3,:3]*=M.visual.transform.localScale.x
    branches={int(p.role):p.transform for p in M.parts.values()}
    out=[]
    for role,pivot,v,ix,col in parts:
        mat=matrix(branches[role])if role>0 else world.copy()
        if role>0:mat[:3,:3]*=M.visual.transform.localScale.x
        else:mat[:3,3]=(world@np.r_[pivot,1])[:3]
        out.append(((np.c_[v,np.ones(len(v))]@mat.T)[:,:3],ix,col))
    return out

def render(geometry,target,title,view):
    right=np.array((0,0,1)if view=='side'else (1,0,0)if view=='front'else(.84,0,.54),dtype=float)
    right/=np.linalg.norm(right);up=np.array((0,1,0));forward=np.cross(right,up)
    im=Image.new('RGB',(960,960),(36,39,43));draw=ImageDraw.Draw(im)
    light=np.array((-.5,1,.4));light/=np.linalg.norm(light);polys=[]
    for v,tri,col in geometry:
        points=v[tri];normal=np.cross(points[:,1]-points[:,0],points[:,2]-points[:,0]);lens=np.linalg.norm(normal,axis=1)
        normal/=np.maximum(lens[:,None],1e-9);shade=.45+.55*np.maximum(0,normal@light)
        xy=np.stack((480+(points@right)*295,880-(points@up)*295),axis=2)
        depth=(points@forward).mean(1)
        colors=np.clip(col*shade[:,None],0,255).astype(np.uint8)
        polys+=list(zip(depth,xy,colors))
    for _,points,c in sorted(polys,key=lambda p:p[0]):draw.polygon([tuple(p)for p in points],fill=tuple(c))
    draw.line((0,880,960,880),fill=(90,90,90));draw.text((20,20),title,fill=(255,239,0))
    draw.text((20,42),'LOD0 Rider Preview',fill=(225,225,225))
    target.parent.mkdir(parents=True,exist_ok=True);im.save(target)

def main():
    p=argparse.ArgumentParser();p.add_argument('--research',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--fixed-size',action='store_true',help='Require unchanged vehicle scale and knees not splayed beyond feet');
    p.add_argument('--max-steer',type=float,default=35);p.add_argument('--lupa-dir',type=Path);p.add_argument('--helper',type=Path,default=ROOT/'mod/motorcycle.lua');p.add_argument('--states',default='idle,accelerate,brake,left,right');args=p.parse_args()
    helper=args.helper.read_text(encoding='utf8');parts=model_parts();results=[]
    for name in ('typhoea','chen','laevat','pograni'):
        lua=make_runtime(args.lupa_dir,helper);g=lua.globals();g.M.settings.max_steer=args.max_steer;nodes,ids,paths=extracted_rig(lua,args.research/name)
        meshes=skins(args.research/name,nodes,ids);g.M.summon();g.M.finishPresentation();assert g.M.vehicle,'offline model creation failed'
        g.M.mount();assert g.M.lease,'offline mount failed'
        lengths={s+kind:[g.M.lease[s+kind][k]for k in ('l1','l2')]for s in ('left','right')for kind in ('Leg','Arm')}
        for state in args.states.split(','):
            g.MOCK.character.movementComponent.speed=0
            g.M.lease.bikeYaw=0;g.M.lease.lean=0;g.M.lease.steer=0
            g.M.lease.leanVelocity=0;g.M.lease.steerVelocity=0
            g.M.lease.velocity=8 if state=='brake'else 0
            g.M.lease.accel=0;g.M.lease.drive=0;g.M.lease.pitch=0
            g.M.lease.previousPosition=g.MOCK.character.rootCom.transform.position
            max_errors={};peak_pitch=0;peak_bank=0;peak_knee_overhang=0;peak_yaw=0;max_tread_gap=0
            frames=45 if state=='accelerate'else 36 if state=='brake'else 90
            for frame in range(frames):
                speed=0 if state in ('idle','lock_left','lock_right')else min(8,frame/60*8)if state!='brake'else max(0,8-frame/45*8)
                g.MOCK.character.movementComponent.speed=speed
                g.MOCK.setAxes(-1 if state in ('left','lock_left')else 1 if state in ('right','lock_right')else 0,0 if state in ('idle','lock_left','lock_right')else 1)
                try:
                    g.M._control(g.M.lease,g.GameInstance.playerController,1/60)
                    g.MOCK.nativeStep(1/60,speed)
                    g.M._visual(1/60)
                except Exception:
                    print('POSE FAILURE',name,state,frame,'scale',g.M.visual.transform.localScale.x)
                    raise
                peak_yaw=max(peak_yaw,abs(g.M.lease.bikeYaw or 0))
                if g.M.lease.groundGaps:
                    assert max(abs(g.M.lease.groundGaps[k])for k in ('rear','front'))<1e-5
                    # Independent actual tyre vertices, not the solver's own envelope.
                    for part,geometry in zip(parts,bike(lua,parts)):
                        if part[0] in (1,2) and np.linalg.norm(part[2][:,1:],axis=1).max()>.30:
                            gap=geometry[0][:,1].min()-g.MOCK.character.rootCom.transform.position.y
                            max_tread_gap=max(max_tread_gap,abs(float(gap)))
                            assert abs(gap)<1e-5,(name,state,frame,'actual tyre gap',gap)
                peak_pitch=max(peak_pitch,abs(g.M.lease.pitch));peak_bank=max(peak_bank,abs(g.M.lease.lean))
                if args.fixed_size:assert abs(g.M.visual.transform.localScale.x-g.M.settings.scale)<1e-8,'never shrink the motorcycle for a rider'
                for side in ('left','right'):
                    leg=g.M.lease[side+'Leg'];t=g.M.visual.transform
                    knee=t.InverseTransformPoint(t,leg.b.position);foot=t.InverseTransformPoint(t,leg.c.position)
                    overhang=(abs(knee.x)-abs(foot.x))*g.M.visual.transform.localScale.x
                    peak_knee_overhang=max(peak_knee_overhang,overhang)
                    if args.fixed_size:assert overhang<.04,(name,state,frame,'knee splay',overhang)
                for side in ('left','right'):
                    for kind in ('Leg','Arm'):
                        chain=g.M.lease[side+kind];target=g.M.lease.targets[side+kind]
                        error=float(np.linalg.norm(matrix(chain.c)[:3,3]-np.array([target[k]for k in ('x','y','z')])))
                        max_errors[side+kind]=max(max_errors.get(side+kind,0),error)
                        assert error<.015,(name,state,frame,side+kind,error)
            # Present all comparison states facing the same reference direction.
            q=g.CS.UnityEngine.Quaternion.Inverse(g.CS.UnityEngine.Quaternion.Euler(0,g.M.lease.bikeYaw,0))
            geometry=deform(meshes,nodes)+bike(lua,parts)
            origin=matrix(g.MOCK.character.rootCom.transform)[:3,3]
            qr=qmatrix([q[k]for k in ('x','y','z','w')]);geometry=[((v-origin)@qr.T,t,c)for v,t,c in geometry]
            for view in ('side','front','threequarter'):
                render(geometry,args.out/(name+'-'+state+'-'+view+'.png'),name+' / '+state+' / '+view,view)
            metrics={}
            for side in ('left','right'):
                for kind in ('Leg','Arm'):
                    c=g.M.lease[side+kind];metrics[side+kind]=[float(np.linalg.norm(matrix(c.b)[:3,3]-matrix(c.a)[:3,3])),float(np.linalg.norm(matrix(c.c)[:3,3]-matrix(c.b)[:3,3]))]
                    assert max(abs(a-b)for a,b in zip(metrics[side+kind],lengths[side+kind]))<2e-4
            result={'character':name,'state':state,'meshes':len(meshes),'lengths':metrics,
                    'fittedScale':float(g.M.visual.transform.localScale.x),'maxSteer':float(g.M.lease.maxSteer)if g.M.lease.maxSteer is not None else None,'maxContactError':max_errors,
                    'peakPitch':float(peak_pitch),'peakBank':float(peak_bank),'peakBodyYaw':float(peak_yaw),
                    'maxActualTreadGap':float(max_tread_gap),'riderInsideOffset':float(g.M.lease.pose.x or 0),'riderRoll':float(g.M.lease.pose.roll or 0),
                    'torsoForwardAngle':float(g.M.lease.pose.angle),'seatZ':float(g.M.lease.pose.z),
                    'peakKneeOutsideFoot':float(peak_knee_overhang),
                    'kneeToFootWidthRatio':sum(abs(g.M.visual.transform.InverseTransformPoint(g.M.visual.transform,g.M.lease[s+'Leg'].b.position).x)for s in ('left','right'))/sum(abs(g.M.visual.transform.InverseTransformPoint(g.M.visual.transform,g.M.lease[s+'Leg'].c.position).x)for s in ('left','right')),
                    'fingerJoints':sum(len(chain)for side in ('left','right')for chain in g.M.lease.fingers[side].values())}
            if g.M.lease.targets:
                result['contact_error']={s+kind:float(np.linalg.norm(matrix(g.M.lease[s+kind].c)[:3,3]-np.array([g.M.lease.targets[s+kind][k]for k in ('x','y','z')])))for s in ('left','right')for kind in ('Leg','Arm')}
            results.append(result)
        saved=[(b.node, [b.position[k]for k in ('x','y','z')], [b.rotation[k]for k in ('x','y','z','w')])for b in g.M.lease.bones.values()]
        g.M.unmount(True)
        for node,pos,rot in saved:
            assert max(abs(node.localPosition[k]-v)for k,v in zip(('x','y','z'),pos))<1e-6
            assert max(abs(node.localRotation[k]-v)for k,v in zip(('x','y','z','w'),rot))<1e-6
        print(name,len(nodes),len(meshes),'pose/lengths verified')
    (args.out/'metrics.json').write_text(json.dumps(results,indent=2))

if __name__=='__main__':main()

