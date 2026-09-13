# DarkOrbit ship review

82 editable Blender models, built from online ship pictures for visual review. Nothing is connected to gameplay. `art/.gdignore` keeps the collection out of Godot's asset import.

## Look at the ships

- Open [darkorbit-fleet.blend](darkorbit-fleet.blend) in Blender to browse the whole collection. The Outliner groups the ships by standard hull, Plus ship, and playable variant. Select a ship and press numpad period to frame it. Middle-drag orbits; the wheel zooms. Numpad 7 shows the top and numpad 1 the front.
- Open an individual `.blend` through the roster below for a closer view. Each file includes a camera and lighting. Press F12 to render. Parts remain editable beneath a named ship root.
- Browse the rendered sheets: [01](overview-1.jpg), [02](overview-2.jpg), [03](overview-3.jpg).
- Compare the online reference pictures: [01](references-1.jpg), [02](references-2.jpg), [03](references-3.jpg). Their ordering matches the rendered sheets.

## Coverage and fidelity

The collection covers 43 entries in the standard ship index, 12 Plus ships, and 27 additional playable variants from their parent ship pages. The roster was checked on September 13, 2026 against [DarkOrbitWiki's ship index](https://darkorbitwiki.com/ships/) and [Plus index](https://darkorbitwiki.com/ships-plus/). Legacy ships remain included for players who own them. Shop and event availability varies. NPCs, drones, P.E.T., admin-only ships, and cosmetic-only skins are excluded.

These are stylized, low-poly reconstructions, not extracted game assets or exact replicas. The references guide silhouette and color; depth, underside construction, paneling, and some Plus attachments are interpretations. Related ships share components. Stat-bearing paint variants retain their own named models and colors. Relative ship sizes are for review and are not canonical measurements.

The downloaded reference pictures depict Bigpoint's DarkOrbit ships. They are included for comparison, with their original page and image URLs recorded in [roster.json](roster.json). The model meshes were authored in this collection. Final production art still needs your review.

## Files and rebuilding

Blender 5.2.1 LTS generated the files. Models use local mesh geometry, material colors, editable bevel modifiers, and no external texture dependencies. The forward direction is -Y and up is +Z. There are no collision meshes, LODs, rigs, or game exports yet.

From the repository root:

```powershell
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/build_models.py
rtk proxy D:/Blender/blender.exe --background --factory-startup --python art/ship-review/build_fleet.py
```

To rebuild one ship, append `-- Goliath` to the first command. Quote names containing spaces. `build_fleet.py` reopens every model and checks its root, mesh geometry, materials, finite coordinates, and nondegenerate faces before saving the fleet. Results are in [validation.json](validation.json). Preview sheets are static review artifacts.

All 82 models passed the Blender checks, and all three completed render sheets were visually inspected. Desktop mouse-interaction verification could not run because the computer-use helper's native pipe was unavailable. Gameplay checks were not run for this isolated art collection.

## Roster

| Ship | Blender model | Render | Reference |
| --- | --- | --- | --- |
| Aegis | [Open](models/aegis.blend) | [View](previews/aegis.jpg) | [Source](https://darkorbitwiki.com/ships/aegis/) |
| Basilisk | [Open](models/basilisk.blend) | [View](previews/basilisk.jpg) | [Source](https://darkorbitwiki.com/ships/basilisk/) |
| Berserker | [Open](models/berserker.blend) | [View](previews/berserker.jpg) | [Source](https://darkorbitwiki.com/ships/berserker/) |
| Bigboy | [Open](models/bigboy.blend) | [View](previews/bigboy.jpg) | [Source](https://darkorbitwiki.com/ships/bigboy/) |
| Centurion | [Open](models/centurion.blend) | [View](previews/centurion.jpg) | [Source](https://darkorbitwiki.com/ships/centurion/) |
| Citadel | [Open](models/citadel.blend) | [View](previews/citadel.jpg) | [Source](https://darkorbitwiki.com/ships/citadel/) |
| Cyborg | [Open](models/cyborg.blend) | [View](previews/cyborg.jpg) | [Source](https://darkorbitwiki.com/ships/cyborg/) |
| Defcom | [Open](models/defcom.blend) | [View](previews/defcom.jpg) | [Source](https://darkorbitwiki.com/ships/defcom/) |
| D-Raven | [Open](models/d-raven.blend) | [View](previews/d-raven.jpg) | [Source](https://darkorbitwiki.com/ships/d-raven/) |
| Diminisher | [Open](models/diminisher.blend) | [View](previews/diminisher.jpg) | [Source](https://darkorbitwiki.com/ships/diminisher/) |
| Disruptor | [Open](models/disruptor.blend) | [View](previews/disruptor.jpg) | [Source](https://darkorbitwiki.com/ships/disruptor/) |
| Goliath | [Open](models/goliath.blend) | [View](previews/goliath.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| Goliath-X | [Open](models/goliath-x.blend) | [View](previews/goliath-x.jpg) | [Source](https://darkorbitwiki.com/ships/goliath-x/) |
| Hammerclaw | [Open](models/hammerclaw.blend) | [View](previews/hammerclaw.jpg) | [Source](https://darkorbitwiki.com/ships/hammerclaw/) |
| Hecate | [Open](models/hecate.blend) | [View](previews/hecate.jpg) | [Source](https://darkorbitwiki.com/ships/hecate/) |
| Holo | [Open](models/holo.blend) | [View](previews/holo.jpg) | [Source](https://darkorbitwiki.com/ships/holo/) |
| Hyperion | [Open](models/hyperion.blend) | [View](previews/hyperion.jpg) | [Source](https://darkorbitwiki.com/ships/hyperion/) |
| Keres | [Open](models/keres.blend) | [View](previews/keres.jpg) | [Source](https://darkorbitwiki.com/ships/keres/) |
| Leonov | [Open](models/leonov.blend) | [View](previews/leonov.jpg) | [Source](https://darkorbitwiki.com/ships/leonov/) |
| Liberator | [Open](models/liberator.blend) | [View](previews/liberator.jpg) | [Source](https://darkorbitwiki.com/ships/liberator/) |
| Mimesis | [Open](models/mimesis.blend) | [View](previews/mimesis.jpg) | [Source](https://darkorbitwiki.com/ships/mimesis/) |
| Nostromo | [Open](models/nostromo.blend) | [View](previews/nostromo.jpg) | [Source](https://darkorbitwiki.com/ships/nostromo/) |
| N-Ambassador | [Open](models/n-ambassador.blend) | [View](previews/n-ambassador.jpg) | [Source](https://darkorbitwiki.com/ships/n-ambassador/) |
| N-Diplomat | [Open](models/n-diplomat.blend) | [View](previews/n-diplomat.jpg) | [Source](https://darkorbitwiki.com/ships/n-diplomat/) |
| N-Envoy | [Open](models/n-envoy.blend) | [View](previews/n-envoy.jpg) | [Source](https://darkorbitwiki.com/ships/n-envoy/) |
| Orcus | [Open](models/orcus.blend) | [View](previews/orcus.jpg) | [Source](https://darkorbitwiki.com/ships/orcus/) |
| Paladin | [Open](models/paladin.blend) | [View](previews/paladin.jpg) | [Source](https://darkorbitwiki.com/ships/paladin/) |
| Phoenix | [Open](models/phoenix.blend) | [View](previews/phoenix.jpg) | [Source](https://darkorbitwiki.com/ships/phoenix/) |
| Piranha | [Open](models/piranha.blend) | [View](previews/piranha.jpg) | [Source](https://darkorbitwiki.com/ships/piranha/) |
| Pusat | [Open](models/pusat.blend) | [View](previews/pusat.jpg) | [Source](https://darkorbitwiki.com/ships/pusat/) |
| Retiarus | [Open](models/retiarus.blend) | [View](previews/retiarus.jpg) | [Source](https://darkorbitwiki.com/ships/retiarus/) |
| Sentinel | [Open](models/sentinel.blend) | [View](previews/sentinel.jpg) | [Source](https://darkorbitwiki.com/ships/sentinel/) |
| Solace | [Open](models/solace.blend) | [View](previews/solace.jpg) | [Source](https://darkorbitwiki.com/ships/solace/) |
| Solaris | [Open](models/solaris.blend) | [View](previews/solaris.jpg) | [Source](https://darkorbitwiki.com/ships/solaris/) |
| Spearhead | [Open](models/spearhead.blend) | [View](previews/spearhead.jpg) | [Source](https://darkorbitwiki.com/ships/spearhead/) |
| Spectrum | [Open](models/spectrum.blend) | [View](previews/spectrum.jpg) | [Source](https://darkorbitwiki.com/ships/spectrum/) |
| Tartarus | [Open](models/tartarus.blend) | [View](previews/tartarus.jpg) | [Source](https://darkorbitwiki.com/ships/tartarus/) |
| Tempest | [Open](models/tempest.blend) | [View](previews/tempest.jpg) | [Source](https://darkorbitwiki.com/ships/tempest/) |
| Vengeance | [Open](models/vengeance.blend) | [View](previews/vengeance.jpg) | [Source](https://darkorbitwiki.com/ships/vengeance/) |
| Venom | [Open](models/venom.blend) | [View](previews/venom.jpg) | [Source](https://darkorbitwiki.com/ships/venom/) |
| Yamato | [Open](models/yamato.blend) | [View](previews/yamato.jpg) | [Source](https://darkorbitwiki.com/ships/yamato/) |
| Y-Ronin | [Open](models/y-ronin.blend) | [View](previews/y-ronin.jpg) | [Source](https://darkorbitwiki.com/ships/y-ronin/) |
| Zephyr | [Open](models/zephyr.blend) | [View](previews/zephyr.jpg) | [Source](https://darkorbitwiki.com/ships/zephyr/) |
| Citadel Plus | [Open](models/citadel-plus.blend) | [View](previews/citadel-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/citadel-plus/) |
| Goliath Plus | [Open](models/goliath-plus.blend) | [View](previews/goliath-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/goliath-plus/) |
| Hammerclaw Plus | [Open](models/hammerclaw-plus.blend) | [View](previews/hammerclaw-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/hammerclaw-plus/) |
| Hecate Plus | [Open](models/hecate-plus.blend) | [View](previews/hecate-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/hecate-plus/) |
| Liberator Plus | [Open](models/liberator-plus.blend) | [View](previews/liberator-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/liberator-plus/) |
| Pusat Plus | [Open](models/pusat-plus.blend) | [View](previews/pusat-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/pusat-plus/) |
| Retiarus Plus | [Open](models/retiarus-plus.blend) | [View](previews/retiarus-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/retiarus-plus/) |
| Solace Plus | [Open](models/solace-plus.blend) | [View](previews/solace-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/solace-plus/) |
| Solaris Plus | [Open](models/solaris-plus.blend) | [View](previews/solaris-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/solaris-plus/) |
| Spearhead Plus | [Open](models/spearhead-plus.blend) | [View](previews/spearhead-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/spearhead-plus/) |
| Spectrum Plus | [Open](models/spectrum-plus.blend) | [View](previews/spectrum-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/spectrum-plus/) |
| Tartarus Plus | [Open](models/tartarus-plus.blend) | [View](previews/tartarus-plus.jpg) | [Source](https://darkorbitwiki.com/ships-plus/tartarus-plus/) |
| A-Elite | [Open](models/a-elite.blend) | [View](previews/a-elite.jpg) | [Source](https://darkorbitwiki.com/ships/aegis/) |
| A-Veteran | [Open](models/a-veteran.blend) | [View](previews/a-veteran.jpg) | [Source](https://darkorbitwiki.com/ships/aegis/) |
| Solemn | [Open](models/solemn.blend) | [View](previews/solemn.jpg) | [Source](https://darkorbitwiki.com/ships/bigboy/) |
| C-Elite | [Open](models/c-elite.blend) | [View](previews/c-elite.jpg) | [Source](https://darkorbitwiki.com/ships/citadel/) |
| C-Veteran | [Open](models/c-veteran.blend) | [View](previews/c-veteran.jpg) | [Source](https://darkorbitwiki.com/ships/citadel/) |
| G-Surgeon | [Open](models/g-surgeon.blend) | [View](previews/g-surgeon.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Saturn | [Open](models/g-saturn.blend) | [View](previews/g-saturn.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Centaur | [Open](models/g-centaur.blend) | [View](previews/g-centaur.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Referee | [Open](models/g-referee.blend) | [View](previews/g-referee.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Goal | [Open](models/g-goal.blend) | [View](previews/g-goal.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Vanquisher | [Open](models/g-vanquisher.blend) | [View](previews/g-vanquisher.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Sovereign | [Open](models/g-sovereign.blend) | [View](previews/g-sovereign.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Peacemaker | [Open](models/g-peacemaker.blend) | [View](previews/g-peacemaker.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Exalted | [Open](models/g-exalted.blend) | [View](previews/g-exalted.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Veteran | [Open](models/g-veteran.blend) | [View](previews/g-veteran.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Enforcer | [Open](models/g-enforcer.blend) | [View](previews/g-enforcer.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Bastion | [Open](models/g-bastion.blend) | [View](previews/g-bastion.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Kick | [Open](models/g-kick.blend) | [View](previews/g-kick.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Ignite | [Open](models/g-ignite.blend) | [View](previews/g-ignite.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| G-Champion | [Open](models/g-champion.blend) | [View](previews/g-champion.jpg) | [Source](https://darkorbitwiki.com/ships/goliath/) |
| S-Elite | [Open](models/s-elite.blend) | [View](previews/s-elite.jpg) | [Source](https://darkorbitwiki.com/ships/spearhead/) |
| S-Veteran | [Open](models/s-veteran.blend) | [View](previews/s-veteran.jpg) | [Source](https://darkorbitwiki.com/ships/spearhead/) |
| V-Lightning | [Open](models/v-lightning.blend) | [View](previews/v-lightning.jpg) | [Source](https://darkorbitwiki.com/ships/vengeance/) |
| V-Revenge | [Open](models/v-revenge.blend) | [View](previews/v-revenge.jpg) | [Source](https://darkorbitwiki.com/ships/vengeance/) |
| V-Avenger | [Open](models/v-avenger.blend) | [View](previews/v-avenger.jpg) | [Source](https://darkorbitwiki.com/ships/vengeance/) |
| V-Corsair | [Open](models/v-corsair.blend) | [View](previews/v-corsair.jpg) | [Source](https://darkorbitwiki.com/ships/vengeance/) |
| V-Adept | [Open](models/v-adept.blend) | [View](previews/v-adept.jpg) | [Source](https://darkorbitwiki.com/ships/vengeance/) |
