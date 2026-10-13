/* Rolê: service worker simples. HTML sempre da rede (fica atualizado); cai no cache se estiver offline.
   Estáticos e bibliotecas: usa o cache e atualiza em segundo plano. Dados do Supabase e tiles do mapa nunca passam por aqui. */
var VERSAO = "role-v3";
var BASE = ["./", "index.html", "manifest.json", "icon.svg", "icon-180.png", "icon-192.png", "icon-512.png", "icon-maskable-512.png", "badge-96.png"];
var CDNS = ["cdnjs.cloudflare.com", "cdn.jsdelivr.net", "fonts.googleapis.com", "fonts.gstatic.com"];

self.addEventListener("install", function(e){
  e.waitUntil(caches.open(VERSAO).then(function(c){ return c.addAll(BASE); }).then(function(){ return self.skipWaiting(); }));
});
self.addEventListener("activate", function(e){
  e.waitUntil(caches.keys().then(function(ks){
    return Promise.all(ks.filter(function(k){ return k !== VERSAO; }).map(function(k){ return caches.delete(k); }));
  }).then(function(){ return self.clients.claim(); }));
});
self.addEventListener("fetch", function(e){
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  var mesmaOrigem = url.origin === self.location.origin;
  if (!mesmaOrigem && CDNS.indexOf(url.hostname) < 0) return;

  if (req.mode === "navigate"){
    // no-cache: sempre revalida com o servidor (o GitHub Pages deixa a página em cache por 10 min)
    e.respondWith(fetch(req, { cache: "no-cache" }).then(function(r){
      var copia = r.clone(); caches.open(VERSAO).then(function(c){ c.put("index.html", copia); });
      return r;
    }).catch(function(){ return caches.match("index.html"); }));
    return;
  }
  e.respondWith(caches.open(VERSAO).then(function(c){
    return c.match(req).then(function(hit){
      var rede = fetch(req, mesmaOrigem ? { cache: "no-cache" } : undefined).then(function(r){
        if (r && (r.ok || r.type === "opaque")) c.put(req, r.clone());
        return r;
      }).catch(function(){ return hit; });
      return hit || rede;
    });
  }));
});

/* ---------- notificações push ---------- */
self.addEventListener("push", function(e){
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch(x){ d = { titulo: "Rolê", corpo: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.titulo || "Rolê", {
    body: d.corpo || "",
    icon: "icon-192.png",
    badge: "badge-96.png",
    tag: d.id ? "n:" + d.id : (d.tipo || "role"),
    renotify: false,
    data: { link: d.link || "#/notificacoes", id: d.id || null }
  }));
});
self.addEventListener("notificationclick", function(e){
  e.notification.close();
  var dados = e.notification.data || {}, base = self.registration.scope, link = dados.link || "#/notificacoes";
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(function(lista){
    for (var i = 0; i < lista.length; i++){
      if (lista[i].url.indexOf(base) === 0){
        lista[i].postMessage({ tipo: "abrir", link: link, id: dados.id });
        return lista[i].focus();
      }
    }
    return self.clients.openWindow(base + link);
  }));
});
