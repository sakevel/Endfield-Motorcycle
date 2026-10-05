"""Reproducible neutral-frame/axle correction of the licensed Sidra model.

Run after repaint-model.py. Only own model data, no extracted game meshes.
The source FBX is a leaned, already-steered parked pose; node origins are not
axle lines. Fit the circular rim plane, straighten the fork, then level wheels.
"""
from pathlib import Path
import struct, hashlib, json, re
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
PATH=ROOT/'mod/assets/sidra-bike.zmlmesh'
EXPECTED='2e5e8c8255b51cd9df16b4f7c1a398ef52b22decc9a24e6be9359470bd9b8322'

def rotation(a,b):
    a=a/np.linalg.norm(a);b=b/np.linalg.norm(b);v=np.cross(a,b);c=np.dot(a,b)
    k=np.array(((0,-v[2],v[1]),(v[2],0,-v[0]),(-v[1],v[0],0)))
    return np.eye(3)+k+k@k/(1+c)

def axis_rotation(axis,angle):
    axis=axis/np.linalg.norm(axis);x,y,z=axis
    k=np.array(((0,-z,y),(z,0,-x),(-y,x,0)))
    return np.eye(3)+np.sin(angle)*k+(1-np.cos(angle))*k@k

def load(data):
    pos=12;parts=[]
    for i in range(struct.unpack_from('<I',data,8)[0]):
        role,nv,ni,tex=struct.unpack_from('<4I',data,pos);f=list(struct.unpack_from('<17f',data,pos+16));start=pos;pos+=84
        packed=np.frombuffer(data,dtype=np.dtype([('p','<i2',3),('n','u1',2),('uv','<u2',2)]),count=nv,offset=pos).copy()
        points=np.array(f[:3])+np.array(f[3:6])+packed['p']/32767*np.array(f[6:9])
        nxy=packed['n']/255*2-1;nz=1-np.abs(nxy).sum(1);ns=np.c_[nxy,nz]
        mask=nz<0;ns[mask,:2]=(1-np.abs(nxy[mask,::-1]))*np.where(nxy[mask]>=0,1,-1)
        ns/=np.linalg.norm(ns,axis=1)[:,None];pos+=nv*12
        indices=data[pos:pos+ni*2];pos+=ni*2
        parts.append(dict(role=role,nv=nv,ni=ni,tex=tex,f=f,points=points,normals=ns,packed=packed,indices=indices,start=start))
    assert pos==len(data)
    return parts

def fit(parts,role):
    rim=next(p['points']for p in parts if p['role']==role and not p['tex'])
    rim=np.unique(np.round(rim,5),axis=0)
    _,ev=np.linalg.eigh(np.cov(rim.T));axis=ev[:,0];axis*=np.sign(axis[0]);basis=ev[:,1:]
    xy=rim@basis;c=np.linalg.lstsq(np.c_[2*xy,np.ones(len(xy))],(xy*xy).sum(1),rcond=None)[0]
    # Axial position is immaterial to rotation. Pick the nearest point on the
    # fitted axle line to the original node origin rather than a rim side cap.
    pivot=np.array(next(p['f'][:3]for p in parts if p['role']==role))
    center=basis@c[:2]+axis*np.dot(pivot,axis)
    radii=np.linalg.norm((rim-center)@basis,axis=1)
    outer=radii[radii>.232];assert len(outer)>=24 and np.std(outer)<.0002,'expected circular rim ring'
    tire=next(p['points']for p in parts if p['role']==role and p['tex'])
    radius=float(np.quantile(np.linalg.norm((tire-center)@basis,axis=1),.995))
    return axis,center,radius

def main():
    data=PATH.read_bytes();assert hashlib.sha256(data).hexdigest()==EXPECTED,'Reconvert + repaint first; never calibrate twice'
    parts=load(data);rear,rc,rr=fit(parts,1);front,fc,fr=fit(parts,2)
    steer=np.array(next(p['f'][:3]for p in parts if p['role']==3))
    straighten=rotation(front,rear)
    for p in parts:
        if p['role'] in (2,3):
            p['points']=(p['points']-steer)@straighten.T+steer
            p['normals']=p['normals']@straighten.T
            p['f'][:3]=list((np.array(p['f'][:3])-steer)@straighten.T+steer)
    fc=straighten@(fc-steer)+steer
    upright=rotation(rear,np.array((1,0,0)));rc=upright@rc;fc=upright@fc
    pitch=math_atan2(fc[1]-rc[1]-(fr-rr),fc[2]-rc[2])
    level=axis_rotation(np.array((1,0,0)),pitch);upright=level@upright;rc=level@rc;fc=level@fc
    for p in parts:
        p['points']=p['points']@upright.T;p['normals']=p['normals']@upright.T
        p['f'][:3]=list(upright@np.array(p['f'][:3]))
    # Set exact fitted axle origins, all material pieces share the same pivot.
    for p in parts:
        if p['role']==1:p['f'][:3]=list(rc)
        if p['role']==2:p['f'][:3]=list(fc)
    allv=np.concatenate([p['points']for p in parts]);lo=allv.min(0);hi=allv.max(0)
    scale=2.2/(hi[2]-lo[2]);origin=np.array(((rc[0]+fc[0])/2,lo[1],(hi[2]+lo[2])/2))
    out=bytearray(data[:12])
    for p in parts:
        f=p['f'];pivot=(np.array(f[:3])-origin)*scale;v=(p['points']-origin)*scale-pivot
        lo,hi=v.min(0),v.max(0);center=(lo+hi)/2;extent=np.maximum((hi-lo)/2,1e-6)
        f[:9]=[*pivot,*center,*extent]
        packed=p['packed'];packed['p']=np.rint((v-center)/extent*32767).astype('<i2')
        ns=p['normals'];ns/=np.abs(ns).sum(1)[:,None];nxy=ns[:,:2].copy();mask=ns[:,2]<0
        nxy[mask]=(1-np.abs(nxy[mask,::-1]))*np.where(nxy[mask]>=0,1,-1)
        packed['n']=np.rint((nxy*.5+.5)*255).astype('u1')
        out+=struct.pack('<4I17f',p['role'],p['nv'],p['ni'],p['tex'],*f)+packed.tobytes()+p['indices']
    result=dict(sourceSHA256=EXPECTED,resultSHA256=hashlib.sha256(out).hexdigest(),
                originalRearAxis=rear.tolist(),originalFrontAxis=front.tolist(),
                wheelAxes=[1,0,0],rearRadius=rr*scale,frontRadius=fr*scale,
                rearPivot=((rc-origin)*scale).tolist(),frontPivot=((fc-origin)*scale).tolist(),
                scale=scale,notes='Circular rim fit; fork rest straightened; chassis upright/grounded. UV/index/material counts unchanged.')
    stem=np.array(next(p['f'][:3]for p in parts if p['role']==3))
    result['steerPivot']=stem.tolist()
    def vector(v):return 'V('+','.join(format(float(x),'.10g')for x in v)+')'
    lua=ROOT/'mod/motorcycle.lua';text=lua.read_text(encoding='utf8')
    replacement='-- ZML_WHEEL_GEOMETRY_BEGIN\n-- Derived from our licensed model by tools/calibrate-bike.py, not game assets.\n'
    replacement+='local BIKE={rearRadius='+format(rr*scale,'.10g')+',frontRadius='+format(fr*scale,'.10g')+',\n'
    replacement+='    rear='+vector((rc-origin)*scale)+',front='+vector((fc-origin)*scale)+',\n'
    replacement+='    steerPivot='+vector(stem)+'}\n-- ZML_WHEEL_GEOMETRY_END'
    text,count=re.subn(r'-- ZML_WHEEL_GEOMETRY_BEGIN.*?-- ZML_WHEEL_GEOMETRY_END',lambda _:replacement,text,flags=re.S)
    assert count==1,'unique owned Lua geometry block required'
    # Validate everything before replacing any output; original source FBX stays untouched.
    PATH.write_bytes(out);lua.write_text(text,encoding='utf8')
    (ROOT/'docs/BIKE_CALIBRATION.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2))

def math_atan2(y,x):
    import math
    return math.atan2(y,x)

if __name__=='__main__':main()


