# ATLAS ONE
## Relatório de Auditoria Técnica e de Segurança — SQL 0.2

**Versão analisada:** atlas-one-schema-draft.sql — 0.2  
**Data do rascunho:** 24/11/2026  
**Objetivo:** identificar falhas estruturais, riscos de segurança e correções necessárias antes da implementação definitiva do Atlas Core.

**Status: NÃO APROVADO PARA EXECUÇÃO**

---

# 1. Escopo da auditoria

Foi realizada uma revisão estática do rascunho SQL 0.2, considerando:

- Estrutura multi-tenant.
- Organizações, empresas e estabelecimentos.
- Identidade e memberships.
- Papéis e permissões.
- Escopos de acesso.
- Herança de permissões.
- Relacionamentos contábeis.
- Compartilhamento de dados.
- Auditoria.
- Políticas RLS.
- Funções RPC.
- Privilégios e grants.

Esta revisão é estática. Não representa execução do SQL, teste de penetração, certificação de segurança ou homologação em PostgreSQL.

Não foram executadas migrations nem alterações em bancos de dados.

# 2. Achados bloqueantes

## B01 — Possibilidade de escalada para administrador global

O mecanismo `check_role_org()` aceita papéis globais quando o papel pertence ao catálogo de sistema.

A proteção existente impede personalização do papel Administrador, mas não garante que sua atribuição a memberships e convites seja exclusiva de um fluxo administrativo da plataforma.

**Risco:** um fluxo de atribuição inadequadamente protegido pode conceder privilégios globais a usuários de uma organização.

**Correção obrigatória:**
- Separar administrador global de administrador organizacional.
- Impedir atribuição de papel global privilegiado por administradores de organizações.
- Criar fluxo exclusivo de plataforma.
- Exigir MFA e auditoria.
- Testar tentativas de autoelevação e elevação por terceiros.

## B02 — Validação insuficiente do acesso contábil

A função `has_accounting_access()` não verifica integralmente os escopos do usuário e não filtra adequadamente o estabelecimento de origem.

**Risco:** um usuário pode receber acesso a dados além do escopo autorizado.

**Correção obrigatória:**
- Validar membership.
- Validar escopos do usuário.
- Validar empresa e estabelecimento.
- Validar serviços autorizados.
- Validar vigência e situação do relacionamento.
- Restringir cada conjunto de dados à concessão correspondente.

## B03 — Possibilidade de membership ativo sem escopo

A validação de escopos não cobre adequadamente todas as operações de atualização.

**Risco:** um membership ativo pode ficar sem escopo válido após uma alteração.

**Correção obrigatória:**
- Garantir pelo menos um escopo válido em todas as operações.
- Validar INSERT, UPDATE e DELETE.
- Realizar a validação no momento correto da transação.
- Criar testes de concorrência e alteração do último escopo.

## B04 — Exposição excessiva de configurações

A política de leitura de `organization_settings` permite acesso amplo aos membros da organização.

**Risco:** configurações sensíveis podem ficar disponíveis para usuários que não deveriam consultá-las.

**Correção obrigatória:**
- Separar configurações públicas e restritas.
- Criar permissões específicas.
- Nunca armazenar segredos em configurações acessíveis ao frontend.
- Utilizar cofre de segredos para credenciais e chaves.

## B05 — Operações RPC ainda não implementadas

O rascunho documenta operações importantes que ainda aparecem como propostas ou comentários.

Entre elas:
- Criação e administração de organizações.
- Alteração de papéis.
- Gestão de escopos.
- Convites e aceite.
- Relacionamentos.
- Aprovação e revogação de concessões.

**Risco:** o modelo aparenta possuir fluxos que ainda não estão efetivamente implementados.

**Correção obrigatória:**
- Implementar os serviços e RPCs necessários.
- Validar autorização em cada operação.
- Registrar auditoria na mesma transação das operações críticas.
- Não considerar comentários ou assinaturas planejadas como funcionalidades concluídas.

# 3. Achados importantes adicionais

## I01 — Papéis globais sujeitos a overrides

A matriz dos papéis de sistema deve ser administrada exclusivamente pela plataforma.

O modelo precisa impedir overrides organizacionais sobre papéis globais cuja matriz seja controlada centralmente.

## I02 — Permissão de auditoria insuficientemente granular

Criar a permissão específica:

`core.audit.view`

A leitura deve respeitar escopo, organização e papel.

## I03 — Leitura ampla dos relacionamentos contábeis

Restringir a leitura dos relacionamentos às partes autorizadas e aos usuários que possuam permissão correspondente.

## I04 — Leitura ampla das concessões de dados

Restringir a consulta das concessões e validar a relação entre empresa e estabelecimento de origem.

## I05 — Exposição de perfis

Revisar as políticas de leitura de `profiles`, evitando exposição desnecessária de informações pessoais.

## I06 — Catálogo de papéis de sistema

Garantir que os sete papéis previstos sejam criados e protegidos por regras de integridade.

## I07 — Entidades suspensas

Definir comportamento consistente para organizações, empresas e estabelecimentos suspensos ou inativos.

Recomendação: somente leitura quando permitido pela política contratual e legal, bloqueando novas operações.

## I08 — Alteração de permissões

A função de alteração de células de permissão precisa validar integralmente:
- Organização.
- Papel.
- Módulo.
- Escopo.
- Empresa.
- Estabelecimento.
- Situação do usuário.
- Autoridade de quem realiza a alteração.

## I09 — Integridade dos relacionamentos

Criar chaves estrangeiras compostas para garantir que a empresa cliente pertence à organização correta.

## I10 — Convites sem escopo obrigatório

O modelo precisa impedir a criação ou aceitação de convites sem escopos válidos.

## I11 — Validação de CNPJ

O rascunho valida formato e vínculo do CNPJ-base, mas precisa validar também os dígitos verificadores.

A regra de matriz deve garantir consistência, inclusive em operações concorrentes.

## I12 — Assinaturas e planos

Substituir campos livres por catálogo e relacionamentos consistentes para planos, status e módulos contratados.

## I13 — Relacionamentos contábeis ambíguos

Validar CNPJ externo, serviços autorizados e identificação inequívoca do cliente.

## I14 — Auditoria não totalmente imutável

O comentário de append-only não é suficiente.

Implementar proteção efetiva contra alteração e exclusão indevidas, além de definir estratégia de retenção e particionamento compatível com as chaves.

## I15 — updated_at incompleto

Revisar todas as tabelas que precisam de atualização automática de `updated_at`.

## I16 — Índices de segurança

Revisar índices utilizados pelas funções de autorização e políticas RLS.

## I17 — Privilégios excessivamente amplos

Revisar grants para evitar que futuras tabelas sejam automaticamente expostas.

## I18 — Exceções de service_role

Documentar e restringir cada operação privilegiada, exigindo validação explícita, identificação do ator e auditoria.

# 4. Decisões técnicas recomendadas

Adotar as seguintes decisões para a revisão do modelo:

1. Administrador global somente por fluxo exclusivo da plataforma.
2. Administrador organizacional restrito à própria organização.
3. Papéis personalizados nunca podem ser irrestritos.
4. Escopos sempre explícitos e validados.
5. Permissões resolvidas pela hierarquia estabelecimento → empresa → organização → papel.
6. Relacionamentos contábeis não concedem acesso irrestrito.
7. Concessões de dados possuem finalidade, escopo, vigência e revogação.
8. Auditoria com leitura controlada e proteção contra alteração.
9. Views de leitura e RPCs para operações protegidas.
10. MFA para administradores globais e operações críticas.
11. Rate limit e proteção contra enumeração nos fluxos de convite.
12. Testes automatizados de RLS e autorização antes de qualquer migration.

# 5. Testes de segurança obrigatórios

Criar uma suíte automatizada que valide:

- Isolamento completo entre organizações.
- Tentativas de elevação de administrador.
- Alteração indevida de papéis.
- Membership ativo sem escopo.
- Acesso a empresas de outras organizações.
- Acesso a estabelecimentos não autorizados.
- Herança de permissões.
- Overrides por nível.
- Acesso a módulos não contratados.
- Relacionamentos contábeis expirados.
- Concessões revogadas.
- Convites expirados e reutilizados.
- Leitura indevida de configurações.
- Alteração ou exclusão de auditoria.
- Chamadas diretas às APIs sem autorização.

Nenhum teste pode ser considerado aprovado sem execução e evidência do resultado.

# 6. Condições para aprovação do SQL

O SQL 0.2 não deve ser executado.

Antes de aprovar uma nova versão:

1. Corrigir todos os bloqueios B01–B05.
2. Resolver os itens I01–I18.
3. Revisar o modelo relacional.
4. Revisar todas as políticas RLS.
5. Implementar as operações RPC.
6. Aprovar os contratos de API.
7. Implementar e executar a suíte de testes de segurança.
8. Revisar grants, funções e privilégios.
9. Criar ambiente Supabase de staging independente.
10. Produzir uma nova versão do SQL para revisão.

# 7. Instruções ao Claude Code

Utilize este relatório como requisito obrigatório de implementação.

Não reproduza automaticamente as estruturas problemáticas do SQL 0.2.

Não considere uma correção concluída apenas porque o código foi alterado.

Para cada achado:
- Identifique a estrutura afetada.
- Explique o risco.
- Proponha a correção.
- Implemente a correção quando estiver dentro da fase autorizada.
- Crie testes específicos.
- Apresente evidências de validação.

Não execute migrations nesta etapa.

Não conecte ao Supabase do Visor360.

Não altere bancos de produção.

Não avance para operações reais até que os bloqueios de segurança estejam resolvidos e aprovados.

**Resultado esperado:** um modelo de dados e autorização revisado, consistente, testável e seguro para servir de base ao Atlas Core.