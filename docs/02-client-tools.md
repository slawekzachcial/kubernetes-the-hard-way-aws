# Installing the Client Tools

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/03-compute-resources.md)

## Install CFSSL

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-client-tools.md).

Since we install binaries into the local `bin` folder, instead of running
`sudo mv cfssl cfssljson /usr/local/bin/`, run:

```sh
mkdir -p bin

mv cfssl cfssljson bin
```

> Note:
> If you are on MacOS and you installed cfssl using Homebrew, `cfssl`
> and `cfssljson` have been copied into `/usr/local/bin` rather than into the
> local `bin` folder. Therefore when using them later in this guide, instead of
> `bin/cfssl` and `bin/cfssljson`, simply run `cfssl` and `cfssljson`.

### Verification

```sh
bin/cfssl version
```

```sh
bin/cfssljson --version
```

## Install kubectl

Follow the [guide
instructions](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/02-client-tools.md#install-kubectl).

Since we install binaries into the local `bin` folder, instead of running
`sudo mv kubectl /usr/local/bin`, run:

```sh
mkdir -p bin

mv kubectl bin
```

### Verification

```sh
bin/kubectl version --client
```

Next [Provisioning Compute Resources](03-compute-resources.md)
