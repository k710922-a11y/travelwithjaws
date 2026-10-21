// 미니 포털 화면 로직 (프레임워크 없이 동작 — Next.js 홈과 미리보기 페이지가 함께 사용)
// mountPortal(root, data, { startScene, heroVideo, hubBase, onToast })
//   data: { items, collections, themes }  — 공개 피드 뷰(public_feed)와 같은 모양

const PF = {
  yt_shorts: { label: "쇼츠", glyph: "▶" },
  yt: { label: "유튜브", glyph: "▶" },
  ig_reels: { label: "릴스", glyph: "◎" },
  blog: { label: "블로그", glyph: "B" },
  official: { label: "공식 안내", glyph: "i" },
  hub_doc: { label: "판단 문서", glyph: "✓" },
};
const TABS = [
  { key: "all", label: "전체" },
  { key: "short", label: "쇼츠·릴스", match: p => p === "yt_shorts" || p === "ig_reels" },
  { key: "yt", label: "영상", match: p => p === "yt" },
  { key: "blog", label: "블로그", match: p => p === "blog" },
  { key: "official", label: "공식 안내", match: p => p === "official" },
  { key: "hub_doc", label: "판단 문서", match: p => p === "hub_doc" },
];
const WITH = [["family", "가족"], ["couple", "연인·부부"], ["friends", "친구"], ["solo", "혼자"]];
const WHERE = [["sea", "바다", -70], ["mix", "바다+도시", 0], ["city", "도시", 70]];
const EV = { official: "공식 안내로 확인", review: "방문자 경험 (협약 자막)", none: "요약 미제공" };

const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const isV = it => it.platform === "yt_shorts" || it.platform === "ig_reels";
const kindOf = v => (v < -33 ? "sea" : v > 33 ? "city" : "mix");
const fmtDate = d => { const [, m, dd] = d.split("-"); return `${+m}월 ${+dd}일`; };

// ---------- 가벼운 일러스트 포스터 (이미지 파일 없음) ----------
function rng(str) { let h = 2166136261; for (const c of str) h = Math.imul(h ^ c.charCodeAt(0), 16777619); return () => ((h = Math.imul(h ^ (h >>> 13), 1597334677)) >>> 0) / 4294967296; }
export function posterSVG(id, kind, vertical) {
  const r = rng(id), W = vertical ? 90 : 160, H = vertical ? 130 : 100, hz = H * (kind === "city" ? 0.7 : 0.55);
  const uid = id.replace(/\W/g, "");
  const skies = { sea: ["#6cc3ef", "#dff6fd"], mix: ["#7fb4ea", "#ffe7bd"], city: ["#5a5fd0", "#ffb59a"] };
  const [s1, s2] = skies[kind];
  let g = `<defs><linearGradient id="s${uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s1}"/><stop offset="1" stop-color="${s2}"/></linearGradient>
  <linearGradient id="w${uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${kind === "city" ? "#6d79c9" : "#3cc0dc"}"/><stop offset="1" stop-color="${kind === "city" ? "#2c3a8f" : "#0a86ad"}"/></linearGradient></defs>
  <rect width="${W}" height="${H}" fill="url(#s${uid})"/>`;
  const sunX = W * (0.2 + r() * 0.6), sunY = hz - H * (0.18 + r() * 0.15);
  g += `<circle cx="${sunX.toFixed(1)}" cy="${sunY.toFixed(1)}" r="${(H * 0.08).toFixed(1)}" fill="#fff4c9" opacity=".95"/>`;
  if (kind !== "sea") {
    let x = kind === "mix" ? W * 0.45 : -2;
    while (x < W + 4) {
      const w = 5 + r() * 9, h = H * (0.12 + r() * (kind === "city" ? 0.42 : 0.26));
      g += `<rect x="${x.toFixed(1)}" y="${(hz - h).toFixed(1)}" width="${w.toFixed(1)}" height="${h.toFixed(1)}" fill="${r() > 0.5 ? "#4b4fb8" : "#3a64ad"}" opacity="${(0.75 + r() * 0.25).toFixed(2)}"/>`;
      if (kind === "city") for (let k = 0; k < 4; k++) if (r() > 0.4) g += `<rect x="${(x + 1.5 + r() * (w - 3)).toFixed(1)}" y="${(hz - h + 3 + r() * (h - 6)).toFixed(1)}" width="1.4" height="1.4" fill="#ffd680"/>`;
      x += w + 0.6;
    }
  }
  g += `<rect y="${hz.toFixed(1)}" width="${W}" height="${(H - hz).toFixed(1)}" fill="url(#w${uid})"/>`;
  if (kind === "mix") { // 현수교
    const d = hz + 4;
    g += `<path d="M0 ${d} H${W}" stroke="#fff" stroke-width="1.2"/><path d="M${W * 0.3} ${d - 18} V${d + 2} M${W * 0.7} ${d - 18} V${d + 2}" stroke="#fff" stroke-width="1.6"/>
    <path d="M${W * 0.3} ${d - 18} Q${W * 0.5} ${d + 6} ${W * 0.7} ${d - 18}" stroke="#fff" fill="none" stroke-width=".9"/>`;
  }
  let waves = "";
  for (let i = 0; i < 6; i++) {
    const y = hz + 4 + i * (H - hz) / 6, a = 1 + i * 0.5;
    let p = `M-40 ${y}`;
    for (let x = -40; x <= W * 1.5; x += 10) p += ` Q${x + 5} ${y - a} ${x + 10} ${y}`;
    waves += `<path d="${p}" stroke="#fff" stroke-opacity="${0.25 + i * 0.07}" fill="none" stroke-width=".8"/>`;
  }
  g += `<g class="wv">${waves}</g>`;
  if (kind === "sea") { // 모래와 파라솔
    g += `<path d="M0 ${H * 0.82} Q${W * 0.35} ${H * 0.78} ${W * 0.6} ${H} H0Z" fill="#f8e3b5"/>`;
    const ux = W * (0.12 + r() * 0.2), uy = H * 0.84;
    g += `<path d="M${ux} ${uy} v12" stroke="#0f2a3d" stroke-width="1"/><path d="M${ux - 9} ${uy} A9 7 0 0 1 ${ux + 9} ${uy}Z" fill="${["#ffb627", "#5b5bd6", "#ff8f6b"][Math.floor(r() * 3)]}"/>`;
  }
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice" aria-hidden="true">${g}</svg>`;
}

// 실제 사진 (권리 승인된 썸네일) — 없으면 일러스트 포스터
const sized = (u, w) => u + (u.includes("?") ? "&" : "?") + "w=" + w;
const photo = (u, w, cls = "ph", eager = false) =>
  `<img class="${cls}" src="${esc(sized(u, w))}" srcset="${esc(sized(u, w))} 1x, ${esc(sized(u, w * 2))} 2x" alt="" ${eager ? 'fetchpriority="high"' : 'loading="lazy"'} decoding="async">`;
const art = (i, seed, kind, vertical, w) => (i.thumb ? photo(i.thumb, w) : posterSVG(seed, kind, vertical));
const demoTag = i => (i.demo ? `<span class="demo-tag" title="화면 확인용 예시 데이터">예시</span>` : "");
function badge(p) { const m = PF[p] ?? { label: p, glyph: "•" }; return `<span class="pf ${p}"><i>${m.glyph}</i>${m.label}</span>`; }

const MARK = `<svg viewBox="0 0 40 40" aria-hidden="true"><defs><clipPath id="mk"><circle cx="20" cy="20" r="19"/></clipPath></defs>
<g clip-path="url(#mk)"><rect width="40" height="40" fill="#a9dcf6"/><circle cx="11" cy="12" r="4.5" fill="#ffb627"/>
<rect x="22" y="10" width="5" height="14" fill="#5b5bd6"/><rect x="28" y="15" width="4" height="9" fill="#3a64ad"/><rect x="33" y="8" width="5" height="16" fill="#5b5bd6"/>
<rect y="24" width="40" height="16" fill="#0091b8"/><path d="M9 29 C12 23 15 20 19 18 C18 22 18.5 26 21 29 Z" fill="#0f2a3d"/>
<path d="M0 30 Q10 26 20 30 T40 30" stroke="#fff" fill="none" stroke-width="1.6"/><path d="M-2 40 Q8 32 20 40Z" fill="#f8e3b5"/></g></svg>`;
const ICON_SEA = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M2 15c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2M2 20c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2"/><circle cx="16" cy="7" r="3"/></svg>`;
const ICON_CITY = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" aria-hidden="true"><path d="M3 21V10h5v11M8 21V4h7v17M15 21v-8h6v8M2 21h20"/></svg>`;

// ---------- 화면 골격 ----------
function shell(d, opts) {
  const count = k => k === "all" ? d.items.length : d.items.filter(i => TABS.find(t => t.key === k).match(i.platform)).length;
  const latest = [...d.items].sort((a, b) => b.published.localeCompare(a.published)).slice(0, 10);
  const tick = latest.map(i => `<button class="tk" data-open="${i.id}">${badge(i.platform)}${demoTag(i)} ${esc(i.title)} <span>${esc(i.place)}</span></button>`).join("");
  return `
  <header class="bar gut"><div class="in">
    <a class="mark" href="#top" aria-label="Travel.with.Jaws 처음으로">${MARK}<b>Travel<i>.</i>with<i>.</i>Jaws</b></a>
    <nav class="mtabs" aria-label="매체 고르기">${TABS.map(t => `<button class="mtab" data-tab="${t.key}" aria-pressed="${t.key === "all"}">${t.label}<span class="n">${count(t.key)}</span></button>`).join("")}</nav>
    ${opts.adminHref === false ? "" : `<a class="admin" href="${esc(opts.adminHref || "/console")}" aria-label="관리자 화면 (허용된 계정만)"><svg viewBox="0 0 24 24" aria-hidden="true" width="16" height="16"><path d="M12 2l8 3v6c0 5-3.4 9.4-8 11-4.6-1.6-8-6-8-11V5l8-3z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M9 12l2 2 4-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg><span>관리자</span></a>`}
  </div></header>

  <section class="hero ${!opts.heroVideo && opts.heroPhotos?.length ? "photo" : ""}" id="top" aria-label="소개">
    ${opts.heroVideo ? `<video autoplay muted loop playsinline preload="metadata" poster="${esc(opts.heroVideo.poster || "")}"><source src="${esc(opts.heroVideo.src)}" type="video/mp4"></video>`
      : opts.heroPhotos?.length ? `<div class="hph" aria-hidden="true">${opts.heroPhotos.map((h, k) => `<figure class="${k === 0 ? "on" : ""}" data-credit="${esc(h.credit || "")}">${photo(h.uri, 1600, "", k === 0)}</figure>`).join("")}</div><span class="hcredit" data-hcredit>${esc(opts.heroPhotos[0].credit || "")}</span>`
      : `<canvas aria-hidden="true"></canvas>`}
    <button class="pause" type="button" data-pause>장면 멈추기</button>
    <div class="in gut">
      <h1><span class="w">바다에서 시작해</span> <span class="w">도시의 불빛까지</span></h1>
      <p class="sub">쇼츠, 릴스, 블로그, 공식 안내에 흩어진 여행 이야기를 한곳에 모아 요약하고, 어디까지가 확인된 사실인지 나눠 보여 드려요.</p>
      <form class="finder" data-finder>
        <fieldset><legend>어디로</legend><div class="seg">${WHERE.map(([k, l]) => `<button type="button" data-where="${k}" aria-pressed="${k === "mix"}">${l}</button>`).join("")}</div></fieldset>
        <fieldset><legend>누구와</legend><div class="seg">${WITH.map(([k, l]) => `<button type="button" data-with="${k}" aria-pressed="false">${l}</button>`).join("")}</div></fieldset>
        <button class="go" type="submit">이야기 모아 보기</button>
      </form>
    </div>
    <div class="mediabelt gut"><div class="in">${TABS.slice(1).map(t => `<button class="mpill" data-tab="${t.key}">${badge(t.key === "short" ? "yt_shorts" : t.key)}<b>${count(t.key)}</b></button>`).join("")}</div></div>
  </section>

  <div class="ticker gut" aria-label="방금 정리된 이야기"><div class="in">
    <h2><span class="live" aria-hidden="true"></span>방금 정리된 이야기</h2>
    <div class="track"><div class="belt">${tick}${tick.replace(/data-open/g, 'tabindex="-1" aria-hidden="true" data-open')}</div></div>
  </div></div>

  <main>
    <section class="sec gut" id="feed"><div class="in">
      <div class="sec-h">
        <div><h2 data-feed-title>오늘의 여행 이야기</h2><p>요약은 원작자와 합의한 범위 안에서 편집팀이 씁니다. 원본은 각 매체에서 보세요.</p></div>
        <div class="dial">
          <span class="end" style="color:var(--sea)">${ICON_SEA}바다</span>
          <input type="range" min="-100" max="100" step="5" value="0" id="seacity" aria-label="바다와 도시 사이 분위기" />
          <span class="end" style="color:var(--city)">도시${ICON_CITY}</span>
          <output for="seacity" data-dial-out>바다 50 : 도시 50</output>
        </div>
      </div>
      <div class="filters" data-filters></div>
      <div class="feed" data-feed></div>
    </div></section>

    <section class="sec gut" id="collections"><div class="in">
      <div class="sec-h"><div><h2>편집팀 컬렉션</h2><p>여러 매체의 이야기를 하나의 여행 질문으로 묶었습니다. 누르면 위 피드가 그 묶음으로 바뀝니다.</p></div></div>
      <div class="rail" data-rail></div>
    </div></section>

    <section class="sec gut" id="themes"><div class="in">
      <div class="sec-h"><div><h2>여행 이유로 찾기</h2><p>국내 8가지, 방한 4가지 테마입니다. 의료 관련 소재는 별도 검토 전까지 다루지 않습니다.</p></div></div>
      <div class="themes" data-themes></div>
    </div></section>

    <section class="sec gut" id="docs"><div class="in">
      <div class="sec-h"><div><h2>판단 문서</h2><p>공식 안내, 방문 경험, 편집 해석, 미확인 항목을 나눠 정리한 문서입니다. 막대는 각 근거의 개수예요.</p></div></div>
      <div class="docs" data-docs></div>
    </div></section>
  </main>

  <footer class="foot-b gut"><div class="in">
    <div><h3 class="fbrand">Travel<i>.</i>with<i>.</i>Jaws</h3><p>바다에서 도시까지, 확인하고 떠나는 여행.<br>travel.jawsweb.site</p></div>
    <div><h3>요약 원칙</h3><p>자막이나 글을 제공받은 경우에만 요약합니다. 제공받지 못한 영상은 제목만 보여 드리고 원본으로 연결합니다.</p></div>
    <div><h3>제휴 표시</h3><p>자료 제공이나 협찬이 있는 이야기는 카드와 상세 화면에 표시하고, 불리한 경험도 지우지 않습니다.</p></div>
    <div><h3>예약과 이용</h3><p>예약·결제·취소는 각 사업자가 처리합니다. 이 사이트는 예약을 확정하거나 시설 이용을 보장하지 않습니다.</p></div>
  </div></footer>
  <div data-layer></div>
  <div class="toast" role="status" hidden data-toast></div>`;
}

// ---------- 마운트 ----------
export function mountPortal(root, data, opts = {}) {
  const S = { tab: "all", with: new Set(), theme: null, coll: null, dial: 0 };
  root.innerHTML = shell(data, opts);
  const $ = s => root.querySelector(s), $$ = s => [...root.querySelectorAll(s)];
  const byId = Object.fromEntries(data.items.map(i => [i.id, i]));
  const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;

  // 히어로 장면
  let stopScene = null, paused = false;
  const canvas = $(".hero canvas"), video = $(".hero video"), slides = $$(".hph figure");
  if (canvas && opts.startScene) stopScene = opts.startScene(canvas, { reduced });
  // 히어로 사진: 6.5초마다 천천히 바뀐다 (움직임 줄이기 설정이면 첫 장만)
  let slide = 0, slideT = null;
  const startSlides = () => {
    if (slides.length < 2 || reduced) return;
    slideT = setInterval(() => {
      slides[slide].classList.remove("on"); slide = (slide + 1) % slides.length; slides[slide].classList.add("on");
      const c = $("[data-hcredit]"); if (c) c.textContent = slides[slide].dataset.credit || "";
    }, 6500);
  };
  if (slides.length) { startSlides(); root.querySelector(".hero").classList.toggle("still", reduced); }
  const pauseBtn = $("[data-pause]");
  if (reduced && !video) pauseBtn.hidden = true;
  if (slides.length < 2 && !video) pauseBtn.hidden = true;
  pauseBtn.addEventListener("click", () => {
    paused = !paused;
    if (video) paused ? video.pause() : video.play();
    else if (slides.length) { clearInterval(slideT); root.querySelector(".hero").classList.toggle("still", paused); if (!paused) startSlides(); }
    else if (paused) { stopScene?.(); stopScene = null; }
    else stopScene = opts.startScene?.(canvas, { reduced });
    pauseBtn.textContent = paused ? "장면 재생" : "장면 멈추기";
  });

  const toast = msg => { const t = $("[data-toast]"); t.textContent = msg; t.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => (t.hidden = true), 2800); };

  function visible() {
    const tab = TABS.find(t => t.key === S.tab);
    let list = data.items.filter(i => S.tab === "all" || tab.match(i.platform));
    if (S.with.size) list = list.filter(i => i.with.some(w => S.with.has(w)));
    if (S.theme) list = list.filter(i => i.theme === S.theme);
    if (S.coll) { const c = data.collections.find(c => c.id === S.coll); list = c.items.map(id => byId[id]).filter(i => list.includes(i)); }
    return list.map(i => ({ i, d: Math.abs(i.seaCity - S.dial) })).sort((a, b) => a.d - b.d || b.i.published.localeCompare(a.i.published));
  }

  function card(i, far) {
    const v = isV(i), k = kindOf(i.seaCity);
    const media = i.platform === "hub_doc"
      ? `<div class="doc"><b>근거 정리</b> 공식 ${i.ledger?.[0] ?? 0} · 경험 ${i.ledger?.[1] ?? 0} · 미확인 ${i.ledger?.[3] ?? 0}</div>`
      : (v || i.platform === "yt") ? `<span class="play" aria-hidden="true"></span>` : "";
    return `<button class="it ${v ? "v" : ""} ${far ? "far" : ""}" data-open="${i.id}" data-id="${i.id}" type="button">
      <div class="poster">${art(i, i.id, k, v, v ? 420 : 640)}<span class="tag">${badge(i.platform)}${demoTag(i)}</span>${media}${i.platform === "hub_doc" ? "" : `<span class="dur">${esc(i.duration)}</span>`}</div>
      <div class="body">
        <div class="who"><span>${esc(i.creator)}</span><span>${fmtDate(i.published)}</span></div>
        <h3>${esc(i.title)}</h3>
        ${i.summary ? `<p class="sum">${esc(i.summary)}</p>` : `<p class="sum none">${esc(i.summaryReason || "요약 미제공")}</p>`}
        <div class="foot"><span class="ev ${i.evidence}">${EV[i.evidence]}</span><span class="place">${esc(i.place)}</span></div>
        ${i.sponsored ? `<span class="spon">${esc(i.disclosure || "자료 제공 있음")}</span>` : ""}
      </div></button>`;
  }

  function renderFilters() {
    const chips = [];
    if (S.coll) chips.push(["coll", "컬렉션: " + data.collections.find(c => c.id === S.coll).title]);
    if (S.theme) chips.push(["theme", "테마: " + data.themes.find(t => t.key === S.theme).label]);
    S.with.forEach(w => chips.push(["with:" + w, "누구와: " + WITH.find(x => x[0] === w)[1]]));
    $("[data-filters]").innerHTML = chips.map(([k, l]) => `<button class="fchip" data-clear="${k}" type="button">${esc(l)} <i aria-hidden="true">✕</i><span class="sr" hidden>해제</span></button>`).join("")
      + (chips.length > 1 ? `<button class="fchip" data-clear="all" type="button">모두 해제</button>` : "");
  }

  // 위치가 바뀌는 카드를 부드럽게 옮김 (사용자 조작에 대한 응답)
  function renderFeed() {
    const feed = $("[data-feed]");
    const before = new Map($$("[data-feed] .it").map(el => [el.dataset.id, el.getBoundingClientRect()]));
    const list = visible();
    feed.innerHTML = list.length ? list.map(({ i, d }) => card(i, d > 90)).join("")
      : `<div class="empty">조건에 맞는 이야기가 아직 없어요. 필터를 하나 풀어 보세요.</div>`;
    if (!reduced) $$("[data-feed] .it").forEach(el => {
      const b = before.get(el.dataset.id); if (!b) return;
      const a = el.getBoundingClientRect(), dx = b.left - a.left, dy = b.top - a.top;
      if (dx || dy) el.animate([{ transform: `translate(${dx}px,${dy}px)` }, { transform: "none" }], { duration: 420, easing: "cubic-bezier(.2,.8,.2,1)" });
    });
    renderFilters();
    const sea = Math.round((100 - S.dial) / 2);
    $("[data-dial-out]").textContent = `바다 ${sea} : 도시 ${100 - sea}`;
    $("[data-feed-title]").textContent = S.coll ? data.collections.find(c => c.id === S.coll).title : "오늘의 여행 이야기";
  }

  function renderRail() {
    $("[data-rail]").innerHTML = data.collections.map(c => {
      const its = c.items.map(id => byId[id]).filter(Boolean);
      const kinds = [...new Set(its.map(i => i.platform))];
      const cover = its.find(x => x.thumb);
      return `<button class="col ${S.coll === c.id ? "on" : ""}" data-coll="${c.id}" type="button">${cover ? photo(cover.thumb, 720, "cov") : posterSVG(c.id + "c", c.mood, false)}
        <span class="cap"><h3>${esc(c.title)}</h3><p>${esc(c.sub)}</p><span class="mix">${kinds.map(badge).join("")}</span><p>이야기 ${its.length}개</p></span></button>`;
    }).join("");
  }
  function renderThemes() {
    $("[data-themes]").innerHTML = data.themes.map(t => {
      const n = data.items.filter(i => i.theme === t.key).length;
      return `<button class="th ${n ? "" : "zero"}" data-theme="${t.key}" aria-pressed="${S.theme === t.key}" type="button"><span><b>${esc(t.label)}</b><span class="seg-tag">${t.segment}</span></span><small>${n}</small></button>`;
    }).join("");
  }
  function renderDocs() {
    const docs = data.items.filter(i => i.platform === "hub_doc");
    const cols = ["var(--official-c)", "var(--review)", "var(--editorial)", "var(--unverified)"], names = ["공식", "경험", "해석", "미확인"];
    $("[data-docs]").innerHTML = docs.map(i => {
      const L = i.ledger || [0, 0, 0, 0], tot = L.reduce((a, b) => a + b, 0) || 1;
      return `<button class="dcard ${i.thumb ? "has-ph" : ""}" data-open="${i.id}" type="button">${i.thumb ? `<span class="dph">${photo(i.thumb, 640)}</span>` : ""}<span class="who" style="display:flex;gap:8px;font-size:var(--fs-xs);color:var(--muted)">${badge("hub_doc")}${demoTag(i)}<span>${esc(i.region)}</span><span>${fmtDate(i.published)} 확인</span></span>
        <h3>${esc(i.title)}</h3>
        <span class="ledger" aria-hidden="true">${L.map((n, k) => `<span style="width:${n / tot * 100}%;background:${cols[k]}"></span>`).join("")}</span>
        <span class="legend">${L.map((n, k) => `<span>${names[k]} <b>${n}</b></span>`).join("")}</span></button>`;
    }).join("");
  }

  // 상세 시트
  let lastFocus = null;
  function openSheet(id) {
    const i = byId[id]; if (!i) return;
    lastFocus = document.activeElement;
    const related = data.items.filter(x => x.id !== i.id && (x.place === i.place || x.region.split(" ")[0] === i.region.split(" ")[0])).slice(0, 3);
    const isDoc = i.platform === "hub_doc";
    const out = isDoc ? (opts.docHref ? opts.docHref(i) : `${opts.hubBase ?? ""}/p/${i.job}`) : i.url;
    $("[data-layer]").innerHTML = `<div class="scrim" data-close></div>
    <aside class="sheet" role="dialog" aria-modal="true" aria-labelledby="sh-t">
      <button class="close" data-close aria-label="닫기" type="button">✕</button>
      <div class="poster">${art(i, i.id + "s", kindOf(i.seaCity), false, 900)}<span class="tag">${badge(i.platform)}${demoTag(i)}</span><span class="dur">${esc(i.duration)}</span></div>
      <div class="sc">
        <div class="who" style="display:flex;gap:10px;flex-wrap:wrap;font-size:var(--fs-xs);color:var(--muted)"><span>${esc(i.creator)}</span><span>${fmtDate(i.published)}</span><span>${esc(i.place)}, ${esc(i.region)}</span></div>
        <h2 id="sh-t">${esc(i.title)}</h2>${i.credit ? `<p class="credit">사진: ${esc(i.credit.replace(/^Photo: /, ""))} · 참고용 사진이며 원본 콘텐츠의 장면이 아닐 수 있습니다</p>` : ""}
        <div class="box"><h4>${i.summary ? "편집 요약" : "요약하지 않은 이유"}</h4><p>${esc(i.summary || i.summaryReason)}</p></div>
        <div class="box"><h4>근거 상태</h4><p><span class="ev ${i.evidence}">${EV[i.evidence]}</span></p>
          <p class="note" style="margin-top:6px">${i.evidence === "official" ? "시설·기관이 공지한 내용을 확인 날짜와 함께 정리했어요." : i.evidence === "review" ? "특정 방문자가 특정 시점에 겪은 경험이에요. 내 조건과 같은지 원본에서 확인해 주세요." : "근거 자료를 받지 못해 내용을 정리하지 않았어요."}</p></div>
        ${i.sponsored ? `<div class="box"><h4>제휴·자료 제공</h4><p>${esc(i.disclosure || "자료 제공 있음")}. 같은 기준으로 확인하고 불리한 내용도 지우지 않습니다.</p></div>` : ""}
        <div class="acts">
          <a class="btn primary" href="${esc(out)}" ${isDoc ? "" : 'target="_blank" rel="noopener"'} data-out="${i.id}" ${isDoc && opts.docHref ? 'target="_blank" rel="noopener"' : ""}>${isDoc ? "판단 문서 열기" : "원본 보기"}<small>${isDoc ? "공식 안내·경험·미확인 항목 전체" : PF[i.platform].label + " 원본으로 이동합니다"}</small></a>
        </div>
        ${related.length ? `<div><h4 style="margin:6px 0 8px;font-size:var(--fs-sm)">같은 지역의 다른 이야기</h4><div class="acts">${related.map(r => `<button class="btn" data-open="${r.id}" type="button" style="text-align:left;font-weight:600">${badge(r.platform)} ${esc(r.title)}</button>`).join("")}</div></div>` : ""}
      </div></aside>`;
    $(".sheet .close").focus();
    opts.onOpen?.(i);
  }
  function closeSheet() { $("[data-layer]").innerHTML = ""; lastFocus?.focus?.(); }

  // ---------- 이벤트 ----------
  root.addEventListener("click", e => {
    const t = e.target.closest("button, a");
    if (!t || !root.contains(t)) return;
    if (t.dataset.close !== undefined) return closeSheet();
    if (t.dataset.open) { e.preventDefault(); return openSheet(t.dataset.open); }
    if (t.dataset.out && opts.onOut) opts.onOut(byId[t.dataset.out], e);
    if (t.dataset.tab) {
      S.tab = t.dataset.tab;
      $$("[data-tab].mtab").forEach(b => b.setAttribute("aria-pressed", b.dataset.tab === S.tab));
      renderFeed(); if (t.classList.contains("mpill")) $("#feed").scrollIntoView({ behavior: reduced ? "auto" : "smooth" });
    }
    if (t.dataset.where) {
      $$("[data-where]").forEach(b => b.setAttribute("aria-pressed", b === t));
      S.dial = WHERE.find(w => w[0] === t.dataset.where)[2]; $("#seacity").value = S.dial;
    }
    if (t.dataset.with) {
      const w = t.dataset.with; S.with.has(w) ? S.with.delete(w) : S.with.add(w);
      t.setAttribute("aria-pressed", S.with.has(w));
    }
    if (t.dataset.coll) {
      S.coll = S.coll === t.dataset.coll ? null : t.dataset.coll; renderRail(); renderFeed();
      if (S.coll) $("#feed").scrollIntoView({ behavior: reduced ? "auto" : "smooth" });
    }
    if (t.dataset.theme) { S.theme = S.theme === t.dataset.theme ? null : t.dataset.theme; renderThemes(); renderFeed(); $("#feed").scrollIntoView({ behavior: reduced ? "auto" : "smooth" }); }
    if (t.dataset.clear) {
      const c = t.dataset.clear;
      if (c === "all") { S.coll = null; S.theme = null; S.with.clear(); }
      else if (c === "coll") S.coll = null; else if (c === "theme") S.theme = null; else S.with.delete(c.split(":")[1]);
      $$("[data-with]").forEach(b => b.setAttribute("aria-pressed", S.with.has(b.dataset.with)));
      renderRail(); renderThemes(); renderFeed();
    }
  });
  $("[data-finder]").addEventListener("submit", e => {
    e.preventDefault(); renderFeed();
    $("#feed").scrollIntoView({ behavior: reduced ? "auto" : "smooth" });
    toast(`${visible().length}개의 이야기를 모았어요`);
  });
  let rafDial = 0;
  $("#seacity").addEventListener("input", e => {
    S.dial = +e.target.value;
    $$("[data-where]").forEach(b => b.setAttribute("aria-pressed", WHERE.find(w => w[0] === b.dataset.where)[2] === S.dial));
    cancelAnimationFrame(rafDial); rafDial = requestAnimationFrame(renderFeed);
  });
  const onKey = e => { if (e.key === "Escape" && $(".sheet")) closeSheet(); };
  document.addEventListener("keydown", onKey);

  renderFeed(); renderRail(); renderThemes(); renderDocs();
  return { toast, destroy() { stopScene?.(); document.removeEventListener("keydown", onKey); root.innerHTML = ""; } };
}
