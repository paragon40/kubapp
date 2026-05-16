from collections import deque

EVENT_QUEUE = deque(maxlen=1000)

def publish(event):
    EVENT_QUEUE.append(event)

def consume_all():
    events = list(EVENT_QUEUE)
    EVENT_QUEUE.clear()
    return events

