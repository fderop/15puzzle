#!/bin/bash
# Runs FifteenPuzzleTests/PuzzleTests.swift without Xcode via a tiny XCTest shim.
set -euo pipefail
cd "$(dirname "$0")"
W=$(mktemp -d)
{ echo "import Foundation"; grep -v -e '^import XCTest' FifteenPuzzleTests/PuzzleTests.swift; } > "$W/tests.swift"
python3 - "$W" <<'PY'
import re,sys
w=sys.argv[1]; cls=None; out=["import Foundation","var ran = 0"]
for l in open(w+"/tests.swift"):
    m=re.match(r'final class (\w+): XCTestCase',l); cls=m.group(1) if m else cls
    m=re.match(r'\s+func (test\w+)\(\)',l)
    if m: out.append(f'do {{ let t = {cls}(); t.{m.group(1)}(); ran += 1 }}')
out.append('print("tests run:", ran, " failed assertions:", failures)')
out.append('exit(failures == 0 ? 0 : 1)')
open(w+"/main.swift","w").write("\n".join(out))
PY
swiftc -O -target "$(uname -m)-apple-macos14.0" -o "$W/runner" Tests/Support/XCTestShim.swift "$W/tests.swift" "$W/main.swift" \
  FifteenPuzzle/{PuzzleModel,MoveTree,Solver,GameController,History}.swift
"$W/runner"
