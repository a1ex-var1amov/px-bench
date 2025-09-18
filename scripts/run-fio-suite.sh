#!/usr/bin/env bash
set -euo pipefail

NS=px-bench
MODE=single
HOURS=1
RUNTIME_PER_JOB=""
SIZE=1GiB
SC_LIST="fio-repl1 fio-repl1-encrypted fio-repl2 fio-repl2-encrypted"
PVC_SIZE=20Gi

usage() {
  echo "Usage: $0 [--namespace NS] [--mode single|per-node] [--hours H] [--runtime-per-job SEC] [--size SIZE] [--sc-list \"...\"]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NS="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --hours) HOURS="$2"; shift 2;;
    --runtime-per-job) RUNTIME_PER_JOB="$2"; shift 2;;
    --size) SIZE="$2"; shift 2;;
    --sc-list) SC_LIST="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

kubectl_cmd() {
  if command -v oc >/dev/null 2>&1; then
    oc -n "$NS" "$@"
  else
    kubectl -n "$NS" "$@"
  fi
}

apply_ns() {
  if command -v oc >/dev/null 2>&1; then
    oc apply -f manifests/namespace.yaml
  else
    kubectl apply -f manifests/namespace.yaml
  fi
}

apply_basics() {
  kubectl_cmd apply -f manifests/serviceaccount.yaml
  kubectl_cmd apply -f manifests/results-pvc.yaml
  kubectl_cmd apply -f manifests/configmap-fiojobs.yaml
  kubectl_cmd apply -f manifests/configmap-runner.yaml
}

run_for_sc() {
  local sc="$1"
  echo "Running fio for StorageClass=${sc} mode=${MODE} hours=${HOURS}"

  # Create a PVC+Pod template on the fly from the job/daemonset by overriding env and volume
  if [[ "$MODE" == "single" ]]; then
    kubectl_cmd delete job fio-runner --ignore-not-found
    cat manifests/fio-runner-job.yaml \
      | sed -e "s/name: test-volume/name: test-volume\n        persistentVolumeClaim:\n          claimName: ${sc}-pvc/" \
      | sed -e "s/value: \"single\"/value: \"${sc}\"/" \
      | sed -e "s/name: HOURS\n          value: \"1\"/name: HOURS\n          value: \"${HOURS}\"/" \
      | kubectl_cmd apply -f -

    # PVC and pod for the storage class
    cat <<EOF | kubectl_cmd apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${sc}-pvc
  namespace: ${NS}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: ${sc}
EOF

    kubectl_cmd wait --for=condition=complete job/fio-runner --timeout=24h || true
  else
    # Per-node: one Job per labeled node, each with its own PVC, pinned via nodeName
    local nodes
    nodes=$(kubectl get nodes -l px-bench=true -o jsonpath='{.items[*].metadata.name}')
    if [[ -z "$nodes" ]]; then
      echo "No nodes labeled px-bench=true. Label target nodes first." >&2
      exit 1
    fi
    for node in $nodes; do
      # sanitize suffix
      local suffix
      suffix=$(echo "$node" | tr -cd 'a-z0-9-' | cut -c1-20)
      local pvc_name="${sc}-pvc-${suffix}"
      local job_name="fio-runner-${suffix}"

      kubectl_cmd delete job "$job_name" --ignore-not-found

      # PVC per node
      cat <<EOF | kubectl_cmd apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: ${pvc_name}
  namespace: ${NS}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
  storageClassName: ${sc}
EOF

      # Job pinned to the node with its PVC
      cat manifests/fio-runner-job.yaml \
        | sed -e "s/name: fio-runner/name: ${job_name}/" \
        | sed -e "s/restartPolicy: Never/restartPolicy: Never\n      nodeName: ${node}/" \
        | sed -e "s/name: test-volume/name: test-volume\n        persistentVolumeClaim:\n          claimName: ${pvc_name}/" \
        | sed -e "s/value: \"single\"/value: \"${sc}\"/" \
        | sed -e "s/name: HOURS\n          value: \"1\"/name: HOURS\n          value: \"${HOURS}\"/" \
        | kubectl_cmd apply -f -

      kubectl_cmd wait --for=condition=complete job/${job_name} --timeout=24h || true
    done
  fi
}

apply_ns
apply_basics

for sc in ${SC_LIST}; do
  run_for_sc "$sc"
done

echo "All requested runs submitted."

