// Política de segurança de conteúdo (CSP) do index.html.
// O GitHub Pages não deixa configurar cabeçalhos, então a CSP vai numa <meta>. Como o app tem um <script> embutido,
// a política autoriza esse script pelo hash SHA-256 do conteúdo. Qualquer edição no script muda o hash:
//   node scripts/csp.js            -> recalcula e grava a meta no index.html
//   node scripts/csp.js --check    -> só confere (usado no pre-push); sai com erro se estiver desatualizada
//   node scripts/csp.js --file X   -> usa outro arquivo (testes)
const fs = require("fs");
const crypto = require("crypto");
const args = process.argv.slice(2);
const check = args.includes("--check");
const i = args.indexOf("--file");
const file = i >= 0 ? args[i + 1] : "index.html";

const SUPABASE = "https://wyirmfuinpaaeodpbwcz.supabase.co";
function politica(hashes) {
  return [
    "default-src 'self'",
    "script-src 'self' " + hashes.map(h => "'sha256-" + h + "'").join(" ") + " https://cdnjs.cloudflare.com https://cdn.jsdelivr.net",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdnjs.cloudflare.com https://cdn.jsdelivr.net",
    "font-src https://fonts.gstatic.com",
    "img-src 'self' data: blob: " + SUPABASE + " https://tiles.openfreemap.org",
    "connect-src 'self' " + SUPABASE + " " + SUPABASE.replace("https://", "wss://") + " https://nominatim.openstreetmap.org https://tiles.openfreemap.org",
    "worker-src 'self' blob:",
    "child-src blob:",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join("; ");
}

// O navegador normaliza CRLF para LF antes de calcular o hash do script.
function hashesDoScript(html) {
  const out = [];
  const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
  let m;
  while ((m = re.exec(html))) out.push(crypto.createHash("sha256").update(m[1].replace(/\r\n/g, "\n"), "utf8").digest("base64"));
  return out;
}

const metaRe = /<meta http-equiv="Content-Security-Policy" content="[^"]*">/;
const html = fs.readFileSync(file, "utf8");
const meta = '<meta http-equiv="Content-Security-Policy" content="' + politica(hashesDoScript(html)) + '">';
if (check) {
  const atual = html.match(metaRe);
  if (!atual || atual[0] !== meta) { console.error("CSP desatualizada em " + file + ". Rode `node scripts/csp.js` e faça commit."); process.exit(1); }
  console.log("CSP ok");
} else {
  const novo = metaRe.test(html) ? html.replace(metaRe, () => meta) : html.replace("<meta charset=\"UTF-8\">", () => "<meta charset=\"UTF-8\">\n" + meta);
  fs.writeFileSync(file, novo);
  console.log("CSP atualizada (" + hashesDoScript(novo).length + " script(s) embutido(s))");
}
