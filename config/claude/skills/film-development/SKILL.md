---
name: film-development
description: Alp's black-and-white film development data - tested exposure indexes, developer times, agitation, and how to run and measure an exposure-ladder test from DSLR scans. Use when the user asks how to expose or develop a film (Fomapan, Rodinal, DD-X, stand development), wants to analyze a test sheet or negative density, or mentions EI, Zone System placement, or the SP-445 tank.
---

# Film development

Tested results and the method used to get them. Add a row per film/developer test; keep the date.

## Tested combinations

| Film | Developer | Process | EI | Notes | Tested |
|---|---|---|---|---|---|
| Fomapan 100 4x5 | Rodinal 1:100 | Stand, 1 h, one tap at 30 min | **100** | Zone III book at 0.35 net density. Very dense negative, highlights compress (apparent shoulder above ~1.4 net). | 2026-11-19 |
| Fomapan 100 4x5 | DD-X 1+4 | ~8 min at 20.5 °C, SP-445 (475 mL, 95 mL concentrate), 30 s initial agitation, then 2 slow inversions every 30 s | **50** | Zone III book at 0.33 net. Book-to-wall range ~1.1, a normal negative. Add 15-20% time only if highlights look flat in real pictures. | 2026-11-19 |

The one-stop difference is the hour-long stand gaining shadow speed, not a DD-X fault. Dilution, volume, temperature, concentrate age (opened 2 weeks) and lighting were all checked.

Film base + fog measured ~0.16 on both sheets.

## Exposure-ladder test (dark-slide method)

One sheet, four exposures, each strip one stop apart:

1. Meter a dark reference object and place it on Zone III. Note the scene range.
2. Pick a shutter speed short enough to avoid reciprocity failure (Fomapan: stay under 1 s) and build exposure with repeated clicks.
3. Slide fully out, 1 click (1x). Push the slide in a quarter, 1 click (2x). Another quarter, 2 clicks (4x). Another quarter, 4 clicks (8x).
4. Strips run 1x, 2x, 4x, 8x = EI 200, 100, 50, 25 for a base of EI 200. The image is inverted, so the densest strip is on the opposite side from where the slide went in.

The dark slide's end is slightly curved, so strip boundaries are not straight lines. Sample at least 25 px (at 2056 px wide) away from each boundary.

## Measuring a test sheet from a DSLR scan

Scan with the `canon-dslr-scanning` skill. Work on the linear green channel (`dcraw_emu -4 -T -Z`, then `magick ... -sample 25%`, dump with `-endian LSB gray:` and read as `<u2`).

- **Net density** = log10(pad / pixel) minus base + fog. With bare pad visible, fit a quadratic to the pad border to get the illumination under the film; read base + fog from the unexposed rebate.
- **Target:** Zone III shadow at about 0.35-0.40 net; Zone I at about 0.10.
- **Reading the EI:** find the strip where the Zone III reference hits the target. Cross-check with a uniform dark surface that spans several strips (a table rail worked) to get density per stop.
- **Under-exposed vs under-developed:** less exposure shifts all densities by a similar amount; less development gives a deficit that grows toward the highlights.

### Stray light limits highlight readings

Dense areas (above ~1.5-2.0 net) read too bright because of flare, so exposure steps in the highlights look nearly flat. Measured on 2026-11-19:

- Bare pad around the sheet, room lights on: worst.
- Passepartout mask plus room lights off: floor ~37% lower (about 0.2 density, roughly one scene stop). Each change contributed about half.
- Shadows and midtones (below ~1.5) are unaffected either way.
- After masking, the negative's own thin areas supply about two thirds of the stray light, so a better surround mask gains little.
- The 300gsm passepartout transmits ~20% of pad light. Fine as a surround, useless as a slot mask.
- Untested fix for reading the top of the curve: a fully opaque slot mask (foil under card) exposing only a thin strip of the dense region across all exposure strips.

With a mask there is no bare pad in frame: shoot a flat-field frame of the empty window at identical settings, or anchor densities to a thin patch measured earlier.

## X-ray film: Fuji HR-U (double-sided, blue base)

First sheets 2026-11-19/20, developed in the SP-445.

- **Tank marks:** the SP-445 holder scratches the emulsion on the side that rests against the holder plate. Develop X-ray film in a flat tray instead if scratches matter.
- **Which side is which:** a negative reads mirrored when viewed from the lens-facing side. Scan both ways up; the scan that looks backwards has the lens side toward the camera. A scratch is slightly crisper in the scan where its side faces the camera (5 px vs 6 px wide in the test), if focus is unchanged.
- **Stripping one side with household bleach** (good side taped down on plain glass, never the ANR glass): dense areas kept about 60% of their density (1.52 to 0.93), thin areas unchanged, overall range roughly halved (1.35 to 0.65). The remaining emulsion was intact. The result scans fine but is flat; poor rinsing left vertical streaks and extra dust. If planning to strip, give more development to build contrast first.
- **Inverting:** see `make-bw-sidecar.py` in the canon-dslr-scanning skill (white balance from the film's raw colour, `--mono`).
