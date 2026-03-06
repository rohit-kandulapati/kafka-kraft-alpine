from confluent_kafka import Consumer
import json

consumer_config = {
    'bootstrap.servers': '127.0.0.1:9092',
    # provides the initial hosts that act as the starting point for a kafka client to discover the full set of alive servers in the cluster
    
    # group.id -> unique string that identifies the consumer group this consumer belongs to, incase of the multiple replicas of the same micro service.
    'group.id': 'order-tracer-id',
    
    'auto.offset.reset': 'earliest' # what to do when there is no bookmark
    
    # '''offset is a unique sequential ID assigned to each message within a partition. It
    # acts as a bookmark for where a consumer has read up to.
    # consumer starts -> stored offset (exists?) -> yes (Start from stored position)
    #                                            -> no(auto offset into play) -> 1. earliest(from start) 2.latest(from end) 3.none(error)'''
}

consumer = Consumer(consumer_config)

consumer.subscribe(['orders'])
## subscribe means - registers interest in one or more topics
## puts the consumer into a consumer group (if group.id is set)
## kafka then:
## - finds all the partitions of those topics
## Assigns partitions to this consumer (and rebalances across other consumers in the group)

print("Consumer is running and subscribed to orders topic")

try:
    while True:
        msg = consumer.poll(1.0)
        if msg is None:
            continue
        if msg.error():
            print(f"Error: {msg.error()}")
            continue

        value = msg.value().decode('utf-8')
        order = json.loads(value)

        print(f"Recieved order: {order['quantity']} X {order['item']} from {order['user']}")
except KeyboardInterrupt:
    print("\n Stopping Consumer")
finally:
    consumer.close()