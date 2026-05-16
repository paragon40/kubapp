FROM python:3.11-slim

WORKDIR /app

COPY . /app

ENV PYTHONUNBUFFERED=1

RUN pip install --no-cache-dir prometheus-client

CMD ["python", "-m", "sre_engine.worker"]

