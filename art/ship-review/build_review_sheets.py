"""Compose review sheets from actual Blender renders and recorded references."""
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
    for suffix in ['', '-rear', '-top', '-side', '-front']:
        path=HERE/'previews'/(slug+suffix+'.png')
        with Image.open(path) as render:
            bounds=render.getchannel('A').getbbox()
            assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<render.width and bounds[3]<render.height, 'Clipped ship: '+str(path)
    im=Image.new('RGB',(1800,1080),BG)
    d=ImageDraw.Draw(im)
    label(im,(42,26),name+' / reference comparison',36)
    label(im,(44,78),'Base appearance reconstruction | editable Blender model',21,MUTED)
    d.rounded_rectangle((30,135,630,1000),radius=16,fill=CARD)
    d.rounded_rectangle((650,135,1770,1000),radius=16,fill=CARD)
    label(im,(54,155),'SUPPLIED BASE IMAGE',20,MUTED)
    put(im,HERE/'references'/(slug+'-base.png'),(75,190,510,415),trim=True)
    source=Image.open(HERE/'references'/(slug+'-base.png'))
    label(im,(54,610),f'{source.width} x {source.height} source, enlarged for comparison',19,MUTED)
    if name=='Aegis':
        label(im,(54,670),'ADDITIONAL GEOMETRY VIEW',20,MUTED)
        put(im,HERE/'references/aegis-engineering-browser-crop.png',(54,710,552,260))
    elif name=='Goliath':
        label(im,(54,670),'SUPPLEMENTARY ANGLE',20,MUTED)
        put(im,HERE/'references/goliath-secondary.webp',(126,720,380,240))
    elif name=='Liberator':
        label(im,(54,670),'SUPPLEMENTARY HANGAR VIEW',20,MUTED)
        put(im,HERE/'references/liberator-secondary.webp',(170,706,300,278))
    else:
        label(im,(54,700),'REFERENCE LIMITS',20,MUTED)
        for j,line in enumerate(['Base catalogue render guides shape and paint.',
                                 'Small details and unseen surfaces are inferred.',
                                 'Source image is packed into the Blender file.']):
            label(im,(54,752+j*42),line,19,MUTED)
    label(im,(678,155),'NEW MODEL / RENDERED IN BLENDER',20,MUTED)
    put(im,HERE/'previews'/(slug+'.png'),(675,210,1070,735),trim=True)
    label(im,(44,1025),'Angles are approximate. Unseen surfaces and small mechanical details are reconstructed.',21,MUTED)
    im.save(HERE/'previews'/(slug+'-comparison.jpg'),quality=94)

    im=Image.new('RGB',(1800,1270),BG)
    d=ImageDraw.Draw(im)
    label(im,(40,24),name+' / five views',36)
    label(im,(42,76),'Base hull | -Y forward | Z up | review scale',21,MUTED)
    views=[('', 'PERSPECTIVE'),('-rear','REAR'),('-top','TOP'),('-side','SIDE'),('-front','FRONT')]
    for i,(suffix,title) in enumerate(views):
        x=30+(i%3)*590
        y=130+(i//3)*540
        d.rounded_rectangle((x,y,x+570,y+515),radius=14,fill=CARD)
        label(im,(x+20,y+17),title,20,MUTED)
        put(im,HERE/'previews'/(slug+suffix+'.png'),(x+15,y+65,540,426),trim=True)
    x,y=1210,670
    label(im,(x+10,y+40),'Inspect in Blender',29)
    for j,text in enumerate(['Middle-drag to orbit','Numpad 7 / 1 / 3 for fixed views','F12 to render','References packed in the file']):
        label(im,(x+10,y+103+j*48),text,21,MUTED)
    label(im,(42,1220),'Reference study. Underside, internal joints and exact panel depths are inferred.',21,MUTED)
    im.save(HERE/'previews'/(slug+'-views.jpg'),quality=94)
    print('SHEETS',name)

if len(sys.argv)==1:
    im=Image.new('RGB',(2000,2110),BG)
    d=ImageDraw.Draw(im)
    label(im,(36,22),'Twelve base ships / revised Blender model review',36)
    label(im,(38,79),'Aegis retained as benchmark | Revised geometry, colors and assemblies on the other eleven ships',22,MUTED)
    for i,name in enumerate(NAMES):
        x=20+(i%4)*495
        y=140+(i//4)*640
        d.rounded_rectangle((x,y,x+475,y+610),radius=14,fill=CARD)
        label(im,(x+18,y+18),name,28)
        label(im,(x+18,y+67),'SOURCE',17,MUTED)
        put(im,HERE/'references'/(name.lower()+'-base.png'),(x+22,y+100,431,195),trim=True)
        label(im,(x+18,y+318),'MODEL',17,MUTED)
        put(im,HERE/'previews'/(name.lower()+'.png'),(x+12,y+348,451,242),trim=True)
    label(im,(38,2070),'Sources enlarged for review. Fine details and hidden surfaces are reconstructed. Ships are not shown to a common scale.',21,MUTED)
    im.save(HERE/'previews/additional-ships-overview.jpg',quality=94)
    print('OVERVIEW all twelve ships')
