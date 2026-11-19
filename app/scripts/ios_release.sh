#!/usr/bin/env bash
# Run from app/ on a disposable macOS runner. Never enable shell tracing here.
set -euo pipefail
# geolocator_apple's Swift Package reads this at package evaluation time.
# The Podfile applies the same define to its CocoaPods fallback.
export BYPASS_PERMISSION_LOCATION_ALWAYS=1

mode="${DISTRIBUTION:-auto}"
required=(APPLE_TEAM_ID APPLE_CERTIFICATE_BASE64 APPLE_CERTIFICATE_PASSWORD
  APPLE_PROVISIONING_PROFILE_BASE64 APPLE_API_KEY_ID APPLE_API_ISSUER_ID
  APPLE_API_PRIVATE_KEY_BASE64)
missing=()
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then missing+=("$name"); fi
done
case "$mode" in
  unsigned) signed=false ;;
  auto)
    if [[ ${#missing[@]} -eq ${#required[@]} ]]; then
      signed=false
    elif [[ ${#missing[@]} -eq 0 ]]; then
      signed=true
    else
      echo "::error::Incomplete Apple signing setup. Missing: ${missing[*]}. See documentation/mobile-release.md."
      exit 1
    fi ;;
  testflight)
    if [[ ${#missing[@]} -gt 0 ]]; then
      echo "::error::TestFlight requested but missing secrets: ${missing[*]}. Helmut: complete documentation/mobile-release.md."
      exit 1
    fi
    signed=true ;;
  *) echo "::error::DISTRIBUTION must be auto, unsigned or testflight."; exit 1 ;;
esac

defines=("--dart-define=API_BASE_URL=${API_BASE_URL:-http://10.0.2.2:8000/api}"
  "--dart-define=PUBLIC_PORTAL_URL=${PUBLIC_PORTAL_URL:-http://localhost:5173}")
if [[ "$signed" == true ]]; then
  python3 scripts/validate_release_config.py
fi

if [[ "$signed" == false ]]; then
  echo "No signing/upload requested: building an unsigned device archive. It cannot be installed or sent to TestFlight."
  flutter build ipa --release --no-codesign "${defines[@]}"
  tar -czf build/ios/aldia-archive.tar.gz -C build/ios/archive Runner.xcarchive
  exit 0
fi

signing_dir="$(mktemp -d "$RUNNER_TEMP/aldia-ios.XXXXXX")"
keychain="$signing_dir/signing.keychain-db"
profile_uuid=""
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [[ -n "$profile_uuid" ]]; then
    rm -f "$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
    rm -f "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$profile_uuid.mobileprovision"
  fi
  rm -f ios/Flutter/Signing.xcconfig
  rm -rf "$signing_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export SIGNING_DIR="$signing_dir"

# Decode only in the runner temp directory. Errors name the secret, never its value.
python3 - <<'PY'
import base64
import os
import re
from pathlib import Path

for name in ('APPLE_TEAM_ID', 'APPLE_API_KEY_ID'):
    if not re.fullmatch(r'[A-Z0-9]{10}', os.environ[name]):
        raise SystemExit(f'::error::{name} must contain 10 uppercase letters/digits.')
if not re.fullmatch(r'[0-9a-fA-F-]{36}', os.environ['APPLE_API_ISSUER_ID']):
    raise SystemExit('::error::APPLE_API_ISSUER_ID must be a team API issuer UUID.')
folder = Path(os.environ['SIGNING_DIR'])
for name, filename in (
    ('APPLE_CERTIFICATE_BASE64', 'certificate.p12'),
    ('APPLE_PROVISIONING_PROFILE_BASE64', 'profile.mobileprovision'),
    ('APPLE_API_PRIVATE_KEY_BASE64', f"AuthKey_{os.environ['APPLE_API_KEY_ID']}.p8"),
):
    try:
        data = base64.b64decode(''.join(os.environ[name].split()), validate=True)
        if not data:
            raise ValueError()
    except ValueError:
        raise SystemExit(f'::error::{name} is empty or invalid base64.') from None
    path = folder / filename
    path.write_bytes(data)
    path.chmod(0o600)
PY

keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_dir/certificate.p12" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"

profile_uuid="$(python3 - <<'PY'
import datetime
import os
import plistlib
import re
from pathlib import Path

folder = Path(os.environ['SIGNING_DIR'])
profile = plistlib.loads((folder / 'profile.plist').read_bytes())
team = os.environ['APPLE_TEAM_ID']
bundle = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
                   Path('ios/Runner.xcodeproj/project.pbxproj').read_text())[1]
entitlements = profile.get('Entitlements', {})
app_id = entitlements.get('application-identifier', '')
if (profile.get('TeamIdentifier') != [team] or not app_id.endswith('.' + bundle)
        or entitlements.get('get-task-allow', False) or profile.get('ProvisionedDevices')
        or profile.get('ProvisionsAllDevices')
        or profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)):
    raise SystemExit('::error::Need an unexpired App Store distribution profile matching APPLE_TEAM_ID and Runner bundle ID.')
uuid = profile['UUID']
if not re.fullmatch(r'[0-9a-fA-F-]{36}', uuid):
    raise SystemExit('::error::Invalid provisioning profile UUID.')
Path('ios/Flutter/Signing.xcconfig').write_text(
    f'DEVELOPMENT_TEAM = {team}\nCODE_SIGN_STYLE = Manual\n'
    f'CODE_SIGN_IDENTITY = Apple Distribution\nPROVISIONING_PROFILE_SPECIFIER = {uuid}\n')
options = plistlib.loads(Path('ios/ExportOptions.plist').read_bytes())
options.update(teamID=team, method='app-store-connect', provisioningProfiles={bundle: uuid})
(folder / 'ExportOptions.plist').write_bytes(plistlib.dumps(options))
print(uuid)
PY
)"
# Xcode 16+ and older Xcode use different profile directories.
for directory in "$HOME/Library/MobileDevice/Provisioning Profiles" \
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$directory"
  cp "$signing_dir/profile.mobileprovision" "$directory/$profile_uuid.mobileprovision"
done

flutter build ipa --release --export-options-plist="$signing_dir/ExportOptions.plist" "${defines[@]}"
tar -czf build/ios/aldia-archive.tar.gz -C build/ios/archive Runner.xcarchive
shopt -s nullglob
ipas=(build/ios/ipa/*.ipa)
if [[ ${#ipas[@]} -ne 1 ]]; then
  echo "::error::Expected one signed IPA. Export failed; inspect the Xcode build log."
  exit 1
fi
# altool finds AuthKey_<id>.p8 in ./private_keys. No Apple ID password is used.
mkdir "$signing_dir/private_keys"
mv "$signing_dir/AuthKey_$APPLE_API_KEY_ID.p8" "$signing_dir/private_keys/"
ipa_path="$PWD/${ipas[0]}"
(
  cd "$signing_dir"
  xcrun altool --validate-app --type ios -f "$ipa_path" --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER_ID"
  xcrun altool --upload-app --type ios -f "$ipa_path" --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER_ID"
)
echo "Uploaded to App Store Connect for processing. Helmut: assign the build to a TestFlight internal group."
