#!/usr/bin/env bash
# Opt-in end-to-end test against real labs. Needs Docker and root for
# containerlab (it re-execs itself with sudo when needed).
#
#   tests/integration.sh          containerlab mini lab only
#   tests/integration.sh netlab   also the netlab FRR lab (pulls the FRR image)
#
# Each step prints what it checks; everything is torn down on exit.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
run="$here/../package/contents/tools/run"
work="$(mktemp -d)"
with_netlab="${1:-}"

cleanup() {
    echo "== teardown"
    sudo containerlab destroy -t "$work/mini.clab.yml" --cleanup >/dev/null 2>&1 || true
    if [ -d "$work/netlab" ]; then
        (cd "$work/netlab" && netlab down --cleanup >/dev/null 2>&1) || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT

snap() { sh "$run" snapshot; }
lab() { snap | jq -e --arg n "$1" '.labs[] | select(.name == $n)'; }
expect() { # expect <lab> <jq-filter> <description>
    if lab "$1" | jq -e "$2" >/dev/null; then echo "  ok   $3"; else
        echo "  FAIL $3"; lab "$1" || snap; exit 1; fi
}

cp "$here/lab/mini.clab.yml" "$work/"
echo "== containerlab mini lab"
sudo containerlab deploy -t "$work/mini.clab.yml" >/dev/null
expect clabw-mini '.lifecycle == "running" and .total == 2' "both nodes running"
expect clabw-mini '.managedBy == "containerlab"' "owned by containerlab"

docker stop clab-clabw-mini-h2 >/dev/null
expect clabw-mini '.lifecycle == "partial" and .running == 1' "one node stopped → partial"

if [ -n "$with_netlab" ]; then
    echo "== netlab lab on the clab provider"
    cp -r "$here/lab/netlab" "$work/netlab"
    (cd "$work/netlab" && netlab up >/dev/null)
    expect netlab '.managedBy == "netlab" and .providers == ["containerlab"]' "one merged netlab card"
    count="$(snap | jq '[.labs[] | select(.dir | endswith("/netlab"))] | length')"
    [ "$count" = 1 ] && echo "  ok   not double-counted" || { echo "  FAIL shown $count times"; exit 1; }
fi

echo "== all passed"
