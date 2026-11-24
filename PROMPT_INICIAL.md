Você vai implementar o Atlas Core do Atlas One neste repositório (`atlas-one`), que começa vazio.

Leia antes de qualquer alteração, nesta ordem:
1. `CLAUDE.md`
2. `docs/decisions/decisoes.md`
3. `docs/domains/core-services.md`
4. `docs/security/rastreabilidade.md`
5. `docs/reference/ATLAS_ONE_BLUEPRINT_v1.0.md`
6. `docs/reference/AUDITORIA_SQL_0.2_GPT.md`

O SQL em `docs/reference/NAO_APROVADO_atlas-one-schema-draft-0.2.sql` não está aprovado: use apenas como ponto de partida e corrija os achados B01–B05 e I01–I18.

## Ordem obrigatória

0. Fundação (blueprint Fases 0 e 1): monorepo, TypeScript estrito, lint, Vitest, pacotes `contracts`, `validation`, `authorization` (somente contrato + negação por padrão), `database` (interfaces de repositório + implementação em memória), `events` (outbox), `observability`, README e plano de testes.
1. Organization Service
2. Identity Service
3. Authorization Service
4. Subscription Service
5. Relationship Service
6. Audit Service
7. Integração com o frontend administrativo

## Para cada entrega

1. Verificar a documentação existente.
2. Identificar dependências.
3. Implementar o domínio.
4. Criar contratos (Zod + OpenAPI) e validações.
5. Implementar testes unitários, de integração (com repositórios em memória) e de segurança.
6. Revisar segurança e isolamento multiempresa.
7. Documentar decisões em `docs/decisions/`.
8. Parar e apresentar relatório: arquivos criados/alterados, comandos executados com resultado real, achados B/I tratados, riscos e pendências.

Não avance para o próximo serviço sem minha confirmação.

## Proibido

- Executar migrations ou `supabase db push`/`reset` contra qualquer ambiente, inclusive banco local, sem aprovação específica.
- Conectar a produção, ao Supabase do Visor360 ou ao AutoSystem.
- Usar dados reais em testes ou fixtures.
- Colocar credenciais, chaves ou URLs de projetos no código.
- Liberar acesso global por conveniência ou criar atalhos que contornem autorização.
- Declarar teste aprovado sem executá-lo.

SQL de schema, RLS e RPC pode ser **escrito** em `supabase/migrations/` como rascunho versionado e revisável, com testes pgTAP em `supabase/tests/`, mas não aplicado.

Comece pela Fundação. Ao terminar, pare e reporte.
