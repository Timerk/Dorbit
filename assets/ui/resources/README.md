# Resource artwork

These seven 1254 x 1254 RGBA PNGs were generated with the built-in ImageGen tool
for the cargo trading menu. They replace the earlier 88 x 88 screenshot crops.
Each is a single sharp mineral specimen with transparent padding, without a
backdrop, floor, shadow or bloom. The generated alpha and original resolution
are preserved; Godot imports them losslessly and generates mipmaps for clean
downscaling inside the native resource cards.

The material colors retain the supplied reference direction: red-orange
Prometium, icy-blue Endurium, yellow-green Terbium, pink Prometid, green Duranium,
amber Promerium and purple Seprom. Resource identities, prices and gameplay
remain in `scripts/cargo_resources.gd`; these files only replace presentation.

Runtime paths are `res://assets/ui/resources/<resource-id>.png`.
The exact final prompts and transparency option are saved in
[resource-generation-prompts.json](../../../docs/menu-design/resource-generation-prompts.json).
Each material used its own built-in generation call, with consistent studio
lighting, crisp fractured detail and no text or interface graphics.
