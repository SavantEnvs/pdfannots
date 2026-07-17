#!/usr/bin/env bash
#
# mayhem/build.sh — build the pdfannots Atheris fuzz harness (Python).
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The org base image
# (ghcr.io/mayhemheroes/base) exports the build contract (CC, SANITIZER_FLAGS, DEBUG_FLAGS, SRC, …)
# and ships python3 + pip + clang/llvm.
#
# pdfannots is fuzzed with Google's Atheris (a coverage-guided Python fuzzer that emulates the
# libFuzzer CLI), so the harness is a Python script. Mayhem requires the target `cmd` to be an ELF
# (it rejects script/wrapper targets), so we build a thin ELF LAUNCHER that execs `python3 <harness>`,
# forwarding all libFuzzer args. exec() replaces the process image, so the running process IS the
# Atheris/libFuzzer harness — transparent to Mayhem.
#
# Air-gapped (SPEC §6.5): the first (online) run bakes a wheelhouse (the pdfannots wheel + all its
# deps — pdfminer.six — + atheris); the offline PATCH re-run installs from it with --no-index, never
# reaching PyPI.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENVIRONMENT (overridable) with sane defaults. SANITIZER_FLAGS is referenced
# for contract parity; it does NOT apply to the fuzzed code here — Atheris instruments the *Python*
# bytecode at runtime (no compiled project to sanitize). `=` (not `:=`) honors an explicit empty
# --build-arg. DEBUG_FLAGS carries DWARF (< 4) onto the ELF launchers so Mayhem's triage can read
# them; clang-19's plain -g emits DWARF-5, hence the explicit -gdwarf-3.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${SRC:=/mayhem}"
: "${MAYHEM_JOBS:=$(nproc)}"
# Python packages install under /opt/toolchains/python (SPEC §6.2 item 8), never ~/.local: $HOME moves
# with the identity that runs the harness. The Dockerfile pins the same value as ENV.
: "${PYTHONUSERBASE:=/opt/toolchains/python}"
export SANITIZER_FLAGS DEBUG_FLAGS CC SRC MAYHEM_JOBS PYTHONUSERBASE

cd "$SRC"
HARNESS_DIR="$SRC/mayhem"
WHEELHOUSE="$HARNESS_DIR/wheelhouse"
PIP="python3 -m pip"

# 1) Python deps — air-gapped via a baked wheelhouse. First (online) run builds the pdfannots wheel
#    from the in-tree source + downloads every runtime dep (pdfminer.six) and atheris into the
#    wheelhouse; the offline re-run reuses it. A pinned atheris keeps the engine stable across rebuilds.
mkdir -p "$WHEELHOUSE"
if [ ! -f "$WHEELHOUSE/.populated" ]; then
  $PIP wheel --wheel-dir "$WHEELHOUSE" "$SRC" "atheris==3.1.0"
  touch "$WHEELHOUSE/.populated"
fi
# Install offline from the wheelhouse (idempotent: a satisfied requirement is a no-op, no network).
$PIP install --no-index --find-links "$WHEELHOUSE" --user --break-system-packages \
  pdfannots "atheris==3.1.0"

# 2) Build the ELF launcher (Mayhem target). A tiny clang-compiled shim (ELF + DWARF<4 via
#    $DEBUG_FLAGS) that exec()s python3 on the baked-in harness. Sanitizing a 30-line exec shim is
#    pointless (it would drag the ASan runtime into the python child), so the launcher is built
#    WITHOUT $SANITIZER_FLAGS but WITH $DEBUG_FLAGS. The Python code is instrumented by Atheris.
$CC $DEBUG_FLAGS -O1 \
    -DSCRIPT_PATH="\"$HARNESS_DIR/fuzz_pdf.py\"" \
    "$HARNESS_DIR/launcher.c" -o "$SRC/fuzz_pdf"
# Standalone run-once reproducer (Atheris replays a single file argument).
cp -f "$SRC/fuzz_pdf" "$SRC/fuzz_pdf-standalone"

# 3) Build the ELF launcher for the behavioral oracle (test.sh runs this — a /mayhem-rooted ELF so
#    the anti-reward-hack sabotage check can neuter it).
$CC $DEBUG_FLAGS -O1 \
    -DORACLE_PATH="\"$HARNESS_DIR/oracle.py\"" \
    "$HARNESS_DIR/oracle_launch.c" -o "$SRC/pdfannots_oracle"

# 4) Fail the build early if the harnessed API drifted (atheris + the package must import cleanly,
#    and the fuzzed entrypoint must exist).
python3 -c "import atheris, pdfannots; from pdfminer.pdfparser import PDFSyntaxError; assert callable(pdfannots.process_file)"

echo ">> build.sh done: $SRC/fuzz_pdf (Mayhem target), $SRC/pdfannots_oracle (oracle)"
