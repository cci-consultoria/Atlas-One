# Decisões — Atlas Core

## 1. Decisões estruturais aprovadas (24/11/2026)

| Id | Decisão |
|---|---|
| D1 | Permissões registradas somente nas células alteradas, com herança estabelecimento › empresa › organização › base do papel. Valor igual ao herdado remove o override. |
| D2 | Sete papéis de sistema + papéis personalizados por organização. |
| D3 | Escopos explícitos e combináveis (organização, empresas, estabelecimentos). Sem escopo = sem acesso. |
| D4 | Backend híbrido: Edge Functions inicialmente, serviços dedicados conforme necessidade. |

## 2. Decisões de segurança adotadas (blueprint §10 e auditoria §4)

| Id | Decisão |
|---|---|
| S-01 | Administrador global da plataforma ≠ Administrador da organização. Global: tabela própria (`platform_admins`), atribuído somente por fluxo de plataforma com MFA (AAL2), justificativa e auditoria. Nenhuma operação organizacional pode criar, atribuir ou herdar privilégio global. |
| S-02 | Papel de sistema "Administrador" é administrador **da organização**: irrestrito dentro da organização e do escopo, nunca fora dela. |
| S-03 | Matriz base dos papéis de sistema administrada só pela plataforma. Organizações podem registrar células por nível (D1) nos papéis de sistema não irrestritos; nunca no Administrador. (Ver divergência V-02.) |
| S-04 | Permissão específica `core.audit.view` para leitura de auditoria, respeitando organização e escopo. |
| S-05 | Entidades suspensas/inativas: somente leitura quando permitido; escritas bloqueadas. |
| S-06 | Leituras por views controladas; escritas por serviços/RPC. Tabelas fora da API pública. |
| S-07 | Limite de licenças atingido: bloquear novas ativações (aceite de convite, reativação) e orientar o administrador. |
| S-08 | Staging em projeto Supabase separado (São Paulo, se disponível). PostgreSQL ≥ 15. |
| S-09 | MFA obrigatório para administradores globais e operações críticas (lista em `core-services.md` §0.4). |
| S-10 | Rate limit e proteção contra enumeração em convites, aceite, login e recuperação de senha. |
| S-11 | Grants mínimos; `ALTER DEFAULT PRIVILEGES` revogando acesso automático a tabelas e funções futuras. |
| S-12 | Auditoria imutável (trigger que rejeita UPDATE/DELETE + sem grants), retenção e particionamento mensal. |
| S-13 | Suporte da CCI a organizações clientes: acesso temporário, justificado, aprovado pela organização e auditado (`support_access_grants`). |
| S-14 | Configurações separadas em públicas (`organization_settings_public`) e restritas (`organization_settings_restricted`, permissão `core.settings.manage`). Segredos nunca em tabela: somente cofre (referência por id). |

## 3. Escolhas técnicas não estratégicas (alternativa mais segura)

| Id | Escolha | Motivo |
|---|---|---|
| T-01 | Monorepo pnpm workspaces + Turborepo; TypeScript `strict`, `noUncheckedIndexedAccess`. | Limites por pacote, builds incrementais. |
| T-02 | Zod para contratos; geração OpenAPI a partir dos schemas (`zod-to-openapi`). | Uma fonte de verdade para validação e documentação. |
| T-03 | Serviços dependem de interfaces de repositório; implementação em memória para testes e PostgreSQL (via `postgres`/Kysely) para staging. | Testes sem banco enquanto migrations não são autorizadas. |
| T-04 | Testes de banco em pgTAP (`supabase/tests/`), escritos agora e executados só após autorização de banco local. | Respeita a proibição de migrations. |
| T-05 | Contrato `authorize()` em `packages/authorization` entregue na Fundação com política **negar tudo**; Organization e Identity usam um *authorizer* de teste explícito nos testes. A resolução real (D1/D3) entra no item 3. | Permite seguir a ordem obrigatória sem atalho de autorização em código de produção. |
| T-06 | Outbox: tabela `outbox_events` gravada na transação; worker com `FOR UPDATE SKIP LOCKED`, entrega pelo menos uma vez; consumidores idempotentes por `event_id`. | Garantia pós-commit. |
| T-07 | Idempotência: tabela `idempotency_keys (org, actor, key, request_hash, response, expires_at)`, TTL 24 h. | Reenvios seguros. |
| T-08 | Erros no formato RFC 9457 (problem+json) com `correlation_id`. | Padronização. |
| T-09 | Paginação por cursor; filtros e ordenação por lista branca. | Evita injeção e varreduras. |
| T-10 | CNPJ: validação de dígitos verificadores em `packages/validation` e no banco (função imutável); preparar para CNPJ alfanumérico (vigência 2026). | I11. |
| T-11 | Matriz única por empresa: índice único parcial + `SELECT … FOR UPDATE` na empresa durante criação/troca de matriz. | I11 concorrência. |

## 4. Divergências registradas

| Id | Divergência | Resolução |
|---|---|---|
| V-01 | Ordem do blueprint (§18: Identidade → Segurança → Estrutura empresarial) ≠ ordem obrigatória do responsável (Organization → Identity → Authorization → …). | Vale a instrução mais recente do responsável. A dependência de autorização é atendida por T-05 (contrato com negação por padrão). |
| V-02 | Auditoria I01 pede impedir overrides organizacionais em "papéis cuja matriz deve ser administrada pela plataforma"; D1 permite células por nível. | Interpretação adotada: organizações não alteram a **matriz base** dos papéis de sistema (S-03) e nunca personalizam o Administrador; células por nível (D1) continuam permitidas nos demais papéis de sistema. **Confirmar com o responsável antes do item 3.** |
| V-03 | Protótipo v0.3 usa matriz inteira e escopo implícito. | Seguir D1/D3; protótipo é só referência visual. |

## 5. Pendências que bloqueiam etapas

| Id | Pendência | Bloqueia |
|---|---|---|
| P-01 | Autorizar banco PostgreSQL local efêmero (Docker, sem rede externa) para executar pgTAP. | Execução dos testes de RLS (não a escrita). |
| P-02 | Confirmar V-02. | Item 3 (Authorization Service). |
| P-03 | Catálogo comercial de planos, limites e preços. | Item 4 (dados do catálogo; a estrutura pode ser feita). |
| P-04 | Política contratual/legal para leitura em organização suspensa. | Comportamento final de S-05 para organizações. |
| P-05 | Condições de migration do blueprint §20 (backup, rollback, staging, aprovação). | Qualquer migration. |
