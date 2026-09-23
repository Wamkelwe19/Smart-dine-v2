-- supabase/seed/seed_menu.sql
--
-- A demo menu for the three UMP stores: at least 6 new items each, with
-- photos, categories, varieties (flavours / sizes), one combo and one special
-- per store, and a cover photo for each hall.
--
-- Run AFTER migrations 0008-0011, in the Supabase SQL Editor.
-- Idempotent: an item that already exists in a store (same name) is left
-- exactly as it is, so running this twice adds nothing twice and never
-- overwrites a price or stock count staff have set.
--
-- Photos are in the public `menu-images` bucket under seed/ (credits in
-- supabase/seed/images/CREDITS.md). The app never deletes anything under
-- seed/, because several stores can share one photo.
--
-- Store matching is by name, so this works with the hall names as they are
-- in the database ("Buidling 6 Cafeteria", "Building 13 Dinning Hall",
-- "Building 5 Cafeteria (Great Hall)"). If the database has no cafeterias at
-- all, these three are created first.

-- ----------------------------------------------------------------- helpers --
-- pg_temp functions exist only for this session and vanish afterwards.

-- The one place the project URL appears.
create or replace function pg_temp.img(p_file text) returns text
language sql immutable as $$
  select 'https://sotsfjzdbnmrfcdifwmi.supabase.co/storage/v1/object/public/menu-images/seed/'
         || p_file;
$$;

create or replace function pg_temp.store(p_pattern text) returns uuid
language sql stable as $$
  select id from public.cafeterias where name ilike p_pattern order by name limit 1;
$$;

-- Adds an item unless the store already has one with that name. Returns the
-- item either way.
create or replace function pg_temp.item(
  p_store uuid, p_name text, p_category text, p_price_cents integer,
  p_stock integer, p_image text, p_description text default null
) returns uuid
language plpgsql as $$
declare
  v_id uuid;
begin
  if p_store is null then return null; end if;

  select id into v_id from public.menu_items
   where cafeteria_id = p_store and lower(name) = lower(p_name)
   limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.menu_items (
    cafeteria_id, name, category, price_cents, stock_count, is_available,
    image_url, description
  )
  values (
    p_store, p_name, p_category, p_price_cents, p_stock, true,
    pg_temp.img(p_image), p_description
  )
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function pg_temp.variety(
  p_item uuid, p_name text, p_delta_cents integer, p_stock integer, p_order integer
) returns void
language sql as $$
  insert into public.menu_item_variants (menu_item_id, name, price_delta_cents, stock_count, sort_order)
  select p_item, p_name, p_delta_cents, p_stock, p_order
   where p_item is not null
  on conflict (menu_item_id, name) do nothing;
$$;

create or replace function pg_temp.part(
  p_combo uuid, p_part uuid, p_qty integer, p_order integer
) returns void
language sql as $$
  insert into public.combo_components (combo_item_id, component_item_id, quantity, sort_order)
  select p_combo, p_part, p_qty, p_order
   where p_combo is not null and p_part is not null
  on conflict (combo_item_id, component_item_id) do nothing;
$$;

-- One special per item: skipped if the item already has any.
create or replace function pg_temp.special(
  p_item uuid, p_kind text, p_percent integer, p_price_cents integer, p_headline text
) returns void
language sql as $$
  insert into public.menu_specials (menu_item_id, kind, percent_off, special_price_cents, headline)
  select p_item, p_kind, p_percent, p_price_cents, p_headline
   where p_item is not null
     and not exists (select 1 from public.menu_specials s where s.menu_item_id = p_item);
$$;

-- Splits an existing item's stock across new flavours, once: only when the
-- item has no varieties yet. Its own stock then moves onto the varieties.
create or replace function pg_temp.split_into_varieties(
  p_item uuid, p_names text[]
) returns void
language plpgsql as $$
declare
  v_stock integer;
  v_each  integer;
  i       integer;
begin
  if p_item is null or exists (
    select 1 from public.menu_item_variants where menu_item_id = p_item
  ) then
    return;
  end if;

  select greatest(stock_count, array_length(p_names, 1)) into v_stock
    from public.menu_items where id = p_item;
  v_each := v_stock / array_length(p_names, 1);

  for i in 1 .. array_length(p_names, 1) loop
    perform pg_temp.variety(
      p_item, p_names[i], 0,
      -- The first flavour takes the remainder so no unit is lost.
      case when i = 1 then v_stock - v_each * (array_length(p_names, 1) - 1) else v_each end,
      i - 1
    );
  end loop;

  update public.menu_items set stock_count = 0 where id = p_item;
end;
$$;

-- ------------------------------------------------------------------ stores --
do $$
begin
  if not exists (select 1 from public.cafeterias) then
    insert into public.cafeterias (name, is_open) values
      ('Building 5 Cafeteria (Great Hall)', true),
      ('Building 13 Dining Hall', true),
      ('Building 6 Cafeteria', true);
  end if;
end;
$$;

-- Cover photos, only where staff have not set one.
update public.cafeterias set image_url = pg_temp.img('hall_great_hall.jpg')
 where image_url is null and name ilike '%great hall%';
update public.cafeterias set image_url = pg_temp.img('hall_dining_hall.jpg')
 where image_url is null and name ilike '%13%';
update public.cafeterias set image_url = pg_temp.img('hall_cafeteria.jpg')
 where image_url is null and name ilike '%6 cafeteria%';

-- Items that already existed all defaulted to "meal" in 0009. Put the obvious
-- ones on the right tab (only while they are still "meal").
update public.menu_items set category = 'beverage'
 where category = 'meal'
   and (name ilike '%coke%' or name ilike '%red bull%' or name ilike '%coffee%'
        or name ilike '%juice%' or name ilike '%water%' or name ilike '%fanta%'
        or name ilike '%sprite%');
update public.menu_items set category = 'snack'
 where category = 'meal'
   and (name ilike '%doritos%' or name ilike '%lays%' or name ilike '%chips%'
        or name ilike '%cake%' or name ilike '%ice cream%' or name ilike '%muffin%'
        or name ilike '%chocolate%' or name ilike '%biscuit%')
   and name not ilike '%&%chips%';

-- ------------------------------------------- Building 5 (Great Hall): grill --
do $$
declare
  s       uuid := pg_temp.store('%great hall%');
  burger  uuid;
  chips   uuid;
  drink   uuid;
  shake   uuid;
  combo   uuid;
  wors    uuid;
begin
  if s is null then
    s := pg_temp.store('%building 5%');
  end if;
  if s is null then
    raise notice 'Great Hall not found; skipped.';
    return;
  end if;

  perform pg_temp.item(s, 'Cheeseburger & Chips', 'meal', 6500, 30, 'cheeseburger_chips.jpg',
    'Flame-grilled beef patty, cheddar, lettuce and tomato, with a side of chips.');
  wors := pg_temp.item(s, 'Boerewors Roll', 'meal', 3500, 25, 'boerewors_roll.jpg',
    'Grilled boerewors in a soft roll with tomato relish.');
  perform pg_temp.item(s, 'Crumbed Chicken Burger', 'meal', 5200, 25, 'chicken_burger.jpg',
    'Crispy crumbed chicken breast, lettuce, tomato and mayo.');

  chips := pg_temp.item(s, 'Slap Chips', 'snack', 2200, 0, 'slap_chips.jpg',
    'Soft, vinegar-kissed chips. Pick your size.');
  perform pg_temp.variety(chips, 'Small', 0, 40, 0);
  perform pg_temp.variety(chips, 'Regular', 800, 40, 1);
  perform pg_temp.variety(chips, 'Large', 1500, 30, 2);

  drink := pg_temp.item(s, 'Soft Drink 330ml', 'beverage', 1600, 0, 'soft_drinks.jpg',
    'Ice-cold can. Pick your flavour.');
  perform pg_temp.variety(drink, 'Coca-Cola', 0, 48, 0);
  perform pg_temp.variety(drink, 'Coke Zero', 0, 36, 1);
  perform pg_temp.variety(drink, 'Fanta Orange', 0, 30, 2);
  perform pg_temp.variety(drink, 'Sprite', 0, 30, 3);

  shake := pg_temp.item(s, 'Milkshake', 'beverage', 3200, 0, 'milkshake.jpg',
    'Thick and creamy, made to order.');
  perform pg_temp.variety(shake, 'Chocolate', 0, 20, 0);
  perform pg_temp.variety(shake, 'Strawberry', 0, 20, 1);
  perform pg_temp.variety(shake, 'Vanilla', 0, 20, 2);

  -- The combo is built from this store's own items; the student picks the
  -- chip size and the drink.
  select id into burger from public.menu_items
   where cafeteria_id = s and name ilike 'classic beef burger' limit 1;
  if burger is null then
    burger := pg_temp.item(s, 'Classic Beef Burger', 'meal', 4500, 30,
      'cheeseburger_chips.jpg', 'Beef patty, lettuce, tomato and our house sauce.');
  end if;

  combo := pg_temp.item(s, 'Burger Meal Deal', 'combo', 7500, 0, 'combo_burger_meal.jpg',
    'Classic beef burger, slap chips and a cold drink. Save on buying separately.');
  perform pg_temp.part(combo, burger, 1, 0);
  perform pg_temp.part(combo, chips, 1, 1);
  perform pg_temp.part(combo, drink, 1, 2);

  perform pg_temp.special(wors, 'percent', 15, null, 'Braai Day');
end;
$$;

-- ------------------------------------------ Building 13 Dining Hall: kitchen --
do $$
declare
  s      uuid := pg_temp.store('%13%');
  juice  uuid;
  muffin uuid;
  chicken uuid;
  pizza  uuid;
  coke   uuid;
  combo  uuid;
begin
  if s is null then
    raise notice 'Building 13 Dining Hall not found; skipped.';
    return;
  end if;

  perform pg_temp.item(s, 'Pap & Wors', 'meal', 4500, 30, 'pap_wors.jpg',
    'Stiff pap, boerewors and a rich tomato-and-onion gravy.');
  perform pg_temp.item(s, 'Beef Stew & Rice', 'meal', 5500, 25, 'beef_stew_rice.jpg',
    'Slow-cooked beef stew over fluffy white rice.');
  chicken := pg_temp.item(s, 'Fried Chicken (2 pc)', 'meal', 4200, 30, 'fried_chicken.jpg',
    'Two pieces of crispy, golden fried chicken.');
  perform pg_temp.item(s, 'Kota', 'meal', 3800, 30, 'kota.jpg',
    'Quarter loaf with chips, polony, russian, cheese and atchar.');

  juice := pg_temp.item(s, 'Fruit Juice 330ml', 'beverage', 1800, 0, 'orange_juice.jpg',
    '100% fruit juice, chilled.');
  perform pg_temp.variety(juice, 'Orange', 0, 25, 0);
  perform pg_temp.variety(juice, 'Apple', 0, 25, 1);
  perform pg_temp.variety(juice, 'Mango', 0, 25, 2);

  muffin := pg_temp.item(s, 'Muffin', 'snack', 2000, 0, 'muffin.jpg',
    'Baked fresh every morning.');
  perform pg_temp.variety(muffin, 'Blueberry', 0, 15, 0);
  perform pg_temp.variety(muffin, 'Chocolate Chip', 0, 15, 1);
  perform pg_temp.variety(muffin, 'Bran', 0, 15, 2);

  -- The Doritos this hall already sells gain their flavours (the original
  -- request's example): its stock is shared out across them.
  perform pg_temp.split_into_varieties(
    (select id from public.menu_items where cafeteria_id = s and name ilike 'doritos' limit 1),
    array['Sweet Chilli Pepper', 'Cheese Supreme', 'Chilli Heatwave']
  );

  select id into pizza from public.menu_items where cafeteria_id = s and name ilike 'pizza' limit 1;
  select id into coke  from public.menu_items where cafeteria_id = s and name ilike 'coke%' limit 1;
  if pizza is not null and coke is not null then
    combo := pg_temp.item(s, 'Pizza & Coke Combo', 'combo', 4200, 0, 'combo_pizza_coke.jpg',
      'A slice of pizza and an ice-cold Coke.');
    perform pg_temp.part(combo, pizza, 1, 0);
    perform pg_temp.part(combo, coke, 1, 1);
  end if;

  perform pg_temp.special(chicken, 'fixed_price', null, 3500, 'Chicken Tuesday');
end;
$$;

-- --------------------------------------------------- Building 6 Cafeteria: café --
do $$
declare
  s      uuid := pg_temp.store('%6 cafeteria%');
  coffee uuid;
  pastry uuid;
  water  uuid;
  salad  uuid;
  combo  uuid;
begin
  if s is null then
    raise notice 'Building 6 Cafeteria not found; skipped.';
    return;
  end if;

  coffee := pg_temp.item(s, 'Cappuccino', 'beverage', 2800, 0, 'cappuccino.jpg',
    'Double shot of espresso with silky steamed milk.');
  perform pg_temp.variety(coffee, 'Regular', 0, 50, 0);
  perform pg_temp.variety(coffee, 'Large', 600, 40, 1);

  perform pg_temp.item(s, 'Chicken Mayo Sandwich', 'meal', 3200, 25, 'chicken_mayo_sandwich.jpg',
    'Shredded chicken, creamy mayo and crisp lettuce on fresh bread.');
  perform pg_temp.item(s, 'Toasted Cheese & Tomato', 'meal', 2800, 25, 'toasted_cheese.jpg',
    'Golden toasted sandwich with melted cheddar and tomato.');

  pastry := pg_temp.item(s, 'Croissant', 'snack', 2200, 0, 'croissant.jpg',
    'Buttery, flaky and baked in-house.');
  perform pg_temp.variety(pastry, 'Plain', 0, 20, 0);
  perform pg_temp.variety(pastry, 'Chocolate', 500, 15, 1);
  perform pg_temp.variety(pastry, 'Ham & Cheese', 1200, 15, 2);

  salad := pg_temp.item(s, 'Fruit Salad Cup', 'snack', 2500, 20, 'fruit_salad.jpg',
    'Seasonal fruit, freshly cut.');

  water := pg_temp.item(s, 'Bottled Water 500ml', 'beverage', 1200, 0, 'water.jpg',
    'Still or sparkling.');
  perform pg_temp.variety(water, 'Still', 0, 60, 0);
  perform pg_temp.variety(water, 'Sparkling', 300, 30, 1);

  -- The crisps this café already sells gain their flavours.
  perform pg_temp.split_into_varieties(
    (select id from public.menu_items where cafeteria_id = s and name ilike 'lays' limit 1),
    array['Salted', 'Salt & Vinegar', 'Cheese & Onion']
  );

  combo := pg_temp.item(s, 'Coffee & Croissant Combo', 'combo', 4500, 0, 'combo_coffee_croissant.jpg',
    'Any cappuccino with any croissant. Pick your size and filling.');
  perform pg_temp.part(combo, coffee, 1, 0);
  perform pg_temp.part(combo, pastry, 1, 1);

  perform pg_temp.special(coffee, 'percent', 20, null, 'Morning Boost');
  perform pg_temp.special(salad, 'featured', null, null, 'Fresh & Healthy');
end;
$$;

-- --------------------------------------------------------------- summary --
select c.name as store,
       count(m.*) filter (where m.category = 'meal')     as meals,
       count(m.*) filter (where m.category = 'combo')    as combos,
       count(m.*) filter (where m.category = 'beverage') as beverages,
       count(m.*) filter (where m.category = 'snack')    as snacks,
       count(m.*)                                        as total_items
  from public.cafeterias c
  left join public.menu_items m on m.cafeteria_id = c.id
 group by c.name
 order by c.name;
