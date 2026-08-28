# Glossary

Contributor-facing definitions for terms with a precise project meaning.
User-facing vocabulary (entry vs entity, release) is governed by the
`writing-copy` skill and the guide-vocabulary rules; this file covers terms
as used in code, specs, and decision records.

| Term | Meaning |
|---|---|
| **App** | A launchable entry in the Apps launcher (`MediaCentaur.Apps.App`): name, one-line shell command, origin. User copy says "app"; code says `App`. |
| **Add-method** | A way of creating an App (the Steam picker, the manual form). Add-methods are importers that resolve to the uniform App shape at add time — launching never dispatches on them. |
| **Origin** | Provenance metadata an add-method records on an App (e.g. `%{"source" => "steam", "app_id" => 413150}`). Used for dedup and artwork refresh, never for launch behavior. |
