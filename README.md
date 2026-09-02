# MonIQ — Native App Package

This is a real Capacitor project that wraps the MonIQ web app in native iOS and Android shells,
so it can be submitted to the App Store and Google Play. It is not a finished, submittable
app yet — a few things still need real hardware/accounts that can't be provided from a sandbox.

## What's already done
- Full Xcode project (`ios/`) and Android Studio/Gradle project (`android/`)
- App name set to "MonIQ", bundle ID `com.avencia.moniq` (change this if you want a different one —
  it must be unique across the App Store / Play Store and can't be changed after your first submission)
- Voice entry rewired to use a native speech-recognition plugin
  (`@capacitor-community/speech-recognition`) instead of the browser API, since the browser's
  Web Speech API silently fails inside a packaged app's WebView — this is a confirmed WebKit bug,
  not something fixable in JavaScript alone
- Microphone/speech permission descriptions added to `ios/App/App/Info.plist`
- `RECORD_AUDIO` and `INTERNET` permissions added to `android/app/src/main/AndroidManifest.xml`
- Every screen except Intro/Demo/Settings/Trial/Pricing/Checkout/Terms/Privacy now requires an active
  trial or subscription to use — real enforcement, not just the pricing copy
- Real subscription verification wired up via **RevenueCat** (`@revenuecat/purchases-capacitor`) for
  the native iOS/Android app — it wraps Apple's / Google's own purchase system and validates the
  result server-side, so it can't be spoofed by editing the app's local data the way the old
  local-only "preview" buttons could be. See "Connect RevenueCat" below to activate it.

## Testing the app right now (no Apple/Google account needed)

### Web / PWA — auto-deployed to GitHub Pages
`.github/workflows/deploy-pages.yml` publishes `www/` to GitHub Pages on every push to `main` (and can
be run manually from the Actions tab via "Run workflow"). Once the first run finishes, the app is live at:

**https://marcustoh108.github.io/moniq-native/**

Open that on your phone or desktop browser — everything works except two native-only pieces: the
native speech-recognition plugin (falls back to the browser's own Web Speech API, which works fine in
a real browser — it only breaks inside a packaged app's WebView) and RevenueCat purchases (falls back
to the local "Preview" trial/purchase buttons). Nothing to configure — the first push after this was
added triggers the first deploy; check progress under the repo's **Actions** tab.

### Android — real native app via Codemagic, auto-built
`codemagic.yaml`'s `android-debug` workflow now triggers automatically on every push to `main`, so
once you've connected this repo in Codemagic (a one-time sign-up + "Add application" step only you can
authorize — codemagic.io → sign up with GitHub → select this repo), it keeps a fresh sideloadable APK
ready with no further clicks. Grab it from the workflow's **Artifacts** after a run finishes, or trigger
one immediately yourself (Codemagic dashboard → this app → `android-debug` → Start new build) instead
of waiting for the next push. Install steps: transfer the `.apk` to your Android phone, tap it, and
allow "Install unknown apps" for whichever app you opened it from when prompted.

## What you still need to do

### Both platforms
- Generate real app icons and a splash screen (currently using Capacitor's default placeholder icon).
  Tools like [Icon Kitchen](https://icon.kitchen) or [App Icon Generator](https://appicon.co) can
  generate the full icon set from a single image, free, from a phone browser.
- **Connect RevenueCat**, so the app enforces subscriptions for real instead of falling back to the
  local "preview" trial/purchase buttons:
  1. Sign up free at [revenuecat.com](https://www.revenuecat.com) (their free tier covers this app's
     scale — no cost until you're doing meaningful revenue).
  2. Add your iOS and/or Android app in the RevenueCat dashboard — this needs the App Store Connect /
     Play Console listing to already exist (see below), so this step comes after those accounts.
  3. Create an entitlement identifier exactly named `premium`, attach it to a monthly and an annual
     product priced to match S$9.90/mo and S$100.90/yr (or your actual prices), and put them in the
     "current" offering.
  4. In the app itself (or by editing `STATE.settings.revenueCat` directly for a fresh install),
     go to Settings → Monetization and paste in the iOS and Android **public** SDK keys from
     RevenueCat's dashboard (Project Settings → API keys — use the public app keys, never the secret
     key). Until these are set, the app keeps using the local-only trial/purchase preview exactly as
     before, so nothing breaks by leaving this for last.
  5. Test with a real device using [sandbox/test purchases](https://www.revenuecat.com/docs/test-and-launch/sandbox)
     before submitting — a purchase can't be fully verified in a simulator.

### iOS — needs a Mac, or a cloud Mac
- An Apple Developer Program account ($99/year, signs up at developer.apple.com) — this can only be
  done by you, it verifies your identity/business
- Xcode installed on a Mac to open `ios/App/App.xcworkspace`, set your Team/signing, and archive/upload
  to App Store Connect — OR use a cloud build service (see below) if you don't own a Mac
- `npm install` and `npx pod-install ios` (CocoaPods) need to run once before the iOS project builds

### Android — can be done without owning special hardware
- A Google Play Console account ($25 one-time, at play.google.com/console)
- Android Studio (free, runs on Windows/Mac/Linux) to open the `android/` folder, generate a signing
  keystore, and build a signed `.aab` (Android App Bundle) for upload — OR use a cloud build service

### Recommended for a phone-only workflow: Codemagic
[codemagic.io](https://codemagic.io) has a free tier and can build + sign both iOS and Android from
this project pushed to a GitHub repo, entirely from its web dashboard (usable from a phone browser).
It still needs your Apple Developer and Google Play accounts connected, since only you can authorize
those, but it removes the need to own a Mac or run Android Studio locally.

A `codemagic.yaml` is already checked into this repo with three workflows:
- **`android-debug`** — builds an unsigned, sideloadable APK, automatically on every push to `main`.
  No accounts needed; see "Testing the app right now" above.
- **`android-release`** — builds a signed `.aab` for Google Play. Needs a keystore uploaded in
  Codemagic's dashboard (Team settings → Code signing identities → Android) named
  `moniq_android_keystore` — Codemagic can generate one for you if you don't have one.
- **`ios-release`** — builds a signed `.ipa`. Needs an Apple Developer Program account and an App
  Store Connect API key connected under Team settings → Integrations → Apple Developer Portal, named
  `codemagic`.

Full step-by-step instructions (what to name each keystore/integration, and how to turn on automatic
Play Store / TestFlight upload once you're ready) are commented directly above each workflow in
`codemagic.yaml`. To use it: sign up at codemagic.io, connect this GitHub repo, and Codemagic will
detect `codemagic.yaml` automatically — no dashboard configuration needed beyond the signing setup
above. Start with `android-debug`, since it needs nothing but the repo itself.

## Local commands (if using a computer)
```
npm install
npx cap sync
npx cap open ios       # opens Xcode
npx cap open android   # opens Android Studio
```

## Updating the app later
If the web app (`index.html`) changes, copy the new version into `www/index.html`, then run
`npx cap sync` to push it into both native projects before rebuilding.
