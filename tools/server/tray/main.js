// Значок «MyWay — сервер» у треї: стан бази, сервера гри й сервісу оновлень, онлайн, і кнопки
// «Запустити / Зупинити / Перезапустити / Оновити гру / Оновити апдейтер». Слово замовника 27.11.2026:
// «не організована процедура перезапуску та інформування про необхідність оновити лаунчер та гру,
// зроби окремим пунктом в треї щоб я міг стартонути, зупинити, оновити».
// Дії — tools/server/myway-server.sh (той самий, що в терміналі); довгі (оновлення) — окремою
// службою systemd-run під hubjob: переживають закриття значка й шлють «✅/❌» на телефон.
// Колір: сірий — усе зупинено; зелений — працює; синій — працює, хтось грає; жовтий — іде дія
// (запуск, відлік зупинки, оновлення); червоний — служба впала.
const path = require('path');
const os = require('os');
const fs = require('fs');
const http = require('http');
const { execFile } = require('child_process');
const { app, Tray, Menu, nativeImage, Notification, shell, dialog } = require('electron');

app.setName('myway-server-tray');
app.setPath('userData', path.join(os.homedir(), '.config', 'myway-server-tray'));
if (!app.requestSingleInstanceLock()) app.quit();

const REPO = path.resolve(__dirname, '..', '..', '..');
const CTL = path.join(REPO, 'tools', 'server', 'myway-server.sh');
const STATE = path.join(os.homedir(), 'MyWay-сервер');
const LOGS = path.join(STATE, 'logs');
const WIKI = 'http://192.168.1.34/myway/';
const HUBJOB = path.join(os.homedir(), '.local', 'bin', 'hubjob');
const UNITS = ['myway-db', 'myway-updates', 'myway-game'];
const NAMES = { 'myway-db': 'База (PostgREST :3000)', 'myway-updates': 'Сервіс оновлень (:24600)',
  'myway-game': 'Сервер гри (UDP 24565)' };
const JOB_UNIT = 'myway-job';
const POLL_MS = 4000;
const COLORS = { off: [140, 140, 140], up: [46, 184, 92], play: [60, 130, 230], busy: [235, 170, 30],
  fail: [220, 60, 60] };

// щит із «М» — щоб не плутати з «Відеокартою», «Марсом» і «Агентом»
function icon([r, g, b], size = 32) {
  const buf = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = (x - size / 2 + 0.5) / (size / 2), v = (y - 2) / (size - 4);
      const half = v < 0.55 ? 0.82 : 0.82 * Math.sqrt(Math.max(0, 1 - ((v - 0.55) / 0.45) ** 2));
      const inside = v >= 0 && v <= 1 && Math.abs(u) <= half;
      const edge = inside && (Math.abs(u) > half - 0.16 || v < 0.07);
      const m = v > 0.25 && v < 0.72 && (Math.abs(Math.abs(u) - 0.38) < 0.09
        || (Math.abs(u) < 0.38 && Math.abs(v - 0.25 - Math.abs(u) * 0.75) < 0.07));
      const k = edge ? 0.7 : m ? 1.35 : 1;
      const i = (y * size + x) * 4;
      buf[i] = Math.min(255, b * k); buf[i + 1] = Math.min(255, g * k); buf[i + 2] = Math.min(255, r * k);
      buf[i + 3] = inside ? 255 : 0;
    }
  }
  return nativeImage.createFromBitmap(buf, { width: size, height: size });
}

let tray = null;
let units = {};       // myway-game → active | inactive | failed | activating | deactivating
let status = null;    // /status.json сервісу оновлень або null
let job = null;       // активна довга дія (myway-job) — її опис
let busy = null;      // коротка дія, яку робить значок зараз
let lastPlayers = null;

function notify(title, body) { new Notification({ title, body: String(body || '').slice(0, 400) }).show(); }

function run(cmd, args, timeout = 300000) {
  return new Promise((resolve) => execFile(cmd, args, { timeout }, (err, stdout, stderr) =>
    resolve({ code: err ? (err.code ?? 1) : 0, out: `${stdout}${stderr}`.trim() })));
}

function getStatus() {
  return new Promise((resolve) => {
    const req = http.get('http://127.0.0.1:24600/status.json', { timeout: 3000 }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => { try { resolve(JSON.parse(data)); } catch { resolve(null); } });
    });
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.on('error', () => resolve(null));
  });
}

async function refresh() {
  const r = await run('systemctl', ['--user', 'show', '-p', 'Id,ActiveState', ...UNITS.map((u) => `${u}.service`),
    `${JOB_UNIT}.service`], 10000);
  const next = {};
  let id = null;
  for (const line of r.out.split('\n')) {
    if (line.startsWith('Id=')) id = line.slice(3).replace('.service', '');
    if (line.startsWith('ActiveState=') && id) next[id] = line.slice(12);
  }
  const was = units;
  units = next;
  for (const u of UNITS) {
    if (was[u] && was[u] !== 'failed' && units[u] === 'failed') notify(`MyWay: ${NAMES[u]} впала`, `журнал: ${LOGS}`);
  }
  if (job && !['active', 'activating'].includes(units[JOB_UNIT])) {
    const ok = units[JOB_UNIT] !== 'failed';
    notify(`MyWay: ${job} — ${ok ? 'готово' : 'помилка'}`, ok ? '' : `журнал: ${path.join(LOGS, 'job.log')}`);
    job = null;
  }
  status = await getStatus();
  const n = status && status['працює'] ? status['гравців'] : null;
  if (lastPlayers !== null && n !== null && n > lastPlayers) {
    const names = (status['гравці'] || []).map((p) => p["ім'я"]).join(', ');
    notify(`MyWay: онлайн ${n}`, names);
  }
  lastPlayers = n;
  render();
}

const cut = (t, n = 90) => (t.length > n ? `${t.slice(0, n - 1)}…` : t);
const ago = (t) => { const s = Math.max(0, Date.now() / 1000 - t); const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60); return h ? `${h} год ${m} хв` : `${m} хв`; };
const gameUp = () => units['myway-game'] === 'active';
const anyUp = () => UNITS.some((u) => ['active', 'activating'].includes(units[u]));
const jobRunning = () => ['active', 'activating'].includes(units[JOB_UNIT]);

function stopping() {
  const z = status && status['зупинка'];
  return z && z['о'] ? Math.max(0, z['о'] - Math.floor(Date.now() / 1000)) : null;
}

function state() {
  if (busy || jobRunning() || stopping() !== null) return 'busy';
  if (UNITS.some((u) => units[u] === 'failed')) return 'fail';
  if (!anyUp()) return 'off';
  if (status && status['працює'] && status['гравців'] > 0) return 'play';
  return 'up';
}

function headline() {
  if (busy) return `MyWay: ${busy}…`;
  if (jobRunning()) return `MyWay: ${job || 'оновлення'} іде…`;
  const left = stopping();
  if (left !== null) return `MyWay: зупинка через ${left} с`;
  if (!anyUp()) return 'MyWay: сервер зупинено';
  if (status && status['працює']) return `MyWay: працює · онлайн ${status['гравців']} з ${status['максимум']}`;
  if (UNITS.some((u) => units[u] === 'failed')) return 'MyWay: служба впала';
  return 'MyWay: запускається…';
}

function confirm(message, detail, buttons = ['Так', 'Скасувати']) {
  return dialog.showMessageBoxSync({ type: 'question', buttons, defaultId: 0, cancelId: buttons.length - 1,
    title: 'MyWay — сервер', message, detail });
}

async function act(label, args, okText) {
  if (busy) return;
  busy = label; render();
  const r = await run(CTL, args);
  busy = null;
  notify(`MyWay: ${label} — ${r.code ? 'помилка' : 'готово'}`, r.code ? r.out.split('\n').slice(-4).join('\n') : okText || '');
  await refresh();
}

// Довга дія — окремою службою під hubjob (сповіщення на телефон), журнал — job.log.
async function longJob(label, args) {
  if (jobRunning()) { notify('MyWay', `уже йде: ${job || 'дія'}`); return; }
  job = label;
  const log = path.join(LOGS, 'job.log');
  fs.mkdirSync(LOGS, { recursive: true });
  fs.appendFileSync(log, `\n═══ ${new Date().toLocaleString('uk-UA')} · ${label}\n`);
  const cmd = fs.existsSync(HUBJOB)
    ? [HUBJOB, '--назва', `MyWay: ${label}`, '--тиша', '15', '--', CTL, ...args]
    : [CTL, ...args];
  const r = await run('systemd-run', ['--user', `--unit=${JOB_UNIT}`, '--collect', '--quiet',
    `--property=StandardOutput=append:${log}`, `--property=StandardError=append:${log}`,
    `--working-directory=${REPO}`, ...cmd], 15000);
  if (r.code) { job = null; notify(`MyWay: ${label} не запустилось`, r.out); }
  else notify(`MyWay: ${label} почалось`, 'Хід — у «Журнал дії». На телефон прийде «завершено» чи «помилка».');
  await refresh();
}

const DELAYS = [[0, 'зараз'], [60, 'через 1 хв'], [300, 'через 5 хв']];

function render() {
  if (!tray) return;
  const k = state();
  tray.setImage(icon(COLORS[k]));
  const head = headline();
  tray.setToolTip(head);
  const items = [{ label: cut(head), enabled: false }];
  if (status && status['працює']) {
    const who = (status['гравці'] || []).map((p) => `${p["ім'я"]}${p['рівень'] ? ` (${p['рівень']})` : ''}`).join(', ');
    if (who) items.push({ label: cut(`   ${who}`), enabled: false });
    items.push({ label: cut(`   ${status['світ']} · ${status['версія']} · працює ${ago(status['запущено'])}`), enabled: false });
    const z = status['зупинка'];
    if (z && z['о']) items.push({ label: cut(`   ⏳ зупинка: ${z['чому'] || 'без причини'}`), enabled: false });
  }
  items.push({ type: 'separator' });
  for (const u of UNITS) {
    const s = units[u] || '?';
    const mark = s === 'active' ? '●' : s === 'failed' ? '✖' : s === 'activating' ? '◐' : '○';
    items.push({ label: `${mark}  ${NAMES[u]} — ${s}`, enabled: false });
  }
  const free = !busy && !jobRunning();
  items.push({ type: 'separator' });
  if (!anyUp() || UNITS.some((u) => units[u] === 'failed')) {
    items.push({ label: '▶  Запустити сервер', enabled: free, click: () => act('запуск', ['start'], 'база, сервіс оновлень і сервер гри працюють') });
  }
  if (anyUp()) {
    items.push({ label: '↻  Перезапустити сервер гри', enabled: free && gameUp(), submenu: DELAYS.map(([d, t]) => ({
      label: `${t} (гравців попередить відліком)`, click: () => act('перезапуск', ['restart', String(d), 'перезапуск сервера']) })) });
    items.push({ label: '■  Зупинити все', enabled: free, submenu: DELAYS.map(([d, t]) => ({
      label: `${t}`, click: () => act('зупинка', ['stop', String(d), 'сервер вимикається'], 'усе зупинено, гравців збережено') })) });
    if (stopping() !== null) items.push({ label: '✋  Скасувати відлік зупинки', enabled: !busy, click: () => act('скасування', ['cancel']) });
  }
  items.push({ type: 'separator' });
  items.push({ label: '⬆  Оновити гру…', enabled: free, click: () => {
    const b = confirm('Оновити гру?', 'Зібрати клієнт для Windows, macOS і Linux, опублікувати новий випуск (старі клієнти апдейтер '
      + 'попросить оновити) і перезапустити сервер гри. Гравців попередить відлік у чаті. Займе кілька хвилин.',
    ['Так, перезапуск через 1 хв', 'Так, перезапуск зараз', 'Скасувати']);
    if (b === 0) longJob('оновлення гри', ['update-game', '60']);
    if (b === 1) longJob('оновлення гри', ['update-game', '0']);
  } });
  items.push({ label: '⬆  Оновити апдейтер (лаунчер)…', enabled: free, click: () => {
    if (confirm('Зібрати новий апдейтер?', 'Версія апдейтера +1, збірка для трьох систем, викладення на вікі '
      + `(${WIKI}). Старі апдейтери покажуть «вийшла нова версія», гравцям у грі прийде повідомлення. `
      + 'Сервер не перезапускається.') === 0) longJob('оновлення апдейтера', ['update-updater']);
  } });
  items.push(
    { type: 'separator' },
    { label: '🌐  Вікі й завантаження', click: () => shell.openExternal(WIKI) },
    { label: '📄  Журнал сервера гри', click: () => shell.openPath(path.join(LOGS, 'game.log')) },
    { label: '📄  Журнал дії (оновлення)', click: () => shell.openPath(path.join(LOGS, 'job.log')) },
    { label: '📁  Каталог проєкту', click: () => shell.openPath(REPO) },
    { label: 'Прибрати значок (сервер працює далі)', click: () => app.quit() },
  );
  tray.setContextMenu(Menu.buildFromTemplate(items));
}

app.whenReady().then(() => {
  tray = new Tray(icon(COLORS.off));
  render(); refresh();
  setInterval(() => { if (!busy) refresh(); }, POLL_MS);
});
app.on('window-all-closed', (e) => e.preventDefault());
