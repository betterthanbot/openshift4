"""Print a `kubectl patch` body that swaps LANGFLOW_SECRET_KEY inside a dotenv Secret.

stdin: the Secret as JSON (`oc get secret <name> -o json`); env NEW: the replacement key.
Used by `make rotate-langflow-key`; see the Makefile for why the key has to be a Fernet key.
"""
import base64
import json
import os
import re
import sys

secret = json.load(sys.stdin)
env = base64.b64decode(secret["data"][".env"]).decode()
new, n = re.subn(
    r"(?m)^(\s*LANGFLOW_SECRET_KEY=).*$",
    lambda m: m.group(1) + '"' + os.environ["NEW"] + '"',
    env,
)
if n != 1:
    sys.exit(f"expected exactly one LANGFLOW_SECRET_KEY line, found {n}")
json.dump({"stringData": {".env": new}}, sys.stdout)
