# Recalibration text pass

Branch: `feat/recalibration-text-pass`
Base: `main` @ `5f5c5bc5`

This branch is a content pass over the decision flow, kiosk, briefing and
departure cutscene. It re-voices the game around the recalibration premise,
adds authored context to every decision bay, trims the post-decision
assessment screens, and rewrites the final cutscene subtitles.

Nothing here changes scoring arithmetic, save format, or the ScreenState
contract.

---

## 1. Premise flip — emergency to recalibration

The refit is no longer a breakdown. SHIPMIND was upgraded and holds all five
functions on legacy defaults until the player recalibrates each one to the
declared operating model.

- `scripts/systems/shipmind.gd` — boot, denial, VO and restore lines
  re-voiced. All ten recommendation functions now argue "it stays with me";
  restore confirms "%s is recalibrated."
- `scripts/ui/intro_screen.gd` — briefing rewritten to three beats: aboard
  mid-refit to the Intelligent Operating Model; SHIPMIND running defaults it
  is sure of; recalibrate all five functions.
- `scripts/puzzles/log_terminal.gd` — override codes are parked "until
  recalibration is complete" under "one accountable authority per function
  during the upgrade window"; entry log reads "Crew member entered the
  navigation room."
- `scripts/puzzles/hub_terminal.gd` — kiosk greeting: "Hello. SHIPMIND here —
  upgraded, and awaiting recalibration." Log empty state: "Nothing yet. The
  defaults have had their way so far."

## 2. Decision blocks — authored context per bay

Each bay now declares a `DECISION_NOTE` constant (OVERVIEW / LOG DETAILS /
SHIPMIND JUSTIFICATION / SUMMARY) and passes it through `placement_block()`
in its intro state. The mobile shell renders these as flowing tab sections.

- `scripts/puzzles/nav_puzzle.gd`
- `scripts/puzzles/life_support_puzzle.gd`
- `scripts/puzzles/comms_puzzle.gd`
- `scripts/puzzles/cargo_puzzle.gd`
- `scripts/puzzles/engineering_puzzle.gd`

Life support now names Aft Berths at 18.1% (under the compartment minimum)
with the summary "The ship-wide average is green. Aft Berths, where the crew
sleeps, is not."

## 3. Post-decision assessment trim

The screen that scores a decision after it is placed no longer scrolls for
junk text.

- `scripts/systems/score.gd` — `reflection_lines(system_id,
  include_mandate := true)` gains a flag. The hub terminal and the standing
  record keep the default (mandate echo present). The five placed states
  pass `false`.
- Each puzzle's placed state drops the dim mandate line (it duplicated the
  revise option's own hint) and the rule separator.
- `scripts/ui/mobile_decision_ui.gd` — the stakes line, mandate echo and
  tag note are removed from the assessment surface; `_tag()` deleted.
- `scripts/terminal/terminal_ui.gd` — `_tag_row()` / `_tag_label()` removed
  from the desktop spectrum.

Scroll remains available in the DECISION tabs by design.

## 4. Departure cutscene — four agreed subtitles

`scripts/world/launch_cutscene.gd` now shows exactly the four agreed lines,
one per beat, with per-shot placement:

1. 0.0s — centre zone, over the black of space inside the bridge: "Now
   equipped with a mandate that puts responsibility in the right hands,"
2. 5.0s — bottom zone: "The Adamant Verity's engines roar to life"
3. 8.2s — bottom zone: "The ship continues on its journey home, with man and
   machine working together."
4. 12.0s — bottom zone: "The Intelligent Operating Model is live."

Placement is anchored to screen percentages (bottom zone sits between 80%
and 95% height; bottom 5% clear). The conflicting "For the first time…"
caption block is removed; no other end-sequence text remains. Zone resets on
replay.

---

## Known limits

- Life support's DECISION_NOTE runs 13–16 wrapped lines against ~11
  available; scroll is accepted there per the decision-tab design.
- Assessment screens now run ~10–12 wrapped lines worst case; the
  proportionality line is the documented next cut if any bay still scrolls.
- Caption placement was set without a live render pass; verify against the
  cutscene on first run.
- Life support board_state still prints "GALLEY + WORKSHOP 21.2 percent"
  while the DECISION_NOTE calls the same compartment "Core Systems" — naming
  not yet reconciled.
- HUD changes (CREW REYES removal, menu pull-in, Stakes→Impact below
  Mandate, icons-only axis legend) are deliberately not in this branch.
