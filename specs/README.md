# Specifications

Protocol specifications owned by the backend.

All entity data is grounded in [schema.org](https://schema.org) vocabulary, serialised as [JSON-LD](https://json-ld.org/). Before adding any new field or type, check schema.org for an existing match and use its canonical name.

## Documents

| File | Contents |
|------|---------|
| [`DATA-FORMAT.md`](DATA-FORMAT.md) | JSON-LD schema for entity data |
| [`IMAGE-CACHING.md`](IMAGE-CACHING.md) | Image caching spec and directory conventions |

## Specs Before Implementation

**Specs are the authoritative contract.** When in doubt about a field name, stored format, or directory layout, the spec wins over the implementation.

- **Before serializing entities**, read `DATA-FORMAT.md`.
- **Before writing image download or storage code**, read `IMAGE-CACHING.md`.
- **When adding a new entity field or type**, check [schema.org](https://schema.org) first.
- **When a contract changes**, update the spec first, then update component code.
