-- 0002_money_in_cents.sql
--
-- Money moves to integer cents. The app currently reads `price` as a Dart
-- `double` and multiplies it by quantity to build a cart total, which is a
-- rounding bug waiting to be found by an auditor. Paystack also expects the
-- amount in the minor unit, so cents is the natural representation end to end.
--
-- Both columns are kept during the transition. `price` remains the source of
-- truth for any code not yet migrated; a trigger keeps the two in step so
-- neither can drift while the Flutter client is being updated.

alter table public.menu_items
  add column if not exists price_cents integer;

update public.menu_items
   set price_cents = round(price * 100)::integer
 where price_cents is null;

alter table public.menu_items alter column price_cents set default 0;
update public.menu_items set price_cents = 0 where price_cents is null;
alter table public.menu_items alter column price_cents set not null;

do $$ begin
  alter table public.menu_items
    add constraint menu_items_price_cents_non_negative check (price_cents >= 0);
exception when duplicate_object then null; end $$;

-- Keep price and price_cents consistent whichever one a writer sets, so the
-- old and new clients can coexist during rollout.
create or replace function public.sync_menu_item_price()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' then
    if new.price_cents is distinct from 0 and new.price_cents is not null then
      new.price := new.price_cents / 100.0;
    else
      new.price_cents := round(coalesce(new.price, 0) * 100)::integer;
    end if;
    return new;
  end if;

  -- UPDATE: whichever column actually changed wins.
  if new.price_cents is distinct from old.price_cents then
    new.price := new.price_cents / 100.0;
  elsif new.price is distinct from old.price then
    new.price_cents := round(new.price * 100)::integer;
  end if;

  return new;
end;
$$;

drop trigger if exists menu_items_sync_price on public.menu_items;
create trigger menu_items_sync_price
  before insert or update on public.menu_items
  for each row execute function public.sync_menu_item_price();

comment on column public.menu_items.price is
  'DEPRECATED, kept in sync by trigger. Use price_cents. Drop once the Flutter client no longer reads it.';
