# kafka-kraft-alpine

A minimal, production-aware Apache Kafka Docker image built from scratch on **Alpine Linux**, running in **KRaft mode** (ZooKeeper-free). This project eliminates the ZooKeeper dependency by leveraging Kafka's built-in Raft consensus protocol for cluster metadata management.

---

## Table of Contents

- [What is KRaft?](#what-is-kraft)
- [Architecture](#architecture)
- [Kafka Configuration Reference](#kafka-configuration-reference)
- [Getting Started – Local (Docker / Podman)](#getting-started--local-docker--podman)
- [Kafka CLI Usage](#kafka-cli-usage)
- [Testing with Python Clients](#testing-with-python-clients)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Environment Variables](#environment-variables)

---

## What is KRaft?

KRaft (**K**afka **R**aft) is Kafka's native consensus protocol that replaces ZooKeeper for cluster metadata management. Before KRaft, every Kafka deployment required a separate ZooKeeper to manage:

- Broker registration and leader election
- Topic and partition metadata
- Controller election

With KRaft, Kafka nodes take on the `controller` role directly, handling all of this internally using the Raft algorithm. This simplifies deployment significantly — no separate ZooKeeper service, no extra infrastructure.

> KRaft became production-ready in **Kafka 3.3** and ZooKeeper support was fully removed in **Kafka 4.0**.

---

<!-- ## Architecture

This image runs Kafka in **combined mode**, meaning a single node acts as both `broker` and `controller`. This is ideal for local development and single-node setups.

```
┌─────────────────────────────────────┐
│         Kafka Node (Alpine)         │
│                                     │
│  ┌─────────────┐  ┌──────────────┐  │
│  │   Broker    │  │  Controller  │  │
│  │  :9092      │  │  :9093       │  │
│  └─────────────┘  └──────────────┘  │
│                                     │
│  process.roles = broker,controller  │
└─────────────────────────────────────┘
        │
        │  PLAINTEXT
        ▼
   Clients / Consumers / Producers
```

For a **multi-node cluster** (e.g., in Kubernetes), nodes are split into dedicated `broker` or `controller` roles, and the `controller.quorum.voters` list is updated to include all controller nodes.

--- -->

## Kafka Configuration Reference

Below is a breakdown of every key configuration parameter and what it does:

### Node Identity

```properties
# Defines what role this node plays in the cluster.
# broker     → handles client requests and stores data
# controller → manages cluster metadata via Raft (replaces ZooKeeper)
# Combined mode: broker,controller
process.roles=broker,controller

# Unique numeric identifier for this node.
# Must be unique across the entire cluster.
# In a Kubernetes StatefulSet, use the pod ordinal index (e.g., 0, 1, 2).
node.id=1
```

### Controller Quorum

```properties
# List of all nodes that participate in controller leader elections.
# Format: node.id@hostname:port,node.id@hostname:port
# Must include ALL controller nodes in the cluster.
# A majority (quorum) must be available for the cluster to function.
controller.quorum.voters=1@localhost:9093
```

### Listeners

```properties
# Ports that Kafka binds to on the container.
# Format: LISTENER_NAME://host:port
# 0.0.0.0 means bind to all interfaces inside the container.
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093

# Addresses published to clients so they know how to connect.
# Must be reachable from outside the container (use the host IP or service name).
advertised.listeners=PLAINTEXT://localhost:9092

# Maps listener names to security protocols.
# PLAINTEXT:PLAINTEXT   → unencrypted client traffic
# CONTROLLER:PLAINTEXT  → unencrypted controller-to-controller Raft traffic
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT

# Which listener brokers use to communicate with each other (inter-broker replication).
inter.broker.listener.name=PLAINTEXT

# Which listener controllers use for Raft coordination.
controller.listener.names=CONTROLLER
```

### Cluster Identity

```properties
# A unique ID for this Kafka cluster.
# Generated once with: kafka-storage.sh random-uuid
# This replaces the cluster identification that ZooKeeper used to provide.
# All nodes in the same cluster must share the same cluster.id.
cluster.id=<your-cluster-uuid>
```

### Log Storage

```properties
# Directory where Kafka stores partition data and metadata.
log.dirs=/var/kafka-logs

# Maximum size of a single log segment file before a new one is created.
# 1073741824 = 1 GB. Larger segments = fewer files but slower startup recovery.
log.segment.bytes=1073741824

# How long to retain log segments (in hours).
# 168 hours = 7 days. Set to -1 to retain forever.
log.retention.hours=168

# How often Kafka checks for old segments eligible for deletion.
# 300000 ms = 5 minutes.
log.retention.check.interval.ms=300000

# How old log data is cleaned up.
# delete  → remove old segments based on time/size retention policies
# compact → keep only the latest value per key (used for changelog topics)
log.cleanup.policy=delete
```

### Topic Defaults

```properties
# Default number of partitions for newly created topics.
# More partitions = more parallelism for consumers.
num.partitions=3

# Default number of replicas for each partition.
# Should equal the number of brokers in the cluster for fault tolerance.
default.replication.factor=3

# Minimum number of in-sync replicas required for a produce request to succeed.
# With 3 replicas, setting this to 2 ensures you can tolerate 1 broker failure.
min.insync.replicas=2
```

---

## Getting Started – Local (Docker / Podman)

### Single Node (Combined Mode)

```bash
# Create an isolated network
podman network create kafka

# Create a persistent volume for Kafka data
podman volume create kafka_kraft

# Run the Kafka broker
podman run -d \
  -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
  -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_LOG_DIRS=/var/lib/kafka/data \
  -e CLUSTER_ID=<your-cluster-uuid> \
  -v kafka_kraft:/var/lib/kafka/data \
  --network=kafka \
  --name=kafka \
  <your-image-name>
```

> Replace `<your-cluster-uuid>` with a UUID generated by running:
> ```bash
> kafka-storage.sh random-uuid
> ```

### Verify the Broker is Running

```bash
podman logs kafka
# Look for: "Kafka Server started"
```

---

## Kafka CLI Usage

Exec into the running container to use Kafka's built-in CLI tools:

```bash
podman exec -it kafka /bin/sh
```

```bash
# Create a topic with 3 partitions
kafka-topics.sh --create \
  --topic test-topic \
  --bootstrap-server localhost:9092 \
  --partitions 3

# List all topics
kafka-topics.sh --list --bootstrap-server localhost:9092

# Describe a topic (partitions, replicas, ISR)
kafka-topics.sh --describe \
  --topic test-topic \
  --bootstrap-server localhost:9092

# Start an interactive producer (type messages, press Enter to send)
kafka-console-producer.sh \
  --topic test-topic \
  --bootstrap-server localhost:9092

# Start a consumer (reads from the beginning)
kafka-console-consumer.sh \
  --topic test-topic \
  --bootstrap-server localhost:9092 \
  --from-beginning
```

---

## Testing with Python Clients

The repo includes a producer and consumer to validate end-to-end message flow.

### Install dependencies

```bash
pip install confluent-kafka
```

### Run the producer

```bash
python producer.py
```

### Run the consumer

```bash
python consumer.py
```

Both scripts connect to `localhost:9092` and use `test-topic` by default.

---

<!-- ## Kubernetes Deployment

### Single-Node (Combined Mode) — StatefulSet

For development or staging environments, deploy a single combined broker+controller node.

```yaml
# kafka-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  namespace: kafka
spec:
  serviceName: kafka-headless
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
        - name: kafka
          image: <your-image-name>
          ports:
            - containerPort: 9092
              name: plaintext
            - containerPort: 9093
              name: controller
          env:
            - name: KAFKA_NODE_ID
              value: "1"
            - name: KAFKA_PROCESS_ROLES
              value: "broker,controller"
            - name: KAFKA_CONTROLLER_QUORUM_VOTERS
              value: "1@kafka-0.kafka-headless.kafka.svc.cluster.local:9093"
            - name: KAFKA_LISTENERS
              value: "PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"
            - name: KAFKA_ADVERTISED_LISTENERS
              value: "PLAINTEXT://kafka-0.kafka-headless.kafka.svc.cluster.local:9092"
            - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
              value: "PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT"
            - name: KAFKA_CONTROLLER_LISTENER_NAMES
              value: "CONTROLLER"
            - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
              value: "1"
            - name: KAFKA_LOG_DIRS
              value: "/var/lib/kafka/data"
            - name: CLUSTER_ID
              value: "<your-cluster-uuid>"
          volumeMounts:
            - name: kafka-data
              mountPath: /var/lib/kafka/data
  volumeClaimTemplates:
    - metadata:
        name: kafka-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
---
# Headless service for stable DNS hostnames
# Resolves to: pod-name.kafka-headless.kafka.svc.cluster.local
apiVersion: v1
kind: Service
metadata:
  name: kafka-headless
  namespace: kafka
spec:
  clusterIP: None
  selector:
    app: kafka
  ports:
    - name: plaintext
      port: 9092
    - name: controller
      port: 9093
---
# ClusterIP service for internal client access
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: kafka
spec:
  selector:
    app: kafka
  ports:
    - name: plaintext
      port: 9092
      targetPort: 9092
``` -->

### Multi-Node Cluster — Isolated Mode (Production)

For production, split broker and controller roles across dedicated nodes. Each controller node gets its own `node.id` and all three are listed in `controller.quorum.voters`.

> **Tip:** Use the pod's ordinal index (injected via the Downward API or parsed from the hostname) as `KAFKA_NODE_ID` to guarantee uniqueness across replicas.

```bash
# Example: derive node ID from pod hostname in your entrypoint script
KAFKA_NODE_ID=$(hostname | awk -F'-' '{print $NF}')
```

In a 3-controller setup, the quorum voters value looks like:

```
1@kafka-0.kafka-headless.kafka.svc.cluster.local:9093,2@kafka-1.kafka-headless.kafka.svc.cluster.local:9093,3@kafka-2.kafka-headless.kafka.svc.cluster.local:9093
```

### Apply to Cluster

```bash
kubectl create namespace kafka
kubectl apply -f kafka-statefulset.yaml

# Verify pods are running
kubectl get pods -n kafka

# Check broker logs
kubectl logs kafka-0 -n kafka
```

### Connect from Inside the Cluster

Other pods can reach the broker using the ClusterIP service:

```
bootstrap-server: kafka.kafka.svc.cluster.local:9092
```

---

## Environment Variables

| Variable | Description | Example |
|---|---|---|
| `KAFKA_NODE_ID` | Unique node ID | `1` |
| `KAFKA_PROCESS_ROLES` | Node roles | `broker,controller` |
| `KAFKA_CONTROLLER_QUORUM_VOTERS` | Controller voter list | `1@localhost:9093` |
| `KAFKA_LISTENERS` | Bind addresses | `PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093` |
| `KAFKA_ADVERTISED_LISTENERS` | Client-facing addresses | `PLAINTEXT://localhost:9092` |
| `KAFKA_LISTENER_SECURITY_PROTOCOL_MAP` | Listener → protocol map | `PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT` |
| `KAFKA_CONTROLLER_LISTENER_NAMES` | Controller listener name | `CONTROLLER` |
| `KAFKA_LOG_DIRS` | Data directory | `/var/lib/kafka/data` |
| `CLUSTER_ID` | Unique cluster UUID | `rohit-kalyan2o3u-wrlka` |
| `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR` | Replication for `__consumer_offsets` | `1` (single node), `3` (cluster) |
| `KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR` | Replication for transaction log | `1` (single node), `3` (cluster) |