-- =====================================================================
-- GALERI REKAMAN SUARA - Supabase Schema (v2)
-- Jalankan seluruh isi file ini di Supabase Dashboard > SQL Editor.
-- Aman dijalankan ulang (idempotent).
--
-- Perubahan utama dari v1:
--   * Storage bucket tunggal bernama "recordings" (audio + cover di sini).
--   * Kolom: audio_url, audio_path, cover_url, cover_path, sort_order,
--     recorded_at, duration, downloadable, created_by, created_at.
--   * Realtime aktif pada tabel recordings (update antar perangkat).
--   * Admin ditandai via claim app_metadata.role = 'admin' pada JWT.
-- =====================================================================

-- 1) EXTENSIONS ------------------------------------------------------
create extension if not exists "pgcrypto";

-- 2) TABEL RECORDINGS ------------------------------------------------
create table if not exists public.recordings (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  description   text,
  category      text,
  audio_path    text not null,          -- path di bucket 'recordings', mis. audio/123-nama.m4a
  audio_url     text,                   -- URL publik (cache; diisi ulang jika null)
  cover_path    text,                   -- path sampul di bucket 'recordings', mis. cover/123-nama.jpg
  cover_url     text,                   -- URL publik sampul (cache)
  filename      text,                   -- nama file asli saat upload (opsional, info saja)
  duration      numeric,                -- durasi detik
  recorded_at   date,                    -- tanggal rekaman
  downloadable  boolean not null default true,
  sort_order    integer not null default 0,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists recordings_sort_order on public.recordings(sort_order);
create index if not exists recordings_created_at on public.recordings(created_at desc);
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

-- 5) ROW LEVEL SECURITY ---------------------------------------------
alter table public.recordings enable row level security;

-- 5a) SELECT publik untuk semua baris (pengunjung bisa membaca metadata)
drop policy if exists "recordings_select_public" on public.recordings;
create policy "recordings_select_public"
  on public.recordings for select using (true);

-- 5b) INSERT hanya admin
drop policy if exists "recordings_insert_admin" on public.recordings;
create policy "recordings_insert_admin"
  on public.recordings for insert with check (public.is_admin());

-- 5c) UPDATE hanya admin
drop policy if exists "recordings_update_admin" on public.recordings;
create policy "recordings_update_admin"
  on public.recordings for update
  using (public.is_admin()) with check (public.is_admin());

-- 5d) DELETE hanya admin
drop policy if exists "recordings_delete_admin" on public.recordings;
create policy "recordings_delete_admin"
  on public.recordings for delete using (public.is_admin());

-- 6) STORAGE BUCKET -------------------------------------------------
-- Satu bucket publik "recordings" untuk file audio dan gambar sampul.
insert into storage.buckets (id, name, public)
values ('recordings', 'recordings', true)
on conflict (id) do update set public = true;

-- 7) STORAGE POLICIES -----------------------------------------------
-- Publik bisa BACA (streaming). Hanya admin bisa TULIS/HAPUS.
drop policy if exists "recordings_bucket_read_public" on storage.objects;
create policy "recordings_bucket_read_public"
  on storage.objects for select using (bucket_id = 'recordings');

drop policy if exists "recordings_bucket_insert_admin" on storage.objects;
create policy "recordings_bucket_insert_admin"
  on storage.objects for insert
  with check (bucket_id = 'recordings' and public.is_admin());

drop policy if exists "recordings_bucket_update_admin" on storage.objects;
create policy "recordings_bucket_update_admin"
  on storage.objects for update
  using (bucket_id = 'recordings' and public.is_admin())
  with check (bucket_id = 'recordings' and public.is_admin());

drop policy if exists "recordings_bucket_delete_admin" on storage.objects;
create policy "recordings_bucket_delete_admin"
  on storage.objects for delete
  using (bucket_id = 'recordings' and public.is_admin());

-- 8) REALTIME -------------------------------------------------------
-- Aktifkan Supabase Realtime pada tabel recordings agar daftar di semua
-- perangkat otomatis diperbarui saat ada INSERT/UPDATE/DELETE.
do $$
begin
  if not exists (
    select 1 from publication where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime;
  end if;
end $$;

alter publication supabase_realtime add table public.recordings;
-- Catatan: tabel harus punya REPLICA IDENTITY FULL agar payload DELETE
-- menyertakan data lama (digunakan client untuk identifikasi baris).
alter table public.recordings replica identity full;

-- 9) MEMBUAT ADMIN PERTAMA ------------------------------------------
-- 1) Buat user via Dashboard > Authentication > Users > Add user
--    (email + password), centang "Auto Confirm User".
-- 2) Tandai sebagai admin:
--
--      update auth.users
--      set raw_app_meta_data = coalesce(raw_app_meta_data,'{}'::jsonb)
--        || '{"role":"admin"}'::jsonb
--      where email = 'admin@situsanda.com';
--
-- 3) Verifikasi:
--
--      select email, raw_app_meta_data from auth.users
--      where email = 'admin@situsanda.com';
--      -- harus memuat "role":"admin"
--
-- Setelah langkah (2), user tersebut bisa login di /admin/login dan
-- melakukan upload/edit/hapus. Pengunjung lain tetap hanya bisa membaca.
-- =====================================================================
