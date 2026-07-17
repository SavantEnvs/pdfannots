#!/usr/bin/env python3
import io
import atheris
import sys


class NamedBytesIO(io.BytesIO):
    # process_file reports progress via file.name, which a real file object has and BytesIO lacks.
    name = "fuzz.pdf"

# Instrument pdfannots and all of pdfminer (parser, document, interpreter, layout) so coverage feedback
# reaches the annotation/layout code; only the large static data tables are left out.
with atheris.instrument_imports(exclude=["pdfminer.glyphlist", "pdfminer.latin_enc", "pdfminer.fontmetrics"]):
    # Imported here, not at module top: anything pdfminer-related imported earlier is cached uninstrumented.
    import pdfannots
    from pdfminer.pdfparser import PDFSyntaxError
    from pdfminer.pdftypes import PDFException
    from pdfminer.psparser import PSException

# Library-defined rejections of malformed input: expected, not findings.
EXPECTED = (PSException, PDFException, PDFSyntaxError)

@atheris.instrument_func
def TestOneInput(data):
    if not data:
        return -1
    try:
        with NamedBytesIO(data) as f:
            pdfannots.process_file(f)
    except EXPECTED:
        pass
def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()

if __name__ == '__main__':
    main()
