# rundown

A talk/routine pacer that lives in the MacBook notch. Write your segments as markdown, hit start, and glance up to see how long the current segment has left, how much of the whole thing remains, and whether to speed up or slow down. A broadcast *rundown* is the timed list of segments for a show; the timers run down.

## Format

One line, comma-separated:

```
5m intro, 10m motivation, 20m results, 5m conclusion, ? Q&A
```

or one segment per line (bullets optional), and both can be mixed:

```
# My talk

- 5m intro
- 10m motivation
- results 20m
- ? questions
- wrap-up 2:30
```

- A segment is `<duration> <name>` or `<name> <duration>`. Durations: `5m`, `90s`, `1h30m`, `2m30s`, `2:30`, `1:05:00`. A bare number as a prefix means minutes (`5 intro`).
- `?`, `~` or `∞` — or no duration at all — makes a **stopwatch** segment: it counts up and never counts as behind or ahead.
- The first `# Heading` is the title. Other headings, blank lines, and lines starting with `>`, `<!--` or `---` are ignored. List bullets (`-`, `*`, `+`, `1.`, `1)`) and checkboxes are stripped.
- Segment names can't contain commas (commas always split segments).

See `examples/`.

## What it shows

Compact (the notch wings):

- **Left:** current segment name and its countdown. Turns orange under 30s, red with a `+1:23` once you're over. Stopwatch segments show `⏱ elapsed`.
- **Right:** time remaining for the whole routine, and a pace chip: green dot = on track, red `▲ 1:20` = behind by 1:20 (speed up), green `▼ 0:45` = ahead (you can slow down).

Hover to expand: title, projected finish time next to the planned one, `speed up · behind 1:20` / `slow down · ahead 0:45` / `on track`, the full segment list with actual/planned and a progress bar on the current one (click a row to jump), and prev / play-pause / next / reset controls.

Definitions:

- **drift** = Σ (actual − planned) over finished timed segments + the overtime of the current segment. Finishing a segment early puts you ahead; running over puts you behind as it happens. |drift| < 20s counts as on track.
- **remaining** = what's left of the current segment (never negative) + all future planned segments. **Projected end** = now + remaining, so it slips forward as you run over.

The menu bar item also shows the total remaining, which is handy on an external display where the notch panel isn't.

## Controls

Global hotkeys (no Accessibility permission needed):

| keys | action |
|---|---|
| `⌃⌥Space` | start / pause / resume |
| `⌃⌥→` | next segment |
| `⌃⌥←` | previous segment (keeps accumulating into it) |
| `⌃⌥R` | reset |
| `⌃⌥N` | hide / show the panel |
| `⌃⌥Q` | quit |

Clicking the compact panel = start when idle, next while running, resume when paused, reset when finished. Right-click it for a small menu (open, start/pause, reset, quit); the expanded view has a ⏻ button too. The menu bar item (timer icon) has Open / Open Recent / Reload / Edit, the same controls, and Quit.

The loaded file is watched: edits reload immediately while idle; during a run they show a "file changed · reload" button in the expanded view instead of interrupting you.

## Build & run

Needs Xcode 15+ (macOS 14 SDK). No Xcode project; it's a Swift package plus a Makefile that assembles the `.app`.

```
make test                    # parser + runner unit tests
make run FILE=examples/talk.md
make install                 # → /Applications/rundown.app
open -a rundown talk.md      # or: rundown.app/Contents/MacOS/rundown talk.md
```

With no argument it reopens the last routine.

## Presenting

Keep the built-in display as the presenter display (Keynote/PowerPoint presenter view, or extended rather than mirrored). The panel sits on the screen with the notch, stays on top of full-screen apps and follows every Space, and the projector never sees it. On a Mac without a notch (or when the notched display is closed) it becomes a small black pill at the top centre of the main screen.
