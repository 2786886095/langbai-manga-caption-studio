const fs = require('fs');

async function main() {
  const [, , port, output, x1Arg, y1Arg, x2Arg, y2Arg] = process.argv;
  const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  const socket = new WebSocket(targets[0].webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, { once: true });
    socket.addEventListener('error', reject, { once: true });
  });
  let nextId = 1;
  const pending = new Map();
  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (!message.id || !pending.has(message.id)) return;
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message));
    else resolve(message.result);
  });
  const command = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
  const [x1, y1, x2, y2] = [x1Arg, y1Arg, x2Arg, y2Arg].map(Number);
  await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x: x1, y: y1 });
  await command('Input.dispatchMouseEvent', {
    type: 'mousePressed', x: x1, y: y1, button: 'left', buttons: 1, clickCount: 1,
  });
  for (let step = 1; step <= 12; step++) {
    const progress = step / 12;
    await command('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: x1 + (x2 - x1) * progress,
      y: y1 + (y2 - y1) * progress,
      button: 'left',
      buttons: 1,
    });
  }
  await command('Input.dispatchMouseEvent', {
    type: 'mouseReleased', x: x2, y: y2, button: 'left', clickCount: 1,
  });
  await new Promise((resolve) => setTimeout(resolve, 250));
  const screenshot = await command('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(output, Buffer.from(screenshot.data, 'base64'));
  socket.close();
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
