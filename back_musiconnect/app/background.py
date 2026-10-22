"""
Disparo de tarefas em segundo plano (ETL, resolvedor) pelas rotas de
administração, sem esperar a resposta HTTP.

O asyncio só guarda referência fraca às tarefas criadas com create_task —
sem uma referência forte, o coletor de lixo pode descartar a tarefa no
meio da execução. Aqui cada tarefa fica num conjunto até terminar.
"""

import asyncio
import logging
from collections.abc import Coroutine

logger = logging.getLogger("background")

_background_tasks: set[asyncio.Task] = set()


def run_in_background(coro: Coroutine) -> asyncio.Task:
    task = asyncio.create_task(coro)
    _background_tasks.add(task)
    task.add_done_callback(_on_done)
    return task


def _on_done(task: asyncio.Task) -> None:
    _background_tasks.discard(task)
    if not task.cancelled() and task.exception() is not None:
        logger.error("Tarefa em segundo plano falhou", exc_info=task.exception())
