# Handoff — Atlas One · Atlas Core

Pacote para o Claude Code implementar o Atlas Core em um **novo repositório independente `atlas-one`**.
Preparado em 24/11/2026 pela CCI Consultoria.

## Como usar

1. Crie o repositório vazio `atlas-one` (GitHub, privado). Não reutilize o repositório `CCI` nem o Supabase do Visor360.
2. Copie para o repositório:
   - `repo-files/CLAUDE.md` → raiz do repositório
   - `docs/` → `docs/` do repositório
   - `reference/` → `docs/reference/`
   - `design/` → `docs/design/`
3. Abra o Claude Code na raiz do repositório e cole o conteúdo de `PROMPT_INICIAL.md`.
4. Revise cada entrega antes de autorizar a próxima (o prompt pede parada ao fim de cada serviço).

## Conteúdo

| Caminho | O que é | Status |
|---|---|---|
| `PROMPT_INICIAL.md` | Primeira mensagem ao Claude Code | — |
| `repo-files/CLAUDE.md` | Regras permanentes do repositório | Obrigatório |
| `docs/decisions/decisoes.md` | D1–D4, decisões de segurança adotadas, escolhas técnicas e divergências resolvidas | Obrigatório |
| `docs/domains/core-services.md` | Limites, operações, invariantes, eventos e testes de cada serviço, na ordem de implementação | Obrigatório |
| `docs/security/rastreabilidade.md` | B01–B05 e I01–I18 → serviço, correção e testes | Obrigatório |
| `reference/ATLAS_ONE_BLUEPRINT_v1.0.md` | Blueprint mestre | Fonte primária |
| `reference/AUDITORIA_SQL_0.2_GPT.md` | Auditoria do SQL 0.2 | Fonte primária |
| `reference/NAO_APROVADO_atlas-one-schema-draft-0.2.sql` | Rascunho SQL 0.2 | **Não aprovado. Não executar. Não copiar sem corrigir.** |
| `reference/documento-tecnico/` | Documento de preparação do backend (abrir o `.dc.html` no navegador, mesma pasta dos `.js`) | Contexto |
| `design/prototipo-v0.3/` | Protótipo HTML aprovado (abrir `Atlas One.dc.html`) | Referência visual |

## Precedência das fontes

1. Instruções explícitas mais recentes do responsável (CCI).
2. `docs/decisions/decisoes.md`.
3. Blueprint mestre v1.0.
4. Auditoria do SQL 0.2.
5. Documento técnico de preparação.
6. Protótipo v0.3 (comportamento visual e de navegação, nunca regra de segurança).
7. SQL 0.2 (apenas como ponto de partida a corrigir).

Contradição não resolvida por esta ordem: registrar em `docs/decisions/divergencias.md` e interromper apenas a parte afetada.

## Sobre o protótipo

Os arquivos em `design/` são **referências de design em HTML**, não código de produção. A interface administrativa (Fase 8 / item 7 da ordem) deve ser recriada em Next.js + React + TypeScript + Tailwind, com fidelidade visual alta: mesma paleta, tipografia (Geist / Geist Mono), sidebar escura, azul `#2D5BD8` como cor de identidade, âmbar `#E8A23A` como acento do PDV, cards brancos com borda `#E6E5E0`, tema escuro por tokens próprios (variáveis `--a1-*` no shell `Atlas One.dc.html`). O protótipo usa dados fictícios e simula permissões no navegador — essa simulação **não** é especificação de segurança.

Pontos em que o protótipo diverge das decisões aprovadas (seguir as decisões, não o protótipo):
- Matriz de permissões: o protótipo copia a matriz inteira ao personalizar um nível; o correto é D1 (somente células alteradas, com origem por célula).
- Escopo: no protótipo `'*'` significa organização inteira e membros sem escopo explícito existem; o correto é D3 (escopo explícito obrigatório).
- Administrador: o protótipo não separa administrador global da plataforma de administrador da organização; o correto é a decisão S-01.
