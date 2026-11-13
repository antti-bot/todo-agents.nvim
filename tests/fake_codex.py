"""A persistent test process that reports itself through Herdr's public API."""
import json
import os
import subprocess
import sys
import time

with open(os.environ['TODO_TEST_LAUNCHES'], 'a') as output:
    output.write(json.dumps({'cwd': os.getcwd(), 'argv': sys.argv[1:], 'pane': os.environ['HERDR_PANE_ID']}) + '\n')
subprocess.run([
    os.environ['HERDR_BIN_PATH'], 'pane', 'report-agent', os.environ['HERDR_PANE_ID'],
    '--source', 'todo-test', '--agent', 'codex', '--state', 'idle',
], check=True)
print('Test agent ready', flush=True)
while True:
    time.sleep(1)
