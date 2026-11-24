# Atlas One — regras permanentes do repositório

## Proibições
- Não executar migrations (nenhum ambiente, inclusive local) sem aprovação explícita registrada em `docs/decisions/`.
- Não conectar a produção. Não usar nem alterar o Supabase do Visor360. Não alterar o AutoSystem nem outros sistemas da CCI.
- Não usar dados reais em testes, seeds ou exemplos (CNPJs fictícios com dígitos válidos gerados por função).
- Não versionar credenciais, chaves, tokens ou URLs de projetos. Usar variáveis de ambiente e cofre de segredos.
- Não liberar acesso global por conveniência. Não criar atalhos que contornem autorização (flags de debug, bypass em testes de integração, `service_role` no frontend).
- Não declarar testes aprovados sem executá-los e mostrar o resultado.
- `docs/reference/NAO_APROVADO_atlas-one-schema-draft-0.2.sql` não está aprovado.

## Decisões obrigatórias (não divergir sem nova aprovação)
- D1 Permissões: somente células alteradas; herança estabelecimento › empresa › organização › base do papel; valor igual ao herdado remove o override.
- D2 Papéis: 7 papéis de sistema (Administrador, Gerente, Operador, Financeiro, Fiscal, Estoque, Auditor) + papéis personalizados por organização, nunca irrestritos. Administrador global da plataforma é distinto e só atribuível por fluxo de plataforma com MFA e auditoria.
- D3 Escopos explícitos e combináveis (organização | empresa | estabelecimento), por união. Membership ativo sem escopo válido não concede acesso.
- D4 Backend híbrido: Edge Functions finas chamando serviços/RPC com o JWT do usuário; serviços dedicados só pelos critérios documentados. Monólito modular nesta etapa, sem microserviços.

## Arquitetura
- Monorepo: `apps/` (web, api, worker), `packages/` (contracts, validation, authorization, database, events, observability, ui, auth), `modules/` (core e futuros), `supabase/`, `docs/`, `tests/`.
- Cada serviço do Core é dono das suas tabelas. Outro serviço só acessa por interface pública do módulo (nunca por consulta direta às tabelas alheias).
- TypeScript estrito. Contratos com Zod, exportados para OpenAPI.
- Identidade do ator vem sempre da sessão autenticada. Nunca aceitar `userId`, papel, permissões ou escopo enviados pelo navegador como autoridade. Organização/empresa/estabelecimento enviados pelo cliente são apenas **alvo** e sempre revalidados.
- Autorização em duas camadas: serviço (contrato `authorize(ctx, module, action, target)`) e banco (RLS + RPC security definer com `search_path = ''`).
- Negação por padrão. Erro de autorização não revela existência do recurso (404 para recurso fora do escopo).
- Alterações em múltiplas entidades: transação única. Auditoria na mesma transação. Eventos de domínio via outbox na mesma transação; publicação pelo worker após o commit.
- Operações críticas aceitam `Idempotency-Key`; mesma chave + mesmo payload devolve a mesma resposta; mesma chave + payload diferente → 409.
- Exclusão de registros críticos é substituída por mudança de situação, cancelamento ou reversão auditável.
- Todo request carrega `correlation_id`, propagado para logs, auditoria e outbox.

## Processo
- Uma entrega por vez, na ordem de `docs/domains/core-services.md`. Parar e reportar ao fim de cada serviço.
- Contradição entre documentos: registrar em `docs/decisions/divergencias.md` e interromper só a parte afetada. Não inventar regras.
- Escolha técnica não estratégica: adotar a alternativa mais segura e sustentável e registrar em `docs/decisions/`.
