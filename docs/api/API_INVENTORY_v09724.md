# GX-TXT dataset API inventory for 0.9.7.24

| API | Version | Status in 0.9.7.24 |
|---|---:|---|
| Canonical Dataset API | 1 | Retained for path and registry compatibility |
| Canonical Dataset API | 2 | Current backend-neutral read API |
| Dataset Variable Schema API | 2 | Retained table/column schema |
| Dataset Variable Schema API | 3 | Current typed and multidimensional schema |
| Dataset Publication API | 1 | Retained unchanged for completed-file publication |
| Dataset Publication API | 2 | Current backend-neutral writer lifecycle |
| Analysis Source Map API | 1 | Retained |
| Analysis Source Access Runtime | 2 | Retained |
| Table Stream API | 1 and 2 | Retained unchanged |

Dataset Publication API v2 uses Variable Schema v3 and produces registry
entries readable by Canonical Dataset API v2. It does not replace or reinterpret
v1 publications. Provider registration and private storage locators are CORE
implementation details.
