import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './pages_worker.mjs';

for (const host of ['spicyself.com', 'chairside-staging.pages.dev', 'preview.chairside-staging.pages.dev']) {
  test(`${host} redirects to the official origin and preserves callback parameters`, async () => {
    const response = await worker.fetch(new Request(`https://${host}/callback?code=synthetic-test&next=%2Fprofile`), {
      ASSETS: { fetch() { throw Error('Aliases must redirect before serving Flutter'); } },
    });
    assert.equal(response.status, 308);
    assert.equal(response.headers.get('location'), 'https://www.spicyself.com/callback?code=synthetic-test&next=%2Fprofile');
  });
}
test('official domain serves existing assets without a redirect loop', async () => {
  let requested;
  const response = await worker.fetch(new Request('https://www.spicyself.com/main.dart.js'), {
    ASSETS: { fetch(request) { requested = request.url; return new Response('asset'); } },
  });
  assert.equal(requested, 'https://www.spicyself.com/main.dart.js');
  assert.equal(await response.text(), 'asset');
  assert.equal(response.status, 200);
});
test('official HTTP request upgrades to HTTPS', async () => {
  const response = await worker.fetch(new Request('http://www.spicyself.com/'), {});
  assert.equal(response.headers.get('location'), 'https://www.spicyself.com/');
});
