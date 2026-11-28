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

if MODE == "details":
    LIMITS["rateLimitsByLimitId"]["codex"].update({
        "credits": {"hasCredits": True, "unlimited": False, "balance": "12.50"},
        "individualLimit": {"limit": "25000", "used": "8000", "remainingPercent": 68, "resetsAt": 1800000000},
        "spendControlReached": False,
    })
    LIMITS["rateLimitsByLimitId"]["review"] = {
        "limitName": "Code review", "primary": {"usedPercent": 0, "windowDurationMins": None, "resetsAt": None},
        "credits": {"hasCredits": True, "unlimited": True, "balance": None},
    }
    LIMITS["rateLimitResetCredits"] = {
        "availableCount": 2,
        "credits": [{"id": "reset-1", "resetType": "codexRateLimits", "status": "available", "title": "Earned reset",
                     "description": "A test reset", "grantedAt": 1790000000, "expiresAt": None}],
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
        elif (message.get("params") or {}).get("threadId"):
            send({"id": request_id, "result": {
                "summary": {}, "dailyUsageBuckets": None,
                "threadUsage": {"threadId": message["params"]["threadId"], "estimatedUsageCreditsMicros": 1250000,
                                "estimatedUsageUsdMicros": 0 if message["params"]["threadId"].endswith("2") else None,
                                "groups": [{"model": "test-model", "reasoningEffort": "high", "speed": "fast",
                                            "estimatedUsageCreditsMicros": 1250000, "netNewInputTokens": 100,
                                            "cachedInputTokens": 900, "inputTokens": 1000, "outputTokens": 20, "totalTokens": 1020}]},
            }})
        else:
            send({"id": request_id, "result": USAGE})
    elif method == "account/workspaceMessages/read":
        send({"id": request_id, "result": {"featureEnabled": True, "messages": [
            {"messageId": "test-message", "messageType": "headline", "messageBody": "Test workspace notice", "createdAt": 1800000000, "archivedAt": None}
        ]}})
    elif method == "thread/list":
        params = message.get("params") or {}
        page = 2 if params.get("cursor") else 1
        send({"id": request_id, "result": {
            "data": [{"id": "01900000-0000-7000-8000-00000000000" + str(page), "name": ("Archived " if params.get("archived") else "") + "Test conversation " + str(page),
                      "preview": "", "modelProvider": "openai", "updatedAt": 1800000000, "cwd": "/tmp/details-test"}],
            "nextCursor": "page-2" if page == 1 else None,
        }})
    elif method == "account/logout":
        login_started = False
        send({"id": request_id, "result": {}})
    else:
        send({"id": request_id, "error": {"code": -32601, "message": method or "unknown"}})
