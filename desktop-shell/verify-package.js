const asar = require('@electron/asar');

const packagePath = process.argv[2];
if (!packagePath) throw new Error('Usage: node verify-package.js <app.asar>');

const index = asar.extractFile(packagePath, 'web/index.html').toString('utf8');
const bootstrap = asar.extractFile(
  packagePath,
  'web/flutter_bootstrap.js',
).toString('utf8');
const main = asar.extractFile(packagePath, 'main.js').toString('utf8');
const result = {
  relativeBase: index.includes('<base href="./">'),
  absoluteBase: index.includes('<base href="/">'),
  relativeCanvasKit: bootstrap.includes("canvasKitBaseUrl: 'canvaskit/'"),
  atomicBackup: main.includes('atomicWriteWithBackup'),
  backupFallback: main.includes('readJsonArtifact'),
};
console.log(JSON.stringify(result));
if (!result.relativeBase || result.absoluteBase || !result.relativeCanvasKit ||
    !result.atomicBackup || !result.backupFallback) {
  process.exitCode = 2;
}
