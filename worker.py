import json
import os
import signal
import time

import redis
from azure.servicebus import ServiceBusClient

from api import app, db, CarModel 

CONNECTION = os.environ["SERVICEBUS_CONNECTION"]
QUEUE_NAME = os.environ.get("QUEUE_NAME", "car-writes")
DELAY = float(os.environ.get("WORKER_DELAY_SECONDS", "0"))  
REQUEST_TTL = 24 * 60 * 60

rds = None
if os.environ.get("REDIS_URL"):
    rds = redis.Redis.from_url(os.environ["REDIS_URL"], decode_responses=True)

running = True


def stop(*_):
    """SIGTERM: дообробити поточну пачку й завершитись (коректне завершення)."""
    global running
    running = False


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)


def set_status(request_id, data):
    if rds:
        rds.set(f"req:{request_id}", json.dumps(data), ex=REQUEST_TTL)


def handle(payload):
    request_id = payload["request_id"]
    if rds:
        current = rds.get(f"req:{request_id}")
        if current and json.loads(current).get("status") == "done":
            print(f"skip duplicate {request_id}", flush=True)
            return

    c = payload["car"]
    with app.app_context():
        car = CarModel(brand=c["brand"], engine_power=c["engine_power"],
                       max_speed=c["max_speed"], img=c["img"],
                       type=c["type"], price=c["price"])
        db.session.add(car)
        db.session.commit()
        car_id = car.id

    set_status(request_id, {"status": "done", "car_id": car_id})


def main():
    print("worker started", flush=True)
    with ServiceBusClient.from_connection_string(CONNECTION) as client:
        with client.get_queue_receiver(queue_name=QUEUE_NAME) as receiver:
            while running:
                messages = receiver.receive_messages(max_message_count=10, max_wait_time=5)
                for msg in messages:
                    try:
                        handle(json.loads(str(msg)))
                        if DELAY:
                            time.sleep(DELAY)
                        receiver.complete_message(msg)     
                    except Exception as e:
                        print(f"error: {e}", flush=True)
                        receiver.abandon_message(msg)      
    print("worker stopped", flush=True)


if __name__ == "__main__":
    main()