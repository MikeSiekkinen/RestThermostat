# Context — Rest Thermostat

Ubiquitous language for the app. Glossary only — no implementation details.
See `docs/adr/` for decisions and `docs/DESIGN.md` for engineering specifics.

## Glossary

### Setpoint (target temperature)
The temperature the user wants the thermostat to reach. Rendered as the **large
center readout** on the Home dial. This is the only user-editable temperature on
Home. Stored and sent to the device in **Celsius**; shown in the device's
display unit (°C/°F). In Auto (heat-cool) mode there are two setpoints — the
[[HEAT setpoint]] and [[COOL setpoint]] — instead of one.

### HEAT setpoint / COOL setpoint
The two setpoints of Auto (heat-cool) mode. **HEAT** is the low bound: the system
heats to keep the room at or above it. **COOL** is the high bound: the system
cools to keep the room at or below it. Labeled `HEAT` / `COOL` on the Home dial
(matching the Schedule event editor); the eco-temperatures sheet spells the same
pair as `LOW (HEAT)` / `HIGH (COOL)`.

### Band
The temperature range between the [[HEAT setpoint]] and [[COOL setpoint]] in Auto
mode — the zone the system does nothing in. On the Home dial it's the active fill
between the two markers.

### Deadband
The minimum gap the [[band]] is allowed to shrink to, so the HEAT and COOL
setpoints can't cross or sit so close the system would heat and cool at once. A
single app-wide value shared by the Home dial and the Schedule Auto event editor.

### Current temperature
The temperature the room actually is, as reported by the device. Rendered as the
**secondary line** below the setpoint on the Home dial (optionally with relative
humidity, e.g. `68° · 45%`). A pure readout — never editable.

### Tap-to-jump
The Home dial's existing gesture: tapping (or dragging to) a point on the tick
**ring** moves the setpoint to the nearest tick and commits it. Mapped by the
angle of the touch, not its distance from center.

### Keyboard entry
Setting the setpoint by typing a value, as an alternative to tap-to-jump. Opened
by tapping the large setpoint readout; on Home this reuses the same numeric-entry
dialog as the Schedule → Edit Event screen.

### Display unit
The unit a temperature is shown in (°C or °F), from the device's
`temperature_scale`. Independent of storage, which is always Celsius.
