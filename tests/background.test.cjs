const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../src/background.js'), 'utf8');

function worker({ missingReceiver = false, injectionError = null } = {}) {
  const calls = [];
  let onClick;
  let messages = 0;
  const record = (method) => async (details) => { calls.push({ method, details }); };
  const chrome = {
    action: {
      onClicked: { addListener: (listener) => { onClick = listener; } },
      setBadgeText: record('badge'),
      setBadgeBackgroundColor: record('badgeColor'),
      setTitle: record('title')
    },
    runtime: { onMessage: { addListener() {} } },
    tabs: {
      sendMessage: async (tabId, message) => {
        calls.push({ method: 'message', tabId, message });
        if (missingReceiver && messages++ === 0) throw new Error('Receiving end does not exist');
      }
    },
    scripting: {
      insertCSS: async (details) => {
        calls.push({ method: 'css', details });
        if (injectionError) throw new Error(injectionError);
      },
      executeScript: record('script')
    }
  };
  vm.runInNewContext(source, { chrome, URL, console, setTimeout });
  return { click: (tab) => onClick(tab), calls };
}

test('Chrome internal pages and the Web Store show guidance without injecting', async () => {
  for (const url of ['chrome://extensions/', 'chrome://newtab/',
    'https://chromewebstore.google.com/detail/example', 'https://chrome.google.com/webstore/detail/example']) {
    const app = worker({ missingReceiver: true, injectionError: 'Cannot access a chrome:// URL' });
    await app.click({ id: 7, url });
    assert.equal(app.calls.some(({ method }) => ['message', 'css', 'script'].includes(method)), false);
    assert.ok(app.calls.some(({ method, details }) => method === 'badge' && details.text === '!'));
    assert.ok(app.calls.some(({ method, details }) => method === 'title' && /regular website/i.test(details.title)));
  }
});

test('an existing overlay toggles without reinjection', async () => {
  const app = worker();
  await app.click({ id: 7, url: 'https://example.com/' });
  assert.equal(app.calls.filter(({ method }) => method === 'message').length, 1);
  assert.equal(app.calls.some(({ method }) => ['css', 'script'].includes(method)), false);
});

test('a fresh page receives the CSS and script before retrying the toggle', async () => {
  const app = worker({ missingReceiver: true });
  await app.click({ id: 7, url: 'https://example.com/' });
  assert.deepEqual(app.calls.filter(({ method }) => ['message', 'css', 'script'].includes(method))
    .map(({ method }) => method), ['message', 'css', 'script', 'message']);
  const injection = app.calls.find(({ method }) => method === 'script');
  assert.deepEqual(Array.from(injection.details.files), ['src/stroke-renderer.js', 'src/content.js']);
});

test('a denied injection is reported without rejecting the click handler', async () => {
  const app = worker({ missingReceiver: true, injectionError: 'Site access is disabled' });
  await app.click({ id: 7, url: 'https://example.com/' });
  assert.ok(app.calls.some(({ method, details }) => method === 'title' && /Site access is disabled/.test(details.title)));
  assert.ok(app.calls.some(({ method, details }) => method === 'badge' && details.text === '!'));
});
