#!/bin/sh

set -eu

pickme_version_file="${SRCROOT}/Configuration/Versioning.xcconfig"

if [ ! -f "${pickme_version_file}" ]; then
  echo "error: Versioning.xcconfig was not found at ${pickme_version_file}" >&2
  exit 1
fi

pickme_current_build="$(sed -n 's/^[[:space:]]*APP_BUILD_NUMBER[[:space:]]*=[[:space:]]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "${pickme_version_file}")"

case "${pickme_current_build}" in
  ''|*[!0-9]*)
    echo "error: APP_BUILD_NUMBER must appear exactly once and contain a positive integer" >&2
    exit 1
    ;;
esac

pickme_match_count="$(grep -Ec '^[[:space:]]*APP_BUILD_NUMBER[[:space:]]*=' "${pickme_version_file}")"
if [ "${pickme_match_count}" -ne 1 ]; then
  echo "error: APP_BUILD_NUMBER must appear exactly once in ${pickme_version_file}" >&2
  exit 1
fi

pickme_next_build=$((pickme_current_build + 1))
pickme_temp_file="$(mktemp "${TMPDIR:-/tmp}/pickme-versioning.XXXXXX")"
trap 'rm -f "${pickme_temp_file}"' EXIT HUP INT TERM

awk -v next_build="${pickme_next_build}" '
  /^[[:space:]]*APP_BUILD_NUMBER[[:space:]]*=/ {
    print "APP_BUILD_NUMBER = " next_build
    next
  }
  { print }
' "${pickme_version_file}" > "${pickme_temp_file}"

chmod 644 "${pickme_temp_file}"
mv "${pickme_temp_file}" "${pickme_version_file}"
trap - EXIT HUP INT TERM

echo "Incremented PickMe build number: ${pickme_current_build} -> ${pickme_next_build}"
