# charon@activitykit

The ActivityKit framework of iOS 16.1, as one Swift module a port writes `import ActivityKit` for,
built against the `charon@swift-runtime` a port carries.

    target("my-port")
        add_requires("charon@swift-runtime")
        add_requires("charon@appintents")
        add_requires("charon@activitykit")
        add_packages("swift-runtime", "appintents", "activitykit")

## What the module is

`Activity`, its `ActivityAttributes`, `ActivityContent`, `ActivityState`, `ActivityStyle`, `PushType`,
`AlertConfiguration`, `ActivityUIDismissalPolicy`, `ActivityAuthorizationError` and
`ActivityAuthorizationInfo`, with the four update streams (`activityUpdates`, `activityStateUpdates`,
`contentStateUpdates`, `contentUpdates`) and the two push-token streams the framework names.

## The seam: there is no activity daemon

A Live Activity is a registration the system's own daemon (`chronod`) owns; it mints the push token and
draws the activity on the Lock Screen and in the Dynamic Island. iOS 6.1.3 runs no such daemon, has no
Live Activity surface and grants no entitlement for one, so the module gives the framework's own answer
for a device that does not support Live Activities, and gives it by asking:
`CharonActivitySupport.shared.areActivitiesEnabled` is `false` with no reader installed, and a caller on a
release that does run the daemon installs the system's own answer with
`install(areActivitiesEnabled:frequentPushesEnabled:)`. From that one answer everything else follows the
framework's own way: `request` throws `ActivityAuthorizationError.unsupported`, `activities` is empty,
the streams carry nothing, and `pushToken` and `pushToStartToken` are `nil` because only the daemon
mints one.

What *is* the app's own and is real: the attributes, the content state, the stale date, the relevance
score (clipped to 0...1, as the framework's own initialiser does), the alert's two texts and its
sound, the dismissal policy, and the errors' domain, codes and sentences. `facts/ActivityKit/Availability.md`.

## The Foundation type it is written in

`AlertConfiguration`'s `title` and `body` are `Foundation.LocalizedStringResource`. Where the runtime's
Foundation has the type, the module uses the platform's; where it does not - it is the swift-5.4.3
overlay, which predates it - the `charon@appintents` package carries it and this one takes it from
there. The recipe measures which with a probe and prints it at every install.

## Licence

MIT, the repository's.
