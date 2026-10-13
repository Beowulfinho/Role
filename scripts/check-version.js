// Usado pelo hook de pre-push: impede publicar sem subir a versão do app.
const { execSync } = require("child_process");
const sh = c => { try { return execSync(c, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }); } catch (e) { return null; } };
const ver = t => { const m = t && t.match(/var APP_VERSION = "(\d+\.\d+)";/); return m ? m[1] : null; };
const novos = parseInt((sh("git rev-list --count origin/main..HEAD") || "0").trim(), 10);
if (!novos) process.exit(0);                       // nada novo para publicar
const atual = ver(sh("git show HEAD:index.html"));
const remoto = ver(sh("git show origin/main:index.html"));
// CSP e páginas legais
const fs = require("fs"), os = require("os"), path = require("path");
const tmp = path.join(os.tmpdir(), "role-index-check.html");
const idx = sh("git show HEAD:index.html");
if (idx) {
  fs.writeFileSync(tmp, idx);
  try { execSync("node scripts/csp.js --check --file \"" + tmp + "\"", { stdio: "inherit" }); } catch (e) { process.exit(1); }
}
for (const p of ["privacidade.html", "termos.html", "excluir-conta.html"]) {
  const t = sh("git show HEAD:" + p);
  if (t && /{{[A-Z_]+}}/.test(t)) { console.error("Push bloqueado: " + p + " ainda tem campos {{...}} sem preencher (nome, documento e e-mail de contato)."); process.exit(1); }
}
if (!atual) { console.error("APP_VERSION não encontrada em index.html."); process.exit(1); }
if (remoto && atual === remoto) {
  console.error("Push bloqueado: a versão do app continua " + atual + ".\nRode `node scripts/bump-version.js`, faça commit (ex.: \"Versão X.Y\") e tente de novo.");
  process.exit(1);
}
console.log("Versão do app: " + (remoto || "—") + " -> " + atual);
