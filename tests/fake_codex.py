import json
import os
import sys
import time
import uuid
from pathlib import Path

if '--exit=0' in sys.argv:
    sys.exit(0)

if 'resume' not in sys.argv:
    session = str(uuid.uuid5(uuid.NAMESPACE_URL, 'codex:' + os.getcwd()))
    directory = Path(os.environ['CODEX_HOME']) / 'sessions' / 'test'
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / (session + '.jsonl')).open('w') as output:
        output.write(json.dumps({'type': 'session_meta', 'payload': {'id': session, 'cwd': os.getcwd()}}) + '\n')
time.sleep(30)
