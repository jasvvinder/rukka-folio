# ADR 2026-09-19 — Two app dependencies for the recovery ladder: `mobile_scanner` for the camera, `url_launcher` for `tel:`

**Status: Proposed — awaiting owner ratification.** Prepared by lane M11-PK1 (19 Sep 2026), which was
asked to *evaluate, rule and write the ADR, and add nothing to the build* — the shape ADR 2026-09-12e
took for XLSX: evaluate against this workspace's real constraints, **compile-verify** the failures
rather than assume them, rule, and only then let a later lane write code. Nothing in `app/` or
`app/pubspec.yaml` is touched by this ADR. Every resolution below was run in a **scratch** package
outside the workspace that reproduces `app/pubspec.yaml` plus the root `dependency_overrides`.

**Why it is blocking.** ADR 2026-09-13c ruling 3 🔒 makes the guardian's scan of the candidate device a
**condition** of approving, and ruling 2 🔒 forbids a typed fallback at recovery. The app ships no
camera plugin: `app/lib/features/ceremony/camera_scanner.dart:6` says so in its own banner — *"no
camera plugin is in `app/pubspec.yaml` yet … [NoCameraScanner] reports `unavailable`"*. So today
**S11.7 cannot approve at all and S11.2 cannot be walked**, and the seams
`GuardianRecovery.verifyOwnKeyByScan`, `GuardianApprovals.verifyCandidateByScan` and
`RecoverySheetEntry.scanSheet` (`app/lib/shared/seams/recovery_ladder.dart:577, :895, :760`) can only
answer `RecoveryScanOutcome.unavailable`. The dialer is not blocking; it is a 07 §1 rule 6 defect —
R2.2's per-row **Call** link and R2.3's **Call {name}** button render the number as inert text today
(`app/lib/features/recovery/widgets/recovery_parts.dart:462–478`), because RV4 correctly declined to
draw a control that would do nothing.

## 1. The constraint set, and how each candidate was tested ⟦tests: n/a — method, not behaviour⟧

1. **`archive` 4.x is pinned** (`pubspec.yaml` root `dependency_overrides: archive: '>=4.0.9 <4.1.0'`,
   ADR 2026-09-12d §1) because `sodium` needs it. This is what killed `excel` and
   `spreadsheet_decoder` in 12e, and 12e's own closing Open warns that the override *hides*
   incompatibility at resolution time. So: resolve **and** build.
2. **No proprietary licence** — the ground `syncfusion_flutter_xlsio` was rejected on (12e).
3. **Zero-knowledge is the product** (00, 04 §1.1–§1.2). A candidate that ships analytics, phones home,
   or needs a cloud vision service is disqualified on the threat model, not on taste. Each row below
   says what the candidate actually links against, read from its podspec, `Package.swift`,
   `build.gradle(.kts)` and sources in the pub cache — not from its README.
4. **iOS first** (TestFlight to the owner's family); **Android must not be foreclosed.**

Method, so a reader can repeat it: a scratch package mirroring `app/pubspec.yaml` and the root
override resolved clean (88 packages). Each candidate was then added to a *copy* of it, resolved, and
the lockfile diffed against the baseline; a probe file importing and using the candidate's API was run
through `flutter analyze` (which type-checks the candidate's whole library); and for the two
recommended packages a scratch `flutter create` app was built for real on **Flutter 3.47.0 / Dart
3.13.0 / Xcode 27.0**.

## 2. The scanner ⟦tests: n/a — findings, not behaviour⟧

| Candidate | Version · licence | Resolves under the pin | What it actually links against | Outcome |
|---|---|---|---|---|
| **`mobile_scanner`** | 7.4.2 · **BSD-3-Clause** | **yes — adds exactly one package**, zero transitive, nothing re-resolved | **iOS: nothing but Apple.** `darwin/mobile_scanner/Package.swift` has `dependencies: []`; the podspec's only dependency is `Flutter`; the Swift sources import `AVFoundation, CoreImage, Foundation, VideoToolbox, Vision` and detect with `VNDetectBarcodesRequest`. **Android:** CameraX 1.6.1 + `com.google.mlkit:barcode-scanning:17.3.0` — the **bundled** flavour (the unbundled one is opt-in behind `dev.steenbakker.mobile_scanner.useUnbundled`). See §3: *bundled* means the models ship in the apk, **not** that Play Services is absent. | **Adopt** |
| `google_mlkit_barcode_scanning` | 0.16.1 · MIT (the Dart wrapper) | yes, +2 packages | `ios/*.podspec`: `s.dependency 'GoogleMLKit/BarcodeScanning', '~> 9.0.0'` — a **Google closed-source binary** on iOS, the platform we ship first, and it forces CocoaPods back into a build that is now SPM-only | Reject — §3 |
| `flutter_zxing` | 3.0.1 · MIT | yes, but **+22 packages** including `camera`, `image_picker` and its six platform implementations | zxing-cpp over FFI; sound, but `image_picker` puts the photo library in the app's permission set for a screen that only needs the camera | Reject — cost |
| `qr_code_dart_scan` | 0.14.0 · MIT | yes, +13 packages (`camera`, `zxing_lib` Apache-2.0, `charset`) | pure-Dart decode over `camera`; **no Google, no native blob** | **Keep as the fallback** — §3 |
| `qr_code_scanner` | 1.0.1 (Aug 2022) · BSD-3 | resolves **only because Dart 3 relaxes a `<3.0.0` SDK bound**, and `flutter analyze` is clean — the exact silent-resolution trap 12e warns about | `android/build.gradle` declares **no `namespace`**, `compileSdkVersion 32`, AGP 7.2.2 on its own buildscript; iOS podspec: `deployment_target '8.0'`, `swift_version '4.0'`, `s.dependency 'MTBBarcodeScanner'` | **Reject — compile-verified**, §2a |
| `scan`, `flutter_barcode_scanner` | 1.6.0 (2021), 2.0.0 (2021) | — | unmaintained for five years, pre-null-safety-3 | Reject |
| `ai_barcode_scanner` | 8.2.0 · a wrapper **over `mobile_scanner`** plus `image_picker` | yes | adds a UI we would not use over the package we are adopting anyway | Reject — no content |

**Both builds were run, not reasoned about.** Scratch app + `mobile_scanner` + `url_launcher` +
`sodium_libs` + `pdf` + `printing` under the archive pin: `flutter build ios --simulator --debug` →
**succeeded in 38.9 s**. Flutter 3.47 builds iOS through **Swift Package Manager**, and the generated
`FlutterGeneratedPluginSwiftPackage/Package.swift` lists only local path packages —
`mobile_scanner-7.4.2`, `printing-5.15.0`, `url_launcher_ios-6.4.2`, `FlutterFramework`. No `Podfile`
is generated and **no remote package is fetched at build time.** `otool -L` on the built binary shows
the scanner's frameworks resolved to `/System/Library/Frameworks/…`: `Vision`, `AVFoundation`,
`CoreImage`, `CoreMedia`, `CoreVideo`, `VideoToolbox`. Nothing third-party is linked.

The same app built for Android — `flutter build apk --debug`, **succeeded** in 812 s — which is what
keeps Android from being foreclosed, and what let §3's ML Kit claims be checked against a real apk
rather than against a README.

### 2a. The 12e trap, reproduced ⟦tests: n/a — evidence⟧

`qr_code_scanner` resolves and analyzes clean, which is exactly why it had to be built. Same scratch
app, `flutter build apk --debug`:

```
FAILURE: Build failed with an exception.
* What went wrong:
A problem occurred configuring project ':qr_code_scanner'.
> Could not create an instance of type com.android.build.api.variant.impl.LibraryVariantBuilderImpl.
   > Namespace not specified. Specify a namespace in the module's build file:
     /Users/…/.pub-cache/hosted/pub.dev/qr_code_scanner-1.0.1/android/build.gradle.
BUILD FAILED in 38s
```

Dead since 2022 and fatal on Android under any current AGP. Recorded because a reader who only ran
`dart pub get` and `flutter analyze` would have concluded the opposite — which is 12e's closing Open
in a different package.

**Nothing phones home on the paths we ship.** `mobile_scanner`'s `PrivacyInfo.xcprivacy` declares
`NSPrivacyTracking false` with empty collected-data, accessed-API and tracking-domain arrays; its
Swift contains no `URLSession` or `dataTask`; its `lib/` imports neither `dart:io` nor `package:http`.
Its **web** implementation loads `https://unpkg.com/@zxing/library@…` at runtime
(`lib/src/web/zxing/zxing_barcode_reader.dart:70`) — irrelevant to iOS and Android, and a standing
reason never to enable the web platform without review (ruling 1, last bullet).

It also asks for its own permission — `AVCaptureDevice.requestAccess` on iOS,
`ActivityCompat.requestPermissions(CAMERA)` on Android — so no `permission_handler` joins the tree,
and its manifest declares `<uses-feature android:name="android.hardware.camera" android:required="false"/>`,
which keeps the app installable on a camera-less phone — the same premise as the camera-free path of
design-system §3.1 rule 7 🔒, which this ADR cites and does not change. ⟦tests: n/a — citation, not behaviour⟧

## 3. Why the ML Kit line is accepted on Android and would not be on iOS ⟦tests: n/a — rationale⟧

`com.google.mlkit:barcode-scanning:17.3.0` is a closed-source AAR, and **this lane cannot verify from
here what it transmits** — that needs a network capture on a real Android device, which is out of
reach in this session. What *can* be stated with evidence:

- It is **absent from iOS entirely** in `mobile_scanner` 7.4.2 (§2: `dependencies: []`, Vision only).
  iOS is the first target, so the first release carries no Google code at all.
- **What "bundled" actually buys, checked rather than repeated.** `com.google.mlkit:barcode-scanning`'s
  own POM
  (`~/.gradle/caches/modules-2/files-2.1/com.google.mlkit/barcode-scanning/17.3.0/…/barcode-scanning-17.3.0.pom`)
  declares `com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1` and
  `com.google.android.gms:play-services-basement:18.4.0` among its dependencies. **Play Services is on
  the classpath either way** — the plugin's README framing ("bundled model in app" vs "dynamically
  downloaded model via Google Play Services") is about the *model*, not the *dependency*, and this ADR
  says so plainly because assuming otherwise is the kind of claim rule 11 was written for. What the
  bundled flavour does buy is verified in the built apk: `assets/mlkit_barcode_models/*.tflite`
  (three files, ≈0.86 MB) ship inside it, so detection needs no model download and works with no
  network at all — which is the property an offline-first ledger needs.
- What it is shown is **camera frames of a QR this app itself rendered** — a public key and a user id
  (04 §6.1 `QrPayload`, 04 §9.1 `DeviceQrPayload`). No amount, no account name, no entry. CLAUDE.md
  rule 4 (no plaintext financial data outside the vault) is not engaged by this component at all.
- `google_mlkit_barcode_scanning` fails where `mobile_scanner` passes precisely because it puts the
  *same* vendor binary on **iOS**, where Apple already ships a barcode detector we can use instead.
  Taking a Google binary when the platform's own framework does the job is the part that is refused.

If the Android capture ever shows it calling home, the exit is already costed: `qr_code_dart_scan`
(pure-Dart decode over `camera`, MIT + Apache-2.0, +13 packages) resolves clean under the pin today,
and the `CeremonyScanner` seam means the swap is one adapter file. That is the whole point of the seam
and is why this ADR does not treat the choice as irreversible.

## 4. The dialer ⟦tests: n/a — findings, not behaviour⟧

`url_launcher` 6.3.2, **BSD-3-Clause, published by the Flutter team in `flutter/packages`** — the same
provenance as `camera` and `path_provider`. It resolves clean and built in the same scratch iOS build
above. `url_launcher_ios` 6.4.2 imports only `Flutter`, `Foundation`, `UIKit` and `SafariServices`,
and its privacy manifest is empty in the same four respects. There is no second candidate worth a row:
`flutter_phone_direct_caller` places the call **without** the dialer confirming, which needs Android's
`CALL_PHONE` permission and puts a dangerous permission in the manifest for a convenience link — that
is not a trade this product makes. Writing the platform channel by hand is two native files to
maintain for a thing the Flutter team maintains for free.

One thing was read rather than assumed, and it changes the ruling. On iOS, `launchUrl` calls
`UIApplication.open` **directly** — there is no `canOpenURL` gate
(`url_launcher_ios-6.4.2/…/URLLauncherPlugin.swift:35–47`); only `canLaunchUrl` calls `canOpenURL`
(`:27–32`). On Android, `launchUrl` is `startActivity` inside a `try/catch (ActivityNotFoundException)`
(`url_launcher_android-6.3.33/…/UrlLauncher.java:95–96`), while `canLaunchUrl` is `resolveActivity`
(`:56`). **Therefore: if the app never calls `canLaunchUrl`, it needs no `LSApplicationQueriesSchemes`
entry in `Info.plist` and no `<queries>` block in `AndroidManifest.xml`** — the two configuration
steps `url_launcher`'s README asks for both exist only to make `canLaunchUrl` answer truthfully.
The package's own README reaches the same conclusion for the same reason: *"in cases where you can
provide fallback behavior it is better to use `launchUrl` directly and handle failure, rather than
disabling the button."* That is 07 §1 rule 6 stated by the plugin's own authors.

## Rulings 🔒 (proposed) ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. `mobile_scanner` is adopted as the app's only camera/QR dependency ⟦tests: F1-07-312 @M11, F1-07-313 @M11⟧
- `app/pubspec.yaml` gains `mobile_scanner: ^7.4.2` and nothing else — the resolution adds **one**
  package and changes no existing version, verified against the `archive` pin. ⟦tests: n/a — resolution fact⟧
- It enters the app **only** through the existing `CeremonyScanner` seam
  (`app/lib/features/ceremony/camera_scanner.dart`). No screen imports `package:mobile_scanner`
  directly; `NoCameraScanner` and `FakeCeremonyScanner` stay, and every widget test keeps running
  without a camera. The plugin's failures map onto the seam's existing vocabulary: permission refused
  → `CameraStatus.denied`, no camera or camera busy → `CameraStatus.unavailable`. ⟦tests: F1-07-312 @M11⟧
- The three recovery seams (`verifyOwnKeyByScan`, `verifyCandidateByScan`, `scanSheet`) are then
  implementable, which is what unblocks S11.2, S11.7 and S11.3. `RecoveryScanOutcome.unavailable`
  keeps its meaning — *this phone cannot scan* — and must keep rendering the honest dead-endless state
  the screens already draw, never a dead preview. ⟦tests: F1-07-313 @M11⟧
- **The Android ML Kit line is accepted with its residual stated** (§3): closed-source, Android-only,
  bundled model, shown nothing but a QR this app rendered. Before the first Android release a network
  capture settles what it transmits; if it transmits anything, `qr_code_dart_scan` is the costed exit
  behind the same seam. ⟦tests: n/a — accepted residual + Open 1⟧
- **The web platform is not enabled for this app.** `mobile_scanner`'s web path fetches a decoder from
  `unpkg.com` at runtime; a zero-knowledge ledger does not load executable code from a CDN. ⟦tests: n/a — scope bound⟧
- `Info.plist` gains `NSCameraUsageDescription` in all three languages; Android needs no manifest edit
  (the plugin's own manifest declares `CAMERA` and `camera required=false`). ⟦tests: n/a — platform config⟧

### 2. `url_launcher` is adopted for `tel:` only, behind a seam, and `canLaunchUrl` is never called ⟦tests: F1-07-314 @M11⟧
- `app/pubspec.yaml` gains `url_launcher: ^6.3.2`, used for **`tel:` and nothing else**. It is not a
  general door to the browser: the app has exactly one HTTP door (`http`, per the pubspec's own
  comment) and this does not become a second one. ⟦tests: n/a — scope bound⟧
- It enters through a `Dialer` seam beside `camera_scanner.dart`'s precedent — one method,
  `Future<bool> dial(String number)` — so screens never import `package:url_launcher` and widget tests
  drive a fake. ⟦tests: F1-07-314 @M11⟧
- The implementation calls **`launchUrl(Uri(scheme: 'tel', path: number))` and never `canLaunchUrl`**
  (§4). Consequence, stated so it is not later "fixed" by someone adding the config back: **no
  `LSApplicationQueriesSchemes` entry and no `<queries>` block are added.** ⟦tests: F1-07-314 @M11⟧
- A number is never parsed, normalised or reformatted by the app: the bytes the book holds are the
  bytes handed to the dialer. ⟦tests: F1-07-314 @M11⟧

### 3. A *Call* control is a control, and its failure is not silence ⟦tests: F1-07-314 @M11, F1-07-315 @M11⟧
- With the dialer wired, R2.2's per-row **Call** link (S11.2) and R2.3's **Call {name}** button (S11.7)
  are real controls wherever the book holds a number. The plain-text render RV4 shipped stays as the
  **no-number** branch, which is correct and is not regressed. ⟦tests: F1-07-315 @M11⟧
- `dial` returning **false** — no SIM, a tablet, the iOS Simulator — renders the number with a
  *copy the number* action and a one-line explanation. It does not throw, does not vanish, and does not
  leave a tapped control that did nothing.
  This is 07 §1 rule 6 🔒 — *every blocked action explains why and offers the path.* ⟦tests: F1-07-314 @M11⟧
- The failure line carries an icon and words, and no meaning rests on its colour — 07 §1 rule 3 🔒. ⟦tests: F1-07-315 @M11⟧
- Its strings go through ARB in EN, PA and HI like every other. ⟦tests: F1-07-315 @M11⟧

## Consequences
- **Dependencies (`app/pubspec.yaml` — the shell lane's file, not this lane's):** two lines,
  `mobile_scanner: ^7.4.2` and `url_launcher: ^6.3.2`, each with the comment this repo's pubspec
  already uses for `pdf`/`archive`/`qr` — what it is for, and what it links against, so the next
  evaluation starts from a fact rather than a search.
- **Code (a later lane, after ratification):** a `MobileScannerCeremonyScanner implements
  CeremonyScanner` in `app/lib/features/ceremony/`; a `Dialer` seam plus its `url_launcher`
  implementation in `app/lib/shared/seams/`; `onCall` wired in
  `app/lib/features/recovery/{recovery_routes.dart,widgets/recovery_parts.dart}` and in S11.7; the
  three recovery scan seams implemented over the ceremony scanner. `camera_scanner.dart:6`'s
  `⚠️ WIRE` banner is deleted in that commit — it is the marker that says this is still open.
- **Platform config:** `NSCameraUsageDescription` (EN/PA/HI) in `app/ios/Runner/Info.plist`. No
  `LSApplicationQueriesSchemes`, no `<queries>` (ruling 2).
- **Docs (owner applies on ratification — this ADR edits no numbered spec):** 07 §5.6 / 13 §3.2's
  S11.2, S11.3 and S11.7 rows stop saying the scan is unavailable; design-system §3.1 rule 7's
  camera-free path is unchanged and now has a real camera to be the alternative to.
- **Milestone:** M11.

## Ids reserved (`check_coverage` reports these as planned until the tests land)
| Id | Ruling | One-line test |
|---|---|---|
| F1-07-312 @M11 | 1 | the `mobile_scanner` adapter satisfies `CeremonyScanner`: refused permission → `CameraStatus.denied`, absent camera → `unavailable`, `dispose` is safe twice; S9.3 opens on the code path in both and draws no preview |
| F1-07-313 @M11 | 1 | S11.2, S11.7 and S11.3 reach their verified states through the seam with a `FakeCeremonyScanner`; on `RecoveryScanOutcome.unavailable` each renders its stated way out and no screen imports `package:mobile_scanner` |
| F1-07-314 @M11 | 2, 3 | the `Dialer` seam is handed `tel:<the stored digits, unaltered>`; the fake asserts `canLaunchUrl` is never called; `dial → false` renders the explanation + *copy the number*, in EN, PA and HI, with no overflow at 200 % on 360×800 |
| F1-07-315 @M11 | 3 | R2.2's row **Call** link and R2.3's **Call {name}** button are enabled controls when a number exists and are absent (number as plain text) when it does not; the failure line pairs its colour with an icon and words |

## Ratification checklist — four answers for the owner 🔒 ⟦tests: n/a — heading; each answer below carries its own marker⟧
1. **Ruling 1** — adopt `mobile_scanner` 7.4.2 (BSD-3; Apple Vision on iOS, CameraX + bundled ML Kit on
   Android) behind the `CeremonyScanner` seam: **yes / no.** ⟦tests: F1-07-312 @M11, F1-07-313 @M11⟧
2. **The Android residual** (§3) — accept a closed-source Google barcode AAR on Android only, shown
   nothing but a QR this app rendered, with a network capture before the Android release and
   `qr_code_dart_scan` as the costed exit: **accept / reject.** If rejected, the answer is
   `qr_code_dart_scan` on both platforms from the start, at +13 packages and a slower decode.
   ⟦tests: n/a — residual acceptance⟧
3. **Ruling 2** — adopt `url_launcher` 6.3.2 for `tel:` only, behind a `Dialer` seam, never calling
   `canLaunchUrl` and therefore adding no `Info.plist`/manifest query config: **yes / no.**
   ⟦tests: F1-07-314 @M11⟧
4. **Ruling 3** — a failed `dial` shows the number with *copy the number*, rather than the control
   being disabled or absent: **yes / no.** ⟦tests: F1-07-314 @M11, F1-07-315 @M11⟧

## Open ⚠️ — including what this lane could **not** verify
1. **What `com.google.mlkit:barcode-scanning:17.3.0` transmits, if anything.** Not checked: it is a
   closed-source AAR and the check is a network capture on a real Android device, which this session
   could not run. Settles it: `mitmproxy`/`tcpdump` against a debug build on a physical phone before
   the first Android release. The iOS-first plan means this is not on the critical path.
2. **No scan or call was executed end to end.** The iOS build is a **simulator** build; a simulator has
   no camera and no Phone app, and `url_launcher`'s own README says exactly that — *"iOS simulators
   don't have a default email or phone apps installed, so can't open `tel:` or `mailto:` links."* So
   *"the scanner decodes a 04 §6.1 `QrPayload` at the size S9.2 renders it"* and *"a tap dials"* are
   **unverified from here** and are the first two things to confirm on the owner's TestFlight build.
   The QR payload's own size and error-correction level are S9.2's and are not changed by this ADR.
3. **Android was built, and the apk inspected — but not run.** `flutter build apk --debug` on the same
   scratch app **succeeded** (812 s, `app-debug.apk`), and the apk contains the bundled ML Kit models
   as assets (§3). Not checked: behaviour on a real Android device, and the network question of Open 1.
   `qr_code_scanner`'s Android failure is evidenced directly from its `android/build.gradle`, which
   declares no `namespace` at all — AGP 8 rejects that outright.
4. **`app/pubspec.yaml` is not this lane's file** and was deliberately not edited; the two lines in
   § Consequences are for the lane that owns it. Until then the `⚠️ WIRE` banner at
   `app/lib/features/ceremony/camera_scanner.dart:6` is still true.
5. **Design gap, unchanged by this ADR:** no canvas draws S11.2's *scan your guardian's screen* step or
   S11.7's *show / scan* pair (ADR 2026-09-13c Open 2, still open), nor a *call failed* line for R2.2 /
   R2.3. Ruling 3's failure state is therefore this lane's conservative reading of 07 §1 rule 6, not a
   drawn design — the design owner may replace it.
