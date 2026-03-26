const API = 'http://127.0.0.1:8000/api/v1';

// ── Auth ──────────────────────────────────────────────────────────────────────
const Auth = {
  getToken: () => localStorage.getItem('cp_token'),
  getUser:  () => JSON.parse(localStorage.getItem('cp_user') || 'null'),
  setAuth:  (token, user) => {
    localStorage.setItem('cp_token', token);
    localStorage.setItem('cp_user', JSON.stringify(user));
  },
  clear: () => {
    localStorage.removeItem('cp_token');
    localStorage.removeItem('cp_user');
  },
  isLoggedIn: () => !!localStorage.getItem('cp_token'),
  isOfficial: () => {
    const u = JSON.parse(localStorage.getItem('cp_user') || 'null');
    return u && ['dept_official','city_admin','super_admin'].includes(u.role);
  },
};

// ── HTTP helpers ──────────────────────────────────────────────────────────────
async function api(method, path, body = null, auth = false) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth) {
    const token = Auth.getToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
  }
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(API + path, opts);
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || `HTTP ${res.status}`);
  }
  return res.json();
}

const get  = (path, auth=false)       => api('GET',  path, null, auth);
const post = (path, body, auth=false) => api('POST', path, body, auth);

// ── Helpers ───────────────────────────────────────────────────────────────────
function severityColor(s) {
  return { critical:'#E24B4A', high:'#D85A30', moderate:'#EF9F27', low:'#639922', resolved:'#1D9E75' }[s] || '#888';
}

function statusColor(s) {
  return {
    resolved:'#1D9E75', in_progress:'#185FA5',
    assigned:'#EF9F27', rejected:'#E24B4A', verified:'#1D9E75'
  }[s] || '#888';
}

function badgeHtml(text, cls) {
  return `<span class="badge badge-${cls || text.replace(' ','_')}">${text.replace('_',' ')}</span>`;
}

function timeAgo(dateStr) {
  if (!dateStr) return '';
  const diff = (Date.now() - new Date(dateStr)) / 1000;
  if (diff < 60)   return 'just now';
  if (diff < 3600) return `${Math.floor(diff/60)}m ago`;
  if (diff < 86400)return `${Math.floor(diff/3600)}h ago`;
  return `${Math.floor(diff/86400)}d ago`;
}

function showToast(msg, type = 'success') {
  const t = document.createElement('div');
  t.className = `toast toast-${type}`;
  t.textContent = msg;
  t.style.cssText = `
    position:fixed; bottom:24px; right:24px; z-index:9999;
    padding:12px 20px; border-radius:10px; font-weight:500;
    background:${type==='error'?'#E24B4A':type==='warn'?'#EF9F27':'#1D9E75'};
    color:#fff; box-shadow:0 4px 12px rgba(0,0,0,0.15);
    animation: slideUp 0.3s ease;
  `;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3000);
}

function getCityId() {
  return localStorage.getItem('cp_city_id');
}

async function ensureCity() {
  if (getCityId()) return getCityId();
  const cities = await get('/cities/');
  if (cities.length) {
    localStorage.setItem('cp_city_id', cities[0].id);
    return cities[0].id;
  }
  return null;
}
