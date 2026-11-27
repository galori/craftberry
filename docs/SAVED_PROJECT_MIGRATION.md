# Saved project migration

Craftberry stores editable add-on projects as JSON sidecars next to their build
artifacts. Opening a sidecar validates it against the app's current project
schema and Bedrock content profile. A compatible older sidecar is migrated in
memory; opening it never rewrites the source file. The next successful build or
revision saves the current schema to the sidecar. A rejected sidecar remains
unchanged and can be recovered or inspected separately.

## Accepted versions

The current project schema is version 3 and the current Bedrock content profile
is `bedrock-stable-1.26.30`.

| Sidecar schema | Target profile | Result |
| --- | --- | --- |
| 1 or 2 | `bedrock-stable-1.21.80` | Migrate the schema and target profile, then validate all content. |
| 1 or 2 | `bedrock-stable-1.26.30` | Migrate the schema, then validate all content. |
| 3 | `bedrock-stable-1.26.30` | Validate and open without migration. |
| Any other schema or profile | Any | Reject without modifying the source sidecar. |

Migration preserves the project UUID, all four pack UUIDs, build version,
prompt, and content. Validation must pass under the current profile before the
migrated project is exposed to the editor or compiler. If migration or
validation fails, the original sidecar stays intact.

## Revision identity

When a revision generates different temporary IDs for content that is
semantically unchanged, Craftberry keeps the existing content IDs and updates
references to those IDs. That keeps the project's pack identity and links to
unchanged visuals and recipes stable across revisions. Changed or ambiguous
content keeps the draft's generated identity.

Only the explicitly listed legacy schema/profile pair above is supported.
Future sidecar versions and unrecognized profile IDs require a deliberate
migration before Craftberry will open them.
