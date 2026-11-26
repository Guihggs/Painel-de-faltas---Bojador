-- =====================================================================
-- Painel de Faltas – Projeto Bojador · estrutura, segurança e acessos
-- Rode uma vez no SQL Editor do Supabase. Pode ser rodado de novo sem perder dados.
-- =====================================================================

-- O que este script cria/garante:
--   • painel_usuarios, faltas, cargas (base original — a tabela "faltas" não tem estrutura alterada);
--   • RLS: administrador lê todas as faltas; instrutor lê só as que têm "Criada por" igual ao próprio nome
--     (comparação sem diferença de maiúsculas/minúsculas e sem espaços excedentes);
--   • faltas_identificadores + checklist_acompanhamento_faltas (acompanhamento individual de cada falta,
--     preservado quando uma nova base é publicada) e a função salvar_checklist.

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
create or replace function public.norm_nome(p text)
returns text language sql immutable parallel safe set search_path = '' as $$
  select nullif(upper(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))), '')
$$;
grant execute on function public.norm_nome(text) to authenticated;

-- Nome normalizado de quem está logado (campo "nome" de painel_usuarios). null = sem vínculo.
create or replace function public.meu_nome_norm()
returns text language sql stable security definer set search_path = '' as $$
  select public.norm_nome(nome) from public.painel_usuarios where user_id = auth.uid() and ativo
$$;
revoke execute on function public.meu_nome_norm() from public, anon;
grant  execute on function public.meu_nome_norm() to authenticated;

-- Identificador estável de cada falta (não depende do "id" da tabela, que muda a cada nova base).
-- Mesma regra de unicidade usada pelo painel: RA + CODTURMA + DATA_FALTA + MODULO.
-- Pode ser lido como coluna calculada: .select('..., id_falta').
create or replace function public.id_falta(f public.faltas)
returns text language sql immutable parallel safe set search_path = '' as $$
  select concat_ws('|', coalesce(btrim(f.ra), ''), coalesce(btrim(f.codturma), ''),
                        coalesce(f.data_falta::text, ''), coalesce(btrim(f.modulo), ''))
$$;
grant execute on function public.id_falta(public.faltas) to authenticated;

-- ---------- Segurança (RLS) ----------
alter table public.painel_usuarios enable row level security;
alter table public.faltas          enable row level security;
alter table public.cargas          enable row level security;

revoke all on public.painel_usuarios, public.faltas, public.cargas from anon, authenticated;
grant select on public.painel_usuarios, public.faltas, public.cargas to authenticated;

-- Administrador: todas as faltas. Instrutor: somente as faltas em que "Criada por" é o próprio nome.
drop policy if exists "ler faltas" on public.faltas;
create policy "ler faltas" on public.faltas for select to authenticated
  using (
    (select public.meu_papel()) = 'admin'
    or ((select public.meu_papel()) = 'instrutor'
        and public.norm_nome(criada_por) = (select public.meu_nome_norm()))
  );

drop policy if exists "ler cargas" on public.cargas;
create policy "ler cargas" on public.cargas for select to authenticated
  using ((select public.meu_papel()) is not null);

drop policy if exists "ver usuarios" on public.painel_usuarios;
create policy "ver usuarios" on public.painel_usuarios for select to authenticated
  using (user_id = (select auth.uid()) or (select public.meu_papel()) = 'admin');
-- Criação/edição de usuários é feita só pela Edge Function "admin-usuarios" (chave secreta no servidor).

-- ---------- Publicar nova base (só admin) ----------
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

-- ---------- Checklist de acompanhamento (visão do instrutor) ----------
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
        and public.norm_nome(criada_por) = (select public.meu_nome_norm()))
  );

drop policy if exists "ler checklist" on public.checklist_acompanhamento_faltas;
create policy "ler checklist" on public.checklist_acompanhamento_faltas for select to authenticated
  using (
    (select public.meu_papel()) = 'admin'
    or ((select public.meu_papel()) = 'instrutor' and exists (
          select 1 from public.faltas_identificadores i
          where i.id_falta = checklist_acompanhamento_faltas.id_falta
            and public.norm_nome(i.criada_por) = (select public.meu_nome_norm())))
  );

-- Salva UM campo do checklist de UMA falta (cria o registro na primeira interação, depois só atualiza).
-- Só o instrutor cujo nome corresponde ao "Criada por" da falta na base atual pode gravar.
create or replace function public.salvar_checklist(p_id_falta text, p_campo text, p_valor boolean)
returns public.checklist_acompanhamento_faltas
language plpgsql security definer set search_path = '' as $$
declare
  v_nome text := public.meu_nome_norm();
  v_quem text;
  v_f    public.faltas;
  v_row  public.checklist_acompanhamento_faltas;
  v_val  boolean := coalesce(p_valor, false);
begin
  if public.meu_papel() is null then
    raise exception 'sem acesso ao painel' using errcode = '42501';
  end if;
  if v_nome is null then
    raise exception 'seu acesso não tem nome vinculado ao campo "Criada por"' using errcode = '42501';
  end if;
  if p_campo not in ('email_enviado','resposta_recebida','falta_justificada','ocorrencia_lancada') then
    raise exception 'campo inválido: %', p_campo using errcode = '22023';
  end if;

  select * into v_f from public.faltas f
  where public.id_falta(f) = p_id_falta and public.norm_nome(f.criada_por) = v_nome
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
