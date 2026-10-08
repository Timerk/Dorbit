"""Assemble consistent model views and comparisons from Blender's final renders."""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parents[1]/'.tools/art-python'))
from PIL import Image, ImageDraw, ImageFont

NAMES = ('Scout','Sentinel','Heavy')
VIEWS = ('perspective','top','side','front','rear','underside')
DETAILS = ('armor-detail','mount-detail','drive-detail')
BG = (22,27,33)
CARD = (41,48,57)
WHITE = (233,238,243)
MUTED = (161,173,185)
ACCENTS = {'Scout':(237,173,77),'Sentinel':(228,96,88),'Heavy':(172,126,232)}
FONT = Path('C:/Windows/Fonts/segoeui.ttf')


def label(image,xy,text,size=24,color=WHITE):
    font = ImageFont.truetype(str(FONT),size) if FONT.exists() else ImageFont.load_default(size=size)
    ImageDraw.Draw(image).text(xy,text,font=font,fill=color)


def place(image,path,rect):
    source = Image.open(path).convert('RGBA')
    x,y,w,h = rect
    source.thumbnail((w,h),Image.Resampling.LANCZOS)
    image.paste(source,(x+(w-source.width)//2,y+(h-source.height)//2),source)


def render_path(name: str, view: str) -> Path:
    return HERE/'previews'/(name.lower()+('' if view=='perspective' else '-'+view)+'.png')


def main() -> None:
    checks = []
    for name in NAMES:
        for view in VIEWS+DETAILS:
            path = render_path(name,view)
            with Image.open(path) as render:
                assert render.size == (1600,1200), 'Draft or unexpected render: '+str(path)
                bounds = render.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
                assert bounds, 'Empty render: '+str(path)
                if view in VIEWS:
                    assert bounds[0]>12 and bounds[1]>12 and bounds[2]<render.width-12 and bounds[3]<render.height-12, 'Clipped model: '+str(path)
                checks.append({'file':path.name,'size':list(render.size),'alpha_bounds':list(bounds),
                               'intentional_detail_crop':view in DETAILS})
        sheet = Image.new('RGB',(2100,1740),BG)
        draw = ImageDraw.Draw(sheet)
        label(sheet,(40,22),name+' / textured model views',40)
        label(sheet,(42,82),'Six cameras, one editable model | -Y forward, +Z up | review units',24,MUTED)
        for i,view in enumerate(VIEWS):
            x = 24+(i%3)*692
            y = 146+(i//3)*752
            draw.rounded_rectangle((x,y,x+668,y+727),radius=16,fill=CARD)
            label(sheet,(x+22,y+19),view.upper(),23,ACCENTS[name])
            place(sheet,render_path(name,view),(x+10,y+80,648,618))
        label(sheet,(42,1682),'Actual Blender renders. Surface maps and approved concept are packed into the .blend.',24,MUTED)
        sheet.save(HERE/'previews'/(name.lower()+'-views.jpg'),quality=95)
        compare = Image.new('RGB',(2400,1130),BG)
        label(compare,(40,22),name+' / approved concept and authored model',40)
        label(compare,(42,82),'The model resolves differences between generated angles.',24,MUTED)
        label(compare,(42,157),'APPROVED CONCEPT',23,ACCENTS[name])
        label(compare,(1280,157),'ACTUAL TEXTURED MESH',23,ACCENTS[name])
        place(compare,HERE/'concepts'/(name.lower()+'.png'),(30,205,1190,820))
        ImageDraw.Draw(compare).rounded_rectangle((1240,205,2370,1025),radius=16,fill=CARD)
        place(compare,render_path(name,'perspective'),(1240,205,1130,820))
        label(compare,(42,1070),'Detailed armor, open wing mounts, recessed drives and sensor slits. Runtime integration follows separately.',24,MUTED)
        compare.save(HERE/'previews'/(name.lower()+'-comparison.jpg'),quality=95)
        details=Image.new('RGB',(2400,1000),BG)
        label(details,(40,22),name+' / actual mesh detail',40)
        label(details,(42,82),'Contoured armor and edge wear | exposed wing machinery | recessed turbine and drive plating',24,MUTED)
        for i,view in enumerate(DETAILS):
            x=24+i*793
            ImageDraw.Draw(details).rounded_rectangle((x,154,x+770,914),radius=16,fill=CARD)
            label(details,(x+22,176),view.replace('-detail','').upper(),25,ACCENTS[name])
            place(details,render_path(name,view),(x+10,238,750,650))
        label(details,(42,946),'Detail crops rendered in Blender from the same saved model. Packed 4K PBR surface maps.',24,MUTED)
        details.save(HERE/'previews'/(name.lower()+'-details.jpg'),quality=95)
    overview = Image.new('RGB',(2400,1120),BG)
    label(overview,(40,22),'Dorbit / three alien spacecraft',42)
    label(overview,(42,84),'Textured Blender models built from the approved Scout, Sentinel and Heavy concepts',25,MUTED)
    for i,name in enumerate(NAMES):
        x = 22+i*793
        ImageDraw.Draw(overview).rounded_rectangle((x,153,x+770,1010),radius=18,fill=CARD)
        label(overview,(x+25,180),name,38,ACCENTS[name])
        place(overview,render_path(name,'perspective'),(x+10,255,750,695))
    label(overview,(42,1060),'Actual model renders | layered armor and machinery | editable .blend + textured .glb + 4K PBR maps',24,MUTED)
    overview.save(HERE/'previews/overview.jpg',quality=95)
    (HERE/'render-validation.json').write_text(json.dumps({'renders':len(checks),'checks':checks},indent=2)+'\n')
    print('Verified 27 final renders; composed six-view sheets, detail sheets, comparisons and overview.')


if __name__ == '__main__':
    main()
