# Context — Rest Thermostat

Ubiquitous language for the app. Glossary only — no implementation details.
See `docs/adr/` for decisions and `docs/DESIGN.md` for engineering specifics.

## Glossary

### Setpoint (target temperature)
The temperature the user wants the thermostat to reach. Rendered as the **large
center readout** on the Home dial. This is the only user-editable temperature on
Home. Stored and sent to the device in **Celsius**; shown in the device's
display unit (°C/°F).

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
