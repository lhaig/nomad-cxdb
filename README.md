# CXDB

An AI context store for agents and LLMs, providing branching conversations and content deduplication.

## Overview

This job deploys [CXDB](https://github.com/strongdm/cxdb) as a service job on Nomad. CXDB stores conversation histories and tool outputs with branch-from-any-turn support, BLAKE3 content deduplication, and fast append operations.

## Prerequisites

- [Nomad](https://developer.hashicorp.com/nomad/docs/install) installed and running.
- [Docker](https://docs.docker.com/get-docker/) installed (since the job uses the Docker driver).

## Host Setup

Create the data directory on each Nomad client that may run this job:

```bash
mkdir -p /opt/cxdb/data
```

## Usage

### 1. Validate the Job

Before running the job, you can validate the syntax of the job file:

```bash
nomad job validate cxdb.nomad.hcl
```

### 2. Plan the Job

Run a plan to see what changes Nomad will make:

```bash
nomad job plan cxdb.nomad.hcl
```

### 3. Run the Job

Submit the job to your Nomad cluster:

```bash
nomad job run cxdb.nomad.hcl
```

### 4. Check Job Status

Verify the status of the job:

```bash
nomad job status cxdb
```

To see the logs of the allocations:

```bash
nomad alloc logs <alloc-id>
```

(Replace `<alloc-id>` with the actual allocation ID from the status command).

### 5. Stop the Job

To stop and purge the job:

```bash
nomad job stop -purge cxdb
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `datacenters` | `["dc1"]` | List of datacenters to deploy to |
| `cxdb_version` | `latest` | CXDB Docker image tag |
| `host_data_path` | `/opt/cxdb/data` | Host path for Docker bind mount (used when `volume_source` is empty) |
| `volume_source` | `""` | Nomad host volume name (empty to use Docker bind mount via `host_data_path`) |
| `log_level` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |
| `enable_metrics` | `false` | Enable Prometheus metrics endpoint |
| `cpu` | `500` | CPU allocation in MHz |
| `memory` | `512` | Memory allocation in MB |
| `service_provider` | `nomad` | Service discovery provider (`nomad` or `consul`) |
| `traefik_host` | `""` | Hostname for Traefik routing (empty to disable Traefik tags) |

### Examples

Minimal deployment:

```bash
nomad job run cxdb.nomad.hcl
```

With Traefik routing and debug logging:

```bash
nomad job run \
  -var='traefik_host=cxdb.example.com' \
  -var='log_level=debug' \
  cxdb.nomad.hcl
```

With more resources and metrics enabled:

```bash
nomad job run \
  -var='cpu=1000' \
  -var='memory=1024' \
  -var='enable_metrics=true' \
  cxdb.nomad.hcl
```

## Connecting

From another Nomad job using Nomad service discovery templates:

```hcl
template {
  data = <<EOF
{{- range nomadService "cxdb" }}
CXDB_HTTP_ADDR=http://{{ .Address }}:{{ .Port }}
{{- end }}
EOF
  destination = "local/env"
  env         = true
}
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| `9009` | Binary | High-throughput client writes (Go SDK) |
| `9010` | HTTP | JSON API, UI, and health checks |

## Persistence

CXDB stores turns, blobs, and registry data on the filesystem at `/data` inside the container. The job supports two storage modes:

### Docker bind mount (default)

Uses `host_data_path` to mount a host directory directly. No Nomad client config needed — just create the directory:

```bash
mkdir -p /opt/cxdb/data
nomad job run cxdb.nomad.hcl
```

### Nomad host volume

Uses a Nomad-managed host volume for better visibility and scheduling constraints. Register the volume in your Nomad client config:

```hcl
client {
  host_volume "cxdb-data" {
    path      = "/opt/cxdb/data"
    read_only = false
  }
}
```

Then deploy with:

```bash
nomad job run -var='volume_source=cxdb-data' cxdb.nomad.hcl
```

In both modes data survives container restarts but not node failures unless you use a shared filesystem or replicated storage backend.

## License

Apache 2.0
