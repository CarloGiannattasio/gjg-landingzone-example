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
# Default: example-nonprod (Small VPC, flow logs off). CI passes each
# real-credential AWS config path and does not rely on that default.
# Optional second argument: gcp_config_path relative to the root module.
# When omitted, the root module default GCP project file is used.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG_PATH="${1:-../config/aws/example/example-nonprod/example-nonprod.json}"
GCP_CONFIG_PATH="${2:-}"
TF="${TERRAFORM_BIN:-terraform}"

if [[ ! -d "$ROOT/.venv" ]]; then
  python3 -m venv "$ROOT/.venv"
fi

"$ROOT/.venv/bin/python" -m pip install --disable-pip-version-check --quiet -r "$ROOT/requirements-dev.txt"

PORT_FILE="$(mktemp)"
GCP_PORT_FILE="$(mktemp)"
LOG_FILE="$(mktemp)"

cleanup() {
  if [[ -n "${MOTO_PID:-}" ]]; then
    kill "$MOTO_PID" 2>/dev/null || true
    wait "$MOTO_PID" 2>/dev/null || true
  fi
  if [[ -n "${GCP_PID:-}" ]]; then
    kill "$GCP_PID" 2>/dev/null || true
    wait "$GCP_PID" 2>/dev/null || true
  fi
  rm -f "$PORT_FILE" "$GCP_PORT_FILE"
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

# hashicorp/google has no single API host. compute_custom_endpoint is the
# Compute base path, which covers the VPC module. Dummy token, loopback only.
python3 - "$GCP_PORT_FILE" <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port_file = sys.argv[1]

class Handler(BaseHTTPRequestHandler):
    def _respond(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length:
            self.rfile.read(length)
        host = self.headers.get("Host", "")
        print(f"gcp-stub {self.command} host={host} path={self.path}", flush=True)
        if "googleapis.com" in host or "googleapis.com" in self.path:
            print("gcp-stub saw googleapis.com; this is not a local mock", flush=True)
            self.send_response(500)
        else:
            self.send_response(404)
        body = json.dumps({"error": {"code": 404, "message": "notFound", "status": "NOT_FOUND"}}).encode()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._respond()

    def do_POST(self):
        self._respond()

    def do_PUT(self):
        self._respond()

    def do_PATCH(self):
        self._respond()

    def do_DELETE(self):
        self._respond()

    def log_message(self, fmt, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(server.server_address[1]))
    handle.flush()
print(f"gcp-stub listening 127.0.0.1:{server.server_address[1]}", flush=True)
server.serve_forever()
PY
GCP_PID=$!

for _ in $(seq 1 30); do
  if [[ -s "$GCP_PORT_FILE" ]]; then
    break
  fi
  if ! kill -0 "$GCP_PID" 2>/dev/null; then
    echo "GCP stub exited before listening." >&2
    exit 1
  fi
  sleep 0.2
done

if [[ ! -s "$GCP_PORT_FILE" ]]; then
  echo "GCP stub did not report a port." >&2
  exit 1
fi

GCP_PORT="$(cat "$GCP_PORT_FILE")"
GCP_ENDPOINT="http://127.0.0.1:${GCP_PORT}/compute/v1/"

# Do not let Application Default Credentials send this plan to Google.
unset GOOGLE_APPLICATION_CREDENTIALS GOOGLE_CREDENTIALS GOOGLE_OAUTH_ACCESS_TOKEN \
  GOOGLE_CLOUD_KEYFILE_JSON CLOUDSDK_AUTH_ACCESS_TOKEN CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE

echo "Planning against Cloud Custodian's pinned Moto (${ENDPOINT}) and loopback Compute (${GCP_ENDPOINT})"
echo "config_path=${CONFIG_PATH}"
"$TF" -chdir=root init -backend=false -input=false -no-color
plan_args=(
  -chdir=root
  plan
  -input=false
  -no-color
  -var="config_path=${CONFIG_PATH}"
  -var="aws_endpoint_url=${ENDPOINT}"
  -var="gcp_endpoint_url=${GCP_ENDPOINT}"
)
if [[ -n "${GCP_CONFIG_PATH}" ]]; then
  echo "gcp_config_path=${GCP_CONFIG_PATH}"
  plan_args+=(-var="gcp_config_path=${GCP_CONFIG_PATH}")
fi
"$TF" "${plan_args[@]}"

rm -f "$LOG_FILE"
