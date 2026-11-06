# 15puzzle

Native macOS 15-puzzle for mouse speed-solving (Swift, AppKit + SwiftUI).

- **Hover to move** — no clicking. Any tile adjacent to the empty cell slides as soon as the cursor enters it; fast sweeps are traced cell by cell so no move is lost.
- **R** reshuffles into a new random solvable state.
- **← / →** undo / redo through the in-memory move tree; **↑ / ↓** switch sibling branches.
- **Review** (after a solve) replays the same scramble with an optimal solution (IDA* + Walking Distance heuristic), stepped with the arrow keys.
- **History** tab charts moves, time and TPS of every solve, with the optimal move count overlaid. Hover a point for that solve's stats.

Stats are stored in `~/Library/Application Support/FifteenPuzzle/history.json`; the personal best is in `UserDefaults`.

## Build

```sh
./build.sh --run   # swiftc build → build/FifteenPuzzle.app (no Xcode needed)
./test.sh          # pure-logic tests
```

`FifteenPuzzle.xcodeproj` is also included for Xcode.
