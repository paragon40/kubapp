import threading
import time
import random
import logger

def run():
    while True:
        time.sleep(random.randint(2, 5))

        logger.logger.info(
            "background task",
            extra={
                "extra_data": {
                    "status": random.choice(["ok", "fail"])
                }
            }
        )

def start():
    t = threading.Thread(target=run, daemon=True)
    t.start()
