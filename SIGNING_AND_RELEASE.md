# DukaBook — Signing and customer-data release gate

## Current state (v2.2 retail-pilot branch)
The current GitHub Actions workflow builds a **beta APK**, using the generated Flutter Android project and its default signing configuration. It does **not** use a persistent private release key. An APK built from a different runner can fail to update an installed beta even if the app ID matches. Never ask shop owners to uninstall an app containing records to install an update.

## Before any real-data pilot or sale
1. Generate **one permanent Android release keystore** on a device you own and trust, using Android Studio or JDK `keytool`. Do not generate it on a borrowed computer where files may remain.
2. Back up the keystore securely offline (two separate protected copies), and record its alias securely. Losing the keystore can make future updates impossible.
3. Configure a release-only GitHub Actions job to load signing materials from GitHub repository Actions secrets. Do **not** put keystores, base64 key data, passwords or key properties in Git history, issue comments, screenshots or chat.
4. Sign the pilot APK with that one key and keep the **same Android application ID** for future pilot releases. Treat a production app ID and its signing key as permanent.
5. Before distribution, verify:
   - installation from a clean device,
   - an upgrade from that signed APK to the next signed APK without wiping data,
   - the same package ID, signing certificate, and increasing version code.
6. Test export, recovery, and data consistency before making the app a shop's only sales record.
7. App-lock/device authentication, secure storage, sensitive-data protection, support process, and a privacy notice need further work. Exported backup JSON is unencrypted.

## Operational plan for first shop
Use dummy products and test customer names while testing reliability. Compare end-of-day cash/M-Pesa receipts and stock movements to a manual ledger. Do not claim verified M-Pesa payments: payment methods are typed manually and no Safaricom Daraja integration exists.

## Explicit non-goals for this branch
- No claim of production-ready data security
- No automatic cloud backups
- No completed commercial licence/payment system
- No profit calculation (purchase costs and expenses aren't recorded)
