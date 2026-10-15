# M1 war-damage surface revision

Edited with the built-in image-generation tool on 2026-10-12 after the user
requested clearer evidence of the former war on M1. The edit target was
`colony-surface.png`; that original remains preserved. The runtime now uses
`colony-surface-war.png`, a 1774 x 887 spherical surface texture with mipmaps.

The revision adds breached impact basins, larger devastated settlement districts,
secondary bombardment scars, rubble and severed roads. Oceans, healthy land,
mountains, clouds and polar ice remain. A surface rotation of 0.16 places a
damaged continent on the sunlit hemisphere visible from the ordinary flight
lane. The shader suppresses surviving city lights in dark burned districts.
The other sector surfaces and moon materials retain their previous settings.

## Exact edit prompt

Use case: precise-object-edit. Edit target: the attached flat equirectangular colony planet surface texture. Preserve its exact 2:1 full-map layout, existing continent and island shapes, blue oceans, natural terrain detail, polar ice, resolution and satellite albedo style. This is a production diffuse material for a real 3D spherical planet, NOT a rendered globe or game screenshot. Change ONLY the evidence of a past invasion on land. The current tiny craters are too subtle when wrapped onto the planet. Show 5 to 7 clearly readable major old bombardment sites distributed across the main land masses, particularly the large continent in the lower center-right and the upper right continent and the left continent. Each major site should be a broad irregular charcoal-grey devastated urban district surrounding a recognizable impact basin, several roughly 70-120 pixels wide at this image scale. Use breached crater rims, dark broken city blocks, pulverized rubble, connected networks of planned angular roads abruptly severed at the scar boundaries, secondary smaller impacts and tapered ash/soot fallout fans that follow the land. Show large dead areas within formerly connected human settlement grids. Integrate the war damage into the geography with sharp geological detail and believable grey/brown transitions, not perfect black circles pasted over the image. Make the old battle unmistakable at orbital distance. Keep the majority of the planet beautiful and habitable: oceans, intact green land, mountains, ice and wispy white clouds remain. This is the aftermath of a previous war, not an active catastrophe: NO glowing lava, active explosions, fireballs, bright fire, huge planet-spanning cracks, clouds of smoke painted as 3D billboards, or space objects. Flat evenly illuminated diffuse texture, no globe lighting or baked directional shadows. Keep the left/right edge continuous for spherical wrapping. NO labels, text, symbols, ships, orbital rings, HUD, borders or watermark. One uninterrupted FLAT RECTANGULAR SURFACE MAP filling all pixels.
