import json
import uuid
from confluent_kafka import Producer

producer_config = {
    'bootstrap.servers': '127.0.0.1:9092'
    # provides the initial hosts that act as the starting point for a kafka client to discover the full set of alive servers in the cluster
}

producer = Producer(producer_config)
# provides the initial hosts that act as the starting point for a kafka client to discover the full set of alive servers in the cluster

def delivery_report(err, msg):
    if err:
        print(f"Err: Delivery failed: {err}")
    else:
        print(f"Delivered {msg.value().decode('utf-8')}")
        print(f"topic: {msg.topic()}, partition: {msg.partition()}, time: {msg.timestamp()}")
order = {
    'order_id': str(uuid.uuid4()),
    'user': 'rohit',
    'item': 'sarvi"s chicken biryani',
    'quantity': 21
}

value = json.dumps(order).encode('utf-8') # json -> string -> utf-8 encode


producer.produce(
    topic='orders', 
    value=value,
    callback=delivery_report) # creates the topic if it is not present and produces an event

producer.flush() 
# kafka producer generally buffers messages for performance, instead of sending the every event
# kafka batches the events
# flush() will help in guaranty delivery