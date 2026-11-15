#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
T="$(newtmp)"; trap 'rm -rf "$T"' EXIT
H="$REPO/bin/wb-health"
NOW=$(date +%s); GB=$((1024 * 1024 * 1024))
export WB_MEMSIZE=$((32 * GB))
swap() { echo "total = $1.00M  used = $2.00M  free = 1.00M  (encrypted)"; }   # sysctl's own wording, in MB

out=$(WB_BOOTTIME=$((NOW - 3 * 86400)) WB_SWAPUSAGE="$(swap 2048 1024)" "$H"); rc=$?
assert_eq "exits 0" "$rc" "0"
assert_eq "healthy: uptime and swap, nothing more" "$out" "up 3 days · swap 1 GB on 32 GB RAM"

out=$(WB_BOOTTIME=$((NOW - 162 * 86400)) WB_SWAPUSAGE="$(swap 2048 1024)" "$H")
assert_contains "30+ days up: restart soon" "$out" "up 162 days"
assert_contains "and it says so" "$out" "restart soon"
assert_contains "and names wb-restore" "$out" "wb-restore"

out=$(WB_BOOTTIME=$((NOW - 2 * 86400)) WB_SWAPUSAGE="$(swap 43008 41612)" "$H")
assert_contains "swap at half of RAM or more: restart soon" "$out" "restart soon"
assert_contains "swap shown in GB" "$out" "swap 41 GB on 32 GB RAM"

out=$(WB_BOOTTIME=$((NOW - 2 * 86400)) WB_SWAPUSAGE="$(swap 20480 16383)" "$H")
assert_not_contains "just under half of RAM: fine" "$out" "restart soon"

out=$(WB_BOOTTIME=$((NOW - 3600)) WB_SWAPUSAGE="$(swap 0 0)" "$H")
assert_eq "under a day: hours" "$out" "up 1 hour · swap 0 GB on 32 GB RAM"

out=$(WB_BOOTTIME=$((NOW - 40 * 86400)) WB_SWAPUSAGE="$(swap 2048 1024)" "$H" --color)
assert_contains "--color: due is yellow" "$out" $'\033[33m'
out=$(WB_BOOTTIME=$((NOW - 3 * 86400)) WB_SWAPUSAGE="$(swap 2048 1024)" "$H" --color)
assert_not_contains "--color: healthy is not" "$out" $'\033[33m'

out=$(WB_BOOTTIME=garbage WB_SWAPUSAGE="$(swap 2048 1024)" "$H"); rc=$?
assert_eq "unreadable uptime: still exits 0" "$rc" "0"
assert_eq "and shows what it can" "$out" "swap 1 GB on 32 GB RAM"
out=$(WB_BOOTTIME=garbage WB_SWAPUSAGE=garbage "$H"); rc=$?
assert_eq "nothing readable: exit 0, print nothing" "$rc:$out" "0:"

# the launcher's screen headers carry the line
hdr() { (cd "$T" && env WB_BOOTTIME=$((NOW - 162 * 86400)) WB_SWAPUSAGE="$(swap 2048 1024)" \
  zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_header 'enter: choose'"); }
out=$(hdr)
assert_contains "header: the keys line" "$out" "enter: choose"
assert_contains "header: then the health line" "$out" "restart soon"
assert_eq "header: two lines" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
out=$(cd "$T" && env WB_BOOTTIME=garbage WB_SWAPUSAGE=garbage zsh -f -c "source '$REPO/shell/workbench.zsh'; _wb_header 'enter: choose'")
assert_eq "header: no health, just the keys" "$out" "enter: choose"
finish
