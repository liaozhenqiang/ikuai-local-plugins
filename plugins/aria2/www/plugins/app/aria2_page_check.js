
function el(id){ return document.getElementById(id); }
function tip(t, cls){
  var m = el('msg'); m.textContent = t || ''; m.className = (cls || 'msg');
  if (t) { setTimeout(function(){ if (m.textContent===t) m.textContent=''; }, 6000); }
}
function copyText(t){
  t = String(t || '');
  if (!t || t === '—') return;
  var done = function(){ tip('已复制', 'msg ok'); };
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(t).then(done, function(){ fallback(); });
  } else { fallback(); }
  function fallback(){
    var ta = document.createElement('textarea');
    ta.value = t; ta.style.position='fixed'; ta.style.opacity='0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); done(); } catch(e){ tip('复制失败，请手动选择', 'msg err'); }
    document.body.removeChild(ta);
  }
}

// action 调用: show 类返回 Data, 其它动作成功时后端不回传内容
function api(action, param, opt){
  opt = opt || {};
  var ms = opt.timeout || 30000;
  var ab = (typeof AbortController === 'function') ? new AbortController() : null;
  var timer = null;
  var init = { method:'POST', headers:{'Content-Type':'application/json'},
               body: JSON.stringify({ func_name:'aria2', action:action, param:param||{} }) };
  if (ab) { init.signal = ab.signal; timer = setTimeout(function(){ ab.abort(); }, ms); }
  return fetch('/Action/call', init).then(function(r){ return r.json(); }).then(function(j){
    if (timer) clearTimeout(timer);
    if (j.Result !== 30000) throw new Error(j.ErrMsg || ('错误码 ' + j.Result));
    return j.Data || {};
  }).catch(function(e){
    if (timer) clearTimeout(timer);
    if (e.name === 'AbortError') throw new Error('后端 ' + Math.round(ms/1000) + ' 秒无响应(action=' + action + ')');
    throw e;
  });
}

var S = null;        // 最近一次 status
var ngUrl = '';      // 当前 iframe 用的 AriaNg URL(端口/密钥变了才重建)

function load(){
  return api('show', {TYPE:'status'}).then(render).catch(function(e){
    el('errbox').style.display = '';
    el('errbox').textContent = '获取状态失败: ' + e.message;
  });
}

// base64url 编码(AriaNg 预设 URL 里的 secret 必须是 base64url, 见其 base64UrlEncode)
function b64url(s){
  try { return btoa(s).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''); }
  catch(e){ return s; }
}

// 拼 AriaNg 的预设 URL: host 用"当前访问页面用的地址", 不猜路由器 IP。
// 格式: #!/settings/rpc/set?protocol=&host=&port=&interface=&secret=(base64url)
function buildNgUrl(s){
  var host = (typeof location !== 'undefined' && location && location.hostname) ? location.hostname : '127.0.0.1';
  return 'aria2ng.html#!/settings/rpc/set?protocol=http&host=' + encodeURIComponent(host) +
         '&port=' + encodeURIComponent(String(s.port || 6800)) +
         '&interface=jsonrpc&secret=' + b64url(String(s.secret || ''));
}

function render(d){
  var s = d && d.status;
  if (!s || typeof s !== 'object') { tip('后端没有返回状态数据', 'msg err'); return; }
  el('errbox').style.display = 'none';
  S = s;
  var run = s.running === true;
  var tag = el('tag');
  tag.textContent = run ? '运行中' : '未运行';
  tag.className = 'tag ' + (run ? 'run' : 'stp');

  el('bStart').disabled = run; el('bStop').disabled = !run; el('bRestart').disabled = !run;
  el('ngNotice').style.display = run ? 'none' : '';

  // HTTPS 页面里 iframe 连 HTTP RPC 会被浏览器拦(混合内容): 提示改用 HTTP 管理地址
  var isHttps = (typeof location !== 'undefined' && location && location.protocol === 'https:');
  var hp = num(s.web_http_port) || 0;
  if (isHttps) {
    el('httpsNotice').style.display = '';
    el('ngFrameWrap').style.display = 'none';
    if (hp > 0) {
      el('httpOpenWrap').style.display = '';
      el('httpOpenNone').style.display = 'none';
      el('httpOpenBtn').onclick = function(){
        location.href = 'http://' + location.hostname + ':' + hp + '/plugins/app/aria2.html';
      };
    } else {
      el('httpOpenWrap').style.display = 'none';
    }
  } else {
    el('httpsNotice').style.display = 'none';
    el('ngFrameWrap').style.display = '';
  }

  var html = '';
  html += card('运行状态', run ? '运行中' : '未运行', run ? 'ok' : 'err');
  html += card('运行时长', run ? (s.uptime || '-') : '-');
  html += card('RPC 端口', s.port || '-');
  html += card('aria2 版本', 'v' + (s.aria2_version || '-'));
  html += card('插件版本', 'v' + (s.version || '-'));
  html += card('下载目录', s.dir || '-');
  el('cards').innerHTML = html;

  if (document.activeElement.id !== 'port') el('port').value = (s.port || '');
  if (document.activeElement.id !== 'secret') el('secret').value = (s.secret || '');
  if (document.activeElement.id !== 'dir') el('dir').value = (s.dir || '');
  if (document.activeElement.id !== 'seedRatio') el('seedRatio').value = (s.seed_ratio == null ? '' : s.seed_ratio);
  setSegUI('bAuto', s.autostart);
  setSegUI('bDht', s.dht);

  // 端口/密钥变化才重建 iframe URL —— 否则每次轮询都把 AriaNg 刷新掉了
  var u = buildNgUrl(s);
  if (u !== ngUrl) { ngUrl = u; el('ngFrame').src = u; }
}
function card(k, v, cls){
  return '<div class="card"><div class="k">'+k+'</div><div class="v '+(cls||'')+'">'+v+'</div></div>';
}

function setSegUI(base, v){
  var on = (v == 1 || v === '1' || v === true);
  el(base+'1').className = on ? 'pri' : '';
  el(base+'0').className = on ? '' : 'dgr';
}

function ctl(op){
  tip('执行中 …');
  return api(op, {}).then(function(){ tip('已' + ({start:'启动',stop:'停止',restart:'重启'}[op]||op), 'msg ok'); return load(); })
    .catch(function(e){ tip('操作失败: ' + e.message, 'msg err'); });
}

function savePort(){
  var v = el('port').value.trim();
  if (!/^\d{1,5}$/.test(v) || +v < 1 || +v > 65535) { tip('端口需为 1~65535 的数字', 'msg err'); return; }
  api('seting', {key:'port', value:v}, {timeout:60000}).then(function(){
    tip('端口已保存并重启生效', 'msg ok'); return load();
  }).catch(function(e){ tip('保存失败: '+e.message, 'msg err'); });
}

function genSecret(){
  var n = 16, s = '', arr = new Uint8Array(n);
  if (window.crypto && crypto.getRandomValues) crypto.getRandomValues(arr);
  else for (var i=0;i<n;i++) arr[i] = Math.floor(Math.random()*256);
  var hex = '0123456789abcdef';
  for (var i=0;i<n;i++) s += hex[arr[i] & 15];
  el('secret').value = s;
  tip('已生成新密钥，点「保存密钥」生效');
}

function saveSecret(){
  var v = el('secret').value.trim();
  if (!/^[a-zA-Z0-9]{6,64}$/.test(v)) { tip('密钥需为 6~64 位字母数字', 'msg err'); return; }
  api('seting', {key:'secret', value:v}, {timeout:60000}).then(function(){
    tip('密钥已保存并重启生效', 'msg ok'); return load();
  }).catch(function(e){ tip('保存失败: '+e.message, 'msg err'); });
}

function saveDir(){
  var v = el('dir').value.trim();
  if (!v) { tip('目录不能为空', 'msg err'); return; }
  api('seting', {key:'dir', value:v}, {timeout:60000}).then(function(){
    tip('下载目录已保存并重启生效', 'msg ok'); return load();
  }).catch(function(e){ tip('保存失败: '+e.message, 'msg err'); });
}

function saveRatio(){
  var v = el('seedRatio').value.trim();
  if (!/^\d+(\.\d+)?$/.test(v)) { tip('分享率需为非负数字(0=无限)', 'msg err'); return; }
  api('seting', {key:'seed_ratio', value:v}, {timeout:60000}).then(function(){
    tip('分享率已保存并重启生效', 'msg ok'); return load();
  }).catch(function(e){ tip('保存失败: '+e.message, 'msg err'); });
}

function saveDht(v){
  api('seting', {key:'dht', value:String(v)}, {timeout:60000}).then(function(){
    tip(v ? 'DHT 已开启' : 'DHT 已关闭', 'msg ok');
    setSegUI('bDht', v); return load();
  }).catch(function(e){ tip('保存失败: '+e.message, 'msg err'); });
}

function saveAuto(v){
  api('seting', {key:'autostart', value:String(v)}, {timeout:60000}).then(function(){
    tip(v ? '开机自启已开启' : '开机自启已关闭', 'msg ok');
    setSegUI('bAuto', v);
  }).catch(function(e){ tip('保存失败: '+e.message, 'msg err'); });
}

function openNg(){
  if (!ngUrl) { tip('等页面加载完再试', 'msg warn'); return; }
  window.open(ngUrl, '_blank');
}

function loadLog(){
  el('log').textContent = '加载中…';
  api('show', {TYPE:'log'}).then(function(d){
    el('log').textContent = d.logtext || '（暂无日志）';
    el('log').scrollTop = el('log').scrollHeight;
  }).catch(function(e){ el('log').textContent = '加载失败: ' + e.message; });
}
function clearLog(){
  if (!confirm('确定清空运行日志吗？')) return;
  api('logclear', {}).then(function(){ tip('日志已清空', 'msg ok'); return loadLog(); })
    .catch(function(e){ tip('清空失败: ' + e.message, 'msg err'); });
}

load();
setInterval(function(){ if (!document.hidden) load(); }, 30000);
