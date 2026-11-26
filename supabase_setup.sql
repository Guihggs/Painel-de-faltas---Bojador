-- =====================================================================
-- Painel de Faltas – Projeto Bojador · estrutura, segurança e acessos
-- Rode uma vez no SQL Editor do Supabase. Pode ser rodado de novo sem perder dados.
-- =====================================================================

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

-- ---------- Papel de quem está logado (null = sem acesso) ----------
create or replace function public.meu_papel()
returns text language sql stable security definer set search_path = '' as $$
  select papel from public.painel_usuarios where user_id = auth.uid() and ativo
$$;
revoke execute on function public.meu_papel() from public, anon;
grant  execute on function public.meu_papel() to authenticated;

-- ---------- Segurança (RLS) ----------
alter table public.painel_usuarios enable row level security;
alter table public.faltas          enable row level security;
alter table public.cargas          enable row level security;

revoke all on public.painel_usuarios, public.faltas, public.cargas from anon, authenticated;
grant select on public.painel_usuarios, public.faltas, public.cargas to authenticated;

drop policy if exists "ler faltas" on public.faltas;
create policy "ler faltas" on public.faltas for select to authenticated
  using ((select public.meu_papel()) is not null);

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
  select coalesce(nome, usuario) into quem from public.painel_usuarios where user_id = auth.uid();
  insert into public.cargas (arquivo, linhas, carregado_por) values (p_arquivo, n, quem);
  return n;
end $$;
revoke execute on function public.substituir_faltas(text, jsonb) from public, anon;
grant  execute on function public.substituir_faltas(text, jsonb) to authenticated;

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
