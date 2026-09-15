# Running Rukka Folio on an iPhone (or the Simulator)

Written 16 Sep 2026 against this machine's actual state: **Xcode 27.0** at `/Applications/Xcode.app`,
**CocoaPods 1.17.0**, **Flutter 3.47.0** (stable), iOS deployment target **15.0**, bundle id
`com.rukkafolio.rukkaFolio`.

**Read § 0 first.** It is the only part that needs a password, it is needed for *both* the Simulator and a
real iPhone, and it also permanently fixes `flutter test` on this machine.

---

## 0. One-time Mac setup — required for anything iOS

Xcode is installed but not *selected*, which is why `flutter doctor` says *"Xcode installation is
incomplete"*. Three commands, once, in **Terminal.app** — not through Claude Code, because `sudo` needs a
real password prompt.

Open Terminal (⌘-Space → "Terminal") and run:

```bash
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

The third installs components Xcode needs on first use and takes a few minutes.

Then check:

```bash
flutter doctor
```

Xcode should now be ✓. **Do these in this order** — selecting Xcode *before* accepting the licence takes
the whole Dart toolchain down (`dart` starts exiting 127), which is recoverable but confusing.

> After this, `scripts/dev_macos_sdk_shim.sh` detects a properly selected Xcode and does nothing, so
> `flutter test` works natively. You can stop using it.

---

## 1. The Simulator — easiest, start here

No cable, no Apple ID, no signing. Best way to see the app quickly.

> **Xcode 27 does not ship `Simulator.app` until you download the iOS platform.**
> `open -a Simulator` fails with *"Unable to find application named 'Simulator'"* — the app genuinely is
> not on disk (verified 16 Sep 2026: no `Simulator.app` anywhere under `/Applications/Xcode.app`), even
> though `xcrun simctl` works and iPhone simulators are listed.
>
> **Fix, once:** open Xcode → **Settings → Components** → find the **iOS** platform → **GET**. It is a
> large download. `flutter doctor` names this too: *"iOS 27.0 Simulator not installed"*.

```bash
cd app
flutter run                       # picks a booted simulator, or prompts
```

If no simulator is running, boot one from the command line — this works even before the GUI app exists:

```bash
xcrun simctl list devices available | grep iPhone    # pick one
xcrun simctl boot "iPhone 17"
flutter devices                                       # confirm Flutter sees it
```

The first run takes several minutes — it runs `pod install` and builds the native side, including the
libsodium encryption library. Later runs are fast.

While it's running: **`r`** hot-reloads, **`R`** restarts, **`q`** quits.

To pick a specific iPhone model, open Simulator → **File → Open Simulator → iOS 18 → iPhone 16**, or:

```bash
flutter devices          # lists what's bootable
flutter run -d "iPhone 16"
```

### Two "phones" without touching hardware

You can boot **two different Simulator models at once** and run the app on each — genuinely useful for
seeing two ledgers side by side:

```bash
xcrun simctl list devices available | grep iPhone     # find two names
xcrun simctl boot "iPhone 17"
xcrun simctl boot "iPhone 17 Pro"
flutter run -d <device-id-1>                           # in one terminal tab
flutter run -d <device-id-2>                           # in another
```

They will **not** sync with each other yet — see § 4.

---

## 2. A real iPhone

### 2a. Sign Xcode into an Apple ID

Xcode → **Settings → Accounts → +** → Apple ID. A **free** Apple ID works: builds run for **7 days**, then
need reinstalling. The paid account ($99/yr, same-day for Individual enrolment per
`docs/ops/lead-times.md §2`) removes the expiry and unlocks TestFlight.

### 2b. Set the signing team

```bash
open app/ios/Runner.xcworkspace
```

Select **Runner** in the left sidebar → **Signing & Capabilities** tab → tick **Automatically manage
signing** → choose your **Team**.

If it complains the bundle identifier is unavailable, change it to something unique — e.g.
`com.rukkafolio.rukkaFolio.<yourname>` — and note that you changed it.

### 2c. Connect the phone

1. Plug the iPhone into the MacBook by cable.
2. On the iPhone: **Trust This Computer?** → **Trust**, then enter the phone's passcode.
3. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**. The phone restarts.
4. Confirm the Mac sees it:

```bash
flutter devices
```

### 2d. Run it

```bash
cd app
flutter run --release -d <device-id>
```

Use `--release` on a real phone — a debug build is noticeably slower and misrepresents how the app feels.

The **first** launch on the phone shows *"Untrusted Developer"*. Fix on the phone:
**Settings → General → VPN & Device Management → [your Apple ID] → Trust**. Then open the app again.

### 2e. Both iPhones

Repeat § 2c–2d with the second phone plugged in. Both can be connected at once; `flutter devices` lists
both and `-d` picks between them.

---

## 3. Wireless, after the first cable run

Once a phone has been paired over cable, Xcode can keep it available over Wi-Fi: Xcode →
**Window → Devices and Simulators** → select the phone → tick **Connect via network**. After that
`flutter devices` finds it with no cable, as long as both are on the same network.

---

## 4. What you will actually see — and what will not work yet

**Works today, fully offline.** Each install is its own independent ledger: onboarding, create a book,
enter money in and out, statements, reports, exports, the app lock. This is the real app, and it is worth
putting in front of a family member to watch the 8-second entry flow on real hardware.

**Does not work yet, and neither phone is at fault:**

| | Why |
|---|---|
| Two devices syncing | There is no deployed server. `RF_API_BASE` defaults to `127.0.0.1`, and no Supabase project exists yet. |
| Signing in with a phone number | No OTP/SMS provider. TRAI DLT registration is 1–2 weeks (`lead-times.md §3`) and is the long pole. |
| Two devices trusting each other | `certifyDevice()` is still an unimplemented stub, so no device certificate is ever issued. Recorded as open in `CHANGELOG.md`. |
| Device activation against a server | Intentionally fails closed until the server half of ADR 2026-09-16 lands. |

So: **treat this as a single-user preview on two separate phones**, not as a sync test. Sync needs the
server work, and the changelog's Open section tracks exactly what is missing.

---

## 5. When something goes wrong

| Symptom | Fix |
|---|---|
| `Xcode installation is incomplete` | § 0 — you have Xcode, it is not selected |
| `Unable to find application named 'Simulator'` | Xcode 27 ships it with the iOS platform component — § 1's note. `xcrun simctl boot` still works meanwhile |
| `iOS 27.0 Simulator not installed` | Same: Xcode → Settings → Components → iOS → GET |
| `dart` exits 127, nothing runs | Xcode selected but licence not accepted. Run `sudo xcodebuild -license accept` |
| `CocoaPods not installed` | `sudo gem install cocoapods` (already present here: 1.17.0) |
| Pod install fails after a Flutter upgrade | `cd app/ios && pod repo update && pod install` |
| `C compiler cannot create executables` during build | The libsodium native build cannot find the macOS SDK — § 0 fixes it permanently; `eval "$(scripts/dev_macos_sdk_shim.sh)"` is the no-sudo workaround |
| Phone not in `flutter devices` | Cable seated, **Trust** accepted, **Developer Mode** on, phone unlocked |
| `Untrusted Developer` on launch | § 2d — trust the profile on the phone |
| Build fails after switching branches | `cd app && flutter clean && flutter pub get` |
