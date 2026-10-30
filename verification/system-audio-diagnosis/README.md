# System audio lost during transcription

Investigated 2026-10-30 using the latest local recording (866.57 seconds).
The saved system track is 48 kHz Float32, two channels, with a DiscreteInOrder
channel layout. The saved transcript contains 28 microphone-only utterances.

`probe.swift` reads the original file through AVAudioFile and converts it through
AVAudioConverter to 16 kHz mono, matching the conversion used by FluidAudio's
AudioSourceFactory disk-backed ASR path (used for recordings over 30 seconds).
It reports energy only and never writes or prints meeting content.

```
swiftc -O -module-cache-path /tmp/minutes-diagnostic-module-cache probe.swift -o /tmp/minutes-audio-probe
/tmp/minutes-audio-probe /path/to/remote.caf
```

Original: raw RMS 0.08948825770285587; 13,865,131 converted samples, RMS 0 and peak 0.
A temporary WAV copy with standard stereo interpretation: identical raw RMS;
13,865,131 converted samples, RMS 0.08931033915588057, peak 1.0257645845413208.
Decoded Float32 PCM SHA-256 matched between original and copy:
`cef64d520bd25ddd0ba30dab5159377f64dd5a25c33e10f2804583d41d491a5f`.
Thus the copy changes layout/container interpretation without changing audio samples.

Cause: AppAudioTap constructs a discrete channel layout. When the capture uses
the stereo mixdown fallback, the buffer retains that layout in the CAF file.
AVAudioConverter's default mono mix drops those discrete channels. The live meter
reads the original samples before this conversion, explaining visible activity.
TranscriptionService accepts an empty remote ASR result and continues with the mic.

Follow-up: normalize known stereo capture layouts, handle existing discrete-layout
recordings explicitly on transcription input, and test both long-file streaming
and short-file conversion. Do not blindly reinterpret arbitrary multichannel device
streams as stereo. Consider surfacing a non-silent input becoming silent after conversion.

Original audio, meeting metadata, and exported transcript were not modified.
No full ASR recovery or live capture test was performed in this investigation.

## Fix and recovery completed

- New two-channel tap buffers are normalized through the existing stereo channel
  extraction helper before being written. Explicit device output-pair routing is retained.
- `TranscriptionAudio` prepares a temporary standard-stereo CAF for legacy two-discrete-
  channel system tracks, shared by recognition and diarization, then removes the copy.
  Other layouts pass through unchanged; retained recordings are never rewritten.
- Synthetic regression tests exercise the capture callback, both FluidAudio conversion
  paths, exact sample preservation, cleanup, and mono/four-channel pass-through.
- Real local reprocessing produced 99 utterances: 28 microphone and 71 remote, with
  two remote speakers. The saved meeting JSON and its owned Markdown export were
  replaced only after verifying the original metadata had not changed and creating
  a backup under Minutes/RecoveryBackups. Original system PCM SHA-256 still matches above.
- Full suite passed with explicit `--no-parallel` (59 app tests, 35 core tests;
  six opt-in tests skipped). Real recovery separately passed using the opt-in
  `regenerateRetainedRecording` test, with outputs staged under /tmp before installation.
- Live browser capture has not been exercised; new-capture coverage uses the actual
  callback and file/conversion pipeline with synthetic PCM.
