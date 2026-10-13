"""Compose review sheets using only Dorbit model renders and generated concepts."""
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]/'.tools/art-python'))
from PIL import Image, ImageDraw, ImageFont

BG=(22,27,33)
CARD=(29,35,42)
WHITE=(228,233,238)
MUTED=(153,167,179)
FONT=Path('C:/Windows/Fonts/segoeui.ttf')
NAMES=['Aegis','Goliath','Bigboy','Defcom','Leonov','Liberator','Nostromo',
       'Phoenix','Piranha','Spearhead','Vengeance','Yamato']


def font(size):
    return ImageFont.truetype(str(FONT),size) if FONT.exists() else ImageFont.load_default(size=size)


def label(im,xy,text,size=22,fill=WHITE):
    ImageDraw.Draw(im).text(xy,text,font=font(size),fill=fill)


def put(im,path,rect,trim=False):
    image=Image.open(path).convert('RGBA')
    if trim:
        bounds=image.getchannel('A').point(lambda a:255 if a>40 else 0).getbbox()
        if bounds:
            image=image.crop(bounds)
    x,y,w,h=rect
    image.thumbnail((w,h),Image.Resampling.LANCZOS)
    # A deliberate enlargement for small references, labeled on the sheet.
    if image.width < w*.8 and image.height < h*.8:
        scale=min(w/image.width,h/image.height)
        image=image.resize((round(image.width*scale),round(image.height*scale)),Image.Resampling.LANCZOS)
    im.paste(image,(x+(w-image.width)//2,y+(h-image.height)//2),image)


for name in NAMES:
    if len(sys.argv)>1 and name not in sys.argv[1:]:
        continue
    slug=name.lower()
    for suffix in ['', '-rear', '-top', '-side', '-front', '-underside']:
        path=HERE/'previews'/(slug+suffix+'.png')
        with Image.open(path) as render:
            bounds=render.getchannel('A').getbbox()
            assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<render.width and bounds[3]<render.height, 'Clipped ship: '+str(path)
    im=Image.new('RGB',(1800,1270),BG)
    d=ImageDraw.Draw(im)
    label(im,(40,24),name+' / six consistent model views',36)
    label(im,(42,76),'Base hull | -Y forward | Z up | review scale',21,MUTED)
    views=[('', 'PERSPECTIVE'),('-rear','REAR'),('-top','TOP'),('-side','SIDE'),('-front','FRONT'),('-underside','UNDERSIDE')]
    for i,(suffix,title) in enumerate(views):
        x=30+(i%3)*590
        y=130+(i//3)*540
        d.rounded_rectangle((x,y,x+570,y+515),radius=14,fill=CARD)
        label(im,(x+20,y+17),title,20,MUTED)
        put(im,HERE/'previews'/(slug+suffix+'.png'),(x+15,y+65,540,426),trim=True)
    label(im,(42,1220),'Reference study. Underside, internal joints and exact panel depths are inferred.',21,MUTED)
    im.save(HERE/'previews'/(slug+'-views.jpg'),quality=94)
    print('SHEETS',name)

if len(sys.argv)==1:
    # Contact sheet preserves each complete generated turnaround. The actual
    # ship views above come from one mesh and are the consistent angle source.
    concepts=Image.new('RGB',(2400,2200),BG)
    label(concepts,(38,22),'Dorbit / ship concept turnarounds',36)
    label(concepts,(40,76),'Generated design references | full sheets and exact prompts in concepts/README.md',22,MUTED)
    for i,name in enumerate(NAMES):
        x=20+(i%3)*795
        y=135+(i//3)*510
        label(concepts,(x+12,y+8),name,26)
        put(concepts,HERE/'concepts'/(name.lower()+'.png'),(x+8,y+48,772,446))
    concepts.save(HERE/'concepts/overview.jpg',quality=94)
