import os
import re
import uuid
from typing import Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field, model_validator


DEFAULT_SRC_RPM_URL = (
    "https://example.invalid/openvswitch-2.17.0-106.el8.src.rpm"
)
GITHUB_API = "https://api.github.com"

app = FastAPI(
    title="OVS UKEY Automation Portal",
    description="Submit and monitor OVS automation workflow requests.",
    version="0.1.0",
)


class BuildRequest(BaseModel):
    src_rpm_url: str = DEFAULT_SRC_RPM_URL
    patch_url: Optional[str] = None
    patch_content: Optional[str] = None

    @model_validator(mode="after")
    def validate_request(self):
        parsed = urlparse(self.src_rpm_url)
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError("src_rpm_url must be a valid HTTPS URL")

        if not parsed.path.endswith(".src.rpm"):
            raise ValueError("src_rpm_url must point to a .src.rpm file")

        if self.patch_url and self.patch_content:
            raise ValueError(
                "Provide patch_url or patch_content, not both"
            )

        if not self.patch_url and not self.patch_content:
            raise ValueError("Provide patch_url or patch_content")

        if self.patch_url:
            patch = urlparse(self.patch_url)
            if patch.scheme != "https" or not patch.netloc:
                raise ValueError("patch_url must be a valid HTTPS URL")

        if self.patch_content is not None:
            if not self.patch_content.strip():
                raise ValueError("patch_content cannot be empty")
            if len(self.patch_content.encode("utf-8")) > 48_000:
                raise ValueError("patch_content exceeds 48 KB; use patch_url for larger patches")

        return self


def github_request(method: str, path: str, payload=None):
    token = os.getenv("GITHUB_TOKEN")
    if not token:
        raise HTTPException(
            status_code=503,
            detail="GitHub integration is not configured: GITHUB_TOKEN is missing",
        )

    owner = os.getenv("GITHUB_OWNER", "abhiwaycoder")
    repo = os.getenv("GITHUB_REPO", "ovs-ukey-automation")
    url = f"{GITHUB_API}/repos/{owner}/{repo}/{path.lstrip('/')}"

    import json

    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
            "User-Agent": "ovs-ukey-automation-portal",
        },
    )

    try:
        with urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8")
            return response.status, body
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise HTTPException(
            status_code=502,
            detail=f"GitHub API returned HTTP {exc.code}: {detail[:500]}",
        ) from exc
    except URLError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Could not reach GitHub API: {exc.reason}",
        ) from exc


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def home():
    return """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>OVS UKEY Automation</title>
  <style>
    body { font: 16px system-ui; max-width: 760px; margin: 36px auto;
           padding: 0 18px; color: #202124; }
    label { display: block; margin-top: 18px; font-weight: 600; }
    input, textarea { box-sizing: border-box; width: 100%; padding: 10px;
                      margin-top: 6px; }
    textarea { min-height: 180px; font-family: monospace; }
    button { margin-top: 20px; padding: 11px 18px; cursor: pointer; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; }
  </style>
</head>
<body>
  <h1>OVS UKEY Automation Portal</h1>
  <p>Submit a source RPM and a patch to request a GitHub Actions run.</p>
  <form id="build-form">
    <label for="src_rpm_url">Source RPM URL</label>
    <input id="src_rpm_url" name="src_rpm_url" type="url" required
      value="https://example.invalid/openvswitch-2.17.0-106.el8.src.rpm">

    <label for="patch_url">Patch URL (HTTPS)</label>
    <input id="patch_url" name="patch_url" type="url"
      placeholder="https://example.com/fix.patch">

    <label for="patch_content">Or paste patch content</label>
    <textarea id="patch_content" name="patch_content"
      placeholder="Paste a unified diff here"></textarea>

    <button type="submit">Submit workflow request</button>
  </form>
  <h2>Response</h2>
  <pre id="result">No request submitted yet.</pre>
  <script>
    document.getElementById("build-form").addEventListener("submit",
      async (event) => {
        event.preventDefault();
        const result = document.getElementById("result");
        result.textContent = "Submitting...";
        const src = document.getElementById("src_rpm_url").value.trim();
        const patchUrl = document.getElementById("patch_url").value.trim();
        const patchContent =
          document.getElementById("patch_content").value;
        const payload = {src_rpm_url: src};
        if (patchUrl) payload.patch_url = patchUrl;
        else if (patchContent.trim()) payload.patch_content = patchContent;
        else {
          result.textContent = "Provide a patch URL or patch content.";
          return;
        }
        try {
          const response = await fetch("/build", {
            method: "POST",
            headers: {"Content-Type": "application/json"},
            body: JSON.stringify(payload)
          });
          const data = await response.json();
          result.textContent = JSON.stringify(data, null, 2);
        } catch (error) {
          result.textContent = String(error);
        }
      });
  </script>
</body>
</html>
"""


@app.post("/build", status_code=202)
def submit_build(request: BuildRequest):
    request_id = str(uuid.uuid4())

    payload = {
        "event_type": "ovs-ukey-build",
        "client_payload": {
            "request_id": request_id,
            "src_rpm_url": request.src_rpm_url,
            "patch_url": request.patch_url,
            "patch_content": request.patch_content,
        },
    }

    status, _ = github_request("POST", "dispatches", payload)
    if status not in (200, 201, 202, 204):
        raise HTTPException(
            status_code=502,
            detail=f"Unexpected GitHub dispatch response: HTTP {status}",
        )

    return {
        "request_id": request_id,
        "status": "dispatched",
        "message": (
            "GitHub accepted the dispatch event. Workflow status tracking "
            "requires the workflow to expose this request ID."
        ),
    }


@app.get("/build/{request_id}")
def build_status(request_id: str):
    # Validate the identifier before using it in any API query.
    try:
        uuid.UUID(request_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid request ID") from exc

    # repository_dispatch does not return a workflow run ID. The workflow
    # must set its run name to include this request ID; then we can correlate
    # it with the GitHub Actions runs list.
    status, body = github_request(
        "GET",
        "actions/runs?per_page=100",
    )

    import json

    try:
        result = json.loads(body)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=502,
            detail="GitHub returned invalid JSON",
        ) from exc

    expected_name = f"OVS Portal {request_id}"
    for run in result.get("workflow_runs", []):
        if run.get("name") == expected_name or run.get("display_title") == expected_name:
            return {
                "request_id": request_id,
                "run_id": run.get("id"),
                "status": run.get("status"),
                "conclusion": run.get("conclusion"),
                "html_url": run.get("html_url"),
            }

    return {
        "request_id": request_id,
        "status": "queued_or_not_yet_visible",
        "message": (
            "No matching run found yet. Ensure the workflow run name includes "
            "the request ID and allow time for GitHub to register the run."
        ),
    }
