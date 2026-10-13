# Segurança do Rolê

Documento vivo. Última revisão: 13/10/2026.

## O que já está protegido

| Camada | Medida |
|---|---|
| Banco | RLS ligada em todas as tabelas; funções `SECURITY DEFINER` com `search_path` fixo, sem acesso anônimo; checagem de `auth.uid()` em cada RPC |
| Arquivos | Buckets `fotos` e `avatares` privados, com limite de tamanho e só JPG/PNG/WebP; acesso por link temporário assinado |
| Fotos | Reprocessadas no aparelho (canvas) antes do envio: some o EXIF/GPS |
| Chaves | O app usa só a chave publicável (`sb_publishable_…`); nenhuma chave secreta no código |
| Push | Função `enviar-push` só aceita chamada com segredo interno guardado no Vault; chaves VAPID no Vault; conta de serviço do FCM como secret |
| Web | Todo texto de usuário passa por `esc()`; CSP por `<meta>` com hash do script embutido; SRI nas bibliotecas de CDN; anti-iframe (clickjacking) |
| Auth | Confirmação de e-mail obrigatória, cadastro anônimo desligado, senha mínima de 8, troca de senha segura |
| Android | Backup desativado, só HTTPS, sem `debuggable`, navegação restrita ao domínio do app, APK/AAB de release assinados |

## Pendências (precisam de decisão ou de plano pago)

1. **Plano Pro do Supabase**: backups diários, PITR e bloqueio de senhas vazadas (HaveIBeenPwned). Sem isso **não há backup**.
2. **SSL obrigatório no banco**: ativar em Database → Settings. Exige reinício (alguns minutos fora do ar).
3. **CAPTCHA** (Cloudflare Turnstile ou hCaptcha): criar o site key e o secret; o secret vai em Auth → Attack Protection.
4. **MFA na sua conta do Supabase, do GitHub e do Firebase**.
5. **Migração SQL** `supabase/migrations/20261013_seguranca.sql`: limite de tentativas, bloqueio, denúncias e exclusão de conta. O app novo já a usa, então aplique **antes** de publicar.
6. **Preencher** `{{NOME_RESPONSAVEL}}`, `{{CNPJ_OU_CPF}}` e `{{EMAIL_CONTATO}}` em `privacidade.html`, `termos.html` e `excluir-conta.html` (o pre-push bloqueia enquanto houver `{{…}}`) e pedir revisão de um advogado.
7. **Google Play**: Play App Signing, formulário de segurança de dados e URL da exclusão de conta (`…/excluir-conta.html`).
8. **Cloudflare na frente do GitHub Pages** (gratuito) para enviar cabeçalhos HSTS, `X-Frame-Options`/`frame-ancestors`, `Referrer-Policy` e `Permissions-Policy`.
9. **Rotação anual** das chaves JWT do Supabase.

## Regras para mudar o código

- Todo texto vindo de usuário em HTML: `esc()`. Nunca `innerHTML` com dado cru.
- Nova tabela: RLS ligada **na mesma migração** e política explícita.
- Nova função `SECURITY DEFINER`: `set search_path = ''`, `revoke … from public, anon`, validar `auth.uid()` e permissão.
- Operação que aceita códigos ou cria coisas: chamar `private.limitar(...)` e devolver valor (não erro) em tentativa inválida, para a contagem persistir.
- Nova biblioteca externa: versão fixa + `integrity` (SRI) e host liberado em `scripts/csp.js`. Depois `node scripts/csp.js`.
- Alterou o `<script>` do `index.html`: rode `node scripts/csp.js` (o `bump-version.js` já faz isso).
- Chave secreta nunca vai para o git, para o app ou para o chat: Supabase Secrets/Vault.

## Assinatura do Android

- Chave de envio: `mobile/keystore/role-upload.jks` + `mobile/keystore.properties` (ambos fora do git).
- **Faça backup dos dois em local seguro** (gerenciador de senhas ou cofre). Sem eles não há como atualizar o app assinado com essa chave. Com Play App Signing, perder a chave de envio é recuperável via suporte do Google.
- Compilar: `cd mobile/android && ./gradlew assembleRelease bundleRelease`.
- O APK de release usa uma assinatura diferente da do APK de teste (debug): para instalar, é preciso desinstalar o antigo (uma vez).

## Plano de resposta a incidente (vazamento de dados pessoais)

1. **Conter**: revogar acesso (rotacionar chaves/segredos afetados, desativar função, bloquear usuário). Anotar data e hora em que soube.
2. **Avaliar**: quais dados, de quantas pessoas, por quanto tempo, se houve acesso indevido.
3. **Comunicar** (LGPD, Resolução CD/ANPD nº 15/2024): se houver risco ou dano relevante aos titulares, avisar a **ANPD e as pessoas afetadas em 3 dias úteis** a partir de quando soube que o incidente afetou dados pessoais (6 dias úteis para agente de pequeno porte). Se faltar informação, enviar comunicação preliminar e completar depois. Avisar pelo e-mail cadastrado e por aviso dentro do app.
4. **Corrigir** a causa e **registrar** o incidente (o que houve, impacto, medidas). Guardar o registro.

## Backup manual (enquanto não houver plano Pro)

- Banco: `pg_dump` pela string de conexão (Database → Settings → Connection string) guardando o arquivo **cifrado**.
- Fotos: o bucket `fotos` não entra em nenhum backup do Supabase; exportar à parte se for importante.
- Faça isso antes de aplicar qualquer migração grande.
