"""Publish the reviewed local source bundle into this repository; no blockchain calls."""
import hashlib, json, os, pathlib, subprocess, zipfile

root = pathlib.Path.cwd().resolve()
archive = root / 'reviewed-sources.zip'
expected = os.environ['SOURCE_BUNDLE_SHA256']
actual = hashlib.sha256(archive.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit('Source bundle checksum mismatch')
allowed_roots = {'fl-v3n', 'verification'}
allowed_files = {'README.md', 'DEPLOYMENTS.md', 'DEPLOYMENTS.json', 'SOURCE-SHA256.json', '.gitignore', 'PUBLICATION-NOTES.md', 'PUBLIC-SECURITY-REVIEW.json'}
with zipfile.ZipFile(archive) as z:
    entries = [i for i in z.infolist() if not i.is_dir()]
    names = []
    for info in entries:
        name = info.filename.replace('\\', '/')
        rel = pathlib.PurePosixPath(name)
        if rel.is_absolute() or '..' in rel.parts or not rel.parts or (rel.parts[0] not in allowed_roots and name not in allowed_files):
            raise SystemExit('Unexpected source bundle path')
        if any(x in rel.parts for x in ['.git', '.github', 'cache', 'broadcast', 'node_modules', 'out', 'target', 'historico']):
            raise SystemExit('Forbidden source bundle path')
        target = root.joinpath(*rel.parts).resolve()
        if not target.is_relative_to(root) or info.file_size > 10000000:
            raise SystemExit('Unsafe source entry')
        if name in names:
            raise SystemExit('Duplicate source entry')
        names.append(name)
    for info, name in zip(entries, names):
        target = root.joinpath(*pathlib.PurePosixPath(name).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(info))

checks = json.loads((root / 'SOURCE-SHA256.json').read_text())
for entry in checks['files']:
    p = pathlib.PurePosixPath(entry['path'])
    if p.is_absolute() or '..' in p.parts:
        raise SystemExit('Unsafe checksum path')
    if hashlib.sha256(root.joinpath(*p.parts).read_bytes()).hexdigest() != entry['sha256']:
        raise SystemExit('Extracted source checksum mismatch')

def git(*args):
    return subprocess.check_output(['git', *args])

git('config', 'user.name', 'github-actions[bot]')
git('config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
git('add', '--', *names)
if git('diff', '--cached', '--name-only').strip():
    git('commit', '-m', 'Publish reviewed variable-supply Fast Launch sources and deployed-address evidence')
commit = git('rev-parse', 'HEAD').decode().strip()
payload = git('cat-file', 'commit', commit)
commit_sha256 = hashlib.sha256(b'commit ' + str(len(payload)).encode() + b'\0' + payload).hexdigest()
proof = {
    'repository': os.environ['GITHUB_REPOSITORY'],
    'commit': commit,
    'commitObjectSha256': commit_sha256,
    'commitObjectSha256Definition': 'SHA-256 over canonical Git commit object: commit, space, decimal payload byte length, NUL, raw commit payload. Native repository Git identifier remains SHA-1.',
    'approvedOriginalZipSha256': checks['approvedZipSha256'],
    'publicSourceBundleSha256': actual,
    'tag': 'fast-launch-variable-supply-2026-10-12',
    'sourcesExtracted': len(names),
}
(root / 'publication-proof.json').write_text(json.dumps(proof, indent=2) + '\n')
tag = proof['tag']
remote_tag = git('ls-remote', '--tags', 'origin', 'refs/tags/' + tag).strip()
if remote_tag:
    git('fetch', 'origin', 'refs/tags/' + tag + ':refs/tags/' + tag)
    if git('rev-list', '-n', '1', tag).decode().strip() != commit:
        raise SystemExit('Existing release tag points to a different commit; refusing to move it')
else:
    git('tag', '-a', tag, '-m', 'Approved R3 sources; 12 deployed contracts checked byte for byte', commit)
    git('push', '--atomic', 'origin', 'HEAD:main', 'refs/tags/' + tag)
notes = f'''Approved sources for the 12 deployed Fast Launch contracts on BNB, HyperEVM, Arc and Robinhood.

- Commit: `{commit}`
- SHA-256 of canonical commit object: `{commit_sha256}`
- Approved original ZIP SHA-256: `{checks['approvedZipSha256']}`
- Public source bundle SHA-256: `{actual}`
- All 12 runtimes match, including immutable values. Five Standard JSON inputs reproduce the builds.
- Source files, deployment guide, tests, addresses, constructor arguments and evidence are included.
- The clean publication excludes wallets, secrets, private RPC URLs, broadcast/cache files and prior private repository history. See PUBLICATION-NOTES.md for the dependency-only Sepolia RPC sanitization.
- Publication only: no blockchain transactions, website, bot, holder-service or Solana changes.

See DEPLOYMENTS.md for all explorer and Sourcify links. Explorer labels (exact or partial) are distinct from the independent runtime checks.
'''
(root / 'release-notes.txt').write_text(notes)
print(json.dumps(proof, indent=2))
