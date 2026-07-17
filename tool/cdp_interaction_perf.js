async function main() {
  const port = process.argv[2];
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
  const points = [
    [1112, 480], [1170, 480], [1228, 480], [1285, 480], [1343, 480],
    [430, 958], [504, 958], [430, 958], [504, 958],
  ];
  const samples = [];
  for (const [x, y] of points) {
    const started = performance.now();
    await command('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    await command('Runtime.evaluate', {
      expression: 'new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))',
      awaitPromise: true,
      returnByValue: true,
    });
    samples.push(Math.round(performance.now() - started));
  }
  const sorted = [...samples].sort((a, b) => a - b);
  process.stdout.write(JSON.stringify({
    samplesMs: samples,
    medianMs: sorted[Math.floor(sorted.length / 2)],
    maxMs: Math.max(...samples),
  }, null, 2));
  socket.close();
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
