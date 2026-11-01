-- Yoco is the current hosted checkout provider for new card payments.
alter table public.payments
  alter column provider set default 'yoco';
