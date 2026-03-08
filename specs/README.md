# Specifications

Protocol specifications owned by the backend.

All entity data is grounded in [schema.org](https://schema.org) vocabulary, serialised as [JSON-LD](https://json-ld.org/). Before adding any new field or type, check schema.org for an existing match and use its canonical name.

## Documents

| File | Contents |
|------|---------|
| [`DATA-FORMAT.md`](DATA-FORMAT.md) | JSON schema for entity data |
| [`IMAGE-CACHING.md`](IMAGE-CACHING.md) | Image caching spec and directory conventions |
| [`IMAGE-SIZING.md`](IMAGE-SIZING.md) | Recommended source dimensions per image role |
| [`PLAYBACK.md`](PLAYBACK.md) | MPV integration, watch progress model, resume algorithm |

## Archived

| File | Reason |
|------|--------|
| [`archived/API.md`](archived/API.md) | WebSocket channel protocol (Rust frontend deprecated) |
| [`archived/COMPONENTS.md`](archived/COMPONENTS.md) | Frontend architecture diagram (Rust frontend deprecated) |

## Specs Before Implementation

**Specs are the authoritative contract.** When in doubt about a field name, message format, or behavior, the spec wins over the implementation.

- **Before writing playback or watch progress code**, read `PLAYBACK.md`.
- **Before serializing entities**, read `DATA-FORMAT.md`.
- **Before writing image download or storage code**, read `IMAGE-CACHING.md` and `IMAGE-SIZING.md`.
- **When adding a new entity field or type**, check [schema.org](https://schema.org) first.
- **When a contract changes**, update the spec first, then update component code.
