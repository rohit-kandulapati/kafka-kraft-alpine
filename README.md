# kafka-kraft-alpine


```Bash
podman network create kafka

podman volume create kafka_kraft

podman run -d -p 9092:9092 -e KAFKA_NODE_ID=1 -e KAFKA_PROCESS_ROLES=broker,controller -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 -e KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093 -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://localhost:9092 -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 -e KAFKA_LOG_DIRS=/var/lib/kafka/data -e CLUSTER_ID=rohit-kalyan2o3u-wrlka -v kafka_kraft:/var/lib/kafka/data --network=kafka --name=kafka docker.io/confluentinc/cp-kafka:7.8.6
```

## KAFKA CLI
```Bash
## to list the topics
kafka-topics.sh --create --topic test-topic --bootstrap-server localhost:9092 --partitions 3

## list topics
kafka-topics.sh --list --bootstrap-server localhost:9092

## describe topic
kafka-topics.sh --describe --topic test-topic --bootstrap-server localhost:9092

## start a producer
kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092

## Start a consumer
kafka-console-consumer.sh --topic test-topic --bootstrap-server localhost:9092 --from-beginning
```

## Kafka Configuration
```Bash
process.roles=broker,controller
## defines what role does this node plays
## broker --> handles requests, stores data
## controller --> manages cluster metadata (This is the difference from ZooKeeper, KRAFT will take care of it)

node.id=1
# unique identifier for this node (must be unique across cluster)
# In Statefulset we can use ordinal indexes

## Controller Quorum Voters
## List of nodes that participate in controller elections
## format: node.id@hostname:port,node.id@hostname@port
## These are the nodes that vote to elect the controller leader
## must include all the controller nodes in the cluster
controller.quorum.voters=1@localhost:9092

## Listeners - what ports that kafka binds to
## Format: listner_name://host:port,listener_name://host:port
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093

## Advertised Listeners - What addresses that clients should use to connect
## This is published to clients - they use addresses to connect
# must be reacable from outside the container
advertised.listeners=PLAINTEXT://localhost:9092

## Listener Security Protocol Map - Maps listener names to security protocols
# CONTROLLER:PLAINTEXT - Controller communication uses plain text
# PLAINTEXT:PLAINTEXT - Client communication uses plain text
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT

## Inter Broker Listener Name - Which listener brokers use to talk to each other
## Brokers will use the PLAINTEXT listener for raft
inter.broker.listener.name=PLAINTEXT

## Controller Listener Names - which listener controllers use for communication 
## Controllers will use the controller listener for raft
controller.listener.names=CONTROLLER

## Cluster Identifiction
## Cluster ID  - unique id for this kafka cluster
# generate with kafka-storage.sh random-uuid
# This replcaes the cluster identification that zookeeper used to provide
cluster.id=rohit-181-4jlfljsfoa-kafka

## log directories - where kafka stores partition data, metadata
log.dirs=/var/kafka-logs

## Log Segment Bytes  - maximum size of a single lo segment file
## when a segment reaches this size, a new segment is created
## 107374184 = 1GB - larger segments = fewer files but slower startup
log.segment.bytes=107374184

## log rotation hours - how long to keep the log segments
## 168 hours means 7 days
# -1 means forever
log.retention.hours=168

## log retention check interval - how often to check for old segments to delete 
## 300000ms = 5 minutes - kafka checks this often for cleanup
log.retention.check.interval.ms=300000

## log cleanup policy - how to clean up old log data
## delete - delete old segments based on time/size retention
## compact - keep only the latest value for each key
log.cleanup.policy=delete

## topic defaults
## num of partitions - default partitions for new topics 
num.partitions=3

## default replication factor - how many copies of data to keep
## should be number of brokers in the cluster
## provices good fault tolerance
default.replication.factor=3

## minimun insync replicas
min.insync.replicas=2
```