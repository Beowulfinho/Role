# Rolê (nome provisório)

App para casais e grupos de amigos avaliarem lugares (restaurantes, bares, passeios, hotéis) com categorias e realidade do Brasil.

- Frontend: PWA de um único `index.html` (vanilla JS), em português.
- Backend: Supabase, projeto `app-avaliacoes` (`wyirmfuinpaaeodpbwcz`, sa-east-1), separado do projeto do FacheAssistant.
- Segurança: RLS por grupo; criação de grupo e entrada por código via RPC (`criar_grupo`, `entrar_grupo`).
- Sem APIs externas na Fase 1: o usuário digita o nome do lugar; o link do Maps é opcional.

## Versão do app

A versão aparece no canto superior esquerdo da tela de grupos, no login e no perfil (`APP_VERSION` em `index.html`).

- **Cada push sobe a versão secundária:** `1.1 -> 1.2 -> ... -> 1.10`. Rode `node scripts/bump-version.js`, faça commit (`Versão 1.N`) e depois o push.
- **Versão principal (`2.0`) só quando o dono pedir explicitamente:** `node scripts/bump-version.js --major`.
- O hook `.githooks/pre-push` bloqueia o push se a versão não mudou. Ative uma vez por clone: `git config core.hooksPath .githooks`.
