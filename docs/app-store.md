# TestFlight and the App Store

How to get the iPhone app (and its watch app) onto testers' phones, then into the App Store. TestFlight is also the
fix for "Xcode never sees my watch": a TestFlight build installs the watch app through the iPhone's Watch app, without
cables or Wi-Fi debugging.

## What's ready in the repo

| | Status |
|---|---|
| App icon | Placeholder brand mark (`mobile/tool/make_icon.py` draws all sizes). Replace before launch. |
| Version | `0.1.0+1` in `mobile/pubspec.yaml` (build number after the `+`: raise it for every upload) |
| Bundle ID | `com.shrish186.livetraining` (`mobile/ios/Flutter/AppIdentity.xcconfig`); watch app `…livetraining.watchkitapp` |
| Permission texts | Bluetooth (heart-rate broadcast and our leg sensors), Motion, Local network |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` (we only use standard HTTPS), so no question on every upload |
| Background | `bluetooth-central`: heart rate and the leg sensor keep streaming with the screen locked (**untested on a device**) |
| Privacy policy | Draft in `docs/privacy-policy.md`. Must be at a public URL before external testing |

## 1. Apple Developer Program ($99/year)

1. <https://developer.apple.com/programs/enroll/>. Enrol as an **individual** now (fastest, needs only an Apple ID
   with two-factor authentication). Switch to an organisation once the company exists. That needs a D-U-N-S number
   and takes 1–2 weeks.
2. When it's active, open Xcode › Settings › Accounts, add the Apple ID, and select the new team.
3. In `ios/Runner.xcodeproj` (open `ios/Runner.xcworkspace`) set **Team** on the Runner, the watch app and the watch
   extension targets (Signing & Capabilities). Keep "Automatically manage signing" on.

## 2. Create the app in App Store Connect (once)

<https://appstoreconnect.apple.com> › Apps › + › New App:

- Platform iOS, name **Live Training** (if it is taken, try "Live Training Intelligence"), primary language English (U.S.)
- Bundle ID: pick `com.shrish186.livetraining` (it appears once Xcode has signed a build, or register it under
  Certificates, Identifiers & Profiles)
- SKU: `livetraining-ios`

## 3. Upload a build

```bash
cd mobile
flutter build ipa --release        # builds and signs ios/Runner + the watch app
open build/ios/archive/Runner.xcarchive
```

In the Organizer window that opens: **Distribute App › App Store Connect › Upload**. Or drag
`build/ios/ipa/*.ipa` into Apple's **Transporter** app. Processing takes 10–30 minutes, then an email arrives.

Every new upload needs a higher build number: `version: 0.1.0+2`, `+3`, …

## 4. TestFlight

- **Internal testers** (up to 100 people added to your App Store Connect team, e.g. the cofounders): no review, the
  build is available as soon as it has processed. Install the **TestFlight** app, accept the invite, tap Install.
  The watch app then appears in the iPhone's **Watch** app › Available Apps › Install.
- **External testers** (players, academy coaches, the December squad in India, up to 10,000 people): needs a short
  Beta App Review (usually under a day) for the first build of each version. Requires a privacy policy URL, a
  description, a feedback email and the review notes below. Share a public link and anyone with it can join.
  TestFlight works in India.
- Builds expire after 90 days. Upload a fresh one before the India trip, so the whole month is covered.

## 5. Review notes (paste into "Beta App Review Information" / "App Review Information")

> Live Training records training sessions: phone or leg-sensor motion, and heart rate from a chest strap or WHOOP
> band using the standard Bluetooth Heart Rate service. It gives live calls during training ("warmed up", "effort",
> "fatigue building") and shows training load and trends.
>
> To try it without any hardware: tap Start session on the Live tab and move the phone for a minute, then Stop. The
> session appears under Sessions with a report. Heart-rate and sensor features need a Bluetooth heart-rate device
> or our prototype leg sensor. A backend URL and WHOOP account are optional (Settings) and only used for uploads
> and recovery data.
>
> The app gives training-load information only. It makes no medical or diagnostic claims.

Before sending a build to review, check that starting and stopping a session with nothing connected and nothing
configured works and shows a report. The reviewer will do exactly that.

## 6. App Store listing (draft)

- **Subtitle (30 chars):** Live load and fatigue calls
- **Category:** Health & Fitness (secondary: Sports)
- **Keywords (100 chars):** training,load,fatigue,cricket,bowling,workload,sprint,whoop,heart rate,readiness,coach,sensor
- **Description:**

  > Train with live calls, not guesses. Live Training combines motion from your phone, Apple Watch or our leg sensor
  > with heart rate and WHOOP recovery, and tells you during the session when you're warmed up, how hard each effort
  > was, and when fatigue is building.
  >
  > • Live calls: readiness, warmed up, efforts, fatigue building
  > • Session reports: timeline, efforts, heart rate, impact load and data quality
  > • Trends: this week against your usual week, and sessions, training time and impact load per week
  > • Cricket: counts deliveries and spots softer landings late in a spell
  > • Squad mode: one phone records a whole group, each player with their own sensor
  >
  > Live Training reports training load and fatigue to help you plan training. It is not a medical device and does
  > not diagnose or predict injuries.

- **Screenshots:** 6.9" iPhone (1320 × 2868) or 6.5" (1284 × 2778), at least 3. Take them from a real session on
  a phone. The renders in `docs/screenshots/` are 390 pt wide previews, not upload-ready.

## 7. App Privacy questionnaire (App Store Connect › App Privacy)

What the app collects **if the athlete sets up a backend URL** (otherwise everything stays on the phone):

| Data type | Collected | Linked to the user | Tracking | Purpose |
|---|---|---|---|---|
| Health & Fitness › Fitness (motion, training load) | Yes | Yes (athlete ID) | No | App functionality |
| Health & Fitness › Health (heart rate, WHOOP recovery) | Yes | Yes | No | App functionality |
| Identifiers › User ID (athlete ID) | Yes | Yes | No | App functionality |
| Location, contacts, browsing, ads data | No | | | |

No third-party analytics or ad SDKs are in the app. Check that this is still true before submitting (`pubspec.yaml`).

## 8. Before the public App Store (not needed for TestFlight)

- The backend must be on HTTPS with a real domain. The app's plain-HTTP exceptions are for local networks only.
- Replace the placeholder icon, write real screenshots.
- Organisation account (company name as the seller), D-U-N-S.
- If WHOOP data is shown in the app: follow WHOOP's developer terms and brand guidelines (official API only, see
  the hard rules in `CLAUDE.md`).
- The developer account holder is the seller of record. Decide whose account (and which company) that is before
  the first paid launch.
