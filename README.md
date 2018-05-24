# CI Stack

Deploying the CI stack consisting of Concourse CI with Vault (backed by Consul) for secret store.

<!-- TOC -->

- [Manually deploying the CI Stack](#manually-deploying-the-ci-stack)
    - [Pre-requisites](#pre-requisites)
    - [Connect to one of the Swarm managers](#connect-to-one-of-the-swarm-managers)
    - [Deploy Docker network](#deploy-docker-network)
    - [Deploy Hashicorp Vault and Consul](#deploy-hashicorp-vault-and-consul)
    - [Intialize Vault](#intialize-vault)
    - [Login to Vault](#login-to-vault)
    - [Prepare Vault for Consul](#prepare-vault-for-consul)
    - [Create a GitHub OAuth Application (Optional)](#create-a-github-oauth-application-optional)
    - [Deploy Concourse](#deploy-concourse)
    - [Deploy Concourse Worker](#deploy-concourse-worker)
- [Deploying using Ansible](#deploying-using-ansible)
    - [Pre-Requisites](#pre-requisites)
- [Limitations](#limitations)

<!-- /TOC -->

## Manually deploying the CI Stack

### Pre-requisites

1. A Docker swarm cluster has already been deployed and available.
2. Bash is available for running shell scripts.
3. SSH access to at least one of the Swarm managers is available.
4. Vault binary is available and in $PATH environment variable. Download from [here](https://www.vaultproject.io/downloads.html)

### Connect to one of the Swarm managers

To manually deploy the CI stack, first SSH to one of the Swarm managers.

### Deploy Docker network

Deploy a network named `ci` that will act as the network for all the components of the CI stack.

```sh
docker network create --driver overlay ci --attachable --internal
```

### Deploy Hashicorp Vault and Consul

The Docker stack definition and other helper files for deploying Hashicorp Vault and Consul are available in `vault-consul` directory.

Run below script to deploy an instance of Hashicorp Vault with Consul as storage backend:

```sh
docker stack deploy vault -c ./vault-consul/stack.yml
```

### Intialize Vault

By default, when Vault is deployed, it needs to be [initalized](https://www.vaultproject.io/intro/getting-started/deploy.html#initializing-the-vault) and [unsealed](https://www.vaultproject.io/intro/getting-started/deploy.html#seal-unseal). Read the links ealier to understand what initalization and unseal of Vault means.

Run below set of commands to initalize and unseal the vault instance deployed:

```sh
# All outputs from vault CLI will be in JSON, for easy parsing
export VAULT_FORMAT="json"

# Initalize vault and store the output
init=$(vault operator init)

# Unseal vault using 3 unseal keys
vault unseal $(jq -re '.unseal_keys_b64[0]' <<< "$init")
vault unseal $(jq -re '.unseal_keys_b64[1]' <<< "$init")
vault unseal $(jq -re '.unseal_keys_b64[2]' <<< "$init")
```

**IMPORTANT NOTE:** It's a good idea to keep the contents of `init` variable safe because that would be required for unsealing Vault again, in case Vault process needs to be restarted (for any reason).

### Login to Vault

The init step also produces a `root token` which can be used to authenticate against vault. Run below commands to authenticate using vault:

```sh
# Find the IP of Swarm cluster and replace below
export SWARM_IP=[fill-your-swarm-ip-here]
export VAULT_ADDR=http://${SWARM_IP}:8200

# using $init from previous step
vault login $(jq -re '.root_token' <<< "$init")
```

### Prepare Vault for Consul

For Concourse to talk to Vault following steps must be done:

1. Create a secret backend `/concourse`.
2. A token that the Concourse will use to communicate with Vault.
3. A Vault policy which will allow the above token read and list secrets in the `concourse` secret backend. The policy is available in `./concourse/policy/concourse.hcl`
4. Binding the vault policy and token.

```sh
# Create a new secret backend for Vault
vault secrets enable kv -path=concourse -description="Secret store for Concourse pipelines"

# Create a policy that can read and list from /concourse secret backend
vault policy write concourse-token ./concourse/policy/concourse.hcl

# Create a token to be used in concourse stack
concourse_token=$(vault token create -ttl="60h" -policy=concourse-token -format=json)
```

### Create a GitHub OAuth Application (Optional)

*NOTE:* Skip this step if client ID and secret of OAuth application are already known.

GitHub will be used as the authentication to Concourse CI. To allow this create a GitHub OAuth application under the GitHub organisation by following [these steps](https://developer.github.com/apps/building-oauth-apps/creating-an-oauth-app/).

### Deploy Concourse

The Docker stack definition and other helper files for deploying Concourse CI are available in `concourse` directory.

Before deploying Concourse, replace `<fill-before-deploy>` test in `./concourse/stack.yml`:

1. Value of `CONCOURSE_VAULT_CLIENT_TOKEN` with the concourse token created in last step.
2. Value of `CONCOURSE_GITHUB_AUTH_CLIENT_ID` with the client ID of GitHub OAuth application created in last step.
3. Value of `CONCOURSE_GITHUB_AUTH_CLIENT_SECRET` with the client secret of GitHub OAuth application in last step.
4. Value of `CONCOURSE_GITHUB_AUTH_ORGANIZATION` with the GitHub organisation name for authentication to Concourse. Any member of this organisation will be able to access the deployed Concourse instance.

Afterwards, run command to deploy the Concourse CI:

```sh
# Generate key-pairs to be used by Concourse Web and Worker instances.
cd concourse
./generate-keys.sh

# Deploy Postgres and Concourse Web
docker stack deploy ci -c stack.yml
```

### Deploy Concourse Worker

Concourse worker container utilizes the docker instance on the host to spin up temporary containers as defined in the pipelines. To communicate with Docker daemon on host, the worker container needs to be run in `privileged` mode.

At the time of writing, Docker Swarm doesn't support `privileged` containers, so Concourse worker needs to be deployed as a stand-alone container and connect to the CI stack.

```sh
cd concourse
# Run worker as a privileged container
docker run --rm --privileged=true -e CONCOURSE_TSA_HOST=concourse-web:2222 -e CONCOURSE_GARDEN_NETWORK -e CONCOURSE_BAGGAECLAIM_DRIVER=detect --volume=$(pwd)/concourse/keys/worker/:/concourse-keys/ -ti --name concourse_worker --hostname concourse-worker -d concourse/concourse worker

# Connect the worker container to CI network so that it's available to Concourse web
docker network connect --alias=concourse-worker ci concourse_worker
```

## Deploying using Ansible

WIP

### Pre-Requisites

1. Ansible
2. WIP

## Limitations

WIP