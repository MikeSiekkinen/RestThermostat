# Rest Thermostat

Community Flutter app for the NoLongerEvil firmware on deprecated Nest Gen 1/2 thermostats.

- **`docs/PRD.md`** — product-intent reference (audience, goals, scope)
- **`docs/DESIGN.md`** — engineering-decisions reference (architecture, state, UI, build)

When PRD and DESIGN disagree, DESIGN wins. PRD divergences are listed in DESIGN §18.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`MikeSiekkinen/RestThermostat`). Use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. Neither exists yet — produce lazily as decisions arise. See `docs/agents/domain.md`.
