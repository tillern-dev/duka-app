# DukaBook v2.2 Retail Pilot BETA — TILLERN LABS

DukaBook is the product; **TILLERN LABS** is its developer brand. This source package integrates the two approved DukaBook images (storefront/shop + receipt) into the home header, Flutter welcome screen, About/More page, Android launcher icons, and Android native launch artwork.

## v2.2 pilot scope

The v2.2 branch adds partial debt repayments, a stock-change audit trail, cash/M-Pesa received totals that include debt collections without double-counting sales, schema-v4 local database migration, and backup schema v2 with compatibility for v2.1 backups.

**This is not yet a release for paying shops.** Signing is not persistent, backups are unencrypted, there is no app lock, and automated migration/restore testing is incomplete. See [PILOT_TEST_PLAN.md](PILOT_TEST_PLAN.md) and [SIGNING_AND_RELEASE.md](SIGNING_AND_RELEASE.md). The existing v2.1 build on main is unaffected.

## What's included

- **English-only** time-of-day dashboard greeting: Good morning / Good afternoon / Good evening, with optional saved owner name.
- Branded welcome screen: shop icon, DukaBook, Run Your Duka Smarter, and Powered by TILLERN LABS.
- Real app icon: generated at the five Android launcher densities, replacing the default Flutter mark.
- Android launcher title **DukaBook Pilot** to distinguish it from the installed v2.1 beta. The public retail release will use **DukaBook**.
- In-app logo and wordmark with Duka green, Book orange, plus TILLERN LABS attribution.
- SafeArea status bar fix, existing offline sales/stock/debts features, manual JSON backup and restore.
- Separate Android application ID `com.eldoret.dukabook.duka_app.pilot` to allow safe side-by-side installation without overwriting v2.1 app data.

## Source tree

```
.github/workflows/build.yml
lib/main.dart
pubspec.yaml
assets/branding/storefront_icon.png
assets/branding/dukabook_logo.png
assets/android/mipmap-*/ic_launcher.png
assets/android/drawable-nodpi/dukabook_splash.png
scripts/apply_android_branding.py
RELEASE_CHECKLIST.md
```

## Apply from Acode on Android

1. **Back up your current repo and keep installed DukaBook v2.0 untouched.** Extract this ZIP outside the repo.
2. Copy the new top-level `lib`, `.github/workflows/build.yml`, `pubspec.yaml`, `assets`, and `scripts` into your cloned `duka-app`, preserving the directory structure. **Do not overwrite `.git`.**
3. Using your Acode terminal, check file sizes and verify assets are present: `ls -lh lib/main.dart assets/branding/*.png scripts/apply_android_branding.py`.
4. `git add lib/main.dart pubspec.yaml .github/workflows/build.yml assets scripts`
5. `git commit -m "feat: DukaBook v2.1 branded beta icon and welcome"`
6. `git push origin main`
7. Open your repository's **Actions** tab and inspect the **Build DukaBook v2.1 Branded Beta APK** result.
8. Download **DukaBook-v2.1-Branded-Beta-APK** artifact and install alongside v2.0. **Use dummy retail records to test the beta**; v2.0 records do not transfer automatically.

## Release safety

- GitHub Actions checks build status; Android device functional tests and signing verification must still be completed.
- Backup exports are **unencrypted JSON** and may contain customer contact details. Keep them private and test restore before relying on it.
- Beta APK uses a temporary signing setup. Before paid distribution, create a persistent release keystore and store it securely in GitHub Actions secrets, with an offline backup. **Don't publish a commercial APK with ephemeral signing.**
- Don't uninstall v2.0 until beta is proven and an intentional data migration is available.
- Cash/M-Pesa are recorded manually; no M-Pesa API connection or payment verification is included.
- TILLERN LABS branding is not a claim of official business registration or trademark clearance.
