const fs = require('fs');

async function main() {
  const [, , port, firstFile, secondFile, output] = process.argv;
  if (!port || !firstFile || !secondFile || !output) {
    throw new Error('Usage: node cdp_import_twice.js <port> <first> <second> <output>');
  }
  const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  const socket = new WebSocket(targets[0].webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });

  let nextId = 1;
  const pending = new Map();
  const eventWaiters = new Map();
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result);
      return;
    }
    const waiters = eventWaiters.get(message.method);
    if (waiters?.length) waiters.shift()(message.params);
  });
  const command = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const nextEvent = (method) => new Promise((resolve) => {
    const waiters = eventWaiters.get(method) || [];
    waiters.push(resolve);
    eventWaiters.set(method, waiters);
  });
  const click = async (x, y) => {
    await command('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  };
  const importFile = async (file) => {
    const chooser = nextEvent('Page.fileChooserOpened');
    await click(62, 883);
    const { backendNodeId } = await chooser;
    await command('DOM.setFileInputFiles', { files: [file], backendNodeId });
    await new Promise((resolve) => setTimeout(resolve, 1200));
  };

  await command('Page.enable');
  await command('DOM.enable');
  await command('Page.setInterceptFileChooserDialog', { enabled: true });
  await importFile(firstFile);
  await importFile(secondFile);
  const screenshot = await command('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
  socket.close();
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
