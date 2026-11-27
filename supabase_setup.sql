-- =====================================================================
-- Painel de Faltas – Projeto Bojador · estrutura, segurança e acessos
-- Rode uma vez no SQL Editor do Supabase. Pode ser rodado de novo sem perder dados.
-- =====================================================================

-- O que este script cria/garante:
--   • painel_usuarios, faltas, cargas (base original — a tabela "faltas" não tem estrutura alterada);
--   • RLS: administrador lê todas as faltas; instrutor lê só as que têm "Criada por" igual ao próprio
--     USUÁRIO (ex.: guilherme.bezerra = GUILHERME.BEZERRA) ou NOME, sem diferença de maiúsculas/minúsculas;
--   • faltas_identificadores + checklist_acompanhamento_faltas (acompanhamento individual de cada falta,
--     preservado quando uma nova base é publicada) e a função salvar_checklist.
--   • mesclar_faltas: carga INCREMENTAL (merge) usada pelo painel — insere faltas novas, atualiza as
--     existentes (chave RA+CODTURMA+DATA_FALTA+MODULO) e mantém as que não vieram no arquivo.

-- ---------- Tabelas ----------
create table if not exists public.painel_usuarios (
  user_id   uuid primary key references auth.users(id) on delete cascade,
  usuario   text not null unique,
  email     text not null,
  nome      text,
  papel     text not null default 'instrutor' check (papel in ('admin','instrutor')),
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);

create table if not exists public.faltas (
  id bigint generated always as identity primary key,
  ra text, nome text, codturma text, modulo text, justificada text, criada_por text,
  data_falta date, criada_em timestamptz, email_jovem text, empresa text, estado text,
  data_ocorrencia date, grupo_ocorrencia text, tipo_ocorrencia text,
  atendimento_responsavel text, observacoes text, data_desligamento date, total_geral numeric
);

create table if not exists public.cargas (
  id bigint generated always as identity primary key,
  arquivo text, linhas integer, carregado_por text,
  carregado_em timestamptz not null default now()
);

-- Registro permanente dos identificadores de falta (alvo da chave estrangeira do checklist).
-- A tabela "faltas" é substituída a cada nova base; esta não é apagada.
create table if not exists public.faltas_identificadores (
  id_falta            text primary key,          -- RA|CODTURMA|DATA_FALTA|MODULO
  ra text, codturma text, data_falta date, modulo text,
  criada_por          text,                      -- último "Criada por" visto para a falta
  visto_primeiro_em   timestamptz not null default now(),
  visto_por_ultimo_em timestamptz not null default now()
);

-- Instrutores (do campo "Criada por") marcados como INATIVOS pelo administrador.
-- Sem linha aqui = ativo. As faltas de instrutores inativos ficam fora de todo o painel.
create table if not exists public.instrutores_status (
  chave         text primary key,              -- "Criada por" normalizado (public.norm_nome)
  nome          text,                          -- grafia exibida
  ativo         boolean not null default true,
  atualizado_por text,
  atualizado_em timestamptz not null default now()
);

-- Checklist de acompanhamento individual de cada falta (separado da tabela de faltas).
create table if not exists public.checklist_acompanhamento_faltas (
  id_checklist          uuid primary key default gen_random_uuid(),
  id_falta              text not null unique
                        references public.faltas_identificadores(id_falta) on update cascade on delete restrict,
  email_enviado         boolean not null default false,
  resposta_recebida     boolean not null default false,
  falta_justificada     boolean not null default false,
  ocorrencia_lancada    boolean not null default false,
  atualizado_por        text,
  atualizado_por_id     uuid references auth.users(id) on delete set null,
  data_ultima_alteracao timestamptz not null default now()
);

-- ---------- Papel de quem está logado (null = sem acesso) ----------
create or replace function public.meu_papel()
returns text language sql stable security definer set search_path = '' as $$
  select papel from public.painel_usuarios where user_id = auth.uid() and ativo
$$;
revoke execute on function public.meu_papel() from public, anon;
grant  execute on function public.meu_papel() to authenticated;

-- ---------- Vínculo instrutor ↔ campo "Criada por" ----------
-- Regra de comparação: remove espaços no início/fim, reduz espaços repetidos a um só
-- e converte para MAIÚSCULAS. Assim "Guilherme Alves" = "GUILHERME ALVES" = " guilherme  alves ".
-- (sem "set search_path" de propósito: assim o Postgres "inline" a função e a consulta fica rápida;
--  ela só usa funções do pg_catalog, qualificadas explicitamente)
create or replace function public.norm_nome(p text)
returns text language sql immutable parallel safe as $$
  select nullif(pg_catalog.upper(pg_catalog.btrim(pg_catalog.regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))), '')
$$;
grant execute on function public.norm_nome(text) to authenticated;

-- Nome normalizado de quem está logado (campo "nome" de painel_usuarios). null = sem vínculo.
create or replace function public.meu_nome_norm()
returns text language sql stable security definer set search_path = '' as $$
  select public.norm_nome(nome) from public.painel_usuarios where user_id = auth.uid() and ativo
$$;
revoke execute on function public.meu_nome_norm() from public, anon;
grant  execute on function public.meu_nome_norm() to authenticated;

-- Valores que identificam quem está logado no campo "Criada por", já normalizados:
-- o USUÁRIO do acesso (ex.: guilherme.bezerra = GUILHERME.BEZERRA) e, se preenchido, o NOME.
create or replace function public.minhas_chaves()
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_remove(array[public.norm_nome(usuario), public.norm_nome(nome)], null), '{}')
  from public.painel_usuarios where user_id = auth.uid() and ativo
$$;
revoke execute on function public.minhas_chaves() from public, anon;
grant  execute on function public.minhas_chaves() to authenticated;

-- Chaves dos instrutores inativos (lidas uma vez por consulta).
create or replace function public.instrutores_inativos()
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(chave), '{}') from public.instrutores_status where not ativo
$$;
revoke execute on function public.instrutores_inativos() from public, anon;
grant  execute on function public.instrutores_inativos() to authenticated;

-- Identificador estável de cada falta (não depende do "id" da tabela, que muda a cada nova base).
-- Mesma regra de unicidade usada pelo painel: RA + CODTURMA + DATA_FALTA + MODULO.
-- Pode ser lido como coluna calculada: .select('..., id_falta').
create or replace function public.id_falta(f public.faltas)
returns text language sql immutable parallel safe as $$
  select pg_catalog.concat_ws('|', coalesce(pg_catalog.btrim(f.ra), ''), coalesce(pg_catalog.btrim(f.codturma), ''),
                        coalesce(f.data_falta::text, ''), coalesce(pg_catalog.btrim(f.modulo), ''))
$$;
grant execute on function public.id_falta(public.faltas) to authenticated;

-- ---------- Segurança (RLS) ----------
alter table public.painel_usuarios enable row level security;
alter table public.faltas          enable row level security;
alter table public.cargas          enable row level security;

revoke all on public.painel_usuarios, public.faltas, public.cargas from anon, authenticated;
grant select on public.painel_usuarios, public.faltas, public.cargas to authenticated;

-- Administrador: todas as faltas. Instrutor: somente as faltas em que "Criada por" é o próprio usuário (ou nome).
drop policy if exists "ler faltas" on public.faltas;
create policy "ler faltas" on public.faltas for select to authenticated
  using (
    coalesce(public.norm_nome(criada_por), '') <> all ((select public.instrutores_inativos())::text[])  -- só instrutores ativos
    and (
      (select public.meu_papel()) = 'admin'
      or ((select public.meu_papel()) = 'instrutor'
          and public.norm_nome(criada_por) = any ((select public.minhas_chaves())::text[]))
    )
  );

drop policy if exists "ler cargas" on public.cargas;
create policy "ler cargas" on public.cargas for select to authenticated
  using ((select public.meu_papel()) is not null);

drop policy if exists "ver usuarios" on public.painel_usuarios;
create policy "ver usuarios" on public.painel_usuarios for select to authenticated
  using (user_id = (select auth.uid()) or (select public.meu_papel()) = 'admin');
-- Criação/edição de usuários é feita só pela Edge Function "admin-usuarios" (chave secreta no servidor).

-- ---------- Substituição total da base (só admin; o painel usa mesclar_faltas, abaixo) ----------
create or replace function public.substituir_faltas(p_arquivo text, p_linhas jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare n integer; quem text;
begin
  if public.meu_papel() is distinct from 'admin' then
    raise exception 'sem permissão de administrador' using errcode = '42501';
  end if;
  delete from public.faltas where true;
  insert into public.faltas (ra,nome,codturma,modulo,justificada,criada_por,data_falta,criada_em,
    email_jovem,empresa,estado,data_ocorrencia,grupo_ocorrencia,tipo_ocorrencia,
    atendimento_responsavel,observacoes,data_desligamento,total_geral)
  select ra,nome,codturma,modulo,justificada,criada_por,data_falta,criada_em,
    email_jovem,empresa,estado,data_ocorrencia,grupo_ocorrencia,tipo_ocorrencia,
    atendimento_responsavel,observacoes,data_desligamento,total_geral
  from jsonb_populate_recordset(null::public.faltas, p_linhas);
  get diagnostics n = row_count;
  -- registra os identificadores estáveis (nunca são apagados, para preservar o checklist)
  insert into public.faltas_identificadores (id_falta, ra, codturma, data_falta, modulo, criada_por)
  select distinct on (public.id_falta(f)) public.id_falta(f), f.ra, f.codturma, f.data_falta, f.modulo, f.criada_por
  from public.faltas f order by public.id_falta(f), f.id
  on conflict (id_falta) do update set criada_por = excluded.criada_por, visto_por_ultimo_em = now();
  select coalesce(nome, usuario) into quem from public.painel_usuarios where user_id = auth.uid();
  insert into public.cargas (arquivo, linhas, carregado_por) values (p_arquivo, n, quem);
  return n;
end $$;
revoke execute on function public.substituir_faltas(text, jsonb) from public, anon;
grant  execute on function public.substituir_faltas(text, jsonb) to authenticated;

-- ---------- Carga incremental (MERGE) – método usado pelo painel ----------
-- A chave de mesclagem é o identificador estável da falta: RA + CODTURMA + DATA_FALTA + MODULO.
--   • falta que veio no arquivo e ainda não existe na base  → é INSERIDA;
--   • falta que veio no arquivo e já existe na base         → é ATUALIZADA (as linhas dela são trocadas
--     pelas do arquivo, o que também atualiza justificativa e ocorrências);
--   • falta que está na base e não veio no arquivo          → é MANTIDA sem alteração.
-- Nada é apagado fora das faltas presentes no arquivo, e o checklist dos instrutores é sempre preservado.
alter table public.cargas add column if not exists modo               text default 'substituicao';
alter table public.cargas add column if not exists faltas_novas       integer;
alter table public.cargas add column if not exists faltas_atualizadas integer;

create or replace function public.mesclar_faltas(p_arquivo text, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n_linhas integer; n_novas integer; n_atual integer; n_rem integer; quem text;
begin
  if public.meu_papel() is distinct from 'admin' then
    raise exception 'sem permissão de administrador' using errcode = '42501';
  end if;
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) = 0 then
    raise exception 'arquivo sem linhas para carregar' using errcode = '22023';
  end if;

  -- linhas recebidas, já com o identificador estável calculado
  drop table if exists _carga, _ids;
  create temp table _carga on commit drop as
  select r.*, public.id_falta(r) as _id
  from jsonb_populate_recordset(null::public.faltas, p_linhas) r;
  n_linhas := (select count(*) from _carga);

  -- quantas faltas do arquivo são novas e quantas já existiam
  create temp table _ids on commit drop as select distinct _id from _carga;
  select count(*) filter (where e._id is null), count(*) filter (where e._id is not null)
    into n_novas, n_atual
  from _ids i
  left join (select distinct public.id_falta(f) as _id from public.faltas f) e on e._id = i._id;

  -- MERGE: troca as linhas das faltas que vieram no arquivo; as demais ficam intactas
  delete from public.faltas f using _ids i where public.id_falta(f) = i._id;
  get diagnostics n_rem = row_count;
  insert into public.faltas (ra,nome,codturma,modulo,justificada,criada_por,data_falta,criada_em,
    email_jovem,empresa,estado,data_ocorrencia,grupo_ocorrencia,tipo_ocorrencia,
    atendimento_responsavel,observacoes,data_desligamento,total_geral)
  select ra,nome,codturma,modulo,justificada,criada_por,data_falta,criada_em,
    email_jovem,empresa,estado,data_ocorrencia,grupo_ocorrencia,tipo_ocorrencia,
    atendimento_responsavel,observacoes,data_desligamento,total_geral
  from _carga;

  -- registra/atualiza os identificadores estáveis (nunca são apagados, para preservar o checklist)
  insert into public.faltas_identificadores (id_falta, ra, codturma, data_falta, modulo, criada_por)
  select distinct on (c._id) c._id, c.ra, c.codturma, c.data_falta, c.modulo, c.criada_por
  from _carga c order by c._id
  on conflict (id_falta) do update set criada_por = excluded.criada_por, visto_por_ultimo_em = now();

  select coalesce(nome, usuario) into quem from public.painel_usuarios where user_id = auth.uid();
  insert into public.cargas (arquivo, linhas, carregado_por, modo, faltas_novas, faltas_atualizadas)
  values (p_arquivo, n_linhas, quem, 'merge', n_novas, n_atual);

  return jsonb_build_object('linhas', n_linhas, 'faltas_novas', n_novas,
    'faltas_atualizadas', n_atual, 'linhas_substituidas', n_rem,
    'total_base', (select count(*) from public.faltas));
end $$;
revoke execute on function public.mesclar_faltas(text, jsonb) from public, anon;
grant  execute on function public.mesclar_faltas(text, jsonb) to authenticated;

-- ---------- Checklist de acompanhamento (visão do instrutor) ----------
-- Índices de desempenho (não alteram colunas nem dados): busca das faltas de cada instrutor.
create index if not exists faltas_criada_por_norm_idx on public.faltas (public.norm_nome(criada_por));
create index if not exists faltas_identificadores_criada_por_norm_idx on public.faltas_identificadores (public.norm_nome(criada_por));
alter table public.faltas_identificadores          enable row level security;
alter table public.checklist_acompanhamento_faltas enable row level security;

revoke all on public.faltas_identificadores, public.checklist_acompanhamento_faltas from anon, authenticated;
grant select on public.faltas_identificadores, public.checklist_acompanhamento_faltas to authenticated;
-- Sem insert/update/delete direto: toda gravação passa pela função salvar_checklist, que valida o dono.

drop policy if exists "ler identificadores" on public.faltas_identificadores;
create policy "ler identificadores" on public.faltas_identificadores for select to authenticated
  using (
    (select public.meu_papel()) = 'admin'
    or ((select public.meu_papel()) = 'instrutor'
        and public.norm_nome(criada_por) = any ((select public.minhas_chaves())::text[]))
  );

drop policy if exists "ler checklist" on public.checklist_acompanhamento_faltas;
create policy "ler checklist" on public.checklist_acompanhamento_faltas for select to authenticated
  using (
    (select public.meu_papel()) = 'admin'
    or ((select public.meu_papel()) = 'instrutor' and exists (
          select 1 from public.faltas_identificadores i
          where i.id_falta = checklist_acompanhamento_faltas.id_falta
            and public.norm_nome(i.criada_por) = any ((select public.minhas_chaves())::text[])))
  );

-- Salva UM campo do checklist de UMA falta (cria o registro na primeira interação, depois só atualiza).
-- Só o instrutor cujo usuário (ou nome) corresponde ao "Criada por" da falta na base atual pode gravar.
create or replace function public.salvar_checklist(p_id_falta text, p_campo text, p_valor boolean)
returns public.checklist_acompanhamento_faltas
language plpgsql security definer set search_path = '' as $$
declare
  v_chaves text[] := coalesce(public.minhas_chaves(), '{}');
  v_quem text;
  v_f    public.faltas;
  v_row  public.checklist_acompanhamento_faltas;
  v_val  boolean := coalesce(p_valor, false);
begin
  if public.meu_papel() is null then
    raise exception 'sem acesso ao painel' using errcode = '42501';
  end if;
  if cardinality(v_chaves) = 0 then
    raise exception 'seu acesso não está vinculado ao campo "Criada por"' using errcode = '42501';
  end if;
  if p_campo not in ('email_enviado','resposta_recebida','falta_justificada','ocorrencia_lancada') then
    raise exception 'campo inválido: %', p_campo using errcode = '22023';
  end if;

  select * into v_f from public.faltas f
  where public.id_falta(f) = p_id_falta and public.norm_nome(f.criada_por) = any (v_chaves)
  order by f.id limit 1;
  if not found then
    raise exception 'falta não encontrada ou não pertence a você' using errcode = '42501';
  end if;

  insert into public.faltas_identificadores (id_falta, ra, codturma, data_falta, modulo, criada_por)
  values (p_id_falta, v_f.ra, v_f.codturma, v_f.data_falta, v_f.modulo, v_f.criada_por)
  on conflict (id_falta) do update set criada_por = excluded.criada_por;

  select coalesce(nullif(btrim(nome), ''), usuario) into v_quem from public.painel_usuarios where user_id = auth.uid();

  insert into public.checklist_acompanhamento_faltas as c
    (id_falta, email_enviado, resposta_recebida, falta_justificada, ocorrencia_lancada,
     atualizado_por, atualizado_por_id, data_ultima_alteracao)
  values (p_id_falta,
          p_campo = 'email_enviado'      and v_val,
          p_campo = 'resposta_recebida'  and v_val,
          p_campo = 'falta_justificada'  and v_val,
          p_campo = 'ocorrencia_lancada' and v_val,
          v_quem, auth.uid(), now())
  on conflict (id_falta) do update set
    email_enviado      = case when p_campo = 'email_enviado'      then v_val else c.email_enviado      end,
    resposta_recebida  = case when p_campo = 'resposta_recebida'  then v_val else c.resposta_recebida  end,
    falta_justificada  = case when p_campo = 'falta_justificada'  then v_val else c.falta_justificada  end,
    ocorrencia_lancada = case when p_campo = 'ocorrencia_lancada' then v_val else c.ocorrencia_lancada end,
    atualizado_por = excluded.atualizado_por,
    atualizado_por_id = excluded.atualizado_por_id,
    data_ultima_alteracao = now()
  returning * into v_row;
  return v_row;
end $$;
revoke execute on function public.salvar_checklist(text, text, boolean) from public, anon;
grant  execute on function public.salvar_checklist(text, text, boolean) to authenticated;

-- Registra os identificadores das faltas que já estão na base (pode rodar de novo sem duplicar).
insert into public.faltas_identificadores (id_falta, ra, codturma, data_falta, modulo, criada_por)
select distinct on (public.id_falta(f)) public.id_falta(f), f.ra, f.codturma, f.data_falta, f.modulo, f.criada_por
from public.faltas f order by public.id_falta(f), f.id
on conflict (id_falta) do update set criada_por = excluded.criada_por, visto_por_ultimo_em = now();

-- ---------- Ranking de instrutores (pódio também na visão do instrutor) ----------
-- Devolve SÓ totais por instrutor (nenhum registro individual), para qualquer usuário ativo do painel.
-- Mesmas regras do painel: 1 falta = RA + CODTURMA + DATA_FALTA + MODULO (conta uma vez), e uma falta pode ter
-- várias ocorrências (acompanhamentos), cada uma contada; linhas idênticas não contam de novo.
-- Ocorrência = DATAOCORRENCIA, GRUPO_OCORRENCIA ou TIPO_OCORRENCIA preenchidos. Filtro opcional de período.
drop function if exists public.ranking_instrutores(date, date);
create function public.ranking_instrutores(p_de date default null, p_ate date default null)
returns table (instrutor text, chave text, total integer, justificadas integer, nao_justificadas integer,
               nao_informadas integer, turmas integer, jovens integer, ocorrencias integer,
               faltas_com_ocorrencia integer, ocorrencias_atendidas integer, grupo_top text, tipo_top text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.meu_papel() is null then
    raise exception 'sem acesso ao painel' using errcode = '42501';
  end if;
  return query
  with b as (
    select f.id, public.id_falta(f) as idf, pg_catalog.btrim(f.criada_por) as forma, f.ra, f.codturma, f.data_ocorrencia,
      nullif(pg_catalog.btrim(coalesce(f.grupo_ocorrencia, '')), '') as grupo,
      nullif(pg_catalog.btrim(coalesce(f.tipo_ocorrencia, '')), '') as tipo,
      nullif(pg_catalog.btrim(coalesce(f.atendimento_responsavel, '')), '') as atend,
      nullif(pg_catalog.btrim(coalesce(f.observacoes, '')), '') as obs,
      pg_catalog.translate(pg_catalog.lower(pg_catalog.btrim(coalesce(f.justificada, ''))), 'ãáàâéêíóôõúç', 'aaaaeeiooouc') as j
    from public.faltas f
    where nullif(pg_catalog.btrim(coalesce(f.criada_por, '')), '') is not null
      and public.norm_nome(f.criada_por) <> all (public.instrutores_inativos())
      and (p_de is null or f.data_falta >= p_de) and (p_ate is null or f.data_falta <= p_ate)
  ), fl as (            -- uma linha por falta
    select b.idf, (array_agg(b.forma order by b.id))[1] as forma, min(b.ra) as ra, min(b.codturma) as codturma,
      bool_or(b.j ~ '^(sim|s|yes|y|true|1|justificada|justificado)$') as just,
      bool_or(b.j ~ '^(nao|n|no|false|0|nao justificada|nao justificado|injustificada)$') as njust
    from b group by b.idf
  ), fk as (
    select fl.*, public.norm_nome(fl.forma) as k from fl
  ), oc as (            -- cada ocorrência distinta de cada falta
    select distinct b.idf, b.data_ocorrencia, b.grupo, b.tipo, b.atend, b.obs
    from b where b.data_ocorrencia is not null or b.grupo is not null or b.tipo is not null
  ), af as (
    select fk.k, (mode() within group (order by fk.forma))::text as nome, count(*)::integer as tot,
      (count(*) filter (where fk.just))::integer as js,
      (count(*) filter (where not fk.just and fk.njust))::integer as njs,
      (count(*) filter (where not fk.just and not fk.njust))::integer as nis,
      (count(distinct coalesce(fk.codturma, '')))::integer as tu, (count(distinct coalesce(fk.ra, '')))::integer as jo
    from fk group by fk.k
  ), ao as (
    select fk.k, count(*)::integer as n, (count(distinct oc.idf))::integer as nf,
      (count(*) filter (where oc.atend is not null))::integer as na,
      (mode() within group (order by oc.grupo) filter (where oc.grupo is not null))::text as g,
      (mode() within group (order by oc.tipo) filter (where oc.tipo is not null))::text as t
    from oc join fk on fk.idf = oc.idf group by fk.k
  )
  select af.nome, af.k, af.tot, af.js, af.njs, af.nis, af.tu, af.jo,
    coalesce(ao.n, 0), coalesce(ao.nf, 0), coalesce(ao.na, 0), ao.g, ao.t
  from af left join ao on ao.k = af.k;
end $$;
revoke execute on function public.ranking_instrutores(date, date) from public, anon;
grant  execute on function public.ranking_instrutores(date, date) to authenticated;

-- ---------- Instrutores ativos/inativos (só administrador) ----------
alter table public.instrutores_status enable row level security;
revoke all on public.instrutores_status from anon, authenticated;
grant select on public.instrutores_status to authenticated;
drop policy if exists "ler status instrutores" on public.instrutores_status;
create policy "ler status instrutores" on public.instrutores_status for select to authenticated
  using ((select public.meu_papel()) = 'admin');

-- Lista todos os instrutores da base (ativos e inativos) com o total de faltas e se têm acesso ao painel.
create or replace function public.listar_instrutores_base()
returns table (chave text, nome text, faltas integer, ativo boolean, tem_acesso boolean, atualizado_por text, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if public.meu_papel() is distinct from 'admin' then
    raise exception 'sem permissão de administrador' using errcode = '42501';
  end if;
  return query
  with b as (
    select public.norm_nome(f.criada_por) as k, pg_catalog.btrim(f.criada_por) as forma, public.id_falta(f) as idf
    from public.faltas f where nullif(pg_catalog.btrim(coalesce(f.criada_por, '')), '') is not null
  ), g as (
    select b.k, (mode() within group (order by b.forma))::text as nome, (count(distinct b.idf))::integer as n from b group by b.k
  )
  select g.k, g.nome, g.n, coalesce(s.ativo, true),
    exists (select 1 from public.painel_usuarios u where public.norm_nome(u.usuario) = g.k or public.norm_nome(u.nome) = g.k),
    s.atualizado_por, s.atualizado_em
  from g left join public.instrutores_status s on s.chave = g.k
  order by g.nome;
end $$;
revoke execute on function public.listar_instrutores_base() from public, anon;
grant  execute on function public.listar_instrutores_base() to authenticated;

-- Marca um instrutor (chave normalizada do "Criada por") como ativo ou inativo.
create or replace function public.definir_instrutor_ativo(p_chave text, p_ativo boolean, p_nome text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_quem text;
begin
  if public.meu_papel() is distinct from 'admin' then
    raise exception 'sem permissão de administrador' using errcode = '42501';
  end if;
  if public.norm_nome(p_chave) is null then
    raise exception 'instrutor inválido' using errcode = '22023';
  end if;
  select coalesce(nullif(pg_catalog.btrim(nome), ''), usuario) into v_quem from public.painel_usuarios where user_id = auth.uid();
  insert into public.instrutores_status (chave, nome, ativo, atualizado_por, atualizado_em)
  values (public.norm_nome(p_chave), p_nome, coalesce(p_ativo, true), v_quem, now())
  on conflict (chave) do update set ativo = excluded.ativo, nome = coalesce(excluded.nome, public.instrutores_status.nome),
    atualizado_por = excluded.atualizado_por, atualizado_em = now();
end $$;
revoke execute on function public.definir_instrutor_ativo(text, boolean, text) from public, anon;
grant  execute on function public.definir_instrutor_ativo(text, boolean, text) to authenticated;

-- ---------- Administrador inicial ----------
-- Quando o usuário abaixo for criado em Authentication → Users, ele vira admin automaticamente.
create or replace function public.bootstrap_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if lower(new.email) = 'guilherme.silva@renapsi.org.br' then
    insert into public.painel_usuarios (user_id, usuario, email, nome, papel)
    values (new.id, 'guilherme.silva', lower(new.email), 'Guilherme Silva', 'admin')
    on conflict (user_id) do update set papel = 'admin', ativo = true;
  end if;
  return new;
end $$;
revoke execute on function public.bootstrap_admin() from public, anon, authenticated;

drop trigger if exists painel_bootstrap_admin on auth.users;
create trigger painel_bootstrap_admin after insert on auth.users
  for each row execute function public.bootstrap_admin();

-- Se o usuário já existir, promove agora.
insert into public.painel_usuarios (user_id, usuario, email, nome, papel)
select id, 'guilherme.silva', lower(email), 'Guilherme Silva', 'admin'
from auth.users where lower(email) = 'guilherme.silva@renapsi.org.br'
on conflict (user_id) do update set papel = 'admin', ativo = true;
