$ErrorActionPreference = 'Stop'
$targets = Invoke-RestMethod 'http://127.0.0.1:9333/json'
$page = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1
if (-not $page) { throw 'No Electron page target' }

$socket = [System.Net.WebSockets.ClientWebSocket]::new()
$socket.ConnectAsync(
  [Uri]$page.webSocketDebuggerUrl,
  [Threading.CancellationToken]::None
).GetAwaiter().GetResult()

$expression = @"
(async()=>{
  const b=window.desktopBridge;
  const id='project-codex-ipc-test';
  const bytes=new Uint8Array([1,2,3,4]);
  await b.saveProjectImage({id,pageId:'page-1',bytes});
  const read=await b.loadProjectImage({id,pageId:'page-1'});
  const manifest=new TextEncoder().encode('{"format":"bubble-caption-studio-manifest","schemaVersion":2,"pages":[]}');
  await b.saveProjectManifest({id,name:'IPC test',bytes:manifest});
  const loaded=await b.loadProjectManifest({id});
  await b.deleteProject({id});
  return JSON.stringify({
    binary:Array.from(read),
    manifestLength:loaded.length,
    hasDownload:typeof b.downloadUpdate==='function',
    hasPicker:typeof b.pickImagePaths==='function'
  });
})()
"@
$request = @{
  id = 1
  method = 'Runtime.evaluate'
  params = @{
    expression = $expression
    awaitPromise = $true
    returnByValue = $true
  }
} | ConvertTo-Json -Depth 6 -Compress
$send = [Text.Encoding]::UTF8.GetBytes($request)
$socket.SendAsync(
  [ArraySegment[byte]]$send,
  [Net.WebSockets.WebSocketMessageType]::Text,
  $true,
  [Threading.CancellationToken]::None
).GetAwaiter().GetResult()
$buffer = New-Object byte[] 65536
$received = $socket.ReceiveAsync(
  [ArraySegment[byte]]$buffer,
  [Threading.CancellationToken]::None
).GetAwaiter().GetResult()
$response = [Text.Encoding]::UTF8.GetString($buffer, 0, $received.Count)
$socket.Dispose()
$response
