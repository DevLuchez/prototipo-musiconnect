from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import engine
from app.models import Base
from app.routers import institutions

# Cria as tabelas no banco automaticamente ao iniciar (se não existirem)
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="MusiConnect API",
    description="Backend para descoberta global de instituições musicais.",
    version="0.1.0",
)

# CORS liberado para desenvolvimento — ajuste em produção
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(institutions.router)


@app.get("/")
def health_check():
    return {"status": "ok", "service": "MusiConnect API"}
