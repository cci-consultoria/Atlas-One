# Atlas Core — serviços de domínio

Ordem de implementação obrigatória: 0 Fundação → 1 Organization → 2 Identity → 3 Authorization → 4 Subscription → 5 Relationship → 6 Audit → 7 Frontend administrativo.

## 0. Contratos transversais (Fundação)

### 0.1 Contexto de requisição
```ts
type RequestContext = {
  actor: { userId: string; aal: 'aal1' | 'aal2'; sessionId: string } // somente da sessão verificada
  platformAdmin: boolean                                               // resolvido no servidor
  correlationId: string
  idempotencyKey?: string
}
type Target = { organizationId: string; companyId?: string; establishmentId?: string; resourceId?: string }
```
Nunca construir `actor` a partir de corpo, query ou header livre do cliente.

### 0.2 Autorização
```ts
authorize(ctx, module: ModuleCode, action: Action, target: Target): Promise<Decision>
// Decision = { allowed: true } | { allowed: false; reason: DenyReason }
// DenyReason: not_member | org_suspended | module_not_contracted | entity_mismatch |
//             entity_read_only | out_of_scope | permission_denied | mfa_required
```
Fundação: implementação que nega tudo. Item 3: implementação real. Ações: `view | create | edit | delete | approve` + permissões específicas (`core.audit.view`, `core.settings.manage`, `core.members.manage`, `core.roles.manage`).

### 0.3 Padrão de comando
Validar contrato → resolver alvo real a partir do banco → `authorize` → transação { escrever, `audit.record`, `outbox.enqueue` } → resposta. Idempotência nos comandos marcados ⚑.

### 0.4 Operações que exigem MFA (AAL2)
Atribuir/remover administrador global; alterar papel ou escopo de membro para Administrador; alterar células de permissão; suspender organização; aprovar concessão de dados; aprovar acesso de suporte; exportar auditoria.

### 0.5 Isolamento
Toda tabela multi-tenant tem `organization_id NOT NULL`; relações entre níveis por FKs compostas `(id, organization_id)`. Repositórios exigem `organizationId` em toda consulta (sem método "listar tudo").

---

## 1. Organization Service
**Dono de:** `organizations`, `companies`, `establishments`, `organization_settings_public`, `organization_settings_restricted`.
**Depende de:** contrato de autorização (T-05), Audit (interface `record`), outbox.

| Operação | Regra |
|---|---|
| `createOrganization` ⚑ | Somente administrador global (AAL2). Cria organização em `onboarding`; criação de assinatura e convite do admin acontecem nos itens 2 e 4 via eventos (`organization.created`). |
| `updateOrganization`, `setOrganizationStatus` ⚑ | Admin da org para dados; suspensão só por administrador global. Organização ativa do próprio ator pode ser suspensa apenas pela plataforma. |
| `createCompany` ⚑, `updateCompany`, `setCompanyStatus` | CNPJ-base 8 dígitos, único na organização; imutável após o primeiro estabelecimento. |
| `createEstablishment` ⚑, `updateEstablishment`, `setEstablishmentStatus` | CNPJ válido (DV, T-10), começa pelo CNPJ-base da empresa, único global; matriz única por empresa com bloqueio (T-11). |
| `getTree(org)` | Retorna somente o visível ao escopo do ator (estabelecimento visível ⇒ empresa dona visível para navegação, sem conceder ações). |
| `getSettings` / `updateSettings` | Públicas: membros; restritas: `core.settings.manage`. Nenhum segredo (S-14). |

**Invariantes:** hierarquia coerente entre organizações; sem exclusão física; entidade suspensa/inativa só leitura (S-05).
**Eventos:** `organization.created|updated|status_changed`, `company.*`, `establishment.*`.
**Achados:** B04, I07, I11, I15, I16.
**Testes mínimos:** CNPJ com DV inválido; CNPJ de outra raiz; duas matrizes concorrentes; empresa de org A em estabelecimento de org B; edição de CNPJ-base com filiais; escrita em entidade suspensa; leitura de configuração restrita sem permissão.

## 2. Identity Service
**Dono de:** `profiles`, `memberships`, `membership_scopes`, `invitations`, `invitation_scopes`, `invitation_tokens`, `platform_admins`, eventos de autenticação.
**Depende de:** Organization (existência/situação de entidades), Subscription (limite de licenças, via interface — stub até o item 4 que **nega** ativação se não houver resposta), Authorization (contrato).

| Operação | Regra |
|---|---|
| Cadastro, login, recuperação de senha | Supabase Auth; mensagens que não revelam existência de e-mail (S-10). |
| `inviteMember` ⚑ | Requer `core.members.manage`; ≥ 1 escopo válido da mesma organização; papel de sistema não global ou personalizado da org; ator não pode convidar com escopo ou papel além do seu (não amplia privilégio); rate limit. |
| `acceptInvitation(token)` ⚑ | Token aleatório ≥ 256 bits, só hash armazenado, uso único (`UPDATE … WHERE status='pending' RETURNING`), validade; revalida org ativa, papel ativo, escopos ainda válidos, limite de licenças; e-mail da sessão = e-mail do convite. Executa em serviço com credencial privilegiada, ator registrado (I18). |
| `setMembershipRole` ⚑, `setMembershipScopes` ⚑ | Admin da org com escopo de organização; nunca a própria participação; escopos substituídos em transação com verificação diferida de ≥ 1 escopo em INSERT/UPDATE/DELETE (B03). |
| `blockMember` / `reactivate` | Reativação respeita limite de licenças (S-07). |
| `grantPlatformAdmin` / `revokePlatformAdmin` | Somente por administrador global, AAL2, justificativa, auditoria (B01). Nenhuma API organizacional toca `platform_admins`. |
| `getProfile` | Perfil próprio completo; de terceiros só nome e e-mail, e apenas de quem compartilha organização ativa (I05). |

**Eventos:** `membership.created|role_changed|scopes_changed|blocked`, `invitation.sent|accepted|expired|canceled`, `auth.*`.
**Achados:** B01, B03, I05, I10, I18.
**Testes mínimos:** token expirado, reutilizado, de outra org, com e-mail diferente; convite com escopo maior que o do emissor; remover o último escopo; autoalteração; admin de org tentando criar admin global; enumeração de e-mail; limite de licenças.

## 3. Authorization Service
**Dono de:** `roles`, `role_permissions`, `permission_overrides`, catálogo de ações e permissões específicas.
**Depende de:** Identity (membership e escopos), Organization (entidades e situação), Subscription (módulo contratado, via interface).

Resolução (implementação real de `authorize`):
1. Membership ativo; organização não suspensa (exceto leitura permitida por P-04).
2. Módulo contratado (independente da permissão).
3. Alvo coerente: estabelecimento ∈ empresa ∈ organização.
4. Escrita bloqueada em entidade suspensa/inativa.
5. Escopo cobre o alvo (organização ⊇ empresa ⊇ estabelecimento; estabelecimento não cobre ações de empresa).
6. Administrador da organização → permitido (dentro de 1–5).
7. Célula: estabelecimento › empresa › organização › base do papel.
8. Ação marcada como crítica exige AAL2.

| Operação | Regra |
|---|---|
| `createCustomRole` ⚑ | A partir de um modelo; cópia independente da matriz; nunca irrestrito; nome único na org. |
| `updateRoleBaseCell` | Só papéis personalizados da própria org. Papéis de sistema: só a plataforma (S-03, I01, I06). |
| `setPermissionCell` ⚑ | Admin da org, AAL2; valida org, papel (não Administrador, da org ou de sistema), módulo, ação, nível, empresa/estabelecimento da org e ativos (I08); valor igual ao herdado ⇒ remove (D1). |
| `getEffectiveMatrix(role, level, target)` | Para cada célula: `effective`, `source`, `hasOverride`, `inherited`. |
| `getMyAccess(target)` | Módulos e ações efetivas para a interface (reflexo, não autoridade). |
| `archiveCustomRole` | Recusa se houver membros ou convites ativos. |

**Achados:** B01 (camada de papel), I01, I06, I08, I16.
**Testes mínimos:** herança nos 4 níveis; override removido ao igualar herdado; escopo de estabelecimento x ação de empresa; papel personalizado irrestrito; override em Administrador; papel de outra org; módulo não contratado; módulo desativado bloqueia novas operações; equivalência entre `authorize()` (TS) e `has_permission()` (SQL) sobre a mesma massa de dados (teste de paridade).

## 4. Subscription Service
**Dono de:** `plans`, `plan_modules`, `subscriptions`, `organization_modules`, `module_requests`, limites e entitlements.
**Depende de:** Organization.

| Operação | Regra |
|---|---|
| `getEntitlements(org)` | Módulos ativos/em teste, limite de licenças, vigência. Core sempre incluído. |
| `requestModule` ⚑ | Admin da org; cria solicitação; não ativa. |
| `activateModule` / `deactivateModule` ⚑ | Somente plataforma. Desativação bloqueia novas operações imediatamente; dados preservados. |
| `changePlan` ⚑ | Somente plataforma; catálogo fechado (I12). |
| `checkSeat(org)` | Usado por Identity no aceite/reativação (S-07). |

**Eventos:** `subscription.*`, `module.activated|deactivated|requested`.
**Achados:** I12.
**Testes mínimos:** módulo não contratado; desativação durante uso; limite de licenças no aceite concorrente (dois aceites para a última vaga).

## 5. Relationship Service
**Dono de:** `accounting_relationships`, `data_grants`, `support_access_grants`.
**Depende de:** Organization, Identity, Authorization, Subscription.

| Operação | Regra |
|---|---|
| `proposeRelationship` ⚑ | Escritório (org) propõe; cliente identificado por `client_company_id` (FK composta com a org cliente, I09) **ou** CNPJ externo válido — nunca ambos ambíguos (I13); serviços de lista fechada. |
| `acceptRelationship` / `endRelationship` ⚑ | Aceite pelo admin da org cliente. |
| `requestGrant` / `approveGrant` ⚑ / `revokeGrant` ⚑ | Concessão com dataset, finalidade, origem (empresa e/ou estabelecimento coerentes com a org dona, I04), destinatário, validade. Aprovação AAL2. |
| `hasAccountingAccess(ctx, company, establishment?, service, dataset)` | Membership ativo na org do escritório **e** escopo do usuário cobrindo o relacionamento **e** relacionamento ativo com o serviço **e** concessão ativa, vigente, do dataset, cobrindo a empresa/estabelecimento de origem (B02). |
| `requestSupportAccess` / `approveSupportAccess` ⚑ | Plataforma solicita com justificativa e prazo; org aprova; expira automaticamente (S-13). |
| Leitura | Somente partes do relacionamento com permissão correspondente (I03, I04). |

**Eventos:** `relationship.*`, `grant.*`, `support_access.*`.
**Achados:** B02, I03, I04, I09, I13.
**Testes mínimos:** concessão expirada/revogada; estabelecimento fora da concessão; usuário do escritório sem escopo; relacionamento encerrado; terceiro lendo relacionamento alheio.

## 6. Audit Service
**Dono de:** `audit_events` (particionada por mês), política de retenção.
**Interface usada por todos:** `record(tx, event)` — grava na mesma transação; falha de auditoria aborta a operação crítica.

| Operação | Regra |
|---|---|
| `record` | Ator (da sessão), organização, ação, módulo, entidade, resultado (`success|denied|failure`), IP, user agent, `correlation_id`, payload sem segredos. Tentativas negadas também são registradas. |
| `query` | `core.audit.view`, filtrada por organização e escopo (I02). |
| `export` ⚑ | AAL2, auditada. |
| Retenção | Partições mensais; arquivamento após prazo a definir; chave primária `(id, created_at)` compatível com particionamento (I14). |

**Achados:** I02, I14, I17, I18.
**Testes mínimos:** UPDATE/DELETE rejeitados mesmo com acesso à tabela; evento com ator e contexto; operação sensível sem evento falha; leitura fora do escopo.

## 7. Frontend administrativo
Next.js + React + TypeScript + Tailwind, recriando o protótipo v0.3 (`docs/design/prototipo-v0.3/`). Separar **Administração da plataforma** (administrador global) de **Administração da organização**. Telas: blueprint §13. Matriz com valor efetivo, origem, override, valor herdado e "restaurar herança". Confirmação + justificativa + MFA nas operações de §0.4. Dados fictícios enquanto não houver staging. Testes Playwright: manipulação de ids na URL, chamadas diretas à API sem sessão, ocultação de ações sem permissão.
