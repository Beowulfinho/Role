// Sobe a versão do app (APP_VERSION em index.html).
//   node scripts/bump-version.js            -> 1.N  vira 1.(N+1)   (padrão: versão secundária)
//   node scripts/bump-version.js --major    -> 1.N  vira 2.0       (só quando o dono pedir explicitamente)
//   node scripts/bump-version.js --file X   -> usa outro arquivo (testes)
const fs = require("fs");
const args = process.argv.slice(2);
const major = args.includes("--major");
const i = args.indexOf("--file");
const file = i >= 0 ? args[i + 1] : "index.html";
let s = fs.readFileSync(file, "utf8");
const re = /var APP_VERSION = "(\d+)\.(\d+)";/;
const m = s.match(re);
if (!m) { console.error("APP_VERSION não encontrada em " + file); process.exit(1); }
const novo = major ? (parseInt(m[1], 10) + 1) + ".0" : m[1] + "." + (parseInt(m[2], 10) + 1);
fs.writeFileSync(file, s.replace(re, 'var APP_VERSION = "' + novo + '";'));
console.log(m[1] + "." + m[2] + " -> " + novo);
// o hash do script embutido muda junto com a versão: atualiza a CSP
require("child_process").execFileSync(process.execPath, ["scripts/csp.js", "--file", file], { stdio: "inherit" });
