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


def test_github_request_without_token_returns_503(monkeypatch):
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)

    with pytest.raises(main.HTTPException) as exc_info:
        main.github_request("GET", "actions/runs?per_page=100")

    assert exc_info.value.status_code == 503
    assert "GITHUB_TOKEN is missing" in exc_info.value.detail


def test_github_http_error_returns_502(monkeypatch):
    from urllib.error import HTTPError
    from unittest.mock import patch

    error = HTTPError(
        url="https://api.github.com/test",
        code=403,
        msg="Forbidden",
        hdrs=None,
        fp=__import__("io").BytesIO(b'{"message":"Forbidden"}'),
    )

    with patch("app.main.urlopen", side_effect=error):
        with pytest.raises(main.HTTPException) as exc_info:
            monkeypatch.setenv("GITHUB_TOKEN", "test-token")
            main.github_request("GET", "actions/runs?per_page=100")

    assert exc_info.value.status_code == 502
    assert "HTTP 403" in exc_info.value.detail


def test_github_network_error_returns_502(monkeypatch):
    from urllib.error import URLError
    from unittest.mock import patch

    with patch("app.main.urlopen", side_effect=URLError("test connection failure")):
        monkeypatch.setenv("GITHUB_TOKEN", "test-token")
        with pytest.raises(main.HTTPException) as exc_info:
            main.github_request("GET", "actions/runs?per_page=100")

    assert exc_info.value.status_code == 502
    assert "Could not reach GitHub API" in exc_info.value.detail


def test_status_returns_matching_workflow_run(monkeypatch):
    request_id = str(uuid.uuid4())
    expected_name = f"OVS Portal {request_id}"

    def fake_github_request(method, path, payload=None):
        assert method == "GET"
        assert path == "actions/runs?per_page=100&page=1"
        return 200, json.dumps({
            "workflow_runs": [{
                "name": expected_name,
                "id": 12345,
                "status": "completed",
                "conclusion": "success",
                "html_url": "https://github.com/example/repo/actions/runs/12345",
            }]
        })

    monkeypatch.setattr(main, "github_request", fake_github_request)

    response = client.get(f"/build/{request_id}")

    assert response.status_code == 200
    assert response.json() == {
        "request_id": request_id,
        "run_id": 12345,
        "status": "completed",
        "conclusion": "success",
        "html_url": "https://github.com/example/repo/actions/runs/12345",
    }


def test_status_reports_when_workflow_run_is_not_visible(monkeypatch):
    request_id = str(uuid.uuid4())

    monkeypatch.setattr(
        main,
        "github_request",
        lambda method, path, payload=None: (
            200,
            json.dumps({"workflow_runs": []}),
        ),
    )

    response = client.get(f"/build/{request_id}")

    assert response.status_code == 200
    data = response.json()
    assert data["request_id"] == request_id
    assert data["status"] == "queued_or_not_yet_visible"
    assert "No matching run found" in data["message"]


def test_status_rejects_invalid_github_json(monkeypatch):
    request_id = str(uuid.uuid4())
    monkeypatch.setattr(
        main, "github_request",
        lambda method, path, payload=None: (200, "not-json"),
    )
    response = client.get(f"/build/{request_id}")
    assert response.status_code == 502


def test_status_handles_missing_workflow_runs(monkeypatch):
    request_id = str(uuid.uuid4())
    monkeypatch.setattr(
        main, "github_request",
        lambda method, path, payload=None: (200, json.dumps({})),
    )
    response = client.get(f"/build/{request_id}")
    assert response.status_code == 200
    assert response.json()["status"] == "queued_or_not_yet_visible"


def test_status_ignores_unmatched_workflow_name(monkeypatch):
    request_id = str(uuid.uuid4())
    monkeypatch.setattr(
        main, "github_request",
        lambda method, path, payload=None: (
            200,
            json.dumps({
                "workflow_runs": [{
                    "name": "Unrelated workflow",
                    "id": 54321,
                    "status": "completed",
                    "conclusion": "success",
                }]
            }),
        ),
    )
    response = client.get(f"/build/{request_id}")
    assert response.status_code == 200
    assert response.json()["status"] == "queued_or_not_yet_visible"


def test_status_finds_workflow_run_on_second_page(monkeypatch):
    request_id = str(uuid.uuid4())
    expected_name = f"OVS Portal {request_id}"
    requested_paths = []

    def fake_github_request(method, path, payload=None):
        requested_paths.append(path)
        if path.endswith("page=1"):
            return 200, json.dumps({
                "workflow_runs": [
                    {"name": f"Unrelated workflow {index}"}
                    for index in range(100)
                ]
            })
        if path.endswith("page=2"):
            return 200, json.dumps({
                "workflow_runs": [{
                    "name": expected_name,
                    "id": 67890,
                    "status": "in_progress",
                    "conclusion": None,
                    "html_url": "https://github.com/example/repo/actions/runs/67890",
                }]
            })
        raise AssertionError(f"Unexpected API path: {path}")

    monkeypatch.setattr(main, "github_request", fake_github_request)

    response = client.get(f"/build/{request_id}")

    assert response.status_code == 200
    assert response.json()["run_id"] == 67890
    assert response.json()["status"] == "in_progress"
    assert requested_paths == [
        "actions/runs?per_page=100&page=1",
        "actions/runs?per_page=100&page=2",
    ]


def test_status_rejects_invalid_workflow_runs_type(monkeypatch):
    request_id = str(uuid.uuid4())

    monkeypatch.setattr(
        main,
        "github_request",
        lambda method, path, payload=None: (
            200,
            json.dumps({"workflow_runs": {"unexpected": "object"}}),
        ),
    )

    response = client.get(f"/build/{request_id}")

    assert response.status_code == 502
    assert "invalid workflow-runs response" in response.json()["detail"]


def test_status_stops_after_five_pages(monkeypatch):
    request_id = str(uuid.uuid4())
    requested_paths = []

    def fake_github_request(method, path, payload=None):
        requested_paths.append(path)
        return 200, json.dumps({
            "workflow_runs": [
                {"name": f"Unrelated workflow {index}"}
                for index in range(100)
            ]
        })

    monkeypatch.setattr(main, "github_request", fake_github_request)

    response = client.get(f"/build/{request_id}")

    assert response.status_code == 200
    assert response.json()["status"] == "queued_or_not_yet_visible"
    assert len(requested_paths) == 5
    assert requested_paths[-1] == "actions/runs?per_page=100&page=5"
