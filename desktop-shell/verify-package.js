const asar = require('@electron/asar');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const yaml = require('js-yaml');
const semver = require('semver');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function fileSha512(file) {
  const digest = crypto.createHash('sha512');
  for await (const chunk of fs.createReadStream(file)) digest.update(chunk);
  return digest.digest('base64');
}

async function verify() {
  assert(process.argv[2], 'Usage: node verify-package.js <app.asar> [expected-version]');
  const packagePath = path.resolve(process.argv[2]);
  const resources = path.dirname(packagePath);
  const dist = path.resolve(resources, '..', '..');
  // @electron/asar uses host path separators even for paths inside its archive.
  const extract = (name) => asar.extractFile(packagePath, path.normalize(name));
  const packaged = JSON.parse(extract('package.json').toString('utf8'));
  const version = packaged.version;
  assert(typeof version === 'string' && semver.valid(version) === version,
    'Packaged app version is not a canonical SemVer');
  if (process.argv[3]) {
    assert(version === process.argv[3],
      `Packaged version ${version} does not match validated version ${process.argv[3]}`);
  }

  const index = extract('web/index.html').toString('utf8');
  const bootstrap = extract('web/flutter_bootstrap.js').toString('utf8');
  const main = extract('main.js').toString('utf8');
  const result = {
    version,
    relativeBase: index.includes('<base href="./">'),
    absoluteBase: index.includes('<base href="/">'),
    relativeCanvasKit: bootstrap.includes("canvasKitBaseUrl: 'canvaskit/'"),
    atomicBackup: main.includes('atomicWriteWithBackup'),
    backupFallback: main.includes('readJsonArtifact'),
  };
  assert(result.relativeBase && !result.absoluteBase && result.relativeCanvasKit &&
    result.atomicBackup && result.backupFallback, 'Packaged offline/storage checks failed');

  const fontManifest = JSON.parse(extract('web/assets/assets/fonts/fonts_manifest.json').toString('utf8'));
  assert(Array.isArray(fontManifest.fonts) && fontManifest.fonts.length === 10 &&
    new Set(fontManifest.fonts.map((font) => font.id)).size === 10,
  'Packaged font manifest must contain ten distinct fonts');
  let fontBytes = 0;
  const assetPath = (value) => {
    assert(typeof value === 'string' && value.startsWith('assets/fonts/') &&
      !value.split('/').includes('..'), 'Invalid bundled font resource path');
    return path.posix.join('web', 'assets', value);
  };
  for (const font of fontManifest.fonts) {
    const bytes = extract(assetPath(font.assetPath));
    const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
    assert(bytes.length === font.sizeBytes && sha256 === font.sha256 &&
      font.id === `sha256:${sha256}:face0`, `Packaged font integrity failed: ${font.assetPath}`);
    const license = extract(assetPath(font.licensePath));
    assert(crypto.createHash('sha256').update(license).digest('hex') === font.licenseSha256 &&
      font.license === 'OFL-1.1' && license.toString('utf8').includes('SIL OPEN FONT LICENSE'),
    `Packaged font license integrity failed: ${font.licensePath}`);
    fontBytes += bytes.length;
  }
  Object.assign(result, { bundledFonts: 10, bundledFontBytes: fontBytes, bundledFontLicenses: true });

  const update = yaml.load(fs.readFileSync(path.join(resources, 'app-update.yml'), 'utf8'));
  assert(update && update.provider === 'github' && String(update.owner) === '2786886095' &&
    update.repo === 'langbai-manga-caption-studio', 'Packaged GitHub updater feed is incorrect');
  assert(update.channel == null || update.channel === 'latest', 'Unexpected updater channel');

  const manifestPath = path.join(dist, 'latest.yml');
  const manifest = yaml.load(fs.readFileSync(manifestPath, 'utf8'));
  assert(manifest && manifest.version === version, 'latest.yml version does not match packaged app');
  const installerName = `Langbai-Manga-Caption-Studio-Setup-${version}.exe`;
  assert(manifest.path === installerName, 'latest.yml must reference the versioned Setup, not Portable');
  assert(Array.isArray(manifest.files) && manifest.files.length > 0, 'latest.yml has no files');
  assert(manifest.files.every((file) => file && file.url === installerName),
    'latest.yml files contain an unexpected/Portable download target');
  const fileInfo = manifest.files[0];
  const installerPath = path.join(dist, installerName);
  const size = fs.statSync(installerPath).size;
  assert(Number.isSafeInteger(fileInfo.size) && fileInfo.size === size && size > 0,
    'Setup size differs from latest.yml');
  const sha512 = await fileSha512(installerPath);
  assert(manifest.sha512 === sha512 && fileInfo.sha512 === sha512,
    'Setup SHA512 differs from latest.yml');

  const blockmapPath = `${installerPath}.blockmap`;
  const blockmapBytes = fs.readFileSync(blockmapPath);
  assert(blockmapBytes.length > 0, 'Setup blockmap is empty');
  if (fileInfo.blockMapSize != null) {
    assert(fileInfo.blockMapSize === blockmapBytes.length, 'Setup blockmap size mismatch');
  }
  const blockmap = JSON.parse(zlib.gunzipSync(blockmapBytes).toString('utf8'));
  assert(String(blockmap.version) === '2' && Array.isArray(blockmap.files) &&
    blockmap.files.length > 0, 'Invalid Setup blockmap');
  let end = 0;
  for (const file of blockmap.files) {
    assert(file.offset === end && Array.isArray(file.sizes) &&
      Array.isArray(file.checksums) && file.sizes.length === file.checksums.length &&
      file.sizes.length > 0 && file.sizes.every((n) => Number.isSafeInteger(n) && n > 0),
    'Setup blockmap layout is invalid');
    end += file.sizes.reduce((sum, n) => sum + n, 0);
  }
  assert(end === size, 'Setup blockmap does not describe this installer size');
  Object.assign(result, {
    updaterFeed: true, updaterManifest: true, installerName, installerSize: size,
    installerSha512: sha512, blockmap: true, manifestPath,
  });
  console.log(JSON.stringify(result));
}

verify().catch((error) => {
  console.error(`PACKAGE_VERIFICATION_FAILED: ${error.message}`);
  process.exitCode = 2;
});
