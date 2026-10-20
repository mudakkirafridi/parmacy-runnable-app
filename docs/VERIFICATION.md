# Verification - Pharmacy Hisab 4.1.0+9

20 October 2026. 58 Flutter tests passed before the final focused checks. Ten backend/emulator tests passed, including five-bill automatic allocation chunks, same-ID retries, cash conservation and profile visibility. The packaged manifest records final checks. No production financial data was modified during QA.

Register actions use Scaffold bottom bars outside the scrolling record list. Single-action registers open their forms directly. Orders and profiles also have fixed actions. Company payments/returns allocate automatically to oldest bill dates, creation chronology and numeric bill references. More than three allocations split into stable-ID journal commands to retain existing Firestore security limits; their total equals the requested payment.

Every posted financial entry, reversal and expense correction applies locally and atomically persists with its upload command in SQLite. Confirmation uses the existing Firestore transactions and security rules. Server reads replay pending commands only when their IDs are not already present. Timeout/unknown commits retain the same ID on retry. Confirmed permanent rejections remain reviewable and server snapshots remove rejected effects. Explicit discard requires a current server snapshot. Timer/resume retry is automatic while the app runs; force-stopped/off phones resume upload at the next launch. Settings and daily close remain server-confirmed.

Profiles normalize whitespace/case and use automatic numeric suffixes. Legacy duplicates keep their stable document IDs; profiles with financial history receive priority for the existing spelling. Legacy renames are queued only after a fresh server snapshot, preventing a stale cache from choosing the wrong canonical profile. Old customer document modules remain unchanged on server writes. A read-only audit confirmed the requested duplicate customer name existed under two IDs; one had a loan entry, one did not. No live financial entries or profile names were changed by audit tools.

All-people loan reports aggregate by stable person ID, with drill-down to individual dated statements. Report labels resolve current profile names rather than stale same-name snapshots. All reports supports PDF only; other reports retain PDF/picture. Home shows cash prominently, daily net sale in the overview, exactly three quick actions and company bills. More omits Synced/Production sign in.

Physical-device testing was not performed. Production Firebase rules/project and free-plan configuration were not changed.
