"""
Gera deploy/site/privacidade.html (https://musiconnect.app.br/privacidade)
a partir do texto da Política de privacidade do app — a fonte única é
front_musiconnect/lib/presentation/screens/privacy_policy_screen.dart.

    python deploy/gerar_privacidade.py          # regenera a página
    python deploy/gerar_privacidade.py --check  # só confere (usado no CI)

Sempre que a política mudar no app, rode o script e commite a página junto.
"""

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "front_musiconnect/lib/presentation/screens/privacy_policy_screen.dart"
CONSTANTS = ROOT / "front_musiconnect/lib/core/constants.dart"
OUTPUT = ROOT / "deploy/site/privacidade.html"

STRING = re.compile(r"'((?:[^'\\]|\\.)*)'")


def dart_const(source: str, name: str) -> str:
    match = re.search(rf"const String {name} = '([^']*)';", source)
    if not match:
        raise SystemExit(f"{name} não encontrado em {CONSTANTS.name}")
    return match.group(1)


def bracket_body(source: str, start: int) -> str:
    """Conteúdo entre o '[' em `start` e o ']' correspondente."""
    depth, i, in_string = 0, start, False
    while i < len(source):
        c = source[i]
        if in_string:
            if c == "\\":
                i += 1
            elif c == "'":
                in_string = False
        elif c == "'":
            in_string = True
        elif c == "[":
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0:
                return source[start + 1:i]
        i += 1
    raise SystemExit("lista não fechada no arquivo da política")


def paragraphs(body: str, constants: dict) -> list[tuple[str, bool]]:
    """Itens de uma lista Dart: (texto, alterado nesta versão)."""
    items, i = [], 0
    while i < len(body):
        rest = body[i:]
        stripped = rest.lstrip()
        if not stripped:
            break
        i += len(rest) - len(stripped)
        changed = stripped.startswith("_Changed(")
        if changed:
            i += len("_Changed(")
        parts = []
        while True:
            rest = body[i:]
            match = STRING.match(rest.lstrip())
            if not match:
                break
            i += len(rest) - len(rest.lstrip()) + match.end()
            parts.append(match.group(1))
        if not parts:
            raise SystemExit(f"trecho inesperado na política: {body[i:i + 60]!r}")
        text = "".join(parts)
        for name, value in constants.items():
            text = text.replace(f"${name}", value)
        items.append((text, changed))
        # pula ")" de _Changed e a vírgula
        i += len(body[i:]) - len(body[i:].lstrip())
        if changed and body[i:i + 1] == ")":
            i += 1
        i += len(body[i:]) - len(body[i:].lstrip())
        if body[i:i + 1] == ",":
            i += 1
    return items


def render_items(items: list[tuple[str, bool]]) -> str:
    out, in_list = [], False
    for text, changed in items:
        cls = ' class="changed"' if changed else ""
        if text.startswith("• "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li{cls}>{html.escape(text[2:])}</li>")
        else:
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append(f"<p{cls}>{html.escape(text)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n        ".join(out)


def build() -> str:
    source = POLICY.read_text(encoding="utf-8")
    constants_source = CONSTANTS.read_text(encoding="utf-8")
    constants = {"kSupportEmail": dart_const(constants_source, "kSupportEmail")}
    version = dart_const(constants_source, "kPrivacyPolicyVersion")
    year, month, day = version.split("-")

    summary = paragraphs(bracket_body(source, source.index("[", source.index("const _changesSummary"))), constants)
    sections_body = bracket_body(source, source.index("[", source.index("const _sections")))

    sections = []
    for match in re.finditer(r"_PolicySection\(\s*'([^']*)',\s*\[", sections_body):
        body = bracket_body(sections_body, match.end() - 1)
        sections.append(
            f"<section>\n        <h2>{html.escape(match.group(1))}</h2>\n"
            f"        {render_items(paragraphs(body, constants))}\n      </section>"
        )
    if not sections:
        raise SystemExit("nenhuma seção encontrada na política")

    summary_items = "\n          ".join(f"<li>{html.escape(t)}</li>" for t, _ in summary)
    return TEMPLATE.format(
        date=f"{day}/{month}/{year}",
        summary=summary_items,
        sections="\n\n      ".join(sections),
    )


TEMPLATE = """<!doctype html>
<!-- Gerado por deploy/gerar_privacidade.py a partir do texto do app — não edite à mão. -->
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Política de privacidade — MusiConnect</title>
  <meta name="description" content="Como o MusiConnect coleta, usa e protege os seus dados (LGPD).">
  <link rel="icon" href="/favicon.png">
  <style>
    :root {{
      --pink: #DF2881;
      --text: #111827;
      --body: #374151;
      --muted: #6B7280;
      --soft: #FDF2F8;
      --changed: #FFF7E6;
      --changed-border: #F59E0B;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      color: var(--body);
      background: #fff;
      line-height: 1.6;
    }}
    main {{ max-width: 720px; margin: 0 auto; padding: 32px 20px 48px; }}
    .brand {{ display: inline-flex; align-items: center; gap: 10px; text-decoration: none;
      color: var(--text); font-weight: 800; font-size: 18px; }}
    .brand img {{ width: 32px; height: 32px; border-radius: 8px; }}
    .brand b {{ font-weight: 800; }}
    .brand span {{ color: var(--pink); }}
    h1 {{ color: var(--text); font-size: 28px; margin: 28px 0 4px; }}
    .updated {{ color: var(--muted); margin: 0 0 24px; font-size: 14px; }}
    .summary {{ background: var(--soft); border-radius: 14px; padding: 16px 20px; margin-bottom: 8px; }}
    .summary h2 {{ margin-top: 0; }}
    .legend {{ font-size: 13px; color: var(--muted); margin: 12px 0 0; }}
    .legend mark {{ background: var(--changed); border-left: 3px solid var(--changed-border);
      padding: 0 6px; color: inherit; }}
    h2 {{ color: var(--text); font-size: 18px; margin: 28px 0 8px; }}
    ul {{ padding-left: 22px; margin: 8px 0; }}
    li + li {{ margin-top: 4px; }}
    .changed {{ background: var(--changed); border-left: 3px solid var(--changed-border);
      padding: 4px 10px; border-radius: 4px; }}
    li.changed {{ list-style-position: inside; margin-left: -22px; }}
    footer {{ text-align: center; color: var(--muted); font-size: 13px; padding: 0 20px 40px; }}
    footer a {{ color: var(--pink); }}
  </style>
</head>
<body>
  <main>
    <a class="brand" href="/"><img src="/logo.png" alt=""><b>Musi<span>Connect</span></b></a>

    <h1>Política de privacidade</h1>
    <p class="updated">Atualizada em {date}</p>

    <div class="summary">
      <h2>O que mudou nesta versão</h2>
      <ul>
          {summary}
      </ul>
      <p class="legend"><mark>Trechos destacados</mark> são novos ou foram alterados nesta versão.</p>
    </div>

      {sections}
  </main>

  <footer>
    <a href="/">Voltar para o início</a>
  </footer>
</body>
</html>
"""


def main() -> None:
    page = build()
    if "--check" in sys.argv:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != page:
            raise SystemExit(
                "deploy/site/privacidade.html está diferente da política do app.\n"
                "Rode: python deploy/gerar_privacidade.py — e commite a página junto."
            )
        print("Página de privacidade em dia com o app.")
        return
    OUTPUT.write_text(page, encoding="utf-8", newline="\n")
    print(f"Gerado: {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
