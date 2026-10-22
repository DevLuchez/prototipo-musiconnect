"""
Tarefas em segundo plano disparadas pelas rotas de administração (ETL,
resolvedor). Precisam ficar referenciadas até terminar — sem referência,
o Python pode descartar a tarefa no meio (alerta do SonarCloud,
python:S7502).
"""

import asyncio

from app.background import _background_tasks, run_in_background


def test_tarefa_fica_referenciada_ate_terminar():
    async def scenario():
        release = asyncio.Event()

        async def job():
            await release.wait()

        task = run_in_background(job())
        assert task in _background_tasks

        release.set()
        await task
        await asyncio.sleep(0)  # deixa o callback de conclusão rodar
        assert task not in _background_tasks

    asyncio.run(scenario())


def test_erro_na_tarefa_nao_deixa_referencia_presa():
    async def scenario():
        async def job():
            raise RuntimeError("falhou")

        task = run_in_background(job())
        await asyncio.sleep(0.01)
        assert task.done()
        assert task not in _background_tasks

    asyncio.run(scenario())
