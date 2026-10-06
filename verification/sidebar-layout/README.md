# Inspector layout investigation

2026-10-06: Opening the speakers inspector caused a transient expansion of the
outer split view from 1080 points to 1559 points, then back to 1080. The left
navigation toolbar item was recreated during this transition. `before.txt`
contains samples taken inside the app every 10 ms (subject to main-thread
scheduling); the probe source is retained here for reproducibility.

Disabling animation for the visibility transaction removed the oscillation but
expanded the window to 1360 points. That candidate was rejected.

Retained fix: give the detail column an explicit minimum of 320 points
and ideal width of 550 points. Native inspector animation remains enabled.
At 1360 points, opening/closing is stable, and opening the inspector preserves
an intentionally hidden left sidebar. The user subsequently confirmed the interaction is perfectly smooth. An exact
1080-point instrumented comparison was not completed; UI resize gestures did
not take effect. The temporary probe was removed from the app sources.

Apple documents column widths as preferences negotiated against layout
constraints: https://developer.apple.com/documentation/swiftui/navigationsplitview

The latest user-triggered probe (`after.txt`) sampled a constant 1166-point
outer split-view width throughout the transition. The final build after probe
removal passed, as did Swift formatting, whitespace, and code-signature checks.
