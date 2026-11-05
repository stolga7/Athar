# Third-party assets and licenses

ATHAR imports two 3D models. Both are released under **CC0 1.0** (public domain
dedication), which allows commercial use, modification, redistribution and use
without attribution. Attribution is given anyway, and the source pages are
recorded so the claim can be re-checked later.

The machine-readable version of this list is
[`ASSET_MANIFEST.json`](ASSET_MANIFEST.json); `scripts/tests/combat_tests.gd`
fails the build if a model ships without a source, creator and license record
here.

## Imported models

### Hunter — "Adventurer"

| | |
|---|---|
| File | `assets/models/characters/adventurer.glb` |
| Source | https://poly.pizza/m/5EGWBMpuXq |
| Creator | Quaternius |
| Publisher | Poly Pizza |
| License | CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/ |
| Modification | Allowed |
| Redistribution in a game | Allowed |
| Commercial use | Allowed |
| Attribution | "Adventurer by Quaternius (CC0 1.0), via Poly Pizza" |
| Skeleton | 62 bones, skinned humanoid |
| Animation clips | 24, of which 11 are used |

Changes made for ATHAR: normalised to 1.80 m with feet on the origin, rotated to
face -Z, materials recoloured to the hunter palette at load time, small parts
excluded from shadow casting for mobile cost, procedural bow and quiver attached
to hand and back bones. The clip catalogue lives in
`scripts/visuals/hunter_rig.gd`.

### Deer — "Stag"

| | |
|---|---|
| File | `assets/models/animals/stag.glb` |
| Source | https://poly.pizza/m/tQdzbZ1Cmw |
| Creator | Quaternius |
| Publisher | Poly Pizza |
| License | CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/ |
| Modification | Allowed |
| Redistribution in a game | Allowed |
| Commercial use | Allowed |
| Attribution | "Stag by Quaternius (CC0 1.0), via Poly Pizza" |
| Skeleton | 38 bones, skinned quadruped with antlers |
| Animation clips | 14, of which 9 are used |

Changes made for ATHAR: normalised to 1.55 m at the shoulder with hooves on the
origin, rotated to face -Z, coat recoloured to a wild stag brown, small parts
excluded from shadow casting. Clip catalogue in `scripts/visuals/deer_rig.gd`.

## Original work

Everything else is authored for this repository and carries the project's own
license:

- trees, rocks, ground, ruins and grass — `scripts/visuals/forest.gd`,
  `wilds_ground.gd`, `wilds_environment.gd`;
- the hunter's bow and quiver — `scripts/visuals/hunter_rig.gd`;
- the training target — `scripts/gameplay/training_dummy.gd`;
- every sound — synthesised at runtime by `scripts/audio/audio_director.gd`.

No texture files, no sampled audio and no other third-party art ship with the
game.

## Rejected assets

A chibi test figure ("Matt") was downloaded once to prove the GLB import path
worked. It was never part of the game and the file was deleted before the Phase 4
commit; it is listed in the manifest's `rejected` section so the download is not a
mystery later.
