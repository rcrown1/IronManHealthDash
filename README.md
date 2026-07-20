# Stark HUD — Workshop Biometric Telemetry

An Apple TV app that turns your living room into Tony Stark's workshop: a constantly
shifting, arc-reactor-blue display of every health metric your iPhone knows about.

Two apps, one project:

| Target | Platform | Role |
|---|---|---|
| **StarkHUD** | tvOS 17+ | The workshop display. Receives live telemetry from your iPhone and renders it across four auto-cycling scenes. Falls back to a full simulation when no phone is linked, so the screen is never dark. |
| **StarkCompanion** | iOS 17+ | The field uplink. Reads HealthKit and streams a telemetry frame to the Apple TV every 10 seconds over the local network (Multipeer Connectivity — no server, no account). |
| **StarkSensor** | watchOS 10+ | The wrist sensor. Runs a workout session so the Watch samples heart rate continuously (~1/sec) and streams each beat to the iPhone over WatchConnectivity. Embedded in StarkCompanion. |

## The display

Scenes auto-cycle every 22 seconds:

1. **ARC CORE** — a procedurally drawn arc reactor that pulses at your live heart
   rate, flanked by six holographic metric panels that rotate through everything else.
2. **VITAL SIGNS** — a synthesized PQRST cardiac trace locked to your BPM, plus
   HRV, blood oxygen, respiratory rate, resting HR, and VO₂ max tiles.
3. **POWER SYSTEMS** — activity rings (Power Draw / Combat Readiness / Upright
   Cycles) with steps, distance, and flights counters.
4. **FULL DIAGNOSTICS** — all sixteen metrics in a grid with sparklines and a
   scanner sweep.

Persistent chrome: Stark Industries header, uplink status badge, live clock,
corner brackets, drifting particles, blueprint grid, scanning bands, and a
JARVIS-flavored diagnostic ticker that mixes real readouts with workshop chatter.

**Siri Remote:** swipe left/right to change scenes manually; play/pause freezes
or resumes auto-cycling.

## Metrics

Heart rate, resting heart rate, HRV, blood oxygen, respiratory rate, VO₂ max,
steps, active energy, exercise minutes, stand hours, walking+running distance,
flights climbed, sleep, mindful minutes, body mass, walking speed — each with a
real name and a workshop designation (heart rate → ARC PULSE, active energy →
POWER DRAW, sleep → RECHARGE CYCLE, …).

## Running it

Open `StarkHUD.xcodeproj` in Xcode 16 or newer.

### Apple TV (or tvOS Simulator)

1. Select the **StarkHUD** scheme → your Apple TV (pair via Xcode ▸ Devices) or
   any tvOS simulator.
2. Set your development team under Signing & Capabilities (device only).
3. Run. It boots straight into **SIMULATION MODE** with synthetic vitals.

### iPhone

1. Select the **StarkCompanion** scheme → your iPhone. Set your team; the
   HealthKit capability is already configured.
2. Run, then grant the HealthKit read permissions when prompted.
3. Keep both devices on the same Wi-Fi (Bluetooth also works for discovery).
   The phone finds the TV automatically; when the link is up the TV badge flips
   from amber **SIMULATION MODE** to blue **UPLINK ‹your iPhone›** and real data
   takes over within ~10 seconds.

The companion keeps the screen awake while open (Multipeer streaming is a
foreground affair). If the link drops, the TV waits 30 seconds and hands the
display back to the simulation engine.

### Apple Watch (accurate live heart rate)

Without the Watch app, heart rate comes from whatever samples the Watch last
committed to HealthKit — often minutes stale. Stark Sensor fixes that:

1. Xcode installs it automatically alongside StarkCompanion (it's embedded);
   or run the **StarkSensor** scheme directly on your paired Watch.
2. Open it on the wrist, tap **START STREAM**, and grant the HealthKit prompt.
   It runs a workout session (nothing is saved to your workout history), which
   keeps the optical sensor hot and delivers a reading roughly every second.
3. Each beat flows Watch → iPhone → Apple TV. The companion pushes heart-rate
   frames every 2 seconds while the stream is live, so the reactor pulse and
   the EKG trace on the TV track you beat-to-beat. When the watch stream is
   quiet for 20 seconds, the phone falls back to HealthKit samples.

### Notes

- tvOS has no HealthKit — that's why the iPhone is the source of truth.
- Everything runs on your local network; no health data leaves the room.
- HealthKit permission prompts only appear for builds signed with a development
  team (unsigned `xcodebuild` runs will report access denied).
- Simulator-to-simulator linking works on one Mac (handy for demos).

## Layout

```
Shared/            Telemetry models + link constants (compiled into TV + phone apps)
StarkHUD/          tvOS app — store, MPC receiver, simulation engine, scenes
StarkCompanion/    iOS app — HealthKit reader, MPC sender, watch receiver, status UI
StarkSensor/       watchOS app — workout-session HR streamer (WatchConnectivity)
Config/            Info.plists and HealthKit entitlements
```

*Personal fan project — not affiliated with Marvel. The suit is still yours to build.*
