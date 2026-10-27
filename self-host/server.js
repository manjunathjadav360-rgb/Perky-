const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const HOST = process.env.HOST || "127.0.0.1";
const PORT = Number(process.env.PORT || 3000);

const PUBLIC_FILES = new Set([
  "/",
  "/index.html",
  "/privacy.html",
  "/terms.html",
  "/manifest.webmanifest",
  "/perkly-icon.svg"
]);

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".ico": "image/x-icon"
};

function send(res, status, contentType, body) {
  res.writeHead(status, {
    "Content-Type": contentType,
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Cache-Control": "no-store"
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.setHeader("Allow", "GET, HEAD");
    return send(res, 405, "application/json; charset=utf-8",
      JSON.stringify({ error: "Method not allowed" }));
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
  } catch {
    return send(res, 400, "text/plain; charset=utf-8", "Bad request");
  }

  if (pathname === "/api/health") {
    return send(res, 200, "application/json; charset=utf-8",
      JSON.stringify({ status: "ok", app: "Perkly", mode: "local-self-hosted-starter" }));
  }

  if (!PUBLIC_FILES.has(pathname)) {
    return send(res, 404, "text/plain; charset=utf-8", "Not found");
  }

  const requested = pathname === "/" ? "/index.html" : pathname;
  const filePath = path.resolve(ROOT, "." + requested);

  if (!filePath.startsWith(ROOT + path.sep)) {
    return send(res, 403, "text/plain; charset=utf-8", "Forbidden");
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      return send(res, 404, "text/plain; charset=utf-8", "Not found");
    }
    const type = MIME_TYPES[path.extname(filePath)] || "application/octet-stream";
    res.writeHead(200, {
      "Content-Type": type,
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      "Cache-Control": "no-store"
    });
    res.end(req.method === "HEAD" ? undefined : data);
  });
});

server.listen(PORT, HOST, () => {
  console.log("Perkly local server is running.");
  console.log("Website: http://" + HOST + ":" + PORT);
  console.log("Health:  http://" + HOST + ":" + PORT + "/api/health");
  console.log("Local-only binding: not exposed to the public internet.");
});

server.on("error", (error) => {
  console.error("Could not start Perkly server:", error.message);
  process.exitCode = 1;
});
