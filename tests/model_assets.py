"""Inspect actual bundled geometry; optional offline render is not a game screenshot."""
from pathlib import Path
import struct, math, hashlib, re, argparse
r=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--preview');a=p.parse_args()
data=(r/'mod/assets/sidra-bike.zmlmesh').read_bytes()
assert data[:8]==b'ZMLBIKE1'
pos=8

def read(fmt):
 global pos
 v=struct.unpack_from('<'+fmt,data,pos);pos+=struct.calcsize('<'+fmt);return v

def normal(v):
 n=math.sqrt(sum(x*x for x in v));return [x/n for x in v]

def sub(a,b):return [x-y for x,y in zip(a,b)]
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def circle_center(points):
 rows=[(2*y,2*z,1)for y,z in points];rhs=[y*y+z*z for y,z in points]
 m=[[sum(a[i]*a[j]for a in rows)for j in range(3)]+[sum(a[i]*b for a,b in zip(rows,rhs))]for i in range(3)]
 for i in range(3):
  pivot=max(range(i,3),key=lambda j:abs(m[j][i]));m[i],m[pivot]=m[pivot],m[i]
  divisor=m[i][i];assert abs(divisor)>1e-9;m[i]=[v/divisor for v in m[i]]
  for j in range(3):
   if i!=j:
    multiplier=m[j][i];m[j]=[v-multiplier*w for v,w in zip(m[j],m[i])]
 return m[0][-1],m[1][-1]
PALETTE=((49,49,49),(166,170,173),(96,96,96),(229,232,230),
         (255,239,0),(28,28,28),(247,247,242),(247,247,242))
parts=[];roles=set();triangles=[];vertices=[];nverts=0;swatches=set()
for _ in range(read('I')[0]):
 role,nv,ni,textured=read('4I');f=read('17f')
 pivot,center,extent=f[:3],f[3:6],f[6:9]
 uvmin,uvextent,color=f[9:11],f[11:13],f[13:17]
 vs=[];ns=[];uvs=[]
 for _ in range(nv):
  x,y,z,nx,ny,u,v=read('3h2B2H')
  nx=nx/255*2-1;ny=ny/255*2-1;nz=1-abs(nx)-abs(ny)
  if nz<0:nx,ny=(1-abs(ny))*(1 if nx>=0 else -1),(1-abs(nx))*(1 if ny>=0 else -1)
  vs.append([pivot[j]+center[j]+extent[j]*v/32767 for j,v in enumerate((x,y,z))])
  ns.append(normal((nx,ny,nz)));uvs.append((uvmin[0]+uvextent[0]*u/65535,uvmin[1]+uvextent[1]*v/65535))
  if textured:
   uv=uvs[-1];index=int(uv[0]*8)
   assert 0<=index<8 and abs(uv[0]-(index+.5)/8)<1/65535 and abs(uv[1]-.5)<1/65535
   swatches.add(index)
 if textured:assert color==(1,1,1,1),'do not multiply painted palette by source .588 grey'
 elif role in (0,3):assert all(abs(color[j]-v)<1e-6 for j,v in enumerate((247/255,247/255,242/255,1)))
 else:assert all(abs(color[j]-v)<1e-6 for j,v in enumerate((28/255,28/255,28/255,1)))
 indices=read(str(ni)+'H');assert max(indices)<nv and ni%3==0
 for i in range(0,ni,3):
  ids=indices[i:i+3];points=[vs[j] for j in ids]
  area=cross(sub(points[1],points[0]),sub(points[2],points[0]))
  # Quantization can flip almost-degenerate slivers; no substantial inverted surfaces.
  if dot(area,area)>1e-10:assert dot(area,ns[ids[0]])>-1e-7
  triangles.append((points,[ns[j] for j in ids],[uvs[j] for j in ids],textured,color))
 vertices+=vs;nverts+=nv;roles.add(role);parts.append((role,pivot))
 if role in (1,2) and not textured:
  # The circular rim must be centred on the local X axis. This would reject
  # the previous baked 11-degree lean / 15-degree front-wheel steering.
  radial=[math.hypot(v[1]-pivot[1],v[2]-pivot[2])for v in vs]
  max_radius=max(radial)
  ring={(round(v[1]-pivot[1],5),round(v[2]-pivot[2],5))for v,d in zip(vs,radial)if d>max_radius*.995}
  assert len(ring)>=16 and max(math.hypot(y,z)for y,z in ring)-min(math.hypot(y,z)for y,z in ring)<.0003
  assert max(map(abs,circle_center(ring)))<.0001,'axle is at ring centre'
assert pos==len(data) and len(parts)==11 and nverts==29204 and len(triangles)==23016 and roles==set(range(5))
assert 4 in swatches and 0 in swatches and 1 in swatches,'yellow frame + dark mechanics + exposed metal'
lo=[min(v[j] for v in vertices)for j in range(3)];hi=[max(v[j] for v in vertices)for j in range(3)]
assert abs((hi[2]-lo[2])-2.2)<1e-4 and abs(lo[1])<1e-4
h=(r/'src/asset_hashes.hpp').read_text()
assert hashlib.sha256(data).hexdigest() in h
assert hashlib.sha256((r/'mod/assets/Textures.png').read_bytes()).hexdigest() in h
assert b'Attribution 4.0 International' in (r/'mod/licenses/CC-BY-4.0.txt').read_bytes()
print('PASS: 11 parts, 29204 vertices, 23016 triangles; ground/axes/winding/pivots/UVs/SHA256/licenses')
if a.preview:
 from PIL import Image,ImageDraw
 im=Image.new('RGB',(1200,800),(37,40,44));draw=ImageDraw.Draw(im)
 # Approximate lit orthographic 3/4 projection, sort polygons by depth.
 right=normal((.65,0,.76));forward=normal(cross(right,(0,1,0)));up=normal(cross(forward,right))
 light=normal((-.4,.9,.3))
 projected=[]
 for points,ns,uvs,textured,color in triangles:
  points2=[(600+dot(v,right)*370,660-dot(v,up)*370)for v in points]
  depth=sum(dot(v,forward)for v in points)/3
  if textured:
   uv=[sum(x[j]for x in uvs)/3 for j in range(2)]
   pixel=PALETTE[min(7,int(max(0,uv[0])*8))]
  else:pixel=(255,255,255)
  shade=.48+.52*max(0,dot(normal([sum(n[j] for n in ns)for j in range(3)]),light))
  rgb=tuple(round(max(0,min(255,pixel[j]*color[j]*shade)))for j in range(3))
  projected.append((depth,points2,rgb))
 for _,points,rgb in sorted(projected):draw.polygon(points,fill=rgb)
 draw.text((24,24),'Sidra Low-Poly Motorcycle #2 - ZML offline asset preview (not in-game)',fill=(240,240,240))
 Path(a.preview).parent.mkdir(parents=True,exist_ok=True);im.save(a.preview)
