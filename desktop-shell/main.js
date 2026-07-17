const { app, BrowserWindow, dialog, ipcMain, shell } = require('electron');
const fs = require('fs/promises');
const path = require('path');

const releasePageUrl = 'https://github.com/2786886095/langbai-manga-caption-studio/releases/latest';
const installUpdateSupported = process.platform === 'win32' && !process.env.PORTABLE_EXECUTABLE_FILE;
let autoUpdater = null;
let updateState = {
  state: 'idle',
  currentVersion: app.getVersion(),
  latestVersion: null,
  progress: 0,
  releaseUrl: releasePageUrl,
  installSupported: installUpdateSupported,
  message: '',
};

function setUpdateState(changes) {
  updateState = { ...updateState, ...changes };
}

async function checkExternalRelease() {
  try {
    const response = await fetch(
      'https://api.github.com/repos/2786886095/langbai-manga-caption-studio/releases/latest',
      { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'langbai-manga-caption-studio' } },
    );
    if (!response.ok) return updateState;
    const release = await response.json();
    const latestVersion = String(release.tag_name || '').replace(/^v/, '');
    const current = app.getVersion().split('.').map(Number);
    const latest = latestVersion.split('.').map(Number);
    let newer = false;
    for (let index = 0; index < Math.max(current.length, latest.length); index++) {
      const currentPart = current[index] || 0;
      const latestPart = latest[index] || 0;
      if (latestPart === currentPart) continue;
      newer = latestPart > currentPart;
      break;
    }
    setUpdateState({
      state: newer ? 'external' : 'upToDate',
      latestVersion,
      releaseUrl: release.html_url || releasePageUrl,
      installSupported: false,
    });
  } catch (error) {
    setUpdateState({ state: 'idle', message: String(error.message || error) });
  }
  return updateState;
}

function configureAutoUpdater() {
  if (!installUpdateSupported) return;
  try {
    ({ autoUpdater } = require('electron-updater'));
    autoUpdater.autoDownload = true;
    autoUpdater.autoInstallOnAppQuit = true;
    autoUpdater.on('checking-for-update', () => setUpdateState({ state: 'checking', progress: 0 }));
    autoUpdater.on('update-available', (info) => setUpdateState({
      state: 'available',
      latestVersion: info.version,
      progress: 0,
    }));
    autoUpdater.on('update-not-available', (info) => setUpdateState({
      state: 'upToDate',
      latestVersion: info.version || app.getVersion(),
      progress: 0,
    }));
    autoUpdater.on('download-progress', (progress) => setUpdateState({
      state: 'downloading',
      progress: Number(progress.percent || 0),
    }));
    autoUpdater.on('update-downloaded', (info) => setUpdateState({
      state: 'downloaded',
      latestVersion: info.version,
      progress: 100,
    }));
    autoUpdater.on('error', (error) => setUpdateState({
      state: 'error',
      message: String(error.message || error),
    }));
  } catch (error) {
    setUpdateState({ state: 'error', message: String(error.message || error) });
  }
}

async function projectDirectory() {
  const directory = path.join(app.getPath('userData'), 'projects');
  await fs.mkdir(directory, { recursive: true });
  return directory;
}

async function readProjectCatalog() {
  try {
    const directory = await projectDirectory();
    return JSON.parse(await fs.readFile(path.join(directory, 'catalog.json'), 'utf8'));
  } catch {
    return [];
  }
}

async function writeProjectCatalog(projects) {
  const directory = await projectDirectory();
  await fs.writeFile(
    path.join(directory, 'catalog.json'),
    JSON.stringify(projects, null, 2),
    'utf8',
  );
}

async function readSettings() {
  try {
    return JSON.parse(
      await fs.readFile(path.join(app.getPath('userData'), 'settings.json'), 'utf8'),
    );
  } catch {
    return {};
  }
}

app.commandLine.appendSwitch('disable-features', 'OutOfBlinkCors');

function createWindow() {
  const window = new BrowserWindow({
    width: 1440,
    height: 1024,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: '#111216',
    title: '浪白漫画字幕工坊 · 本地漫画工作台',
    icon: path.join(__dirname, 'assets', 'app-icon.png'),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: false,
      nodeIntegration: false,
    },
  });
  void window.loadFile(path.join(__dirname, 'web', 'index.html'));
}

ipcMain.handle('desktop:save-file', async (_event, request) => {
  const filters = request.kind === 'project'
    ? [{ name: '气泡字幕工程', extensions: ['bcs.json'] }]
    : request.kind === 'text'
      ? [{ name: '字幕脚本', extensions: ['txt'] }]
      : [{ name: 'ZIP 压缩包', extensions: ['zip'] }];
  const settings = await readSettings();
  const directory = settings.exportDirectory && path.isAbsolute(settings.exportDirectory)
    ? settings.exportDirectory
    : null;
  if (directory && settings.askExportLocation === false) {
    await fs.mkdir(directory, { recursive: true });
    const filePath = path.join(directory, path.basename(request.fileName));
    await fs.writeFile(filePath, Buffer.from(request.base64, 'base64'));
    return filePath;
  }
  const result = await dialog.showSaveDialog({
    title: request.title || '保存文件',
    defaultPath: directory ? path.join(directory, request.fileName) : request.fileName,
    filters,
  });
  if (result.canceled || !result.filePath) return null;
  await fs.writeFile(result.filePath, Buffer.from(request.base64, 'base64'));
  return result.filePath;
});

ipcMain.handle('desktop:open-project', async () => {
  const result = await dialog.showOpenDialog({
    title: '打开气泡字幕工程',
    properties: ['openFile'],
    filters: [{ name: '气泡字幕工程', extensions: ['bcs.json', 'json'] }],
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  const filePath = result.filePaths[0];
  const bytes = await fs.readFile(filePath);
  return {
    name: path.basename(filePath),
    path: filePath,
    base64: bytes.toString('base64'),
  };
});

ipcMain.handle('desktop:list-projects', async () => {
  const projects = await readProjectCatalog();
  projects.sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)));
  return JSON.stringify(projects);
});

ipcMain.handle('desktop:create-project', async (_event, request) => {
  const now = new Date();
  const project = {
    id: `project-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    name: String(request.name),
    updatedAt: now.toISOString(),
    hasData: false,
  };
  await writeProjectCatalog([project, ...(await readProjectCatalog())]);
  return JSON.stringify(project);
});

ipcMain.handle('desktop:load-project-data', async (_event, request) => {
  try {
    const directory = await projectDirectory();
    const bytes = await fs.readFile(path.join(directory, `${request.id}.bcs.json`));
    return bytes.toString('base64');
  } catch {
    return null;
  }
});

ipcMain.handle('desktop:save-project-data', async (_event, request) => {
  const directory = await projectDirectory();
  await fs.writeFile(
    path.join(directory, `${request.id}.bcs.json`),
    Buffer.from(request.base64, 'base64'),
  );
  const previous = (await readProjectCatalog()).find((project) => project.id === request.id);
  const updated = {
    id: String(request.id),
    name: String(request.name),
    updatedAt: new Date().toISOString(),
    hasData: true,
    thumbnailBase64: request.thumbnailBase64 || previous?.thumbnailBase64 || null,
  };
  await writeProjectCatalog([
    updated,
    ...(await readProjectCatalog()).filter((project) => project.id !== request.id),
  ]);
  return 'ok';
});

ipcMain.handle('desktop:load-project-edits', async (_event, request) => {
  try {
    const directory = await projectDirectory();
    const bytes = await fs.readFile(path.join(directory, `${request.id}.edits.json`));
    return bytes.toString('base64');
  } catch {
    return null;
  }
});

ipcMain.handle('desktop:save-project-edits', async (_event, request) => {
  const directory = await projectDirectory();
  await fs.writeFile(
    path.join(directory, `${request.id}.edits.json`),
    Buffer.from(request.base64, 'base64'),
  );
  const previous = (await readProjectCatalog()).find((project) => project.id === request.id);
  const updated = {
    id: String(request.id),
    name: String(request.name),
    updatedAt: new Date().toISOString(),
    hasData: true,
    thumbnailBase64: request.thumbnailBase64 || previous?.thumbnailBase64 || null,
  };
  await writeProjectCatalog([
    updated,
    ...(await readProjectCatalog()).filter((project) => project.id !== request.id),
  ]);
  return 'ok';
});

ipcMain.handle('desktop:delete-project', async (_event, request) => {
  const directory = await projectDirectory();
  await fs.rm(path.join(directory, `${request.id}.bcs.json`), { force: true });
  await fs.rm(path.join(directory, `${request.id}.edits.json`), { force: true });
  await writeProjectCatalog(
    (await readProjectCatalog()).filter((project) => project.id !== request.id),
  );
  return 'ok';
});

ipcMain.handle('desktop:get-settings', async () => JSON.stringify(await readSettings()));

ipcMain.handle('desktop:save-settings', async (_event, request) => {
  await fs.writeFile(
    path.join(app.getPath('userData'), 'settings.json'),
    request.json,
    'utf8',
  );
  return 'ok';
});

ipcMain.handle('desktop:choose-export-directory', async () => {
  const result = await dialog.showOpenDialog({
    title: '选择默认保存目录',
    properties: ['openDirectory', 'createDirectory'],
  });
  return result.canceled ? null : result.filePaths[0];
});

function safeExportTarget(directory, fileName) {
  if (!directory || !path.isAbsolute(directory)) throw new Error('导出目录无效');
  const safeName = path.basename(String(fileName)).replace(/[<>:"/\\|?*]/g, '_');
  return path.join(directory, safeName);
}

ipcMain.handle('desktop:choose-image-export-directory', async (_event, request = {}) => {
  const settings = await readSettings();
  const configured = settings.exportDirectory && path.isAbsolute(settings.exportDirectory)
    ? settings.exportDirectory
    : null;
  if (configured && settings.askExportLocation === false) {
    await fs.mkdir(configured, { recursive: true });
    return configured;
  }
  const initialDirectory = request.initialDirectory && path.isAbsolute(request.initialDirectory)
    ? request.initialDirectory
    : configured;
  const result = await dialog.showOpenDialog({
    title: '选择成图导出文件夹',
    defaultPath: initialDirectory || undefined,
    properties: ['openDirectory', 'createDirectory'],
  });
  return result.canceled ? null : result.filePaths[0];
});

ipcMain.handle('desktop:export-image-exists', async (_event, request) => {
  try {
    await fs.access(safeExportTarget(request.directory, request.fileName));
    return true;
  } catch {
    return false;
  }
});

ipcMain.handle('desktop:write-export-image', async (_event, request) => {
  const target = safeExportTarget(request.directory, request.fileName);
  await fs.mkdir(path.dirname(target), { recursive: true });
  if (!request.overwrite) {
    try {
      await fs.writeFile(target, Buffer.from(request.base64, 'base64'), { flag: 'wx' });
      return target;
    } catch (error) {
      if (error.code === 'EEXIST') throw new Error('目标图片已存在');
      throw error;
    }
  }
  await fs.writeFile(target, Buffer.from(request.base64, 'base64'));
  return target;
});

ipcMain.handle('desktop:check-for-updates', async () => {
  if (!installUpdateSupported || !autoUpdater) {
    return JSON.stringify(await checkExternalRelease());
  }
  setUpdateState({ state: 'checking', message: '', progress: 0 });
  try {
    await autoUpdater.checkForUpdates();
  } catch (error) {
    setUpdateState({ state: 'error', message: String(error.message || error) });
  }
  return JSON.stringify(updateState);
});

ipcMain.handle('desktop:get-update-status', () => JSON.stringify(updateState));

ipcMain.handle('desktop:install-update', () => {
  if (autoUpdater && updateState.state === 'downloaded') {
    setImmediate(() => autoUpdater.quitAndInstall(false, true));
    return 'ok';
  }
  void shell.openExternal(releasePageUrl);
  return 'external';
});

ipcMain.handle('desktop:open-update-page', () => {
  void shell.openExternal(updateState.releaseUrl || releasePageUrl);
  return 'ok';
});

app.whenReady().then(() => {
  configureAutoUpdater();
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
