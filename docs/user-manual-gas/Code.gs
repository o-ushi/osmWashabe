/**
 * osmWashabe 操作マニュアル翻訳
 *
 * 日本語マスターのスライド構成を英語版・ベトナム語版ファイルへコピーし、
 * テキストだけを翻訳して上書きする。ファイル ID は変えない（アプリのヘルプ URL を維持）。
 *
 * 他ファイルへスライドをコピーすると、見た目は青字リンクでも
 * 飛び先がマスター側のスライド ID のままになる。クリックしても反応しない。
 * そのためリンクはマスターから「何枚目へ飛ぶか」を記録し、翻訳後に
 * 英語・ベトナム語ファイル側の同じ番号のスライドへ付け直す。
 *
 * 使い方は README.md を参照。
 */

var MASTER_ID = '1z40A2lvJK4UUnBNcvAC5vGWfLwaa9ZmCjFMZlPQ-h_0';
var TARGET_EN_ID = '1F0O1UzMktD5VMwhOdNF1KoOG7Fl1lFMz1EEpgxgVapM';
var TARGET_VI_ID = '114UigCR54j4tQdUayjALDJPrCLAoOGbTXMDlv_UtEDU';

function onOpen() {
  SlidesApp.getUi()
    .createMenu('マニュアル翻訳')
    .addItem('英語版を更新', 'updateEnglish')
    .addItem('ベトナム語版を更新', 'updateVietnamese')
    .addItem('英語とベトナム語を両方更新', 'updateBoth')
    .addToUi();
}

function updateEnglish() {
  syncAndTranslate_(TARGET_EN_ID, 'en');
}

function updateVietnamese() {
  syncAndTranslate_(TARGET_VI_ID, 'vi');
}

function updateBoth() {
  syncAndTranslate_(TARGET_EN_ID, 'en');
  syncAndTranslate_(TARGET_VI_ID, 'vi');
}

function syncAndTranslate_(targetId, lang) {
  var ui = SlidesApp.getUi();
  var master = SlidesApp.openById(MASTER_ID);
  var target = SlidesApp.openById(targetId);

  var linkPlan = collectLinkPlan_(master);
  copyMasterSlides_(master, target);
  var stats = translatePresentation_(target, lang);
  applyLinkPlan_(target, linkPlan, lang, stats);

  var message =
    (lang === 'en' ? '英語版' : 'ベトナム語版') +
    'を更新しました。\n' +
    'テキスト枠: ' +
    stats.boxes +
    '\n辞書ヒット: ' +
    stats.glossary +
    '\n機械翻訳: ' +
    stats.machine +
    '\nリンク復元: ' +
    stats.links +
    '\nスキップ: ' +
    stats.skipped;
  ui.alert(message);
}

function copyMasterSlides_(master, target) {
  var srcSlides = master.getSlides();
  var destSlides = target.getSlides();
  var i;
  for (i = destSlides.length - 1; i >= 1; i--) {
    destSlides[i].remove();
  }
  for (i = 0; i < srcSlides.length; i++) {
    target.appendSlide(srcSlides[i]);
  }
  target.getSlides()[0].remove();
}

function translatePresentation_(presentation, lang) {
  var stats = { boxes: 0, glossary: 0, machine: 0, skipped: 0, links: 0, cache: {} };
  var slides = presentation.getSlides();
  for (var i = 0; i < slides.length; i++) {
    translatePageElements_(slides[i].getPageElements(), lang, stats);
  }
  return stats;
}

function translatePageElements_(elements, lang, stats) {
  for (var i = 0; i < elements.length; i++) {
    var el = elements[i];
    var type = el.getPageElementType();
    if (type === SlidesApp.PageElementType.SHAPE) {
      translateTextRange_(el.asShape().getText(), lang, stats, false);
    } else if (type === SlidesApp.PageElementType.TABLE) {
      translateTable_(el.asTable(), lang, stats);
    } else if (type === SlidesApp.PageElementType.GROUP) {
      translatePageElements_(el.asGroup().getChildren(), lang, stats);
    }
  }
}

function translateTable_(table, lang, stats) {
  var rows = table.getNumRows();
  var cols = table.getNumColumns();
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      var cell = table.getCell(r, c);
      if (!isHeadTableCell_(cell)) continue;
      translateTextRange_(cell.getText(), lang, stats, true);
    }
  }
}

/** 結合セルは左上だけ翻訳する。それ以外は getText が例外になる。 */
function isHeadTableCell_(cell) {
  try {
    if (
      cell.getMergeState &&
      SlidesApp.CellMergeState &&
      cell.getMergeState() === SlidesApp.CellMergeState.MERGED
    ) {
      return false;
    }
  } catch (e) {}
  try {
    cell.getText();
    return true;
  } catch (e) {
    return false;
  }
}

function translateTextRange_(textRange, lang, stats, inTable) {
  var original = textRange.asString();
  if (!original || !original.replace(/\s/g, '')) {
    return;
  }
  stats.boxes++;
  var translated = translatePreservingBreaks_(original, lang, stats);
  if (inTable) {
    translated = flattenSpuriousBreaks_(original, translated);
  }
  if (translated !== original) {
    textRange.setText(translated);
  }
}

function collectLinkPlan_(presentation) {
  var slides = presentation.getSlides();
  var indexById = {};
  var i;
  for (i = 0; i < slides.length; i++) {
    indexById[slides[i].getObjectId()] = i;
  }
  var plan = [];
  for (i = 0; i < slides.length; i++) {
    collectElementLinkPlan_(slides[i].getPageElements(), [i], indexById, plan);
  }
  return plan;
}

function collectElementLinkPlan_(elements, path, indexById, plan) {
  for (var i = 0; i < elements.length; i++) {
    var el = elements[i];
    var here = path.concat([i]);
    var host = asLinkable_(el);
    var objectLink = describeLink_(getHostLink_(host), indexById);
    if (objectLink) {
      plan.push({ kind: 'object', path: here, link: objectLink });
    }
    var type = el.getPageElementType();
    if (type === SlidesApp.PageElementType.SHAPE) {
      collectTextLinkPlan_(el.asShape().getText(), here.concat(['text']), indexById, plan);
    } else if (type === SlidesApp.PageElementType.TABLE) {
      collectTableLinkPlan_(el.asTable(), here, indexById, plan);
    } else if (type === SlidesApp.PageElementType.GROUP) {
      collectElementLinkPlan_(el.asGroup().getChildren(), here, indexById, plan);
    }
  }
}

function collectTableLinkPlan_(table, path, indexById, plan) {
  var rows = table.getNumRows();
  var cols = table.getNumColumns();
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      var cell = table.getCell(r, c);
      if (!isHeadTableCell_(cell)) continue;
      collectTextLinkPlan_(
        cell.getText(),
        path.concat(['table', r, c]),
        indexById,
        plan,
      );
    }
  }
}

function collectTextLinkPlan_(textRange, path, indexById, plan) {
  var links = [];
  try {
    links = textRange.getLinks() || [];
  } catch (e) {
    links = [];
  }
  var i;
  for (i = 0; i < links.length; i++) {
    var range = links[i];
    var desc = describeLink_(range.getTextStyle().getLink(), indexById);
    var text = range.asString().replace(/[\n\v]+$/g, '');
    if (desc && text) {
      plan.push({ kind: 'text', path: path, text: text, link: desc });
    }
  }
}

function getHostLink_(host) {
  if (!host || !host.getLink) return null;
  try {
    return host.getLink();
  } catch (e) {
    return null;
  }
}

function describeLink_(link, indexById) {
  if (!link) return null;
  var type = null;
  try {
    type = link.getLinkType();
  } catch (e) {
    return null;
  }
  var typeName = String(type);
  if (type === SlidesApp.LinkType.URL || typeName === 'URL') {
    var url = null;
    try {
      url = link.getUrl();
    } catch (e) {}
    return url ? { kind: 'url', url: url } : null;
  }
  if (type === SlidesApp.LinkType.SLIDE_POSITION || typeName === 'SLIDE_POSITION') {
    try {
      return { kind: 'position', position: link.getSlidePosition() };
    } catch (e) {
      return null;
    }
  }
  var idx = null;
  try {
    var slide = link.getLinkedSlide();
    if (slide) idx = indexById[slide.getObjectId()];
  } catch (e) {}
  if (idx == null) {
    try {
      var sid = link.getSlideId();
      if (sid != null && indexById[sid] != null) idx = indexById[sid];
    } catch (e) {}
  }
  if (idx == null) {
    try {
      idx = link.getSlideIndex();
    } catch (e) {}
  }
  if (idx == null) return null;
  return { kind: 'slide', index: idx };
}

function applyLinkPlan_(presentation, plan, lang, stats) {
  var slides = presentation.getSlides();
  var i;
  for (i = 0; i < plan.length; i++) {
    var item = plan[i];
    try {
      if (item.kind === 'object') {
        var host = asLinkable_(elementAtPath_(slides, item.path));
        if (applyDescribedLink_(host, item.link, slides)) stats.links++;
      } else if (item.kind === 'text') {
        var textRange = textAtPath_(slides, item.path);
        if (linkTextInRange_(textRange, item.text, item.link, slides, lang, stats)) {
          stats.links++;
        }
      }
    } catch (e) {}
  }
}

function elementAtPath_(slides, path) {
  var elements = slides[path[0]].getPageElements();
  var el = elements[path[1]];
  var k = 2;
  while (k < path.length && path[k] !== 'text' && path[k] !== 'table') {
    el = el.asGroup().getChildren()[path[k]];
    k++;
  }
  return el;
}

function textAtPath_(slides, path) {
  var el = elementAtPath_(slides, path);
  var k = 2;
  while (k < path.length && path[k] !== 'text' && path[k] !== 'table') {
    k++;
  }
  if (path[k] === 'table') {
    return el.asTable().getCell(path[k + 1], path[k + 2]).getText();
  }
  return el.asShape().getText();
}

function linkTextInRange_(textRange, originalNeedle, desc, slides, lang, stats) {
  var full = textRange.asString();
  var needles = [originalNeedle];
  if (hasJapanese_(originalNeedle)) {
    needles.push(translatePreservingBreaks_(originalNeedle, lang, stats));
  }
  var n;
  for (n = 0; n < needles.length; n++) {
    var needle = needles[n];
    if (!needle) continue;
    var idx = full.indexOf(needle);
    if (idx < 0) continue;
    var end = idx + needle.length;
    while (end > idx && (full.charAt(end - 1) === '\n' || full.charAt(end - 1) === '\v')) {
      end--;
    }
    if (end <= idx) continue;
    return applyDescribedLink_(textRange.getRange(idx, end).getTextStyle(), desc, slides);
  }
  return false;
}

function applyDescribedLink_(host, desc, slides) {
  if (!host || !desc) return false;
  try {
    if (desc.kind === 'url') {
      host.setLinkUrl(desc.url);
      return true;
    }
    if (desc.kind === 'position') {
      host.setLinkSlide(desc.position);
      return true;
    }
    if (desc.kind === 'slide' && slides[desc.index]) {
      host.setLinkSlide(slides[desc.index]);
      return true;
    }
  } catch (e) {
    return false;
  }
  return false;
}

function asLinkable_(el) {
  var type = el.getPageElementType();
  try {
    if (type === SlidesApp.PageElementType.SHAPE) return el.asShape();
    if (type === SlidesApp.PageElementType.IMAGE) return el.asImage();
    if (type === SlidesApp.PageElementType.GROUP) return el.asGroup();
    if (type === SlidesApp.PageElementType.LINE) return el.asLine();
    if (
      SlidesApp.PageElementType.WORD_ART &&
      type === SlidesApp.PageElementType.WORD_ART
    ) {
      return el.asWordArt();
    }
  } catch (e) {}
  return el;
}

/**
 * 改行・タブ・縦タブは区切りのまま残し、日本語の断片だけ翻訳する。
 * 索引のページ番号列（タブ揃え）を潰さない。
 */
function translatePreservingBreaks_(original, lang, stats) {
  var parts = String(original).split(/(\n|\v|\t+)/);
  var out = [];
  var i;
  for (i = 0; i < parts.length; i++) {
    var part = parts[i];
    if (part === '') continue;
    if (part === '\n' || part === '\v' || /^\t+$/.test(part) || !part.replace(/\s/g, '')) {
      out.push(part);
      continue;
    }
    var translated = translateString_(part, lang, stats);
    if (!/[\n\v]/.test(part)) {
      translated = stripInjectedNewlines_(translated);
    }
    out.push(translated);
  }
  return out.join('');
}

function flattenSpuriousBreaks_(original, translated) {
  var origCore = String(original).replace(/\r/g, '').replace(/\n+$/, '');
  if (/[\n\v]/.test(origCore) || !origCore.replace(/\s/g, '')) {
    return translated;
  }
  return stripInjectedNewlines_(translated);
}

function stripInjectedNewlines_(text) {
  return String(text).replace(/\r/g, '').replace(/\n+/g, ' ').replace(/ {2,}/g, ' ');
}

function translateString_(original, lang, stats) {
  if (!hasJapanese_(original)) {
    stats.skipped++;
    return original;
  }

  var glossary = lang === 'vi' ? GLOSSARY_VI : GLOSSARY_EN;
  var exact = lookupGlossary_(original, glossary);
  if (exact !== null) {
    stats.glossary++;
    return exact;
  }

  var withTerms = applyLongestKeys_(original, glossary);
  if (!hasJapanese_(withTerms)) {
    stats.glossary++;
    return withTerms;
  }

  if (stats.cache[withTerms]) {
    stats.machine++;
    return stats.cache[withTerms];
  }

  var machine = LanguageApp.translate(withTerms, 'ja', lang);
  stats.cache[withTerms] = machine;
  stats.machine++;
  return machine;
}

function lookupGlossary_(text, glossary) {
  if (glossary[text]) {
    return glossary[text];
  }
  var trimmed = text.replace(/\s+$/g, '').replace(/^\s+/g, '');
  if (trimmed !== text && glossary[trimmed]) {
    return text.replace(trimmed, glossary[trimmed]);
  }
  return null;
}

function applyLongestKeys_(text, glossary) {
  var keys = Object.keys(glossary).sort(function (a, b) {
    return b.length - a.length;
  });
  var out = text;
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i];
    if (key.length < 2) continue;
    if (out.indexOf(key) !== -1) {
      out = out.split(key).join(glossary[key]);
    }
  }
  return out;
}

function hasJapanese_(text) {
  return /[\u3040-\u30ff\u3400-\u9fff]/.test(text);
}
