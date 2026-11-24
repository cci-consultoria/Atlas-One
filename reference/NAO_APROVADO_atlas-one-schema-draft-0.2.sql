-- =====================================================================
-- ATLAS ONE — RASCUNHO DE ESQUEMA (PostgreSQL 15+ / Supabase)
-- Versão: rascunho 0.2 · 24/11/2026 · derivado do protótipo v0.3
--
-- !!! NÃO EXECUTAR !!!
-- Documento de revisão. Não é migration. Não aplicar em nenhum ambiente
-- (inclusive o Supabase existente do Visor360). Migration só após:
--   * decisões restantes resolvidas (documento técnico §12);
--   * itens de segurança abertos resolvidos (documento técnico §12);
--   * testes automatizados de RLS escritos e aprovados.
--
-- Decisões aprovadas incorporadas:
--   D1 Permissões ...... somente células alteradas (permission_overrides),
--                        herança estabelecimento › empresa › organização › papel.
--   D2 Papéis .......... 7 papéis de sistema + papéis personalizados por organização.
--   D3 Acesso .......... escopos explícitos e combináveis
--                        (organização | empresas | estabelecimentos).
--   D4 Backend ......... híbrido: Edge Functions chamam funções RPC deste schema
--                        com o JWT do usuário; serviços dedicados conforme necessidade.
--
-- Princípios aplicados:
--   * Nenhuma política de INSERT/UPDATE/DELETE para usuários: toda escrita passa
--     por funções RPC security definer que validam permissão e gravam auditoria
--     na mesma transação.
--   * Funções security definer com search_path vazio e nomes qualificados.
--   * Integridade entre níveis por chaves estrangeiras compostas com organization_id.
-- =====================================================================

create schema if not exists atlas;
revoke all on schema atlas from public;
grant usage on schema atlas to authenticated;

-- ---------- Enumerações ------------------------------------------------
create type atlas.org_status     as enum ('active', 'onboarding', 'suspended');
create type atlas.company_status as enum ('active', 'onboarding', 'inactive');
create type atlas.estab_status   as enum ('active', 'onboarding', 'suspended');
create type atlas.estab_kind     as enum ('headquarters', 'branch');            -- Matriz / Filial
create type atlas.tax_regime     as enum ('simples', 'presumido', 'real', 'mei');
create type atlas.member_status  as enum ('active', 'blocked');
create type atlas.invite_status  as enum ('pending', 'accepted', 'expired', 'canceled');
create type atlas.perm_action    as enum ('view', 'create', 'edit', 'delete', 'approve');
create type atlas.scope_level    as enum ('organization', 'company', 'establishment');
create type atlas.module_status  as enum ('active', 'requested', 'trial', 'canceled');
create type atlas.audit_result   as enum ('success', 'denied', 'failure');

create or replace function atlas.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

-- =====================================================================
-- 1. TENANCY: organização › empresa › estabelecimento
-- =====================================================================
create table atlas.organizations (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  short_name       text,
  kind             text not null,
  responsible_cnpj char(14),
  email_domain     text,
  status           atlas.org_status not null default 'onboarding',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table atlas.companies (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  legal_name      text not null,                                  -- razão social
  trade_name      text not null,                                  -- nome fantasia
  cnpj_base       char(8) not null check (cnpj_base ~ '^[0-9]{8}$'),
  tax_regime      atlas.tax_regime not null,
  status          atlas.company_status not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint companies_org_cnpj_base unique (organization_id, cnpj_base),
  constraint companies_id_org unique (id, organization_id)        -- alvo de FKs compostas
);

create table atlas.establishments (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null,
  company_id             uuid not null,
  name                   text not null,
  kind                   atlas.estab_kind not null,
  cnpj                   char(14) not null unique check (cnpj ~ '^[0-9]{14}$'),
  state_registration     text,                                    -- IE
  municipal_registration text,                                    -- IM
  address                jsonb,
  phone                  text,
  email                  text,
  is_fuel_station        boolean not null default false,
  status                 atlas.estab_status not null default 'onboarding',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint establishments_id_org unique (id, organization_id),
  -- o estabelecimento pertence à mesma organização da empresa
  constraint establishments_company_fk foreign key (company_id, organization_id)
    references atlas.companies(id, organization_id)
);
create unique index one_hq_per_company on atlas.establishments(company_id) where kind = 'headquarters';
create index on atlas.establishments(organization_id);

-- CNPJ do estabelecimento deve começar pelo CNPJ-base da empresa
create or replace function atlas.check_estab_cnpj() returns trigger
language plpgsql set search_path = '' as $$
declare v_base char(8);
begin
  select c.cnpj_base into v_base from atlas.companies c where c.id = new.company_id;
  if substr(new.cnpj, 1, 8) <> v_base then
    raise exception 'CNPJ % não pertence ao CNPJ-base % da empresa', new.cnpj, v_base;
  end if;
  return new;
end $$;
create trigger establishments_cnpj before insert or update of cnpj, company_id
  on atlas.establishments for each row execute function atlas.check_estab_cnpj();

-- CNPJ-base não muda depois que a empresa tem estabelecimentos
create or replace function atlas.lock_cnpj_base() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.cnpj_base <> old.cnpj_base
     and exists (select 1 from atlas.establishments e where e.company_id = old.id) then
    raise exception 'CNPJ-base não pode ser alterado: a empresa já possui estabelecimentos';
  end if;
  return new;
end $$;
create trigger companies_lock_cnpj_base before update of cnpj_base
  on atlas.companies for each row execute function atlas.lock_cnpj_base();

-- =====================================================================
-- 2. CATÁLOGO, PLANOS E CONTRATAÇÃO
-- =====================================================================
create table atlas.modules (
  code       text primary key,      -- core, postos, pdv, conv, payments, fin, contabil, fiscal, bi, ai, docs, int
  name       text not null,
  group_name text not null,         -- Plataforma, Operação, Gestão, Inteligência, Serviços
  is_core    boolean not null default false
);

create table atlas.subscriptions (
  organization_id uuid primary key references atlas.organizations(id),
  plan_code       text not null,
  status          text not null,
  renews_at       date,
  seat_limit      int check (seat_limit is null or seat_limit > 0)
);

create table atlas.organization_modules (
  organization_id uuid not null references atlas.organizations(id),
  module_code     text not null references atlas.modules(code),
  status          atlas.module_status not null,
  updated_at      timestamptz not null default now(),
  primary key (organization_id, module_code)
);

-- =====================================================================
-- 3. PAPÉIS (D2): 7 de sistema + personalizados por organização
-- =====================================================================
create table atlas.roles (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid references atlas.organizations(id),   -- null = papel de sistema
  code            text not null,
  name            text not null,
  description     text,
  is_admin        boolean not null default false,             -- irrestrito; só o Administrador de sistema
  created_from    uuid references atlas.roles(id),            -- modelo usado na criação (cópia independente)
  status          text not null default 'active' check (status in ('active', 'archived')),
  created_by      uuid references auth.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint roles_system_codes check (
    organization_id is not null
    or code in ('admin', 'manager', 'operator', 'finance', 'fiscal', 'inventory', 'auditor')),
  constraint roles_only_system_admin check (
    not is_admin or (organization_id is null and code = 'admin'))
);
create unique index roles_system_code on atlas.roles(code) where organization_id is null;
create unique index roles_org_code    on atlas.roles(organization_id, code) where organization_id is not null;
create unique index roles_org_name    on atlas.roles(organization_id, lower(name)) where organization_id is not null;

-- Matriz base de qualquer papel (sistema ou personalizado). Presença = permitido.
create table atlas.role_permissions (
  role_id     uuid not null references atlas.roles(id) on delete cascade,
  module_code text not null references atlas.modules(code),
  action      atlas.perm_action not null,
  primary key (role_id, module_code, action)
);
-- Papéis de sistema: matriz mantida somente pela plataforma (migrations).
-- Papéis personalizados: matriz copiada do modelo na criação e editada pelo
-- administrador da organização; alterações futuras no modelo NÃO propagam.

-- Garante que o papel usado em participações, convites e overrides é de sistema
-- ou da mesma organização, está ativo e — para overrides — não é o Administrador.
create or replace function atlas.check_role_org() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from atlas.roles r
                  where r.id = new.role_id and r.status = 'active'
                    and (r.organization_id is null or r.organization_id = new.organization_id)) then
    raise exception 'Papel % inválido para a organização %', new.role_id, new.organization_id;
  end if;
  if tg_table_name = 'permission_overrides'
     and exists (select 1 from atlas.roles r where r.id = new.role_id and r.is_admin) then
    raise exception 'O papel Administrador não aceita personalização';
  end if;
  return new;
end $$;

-- =====================================================================
-- 4. IDENTIDADE, PARTICIPAÇÕES E ESCOPOS (D3)
-- =====================================================================
create table atlas.profiles (
  user_id    uuid primary key references auth.users(id),
  full_name  text not null,
  created_at timestamptz not null default now()
);

create table atlas.memberships (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  user_id         uuid not null references auth.users(id),
  role_id         uuid not null references atlas.roles(id),
  status          atlas.member_status not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint memberships_org_user unique (organization_id, user_id),
  constraint memberships_id_org unique (id, organization_id)
);
create index on atlas.memberships(user_id);
create trigger memberships_role before insert or update of role_id, organization_id
  on atlas.memberships for each row execute function atlas.check_role_org();

-- Escopos explícitos e combináveis. União das linhas = área de acesso.
--   organization  → toda a organização
--   company       → a empresa e todos os seus estabelecimentos (atuais e futuros)
--   establishment → somente aquele estabelecimento
-- Participação ativa sem escopo = SEM acesso (nunca acesso total implícito).
create table atlas.membership_scopes (
  id               uuid primary key default gen_random_uuid(),
  membership_id    uuid not null,
  organization_id  uuid not null,
  level            atlas.scope_level not null,
  company_id       uuid,
  establishment_id uuid,
  constraint ms_membership_fk foreign key (membership_id, organization_id)
    references atlas.memberships(id, organization_id) on delete cascade,
  constraint ms_company_fk foreign key (company_id, organization_id)
    references atlas.companies(id, organization_id),
  constraint ms_estab_fk foreign key (establishment_id, organization_id)
    references atlas.establishments(id, organization_id),
  constraint ms_shape check (
    (level = 'organization'  and company_id is null     and establishment_id is null) or
    (level = 'company'       and company_id is not null and establishment_id is null) or
    (level = 'establishment' and company_id is null     and establishment_id is not null)),
  constraint ms_unique unique nulls not distinct (membership_id, level, company_id, establishment_id)
);
create index on atlas.membership_scopes(membership_id);

-- Toda participação ativa precisa de pelo menos um escopo (verificado no commit)
create or replace function atlas.check_membership_has_scope() returns trigger
language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  if tg_table_name = 'memberships' then v_id := new.id; else v_id := old.membership_id; end if;
  if exists (select 1 from atlas.memberships m where m.id = v_id and m.status = 'active')
     and not exists (select 1 from atlas.membership_scopes s where s.membership_id = v_id) then
    raise exception 'Participação % sem escopo explícito', v_id;
  end if;
  return null;
end $$;
create constraint trigger memberships_need_scope after insert or update of status on atlas.memberships
  deferrable initially deferred for each row execute function atlas.check_membership_has_scope();
create constraint trigger scopes_keep_one after delete on atlas.membership_scopes
  deferrable initially deferred for each row execute function atlas.check_membership_has_scope();

create table atlas.invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  email           text not null,
  role_id         uuid not null references atlas.roles(id),
  invited_by      uuid not null references auth.users(id),
  expires_at      timestamptz not null,
  status          atlas.invite_status not null default 'pending',
  created_at      timestamptz not null default now(),
  constraint invitations_id_org unique (id, organization_id)
);
create unique index invitations_one_pending on atlas.invitations(organization_id, lower(email)) where status = 'pending';
create trigger invitations_role before insert or update of role_id
  on atlas.invitations for each row execute function atlas.check_role_org();

create table atlas.invitation_scopes (
  invitation_id    uuid not null,
  organization_id  uuid not null,
  level            atlas.scope_level not null,
  company_id       uuid,
  establishment_id uuid,
  foreign key (invitation_id, organization_id) references atlas.invitations(id, organization_id) on delete cascade,
  foreign key (company_id, organization_id) references atlas.companies(id, organization_id),
  foreign key (establishment_id, organization_id) references atlas.establishments(id, organization_id),
  check (
    (level = 'organization'  and company_id is null     and establishment_id is null) or
    (level = 'company'       and company_id is not null and establishment_id is null) or
    (level = 'establishment' and company_id is null     and establishment_id is not null))
);

-- Token separado: nunca legível por usuários (sem grant, sem política)
create table atlas.invitation_tokens (
  invitation_id uuid primary key references atlas.invitations(id) on delete cascade,
  token_hash    text not null unique
);

-- =====================================================================
-- 5. PERMISSÕES POR CÉLULA (D1)
-- Uma linha = uma célula alterada (papel × nível × módulo × ação).
-- Ausência de linha = herda do nível acima. Restaurar herança = apagar a linha.
-- =====================================================================
create table atlas.permission_overrides (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references atlas.organizations(id),
  role_id          uuid not null references atlas.roles(id),
  level            atlas.scope_level not null,
  company_id       uuid,
  establishment_id uuid,
  module_code      text not null references atlas.modules(code),
  action           atlas.perm_action not null,
  allowed          boolean not null,
  updated_by       uuid references auth.users(id),
  updated_at       timestamptz not null default now(),
  constraint po_company_fk foreign key (company_id, organization_id)
    references atlas.companies(id, organization_id) on delete cascade,
  constraint po_estab_fk foreign key (establishment_id, organization_id)
    references atlas.establishments(id, organization_id) on delete cascade,
  constraint po_shape check (
    (level = 'organization'  and company_id is null     and establishment_id is null) or
    (level = 'company'       and company_id is not null and establishment_id is null) or
    (level = 'establishment' and company_id is null     and establishment_id is not null)),
  constraint permission_overrides_cell unique nulls not distinct
    (organization_id, role_id, level, company_id, establishment_id, module_code, action)
);
create index on atlas.permission_overrides(organization_id, role_id, module_code, action);
create trigger permission_overrides_role before insert or update of role_id, organization_id
  on atlas.permission_overrides for each row execute function atlas.check_role_org();

-- =====================================================================
-- 6. RELACIONAMENTOS CONTÁBEIS, COMPARTILHAMENTO, AUDITORIA, CONFIGURAÇÕES
-- =====================================================================
create table atlas.accounting_relationships (
  id                     uuid primary key default gen_random_uuid(),
  office_organization_id uuid not null references atlas.organizations(id),
  client_company_id      uuid references atlas.companies(id),   -- null = cliente fora da plataforma
  client_external_cnpj   char(14),
  services               text[] not null check (services <@ array['contabil', 'fiscal', 'dp']),
  responsible_user_id    uuid references auth.users(id),
  status                 text not null check (status in ('pending', 'active', 'ended')),
  accepted_by            uuid references auth.users(id),
  accepted_at            timestamptz,
  check (client_company_id is not null or client_external_cnpj is not null)
);

create table atlas.data_grants (
  id                      uuid primary key default gen_random_uuid(),
  owner_organization_id   uuid not null references atlas.organizations(id),
  dataset                 text not null,              -- sales_fiscal, bank_statements, payroll, bi, card_tx
  source_company_id       uuid,
  source_establishment_id uuid,
  grantee_organization_id uuid references atlas.organizations(id),
  grantee_label           text,                       -- conector ou terceiro fora da plataforma
  purpose                 text not null,
  valid_until             date,
  status                  text not null check (status in ('pending', 'active', 'revoked')),
  approved_by             uuid references auth.users(id),
  foreign key (source_company_id, owner_organization_id) references atlas.companies(id, organization_id),
  foreign key (source_establishment_id, owner_organization_id) references atlas.establishments(id, organization_id),
  check (grantee_organization_id is not null or grantee_label is not null)
);

-- Append-only. Candidata a particionamento mensal por created_at.
create table atlas.audit_events (
  id              bigint generated always as identity primary key,
  organization_id uuid not null,
  actor_user_id   uuid,                                       -- null = sistema
  action          text not null,
  module_code     text not null,
  entity_type     text,
  entity_id       text,
  result          atlas.audit_result not null,
  ip              inet,
  user_agent      text,
  correlation_id  text,
  payload         jsonb,
  created_at      timestamptz not null default now()
);
create index on atlas.audit_events(organization_id, created_at desc);

create table atlas.organization_settings (
  organization_id uuid primary key references atlas.organizations(id),
  settings        jsonb not null default '{}'
);

create trigger t_orgs   before update on atlas.organizations  for each row execute function atlas.touch_updated_at();
create trigger t_comps  before update on atlas.companies      for each row execute function atlas.touch_updated_at();
create trigger t_estabs before update on atlas.establishments for each row execute function atlas.touch_updated_at();
create trigger t_roles  before update on atlas.roles          for each row execute function atlas.touch_updated_at();
create trigger t_memb   before update on atlas.memberships    for each row execute function atlas.touch_updated_at();

-- =====================================================================
-- 7. FUNÇÕES DE AUTORIZAÇÃO
-- =====================================================================

-- Participação ativa em organização não suspensa
create or replace function atlas.is_member(p_org uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from atlas.memberships m
      join atlas.organizations o on o.id = m.organization_id
     where m.organization_id = p_org and m.user_id = auth.uid()
       and m.status = 'active' and o.status <> 'suspended');
$$;

create or replace function atlas.is_org_admin(p_org uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select atlas.is_member(p_org) and exists (
    select 1 from atlas.memberships m
      join atlas.roles r on r.id = m.role_id
      join atlas.membership_scopes s on s.membership_id = m.id and s.level = 'organization'
     where m.organization_id = p_org and m.user_id = auth.uid() and m.status = 'active' and r.is_admin);
$$;

-- Contratação: verificação independente da permissão
create or replace function atlas.has_module(p_org uuid, p_module text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_module = 'core' or exists (
    select 1 from atlas.organization_modules om
     where om.organization_id = p_org and om.module_code = p_module and om.status in ('active', 'trial'));
$$;

-- Escopo (D3). Ação de organização: só escopo de organização.
-- Ação de empresa: escopo de organização ou da empresa.
-- Ação de estabelecimento: organização, empresa dona ou o próprio estabelecimento.
create or replace function atlas.scope_covers(p_membership uuid, p_company uuid, p_estab uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from atlas.membership_scopes s
     where s.membership_id = p_membership
       and ( s.level = 'organization'
          or (s.level = 'company' and p_company is not null and s.company_id = p_company)
          or (s.level = 'establishment' and p_estab is not null and s.establishment_id = p_estab)));
$$;

-- Visibilidade na árvore (leitura de cadastro): escopo de estabelecimento
-- permite ver a empresa dona, mas não concede ações sobre a empresa inteira.
create or replace function atlas.can_see_company(p_org uuid, p_company uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select atlas.is_member(p_org) and exists (
    select 1 from atlas.memberships m
      join atlas.membership_scopes s on s.membership_id = m.id
     where m.organization_id = p_org and m.user_id = auth.uid() and m.status = 'active'
       and ( s.level = 'organization'
          or (s.level = 'company' and s.company_id = p_company)
          or (s.level = 'establishment' and exists (
                select 1 from atlas.establishments e
                 where e.id = s.establishment_id and e.company_id = p_company))));
$$;

create or replace function atlas.can_see_establishment(p_org uuid, p_company uuid, p_estab uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select atlas.is_member(p_org) and exists (
    select 1 from atlas.memberships m
      join atlas.membership_scopes s on s.membership_id = m.id
     where m.organization_id = p_org and m.user_id = auth.uid() and m.status = 'active'
       and ( s.level = 'organization'
          or (s.level = 'company' and s.company_id = p_company)
          or (s.level = 'establishment' and s.establishment_id = p_estab)));
$$;

-- Resolução por célula (D1): estabelecimento › empresa › organização › base do papel.
-- Devolve também a origem, usada pela interface para exibir a herança.
create or replace function atlas.resolve_permission(
  p_role uuid, p_org uuid, p_company uuid, p_estab uuid, p_module text, p_action atlas.perm_action)
returns table (allowed boolean, source text)
language plpgsql stable security definer set search_path = '' as $$
begin
  return query
    select o.allowed, o.level::text
      from atlas.permission_overrides o
     where o.organization_id = p_org and o.role_id = p_role
       and o.module_code = p_module and o.action = p_action
       and ( (o.level = 'establishment' and p_estab is not null and o.establishment_id = p_estab)
          or (o.level = 'company' and p_company is not null and o.company_id = p_company)
          or  o.level = 'organization')
     order by case o.level when 'establishment' then 1 when 'company' then 2 else 3 end
     limit 1;
  if not found then
    return query
      select exists (select 1 from atlas.role_permissions rp
                      where rp.role_id = p_role and rp.module_code = p_module and rp.action = p_action),
             'role'::text;
  end if;
end $$;

-- Autorização efetiva = participação ativa
--                     ∧ organização não suspensa
--                     ∧ módulo contratado
--                     ∧ entidades pertencem à organização e são coerentes entre si
--                     ∧ entidade não suspensa/inativa (exceto leitura)
--                     ∧ escopo cobre o alvo
--                     ∧ (Administrador ∨ célula resolvida = permitido)
create or replace function atlas.has_permission(
  p_org uuid, p_module text, p_action atlas.perm_action,
  p_company uuid default null, p_estab uuid default null)
returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_m       atlas.memberships;
  v_admin   boolean;
  v_company uuid := p_company;
  v_comp_st atlas.company_status;
  v_est_st  atlas.estab_status;
  v_allowed boolean;
begin
  if not atlas.is_member(p_org) then return false; end if;
  if not atlas.has_module(p_org, p_module) then return false; end if;

  select * into v_m from atlas.memberships
   where organization_id = p_org and user_id = auth.uid() and status = 'active';

  if p_estab is not null then
    select e.company_id, e.status into v_company, v_est_st
      from atlas.establishments e where e.id = p_estab and e.organization_id = p_org;
    if not found then return false; end if;
    if p_company is not null and p_company <> v_company then return false; end if;
  end if;
  if v_company is not null then
    select c.status into v_comp_st from atlas.companies c
     where c.id = v_company and c.organization_id = p_org;
    if not found then return false; end if;
  end if;

  if p_action <> 'view' and (v_comp_st = 'inactive' or v_est_st = 'suspended') then
    return false;
  end if;

  if not atlas.scope_covers(v_m.id, v_company, p_estab) then return false; end if;

  select r.is_admin into v_admin from atlas.roles r where r.id = v_m.role_id;
  if v_admin then return true; end if;

  select rp.allowed into v_allowed
    from atlas.resolve_permission(v_m.role_id, p_org, v_company, p_estab, p_module, p_action) rp;
  return coalesce(v_allowed, false);
end $$;

-- Acesso de escritório contábil a dados de empresa cliente (rascunho):
-- relacionamento ativo com o serviço ∧ compartilhamento ativo e vigente do dataset.
create or replace function atlas.has_accounting_access(p_company uuid, p_service text, p_dataset text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
      from atlas.accounting_relationships ar
      join atlas.memberships m on m.organization_id = ar.office_organization_id
                              and m.user_id = auth.uid() and m.status = 'active'
      join atlas.companies c on c.id = ar.client_company_id
      join atlas.data_grants g on g.owner_organization_id = c.organization_id
                              and g.grantee_organization_id = ar.office_organization_id
     where ar.client_company_id = p_company and ar.status = 'active'
       and p_service = any (ar.services)
       and g.dataset = p_dataset and g.status = 'active'
       and (g.valid_until is null or g.valid_until >= current_date)
       and (g.source_company_id is null or g.source_company_id = p_company));
$$;

-- =====================================================================
-- 8. ESCRITA VIA RPC (exemplos). Chamadas pelas Edge Functions com o JWT do usuário.
-- =====================================================================
create or replace function atlas.log_event(
  p_org uuid, p_action text, p_module text, p_entity_type text, p_entity_id text,
  p_result atlas.audit_result, p_payload jsonb default null)
returns void language sql security definer set search_path = '' as $$
  insert into atlas.audit_events (organization_id, actor_user_id, action, module_code, entity_type, entity_id, result, payload)
  values (p_org, auth.uid(), p_action, p_module, p_entity_type, p_entity_id, p_result, p_payload);
$$;

-- D1: grava somente células que diferem do valor herdado.
-- p_allowed = null  → restaura a herança (remove a célula).
-- p_allowed = valor herdado → remove a célula (não há alteração a registrar).
create or replace function atlas.set_permission_cell(
  p_org uuid, p_role uuid, p_level atlas.scope_level, p_company uuid, p_estab uuid,
  p_module text, p_action atlas.perm_action, p_allowed boolean)
returns text                                   -- 'stored' | 'inherited'
language plpgsql security definer set search_path = '' as $$
declare v_inherited boolean; v_parent_company uuid;
begin
  if not atlas.is_org_admin(p_org) then
    perform atlas.log_event(p_org, 'permission.cell.set', 'core', 'role', p_role::text, 'denied');
    raise exception 'Somente administradores alteram permissões' using errcode = '42501';
  end if;

  if p_level = 'organization' then
    select exists (select 1 from atlas.role_permissions rp
                    where rp.role_id = p_role and rp.module_code = p_module and rp.action = p_action)
      into v_inherited;
  elsif p_level = 'company' then
    select rp.allowed into v_inherited
      from atlas.resolve_permission(p_role, p_org, null, null, p_module, p_action) rp;
  else
    select e.company_id into v_parent_company
      from atlas.establishments e where e.id = p_estab and e.organization_id = p_org;
    if not found then raise exception 'Estabelecimento fora da organização'; end if;
    select rp.allowed into v_inherited
      from atlas.resolve_permission(p_role, p_org, v_parent_company, null, p_module, p_action) rp;
  end if;

  if p_allowed is null or p_allowed = v_inherited then
    delete from atlas.permission_overrides
     where organization_id = p_org and role_id = p_role and level = p_level
       and company_id is not distinct from p_company and establishment_id is not distinct from p_estab
       and module_code = p_module and action = p_action;
  else
    insert into atlas.permission_overrides
      (organization_id, role_id, level, company_id, establishment_id, module_code, action, allowed, updated_by)
    values (p_org, p_role, p_level, p_company, p_estab, p_module, p_action, p_allowed, auth.uid())
    on conflict on constraint permission_overrides_cell
    do update set allowed = excluded.allowed, updated_by = excluded.updated_by, updated_at = now();
  end if;

  perform atlas.log_event(p_org, 'permission.cell.set', 'core', 'role', p_role::text, 'success',
    jsonb_build_object('level', p_level, 'company', p_company, 'establishment', p_estab,
                       'module', p_module, 'action', p_action, 'allowed', p_allowed));
  return case when p_allowed is null or p_allowed = v_inherited then 'inherited' else 'stored' end;
end $$;

-- Demais RPCs previstas (mesmo padrão: verificar → escrever → auditar):
--   atlas.create_organization(name, kind, cnpj, plan, admin_email)        -- plataforma
--   atlas.update_organization(org, patch) / atlas.set_organization_status(org, status)
--   atlas.create_company(org, ...) / atlas.update_company(id, patch) / atlas.set_company_status(id, status)
--   atlas.create_establishment(company, ...) / atlas.update_establishment(id, patch) / atlas.set_establishment_status(id, status)
--   atlas.create_custom_role(org, name, template_role)    -- admin; copia role_permissions do modelo
--   atlas.update_custom_role(role, name, description) / atlas.set_role_base_cell(role, module, action, allowed)
--   atlas.archive_custom_role(role)                       -- recusa se houver participações ou convites ativos
--   atlas.set_membership_role(membership, role)           -- admin
--   atlas.set_membership_scopes(membership, scopes jsonb) -- admin; substitui em transação (≥ 1 escopo)
--   atlas.invite_member(org, email, role, scopes jsonb)   -- admin; token gerado pela Edge Function
--   atlas.accept_invitation(token)                        -- service role na Edge Function (usuário ainda sem participação)
--   atlas.request_module(org, module) / atlas.accept_relationship(id) / atlas.approve_grant(id) / atlas.revoke_grant(id)
-- Regras anti-escalada: só administradores (escopo de organização) gerenciam papéis,
-- células, participações, escopos e convites; ninguém altera a própria participação.

-- =====================================================================
-- 9. RLS — leitura por política; escrita somente via RPC
-- =====================================================================
alter table atlas.organizations            enable row level security;
alter table atlas.companies                enable row level security;
alter table atlas.establishments           enable row level security;
alter table atlas.modules                  enable row level security;
alter table atlas.subscriptions            enable row level security;
alter table atlas.organization_modules     enable row level security;
alter table atlas.roles                    enable row level security;
alter table atlas.role_permissions         enable row level security;
alter table atlas.profiles                 enable row level security;
alter table atlas.memberships              enable row level security;
alter table atlas.membership_scopes        enable row level security;
alter table atlas.invitations              enable row level security;
alter table atlas.invitation_scopes        enable row level security;
alter table atlas.invitation_tokens        enable row level security;   -- sem política: inacessível
alter table atlas.permission_overrides     enable row level security;
alter table atlas.accounting_relationships enable row level security;
alter table atlas.data_grants              enable row level security;
alter table atlas.audit_events             enable row level security;
alter table atlas.organization_settings    enable row level security;

-- Organizações: o usuário vê as próprias participações, mesmo de organização suspensa
create policy org_read on atlas.organizations for select using (
  exists (select 1 from atlas.memberships m
           where m.organization_id = id and m.user_id = (select auth.uid()) and m.status = 'active'));
create policy company_read on atlas.companies for select
  using (atlas.can_see_company(organization_id, id));
create policy estab_read on atlas.establishments for select
  using (atlas.can_see_establishment(organization_id, company_id, id));
create policy modules_read on atlas.modules for select using (true);
create policy subs_read on atlas.subscriptions for select using (atlas.is_member(organization_id));
create policy orgmods_read on atlas.organization_modules for select using (atlas.is_member(organization_id));
create policy roles_read on atlas.roles for select
  using (organization_id is null or atlas.is_member(organization_id));
create policy role_perms_read on atlas.role_permissions for select using (
  exists (select 1 from atlas.roles r where r.id = role_id
           and (r.organization_id is null or atlas.is_member(r.organization_id))));
create policy profiles_read on atlas.profiles for select using (
  user_id = (select auth.uid()) or exists (
    select 1 from atlas.memberships a join atlas.memberships b on a.organization_id = b.organization_id
     where a.user_id = (select auth.uid()) and a.status = 'active' and b.user_id = profiles.user_id));
create policy memberships_read on atlas.memberships for select using (
  user_id = (select auth.uid()) or atlas.has_permission(organization_id, 'core', 'view'));
create policy mscopes_read on atlas.membership_scopes for select using (
  exists (select 1 from atlas.memberships m where m.id = membership_id
           and (m.user_id = (select auth.uid()) or atlas.has_permission(m.organization_id, 'core', 'view'))));
create policy invitations_read on atlas.invitations for select
  using (atlas.has_permission(organization_id, 'core', 'view'));
create policy iscopes_read on atlas.invitation_scopes for select
  using (atlas.has_permission(organization_id, 'core', 'view'));
create policy overrides_read on atlas.permission_overrides for select
  using (atlas.has_permission(organization_id, 'core', 'view'));
create policy rel_read on atlas.accounting_relationships for select using (
  atlas.is_member(office_organization_id)
  or exists (select 1 from atlas.companies c where c.id = client_company_id and atlas.is_member(c.organization_id)));
create policy grants_read on atlas.data_grants for select using (
  atlas.is_member(owner_organization_id) or atlas.is_member(grantee_organization_id));
-- Auditoria: Administrador e Auditor de sistema (ver decisão pendente R2 para papéis personalizados)
create policy audit_read on atlas.audit_events for select using (
  exists (select 1 from atlas.memberships m join atlas.roles r on r.id = m.role_id
           where m.organization_id = audit_events.organization_id and m.user_id = (select auth.uid())
             and m.status = 'active' and r.organization_id is null and r.code in ('admin', 'auditor'))
  and atlas.is_member(organization_id));
create policy settings_read on atlas.organization_settings for select using (atlas.is_member(organization_id));

-- =====================================================================
-- 10. PRIVILÉGIOS
-- =====================================================================
revoke all on all tables in schema atlas from public, anon, authenticated;
grant select on all tables in schema atlas to authenticated;
revoke select on atlas.invitation_tokens from authenticated;
revoke update, delete, truncate on atlas.audit_events from public, anon, authenticated;

revoke all on all functions in schema atlas from public, anon, authenticated;
grant execute on function atlas.is_member(uuid), atlas.has_module(uuid, text),
  atlas.has_permission(uuid, text, atlas.perm_action, uuid, uuid),
  atlas.set_permission_cell(uuid, uuid, atlas.scope_level, uuid, uuid, text, atlas.perm_action, boolean)
  to authenticated;
-- Políticas RLS são avaliadas com o papel do usuário: as funções chamadas
-- nelas (is_member, has_permission, can_see_*) precisam de EXECUTE para authenticated.
-- resolve_permission, scope_covers e log_event ficam restritas ao uso interno
-- (chamadas apenas de dentro de outras funções security definer).
grant execute on function atlas.can_see_company(uuid, uuid),
  atlas.can_see_establishment(uuid, uuid, uuid) to authenticated;
alter default privileges in schema atlas revoke execute on functions from public;

-- Toda tabela operacional futura (vendas, tanques, caixas, títulos...) deve
-- carregar organization_id, company_id e establishment_id com FKs compostas,
-- índices e políticas baseadas em has_permission(org, módulo, ação, company, estab).
