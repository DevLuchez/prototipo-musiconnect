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
import re
from datetime import datetime, date, timezone
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
# Modelos em ordem de preferência. O flash escreve melhor (o lite deixava
# termos em inglês no título, trocava cargo por nome de instituição e às
# vezes soltava caracteres de outros alfabetos), mas a cota gratuita dele é
# de só 20 pedidos/dia. Esgotada a cota diária de um, segue com o próximo
# (o lite tem cota bem maior; a checagem de inglês abaixo protege o texto).
GEMINI_MODELS = ["gemini-3.5-flash", "gemini-3.5-flash-lite"]

# Aguarda entre chamadas para respeitar o limite por minuto do free tier
RATE_LIMIT_SLEEP = 7  # segundos → ~8 req/min (com margem de segurança)


# Nomes oficiais dos instrumentos — os que aparecem no filtro do app. O
# prompt pede ao Gemini para usar exatamente um destes; o que vier fora da
# lista passa por _INSTRUMENT_PT (inglês, grafias variantes) e, se ainda
# assim for desconhecido, fica como veio e é registrado no log para que a
# lista seja completada.
CANONICAL_INSTRUMENTS = [
    "Violino", "Viola", "Violoncelo", "Contrabaixo", "Harpa",
    "Flauta", "Flauta Doce", "Flautim", "Oboé", "Corne Inglês", "Clarinete", "Clarone",
    "Fagote", "Contrafagote", "Saxofone",
    "Trompa", "Trompete", "Trombone", "Trombone Baixo", "Tuba",
    "Percussão", "Tímpanos", "Bateria",
    "Piano", "Órgão", "Cravo", "Teclado", "Acordeão",
    "Violão", "Guitarra", "Baixo", "Cavaquinho", "Bandolim", "Alaúde", "Sitar", "Gaita de Fole",
    "Vocal", "Soprano", "Mezzo-Soprano", "Contralto", "Tenor", "Barítono",
    "Baixo-Barítono", "Regência", "Composição",
]


def _build_prompt(raw_text: str) -> str:
    today = date.today().strftime("%d/%m/%Y")
    return f"""Você é especialista em oportunidades culturais e musicais.

Analise o texto de um edital/oportunidade e extraia as informações no formato JSON.
Retorne APENAS o JSON válido, sem textos técnicos adicionais, sem markdown, sem ```json.

A data de hoje é {today}.

{{
  "title": "título em português brasileiro, conciso (máx 150 caracteres), no formato 'O quê + instrumento/cargo + na/no Organização' (ex: 'Audição para Tutti Violoncelo na Orquestra Sinfônica de Lahti', 'Bolsa de Harpa na National Repertory Orchestra', 'Verbier Festival Junior Orchestra 2027 - Clarinete'). Só o NOME da organização/evento/programa fica no idioma original; todas as outras palavras vão para o português, inclusive termos em inglês como Audition, Fellowship, Scholarship, Principal, Section, Supplementary, Senior Artist, Teacher, Clarinet, Cello. Revise a ortografia.",
  "description": "descrição clara do que é a oportunidade em 2-4 frases em português, com ortografia revisada",
  "type": "um de: audicao | emprego | curso | competicao",
  "instruments": ["Violino", "Piano", "Vocal"] — lista de instrumentos. Use EXATAMENTE um destes nomes: {", ".join(CANONICAL_INSTRUMENTS)}. Use 'Vocal' para voz/canto/singer/voice. Só se o instrumento não estiver na lista, escreva o nome dele em português. Gêneros (jazz, música de câmara, orquestra) NÃO são instrumentos. Formação com instrumentos definidos → liste-os (quarteto de cordas → Violino, Viola, Violoncelo; trio com piano → Violino, Violoncelo, Piano; quinteto de metais → Trompete, Trompa, Trombone, Tuba; quinteto de sopros → Flauta, Oboé, Clarinete, Fagote, Trompa). Se não mencionado, retorne [].
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
  "is_active_participation": true se a pessoa participa fazendo música — tocando, cantando, regendo ou compondo (vaga, audição, concurso, master class, aula de instrumento/canto/regência/composição, festival-escola, curso aberto a qualquer instrumento); false se é só para ouvir, estudar ou debater (curso teórico ou de apreciação, palestra, conferência, simpósio, inscrição como ouvinte, audição comentada) ou se é para crianças pequenas (musicalização infantil),
  "is_open_call": true se o texto anuncia algo em que músicos podem se inscrever ou se candidatar (vaga, audição, curso, oficina, masterclass, concurso, bolsa, festival com inscrição); false se é notícia, relato, fotos, programação de concertos ou balanço de algo que já aconteceu,
  "llm_confidence": 0.0 a 1.0 (confiança na extração e relevância para músicos)
}}

Texto do edital:
{raw_text[:6000]}"""


# Lembrete acrescentado ao prompt quando a resposta volta em inglês — o
# modelo "lite" às vezes só copia o anúncio quando o texto original é curto.
_PORTUGUESE_REMINDER = (
    "\n\nIMPORTANTE: a resposta anterior veio em inglês. Escreva \"title\" e "
    "\"description\" em português brasileiro (só o nome da organização fica no original)."
)

_EN_WORDS = {"the", "and", "of", "for", "to", "is", "are", "will", "with", "at", "on",
             "audition", "position", "we", "our", "be", "take", "place", "looking"}
_PT_WORDS = {"de", "da", "do", "para", "com", "em", "é", "são", "na", "no", "uma", "um",
             "os", "as", "que", "pelo", "pela", "vaga", "audição"}


def _looks_english(text: Optional[str]) -> bool:
    """Heurística simples: mais palavras típicas do inglês que do português."""
    words = re.findall(r"[a-zà-ÿ]+", (text or "").lower())
    en = sum(w in _EN_WORDS for w in words)
    pt = sum(w in _PT_WORDS for w in words)
    return en >= 2 and en > pt


def _in_english(data: dict) -> bool:
    return _looks_english(data.get("title")) or _looks_english(data.get("description"))


class _DailyQuotaExhausted(Exception):
    """Cota diária de todos os modelos esgotada: o resto fica para amanhã."""


def _is_daily_quota(err: str) -> bool:
    return ("429" in err or "RESOURCE_EXHAUSTED" in err) and "PerDay" in err


def _utc_now() -> datetime:
    """Agora em UTC, sem fuso — as colunas do banco são timestamp sem fuso."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _parse_llm_response(text: str) -> Optional[dict]:
    """Tenta parsear o JSON retornado pelo Gemini."""
    # Remove possível markdown residual
    cleaned = text.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        cleaned = "\n".join(lines[1:-1])

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass
    # O modelo lite às vezes solta uma barra invertida que não é escape
    # válido de JSON (ex: "\u" sem os 4 dígitos, "\(" ) — vira barra literal.
    repaired = re.sub(r'\\(?!["\\/bfnrt]|u[0-9a-fA-F]{4})', r"\\\\", cleaned)
    try:
        return json.loads(repaired)
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


# Inglês e grafias variantes → nome oficial (chaves em minúsculas)
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
    "lute": "Alaúde", "mandolin": "Bandolim",
    "piccolo": "Flautim", "english horn": "Corne Inglês", "cor anglais": "Corne Inglês",
    "bass clarinet": "Clarone", "contrabassoon": "Contrafagote",
    "bass trombone": "Trombone Baixo", "timpani": "Tímpanos", "tímpani": "Tímpanos",
    "tímpano": "Tímpanos", "timpano": "Tímpanos", "drums": "Bateria", "drum kit": "Bateria",
    "keyboard": "Teclado", "electric guitar": "Guitarra", "bass guitar": "Baixo",
    "bagpipes": "Gaita de Fole", "voz": "Vocal", "canto": "Vocal",
    # Grafias que o Gemini já devolveu
    "clarineta": "Clarinete", "fagot": "Fagote", "tpa": "Trompa", "alaude": "Alaúde",
    "mandolim": "Bandolim",
}
_CANONICAL_BY_KEY = {name.lower(): name for name in CANONICAL_INSTRUMENTS}

# Gêneros e formações que o Gemini às vezes devolve como instrumento.
_NOT_INSTRUMENTS = {
    "jazz", "câmara", "camara", "música de câmara", "musica de camara",
    "chamber music", "orquestra", "orchestra",
}

# Palavras que ficam minúsculas no meio do nome ("Gaita de Fole").
_LOWERCASE_WORDS = {"de", "da", "do", "das", "dos", "e"}


def _title_pt(name: str) -> str:
    words = name.split()
    return " ".join(
        w.lower() if i > 0 and w.lower() in _LOWERCASE_WORDS else w[:1].upper() + w[1:].lower()
        for i, w in enumerate(words)
    )


def _normalize_instrument(name: str) -> Optional[str]:
    """Nome oficial do instrumento, em português; None se não for instrumento
    (gênero ou formação). Desconhecido: fica como veio (capitalizado) e vai
    para o log, para completar a lista."""
    key = " ".join(name.split()).lower()
    if not key or key in _NOT_INSTRUMENTS:
        return None
    known = _CANONICAL_BY_KEY.get(key) or _INSTRUMENT_PT.get(key)
    if known:
        return known
    logger.warning(f"[Enricher] Instrumento fora da lista: '{name.strip()}'")
    return _title_pt(key)


def normalize_instruments(names) -> list[str]:
    """Normaliza a lista inteira, sem repetidos e na ordem original."""
    result: list[str] = []
    for name in names or []:
        normalized = _normalize_instrument(name) if name else None
        if normalized and normalized not in result:
            result.append(normalized)
    return result


def renormalize_existing(db: Session) -> int:
    """Aplica a normalização atual às oportunidades já enriquecidas — assim um
    nome acrescentado à lista corrige também as antigas. Devolve quantas
    mudaram."""
    changed = 0
    for opp in db.query(Opportunity).filter(Opportunity.instruments != None):  # noqa: E711
        normalized = normalize_instruments(opp.instruments)
        if normalized != list(opp.instruments):
            opp.instruments = normalized
            changed += 1
    db.commit()
    return changed


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
    opp.instruments  = normalize_instruments(raw_instruments)

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

    # Se LLM diz que não é musical — ou que não é uma chamada (notícia de
    # site de instituição, ver scrapers/wordpress_scraper.py) —, desativa
    # para não exibir
    if not data.get("is_music_related", True) or not data.get("is_open_call", True):
        opp.is_active = False

    # Sem instrumento informado, só fica se a pessoa participa fazendo música
    # — com qualquer instrumento ou numa formação (decisão da Laura,
    # 02/11/2026): curso teórico, palestra, inscrição como ouvinte e
    # musicalização infantil saem. Com instrumento, a regra não se aplica —
    # um erro do modelo não esconde uma audição de violino.
    if not opp.instruments and not data.get("is_active_participation", True):
        opp.is_active = False

    opp.llm_confidence = float(data.get("llm_confidence", 0.5))
    opp.enriched_at    = _utc_now()


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
        fixed = renormalize_existing(db)
        if fixed:
            logger.info(f"[Enricher] Instrumentos padronizados em {fixed} oportunidades já existentes")

        # Busca todas as oportunidades ainda não enriquecidas
        pending = (
            db.query(Opportunity)
            .filter(Opportunity.enriched_at == None)  # noqa: E711
            .filter(Opportunity.raw_text != None)      # noqa: E711
            .all()
        )

        logger.info(f"[Enricher] {len(pending)} oportunidades para enriquecer")

        model_index = 0

        async def generate(contents: str):
            """Chama o modelo atual; cota diária esgotada → próximo modelo."""
            nonlocal model_index
            retried_503 = False
            while True:
                model = GEMINI_MODELS[model_index]
                try:
                    return client.models.generate_content(model=model, contents=contents)
                except Exception as api_err:
                    err_str = str(api_err)
                    if _is_daily_quota(err_str):
                        if model_index + 1 < len(GEMINI_MODELS):
                            model_index += 1
                            logger.warning(
                                f"[Enricher] Cota diária do {model} esgotada; "
                                f"seguindo com o {GEMINI_MODELS[model_index]}"
                            )
                            continue
                        raise _DailyQuotaExhausted() from api_err
                    # 429 por minuto: lê o retryDelay da resposta da API
                    if "429" in err_str or "RESOURCE_EXHAUSTED" in err_str:
                        delay_match = re.search(r'retryDelay.*?\"(\d+)s', err_str)
                        wait_s = int(delay_match.group(1)) + 5 if delay_match else 60
                        logger.warning(
                            f"[Enricher] Cota esgotada (429). "
                            f"Aguardando {wait_s}s antes de retomar..."
                        )
                        await asyncio.sleep(wait_s)
                        # Não retenta no mesmo registro; marca como falha e continua
                        raise
                    # 503: sobrecarga momentânea — um retry rápido
                    if ("503" in err_str or "UNAVAILABLE" in err_str) and not retried_503:
                        retried_503 = True
                        logger.warning("[Enricher] 503 transitório, retry em 10s...")
                        await asyncio.sleep(10)
                        continue
                    raise

        for i, opp in enumerate(pending):
            try:
                prompt = _build_prompt(opp.raw_text or opp.description or opp.title)
                response = await generate(prompt)

                data = _parse_llm_response(response.text)

                if data and _in_english(data):
                    logger.info(f"[Enricher] Resposta em inglês, pedindo de novo: '{opp.title[:60]}'")
                    await asyncio.sleep(RATE_LIMIT_SLEEP)
                    retry = await generate(prompt + _PORTUGUESE_REMINDER)
                    retry_data = _parse_llm_response(retry.text)
                    if retry_data and not _in_english(retry_data):
                        data = retry_data
                    else:
                        logger.warning(f"[Enricher] Continua em inglês: '{opp.title[:60]}'")

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
                    opp.enriched_at    = _utc_now()
                    opp.llm_confidence = 0.0
                    db.commit()
                    failed += 1
                    logger.warning(
                        f"[Enricher] [{i+1}/{len(pending)}] Parse falhou — "
                        f"'{opp.title[:60]}'"
                    )

                await asyncio.sleep(RATE_LIMIT_SLEEP)

            except _DailyQuotaExhausted:
                logger.warning(
                    f"[Enricher] Cota diária de todos os modelos esgotada; "
                    f"{len(pending) - i} oportunidades ficam para a próxima execução"
                )
                break

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
