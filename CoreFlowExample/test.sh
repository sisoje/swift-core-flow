#!/bin/sh
# Runs the UI-test suite once on an iPhone simulator, against the TEST app
# (@testable import of the UI package, where every component lives). Each
# test launches its own scenario (launchApp sets SCENARIO per launch). The
# real app is the CoreFlowRealApp scheme.
set -eu
cd "$(dirname "$0")"

xcodegen generate

rm -rf TestResults.xcresult
xcodebuild test \
    -project CoreFlowExample.xcodeproj \
    -scheme CoreFlowTestApp \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
    -enableCodeCoverage YES \
    -resultBundlePath TestResults.xcresult \
    -collect-test-diagnostics never

# Per-target coverage from the result bundle — the CoreFlowExampleUI line is
# the one that matters: the UI tests component-test the package's Cores.
xcrun xccov view --report --only-targets TestResults.xcresult

# Adjusted coverage: @Shell hosts' members execute as Core's macro-generated
# copies, which Swift's coverage can't attribute back to source lines (the
# expansion buffers are invisible to xccov) — so host members are excluded
# from the denominator. Everything left runs as itself; an uncovered line
# here is a real gap.
xcrun xccov view --report --json TestResults.xcresult | python3 -c "
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
