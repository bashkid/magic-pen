// Offscreen document: an invisible DOM page whose only job is MediaRecorder,
// which the MV3 service worker cannot run itself.

let recorder = null;
let chunks = [];

// Pick the best container this Chrome actually supports rather than assuming
// vp9 — an unsupported mimeType makes the MediaRecorder constructor throw.
function pickMime() {
  const candidates = [
    'video/webm;codecs=vp9',
    'video/webm;codecs=vp8',
    'video/webm'
  ];
  return candidates.find((t) => MediaRecorder.isTypeSupported(t)) || '';
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'OFFSCREEN_PING') {
    sendResponse({ ready: true });
    return false;
  }
  if (msg.type === 'OFFSCREEN_START') {
    // Reply only after recording genuinely began, so the caller learns of
    // failures instead of assuming success.
    start(msg.streamId).then(sendResponse);
    return true;
  }
  if (msg.type === 'OFFSCREEN_STOP') {
    stop();
    sendResponse({ ok: true });
    return false;
  }
  return false;
});

async function start(streamId) {
  try {
    if (recorder) return { ok: false, error: 'Already recording' };

    // The legacy `mandatory` constraint form is what pairs with a
    // desktopCapture stream id. This is NOT getDisplayMedia().
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {
        mandatory: {
          chromeMediaSource: 'desktop',
          chromeMediaSourceId: streamId
        }
      }
    });

    const mimeType = pickMime();
    chunks = [];
    recorder = mimeType ? new MediaRecorder(stream, { mimeType }) : new MediaRecorder(stream);

    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) chunks.push(e.data);
    };

    recorder.onerror = (e) => {
      chrome.runtime.sendMessage({
        type: 'RECORDING_ERROR',
        error: 'Recorder error: ' + String((e.error && e.error.name) || e)
      });
    };

    recorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop());
      const blob = new Blob(chunks, { type: mimeType || 'video/webm' });
      chunks = [];
      recorder = null;
      if (blob.size === 0) {
        chrome.runtime.sendMessage({ type: 'RECORDING_ERROR', error: 'Empty recording' });
        return;
      }
      chrome.runtime.sendMessage({
        type: 'RECORDING_READY',
        url: URL.createObjectURL(blob)
      });
    };

    // If the user stops sharing from Chrome's own bar, finish cleanly.
    stream.getVideoTracks()[0].addEventListener('ended', stop);

    recorder.start(1000); // flush a chunk every second
    return { ok: true, mimeType };
  } catch (err) {
    recorder = null;
    return { ok: false, error: String(err.message || err) };
  }
}

function stop() {
  if (recorder && recorder.state !== 'inactive') recorder.stop();
}
