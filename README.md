# fifteen

- **T** toggles the tile colors between the original scheme and its transpose across the main diagonal.
- **R** reshuffles into a new random solvable state.
- **G** toggles Ghost in Train.
- **S** opens Solve in Train. Drag tiles to set targets, then press **S** again to find a shortest path. Press **S** once more to cancel the path.
- **Space** plays one optimal move in Train. If a target path is active, Space follows that path.
- **← / →** undo / redo actual move history in Train. **↑ / ↓** switch sibling branches.
- **Review** replays the original scramble with an optimal solution. Arrow keys step through the solution in both Play and Train.

```sh
./build.sh --run   # swiftc build → build/fifteen.app (no Xcode needed)
./test.sh          # pure-logic tests
```
