# POWDER RFsim Experiment Notes

## Status and first target

This is an AI-generated, human-verified/modified document.

The repository contains the OAI downlink scheduler, the custom FlexRIC MAC service model, the Python xApp, and the external RL server. It also contains an OAI CN5G Compose example and its subscriber database. The AI control loop has source-level defects listed below; it is **not yet verified end to end**.

The build and deployment commands below are a proposed Linux bring-up procedure, checked against the bundled source and documentation (by AI). They have not been run on a POWDER node. The local assessment host is macOS/ARM.

Recommended first experiment:

- One **bare-metal x86_64 node with Ubuntu 24.04**, sudo access, and Internet access for package/build dependencies and container images.
- Target a **d430**, prioritizing its greater availability: two Intel Xeon E5-2630 v3 CPUs (16 physical cores total, 2.4 GHz) and **64 GB RAM**. Start with one simulated UE and measure RFsim performance before adding more UEs. CPU execution is sufficient for the initial small DQN/PPO networks.
- Allow at least **50 GB free disk**, preferably 100 GB, for sources, builds, core images, and logs. Check the allocated filesystem, not just total node disk capacity. Allow several hours for the first build and debugging session.
- Run the core containers, gNB, **one** RFsim nrUE, nearRT-RIC, xApp, and AI server on this node. RFsim transports samples over software sockets; no SDR allocation is needed for this stage.
- Keep RIC/AI connections on loopback and core traffic on the Docker bridge. Later multi-host experiments should use POWDER's experimental network.

Use a single-node bare-metal profile with hardware type **`d430`** and an **Ubuntu 24.04** image. POWDER also advertises an `oai_nr_sim` profile, but its installed OAI version/configuration must be checked: this experiment needs **this repository's modified sources**.

References: [POWDER hardware](https://docs.powderwireless.net/hardware.html),
[starter profiles](https://docs.powderwireless.net/powder-profiles.html),
[reservations](https://docs.powderwireless.net/reservations.html).
