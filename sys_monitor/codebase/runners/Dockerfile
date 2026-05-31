FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

# Environment
ENV PYTHONUNBUFFERED=1
ENV METRICS_FILE=./evidence/metrics.prom

EXPOSE 8080

CMD ["python", "src/app.py"]
