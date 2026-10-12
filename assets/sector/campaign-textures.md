# Campaign texture sources

Original artwork generated with the built-in image-generation tool on 2026-10-12.
The approved concepts in `art/map-background-concepts/*-v2.png` guided the
palette, scale and campaign history. The new textures contain no player ships,
HUD or orbital structures. Real meshes supply the moving-camera silhouettes,
parallax and occlusion; these are surface materials, not painted game views.

| Runtime asset | Use |
| --- | --- |
| `nebula-panorama.png` | 1774 x 887 spherical sky, recolored and rotated per map |
| `colony-surface.png` | 1774 x 887 habitable M1 planet with old settlement networks and bombardment scars |
| `mineral-surface.png` | 1774 x 887 rocky worlds, with different rotations and amber, copper or slate tints |
| `belt-rock.png` | Detailed stone albedo for decorative asteroid belts |

Godot generates mipmaps. The shaders close the panorama seams and fade the sky's
polar caps, draw the planet terminator, and add restrained surviving city lights.
The colony texture includes cloud patterns; clouds do not currently animate.
The mineral texture includes terrain, ruined settlement footprints and mines.
One additional procedural excavation stays aligned with each extraction stream.

The existing asteroid meshes and normal maps remain in use. The generated stone
albedo applies to decorative belts; playable asteroid materials retain their
existing art. None of these assets is required to simulate a dedicated server.

## Final prompts

### Nebula panorama

Use case: stylized-concept. Asset type: production equirectangular 360-degree space sky texture for a full 3D space flight game. Create a 2:1 panoramic image at the highest available resolution, ideally 4096 x 2048, containing ONLY deep space and a richly detailed blue/cyan interstellar nebula. No planets, moons, ships, structures, asteroids, figures, horizon, text or HUD. Gorgeous physically plausible wispy gas, complex branching filaments and fine turbulent dust lanes, with small clusters of luminous pale ice-blue gas behind opaque dark charcoal clouds. Immense scale and extraordinary detail like a premium space-game environment. Keep the overall exposure dark, with luminous cloud rims that stay below white. Avoid a smooth blurry noise texture. A sweeping irregular diagonal nebula spans the panorama, strongest toward the sides, with broad dark openings of deep midnight blue in the middle for gameplay contrast. Very sparse fine stars only; the engine adds sharp stars separately. Equirectangular spherical projection: continuous texture at the left/right seam with matching dark edges, north and south poles fade to near-black uniform color. Do not depict a flat ground or photographic horizon. This is a sky MATERIAL TEXTURE, not a framed game screenshot. Strong value structure that can also be recolored to amber, copper-red, and violet while retaining intricate dust detail.

### Colony surface

Production game asset: 2:1 equirectangular albedo texture of the entire surface of an ORIGINAL habitable alien colony planet, viewed as a FLAT UNWRAPPED MAP, not a globe. Highest resolution available. Beautiful deep navy blue oceans, irregular coherent green/tan continents and archipelagos, intricate branching rivers, mountain ridges, coastlines, tan deserts, white polar ice caps. Photorealistic satellite detail, natural geology visible at every scale. Entire surface in even diffuse light, NO directional lighting, NO rendered sphere, NO space background, NO text or map lines. A thin layer of subtle white wispy weather systems, only 15 percent cloud coverage so terrain remains detailed and visible. On two continents show recognizable tiny dim warm connected former human city networks amid natural terrain; several dark round bombardment scars with ragged scorched edges interrupt these cities. Dead districts remain mostly dark. Keep damage grounded and modest, not molten world. Match left and right edges seamlessly; map both pole edges to ice. This texture will be wrapped onto a real 3D spherical planet in a space flight game. Output a single uninterrupted FLAT RECTANGULAR MAP filling the image.

### Mineral surface

Production game asset: a 2:1 equirectangular seamless albedo texture of the entire surface of an original rocky desert colony planet, as a FLAT UNWRAPPED RECTANGULAR MAP, not a sphere. Highest resolution available. Photorealistic satellite geology: ancient impact basins, mountains, eroded mesas and branching canyon systems, dusty ridges, small weathered crater fields, broad smooth desert valleys, dark charcoal volcanic plains amid pale sandstone. Warm neutral desaturated grey-brown base so the game can tint it amber, rust-red or slate violet. Several angular abandoned former human city grids carved subtly into terrain with tiny dark rectangular city footprints and road networks. Two huge abandoned terraced strip mines and adjacent scorched battle damage interrupted settlement grids, but geology remains dominant. No glowing lava or molten cracks, no ships, orbiting structures, clouds, labels, text, framing, stars or space. Flat evenly illuminated diffuse albedo; NO directional shadows and NO globe lighting or rendered sphere. Rich detail readable at all scales. Texture fills every pixel, continuous left/right edge for spherical mapping and coherent geology at both poles. A single flat rectangular surface texture intended to wrap onto a real 3D planet.

### Belt stone

Production game PBR texture asset: a single square seamless tileable asteroid rock ALBEDO map, highest available resolution, ideally 2048x2048. Entire image is a close orthographic surface scan of dark charcoal and weathered grey extraterrestrial stone. Extraordinary photorealistic geological detail: fractured sharp strata, varied blocky plates, chipped angular mineral edges, deep narrow irregular hairline crevices, dusty charcoal pockets, sparse tiny oxidized ochre mineral flecks, subtle fine grain. Strong coherent geology at large and small scales, as premium AAA realistic asteroid surfaces. Average dark medium grey, varied grey values, mostly neutral with very subtle blue-grey shadows. Even flat diffuse lighting only, NO dramatic directional illumination, NO white specular highlights, NO rendered spherical rock, no planet, no objects, no frame or space background. Avoid lava, glowing cracks, cloudy blurry noise or soft rounded pebble shapes. This is ONLY the seamless square diffuse surface color TEXTURE, not a beauty render. All four edges must tile continuously. No text, watermark or borders.
