# OAI (+ FlexRIC) MAC AI Scheduler

This repository extends **OpenAirInterface (OAI)** with a **drift-plus-penalty MAC scheduler** and a **FlexRIC** xApp and extended **MAC E2 Service Model** to connect to external AI modules, enabling **dynamic reconfiguration of the scheduler** based on real-time network conditions.

## Main Components

- **OAI:**
    
    - Contains a modified **MAC scheduler** implementing the **drift-plus-penalty** algorithm (resource eficiency, throughput optimization and queue stability).
        
    - Includes new variables for collecting runtime statistics and scheduler-related metrics used for analysis or learning feedback.
        
- **FlexRIC:**
    
    - Integrates an **xApp** that acts as a _connector_ between the OAI testbed and an **external AI module**.
        
    - The AI module trains an agent capable of inferring suitable scheduling weights.
        
    - The **MAC E2 Service Model** has been extended to support additional subscription and control functionality:
        
        - The xApp can subscribe to relevant RAN data and provide it to the AI module.
            
        - The xApp can compute and report a reward associated with the agent's performance.
            
        - The xApp delivers the updated scheduling weights back to the MAC scheduler via the FlexRIC E2 interface.
            

## AI Module

- The xApp communicates with the external AI module via **REST** API.

- AI module training can be performed using ns-3 simulations (see [RBIS repo](https://github.com/tlmat-unican/RBIS)).  

## Repository Structure

```
oai-mac-ai-scheduler/
├── openairinterface5g/
│   ├── openair2/LAYER2/NR_MAC_gNB/
│   │    └─── gNB_scheduler_dlsch.c               # DPP MAC scheduler implementation
│   └── openair2/E2AP/
│        ├── flexric/
│        │    ├── examples/xApp/python3/
│        │    │    └─── xapp_drl_scheduling.py    # Custom xApp (RAN-AI connector)
│        │    └── src/sm/mac_sm/                  # Extended MAC Service Model
│        └── RAN_FUNCTION/CUSTOMIZED/
│             └── ran_func_mac.c                  # E2-MAC interface
├── env/                                          # DRL environments
├── scripts/                                      # Core, RIC, gNB, and nrUE launchers
└── server_drl.py                                 # REST API server (AI module)
└── monitor_mac.py                                # Read-only MAC telemetry helper
```

## Build and Run

For a source-level readiness assessment and a staged single-node POWDER **d430** RFsim deployment procedure, see [POWDER d430 RFsim bring-up](docs/POWDER_RFSIM.md). It records the current AI control-loop blockers, required toolchain, and core/gNB settings that must match before running this testbed.

The [lab checkpoint](docs/LAB_CHECKPOINT.md) records the guided POWDER session's fixes and downlink result, evidence still to collect, shutdown/restart steps, and a lab-assignment outline.

1. **Clone the repository**

```bash
git clone https://github.com/tlmat-unican/oai-mac-ai-scheduler.git
cd oai-mac-ai-scheduler
```

2. **Setup OAI RAN + FlexRIC + Core**

See [References](#references) for complete installation.

3. **Enable dynamic AI reconfiguration (optional)**

    **3.1 Start AI Module (DRL server)**

    ```bash
    uvicorn server_drl:app --host 0.0.0.0 --port 8000
    ```

    **3.2 Run xApp**

    ```bash
    export PYTHONPATH=openairinterface5g/openair2/E2AP/flexric/build/src/xApp/swig:$PYTHONPATH
    python3 openairinterface5g/openair2/E2AP/flexric/examples/xApp/python3/xapp_drl_scheduling.py
    ```

4. **Plot collected metrics**

Open ``openairinterface5g/figs/plot_metrics.ipynb`` in Jupyter to visualize results.

## POWDER RFsim startup scripts

After building OAI/FlexRIC and installing the service models and Docker, run the launchers on the **POWDER Linux node** as your normal user; they invoke `sudo` where needed. From the repository root:

| Order | Command | Component |
| --- | --- | --- |
| 1 | `./scripts/run_core.sh start` | Start the bundled core containers and wait for readiness. |
| 2 | `./scripts/run_ric.sh` | Start nearRT-RIC in a foreground terminal. |
| 3 | `./scripts/run_gnb.sh` | Start the E2-enabled gNB in another terminal. |
| 4 | `./scripts/run_ue.sh` | Start one RFsim UE in another terminal. |

The scripts resolve the checkout location automatically and use the configuration from the single-node d430 procedure. Run each script with `--help` for its
environment overrides. RIC/gNB/UE logs have timestamped filenames under `~/oai-run-logs/` (override with `LOG_DIR`).

Use `./scripts/run_core.sh status` to inspect the core and `./scripts/run_core.sh logs oai-amf oai-smf oai-upf` for recent core logs. To pause, stop traffic and any xApp, then stop the UE, gNB, and RIC with Ctrl+C. Finally, `./scripts/run_core.sh stop` stops the containers while retaining their storage. See the [runbook](docs/POWDER_RFSIM.md#startup-scripts) for the startup checks and the equivalent underlying commands.

## Read-only MAC telemetry

With the nearRT-RIC, one E2-enabled gNB, and an attached UE running, use the repository's [MAC monitor](monitor_mac.py) to check the Python telemetry path:

```bash
export FLEXRIC="$PWD/openairinterface5g/openair2/E2AP/flexric"
export PYTHONPATH="$FLEXRIC/build/src/xApp/swig${PYTHONPATH:+:$PYTHONPATH}"
python3 -u monitor_mac.py --duration 20
```

Run these commands from the repository root with the same Python major/minor version used to build the SDK. The helper subscribes to one-second MAC reports, prints RNTI, flow count, raw downlink MCS, and cumulative MAC byte/PRB counters, then unsubscribes and shuts down. It is a bring-up utility independent of the AI server. See the [RFsim runbook](docs/POWDER_RFSIM.md#read-only-mac-telemetry) for prerequisites and expected output.

## References

- [OpenAirInterface (OAI)](https://openairinterface.org/)

- [FlexRIC](https://gitlab.eurecom.fr/mosaic5g/flexric)
