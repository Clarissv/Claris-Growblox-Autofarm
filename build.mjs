import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const version = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
const windRoot = join(root, '..', 'WindUI');
// Git's Windows checkout settings must not change a release revision or digest.
const readText = path => readFileSync(path, 'utf8').replace(/\r\n/g, '\n');
const core = readText(join(root, 'src/core.lua'));
const main = readText(join(root, 'src/main.lua'));
const navigation = readText(join(root, 'src/navigation.lua'));
const wind = readText(join(windRoot, 'dist/main.lua'));
const license = readText(join(windRoot, 'LICENSE'));
const bundle = main.replace('__CLARIS_CORE__', `(function()\n${core}\nend)()`)
    .replace('__CLARIS_NAV__', `(function()\n${navigation}\nend)()`);
if (/__CLARIS_(CORE|NAV)__/.test(bundle)) throw new Error('Unresolved bundle marker');
const digest = data => createHash('sha256').update(data).digest('hex');
const revision = digest(bundle + '\n' + wind).slice(0, 20);
const repo = 'https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/';
const base = `${repo}releases/${revision}/`;
const checksum = source => {
    let a = 1, b = 0;
    for (const byte of Buffer.from(source, 'utf8')) {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return b * 65536 + a;
};
const loaderValues = {VERSION: version, BASE: base, REPO: repo, REVISION: revision,
    MAIN_SIZE: Buffer.byteLength(bundle), MAIN_CHECKSUM: checksum(bundle),
    WIND_SIZE: Buffer.byteLength(wind), WIND_CHECKSUM: checksum(wind)};
const loader = readText(join(root, 'src/loader.lua')).replace(/__CLARIS_(\w+)__/g, (_, key) => {
    if (!(key in loaderValues)) throw new Error(`Unknown loader marker ${key}`);
    return loaderValues[key];
});
const files = {
    'main.lua': bundle,
    'vendor/WindUI.lua': wind,
    'vendor/WindUI.LICENSE': license,
};
for (const [path, content] of Object.entries(files)) {
    for (const prefix of ['', `releases/${revision}/`]) {
        const target = join(root, prefix, path);
        mkdirSync(dirname(target), { recursive: true });
        if (prefix && existsSync(target) && readFileSync(target, 'utf8') !== content) {
            throw new Error(`Refusing to overwrite immutable release ${target}`);
        }
        writeFileSync(target, content);
    }
}
writeFileSync(join(root, 'loader.lua'), loader);
const manifest = {
    version, revision, base,
    files: Object.fromEntries(Object.entries(files).map(([path, content]) => [path, digest(content)])),
};
writeFileSync(join(root, 'release.json'), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Built v${manifest.version}, revision ${revision}`);
