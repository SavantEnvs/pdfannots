#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the pdfannots behavioral oracle that mayhem/build.sh produced.
#
# It runs the known-answer self-test via the /mayhem/pdfannots_oracle launcher (a NON-system ELF, so
# the verify-repo §6.3 sabotage neuter can trip it) and asserts that pdfannots parsed real PDFs from
# the upstream test corpus to specific annotation values. A no-op / exit(0) PATCH FAILS this (the
# expected SELFTEST_PASS marker + values are absent). Emits a CTRF (https://ctrf.io) summary. It
# never builds.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

ORACLE="$SRC/pdfannots_oracle"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x "$ORACLE" ]; then
  echo "FAIL: $ORACLE missing — mayhem/build.sh did not build the oracle launcher" >&2
  emit_ctrf "pdfannots-knownanswer" 0 1
  exit 1
fi

# The oracle asserts behavior internally and prints a marker carrying the asserted values ONLY when
# every assertion holds; any failure (or a neutered binary) yields no marker.
out="$("$ORACLE" 2>&1)"; rc=$?
echo "$out"

passed=0; failed=0
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "SELFTEST_PASS issue9='World'"; then
  passed=1
else
  failed=1
  echo "FAIL: pdfannots oracle did not assert the expected behavior (rc=$rc)" >&2
fi

# The oracle uses real file handles, so it cannot see a harness that breaks on its own seed. Replay the
# seed and a malformed input through the actual fuzz target ELF (BytesIO path): the seed must parse
# (exit 0) and malformed input must be rejected quietly, not reported as a crash.
HARNESS="$SRC/fuzz_pdf"
SEED="$SRC/mayhem/annot-fuzz/testsuite/issue9.pdf"
if [ -x "$HARNESS" ] && [ -f "$SEED" ]; then
  if "$HARNESS" "$SEED" >/tmp/harness-seed.log 2>&1; then
    echo "harness replays issue9.pdf: ok"
  else
    failed=$((failed + 1)); passed=0
    echo "FAIL: fuzz_pdf crashed on its own seed issue9.pdf" >&2; tail -20 /tmp/harness-seed.log >&2
  fi
  printf '%s\n' '%PDF-1.4' '1 0 obj' '<< /Type /Catalog /X << /A >> >>' 'endobj' 'trailer' '<< /Root 1 0 R >>' '%%EOF' > /tmp/malformed.pdf
  if "$HARNESS" /tmp/malformed.pdf >/tmp/harness-bad.log 2>&1; then
    echo "harness rejects malformed pdf quietly: ok"
  else
    failed=$((failed + 1)); passed=0
    echo "FAIL: fuzz_pdf reports malformed input as a crash" >&2; tail -20 /tmp/harness-bad.log >&2
  fi
else
  failed=$((failed + 1)); passed=0
  echo "FAIL: $HARNESS or $SEED missing" >&2
fi

emit_ctrf "pdfannots-knownanswer" "$passed" "$failed"
