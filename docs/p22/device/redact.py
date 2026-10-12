#!/usr/bin/env python3
"""Remove credential-bearing query parameters before saving/sharing QA logs."""
import argparse
import pathlib
import re

def redact(s):
    return re.sub(r'(?i)(access_token|id_token|refresh_token|serverAuthCode|client_secret)=([^&\s]+)',
                  r'\1=<REDACTED>', s)

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('path'); p.add_argument('--tail',type=int); p.add_argument('--write',action='store_true')
    a=p.parse_args(); path=pathlib.Path(a.path)
    s=redact(path.read_text(errors='replace'))
    if a.write: path.write_text(s)
    elif a.tail: print('\n'.join(s.splitlines()[-a.tail:]))
    else: print(s)
