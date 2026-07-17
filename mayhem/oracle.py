#!/usr/bin/env python3
"""Behavioral oracle (known-answer test) for pdfannots.

Exercises the SAME parsing pipeline the fuzzer drives — pdfannots.process_file() over a real PDF ->
Document -> Page.annots -> Annotation.subtype/gettext() — and ASSERTS specific extracted annotation
values against the upstream test corpus (tests/issue9.pdf, tests/issue46.pdf). A no-op / neutered
program (which prints nothing) FAILS test.sh, because the SELFTEST_PASS marker and its asserted
values are only printed when every assertion holds.
"""
import pathlib

import pdfannots
from pdfannots.types import AnnotationType

# Resolve the upstream test corpus relative to this file: oracle.py lives at <repo>/mayhem/oracle.py,
# so the PDFs are at <repo>/tests/*.pdf (the whole repo is COPYed to /mayhem in the commit image).
TESTS = pathlib.Path(__file__).resolve().parent.parent / "tests"


def extract(filename):
    with (TESTS / filename).open("rb") as f:
        doc = pdfannots.process_file(f)
    return [a for p in doc.pages for a in p.annots]


# 1) issue9.pdf — exactly one annotation whose highlighted text is "World".
a9 = extract("issue9.pdf")
assert len(a9) == 1, len(a9)
assert a9[0].gettext() == "World", a9[0].gettext()

# 2) issue46.pdf — three annotations with known subtypes and text.
a46 = extract("issue46.pdf")
assert len(a46) == 3, len(a46)
assert a46[0].subtype == AnnotationType.Highlight, a46[0].subtype
assert a46[0].gettext() == "C – Curate", a46[0].gettext()
assert a46[1].subtype == AnnotationType.Square, a46[1].subtype
assert a46[1].gettext() is None, a46[1].gettext()
assert a46[2].subtype == AnnotationType.Highlight, a46[2].subtype
assert a46[2].gettext() == "This was a novel idea at the time", a46[2].gettext()

# 3) Reject clearly non-PDF input: process_file must raise, not silently "succeed".
import io
try:
    pdfannots.process_file(io.BytesIO(b"this is definitely not a pdf file\n"))
    raise SystemExit("BUG: non-PDF input was accepted by process_file")
except SystemExit:
    raise
except Exception:
    pass

print(
    "SELFTEST_PASS issue9=%r issue46_0=%r issue46_2=%r"
    % (a9[0].gettext(), a46[0].gettext(), a46[2].gettext())
)
