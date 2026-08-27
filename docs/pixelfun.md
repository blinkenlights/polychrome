# Pixelfun

Unified Pixel Fun picks a transform backend from `Installation.arrangement()`:

- **`:circular`** → Sphere (seamless ring: SO(3) orientation, Möbius/Merlin zoom, `nx/ny/nz`)
- **`:linear`** → Flat (canvas translate / rotate / uniform zoom / sway)

## Builtin formulas

Prefer paired or oscillating time terms to avoid one-way drift on rings:

```
sin(x*0.7+t*2)*cos(y*0.7+t*1.3)

sin(x*0.4+sin(y*0.3+t)*3+t)*cos(y*0.4+cos(x*0.3+t)*3+t)

sin(x*0.5+t)*cos(y*0.5+t)+sin((x+y)*0.35+t*1.5)*0.5

sin(hypot(x,y)*5-t*3)*sin(hypot(x+3,y+3)*5+t*2)

sin(x*y*0.06+sin(t)*x*0.2-t*2)*cos(hypot(x,y)*2+t)
```

## Formula design notes

| Pattern | Ring effect | Alternative |
|---|---|---|
| `sin(x - t)` | constant drift in +x | `sin(x)*cos(t)` |
| `sin(x + t)` | constant drift in −x | pair with opposite sign |
| `sin(hypot(x,y) - t)` | radial pulse | usually fine |
| mixed `+t` / `-t` | often net one-way | use same \|t\| on both axes |

Both backends share **Rotation** (°/s) and its **Auto** sweep, which swings ±*Sweep*° out and back — the same number of degrees on a wall as on a ring. **Translate Auto** likewise pans a position offset in px on both, bounded by half the installation.

The manual translate differs: **Flat** has **Translate X** and **Translate Y** as separate drift amplitudes (each capped at half the installation's width/height, so a 233×8 wall gets a wide X and a shallow Y), and **Zoom** is a uniform × scale. **Sphere** drives position through orbit/elevation instead, and zooms via Möbius/Merlin. **Time direction** reverses formula animation and manual motion together.

## Translate/rotate auto immunity (Sphere)

Formulas that use only `i` and `t` (no `x`, `y`, `nx`, `ny`, `nz`) are unaffected by translate/rotate auto: **Leuchtplankton** and **Sternenhimmel**. Do not enable trans/rot auto on those presets.
