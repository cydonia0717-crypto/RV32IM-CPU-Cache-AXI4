#!/usr/bin/env python3
"""Convert a little-endian binary to full 64KB word-addressed readmemh image."""
import sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
if len(b)>65536: raise SystemExit('image exceeds 64KB')
b=b.ljust(65536,b'\0')
Path(sys.argv[2]).write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
