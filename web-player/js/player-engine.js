import { resolveAyah, fileUrl } from './audio-resolver.js';
import { findThumnFor } from './thumn.js';

function posCompare(s1, a1, s2, a2) {
  return s1 !== s2 ? s1 - s2 : a1 - a2;
}

/**
 * Plays through a reciter's resolved audio for one surah "page", with two
 * independent repeat axes (ayah, and one of range/thumn/surah) plus gapless
 * transitions via two alternating <audio> elements: while one plays, the
 * other is preloaded with whatever file comes next, so 'ended' just swaps
 * roles and calls play() on an element that's (ideally) already buffered.
 *
 * Forward progression is always capped at the end of `pageSurah` (the surah
 * this player page is showing) EXCEPT while a thumn repeat's own span
 * genuinely crosses into another surah — that crossing is the point of thumn
 * repeat. Once a structural repeat's iterations are spent, playback keeps
 * reading forward (matching the mobile app's documented behaviour) but stays
 * capped at the page's surah end rather than wandering into surahs this page
 * never rendered.
 */
export class PlayerEngine {
  constructor({ pageSurah, surahs, overrides, timings, baseUrl, thumns, onAyahChange, onStop, onError }) {
    this.pageSurah = pageSurah;
    this.surahs = surahs;
    this.surahMap = new Map(surahs.map((s) => [s.number, s]));
    this.overrides = overrides;
    /** Present only for timed mirrors (one MP3 per surah + ayah spans). */
    this.timings = timings || null;
    this.baseUrl = baseUrl;
    this.thumns = thumns || [];
    this.onAyahChange = onAyahChange || (() => {});
    this.onStop = onStop || (() => {});
    this.onError = onError || (() => {});

    this.audioA = new Audio();
    this.audioB = new Audio();
    this.audioA.preload = 'auto';
    this.audioB.preload = 'auto';
    this.active = this.audioA;
    this.standby = this.audioB;

    this.speed = 1;
    this.playing = false;

    this.pos = null; // {surah, ayah}
    this.fileIdx = 0;

    this.ayahRepeatMode = 'off'; // off | count | infinite
    this.ayahRepeatCount = 3;
    this._ayahRepeatsDone = 0;

    this.structuralKind = null; // null | 'range' | 'thumn' | 'surah'
    this.structuralMode = 'off';
    this.structuralCount = 3;
    this._structuralRepeatsDone = 0;
    this.unit = null; // {startSurah, startAyah, endSurah, endAyah} (end null = unbounded)

    this._prepared = null;

    this.audioA.addEventListener('ended', () => this._advance(false));
    this.audioB.addEventListener('ended', () => this._advance(false));
    this.audioA.addEventListener('error', () => this._advance(true));
    this.audioB.addEventListener('error', () => this._advance(true));
  }

  // ── position helpers ──────────────────────────────────────────────

  _resolve(surah, ayah) {
    return resolveAyah(this.overrides, surah, ayah, this.timings);
  }

  _clipsFor(pos) {
    return this._resolve(pos.surah, pos.ayah).clips;
  }

  /**
   * Starts `audio` at a clip's offset and, for a clipped source, arranges for
   * it to stop at the clip's end.
   *
   * A whole file just plays to its natural 'ended'. A clip has no such event,
   * so the end is watched two ways: `timeupdate` (native, but only ~4x/sec) and
   * a timer for the exact remaining time, whichever fires first. The timer is
   * scaled by playbackRate, and re-armed by setSpeed, so changing speed
   * mid-ayah does not overrun the boundary.
   */
  _startClip(audio, clip) {
    this._clearClipWatch(audio);
    audio.playbackRate = this.speed;

    const begin = () => {
      try {
        audio.currentTime = clip.start || 0;
      } catch (e) {
        /* seeking before metadata — the loadedmetadata path below retries */
      }
      audio.play().catch(() => {});
      if (clip.end != null) this._armClipEnd(audio, clip);
    };

    if (clip.start && audio.readyState < 1) {
      audio.addEventListener('loadedmetadata', begin, { once: true });
      audio._clipSeekPending = begin;
    } else {
      begin();
    }
  }

  _armClipEnd(audio, clip) {
    this._clearClipWatch(audio);
    audio._clipEnd = clip.end;
    const onTick = () => {
      if (audio !== this.active || !this.playing) return;
      if (audio.currentTime >= audio._clipEnd) {
        this._clearClipWatch(audio);
        this._advance(false);
      }
    };
    audio._clipTick = onTick;
    audio.addEventListener('timeupdate', onTick);
    const remain = (clip.end - audio.currentTime) / (this.speed || 1);
    if (remain > 0) {
      audio._clipTimer = setTimeout(() => {
        if (audio === this.active && this.playing) {
          this._clearClipWatch(audio);
          this._advance(false);
        }
      }, remain * 1000);
    }
  }

  _clearClipWatch(audio) {
    if (audio._clipTimer) {
      clearTimeout(audio._clipTimer);
      audio._clipTimer = null;
    }
    if (audio._clipTick) {
      audio.removeEventListener('timeupdate', audio._clipTick);
      audio._clipTick = null;
    }
    if (audio._clipSeekPending) {
      audio.removeEventListener('loadedmetadata', audio._clipSeekPending);
      audio._clipSeekPending = null;
    }
  }

  _nextAyahPos(surah, ayah) {
    const surahData = this.surahMap.get(surah);
    if (ayah + 1 <= surahData.ayahCount) return { surah, ayah: ayah + 1 };
    if (surah + 1 <= 114) return { surah: surah + 1, ayah: 1 };
    return null;
  }

  _findPlayableFrom(surah, ayah, boundEnd) {
    let cur = { surah, ayah };
    while (cur) {
      if (boundEnd && posCompare(cur.surah, cur.ayah, boundEnd.surah, boundEnd.ayah) >= 0) return null;
      const { clips } = this._resolve(cur.surah, cur.ayah);
      if (clips.length > 0) return cur;
      cur = this._nextAyahPos(cur.surah, cur.ayah);
    }
    return null;
  }

  _pageBoundEnd() {
    return this.pageSurah < 114 ? { surah: this.pageSurah + 1, ayah: 1 } : null;
  }

  _unitBoundEnd() {
    if (!this.unit) return null;
    return this.unit.endSurah != null ? { surah: this.unit.endSurah, ayah: this.unit.endAyah } : null;
  }

  // ── the step-planning core, used both to advance and to preload ────

  _planNext(pos, fileIdx, ayahRepeatsDone, structuralRepeatsDone) {
    const clips = this._clipsFor(pos);
    if (fileIdx + 1 < clips.length) {
      return { pos, fileIdx: fileIdx + 1, isNewAyah: false, ayahRepeatsDone, structuralRepeatsDone };
    }

    if (
      this.ayahRepeatMode === 'infinite' ||
      (this.ayahRepeatMode === 'count' && ayahRepeatsDone + 1 < this.ayahRepeatCount)
    ) {
      return { pos, fileIdx: 0, isNewAyah: false, ayahRepeatsDone: ayahRepeatsDone + 1, structuralRepeatsDone };
    }

    const pageBound = this._pageBoundEnd();
    const activeBound = this.unit ? this._unitBoundEnd() : pageBound;
    const afterPos = this._nextAyahPos(pos.surah, pos.ayah);
    let next = afterPos ? this._findPlayableFrom(afterPos.surah, afterPos.ayah, activeBound) : null;

    if (next === null) {
      const canLoop =
        this.unit &&
        (this.structuralMode === 'infinite' ||
          (this.structuralMode === 'count' && structuralRepeatsDone + 1 < this.structuralCount));
      if (canLoop) {
        const start = this._findPlayableFrom(this.unit.startSurah, this.unit.startAyah, activeBound);
        if (start) {
          return {
            pos: start,
            fileIdx: 0,
            isNewAyah: true,
            ayahRepeatsDone: 0,
            structuralRepeatsDone: structuralRepeatsDone + 1,
          };
        }
      }
      next = afterPos ? this._findPlayableFrom(afterPos.surah, afterPos.ayah, pageBound) : null;
    }

    if (next === null) return null;
    return { pos: next, fileIdx: 0, isNewAyah: true, ayahRepeatsDone: 0, structuralRepeatsDone };
  }

  // ── gapless transition machinery ────────────────────────────────────

  _prepareNext() {
    if (!this.playing || !this.pos) return;
    const step = this._planNext(this.pos, this.fileIdx, this._ayahRepeatsDone, this._structuralRepeatsDone);
    this._prepared = step;
    if (!step) {
      this.standby.removeAttribute('src');
      return;
    }
    const clip = this._clipsFor(step.pos)[step.fileIdx];
    const url = fileUrl(this.baseUrl, clip.stem);
    // For a timed mirror the next ayah is usually in the file already loaded on
    // this element — reassigning src would throw away the buffer and re-fetch a
    // ~90 MB surah, so only set it when it actually changes.
    if (this.standby.src !== url) {
      this.standby.src = url;
      this.standby.load();
    }
    this.standby.playbackRate = this.speed;
  }

  _advance(wasError) {
    if (!this.playing) return;
    if (wasError) this.onError({ pos: this.pos, fileIdx: this.fileIdx });

    this._clearClipWatch(this.standby);
    [this.active, this.standby] = [this.standby, this.active];
    let step = this._prepared;

    if (!step) {
      // Preload hadn't landed yet (e.g. settings changed right at the boundary) — recompute now.
      step = this._planNext(this.pos, this.fileIdx, this._ayahRepeatsDone, this._structuralRepeatsDone);
      if (step) {
        const clip = this._clipsFor(step.pos)[step.fileIdx];
        const url = fileUrl(this.baseUrl, clip.stem);
        if (this.active.src !== url) this.active.src = url;
      }
    }

    if (!step) {
      this._stopInternal(true);
      return;
    }

    this.pos = step.pos;
    this.fileIdx = step.fileIdx;
    this._ayahRepeatsDone = step.ayahRepeatsDone;
    this._structuralRepeatsDone = step.structuralRepeatsDone;

    this._startClip(this.active, this._clipsFor(this.pos)[this.fileIdx]);

    if (step.isNewAyah) {
      const { coveredBy } = this._resolve(this.pos.surah, this.pos.ayah);
      this.onAyahChange({ surah: this.pos.surah, ayah: this.pos.ayah, coveredBy });
    }

    this._prepareNext();
  }

  // ── public transport controls ───────────────────────────────────────

  playFrom(surah, ayah) {
    this._stopInternal(false);
    const start = this._findPlayableFrom(surah, ayah, null);
    if (!start) return;

    this.playing = true;
    this.pos = start;
    this.fileIdx = 0;
    this._ayahRepeatsDone = 0;
    this._structuralRepeatsDone = 0;

    const clip = this._clipsFor(this.pos)[0];
    const url = fileUrl(this.baseUrl, clip.stem);
    if (this.active.src !== url) this.active.src = url;
    this._startClip(this.active, clip);

    const { coveredBy } = this._resolve(this.pos.surah, this.pos.ayah);
    this.onAyahChange({ surah: this.pos.surah, ayah: this.pos.ayah, coveredBy });

    this._prepareNext();
  }

  stop() {
    this._stopInternal(true);
  }

  _stopInternal(notify) {
    const wasPlaying = this.playing;
    this.playing = false;
    this._clearClipWatch(this.audioA);
    this._clearClipWatch(this.audioB);
    this.audioA.pause();
    this.audioA.removeAttribute('src');
    this.audioB.pause();
    this.audioB.removeAttribute('src');
    this._prepared = null;
    if (notify && wasPlaying) this.onStop();
  }

  isPlaying() {
    return this.playing;
  }

  currentPos() {
    return this.pos ? { ...this.pos } : null;
  }

  setSpeed(x) {
    this.speed = x;
    this.active.playbackRate = x;
    this.standby.playbackRate = x;
    // A clip's stop timer was sized for the old rate; re-arm it or the ayah
    // would run past its boundary (slower) or be cut short (faster).
    if (this.playing && this.pos) {
      const clip = this._clipsFor(this.pos)[this.fileIdx];
      if (clip && clip.end != null) this._armClipEnd(this.active, clip);
    }
  }

  // ── ayah repeat (restarts the current ayah immediately) ────────────

  setAyahRepeat(mode, count) {
    this.ayahRepeatMode = mode;
    if (count) this.ayahRepeatCount = count;
    this._ayahRepeatsDone = 0;
    if (this.playing && this.pos) {
      this.fileIdx = 0;
      const clip = this._clipsFor(this.pos)[0];
      const url = fileUrl(this.baseUrl, clip.stem);
      if (this.active.src !== url) this.active.src = url;
      this._startClip(this.active, clip);
      this._prepareNext();
    }
  }

  // ── structural repeat (range / thumn / surah) — lets the current unit
  //    finish naturally before looping ─────────────────────────────────

  engageRange(surah, fromAyah, toAyah, mode, count) {
    const endPos = this._nextAyahPos(surah, toAyah);
    this.structuralKind = 'range';
    this.unit = {
      startSurah: surah,
      startAyah: fromAyah,
      endSurah: endPos ? endPos.surah : null,
      endAyah: endPos ? endPos.ayah : null,
    };
    this.structuralMode = mode;
    if (count) this.structuralCount = count;
    this._structuralRepeatsDone = 0;
    this._prepareNext();
  }

  engageThumnAt(surah, ayah, mode, count) {
    const t = findThumnFor(this.thumns, surah, ayah);
    if (!t) return false;
    this.structuralKind = 'thumn';
    this.unit = { startSurah: t.startSurah, startAyah: t.startAyah, endSurah: t.endSurah, endAyah: t.endAyah };
    this.structuralMode = mode;
    if (count) this.structuralCount = count;
    this._structuralRepeatsDone = 0;
    this._prepareNext();
    return true;
  }

  engageSurah(surah, mode, count) {
    const endPos = surah < 114 ? { surah: surah + 1, ayah: 1 } : null;
    this.structuralKind = 'surah';
    this.unit = {
      startSurah: surah,
      startAyah: 1,
      endSurah: endPos ? endPos.surah : null,
      endAyah: endPos ? endPos.ayah : null,
    };
    this.structuralMode = mode;
    if (count) this.structuralCount = count;
    this._structuralRepeatsDone = 0;
    this._prepareNext();
  }

  disengageStructural() {
    this.structuralKind = null;
    this.unit = null;
    this.structuralMode = 'off';
    this._structuralRepeatsDone = 0;
    this._prepareNext();
  }

  currentThumn() {
    if (!this.pos) return null;
    return findThumnFor(this.thumns, this.pos.surah, this.pos.ayah);
  }
}
