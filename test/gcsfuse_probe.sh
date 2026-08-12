#!/bin/bash
# gcsfuse behavior probe harness.
#
# Settles the UNVERIFIED items in NFS-FUSE-IMPLEMENTATION-PLAN.md Phase 0.4.
# Several design decisions in Phases 4-5 branch on these results, so run this
# BEFORE writing any migration code.
#
# Deliberately NOT baked into the Docker image -- bind-mount it at runtime so
# probes can be iterated without a 2.7GB rebuild:
#
#   docker run --rm --privileged -v /dev:/dev \
#     -v $PWD/slurm_gcp_docker/test:/probe \
#     -v ~/.config/gcloud:/root/.config/gcloud \
#     --entrypoint bash <image> /probe/gcsfuse_probe.sh <bucket-name>
#
# Requires: gcsfuse, fusermount, /dev/fuse, and ADC or a service account with
# read/write on <bucket-name>.
#
# Writes only under gs://<bucket>/_gcsfuse_probe_<pid>/ and removes it at exit.

set -uo pipefail   # NOT -e: a failing probe is a result, not an abort

BUCKET="${1:?usage: gcsfuse_probe.sh <bucket-name>}"
# $$ is always 1 inside a container, so it alone does not make this unique
# across runs -- a stale prefix from a previous run shows up as bogus
# "File exists" failures in P2.
PREFIX="_gcsfuse_probe_$(date +%s)_$$"
MNT="/tmp/gcsfuse_probe_mnt"
LOCAL="/tmp/gcsfuse_probe_local"

PASS=0; FAIL=0; SKIP=0

result() {  # result <id> <PASS|FAIL|INFO|SKIP> <message>
	case "$1" in P*) ;; esac
	printf '%-5s %-6s %s\n' "$1" "[$2]" "$3"
	case "$2" in
		PASS) PASS=$((PASS+1)) ;;
		FAIL) FAIL=$((FAIL+1)) ;;
		SKIP) SKIP=$((SKIP+1)) ;;
	esac
}

hdr() { echo; echo "=== $* ==="; }

cleanup() {
	hdr "cleanup"
	fusermount -u "$MNT" 2>/dev/null || fusermount3 -u "$MNT" 2>/dev/null
	rmdir "$MNT" 2>/dev/null
	rm -rf "$LOCAL"
	gcloud storage rm -r "gs://$BUCKET/$PREFIX" 2>/dev/null && echo "removed gs://$BUCKET/$PREFIX"
	echo
	echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
	echo "Record these results in BUCKET_FUSE_MIGRATION.md before proceeding."
}
trap cleanup EXIT

hdr "environment"
echo "gcsfuse:     $(command -v gcsfuse || echo MISSING) $(gcsfuse --version 2>/dev/null)"
echo "fusermount:  $(command -v fusermount || echo MISSING)"
echo "fusermount3: $(command -v fusermount3 || echo MISSING)"
echo "/dev/fuse:   $([ -c /dev/fuse ] && echo present || echo MISSING)"
echo "fuse.conf:   $(grep -c '^user_allow_other' /etc/fuse.conf 2>/dev/null || echo 0) x user_allow_other"
echo "uid/gid:     $(id -u)/$(id -g)"

mkdir -p "$MNT" "$LOCAL"

# Mount read-write. --implicit-dirs is required because we deliberately do NOT
# use hierarchical namespace (see NFS-FUSE.md: Standard bucket + Rapid Cache).
hdr "mounting gs://$BUCKET at $MNT"
if ! gcsfuse --implicit-dirs \
     --file-mode=0755 --dir-mode=0755 \
     --only-dir "$PREFIX" \
     "$BUCKET" "$MNT" 2>&1; then
	# --only-dir on a nonexistent prefix can fail; seed it and retry
	echo "seeding prefix and retrying..."
	echo seed | gcloud storage cp - "gs://$BUCKET/$PREFIX/.seed" || exit 1
	gcsfuse --implicit-dirs --file-mode=0755 --dir-mode=0755 \
	  --only-dir "$PREFIX" "$BUCKET" "$MNT" || exit 1
fi
mountpoint -q "$MNT" && echo "mounted OK" || { echo "MOUNT FAILED"; exit 1; }

# ---------------------------------------------------------------- P1: chmod
hdr "P1 - chmod  (blocker B3: nfs.py:146,152,158 call os.chmod unguarded)"
echo hello > "$MNT/p1.txt"
if chmod 0775 "$MNT/p1.txt" 2>/tmp/p1.err; then
	MODE=$(stat -c %a "$MNT/p1.txt")
	if [ "$MODE" = "775" ]; then
		result P1 PASS "chmod succeeded and mode stuck ($MODE) - B3 may be advisory only"
	else
		result P1 INFO "chmod returned 0 but mode is $MODE (mount --file-mode wins) - silent no-op; de-chmod pass still needed"
	fi
else
	result P1 FAIL "chmod errored: $(cat /tmp/p1.err) - de-chmod pass is MANDATORY, localization would abort"
fi

# ------------------------------------------------------------- P2: symlinks
hdr "P2 - symlink round-trip  (blocker B2: outputs/ is a symlink farm)"
mkdir -p "$MNT/p2/jobs/5/workspace" "$MNT/p2/outputs/5/bam"
echo BAMDATA > "$MNT/p2/jobs/5/workspace/sample.bam"
# Compute the relative path the same way delocalization.py:112 does
# (os.path.relpath(target, os.path.dirname(dest))) rather than hardcoding it --
# an off-by-one in the ../ count looks exactly like a gcsfuse failure.
REL=$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" \
      "$MNT/p2/jobs/5/workspace/sample.bam" "$MNT/p2/outputs/5/bam")
echo "computed relative target: $REL"
if ln -s "$REL" "$MNT/p2/outputs/5/bam/sample.bam" 2>/tmp/p2.err; then
	GOT=$(readlink "$MNT/p2/outputs/5/bam/sample.bam" 2>/dev/null)
	[ "$GOT" = "$REL" ] \
	  && result P2a PASS "readlink round-trips ('$GOT')" \
	  || result P2a FAIL "readlink returned '$GOT', expected '$REL'"

	RESOLVED=$(readlink -f "$MNT/p2/outputs/5/bam/sample.bam" 2>/dev/null)
	[ -n "$RESOLVED" ] && [ -e "$RESOLVED" ] \
	  && result P2b PASS "readlink -f resolves to an existing path ($RESOLVED)" \
	  || result P2b FAIL "readlink -f gave '$RESOLVED' - base.py:1594 would treat outputs as uncaptured and rm -f them"

	CONTENT=$(cat "$MNT/p2/outputs/5/bam/sample.bam" 2>/dev/null)
	[ "$CONTENT" = "BAMDATA" ] \
	  && result P2c PASS "reading through the relative symlink works" \
	  || result P2c FAIL "read through symlink gave '$CONTENT' - '..' traversal broken under --implicit-dirs"

	[ -L "$MNT/p2/outputs/5/bam/sample.bam" ] \
	  && result P2d PASS "os.lexists/-L sees it as a symlink" \
	  || result P2d FAIL "not reported as a symlink (delocalization.py:97 guard would misbehave)"
else
	result P2 FAIL "os.symlink itself failed: $(cat /tmp/p2.err) - outputs MUST become uploads"
fi

# Absolute-target symlink used as a URL container (the scratch-disk pattern,
# delocalization.py:101-102 -> nfs.py:214). Deliberately broken; only the
# stored string matters.
ln -s "/mnt/scratch/canine-scratch-abc123/out.bam" "$MNT/p2/urlref" 2>/dev/null
URLGOT=$(readlink "$MNT/p2/urlref" 2>/dev/null)
[ "$URLGOT" = "/mnt/scratch/canine-scratch-abc123/out.bam" ] \
  && result P2e PASS "broken symlink usable as a URL container (scratch pattern survives)" \
  || result P2e FAIL "URL-container pattern broken: got '$URLGOT'"

# ------------------------------------------------------------------- P3: df
hdr "P3 - df fields  (same_volume: nfs.py:239 uses -P/\$6, delocalization.py:24 uses \$1)"
echo "df -P \$6 (mount point): '$(df -P "$MNT" | awk 'NR>1 {print $6}')'"
echo "df    \$1 (device):      '$(df "$MNT" | awk 'NR>1 {print $1}')'"
echo "df -P line count:        $(df -P "$MNT" | wc -l)  (3 => device name wrapped; delocalization.py:24 lacks -P and would misparse)"
result P3 INFO "compare the two above - they must agree for same_volume() to behave consistently"

# --------------------------------------------------------------- P4: st_dev
hdr "P4 - st_dev  (delocalization.py:111 branches on it)"
D1=$(stat -c %d "$MNT/p2/jobs/5/workspace/sample.bam")
D2=$(stat -c %d "$MNT/p2/outputs/5/bam")
D3=$(stat -c %d "$LOCAL")
echo "st_dev on-mount fileA=$D1  on-mount dirB=$D2  off-mount local=$D3"
[ "$D1" = "$D2" ] && [ "$D1" != "$D3" ] \
  && result P4 PASS "st_dev is uniform within the mount and differs off-mount (branch behaves)" \
  || result P4 INFO "st_dev comparison is degenerate - delocalization.py:111 branch is unreliable"

# ---------------------------------------------------------------- P5: flock
hdr "P5 - flock  (base.py:1507,1633 lock bucket mountpoints)"
if flock -n "$MNT" true 2>/tmp/p5.err; then
	flock -n "$MNT" true 2>/dev/null && \
	  result P5 INFO "flock returns success - but gcsfuse implements no locking, so this is a NO-OP, not mutual exclusion" || true
else
	result P5 INFO "flock failed: $(cat /tmp/p5.err) - base.py:1633's -n guard would misreport mount usage"
fi

# ------------------------------------- P6: FIFOs, append, truncate, hardlink
hdr "P6 - POSIX features  (blockers B4 mkfifo, B7 append)"
mkfifo "$MNT/p6.fifo" 2>/tmp/p6a.err \
  && result P6a INFO "mkfifo unexpectedly SUCCEEDED - recheck B4" \
  || result P6a PASS "mkfifo refused as expected: $(head -1 /tmp/p6a.err) - B4 confirmed, FIFOs must go to local scratch"

printf 'line1\n' > "$MNT/p6.log"
if printf 'line2\n' >> "$MNT/p6.log" 2>/tmp/p6b.err; then
	LINES=$(wc -l < "$MNT/p6.log")
	[ "$LINES" = "2" ] \
	  && result P6b PASS "append via >> produced $LINES lines" \
	  || result P6b FAIL "append produced $LINES lines (expected 2) - data loss on append"
else
	result P6b FAIL "append refused: $(cat /tmp/p6b.err)"
fi

truncate -s 3 "$MNT/p6.log" 2>/tmp/p6c.err \
  && result P6c INFO "truncate succeeded" \
  || result P6c INFO "truncate refused: $(head -1 /tmp/p6c.err)"

ln "$MNT/p1.txt" "$MNT/p6.hardlink" 2>/dev/null \
  && result P6d INFO "hard link unexpectedly succeeded" \
  || result P6d PASS "hard link refused as expected"

# -------------------------------------------------------------- P9: identity
hdr "P9 - authenticating identity"
echo "GOOGLE_APPLICATION_CREDENTIALS=${GOOGLE_APPLICATION_CREDENTIALS:-<unset>}"
echo "CLOUDSDK_CONFIG=${CLOUDSDK_CONFIG:-<unset>}"
gcloud auth list --format="value(account,status)" 2>/dev/null | sed 's/^/  gcloud: /'
curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email \
  2>/dev/null | sed 's/^/  metadata SA: /' || echo "  metadata SA: unavailable (not on GCE)"
result P9 INFO "confirm this is the identity intended to hold bucket IAM"

# ------------------------------------------- P10: streaming write visibility
hdr "P10 - incremental visibility of an open append fd  (blocker B1)"
# Mirrors container_heartbeat.sh:15 / Slurm's stdout fd: a long-lived writer
# whose output must be readable BEFORE the writer exits.
( exec 3> "$MNT/p10.stream"
  echo "first" >&3
  sleep 2
  echo "second" >&3
  sleep 3
  exec 3>&- ) &
WRITER=$!
sleep 3
MID=$(cat "$MNT/p10.stream" 2>/dev/null | tr '\n' ' ')
wait $WRITER
FINAL=$(cat "$MNT/p10.stream" 2>/dev/null | tr '\n' ' ')
echo "visible while writer open (via the mount): '$MID'"
echo "visible after writer closed (via the mount): '$FINAL'"
if [ -n "$MID" ]; then
	result P10a PASS "content visible through the SAME mount before close"
else
	result P10a FAIL "nothing visible through the mount until close"
fi

# P10a alone is not enough: reading back through the same gcsfuse process can be
# served from its own write buffer, which would still be lost if the node dies.
# The preemption question (B1) is specifically whether bytes reach GCS. Check
# from outside the mount, via the API.
( exec 3> "$MNT/p10b.stream"
  echo "durable?" >&3
  sleep 6
  exec 3>&- ) &
WRITER2=$!
sleep 3
if gcloud storage cat "gs://$BUCKET/$PREFIX/p10b.stream" >/tmp/p10b.out 2>/tmp/p10b.err; then
	result P10b PASS "object readable via GCS API while writer still open ('$(tr -d '\n' </tmp/p10b.out)') - bytes are durable pre-close, B1 is survivable"
else
	result P10b FAIL "object NOT in GCS while writer open ($(head -1 /tmp/p10b.err)) - B1 CONFIRMED: a preempted node loses all buffered stdout/stderr. Slurm logs must move to local scratch (Phase 4)"
fi
wait $WRITER2

# ----------------------------------------------------------- not runnable here
hdr "requires real cluster topology - NOT run"
result P7 SKIP "mount propagation into the nested podman task container (needs worker container + podman)"
result P8 SKIP "cross-host metadata staleness (needs two VMs writing/reading the same object)"
