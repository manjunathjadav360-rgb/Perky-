# Perkly

Perkly is an early-stage rewards and survey platform built as a mobile-first static website with Supabase authentication and PostgreSQL-backed workflows.

> **Deployment status:** The latest code is committed, but the public website is not confirmed live yet. GitHub requires the repository owner to enable **Settings → Pages → Source → GitHub Actions** once; then run the deployment workflow from the Actions tab.

## Current features

- Responsive public landing page, activity cards, reward previews and mobile install metadata
- Email/password signup, login and password recovery through Supabase Auth
- Member dashboard with point ledger, task submissions, reward requests and history
- Task submissions stored for admin review; points are credited after approval; daily check-in can be submitted once per UTC day while other demo activities are one-time
- Partner enquiry form with server-side validation and rate limiting
- Reward redemption through a transactional Supabase RPC
- Admin review UI gated by the trusted `app_metadata.role = "admin"` claim
- Database refund entry when a redemption is rejected or cancelled

## Free deployment

This repository is a static site: `index.html` is the entry point. No build command is required.

### GitHub Pages
1. Open **Settings → Pages** for this repository.
2. Under **Build and deployment → Source**, choose **GitHub Actions** and save. This one-time setting requires repository-owner access.
3. Open the **Actions** tab, choose **Deploy Perkly to GitHub Pages**, tap **Run workflow**, and confirm.
4. Wait for the workflow to finish. Its deployment job displays the published URL.
5. If the Actions workflow is not available, make sure GitHub Actions are enabled for the repository.

The connected GitHub integration cannot enable Pages itself because GitHub requires repository administration permission. The workflow is manual by design so it does not repeatedly fail before this one-time setting is configured.

### Supabase Auth URL configuration
After GitHub Pages provides the URL, open Supabase **Authentication → URL Configuration**:
- Set **Site URL** to the exact deployed website URL.
- Add that same URL to **Redirect URLs**.

The website uses the Supabase project URL and publishable key in `index.html`. A publishable key is intended for browser use; never put a service-role or secret key in this repository.

### Set up the first admin account
After creating your own account through the website, open **Supabase → SQL Editor** and run the statement below after replacing the placeholder with your own account email:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || jsonb_build_object('role', 'admin')
where lower(email) = lower('YOUR_ACCOUNT_EMAIL');
```

Confirm that exactly one intended account was updated. Then sign out and sign in again so the new trusted app-metadata claim appears in your session. Never place admin roles in editable user metadata or let the browser assign its own role.

## Important limits

- Reward items currently marked `sample` are display previews, not real offers.
- The website does not yet connect to an external survey provider, issue vouchers, pay cash, or run a payment gateway.
- Points are not money. Only approved activities and properly funded partner offers should be represented as real earning opportunities.
- Keep the Supabase database's row-level security enabled. Assign the admin role only through trusted server-side/admin tooling, never from client-side profile fields.
- The Supabase security advisor reports leaked-password protection is disabled. Before a public launch, enable it under the project's Authentication/password security settings and review all remaining advisor findings.
- Review legal, privacy, tax, consumer-protection and payment requirements before accepting real users or launching paid campaigns.

## Files

- `index.html` — responsive UI and browser-side Supabase integration
- `privacy.html` / `terms.html` — prototype privacy and usage notices; final legal review is still required before launch
- `supabase/migrations/` — supplemental SQL changes for the connected project's existing schema
- The migration folder does not yet include the original baseline schema migrations. Do not run `supabase db push` against a fresh project from this folder alone; the connected project already has its base schema and the files here document subsequent changes.
