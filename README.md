# OVS Stale UKEY Automation

Automation for reproducing and verifying Open vSwitch stale UKEY cleanup.

## Reproduction

Run on Compute1:

    ./scripts/reproduce_stale_ukey.sh
    pytest -v

The reproduction:

1. Generates deterministic IPv6 multicast traffic.
2. Creates a datapath flow and UKEY.
3. Deletes the datapath flow.
4. Leaves the UKEY stale.
5. Waits for four consecutive missed revalidator dumps.
6. Verifies missed_dumps=1..4.
7. Verifies the datapath delete attempt.
8. Verifies revalidate_missing_dp_flow.
9. Verifies the UKEY is removed.
10. Saves evidence under evidence/.

## Project flow

Deterministic reproduction -> Automated verification -> GitHub Actions -> CI -> OpenStack -> End-to-end validation

## Self-hosted GitHub Actions runner

The workflow requires a self-hosted runner labelled `self-hosted` and
`ovs-ukey`. The configured runner needs the OVS build, disposable runtime,
Python 3, pip, and the `gha-runner` account.

The workflow invokes `/usr/local/sbin/ovs-ukey-ci` through sudo. The current
sudoers policy allows the runner to invoke that specific entry point:

`gha-runner ALL=(root) NOPASSWD: /usr/local/sbin/ovs-ukey-ci`

That entry point delegates to `/usr/local/libexec/ovs-ukey-reproduce`.
The reproduction script uses absolute paths specific to Compute1, so those
paths and prerequisites must be provisioned before using another runner.

## Safety

Use only the configured disposable runtime. Do not point the script at
production OVS sockets or databases, and do not restart production OVS
services as part of this test.

## Python dependencies

Install the test dependency with:

`python3 -m pip install -r requirements.txt`

---

## FastAPI Portal

The FastAPI portal submits OVS stale-UKEY automation requests through GitHub Actions.

### Features
- Web form for source RPM URL and patch input.
- Validates request inputs and supports a patch URL or patch content.
- Dispatches the `ovs-ukey-build` repository event.
- Provides a request-status endpoint.
- Includes automated portal API tests.

### Architecture

Browser -> FastAPI -> GitHub repository_dispatch -> OVS Portal Request workflow -> Input validation

**Current limitation:** The portal workflow validates inputs only. It does not yet download source RPMs, apply patches, build RPMs, or execute stale-UKEY reproduction. The existing self-hosted reproduction workflow remains separate.

Portal dispatch and workflow validation were tested successfully, and the local test suite passed 10 tests during verification.

### Configuration

Install dependencies:

    python3 -m venv .venv
    . .venv/bin/activate
    python -m pip install -r requirements.txt

Configure a local `.env` file with a fine-grained token restricted to `abhiwaycoder/ovs-ukey-automation`:

    GITHUB_TOKEN=<your-token>
    GITHUB_OWNER=abhiwaycoder
    GITHUB_REPO=ovs-ukey-automation

Use `chmod 600 .env`. Never commit or disclose the token. Load these variables into the service process before starting the portal.

### Start the portal

    .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000

Open `http://127.0.0.1:8000/`. The health endpoint is `/health`, and interactive API documentation is available at `/docs`.

### API endpoints

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/` | Portal web form |
| GET | `/health` | Health check |
| POST | `/build` | Validate and dispatch a request |
| GET | `/build/{request_id}` | Query workflow status |

The `/build` endpoint currently dispatches a validation request; it does not build an RPM.

### Tests

    .venv/bin/python -m pytest -v

Passing local tests does not replace validation on the configured disposable OVS test runtime.

### Portal safety
- Use only the configured disposable runtime for reproduction.
- Never point scripts at production OVS sockets or databases.
- Do not restart production OVS services as part of testing.
- Do not submit real build requests until build execution and its safety controls are implemented and reviewed.
- Keep credentials out of version control and preserve existing backup files.
