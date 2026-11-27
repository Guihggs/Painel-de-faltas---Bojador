# Painel de Faltas – Projeto Bojador

![HTML5](https://img.shields.io/badge/HTML5-E34F26?logo=html5&logoColor=white)
![JavaScript](https://img.shields.io/badge/JavaScript-F7DF1E?logo=javascript&logoColor=black)
![Supabase](https://img.shields.io/badge/Supabase-3FCF8E?logo=supabase&logoColor=white)
![Vercel](https://img.shields.io/badge/deploy-Vercel-000000?logo=vercel&logoColor=white)

Painel web da **demà** para acompanhar as faltas registradas pelos instrutores do **Projeto Bojador**. Os administradores têm uma visão completa da operação. Cada instrutor tem uma área própria, focada no acompanhamento diário das suas faltas.

**Acesso em produção:** <https://painel-de-faltas-bojador.vercel.app>

---

## Sumário

- [Visão geral](#visão-geral)
- [Funcionalidades](#funcionalidades)
- [Arquitetura](#arquitetura)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Instalação e configuração](#instalação-e-configuração)
- [Operação](#operação)
- [Modelo de dados](#modelo-de-dados)
- [Segurança](#segurança)
- [Tecnologias](#tecnologias)

---

## Visão geral

| | Administrador | Instrutor |
|---|---|---|
| **Dados visíveis** | Todas as faltas da base | Somente as faltas em que `Criada por` corresponde ao próprio usuário |
| **Páginas** | Visão geral · Pódio · Ocorrências · Análises · Detalhamento · Qualidade da base | O que fazer · Ranking · Minhas faltas · Análises |
| **Ações** | Carregar dados (merge), gerenciar acessos, ativar/inativar instrutores, exportar | Preencher o checklist de acompanhamento, enviar e-mail ao jovem, exportar |

O filtro por instrutor é aplicado **no banco de dados (RLS)**, não só na interface.

## Funcionalidades

### Para administradores

- **Indicadores gerais:** total de faltas, justificadas, não justificadas, ocorrências e atendimentos.
- **Pódio e ranking** de instrutores.
- **Ocorrências:** distribuição por grupo, tipo, estado e responsável pelo atendimento.
- **Análises gráficas** por estado, empresa, turma, módulo e período.
- **Detalhamento individual** com todas as colunas da base, ordenação e filtro em cada coluna.
- **Qualidade da base:** relatório de inconsistências e regras aplicadas na importação.
- **Carga incremental (merge)** a partir de `.xlsx`, `.xls` ou `.csv`, com prévia antes de carregar: insere as faltas novas, atualiza as existentes e mantém o restante da base.
- **Gerenciar acessos:** criar acessos para todos os instrutores da base de uma vez, editar usuário, nome e senha, ativar, desativar e excluir.
- **Instrutores ativos:** tira do painel inteiro as faltas de instrutores inativos, sem apagar nenhum dado.

### Para instrutores

- **"O que fazer agora":** quadro com as faltas pendentes e um atalho direto para elas.
- **Situação de cada falta:** Pendente → Em andamento → Concluída, com o progresso das 4 etapas.
- **Checklist de acompanhamento:** E-mail enviado, Resposta recebida, Falta justificada e Ocorrência lançada. Cada clique é salvo na hora, com data, hora e autor da alteração.
- **✉ E-mail:** abre uma mensagem pronta para o jovem e marca a etapa "E-mail enviado".
- **Minhas faltas:** tabela enxuta com as colunas Jovem, Situação, Data, Turma, Módulo, **Estado**, Justificada e Ocorrências, cada uma com filtro, e um botão **Detalhes** por falta.
- **Filtros rápidos:** Período, Turma, Módulo e Situação, com os atalhos *Pendentes*, *Esta semana* e *Este mês*.
- **Posição no ranking** ("Você está em Xº de N"), com o ranking completo sob demanda.
- **Guia "Como usar"** no primeiro acesso.

### Recursos gerais

- **Exportação para Excel** com os filtros e a ordem que estão na tela. Dá para exportar **todas as páginas** ou só as **primeiras N páginas** (25 registros por página).
- **Filtros globais** por período, modalidade, instrutor, estado, empresa, turma, módulo, justificativa e ocorrências.
- **Modo de demonstração** com dados fictícios ("Ver com dados de exemplo" na tela de login).
- Layout responsivo (no celular, a tabela vira cartões) e tema claro/escuro automático.

## Arquitetura

```
┌──────────────────────┐      HTTPS       ┌───────────────────────────────┐
│  index.html (Vercel) │ ───────────────► │ Supabase                      │
│  HTML + CSS + JS     │                  │  • Auth (login por usuário)   │
│  Chart.js · SheetJS  │ ◄─────────────── │  • Postgres + RLS             │
└──────────────────────┘                  │  • RPCs (salvar_checklist,    │
                                          │    substituir_faltas, …)      │
                                          │  • Edge Function              │
                                          │    admin-usuarios             │
                                          └───────────────────────────────┘
```

- **Frontend estático:** um único arquivo, sem etapa de build.
- **Backend:** Supabase, com as regras de acesso no próprio banco (RLS e funções `security definer`).
- **Gestão de usuários:** Edge Function que usa a chave secreta só no servidor.

## Estrutura do repositório

| Arquivo | Descrição |
|---|---|
| `index.html` | O painel completo (interface, estilos e lógica). |
| `supabase_setup.sql` | Cria as tabelas, as políticas RLS, as funções e o administrador inicial. Pode ser rodado de novo sem perder dados. |
| `admin-usuarios.ts` | Edge Function que lista, cria, edita, redefine a senha, ativa/desativa e exclui usuários. |

## Instalação e configuração

### 1. Banco de dados

1. No Supabase, abra o **SQL Editor**.
2. Rode todo o conteúdo de `supabase_setup.sql`.

### 2. Edge Function

1. Em **Edge Functions**, crie uma função chamada `admin-usuarios`.
2. Cole o conteúdo de `admin-usuarios.ts` e publique.

> Sempre que o `admin-usuarios.ts` mudar, publique a função de novo.

### 3. Primeiro administrador

Em **Authentication → Users**, crie o usuário do administrador inicial definido em `supabase_setup.sql`. Ele recebe o papel `admin` automaticamente. Os demais acessos são criados pelo próprio painel.

### 4. Configuração do frontend

No início do `<script>` do `index.html`:

```js
const SUPABASE_URL  = 'https://SEU-PROJETO.supabase.co';
const LOGIN_DOMINIO = 'renapsi.org.br';      // usuário "nome.sobrenome" → nome.sobrenome@renapsi.org.br
const SUPABASE_KEY  = 'sb_publishable_...';  // chave PUBLISHABLE (ou anon)
```

> ⚠️ Nunca coloque no `index.html` a senha do banco nem a chave `secret`/`service_role`.

### 5. Deploy

O projeto está ligado à **Vercel**, que publica automaticamente a cada commit na branch `main`. Por ser um arquivo estático, também funciona em qualquer hospedagem estática, como o GitHub Pages.

## Operação

### Carregar dados (carga incremental / merge)

1. Entre como **administrador** e abra o menu do perfil → **Carregar dados**.
2. Escolha um arquivo `.xlsx`, `.xls` ou `.csv` com as colunas:

   `RA` · `NOME` · `CODTURMA` · `MODULO` · `JUSTIFICADA` · `Criada por` · `DATA_FALTA` · `Criada em` · `EMAIL JOVEM` · `EMPRESA` · `ESTADO` · `DATAOCORRENCIA` · `GRUPO_OCORRENCIA` · `TIPO_OCORRENCIA` · `ATENDIMENTO_RESPONSAVEL` · `OBSERVACOES` · `DATA DESLIGAMENTO` · `Total Geral`

3. Confira a prévia e clique em **Carregar no Supabase**. Ao terminar, o painel mostra quantas faltas foram inseridas e quantas foram atualizadas.

A carga usa o método **merge**, pela chave da falta `RA + CODTURMA + DATA_FALTA + MODULO`:

| Situação da falta | O que acontece |
|---|---|
| Está no arquivo e **não existe** na base | É **inserida** |
| Está no arquivo e **já existe** na base | É **atualizada**: as linhas dela são trocadas pelas do arquivo (justificativa, ocorrências, observações etc.) |
| Está na base e **não veio** no arquivo | É **mantida** sem alteração |

- O arquivo pode trazer só o período novo ou alterado, não precisa ser a base inteira.
- Uma falta com várias ocorrências deve vir **com todas as linhas dela** no arquivo, porque a atualização troca o conjunto completo de linhas daquela falta.
- O **checklist dos instrutores é sempre mantido**.
- Cada carga fica registrada em `cargas`, com o modo (`merge`) e as quantidades de faltas novas e atualizadas.

### Criar acessos dos instrutores

Em **Gerenciar acessos → Criar acessos para todos os instrutores da base**, defina a senha inicial e clique em **Ver instrutores sem acesso**. O painel sugere como usuário o próprio `Criada por` em minúsculas (`GUILHERME.BEZERRA` → `guilherme.bezerra`) e cria todos os acessos de uma vez.

> O vínculo entre o instrutor e as faltas compara o **usuário** (ou o **nome**) do acesso com o `Criada por`, sem diferenciar maiúsculas de minúsculas.

### Ativar ou inativar instrutores

Em **Instrutores ativos**, marque cada instrutor como ativo ou inativo. As faltas de um instrutor inativo saem de todos os indicadores, gráficos, rankings e tabelas. Basta reativá-lo para que elas voltem.

## Modelo de dados

| Tabela | Finalidade |
|---|---|
| `painel_usuarios` | Usuários do painel: papel (`admin`/`instrutor`), nome e status. |
| `faltas` | Base de faltas, mantida por cargas incrementais (merge). |
| `cargas` | Histórico das cargas: arquivo, linhas, autor, data, modo e faltas novas/atualizadas. |
| `faltas_identificadores` | Registro permanente de cada falta já publicada. |
| `checklist_acompanhamento_faltas` | Etapas do acompanhamento de cada falta. |
| `instrutores_status` | Instrutores marcados como ativos ou inativos. |

**Identificador estável da falta:** `RA | CODTURMA | DATA_FALTA | MODULO`, exposto como a coluna calculada `id_falta`. Ele não depende do `id` da tabela `faltas`, por isso o checklist continua válido entre uma carga e outra.

**Principais funções:** `mesclar_faltas` (carga incremental/merge, usada pelo painel), `substituir_faltas` (substituição total, mantida só para uso manual no SQL), `salvar_checklist` (gravação das etapas, conferindo o dono da falta), `listar_instrutores_base` e `definir_instrutor_ativo`.

## Segurança

- **As permissões são garantidas no servidor.** Esconder botões na interface é só conveniência.
- **Leitura de dados:** exige um usuário ativo em `painel_usuarios`. O administrador lê tudo e o instrutor lê só as próprias faltas.
- **Checklist:** não aceita insert nem update direto. A escrita passa por `salvar_checklist`, que confere no banco se a falta pertence a quem está gravando.
- **Ações administrativas:** `mesclar_faltas`, `substituir_faltas`, `definir_instrutor_ativo` e a Edge Function `admin-usuarios` recusam quem não for administrador ativo.
- **Usuários desativados** não conseguem entrar.
- **Chaves:** o frontend usa só a chave pública. A chave secreta fica restrita à Edge Function.

## Tecnologias

- HTML, CSS e JavaScript puro, sem frameworks nem build
- [Supabase](https://supabase.com): Auth, Postgres com RLS e Edge Functions (Deno)
- [Chart.js](https://www.chartjs.org/): gráficos
- [SheetJS](https://sheetjs.com/): leitura e exportação de planilhas
- [Vercel](https://vercel.com): hospedagem e deploy contínuo

---

<sub>Projeto interno da Renapsi / demà · Projeto Bojador.</sub>
