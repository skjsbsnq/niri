#!/usr/bin/env bash
set -euo pipefail

ACPI_CALL=/proc/acpi/call
EC_IO=/sys/kernel/debug/ec/ec0/io
WMAA='\_SB.PCI0.WMID.WMAA'

if [[ ${EUID} -ne 0 ]]; then
	echo "Run as root: sudo $0 [--set SPEED|--custom-set SPEED|--custom-off|--set-mode MODE|--direct-fasp SPEED|--hold-fasp SPEED]" >&2
	exit 1
fi

if [[ ! -w "$ACPI_CALL" || ! -r "$ACPI_CALL" ]]; then
	echo "$ACPI_CALL is not readable/writable. Load acpi_call first." >&2
	exit 1
fi

call_wmaa() {
	local label=$1
	local hex=$2
	printf '%s: ' "$label"
	printf '%s 0 0 b%s\n' "$WMAA" "$hex" >"$ACPI_CALL"
	cat "$ACPI_CALL"
	printf '\n'
}

read_ec() {
	printf 'EC 0x5f FASP: '
	od -An -tx1 -v -j 0x5f -N 1 "$EC_IO"
	printf 'EC 0x9b-0x9e FAN: '
	od -An -tx1 -v -j 0x9b -N 4 "$EC_IO"
	printf 'EC 0xe2-e4 FLAGS/FASP?: '
	od -An -tx1 -v -j 0xe2 -N 3 "$EC_IO"
	printf 'EC 0xf0 CMEN / 0xf2-f8: '
	od -An -tx1 -v -j 0xf0 -N 1 "$EC_IO"
	od -An -tx1 -v -j 0xf2 -N 7 "$EC_IO"
}

read_wmi() {
	call_wmaa 'WMI get SystemPerMode 0x08' '00fa000800000000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI get fan RPM 0x0d' '00fa000d00000000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI get MaxFanSpeedSwitch/FAAP 0x14' '00fa001400000000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI get MaxFanSpeed/FASP 0x15' '00fa001500000000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI get CMEN 0x17' '00fa001700000000000000000000000000000000000000000000000000000000'
}

set_faap_fasp() {
	local speed_dec=$1
	local speed_hex
	speed_hex=$(printf '%02x' "$speed_dec")

	call_wmaa 'WMI set MaxFanSpeedSwitch/FAAP ON 0x14' '00fb001401000000000000000000000000000000000000000000000000000000'
	call_wmaa "WMI set MaxFanSpeed/FASP 0x15 = $speed_dec" "00fb0015${speed_hex}00000000000000000000000000000000000000000000000000000000"
}

set_custom_on() {
	call_wmaa 'WMI set CPUPower/custom ON 0x17' '00fb001701000000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI set CPU temp wall 99' '00fb001704630000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI set SPL 101' '00fb001702650000000000000000000000000000000000000000000000000000'
	call_wmaa 'WMI set SPPT 105' '00fb001703690000000000000000000000000000000000000000000000000000'
}

set_custom_off() {
	call_wmaa 'WMI set CPUPower/custom OFF 0x17' '00fb001700000000000000000000000000000000000000000000000000000000'
}

set_system_mode() {
	case "$1" in
		balance|balanced|0)
			call_wmaa 'WMI set SystemPerMode Balance 0x08=0' '00fb000800000000000000000000000000000000000000000000000000000000'
			;;
		performance|perf|fast|1)
			call_wmaa 'WMI set SystemPerMode Performance 0x08=1' '00fb000801000000000000000000000000000000000000000000000000000000'
			;;
		quiet|work|silent|2)
			call_wmaa 'WMI set SystemPerMode Quiet 0x08=2' '00fb000802000000000000000000000000000000000000000000000000000000'
			;;
		*)
			echo "MODE must be one of: balance, performance, quiet" >&2
			exit 1
			;;
	esac
}

validate_speed() {
	if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ || $1 -lt 0 || $1 -gt 100 ]]; then
		echo "SPEED must be 0..100" >&2
		exit 1
	fi
}

echo '== before =='
read_ec
read_wmi

if [[ ${1:-} == "--set" ]]; then
	if [[ $# -ne 2 ]]; then
		echo "Usage: sudo $0 --set SPEED   # SPEED is 0..100" >&2
		exit 1
	fi
	validate_speed "$2"

	echo "== set FAAP on, FASP=$2 =="
	set_faap_fasp "$2"

	for i in 1 2 3 4 5; do
		sleep 1
		echo "== after ${i}s =="
		read_ec
		read_wmi
	done
elif [[ ${1:-} == "--custom-set" ]]; then
	if [[ $# -ne 2 ]]; then
		echo "Usage: sudo $0 --custom-set SPEED   # SPEED is 0..100" >&2
		exit 1
	fi
	validate_speed "$2"

	echo "== set custom on, FAAP on, FASP=$2 =="
	set_custom_on
	set_faap_fasp "$2"

	for i in 1 2 3 4 5; do
		sleep 1
		echo "== after custom ${i}s =="
		read_ec
		read_wmi
	done
elif [[ ${1:-} == "--custom-off" ]]; then
	echo '== set custom off =='
	set_custom_off
	sleep 1
	read_ec
	read_wmi
elif [[ ${1:-} == "--set-mode" ]]; then
	if [[ $# -ne 2 ]]; then
		echo "Usage: sudo $0 --set-mode MODE   # balance|performance|quiet" >&2
		exit 1
	fi
	echo "== set mode $2 =="
	set_system_mode "$2"
	sleep 1
	read_ec
	read_wmi
elif [[ ${1:-} == "--direct-fasp" ]]; then
	if [[ $# -ne 2 ]]; then
		echo "Usage: sudo $0 --direct-fasp SPEED   # SPEED is 0..100, writes EC 0x5f directly" >&2
		exit 1
	fi
	validate_speed "$2"
	speed_hex=$(printf '%02x' "$2")
	echo "== direct EC write FASP 0x5f=$2 =="
	printf "\\x${speed_hex}" | dd of="$EC_IO" bs=1 seek=$((0x5f)) conv=notrunc 2>/dev/null
	echo '== immediate =='
	read_ec
	read_wmi
	for i in 1 2 3 4 5; do
		sleep 1
		echo "== after direct ${i}s =="
		read_ec
		read_wmi
	done
elif [[ ${1:-} == "--hold-fasp" ]]; then
	if [[ $# -ne 2 ]]; then
		echo "Usage: sudo $0 --hold-fasp SPEED   # SPEED is 0..100, writes EC 0x5f repeatedly for 10s" >&2
		exit 1
	fi
	validate_speed "$2"
	speed_hex=$(printf '%02x' "$2")
	echo "== hold EC write FASP 0x5f=$2 for 10s =="
	for i in $(seq 1 100); do
		printf "\\x${speed_hex}" | dd of="$EC_IO" bs=1 seek=$((0x5f)) conv=notrunc 2>/dev/null
		if (( i % 10 == 0 )); then
			echo "== hold tick $((i / 10))s =="
			read_ec
			call_wmaa 'WMI get fan RPM 0x0d' '00fa000d00000000000000000000000000000000000000000000000000000000'
		fi
		sleep 0.1
	done
	echo '== after hold release =='
	for i in 1 2 3 4 5; do
		sleep 1
		echo "== after release ${i}s =="
		read_ec
		call_wmaa 'WMI get fan RPM 0x0d' '00fa000d00000000000000000000000000000000000000000000000000000000'
	done
fi
