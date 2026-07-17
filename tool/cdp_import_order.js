const fs = require('fs');

async function main() {
  const [, , port, firstFile, secondFile, output] = process.argv;
  const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  const socket = new WebSocket(targets[0].webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  let nextId = 1;
  const pending = new Map();
  const waiters = new Map();
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const request = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) request.reject(new Error(message.error.message));
      else request.resolve(message.result);
      return;
    }
    const queue = waiters.get(message.method);
    if (queue?.length) queue.shift()(message.params);
  });
  const command = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const nextEvent = (method) => new Promise((resolve) => {
    const queue = waiters.get(method) || [];
    queue.push(resolve);
    waiters.set(method, queue);
  });
  await command('Page.enable');
  await command('DOM.enable');
  await command('Page.setInterceptFileChooserDialog', { enabled: true });
  const chooser = nextEvent('Page.fileChooserOpened');
  await command('Input.dispatchMouseEvent', { type: 'mousePressed', x: 90, y: 952, button: 'left', clickCount: 1 });
  await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x: 90, y: 952, button: 'left', clickCount: 1 });
  const { backendNodeId } = await chooser;
  await command('DOM.setFileInputFiles', { files: [firstFile, secondFile], backendNodeId });
  await new Promise((resolve) => setTimeout(resolve, 1400));
  const screenshot = await command('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
  socket.close();
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
