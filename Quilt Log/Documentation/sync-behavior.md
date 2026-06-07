# Quilt Log Sync Behavior

Quilt Log now uses SwiftData as its primary store and configures the store for a private CloudKit database named `iCloud.com.erikoliver.quiltlog`.

## Local-First Sync

SwiftData remains the app's local persistence API. Edits save locally first. CloudKit export and import happen asynchronously through Apple's SwiftData/Core Data CloudKit stack when the system decides conditions are appropriate.

The app does not block editing while waiting for CloudKit. A device can create or edit quilts while offline; those changes are expected to sync later.

The app target requests the iCloud CloudKit entitlement for `iCloud.com.erikoliver.quiltlog`. A signed development build must have that container associated with the `com.erikoliver.quiltlog` app identifier in the Apple Developer account before CloudKit mirroring can upload or download records. If Core Data logs `CKError "Bad Container"`, the local SwiftData store can still work, but CloudKit has not accepted the container configuration yet.

## Identifiers

Each quilt and photo has a stable UUID. The legacy SQLite integer IDs are retained only as imported metadata and are not used for sync identity.

## Sequence Numbers

Sequence numbers are user-visible ordering values, not CloudKit uniqueness constraints. If two devices create or edit the same sequence number while offline, the app keeps the data and reports the conflict in normal editing flows rather than allowing CloudKit to discard records.

## Photos

Photo originals and thumbnails are stored as SwiftData binary attributes with external storage enabled. This lets the persistence stack keep large image data adjacent to the model store and lets CloudKit serialize large values as asset-style payloads where needed.

The app does not recompress imported originals during migration.

## Legacy Migration

On first launch with an empty SwiftData store, the app looks for the old sandboxed SQLite library at `Application Support/Quilt Log/Quilt Log.sqlite`. If found, it imports quilts and photos into SwiftData and marks the conversion complete in SwiftData metadata. The legacy SQLite file is left in place as a fallback.

## Backup Export

macOS backup export writes a ZIP containing `manifest.json` plus original and thumbnail image files. The ZIP is intended as a portable backup/export format, separate from CloudKit sync.
