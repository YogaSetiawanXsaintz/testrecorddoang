#!/usr/bin/env node
/**
 * build.js — injeksikan env var Supabase ke index.html
 *
 * Sumber  : src/index.template.html  (placeholder __SUPABASE_URL__, __SUPABASE_ANON_KEY__)
 * Hasil   : index.html               (siap deploy)
 *
 * Env var yang dipakai (urutan prioritas):
 *   NEXT_PUBLIC_SUPABASE_URL
 *   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY  →  fallback  NEXT_PUBLIC_SUPABASE_ANON_KEY
 *
 * Nilai cadangan hardcoded di bawah adalah publishable key (anon) yang aman
 * untuk publik — data sebenarnya dilindungi oleh RLS di Supabase. Nilai ini
 * dipakai bila env var belum diset atau build step tidak jalan.
 *
 * Jalankan:  node build.js
 */
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const SRC = path.join(ROOT, 'src', 'index.template.html');
const OUT = path.join(ROOT, 'index.html');

// Nilai cadangan publishable key — AMAN untuk diekspos di browser (RLS aktif).
const FALLBACK_SUPABASE_URL = "https://tsyhioxzzhlqldhjztbx.supabase.co";
const FALLBACK_SUPABASE_KEY = "sb_publishable_MHZ-uLsW1yRuqCLXkVFINg_T3HI2WZ4";

const SUPABASE_URL =
  process.env.NEXT_PUBLIC_SUPABASE_URL || FALLBACK_SUPABASE_URL;
const SUPABASE_ANON_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  || FALLBACK_SUPABASE_KEY;

if (!process.env.NEXT_PUBLIC_SUPABASE_URL) {
  console.warn('ℹ️  NEXT_PUBLIC_SUPABASE_URL tidak diset — memakai nilai cadangan hardcoded.');
}
if (!process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY && !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
  console.warn('ℹ️  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY tidak diset — memakai nilai cadangan hardcoded.');
}

let html = fs.readFileSync(SRC, 'utf8');
const ready = (SUPABASE_URL && SUPABASE_ANON_KEY) ? '1' : '0';
html = html.replace(/__SUPABASE_URL__/g, SUPABASE_URL);
html = html.replace(/__SUPABASE_ANON_KEY__/g, SUPABASE_ANON_KEY);
html = html.replace(/__CONFIG_READY__/g, ready);

fs.writeFileSync(OUT, html, 'utf8');
console.log('✅ Build selesai: ' + path.relative(process.cwd(), OUT));
console.log('   SUPABASE_URL:', SUPABASE_URL ? '✓ ' + SUPABASE_URL : '✗ kosong');
console.log('   ANON_KEY   :', SUPABASE_ANON_KEY ? '✓ terisi (' + (SUPABASE_ANON_KEY.slice(0, 14)) + '...)' : '✗ kosong');
console.log('   CONFIG_READY:', ready);
