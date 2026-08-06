#!/bin/sh
# Adjusted coverage over an xcresult. @Shell hosts' members execute as Core's
# macro-generated copies, which Swift's coverage can't attribute back to
# source lines (expansion buffers are invisible to xccov) — so host members
# are excluded from the denominator. Everything left runs as itself; an
# uncovered line here is a real gap.
#
#   sh coverage.sh [path/to/TestResults.xcresult]
#
# With no argument, finds the newest test xcresult in DerivedData — the
# Xcode Cmd-U case, wired as a scheme test post-action (which may race the
# bundle finalization; rerun by hand if xccov complains).
set -eu
cd "$(dirname "$0")"

RESULT="${1:-}"
if [ -z "$RESULT" ]; then
    RESULT=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/CoreFlowExample-*/Logs/Test/*.xcresult 2>/dev/null | head -1)
fi
[ -n "$RESULT" ] || { echo "coverage.sh: no xcresult found"; exit 1; }
echo "Coverage from: $RESULT"

xcrun xccov view --report --only-targets "$RESULT"

xcrun xccov view --report --json "$RESULT" | python3 -c "
import json, re, sys, glob
hosts = set()
for path in glob.glob('CoreFlowExampleUI/Sources/CoreFlowExampleUI/*.swift'):
    for m in re.finditer(r'@Shell\s+(?:public\s+)?struct\s+(\w+)', open(path).read()):
        hosts.add(m.group(1))
d = json.load(sys.stdin)
t = next(t for t in d['targets'] if 'ExampleUI' in t['name'])
pat = re.compile(r'\b(?:%s)\b' % '|'.join(sorted(hosts)))
def is_host(fn):
    return bool(pat.search(fn['name'])) and 'Scenario' not in fn['name']
cov = tot = 0
print('Adjusted coverage (twin-tested host members excluded):')
for f in t['files']:
    c = sum(fn['coveredLines'] for fn in f['functions'] if not is_host(fn))
    x = sum(fn['executableLines'] for fn in f['functions'] if not is_host(fn))
    cov += c; tot += x
    if x: print('  %-26s %7.2f%% (%d/%d)' % (f['name'].split('/')[-1], 100.0*c/x, c, x))
print('  %-26s %7.2f%% (%d/%d)' % ('TOTAL', 100.0*cov/tot, cov, tot))
"
