const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('../extension/src/core.js');

test('normalizeHref drops tracking params and keeps identifying ones', () => {
  const a = L.normalizeHref('https://www.linkedin.com/feed/update/urn:li:activity:1/?trk=abc&x=1');
  const b = L.normalizeHref('/feed/update/urn:li:activity:1?trk=zzz');
  assert.equal(a, b);
  const j1 = L.normalizeHref('https://www.linkedin.com/jobs/search-results/?keywords=intern&f_TPR=a1794198234-&geoId=1');
  const j2 = L.normalizeHref('https://www.linkedin.com/jobs/search-results/?geoId=1&keywords=intern&f_TPR=a999-');
  assert.equal(j1, j2);
  assert.notEqual(j1, L.normalizeHref('https://www.linkedin.com/jobs/search-results/?keywords=analyst&geoId=1'));
});

test('cardKey separates reactions from comments on the same post', () => {
  const href = 'https://www.linkedin.com/posts/me_share-123/';
  assert.notEqual(
    L.cardKey(href, 'Jordan Lee and 20 others reacted to your post.'),
    L.cardKey(href, 'Alex commented on your post.')
  );
  // Growing reaction counts keep the same key.
  assert.equal(
    L.cardKey(href, 'Jordan Lee and 20 others reacted to your post.'),
    L.cardKey(href, 'Sam Rivera and 21 others reacted to your post.')
  );
});

test('fresh install: everything registers as unread', () => {
  const { data, added } = L.register(L.emptyData(), ['a', 'b', 'c'], 1);
  assert.equal(added, 3);
  assert.equal(L.unreadCount(data), 3);
});

test('after mark-all-read, newer items are unread but older scrolled-in items are read', () => {
  let d = L.register(L.emptyData(), ['b', 'c'], 1).data;
  d = L.markAllRead(d);
  assert.equal(L.unreadCount(d), 0);
  // 'a' is new at the top; 'z' loads below known items when scrolling.
  d = L.register(d, ['a', 'b', 'c', 'z'], 2).data;
  assert.ok(L.isUnread(d, 'a'));
  assert.ok(!L.isUnread(d, 'z'));
});

test('mark all read except selected keeps the selection unread and flagged', () => {
  let d = L.register(L.emptyData(), ['a', 'b', 'c', 'd'], 1).data;
  d = L.markAllReadExcept(d, ['b', 'd']);
  assert.deepEqual(['a', 'b', 'c', 'd'].filter((k) => L.isUnread(d, k)), ['b', 'd']);
  assert.ok(L.isKept(d, 'b') && L.isKept(d, 'd'));
  assert.ok(d.baseline);
});

test('mark selected read / unread', () => {
  let d = L.register(L.emptyData(), ['a', 'b', 'c'], 1).data;
  d = L.markAllRead(d);
  d = L.markUnread(d, ['a', 'c']);
  assert.equal(L.unreadCount(d), 2);
  assert.ok(L.isKept(d, 'a'));
  d = L.markRead(d, ['a']);
  assert.ok(!L.isUnread(d, 'a') && !L.isKept(d, 'a'));
  assert.equal(L.unreadCount(d), 1);
});

test('mark all unread affects the given (loaded) keys, not kept', () => {
  let d = L.markAllRead(L.register(L.emptyData(), ['a', 'b'], 1).data);
  d = L.markAllUnread(d, ['a', 'b']);
  assert.equal(L.unreadCount(d), 2);
  assert.ok(!L.isKept(d, 'a'));
});

test('operations do not mutate their input (undo relies on this)', () => {
  const d0 = L.register(L.emptyData(), ['a', 'b'], 1).data;
  const snapshot = JSON.stringify(d0);
  L.markAllRead(d0);
  L.markUnread(d0, ['a']);
  L.markAllReadExcept(d0, ['b']);
  assert.equal(JSON.stringify(d0), snapshot);
});

test('prune drops old read entries but never unread or on-screen ones', () => {
  const old = 0;
  const now = 200 * 24 * 60 * 60 * 1000;
  let d = L.register(L.emptyData(), ['a', 'b', 'c'], old).data;
  d = L.markRead(d, ['a', 'b']);
  d = L.prune(d, now, ['b']);
  assert.ok(!d.items.a);
  assert.ok(d.items.b);
  assert.ok(d.items.c);
});

test('rangeBetween selects inclusive ranges in either direction', () => {
  const order = ['a', 'b', 'c', 'd'];
  assert.deepEqual(L.rangeBetween(order, 'b', 'd'), ['b', 'c', 'd']);
  assert.deepEqual(L.rangeBetween(order, 'd', 'b'), ['b', 'c', 'd']);
});

test('sanitize recovers from bad storage', () => {
  assert.deepEqual(L.sanitize(null), L.emptyData());
  assert.deepEqual(L.sanitize({ foo: 1 }), L.emptyData());
});
