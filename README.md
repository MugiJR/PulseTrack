# PulseTrack — Apple Watch fitness tracker for iPhone

A native SwiftUI + HealthKit app with three screens:

| Tab | What it shows |
|---|---|
| **Sleep** | 0–100 sleep score, stage timeline (Awake / REM / Core / Deep), time and % in each stage, efficiency, bedtime/wake, wake-ups, sleeping heart rate, HRV, respiratory rate, blood oxygen, score breakdown, and a 7-night trend. Swipe between nights with the arrows. |
| **Workout** | Your previous workout: duration, active calories, distance, average/max heart rate, training load, time in each HR zone, and how long it takes to recover. Tap any workout in the last 30 days to look at it. |
| **Recovery** | Countdown to full recovery (and when you'll be ready), a readiness score, what's affecting it (training load, sleep, HRV and resting HR compared with your 30-day averages), and guidance for today. |

All data is read-only, comes from Apple Health and stays on the device. A **demo data** mode lets you try the app in the Simulator.

## Install on iPhone with a Windows PC (no Mac needed)

**What you need:** a free GitHub account, a Windows PC, an iPhone cable, and your Apple ID.

### 1. Build the app on GitHub's free cloud Mac
1. Sign in at github.com → **New repository** → name it `PulseTrack` → **Public** (public repos get free Mac build time) → *Create*.
   The repo only holds code. Your health data never goes anywhere near it.
2. On the new repo page, click **uploading an existing file**. Unzip `PulseTrack.zip` on your PC, open the `PulseTrack` folder, select **everything inside it** (including the `.github` folder — turn on *View → Hidden items* in File Explorer if you can't see it) and drag it onto the page. Click **Commit changes**.
   - Check that the repo shows `project.yml`, `PulseTrack/` and `.github/` at the top level.
   - If `.github` didn't upload: *Add file → Create new file*, name it `.github/workflows/build-ipa.yml`, paste in that file's contents, and commit.
3. Open the **Actions** tab. The build "Build PulseTrack IPA" starts by itself (or click it → **Run workflow**). It takes about 5–10 minutes.
4. When it shows a green tick, open the run, scroll to **Artifacts**, and download **PulseTrack-ipa**. Unzip it to get `PulseTrack.ipa`.
   - Red cross? Open the failed step and copy the error lines. Claude can fix them.

### 2. Install it with Sideloadly
1. On Windows, install **iTunes** and **iCloud** from apple.com (the website versions, not the Microsoft Store ones). Sideloadly needs them to talk to your iPhone.
2. Download and install **Sideloadly** from sideloadly.io.
3. Plug in your iPhone, unlock it, and tap **Trust** on the phone.
4. Open Sideloadly, drag `PulseTrack.ipa` into it, type your Apple ID email, and click **Start**. Enter your Apple ID password when asked (Sideloadly only sends it to Apple).
5. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
6. Turn on **Developer Mode** if iOS asks: **Settings → Privacy & Security → Developer Mode** → on, then restart.
7. Open PulseTrack → **Connect Apple Health** → allow all categories.

### Limits of a free Apple ID
- The app stops opening after **7 days**. Plug in and press Start in Sideloadly again (or turn on its auto-refresh). Your data lives in Apple Health, so nothing is lost.
- You can have at most 3 sideloaded apps at a time.
- A $99/yr Apple Developer account removes these limits and allows TestFlight installs.

---

## Building on a Mac instead

### Requirements
- A Mac with **Xcode 15 or later**
- An iPhone on **iOS 17+** paired with an Apple Watch (for real data)
- A free or paid Apple ID signed into Xcode (needed to install on your phone)

### Run it
```bash
brew install xcodegen      # one-time
cd PulseTrack
xcodegen                   # creates PulseTrack.xcodeproj from project.yml
open PulseTrack.xcodeproj
```
1. In Xcode, select the **PulseTrack** target → *Signing & Capabilities* → choose your **Team**. If the bundle ID is taken, change `com.yourname.pulsetrack`. (HealthKit is already set up in the entitlements.)
2. Plug in your iPhone, pick it as the run destination, and press **⌘R**.
3. On the phone, tap **Connect Apple Health** and turn on all categories.

> The Simulator has no Apple Watch data, so tap **Explore with demo data** there.

## How the scores work
**Sleep score (100 pts)**
- Duration — 40 pts (full at 7.5h+, zero at 4h; small penalty past 9.5h)
- Deep sleep — 15 pts (full at ≥15% of sleep)
- REM sleep — 15 pts (full at ≥20%)
- Efficiency — 15 pts (time asleep ÷ time in bed; full at ≥92%)
- Restfulness — 15 pts (full at ≤15 min awake, zero at 75 min)

**Recovery time**
- Training load = Banister TRIMP (minutes × heart-rate reserve weighting). Max HR = 208 − 0.7 × age (from Health), or 190 if no age is set.
- Base recovery = 4h + 0.33h per load point, max 72h.
- Multiplied by sleep (×0.9–1.3), HRV against your 30-day average (×0.9–1.25) and resting HR against your 30-day average (×0.95–1.15).
- Leftover fatigue from other workouts in the last 5 days adds 30% of their remaining time.
- Readiness = weighted mix of sleep (35%), HRV (35%), resting HR (15%) and remaining fatigue (15%).

To change the thresholds, edit `PulseTrack/Health/Analysis.swift`.

## Project layout
```
PulseTrack/
  App/PulseTrackApp.swift      App entry + tab bar
  Models/Models.swift          Sleep, workout and recovery models
  Health/HealthService.swift   HealthKit queries (async)
  Health/HealthManager.swift   Observable state, loads & combines data
  Health/Analysis.swift        Sleep parsing, sleep score, HR zones, recovery model
  Health/DemoData.swift        Realistic sample data
  Views/                       Onboarding, Sleep, Workout, Recovery, shared components
```

*Estimates are for training guidance only and are not medical advice.*
