"""Read-only production asset sampling; never measures authenticated app readiness.

No scripts execute, credentials are sent, or business data is requested.
Every sample opens an independent HTTP request. These are transport samples,
not browser cold/warm navigation, CLS, rendering or database measurements.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import math
import pathlib
import statistics
import time
import urllib.request

ASSETS = ["tasks/index.html", "fleet/index.html", "recruitment/index.html",
          "assets/js/shell-components.js", "assets/css/app-theme.css"]


def sample(item):
    asset, attempt = item
    started = time.perf_counter()
    try:
        request = urllib.request.Request("https://one.atwargroup.com/" + asset,
                                         headers={"User-Agent": "ATWAR-static-baseline"})
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read()
            status = response.status
        return {"asset": asset, "attempt": attempt, "status": status,
                "total_ms": round((time.perf_counter() - started) * 1000, 2),
                "bytes": len(body), "sha256": hashlib.sha256(body).hexdigest()}
    except Exception as error:
        return {"asset": asset, "attempt": attempt, "error": type(error).__name__}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        samples = list(pool.map(sample, [(asset, i) for asset in ASSETS for i in range(1, 11)]))
    summary = []
    for asset in ASSETS:
        rows = [row for row in samples if row["asset"] == asset]
        times = sorted(row["total_ms"] for row in rows if row.get("status") == 200)
        summary.append({"asset": asset, "successes": len(times), "attempts": len(rows),
                        "median_ms": round(statistics.median(times), 2) if times else None,
                        "p95_ms": times[math.ceil(len(times) * .95) - 1] if times else None})
    result = {"captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "Independent HTTP requests from execution host; four concurrent workers. No browser cache, session, render, CLS or database timings. Not end-user readiness or a before/after improvement claim.",
              "summary": summary, "samples": samples}
    pathlib.Path(args.output).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
