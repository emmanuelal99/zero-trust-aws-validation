/* ============================================================
   LogiTrack — Enhanced JavaScript
   ============================================================ */

/* ─── PAGE LOADER ─────────────────────────────────────────── */
(function () {
  const loader = document.getElementById('page-loader');
  if (!loader) return;
  const fill = loader.querySelector('.loader-bar-fill');
  const txt  = loader.querySelector('.loader-text');
  const msgs = ['Connecting to network…', 'Loading assets…', 'Almost ready…'];
  let pct = 0, msgIdx = 0;
  const tick = setInterval(() => {
    pct += Math.random() * 22 + 8;
    if (pct >= 100) { pct = 100; clearInterval(tick); }
    if (fill) fill.style.width = pct + '%';
    if (txt && pct > 30 && msgIdx < msgs.length) txt.textContent = msgs[msgIdx++] || msgs[msgs.length-1];
  }, 220);
  window.addEventListener('load', () => {
    setTimeout(() => { if (loader) loader.classList.add('hidden'); }, 400);
  });
})();

/* ─── CUSTOM CURSOR ───────────────────────────────────────── */
(function () {
  if (window.matchMedia('(pointer: coarse)').matches) return;
  const dot  = document.querySelector('.cursor-dot');
  const ring = document.querySelector('.cursor-ring');
  if (!dot || !ring) return;
  let mx = 0, my = 0, rx = 0, ry = 0;
  document.addEventListener('mousemove', e => { mx = e.clientX; my = e.clientY; });
  function animCursor() {
    dot.style.left  = mx + 'px'; dot.style.top  = my + 'px';
    rx += (mx - rx) * 0.12; ry += (my - ry) * 0.12;
    ring.style.left = rx + 'px'; ring.style.top = ry + 'px';
    requestAnimationFrame(animCursor);
  }
  animCursor();
  document.querySelectorAll('a, button, .service-card, .btn, .nav-cta').forEach(el => {
    el.addEventListener('mouseenter', () => ring.classList.add('hovering'));
    el.addEventListener('mouseleave', () => ring.classList.remove('hovering'));
  });
})();

/* ─── SCROLL PROGRESS BAR ─────────────────────────────────── */
(function () {
  const bar = document.getElementById('scroll-progress');
  if (!bar) return;
  window.addEventListener('scroll', () => {
    const max = document.body.scrollHeight - window.innerHeight;
    bar.style.transform = 'scaleX(' + (max ? window.scrollY / max : 0) + ')';
  }, { passive: true });
})();

/* ─── NAVBAR SCROLL ───────────────────────────────────────── */
const navbar = document.querySelector('.navbar');
if (navbar) {
  window.addEventListener('scroll', () => {
    navbar.classList.toggle('scrolled', window.scrollY > 60);
  }, { passive: true });
}

/* ─── HAMBURGER MENU ──────────────────────────────────────── */
const hamburger = document.querySelector('.hamburger');
const navLinks  = document.querySelector('.nav-links');
if (hamburger && navLinks) {
  hamburger.addEventListener('click', () => {
    const open = navLinks.classList.toggle('open');
    const spans = hamburger.querySelectorAll('span');
    spans[1].style.opacity  = open ? '0' : '1';
    spans[0].style.transform = open ? 'rotate(45deg) translate(5px, 5px)' : '';
    spans[2].style.transform = open ? 'rotate(-45deg) translate(5px, -5px)' : '';
  });
}

/* ─── ACTIVE NAV LINK ─────────────────────────────────────── */
const currentPage = window.location.pathname.split('/').pop() || 'index.html';
document.querySelectorAll('.nav-links a').forEach(link => {
  const href = link.getAttribute('href');
  if (href === currentPage || (currentPage === '' && href === 'index.html')) {
    link.classList.add('active');
  }
});

/* ─── SCROLL REVEAL ───────────────────────────────────────── */
const revealObs = new IntersectionObserver((entries) => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      const delay = entry.target.dataset.delay || 0;
      setTimeout(() => entry.target.classList.add('visible'), +delay);
      revealObs.unobserve(entry.target);
    }
  });
}, { threshold: 0.1 });
document.querySelectorAll('.reveal').forEach(el => revealObs.observe(el));

/* ─── LIVE CLOCK ──────────────────────────────────────────── */
function updateClocks() {
  const zones = [
    { id: 'clock-lon', tz: 'Europe/London'    },
    { id: 'clock-fra', tz: 'Europe/Berlin'    },
    { id: 'clock-dxb', tz: 'Asia/Dubai'       },
    { id: 'clock-sgp', tz: 'Asia/Singapore'   },
    { id: 'clock-nyc', tz: 'America/New_York' },
  ];
  zones.forEach(z => {
    const el = document.getElementById(z.id);
    if (!el) return;
    el.textContent = new Date().toLocaleTimeString('en-GB', { timeZone: z.tz, hour: '2-digit', minute: '2-digit', second: '2-digit' });
  });
}
updateClocks();
setInterval(updateClocks, 1000);

/* ─── TYPEWRITER ──────────────────────────────────────────── */
(function () {
  const el = document.querySelector('.typewriter-text');
  if (!el) return;
  const words = ['FASTER.', 'SMARTER.', 'ANYWHERE.', 'ON TIME.'];
  let wi = 0, ci = 0, deleting = false;
  function type() {
    const word = words[wi];
    el.textContent = deleting ? word.slice(0, ci--) : word.slice(0, ++ci);
    let delay = deleting ? 60 : 110;
    if (!deleting && ci === word.length) { delay = 1800; deleting = true; }
    else if (deleting && ci === 0) { deleting = false; wi = (wi + 1) % words.length; delay = 300; }
    setTimeout(type, delay);
  }
  setTimeout(type, 1200);
})();

/* ─── HERO PARTICLES ──────────────────────────────────────── */
(function () {
  const container = document.getElementById('hero-particles');
  if (!container) return;
  for (let i = 0; i < 22; i++) {
    const p = document.createElement('div');
    p.className = 'particle';
    const size = Math.random() * 5 + 2;
    p.style.left             = (Math.random() * 100) + '%';
    p.style.width            = size + 'px';
    p.style.height           = size + 'px';
    p.style.animationDuration = (Math.random() * 12 + 10) + 's';
    p.style.animationDelay   = (Math.random() * -18) + 's';
    p.style.opacity          = (Math.random() * 0.5 + 0.1);
    container.appendChild(p);
  }
})();

/* ─── HERO PARALLAX ───────────────────────────────────────── */
(function () {
  const bg = document.querySelector('.hero-bg');
  if (!bg) return;
  window.addEventListener('scroll', () => {
    if (window.scrollY < window.innerHeight) bg.style.transform = 'translateY(' + (window.scrollY * 0.35) + 'px)';
  }, { passive: true });
})();

/* ─── FLOATING HERO SHAPES ────────────────────────────────── */
(function () {
  const container = document.querySelector('.hero-shapes');
  if (!container) return;
  const shapes = [
    { w:60,  h:60,  top:'15%', left:'78%', delay:0,   dur:6  },
    { w:35,  h:35,  top:'55%', left:'88%', delay:1.5, dur:8  },
    { w:90,  h:90,  top:'70%', left:'70%', delay:0.8, dur:10 },
    { w:20,  h:20,  top:'25%', left:'92%', delay:2.2, dur:7  },
    { w:50,  h:50,  top:'40%', left:'82%', delay:3,   dur:9  },
  ];
  shapes.forEach(s => {
    const el = document.createElement('div');
    el.className = 'hero-shape';
    el.style.cssText = 'width:'+s.w+'px;height:'+s.h+'px;top:'+s.top+';left:'+s.left+';animation-delay:'+s.delay+'s;animation-duration:'+s.dur+'s;';
    container.appendChild(el);
  });
})();

/* ─── COUNTER ANIMATION ───────────────────────────────────── */
function animateCounters() {
  document.querySelectorAll('.stat-num[data-target]').forEach(el => {
    const target = parseFloat(el.dataset.target);
    const suffix = el.dataset.suffix || '';
    let current  = 0;
    const inc    = target / 60;
    const timer  = setInterval(() => {
      current += inc;
      if (current >= target) { current = target; clearInterval(timer); }
      el.textContent = (target % 1 !== 0 ? current.toFixed(1) : Math.floor(current).toLocaleString()) + suffix;
    }, 1600 / 60);
  });
}
const statsBar = document.querySelector('.stats-bar');
if (statsBar) {
  const sObs = new IntersectionObserver(entries => {
    if (entries[0].isIntersecting) { animateCounters(); sObs.disconnect(); }
  }, { threshold: 0.5 });
  sObs.observe(statsBar);
}

/* ─── TOAST SYSTEM ────────────────────────────────────────── */
const toastContainer = document.getElementById('toast-container');
function showToast(msg, icon, duration) {
  icon     = icon     || '📦';
  duration = duration || 4500;
  if (!toastContainer) return;
  const t = document.createElement('div');
  t.className = 'toast';
  t.innerHTML = '<span class="toast-icon">'+icon+'</span><span class="toast-msg">'+msg+'</span><span class="toast-close">✕</span>';
  toastContainer.appendChild(t);
  const remove = function() { t.classList.add('removing'); setTimeout(function(){ t.remove(); }, 300); };
  t.querySelector('.toast-close').addEventListener('click', remove);
  setTimeout(remove, duration);
}



function initTracker() {
  const input  = document.getElementById('trackingInput');
  const result = document.getElementById('trackingResult');
  const btn    = document.querySelector('.track-btn');
  if (!input || !result || !btn) return;

  function runSearch() {
    const id = input.value.trim().toUpperCase();
    if (!id) { input.focus(); input.style.borderColor='var(--red)'; setTimeout(function(){input.style.borderColor='';},1000); return; }
    btn.innerHTML = '<span style="display:inline-block;animation:spin 0.7s linear infinite">⟳</span> Searching…';
    btn.disabled  = true;
    if (!document.getElementById('spin-style')) {
      const s = document.createElement('style');
      s.id = 'spin-style';
      s.textContent = '@keyframes spin{to{transform:rotate(360deg)}}';
      document.head.appendChild(s);
    }
    result.style.display = 'none';

    setTimeout(function() {
      btn.innerHTML = '&#128269; Track';
      btn.disabled  = false;
      const data = trackingData[id];
      if (!data) {
        result.style.display = 'block';
        result.innerHTML = '<div style="text-align:center;padding:24px 0;color:#888;"><div style="font-size:2.5rem;margin-bottom:10px;">📦</div><strong style="color:#333;">No shipment found</strong><br><span style="font-size:0.82rem;">Try: <a href="#" onclick="document.getElementById(\'trackingInput\').value=\'DHL1234567890\';return false;" style="color:var(--red);">DHL1234567890</a></span></div>';
        showToast('Tracking number not found.', '⚠️');
        return;
      }
      const color = data.progress === 100 ? '#4caf50' : data.statusClass === 'pending' ? '#1565c0' : 'var(--red)';
      const progressHTML = '<div style="margin:16px 0 4px;display:flex;justify-content:space-between;font-size:0.75rem;color:#888;"><span>Shipment progress</span><span>'+data.progress+'%</span></div><div style="height:6px;background:#f0f0f0;border-radius:99px;overflow:hidden;margin-bottom:16px;"><div style="height:100%;width:0%;background:'+color+';border-radius:99px;transition:width 1s ease;" data-pct="'+data.progress+'"></div></div>';
      const timelineHTML = data.events.map(function(e) {
        return '<div class="timeline-item '+e.state+'"><div class="tl-time">'+e.time+'</div><div class="tl-info"><h4>'+e.loc+'</h4><p>'+e.desc+'</p></div></div>';
      }).join('');
      result.style.display = 'block';
      result.innerHTML = '<div class="result-header"><div><div class="result-id">Tracking #: '+id+'</div><div style="font-size:0.8rem;color:#888;margin-top:4px;">'+data.origin+' → '+data.destination+' · ETA: <strong>'+data.eta+'</strong></div></div><div class="result-status '+data.statusClass+'">'+data.status+'</div></div>'+progressHTML+'<div class="tracking-timeline">'+timelineHTML+'</div>';
      const pBar = result.querySelector('[data-pct]');
      if (pBar) setTimeout(function(){ pBar.style.width = pBar.dataset.pct + '%'; }, 100);
      showToast(data.status+': '+data.origin+' → '+data.destination, data.progress===100?'✅':'📍');
    }, 1100);
  }

  btn.addEventListener('click', runSearch);
  input.addEventListener('keydown', function(e){ if(e.key==='Enter') runSearch(); });
}

/* ─── RIPPLE EFFECT ───────────────────────────────────────── */
function addRipple(e) {
  const btn  = e.currentTarget;
  const r    = document.createElement('span');
  const rect = btn.getBoundingClientRect();
  const size = Math.max(rect.width, rect.height);
  r.className = 'ripple';
  r.style.cssText = 'width:'+size+'px;height:'+size+'px;left:'+(e.clientX-rect.left-size/2)+'px;top:'+(e.clientY-rect.top-size/2)+'px;';
  btn.appendChild(r);
  setTimeout(function(){ r.remove(); }, 700);
}
document.querySelectorAll('.btn,.track-btn,.btn-red,.nav-cta').forEach(function(btn){
  btn.classList.add('ripple-btn');
  btn.addEventListener('click', addRipple);
});

/* ─── 3D TILT CARDS ───────────────────────────────────────── */
function initTilt() {
  document.querySelectorAll('.service-card,.testimonial-card,.value-card').forEach(function(card){
    card.addEventListener('mousemove', function(e){
      const rect = card.getBoundingClientRect();
      const dx = (e.clientX - rect.left - rect.width/2)  / (rect.width/2);
      const dy = (e.clientY - rect.top  - rect.height/2) / (rect.height/2);
      card.style.transform  = 'perspective(800px) rotateY('+(dx*6)+'deg) rotateX('+(-dy*6)+'deg) translateY(-6px) scale(1.01)';
      card.style.transition = 'transform 0.08s ease';
    });
    card.addEventListener('mouseleave', function(){
      card.style.transform  = '';
      card.style.transition = 'transform 0.4s cubic-bezier(0.34,1.56,0.64,1)';
    });
  });
}

/* ─── MAGNETIC BUTTONS ────────────────────────────────────── */
function initMagnetic() {
  if (window.matchMedia('(pointer: coarse)').matches) return;
  document.querySelectorAll('.btn,.nav-cta').forEach(function(el){
    el.classList.add('magnetic');
    el.addEventListener('mousemove', function(e){
      const rect = el.getBoundingClientRect();
      const dx = (e.clientX - (rect.left + rect.width/2))  * 0.3;
      const dy = (e.clientY - (rect.top  + rect.height/2)) * 0.3;
      el.style.transform = 'translate('+dx+'px,'+dy+'px)';
    });
    el.addEventListener('mouseleave', function(){ el.style.transform = ''; });
  });
}

/* ─── SMOOTH PAGE TRANSITIONS ─────────────────────────────── */
(function(){
  const overlay = document.getElementById('page-transition');
  if (!overlay) return;
  overlay.classList.add('leaving');
  overlay.addEventListener('animationend', function(){ overlay.classList.remove('leaving'); }, {once:true});
  document.querySelectorAll('a[href]').forEach(function(link){
    const href = link.getAttribute('href');
    if (!href || href[0]==='#' || href.startsWith('http') || href.startsWith('mailto') || href.startsWith('tel') || href.startsWith('javascript')) return;
    link.addEventListener('click', function(e){
      e.preventDefault();
      overlay.classList.add('entering');
      overlay.addEventListener('animationend', function(){ window.location.href = href; }, {once:true});
    });
  });
})();

/* ─── CONTACT FORM ────────────────────────────────────────── */
const contactForm = document.getElementById('contactForm');
if (contactForm) {
  contactForm.addEventListener('submit', function(e){
    const btn = contactForm.querySelector('.btn-red');
    if (btn) {
      btn.textContent = 'Sending…';
      btn.style.pointerEvents = 'none'; // Prevents double-clicking
    }
    // Form now naturally proceeds to submit to your Django backend!
  });
}

/* ─── STAGGER DELAYS ──────────────────────────────────────── */
function initStaggerDelays() {
  document.querySelectorAll('.services-grid,.testimonials-grid,.team-grid,.values-grid').forEach(function(grid){
    grid.querySelectorAll('.reveal').forEach(function(child, i){ child.dataset.delay = i * 90; });
  });
}

/* ─── PARALLAX IMAGES ON SCROLL ──────────────────────────── */
function initImgParallax() {
  const imgs = document.querySelectorAll('.service-full-img img,.about-img img,.why-visual img');
  if (!imgs.length) return;
  window.addEventListener('scroll', function(){
    imgs.forEach(function(img){
      const rect = img.closest('div').getBoundingClientRect();
      if (rect.top < window.innerHeight && rect.bottom > 0) {
        const pct = (window.innerHeight - rect.top) / (window.innerHeight + rect.height);
        img.style.transform = 'scale(1.08) translateY('+ ((pct-0.5)*28) +'px)';
      }
    });
  }, {passive:true});
}

/* ─── PERIODIC LIVE TOASTS ────────────────────────────────── */
/*const deliveryToasts = [
  {msg:'Real-time tracking update'},
  {msg:'Get quote: and ready to ship smarter'},
  {msg:'24 hours support: we’re here for you'},
  {msg:'Get help: contact our support team'},
];
let dIdx = 0;
function scheduleDeliveryToast() {
  setTimeout(function(){
    const d = deliveryToasts[dIdx++ % deliveryToasts.length];
    showToast(d.msg, d.icon, 5000);
    scheduleDeliveryToast();
  }, Math.random() * 14000 + 10000);
}*/

/* ─── BOOT ────────────────────────────────────────────────── */
/*document.addEventListener('DOMContentLoaded', function(){
  initTracker();
  initTilt();
  initMagnetic();
  initStaggerDelays();
  initImgParallax();
  scheduleDeliveryToast();
  const path = window.location.pathname;
  if (path.indexOf('index') !== -1 || path.endsWith('/') || path === '') {
    setTimeout(function(){ showToast('Welcome to LogiTrack — <strong>220+ countries</strong> served worldwide.', '🌍', 5000); }, 1800);
  }
}); */

/* ─── BOOT ────────────────────────────────────────────────── */
document.addEventListener('DOMContentLoaded', function(){
  // Initialize core UI features only.
  if (typeof initTracker === 'function') initTracker();
  if (typeof initTilt === 'function') initTilt();
  if (typeof initMagnetic === 'function') initMagnetic();
  if (typeof initStaggerDelays === 'function') initStaggerDelays();
  if (typeof initImgParallax === 'function') initImgParallax();
});