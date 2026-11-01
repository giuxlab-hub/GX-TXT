# GX-TXT dataset API inventory for 0.9.7.28

| API | Version | Status in 0.9.7.28 |
|---|---:|---|
| Canonical Dataset API | 1 | Retained compatibility |
| Canonical Dataset API | 2 | Generic backend-neutral metadata and reads |
| Dataset Variable Schema API | 2 | Retained table schema |
| Dataset Variable Schema API | 3 | Typed, dimensional and coordinate schema |
| Dataset Publication API | 1 | Retained completed-file publication |
| Dataset Publication API | 2 | Backend-neutral transactional writers |
| Table Stream API | 1 and 2 | Retained bare-path CSV behavior |
| Table Stream API | 3 | Table-shaped facade over Canonical Dataset API v2 |
| Analysis Source Map API | 1 | Retained |
| Analysis Source Access Runtime | 2 | Retained discovery metadata |

Table Stream v3 introduces no dataset model and no storage provider. It
transports Canonical Dataset v2 metadata and Variable Schema v3 for selected
rank-1 variables sharing a row dimension.

| Storage Auto and materialization extension | 1 | Public CORE extension of Canonical Dataset v2 and Publication v2 |

| Large Dataset final audit | 0.9.7.28 | Integrated validation; no new runtime API |

| Publication v2 standard_octave binding | 2 | Persistent binding to existing Tcl API |
| Audio Decode API | 1 | Generic FFmpeg/FFprobe service with Tcl and Octave access |
