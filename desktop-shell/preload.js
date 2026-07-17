const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('desktopBridge', {
  saveFile: (request) => ipcRenderer.invoke('desktop:save-file', request),
  openProject: () => ipcRenderer.invoke('desktop:open-project'),
  listProjects: () => ipcRenderer.invoke('desktop:list-projects'),
  createProject: (request) => ipcRenderer.invoke('desktop:create-project', request),
  loadProjectData: (request) => ipcRenderer.invoke('desktop:load-project-data', request),
  saveProjectData: (request) => ipcRenderer.invoke('desktop:save-project-data', request),
  loadProjectEdits: (request) => ipcRenderer.invoke('desktop:load-project-edits', request),
  saveProjectEdits: (request) => ipcRenderer.invoke('desktop:save-project-edits', request),
  deleteProject: (request) => ipcRenderer.invoke('desktop:delete-project', request),
  getSettings: () => ipcRenderer.invoke('desktop:get-settings'),
  saveSettings: (request) => ipcRenderer.invoke('desktop:save-settings', request),
  chooseExportDirectory: () => ipcRenderer.invoke('desktop:choose-export-directory'),
  chooseImageExportDirectory: (request) => ipcRenderer.invoke('desktop:choose-image-export-directory', request),
  exportImageExists: (request) => ipcRenderer.invoke('desktop:export-image-exists', request),
  writeExportImage: (request) => ipcRenderer.invoke('desktop:write-export-image', request),
  checkForUpdates: () => ipcRenderer.invoke('desktop:check-for-updates'),
  getUpdateStatus: () => ipcRenderer.invoke('desktop:get-update-status'),
  installUpdate: () => ipcRenderer.invoke('desktop:install-update'),
  openUpdatePage: () => ipcRenderer.invoke('desktop:open-update-page'),
  platform: process.platform,
});
