# Kubernetes The Hard Way - AWS

This page is based on [Kubernetes The Hard
Way](https://github.com/kelseyhightower/kubernetes-the-hard-way/) guide. It
compiles AWS CLI commands, mainly from revision
[8185017](https://github.com/kelseyhightower/kubernetes-the-hard-way/tree/818501707e418fc4d6e6aedef8395ca368e3097e)
of the guide (right before AWS support has been removed), with small
adjustments. Best is to follow the original guide side-by-side with this page as
the former providers background and context and this page contains only the
commands.

The intent of this page is similar to the original guide. My motivation to
compile it has been to learn more about AWS and Kubernetes.

## Labs

* [Prerequisites](docs/01-prerequisites.md)
* [Installing the Client Tools](docs/02-client-tools.md)
* [Provisioning Compute Resources](docs/03-compute-resources.md)
* [Provisioning a CA and Generating TLS Certificates](docs/04-certificate-authority.md)
* [Generating Kubernetes Authentication Files for Authentication](docs/05-kubernetes-configuration-files.md)
* [Generating the Data Encryption Config and Key](docs/06-data-encryption-keys.md)
* [Bootstrapping the etcd Cluster](docs/07-bootstrapping-etcd.md)
* [Bootstrapping the Kubernetes Control Plane](docs/08-bootstrapping-kubernetes-controllers.md)
* [Bootstrapping the Kubernetes Worker Nodes](docs/09-bootstrapping-kubernetes-workers.md)
* [Configuring kubectl for Remote Access](docs/10-configuring-kubectl.md)
* [Provisioning Pod Network Routes](docs/11-pod-network-routes.md)
* [Deploying the DNS Cluster Add-on](docs/12-dns-addon.md)
* [Smoke Test](docs/13-smoke-test.md)
* [Cleaning Up](docs/14-cleanup.md)

