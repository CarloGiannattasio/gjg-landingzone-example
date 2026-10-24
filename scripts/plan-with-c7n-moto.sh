#!/usr/bin/env bash
# Plan the landing zone against the Moto release Cloud Custodian pins.
#
# There is no Cloud Custodian package, image, or file named moto3. c7n's
# dev group pins moto>=5.0,<6.0 and uv.lock resolves moto==5.2.3. Tests
# call moto.mock_aws, which only intercepts boto3 inside the process.
# Terraform needs an HTTP endpoint, so this script serves that same pinned
# library with moto.server.ThreadedMotoServer.
#
# Does not run terraform apply.
# Optional first argument: config_path relative to the root module.
# Default: example-nonprod (Small VPC, flow logs off).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG_PATH="${1:-../config/aws/example/example-nonprod/example-nonprod.json}"
TF="${TERRAFORM_BIN:-terraform}"

if [[ ! -d "$ROOT/.venv" ]]; then
  python3 -m venv "$ROOT/.venv"
fi

"$ROOT/.venv/bin/python" -m pip install --disable-pip-version-check --quiet -r "$ROOT/requirements-dev.txt"

PORT_FILE="$(mktemp)"
LOG_FILE="$(mktemp)"

cleanup() {
  if [[ -n "${MOTO_PID:-}" ]]; then
    kill "$MOTO_PID" 2>/dev/null || true
    wait "$MOTO_PID" 2>/dev/null || true
  fi
  rm -f "$PORT_FILE"
}
trap cleanup EXIT

# First import of moto is slow. The process prints before that import so a
# hang is visible, then binds port 0 and records the real port.
"$ROOT/.venv/bin/python" - "$PORT_FILE" <<'PY' >"$LOG_FILE" 2>&1 &
import sys
import time

print("importing moto", flush=True)
from moto.server import ThreadedMotoServer

port_file = sys.argv[1]
server = ThreadedMotoServer(ip_address="127.0.0.1", port=0, verbose=False)
server.start()
_host, port = server.get_host_and_port()
with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(port))
    handle.flush()
print(f"listening 127.0.0.1:{port}", flush=True)

try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    server.stop()
PY
MOTO_PID=$!

for _ in $(seq 1 120); do
  if [[ -s "$PORT_FILE" ]]; then
    break
  fi
  if ! kill -0 "$MOTO_PID" 2>/dev/null; then
    echo "Moto server exited before listening. Log:" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
done

if [[ ! -s "$PORT_FILE" ]]; then
  echo "Moto server did not report a port. Log:" >&2
  cat "$LOG_FILE" >&2
  exit 1
fi

PORT="$(cat "$PORT_FILE")"
ENDPOINT="http://127.0.0.1:${PORT}"

python3 - "$PORT" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
for _ in range(50):
    sock = socket.socket()
    sock.settimeout(0.2)
    try:
        sock.connect(("127.0.0.1", port))
    except OSError:
        time.sleep(0.1)
        continue
    else:
        sock.close()
        sys.exit(0)
    finally:
        sock.close()
print(f"127.0.0.1:{port} did not accept connections", file=sys.stderr)
sys.exit(1)
PY

echo "Planning against Cloud Custodian's pinned Moto (${ENDPOINT})"
"$TF" -chdir=root init -backend=false -input=false -no-color
"$TF" -chdir=root plan -input=false -no-color \
  -var="config_path=${CONFIG_PATH}" \
  -var="aws_endpoint_url=${ENDPOINT}"

rm -f "$LOG_FILE"
