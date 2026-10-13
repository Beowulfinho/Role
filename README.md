# Rolê (nome provisório)

App para casais e grupos de amigos avaliarem lugares (restaurantes, bares, passeios, hotéis) com categorias e realidade do Brasil.

- Frontend: PWA de um único `index.html` (vanilla JS), em português.
- Backend: Supabase, projeto `app-avaliacoes` (`wyirmfuinpaaeodpbwcz`, sa-east-1), separado do projeto do FacheAssistant.
- Segurança: RLS por grupo; criação de grupo e entrada por código via RPC (`criar_grupo`, `entrar_grupo`).
- Sem APIs externas na Fase 1: o usuário digita o nome do lugar; o link do Maps é opcional.
