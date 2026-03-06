#!/bin/bash
set -euo pipefail

# setting default values
KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
KAFKA_CONFIG_FILE=${KAFKA_CONFIG_FILE:-${KAFKA_HOME}/config/server.properties}
KAFKA_LOG_DIRS=${KAFKA_LOG_DIRS:-/var/kafka-logs}
DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-local}
KAFKA_NODE_ID=${KAFKA_NODE_ID:-1}
KAFKA_CLUSTER_ID=${KAFKA_CLUSTER_ID:-kafka-local-testing-2rrfjldjkr}

is_kubernetes(){
    [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]] || [[ -n "$HOSTNAME" && "$HOSTNAME" =~ -[0-9]+$ ]]
}

# get_pod_ordinal(){
#     if [[ "$HOSTNAME" =~ -([0-9]+)$ ]]; then ## Capturing the ordinal part
#         echo ${BASH_REMATCH[1]}
#     else
#         echo 0
#     fi
# }

# if is_kubernetes(); then
#     echo "Running in kubernetes"
#     POD_ORDINAL=$(get_pod_ordinal)
#     KAFKA_NODE_ID=$((POD_ORDINAL+1))
#     echo "Pod Ordinal: $POD_ORDINAL"
#     echo "Kafka Node ID: $KAFKA_NODE_ID"
# else
#     echo "running locally"
#     KAFKA_NODE_ID=1
# fi

generate_base_config(){
    local config_file=$1

    cat > $config_file << EOF
process.roles=broker,controller
node.id=${KAFKA_NODE_ID}
cluster.id=${KAFKA_CLUSTER_ID}

listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
controller.listener.names=CONTROLLER

log.dirs=${KAFKA_LOG_DIRS}

message.max.bytes=5000000
replica.fetch.max.bytes=50000100
replica.fetch.response.max.bytes=50000100
unclean.leader.election.enable=false
auto.create.topics.enable=false

transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1

EOF
}

add_local_config(){
    local config_file=$1
    cat >> $config_file << EOF
controller.quorum.voters=1@localhost:9093
advertised.listeners=PLAINTEXT://localhost:9092
offsets.topic.replication.factor=1
EOF
}

add_cluster_config(){
    local config_file=$1

    cat >> $config_file << EOF
controller.quorum.voters=${QUORUM_VOTERS}
advertised.listeners=${ADVERTISED_LISTENERS}
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
EOF
}

format_storage_if_needed(){
    echo "Checking if Kafka storage needs formatting"

    if [[ ! -f "${KAFKA_LOG_DIRS}/meta.properties" ]]; then
        echo "Storage not formatted. Formatting with cluster ID: ${KAFKA_CLUSTER_ID}"

        kafka-storage.sh format -t ${KAFKA_CLUSTER_ID} -c ${KAFKA_CONFIG_FILE}

        if [[ $? -eq 0  ]]; then
            echo "Storage formatted successfully"
        else
            echo "ERROR: Failed to format storage"
            exit 1
        fi
    else
        echo "Storage already formatted, skipping storage format"
    fi
}

build_quorum_voters(){
    local replicas=${KAFKA_REPLICAS:-3}
    local service_name=${KAFKA_SERVICE_NAME:-kafka}
    local namespace=${KAFKA_NAMESPACE:-default}
    local voters=""

    for i in $(seq 1 $replicas); do
        if [[ -n "$voters" ]]; then
            voters="${voters},"
        fi
        voters="${voters}${i}@${service_name}-$((i-1)).${service_name}-headless.${namespace}.svc.cluster.local:9093"
    done

    QUORUM_VOTERS=$voters
    echo "Built quorum voters: $QUORUM_VOTERS"
    
}

setup_advertised_listeners(){
    local service_name=${KAFKA_SERVICE_NAME:-kafka}
    local namespace=${KAFKA_NAMESPACE:-default}

    ADVERTISED_LISTENERS="PLAINTEXT://${HOSTNAME}.${service_name}-headless.${namespace}.svc.cluster.local:9092"
    echo "Set advertised listeners: $ADVERTISED_LISTENERS"
}

setup_cluster_mode(){
    echo "Setting up cluster mode configuration"
    if [[ -n "$HOSTNAME" ]] && [[ "$HOSTNAME" =~ -([0-9]+)$ ]]; then
        POD_ORDINAL=${BASH_REMATCH[1]}
        KAFKA_NODE_ID=$((POD_ORDINAL+1))
        echo "Pod Ordinal: $POD_ORDINAL, Node ID: $KAFKA_NODE_ID"
    fi

    build_quorum_voters

    setup_advertised_listeners
}


main(){
    echo "KAFKA_HOME: ${KAFKA_HOME}"
    echo "DEPLOYMENT_MODE: ${DEPLOYMENT_MODE}"
    echo "NODE_ID: ${KAFKA_NODE_ID}"

    mkdir -p $(dirname ${KAFKA_CONFIG_FILE})
    mkdir -p ${KAFKA_LOG_DIRS}

    generate_base_config ${KAFKA_CONFIG_FILE}

    if [[ "$DEPLOYMENT_MODE" == "cluster" ]] || is_kubernetes; then
        echo "Configuring for cluster mode"
        setup_cluster_mode
        add_cluster_config ${KAFKA_CONFIG_FILE}
    else
        add_local_config ${KAFKA_CONFIG_FILE}
    fi

    format_storage_if_needed

    echo "Starting Kafka with: $@"
    exec "$@"
}

main "$@"