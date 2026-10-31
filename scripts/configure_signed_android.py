#!/usr/bin/env python3
"""Configure the generated Flutter 3.22 Groovy Gradle project for signing.
No key material or password is committed, copied into logs, or written to Gradle.
The keystore is placed in the ephemeral GitHub runner's temporary directory.
"""
from pathlib import Path
import base64
import binascii
import os

required = (
    "DUKABOOK_KEYSTORE_B64",
    "DUKABOOK_KEYSTORE_PASSWORD",
    "DUKABOOK_KEY_ALIAS",
    "DUKABOOK_KEY_PASSWORD",
    "RUNNER_TEMP",
)
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit(
        "Missing GitHub Actions signing secrets/config: " + ", ".join(missing)
        + ". Do not paste signing secrets into an issue, repository or chat."
    )

try:
    keystore_bytes = base64.b64decode(
        os.environ["DUKABOOK_KEYSTORE_B64"].strip(), validate=True
    )
except (ValueError, binascii.Error):
    raise SystemExit("Keystore secret is not valid single-line base64 data.")
if not 500 <= len(keystore_bytes) <= 48 * 1024:
    raise SystemExit("Keystore file has an unexpected size.")

root = Path(__file__).resolve().parent.parent
gradle = root / "android" / "app" / "build.gradle"
if not gradle.is_file():
    raise SystemExit("Missing Android Gradle project. Run flutter create first.")

text = gradle.read_text(encoding="utf-8")
# Flutter's Groovy template uses either "signingConfig = signingConfigs.debug"
# or the older "signingConfig signingConfigs.debug" syntax. Accept both.
import re
debug_signing_pattern = re.compile(
    r"(?m)^([ \\t]*signingConfig[ \\t]*)(=[ \\t]*)?signingConfigs\\.debug[ \\t]*$"
)
if len(debug_signing_pattern.findall(text)) != 1:
    raise SystemExit("Expected one default debug release signing configuration.")
if text.count("    buildTypes {") != 1:
    raise SystemExit("Unexpected Android Gradle file layout.")

signing_block = """    signingConfigs {
        release {
            storeFile file(System.getenv('RUNNER_TEMP') + '/dukabook-signed-test.jks')
            storePassword System.getenv('DUKABOOK_KEYSTORE_PASSWORD')
            keyAlias System.getenv('DUKABOOK_KEY_ALIAS')
            keyPassword System.getenv('DUKABOOK_KEY_PASSWORD')
        }
    }
"""
text = text.replace("    buildTypes {", signing_block + "    buildTypes {", 1)
text = debug_signing_pattern.sub(
    lambda match: match.group(1) + (match.group(2) or "") + "signingConfigs.release",
    text,
    count=1,
)

key_path = Path(os.environ["RUNNER_TEMP"]) / "dukabook-signed-test.jks"
key_path.write_bytes(keystore_bytes)
key_path.chmod(0o600)
gradle.write_text(text, encoding="utf-8")
print("Signed-test release Gradle configuration prepared (secrets are never printed).")
