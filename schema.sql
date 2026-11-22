-- =====================================================================
-- GALERI REKAMAN SUARA - Supabase Schema
-- Jalankan seluruh isi file ini di Supabase Dashboard > SQL Editor.
-- Aman dijalankan ulang (idempotent) kecuali bagian yang ditandai.
-- =====================================================================

-- 1) EXTENSIONS ------------------------------------------------------
create extension if not exists "pgcrypto";

-- 2) TABEL RECORDINGS ------------------------------------------------
-- Setiap baris = satu rekaman suara milik admin.
create table if not exists public.recordings (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  recorded_at   date,
  category      text,
  audio_path    text not null,          -- path di bucket 'audio'
  cover_path    text,                   -- path di bucket 'covers'
  filename      text,                   -- nama file asli saat upload
  mime          text,                   -- tipe MIME hasil (audio/mp4, audio/mpeg, ...)
  duration      numeric,                -- durasi (detik), diisi trigger/handler
  downloadable  boolean not null default true,
  order_idx     integer not null default 0,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists recordings_order_idx on public.recordings(order_idx);
create index if not exists recordings_category on public.recordings(category);
create index if not exists recordings_recorded_at on public.recordings(recorded_at);

-- 3) UPDATED_AT TRIGGER ---------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_recordings_updated on public.recordings;
create trigger trg_recordings_updated
  before update on public.recordings
  for each row execute function public.set_updated_at();

-- 4) HELPER: apakah user saat ini admin? -----------------------------
-- Mengecek klaim app_metadata.role === 'admin' pada JWT user.
create or replace function public.is_admin()
returns boolean language sql security definer stable as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin',
    (auth.jwt() -> 'user_metadata'  ->> 'role') = 'admin',
    false
  );
$$;

-- 5) ROW LEVEL SECURITY ----------------------------------------------
-- Default: blok semua. Lalu buka kebijakan berikut.
alter table public.recordings enable row level security;

-- 5a) SELECT publik untuk semua baris (pengunjung bisa membaca metadata)
drop policy if exists "recordings_select_public" on public.recordings;
create policy "recordings_select_public"
  on public.recordings for select
  using (true);

-- 5b) INSERT hanya admin
drop policy if exists "recordings_insert_admin" on public.recordings;
create policy "recordings_insert_admin"
  on public.recordings for insert
  with check (public.is_admin());

-- 5c) UPDATE hanya admin
drop policy if exists "recordings_update_admin" on public.recordings;
create policy "recordings_update_admin"
  on public.recordings for update
  using (public.is_admin())
  with check (public.is_admin());

-- 5d) DELETE hanya admin
drop policy if exists "recordings_delete_admin" on public.recordings;
create policy "recordings_delete_admin"
  on public.recordings for delete
  using (public.is_admin());

-- 6) STORAGE BUCKETS ------------------------------------------------
-- Bucket 'audio' untuk file audio, 'covers' untuk gambar sampul.
insert into storage.buckets (id, name, public)
values ('audio', 'audio', true)
on conflict (id) do update set public = true;

insert into storage.buckets (id, name, public)
values ('covers', 'covers', true)
on conflict (id) do update set public = true;

-- 7) STORAGE POLICIES ------------------------------------------------
-- Audio: publik bisa BACA (streaming). Hanya admin bisa TULIS/HAPUS.
drop policy if exists "audio_read_public" on storage.objects;
create policy "audio_read_public"
  on storage.objects for select
  using (bucket_id = 'audio');

drop policy if exists "audio_insert_admin" on storage.objects;
create policy "audio_insert_admin"
  on storage.objects for insert
  with check (bucket_id = 'audio' and public.is_admin());

drop policy if exists "audio_update_admin" on storage.objects;
create policy "audio_update_admin"
  on storage.objects for update
  using (bucket_id = 'audio' and public.is_admin())
  with check (bucket_id = 'audio' and public.is_admin());

drop policy if exists "audio_delete_admin" on storage.objects;
create policy "audio_delete_admin"
  on storage.objects for delete
  using (bucket_id = 'audio' and public.is_admin());

-- Covers: publik bisa BACA. Hanya admin bisa TULIS/HAPUS.
drop policy if exists "covers_read_public" on storage.objects;
create policy "covers_read_public"
  on storage.objects for select
  using (bucket_id = 'covers');

drop policy if exists "covers_insert_admin" on storage.objects;
create policy "covers_insert_admin"
  on storage.objects for insert
  with check (bucket_id = 'covers' and public.is_admin());

drop policy if exists "covers_update_admin" on storage.objects;
create policy "covers_update_admin"
  on storage.objects for update
  using (bucket_id = 'covers' and public.is_admin())
  with check (bucket_id = 'covers' and public.is_admin());

drop policy if exists "covers_delete_admin" on storage.objects;
create policy "covers_delete_admin"
  on storage.objects for delete
  using (bucket_id = 'covers' and public.is_admin());

-- 8) MEMBUAT ADMIN PERTAMA -------------------------------------------
-- Cara yang disarankan (lihat README untuk langkah lengkap):
--
--   a) Daftarkan user via Supabase Dashboard > Authentication > Users > Add user
--      (email + password), atau lewat SQL:
--         insert into auth.users (...) -- tidak disarankan manual.
--   b) Tandai sebagai admin dengan mengisi app_metadata.role = 'admin':
--
--         update auth.users
--         set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb)
--           || '{"role":"admin"}'::jsonb
--         where email = 'admin@contoh.com';
--
--   c) Verifikasi:
--         select email, raw_app_meta_data from auth.users where email='admin@contoh.com';
--
-- Setelah langkah (b), user tersebut bisa login di /admin/login dan
-- melakukan upload/edit/hapus. Pengunjung lain tetap hanya bisa membaca.

-- (Opsional) Trigger: set role admin otomatis untuk whitelist email.
-- Hapus komentar baris berikut dan sesuaikan daftar email jika ingin
-- otomatis menandai admin saat pendaftaran baru:
--
-- create or replace function public.set_admin_on_signup()
-- returns trigger language plpgsql security definer as $$
-- begin
--   if new.email in ('admin@contoh.com') then
--     new.raw_app_meta_data = coalesce(new.raw_app_meta_data,'{}'::jsonb)
--       || '{"role":"admin"}'::jsonb;
--   end if;
--   return new;
-- end;
-- $$;
-- drop trigger if exists trg_admin_signup on auth.users;
-- create trigger trg_admin_signup
--   before insert on auth.users
--   for each row execute function public.set_admin_on_signup();

-- =====================================================================
-- SELESAI. Pastikan tidak ada error di SQL Editor, lalu salin
-- SUPABASE_URL dan anon key ke index.html (variabel SUPABASE_URL /
-- SUPABASE_ANON_KEY, atau lewat window.__SUPABASE_URL__).
-- =====================================================================
