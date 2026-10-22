# Verification - Pharmacy Hisab 4.1.0+9

20 October 2026. 58 Flutter tests passed before the final focused checks. Ten backend/emulator tests passed, including five-bill automatic allocation chunks, same-ID retries, cash conservation and profile visibility. The packaged manifest records final checks. No production financial data was modified during QA.

Register actions use Scaffold bottom bars outside the scrolling record list. Single-action registers open their forms directly. Orders and profiles also have fixed actions. Company payments/returns allocate automatically to oldest bill dates, creation chronology and numeric bill references. More than three allocations split into stable-ID journal commands to retain existing Firestore security limits; their total equals the requested payment.

Every posted financial entry, reversal and expense correction applies locally and atomically persists with its upload command in SQLite. Confirmation uses the existing Firestore transactions and security rules. Server reads replay pending commands only when their IDs are not already present. Timeout/unknown commits retain the same ID on retry. Confirmed permanent rejections remain reviewable and server snapshots remove rejected effects. Explicit discard requires a current server snapshot. Timer/resume retry is automatic while the app runs; force-stopped/off phones resume upload at the next launch. Settings and daily close remain server-confirmed.

Profiles normalize whitespace/case and use automatic numeric suffixes. Legacy duplicates keep their stable document IDs; profiles with financial history receive priority for the existing spelling. Legacy renames are queued only after a fresh server snapshot, preventing a stale cache from choosing the wrong canonical profile. Old customer document modules remain unchanged on server writes. A read-only audit confirmed the requested duplicate customer name existed under two IDs; one had a loan entry, one did not. No live financial entries or profile names were changed by audit tools.

All-people loan reports aggregate by stable person ID, with drill-down to individual dated statements. Report labels resolve current profile names rather than stale same-name snapshots. All reports supports PDF only; other reports retain PDF/picture. Home shows cash prominently, daily net sale in the overview, exactly three quick actions and company bills. More omits Synced/Production sign in.

Physical-device testing was not performed. Production Firebase rules/project and free-plan configuration were not changed.


## 4.2.0 verification
65 Flutter tests and 10 backend/emulator tests passed. Analyzer is clean. Salary split (5,000 owed + 10,000 payment), legacy advance application, current/after-payment balances, company Home actions, daily Ograi bill totals, current-version statements and readable red reversals were checked. PDF/PNG QA samples were rendered and inspected.

Native credential tests verify that delete/retype events do not echo setText and that delayed events from an older clear epoch are ignored. Android native code compiled; device keyboard acceptance is still required.

Owner corrections use a reverse/replacement audit trail. Normal corrections are atomic Firestore transactions. Corrections with more than one allocation on either side use a durable two-stage server operation to stay within Firestore rule expression limits: an owner reversal tagged with editTarget, followed by the corrected posting. Stable IDs prevent duplicates; a different edit cannot reuse another action's reversal. A partial server reversal rebases the pending local correction before retry. A permanent conflict can leave the reversal committed until the queued correction is resolved; such entries require the existing upload review flow. Linked order bill corrections stay atomic and preserve the received order relationship.

Rules retain full effect/allocation/account validation and owner-only source updates. Duplicate reversal-shape checks were removed from module validation because the newly created reversal document independently validates that same shape and requires the owner-protected source update. A malformed correction-reversal cannot serve as the module operation; the emulator explicitly denies that forged case. Previous-client expense corrections remain compatible.
