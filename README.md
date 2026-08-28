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

## What you still need to do

### Both platforms
- Generate real app icons and a splash screen (currently using Capacitor's default placeholder icon).
  Tools like [Icon Kitchen](https://icon.kitchen) or [App Icon Generator](https://appicon.co) can
  generate the full icon set from a single image, free, from a phone browser.

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
