# ADR-0002: Heat-cool dual-marker dial

- **Status:** Accepted
- **Date:** 2026-07-19
- **Context issue:** [#116](https://github.com/MikeSiekkinen/RestThermostat/issues/116)
- **Related:** [#102](https://github.com/MikeSiekkinen/RestThermostat/issues/102) (Schedule Auto editor — shares the deadband), [#113](https://github.com/MikeSiekkinen/RestThermostat/issues/113)/[#114](https://github.com/MikeSiekkinen/RestThermostat/issues/114) (Home keyboard entry — the `TempEntryDialog` + single tap-target this builds on)
- **Supersedes / superseded by:** —

> The dial's entire model — from painter to gesture to write — was built around **one** scalar target; `interactive_temperature_dial.dart` explicitly called proper dual-marker UI "a follow-up ticket." This ADR records the decisions from the 2026-07-19 `/grill-with-docs` pass that turned heat-cool into a true two-setpoint control, because they cut across several interacting mechanisms (band paint, push physics, paired reconciliation) that would otherwise be implicit in the code.

## Context

In `heat-cool` mode a thermostat holds **two** setpoints — a heat (low) floor and a cool (high) ceiling — with a band between them the equipment leaves alone. Before this change the Home dial collapsed that to one number + one marker, and the write used a **nearest-bound heuristic**: it replaced whichever of low/high was closer to the dragged value and inferred the other. That's lossy (the user can't see or directly set both) and surprising (dragging near the middle silently moves whichever bound happened to be closer).

The model already carried the fields (`Device.targetTemperatureHigh`/`Low`, nullable), and the Details/Schedule headers already rendered the `low – high` band read-only. This ticket makes the **Home dial** itself a two-setpoint control.

## Decision

### 1. Labels — HEAT / COOL

The two markers and the stacked center readout are labeled **HEAT** (low) and **COOL** (high), matching the Schedule editor and the eco sheet's `LOW (HEAT)` / `HIGH (COOL)` vocabulary. The center stacks `HEAT` over its value, a divider, then the COOL value over `COOL`, sized so the pair is ≈ the single-setpoint number's height.

### 2. Deadband — one 1.5°C constant

A minimum **1.5°C (≈3°F)** gap is enforced between the two setpoints, defined **once** as `TemperatureDial.deadbandCelsius` and referenced by both the dial and #102's Schedule Auto editor, so the two can never disagree. Chosen over a per-surface constant (drifts) and over "no gap" (lets the band collapse to zero, which the equipment can't honor).

### 3. Drag = grab-and-push

Tap and drag both move the marker **nearest** the touch (by tick distance; an exact-midpoint tie grabs HEAT). The grabbed marker is resolved **once at gesture start** and held for the whole drag — so pushing one marker past the other doesn't hand the drag off mid-gesture (the naive "nearest each frame" recompute is unstable under an aggressive push). Pushing the grabbed marker into the deadband **shoves the other** to preserve the 1.5°C gap; when the shoved marker hits a 4.5/32°C rail, the dragged one stops too. **One drag may therefore write both setpoints.** Per-tick selection-click haptics fire on the moving marker via the existing throttle.

The grab/move split is two pure, unit-tested statics: `TemperatureDial.nearestIsLow(...)` (the decision) and `TemperatureDial.moveMarker(...)` (the push + deadband + rail math).

### 4. Keyboard entry — dual-field dialog with in-form deadband

A single tap target over the whole stacked readout opens a **dual-field `RangeEntryDialog`** (Heat + Cool, integer-only, unit-aware). Rather than build a second parser, both fields reuse `TempEntryDialog`'s extracted `prefillText` / `tryParseCelsius` statics. The deadband is enforced **in the form**: Set is disabled with an inline error until `heat + 1.5°C ≤ cool`, mirroring #102 and the eco sheet's `low < high` gate. Both values commit together. Single-setpoint modes keep the existing single `TempEntryDialog`.

### 5. Band color — warm→cool between the markers only

The active fill is painted **only between the two markers** (not from tick 0) as a **warm→cool gradient** — `heatGradient`'s warm tone at the HEAT marker lerping to `coolGradient`'s cool tone at the COOL marker (`TemperatureDial.rangeBandColors`). Ticks outside the band are inactive. Heat-cool's old neutral-grey gradient (`gradientColorsFor`) is retained **only** for the single-marker fallback.

### 6. Paired optimistic state + reconciliation

The optimistic override becomes a `(low, high)` pair (`_optimisticLowC`/`_optimisticHighC`). Heat-cool commits POST the explicit `{"low": l, "high": h}` — the nearest-bound heuristic is **dropped** for the dual path. The +1/+3/+7s confirm-watch reconciles **both** bounds (±½-tick each) against the snapshot's `targetTemperatureLow`/`targetTemperatureHigh`, clears the override when both match, and reverts **both** on a POST failure. Both markers animate together via a single `_DialBand` tween so reduced-motion and reconciliation move them in lockstep.

### 7. Null-bound fallback

If a heat-cool device reports a **null** low or high, the dial falls back to the single-marker rendering and the single-scalar write path (today's behavior) — the dual path requires both bounds present.

## Consequences

- The dial widget grows a second render/gesture path; the shared scaffolding (`_dialScaffold`) and the single path are kept intact, so heat/cool/off are visually and behaviorally unchanged.
- `TempEntryDialog` gains two public statics (`prefillText`, `tryParseCelsius`) so the range dialog and the single dialog parse/clamp identically — one source of truth for the °C↔°F round-trip.
- The 1.5°C constant is now the contract point with #102; whichever ticket lands second references `TemperatureDial.deadbandCelsius` rather than re-declaring it.
- Screen-reader support for the dual band is a descriptive container label + the tappable readout button (the single-value slider `onIncrease`/`onDecrease` model doesn't map to two independent setpoints); richer per-marker a11y adjustment is left for a follow-up.

See `CONTEXT.md` for the HEAT/COOL-setpoint, band, and deadband glossary terms added during the same grill.
