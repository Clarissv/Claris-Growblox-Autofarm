import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(readFileSync(join(root, 'release.json'), 'utf8'));
const read = name => readFileSync(join(root, name), 'utf8').replace(/\r\n/g, '\n');
const hash = text => createHash('sha256').update(text).digest('hex');

test('loader selects a complete immutable release for the agreed GitHub repository', () => {
    const loader = read('loader.lua');
    assert.match(manifest.revision, /^[a-f0-9]{20}$/);
    assert.equal(manifest.base, `https://raw.githubusercontent.com/Clarissv/Claris-Growblox-Autofarm/main/releases/${manifest.revision}/`);
    assert.ok(loader.includes(manifest.base));
    for (const [name, expected] of Object.entries(manifest.files)) {
        const content = read(`releases/${manifest.revision}/${name}`);
        assert.equal(hash(content), expected, `${name}: digest mismatch`);
        assert.equal(content, read(name), `${name}: entry/release mismatch`);
    }
});

test('bundle contains the current source and vendored WindUI license', () => {
    const core = read('src/core.lua');
    const source = read('src/main.lua');
    const expected = source.replace('__CLARIS_CORE__', `(function()\n${core}\nend)()`)
        .replace('__CLARIS_NAV__', `(function()\n${read('src/navigation.lua')}\nend)()`)
        .replace('__CLARIS_FPS__', `(function()\n${read('src/fps.lua')}\nend)()`);
    assert.equal(read('main.lua'), expected, 'Run npm run build after editing source');
    assert.ok(!expected.includes('__CLARIS_CORE__'));
    assert.ok(!expected.includes('__CLARIS_NAV__'));
    assert.ok(!expected.includes('__CLARIS_FPS__'));
    assert.match(read('vendor/WindUI.LICENSE'), /MIT License/);
});
