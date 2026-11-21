# Meeting-end signal probe

The probe samples the selected application's Core Audio input and output activity every half second. It includes helpers whose executable is inside the app bundle and prints only state changes. It reads no audio samples. Output activity means an open output stream and can stay active through silence. The probe observes the entire browser, including other tabs.

Build on macOS 15 or later and run from a terminal in the desktop session:

```sh
MACOSX_DEPLOYMENT_TARGET=15.0 swiftc verification/meeting-end/probe.swift -o /tmp/minutes-meeting-end-probe
/tmp/minutes-meeting-end-probe /Applications/Helium.app 300
```

In a private call, note the local time at join, mute, unmute, leave, and rejoin. Hold mute and the post-leave state for at least 35 seconds to exercise a proposed 30-second reminder. Leave the browser tab open. A missing process or failed read is a distinct observation from an inactive input stream.

## Controls observed on 2026-11-21

- A temporary native app started and stopped a silent output stream twice. Both transitions appeared in the trace, and input stayed inactive.
- A local page in an isolated Chrome profile acquired a real microphone track. Disabling the track for seven seconds and enabling it again left the input flag active. Stopping the track cleared the flag within one sampling interval of the logged action (to one-second timestamp precision). Reacquiring and stopping the track produced a second active/inactive cycle. The page did not record or send audio. This exercised browser media APIs independently of Meet.

## Google Meet in Helium

The operator exercised a private call with a mute/unmute interval, then left the call with the tab open and confirmed completion. The observation began with both streams active. Individual join and mute clicks were not timestamped. Core Audio reported only these changes:

```text
14:41:19  input=true output=true processes=3
14:42:56  input=false output=true processes=3
14:42:57  input=false output=false processes=3
```

Both streams stayed inactive for more than 35 seconds after leave. A 30-second grace period beginning when both became inactive would have expired around 14:43:27. No reminder was delivered. This single run supports trying the transition for Helium with Meet. It does not establish behavior during device changes, concurrent media tabs, Meet reconnects, or calls in other apps.

## FaceTime and release timing

With automatic stop enabled on the five-second prototype, FaceTime and its conferencing helper reported both streams inactive at 15:24:15. Minutes finalized the recording at 15:24:20 and saved two transcript utterances at 15:24:22.

Version 0.1.17 keeps the five-second reminder and starts automatic stop on the first inactive sample after observing input. Tests cover both timings, including resumed streams and missing samples. The immediate-stop change has not been timed in a live call.
