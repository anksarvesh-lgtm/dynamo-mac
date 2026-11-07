"use strict";

// ---------------------------------------------------------------------------
// Live Football — FIFA World Cup 2026 live scores for SuperIsland.
//
// Data: ESPN public scoreboard (keyless, undocumented):
//   https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard
// Country flags come from ESPN's CDN logos in the same payload; emoji flags
// are used in notifications. Independent fan project — not affiliated with FIFA.
// ---------------------------------------------------------------------------

var ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world";
var ESPN_STANDINGS = "https://site.api.espn.com/apis/v2/sports/soccer/fifa.world/standings";
var SCOREBOARD_URL = "https://www.espn.com/soccer/scoreboard/_/league/fifa.world";

var DAY_MS = 24 * 60 * 60 * 1000;
var CELEBRATION_MS = 9000;
var ROTATE_MS = 10000;       // auto-rotate featured match when several are live
var MANUAL_HOLD_MS = 45000;  // how long a manual prev/next selection sticks

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

var matches = [];            // normalized matches, window [-2d, +8d], sorted by kickoff
var groupByTeam = {};        // "CAN" -> "A" (from standings, best-effort)
var lastFetchAt = 0;
var lastFetchOK = 0;
var fetchInFlight = false;
var firstFetchDone = false;  // suppress celebrations on the very first sync
var fetchError = null;
var heartbeatID = null;

var celebration = null;      // { match, side, until } — goal flash window
var ftFlash = null;          // { match, until } — full-time flash window

var activeTab = "today";     // "today" | "fixtures" | "results"
var manualFeaturedID = null;
var manualFeaturedUntil = 0;

// ---------------------------------------------------------------------------
// Settings helpers
// ---------------------------------------------------------------------------

function settingBool(key, fallback) {
  var v = SuperIsland.settings.get(key);
  if (typeof v === "boolean") return v;
  if (v === null || v === undefined) return fallback;
  if (typeof v === "number") return v !== 0;
  if (typeof v === "string") return v.toLowerCase() === "true";
  return fallback;
}

function settingString(key, fallback) {
  var v = SuperIsland.settings.get(key);
  if (v === null || v === undefined || v === "") return fallback;
  return String(v);
}

function favoriteCode() {
  return settingString("favoriteTeam", "").trim().toUpperCase();
}

function livePollSeconds() {
  var v = Number(settingString("livePoll", "30"));
  return Number.isFinite(v) && v >= 15 ? v : 30;
}

// ---------------------------------------------------------------------------
// Emoji flags (for notifications) — FIFA trigram -> ISO 3166-1 alpha-2
// ---------------------------------------------------------------------------

var TRIGRAM_TO_ISO2 = {
  USA: "US", CAN: "CA", MEX: "MX", PAR: "PY", BIH: "BA", ARG: "AR", BRA: "BR",
  GER: "DE", FRA: "FR", ESP: "ES", POR: "PT", NED: "NL", BEL: "BE", CRO: "HR",
  ITA: "IT", URU: "UY", COL: "CO", ECU: "EC", CHI: "CL", PER: "PE", VEN: "VE",
  JPN: "JP", KOR: "KR", KSA: "SA", IRN: "IR", IRQ: "IQ", QAT: "QA", UAE: "AE",
  JOR: "JO", UZB: "UZ", AUS: "AU", NZL: "NZ", MAR: "MA", SEN: "SN", TUN: "TN",
  ALG: "DZ", EGY: "EG", NGA: "NG", GHA: "GH", CIV: "CI", CMR: "CM", RSA: "ZA",
  CPV: "CV", SUI: "CH", AUT: "AT", SWE: "SE", NOR: "NO", DEN: "DK", POL: "PL",
  CZE: "CZ", SVK: "SK", SVN: "SI", SRB: "RS", TUR: "TR", UKR: "UA", GRE: "GR",
  ROU: "RO", HUN: "HU", IRL: "IE", ISL: "IS", FIN: "FI", PAN: "PA", CRC: "CR",
  HON: "HN", GUA: "GT", SLV: "SV", JAM: "JM", HAI: "HT", CUW: "CW", TRI: "TT",
  BOL: "BO", IDN: "ID", THA: "TH", VIE: "VN", CHN: "CN", IND: "IN", MLI: "ML",
  BFA: "BF", GAB: "GA", COD: "CD", GUI: "GN", ZAM: "ZM", KEN: "KE",
  ENG: "GB-ENG", SCO: "GB-SCT", WAL: "GB-WLS"
};

function flagEmoji(trigram) {
  var iso = TRIGRAM_TO_ISO2[(trigram || "").toUpperCase()];
  if (!iso) return "🏳️";
  if (iso.indexOf("-") >= 0) {
    // England/Scotland/Wales: black flag + tag letters + cancel tag
    var letters = iso.toLowerCase().replace(/-/g, "");
    var points = [0x1f3f4];
    for (var i = 0; i < letters.length; i++) points.push(0xe0000 + letters.charCodeAt(i));
    points.push(0xe007f);
    return String.fromCodePoint.apply(String, points);
  }
  return String.fromCodePoint(
    0x1f1e6 + (iso.charCodeAt(0) - 65),
    0x1f1e6 + (iso.charCodeAt(1) - 65)
  );
}

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

var STAGE_LABELS = {
  "group-stage": "Group",
  "round-of-32": "Round of 32",
  "round-of-16": "Round of 16",
  "quarterfinals": "Quarter-final",
  "semifinals": "Semi-final",
  "3rd-place-match": "3rd place",
  "final": "Final"
};

function normalizeTeam(competitor) {
  var t = (competitor && competitor.team) || {};
  var name = t.displayName || t.name || t.shortDisplayName || "TBD";
  var abbr = (t.abbreviation || name.slice(0, 3)).toUpperCase();
  var score = parseInt(competitor && competitor.score, 10);
  return {
    name: name,
    shortName: t.shortDisplayName || name,
    abbr: abbr,
    logo: t.logo || null,
    score: Number.isFinite(score) ? score : null,
    winner: !!(competitor && competitor.winner)
  };
}

function normalizeEvent(ev) {
  var comp = (ev.competitions && ev.competitions[0]) || {};
  var competitors = comp.competitors || [];
  var homeC = null;
  var awayC = null;
  for (var i = 0; i < competitors.length; i++) {
    if (competitors[i].homeAway === "away") awayC = competitors[i];
    else if (homeC === null) homeC = competitors[i];
  }
  if (!homeC) homeC = competitors[0] || {};
  if (!awayC) awayC = competitors[1] || {};

  var st = ev.status || comp.status || {};
  var stType = st.type || {};
  var statusName = (stType.name || "").toUpperCase();
  var state = stType.state || "pre"; // pre | in | post
  var isHalftime = statusName.indexOf("HALFTIME") >= 0;

  var minute = null;
  if (state === "in" && st.displayClock) {
    var m = String(st.displayClock).match(/\d+(\+\d+)?/);
    if (m) minute = m[0];
  }

  var slug = (ev.season && ev.season.slug) || "group-stage";
  var stageLabel = STAGE_LABELS[slug] || "";

  var venue = (comp.venue && comp.venue.fullName) || "";
  var city = (comp.venue && comp.venue.address && comp.venue.address.city) || "";

  return {
    id: String(ev.id),
    kickoffMs: Date.parse(ev.date),
    state: state,
    isHalftime: isHalftime,
    minute: minute,
    home: normalizeTeam(homeC),
    away: normalizeTeam(awayC),
    stage: slug,
    stageLabel: stageLabel,
    venue: venue,
    city: city
  };
}

function matchGroupLabel(match) {
  if (match.stage !== "group-stage") return match.stageLabel;
  var letter = groupByTeam[match.home.abbr] || groupByTeam[match.away.abbr];
  return letter ? "Group " + letter : "Group";
}

function isLive(match) { return match.state === "in"; }

function scoreText(match) {
  var h = match.home.score === null ? 0 : match.home.score;
  var a = match.away.score === null ? 0 : match.away.score;
  return h + "–" + a;
}

// ---------------------------------------------------------------------------
// Fetching + goal detection
// ---------------------------------------------------------------------------

function pad2(n) { return (n < 10 ? "0" : "") + n; }

function espnDate(ms) {
  var d = new Date(ms);
  return "" + d.getUTCFullYear() + pad2(d.getUTCMonth() + 1) + pad2(d.getUTCDate());
}

function currentPollMs() {
  var now = Date.now();
  for (var i = 0; i < matches.length; i++) {
    var m = matches[i];
    if (isLive(m)) return livePollSeconds() * 1000;
    // a kickoff inside the next 10 minutes — poll every minute so we catch it
    if (m.state === "pre" && m.kickoffMs - now < 10 * 60 * 1000 && m.kickoffMs - now > -10 * 60 * 1000) {
      return 60 * 1000;
    }
  }
  return 5 * 60 * 1000;
}

function refreshNow() {
  if (fetchInFlight) return;
  fetchInFlight = true;
  lastFetchAt = Date.now();

  var from = espnDate(Date.now() - 2 * DAY_MS);
  var to = espnDate(Date.now() + 8 * DAY_MS);
  var url = ESPN_BASE + "/scoreboard?limit=300&dates=" + from + "-" + to;

  SuperIsland.http.fetch(url).then(function (res) {
    fetchInFlight = false;
    if (!res || res.status !== 200 || !res.data || !res.data.events) {
      fetchError = res && res.error ? String(res.error) : "HTTP " + (res ? res.status : "?");
      return;
    }
    fetchError = null;
    lastFetchOK = Date.now();

    var fresh = [];
    for (var i = 0; i < res.data.events.length; i++) {
      try {
        var m = normalizeEvent(res.data.events[i]);
        if (Number.isFinite(m.kickoffMs)) fresh.push(m);
      } catch (e) {
        console.error("normalize failed: " + e);
      }
    }
    fresh.sort(function (a, b) { return a.kickoffMs - b.kickoffMs; });

    if (firstFetchDone) detectEvents(matches, fresh);
    matches = fresh;
    if (!firstFetchDone) {
      firstFetchDone = true;
      // Loaded mid-match (e.g. app started after kickoff): claim the island
      // so the notch shows the live score right away.
      if (liveMatches().length > 0) revealIsland(4000);
    }
  });
}

function findByID(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
  return null;
}

function detectEvents(oldList, newList) {
  for (var i = 0; i < newList.length; i++) {
    var next = newList[i];
    var prev = findByID(oldList, next.id);
    if (!prev) continue;

    // Goals (per side, so we know who scored)
    if (prev.home.score !== null && next.home.score !== null && next.home.score > prev.home.score) {
      onGoal(next, "home");
    }
    if (prev.away.score !== null && next.away.score !== null && next.away.score > prev.away.score) {
      onGoal(next, "away");
    }

    // Kickoff
    if (prev.state === "pre" && next.state === "in") onKickoff(next);

    // Full time
    if (prev.state === "in" && next.state === "post") onFullTime(next);
  }
}

function involvesFavorite(match) {
  var fav = favoriteCode();
  if (!fav) return false;
  return match.home.abbr === fav || match.away.abbr === fav ||
    match.home.name.toUpperCase().indexOf(fav) >= 0 ||
    match.away.name.toUpperCase().indexOf(fav) >= 0;
}

function onGoal(match, side) {
  celebration = { match: match, side: side, until: Date.now() + CELEBRATION_MS };

  var team = side === "home" ? match.home : match.away;
  if (settingBool("notifyGoals", true)) {
    SuperIsland.notifications.send({
      title: "⚽ GOOOAL — " + team.name + "!",
      body: flagEmoji(match.home.abbr) + " " + match.home.name + " " + scoreText(match) + " " +
        match.away.name + " " + flagEmoji(match.away.abbr) +
        (match.minute ? " · " + match.minute + "'" : ""),
      sound: settingBool("playSound", true)
    });
  }
  SuperIsland.playFeedback("success");
  revealIsland(CELEBRATION_MS - 1500);
}

function onKickoff(match) {
  // Become the active module so the notch flips to the score for the whole
  // match, even if another module had the island before kickoff.
  revealIsland(5000);
  if (!settingBool("notifyKickoff", true)) return;
  if (settingBool("favoriteOnlyAlerts", false) && !involvesFavorite(match)) return;
  SuperIsland.notifications.send({
    title: "🏟️ Kickoff",
    body: flagEmoji(match.home.abbr) + " " + match.home.name + " vs " +
      match.away.name + " " + flagEmoji(match.away.abbr) + " · " + matchGroupLabel(match),
    sound: false
  });
}

function onFullTime(match) {
  ftFlash = { match: match, until: Date.now() + 7000 };
  if (!settingBool("notifyFullTime", true)) return;
  if (settingBool("favoriteOnlyAlerts", false) && !involvesFavorite(match)) return;
  SuperIsland.notifications.send({
    title: "FT: " + match.home.name + " " + scoreText(match) + " " + match.away.name,
    body: flagEmoji(match.home.abbr) + " " + flagEmoji(match.away.abbr) + " " +
      matchGroupLabel(match) + (match.venue ? " · " + match.venue : ""),
    sound: settingBool("playSound", true)
  });
}

function revealIsland(visibleMs) {
  if (SuperIsland.island.state === "fullExpanded") return;
  SuperIsland.island.activate(false);
  setTimeout(function () { SuperIsland.island.activate(false); }, 120);
  setTimeout(function () {
    if (SuperIsland.island.state !== "fullExpanded") SuperIsland.island.dismiss();
  }, (visibleMs || 4000) + 120);
}

function fetchStandings() {
  SuperIsland.http.fetch(ESPN_STANDINGS).then(function (res) {
    if (!res || res.status !== 200 || !res.data || !res.data.children) return;
    var map = {};
    var children = res.data.children;
    for (var i = 0; i < children.length; i++) {
      var name = children[i].name || children[i].abbreviation || "";
      var m = name.match(/Group\s+([A-L])/i);
      if (!m) continue;
      var letter = m[1].toUpperCase();
      var entries = (children[i].standings && children[i].standings.entries) || [];
      for (var j = 0; j < entries.length; j++) {
        var abbr = entries[j].team && entries[j].team.abbreviation;
        if (abbr) map[abbr.toUpperCase()] = letter;
      }
    }
    groupByTeam = map;
  });
}

function heartbeat() {
  // Expire transient flashes
  if (celebration && Date.now() > celebration.until) celebration = null;
  if (ftFlash && Date.now() > ftFlash.until) ftFlash = null;
  if (manualFeaturedID && Date.now() > manualFeaturedUntil) manualFeaturedID = null;

  if (Date.now() - lastFetchAt >= currentPollMs()) refreshNow();
}

// ---------------------------------------------------------------------------
// Featured match selection
// ---------------------------------------------------------------------------

function liveMatches() { return matches.filter(isLive); }

function featuredMatch() {
  if (matches.length === 0) return null;

  if (manualFeaturedID) {
    var manual = findByID(matches, manualFeaturedID);
    if (manual) return manual;
  }

  if (celebration) {
    var celebrating = findByID(matches, celebration.match.id);
    if (celebrating) return celebrating;
  }

  var live = liveMatches();
  if (live.length > 0) {
    for (var i = 0; i < live.length; i++) {
      if (involvesFavorite(live[i])) return live[i];
    }
    // rotate through concurrent live matches
    return live[Math.floor(Date.now() / ROTATE_MS) % live.length];
  }

  if (ftFlash) {
    var justEnded = findByID(matches, ftFlash.match.id);
    if (justEnded) return justEnded;
  }

  var now = Date.now();
  var favNext = null, next = null, lastDone = null;
  for (var j = 0; j < matches.length; j++) {
    var m = matches[j];
    if (m.state === "pre" && m.kickoffMs > now - 5 * 60 * 1000) {
      if (!next) next = m;
      if (!favNext && involvesFavorite(m)) favNext = m;
    }
    if (m.state === "post") lastDone = m; // list is sorted, keeps the latest
  }
  if (favNext) return favNext;
  if (next) return next;
  return lastDone || matches[matches.length - 1];
}

function stepFeatured(direction) {
  var current = featuredMatch();
  if (!current) return;
  var pool = liveMatches();
  if (pool.length < 2) {
    // nothing live to cycle — walk the full schedule instead
    pool = matches;
  }
  var idx = 0;
  for (var i = 0; i < pool.length; i++) if (pool[i].id === current.id) { idx = i; break; }
  var nextIdx = (idx + direction + pool.length) % pool.length;
  manualFeaturedID = pool[nextIdx].id;
  manualFeaturedUntil = Date.now() + MANUAL_HOLD_MS;
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

function kickoffTime(match) {
  var d = new Date(match.kickoffMs);
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

function dayKey(ms) {
  var d = new Date(ms);
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
}

function dayLabel(ms) {
  var today = dayKey(Date.now());
  var tomorrow = dayKey(Date.now() + DAY_MS);
  var yesterday = dayKey(Date.now() - DAY_MS);
  var key = dayKey(ms);
  if (key === today) return "Today";
  if (key === tomorrow) return "Tomorrow";
  if (key === yesterday) return "Yesterday";
  var d = new Date(ms);
  return DAY_NAMES[d.getDay()] + " " + MONTH_NAMES[d.getMonth()] + " " + d.getDate();
}

function statusText(match) {
  if (match.isHalftime) return "HT";
  if (isLive(match)) return (match.minute || "0") + "'";
  if (match.state === "post") return "FT";
  return kickoffTime(match);
}

// ---------------------------------------------------------------------------
// Shared view builders
// ---------------------------------------------------------------------------

var LIVE_RED = { r: 1, g: 0.3, b: 0.3, a: 1 };
var PITCH_GREEN = { r: 0.3, g: 0.9, b: 0.45, a: 1 };
var GOLD = { r: 1, g: 0.82, b: 0.3, a: 1 };
var DIM = { r: 1, g: 1, b: 1, a: 0.45 };
var FAINT = { r: 1, g: 1, b: 1, a: 0.3 };

function flagView(team, size) {
  if (team.logo) {
    return View.image(team.logo, { width: size, height: size, cornerRadius: size / 2 });
  }
  return View.icon("flag.circle.fill", { size: size, color: DIM });
}

function liveDot(size) {
  return View.animate(View.icon("circle.fill", { size: size || 6, color: LIVE_RED }), "pulse");
}

function favStar(match, size) {
  if (!involvesFavorite(match)) return null;
  return View.icon("star.fill", { size: size || 8, color: GOLD });
}

function isCelebrating() {
  return celebration !== null && Date.now() < celebration.until;
}

// ---------------------------------------------------------------------------
// Compact view (≈188×34)
// ---------------------------------------------------------------------------

function compactGoalView() {
  var match = celebration.match;
  var live = findByID(matches, match.id) || match;
  var team = celebration.side === "home" ? live.home : live.away;
  return View.hstack([
    View.animate(View.icon("soccerball.inverse", { size: 15, color: "white" }), "spin"),
    View.animate(View.text("GOAL!", { style: "title", color: PITCH_GREEN }), "blink"),
    flagView(team, 16),
    View.text(scoreText(live), { style: "monospaced", color: "white" })
  ], { spacing: 6, align: "center" });
}

function compactMatchView(match) {
  var mid;
  if (match.state === "pre") {
    mid = View.text(kickoffTime(match), { style: "monospacedSmall", color: DIM });
  } else {
    mid = View.text(scoreText(match), { style: "monospaced", color: "white" });
  }

  var trailing;
  if (match.isHalftime) {
    trailing = View.text("HT", { style: "footnote", color: GOLD });
  } else if (isLive(match)) {
    trailing = View.hstack([
      liveDot(5),
      View.text((match.minute || "0") + "'", { style: "footnote", color: LIVE_RED })
    ], { spacing: 3, align: "center" });
  } else if (match.state === "post") {
    trailing = View.text("FT", { style: "footnote", color: FAINT });
  } else {
    trailing = null;
  }

  return View.hstack([
    flagView(match.home, 16),
    View.text(match.home.abbr, { style: "footnote", color: "white" }),
    mid,
    View.text(match.away.abbr, { style: "footnote", color: "white" }),
    flagView(match.away, 16),
    trailing
  ], { spacing: 5, align: "center" });
}

function compactView() {
  if (isCelebrating()) return compactGoalView();
  var match = featuredMatch();
  if (!match) {
    return View.hstack([
      View.icon("soccerball", { size: 13, color: DIM }),
      View.text(fetchError ? "offline" : "no matches", { style: "footnote", color: DIM })
    ], { spacing: 5, align: "center" });
  }
  return compactMatchView(match);
}

// ---------------------------------------------------------------------------
// Minimal compact (hardware notch: leading / trailing only)
// ---------------------------------------------------------------------------

function minimalLeading() {
  if (isCelebrating()) {
    return View.animate(View.icon("soccerball.inverse", { size: 14, color: PITCH_GREEN }), "spin");
  }
  var match = featuredMatch();
  if (!match) return View.icon("soccerball", { size: 13, color: DIM });
  return View.hstack([
    flagView(match.home, 16),
    View.text(match.state === "pre" ? match.home.abbr : String(match.home.score === null ? 0 : match.home.score),
      { style: "monospacedSmall", color: "white" })
  ], { spacing: 4, align: "center" });
}

function minimalTrailing() {
  if (isCelebrating()) {
    return View.animate(View.text("GOAL!", { style: "monospacedSmall", color: PITCH_GREEN }), "blink");
  }
  var match = featuredMatch();
  if (!match) return View.text("--", { style: "monospacedSmall", color: DIM });
  return View.hstack([
    View.text(match.state === "pre" ? match.away.abbr : String(match.away.score === null ? 0 : match.away.score),
      { style: "monospacedSmall", color: "white" }),
    flagView(match.away, 16),
    isLive(match) ? liveDot(4) : null
  ], { spacing: 4, align: "center" });
}

// ---------------------------------------------------------------------------
// Expanded view (360×80)
// ---------------------------------------------------------------------------

function teamColumn(team, align) {
  return View.vstack([
    flagView(team, 34),
    View.text(team.abbr, { style: "caption", color: "white" })
  ], { spacing: 3, align: "center" });
}

function expandedView() {
  var match = featuredMatch();
  if (!match) {
    return View.hstack([
      View.icon("soccerball", { size: 24, color: DIM }),
      View.vstack([
        View.text("World Cup 2026", { style: "title", color: "white" }),
        View.text(fetchError ? "Can't reach ESPN — retrying" : "No fixtures in window", { style: "footnote", color: DIM })
      ], { spacing: 2, align: "leading" })
    ], { spacing: 10, align: "center" });
  }

  var celebratingThis = isCelebrating() && celebration.match.id === match.id;

  var centerTop;
  if (celebratingThis) {
    centerTop = View.animate(View.text("GOAL!", { style: "title", color: PITCH_GREEN }), "blink");
  } else if (match.state === "pre") {
    centerTop = View.text(kickoffTime(match), { style: "title", color: "white" });
  } else {
    centerTop = View.text(scoreText(match), { style: "largeTitle", color: "white" });
  }

  var centerBottom;
  if (match.isHalftime) {
    centerBottom = View.text("Half-time", { style: "footnote", color: GOLD });
  } else if (isLive(match)) {
    centerBottom = View.hstack([
      liveDot(5),
      View.text((match.minute || "0") + "' live", { style: "footnote", color: LIVE_RED })
    ], { spacing: 3, align: "center" });
  } else if (match.state === "post") {
    centerBottom = View.text("Full-time", { style: "footnote", color: DIM });
  } else {
    centerBottom = View.text(dayLabel(match.kickoffMs), { style: "footnote", color: DIM });
  }

  var homeCol = celebratingThis && celebration.side === "home"
    ? View.animate(teamColumn(match.home), "bounce") : teamColumn(match.home);
  var awayCol = celebratingThis && celebration.side === "away"
    ? View.animate(teamColumn(match.away), "bounce") : teamColumn(match.away);

  var contextLine = matchGroupLabel(match) + (match.venue ? " · " + match.venue : "") +
    (match.city ? ", " + match.city : "");

  return View.hstack([
    View.button(View.icon("chevron.left", { size: 12, color: FAINT }), "prev"),
    homeCol,
    View.frame(
      View.vstack([centerTop, centerBottom], { spacing: 1, align: "center" }),
      { maxWidth: 9999 }
    ),
    awayCol,
    View.button(View.icon("chevron.right", { size: 12, color: FAINT }), "next"),
    View.vstack([
      favStar(match, 9),
      View.marqueeText(contextLine, { style: "footnote", color: FAINT })
    ], { spacing: 2, align: "trailing" })
  ], { spacing: 8, align: "center" });
}

// ---------------------------------------------------------------------------
// Full expanded view (400×200) — Today / Fixtures / Results browser
// ---------------------------------------------------------------------------

function tabButton(id, label) {
  var active = activeTab === id;
  var inner = View.padding(
    View.text(label, { style: "caption", color: active ? "white" : DIM }),
    { edges: "horizontal", amount: 8 }
  );
  if (active) {
    inner = View.cornerRadius(View.background(View.padding(
      View.text(label, { style: "caption", color: "white" }),
      { edges: "horizontal", amount: 8 }
    ), { r: 1, g: 1, b: 1, a: 0.14 }), 9);
  }
  return View.button(inner, "tab-" + id);
}

function fixtureRow(match) {
  var celebratingThis = isCelebrating() && celebration.match.id === match.id;
  var live = isLive(match);

  var statusColor = live ? LIVE_RED : (match.state === "post" ? FAINT : DIM);
  var status = View.frame(
    View.hstack([
      live && !match.isHalftime ? liveDot(4) : null,
      View.text(statusText(match), { style: "monospacedSmall", color: match.isHalftime ? GOLD : statusColor })
    ], { spacing: 3, align: "center" }),
    { width: 46, alignment: "leading" }
  );

  var mid = match.state === "pre"
    ? View.text("vs", { style: "monospacedSmall", color: FAINT })
    : View.text(scoreText(match), { style: "monospaced", color: celebratingThis ? PITCH_GREEN : "white" });

  var dimWinners = match.state === "post";
  var homeColor = dimWinners && !match.home.winner && match.home.score !== match.away.score ? DIM : "white";
  var awayColor = dimWinners && !match.away.winner && match.home.score !== match.away.score ? DIM : "white";

  var row = View.hstack([
    status,
    View.frame(View.text(match.home.abbr, { style: "caption", color: homeColor }), { width: 34, alignment: "trailing" }),
    flagView(match.home, 15),
    View.frame(mid, { width: 34, alignment: "center" }),
    flagView(match.away, 15),
    View.frame(View.text(match.away.abbr, { style: "caption", color: awayColor }), { width: 34, alignment: "leading" }),
    favStar(match, 8),
    View.spacer(),
    View.text(matchGroupLabel(match), { style: "footnote", color: FAINT })
  ], { spacing: 5, align: "center" });

  if (celebratingThis) row = View.animate(row, "blink");
  return View.button(row, "feat-" + match.id);
}

function heroCard(match) {
  var celebratingThis = isCelebrating() && celebration.match.id === match.id;
  var live = isLive(match);

  var centerTop;
  if (celebratingThis) {
    centerTop = View.animate(View.text("GOAL!", { style: "largeTitle", color: PITCH_GREEN }), "blink");
  } else if (match.state === "pre") {
    centerTop = View.text(kickoffTime(match), { style: "largeTitle", color: "white" });
  } else {
    centerTop = View.text(scoreText(match), { style: "largeTitle", color: "white" });
  }

  var centerBottom;
  if (match.isHalftime) {
    centerBottom = View.text("Half-time", { style: "caption", color: GOLD });
  } else if (live) {
    centerBottom = View.hstack([
      liveDot(5),
      View.text((match.minute || "0") + "' live", { style: "caption", color: LIVE_RED })
    ], { spacing: 4, align: "center" });
  } else if (match.state === "post") {
    centerBottom = View.text("Full-time", { style: "caption", color: DIM });
  } else {
    centerBottom = View.text("Kickoff " + dayLabel(match.kickoffMs).toLowerCase(), { style: "caption", color: DIM });
  }

  function heroTeam(team, bouncing) {
    var col = View.vstack([
      flagView(team, 44),
      View.text(team.abbr, { style: "caption", color: "white" })
    ], { spacing: 4, align: "center" });
    return bouncing ? View.animate(col, "bounce") : col;
  }

  var contextLine = matchGroupLabel(match) +
    (match.venue ? " · " + match.venue : "") +
    (match.city ? ", " + match.city : "");

  var content = View.hstack([
    View.spacer(),
    heroTeam(match.home, celebratingThis && celebration.side === "home"),
    View.frame(
      View.vstack([
        centerTop,
        centerBottom,
        View.text(contextLine, { style: "footnote", color: FAINT, lineLimit: 1 })
      ], { spacing: 3, align: "center" }),
      { width: 180 }
    ),
    heroTeam(match.away, celebratingThis && celebration.side === "away"),
    View.spacer()
  ], { spacing: 14, align: "center" });

  return View.frame(
    View.cornerRadius(
      View.background(
        View.padding(content, { edges: "all", amount: 12 }),
        { r: 1, g: 1, b: 1, a: 0.06 }
      ),
      12
    ),
    { maxWidth: 9999 }
  );
}

function dayHeader(label) {
  return View.padding(
    View.text(label.toUpperCase(), { style: "footnote", color: FAINT }),
    { edges: "vertical", amount: 2 }
  );
}

function rowsWithDayHeaders(list) {
  var out = [];
  var lastDay = null;
  for (var i = 0; i < list.length; i++) {
    var label = dayLabel(list[i].kickoffMs);
    if (label !== lastDay) {
      out.push(dayHeader(label));
      lastDay = label;
    }
    out.push(fixtureRow(list[i]));
  }
  return out;
}

function tabContent() {
  var now = Date.now();
  var list, emptyText;

  if (activeTab === "today") {
    var today = dayKey(now);
    list = matches.filter(function (m) { return dayKey(m.kickoffMs) === today; });
    // live first, then upcoming, then finished
    list.sort(function (a, b) {
      var rank = function (m) { return isLive(m) ? 0 : (m.state === "pre" ? 1 : 2); };
      return rank(a) - rank(b) || a.kickoffMs - b.kickoffMs;
    });
    emptyText = "No matches today";

    if (list.length > 0) {
      // Hero: the live match (or the featured one if it's today), big and
      // front-and-center; everything else lists below.
      var hero = null;
      for (var h = 0; h < list.length; h++) {
        if (isLive(list[h])) { hero = list[h]; break; }
      }
      if (!hero) {
        var feat = featuredMatch();
        if (feat && dayKey(feat.kickoffMs) === today) hero = feat;
      }
      if (!hero) hero = list[0];

      var rest = list.filter(function (m) { return m.id !== hero.id; });
      var kids = [heroCard(hero)];
      if (rest.length > 0) {
        kids.push(dayHeader("More today"));
        for (var r = 0; r < rest.length; r++) kids.push(fixtureRow(rest[r]));
      }
      return View.scroll(
        View.vstack(kids, { spacing: 6, align: "leading" }),
        { axes: "vertical", showsIndicators: false }
      );
    }
  } else if (activeTab === "fixtures") {
    list = matches.filter(function (m) { return m.state === "pre" && m.kickoffMs > now - 5 * 60 * 1000; });
    emptyText = "No upcoming fixtures in the next week";
  } else {
    list = matches.filter(function (m) { return m.state === "post"; });
    list.sort(function (a, b) { return b.kickoffMs - a.kickoffMs; });
    emptyText = "No recent results";
  }

  if (list.length === 0) {
    return View.frame(
      View.vstack([
        View.icon("soccerball", { size: 20, color: FAINT }),
        View.text(fetchError ? "Can't reach ESPN — retrying" : emptyText, { style: "footnote", color: DIM })
      ], { spacing: 6, align: "center" }),
      { maxWidth: 9999, maxHeight: 9999, alignment: "center" }
    );
  }

  var children = activeTab === "today"
    ? list.map(fixtureRow)
    : rowsWithDayHeaders(list);

  return View.scroll(
    View.vstack(children, { spacing: 4, align: "leading" }),
    { axes: "vertical", showsIndicators: false }
  );
}

function fullExpandedView() {
  var ageSec = lastFetchOK ? Math.max(0, Math.round((Date.now() - lastFetchOK) / 1000)) : null;
  var liveCount = liveMatches().length;

  var header = View.hstack([
    View.icon("soccerball.inverse", { size: 13, color: PITCH_GREEN }),
    View.text("World Cup 2026", { style: "caption", color: "white" }),
    liveCount > 0 ? View.hstack([
      liveDot(4),
      View.text(liveCount + " live", { style: "footnote", color: LIVE_RED })
    ], { spacing: 3, align: "center" }) : null,
    View.spacer(),
    tabButton("today", "Today"),
    tabButton("fixtures", "Fixtures"),
    tabButton("results", "Results")
  ], { spacing: 6, align: "center" });

  var footer = View.padding(
    View.hstack([
      View.text(
        fetchError ? "ESPN unreachable — retrying" :
          (ageSec === null ? "Loading…" : "Live data: ESPN · updated " + ageSec + "s ago"),
        { style: "footnote", color: FAINT }
      ),
      View.spacer(),
      View.button(View.icon("arrow.clockwise", { size: 10, color: DIM }), "refresh"),
      View.button(View.icon("safari", { size: 10, color: DIM }), "open-web")
    ], { spacing: 8, align: "center" }),
    { edges: "vertical", amount: 6 }
  );

  return View.vstack([
    header,
    View.frame(tabContent(), { maxWidth: 9999, maxHeight: 9999 }),
    footer
  ], { spacing: 6, align: "leading" });
}

// ---------------------------------------------------------------------------
// Module registration
// ---------------------------------------------------------------------------

SuperIsland.registerModule({
  onActivate: function () {
    fetchStandings();
    refreshNow();
    if (heartbeatID === null) {
      heartbeatID = setInterval(heartbeat, 5000);
    }
  },

  onDeactivate: function () {
    if (heartbeatID !== null) { clearInterval(heartbeatID); heartbeatID = null; }
  },

  onAction: function (actionID) {
    if (actionID === "prev") { stepFeatured(-1); return; }
    if (actionID === "next") { stepFeatured(1); return; }
    if (actionID === "refresh") { lastFetchAt = 0; refreshNow(); return; }
    if (actionID === "open-web") { SuperIsland.openURL(SCOREBOARD_URL); return; }
    if (actionID.indexOf("tab-") === 0) {
      activeTab = actionID.slice(4);
      SuperIsland.playFeedback("selection");
      return;
    }
    if (actionID.indexOf("feat-") === 0) {
      manualFeaturedID = actionID.slice(5);
      manualFeaturedUntil = Date.now() + MANUAL_HOLD_MS;
      SuperIsland.playFeedback("selection");
      return;
    }
  },

  compact: compactView,

  minimalCompact: {
    leading: minimalLeading,
    trailing: minimalTrailing,
    precedence: function () {
      // 1 holds the notch (the host yields to media for any value > 1,
      // see AppState.compactPresentationModule); 0 hands the notch back
      // to music/default when no match is on.
      if (isCelebrating() || liveMatches().length > 0) return 1;
      return 0;
    }
  },

  expanded: expandedView,

  fullExpanded: fullExpandedView
});
