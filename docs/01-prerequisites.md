# Prerequisites

## Amazon Web Services

The commands below deploy Kubernetes cluster into [Amazon Web
Services](https://aws.amazon.com). I was able to run them using [AWS Free
Tier](https://aws.amazon.com/free/), at no cost.

## Amazon Web Services CLI

Install AWS CLI following instructions at https://aws.amazon.com/cli/.

Details how to configure AWS CLI are available
[here](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).

While any supported method would work, for the purpose of this guide we will
assume that you configured AWS CLI using environment variables.

To do that, in **every terminal** that you open to run commands from
this guide, first execute the these commands:

```sh
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=us-east-2
```

This guide will provision AWS resources in `us-east-2` region. If you decide
to use a different AWS region change the value of the environment variable above.

Note that if you decide to use `us-east-1` make sure to update domain name from
`${AWS_DEFAULT_REGION}.compute.internal` to `${AWS_DEFAULT_REGION}.ec2.internal`
when [setting VPC DHCP options](03-compute-resources.md#dhcp-option-sets).

## Running Commands in Parallel with tmux

To save some typing you may want to check [this hint](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/01-prerequisites.md#running-commands-in-parallel-with-tmux)
in the original guide.

Next: [Installing the Client Tools](02-client-tools.md)
