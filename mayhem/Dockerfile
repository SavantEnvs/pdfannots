# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) for 0xabu/pdfannots (Python / Atheris), built ON TOP of the
# org base image (ghcr.io/mayhemheroes/base), which provides debian + clang/llvm + python3 + pip +
# the non-root identities + the build-contract ENV.
#
# mayhem/build.sh bakes a wheelhouse (online, once) — the pdfannots wheel built from the in-tree
# source, all its runtime deps (pdfminer.six), and atheris — then installs from it with --no-index,
# so the air-gapped PATCH re-run (docker run --network none ... bash mayhem/build.sh) never reaches
# PyPI (SPEC §6.5). It then compiles the thin ELF launcher target (Mayhem requires an ELF target).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t pdfannots-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never baked as ENV — an empty value breaks
# clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Sanitizer override knob (declared WITHOUT a default so an unset arg lets the base ENV flow through).
ARG SANITIZER_FLAGS
# Build parallelism (optional; build.sh falls back to nproc).
ARG MAYHEM_JOBS=

# Python packages (atheris + pdfannots + deps) live under /opt/toolchains/python, pinned via
# $HOME-independent ENV (SPEC §6.2 item 8): pip's user site resolves from PYTHONUSERBASE, so every
# identity/$HOME that runs the harness (Mayhem, triage, the PATCH re-run) finds the same packages.
# Root creates it world-readable and hands the write side to mayhem (2000) so build.sh can refresh it.
ENV PYTHONUSERBASE=/opt/toolchains/python
USER root
RUN install -d -m 0755 -o 2000 -g 2000 /opt/toolchains/python

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git history) is
# copied to /mayhem as `mayhem`; build.sh builds in place and installs python deps to $PYTHONUSERBASE.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run the behavioral oracle at build time — a failing suite fails the image build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
