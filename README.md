# Painel de Faltas – Projeto Bojador

Painel web da **demà** para acompanhar as faltas registradas pelos instrutores do Projeto Bojador. Mostra indicadores gerais, pódio de instrutores, ocorrências, análises por estado, empresa, turma e módulo, tabela detalhada e um relatório de qualidade da base.

Os dados ficam no **Supabase** e só usuários autorizados entram no painel.

## Funcionalidades

- **Login por usuário** (ex.: `nome.sobrenome`, que vira `nome.sobrenome@renapsi.org.br`).
- **Dois perfis de acesso:**
  - **Instrutor** – vê uma visão individual e simplificada, só com as próprias faltas, e preenche o checklist de acompanhamento de cada falta.
  - **Administrador** – visualiza e, no menu do perfil (canto superior), também tem **Publicar nova base** e **Gerenciar acessos**. Essas opções não aparecem para instrutores.
- **Visão individual do instrutor:** só as faltas em que o campo `Criada por` é igual ao usuário do instrutor (ex.: `guilherme.bezerra` = `GUILHERME.BEZERRA`, sem diferença de maiúsculas/minúsculas). O filtro é aplicado no banco (RLS), não só na tela. Pódio, rankings, distribuição e comparativo entre instrutores não aparecem nessa visão.
- **Visão do instrutor, feita para o dia a dia:**
  - quadro **"O que fazer agora"** com as faltas pendentes e o botão **Ver pendentes**;
  - situação única por falta (**Pendente → Em andamento → Concluída**) com o progresso das 4 etapas;
  - tabela enxuta com nomes em português, **Detalhes** por falta (empresa, observações, todas as ocorrências) e cartões no celular;
  - botão **✉ E-mail** com mensagem pronta para o jovem, que marca "E-mail enviado" sozinho;
  - filtros de Período, Turma, Módulo e Situação, com atalhos **Pendentes / Esta semana / Este mês**;
  - posição resumida no ranking ("Você está em Xº de N"), com o ranking completo sob demanda;
  - indicadores, ocorrências e gráficos recolhidos em **Análises**; guia **Como usar** no primeiro acesso.
- **Checklist de acompanhamento** (só instrutor): na tabela de detalhamento, cada falta tem os campos E-mail enviado, Resposta recebida, Falta justificada e Ocorrência lançada, salvos automaticamente a cada clique, com data/hora e responsável da última alteração. No topo, indicadores do checklist e das faltas ainda sem acompanhamento.
- **Filtros** por período, instrutor, estado, empresa, turma, módulo, justificativa e ocorrências.
- **Exportação** dos dados filtrados para Excel.
- **Modo de demonstração** com dados de exemplo (botão "Ver com dados de exemplo" na tela de login).
- Tema claro/escuro automático e layout adaptado a celular.

## Estrutura do repositório

| Arquivo | O que é |
|---|---|
| `index.html` | O painel completo (HTML, CSS e JavaScript em um só arquivo). |
| `supabase_setup.sql` | Cria tabelas, regras de segurança (RLS), a função de publicação da base e o administrador inicial. |
| `admin-usuarios.ts` | Edge Function do Supabase que cria, edita, redefine senha, ativa/desativa e exclui usuários. |

## Como configurar

### 1. Banco de dados

1. No Supabase, abra **SQL Editor**.
2. Cole e rode o conteúdo de `supabase_setup.sql`. Ele pode ser rodado de novo sem perder dados.

Isso cria as tabelas `painel_usuarios`, `faltas`, `cargas`, `faltas_identificadores` e `checklist_acompanhamento_faltas`, ativa o RLS, cria a função `salvar_checklist` e define o administrador inicial.

### Criar os acessos dos instrutores

Em **Gerenciar acessos → Criar acessos para todos os instrutores da base**, informe a senha inicial e clique em **Ver instrutores sem acesso**. O painel lista cada `Criada por` que ainda não tem acesso e sugere o próprio valor em minúsculas como usuário (ex.: `GUILHERME.BEZERRA` → `guilherme.bezerra`). Ao confirmar, cria um acesso de instrutor para cada um, já com o nome vinculado.

Na lista de acessos, cada usuário tem **Editar usuário** (muda o login), **Editar nome** e **Editar senha**.

> Depois de atualizar o `admin-usuarios.ts`, publique a Edge Function de novo no Supabase. É ela que permite trocar o usuário.

> **Importante para os instrutores:** o vínculo é feito pelo **usuário** do acesso, comparado com o `Criada por` sem diferença de maiúsculas/minúsculas (ex.: `guilherme.bezerra` = `GUILHERME.BEZERRA`). O campo **Nome** também é aceito, se coincidir com o `Criada por`.

### 2. Edge Function de acessos

1. Em **Edge Functions**, crie uma função chamada **`admin-usuarios`**.
2. Cole o conteúdo de `admin-usuarios.ts` e publique.

A função usa a chave secreta do próprio Supabase no servidor e só atende quem tem papel `admin` e está ativo.

### 3. Primeiro administrador

Em **Authentication → Users**, crie o usuário do administrador inicial definido em `supabase_setup.sql`. Ele vira admin automaticamente. Depois disso, os demais acessos são criados pelo próprio painel em **Gerenciar acessos**.

### 4. Chaves no painel

No início do `<script>` do `index.html`, confira:

```js
const SUPABASE_URL  = 'https://SEU-PROJETO.supabase.co';
const LOGIN_DOMINIO = 'renapsi.org.br';
const SUPABASE_KEY  = 'sb_publishable_...'; // chave PUBLISHABLE (ou anon)
```

> Nunca coloque no `index.html` a senha do banco nem a chave `secret`/`service_role`.

### 5. Publicar o site

O painel está publicado na Vercel em **https://painel-de-faltas-bojador.vercel.app**, que atualiza sozinha a cada commit na branch `main`. Como é um único arquivo estático, também funciona em qualquer hospedagem estática (ex.: GitHub Pages).

## Atualizar a base de faltas

1. Entre com um usuário **administrador**.
2. Clique no seu nome (canto superior direito) → **Publicar nova base**.
3. Escolha o arquivo `.xlsx`, `.xls` ou `.csv` com as colunas:
   `RA, NOME, CODTURMA, MODULO, JUSTIFICADA, Criada por, DATA_FALTA, Criada em, EMAIL JOVEM, EMPRESA, ESTADO, DATAOCORRENCIA, GRUPO_OCORRENCIA, TIPO_OCORRENCIA, ATENDIMENTO_RESPONSAVEL, OBSERVACOES, DATA DESLIGAMENTO, Total Geral`
4. Confira a prévia e clique em **Publicar no Supabase**. A nova base substitui a anterior para todos.

## Instrutores ativos

Em **Instrutores ativos** (menu do administrador), cada instrutor do campo `Criada por` pode ser marcado como **ativo** ou **inativo**. As faltas de instrutores inativos ficam fora de todo o painel — indicadores, gráficos, rankings e tabelas, para administradores e instrutores. O filtro é aplicado no banco (tabela `instrutores_status` + RLS). Nada é apagado: basta reativar.

## Checklist de acompanhamento

- Fica na tabela `checklist_acompanhamento_faltas`, separada de `faltas` (a tabela de faltas não é alterada).
- Cada falta é identificada por um **ID estável**, `RA|CODTURMA|DATA_FALTA|MODULO`, que é a mesma regra de unicidade usada pelo painel. Ele não depende do `id` da tabela `faltas`, que muda a cada nova base. Esse ID é exposto como coluna calculada `id_falta`.
- `faltas_identificadores` guarda permanentemente cada ID já publicado e é o alvo da chave estrangeira do checklist. Por isso **publicar uma nova base não apaga o checklist**.
- A gravação é feita só pela função `salvar_checklist(id_falta, campo, valor)`. Ela confere se a falta pertence ao instrutor logado, cria o registro na primeira interação e depois só atualiza o campo alterado (`id_falta` é único, então não há duplicados). Ela também grava `atualizado_por` e `data_ultima_alteracao`.
- "Sem acompanhamento iniciado" = nenhum dos 4 itens marcado.

## Segurança

- Esconder botões na tela é só conveniência: as permissões são garantidas no servidor.
- A leitura de `faltas` e `cargas` exige um usuário ativo em `painel_usuarios` (RLS). Administradores leem todas as faltas; instrutores, só as próprias (`Criada por` = nome do acesso).
- O checklist só pode ser lido pelo instrutor dono da falta (ou por administradores). Não há insert/update direto: a escrita passa por `salvar_checklist`, que valida o dono no banco.
- A publicação da base (`substituir_faltas`) e a Edge Function `admin-usuarios` recusam qualquer usuário que não seja administrador ativo.
- Usuários desativados são bloqueados no login.

## Tecnologias

- HTML, CSS e JavaScript puro
- [Supabase](https://supabase.com) (Auth, Postgres com RLS, Edge Functions)
- [Chart.js](https://www.chartjs.org/) para os gráficos
- [SheetJS](https://sheetjs.com/) para ler e exportar planilhas
