# Setting up the OVS UKEY self-hosted runtime runner

This guide configures a dedicated GitHub Actions runner to execute the instrumented stale-UKEY reproduction in an isolated OVS test environment.

The runtime workflow is separate from the GitHub-hosted RPM build. It needs access to a running disposable OVS instance, the instrumented OVS build, Linux network-namespace tools, and a restricted privileged entry point.

## 1. Prepare a dedicated test host

Use a dedicated disposable Linux VM or test machine. Do not use a production OVS host or a node carrying production OpenStack workloads.

The previous Compute1 runner experienced host-wide memory pressure. Use a separate host with sufficient memory and disk capacity for the instrumented OVS runtime and its logs.

Install the operating-system tools used by the reproduction:

- Bash and coreutils
- Python 3 and pip
- iproute tools, including ip and nsenter
- ping (usually provided by iputils)
- procps-ng
- git
- visudo (provided by sudo)

The Python dependencies are listed in requirements.txt.

## 2. Prepare the instrumented OVS source and disposable runtime

The runner must have an OVS source/build tree containing:

- utilities/ovs-vsctl
- utilities/ovs-appctl
- vswitchd/.libs/lt-ovs-vswitchd
- ofproto/.libs/libofproto-*.so* built with the STALE_UKEY_DEBUG instrumentation
- The corresponding ovsdb/.libs, ofproto/.libs, and lib/.libs library directories

The disposable runtime must already be started before the GitHub Actions workflow runs. Its paths must include:

- A runtime run/ directory containing db.sock, ovs-vswitchd.ctl, and ovs-vswitchd.pid.
- A logs/ directory containing ovs-vswitchd.log.
- A network namespace that contains the running ovs-vswitchd process.

The process identified by the PID file must be the disposable OVS process and its command line must reference the configured database socket. The reproduction script verifies this before it creates test interfaces.

Do not point the configured paths at a system OVS service, production database, or production network.

## 3. Create and register the GitHub Actions runner account

Create a dedicated, unprivileged Linux account for the GitHub Actions runner, for example gha-runner. Register the machine as a self-hosted runner for this repository and apply both labels:

- self-hosted
- ovs-ukey

Complete runner registration from Repository → Settings → Actions → Runners → New self-hosted runner. Use the registration commands GitHub displays for the host's operating system and architecture. Keep the registration token private and do not store it in this repository.

The runner account's primary group is used to grant read access to the evidence files created by the root-owned reproduction.

## 4. Install the restricted runtime entry point

Clone the repository on the runner host, then run the installer as root:

~~~bash
git clone https://github.com/abhiwaycoder/ovs-ukey-automation.git
cd ovs-ukey-automation

sudo bash scripts/install_runtime_runner.sh --runner-user gha-runner
~~~

Replace gha-runner with the Linux account used by the registered GitHub Actions runner.

The installer places:

- The reproduction script at /usr/local/libexec/ovs-ukey-ci/reproduce_stale_ukey.sh.
- The fixed entry point at /usr/local/sbin/ovs-ukey-ci.
- The configuration at /etc/ovs-ukey-ci.conf.
- A sudoers rule that allows the runner account to execute only /usr/local/sbin/ovs-ukey-ci as root.

The generated sudoers file is checked with visudo. The installer does not grant unrestricted passwordless root access, install OVS, or start/restart services.

When the reproduction script changes in the repository, update the installed copy by rerunning the installer from the updated checkout.

## 5. Configure the runtime paths

Edit the root-owned configuration:

~~~bash
sudoedit /etc/ovs-ukey-ci.conf
~~~

Set every path to match the host. The example file is config/ovs-ukey-ci.conf.example.

Important settings:

| Setting | Purpose |
|---|---|
| OVS_UKEY_RUNTIME_ROOT | Base directory of the disposable OVS runtime. |
| OVS_UKEY_SOURCE_ROOT | Root of the instrumented OVS source/build tree. |
| OVS_UKEY_NETWORK_NAMESPACE | Network namespace containing the OVS runtime. |
| OVS_UKEY_BRIDGE | Test bridge created by the reproduction. |
| OVS_UKEY_DB_SOCKET | Database socket used to identify and contact the disposable OVS instance. |
| OVS_UKEY_PID_FILE | PID file for the disposable ovs-vswitchd. |
| OVS_UKEY_CONTROL_SOCKET | ovs-vswitchd control socket. |
| OVS_UKEY_LOG_FILE | Instrumented ovs-vswitchd log file. |
| OVS_UKEY_VSCTL, OVS_UKEY_APPCTL, OVS_UKEY_VSWITCHD | OVS command and daemon binaries. |
| OVS_UKEY_LIBOFPROTO | Instrumented libofproto shared library containing STALE_UKEY_DEBUG. |
| OVS_UKEY_RUNNER_GROUP | Group that receives read access to collected evidence. |
| OVS_UKEY_EVIDENCE | Evidence directory; keep this at /var/lib/ovs-ukey-ci/evidence to match the workflow upload paths. |

The file must remain owned by root and must not be group- or world-writable. The reproduction script checks these conditions before sourcing it.

Verify the instrumentation without running the reproduction:

~~~bash
grep -a -q 'STALE_UKEY_DEBUG' \
  /opt/ovs-ukey-ci/ovs-source/ofproto/.libs/libofproto-3.5.so.0.0.3
~~~

Use the actual path and library filename configured on the host.

## 6. Verify runner permissions without starting the test

Check the configuration ownership and permissions:

~~~bash
sudo stat -c '%U:%G %a %n' /etc/ovs-ukey-ci.conf
sudo visudo -cf /etc/sudoers.d/ovs-ukey-ci-gha-runner
~~~

Check that the runner account has permission to invoke only the intended entry point:

~~~bash
sudo -u gha-runner sudo -n -l /usr/local/sbin/ovs-ukey-ci
~~~

The output should list the fixed command and should not grant ALL commands. Also verify that the configured database socket, control socket, PID file, log file, and OVS binary paths exist.

These checks do not start or modify the OVS runtime.

## 7. Run the GitHub Actions workflow

After the host, instrumented build, disposable runtime, configuration, and runner labels have been reviewed:

1. Open the repository's Actions tab.
2. Select OVS UKEY Runtime Reproduction.
3. Select Run workflow.
4. Enable confirm_disposable_runtime to acknowledge that the runner is a disposable test environment.
5. Start the workflow.

The workflow runs the reproduction through the restricted sudo entry point. It checks for all four missed-dump values, verifies the datapath deletion attempt and the revalidate_missing_dp_flow coverage counter, runs pytest against the captured evidence, and uploads the evidence bundle even when a later step fails.

Review the workflow summary and download the ovs-ukey-runtime-evidence-<run-id> artifact. Verify its runtime-evidence-SHA256SUMS manifest.

## 8. Evidence expected from a successful run

The workflow expects these files under /var/lib/ovs-ukey-ci/evidence:

- dp-final.txt
- upcall-final.txt
- ovs-vswitchd.log
- stale-ukey-debug.log
- coverage-final.txt
- runtime-evidence-SHA256SUMS

The debug log must contain missed_dumps=1, 2, 3, and 4. The coverage output must include revalidate_missing_dp_flow. Review the actual log records and final UKEY/datapath output; file presence alone is not evidence of a passing test.

## Safety

- Use only a disposable OVS runtime and dedicated runner host.
- Never run this workflow against production OVS sockets, databases, bridges, or services.
- Do not grant the runner unrestricted passwordless sudo.
- Do not put runner registration tokens, GitHub tokens, private RPM signing keys, or GPG home directories in the repository.
- Keep the runner account unprivileged and keep the configuration and installed privileged scripts root-owned.
