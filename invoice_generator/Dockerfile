# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
ENV FLASK_APP=app.py

# Set work directory
WORKDIR /app

# Install system dependencies for OpenCV, Tesseract, Pyzbar, and WeasyPrint
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    libtesseract-dev \
    libzbar0 \
    libgl1 \
    libglib2.0-0 \
    libpango-1.0-0 \
    libpangoft2-1.0-0 \
    libjpeg-dev \
    libopenjp2-7-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt /app/
RUN pip install --upgrade pip && pip install -r requirements.txt gunicorn

# Copy project
COPY . /app/

# Expose port
EXPOSE 10000

# Run gunicorn server
CMD ["gunicorn", "--bind", "0.0.0.0:10000", "app:app"]
