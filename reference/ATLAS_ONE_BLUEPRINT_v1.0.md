# ATLAS ONE
## Blueprint Mestre de Implementação — Atlas Core
**Versão:** 1.0  
**Status:** Especificação para implementação  
**Destino:** Novo repositório independente `atlas-one`  
**Executor:** Claude Code  
**Organização:** CCI Consultoria

---

# 1. Objetivo

Implementar a fundação técnica do Atlas One, começando pelo Atlas Core.

O Atlas One será uma plataforma modular, multiempresa e multiorganização, preparada para atender operações internas da CCI e clientes externos por meio de módulos independentes.

O Atlas Core será responsável pela estrutura organizacional, identidade, autenticação, autorização, permissões, módulos contratados, relacionamentos entre organizações, auditoria e serviços compartilhados.

A implementação deve respeitar os projetos e sistemas existentes, sem introduzir dependências ou alterações no Visor360.

# 2. Regras inegociáveis

1. Criar um novo repositório independente chamado `atlas-one`.
2. Não reutilizar o banco Supabase do Visor360.
3. Não executar migrations nesta etapa.
4. Não conectar a bancos de produção.
5. Não modificar sistemas existentes da CCI.
6. Não implementar regras de negócio exclusivamente no frontend.
7. Não confiar em permissões informadas pelo navegador.
8. Toda operação deve validar organização, empresa, estabelecimento, módulo e permissão.
9. Toda operação sensível deve gerar auditoria.
10. O Assistente Inteligente Atlas não terá acesso irrestrito ao banco.
11. Operações financeiras, fiscais e contábeis devem passar pelos serviços responsáveis.
12. Exclusões de operações críticas devem ser substituídas por cancelamentos, estornos ou reversões auditáveis.
13. Não considerar o SQL 0.2 aprovado.
14. Não avançar para migrations sem concluir os bloqueios de segurança e os testes obrigatórios.

# 3. Arquitetura

Adotar inicialmente uma arquitetura de monólito modular.

**Tecnologias propostas:**
- Next.js e React.
- TypeScript.
- Tailwind CSS.
- PostgreSQL.
- Supabase Auth, em projeto independente.
- Supabase Edge Functions inicialmente.
- APIs e contratos documentados com OpenAPI.
- Vitest para testes unitários e de serviços.
- Playwright para testes de interface e fluxos.
- Filas e processamento assíncrono para tarefas demoradas.
- Armazenamento privado para documentos.

Não introduzir microserviços nesta primeira etapa.

A arquitetura deverá permitir separar serviços no futuro quando houver necessidade comprovada.

# 4. Estrutura do produto

## 4.1 Atlas Core
Responsável por:
- Organizações.
- Empresas e estabelecimentos.
- Usuários e identidades.
- Memberships.
- Papéis e permissões.
- Escopos de acesso.
- Módulos e assinaturas.
- Relacionamentos contábeis.
- Concessões de acesso a dados.
- Auditoria.
- Configurações organizacionais.

## 4.2 Atlas Pessoas
Cadastro central de pessoas físicas e jurídicas, com identificadores, vínculos, contatos e relações empresariais.

Usuários autenticados e pessoas cadastradas são conceitos diferentes. Nem toda pessoa precisa possuir login.

## 4.3 Atlas Documentos
Repositório central de documentos, com armazenamento privado, metadados, versões, classificação, integridade e controle de acesso.

## 4.4 Atlas Integrações
Camada responsável por conectores, importações, exportações, APIs, webhooks, filas, tentativas, reconciliação e registros técnicos.

## 4.5 Assistente Inteligente Atlas
Assistente transversal da plataforma.

Deve:
- Consultar informações autorizadas.
- Analisar documentos.
- Interpretar notas fiscais.
- Identificar divergências.
- Preparar lançamentos.
- Sugerir classificações.
- Executar tarefas autorizadas por meio dos serviços de domínio.
- Solicitar aprovação quando necessário.

O assistente nunca deve executar SQL diretamente nem possuir privilégios superiores aos do usuário.

## 4.6 Atlas Postos
Primeiro produto operacional da plataforma.

Sua implementação ocorrerá após a fundação do Core, com módulos de:
- Cadastros.
- Combustíveis.
- Compras.
- Estoque.
- Conveniência.
- Financeiro.
- PDV.
- Pagamentos.
- Fiscal.
- BI.

O Atlas Postos será implementado de forma progressiva, sem substituir imediatamente o sistema atual.

# 5. Estrutura do repositório

Criar uma estrutura organizada por aplicações, pacotes compartilhados e domínios.

```text
atlas-one/
├── apps/
│   ├── web/
│   ├── api/
│   └── worker/
│
├── packages/
│   ├── ui/
│   ├── auth/
│   ├── authorization/
│   ├── contracts/
│   ├── database/
│   ├── events/
│   ├── validation/
│   └── observability/
│
├── modules/
│   ├── core/
│   ├── people/
│   ├── catalog/
│   ├── documents/
│   ├── integrations/
│   ├── assistant/
│   └── postos/
│
├── supabase/
│   ├── migrations/
│   ├── functions/
│   ├── seed/
│   └── tests/
│
├── docs/
│   ├── architecture/
│   ├── security/
│   ├── api/
│   ├── domains/
│   └── decisions/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── security/
│   └── e2e/
│
├── CLAUDE.md
├── README.md
└── package.json
```

A estrutura pode ser refinada pelo executor, desde que preserve os limites dos domínios e documente qualquer alteração relevante.

# 6. Modelo organizacional

Adotar a seguinte hierarquia:

**Organização → Empresa → Estabelecimento**

- Uma organização pode possuir várias empresas.
- Uma empresa pode possuir vários estabelecimentos.
- Uma empresa representa uma raiz de CNPJ.
- O estabelecimento representa um CNPJ completo.
- Usuários podem participar de várias organizações.
- Uma organização pode ter vários usuários.
- Empresas e estabelecimentos possuem estados próprios.

O usuário autenticado é uma identidade do sistema. A associação do usuário à organização ocorre por meio de membership.

# 7. Identidade e autenticação

Implementar:
- Cadastro e autenticação por e-mail e senha.
- Recuperação de senha.
- Perfil do usuário.
- Memberships.
- Convites.
- Aceitação segura de convites.
- Controle de sessões.
- Preparação para MFA.
- Registro de eventos de autenticação.

O token de convite deve:
- Ser armazenado de forma segura, preferencialmente como hash.
- Ter validade.
- Ser utilizado uma única vez.
- Não permitir ampliação de permissões.
- Estar vinculado à organização e aos escopos previamente definidos.

A aceitação do convite deve validar novamente a situação da organização, do usuário, do convite e das permissões.

# 8. Autorização e permissões

A autorização deve considerar simultaneamente:

1. Identidade autenticada.
2. Membership ativo.
3. Organização.
4. Empresa e estabelecimento.
5. Módulo contratado.
6. Papel atribuído.
7. Permissão específica.
8. Situação das entidades envolvidas.
9. Exigência de MFA para operações sensíveis.

## 8.1 Papéis do sistema

Criar os sete papéis inicialmente definidos:

- Administrador.
- Gerente.
- Operador.
- Financeiro.
- Fiscal.
- Estoque.
- Auditor.

Permitir papéis personalizados por organização.

Papéis personalizados nunca poderão possuir acesso irrestrito.

O administrador global da plataforma deve ser diferente do administrador de uma organização.

**Regra crítica:** uma organização não pode atribuir a si mesma, ou a um usuário comum, privilégios de administrador global.

A atribuição de administrador global deve ocorrer exclusivamente por fluxo privilegiado da plataforma, com autenticação reforçada e auditoria.

## 8.2 Ações

A matriz de permissões deve suportar:
- Visualizar.
- Criar.
- Editar.
- Excluir.
- Aprovar.

Permissões adicionais poderão ser criadas quando os domínios exigirem operações específicas.

## 8.3 Escopos

Permitir escopos:
- Organização.
- Empresa.
- Estabelecimento.

Os escopos podem ser combinados por união.

Regras:
- Escopo de organização abrange suas empresas e estabelecimentos.
- Escopo de empresa abrange todos os estabelecimentos atuais e futuros daquela empresa.
- Escopo de estabelecimento abrange somente o estabelecimento selecionado.
- O acesso à empresa para navegação hierárquica não significa autorização para executar ações em toda a empresa.
- Membership ativo sem escopo válido não concede acesso operacional.

## 8.4 Herança de permissões

Ordem de resolução:

1. Estabelecimento.
2. Empresa.
3. Organização.
4. Permissão-base do papel.

Armazenar somente alterações explícitas.

Quando o valor de uma célula voltar a ser igual ao valor herdado, remover o override.

A interface deve apresentar:
- Valor efetivo.
- Origem da permissão.
- Existência de override.
- Valor herdado.
- Possibilidade de restaurar herança.

# 9. Auditoria do SQL 0.2 — bloqueios obrigatórios

O SQL 0.2 é um rascunho não aprovado. A implementação deverá corrigir e testar os seguintes pontos antes de qualquer migração.

## B01 — Escalada de administrador global
Impedir que administradores organizacionais atribuam papéis globais privilegiados.

## B02 — Acesso contábil
Validar escopo do usuário, empresa de origem, estabelecimento de origem, relacionamento ativo, serviços autorizados e validade da concessão.

## B03 — Escopos de membership
Garantir que nenhuma operação de atualização ou exclusão deixe um membership ativo sem escopo válido.

## B04 — Configurações organizacionais
Separar configurações públicas das restritas. Não permitir que qualquer membro leia dados sensíveis por meio de um JSON genérico.

## B05 — RPCs
Implementar e testar as operações necessárias antes de considerar o banco pronto. Comentários ou assinaturas planejadas não contam como implementação.

## I01 — Papéis globais
Impedir overrides organizacionais em papéis cuja matriz deve ser administrada pela plataforma.

## I02 — Auditoria
Criar permissão específica para consulta de auditoria, respeitando organização, escopo e função do usuário.

## I03 — Relacionamentos contábeis
Restringir a visualização aos participantes autorizados.

## I04 — Concessões de dados
Restringir a leitura das concessões e validar a consistência entre empresa e estabelecimento.

## I05 — Perfis
Evitar exposição desnecessária de dados pessoais e de usuários sem vínculo ativo.

## I06 — Papéis de sistema
Garantir catálogo, identificadores e propriedades dos papéis de sistema.

## I07 — Organizações suspensas
Aplicar o comportamento de somente leitura quando permitido pela política contratual e legal, bloqueando escritas e operações proibidas.

## I08 — Alteração de permissões
Validar organização, papel, módulo, escopo e situação da entidade em todas as operações.

## I09 — Relacionamentos contábeis
Garantir integridade entre organização cliente e empresa vinculada.

## I10 — Convites
Exigir escopos válidos e não permitir convites sem autorização correspondente.

## I11 — CNPJ
Validar formato e dígitos verificadores. Garantir consistência entre raiz e estabelecimento. A regra de matriz deve ser implementada de forma segura contra concorrência.

## I12 — Assinaturas
Usar catálogo e relacionamentos consistentes para planos, módulos, status e vigência.

## I13 — Relacionamentos contábeis
Validar CNPJ externo, serviços autorizados e identificação inequívoca do cliente.

## I14 — Auditoria imutável
Impedir alterações ou exclusões indevidas de eventos. Definir estratégia de particionamento compatível com as chaves e índices.

## I15 — updated_at
Garantir atualização consistente dos campos temporais.

## I16 — Índices
Revisar índices usados por RLS e consultas de autorização.

## I17 — Privilégio mínimo
Não conceder acesso amplo automaticamente a futuras tabelas.

## I18 — service_role
Restringir exceções, validar contexto, registrar ator e auditar todas as operações privilegiadas.

# 10. Decisões de segurança adotadas

- Acesso de suporte da CCI a organizações clientes deve ser temporário, justificado, aprovado e auditado.
- Criar permissão específica `core.audit.view`.
- Entidades suspensas ou inativas devem operar em modo somente leitura quando permitido; escritas ficam bloqueadas.
- Expor leituras por views controladas e operações por RPC/serviços, evitando exposição irrestrita de tabelas.
- Atingido o limite de usuários contratados, bloquear novas ativações e apresentar orientação ao administrador.
- Criar projeto Supabase separado para staging, preferencialmente na região de São Paulo, se disponível.
- Usar PostgreSQL 15 ou superior, validando compatibilidade das funcionalidades adotadas.
- Exigir MFA para administradores globais e operações críticas.
- Implementar rate limits e proteção contra enumeração nos convites.
- Revisar grants e privilégios padrão para novas tabelas e funções.
- Definir retenção, arquivamento e particionamento de auditoria.

# 11. Serviços do Atlas Core

Implementar serviços de domínio independentes.

## Organization Service
Responsável por organizações, empresas, estabelecimentos, status e estrutura hierárquica.

## Identity Service
Responsável por perfis, memberships, convites, sessões e vínculos.

## Authorization Service
Responsável por papéis, permissões, escopos, herança e validação de acesso.

## Subscription Service
Responsável por planos, módulos contratados, limites, vigência e entitlements.

## Relationship Service
Responsável pelos vínculos entre organizações, incluindo relacionamento contábil e concessões específicas de dados.

## Audit Service
Responsável pelos eventos de segurança e auditoria de operações.

Todos os serviços devem compartilhar contratos de autorização e validação.

# 12. Contrato de autorização

Toda operação protegida deve receber ou resolver um contexto contendo:

- Usuário autenticado.
- Organização.
- Módulo.
- Ação.
- Empresa, quando aplicável.
- Estabelecimento, quando aplicável.
- Recurso, quando aplicável.
- Nível de autenticação da sessão.

O identificador do usuário deve ser derivado da sessão autenticada, nunca aceito como autoridade a partir de um parâmetro livre do navegador.

A validação deve acontecer no backend e no banco, conforme a responsabilidade de cada camada.

O frontend pode ocultar ou desabilitar funcionalidades, mas isso não substitui a autorização no servidor.

# 13. Interface administrativa

Criar uma interface administrativa moderna, profissional e responsiva.

Separar claramente:
- Administração global da plataforma.
- Administração de cada organização.

## Telas

1. Visão geral da plataforma.
2. Organizações.
3. Detalhes da organização.
4. Empresas e estabelecimentos.
5. Usuários e memberships.
6. Convites.
7. Papéis e permissões.
8. Matriz de permissões.
9. Planos e módulos.
10. Assinaturas e limites.
11. Relacionamentos contábeis.
12. Concessões de acesso a dados.
13. Auditoria.
14. Segurança.
15. Configurações.

A matriz de permissões deve indicar visualmente se cada permissão é herdada ou sobrescrita.

Alterações sensíveis exigem confirmação, justificativa e autenticação reforçada quando aplicável.

A interface não deve exibir tokens, senhas, chaves privadas ou segredos.

# 14. Assistente Inteligente Atlas

O assistente será um componente transversal do Atlas One.

Criar uma arquitetura de ferramentas controladas, com catálogo de ações, validação de permissões e registro de execução.

Separar os níveis:

1. Consultar.
2. Analisar.
3. Preparar.
4. Executar.

Execução deve ocorrer exclusivamente por serviços de domínio.

Aprovações devem estar vinculadas à operação e ao conteúdo aprovado. Se o conteúdo mudar, a aprovação anterior deve ser invalidada.

O assistente deverá possuir proteção contra prompt injection, vazamento entre organizações e execução de ações não autorizadas.

Preparar integração futura com WhatsApp Business oficial, sem implementá-la como dependência do Core inicial.

# 15. API e eventos

Documentar APIs com OpenAPI.

Padronizar:
- Autenticação.
- Autorização.
- Validação.
- Paginação.
- Filtros.
- Ordenação.
- Tratamento de erros.
- Idempotência.
- Correlation ID.
- Auditoria.

Criar eventos de domínio publicados após confirmação da transação.

Usar padrão outbox para evitar eventos publicados sem a respectiva operação persistida.

# 16. Interface e experiência

Adotar design system próprio do Atlas One.

Diretrizes:
- Identidade visual premium e corporativa.
- Azul e tons escuros como base da identidade.
- Modos claro e escuro.
- Layout responsivo.
- Navegação consistente.
- Componentes acessíveis.
- Estados de carregamento, vazio, sucesso e erro.
- Feedback claro para operações sensíveis.
- Busca, filtros e paginação.
- Navegação hierárquica por organização, empresa e estabelecimento.

O protótipo deve utilizar dados fictícios e não deve depender de banco real.

# 17. Testes obrigatórios

Criar testes unitários, integração, segurança e ponta a ponta.

## Isolamento multi-tenant
- Organização A não acessa dados da organização B.
- Usuário sem membership não acessa recursos.
- Convite de uma organização não permite entrada em outra.

## Permissões
- Usuário sem permissão não executa operação.
- Administrador organizacional não atribui administrador global.
- Papel personalizado nunca recebe acesso irrestrito.
- Override não ultrapassa o escopo autorizado.
- Herança funciona na ordem definida.

## Escopos
- Escopo de estabelecimento não autoriza ações na empresa inteira.
- Escopo de empresa alcança estabelecimentos vinculados.
- Membership ativo sem escopo não concede acesso.
- Atualizações não podem eliminar o último escopo válido.

## Módulos
- Módulo não contratado não pode ser utilizado.
- Desativação de módulo bloqueia novas operações.

## Relacionamentos
- Concessão contábil exige relacionamento válido.
- Concessão expirada ou revogada bloqueia o acesso.
- Empresa e estabelecimento devem pertencer à organização correta.

## Auditoria
- Operações sensíveis geram eventos.
- Usuário não altera ou apaga auditoria.
- Eventos identificam ator e contexto.

## Convites
- Token expirado é recusado.
- Token reutilizado é recusado.
- Convite não amplia escopo ou privilégio.

## Segurança adicional
- Testar elevação de privilégios.
- Testar enumeração de usuários.
- Testar manipulação de identificadores no frontend.
- Testar chamadas diretas às APIs.
- Testar políticas RLS individualmente.
- Testar concorrência em operações críticas.

# 18. Ordem de implementação

## Fase 0 — Preparação
- Criar repositório.
- Configurar ferramentas.
- Documentar arquitetura.
- Criar contratos.
- Consolidar decisões.
- Implementar plano de testes.
- Resolver bloqueios de segurança.

## Fase 1 — Fundação
- Estrutura do monorepo.
- Configuração TypeScript.
- Design system inicial.
- Logs e observabilidade.
- Validação.
- Contratos compartilhados.

## Fase 2 — Identidade
- Autenticação.
- Perfis.
- Memberships.
- Convites.
- Recuperação de acesso.

## Fase 3 — Segurança
- Papéis.
- Permissões.
- Escopos.
- Herança.
- Validação de autorização.
- Testes de isolamento.

## Fase 4 — Estrutura empresarial
- Organizações.
- Empresas.
- Estabelecimentos.
- Validação de CNPJ.

## Fase 5 — Comercial
- Planos.
- Módulos.
- Assinaturas.
- Limites e entitlements.

## Fase 6 — Relacionamentos
- Relacionamentos contábeis.
- Concessões de dados.
- Expiração e revogação.

## Fase 7 — Auditoria
- Eventos de segurança.
- Histórico operacional.
- Retenção e integridade.

## Fase 8 — Interface administrativa
- Todas as telas do Core.
- Fluxos de administração.
- Matriz de permissões.
- Painel de segurança.

## Fase 9 — Validação
- Testes completos.
- Revisão de segurança.
- Revisão de arquitetura.
- Documentação.
- Preparação para staging.

# 19. Critérios de conclusão do Atlas Core

O Atlas Core só poderá ser considerado pronto para avaliação de staging quando:

- Organizações, empresas e estabelecimentos estiverem implementados.
- Autenticação e memberships funcionarem.
- Convites estiverem protegidos.
- Papéis e permissões estiverem implementados.
- Escopos e herança estiverem validados.
- Módulos e assinaturas estiverem controlados.
- Relacionamentos e concessões estiverem protegidos.
- Auditoria estiver funcionando.
- Testes de isolamento multi-tenant forem aprovados.
- Todos os bloqueios B01–B05 e I01–I18 estiverem resolvidos ou formalmente justificados.
- Testes de segurança estiverem aprovados.
- Documentação estiver atualizada.

# 20. Condições para migrations

Nenhuma migration poderá ser executada nesta etapa.

Antes de autorizar migrations, exigir:

1. Revisão completa do modelo de dados.
2. Correção dos bloqueios de segurança.
3. Testes automatizados de RLS.
4. Contratos de API aprovados.
5. Projeto Supabase de staging independente.
6. Revisão dos grants e privilégios.
7. Estratégia de backup e recuperação.
8. Plano de rollback.
9. Aprovação explícita para iniciar a fase de banco.

O banco do Visor360 nunca deve ser utilizado como ambiente do Atlas One.

# 21. Instrução inicial ao Claude Code

Comece inspecionando o repositório de destino. Caso esteja vazio, inicialize o projeto conforme este blueprint.

Não tente implementar tudo em uma única alteração.

Primeiro:
- Crie a estrutura.
- Configure as ferramentas.
- Escreva o README.
- Crie o CLAUDE.md com as regras permanentes.
- Documente os limites entre domínios.
- Configure os testes iniciais.
- Crie o protótipo administrativo com dados fictícios, quando aplicável.

Depois, avance por fases, mantendo cada entrega compilável e testável.

Em cada fase:
- Explique o que foi criado.
- Informe arquivos modificados.
- Informe testes executados e resultados.
- Liste riscos ou pendências.
- Não declare testes aprovados sem executá-los.

Se faltar documentação de origem ou houver contradição entre arquivos, registre a divergência e interrompa somente a parte afetada. Não invente regras.

**Não executar migrations, não conectar a produção e não alterar o Visor360.**

---

**Resultado esperado:** uma fundação Atlas Core segura, modular, testável e documentada, pronta para evoluir até o Atlas Postos e os demais produtos do Atlas One.