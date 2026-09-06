# Demo assets

Reproducible terminal recordings used in the README and as the GitHub social preview.

| Asset | Source | Renders |
|-------|--------|---------|
| `quiz.gif` | `quiz.tape` + `quiz-demo.sh` | one `/quiz` round: a half-right answer gets corrected, results land in the ledger |
| `learn.gif` | `learn.tape` + `learn-demo.sh` | the pause summary followed by `/learn` |
| `social-preview.png` | `social-preview.tape` + `social-preview.sh` | 1280x640 frame for Settings > Social preview |

The `*-demo.sh` scripts are **scripted replays**, not live model calls: the transcript continues the JWT auth session used throughout the README and is fixed so the GIFs re-render identically. Keep the wording aligned with the examples in `README.md` when you change either.

## Re-render

Requires [VHS](https://github.com/charmbracelet/vhs) (which needs `ttyd` and `ffmpeg`). From the repo root:

```bash
vhs docs/demo/quiz.tape
vhs docs/demo/learn.tape
vhs docs/demo/social-preview.tape && rm -f docs/demo/social-preview-frames.gif
```

`DEMO_FAST=1 bash docs/demo/quiz-demo.sh` prints the transcript with no delays; `tests/demo.bats` runs the scripts that way to make sure they stay executable.
