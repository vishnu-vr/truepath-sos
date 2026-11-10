# Data model (Firestore)

Project `truepath-sos-2611`, database `(default)`, region asia-south1.

## Collections

### `users/{uid}`
```
name, email, fcmTokens: string[], isAdmin?: bool
```
One doc per person — caregivers and cane users alike (roles are per-cane).
Created by the app at sign-up; `fcmTokens` appended on every login/token
refresh; pruned by the backend when FCM reports a token dead.

### `devices/{deviceId}`
```
name, status: 'provisioned' | 'active',
secretHash,                 // sha256 of the device secret (never plaintext)
pairCodeHash,               // sha256 of the claim code; DELETED on claim
ownerUid,                   // set once at claim, immutable
primaryCaregiverUid,        // transferable; falls back to owner on removal
caregiverUids: string[],    // all receive SOS pushes; owner always included
caneUserUid,                // nullable
members: { uid: {name, email} },   // denormalized display info
battery, lastSeenAt, provisionedAt, claimedAt
```
`members` exists so clients never need to read other people's `users` docs
(privacy). The backend recomputes it on every membership change.

### `alerts/{autoId}`
```
deviceId, deviceName,
caregiverUids: string[],    // snapshot at SOS time; may resolve
memberUids: string[],       // caregivers + cane user; may read
type, status: 'active' | 'resolved',
location: GeoPoint, battery, sentAt, createdAt, resolvedAt, resolvedBy
```

## Security rules (firestore.rules)

- `users/{uid}` — read/write only by that user; admins may read.
- `devices` — read by owner/caregivers/cane user/admin; **no client writes**
  (claim/manage/provision/sos go through the backend Admin SDK).
- `alerts` — read by `memberUids` members or admin; the ONLY client write in
  the whole database is an update restricted to
  `status/resolvedAt/resolvedBy` by someone in `caregiverUids`.
- Admin = `request.auth.token.admin == true` (custom claim).

## Composite indexes (firestore.indexes.json)

- `alerts`: `memberUids` CONTAINS + `createdAt` DESC (app/website queries)
- `alerts`: `caregiverUids` CONTAINS + `createdAt` DESC

Deploy rules+indexes: `firebase deploy --only firestore --project truepath-sos-2611`.

## Invariants (enforced by backend; keep them)

1. Owner is always in `caregiverUids` and can never be removed.
2. `primaryCaregiverUid` is always in `caregiverUids`.
3. `members` holds exactly {owner} ∪ caregivers ∪ {cane user}.
4. A claimed device never has `pairCodeHash`.
5. Secrets exist only as sha256 hashes, compared constant-time.
