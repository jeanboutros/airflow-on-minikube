# syntax=docker/dockerfile:1
FROM apache/airflow:2.9.0

LABEL author="Jean Boutros"
LABEL version="0.0.1"
LABEL name="airflow-custom-image"
LABEL highest_environment="dev"

COPY ./requirements.txt .
RUN python -m pip install --upgrade pip
RUN pip install -r requirements.txt
