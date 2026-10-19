// Service worker: overlay toggling, screen capture, screenshots, saving.
// It has no DOM, so MediaRecorder work is delegated to an offscreen document.

const OFFSCREEN_PATH = 'src/offscreen.html';
const ACTION_TITLE = 'Toggle Magic Pen (draw on this page)';
const UNSUPPORTED_PAGE_MESSAGE = 'Open a regular website, then click Magic Pen. Chrome pages and the Chrome Web Store cannot be annotated.';

function pageRestriction(url) {
  try {
    const page = new URL(url);
    const supportedProtocol = ['http:', 'https:', 'file:'].includes(page.protocol);
    const isWebStore = page.hostname === 'chromewebstore.google.com'
      || (page.hostname === 'chrome.google.com'
        && (page.pathname === '/webstore' || page.pathname.startsWith('/webstore/')));
    return supportedProtocol && !isWebStore ? null : UNSUPPORTED_PAGE_MESSAGE;
  } catch {
    return UNSUPPORTED_PAGE_MESSAGE;
  }
}

async function setActionStatus(tabId, message = '') {
  await Promise.all([
    chrome.action.setBadgeText({ tabId, text: message ? '!' : '' }),
    chrome.action.setBadgeBackgroundColor({ tabId, color: '#b45309' }),
    chrome.action.setTitle({ tabId, title: message ? `Magic Pen: ${message}` : ACTION_TITLE })
  ]);
}

// --- toolbar button toggles the on-page overlay -----------------------------
chrome.action.onClicked.addListener(async (tab) => {
  if (!Number.isInteger(tab.id) || tab.id < 0) return;
  try {
    const restriction = pageRestriction(tab.url);
    if (restriction) {
      await setActionStatus(tab.id, restriction);
      return;
    }
    await setActionStatus(tab.id);
    try {
      await chrome.tabs.sendMessage(tab.id, { type: 'ANNOTATOR_TOGGLE' });
    } catch {
      await chrome.scripting.insertCSS({ target: { tabId: tab.id }, files: ['src/content.css'] });
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ['src/stroke-renderer.js', 'src/content.js'] });
      await chrome.tabs.sendMessage(tab.id, { type: 'ANNOTATOR_TOGGLE' });
    }
  } catch (error) {
    const message = `Could not start drawing: ${error.message || error}. Refresh the page and check site access.`;
    try {
      await setActionStatus(tab.id, message);
    } catch (statusError) {
      console.error('Magic Pen could not display its launch status:', statusError);
    }
  }
});

// --- offscreen document lifecycle -------------------------------------------
async function hasOffscreen() {
  const ctx = await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] });
  return ctx.length > 0;
}

// THE BUG THAT BROKE RECORDING BEFORE:
// createDocument() resolves as soon as the document exists, which is BEFORE its
// script has run and registered an onMessage listener. Posting OFFSCREEN_START
// right away meant the message hit nobody and vanished. So we now hand-shake:
// ping until the offscreen page answers, and only then send real work.
async function ensureOffscreenReady() {
  if (!(await hasOffscreen())) {
    await chrome.offscreen.createDocument({
      url: OFFSCREEN_PATH,
      reasons: ['USER_MEDIA'],
      justification: 'Record the screen with MediaRecorder, which needs a DOM.'
    });
  }
  for (let i = 0; i < 50; i++) {           // ~5s worst case
    try {
      const pong = await chrome.runtime.sendMessage({ type: 'OFFSCREEN_PING' });
      if (pong && pong.ready) return true;
    } catch { /* listener not up yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error('Recorder page never became ready');
}

// --- messages ----------------------------------------------------------------
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  switch (msg.type) {
    case 'START_RECORDING':
      startRecording(sender.tab).then(sendResponse);
      return true;
    case 'STOP_RECORDING':
      stopRecording().then(sendResponse);
      return true;
    case 'CAPTURE_TAB':
      captureTab(sender.tab).then(sendResponse);
      return true;
    case 'SAVE_IMAGE':
      saveDataUrl(msg.dataUrl).then(sendResponse);
      return true;
    case 'RECORDING_READY':      // from offscreen
      saveRecording(msg.url);
      return false;
    case 'RECORDING_ERROR':      // from offscreen
      notifyTabs({ type: 'ANNOTATOR_RECORDING_STATE', recording: false, error: msg.error });
      return false;
    default:
      return false;
  }
});

// --- recording ---------------------------------------------------------------
async function startRecording(tab) {
  try {
    // Get the recorder page up and confirmed BEFORE showing the picker, so the
    // stream id is never handed to a page that cannot receive it.
    await ensureOffscreenReady();

    const streamId = await new Promise((resolve, reject) => {
      chrome.desktopCapture.chooseDesktopMedia(['screen', 'window', 'tab'], tab, (id) => {
        if (chrome.runtime.lastError) return reject(new Error(chrome.runtime.lastError.message));
        if (!id) return reject(new Error('Capture cancelled'));
        resolve(id);
      });
    });

    // Offscreen replies only once getUserMedia + MediaRecorder actually started,
    // so a failure surfaces here instead of silently doing nothing.
    const res = await chrome.runtime.sendMessage({ type: 'OFFSCREEN_START', streamId });
    if (!res || !res.ok) throw new Error((res && res.error) || 'Recorder did not start');
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
}

async function stopRecording() {
  try {
    await chrome.runtime.sendMessage({ type: 'OFFSCREEN_STOP' });
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
}

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
}

function saveRecording(blobUrl) {
  chrome.downloads.download(
    { url: blobUrl, filename: `annotator/recording-${stamp()}.webm`, saveAs: true },
    (downloadId) => {
      notifyTabs({ type: 'ANNOTATOR_RECORDING_STATE', recording: false, saved: true });
      if (downloadId === undefined) return;
      // The callback fires when the download STARTS. Closing the offscreen
      // document now would revoke the blob URL mid-write, so wait for the end.
      const done = (delta) => {
        if (delta.id !== downloadId || !delta.state) return;
        if (delta.state.current === 'in_progress') return;
        chrome.downloads.onChanged.removeListener(done);
        chrome.offscreen.closeDocument().catch(() => {});
      };
      chrome.downloads.onChanged.addListener(done);
    }
  );
}

// --- screenshots --------------------------------------------------------------
async function captureTab(tab) {
  try {
    const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, {
      format: 'png'
    });
    return { ok: true, dataUrl };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
}

async function saveDataUrl(dataUrl) {
  try {
    await chrome.downloads.download({
      url: dataUrl,
      filename: `annotator/screenshot-${stamp()}.png`,
      saveAs: true
    });
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err.message || err) };
  }
}

async function notifyTabs(message) {
  const tabs = await chrome.tabs.query({});
  for (const t of tabs) {
    if (t.id) chrome.tabs.sendMessage(t.id, message).catch(() => {});
  }
}
