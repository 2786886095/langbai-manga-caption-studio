const { app, BrowserWindow, dialog, ipcMain, shell } = require('electron');
const fs = require('fs/promises');
const path = require('path');

const releasePageUrl = 'https://github.com/2786886095/langbai-manga-caption-studio/releases/latest';
const installUpdateSupported = process.platform === 'win32' && !process.env.PORTABLE_EXECUTABLE_FILE;
let autoUpdater = null;
const approvedImagePaths = new Set();
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
    // Checking stays cheap; the installer downloads only after user consent.
    autoUpdater.autoDownload = false;
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
  const directory = await projectDirectory();
  const catalogPath = path.join(directory, 'catalog.json');
  for (const candidate of [catalogPath, `${catalogPath}.bak`]) {
    try {
      return JSON.parse(await fs.readFile(candidate, 'utf8'));
    } catch {
      // Try the previous complete generation before returning an empty hub.
    }
  }
  return [];
}

async function writeProjectCatalog(projects) {
  const directory = await projectDirectory();
  await atomicWriteWithBackup(
    path.join(directory, 'catalog.json'),
    Buffer.from(JSON.stringify(projects, null, 2), 'utf8'),
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

const desktopTranslations = {
  en: {
    appTitle: 'Langbai Manga Caption Studio · Local workspace',
    projectFiles: 'Caption projects',
    captionScripts: 'Caption scripts',
    archives: 'ZIP archives',
    saveFile: 'Save file',
    openProject: 'Open caption project',
    selectImages: 'Select manga images',
    images: 'Images',
    chooseDefaultFolder: 'Choose default save folder',
    chooseExportFolder: 'Choose image export folder',
  },
  ja: {
    appTitle: '浪白漫画字幕工房 · ローカルワークスペース',
    projectFiles: '字幕プロジェクト',
    captionScripts: '字幕スクリプト',
    archives: 'ZIP アーカイブ',
    saveFile: 'ファイルを保存',
    openProject: '字幕プロジェクトを開く',
    selectImages: '漫画画像を選択',
    images: '画像',
    chooseDefaultFolder: '既定の保存フォルダーを選択',
    chooseExportFolder: '画像の書き出し先を選択',
  },
  ko: {
    appTitle: '랑바이 만화 자막 공방 · 로컬 작업 공간',
    projectFiles: '자막 프로젝트',
    captionScripts: '자막 스크립트',
    archives: 'ZIP 압축 파일',
    saveFile: '파일 저장',
    openProject: '자막 프로젝트 열기',
    selectImages: '만화 이미지 선택',
    images: '이미지',
    chooseDefaultFolder: '기본 저장 폴더 선택',
    chooseExportFolder: '이미지 내보내기 폴더 선택',
  },
  zh_TW: {
    appTitle: '浪白漫畫字幕工坊 · 本機工作區',
    projectFiles: '氣泡字幕工程',
    captionScripts: '字幕腳本',
    archives: 'ZIP 壓縮檔',
    saveFile: '儲存檔案',
    openProject: '開啟氣泡字幕工程',
    selectImages: '選擇漫畫圖片',
    images: '圖片',
    chooseDefaultFolder: '選擇預設儲存資料夾',
    chooseExportFolder: '選擇成圖匯出資料夾',
  },
};

const desktopChinese = {
  appTitle: '浪白漫画字幕工坊 · 本地漫画工作台',
  projectFiles: '气泡字幕工程',
  captionScripts: '字幕脚本',
  archives: 'ZIP 压缩包',
  saveFile: '保存文件',
  openProject: '打开气泡字幕工程',
  selectImages: '选择漫画图片',
  images: '图片',
  chooseDefaultFolder: '选择默认保存目录',
  chooseExportFolder: '选择成图导出文件夹',
};

async function desktopTranslator(settings = null) {
  const current = settings || await readSettings();
  const messages = desktopTranslations[current.languageCode] || desktopChinese;
  return (key) => messages[key] || desktopChinese[key] || key;
}

app.commandLine.appendSwitch('disable-features', 'OutOfBlinkCors');

function requestBuffer(request) {
  if (request && request.bytes) return Buffer.from(request.bytes);
  return Buffer.from(request.base64 || '', 'base64');
}

async function atomicWriteWithBackup(filePath, bytes) {
  const temporaryPath = `${filePath}.tmp-${process.pid}-${Date.now()}`;
  await fs.writeFile(temporaryPath, bytes);
  try {
    try {
      await fs.copyFile(filePath, `${filePath}.bak`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    await fs.rename(temporaryPath, filePath);
  } catch (error) {
    await fs.rm(temporaryPath, { force: true });
    throw error;
  }
}

async function readJsonArtifact(filePath, expectedFormat) {
  for (const candidate of [filePath, `${filePath}.bak`]) {
    try {
      const bytes = await fs.readFile(candidate);
      const parsed = JSON.parse(bytes.toString('utf8'));
      if (parsed && parsed.format === expectedFormat) return bytes;
    } catch {
      // Fall through to the previous complete generation.
    }
  }
  return null;
}

function storageName(value) {
  return String(value || '').replace(/[^A-Za-z0-9_.-]/g, '_');
}

async function createWindow() {
  const t = await desktopTranslator();
  const window = new BrowserWindow({
    width: 1440,
    height: 1024,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: '#111216',
    title: t('appTitle'),
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
  const settings = await readSettings();
  const t = await desktopTranslator(settings);
  const filters = request.kind === 'project'
    ? [{ name: t('projectFiles'), extensions: ['bcs.json'] }]
    : request.kind === 'text'
      ? [{ name: t('captionScripts'), extensions: ['txt'] }]
      : [{ name: t('archives'), extensions: ['zip'] }];
  const directory = settings.exportDirectory && path.isAbsolute(settings.exportDirectory)
    ? settings.exportDirectory
    : null;
  if (directory && settings.askExportLocation === false) {
    await fs.mkdir(directory, { recursive: true });
    const filePath = path.join(directory, path.basename(request.fileName));
    await fs.writeFile(filePath, requestBuffer(request));
    return filePath;
  }
  const result = await dialog.showSaveDialog({
    title: request.title || t('saveFile'),
    defaultPath: directory ? path.join(directory, request.fileName) : request.fileName,
    filters,
  });
  if (result.canceled || !result.filePath) return null;
  await fs.writeFile(result.filePath, requestBuffer(request));
  return result.filePath;
});

ipcMain.handle('desktop:open-project', async () => {
  const t = await desktopTranslator();
  const result = await dialog.showOpenDialog({
    title: t('openProject'),
    properties: ['openFile'],
    filters: [{ name: t('projectFiles'), extensions: ['bcs.json', 'json'] }],
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  const filePath = result.filePaths[0];
  const bytes = await fs.readFile(filePath);
  return {
    name: path.basename(filePath),
    path: filePath,
    bytes: new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength),
  };
});

ipcMain.handle('desktop:pick-image-paths', async () => {
  const t = await desktopTranslator();
  const result = await dialog.showOpenDialog({
    title: t('selectImages'),
    properties: ['openFile', 'multiSelections'],
    filters: [{ name: t('images'), extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'] }],
  });
  if (result.canceled) return null;
  for (const filePath of result.filePaths) approvedImagePaths.add(path.resolve(filePath));
  return JSON.stringify(result.filePaths.map((filePath) => ({
    name: path.basename(filePath),
    path: filePath,
  })));
});

ipcMain.handle('desktop:read-image-file', async (_event, request) => {
  const filePath = path.resolve(String(request.path || ''));
  if (!approvedImagePaths.has(filePath)) throw new Error('图片路径未经用户选择');
  const bytes = await fs.readFile(filePath);
  approvedImagePaths.delete(filePath);
  return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
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
  const directory = await projectDirectory();
  const bytes = await readJsonArtifact(
    path.join(directory, `${request.id}.bcs.json`),
    'bubble-caption-studio',
  );
  return bytes == null
    ? null
    : new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
});

ipcMain.handle('desktop:load-project-manifest', async (_event, request) => {
  const directory = await projectDirectory();
  const bytes = await readJsonArtifact(
    path.join(directory, storageName(request.id), 'manifest.json'),
    'bubble-caption-studio-manifest',
  );
  return bytes == null
    ? null
    : new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
});

ipcMain.handle('desktop:load-project-image', async (_event, request) => {
  const directory = await projectDirectory();
  const bytes = await fs.readFile(
    path.join(
      directory,
      storageName(request.id),
      'images',
      `${storageName(request.pageId)}.bin`,
    ),
  );
  return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
});

ipcMain.handle('desktop:save-project-image', async (_event, request) => {
  const directory = await projectDirectory();
  const imageDirectory = path.join(directory, storageName(request.id), 'images');
  await fs.mkdir(imageDirectory, { recursive: true });
  await fs.writeFile(
    path.join(imageDirectory, `${storageName(request.pageId)}.bin`),
    requestBuffer(request),
  );
  return 'ok';
});

ipcMain.handle('desktop:save-project-manifest', async (_event, request) => {
  const directory = await projectDirectory();
  const projectPath = path.join(directory, storageName(request.id));
  await fs.mkdir(projectPath, { recursive: true });
  await atomicWriteWithBackup(
    path.join(projectPath, 'manifest.json'),
    requestBuffer(request),
  );
  // A successful manifest write completes legacy migration; remove the huge packed copy.
  await fs.rm(path.join(directory, `${request.id}.bcs.json`), { force: true });
  const catalog = await readProjectCatalog();
  const previous = catalog.find((project) => project.id === request.id);
  const updated = {
    id: String(request.id),
    name: String(request.name),
    updatedAt: new Date().toISOString(),
    hasData: true,
    thumbnailBase64: request.thumbnailBase64 || previous?.thumbnailBase64 || null,
  };
  await writeProjectCatalog([
    updated,
    ...catalog.filter((project) => project.id !== request.id),
  ]);
  return 'ok';
});

ipcMain.handle('desktop:save-project-data', async (_event, request) => {
  const directory = await projectDirectory();
  await atomicWriteWithBackup(
    path.join(directory, `${request.id}.bcs.json`),
    requestBuffer(request),
  );
  const catalog = await readProjectCatalog();
  const previous = catalog.find((project) => project.id === request.id);
  const updated = {
    id: String(request.id),
    name: String(request.name),
    updatedAt: new Date().toISOString(),
    hasData: true,
    thumbnailBase64: request.thumbnailBase64 || previous?.thumbnailBase64 || null,
  };
  await writeProjectCatalog([
    updated,
    ...catalog.filter((project) => project.id !== request.id),
  ]);
  return 'ok';
});

ipcMain.handle('desktop:load-project-edits', async (_event, request) => {
  const directory = await projectDirectory();
  const bytes = await readJsonArtifact(
    path.join(directory, `${request.id}.edits.json`),
    'bubble-caption-studio-edits',
  );
  return bytes == null
    ? null
    : new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
});

ipcMain.handle('desktop:save-project-edits', async (_event, request) => {
  const directory = await projectDirectory();
  await atomicWriteWithBackup(
    path.join(directory, `${request.id}.edits.json`),
    requestBuffer(request),
  );
  const catalog = await readProjectCatalog();
  const previous = catalog.find((project) => project.id === request.id);
  const updated = {
    id: String(request.id),
    name: String(request.name),
    updatedAt: new Date().toISOString(),
    hasData: true,
    thumbnailBase64: request.thumbnailBase64 || previous?.thumbnailBase64 || null,
  };
  await writeProjectCatalog([
    updated,
    ...catalog.filter((project) => project.id !== request.id),
  ]);
  return 'ok';
});

ipcMain.handle('desktop:delete-project', async (_event, request) => {
  const directory = await projectDirectory();
  await fs.rm(path.join(directory, `${request.id}.bcs.json`), { force: true });
  await fs.rm(path.join(directory, `${request.id}.bcs.json.bak`), { force: true });
  await fs.rm(path.join(directory, `${request.id}.edits.json`), { force: true });
  await fs.rm(path.join(directory, `${request.id}.edits.json.bak`), { force: true });
  await fs.rm(path.join(directory, storageName(request.id)), { recursive: true, force: true });
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
  const t = await desktopTranslator();
  const result = await dialog.showOpenDialog({
    title: t('chooseDefaultFolder'),
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
  const t = await desktopTranslator(settings);
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
    title: t('chooseExportFolder'),
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
      await fs.writeFile(target, requestBuffer(request), { flag: 'wx' });
      return target;
    } catch (error) {
      if (error.code === 'EEXIST') throw new Error('目标图片已存在');
      throw error;
    }
  }
  await fs.writeFile(target, requestBuffer(request));
  return target;
});

ipcMain.handle('desktop:check-for-updates', async () => {
  if (!installUpdateSupported) {
    return JSON.stringify(await checkExternalRelease());
  }
  if (!autoUpdater) return JSON.stringify(updateState);
  setUpdateState({ state: 'checking', message: '', progress: 0 });
  try {
    await autoUpdater.checkForUpdates();
  } catch (error) {
    setUpdateState({ state: 'error', message: String(error.message || error) });
  }
  return JSON.stringify(updateState);
});

ipcMain.handle('desktop:get-update-status', () => JSON.stringify(updateState));

ipcMain.handle('desktop:download-update', () => {
  if (!installUpdateSupported || !autoUpdater || updateState.state !== 'available') {
    return JSON.stringify(updateState);
  }
  setUpdateState({ state: 'downloading', message: '', progress: 0 });
  void autoUpdater.downloadUpdate();
  return JSON.stringify(updateState);
});

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
  void createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) void createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
