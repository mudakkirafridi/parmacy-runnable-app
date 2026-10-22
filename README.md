# Pharmacy Hisab 4.2.0

Flutter pharmacy bookkeeping app with a blue/navy interface, English/Urdu, PIN/fingerprint, Firebase Authentication and free-plan Firestore.

## Current behavior
- Salary pays outstanding dues first; the remainder becomes staff advance. Legacy overlapping dues/advance are presented as a net position and the next payment applies unused advance without another cash outflow.
- Home shows cash, financial overview, Ograi / Order / Company bill shortcuts, and company balances with payment/report actions.
- Fixed footer entry actions across registers. Company payments allocate oldest bills first.
- Owner entry edits preserve an audited previous version. Ordinary statements show the current version; manual reversals remain visible in red. Allocated bills require linked allocations to be reversed before correction.
- Ograi reports include same-company, same-day active bill totals. Combined company reports include bills, payments and returns. PDF/picture sharing remains available per report; All reports uses PDF only.
- Android email/password inputs use native EditText. Native edits are never echoed back through setText; versioned explicit resets reject delayed old input events.
- SQLite snapshots and a pending command queue save locally and retry on active/resumed app sessions. Multiple-allocation payment edits use two independently validated, resumable server steps with stable IDs. Server conflicts remain reviewable.

## Build
```powershell
flutter pub get
flutter build apk --release --no-pub --dart-define-from-file=config/production.android.json
```

Package: pk.pharmacyhisab.pharmacy_hisab. Existing APK signing identity is retained for in-place updates.

## Validation
65 Flutter tests pass; analyzer reports no issues. 10 backend/emulator tests pass, including interrupted edit retry, owner/staff isolation and forged-correction rejection. Firestore rules were deployed to pharmacy-hisab-20261015-v2. Production journal records were not modified by tooling. Native Android credentials compiled in the release APK; physical phone keyboard, fingerprint and update acceptance remain required.

```powershell
flutter analyze --no-pub
flutter test --no-pub
firebase emulators:exec --only firestore --project demo-pharmacy-free-v2 "npm --prefix functions test"
```

The functions folder contains a reference ledger and emulator tests. The production app uses direct authenticated Firestore transactions under the Spark plan.

See [Roman Urdu device checklist](docs/UPDATE-v4.2-Roman-Urdu.md), [verification notes](docs/VERIFICATION.md) and [operations](docs/OPERATIONS.md).
