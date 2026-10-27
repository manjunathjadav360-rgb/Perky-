# Perkly self-hosted starter

This is a first local-server step. It serves the existing Perkly website from your own computer and provides a small health endpoint. It does **not** replace Supabase yet, and it is not a public production server.

## Requirements

- A computer you control
- Node.js 18 or newer
- A copy of this repository

## Run it

From the repository folder:

```sh
cd self-host
npm start
```

Then open:

- Website: http://127.0.0.1:3000
- Health check: http://127.0.0.1:3000/api/health

No third-party Node packages are required.

## Safety notes

- By default the server listens only on `127.0.0.1`, so it is available only on that computer.
- Do not change the host to `0.0.0.0` or expose it to the internet until authentication, request handling, TLS, rate limiting, logging, backups, and deployment security are designed and reviewed.
- The current website still uses its existing Supabase integration. Do not put Supabase service-role keys, database passwords, or other secrets in browser code or this repository.
- The health endpoint confirms only that this local Node process is responding; it does not verify database connectivity.
- A public custom domain requires participation in the public DNS/domain-registration system. This starter does not create a public domain.
