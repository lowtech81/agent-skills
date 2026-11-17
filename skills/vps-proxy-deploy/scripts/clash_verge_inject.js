// Template for Clash Verge Profile Extension Script (Script.js)
// Fixes:
// 1. Missing DNS nameservers / IPv6 timeouts for domain-based nodes (e.g., Cloudflare WS)
// 2. Duplicate extended nodes when Merge template uses `include-all-proxies: true`
// 3. Pollution of the "🛑 广告拦截" group with proxy nodes

function main(config, profileName) {
  // 1) Force IPv4 & ensure complete domestic DNS for proxy server domain resolution
  config.ipv6 = false;
  config["unified-delay"] = true;
  config["tcp-concurrent"] = true;
  config.dns = {
    enable: true,
    ipv6: false,
    "enhanced-mode": "fake-ip",
    "fake-ip-range": "198.18.0.1/16",
    "default-nameserver": ["223.5.5.5", "119.29.29.29", "180.76.76.76"],
    nameserver: [
      "223.5.5.5",
      "119.29.29.29",
      "https://dns.alidns.com/dns-query",
      "https://doh.pub/dns-query"
    ],
    "proxy-server-nameserver": [
      "223.5.5.5",
      "119.29.29.29",
      "https://dns.alidns.com/dns-query"
    ]
  };

  // 2) Define custom extended nodes
  var nodes = [
    // Replace or append custom VLESS-REALITY / Hysteria2 / WS nodes here
  ];

  var names = [];
  for (var i = 0; i < nodes.length; i++) names.push(nodes[i].name);

  // 3) Prepend custom nodes to config.proxies with strict deduplication
  var proxies = config.proxies || [];
  var kept = [];
  var seenProxy = {};
  for (var k = 0; k < nodes.length; k++) {
    kept.push(nodes[k]);
    seenProxy[nodes[k].name] = true;
  }
  for (var j = 0; j < proxies.length; j++) {
    if (proxies[j] && proxies[j].name && !seenProxy[proxies[j].name]) {
      kept.push(proxies[j]);
      seenProxy[proxies[j].name] = true;
    }
  }
  config.proxies = kept;

  var allProxyNames = [];
  for (var a = 0; a < kept.length; a++) allProxyNames.push(kept[a].name);

  // 4) Populate proxy-groups without duplicating nodes when include-all-proxies is enabled
  var groups = config["proxy-groups"] || [];
  for (var m = 0; m < groups.length; m++) {
    var g = groups[m];
    if (!g || g.name === "🛑 广告拦截") continue;
    var existing = g.proxies || [];
    var list = [];
    var seen = {};

    if (g["include-all-proxies"]) {
      for (var p = 0; p < existing.length; p++) {
        var item = existing[p];
        if (names.indexOf(item) === -1 && !seen[item]) {
          list.push(item);
          seen[item] = true;
        }
      }
      for (var q = 0; q < allProxyNames.length; q++) {
        var pName = allProxyNames[q];
        if (!seen[pName]) {
          list.push(pName);
          seen[pName] = true;
        }
      }
      g.proxies = list;
      delete g["include-all-proxies"];
    } else if (existing.length > 0) {
      for (var n = 0; n < names.length; n++) {
        if (!seen[names[n]]) {
          list.push(names[n]);
          seen[names[n]] = true;
        }
      }
      for (var r = 0; r < existing.length; r++) {
        if (!seen[existing[r]]) {
          list.push(existing[r]);
          seen[existing[r]] = true;
        }
      }
      g.proxies = list;
    }
  }

  return config;
}
