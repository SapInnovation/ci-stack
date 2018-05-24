#!/usr/bin/env bash

export VAULT_FORMAT="json"
export VAULT_ADDR='http://127.0.0.1:8200'

main(){
    deploy_ci_network
    deploy_vault
    vault_init_unseal
    vault_login_with_root
    deploy_concourse
    prepare_vault_for_concourse
    run_concourse_worker
}

deploy_ci_network(){
    # Create a network to have the whole CI stack in
    docker network create --driver overlay ci --attachable --internal
}

deploy_vault(){
    # Deploy vault and consul
    docker stack deploy vault -c ./vault-consul/stack.yml
    sleep 10
}

# Init and unseal vault
vault_init_unseal(){
    # See below link to see why we need to unseal vault
    # https://www.vaultproject.io/docs/concepts/seal.html
    init=$(vault operator init)
    vault unseal $(jq -re '.unseal_keys_b64[0]' <<< "$init")
    vault unseal $(jq -re '.unseal_keys_b64[1]' <<< "$init")
    vault unseal $(jq -re '.unseal_keys_b64[2]' <<< "$init")
}

vault_login_with_root(){
    # Login so that we can communcate to vault
    vault login $(jq -re '.root_token' <<< "$init")
}

prepare_vault_for_concourse(){
    # Enable /concourse secret backend for concourse
    vault secrets enable kv -path=concourse -description="Secret store for Concourse pipelines"
    # Create a policy that can read and list from /concourse secret backend
    vault policy write concourse-token ./concourse/policy/concourse.hcl
    # Create a token to be used in concourse stack
    concourse_token=$(vault token create -ttl="60h" -policy=concourse-token -format=json)
}

deploy_concourse(){
    # Use token got above and replace it in stack.yml for concourse
    replace_concourse_token_from_above_in_stack_yml
    docker stack deploy ci -c stack.yml
}

run_concourse_worker(){
    # Deploy a separate container of concourse worker
    docker run --rm --privileged=true -e CONCOURSE_TSA_HOST=concourse-web:2222 -e CONCOURSE_GARDEN_NETWORK -e CONCOURSE_BAGGAECLAIM_DRIVER=detect --volume=$(pwd)/concourse/keys/worker/:/concourse-keys/ -ti --name concourse_worker --hostname concourse-worker -d concourse/concourse worker
    # Attach the concourse worker to `ci` network
    docker network connect --alias=concourse-worker ci concourse_worker
}