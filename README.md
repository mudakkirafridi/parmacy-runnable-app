# Pharmacy Hisab 4.1.0

Flutter financial registers for Family Pharmacy, Android 7.0+. Editable source: Desktop / parmacy app. Install the release APK over the previous version to preserve login, PIN, SQLite cache and financial history.

## Current behavior

- Fixed bottom actions in registers, orders and profiles. A register with one available action opens its form directly.
- Company Ograi shows total remaining balance and automatically pays oldest bills. Large allocations use stable-ID journal parts within existing Firestore transaction limits.
- Entries, reversals and expense corrections save locally with durable SQLite upload commands, then synchronize automatically. Network timeouts retry the same IDs. Server-rejected changes remain reviewable and their effects are rebased against confirmed records. The app must run/resume to process pending transaction commands; force-stop/power-off resumes on the next launch.
- Unique profile names use numeric suffixes. Legacy profile document IDs and journals stay intact. Fresh server snapshots determine canonical legacy spellings; cached display names alone never trigger migration writes.
- One summary row per loan person, with individual dated statements on tap. All reports shares PDF only; other report categories retain PDF/picture.
- Home: main Cash balance card, Daily net sale in overview, exactly Ograi / Order / Company bill quick actions, and company bills. The dedicated Reports tab remains available. More omits Synced and Production sign in.
- Four-digit PIN with Unlock, fingerprint, retained Firebase session, native keyboard composing behavior, one-step Back and double Back exit are retained. Rent stays an expense category; customer sales/returns and CSV exports remain removed.
- Financial security/allocation/closed-day validation still runs in Firestore. Settings and daily close remain server-confirmed.

## Configuration and checks

Free Firebase project: pharmacy-hisab-20261015-v2; store: family-pharmacy. Production uses Firebase Authentication and direct Firestore transactions. No Blaze upgrade or deployed Cloud Functions. Legacy functions/ code is used for reference/emulator tests. Passwords and service-account keys are not embedded in the app or source archive. Preserve the Auth UID when changing login credentials in Firebase.

    flutter pub get
    flutter analyze --no-pub
    flutter test --no-pub
    flutter build apk --release --dart-define-from-file=config/production.android.json
    firebase emulators:exec --only firestore --project demo-pharmacy-free-v2 "npm --prefix functions test"

58 Flutter tests, final focused checks and 10 backend/emulator tests cover the changes. Physical-device acceptance is still required. See docs/UPDATE-v4.1-Roman-Urdu.md, docs/VERIFICATION.md and docs/OPERATIONS.md.
