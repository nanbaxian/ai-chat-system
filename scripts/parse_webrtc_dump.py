#!/usr/bin/env python3
"\"\"\"Extract candidate-pair and transport summaries from a WebRTC internals dump.\"\"\"
import argparse
import gzip
import json


def parse_dump(path):
    with gzip.open(path, 'rt', errors='ignore') as f:
        data = json.load(f)
    pcs = data.get("PeerConnections", {})
    pairs = []
    transports = []
    for pc_id, pc in pcs.items():
        stats = pc.get("stats", {})
        for key, body in stats.items():
            if key.startswith("candidate-pair"):
                state = json.loads(body["values"])[-1]
                pairs.append((key, state))
            if key.startswith("transport"):
                transports.append((key, json.loads(body["values"])[-1]))
    return pairs, transports


def main():
    parser = argparse.ArgumentParser(description="Summarize candidate-pair/transport states")
    parser.add_argument("dump", help="Path to a webrtc_internals_dump*.gz file")
    args = parser.parse_args()
    pairs, transports = parse_dump(args.dump)
    print("Candidate-pair states:")
    for name, state in pairs:
        print(f"  {name}: {state}")
    print("\nTransport states:")
    for name, state in transports:
        print(f"  {name}: {state}")


if __name__ == "__main__":
    main()
