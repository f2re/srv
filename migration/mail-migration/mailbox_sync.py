#!/usr/bin/env python3
"""Run repeatable mailbox migrations with imapsync from a CSV manifest.

Passwords are read from separate 0600 files and are never stored in the CSV.
The default is a dry run. Use --apply only after reviewing the generated
commands and validating one pilot mailbox.
"""

import argparse
import csv
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


def validate_secret_file(path):
    p = Path(path).expanduser().resolve()
    if not p.is_file():
        raise RuntimeError("Password file does not exist: {}".format(p))
    mode = p.stat().st_mode & 0o777
    if mode & 0o077:
        raise RuntimeError("Password file must not be group/world-readable: {} mode={:o}".format(p, mode))
    if not p.read_text(encoding="utf-8").splitlines():
        raise RuntimeError("Password file is empty: {}".format(p))
    return p


def security_args(side, mode):
    mode = (mode or "ssl").lower()
    if mode == "ssl":
        return ["--ssl" + side]
    if mode in ("starttls", "tls"):
        return ["--tls" + side]
    if mode == "plain":
        return []
    raise RuntimeError("Unsupported security mode: {}".format(mode))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_file")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--mailbox", action="append", help="Only migrate selected target mailbox")
    ap.add_argument("--log-dir", default="./imapsync-logs")
    args = ap.parse_args()

    binary = shutil.which("imapsync")
    if not binary:
        raise SystemExit("imapsync is not installed")
    log_dir = Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    selected = set(args.mailbox or [])

    with open(args.csv_file, newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise SystemExit("CSV contains no mailboxes")

    failures = 0
    for row in rows:
        target_user = row["target_user"].strip()
        if selected and target_user not in selected:
            continue
        pass1 = validate_secret_file(row["source_password_file"])
        pass2 = validate_secret_file(row["target_password_file"])
        safe_name = "".join(c if c.isalnum() or c in "._-" else "_" for c in target_user)
        logfile = log_dir / (safe_name + ".log")
        cmd = [
            binary,
            "--host1", row["source_host"], "--port1", row["source_port"],
            "--user1", row["source_user"], "--passfile1", str(pass1),
            "--host2", row["target_host"], "--port2", row["target_port"],
            "--user2", target_user, "--passfile2", str(pass2),
            "--automap", "--syncinternaldates", "--nofoldersizes",
            "--logfile", str(logfile),
        ]
        cmd += security_args("1", row.get("source_security"))
        cmd += security_args("2", row.get("target_security"))
        extra = row.get("extra_args", "").strip()
        if extra:
            extra_tokens = shlex.split(extra)
            forbidden = {
                "--password1", "--password2", "--passfile1", "--passfile2",
                "--host1", "--host2", "--port1", "--port2", "--user1", "--user2",
            }
            if any(token.split("=", 1)[0] in forbidden for token in extra_tokens):
                raise RuntimeError("extra_args must not override hosts, users, ports or credentials")
            cmd += extra_tokens
        if not args.apply:
            cmd.append("--dry")
        print("+", " ".join(shlex.quote(x) for x in cmd), flush=True)
        proc = subprocess.run(cmd)
        if proc.returncode != 0:
            failures += 1
            print("FAILED:", target_user, "see", logfile, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
