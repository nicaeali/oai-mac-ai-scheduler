"""Read-only, one-second MAC telemetry for a single connected FlexRIC E2 node."""

import argparse
import importlib
from pathlib import Path
import signal
import sys
import time


def make_monitor(ric):
    """Create the callback after loading the native SDK."""
    class MACMonitor(ric.mac_cb):
        def __init__(self):
            ric.mac_cb.__init__(self)
            self.records = 0
            self.error = None

        def handle(self, ind):
            # Keep Python exceptions from escaping through the SWIG director.
            try:
                for ue in ind.ue_stats:
                    print(
                        f"[MAC] timestamp_us={int(ind.tstamp)} "
                        f"RNTI=0x{int(ue.rnti):04x} "
                        f"flows={int(ue.n_flows)} "
                        f"DL_MCS={int(ue.dl_mcs1)} "
                        f"DL_total_bytes={int(ue.dl_aggr_tbs)} "
                        f"DL_total_PRBs={int(ue.dl_aggr_prb)}",
                        flush=True,
                    )
                    self.records += 1
            except Exception as exc:
                self.error = repr(exc)
                print(f"[MAC ERROR] {self.error}", file=sys.stderr, flush=True)

    return MACMonitor()


def stop_sdk(ric, handle):
    if handle is not None:
        ric.rm_report_mac_sm(handle)
        # Let in-flight callbacks finish and the unsubscribe acknowledgement arrive.
        time.sleep(1)

    deadline = time.monotonic() + 10
    while not ric.try_stop():
        if time.monotonic() >= deadline:
            raise RuntimeError("Timed out waiting for xApp shutdown")
        time.sleep(0.1)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--duration", type=int, default=20,
        help="seconds to monitor after subscribing (default: 20)",
    )
    args = parser.parse_args(argv)
    if args.duration < 1:
        parser.error("--duration must be at least 1 second")

    try:
        ric = importlib.import_module("xapp_sdk")
    except ImportError as exc:
        sdk_path = (
            Path(__file__).resolve().parent
            / "openairinterface5g/openair2/E2AP/flexric/build/src/xApp/swig"
        )
        print(
            f"Cannot import the FlexRIC Python SDK: {exc}\n"
            "Build the bundled FlexRIC with -DXAPP_MULTILANGUAGE=ON, use the "
            "same Python major/minor version, and add this directory to PYTHONPATH:\n"
            f"{sdk_path}",
            file=sys.stderr,
        )
        return 1

    initialized = False
    handle = None
    monitor = None
    status = 0
    previous_sigint = signal.getsignal(signal.SIGINT)
    try:
        print("Connecting to FlexRIC; the nearRT-RIC must already be running.", flush=True)
        ric.init()
        initialized = True
        signal.signal(signal.SIGINT, signal.default_int_handler)

        deadline = time.monotonic() + 10
        nodes = ric.conn_e2_nodes()
        while len(nodes) == 0 and time.monotonic() < deadline:
            time.sleep(0.2)
            nodes = ric.conn_e2_nodes()
        print(f"Connected E2 nodes: {len(nodes)}", flush=True)
        if len(nodes) != 1:
            raise RuntimeError(f"Expected one connected E2 node, found {len(nodes)}")

        # Retain both the node list and callback until native shutdown completes.
        monitor = make_monitor(ric)
        handle = ric.report_mac_sm(nodes[0].id, ric.Interval_ms_1000, monitor)
        print(f"Monitoring MAC for {args.duration} seconds...", flush=True)
        deadline = time.monotonic() + args.duration
        while True:
            if monitor.error is not None:
                raise RuntimeError(f"MAC callback failed: {monitor.error}")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            time.sleep(min(0.1, remaining))
    except KeyboardInterrupt:
        print("Stopping MAC monitor...", flush=True)
        status = 130
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr, flush=True)
        status = 1
    finally:
        if initialized:
            try:
                stop_sdk(ric, handle)
            except Exception as exc:
                print(f"[SHUTDOWN ERROR] {exc}", file=sys.stderr, flush=True)
                status = 1
        signal.signal(signal.SIGINT, previous_sigint)

    if status == 0:
        if monitor.error is not None:
            print(f"[ERROR] MAC callback failed: {monitor.error}", file=sys.stderr)
            return 1
        if monitor.records == 0:
            print("[ERROR] No MAC UE records received. Check UE attachment and MAC subscription logs.", file=sys.stderr)
            return 1
        print(f"Received {monitor.records} MAC UE records.", flush=True)
    return status


if __name__ == "__main__":
    sys.exit(main())
