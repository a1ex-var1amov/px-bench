## px-bench run examples

The commands below assume you are using the Deployment `fio-runner-ephemeral` in namespace `px-bench` and want to run per-section jobs from `fiocfg/fiojobs.fio`.

Notes:
- JOB_MODE=per_section makes the runner iterate sections one-by-one in separate fio invocations.
- Use JOB_FILTER (regex) to include sections; use JOB_EXCLUDE (regex) to exclude.
- RUNTIME_PRE_JOB sets per-section duration (seconds). HOURS sets how long the runner keeps iterating.
- After changing env vars, restart the Deployment to pick up changes.

Base env you can reuse (optional):
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  MODE=per-node JOB_MODE=per_section \
  RUNTIME_PRE_JOB=60 HOURS=1 RANDREPEAT=true ITERATION_SLEEP_SECS=0
```

Restart after changes:
```bash
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

### Only reads
Include read-only sections (sequential and random), exclude mixed randrw sections.
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_FILTER='read$' JOB_EXCLUDE='(randrw|mix)'
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

### Only writes
Include write-only sections (sequential), exclude random and mixed.
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_FILTER='write$' JOB_EXCLUDE='rand|mix'
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

If you want all write flavors (sequential and random writes) but not mixed:
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_FILTER='(write$|rand-write$)' JOB_EXCLUDE='mix'
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

### Only random (no sequential)
Include random read/write sections, exclude sequential and mixed (adjust to include mix if desired).
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_FILTER='rand-(read|write)$' JOB_EXCLUDE='mix'
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

To include mixed random (randrw) as well:
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_FILTER='rand' JOB_EXCLUDE=''
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

### Only sequential
Include sequential read/write sections; exclude any section containing "rand" or "mix".
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_FILTER='(read|write)$' JOB_EXCLUDE='rand|mix'
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

### Bonus: all tests in one run
Run the full `fiojobs.fio` in a single fio invocation per iteration.
```bash
oc -n px-bench set env deploy/fio-runner-ephemeral \
  JOB_MODE=all_in_one JOBS- JOB_FILTER- JOB_EXCLUDE- RUNTIME_PRE_JOB-
oc -n px-bench rollout restart deploy/fio-runner-ephemeral
```

Tip: The provided fio config uses `[global]` stonewall, so sections execute sequentially within a single run. To execute sections truly concurrently, you would need a different fio config (e.g., remove stonewall, set `group_reporting`, and/or use `numjobs`).

### DaemonSet variant (if you use the DaemonSet instead of Deployment)
Replace `deploy/fio-runner-ephemeral` with `ds/fio-runner-ephemeral` in the commands above.


