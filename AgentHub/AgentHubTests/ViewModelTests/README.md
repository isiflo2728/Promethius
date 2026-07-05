# ViewModelTests (app-target)

App-level view-model tests that need an Xcode test target (host app, App Group,
CloudKit entitlements) live here.

Pure `AgentKit` logic tests — including the CloudKit-lag / dedup safeguards in
`IntentQueue` — live in the package instead and run with `swift test`:

    Packages/AgentKit/Tests/AgentKitTests/
