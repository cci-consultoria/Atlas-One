# Rastreabilidade — auditoria do SQL 0.2

Status inicial de todos os itens: **aberto**. Um item só muda para "resolvido" com correção implementada, teste específico executado e evidência anexada no relatório da entrega.

| Id | Achado | Serviço | Correção prevista | Testes |
|---|---|---|---|---|
| B01 | Escalada para administrador global | Identity, Authorization | `platform_admins` separado; Administrador de sistema limitado à organização; fluxo de plataforma com AAL2 e auditoria | autoelevação; elevação por terceiro; convite/papel com privilégio global |
| B02 | Acesso contábil sem escopo do usuário e sem filtro de estabelecimento | Relationship | `hasAccountingAccess` com membership, escopo, empresa e estabelecimento de origem, serviço, vigência | concessão expirada, revogada, estabelecimento fora, usuário sem escopo |
| B03 | Membership ativo pode ficar sem escopo | Identity | verificação diferida em INSERT/UPDATE/DELETE de escopos e mudança de status; troca de escopos em transação | remover último escopo; concorrência; reativação sem escopo |
| B04 | Configurações expostas | Organization | separar pública/restrita; `core.settings.manage`; segredos só em cofre | leitura restrita por membro comum |
| B05 | RPCs só comentadas | Todos | cada operação de `core-services.md` implementada e testada; nada conta como pronto por assinatura | cobertura por operação |
| I01 | Overrides em papéis administrados pela plataforma | Authorization | matriz base de sistema imutável pela org; sem override no Administrador (ver V-02) | override em Administrador; edição de base de sistema |
| I02 | Auditoria pouco granular | Audit | `core.audit.view` com escopo | leitura fora do escopo |
| I03 | Leitura ampla de relacionamentos | Relationship | só partes com permissão | terceiro lendo |
| I04 | Leitura ampla de concessões; origem incoerente | Relationship | leitura restrita; FKs compostas empresa/estabelecimento | estabelecimento de outra empresa |
| I05 | Exposição de perfis | Identity | perfil de terceiros mínimo e só com organização ativa em comum | leitura de ex-membro |
| I06 | Catálogo de papéis de sistema | Authorization | seed fixo, ids estáveis, check de códigos, protegido | alteração/remoção de papel de sistema |
| I07 | Entidades suspensas | Organization, Authorization | somente leitura (P-04 para organizações) | escrita em suspensa/inativa |
| I08 | Alteração de permissões sem validação completa | Authorization | validação de org, papel, módulo, ação, nível, entidades, autoridade, AAL2 | cada campo inválido |
| I09 | Integridade do relacionamento | Relationship | FK composta empresa cliente ↔ org cliente | empresa de outra org |
| I10 | Convites sem escopo | Identity | ≥ 1 escopo válido na criação e no aceite | convite sem escopo; escopo removido antes do aceite |
| I11 | CNPJ sem DV; matriz concorrente | Organization | DV em TS e SQL; bloqueio na empresa | DV inválido; duas matrizes simultâneas |
| I12 | Assinaturas com campos livres | Subscription | catálogo `plans`/`plan_modules`, enums de status | plano inexistente |
| I13 | Relacionamento ambíguo | Relationship | XOR empresa da plataforma / CNPJ externo válido; serviços em lista fechada | ambos preenchidos; CNPJ inválido |
| I14 | Auditoria não imutável | Audit | trigger de rejeição + sem grants; partição mensal; PK `(id, created_at)` | UPDATE/DELETE |
| I15 | `updated_at` incompleto | Todos | trigger em todas as tabelas mutáveis | atualização reflete horário |
| I16 | Índices de RLS | Todos | índices em `organization_id`, `(membership_id)`, `(user_id, organization_id)`, células | `EXPLAIN` em staging |
| I17 | Privilégios amplos | Fundação/DB | `ALTER DEFAULT PRIVILEGES` revogando; grants explícitos por objeto | tabela nova sem acesso |
| I18 | Exceções de service_role | Identity, Audit | lista fechada de operações privilegiadas (aceite de convite, jobs, plataforma), ator registrado, auditoria | operação privilegiada sem ator |
