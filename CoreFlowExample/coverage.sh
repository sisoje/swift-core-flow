#!/bin/sh
# Which components' scenarios actually ran — coverage as a checklist, not a
# number: percentages misattribute here (host members execute as Core's
# macro-generated copies, invisible to xccov), but "did this component's
# scenario execute" is exact.
#
#   sh coverage.sh [path/to/TestResults.xcresult]
#
# No argument: newest test xcresult in DerivedData — the Xcode Cmd-U case,
# wired as a scheme test post-action writing CoverageReport.txt (post-actions
# may race bundle finalization; rerun by hand if it looks empty).
set -eu
cd "$(dirname "$0")"

RESULT="${1:-}"
[ -n "$RESULT" ] || RESULT=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/CoreFlowExample-*/Logs/Test/*.xcresult 2>/dev/null | head -1)
[ -n "$RESULT" ] || { echo "coverage.sh: no xcresult found"; exit 1; }

xcrun xccov view --report --json "$RESULT" | python3 -c "
import json, re, sys, glob
hosts = {}
for path in glob.glob('CoreFlowExampleUI/Sources/CoreFlowExampleUI/*.swift'):
    for m in re.finditer(r'@Shell\s+(?:public\s+)?struct\s+(\w+)', open(path).read()):
        hosts[m.group(1)] = path.split('/')[-1]
d = json.load(sys.stdin)
t = next(t for t in d['targets'] if 'ExampleUI' in t['name'])
ran = {f['name'].split('/')[-1]: any('Scenario' in fn['name'] and fn['executionCount'] > 0
                                     for fn in f['functions'])
       for f in t['files']}
for host, file in sorted(hosts.items()):
    print(('  covered  ' if ran.get(file) else 'UNCOVERED  ') + host)
"
