// Demo choreography for https://entitease.vercel.app/ (run with scripts/choreo.sh).
//
// Test plan
//   Goal: show that EntitEase lets you find an HTML entity and copy it in one click.
//   1. Landing view: categories list and entity cards are visible.
//   2. Click the "Dollar Sign" card -> it is copied (card shows its copied state).
//   3. Search "arrow" -> the list filters to arrow entities as you type.
//   4. Click the first result -> copied.
//   5. Clear the search -> the full list returns.
//   6. Open the "Currency" category -> only currency entities are listed.
export default async function (d) {
  const { page } = d;
  const search = page.locator('input').first();
  const cards = page.locator('li.entities-list__item');

  await d.caption('EntitEase: browse HTML entities by category', 900);

  await d.caption('Click a card to copy its entity', 300);
  await d.clickEl(cards.filter({ hasText: 'Dollar Sign' }));
  await d.hold(900);

  await d.caption('Search for an entity', 300);
  await d.clickEl(search);
  await d.type('arrow', 90);
  await d.hold(1100);

  await d.caption('Results filter as you type', 300);
  await d.hoverEl(cards.nth(2));
  await d.hold(500);

  await d.caption('Copy one of the results', 300);
  await d.clickEl(cards.first());
  await d.hold(1000);

  await d.caption('Clear the search to return to categories', 300);
  await d.clickEl(search);
  await d.press('Meta+a');
  await d.press('Backspace');
  await d.hold(900);

  await d.caption('Open the Currency category', 300);
  await d.clickEl(page.locator('li.entities-list__category', { hasText: 'Currency' }));
  await d.hold(1500);

  await d.caption('');
  await d.hold(800);
}
