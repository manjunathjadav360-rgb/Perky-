-- Keep one visible card per reward concept in the public preview.
-- The older voucher and coffee rows are already inactive; hide their duplicate sample rows too.
update public.rewards
set active = false
where id in ('sample-voucher', 'sample-coffee')
  and active = true;
