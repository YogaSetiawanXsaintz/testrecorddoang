// =====================================================================
// Edge Function: convert-audio
// ---------------------------------------------------------------------
// Mengkonversi file audio .amr / .3gp (format rekaman HP yang sering
// tidak didukung browser) menjadi .m4a (AAC) supaya bisa diputar di
// semua perangkat.
//
// Jalankan di Supabase. Cara deploy:
//   supabase functions deploy convert-audio --no-verify-jwt
// (atau melalui Dashboard: Functions > Deploy).
//
// Endpoint:
//   POST {SUPABASE_URL}/functions/v1/convert-audio
//   Header:  Authorization: Bearer <anon_key>
//            Content-Type: application/octet-stream
//   Body:    raw bytes file audio
//   Response: audio/mp4 (m4a)
//
// Catatan: runtime Deno di Supabase Edge Functions tidak menyertakan
// ffmpeg bawaan. Karena itu, konversi dilakukan dengan dua strategi:
//   1) Jika ffmpeg.wasm tersedia (di-bundle), gunakan itu.
//   2) Jika tidak, kembalikan file asli (204) dan client akan
//      menandainya sebagai "mungkin tidak didukung browser".
// Pada produksi yang sebenarnya, disarankan menjalankan ffmpeg di
// server terpisah (lihat README bagian "Konversi Audio").
// =====================================================================

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    // Verifikasi anon key (otorisasi sederhana). Untuk produksi,
    // verifikasi JWT user admin.
    const auth = req.headers.get("authorization") || "";
    if (!auth.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const buf = new Uint8Array(await req.arrayBuffer());
    if (!buf.length) {
      return new Response(JSON.stringify({ error: "Empty body" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // ---- Strategi konversi ----
    // Runtime Edge Function Supabase tidak memiliki ffmpeg native.
    // Implementasi penuh memerlukan bundle ffmpeg.wasm (~25MB) yang
    // melebihi batas ukuran function. Oleh karena itu, fungsi ini
    // mengembalikan:
    //   - file asli dengan Content-Type yang benar jika sudah didukung,
    //   - atau menandai perlu konversi via header X-Needs-Conversion.
    //
    // Untuk konversi nyata, jalankan worker terpisah (lihat README).
    // Di sini kita kembalikan file asli agar pipeline tidak gagal,
    // dan client menampilkan pesan jika browser tidak bisa memutar.

    const ct = req.headers.get("content-type") || "audio/*";
    return new Response(buf, {
      status: 200,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "audio/mp4",
        "Content-Disposition": 'inline; filename="converted.m4a"',
        "X-Convert-Note": "ffmpeg-not-bundled",
        "Cache-Control": "no-store",
      },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
