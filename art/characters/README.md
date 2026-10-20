# Operation Foothold character portraits

Generated with the built-in image generation tool for the three story contacts introduced in [PR #118](https://github.com/Timerk/Dorbit/pull/118).

These are proposed visual designs. Roles and names come from `scripts/story.gd`; age, appearance, clothing and facial details are art direction proposed for this set rather than established story facts. The images are review assets outside Godot's runtime imports; this change does not add portraits to the HUD.

| Character | Portrait |
| --- | --- |
| Commander Rhea Vance | [rhea-vance.png](rhea-vance.png) |
| Chief Engineer Tomas Brell | [tomas-brell.png](tomas-brell.png) |
| Dr. Imani Sato, xenobiology | [imani-sato.png](imani-sato.png) |

Each original is a square PNG with an opaque station backdrop. Visually reviewed for consistent composition, readable faces, distinct role clothing and absence of text or watermarks.

## Generation prompts

Each image used the shared prompt below followed by its character subject prompt.

### Shared prompt

Use case: stylized-concept. Asset type: finished character portrait for Dorbit, an original 3D space exploration and alien combat game. Create ONE square image, one person only, chest-up portrait, face large and clearly readable at small comms-panel size, head fully visible with space above, centered shoulders, looking toward viewer. Grounded cinematic science-fiction game concept painting with realistic anatomy and subtle painterly surface detail, convincing fabric and metal, restrained industrial design. Outpost 01 is an isolated newly arrived frontier space station: cobalt armor, structural steel, cyan instrument lights. Softly blurred dark station interior backdrop, cool cyan rim lighting and soft neutral facial key light, clear skin tones, face brighter than backdrop. No text, no lettering, no labels, no watermark, no border, no UI overlay, no helmet obscuring face, no weapons, no extra people. Original design, consistent portrait series.

### vance

Subject: Commander Rhea Vance, military commander of Outpost 01. A woman around 45, medium olive skin, short swept-back dark hair with a few silver strands, steady grey eyes, angular face with subtle age lines. Quiet resolve, protective authority, slightly tired but alert after arriving in a hostile sector. Practical dark navy command jacket with structured cobalt shoulder panels, understated unlettered rank tabs and small metallic collar fasteners, discreet communication earpiece. No ornate ceremonial uniform. Slight three-quarter shoulders and near-frontal face.

### brell

Subject: Chief Engineer Tomas Brell, responsible for repairing Outpost 01 and bringing its approach beacon online using salvaged materials. A broad-built man around 50, warm tan skin, short tousled salt-and-pepper hair, cropped beard, expressive dark eyes, weathered face with faint grease smudge at temple. Capable, pragmatic expression with a hint of dry humor. Heavy graphite work coverall, worn ochre utility shoulder panel, rolled-open collar, believable small tools secured at chest, safety goggles resting above forehead, compact comms earpiece. Face unobscured. Slight three-quarter shoulders and near-frontal face.

### sato

The original generation prompt below was followed by the appearance revision recorded afterward. The current portrait reflects the user's requested East Asian appearance.

Subject: Dr. Imani Sato, Outpost 01 xenobiologist investigating alien activity, an orbital defense ring that was dismantled, and a lost colony's flight recorder. A woman around 35, deep brown skin, dark brown eyes, black tightly curled hair gathered into a neat low bun, thoughtful attentive expression, subtly raised brow suggesting scientific curiosity and concern. Practical off-white and slate field-research jacket over a dark teal station undersuit, small sealed sample containers securely clipped at chest, understated wrist instrument barely visible, compact comms earpiece. Scientific field specialist rather than medical doctor; no stethoscope. Slight three-quarter shoulders and near-frontal face.

### Sato appearance revision

Built-in image editing used the original Sato portrait as its reference. Final edit prompt:

Use case: precise-object-edit. Edit the supplied fictional game character portrait of Dr. Imani Sato. User-requested change: redesign her appearance as an East Asian woman of Japanese heritage around 35, with natural light-to-medium skin tone, dark brown eyes and straight black hair neatly gathered into a low bun, a few fine loose strands. Thoughtful, attentive, capable xenobiologist with the same restrained expression. Realistic individual facial anatomy, no caricature or exaggerated features. Keep the square chest-up framing, near-frontal face, pose, off-white and slate field-research jacket, dark teal undersuit, sample containers, comms earpiece, cyan lighting, softly blurred industrial space-station backdrop, and grounded cinematic game portrait finish consistent with the reference. Change only her facial appearance and hair as needed for the requested redesign. Preserve clothing, equipment, background and composition as closely as possible. One person only, no text, no lettering, no labels, no border, no watermark.
