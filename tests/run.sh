#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

log=$(mktemp)
trap 'rm -f "$log"' EXIT

engine_errors() {
	grep -Eq '^(SCRIPT ERROR:|ERROR:)|leaked at exit|resources still in use' "$log"
}

if ! godot --headless --path . --import >"$log" 2>&1 || engine_errors; then
	cat "$log"
	exit 1
fi

failed=0
found=0
for scene in tests/*.tscn; do
	[ -f "$scene" ] || continue
	name=$(basename "$scene")
	case "$name" in
		screens.tscn) continue ;;
	esac
	found=$((found + 1))
	echo "== $name =="
	# Bound runs that never report, including scenes with a parse error.
	if ! godot --headless --path . --max-fps 120 --quit-after 2400 "res://tests/$name" >"$log" 2>&1 \
		|| engine_errors || ! grep -Eq ' PASS: [0-9]+ checks$' "$log"; then
		failed=1
		echo "suite $name failed or exited without a passing report" >&2
	fi
	cat "$log"
done

if [ "$found" -eq 0 ]; then
	echo "no test scenes found" >&2
	exit 1
fi

if [ "$failed" -ne 0 ]; then
	echo "headless suites failed" >&2
	exit 1
fi

echo "All $found headless suites passed."
exit 0
