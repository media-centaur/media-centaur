# Specifications

Protocol specifications owned by the backend.

## Documents

| File | Contents |
|------|---------|
| [`DATA-FORMAT.md`](DATA-FORMAT.md) | Entity data shape — types, fields, examples |
| [`IMAGE-CACHING.md`](IMAGE-CACHING.md) | Image caching spec and directory conventions |

## Specs Before Implementation

**Specs are the authoritative contract.** When in doubt about a field name, stored format, or directory layout, the spec wins over the implementation.

- **Before serializing entities**, read `DATA-FORMAT.md`.
- **Before writing image download or storage code**, read `IMAGE-CACHING.md`.
- **When a contract changes**, update the spec first, then update component code.
