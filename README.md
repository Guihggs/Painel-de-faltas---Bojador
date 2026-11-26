# Painel de Faltas – Projeto Bojador

Painel web da **demà** para acompanhar as faltas registradas pelos instrutores do Projeto Bojador. Mostra indicadores gerais, pódio de instrutores, ocorrências, análises por estado, empresa, turma e módulo, tabela detalhada e um relatório de qualidade da base.

Os dados ficam no **Supabase** e só usuários autorizados entram no painel.

## Funcionalidades

- **Login por usuário** (ex.: `nome.sobrenome`, que vira `nome.sobrenome@renapsi.org.br`).
- **Dois perfis de acesso:**
  - **Instrutor** – apenas visualiza o painel.
  - **Administrador** – visualiza e, no menu do perfil (canto superior), também tem **Publicar nova base** e **Gerenciar acessos**. Essas opções não aparecem para instrutores.
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

Isso cria as tabelas `painel_usuarios`, `faltas` e `cargas`, ativa o RLS e define o administrador inicial.

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

Como é um único arquivo estático, basta servir o `index.html`. No GitHub: **Settings → Pages → Deploy from a branch → `main` / root**.

## Atualizar a base de faltas

1. Entre com um usuário **administrador**.
2. Clique no seu nome (canto superior direito) → **Publicar nova base**.
3. Escolha o arquivo `.xlsx`, `.xls` ou `.csv` com as colunas:
   `RA, NOME, CODTURMA, MODULO, JUSTIFICADA, Criada por, DATA_FALTA, Criada em, EMAIL JOVEM, EMPRESA, ESTADO, DATAOCORRENCIA, GRUPO_OCORRENCIA, TIPO_OCORRENCIA, ATENDIMENTO_RESPONSAVEL, OBSERVACOES, DATA DESLIGAMENTO, Total Geral`
4. Confira a prévia e clique em **Publicar no Supabase**. A nova base substitui a anterior para todos.

## Segurança

- Esconder botões na tela é só conveniência: as permissões são garantidas no servidor.
- A leitura de `faltas` e `cargas` exige um usuário ativo em `painel_usuarios` (RLS).
- A publicação da base (`substituir_faltas`) e a Edge Function `admin-usuarios` recusam qualquer usuário que não seja administrador ativo.
- Usuários desativados são bloqueados no login.

## Tecnologias

- HTML, CSS e JavaScript puro
- [Supabase](https://supabase.com) (Auth, Postgres com RLS, Edge Functions)
- [Chart.js](https://www.chartjs.org/) para os gráficos
- [SheetJS](https://sheetjs.com/) para ler e exportar planilhas
