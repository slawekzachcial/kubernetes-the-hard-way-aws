variable "controller_ips" {
  type = "list"

  default = [
    "10.240.0.10",
    "10.240.0.11",
    "10.240.0.12",
  ]
}

variable "worker_ips" {
  type = "list"

  default = [
    "10.240.0.20",
    "10.240.0.21",
    "10.240.0.22",
  ]
}

variable "worker_pod_cidrs" {
  type = "list"

  default = [
    "10.200.0.0/24",
    "10.200.1.0/24",
    "10.200.2.0/24",
  ]
}
