# The "cxdb" job runs CXDB, an AI context store for agents and LLMs.
# It provides branching conversations, content deduplication, and fast
# append operations for conversation histories and tool outputs.
#
# For more information on CXDB, refer to:
#
#     https://github.com/strongdm/cxdb

variable "datacenters" {
  description = "List of datacenters to deploy to"
  type        = list(string)
  default     = ["dc1"]
}

variable "cxdb_version" {
  description = "CXDB Docker image tag"
  type        = string
  default     = "latest"
}

variable "host_data_path" {
  description = "Host path for persistent CXDB data when not using host volumes"
  type        = string
  default     = "/opt/cxdb/data"
}

variable "volume_source" {
  description = "Nomad host volume name (empty to use Docker bind mount via host_data_path)"
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Log verbosity: debug, info, warn, error"
  type        = string
  default     = "info"
}

variable "enable_metrics" {
  description = "Enable Prometheus metrics endpoint"
  type        = bool
  default     = false
}

variable "cpu" {
  description = "CPU allocation in MHz"
  type        = number
  default     = 500
}

variable "memory" {
  description = "Memory allocation in MB"
  type        = number
  default     = 512
}

variable "service_provider" {
  description = "Service discovery provider (nomad or consul)"
  type        = string
  default     = "nomad"
}

variable "traefik_host" {
  description = "Hostname for Traefik routing (empty to disable Traefik tags)"
  type        = string
  default     = ""
}

job "cxdb" {
  datacenters = var.datacenters
  type        = "service"

  # The "update" block specifies the update strategy of task groups. The update
  # strategy is used to control things like rolling upgrades, canaries, and
  # blue/green deployments.
  #
  # For more information and examples on the "update" block, refer to:
  #
  #     https://developer.hashicorp.com/nomad/docs/job-specification/update
  #
  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    progress_deadline = "10m"
    auto_revert      = true
    canary           = 0
  }

  # The migrate block specifies the group's strategy for migrating off of
  # draining nodes.
  #
  # For more information on the "migrate" block, refer to:
  #
  #     https://developer.hashicorp.com/nomad/docs/job-specification/migrate
  #
  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  ui {
    description = "CXDB - AI Context Store"
    link {
      label = "CXDB on GitHub"
      url   = "https://github.com/strongdm/cxdb"
    }
  }

  group "cxdb" {
    count = 1

    network {
      port "binary" {
        to = 9009
      }

      port "http" {
        to = 9010
      }
    }

    # The "service" block instructs Nomad to register this task as a service
    # in the service discovery engine, which is currently Nomad or Consul.
    #
    # For more information and examples on the "service" block, refer to:
    #
    #     https://developer.hashicorp.com/nomad/docs/job-specification/service
    #
    service {
      name     = "cxdb"
      port     = "http"
      provider = var.service_provider

      tags = flatten([
        ["cxdb", "ai", "context-store"],
        var.traefik_host != "" ? [
          "traefik.enable=true",
          "traefik.http.routers.cxdb.rule=Host(`${var.traefik_host}`)",
          "traefik.http.routers.cxdb.entrypoints=https",
          "traefik.http.routers.cxdb.tls=true",
        ] : [],
      ])

      check {
        name     = "alive"
        type     = "http"
        path     = "/v1/contexts"
        interval = "15s"
        timeout  = "3s"
      }
    }

    # The "restart" block configures a group's behavior on task failure.
    #
    # For more information and examples on the "restart" block, refer to:
    #
    #     https://developer.hashicorp.com/nomad/docs/job-specification/restart
    #
    restart {
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    # When volume_source is set, use a Nomad-managed host volume for data.
    # Otherwise the task falls back to a Docker bind mount via host_data_path.
    dynamic "volume" {
      for_each = var.volume_source != "" ? { "cxdb-data" = var.volume_source } : {}
      labels   = [volume.key]
      content {
        type      = "host"
        source    = volume.value
        read_only = false
      }
    }

    # CXDB stores turns, blobs, and registry data on disk, so pin the
    # allocation to the same node on updates to preserve data.
    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 500
    }

    task "cxdb" {
      driver = "docker"

      config {
        image          = "cxdb/cxdb:${var.cxdb_version}"
        ports          = ["binary", "http"]
        auth_soft_fail = true

        # Docker bind mount fallback when not using host volumes.
        volumes = var.volume_source == "" ? ["${var.host_data_path}:/data"] : []
      }

      # Nomad host volume mount when volume_source is set.
      dynamic "volume_mount" {
        for_each = var.volume_source != "" ? [1] : []
        content {
          volume      = "cxdb-data"
          destination = "/data"
          read_only   = false
        }
      }

      env {
        CXDB_DATA_DIR       = "/data"
        CXDB_BIND           = "0.0.0.0:9009"
        CXDB_HTTP_BIND      = "0.0.0.0:9010"
        CXDB_LOG_LEVEL      = var.log_level
        CXDB_ENABLE_METRICS = var.enable_metrics
      }

      identity {
        env  = true
        file = true
      }

      resources {
        cpu    = var.cpu
        memory = var.memory
      }
    }
  }
}
