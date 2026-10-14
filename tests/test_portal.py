import json
import uuid

import pytest
from fastapi.testclient import TestClient

from app import main


client = TestClient(main.app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_home_form():
    response = client.get("/")
    assert response.status_code == 200
    assert "OVS UKEY Automation Portal" in response.text
    assert "src_rpm_url" in response.text
    assert "patch_content" in response.text


def test_build_requires_a_patch():
    response = client.post(
        "/build",
        json={
            "src_rpm_url":
                "https://example.com/openvswitch-2.17.0-106.el8.src.rpm"
        },
    )
    assert response.status_code == 422


def test_build_rejects_non_https_source_rpm():
    response = client.post(
        "/build",
        json={
            "src_rpm_url":
                "http://example.com/openvswitch-2.17.0-106.el8.src.rpm",
            "patch_content": "diff --git a/a b/a\n",
        },
    )
    assert response.status_code == 422


def test_dispatch_returns_request_id(monkeypatch):
    captured = {}

    def fake_github_request(method, path, payload=None):
        captured["method"] = method
        captured["path"] = path
        captured["payload"] = payload
        return 204, ""

    monkeypatch.setattr(main, "github_request", fake_github_request)

    response = client.post(
        "/build",
        json={
            "src_rpm_url":
                "https://example.com/openvswitch-2.17.0-106.el8.src.rpm",
            "patch_content": "diff --git a/a b/a\n",
        },
    )

    assert response.status_code == 202
    data = response.json()
    uuid.UUID(data["request_id"])
    assert data["status"] == "dispatched"
    assert captured["method"] == "POST"
    assert captured["path"] == "dispatches"
    assert captured["payload"]["event_type"] == "ovs-ukey-build"
    assert captured["payload"]["client_payload"]["request_id"] == data["request_id"]


def test_status_rejects_invalid_request_id():
    response = client.get("/build/not-a-uuid")
    assert response.status_code == 400
