#!/usr/bin/env bash
set -euo pipefail

EC_IO=/sys/kernel/debug/ec/ec0/io
INTERVAL=${1:-0.5}

if [[ ${EUID} -ne 0 ]]; then
	echo "Run as root: sudo $0 [interval_seconds]" >&2
	exit 1
fi

if [[ ! -r "$EC_IO" ]]; then
	echo "$EC_IO is not readable. Mount debugfs/load ec_sys first." >&2
	exit 1
fi

tmp_prev=$(mktemp)
tmp_cur=$(mktemp)
trap 'rm -f "$tmp_prev" "$tmp_cur"' EXIT

dump_ec() {
	dd if="$EC_IO" bs=256 count=1 status=none
}

hex_byte() {
	od -An -tx1 -j "$1" -N 1 "$tmp_cur" | tr -d ' \n'
}

word_be() {
	local hi lo
	hi=$(hex_byte "$1")
	lo=$(hex_byte "$2")
	printf '%d' "$(( 0x$hi * 256 + 0x$lo ))"
}

decode_line() {
	local fasp e2 faap bpwm itsm cmen f1 f2
	fasp=$(hex_byte 0x5f)
	e2=$(hex_byte 0xe2)
	faap=$(( (0x$e2 >> 5) & 1 ))
	bpwm=$(hex_byte 0xe3)
	itsm=$(hex_byte 0xe4)
	cmen=$(hex_byte 0xf0)
	f1=$(word_be 0x9b 0x9c)
	f2=$(word_be 0x9d 0x9e)
	printf 'rpm=%5d/%5d fasp=%s faap=%d bpwm=%s itsm=%s cmen=%s f2-f8=' "$f1" "$f2" "$fasp" "$faap" "$bpwm" "$itsm" "$cmen"
	od -An -tx1 -j 0xf2 -N 7 "$tmp_cur" | tr -s ' ' | sed 's/^ //;s/$//'
}

diff_line() {
	local out="" old new
	for i in $(seq 0 255); do
		old=$(od -An -tx1 -j "$i" -N 1 "$tmp_prev" | tr -d ' \n')
		new=$(od -An -tx1 -j "$i" -N 1 "$tmp_cur" | tr -d ' \n')
		if [[ "$old" != "$new" ]]; then
			out+=" $(printf '%02x' "$i"):$old>$new"
		fi
	done
	if [[ -n "$out" ]]; then
		printf 'diff:%s\n' "$out"
	fi
}

dump_ec >"$tmp_prev"
cp "$tmp_prev" "$tmp_cur"
printf '[%(%H:%M:%S)T] ' -1
decode_line

while true; do
	sleep "$INTERVAL"
	dump_ec >"$tmp_cur"
	printf '[%(%H:%M:%S)T] ' -1
	decode_line
	diff_line
	cp "$tmp_cur" "$tmp_prev"
done
