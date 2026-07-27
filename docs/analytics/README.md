# Maia Analytics

Pipeline for product analytics and SQL / data-science practice:

```
Maia iOS → Firebase Analytics → BigQuery → SQL / Looker Studio / Python
```

Firestore still stores a per-user event mirror for debugging. **BigQuery (via Firebase Analytics export) is the source of truth for analysis.**

## Docs in this folder

| File | Purpose |
|------|---------|
| [event-schema.md](event-schema.md) | Event names + parameters |
| [bigquery-setup.md](bigquery-setup.md) | Console checklist (Faz 0) |
| [queries/](queries/) | Starter BigQuery SQL |

## Fazlar

1. **Faz 0** — Enable BigQuery linking (see `bigquery-setup.md`)
2. **Faz 1** — Enriched events in app (done in code) + this docs pack
3. **Faz 2** — Looker Studio dashboard on the BigQuery dataset
4. **Faz 3** — Python notebooks (retention, CEFR × language)

## Debug on device / Simulator

Xcode scheme → Arguments → `-FIRDebugEnabled` to see events in Firebase DebugView with dimensions:

- `learning_language` (`en` / `de`)
- `user_cefr_level` (user setting, e.g. `A2+`)
- `cefr_level` (word band when set on word events; otherwise user setting)
- `is_premium` (`true` / `false`)
- `platform`, `app_version`
