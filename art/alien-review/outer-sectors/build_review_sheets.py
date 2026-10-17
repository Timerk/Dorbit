"""Compose review galleries from the saved Blender camera renders."""
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
module=importlib.util.spec_from_file_location('review_sheets',HERE.parent/'build_review_sheets.py')
sheets=importlib.util.module_from_spec(module)
module.loader.exec_module(sheets)
Image,ImageDraw=sheets.Image,sheets.ImageDraw
NAMES=('Skirmisher','Raider','Marauder','Warden','Ravager','Overlord')
ACCENTS=((116,230,178),(55,189,184),(255,195,110),(238,121,84),(183,136,250),(237,112,193))
VIEWS=('perspective','top','side','front','rear','underside')
DETAILS=('armor-detail','mount-detail','drive-detail')


def render_path(name,view):
    return HERE/'previews'/(name.lower()+('' if view=='perspective' else '-'+view)+'.png')


def card(image,rect,caption,path,accent):
    x,y,w,h=rect
    ImageDraw.Draw(image).rounded_rectangle((x,y,x+w,y+h),radius=14,fill=sheets.CARD)
    sheets.label(image,(x+20,y+14),caption,24,accent)
    sheets.place(image,path,(x+8,y+62,w-16,h-72))


def main():
    checks=[]
    overview=Image.new('RGB',(2400,1890),sheets.BG)
    sheets.label(overview,(38,20),'Dorbit / outer-sector alien models',44)
    sheets.label(overview,(40,81),'M2, M3 and M4 | actual Blender renders from six editable models',25,sheets.MUTED)
    for index,(name,accent) in enumerate(zip(NAMES,ACCENTS)):
        for view in VIEWS+DETAILS:
            path=render_path(name,view)
            with Image.open(path) as render:
                assert render.size==(1600,1200), str(path)
                bounds=render.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
                assert bounds, 'Empty render: '+str(path)
                if view in VIEWS:
                    assert bounds[0]>12 and bounds[1]>12 and bounds[2]<1588 and bounds[3]<1188, 'Clipped model: '+str(path)
                checks.append(dict(file=path.name,size=list(render.size),alpha_bounds=list(bounds),detail=view in DETAILS))
        views=Image.new('RGB',(2100,1700),sheets.BG)
        sheets.label(views,(38,20),name+' / model views',42)
        sheets.label(views,(40,81),'Six cameras, one mesh construction | -Y forward, +Z up | review units',24,sheets.MUTED)
        for i,view in enumerate(VIEWS):
            card(views,(22+i%3*693,140+i//3*750,670,725),view.upper(),render_path(name,view),accent)
        sheets.label(views,(40,1650),'Actual Blender renders. The concept and 4K surface maps are packed into the .blend.',23,sheets.MUTED)
        views.save(HERE/'previews'/(name.lower()+'-views.jpg'),quality=94)
        details=Image.new('RGB',(2400,960),sheets.BG)
        sheets.label(details,(38,20),name+' / mesh details',42)
        sheets.label(details,(40,81),'Fitted armor and coating wear | open hydraulic joints | recessed rear propulsion',24,sheets.MUTED)
        for i,view in enumerate(DETAILS):
            card(details,(22+i*793,146,770,750),view.replace('-detail','').upper(),render_path(name,view),accent)
        details.save(HERE/'previews'/(name.lower()+'-details.jpg'),quality=94)
        compare=Image.new('RGB',(2400,1120),sheets.BG)
        sheets.label(compare,(38,20),name+' / reference and model',42)
        sheets.label(compare,(40,81),'The authored geometry resolves inconsistent generated construction views.',24,sheets.MUTED)
        card(compare,(22,145,1170,890),'APPROVED REFERENCE',HERE.parent/'concepts/outer-sectors'/(name.lower()+'.png'),accent)
        card(compare,(1208,145,1170,890),'ACTUAL BLENDER MODEL',render_path(name,'perspective'),accent)
        sheets.label(compare,(40,1060),'Editable geometry, packed 4K PBR finish, portable GLB and derived game model.',24,sheets.MUTED)
        compare.save(HERE/'previews'/(name.lower()+'-comparison.jpg'),quality=94)
        card(overview,(22+index%3*793,146+index//3*850,770,825),name,render_path(name,'perspective'),accent)
    sheets.label(overview,(40,1840),'Modeled armor, mechanisms and drives | nine cameras per model | no concept images projected onto the meshes',23,sheets.MUTED)
    overview.save(HERE/'previews/overview.jpg',quality=94)
    (HERE/'render-validation.json').write_text(json.dumps(dict(renders=len(checks),checks=checks),indent=2)+'\n')
    print('Verified 54 renders; composed six view sheets, detail sheets, comparisons and overview.')


if __name__=='__main__':
    main()
