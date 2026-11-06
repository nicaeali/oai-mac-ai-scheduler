# Lab checkpoint: OAI RFsim and FlexRIC on a POWDER d430 (AI-generated)

- **Recorded:** 2026-11-06
- **Milestone:** single-UE downlink UDP baseline
- **Execution:** commands run manually by the experimenter on POWDER

This is a session record and a starting point for a lab assignment. The
[deployment runbook](POWDER_RFSIM.md) contains the build and launch commands. The runtime source fixes described below were applied on the POWDER checkout; capture that checkout's actual revision and diff when preparing the lab release. The documentation in this local repository does not establish which changes have been committed or pushed from the node.

## 1. What has been demonstrated

| Milestone | Evidence available at this checkpoint |
| --- | --- |
| A suitable d430 host | OS, CPU, memory, and filesystem output supplied by the experimenter. |
| FlexRIC compilation | Initial post-build failure was diagnosed and corrected; subsequent testing proceeded. |
| FlexRIC tests | Initially 12 of 13 tests passed. After the fixes below, the experimenter reported that everything passed. Preserve the final CTest logs as the lab artifact. |
| OAI gNB and nrUE compilation | Executable listings showed `nr-softmodem` (125 MB) and `nr-uesoftmodem` (48 MB). |
| End-to-end downlink data | The UE-side iperf receiver at `10.0.0.2` received traffic from `192.168.70.135` for 30 seconds with zero reported datagram loss. |
| E2 build/runtime evidence | The first OAI cache showed `E2_AGENT=OFF`; explicit reconfiguration and symbol checks were then prescribed. The final cache, symbol output, and live E2 setup log still need to be included in the evidence bundle. Traffic delivery alone does not establish E2 connectivity. |
| Live MAC telemetry through the Python SDK | The `monitor_mac.py` exercise was proposed but has not yet been executed/reported at this checkpoint. |
| Scheduler control and AI training | Pending. No closed-loop AI scheduling result or performance improvement has been demonstrated. |

The completed lab milestone is the **RAN/core downlink baseline**. The next milestone is live MAC telemetry, followed by a known fixed control action and then the AI loop.

## 2. Environment and topology

### Observed host

| Item | Recorded value |
| --- | --- |
| POWDER hardware | d430 |
| OS | Ubuntu 24.04.5 LTS, Noble |
| Architecture | x86_64 |
| CPUs | Two Intel Xeon E5-2630 v3 processors at 2.40 GHz |
| Physical cores / hardware threads | 16 / 32 |
| Instruction support | AVX2; OAI configured with AVX512 disabled |
| Memory | 62 GiB reported; approximately 61 GiB initially available |
| Root filesystem at the start | `/dev/sda3`, 63 GB total, 57 GB available |
| Checkout location | `~/oai-mac-ai-scheduler` (`/users/gulec/oai-mac-ai-scheduler` in this session) |

The selected profile was a one-node bare-metal setup based on POWDER's
[`PortalProfiles/single-pc`](https://www.powderwireless.net/p/PortalProfiles/single-pc) template, configured for `d430` and Ubuntu 24.04. A reservation holds capacity; the experiment instantiated from the profile provisions the node.

### Deployment layout

```text
One POWDER d430

  External data network container (192.168.70.135)
           |
          UPF (192.168.70.134)
           | N3 / GTP-U
       OAI gNB (host bridge address 192.168.70.129)
           | RFsim over loopback
       OAI nrUE
           |
       oaitun_ue1 (observed UE IP: 10.0.0.2)
           |
       iperf UDP receiver

  gNB -- E2/SCTP --> FlexRIC nearRT-RIC (127.0.0.1)
                         |
                   Python MAC monitor [next exercise]
                         |
                   AI controller [later exercise]
```

### Configuration used in the procedure

| Setting | Value |
| --- | --- |
| Docker core bridge | `oai-cn5g`, subnet `192.168.70.128/26` |
| Docker network name | `oai-cn5g-public-net` |
| Host bridge / gNB address | `192.168.70.129` |
| AMF / SMF / UPF | `192.168.70.132` / `.133` / `.134` |
| External data network | `192.168.70.135` |
| PLMN / tracking area code | `001/01` / `1` |
| First UE IMSI | `001010000000001` |
| DNN / SST | `oai` / `1` |
| UE address pool | `10.0.0.0/24` |
| Radio configuration | Band 78, 106 PRBs, numerology 1, one TX/RX chain |
| nrUE center frequency | `3619200000` Hz |
| RFsim peer | gNB server; UE connects to `127.0.0.1`, default port 4043 |
| E2AP / KPM | `E2AP_V2` / `KPM_V2_03` |
| Compiler selection | GCC/G++ 13 |
| Build parallelism | Eight jobs |
| FlexRIC Python bindings | SWIG >= 4.1 and Python 3.12 selected in the procedure |
| OAI build generator | Unix Makefiles in this session |

Capture exact installed tool versions and container image digests from the node; they were not all pasted into the session transcript. The core services selected were MySQL, NRF, UDR, UDM, AUSF, AMF, SMF, UPF, and the external data network. The procedure used Ubuntu's `docker.io` and `docker-compose-v2` packages.

## 3. Procedure and troubleshooting ledger

### A. Source and prerequisites

The procedure used a GitHub fork of `tlmat-unican/oai-mac-ai-scheduler` and the OAI/FlexRIC source trees vendored inside it. The local source assessment began at upstream commit `7ed194cc`; record the actual POWDER/fork commit separately. The additional OAI dependencies were installed using:

```bash
cd "$HOME/oai-mac-ai-scheduler/openairinterface5g/cmake_targets"
./build_oai -I -w SIMU
```

### B. FlexRIC Python SDK post-build failure

**Observed:** `_xapp_sdk.so` reached the linking step, then CMake failed copying `xapp_mac_rlc_pdcp_gtp_moni.py`. Make deleted the output module after the failed post-build command.

**Cause:** the SWIG CMake file referenced two absent example files:
`xapp_mac_rlc_pdcp_gtp_moni.py` and `xapp_slice_moni_ctrl.py`.

**Correction:** in
`openairinterface5g/openair2/E2AP/flexric/src/xApp/swig/CMakeLists.txt`, replace those two example-copy commands with a copy of the included `xapp_drl_scheduling.py`. Retain the copies for `_xapp_sdk.so`, `xapp_sdk.py`, and `watch_slice_stats`. Regenerate and rebuild incrementally.

### C. Agent/RIC/xApp integration test: null function pointer

**Observed:** `Unit_test_Agent_RIC_xApp` segfaulted; GDB showed a call to address zero from `process_format_3_message()` in `sqlite3_wrapper.c`.

**Cause:** the KPM SQLite UE-ID dispatch table only implements gNB, gNB-DU, and gNB-CU-UP converters. The randomized test generated `NG_ENB_UE_ID_E2SM`, whose table entry is `NULL`.

**Correction:** check the UE-ID type's bounds and handler before calling it:

```c
if ((unsigned)type >= END_UE_ID_E2SM ||
    get_ue_id_e2sm[type] == NULL) {
  fprintf(stderr,
          "[SQLite/KPM] Skipping UE report: unsupported UE ID type %d\n",
          (int)type);
  continue;
}
```

This diagnoses and skips unsupported KPM UE reports. It does not implement logging for the additional UE-ID formats; that limitation belongs in the lab report.

### D. Integration test: invalid measurement metadata access

**Observed:** the next backtrace entered `cp_ba_to_str()` from the KPM SQLite writer, at measurement index `k = 2`.

**Causes found in the source:**

1. `fill_rnd_kpm_ind_msg_frm_1()` generated four measurement records but only two metadata entries. The third metadata access was out of bounds.
2. The logger always read `meas_type.name`, although the tagged union can instead hold a numeric measurement ID.

**Corrections:**

- In `test/rnd/fill_rnd_data_kpm.c`, derive the Format 1 metadata count from the generated record count:

  ```c
  msg_frm_1.meas_info_lst_len = msg_frm_1.meas_data_lst[0].meas_record_len;
  ```

- In `src/xApp/db/sqlite3/sqlite3_wrapper.c`, add metadata-pointer/length checks to all three KPM format writers; diagnose and skip rows that cannot be mapped.
- Pass the complete `meas_type_t` to the SQL formatter and inspect its tag. Preserve named measurements and represent numeric IDs as `id:<number>` in the existing `meas_name` column.
- Initialize the SQL output to an empty string before early returns, and use empty strings for absent UE-ID fields rather than passing NULL to `%s`.

A focused local ASan/UBSan probe exercised the corrected SQLite writers for Formats 1/2/3, named/numeric measurements, and missing/short metadata. The experimenter subsequently reported that the repeated integration test and full FlexRIC suite passed on POWDER. Save those node-side test logs with the lab.

### E. OAI CMake generator mismatch

**Observed:** requesting Ninja failed because the existing OAI build directory used Unix Makefiles.

**Correction:** reuse Unix Makefiles. CMake generator selection belongs to a build directory; changing the requested generator does not convert an existing cache. The runbook now uses explicit Makefiles configuration for this setup.

### F. Successful compilation with E2 disabled

**Observed:** the build produced both executables, but the cache contained:

```text
E2_AGENT:STRING=OFF
```

**Correction prescribed:** configure the existing OAI build directly with `E2_AGENT=ON`, `E2AP_V2`, and `KPM_V2_03`; inspect the cache before rebuilding; then inspect the gNB binary for `init_agent_api`, `read_mac_sm`, and `write_ctrl_mac_sm`. The exact cause of the lost options was not established from the supplied log. Record the corrected cache and symbols as evidence.

### G. Core, gNB, and UE configuration alignment

The supplied gNB configuration uses PLMN `999/70` and `192.168.112.x` addresses. The launch procedure overrides these with `001/01`, AMF `192.168.70.132`, and gNB `192.168.70.129`. It also selects one TX/RX chain and reduces MAC log verbosity to avoid printing scheduler details every slot.

The supplied `ue.conf` also belongs to another scenario (`99970...`, DNN
`internet`, and a satellite-channel include). The baseline UE launch passes the matching test IMSI, key, OPc, DNN, and SST directly on the command line. See the runbook for the complete commands.

### Known source files edited on POWDER

All three paths are under `openairinterface5g/openair2/E2AP/flexric/`:

1. `src/xApp/swig/CMakeLists.txt`
2. `src/xApp/db/sqlite3/sqlite3_wrapper.c`
3. `test/rnd/fill_rnd_data_kpm.c`

The E2 build correction changes CMake configuration, not the source default. Export both source changes and build-cache evidence.

## 4. Recorded traffic result

Receiver command on the node:

```bash
iperf -s -u -B 10.0.0.2 -i 1
```

Sender command supplied in the procedure:

```bash
sudo docker exec oai-ext-dn \
  iperf -c 10.0.0.2 -u -i 1 -t 30 -b 5M
```

Actual receiver summary supplied by the experimenter:

```text
[  1] local 10.0.0.2 port 5001 connected with 192.168.70.135 port 34707
[  1] 0.0000-30.0006 sec  18.8 MBytes  5.24 Mbits/sec   0.204 ms 0/13378 (0%)
[  3] WARNING: ack of last datagram failed.
```

| Measurement | Result |
| --- | --- |
| Duration | 30.0006 seconds |
| Received transfer | 18.8 MBytes |
| Received throughput | 5.24 Mbits/s |
| Reported final jitter | 0.204 ms |
| Lost / total datagrams | 0 / 13,378 |
| Reported loss | 0% |

The receiver establishes successful downlink delivery for this run. The final iperf warning concerns the end-of-test acknowledgement/report exchange; keep the client output and check the return path if it repeats. A successful closing handshake has not been established by this receiver output alone.

This is one single-UE baseline run. Record the iperf version and rate-unit conventions when interpreting `-b 5M` and the displayed 5.24 Mbits/s. Scheduler comparisons will require repeated runs and controlled load/channel conditions.

## 5. Pause and orderly shutdown

Stopping the foreground processes preserves the source tree, binaries, and logs on the allocated node. Use **Ctrl+C in each process's terminal** and wait for the shell prompt to return:

1. Let the timed traffic client finish, or stop it. The recorded 30-second run has already completed. For a client launched through `docker exec`, confirm it has ended inside the container; closing the attached terminal alone is not a reliable process-stop mechanism. `sudo docker top oai-ext-dn` shows its processes while the container is running.
2. Stop the iperf receiver.
3. If an xApp has since been started, let it unsubscribe and exit before stopping the RAN/RIC. The proposed MAC monitor has not run at this checkpoint.
4. Stop `nr-uesoftmodem`.
5. Stop `nr-softmodem`.
6. Stop `nearRT-RIC`.

Check for remaining processes:

```bash
pgrep -a -x 'nr-softmodem|nr-uesoftmodem|nearRT-RIC|iperf'
```

No output means none of those process names matched; `pgrep` then exits with status 1, which is normal for this check.

The core containers can remain running for a short pause. To stop them while retaining the containers and their database storage:

```bash
export OAI="$HOME/oai-mac-ai-scheduler/openairinterface5g"
cd "$OAI/doc/tutorial_resources/oai-cn5g"
sudo docker compose stop -t 30
sudo docker compose ps -a
```

**POWDER experiment lifetime matters:** stopping processes is different from
terminating the experiment. Terminating the experiment or letting the experiment
expire can discard node-local files. Download the evidence bundle below before
releasing the node. A reservation's end and an experiment's expiration are
separate events.

## 6. Preserve the lab evidence

Archive the current logs before restarting: the previously supplied `tee` commands reuse filenames, and the gNB initializes `ue_qos_stats.csv` on a new run. These commands run on POWDER and collect evidence without committing or pushing repository changes:

```bash
export REPO="$HOME/oai-mac-ai-scheduler"
export OAI="$REPO/openairinterface5g"
export FLEXRIC="$OAI/openair2/E2AP/flexric"
export CORE="$OAI/doc/tutorial_resources/oai-cn5g"
export SNAPSHOT="$HOME/oai-lab-checkpoint-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SNAPSHOT"

git -C "$REPO" rev-parse HEAD > "$SNAPSHOT/git-head.txt"
git -C "$REPO" remote -v > "$SNAPSHOT/git-remotes.txt"
git -C "$REPO" status --short --branch > "$SNAPSHOT/git-status.txt"
git -C "$REPO" diff HEAD --binary > "$SNAPSHOT/source-changes.patch"
git -C "$REPO" bundle create "$SNAPSHOT/repository.bundle" --all

tar -C "$REPO" -czf "$SNAPSHOT/fixed-flexric-sources.tar.gz" \
  openairinterface5g/openair2/E2AP/flexric/src/xApp/swig/CMakeLists.txt \
  openairinterface5g/openair2/E2AP/flexric/src/xApp/db/sqlite3/sqlite3_wrapper.c \
  openairinterface5g/openair2/E2AP/flexric/test/rnd/fill_rnd_data_kpm.c

cp "$OAI/cmake_targets/ran_build/build/CMakeCache.txt" "$SNAPSHOT/oai-CMakeCache.txt"
cp "$FLEXRIC/build/CMakeCache.txt" "$SNAPSHOT/flexric-CMakeCache.txt"
cp "$CORE/conf/config.yaml" "$SNAPSHOT/core-config.yaml"
cp "$CORE/database/oai_db.sql" "$SNAPSHOT/core-seed.sql"

for f in \
  "$HOME/nearRT-RIC.log" "$HOME/gnb-rfsim.log" "$HOME/ue-rfsim.log" \
  "$HOME/iperf-server.log" "$HOME/iperf-client.log" "$HOME/mac-monitor.log" \
  "$HOME/flexric-build.log" "$HOME/flexric-integration-retest.log" \
  "$HOME/flexric-tests.log" "$HOME/flexric-integration-backtrace.log" \
  "$FLEXRIC/build/Testing/Temporary/LastTest.log" \
  "$OAI/cmake_targets/ran_build/build/ue_qos_stats.csv"
do
  if [ -f "$f" ]; then cp "$f" "$SNAPSHOT/"; fi
done
if [ -d "$HOME/oai-build-logs" ]; then
  cp -a "$HOME/oai-build-logs" "$SNAPSHOT/"
fi

{
  date -Is
  uname -a
  cat /etc/os-release
  lscpu
  free -h
  df -h
  gcc-13 --version
  g++-13 --version
  cmake --version
  swig -version
  python3 --version
  iperf --version
} > "$SNAPSHOT/environment.txt" 2>&1

nm "$OAI/cmake_targets/ran_build/build/nr-softmodem" \
  | grep -E ' (init_agent_api|read_mac_sm|write_ctrl_mac_sm)$' \
  > "$SNAPSHOT/gnb-e2-symbols.txt"

cd "$CORE"
sudo docker version > "$SNAPSHOT/docker-version.txt"
sudo docker compose version > "$SNAPSHOT/compose-version.txt"
sudo docker compose config > "$SNAPSHOT/core-compose-resolved.yaml"
sudo docker compose ps -a > "$SNAPSHOT/core-status.txt"
sudo docker compose logs --no-color > "$SNAPSHOT/core.log" 2>&1
image_ids=$(sudo docker compose images -q)
if [ -n "$image_ids" ]; then
  sudo docker image inspect $image_ids \
    --format '{{.Id}} {{json .RepoTags}} {{json .RepoDigests}}' \
    > "$SNAPSHOT/core-image-digests.txt"
fi
ip -4 addr > "$SNAPSHOT/ipv4-addresses.txt"
ip -4 route > "$SNAPSHOT/ipv4-routes.txt"

tar -C "$HOME" -czf "${SNAPSHOT}.tar.gz" "$(basename "$SNAPSHOT")"
ls -lh "${SNAPSHOT}.tar.gz"
```

The Git bundle records committed history; the patch records tracked changes
relative to HEAD. Review `git-status.txt` and copy any additional untracked lab
files into the snapshot before creating the final archive. The iperf output
above was displayed directly in a terminal; copy that terminal output separately
if a full transcript is desired. An empty `gnb-e2-symbols.txt` needs investigation
alongside the E2 cache and build logs.

From your Mac, download the archive using your own login details and the actual
timestamp printed above:

```bash
scp YOUR_USER@YOUR_NODE:~/oai-lab-checkpoint-TIMESTAMP.tar.gz .
```

The container images use moving tags such as `develop`. Use the recorded image
digests and source revision when preparing a reproducible student release.

## 7. Resume the same experiment

1. Reconnect to the still-allocated POWDER node and restore the environment variables from the runbook. Recompilation is only needed after relevant source/configuration changes.
2. If the core was stopped, use the runbook's staged `docker compose up -d --wait` commands: MySQL/NRF first, then the full service set. Check container health.
3. Start nearRT-RIC in one terminal.
4. Start the gNB in another terminal with the recorded PLMN/IP/RFsim overrides.
5. Start the nrUE in another terminal with the matching test credentials.
6. Check the new UE tunnel address and test connectivity. Use the actual assigned address for the receiver and traffic generator.
7. Start the UDP receiver, then traffic from `oai-ext-dn`.
8. Continue with the proposed one-second MAC monitor while traffic is active.

The launch commands are in
[the runbook's RFsim section](POWDER_RFSIM.md#4-first-milestone-rfsim-attachment-and-downlink-traffic).
If the POWDER experiment has ended, allocate a new node and recreate the setup
using the captured source, build configuration, and container images.

## 8. Lab-assignment outline

**Suggested title:** Bringing Up an OAI RFsim Testbed with FlexRIC on POWDER

### Learning objectives

- Explain the roles of the 5G core, gNB, nrUE, RFsim, E2 agent, RIC, and xApp.
- Build matching OAI/FlexRIC protocol versions and verify optional features.
- Diagnose build-system failures and native crashes using logs and GDB.
- Align subscriber, PLMN, slice, and IP configuration across components.
- Measure downlink UDP delivery and preserve reproducible evidence.

### Suggested parts and deliverables

| Part | Required artifact |
| --- | --- |
| Host/profile preparation | Hardware/OS output and a topology/address diagram. |
| Build and diagnostics | Source revision/diff, tool versions, CMake settings, test summary, and explanations of the observed failures. |
| E2 verification | `E2_AGENT=ON`, gNB symbols, and a live E2 setup log. |
| Core and UE attachment | Core status, subscriber query, registration/PDU-session evidence, and tunnel address. |
| Downlink experiment | Full sender and receiver logs, duration, transfer, throughput, jitter, loss, and interpretation of the final ACK warning. |
| Reproducibility | Image digests, configuration, source fixes, and a demonstrated stop/restart procedure. |

For repeat runs, capture the receiver output with `tee` rather than relying on
terminal scrollback. Students should report repeated measurements rather than
assuming the single reference run guarantees identical performance.

### Discussion questions

1. Why can compilation succeed while `E2_AGENT` is disabled?
2. Why did switching CMake generators fail in an existing build directory?
3. How does a null function-pointer call appear in a GDB backtrace?
4. Why are both tagged-union checks and metadata-length checks necessary in the KPM logger? Why must the test generator's metadata count also be corrected?
5. What does the receiver's zero-loss result establish, and what does the final acknowledgement warning leave unresolved?
6. What additional evidence is needed to claim that AI changes MAC scheduling decisions or improves performance?

### Follow-on lab

Verify live MAC telemetry, repair and test the scheduler action/observation contract, apply a fixed E2 control action, and then connect the AI server. The remaining implementation issues are listed in [the runbook's repair order](POWDER_RFSIM.md#2-confirmed-blockers-and-repair-order).
