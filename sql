alter table public.profiles add column if not exists credits int not null default 3;
alter table public.listings add column if not exists verified boolean not null default false;
alter table public.listings add column if not exists photo text;
alter table public.listings add column if not exists plan text not null default 'free';
alter table public.listings add column if not exists plan_until date;

create or replace function public.lock_status() returns trigger language plpgsql security definer set search_path=public as $$ begin if not is_admin() then if tg_op='INSERT' then new.status:='pending'; new.verified:=false; new.plan:='free'; new.plan_until:=null; else new.status:=old.status; new.verified:=old.verified; new.plan:=old.plan; new.plan_until:=old.plan_until; end if; end if; return new; end $$;

drop policy if exists p_adm_upd on public.profiles;
create policy p_adm_upd on public.profiles for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists x_del on public.reports;
create policy x_del on public.reports for delete using (public.is_admin());

insert into storage.buckets(id,name,public) values('photos','photos',true) on conflict do nothing;
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select using (bucket_id='photos');
drop policy if exists photos_ins on storage.objects;
create policy photos_ins on storage.objects for insert to authenticated with check (bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists photos_upd on storage.objects;
create policy photos_upd on storage.objects for update to authenticated using (bucket_id='photos' and (storage.foldername(name))[1]=auth.uid()::text);

create table if not exists public.requests(id uuid primary key default gen_random_uuid(), customer uuid not null references auth.users on delete cascade, material text not null, qty text, place text, city text, details text, status text not null default 'open', created_at timestamptz default now());
create table if not exists public.request_contacts(request uuid primary key references public.requests on delete cascade, name text, phone text);
create table if not exists public.unlocks(id uuid primary key default gen_random_uuid(), request uuid not null references public.requests on delete cascade, supplier uuid not null references auth.users on delete cascade, created_at timestamptz default now(), unique(request, supplier));
create table if not exists public.orders(id uuid primary key default gen_random_uuid(), supplier uuid not null references auth.users on delete cascade, customer_name text, item text, amount numeric not null, fee_pct numeric not null default 0, fee numeric not null default 0, fee_paid boolean not null default false, created_at timestamptz default now());
create table if not exists public.payments(id uuid primary key default gen_random_uuid(), supplier uuid references auth.users on delete set null, supplier_name text, kind text, amount numeric not null default 0, credits int default 0, created_at timestamptz default now());
create table if not exists public.settings(key text primary key, value text);
insert into public.settings values('fee_pct','0'),('admin_wa',''),('upi',''),('p10','299'),('p30','799'),('silver','299'),('gold','599') on conflict do nothing;
create table if not exists public.messages(id uuid primary key default gen_random_uuid(), enquiry uuid not null references public.enquiries on delete cascade, sender uuid not null references auth.users on delete cascade, body text not null, created_at timestamptz default now());

create or replace function public.is_supplier() returns boolean language sql security definer set search_path=public stable as $$ select exists(select 1 from profiles where id=auth.uid() and role='supplier') $$;
create or replace function public.can_chat(eid uuid) returns boolean language sql security definer set search_path=public stable as $$ select public.is_admin() or exists(select 1 from enquiries e join listings l on l.id=e.listing where e.id=eid and (e.customer=auth.uid() or l.owner=auth.uid())) $$;
create or replace function public.has_unlock(rid uuid) returns boolean language sql security definer set search_path=public stable as $$ select exists(select 1 from unlocks where request=rid and supplier=auth.uid()) $$;
create or replace function public.unlock_request(rid uuid) returns json language plpgsql security definer set search_path=public as $$ declare c int; begin if not public.is_supplier() then return json_build_object('ok',false,'msg','not_supplier'); end if; if not exists(select 1 from requests where id=rid and status='open') then return json_build_object('ok',false,'msg','closed'); end if; if exists(select 1 from unlocks where request=rid and supplier=auth.uid()) then return json_build_object('ok',true); end if; select credits into c from profiles where id=auth.uid() for update; if coalesce(c,0)<1 then return json_build_object('ok',false,'msg','credits'); end if; update profiles set credits=credits-1 where id=auth.uid(); insert into unlocks(request,supplier) values(rid,auth.uid()); return json_build_object('ok',true); end $$;
create or replace function public.order_fee() returns trigger language plpgsql security definer set search_path=public as $$ declare p numeric; begin select coalesce(nullif(value,'')::numeric,0) into p from settings where key='fee_pct'; new.fee_pct:=coalesce(p,0); new.fee:=round(new.amount*coalesce(p,0)/100,2); new.fee_paid:=false; return new; end $$;
drop trigger if exists order_fee on public.orders;
create trigger order_fee before insert on public.orders for each row execute function public.order_fee();

alter table public.requests enable row level security;
alter table public.request_contacts enable row level security;
alter table public.unlocks enable row level security;
alter table public.orders enable row level security;
alter table public.payments enable row level security;
alter table public.settings enable row level security;
alter table public.messages enable row level security;

drop policy if exists q_ins on public.requests;
create policy q_ins on public.requests for insert with check (customer=auth.uid());
drop policy if exists q_sel on public.requests;
create policy q_sel on public.requests for select using (customer=auth.uid() or public.is_supplier() or public.is_admin());
drop policy if exists q_upd on public.requests;
create policy q_upd on public.requests for update using (customer=auth.uid() or public.is_admin()) with check (customer=auth.uid() or public.is_admin());
drop policy if exists rc_ins on public.request_contacts;
create policy rc_ins on public.request_contacts for insert with check (exists(select 1 from public.requests r where r.id=request_contacts.request and r.customer=auth.uid()));
drop policy if exists rc_sel on public.request_contacts;
create policy rc_sel on public.request_contacts for select using (public.is_admin() or public.has_unlock(request_contacts.request) or exists(select 1 from public.requests r where r.id=request_contacts.request and r.customer=auth.uid()));
drop policy if exists u_sel on public.unlocks;
create policy u_sel on public.unlocks for select using (supplier=auth.uid() or public.is_admin() or exists(select 1 from public.requests r where r.id=unlocks.request and r.customer=auth.uid()));
drop policy if exists o_ins on public.orders;
create policy o_ins on public.orders for insert with check (supplier=auth.uid() and public.is_supplier());
drop policy if exists o_sel on public.orders;
create policy o_sel on public.orders for select using (supplier=auth.uid() or public.is_admin());
drop policy if exists o_upd on public.orders;
create policy o_upd on public.orders for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists pay_adm on public.payments;
create policy pay_adm on public.payments for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists pay_own on public.payments;
create policy pay_own on public.payments for select using (supplier=auth.uid());
drop policy if exists s_sel on public.settings;
create policy s_sel on public.settings for select using (true);
drop policy if exists s_ins on public.settings;
create policy s_ins on public.settings for insert with check (public.is_admin());
drop policy if exists s_upd on public.settings;
create policy s_upd on public.settings for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists m_ins on public.messages;
create policy m_ins on public.messages for insert with check (sender=auth.uid() and public.can_chat(enquiry));
drop policy if exists m_sel on public.messages;
create policy m_sel on public.messages for select using (public.can_chat(enquiry));
