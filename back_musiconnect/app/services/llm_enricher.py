"""
Enriquecimento de oportunidades musicais via Google Gemini.

Pipeline:
  1. Busca oportunidades com enriched_at IS NULL (ainda não processadas)
  2. Para cada uma, envia raw_text ao Gemini Flash 2.0
  3. Gemini extrai campos estruturados em JSON
  4. Atualiza o registro no banco com os dados limpos
  5. Define enriched_at para marcar como processada

Confiança (llm_confidence):
  - >= 0.80 → oportunidade exibida ao usuário final
  - < 0.80  → oportunidade mantida no banco mas não exibida (dado ruim)
"""

import asyncio
import json
import logging
from datetime import datetime, date
from typing import Optional

#import google.generativeai as genai
from google import genai
from sqlalchemy.orm import Session

from app.config import settings
from app.database import SessionLocal
from app.models import Opportunity
from app.services.institution_factory import VALID_CATEGORIES

logger = logging.getLogger("services.llm_enricher")

# Modelo Gemini Flash — atualizar conforme modelos forem disponibilizados
# gemini-3.5-flash-lite: modelo lite disponível com quota generosa no free tier
GEMINI_MODEL = "gemini-3.5-flash-lite"

# Aguarda entre chamadas para respeitar o free tier
# gemini-2.0-flash-lite: 30 req/min, 1500 req/dia
RATE_LIMIT_SLEEP = 2.5  # segundos → max ~24 req/min (com margem de segurança)


def _build_prompt(raw_text: str) -> str:
    today = date.today().strftime("%d/%m/%Y")
    return f"""Você é especialista em oportunidades culturais e musicais.

Analise o texto de um edital/oportunidade e extraia as informações no formato JSON.
Retorne APENAS o JSON válido, sem textos técnicos adicionais, sem markdown, sem ```json.

A data de hoje é {today}.

{{
  "title": "título TRADUZIDO para português brasileiro, limpo e conciso (máx 150 caracteres)",
  "description": "descrição clara do que é a oportunidade em 2-4 frases em português",
  "type": "um de: audicao | emprego | curso | competicao",
  "instruments": ["Violino", "Piano", "Vocal"] — lista de instrumentos SEMPRE em português, primeira letra maiúscula. Use 'Vocal' para voz/cântante/singer/voice. Se não mencionado, retorne [].
  "level": "um de: iniciante | intermediario | avancado | profissional | null",
  "deadline": "DD/MM/AAAA — se houver intervalo de datas (ex: '1 Aug 2026 - 15 Jan 2027'), use a data FINAL como prazo. Se não houver prazo explícito, retorne null",
  "country": "país onde ocorre em português (ex: Brasil, Bélgica, Alemanha) ou null",
  "state": "sigla do estado (SP, RJ, MG...) ou null se fora do Brasil",
  "city": "cidade onde ocorre ou null",
  "institution": "nome da ORQUESTRA, CONSERVATÓRIO, FESTIVAL ou ORGANIZAÇÃO responsável (NÃO a plataforma Musical Chairs/Funarte/DOU, e NÃO o nome de uma sala de concerto/teatro/endereço do evento). Se o texto só mencionar um local/venue e não a organização responsável, retorne null.",
  "institution_category": "tipo da organização de \"institution\", um de: music_school (conservatório, escola ou faculdade de música) | music_org (orquestra, banda, coro, companhia de ópera/balé, festival, concurso, fundação ou associação) | concert_hall (sala de concerto) | theatre (teatro ou casa de ópera) | music_venue (casa de shows) | null se institution for null ou não der para saber",
  "is_remote": true se online/remoto, false se presencial ou não especificado,
  "is_active": true se prazo ainda não venceu ou não especificado, false se claramente vencido,
  "is_music_related": true ou false,
  "llm_confidence": 0.0 a 1.0 (confiança na extração e relevância para músicos)
}}

Texto do edital:
{raw_text[:3000]}"""


def _parse_llm_response(text: str) -> Optional[dict]:
    """Tenta parsear o JSON retornado pelo Gemini."""
    # Remove possível markdown residual
    cleaned = text.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1])

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as e:
        logger.warning(f"[Enricher] Falha ao parsear JSON do Gemini: {e}")
        logger.debug(f"[Enricher] Resposta bruta: {text[:500]}")
        return None


def _parse_deadline(deadline_str: Optional[str]) -> Optional[date]:
    """Converte 'DD/MM/AAAA' para objeto date."""
    if not deadline_str:
        return None
    try:
        return datetime.strptime(deadline_str.strip(), "%d/%m/%Y").date()
    except ValueError:
        return None


# Mapeamento de nomes de instrumentos em inglês para português
_INSTRUMENT_PT = {
    "violin": "Violino", "viola": "Viola",
    "cello": "Violoncelo", "violoncello": "Violoncelo",
    "double bass": "Contrabaixo", "contrabass": "Contrabaixo", "bass": "Contrabaixo",
    "harp": "Harpa", "flute": "Flauta", "oboe": "Oboé",
    "clarinet": "Clarinete", "bassoon": "Fagote",
    "horn": "Trompa", "french horn": "Trompa",
    "trumpet": "Trompete", "trombone": "Trombone", "tuba": "Tuba",
    "piano": "Piano", "organ": "Órgão", "harpsichord": "Cravo",
    "guitar": "Violão", "percussion": "Percussão",
    "voice": "Vocal", "singing": "Vocal", "singer": "Vocal",
    "soprano": "Soprano", "mezzo-soprano": "Mezzo-Soprano", "mezzo soprano": "Mezzo-Soprano",
    "alto": "Contralto", "tenor": "Tenor",
    "baritone": "Barítono", "bass-baritone": "Baixo-Barítono",
    "conducting": "Regência", "conductor": "Regência",
    "composition": "Composição", "composing": "Composição",
    "saxophone": "Saxofone", "accordion": "Acordeão",
    "lute": "Alaude", "mandolin": "Mandolim",
}


def _normalize_instrument(name: str) -> str:
    """Normaliza nome do instrumento para português capitalizado."""
    key = name.strip().lower()
    return _INSTRUMENT_PT.get(key, name.strip().title())


def _apply_enrichment(opp: Opportunity, data: dict) -> None:
    """Aplica os campos extraídos pelo LLM ao objeto Opportunity."""
    opp.title        = (data.get("title") or opp.title)[:300]
    opp.description  = data.get("description") or opp.description
    # type: mesma lógica de institution/deadline — se o scraper já
    # classificou pela URL (dado estrutural confiável), isso prevalece
    # sobre o palpite do LLM. Sem essa prioridade, masterclasses/workshops/
    # dias abertos (corretamente marcados "curso" pelo scraper) às vezes
    # eram reclassificados como "edital" pelo LLM, que só vê o texto solto.
    opp.type         = opp.type or data.get("type")

    # Normaliza instrumentos para português
    raw_instruments = data.get("instruments") or opp.instruments or []
    opp.instruments  = [_normalize_instrument(i) for i in raw_instruments if i]

    opp.level        = data.get("level") or opp.level
    # deadline e institution: se já vieram da página de detalhe do scraper
    # (dado estruturado, confiável), isso prevalece sobre o palpite do LLM,
    # que só tem o texto solto do resumo RSS para tentar adivinhar.
    opp.deadline     = opp.deadline or _parse_deadline(data.get("deadline"))
    opp.institution  = opp.institution or data.get("institution")
    category = data.get("institution_category")
    opp.institution_category = category if category in VALID_CATEGORIES else None
    opp.country      = data.get("country") or opp.country
    opp.state        = data.get("state") or opp.state
    opp.city         = data.get("city") or opp.city
    opp.is_remote    = data.get("is_remote", opp.is_remote)
    opp.is_active    = data.get("is_active", opp.is_active)

    # Se LLM diz que não é musical, desativa para não exibir
    if not data.get("is_music_related", True):
        opp.is_active = False

    opp.llm_confidence = float(data.get("llm_confidence", 0.5))
    opp.enriched_at    = datetime.utcnow()


async def enrich_opportunities() -> dict:
    """
    Enriquece todas as oportunidades ainda não processadas pelo LLM.

    Returns:
        Dict com contagens de processados, sucesso e falhas.
    """
    if not settings.gemini_api_key:
        logger.error("[Enricher] GEMINI_API_KEY não configurada. Abortando.")
        return {"error": "GEMINI_API_KEY não configurada", "processed": 0}

    # Novo SDK google-genai (v2.x): usa Client ao invés de genai.configure()
    client = genai.Client(api_key=settings.gemini_api_key)

    db: Session = SessionLocal()
    success = 0
    failed = 0

    try:
        # Busca todas as oportunidades ainda não enriquecidas
        pending = (
            db.query(Opportunity)
            .filter(Opportunity.enriched_at == None)  # noqa: E711
            .filter(Opportunity.raw_text != None)      # noqa: E711
            .all()
        )

        logger.info(f"[Enricher] {len(pending)} oportunidades para enriquecer")

        for i, opp in enumerate(pending):
            try:
                prompt = _build_prompt(opp.raw_text or opp.description or opp.title)

                # Tenta com até 2 retries para lidar com 503 transient
                response = None
                for attempt in range(2):
                    try:
                        response = client.models.generate_content(
                            model=GEMINI_MODEL,
                            contents=prompt,
                        )
                        break  # sucesso, sai do retry loop
                    except Exception as api_err:
                        err_str = str(api_err)
                        # 429: cota esgotada — lê o retryDelay da resposta da API
                        if "429" in err_str or "RESOURCE_EXHAUSTED" in err_str:
                            import re as _re
                            delay_match = _re.search(r'retryDelay.*?\"(\d+)s', err_str)
                            wait_s = int(delay_match.group(1)) + 5 if delay_match else 60
                            logger.warning(
                                f"[Enricher] Cota esgotada (429). "
                                f"Aguardando {wait_s}s antes de retomar..."
                            )
                            await asyncio.sleep(wait_s)
                            # Não retenta no mesmo registro; marca como falha e continua
                            raise  # propaga para o bloco except externo
                        # 503: sobrecarga momentânea — retry rápido
                        elif "503" in err_str or "UNAVAILABLE" in err_str:
                            if attempt == 0:
                                logger.warning(f"[Enricher] 503 transitório, retry em 10s...")
                                await asyncio.sleep(10)
                                continue
                            raise
                        else:
                            raise

                if response is None:
                    raise RuntimeError("Sem resposta após retries")

                data = _parse_llm_response(response.text)

                if data:
                    _apply_enrichment(opp, data)
                    db.commit()
                    success += 1
                    logger.info(
                        f"[Enricher] [{i+1}/{len(pending)}] OK — "
                        f"'{opp.title[:60]}' "
                        f"(confiança: {opp.llm_confidence:.2f})"
                    )
                else:
                    opp.enriched_at    = datetime.utcnow()
                    opp.llm_confidence = 0.0
                    db.commit()
                    failed += 1
                    logger.warning(
                        f"[Enricher] [{i+1}/{len(pending)}] Parse falhou — "
                        f"'{opp.title[:60]}'"
                    )

                await asyncio.sleep(RATE_LIMIT_SLEEP)

            except Exception as e:
                logger.error(
                    f"[Enricher] Erro ao processar '{opp.title[:60]}': {e}"
                )
                failed += 1
                await asyncio.sleep(RATE_LIMIT_SLEEP)

    finally:
        db.close()

    total = success + failed
    logger.info(
        f"[Enricher] Concluído: {total} processadas, "
        f"{success} com sucesso, {failed} falhas"
    )
    return {
        "total_pending": len(pending) if "pending" in dir() else 0,
        "processed": total,
        "success": success,
        "failed": failed,
    }
