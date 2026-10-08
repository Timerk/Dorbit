# Resource artwork

These eight high-resolution RGBA PNGs were generated with the built-in ImageGen tool
for the cargo trading menu. They replace the earlier 88 x 88 screenshot crops.
Each is a single sharp mineral specimen with transparent padding, without a
backdrop, floor, shadow or bloom. The generated alpha and original resolution
are preserved; Godot imports them losslessly and generates mipmaps for clean
downscaling inside the native resource cards.

The material colors retain the supplied reference direction: red-orange
Prometium, icy-blue Endurium, yellow-green Terbium, pink Prometid, green Duranium,
amber Promerium and purple Seprom. Skylab adds ivory/gray Xenomit at 1280 x 1280;
the original seven renders are 1254 x 1254. Resource identities, prices and gameplay
remain in `scripts/cargo_resources.gd`; these files only replace presentation.

Runtime paths are `res://assets/ui/resources/<resource-id>.png`.
The exact final prompts and transparency option are saved in
[resource-generation-prompts.json](../../../docs/menu-design/resource-generation-prompts.json).
Each material used its own built-in generation call, with consistent studio
lighting, crisp fractured detail and no text or interface graphics.

Xenomit used the [exact Skylab addition prompt](../../../docs/menu-design/xenomit-generation-prompt.txt)
with `transparent_background: true`, preserving its generated alpha and resolution.
