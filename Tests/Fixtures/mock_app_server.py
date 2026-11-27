#!/usr/bin/env python3
"""Local stand-in for Codex app-server. It never opens a network connection."""

import json
import os
import sys

sys.stdout.reconfigure(line_buffering=True)

MODE = os.environ.get("CODEX_QUOTA_MOCK", "quota")
PID_FILE = os.environ.get("CODEX_QUOTA_MOCK_PID_FILE")
LOGIN_FILE = os.environ.get("CODEX_QUOTA_MOCK_LOGIN_FILE")
login_started = False
initialized = False

if PID_FILE:
    with open(PID_FILE, "w", encoding="utf-8") as output:
        output.write(str(os.getpid()))

LIMITS = {
    "rateLimits": {
        "limitId": "codex",
        "limitName": "Codex",
        "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1800000000},
        "secondary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1800000000},
        "planType": "plus",
        "rateLimitReachedType": None,
    },
    "rateLimitsByLimitId": {
        "codex": {
            "limitId": "codex",
            "limitName": "Codex",
            "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1800000000},
            "secondary": {"usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1800000000},
            "planType": "plus",
            "rateLimitReachedType": None,
        }
    },
    "rateLimitResetCredits": None,
}

USAGE = {
    "summary": {
        "lifetimeTokens": 123456,
        "peakDailyTokens": 999,
        "longestRunningTurnSec": 7322,
        "currentStreakDays": 4,
        "longestStreakDays": 19,
    },
    "dailyUsageBuckets": [{"startDate": "2026-11-24", "tokens": 700}],
}


def send(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def account_body():
    if MODE == "login-held":
        return {"account": None, "requiresOpenaiAuth": True}
    if MODE == "login" and not login_started:
        return {"account": None, "requiresOpenaiAuth": True}
    return {
        "account": {"type": "chatgpt", "email": "person@example.com", "planType": "plus"},
        "requiresOpenaiAuth": False,
    }


for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue
    message = json.loads(line)
    method = message.get("method")
    request_id = message.get("id")
    if method == "initialized":
        initialized = True
        continue
    if request_id is None:
        continue
    if method == "initialize":
        capabilities = (message.get("params") or {}).get("capabilities") or {}
        if capabilities.get("experimentalApi") is not True:
            send({"id": request_id, "error": {"code": -32602, "message": "experimentalApi"}})
            continue
        send({"id": request_id, "result": {"codexHome": os.environ.get("CODEX_HOME", ""), "userAgent": "mock"}})
        continue
    if not initialized:
        send({"id": request_id, "error": {"code": -32600, "message": "initialize"}})
        continue
    if method == "account/login/start":
        login_started = True
        if LOGIN_FILE:
            with open(LOGIN_FILE, "w", encoding="utf-8") as output:
                output.write("started")
        send({
            "id": request_id,
            "result": {"type": "chatgpt", "loginId": "login-1", "authUrl": "https://example.test/login"},
        })
    elif method == "account/read":
        send({"id": request_id, "result": account_body()})
    elif method == "account/rateLimits/read":
        send({"id": request_id, "result": LIMITS})
    elif method == "account/usage/read":
        if MODE == "usage-failure":
            send({"id": request_id, "error": {"code": -32000, "message": "usage unavailable"}})
        else:
            send({"id": request_id, "result": USAGE})
    elif method == "account/logout":
        login_started = False
        send({"id": request_id, "result": {}})
    else:
        send({"id": request_id, "error": {"code": -32601, "message": method or "unknown"}})
