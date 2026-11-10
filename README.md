# fifteen

Native macOS 15-puzzle for mouse speed-solving (Swift, AppKit + SwiftUI).

- **Hover to move** — no clicking. Any tile adjacent to the empty cell slides as soon as the cursor enters it; fast sweeps are traced cell by cell so no move is lost.
- **T** rotates the tile color scheme 90 degrees clockwise. Four presses restore the original colors.
- **R** reshuffles into a new random solvable state.
- **Play** shows the timer, move count, and Review after a solve. Only Play games enter history or update the personal best.
- **Train** has a separate game with Ghost, Solve, optimal counts, deficit, and TPS. Training games do not enter history.
- **G** toggles Ghost in Train.
- **S** opens Solve in Train. Drag tiles to set targets, then press **S** again to find a shortest path. Press **S** once more to cancel the path.
- **Space** plays one optimal move in Train. If a target path is active, Space follows that path.
- **← / →** undo / redo actual move history in Train. **↑ / ↓** switch sibling branches.
- **Review** replays the original scramble with an optimal solution. Arrow keys step through the solution in both Play and Train.
- **History** charts saved Play games, with the optimal move count overlaid. Hover a point for its stats.

Stats are stored in `~/Library/Application Support/FifteenPuzzle/history.json`; the personal best is in `UserDefaults`.

## Build

```sh
./build.sh --run   # swiftc build → build/fifteen.app (no Xcode needed)
./test.sh          # pure-logic tests
```

`FifteenPuzzle.xcodeproj` is also included for Xcode.
