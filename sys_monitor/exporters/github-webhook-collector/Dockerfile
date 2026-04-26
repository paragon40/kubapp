FROM python:3.11

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY src ./src

EXPOSE 3000

CMD ["python", "src/app.py"]
