# DukaBook retail beta checklist

- [x] Shop-style logo and matching Android launcher artwork included in this source package.
- [x] English-only greeting and branded Flutter splash source code included.
- [x] Android launcher name is DukaBook β (separate beta install).
- [x] Status bar SafeArea fix present in source.
- [x] Manual backup/restore code with validation present (not device-tested).
- [ ] **GitHub Actions release APK builds successfully.**
- [ ] **Install beta alongside existing v2.0; test on Android 11 and other devices.**
- [ ] Test icon size, launcher label, native splash, Flutter splash, and greeting at morning/afternoon/evening.
- [ ] Test all stock/sales/debt operations and backup/restore with dummy records; verify persistence across restart.
- [ ] Create a permanent release signing keystore, protect credentials, test an upgrade without data loss.
- [ ] Test recoverability on a second device and privacy protections before serving real retail customers.
- [ ] Consider licensing, support terms, and legal/business name checks before commercial release.

Do not delete DukaBook v2.0, clear app data, or trust unencrypted backups for sensitive customer records.
