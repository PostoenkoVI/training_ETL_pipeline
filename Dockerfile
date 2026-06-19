FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1
WORKDIR /app
RUN apt-get update
RUN apt-get install -y gcc
RUN apt-get install -y libpq-dev
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r ./requirements.txt
COPY . ./
CMD ["python", "main.py"]