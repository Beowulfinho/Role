/* Rolê: service worker simples. HTML sempre da rede (fica atualizado); cai no cache se estiver offline.
   Estáticos e bibliotecas: usa o cache e atualiza em segundo plano. Dados do Supabase e tiles do mapa nunca passam por aqui. */
var VERSAO = "role-v1";
var BASE = ["./", "index.html", "manifest.json", "icon.svg", "icon-180.png", "icon-192.png", "icon-512.png", "icon-maskable-512.png"];
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
    e.respondWith(fetch(req).then(function(r){
      var copia = r.clone(); caches.open(VERSAO).then(function(c){ c.put("index.html", copia); });
      return r;
    }).catch(function(){ return caches.match("index.html"); }));
    return;
  }
  e.respondWith(caches.open(VERSAO).then(function(c){
    return c.match(req).then(function(hit){
      var rede = fetch(req).then(function(r){
        if (r && (r.ok || r.type === "opaque")) c.put(req, r.clone());
        return r;
      }).catch(function(){ return hit; });
      return hit || rede;
    });
  }));
});
