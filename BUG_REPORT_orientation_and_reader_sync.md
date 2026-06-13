# Bug Report: Orientation Transition And Reader Sync

## Summary

This Quran Flutter app uses two different reading modes:

- `portrait`: `PageView`
- `landscape`: `ContinuousQuranView` based on `ListView + ScrollController`

The main bug family is related to switching between portrait and landscape while preserving the correct reading position and avoiding visual glitches.

## Current Architecture

- Portrait mode uses a page-based controller.
- Landscape mode uses a continuous vertical scroll of page images.
- The app tracks the current page and uses it to restore position when switching orientation.
- The app also has:
  - bookmarks
  - hizb popup notifications
  - top overlay bar
  - bottom overlay menu
  - surah index and hizb index

## Main Problems

### 1. Incorrect visual transition when rotating

When rotating from portrait to landscape, the app may briefly show:

- a white screen
- a black screen
- or a visible transition glitch before the target page settles

This does not always happen, but it happens often enough to be noticeable.

### 2. Position sync between portrait and landscape is fragile

The app needs the user to remain on the same logical page when rotating:

- portrait -> landscape
- landscape -> portrait

This has been difficult because:

- portrait is page-based
- landscape is offset-based

So the app must convert:

- `page -> scroll offset`
- `scroll offset -> page`

Any mismatch here causes the wrong target page or visible jumps.

### 3. Previous implementation caused flash/jump behavior

Earlier attempts relied on:

- `jumpTo`
- `postFrameCallback`
- delayed readiness logic
- visual transition workarounds

Those approaches reduced some symptoms but often caused new regressions.

## Root Cause Identified Earlier

The core issue discussed earlier was that the landscape reader could be initialized in a way that visually exposed an intermediate state before the final target position was ready.

This made the transition appear broken even when the final position was eventually corrected.

## Important Technical Context

The landscape reader displays page images. That means visual behavior depends on:

- image size
- page aspect ratio
- viewport width
- scroll offset initialization
- image decoding / rendering timing

This is why orientation changes can show a temporary visual artifact if the first visible frame is not already correct.

## Current Known Good UI Fixes That Should Be Preserved

The following fixes are unrelated to the orientation transition bug and should be preserved:

- Arabic text that was previously corrupted or mojibake is now readable again
- the top overlay bar respects the protected camera / safe area in portrait
- the bottom overlay menu respects the bottom system area in portrait
- when the bottom menu is hidden, the portrait page uses the freed space again
- the surah index opens near the current surah
- the current surah can be highlighted in the index

## What Was Tried Before

Different approaches were attempted during debugging, including:

- keeping portrait and landscape readers both alive in the widget tree
- using `Offstage` / `Stack`
- moving state into a coordinator
- using initial page / initial offset strategies
- forcing readiness before showing the new reader
- using placeholder first-frame rendering
- adding and removing black background fallback behavior

Some of these helped partially, but the behavior was still not consistently smooth.

## Current Direction

The current desired behavior is:

- preserve the correct logical reading position
- avoid any white/black flash during rotation
- make rotation feel visually immediate and stable
- avoid regressions in bookmarks, hizb popup, top bar, bottom menu, and index behavior

## Desired Outcome

When the user rotates:

1. The app should keep the same reading position.
2. The target page should appear immediately.
3. No blank frame should be shown.
4. No fake temporary page should appear.
5. No UI overlays should shift into unsafe screen areas.

## Notes For Future Debugging

- Be careful not to regress the safe-area fixes.
- Be careful not to regress surah index behavior.
- Any orientation fix should be evaluated together with:
  - bookmark navigation
  - hizb popup display
  - top overlay visibility
  - bottom menu safe-area behavior
  - last-page restore

