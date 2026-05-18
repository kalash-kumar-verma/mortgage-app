"""
Django settings for mortgage_api project.

Environment-aware: reads from .env file or system environment variables.
- Development: copy .env.example → .env, leave DATABASE_URL blank → uses SQLite
- Production:  set DATABASE_URL=postgresql://... → switches to PostgreSQL automatically

python manage.py runserver 0.0.0.0:8000  works unchanged for local development.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file if it exists (development). In production (Docker/Render/Railway),
# env vars are injected by the platform — load_dotenv() safely does nothing.
load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent


# ─── Security ────────────────────────────────────────────────────────────────

# In production: set SECRET_KEY env var to a strong random value.
# Generate one with:
#   python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
SECRET_KEY = os.environ.get(
    'SECRET_KEY',
    'django-insecure-p*b0@l+2)q&5nq29*^%cv29p1#2nzy)zat)430h8&fn5i2f-jw',  # dev fallback only
)

# DEBUG=True for development, DEBUG=False for production.
# Accepts: "True", "1", "yes" (case-insensitive) → True; everything else → False
DEBUG = os.environ.get('DEBUG', 'True').strip().lower() in ('true', '1', 'yes')

# ALLOWED_HOSTS: comma-separated list of hostnames.
# Development default: ["*"] (allow all — safe because DEBUG=True)
# Production example: ALLOWED_HOSTS=yourdomain.com,yourapp.onrender.com
_allowed_hosts_env = os.environ.get('ALLOWED_HOSTS', '*').strip()
ALLOWED_HOSTS = [h.strip() for h in _allowed_hosts_env.split(',') if h.strip()]


# ─── Application Definition ───────────────────────────────────────────────────

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    'rest_framework',
    'rest_framework.authtoken',
    'corsheaders',

    'core',
]

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework.authentication.TokenAuthentication',
        'rest_framework.authentication.SessionAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
}

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',          # CORS must be first
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',     # Static files in production
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'mortgage_api.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'mortgage_api.wsgi.application'


# ─── Database ────────────────────────────────────────────────────────────────
#
# AUTO-DETECTION:
#   DATABASE_URL is empty (or unset) → SQLite (local dev, zero configuration)
#   DATABASE_URL is set              → PostgreSQL (staging / production)
#
# This means running `python manage.py runserver` locally continues to work
# exactly as before — no .env file needed for basic development.

_database_url = os.environ.get('DATABASE_URL', '').strip()

if _database_url:
    # PostgreSQL via DATABASE_URL (Render, Railway, Docker compose, local PG)
    import urllib.parse as _urlparse
    _parsed = _urlparse.urlparse(_database_url)
    DATABASES = {
        'default': {
            'ENGINE':   'django.db.backends.postgresql',
            'NAME':     _parsed.path.lstrip('/'),
            'USER':     _parsed.username or '',
            'PASSWORD': _parsed.password or '',
            'HOST':     _parsed.hostname or 'localhost',
            'PORT':     str(_parsed.port or 5432),
            'CONN_MAX_AGE': 60,  # keep connections alive for 60s (production perf)
            'OPTIONS': {
                'connect_timeout': 10,
            },
        }
    }
else:
    # SQLite — local development default (no configuration needed)
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME':   BASE_DIR / 'db.sqlite3',
        }
    }


# ─── Password Validation ─────────────────────────────────────────────────────

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]


# ─── Internationalisation ────────────────────────────────────────────────────

LANGUAGE_CODE = 'en-us'
TIME_ZONE     = 'Asia/Kolkata'   # IST — matches the user's timezone
USE_I18N      = True
USE_TZ        = True


# ─── Static & Media Files ────────────────────────────────────────────────────

STATIC_URL  = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'   # collectstatic destination

# WhiteNoise: compress + serve static files directly from gunicorn (no Nginx needed)
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

MEDIA_URL  = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'


# ─── CORS ────────────────────────────────────────────────────────────────────
#
# For local development and open APK distribution: allow all origins.
# To lock down in production, replace with:
#   CORS_ALLOWED_ORIGINS = ['https://yourapp.com']

_cors_origins_env = os.environ.get('CORS_ALLOWED_ORIGINS', '').strip()
if _cors_origins_env:
    CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors_origins_env.split(',') if o.strip()]
    CORS_ALLOW_ALL_ORIGINS = False
else:
    CORS_ALLOW_ALL_ORIGINS = True   # dev default


# ─── Miscellaneous ────────────────────────────────────────────────────────────

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Security headers — enable in production
if not DEBUG:
    SECURE_BROWSER_XSS_FILTER   = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    X_FRAME_OPTIONS             = 'DENY'
    SECURE_SSL_REDIRECT         = True
    SECURE_HSTS_SECONDS         = 31536000   # 1 year
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SESSION_COOKIE_SECURE       = True
    CSRF_COOKIE_SECURE          = True

# CSRF trusted origins — required for Django 4.x when behind a proxy / on HTTPS.
# Comma-separated list of full origins (scheme + host).
# Example: CSRF_TRUSTED_ORIGINS=https://yourapp.onrender.com
_csrf_env = os.environ.get('CSRF_TRUSTED_ORIGINS', '').strip()
if _csrf_env:
    CSRF_TRUSTED_ORIGINS = [o.strip() for o in _csrf_env.split(',') if o.strip()]