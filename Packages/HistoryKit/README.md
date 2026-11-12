# HistoryKit

Local version history and at-rest password protection for NOTEAPP. Engine only,
no UI, no third-party dependencies.

## What it provides

| Type | Purpose |
| --- | --- |
| `VersionSnapshot` | Codable metadata for one snapshot: notebook, optional page, time, reason, SHA-256 and byte count. |
| `VersionHistoryStore` | Actor that records payloads and metadata, lists/loads them, prunes, deletes a notebook's history and reports disk use. |
| `SnapshotPolicy` | Pure retention rules: newest N per page, one per day for the last 7 UTC days, global byte budget. |
| `PasswordProtector` | AES-256-GCM with PBKDF2-HMAC-SHA256 (CommonCrypto), random salt and nonce, typed wrong-password error. |
| `KeychainKeyStore` | Protocol plus `SecurityKeychainKeyStore`, which stores a 32-byte device key and an encrypted remembered password. |
| `LockPolicy` | Idle auto-lock, lock-on-background and hide-from-search settings. |
| `ManifestEncryption` | Encrypts a Codable manifest into a `NHLK` + version-byte envelope that can be detected without decrypting. |

## On-disk layout

```
<root>/notebooks/<notebook-uuid>/index.json
<root>/notebooks/<notebook-uuid>/<unix-ms>-<sha256-prefix>-<snapshot-uuid>.snapshot
```

The payload is always written before the index entry. If the index write fails,
the payload is removed again; a crash between the two leaves only an unreferenced
payload, which `list` never shows and `prune` sweeps away. Deletion reverses the
order: metadata first, payload second. So the index never names a file that is
not there.

## Security choices

- PBKDF2-HMAC-SHA256 with 210,000 rounds by default; the round count is stored in
  each `SealedBlob` so old blobs stay readable.
- Fresh 16-byte salt and 12-byte AES-GCM nonce for every seal.
- Wrong password and tampered ciphertext both throw
  `PasswordProtectorError.wrongPassword`; no partial plaintext is returned.
- `SecurityKeychainKeyStore` encrypts the remembered password with the device key
  before writing it, so the keychain item is not a plaintext password.
- `VersionHistoryStore` stores payload bytes exactly as given. For a locked
  notebook, pass bytes already sealed with `PasswordProtector` and decrypt after
  unlock, or accept that the history relies on iOS Data Protection alone.
- The remembered password is optional. There is no recovery path if both the
  password and the remembered copy are lost.

## Integration notes

1. Add `Packages/HistoryKit` to the Xcode project and link the `HistoryKit`
   product to the app target. No other package is required.
2. Create one store at app start, for example
   `VersionHistoryStore(root: applicationSupportDirectory.appendingPathComponent("History"))`.
3. Record after a successful save (payload bytes are the page/notebook file
   bytes), then prune on launch or when the app backgrounds. PBKDF2 and file I/O
   are synchronous inside the actor; call them off the main thread.
4. Use `ManifestEncryption.write`/`isEncryptedManifest` for a locked notebook's
   manifest. The helper's JSON is internal to the envelope, so it does not need
   to match the app's own manifest codec.
5. Use `SecurityKeychainKeyStore` for the device key. An unsigned Mac build may
   return `errSecMissingEntitlement` from the data-protection keychain; sign the
   app or pass `usesDataProtectionKeychain: false`.
6. History is local-only and is never part of sync.

## Tests

```sh
swift test --package-path Packages/HistoryKit
```
