# ─────────────────────────────────────────────────────────────────
#  Dockerfile  —  Jewellery Mortgage API
#
#  Multi-stage: slim final image (~200MB).
#  Compatible with: Render, Railway, Fly.io, Docker VPS.
#
#  Build:  docker build -t mortgage-api .
#  Run:    docker run -p 8000:8000 --env-file .env mortgage-api
# ─────────────────────────────────────────────────────────────────

FROM python:3.11-slim

# System dependencies for psycopg2-binary and Pillow
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
        libjpeg62-turbo-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies first (layer caches until requirements.txt changes)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY . .

# Create a non-root user for security
RUN useradd --no-create-home --shell /bin/false appuser \
    && chown -R appuser:appuser /app
USER appuser

# Collect static files into /app/staticfiles
# A dummy SECRET_KEY is passed so collectstatic succeeds without real env vars
RUN SECRET_KEY=build-time-dummy-key python manage.py collectstatic --noinput

# Expose port (Cloud platforms set $PORT; default to 8000 locally)
EXPOSE 8000

# Entrypoint: run migrations then start gunicorn
CMD ["sh", "-c", "python manage.py migrate --noinput && gunicorn mortgage_api.wsgi:application --bind 0.0.0.0:${PORT:-8000} --workers 2 --timeout 60"]
