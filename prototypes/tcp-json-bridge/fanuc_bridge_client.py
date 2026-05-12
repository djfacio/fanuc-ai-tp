import argparse
import json
import socket
import sys
import uuid


def main() -> int:
    parser = argparse.ArgumentParser(description="Send one JSON-lines request to a FANUC bridge service.")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--type", default="ping", dest="request_type")
    parser.add_argument("--timeout", default=5.0, type=float)
    parser.add_argument("--payload", default="{}", help="JSON object payload")
    args = parser.parse_args()

    try:
        payload = json.loads(args.payload)
    except json.JSONDecodeError as exc:
        print(f"Invalid payload JSON: {exc}", file=sys.stderr)
        return 2

    if not isinstance(payload, dict):
        print("Payload must be a JSON object.", file=sys.stderr)
        return 2

    request = {
        "id": str(uuid.uuid4()),
        "type": args.request_type,
        "payload": payload,
    }

    with socket.create_connection((args.host, args.port), timeout=args.timeout) as sock:
        sock.settimeout(args.timeout)
        sock.sendall((json.dumps(request, separators=(",", ":")) + "\n").encode("ascii"))
        response = _read_line(sock)

    print(response)
    return 0


def _read_line(sock: socket.socket) -> str:
    chunks = []
    while True:
        data = sock.recv(1)
        if not data:
            break
        if data == b"\n":
            break
        chunks.append(data)
    return b"".join(chunks).decode("ascii", errors="replace")


if __name__ == "__main__":
    raise SystemExit(main())
