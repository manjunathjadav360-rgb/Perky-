-- Hide duplicate demo cards so members do not see the same activity or reward twice.
update public.earning_tasks set active = false where id in ('daily','learn','feedback');
update public.rewards set active = false where id in ('coffee','voucher');
