# Mobile release runbook

Prepared on 2026-11-19. This prepares builds and distribution plumbing; store approval and real-device acceptance
have not been verified. Do not submit the demo as a finished municipal service. Every account-dependent action below
is marked **Helmut**. No store account was accessed and no signing credentials were created for this work.

## Already prepared

| Area | Prepared behavior |
| --- | --- |
| Debug CI | `.github/workflows/mobile.yml`: pushes to `develop` and manual runs build a debug APK artifact, retained 14 days. A separate Linux debug build checks desktop compilation. No signing secrets needed. |
| Android release | `mobile-release.yml`: manual only; checks all four secrets, builds signed AAB and APK, retains them and the R8 mapping for 14 days. Does not upload to Google Play. |
| iOS | `ios-release.yml`: manual only, `macos-latest`; unsigned device archive without Apple secrets; complete credentials permit signed IPA validation and TestFlight upload. Archives/IPA retained 14 days. |
| Toolchain | Official Flutter release tag `3.47.9`, installed exactly as in `ci.yml`; actions pinned by commit SHA, `contents: read`, checkout credentials not persisted. Android SDK/Java come from the runner image. |
| Native setup | Android label `Aldia`, R8 minification/resource shrinking, no debug-key release fallback. iOS 15.0 Podfile and Xcode settings, Spanish permission prompts, no background modes, encryption exemption flag, export template. |
| Artwork | Original geometric white A on graphite `#242424`; Android adaptive/legacy/monochrome icons, pre-12 and Android 12+ splash, all iOS AppIcon sizes (opaque RGB, including 1024 px) and neutral LaunchScreen. |
| Versions | `app/pubspec.yaml` currently `0.1.0+1`: Android versionName `0.1.0` / versionCode `1`; iOS short version `0.1.0` / build `1`. No CI override. Increase the build number for each uploaded build, including reruns after a successful upload. |

`ci.yml` and branch protection are unchanged. These workflows introduce no required status checks.
The new manual workflows must first be present on the repository's default branch for GitHub's **Run workflow**
button to appear; that merge is outside this job. Then choose the intended source ref, normally `develop`.

### Identifiers and public configuration

- Android application ID/namespace: **`org.aldia.aldia_app` — provisional, to change/confirm before store creation**.
  Before the first upload, choose an ID owned by the publisher, update `app/android/app/build.gradle.kts`, move/update
  `MainActivity.kt`'s package if changing the namespace, and update `AppConfig.userAgentPackage` in
  `app/lib/core/config.dart`. Search `app/` for the old ID to catch references. After publication the ID must stay fixed.
- iOS bundle ID: **`org.aldia.aldiaApp`** in all Runner build configurations (RunnerTests adds `.RunnerTests`).
  **Helmut:** register this exact App ID under the Apple team, or choose an available owned ID and update all Runner
  configurations plus the `provisioningProfiles` key in `app/ios/ExportOptions.plist` before making store records.
- Signed workflows require `api_base_url` (HTTPS, ending in `/api`) and `public_portal_url` (HTTPS).
  They are public build settings, not secrets; do not embed API tokens in URLs or `--dart-define` values.
  Example shape only: `https://api.YOUR-DOMAIN/api`, `https://YOUR-DOMAIN`.
  These endpoints must actually be deployed and usable by reviewers and testers.
- Map tiles/address lookup currently use public OpenStreetMap/Nominatim demo services; follow the deployment limits
  in [app/README.md](../app/README.md). Arrange a production provider/proxy before multi-user distribution.
  `TILE_URL` can be supplied to local Flutter commands; changing provider configuration in CI needs a workflow update.

## Get the debug APK onto an Android phone

1. **Helmut (GitHub):** open **Actions → Mobile debug builds → Run workflow**, choose `develop`, and set URLs reachable
   from the phone. With USB debugging, use `http://127.0.0.1:8000/api` and `http://127.0.0.1:5173` plus the reverse
   commands below. Over private Wi-Fi, use the computer's LAN IP and start the API on `0.0.0.0:8000`.
   Push-triggered builds default to the Android emulator's `10.0.2.2`; that address does not reach a laptop from a
   physical phone. URLs are compiled in; changing them requires another build.
2. **Helmut (GitHub):** after the Android job succeeds, download `aldia-android-debug-<run number>` from the run's
   **Artifacts** section before its 14-day expiry. Unzip it to obtain `app-debug.apk`.
3. Enable Developer options and USB debugging on the phone, connect it and accept its trust dialog. With Android
   platform tools installed, run these locally (no store account needed):

   ```bash
   adb devices
   adb reverse tcp:8000 tcp:8000
   adb reverse tcp:5173 tcp:5173
   adb install -r /path/to/app-debug.apk
   ```

4. Alternatively transfer `app-debug.apk` to the phone, tap it in Files and allow **Install unknown apps** for that
   file manager when prompted; remove that permission afterwards. Android/OEM policy may require additional confirmation.
5. Open **Aldia**, allow camera/location while using the app, and run the device scenarios in
   [testing.md §4.3](testing.md#43-app-on-a-real-android-phone-not-executed).
   Debug HTTP is allowed; signed Android releases require HTTPS. A signature mismatch when replacing a release/older
   CI debug build requires uninstalling the old app first (this deletes its local drafts and outbox).

## Android signing and Google Play

### Create and protect the upload key

1. On Helmut's machine, outside the checkout, create the upload keystore. This prompts for passwords and certificate
   identity locally; do not pass passwords on the command line or paste them into chat:

   ```bash
   mkdir -p "$HOME/.local/share/aldia-signing"
   chmod 700 "$HOME/.local/share/aldia-signing"
   keytool -genkeypair -v -storetype JKS -keyalg RSA -keysize 2048 \
     -validity 10000 -alias aldia-upload \
     -keystore "$HOME/.local/share/aldia-signing/aldia-upload.jks"
   chmod 600 "$HOME/.local/share/aldia-signing/aldia-upload.jks"
   ```

2. Back up the keystore and passwords in private secure storage. This is an **upload key** when using Play App Signing;
   Google holds the app signing key. The locally signed APK uses the upload key, so it normally cannot update a
   Play-installed app. Never commit the keystore, `key.properties`, or base64 output (base64 is not encryption).
3. **Helmut (GitHub):** repository **Settings → Secrets and variables → Actions → New repository secret**:

   | Secret | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | Base64 of the entire `.jks` file, not a path |
   | `ANDROID_KEYSTORE_PASSWORD` | Keystore password from keytool |
   | `ANDROID_KEY_ALIAS` | `aldia-upload` |
   | `ANDROID_KEY_PASSWORD` | Key password; if keytool reused the store password, use that same value |

   To avoid terminal output, **Helmut (GitHub CLI, already authenticated)** can send the bytes directly to a secret:

   ```bash
   base64 < "$HOME/.local/share/aldia-signing/aldia-upload.jks" | tr -d '\n' | \
     gh secret set ANDROID_KEYSTORE_BASE64 --repo helmutkurk/ciudad-check
   gh secret set ANDROID_KEYSTORE_PASSWORD --repo helmutkurk/ciudad-check
   gh secret set ANDROID_KEY_ALIAS --repo helmutkurk/ciudad-check
   gh secret set ANDROID_KEY_PASSWORD --repo helmutkurk/ciudad-check
   ```

   The last three commands prompt for the values. Use the actual repository slug if it differs.
4. **Helmut (GitHub):** run **Android release** on the intended ref with real HTTPS URLs. Missing secrets fail before
   Flutter installation. CI decodes the keystore only into runner temp storage, passes its path/passwords through
   the environment, and removes it in an `always()` step. Download the signed AAB/APK and archive the R8 mapping
   privately before the artifact expires. This workflow makes no Google Play API calls.

Optional local build (no store account required): copy `app/android/key.properties.example` to ignored
`app/android/key.properties`, edit it privately and use an absolute keystore path. Java `.properties` passwords
containing backslashes/newlines need proper escaping; environment variables avoid that issue. Gradle reads
`storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Environment variables take precedence:
`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
The base64 variable is decoded by CI's `scripts/prepare_android_signing.py`, not by Gradle.

```bash
cd app
mise exec -- flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.YOUR-DOMAIN/api \
  --dart-define=PUBLIC_PORTAL_URL=https://YOUR-DOMAIN
mise exec -- flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.YOUR-DOMAIN/api \
  --dart-define=PUBLIC_PORTAL_URL=https://YOUR-DOMAIN
```

### Console and first internal release

1. **Helmut (Google):** create/verify a Google Play Console developer account, choose the appropriate individual or
   organization publisher, complete identity/contact checks and accept the current agreements.
2. **Helmut (Play Console):** **All apps → Create app**; name **Aldia**, default language Spanish, app type **App**,
   free distribution, and complete the declarations. Confirm the permanent application ID before first AAB upload.
3. **Helmut (Play Console):** **Testing → Internal testing → Create new release**; enroll in Play App Signing,
   upload `app-release.aab`, add Spanish release notes, resolve Console validation errors, review and roll out to
   internal testing. Add a tester email list/group, save it and share the opt-in link with those testers.
   Install from that link using a tester's Google account; verify camera, GPS, networking and offline retry.
4. **Helmut (Play Console):** fill **App content** (ads: **No**, audience, content rating, app access/reviewer
   instructions) and the store listing below. If login is later enabled, provide working reviewer access.
5. **Helmut (Play Console):** complete Data safety and privacy/deletion URLs using the facts below. Internal-only
   testing is currently exempt from the displayed Data safety section; prepare it before broader distribution.
   Follow any testing/production-access requirements shown for this developer account; internal testing does not
   automatically qualify an account for production. See [Google's testing guide](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en).

## iOS and TestFlight

The simulator cannot take the required live photo. It can test onboarding, maps, filters and existing reports;
the full report path needs a real iPhone. `DEV_FAKE_CAMERA` is disabled on mobile, including simulators.
An unsigned **device** archive is a build check; it cannot run on the simulator, install on a phone or go to TestFlight.

### Account-free build path

**Helmut (GitHub):** run **iOS archive and TestFlight**, distribution **unsigned** (or **auto** with no Apple secrets).
No Apple account is needed. Download the archive tarball from the artifact and extract with:

```bash
tar -xzf aldia-archive.tar.gz
```

On a Mac with Xcode and CocoaPods installed, the equivalent local unsigned check is:

```bash
cd app
mise exec -- flutter pub get
BYPASS_PERMISSION_LOCATION_ALWAYS=1 mise exec -- flutter build ipa --release --no-codesign
# build/ios/archive/Runner.xcarchive; no IPA without signing
```

Flutter integrates Swift Package Manager plugins and uses the Podfile for any remaining CocoaPods plugins.
The CI script exports `BYPASS_PERMISSION_LOCATION_ALWAYS=1` for geolocator's Swift package; the Podfile defines the
same flag for CocoaPods. Also set this environment variable for local iOS builds/runs to omit always-location support.
The Podfile and Xcode project both target iOS 15.0. Spanish camera, photo-purpose, foreground location and local-network
strings are present. The photo-purpose string covers the image-picker native library; the app offers live camera,
not a gallery picker. No microphone, always-location, tracking or background modes are requested.
The encryption exemption assumes standard platform HTTPS only; reassess it if custom encryption is introduced.

### Create the Apple identities and upload credentials

1. **Helmut (Apple):** enroll in the paid Apple Developer Program, complete verification/agreements and note the
   10-character **Team ID**. A free personal team is insufficient for TestFlight distribution.
2. **Helmut (Apple Developer → Certificates, Identifiers & Profiles):** register an explicit App ID matching
   `org.aldia.aldiaApp`. Enable only capabilities actually used; no push/background capability is configured.
3. **Helmut (Apple/Xcode/Keychain Access):** create an **Apple Distribution** certificate with a local certificate
   signing request. Download/install it on the Mac where its private key was generated. Export certificate **and
   private key** together as a password-protected `.p12` in Keychain Access; a `.cer` alone cannot sign.
4. **Helmut (Apple Developer):** create an **App Store Connect distribution provisioning profile** for the explicit
   App ID and that distribution certificate; download the `.mobileprovision`. No device registration is required
   for this profile. The workflow checks team, bundle, expiry and distribution type. See
   [Apple's profile guide](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile).
5. **Helmut (App Store Connect):** **Apps → + → New App**, iOS, name **Aldia**, Spanish primary language, the matching
   Bundle ID, unique internal SKU (for example `aldia-ios`), and access for the release team.
6. **Helmut (App Store Connect → Users and Access → Integrations → App Store Connect API):** create a **team API key**
   with an upload-capable role (App Manager), note its **Key ID** and **Issuer ID**, download its `.p8` once and back
   it up privately. The API key authenticates uploads; it does not replace the certificate/private key/profile
   used for offline manual signing in this workflow. An individual key without a team Issuer ID is not this setup.
7. **Helmut (GitHub):** add all seven repository secrets:

   | Secret | Value |
   | --- | --- |
   | `APPLE_TEAM_ID` | 10-character Apple team ID |
   | `APPLE_CERTIFICATE_BASE64` | Base64 of Apple Distribution certificate + private key `.p12` |
   | `APPLE_CERTIFICATE_PASSWORD` | Nonempty `.p12` export password |
   | `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 of matching App Store `.mobileprovision` |
   | `APPLE_API_KEY_ID` | App Store Connect team API Key ID |
   | `APPLE_API_ISSUER_ID` | Team API Issuer UUID |
   | `APPLE_API_PRIVATE_KEY_BASE64` | Base64 of downloaded `AuthKey_<KeyID>.p8` |

   **Helmut (GitHub CLI, authenticated):** send file contents directly, without printing them:

   ```bash
   base64 < /PRIVATE/PATH/AppleDistribution.p12 | tr -d '\n' | gh secret set APPLE_CERTIFICATE_BASE64 --repo helmutkurk/ciudad-check
   base64 < /PRIVATE/PATH/Aldia.mobileprovision | tr -d '\n' | gh secret set APPLE_PROVISIONING_PROFILE_BASE64 --repo helmutkurk/ciudad-check
   base64 < /PRIVATE/PATH/AuthKey_KEYID.p8 | tr -d '\n' | gh secret set APPLE_API_PRIVATE_KEY_BASE64 --repo helmutkurk/ciudad-check
   gh secret set APPLE_TEAM_ID --repo helmutkurk/ciudad-check
   gh secret set APPLE_CERTIFICATE_PASSWORD --repo helmutkurk/ciudad-check
   gh secret set APPLE_API_KEY_ID --repo helmutkurk/ciudad-check
   gh secret set APPLE_API_ISSUER_ID --repo helmutkurk/ciudad-check
   ```

8. **Helmut (GitHub):** run **iOS archive and TestFlight → testflight**, source ref and production HTTPS URLs.
   **auto** also signs/uploads when all seven secrets exist; **unsigned** always skips signing/upload.
   Partial setup or explicit **testflight** without all secrets fails with missing secret names.
   The runner imports the certificate into a temporary keychain, writes ignored `Flutter/Signing.xcconfig`, exports
   the IPA and validates/uploads with `xcrun altool` using the API key. The cleanup trap removes temporary key material,
   installed profiles and signing config. Credentials are never included in artifacts. Use GitHub-hosted runners only.
9. **Helmut (App Store Connect):** wait for build processing, resolve any validation/export compliance messages,
   complete beta description/contact details, then **TestFlight → Internal Testing → +** to create a group. Add team
   users with app access under **Users and Access**, add the processed build, invite testers, and have them accept
   through the TestFlight app on their iPhones. Upload success alone does not assign the build to a group.
   See [Apple's internal tester guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).
10. **Helmut (App Store Connect):** before public review, enter the privacy labels below, support/privacy URLs,
    screenshots and review notes. Check the archive's Xcode privacy report for every plugin's manifest and required
    API reasons; source plugins ship their own manifests. Follow any new validation requirements rather than claiming
    this Linux-only preparation proves acceptance. See [Apple's SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/).

For a local signed export, **Helmut (Apple/Xcode):** copy `ios/ExportOptions.plist` outside the repo, replace the team/profile placeholders,
select the team/certificate/profile for Runner in Xcode and use `flutter build ipa --release --export-options-plist=...`
with the same public URL defines. The tracked template uses `app-store`; the CI script renders the modern Xcode
equivalent `app-store-connect` into runner temp storage. Never commit a real `Signing.xcconfig` or certificate.
The [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios) covers archive/export/upload behavior;
the temporary-keychain setup follows [GitHub's signing guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

## Privacy declarations based on this code

These are a worksheet for **Helmut**, not already-submitted store answers. Check the exact binary and production
backend/providers at submission time, especially if the parallel phone-login job has landed. Sources of project facts:
[API contract](api-contract.md), [app behavior](../app/README.md), `app/lib/services/photo_service.dart`,
`app/lib/services/location_service.dart` and the native permission manifests.

| Data/use | Current facts and proposed declarations |
| --- | --- |
| Camera/photos | Live photo is required to submit; photo is uploaded/stored and publicly viewable with the report. EXIF is stripped server-side, which does not remove visible faces/plates. Google: collected **Photos**, purpose **App functionality**. Apple: **Photos or Videos**, purpose **App Functionality**. No video/audio feature. |
| Location | Foreground GPS or user-chosen precise report coordinates are sent and public. Google: **Precise location**; also declare **Approximate location** if coarse permission/provider/logging yields it. Apple: **Precise Location** (and **Coarse Location** if actually collected). Purpose: app functionality. Manual map entry works when GPS is denied; report location is still required. No background location. |
| Written report | Category, note and capture time go to the API. Google: **Other user-generated content**; Apple: **Other User Content**, app functionality. The note is optional. Do not write private personal details. |
| Phone number | The reviewed app has a phone-account placeholder, not real SMS login. For that binary, do not claim phone collection. **If phone login is enabled before release:** Google **Phone number**, **Account management**; Apple **Phone Number**, **App Functionality**, linked to the account. Include the SMS/identity provider, retention and deletion process. Never mark a collected number as anonymous. |
| Advertising/tracking | No ads, advertising ID, ad SDK, cross-app tracking or analytics SDK in the reviewed app. Google **Contains ads: No**; Apple **Data Used to Track You: No**. Recheck new SDKs and service logs. Permission to access the camera is not itself a separate collected-data type. |
| Links and identifiers | Reports have public IDs; local follows/inbox/drafts are device-local. No verified anonymous-data guarantee exists. For Apple, conservatively mark submitted content/location **linked to user** unless the final service demonstrably de-identifies it before collection; phone data is linked when enabled. Audit backend identifiers/logs before answering either store's identifier categories. |
| Sharing | Public photos/coordinates/notes are intentionally published; municipality/hosting/verifier and map/geocoder providers also need disclosure. Google user-initiated transfers and service-provider transfers can qualify for sharing exceptions, but collection remains reportable. **Helmut:** confirm actual consent/provider contracts before choosing any sharing exemption. |
| Transport, retention, deletion | Release endpoints must use HTTPS. Do not answer **encrypted in transit: Yes** until all actual endpoints/providers satisfy it. **Borrar mis datos** only deletes local data; submitted public reports remain on the server. Do not claim server/account deletion exists. **Helmut:** publish an actual retention/support/deletion process and required URLs before submission; enable compliant account deletion if accounts are added. |

**Helmut (Play Console):** use this worksheet in **App content → Data safety**, review each collected data type's
purpose, required/optional status and sharing, and link an actual privacy policy. See
[Google's Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).
**Helmut (App Store Connect):** use **App Privacy → Get Started/Edit**, choose collected types/purposes/linkage,
confirm no tracking, and publish the labels and privacy policy URL. See
[Apple's privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).
No privacy or support URL below is a live policy; replace every placeholder before distribution.

## Spanish store-listing text pack

Use this copy only where the corresponding service is available. It deliberately promises neither automatic AI
classification, SMS login, push notifications, official municipal participation nor a guaranteed repair deadline.

| Field | Copy |
| --- | --- |
| Name (both stores) | Aldia |
| Google Play short description | Reporta problemas de tu calle con foto y ubicación y consulta su estado. |
| Apple subtitle | Tu ciudad, al día |
| Apple keywords | ciudad,reportes,baches,calles,alumbrado,accesibilidad,comunidad,mapa |
| Google Play category | Tools / Herramientas |
| Apple primary / secondary category | Utilities / Utilidades; Social Networking / Redes sociales (optional) |
| Support URL | `https://YOUR-DOMAIN/support` — **Helmut: publish and replace** |
| Privacy policy URL | `https://YOUR-DOMAIN/privacy` — **Helmut: publish and replace** |
| Data/account deletion URL if required | `https://YOUR-DOMAIN/delete-data` — **Helmut: implement/publish and replace** |
| Support email | `SUPPORT_EMAIL_TO_REPLACE` — **Helmut: provide a monitored address** |

Long description:

```text
Ayuda a poner tu ciudad al día.

Con Aldia puedes reportar problemas de la vía pública con una foto tomada en el momento y la ubicación del lugar.
Señala un bache, una luminaria apagada o una barrera de accesibilidad y consulta los reportes en el mapa o en la lista.

• Elige el lugar y la categoría del problema.
• Revisa reportes cercanos para evitar duplicados.
• Toma una foto, añade una descripción y envía el reporte.
• Guarda un borrador o deja el envío pendiente cuando no tengas conexión.
• Sigue reportes y consulta los cambios de estado al actualizar la app.

La foto, la ubicación y la descripción del reporte se publican para ayudar a entender el problema. Evita incluir
personas, placas de vehículos o información privada. Puedes ubicar el punto en el mapa si no deseas usar el GPS.

Aldia no incluye anuncios. La atención de los reportes depende de la disponibilidad del servicio y de la entidad
responsable en cada lugar; enviar un reporte no garantiza una reparación ni un plazo de respuesta.
```

Initial internal-test release notes:

```text
Primera versión de prueba de Aldia: reportes con foto y ubicación, mapa, borradores y consulta de estados.
La verificación de categoría está en modo de prueba. Comparte tus observaciones con el equipo.
```

**Helmut (both consoles):** paste/review the copy, choose actual supported countries and audience, upload screenshots
from the shipped build (synthetic/consented report data only), and supply the publisher/support details. Public store
screenshots must not expose local tokens or real people's photos. A privacy URL and a functioning production service
are release requirements, not satisfied by placeholders or a successful build.

## Regenerate assets and verify

Pillow is a development-machine tool only (already available for generation here); no app dependency or lockfile was
added. From the repository root:

```bash
python3 app/scripts/generate_icons.py
cd app
mise exec -- flutter analyze
mise exec -- flutter test
```

Before distribution, run [testing.md](testing.md) on real Android and iPhone hardware, including fresh install, denied
permissions, rotation, offline/outbox retry, HTTPS uploads, sharing and upgrades. Keep the R8 mapping and iOS archive
for each released build. Android/iOS native builds and TestFlight can only be confirmed by their respective workflows
and device checks; this machine has no Android SDK or Xcode.

### Validation recorded for this preparation

- Flutter analysis: clean; Flutter tests: **104 passed**; Linux debug bundle: built successfully.
- The installed Flutter SDK cache is read-only in the sandbox. Analysis, tests and Linux build ran with the same
  Flutter version in the existing writable SDK/cache, using the README's fallback:
  `mise exec -- env PATH=/tmp/aldia-flutter-sdk/bin:$PATH PUB_CACHE=/tmp/aldia-pub-cache flutter analyze`
  (replace `flutter analyze` with `flutter test` or `flutter build linux --debug` for the other checks).
- PyYAML parsed all three workflows; trigger, read-only permission and full action-SHA assertions passed.
  Native XML/plists parsed, Bash syntax and `ruby -c ios/Podfile` passed. Icon dimensions, opacity and deterministic
  regeneration were checked; the generated 1024 px icon was visually inspected.
- Synthetic script checks exercised missing/malformed Android secrets and URL rejection; iOS auto/unsigned/missing/
  partial/complete/expired-profile paths, export settings and cleanup passed with stubbed Flutter/Apple commands.
  These checks used no real signing keys and contacted no store.
- Actual Android/iOS compilation, certificate validity, device installation, export/upload and store acceptance remain
  unverified until the hosted workflows and Helmut's device/account steps run.
