#!/bin/sh
# Import the project (class_name cache), then run every tests/*.tscn suite
# except the screenshot harness. New combat/input scenes dropped in tests/
# are picked up. Each suite is its own process and must quit 0 or 1.
set -eu
cd "$(dirname "$0")/.."

godot --headless --path . --import

failed=0
found=0
for scene in tests/*.tscn; do
	name=$(basename "$scene")
	case "$name" in
		screens.tscn) continue ;;
	esac
	found=$((found + 1))
	echo "== $name =="
	# Same invocation shape as the direct commands in the README.
	log=$(mktemp)
	if ! godot --headless --path . "res://tests/$name" >"$log" 2>&1; then
		cat "$log"
		rm -f "$log"
		failed=1
		continue
	fi
	cat "$log"
	if grep -E "leaked at exit|resources still in use" "$log" >/dev/null; then
		echo "suite $name leaked audio resources at shutdown" >&2
		rm -f "$log"
		failed=1
		continue
	fi
	rm -f "$log"
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
