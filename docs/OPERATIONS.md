# Free Firebase operations - v2

Project pharmacy-hisab-20261015-v2, Firestore (default) in Mumbai asia-south1, store family-pharmacy. No deployed Cloud Functions or Blaze upgrade. Free quotas apply.

Only Firebase Authentication verifies passwords. Preserve the UID when changing credentials. A device PIN/fingerprint unlocks an existing session; a new or signed-out device still needs Firebase login. App Check enforcement is off, while Auth and restrictive rules are on.

One immutable entry, module state and payment-account increments commit atomically. Modules hold noncash balances, obligations, unique keys and supplier advances. The operation snapshot omits createdAt and must match its entry; entries use a server timestamp. Editing an expense posts an inverse plus replacement atomically. Daily close locks through its date. At most three distinct bills may be allocated in one entry.

Staff require module:read/module:post permissions. Managers need explicit salary, zakat, zakat_companies and loans permissions. Owners manage membership, shares, reversals and opening balances. Shared money balances require cashbook access. Profile archival preserves history. Offline downloaded data cannot be remotely recalled. Cached financial records are not fully encrypted; use trusted devices and an OS passcode. Local PIN hashes use secure storage. Android backup is disabled.

Legacy functions/index.js is not deployed. Keep active definitions, config/posting-types.json and admin-only /system/postingTypes synchronized, and rerun emulator tests after changes. Module/account/control baselines are admin-initialized.

No automatic backups, receipt uploader, scheduled external notifications, attendance import or Abuzar integration is configured. Net sale is manually copied as a reporting total and does not change cash/bank. Reports are not full backups. Module documents have size/contention limits, and history currently loads completely; larger stores need pagination and partitioning.

## Version 3 orders and reversals

Orders use supplier read/post permissions and a separate orders collection. Rules require a new linked supplier bill to change an open order to received in the same transaction. A linked bill reversal must reopen the order. Order records cannot be hard-deleted. Loan and used salary-advance reversals reject invalid dependent balances. Owner collection queries are allowed by existing owner checks; staff retain module-scoped reads. No orders aggregate document or paid backend is required.
