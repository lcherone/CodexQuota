#!/usr/bin/env python3
"""Prepare an isolated app bundle and offline sample data for README captures."""

import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile


def iso(value):
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def serve(payload_path):
    payload = json.loads(Path(payload_path).read_text())
    account = "work" if Path(os.environ.get("CODEX_HOME", "")).name == "work" else "personal"
    profile = payload[account]
    sys.stdout.reconfigure(line_buffering=True)
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:
            continue
        method = request.get("method")
        params = request.get("params") or {}
        result = None
        if method == "initialize":
            result = {"userAgent": "Codex Quota offline demo", "codexHome": os.environ.get("CODEX_HOME", "")}
        elif method == "account/read":
            result = {"account": {"type": "chatgpt", "email": profile["email"], "planType": "plus"}, "requiresOpenaiAuth": False}
        elif method == "account/rateLimits/read":
            result = profile["limits"]
        elif method == "account/usage/read":
            result = payload["conversationUsage"] if params.get("threadId") else payload["usage"]
            if params.get("threadId"):
                result["threadUsage"]["threadId"] = params["threadId"]
        elif method == "thread/list":
            titles = ["Polish the settings panel", "Review the release checklist", "Make the daily chart clearer"]
            rows = [
                {"id": f"01900000-0000-7000-8000-{index + 1:012d}",
                 "name": ("Archived · " if params.get("archived") else "") + title,
                 "updatedAt": payload["timestamp"] - index * 3600, "modelProvider": "openai", "cwd": "/demo/projects/quota"}
                for index, title in enumerate(titles)
            ]
            result = {"data": rows, "nextCursor": None}
        elif method == "account/workspaceMessages/read":
            result = {"featureEnabled": True, "messages": [
                {"messageId": "demo-notice", "messageType": "headline", "messageBody": "A little room for the next idea. Your team’s weekly allowance has refreshed.",
                 "createdAt": payload["timestamp"] - 3600, "archivedAt": None}
            ]}
        elif method == "account/logout":
            result = {}
        response = {"id": request["id"], "result": result}
        if result is None:
            response = {"id": request["id"], "error": {"code": -32601, "message": "Unavailable in the offline README demo"}}
        print(json.dumps(response), flush=True)


def prepare():
    root = Path(__file__).resolve().parent.parent
    built = root / "build/CodexQuota.app"
    if not built.is_dir():
        raise SystemExit("Build the app first with ./scripts/build-app.sh")
    destination = Path(tempfile.mkdtemp(prefix="codexquota-readme-"))
    library = destination / "library"
    library.mkdir(mode=0o700)
    now = datetime.now(timezone.utc)
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    reset = midnight + timedelta(days=3)
    start = reset - timedelta(days=7)
    daily = [184000, 362000, 278000, 521000, 437000, 624000, 198000, 750000, 485000, 912000, 543000, 678000, 1104000, 826000]
    buckets = [{"startDate": (midnight - timedelta(days=13 - index)).strftime("%Y-%m-%d"), "tokens": tokens} for index, tokens in enumerate(daily)]
    usage = {"summary": {"lifetimeTokens": 12480000, "peakDailyTokens": 1104000, "longestRunningTurnSec": 7322, "currentStreakDays": 4, "longestStreakDays": 19}, "dailyUsageBuckets": buckets}
    payload = {"timestamp": int(now.timestamp()), "usage": usage, "conversationUsage": {
        "summary": {}, "dailyUsageBuckets": None, "threadUsage": {
            "estimatedUsageCreditsMicros": 1250000, "estimatedUsageUsdMicros": 320000,
            "groups": [{"model": "example-model", "reasoningEffort": "high", "speed": "standard", "estimatedUsageCreditsMicros": 1250000,
                        "netNewInputTokens": 12400, "cachedInputTokens": 42600, "inputTokens": 55000, "outputTokens": 8200, "totalTokens": 63200}]}}}
    accounts = []
    samples = []
    for account, label, email, used, values in [
        ("personal", "Personal", "person@example.com", 62, [0, 8, 18, 32, 55]),
        ("work", "Work", "team@example.com", 34, [0, 5, 12, 21, 30]),
    ]:
        home = library / "homes" / account
        home.mkdir(parents=True, mode=0o700)
        accounts.append({"id": account, "label": label, "codexHome": str(home), "createdAt": iso(now - timedelta(days=30))})
        primary = {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": int((now + timedelta(hours=2)).timestamp())}
        secondary = {"usedPercent": used, "windowDurationMins": 10080, "resetsAt": int(reset.timestamp())}
        bucket = {"limitId": "codex", "limitName": "Codex", "planType": "plus", "primary": primary, "secondary": secondary,
                  "credits": {"hasCredits": True, "unlimited": False, "balance": "12.50"},
                  "individualLimit": {"limit": "100", "used": "20", "remainingPercent": 80, "resetsAt": int(reset.timestamp())}, "spendControlReached": False}
        payload[account] = {"email": email, "limits": {"rateLimits": bucket, "rateLimitsByLimitId": {"codex": bucket},
            "rateLimitResetCredits": {"availableCount": 1, "credits": [{"id": "demo-reset", "resetType": "codexRateLimits", "status": "available", "title": "Full quota reset",
                "description": "A sample earned reset. Displayed for reference; this app does not redeem resets.", "grantedAt": int((now - timedelta(days=2)).timestamp()), "expiresAt": int((now + timedelta(days=28)).timestamp())}]}}}
        def sample(checked, percent, reset_at):
            return {"accountId": account, "sampledAt": iso(checked), "email": email, "planType": "plus", "limitId": "codex", "limitName": "Codex",
                    "usedPercent": percent, "windowDurationMins": 10080, "resetsAt": iso(reset_at), "dailyBuckets": buckets,
                    "lifetimeTokens": 12480000, "peakDailyTokens": 1104000, "longestRunningTurnSec": 7322, "currentStreakDays": 4, "longestStreakDays": 19,
                    "optionalStatisticsSampledAt": iso(now), "optionalStatisticsArePartial": False}
        for weeks_ago, percent in [(2, 48), (1, 81)]:
            ended = reset - timedelta(days=7 * weeks_ago)
            samples.append(sample(ended - timedelta(seconds=5), percent, ended))
        for index, percent in enumerate(values):
            samples.append(sample(start + timedelta(days=index) - timedelta(seconds=1), percent, reset))
        samples.append(sample(now - timedelta(seconds=1), used, reset))
    store = {"version": 1, "selectedAccountId": "personal", "accounts": accounts, "samples": samples, "appearance": "light", "alertPreferences": {"enabled": False, "weeklyThreshold": 80}, "alertReceipts": []}
    (library / "store.json").write_text(json.dumps(store))
    (library / "store.json").chmod(0o600)
    payload_path = destination / "responses.json"
    payload_path.write_text(json.dumps(payload))
    server = destination / "offline-codex"
    server.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(str(value)) for value in [sys.executable, Path(__file__).resolve(), "--serve", payload_path]) + "\n")
    server.chmod(0o700)
    app = destination / "Codex Quota Demo.app"
    shutil.copytree(built, app)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier="dev.codexquota.ReadmeDemo", CFBundleName="Codex Quota Demo", CFBundleDisplayName="Codex Quota Demo", CFBundleExecutable="ReadmeDemoLauncher")
    info_path.write_bytes(plistlib.dumps(info))
    executable = app / "Contents/MacOS/CodexQuota"
    launcher = app / "Contents/MacOS/ReadmeDemoLauncher"
    launcher.write_text(f"#!/bin/sh\nexport CODEX_QUOTA_DIR={shlex.quote(str(library))}\nexport CODEX_BIN={shlex.quote(str(server))}\nexec {shlex.quote(str(executable))} \"$@\"\n")
    launcher.chmod(0o700)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    print(json.dumps({"app": str(app), "directory": str(destination), "library": str(library)}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serve", metavar="RESPONSES", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    if arguments.serve:
        serve(arguments.serve)
    else:
        prepare()
