# DukaBook permanent Android signing — first-time setup

**Status:** The initial v2.2.0+4 signed-test APK successfully built and passed the GitHub Actions signature verification. The owner installed it alongside the Pilot. A v2.2.1+5 signed in-place update is now prepared for the next verification; preservation of test records has not yet been confirmed.

The existing v2.1 beta and v2.2 Pilot are not replaced. Signed testing uses a separate Android identity: `com.eldoret.dukabook.duka_app.signedtest`, with launcher name **DukaBook Signed Test**. It has its own empty database when first installed.

## 1. Generate a private Android signing keystore ON A DEVICE YOU CONTROL

Use a trusted, controlled Windows/macOS/Linux machine with Java JDK and `keytool`, or a securely backed-up local Linux environment on your own phone. Do not create a long-term signing key on a borrowed PC or in an ephemeral hosted CI runner.

With a trusted Linux shell that has Java installed, *outside your GitHub repository*:

```sh
mkdir -p "$HOME/dukabook-signing-private"
chmod 700 "$HOME/dukabook-signing-private"
keytool -genkeypair -keystore "$HOME/dukabook-signing-private/dukabook-release.jks" -storetype PKCS12 -alias dukabook-release -keyalg RSA -keysize 3072 -validity 10000
```

The command interactively requests a **strong, unique** keystore password. PKCS12 typically uses the same password for the private key. Do not put passwords directly on the command line or in a committed file. Record them using a secure password manager accessible to the owner.

**Before anything else:** make two protected copies of the `.jks` keystore in separate trusted locations, test that at least one copy can be opened with `keytool -list -keystore ...`, and do not delete the original until you confirm backups. Protect both the file and its password. A future release cannot be signed with the same identity if the keystore is lost.

**Acode / Alpine on Android (optional):** the `keytool` utility is included in Java JDK packages; if your shell offers Alpine's `apk`, you may be able to install a supported OpenJDK package. Before generating a keystore in an Acode terminal, verify you can copy it to durable protected storage outside the terminal. Some terminal environments are reset on reinstall or clearing data. Do not proceed if you cannot export a trusted backup.

## 2. Add four GitHub Actions repository secrets

In **tillern-dev/duka-app** on GitHub, open **Settings → Secrets and variables → Actions → New repository secret**. Enter these exact names and keep their **values private**:

- `DUKABOOK_KEYSTORE_B64`: one-line Base64 encoding of the keystore file bytes. On Linux, generate the text locally with `base64 path/to/dukabook-release.jks | tr -d '\n'`. Copy that text only to the secret input.
- `DUKABOOK_KEYSTORE_PASSWORD`: the keystore password.
- `DUKABOOK_KEY_ALIAS`: the exact alias chosen when generating the keystore (the example uses `dukabook-release`).
- `DUKABOOK_KEY_PASSWORD`: private-key password (often the same as the PKCS12 keystore password).

Never post the base64 text, keystore, or passwords to ChatGPT, GitHub issues, pull requests, or source files. GitHub Actions secrets are separate from public repository contents; nevertheless, repository owner access and workflow security must be maintained.

## 3. Build a signed APK safely

1. Open [GitHub Actions](https://github.com/tillern-dev/duka-app/actions).
2. Select **Build Permanently Signed DukaBook Test APK**.
3. Click **Run workflow**, choose branch **feature/v2-2-retail-pilot**, and confirm the explicit acknowledgement.
4. Open the build run and require **Success** on the **Verify APK signature** step.
5. For the initial installation, download artifact `DukaBook-v2.2-Permanently-Signed-Test-APK` from the successful historical workflow run. For the update test, use `DukaBook-v2.2.1-Signed-Update-Test-APK` from a new successful manual workflow run.
6. Install **DukaBook Signed Test** alongside the existing **DukaBook Pilot**. They use different package IDs, and **no customer data transfers automatically**.

If secrets are missing or invalid, the build should fail before signing or uploading an APK.

## 4. Prove updates don't destroy data

After the *first* signed-test APK is installed, **add dummy products, sales, repayments and stock movements before upgrading**. The manual signed-test workflow now builds **v2.2.1+5** with the exact same application ID and signing credentials as the original v2.2.0+4 build. Run the workflow on `feature/v2-2-retail-pilot`, download the v2.2.1 artifact, and install it **as an update over DukaBook Signed Test without uninstalling**. Confirm all test records remain intact and both signed APKs use the same certificate SHA-256 fingerprint. Do not attempt this update on DukaBook Pilot.

Do not call the signing system validated until the update-in-place test passes. Do not uninstall the existing pilot to test this.

## 5. More release blockers

- Test backup/restore on two devices and protect/limit access to customer information.
- Add PIN / device-auth protection and secure encrypted backup options.
- Confirm Cash/M-Pesa recorded totals with manual receipts; payments are not automatically verified.
- Test refunds/corrections, record integrity, business-owner support, and privacy notice before using live shop data.

References: Flutter Android deployment and signing documentation; Android Developers, *Sign your app*; GitHub Actions documentation for manual workflow dispatch.
