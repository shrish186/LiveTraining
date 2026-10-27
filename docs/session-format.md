# Session file format (v1)

A recorded training session is **two files** that share a basename:

| File | Contents |
|---|---|
| `<session_id>.csv` | every sample from every source, long format |
| `<session_id>.json` | metadata describing the session |

The format is sport-agnostic. Nothing in it assumes a sport, a sensor or a body placement.

## CSV

Header, exactly (no spaces, lowercase):

```
t_ms,source,kind,x,y,z,value
```

| Column | Type | Meaning |
|---|---|---|
| `t_ms` | integer ≥ 0 | milliseconds since session start, from **one monotonic clock on the phone** shared by all streams |
| `source` | enum | where the row came from (see below) |
| `kind` | enum | what the row measures (see below) |
| `x`,`y`,`z` | float | axis values for `acc` / `gyro`; empty otherwise |
| `value` | float or text | scalar for `hr` / `rr`, label for `event`; empty for `acc` / `gyro` |

Unused columns are left **empty** (not `0`, not `NaN`).

### `source`

| Value | Device |
|---|---|
| `phone` | the phone's own motion sensors (stand-in sensor) |
| `whoop_hr` | WHOOP strap via its built-in Heart Rate Broadcast (standard BLE Heart Rate service 0x180D) |
| `movesense` | Movesense sensor (planned) |
| `xiao` | Seeed XIAO nRF52840 Sense (planned) |
| `polar` | Polar sensor (planned) |

The `phone` source is also used for `event` rows, because events come from buttons in the app.

### `kind`

| Value | Unit | Columns used |
|---|---|---|
| `acc` | m/s², **including gravity** | `x`,`y`,`z` |
| `gyro` | rad/s | `x`,`y`,`z` |
| `hr` | beats per minute | `value` |
| `rr` | milliseconds between beats | `value` |
| `event` | label text | `value` |

Event labels are free text, e.g. `sync_jumps`, `drill_start`, `drill_end`, `mark`.
Labels must not contain commas, quotes or newlines. The app replaces these with spaces before writing.

### Rules

- Rows are written in the order they arrive. `t_ms` is *nearly* sorted across streams but readers must not
  rely on strict ordering. Sort by `t_ms` if you need to.
- Different sources have different rates. A reader should never assume a row exists at every millisecond, or that streams are aligned.
- Numbers use `.` as the decimal separator. Floats are written with up to 5 decimals.
- Files are UTF-8 with `\n` line endings.

### Example

```
t_ms,source,kind,x,y,z,value
0,phone,event,,,,session_start
4,phone,acc,0.1214,9.7902,0.3311,
5,phone,gyro,0.0012,-0.0031,0.0004,
14,phone,acc,0.1301,9.8012,0.3254,
812,whoop_hr,hr,,,,72
812,whoop_hr,rr,,,,833.98
15032,phone,event,,,,sync_jumps
```

## Metadata JSON

```json
{
  "format_version": 1,
  "session_id": "4f6c2b0e-3f7a-4d2f-9f0e-6a1f5d2b7c11",
  "athlete_id": 1,
  "sport": "soccer",
  "session_type": "training",
  "started_at": "2026-10-27T18:02:11Z",
  "app_version": "0.1.0",
  "device_model": "iPhone15,2",
  "sources": [
    {"id": "phone", "kinds": ["acc", "gyro"], "sample_rate_hz": 99.6},
    {"id": "whoop_hr", "kinds": ["hr", "rr"], "sample_rate_hz": 1}
  ],
  "placement": "phone_armband",
  "notes": "cold evening, turf",
  "duration_ms": 3720450,
  "complete": true
}
```

| Field | Required | Notes |
|---|---|---|
| `format_version` | no (default 1) | bump if this spec changes incompatibly |
| `session_id` | yes | UUID. Also the file basename. |
| `athlete_id` | no | backend athlete ID (integer), or `null` if not set |
| `sport` | yes | lowercase slug, e.g. `soccer`, `running`, `basketball`, `general`. Matches a sport profile name where one exists. |
| `session_type` | yes | e.g. `training`, `match`, `drill`, `gym` |
| `started_at` | yes | ISO 8601, UTC, the wall-clock time of `t_ms = 0` |
| `app_version` | no | recording app version |
| `device_model` | no | phone model string |
| `sources` | no | list of `{id, kinds, sample_rate_hz}`. The rate is the *measured* average of that source's busiest stream. |
| `placement` | no | where the motion sensor was worn: `shin`, `thigh`, `wrist`, `waist`, `chest`, `upper_arm`, `phone_armband`, `phone_pocket`, … |
| `notes` | no | free text |
| `duration_ms` | no | written by the app at stop |
| `complete` | no | `false` while recording. A session that stays `false` was cut short (app killed), but its CSV is still valid up to that point. |

Unknown extra fields are allowed and preserved.

## Who reads and writes this

- **mobile/** writes it (`SessionRecorder`, `csv_row.dart`).
- **backend/** validates and summarises it on upload (`app/session_format.py`).
- **analysis/** reads it (`ltlib/session_io.py`) and generates it synthetically (`make_synthetic_session.py`).

Change all three together, and update this file, if the format changes.
