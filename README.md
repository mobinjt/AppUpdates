# AppUpdates

Required and suggested updates for the owner's apps. The app's backend holds a policy per
platform: builds below a minimum must update before the app can be used, builds below a
recommended one are asked once. The app checks it when it opens and comes to the foreground,
keeps the last policy so a required update still shows offline, and remembers a dismissed
suggestion until a newer build is recommended.

- **AppUpdates:** `AppUpdateChecker`, for the app. How to fetch the policy is passed in, so any
  backend works.
- **AppUpdatesCore:** `AppUpdatePolicy` alone (its status and the build header), Foundation only,
  so a server or an admin tool on Linux or the Mac shares the same model.

## Adding it to an app

1. Add the package by its URL (Xcode > Add Package Dependencies) and the **AppUpdates** product to
   the app target.
2. Make the checker once, with how to read the policy from your backend:

   ```swift
   import AppUpdates

   let updates = AppUpdateChecker(defaults: .standard) { platform in
       let url = server.appending(path: "app-update/\(platform.rawValue)")
       let (data, _) = try await URLSession.shared.data(from: url)
       return try JSONDecoder().decode(AppUpdatePolicy.self, from: data)
   }
   ```

3. Check when the app opens and comes to the foreground, and show what it says:

   ```swift
   .task(id: scenePhase) { if scenePhase == .active { await updates.check() } }
   .overlay { if updates.isRequired { UpdateRequiredView(url: updates.updateURL) } }
   .sheet(isPresented: .constant(updates.offersSuggestion)) { … updates.dismissSuggestion() }
   ```

   `check()` asks at most once a minute; pass `minimumInterval: .zero` to ask now.

4. Optionally, send `AppUpdatePolicy.currentBuildHeaders` with every request so the backend can
   turn old builds away with 426 Upgrade Required and the policy as the body. Hand that body to
   the checker:

   ```swift
   if let policy = AppUpdatePolicy.upgradeRequired(in: data, response: response) {
       updates.apply(policy)
   }
   ```

## The backend's side

Serve one `AppUpdatePolicy` per platform as JSON:

```json
{ "platform": "ios", "minimumBuild": 40, "recommendedBuild": 42,
  "updateURL": "https://testflight.apple.com/join/…", "message": "A new game is out." }
```

Every field but `platform` is optional. `X-App-Build: ios 42` names a request's platform and build
(`AppUpdatePolicy.parseHeader`). `problem` says what's wrong with a policy someone typed, for the
screen where it's edited.

## How it's built

- iOS 18 and macOS 15, Swift 6; `AppUpdatesCore` also builds on Linux. No dependencies.
- The checker keeps its policy and the dismissed build in the `UserDefaults` it's given
  (`appUpdate.policy`, `appUpdate.dismissedBuild`). Builds are `CFBundleVersion` numbers.
- Its log messages use the app's bundle ID as the subsystem, category `updates`.

`swift test` covers required and suggested updates, the once-per-build suggestion, offline use,
other platforms' policies, spacing out checks, 426 answers, the header and policy validation.

## License

MIT. See [LICENSE](LICENSE).
