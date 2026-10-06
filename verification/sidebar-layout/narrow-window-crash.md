# Narrow-window inspector crash

2026-10-06

The user reported a crash after opening Speakers at minimum window width and
clicking the double-chevron toolbar overflow control. Crash reports at 16:17:02
and 16:17:11 show `NSGenericException` in AppKit constraint updates, reached
through SwiftUI `SplitViewChildController.hostingView(...didUpdateMinSize...)`.
The system log identifies an excessive number of Update Constraints passes at
a window width of 840 points.

Independently reproduced the same exception by opening Speakers in a
901-point tiled window, then shrinking it to 840 points. Thus the failure is
not restricted to choosing an overflow-menu action.

Retained fix: coordinate the existing native navigation sidebar and inspector
explicitly below 1080 points. Opening Speakers closes the meeting sidebar;
reopening the meeting sidebar closes Speakers. Shrinking a window with both
open also closes the meeting sidebar. Wider windows still support both panes.
The existing 320-point detail-column minimum/550-point ideal remains.

Rejected experiments (not present in app sources): moving the inspector outside
the navigation split, adding a transcript minimum without coordinating visibility,
and replacing the inspector with an HSplitView. These still crashed or clipped
content under narrow constraints.

Final-build UI verification:

- At 840 points, repeatedly opened Speakers with the left sidebar visible and
  reopened the left sidebar with Speakers visible. Both directions completed
  without a crash; screenshots showed readable content without clipping.
- Expanded to 1800 points and opened both sidebars successfully.
- Returned directly to approximately 840 points with both sidebars open:
  meeting sidebar collapsed, Speakers stayed open, app remained responsive.
- The problematic cramped three-column state is prevented; the toolbar fits
  without its overflow chevron in the verified minimum-width configuration.
- Debug packaging, formatting, whitespace, and signature checks passed.

No recording or transcription was in progress during reproduction. Settings,
meeting data, and speaker-assignment logic were unchanged. Nix installation and
macOS 15 runtime behavior were not tested or updated.

A subsequent attempt to avoid transient toolbar overflow by separating the
Speakers toolbar item and increasing its visibility priority was reverted at
the user's request. The original toolbar grouping remains; the user still sees
a brief overflow chevron at cramped widths and accepts that visual edge case.
