async function main() {
  const [, , port, xArg, yArg] = process.argv;
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
  const x = Number(xArg);
  const y = Number(yArg);
  await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await new Promise((resolve) => setTimeout(resolve, 180));
  const result = await command('Runtime.evaluate', {
    expression: `(() => {
      const element = document.elementFromPoint(${x}, ${y});
      return JSON.stringify({
        tag: element?.tagName,
        cursor: element ? getComputedStyle(element).cursor : null,
        bodyCursor: getComputedStyle(document.body).cursor
      });
    })()`,
    returnByValue: true,
  });
  process.stdout.write(`${result.result.value}\n`);
  socket.close();
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
