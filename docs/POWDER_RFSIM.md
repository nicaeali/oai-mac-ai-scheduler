# POWDER RFsim Experiment Notes

## Status and first target

This is an AI-generated, human-verified/modified document.

The repository contains the OAI downlink scheduler, the custom FlexRIC MAC service model, the Python xApp, and the external RL server. It also contains an OAI CN5G Compose example and its subscriber database. The AI control loop has source-level defects listed below; it is **not yet verified end to end**.

The initial assessment was performed on macOS/ARM (by AI). A subsequent, manually executed POWDER session reached a single-UE downlink UDP baseline and the experimenter reported that the repaired FlexRIC tests passed. See the [lab checkpoint](LAB_CHECKPOINT.md) for the observed result, required source fixes, and evidence still to collect. The commands below incorporate the configuration corrections from that session; the AI loop remains pending.

Recommended first experiment:

- One **bare-metal x86_64 node with Ubuntu 24.04**, sudo access, and Internet access for package/build dependencies and container images.
- Target a **d430**, prioritizing its greater availability: two Intel Xeon E5-2630 v3 CPUs (16 physical cores total, 2.4 GHz) and **64 GB RAM**. Start with one simulated UE and measure RFsim performance before adding more UEs. CPU execution is sufficient for the initial small DQN/PPO networks.
- Allow at least **50 GB free disk**, preferably 100 GB, for sources, builds, core images, and logs. Check the allocated filesystem, not just total node disk capacity. Allow several hours for the first build and debugging session.
- Run the core containers, gNB, **one** RFsim nrUE, nearRT-RIC, xApp, and AI server on this node. RFsim transports samples over software sockets; no SDR allocation is needed for this stage.
- Keep RIC/AI connections on loopback and core traffic on the Docker bridge. Later multi-host experiments should use POWDER's experimental network.

Use a single-node bare-metal profile with hardware type **`d430`** and an **Ubuntu 24.04** image. The guided session used the
[`PortalProfiles/single-pc`](https://www.powderwireless.net/p/PortalProfiles/single-pc) template as the starting point. POWDER also advertises an `oai_nr_sim` profile, but its installed OAI version/configuration must be checked: this experiment needs **this repository's modified sources**.

References: [POWDER hardware](https://docs.powderwireless.net/hardware.html), [starter profiles](https://docs.powderwireless.net/powder-profiles.html), [reservations](https://docs.powderwireless.net/reservations.html).

## 1. Architecture

```text
                      POWDER Linux node

  OAI nrUE <-- RFsim --> OAI gNB <--- N2/N3 ---> OAI 5G Core
                           |
                     DPP DL scheduler
                           |
                      E2 agent / custom MAC SM
                           | E2AP / SCTP
                      FlexRIC nearRT-RIC
                           |
                      Python DRL xApp
                           | HTTP / JSON (localhost:8000)
                      FastAPI AI server
                           |
                      Stable-Baselines3 DQN or PPO
```

The gNB still makes slot-level scheduling decisions. The xApp subscribes at **1,000 ms** and changes the scheduler's parameter indices on that slower loop. The current scheduler assumes a **0.5 ms slot (numerology 1)**. The AI does not directly assign individual PRBs each slot.

All paths below are relative to the repository root:

| Component | Entry point and role |
| --- | --- |
| Scheduler | `openairinterface5g/openair2/LAYER2/NR_MAC_gNB/gNB_scheduler_dlsch.c`: `scheduler_custom()`, virtual throughput queues, eligibility/ranking, and resource allocation. The normal DL path calls this custom scheduler. |
| Scheduler state | `openairinterface5g/openair2/LAYER2/NR_MAC_gNB/nr_mac_gNB.h`: `e2_mac_ctrl` stores per-UE `v`, `wq`, and `wg` indices. |
| OAI/E2 adapter | `openairinterface5g/openair2/E2AP/RAN_FUNCTION/CUSTOMIZED/ran_func_mac.c`: exports telemetry in `read_mac_sm()` and applies controls in `write_ctrl_mac_sm()`. |
| Wire format | `openairinterface5g/openair2/E2AP/flexric/src/sm/mac_sm/`: modified MAC indication/control structures and plain encoders/decoders. |
| Python/C++ boundary | `openairinterface5g/openair2/E2AP/flexric/src/xApp/swig/`: SWIG SDK and MAC callbacks/control wrapper. |
| xApp | `openairinterface5g/openair2/E2AP/flexric/examples/xApp/python3/xapp_drl_scheduling.py`: computes interval throughput/reward, calls `/configure` and `/infer_sched_config`, and sends MAC control. |
| AI service | `server_drl.py`: FastAPI endpoints and background model training. Defaults to training from scratch, not loading a trained policy. |
| Environments | `env/env_DQN_Basic.py`, `env/env_PPO_Basic.py`: Gymnasium observation/action spaces and synchronization with live telemetry. |
| Core | `openairinterface5g/doc/tutorial_resources/oai-cn5g/`: Compose file, core configuration, and test subscriber records. |
| Measurements | `ue_qos_stats.csv` in the gNB working directory; `learning_curve_Basic.csv` in the AI server working directory; plotting notebook under `openairinterface5g/figs/`. |

The intended observation is `[mcs_0...mcs_N, q_0...q_N, g_0...g_N]`, with one flow per UE in the current adapter. Control is a global `v` index plus per-UE `wq` and `wg` index arrays. The intended `v` lookup is `[0, 50, 200, 600]`. DQN currently has `4 * 2**num_ues` actions (64 with four UEs); PPO currently varies only `v`, because both weight dimensions have one state.

The reward combines GFBR satisfaction and resource usage: the xApp assumes GFBRs of `[3, 3, 6, 6]` Mbps and an RB budget of 212,000 per reporting interval. These are experiment-specific constants, not values discovered from the RAN.

OAI and FlexRIC are **vendored ordinary files** in this Git repository. The nested OAI `.gitmodules` file is inherited metadata; it does not make this checkout a stock OAI/FlexRIC deployment. Build the bundled FlexRIC and install its SMs so the gNB, RIC, and xApp agree on the custom MAC ABI.

## 2. Confirmed blockers and repair order

### Before the first AI-controlled run

1. **Binary action serialization is incorrect.** `send_control_mac()` converts weights to a string and calls `cp_str_to_ba()`, whose implementation uses `strlen()`. Zero is a valid action index, so arrays are truncated at the first zero; later C code copies `n_users` bytes from that undersized allocation. Replace this with length-aware byte/array bindings and explicit ownership. A local compiled probe calling the actual helper confirmed that `[0,1,0,1]` copies zero bytes and `[1,0,1,0]` copies one byte.

2. **Fractional scheduler weights are lost.** `WQ_DICT` and `WG_DICT` are `uint32_t[2] = {0.1, 1}`. The local `wq`/`wg` variables are also integers. Consequently index zero means zero, not 0.1. Both the tables and consuming variables need floating-point types. A compiled C probe confirmed the conversion to `{0, 1}`. This particularly affects PPO, which always selects weight index zero with its current action space.

3. **UE cardinality and control identity are inconsistent.** The xApp configures four UEs unconditionally, while the indication contains the actual connected UEs. A one-UE observation therefore has the wrong shape for that model. Configure a fixed one-UE experiment first, validate array lengths, and stop or reconfigure deliberately on UE-set changes. The OAI writer also iterates all connected UEs without checking `msg->n_users`. Controls are positional rather than RNTI-addressed; dynamic attachment/reordering requires additional work.

4. **Queue telemetry does not match the AI observation contract.** OAI assigns raw byte backlog and a large virtual queue to `uint8_t` fields, causing truncation/wraparound. The environments instead declare queue classes in `[0,2]`. Define meaningful discretization thresholds/units or widen and normalize the observations consistently across the SM, xApp, and environment. MCS is already discretized to `[0,1,2]`; zero is a valid low-MCS class, not a disconnected UE.

5. **The server lifecycle and baseline modes need repair.** Fresh `Static` and `Random` configuration requests reach an invalid-model return; static actions use scalar weights instead of lists, and random inference refers to an unassigned `num_ues`. Condition waits have no predicate or timeout, blocking work occurs inside async endpoints, and `/stop_training` clears the thread reference without stopping the worker. Reconfiguration can replace state while an old worker is active. Only Basic environments are present; ISAC branches refer to undefined classes. Validate supported requests, implement a bounded state/action handshake and real shutdown, and test observation/action/reward alignment before trusting training results.

6. **HTTP failure handling is incomplete.** The xApp has no request timeouts or HTTP/status/schema checks. An error JSON can be treated as an action. Use bounded calls and validate `v`, list lengths, and each index before E2 control.

### Before sustained experiments or scheduler-performance claims

- The scheduler's `qsort` comparator returns only 0 or 1 rather than a valid negative/zero/positive ordering. Fix ranking and exercise ties explicitly.
- MAC read/write functions need a concurrency review against the scheduler's lock/UE lifetime rules. Validate count mismatches before accessing arrays.
- The MAC indication cleanup omits the newly allocated `bytes`/`rbs` arrays; the SWIG callback deep-copies dynamic fields without corresponding cleanup; decoded control arrays also need ownership cleanup.
- GFBR is indexed by UE UID from a fixed five-entry array. The xApp has four-entry statistics/GFBR arrays. Neither is a general multi-UE implementation.
- Reward accounting assumes a one-second interval and stable UE ordering, and starts counter deltas from zero. Establish an initial baseline and use actual indication intervals and per-RNTI counters before measuring performance.
- Per-slot informational logging can dominate runtime. Reduce it after initial control verification. Audit virtual-queue units and update timing alongside throughput/RB accounting.
- The bundled C `examples/xApp/c/ctrl/mac_ctrl.c` is not a working substitute for the Python xApp: it initializes the `wq` pointer to integer `42`.

## 3. Node preparation and builds

On the allocated node, first collect:

```bash
uname -a
cat /etc/os-release
lscpu
free -h
df -h
```

Use the same repository revision, including local bring-up fixes, on the node. The following assumes it is checked out at `~/oai-mac-ai-scheduler`. Define these variables in each terminal (or in your tmux session):

```bash
export REPO="$HOME/oai-mac-ai-scheduler"
export OAI="$REPO/openairinterface5g"
export FLEXRIC="$OAI/openair2/E2AP/flexric"
```

### Dependencies

```bash
sudo apt update
sudo apt install -y build-essential gcc-13 g++-13 cmake ninja-build ccache \
  git pkg-config libsctp-dev lksctp-tools libpcre2-dev libsqlite3-dev \
  swig python3-dev python3-venv python3-pip tmux iperf
sudo modprobe sctp
gcc-13 --version
swig -version
python3 --version
```

Ubuntu 24.04 provides Python 3.12 and a sufficiently recent SWIG. This FlexRIC requires **SWIG >= 4.1** and explicitly rejects GCC 11. Docker installation and verification using Ubuntu's packages are included in the core startup section below.

### FlexRIC, including the Python SDK

The original checkout requires the SWIG example-copy and KPM SQLite/test-data
fixes recorded in [the troubleshooting ledger](LAB_CHECKPOINT.md#3-procedure-and-troubleshooting-ledger).
Use the corrected source revision/diff from your POWDER session when reproducing
the lab. Those fixes were applied manually on the node.


```bash
cmake -S "$FLEXRIC" -B "$FLEXRIC/build" \
  -DCMAKE_C_COMPILER=gcc-13 -DCMAKE_CXX_COMPILER=g++-13 \
  -DCMAKE_BUILD_TYPE=Debug -DXAPP_MULTILANGUAGE=ON \
  -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib \
  -DPython3_EXECUTABLE=/usr/bin/python3 \
  -DPYTHON_INCLUDE_DIR=/usr/include/python3.12 \
  -DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/libpython3.12.so \
  -DE2AP_VERSION=E2AP_V2 -DKPM_VERSION=KPM_V2_03
cmake --build "$FLEXRIC/build" -j8
sudo cmake --install "$FLEXRIC/build"
sudo ldconfig
ctest --test-dir "$FLEXRIC/build" --output-on-failure --parallel 4 --timeout 120
```

Keep build/test output if any target fails; the extended service model must be checked with its bundled tests, rather than assuming upstream tests cover the new arrays. Default installation places SMs in `/usr/local/lib/flexric/` and the configuration in `/usr/local/etc/flexric/flexric.conf`.

### OAI gNB and nrUE with RF simulation and E2

```bash
cd "$OAI/cmake_targets"
./build_oai -I -w SIMU

export OAI_BUILD="$OAI/cmake_targets/ran_build/build"
cmake -S "$OAI" -B "$OAI_BUILD" -G "Unix Makefiles" \
  -DCMAKE_C_COMPILER=/usr/bin/gcc-13 \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++-13 \
  -DOAI_SIMU=ON -DAVX512=OFF \
  -DE2_AGENT:STRING=ON \
  -DE2AP_VERSION:STRING=E2AP_V2 \
  -DKPM_VERSION:STRING=KPM_V2_03

grep -E '^(CMAKE_GENERATOR|E2_AGENT|E2AP_VERSION|KPM_VERSION):' \
  "$OAI_BUILD/CMakeCache.txt"
```

Verify that the cache says `E2_AGENT=ON`, `E2AP_V2`, and `KPM_V2_03` before compiling. The guided session encountered both a Ninja/Makefiles generator mismatch and a successful build with E2 disabled. Its existing build tree used Unix Makefiles. Investigate configuration errors or unexpected cache values before proceeding.

```bash
cmake --build "$OAI_BUILD" --parallel 8 \
  --target nr-softmodem nr-cuup nr-uesoftmodem \
    params_libconfig coding rfsimulator dfts params_yaml vrtsim

nm "$OAI_BUILD/nr-softmodem" \
  | grep -E ' (init_agent_api|read_mac_sm|write_ctrl_mac_sm)$'
```

The OAI and FlexRIC E2AP/KPM versions must match. Expected OAI binaries are under
`$OAI/cmake_targets/ran_build/build/`. Build from this source tree to retain the
DPP scheduler and extended MAC SM.

### AI Python environment (CPU)

The root `requirements.txt` is a full environment freeze containing Linux/CUDA packages and does not list the xApp's `requests` dependency. For the initial Ubuntu 24.04 CPU setup, install the direct runtime dependencies instead:

```bash
cd "$REPO"
python3 -m venv venv
venv/bin/python -m pip install --upgrade pip
venv/bin/python -m pip install torch==2.9.1 --index-url https://download.pytorch.org/whl/cpu
venv/bin/python -m pip install fastapi==0.123.8 uvicorn==0.38.0 \
  stable_baselines3==2.7.0 gymnasium==1.2.2 numpy==2.3.5 requests==2.32.5
export PYTHONPATH="$FLEXRIC/build/src/xApp/swig${PYTHONPATH:+:$PYTHONPATH}"
venv/bin/python -c 'import xapp_sdk, fastapi, stable_baselines3, requests; print("Imports OK")'
```

Build the SDK and run the xApp with the same Python major/minor ABI. Keep the AI server at **one Uvicorn worker** because model/environment state is process-local.

## 4. First milestone: RFsim attachment and downlink traffic

Start each foreground process in a separate terminal/tmux pane. Check each milestone before moving on.

### Core

The guided setup used Ubuntu's Docker Engine and Compose v2 packages. On a node that does not already have a working Docker installation:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
```

Start the data-connectivity services using Bash:

```bash
cd "$OAI/doc/tutorial_resources/oai-cn5g"
CORE_SERVICES=(mysql oai-nrf oai-udr oai-udm oai-ausf oai-amf oai-smf oai-upf oai-ext-dn)
sudo modprobe sctp
sudo docker compose config --quiet
sudo docker compose pull "${CORE_SERVICES[@]}"
sudo docker compose up -d --wait --wait-timeout 180 mysql oai-nrf
sudo docker compose up -d --wait --wait-timeout 240 "${CORE_SERVICES[@]}"
sudo docker compose ps -a
sudo docker compose logs --tail=100 oai-amf oai-smf oai-upf
ip -4 addr show dev oai-cn5g
```

Confirm that the first test subscriber was loaded:

```bash
sudo docker compose exec -T mysql mysql -utest -ptest oai_db \
  -e "SELECT ueid, authenticationMethod FROM AuthenticationSubscription WHERE ueid = '001010000000001';"
```

Expected: one row for `001010000000001` with authentication method `5G_AKA`.

For a same-node resume, use the staged startup commands with the already
downloaded images. Preserve the existing containers/database with
`docker compose stop` when pausing; see the checkpoint for the full shutdown order and evidence capture.

The bundled core uses `192.168.70.128/26`: AMF `.132`, UPF `.134`, external data network `.135`. The Docker bridge normally receives `.129`; confirm it before using the commands below. The subscriber database contains IMSI `001010000000001`, DNN `oai`, SST `1`, and its test authentication material.

The Compose images use moving `develop`/`latest` tags. Record pulled image digests and the Git revision after the first successful setup so it can be recreated.

### nearRT-RIC

```bash
set -o pipefail
"$FLEXRIC/build/examples/ric/nearRT-RIC" \
  -c /usr/local/etc/flexric/flexric.conf -p /usr/local/lib/flexric/ \
  2>&1 | tee "$HOME/nearRT-RIC.log"
```

The bundled configuration uses `NEAR_RIC_IP = 127.0.0.1`.

### gNB

The bundled `gnb.sa.band78.fr1.106PRB.usrpb210.conf` was customized for a different testbed: PLMN **999/70**, AMF `192.168.112.27`, gNB `192.168.112.26`, and two RF chains. Override these for the bundled core and initial one-chain RFsim run:

```bash
cd "$OAI/cmake_targets/ran_build/build"
set -o pipefail
sudo ./nr-softmodem \
  -O "$OAI/targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb.sa.band78.fr1.106PRB.usrpb210.conf" \
  --rfsim \
  --rfsimulator.serveraddr server \
  '--gNBs.[0].min_rxtxtime' 6 \
  '--gNBs.[0].plmn_list.[0].mcc' 001 \
  '--gNBs.[0].plmn_list.[0].mnc' 01 \
  '--gNBs.[0].plmn_list.[0].mnc_length' 2 \
  '--gNBs.[0].amf_ip_address.[0].ipv4' 192.168.70.132 \
  '--gNBs.[0].NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_NG_AMF' 192.168.70.129 \
  '--gNBs.[0].NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_NGU' 192.168.70.129 \
  '--RUs.[0].nb_tx' 1 '--RUs.[0].nb_rx' 1 \
  --e2_agent.near_ric_ip_addr 127.0.0.1 \
  --e2_agent.sm_dir /usr/local/lib/flexric/ \
  --log_config.global_log_level info \
  --log_config.ngap_log_level info \
  --log_config.rrc_log_level info \
  --log_config.mac_log_level warning \
  2>&1 | tee "$HOME/gnb-rfsim.log"
```

Expect an NG setup with the AMF and an E2 setup with the RIC. The configuration includes an `e2_agent` block. Leave the gNB running while it waits for the RFsim peer, then start the UE. The MAC log level limits the custom scheduler's per-slot informational output.

### One nrUE

```bash
cd "$OAI/cmake_targets/ran_build/build"
set -o pipefail
sudo ./nr-uesoftmodem -r 106 --numerology 1 --band 78 -C 3619200000 \
  --rfsim --rfsimulator.serveraddr 127.0.0.1 \
  --uicc0.imsi 001010000000001 \
  --uicc0.key fec86ba6eb707ed08905757b1bb44b8f \
  --uicc0.opc C42449363BBAD02B66D16BC975D77CC1 \
  --uicc0.dnn oai --uicc0.nssai_sst 1 \
  2>&1 | tee "$HOME/ue-rfsim.log"
```

These are the bundled core's test credentials. The supplied `ue.conf` contains another testbed's credentials/DNN and a satellite-channel include, so this command sets the subscriber parameters explicitly. Check registration, PDU session establishment, and the assigned IP:

```bash
ip -4 addr show dev oaitun_ue1
ping -c 5 -I oaitun_ue1 192.168.70.135
```

Generate **downlink** traffic to exercise the modified scheduler. The database requests `10.0.0.2` for the first UE; substitute the actual TUN address if different. Start the UDP receiver on the node:

```bash
iperf -s -u -B 10.0.0.2 -i 1 2>&1 | tee "$HOME/iperf-server.log"
```

Then send from the external data-network container in another terminal:

```bash
sudo docker exec oai-ext-dn iperf -c 10.0.0.2 -u -i 1 -t 30 -b 5M \
  2>&1 | tee "$HOME/iperf-client.log"
```

Require received traffic at the UE and rising gNB DL byte/RB counters. A sender report alone does not establish successful delivery.

## 5. Second milestone: close the scheduler control loop

Complete the repairs in section 2 before treating the DRL xApp as runnable with the one-UE experiment. In particular, its current hardcoded four-UE configuration will not match the observation produced above.

Recommended verification sequence:

1. Subscribe to MAC telemetry and inspect one UE's RNTI, counter deltas, MCS class, queue state, and indication timestamps.
2. Send a **known fixed action** with zero and nonzero indices. Check identical values at the xApp, decoded E2 control, and scheduler lookup. The existing Static server branch needs repair before it can provide this baseline.
3. Exercise the AI API without E2, using synthetic one-UE observations. Check valid action shapes, bounded responses, clean shutdown/reconfiguration, and correct reward alignment across multiple training updates.
4. Start a fresh AI server and then the repaired xApp, from the repository root:

   ```bash
   cd "$REPO"
   venv/bin/python -m uvicorn server_drl:app --host 127.0.0.1 --port 8000 --workers 1
   ```

   In another terminal with `REPO`, `FLEXRIC`, and `PYTHONPATH` set as above:

   ```bash
   cd "$REPO"
   venv/bin/python "$FLEXRIC/examples/xApp/python3/xapp_drl_scheduling.py"
   ```

5. Confirm the full chain: **MAC indication → HTTP inference → valid action → E2 control → changed scheduler parameters**, while downlink traffic continues.
6. Run long enough to cross model update boundaries, monitor memory/latency, and exercise clean shutdown. The original defaults are 100,000 training steps, which at one indication/second are roughly 28 hours before overhead.

Success means UE attachment, working downlink data, sustained telemetry,
valid AI responses, and demonstrated application of controls at the gNB.
Improved scheduling performance is a separate experiment requiring a fixed baseline, reproducible load/channel conditions, and consistent metrics.

Then add a second UE using the bundled [multi-UE namespace tutorial](../openairinterface5g/doc/NR_SA_Tutorial_OAI_multi_UE.md). The namespace isolation avoids confusing host-local routing with traffic that
actually traverses the UE and core. Expand to four UEs after count/identity and reward handling are verified.

## 6. Pause, resume, and lab records

The experimenter runs the commands on POWDER and shares relevant output when diagnosis is needed. Preserve build logs, configuration, image digests, model settings, and the actual Git revision/diff with each experiment.

See the [lab checkpoint](LAB_CHECKPOINT.md) for the shutdown order, same-node restart procedure, evidence-bundle commands, recorded downlink result, and a lab-assignment outline. Archive logs before restarting and download the bundle before terminating or allowing the POWDER experiment to expire.
