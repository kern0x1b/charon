# The navigation session: a measurement, decided and measured, and not carried yet

**Fourteen rows, and this page says the honest thing about all of them: they are `owed`, not landed.**
Their reason used to be "the head unit", which is wrong — a navigation session is not a connection to
a car, and the port can carry it. What is missing is the code, and this page records the decision, the
measurements behind it, and what carrying it needs, so the next round starts from facts rather than
from the old blanket sentence.

## What decides the world, and it is not the wall

The 26.2 header is explicit about who makes one:

```
CPNavigationSession.h:26   @c CPNavigationSession represents the active navigation session. A @c CPNavigationSession will be created for you
CPNavigationSession.h:27   when calling startNavigationSessionForTrip: on @c CYMapTemplate
CPNavigationSession.h:33   - (instancetype)init NS_UNAVAILABLE;
CPNavigationSession.h:34   + (instancetype)new NS_UNAVAILABLE;
```

and the way in is a method the port already registers as `implemented`:

```
CPMapTemplate.h:112        - (CPNavigationSession *)startNavigationSessionForTrip:(CPTrip *)trip;
                           @return CPNavigationSession maintain a reference to the navigation session to perform guidance updates
```

So the session is not the gate: the **scene** is the gate (a `UIScene` the system makes for a
connection, `facts/CarPlay/Scenes.md`), and the session is what the program is handed *inside* one, by
a map template the port already carries. That makes these fourteen rows a measurement — what the SDK
answers with no head unit — and the two `+new`/`-init` rows a third thing, the header's own
`NS_UNAVAILABLE`, which the previous commit settled (`facts/CarPlay/Session.md`).

**The 16.0 cache names the creator, and it is not the program:** the class's only initialiser is the
private `-initWithTrip:mapTemplate:`, and the private protocol `CPNavigationSessionProviding` declares
`-hostStartNavigationSessionForTrip:reply:`. The app is given the session; it does not build one.

## The two releases, measured per class, and why first-rung alone was not enough

`first-rung.py` answers for NAMES, so three of the six 17.4 members read 16.0 — and every one of them
is a **name collision**, not the member: `CPRouteGuidance` carries `currentLaneGuidance`,
`currentRoadNameVariants` and `maneuverState` at 16.0. `tools/corpus/objc-inventory.lua` answers per
class, and the two disagree exactly where they should:

| member | `first-rung.py` (a name) | 16.0, per class | 18.0, per class |
| --- | --- | --- | --- |
| `currentLaneGuidance` | 16.0 | **absent** | present |
| `currentRoadNameVariants` | 16.0 | **absent** | present |
| `maneuverState` | 16.0 | **absent** | present |
| `addManeuvers:` | 18.0 | absent | present |
| `addLaneGuidances:` | 18.0 | absent | present |
| `resumeTripWithUpdatedRouteInformation:` | 18.0 | absent | present |

Both numbers are measurements and the per-class one is the one a row may rest on: a selector name
that exists somewhere in a cache is not a member of a class. The 16.0 per-class list for
`CPNavigationSession` is `trip`, `upcomingManeuvers`, `cancelTrip`, `finishTrip`,
`pauseTripForReason:description:`, `pauseTripForReason:description:turnCardColor:` and
`updateTravelEstimates:forManeuver:`, plus the private `initWithTrip:mapTemplate:`, `manager` and
`mapTemplate`. The 18.0 list adds the six, with their private accessors `setCurrentLaneGuidance:`,
`setManeuverState:`, `setCurrentRoadNameVariants:`, `laneGuidances`, `maneuvers` and `pauseReason` —
which is how a band's reader can see that they are stored values and not messages to a car.

Command and verdict, for a reader who wants to repeat it:

```
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/16.0/dyld_shared_cache_arm64e
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/18.0/dyld_shared_cache_arm64e
awk -F'\t' '$2=="CPNavigationSession"' <the two tsvs>
```

(the arm64e caches are split: a 384 KB header and the bodies in `.01`, `.03`, …, and the reader takes
the base path. The 16.0 inventory this repository already had was reused rather than rebuilt — it is
`charon/.agent-work/runs/coreml-1/objc16.tsv`, 81 MB, and the 18.0 one is under this band's own
`.agent-work/runs/carplay-1/objc18.tsv`, 104 MB.)

## What carrying the fourteen needs, and the three classes they reach for

Six of the fourteen are 17.4 and two of their types are classes the port does not carry:
`currentLaneGuidance` is a `CPLaneGuidance *` and `resumeTripWithUpdatedRouteInformation:` takes a
`CPRouteInformation *`. So a 17.4 object carries a category on `CPNavigationSession` with the six
members **and** the value classes they need, and those classes are small and measurable:

| class | 18.0 members that matter | what it is |
| --- | --- | --- |
| `CPLane` | `angles`, `primaryAngle`, `secondaryAngles`, `highlightedAngle`, `index`, `status`, `initWithAngles:highlightedAngle:isPreferred:`, NSCopying, NSSecureCoding | one lane and which way it goes |
| `CPLaneGuidance` | `lanes`, `instructionVariants`, `index`, `componentID`, NSCopying, NSSecureCoding | guidance for one lane or a few |
| `CPRouteInformation` | `maneuvers`, `laneGuidances`, `currentManeuvers`, `currentLaneGuidance`, `tripTravelEstimates`, `maneuverTravelEstimates`, `initWithManeuvers:laneGuidances:currentManeuvers:currentLaneGuidance:tripTravelEstimates:maneuverTravelEstimates:` | the route ahead, as values |

All three are value holders with no reference to a car, which is why they are in the measurement world
and not the wall's. Two of the corpus's CarPlay classes are *not* in the queue's 48 for this reason —
they are additions this round would make, and the registry needs an entry for each class the package
builds.

The 15.4 member is one method, `pauseTripForReason:description:turnCardColor:`, and belongs in a 15.4
object as a category on the 12.0 class, the way `CarPlayButtons16.m` carries the 16.0 buttons.

## The one row in this family that is a defect in main, and what it needs

`-[CPMapTemplate startNavigationSessionForTrip:]` is registered `implemented` in
`registry/CarPlay/ios12.json` **and no source file in the tree implements it**: `CPNavigationSession`
appears nowhere under `packages/`, and neither does that selector. The gate cannot see it, because
`backports.lua`'s unbuilt check counts a member row as built when its owner class is exported
(`built = built or (owner and found.classes[owner])`), and `CPMapTemplate` is exported. So the map
template a program pushes answers nothing when it is asked to begin guidance, and the row claims
otherwise.

That is the load-bearing reason the session cannot be `absent` while its creator is advertised: the
method that makes the session is the port's own, and it is the map template — which the port already
carries and draws — that is the thing this port has instead of a head unit. Carrying the session
means giving that method a body: a session holding the trip, the maneuvers and the estimates, and the
estimates and maneuvers reaching the map template's own guidance, which is what
`facts/CarPlay/CarPlay.md` already draws.

## The rows, and their state

| rows | introduced | state | why |
| --- | --- | --- | --- |
| `CPNavigationSession`, `trip`, `upcomingManeuvers`, `cancelTrip`, `finishTrip`, `pauseTripForReason:description:`, `updateTravelEstimates:forManeuver:` | 12.0 | `owed` | a measurement the port can take: the map template is the creator and the port has one |
| `pauseTripForReason:description:turnCardColor:` | 15.4 | `owed` | the same, one method later |
| `currentLaneGuidance`, `currentRoadNameVariants`, `maneuverState`, `addManeuvers:`, `addLaneGuidances:`, `resumeTripWithUpdatedRouteInformation:` | 17.4 | `owed` | the same, and they need `CPLaneGuidance` and `CPRouteInformation` carried with them |

`owed` is the port's own word for "the release carries the name, the port could carry it, and nobody
has written it yet" (`modules/apple/backports.lua`, the five statuses). It is not a landing state and
this page does not claim these rows are done.
