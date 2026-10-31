# DukaBook v2.2 — Retail pilot validation

**Status: pre-release test branch. Do not use as the sole record of live shop sales.**
DukaBook is a product by TILLERN LABS; business/trademark registration is not implied.

## Changes available to test
- Debt instalments: enter any positive repayment at or below the current balance. Each receipt is recorded separately; balances reach zero only on the final instalment.
- Cash received and M-Pesa received include debt collections made that day. Credit sales remain in gross sales but are **not** cash collected.
- Opening stock, manual changes, product removal, and sales are logged as stock movements.
- Database v3 -> v4 migration preserves existing records and fills unpaid balances.
- Backup format v2 includes remaining balances and stock movements; restore also accepts legacy v2.1 backup format v1.
- Existing DukaBook icon, English greeting, splash, and TILLERN LABS branding are retained.

## Mandatory checks before a live trial
1. **Do not uninstall v2.1 or clear its data.** This branch uses the same beta Android application ID and GitHub's temporary signing. A newly built APK may not update the prior beta. Export an old beta backup securely and validate it on a disposable test installation.
2. Run on a spare/test phone with dummy records. Create a 10-unit product selling at KES 100, then sell 2 for Cash. Expected stock 8, gross sales +KES 200 and cash received +KES 200.
3. Credit sale: add a KES 500 credit sale. Gross sales increase by KES 500; cash received stays unchanged; debt to collect increases by KES 500.
4. Receive KES 200 Cash on that debt. Remaining balance = KES 300; debt collection history adds KES 200; cash received rises by KES 200, **but gross sales do not rise again**.
5. Receive KES 300 via M-Pesa. Balance = zero and the debt moves to Paid; collections sum KES 500.
6. Try receiving zero, a negative amount, or more than the balance. These must be rejected without changing data.
7. Restock from 8 to 15 units. Stock movement history includes a +7 adjustment. A new sale should add a negative change.
8. Close and relaunch; verify stock, payment history, dashboard figures, and shop settings persist.
9. Export a JSON backup; verify that it actually exists in a private destination. Restore on a separate **empty test install** and compare counts and balances.
10. Restore a v2.1 format-1 JSON backup on a test install; old paid debts must stay paid, old open debts must show their full original balance. Do not overwrite the only copy of shop data.
11. Try a malformed JSON backup. Restore must fail without deleting existing data.
12. Confirm the splash, app icon, app name, PIN/security limitations, and responsiveness on affordable Android devices.

## Blocking issues before a shop relies on DukaBook
- **Permanent signing key and verified update in place**: not yet provisioned. Do not distribute an APK that cannot be updated without deleting customer records.
- **Customer data security**: app PIN/device-auth lock and encrypted-at-rest backups are not yet implemented; exported JSON files are unencrypted.
- **End-of-day reconciliation**: cash and M-Pesa receipts are recorded manually; they are not verified with Safaricom.
- **Stock corrections/refunds**: add formal reversal records and permissions instead of manually overwriting numbers.
- **Cost/profit**: expenses and purchase costs are not implemented, so do not present sales revenue as profit.
- Add automated database migration tests, backup/restore tests, and a signed release build before paid launch.

## Suggested supervised 7-day pilot
Day 1: setup and dummy transactions. Days 2–3: compare app figures with manually logged cash, M-Pesa and stock; review discrepancies daily. Day 4: debt repayments and stock adjustment tests. Day 5: backup and restore rehearsal. Day 6: install a **signed update** without data loss (once signing is configured). Day 7: owner feedback and go/no-go decision.

Do not store or distribute real customer personal data without privacy safeguards and appropriate consent/notice.
