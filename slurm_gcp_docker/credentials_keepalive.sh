#!/bin/bash
#
# Keep the user's credential secret alive for as long as this cluster lives.
#
# The secret carries a short rolling TTL (canine sets it at creation). This loop
# pushes expire_time forward; if it stops, the secret self-deletes within one
# TTL. That is the intended cleanup path for a cluster that died without
# teardown -- SIGKILL, a dead VM, a `docker kill` -- where nothing runs to
# delete it explicitly.
#
# WHY THIS RUNS IN THE CONTROLLER CONTAINER, not in the wolF driver:
# wolF sets shutdown_on_exit=False, so the controller container deliberately
# outlives the driver process, and Slurm keeps creating workers after the
# driver exits. A driver-hosted keepalive would stop renewing while the cluster
# was still scheduling work, and every worker created after the TTL elapsed
# would fail to fetch credentials.
#
# Renewal is an admin operation on Secret Manager, which is NOT billed -- only
# AccessSecretVersion is. So a short TTL with frequent renewal costs nothing and
# shortens the window in which credentials outlive a dead cluster.
#
# Started in the background by docker_entrypoint_controller.sh.

export CLOUDSDK_CONFIG=${CLOUDSDK_CONFIG:-/slurm_gcloud_config}

RENEW_INTERVAL=${CREDENTIALS_RENEW_INTERVAL:-300}   # 5m, against a 1h TTL
TTL=${CREDENTIALS_TTL:-3600}

# canine records the secret name here when it publishes credentials.
CONF=/mnt/nfs/clust_conf/canine/backend_conf.pickle

get_secret_name() {
	[ -f "$CONF" ] || return 1
	python3 - "$CONF" <<'PY' 2>/dev/null
import pickle, sys
try:
    with open(sys.argv[1], "rb") as f:
        c = pickle.load(f)
    n = c.get("credentials_secret")
    if n:
        print(n)
except Exception:
    pass
PY
}

while true; do
	SECRET=$(get_secret_name)
	if [ -n "$SECRET" ]; then
		if ! gcloud secrets update "$SECRET" --ttl="${TTL}s" --quiet >/dev/null 2>&1; then
			# Non-fatal and expected in two benign cases: the secret was already
			# deleted at teardown, or it expired while this loop was asleep.
			echo "$(date) could not renew credential secret ${SECRET}" >&2
		fi
	fi
	sleep "$RENEW_INTERVAL"
done
