# ── Build stage ──────────────────────────────────────────────────────────────
FROM python:3.12-slim

# Evita arquivos .pyc e garante output imediato nos logs
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Instala dependências do sistema necessárias para psycopg (libpq) e GeoAlchemy2
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copia e instala dependências Python primeiro (camada cacheável)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia o código da aplicação
COPY . .

EXPOSE 8000

# Em produção, remova --reload. Em desenvolvimento, pode adicionar.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
