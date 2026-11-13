import json
import os
import re
import sys
import time
import uuid
from pathlib import Path

if '--exit=0' in sys.argv:
    sys.exit(0)

prompt = sys.argv[-1]
marker = re.search(r'todo-agent-task:([\w-]+)', prompt)
if marker and '--no-transcript' not in sys.argv:
    session = str(uuid.uuid5(uuid.NAMESPACE_URL, 'codex:' + marker.group(1)))
    directory = Path(os.environ['CODEX_HOME']) / 'sessions' / 'test'
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / (session + '.jsonl')).open('w') as output:
        output.write(json.dumps({'type': 'session_meta', 'payload': {'id': session}}) + '\n')
        output.write(json.dumps({'type': 'event_msg', 'payload': {'message': prompt}}) + '\n')
time.sleep(30)
