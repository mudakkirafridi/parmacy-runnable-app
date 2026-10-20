# Financial model - v2

Amounts use integer paisa and balanced debit/credit effects. One daily net sale debits salesControl and credits netSales, with no cash movement. Customer finance and old rent accrual/deposit types are retired.

Supplier bills create obligations. Payments reduce allocated remaining; confirmed medicine returns reduce payable without cash outflow. Supplier advances track unallocated credit; applying them does not pay cash twice. Up to three distinct bills per entry.

Rent payment directly records rent expense and money outflow. Expenses debit category expense and credit cash/bank. Removal creates an inverse; editing atomically reverses and replaces. History stays immutable.

Owner shares use basis points totaling 10,000. Capital/drawings retain owner/share snapshots. Share edits do not rewrite history or automatically distribute profit. Profile archival preserves history.

Module aggregates exclude money balances. Atomic transactions/rules enforce definitions, effects, state differences, allocation limits, uniqueness, advances and membership. Daily close locks current/past dates; later corrections need an open date.
