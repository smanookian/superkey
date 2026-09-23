# Superkey mascot — brief for Nano Banana Pro

Direction chosen with the author: **(c) playful pixel robot**, name to be
picked from the shortlist below. No voice; it communicates with pose, a
single text line in the coach, and three sound effects.

## Where it lives (hard constraints)

- The coach card is ~440×~180 logical px, bottom-right of the screen, styled
  in whatever Omarchy theme the user runs (dark *and* light themes exist:
  Tokyo Night, Catppuccin, Gruvbox, Nord, Rose Pine, Flexoki Light, …).
- The robot occupies a **40×40 logical px** slot at the card's top-left.
  Sprites are authored at **64×64 px on a true pixel grid** (so 1 sprite
  pixel ≈ 0.6 screen px at 1×; crisp at 2× HiDPI) with transparent
  background. Never larger — it must read as a small companion, not a
  character in the way.
- It must work on both dark and light backgrounds → the body needs a
  **1-px darker outline** and no pure-white/pure-black fills.
- Color: **max 8 colors**, one accent. The accent should be a warm orange
  close to Stevinator's burnt orange `#C44D2B` — it's the only brand color
  the robot carries, and it will contrast with every Omarchy theme.
- Style: chunky, readable pixel art (think 16-bit console, not 8-bit
  minimalism and not "HD pixel art"). Clean silhouettes. No gradients, no
  anti-aliasing, no outlines thicker than 1 px.

## Personality (fits the Stevinator voice: playful, not fluffy)

A small, eager utility robot who *knows the desktop* — lights up when a
shortcut lands, tilts its head when you're stuck, never cheers with
confetti. Dry, precise, a little nerdy. It points; it doesn't dance.

Physical concept (pick one, keep it consistent everywhere):

1. **Keycap-head** — a rounded square head shaped like a keyboard keycap,
   with a single glowing "⌘/Super"-style symbol as its face. Body: a tiny
   two-legged chassis. *Most on-brand for "Superkey".*
2. **Terminal-box** — a boxy CRT/terminal monitor head with a blinking
   cursor as its mouth, antenna on top.
3. **Owl-bot** — round head, big round lens eyes, small wings that act as
   pointing arms.

Recommendation: **1**. It *is* the product name.

## The six states (one sprite each, same character, same scale, same light)

| State | Used when | What it does |
|---|---|---|
| `idle` | waiting for the user | neutral stance, eye/symbol dim-lit, feet planted |
| `blink` | idle, every ~4 s | identical to idle with the symbol/eyes briefly off (1-frame variant) |
| `point-right` | a window step is active (highlight frame on screen) | one arm extended right, body leaning slightly |
| `think` | Hint shown, or nothing observable ("I can't see this one") | head tilted, a small "?" or dim symbol, one arm to chin |
| `success` | step verified | symbol at full brightness, small hop pose (feet off ground), no particles/confetti |
| `done` | lesson complete | both arms up, symbol bright, a single small orange spark above the head |

Each state is delivered as a separate 64×64 PNG. `blink` and `idle` must
differ only in the symbol/eyes so they can alternate cleanly.

## Prompting workflow for Nano Banana Pro

1. **Concept sheet first.** One image: the character in `idle`, front view,
   64×64 pixel-art scaled up 8× for review, transparent background, with
   the 8-color palette shown as swatches beside it. Iterate on this until
   the silhouette is right; nothing else is generated before it's approved.
2. **Each state via image editing from the approved idle**, not fresh
   generation — that is what keeps proportions, palette, and line weight
   consistent. Prompt pattern: *"Same character, same palette, same pixel
   grid and scale. Change only: …"* and describe the pose from the table.
3. **Post-processing (I do this):** snap to a true 64×64 grid, quantize to
   the palette, strip semi-transparent edge pixels, verify every state
   shares the exact footprint, export PNGs to `assets/robot/`, wire a
   sprite player into the coach (idle↔blink, transitions by phase, all
   disabled under *Less motion* except state swaps).

### Prompt — concept sheet (paste into Nano Banana Pro)

> Pixel art character sprite, 64×64 pixel grid, shown enlarged 8× with
> visible square pixels, transparent background. A small friendly utility
> robot whose head is a rounded keyboard keycap; on the front of the keycap
> a single glowing diamond/four-loop "Super key" symbol serves as its face.
> Tiny two-legged chassis body, short stubby arms, standing front-on in a
> neutral idle pose. 16-bit console style: chunky, clean silhouette, 1-pixel
> darker outline around all shapes, flat fills, no gradients, no
> anti-aliasing, no text. Palette limited to 8 colors: cool grays for the
> body, one warm burnt-orange accent (#C44D2B) for the glowing symbol and
> one small detail, one dark outline color. Show the 8 palette swatches in a
> row beside the character. Readable at small size, calm and precise, not
> cute-overload.

### Prompt — a state (image-edit on the approved idle)

> Same character, same 64×64 pixel grid, same scale, same 8-color palette,
> same 1-pixel outline style, transparent background. Change only the pose:
> [point-right → right arm fully extended to the right at shoulder height,
> body leaning slightly right, symbol lit]. Everything else identical.

Repeat with the pose text from the table for `think`, `success`, `done`,
and `blink` ("change only: symbol and eyes switched off").

## Name shortlist (for the robot, not the app)

- **Cap** — it's a keycap. Short, says the thing.
- **Modi** — from *modifier* key.
- **Bit** — small, digital, friendly.
- **Meta** — the historical name of the Super key.

## Deliverables back to me

Six PNGs (or one sheet) at any size as long as the pixel grid is honest;
I'll normalize them. Tell me which concept and name you picked so the
coach copy can use it ("Cap can't see this one — press Continue…").
