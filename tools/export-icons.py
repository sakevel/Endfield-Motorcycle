"""Export original mod artwork and our deliberately simple code-native wheel glyph."""
from pathlib import Path
from PIL import Image, ImageDraw
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
for name,size,cap in [('icon',256,64*1024),('wheel-icon',128,16*1024)]:
    if name=='wheel-icon':
        # Render this tiny owned SVG vocabulary, no external raster editing.
        source=Image.new('RGBA',(1024,1024));draw=ImageDraw.Draw(source)
        for element in ET.parse(root/'assets/wheel-icon.svg').iter():
            tag=element.tag.rsplit('}',1)[-1];a=element.attrib
            if tag=='circle':
                x,y,r=(float(a[k])*4 for k in ('cx','cy','r'))
                width=int(float(a['stroke-width'])*4)
                # SVG strokes are centred, Pillow's ellipse strokes are inset.
                r+=width/2
                draw.ellipse((x-r,y-r,x+r,y+r),outline='white',width=width)
            elif tag=='polygon':
                points=[tuple(float(v)*4 for v in p.split(',')) for p in a['points'].split()]
                draw.polygon(points,fill='white')
    else:
        source=Image.open(root/'assets'/f'{name}-source.png')
    assert source.mode=='RGBA' and source.getchannel('A').getextrema()==(0,255)
    output=root/'mod'/f'{name}.png'
    source.resize((size,size),Image.Resampling.LANCZOS).save(output,optimize=True)
    assert output.stat().st_size<=cap
    print(output,output.stat().st_size)
