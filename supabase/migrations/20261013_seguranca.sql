-- Rolê: migração de segurança (PENDENTE de aplicar no Supabase wyirmfuinpaaeodpbwcz)
-- Conteúdo: limite de tentativas, limites de tamanho/formato, bloqueio de usuários, denúncias, exclusão de conta.

-- 1) limite de tentativas por usuário (protege contra força bruta de códigos e abuso)
create table if not exists private.taxa_uso (
  id bigserial primary key, user_id uuid not null, acao text not null, em timestamptz not null default now());
create index if not exists taxa_uso_idx on private.taxa_uso (user_id, acao, em);
alter table private.taxa_uso enable row level security;

create or replace function private.limitar(p_acao text, p_max integer, p_janela interval)
returns void language plpgsql security definer set search_path = '' as $$
declare v uuid := (select auth.uid()); n integer;
begin
  if v is null then return; end if;
  select count(*) into n from private.taxa_uso where user_id = v and acao = p_acao and em > now() - p_janela;
  if n >= p_max then raise exception 'muitas tentativas'; end if;
  insert into private.taxa_uso (user_id, acao) values (v, p_acao);
end $$;

-- 2) limites de tamanho e formato (o banco não confia só no cliente)
alter table public.perfis add constraint perfis_nome_tam check (char_length(nome) between 1 and 60) not valid;
alter table public.avaliacoes add constraint avaliacoes_comentario_tam check (char_length(comentario) <= 1000) not valid;
alter table public.avaliacoes add constraint avaliacoes_pedidos_tam check (char_length(pedidos) <= 200) not valid;
alter table public.lugares add constraint lugares_maps_url_ok check (maps_url is null or (char_length(maps_url) <= 500 and maps_url ~* '^https?://')) not valid;
alter table public.lugares add constraint lugares_atributos_tam check (cardinality(atributos) <= 30) not valid;
alter table public.locais add constraint locais_cidade_tam check (char_length(cidade) <= 120) not valid;
alter table public.locais add constraint locais_bairro_tam check (char_length(bairro) <= 120) not valid;
alter table public.locais add constraint locais_categoria_tam check (char_length(categoria) <= 120) not valid;
alter table public.perfis validate constraint perfis_nome_tam;
alter table public.avaliacoes validate constraint avaliacoes_comentario_tam;
alter table public.avaliacoes validate constraint avaliacoes_pedidos_tam;
alter table public.lugares validate constraint lugares_maps_url_ok;
alter table public.lugares validate constraint lugares_atributos_tam;
alter table public.locais validate constraint locais_cidade_tam;
alter table public.locais validate constraint locais_bairro_tam;
alter table public.locais validate constraint locais_categoria_tam;

-- 3) exclusão de conta: o que é conteúdo compartilhado não trava a exclusão
alter table public.visitas alter column criado_por drop not null;
alter table public.lugares alter column criado_por drop not null;
alter table public.locais alter column criado_por drop not null;
alter table public.visitas drop constraint visitas_criado_por_fkey, add constraint visitas_criado_por_fkey foreign key (criado_por) references auth.users(id) on delete set null;
alter table public.lugares drop constraint lugares_criado_por_fkey, add constraint lugares_criado_por_fkey foreign key (criado_por) references auth.users(id) on delete set null;
alter table public.locais drop constraint locais_criado_por_fkey, add constraint locais_criado_por_fkey foreign key (criado_por) references auth.users(id) on delete set null;
alter table public.fotos drop constraint fotos_criado_por_fkey, add constraint fotos_criado_por_fkey foreign key (criado_por) references auth.users(id) on delete cascade;

-- 4) bloqueios e denúncias
create table public.bloqueios (
  bloqueador uuid not null references auth.users(id) on delete cascade,
  bloqueado uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (bloqueador, bloqueado), check (bloqueador <> bloqueado));
alter table public.bloqueios enable row level security;
create policy bloqueios_proprios on public.bloqueios for select to authenticated using (bloqueador = (select auth.uid()));
revoke all on public.bloqueios from anon, authenticated; grant select on public.bloqueios to authenticated;

create table public.denuncias (
  id uuid primary key default gen_random_uuid(),
  denunciante uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('perfil','catalogo','lugar','foto','outro')),
  alvo_id uuid,
  motivo text not null check (motivo in ('spam','assedio','conteudo_improprio','falso','outro')),
  detalhe text check (char_length(detalhe) <= 500),
  status text not null default 'nova' check (status in ('nova','analisada','descartada')),
  created_at timestamptz not null default now());
alter table public.denuncias enable row level security;
create policy denuncias_admin_ler on public.denuncias for select to authenticated using (private.is_admin_global());
revoke all on public.denuncias from anon, authenticated; grant select on public.denuncias to authenticated;

create or replace function private.bloqueado(p_a uuid, p_b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.bloqueios where (bloqueador = p_a and bloqueado = p_b) or (bloqueador = p_b and bloqueado = p_a)); $$;

create or replace function public.bloquear_usuario(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v uuid := (select auth.uid());
begin
  if v is null then raise exception 'nao autenticado'; end if;
  if p_user is null or p_user = v then raise exception 'usuario invalido'; end if;
  perform private.limitar('bloquear', 60, interval '1 hour');
  insert into public.bloqueios (bloqueador, bloqueado) values (v, p_user) on conflict do nothing;
  delete from public.amizades
   where least(solicitante, destinatario) = least(v, p_user) and greatest(solicitante, destinatario) = greatest(v, p_user);
end $$;

create or replace function public.desbloquear_usuario(p_user uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.bloqueios where bloqueador = (select auth.uid()) and bloqueado = p_user; $$;

create or replace function public.listar_bloqueios() returns table(user_id uuid, nome text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.nome from public.bloqueios b join public.perfis p on p.id = b.bloqueado
  where b.bloqueador = (select auth.uid()) order by p.nome; $$;

create or replace function public.denunciar(p_tipo text, p_alvo uuid, p_motivo text, p_detalhe text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare v uuid := (select auth.uid()); a uuid;
begin
  if v is null then raise exception 'nao autenticado'; end if;
  perform private.limitar('denuncia', 10, interval '1 day');
  insert into public.denuncias (denunciante, tipo, alvo_id, motivo, detalhe)
  values (v, p_tipo, p_alvo, p_motivo, nullif(left(trim(coalesce(p_detalhe, '')), 500), ''));
  for a in select user_id from public.admins loop
    perform private.notificar(a, 'denuncia', 'Nova denúncia', 'Há uma denúncia para analisar.', '#/denuncias', '{}');
  end loop;
end $$;

create or replace function public.listar_denuncias() returns table(id uuid, tipo text, alvo_id uuid, alvo_nome text, motivo text, detalhe text, status text, denunciante_nome text, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_admin_global() then raise exception 'sem permissao'; end if;
  return query select d.id, d.tipo, d.alvo_id,
      case d.tipo when 'perfil' then (select p.nome from public.perfis p where p.id = d.alvo_id)
                  when 'catalogo' then (select g.nome from public.grupos g where g.id = d.alvo_id) end,
      d.motivo, d.detalhe, d.status, (select p.nome from public.perfis p where p.id = d.denunciante), d.created_at
    from public.denuncias d order by (d.status = 'nova') desc, d.created_at desc limit 100;
end $$;

create or replace function public.resolver_denuncia(p_id uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin_global() then raise exception 'sem permissao'; end if;
  if p_status not in ('analisada','descartada') then raise exception 'status invalido'; end if;
  update public.denuncias set status = p_status where id = p_id;
end $$;

-- 5) excluir a própria conta (as fotos no Storage são removidas pelo app antes de chamar)
create or replace function public.excluir_minha_conta() returns void
language plpgsql security definer set search_path = '' as $$
declare v uuid := (select auth.uid()); g record; novo uuid;
begin
  if v is null then raise exception 'nao autenticado'; end if;
  perform private.limitar('excluir_conta', 5, interval '1 day');
  delete from public.grupos where criado_por = v and tipo = 'pessoal';
  for g in select id from public.grupos where criado_por = v loop
    select user_id into novo from public.grupo_membros where grupo_id = g.id and user_id <> v order by (papel = 'admin') desc, created_at limit 1;
    if novo is null then
      delete from public.grupos where id = g.id;
    else
      update public.grupos set criado_por = novo where id = g.id;
      update public.grupo_membros set papel = 'admin' where grupo_id = g.id and user_id = novo;
    end if;
  end loop;
  delete from auth.users where id = v;
end $$;

-- 6) funções existentes com limite de tentativas e bloqueio
--    (tentativa errada devolve valor em vez de erro, para a contagem persistir na transação)
create or replace function public.adicionar_amigo(p_codigo text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_outro uuid; a public.amizades;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  perform private.limitar('adicionar_amigo', 20, interval '1 hour');
  select id into v_outro from public.perfis where codigo_amigo = upper(trim(p_codigo));
  if v_outro is null or private.bloqueado(v_uid, v_outro) then return 'invalido'; end if;
  if v_outro = v_uid then raise exception 'codigo proprio'; end if;
  select * into a from public.amizades
    where least(solicitante, destinatario) = least(v_uid, v_outro) and greatest(solicitante, destinatario) = greatest(v_uid, v_outro);
  if a.id is not null then
    if a.status = 'aceita' then return 'aceita'; end if;
    if a.solicitante = v_uid then return 'pendente'; end if;
    update public.amizades set status = 'aceita' where id = a.id;
    return 'aceita';
  end if;
  insert into public.amizades (solicitante, destinatario) values (v_uid, v_outro);
  return 'pendente';
end $$;

create or replace function public.entrar_grupo(p_codigo text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'nao autenticado'; end if;
  perform private.limitar('entrar_grupo', 20, interval '1 hour');
  select id into v_id from public.grupos where codigo_convite = upper(trim(p_codigo)) and tipo <> 'pessoal';
  if v_id is null then return null; end if;
  insert into public.grupo_membros (grupo_id, user_id) values (v_id, (select auth.uid())) on conflict do nothing;
  return v_id;
end $$;

create or replace function public.criar_grupo(p_nome text, p_tipo text default 'amigos', p_amigos uuid[] default '{}') returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_id uuid; v_codigo text; v_amigo uuid;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  if p_tipo not in ('casal','amigos') then raise exception 'tipo invalido'; end if;
  perform private.limitar('criar_grupo', 10, interval '1 hour');
  loop
    v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from public.grupos where codigo_convite = v_codigo);
  end loop;
  insert into public.grupos (nome, tipo, codigo_convite, criado_por) values (p_nome, p_tipo, v_codigo, v_uid) returning id into v_id;
  insert into public.grupo_membros (grupo_id, user_id, papel) values (v_id, v_uid, 'admin');
  foreach v_amigo in array coalesce(p_amigos, '{}') loop
    if private.is_amigo(v_amigo) then
      insert into public.grupo_membros (grupo_id, user_id) values (v_id, v_amigo) on conflict do nothing;
    end if;
  end loop;
  return v_id;
end $$;

create or replace function public.alternar_curtida(p_grupo uuid, p_tipo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid()); v_ativo boolean;
begin
  if v_uid is null then raise exception 'nao autenticado'; end if;
  if p_tipo not in ('coracao','like') then raise exception 'tipo invalido'; end if;
  perform private.limitar('curtida', 120, interval '1 hour');
  if not exists (select 1 from public.grupos where id = p_grupo and publico) then raise exception 'catalogo nao publico'; end if;
  if private.is_membro(p_grupo) then raise exception 'proprio catalogo'; end if;
  if exists (select 1 from public.curtidas where grupo_id = p_grupo and user_id = v_uid and tipo = p_tipo) then
    delete from public.curtidas where grupo_id = p_grupo and user_id = v_uid and tipo = p_tipo; v_ativo := false;
  else
    insert into public.curtidas (grupo_id, user_id, tipo) values (p_grupo, v_uid, p_tipo); v_ativo := true;
  end if;
  return jsonb_build_object('ativo', v_ativo,
    'coracoes', (select count(*) from public.curtidas where grupo_id = p_grupo and tipo = 'coracao'),
    'likes', (select count(*) from public.curtidas where grupo_id = p_grupo and tipo = 'like'));
end $$;

-- perfil público: não mostra quem bloqueou você nem quem você bloqueou
do $$
declare d text;
begin
  d := pg_get_functiondef('public.perfil_publico'::regproc);
  d := replace(d, 'if pf.id is null then return null; end if;', 'if pf.id is null or (p_id <> v_uid and private.bloqueado(v_uid, p_id)) then return null; end if;');
  execute d;
end $$;

-- lista de amigos sem bloqueados
create or replace function public.listar_amigos() returns table(id uuid, user_id uuid, nome text, status text, direcao text)
language sql stable security definer set search_path = '' as $$
  select a.id, o.id, o.nome, a.status,
         case when a.status = 'aceita' then 'amigo' when a.solicitante = (select auth.uid()) then 'enviada' else 'recebida' end
  from public.amizades a
  join public.perfis o on o.id = case when a.solicitante = (select auth.uid()) then a.destinatario else a.solicitante end
  where (select auth.uid()) in (a.solicitante, a.destinatario) and not private.bloqueado((select auth.uid()), o.id)
  order by o.nome; $$;

-- permissões: só usuários logados chamam as funções novas/alteradas
revoke execute on function public.bloquear_usuario(uuid), public.desbloquear_usuario(uuid), public.listar_bloqueios(),
  public.denunciar(text, uuid, text, text), public.listar_denuncias(), public.resolver_denuncia(uuid, text), public.excluir_minha_conta(),
  public.adicionar_amigo(text), public.entrar_grupo(text), public.criar_grupo(text, text, uuid[]), public.alternar_curtida(uuid, text),
  public.listar_amigos(), public.perfil_publico(uuid) from public, anon;
grant execute on function public.bloquear_usuario(uuid), public.desbloquear_usuario(uuid), public.listar_bloqueios(),
  public.denunciar(text, uuid, text, text), public.listar_denuncias(), public.resolver_denuncia(uuid, text), public.excluir_minha_conta(),
  public.adicionar_amigo(text), public.entrar_grupo(text), public.criar_grupo(text, text, uuid[]), public.alternar_curtida(uuid, text),
  public.listar_amigos(), public.perfil_publico(uuid) to authenticated;
revoke all on table private.taxa_uso from public, anon, authenticated;
revoke usage on sequence private.taxa_uso_id_seq from public, anon, authenticated;

-- limpeza diária da tabela de tentativas
select cron.schedule('limpa-taxa-uso', '30 6 * * *', $c$delete from private.taxa_uso where em < now() - interval '2 days'$c$);
