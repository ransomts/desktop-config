// Typo-tolerant matching for the pick lists and the launcher. Used only when nothing
// matches what was typed exactly, so correct typing never changes the order of results.
.pragma library

// How many slips a typed word of this length may contain.
function allowed(n) { return n < 4 ? 0 : n < 7 ? 1 : 2 }

// Edit distance between a and b (insert, delete, replace, or swap two neighbours),
// or 99 as soon as it is certain to exceed `max`.
function distance(a, b, max) {
    const n = a.length, m = b.length
    if (Math.abs(n - m) > max) return 99
    let prev2 = null, prev = [], cur = []
    for (let j = 0; j <= m; j++) prev[j] = j
    for (let i = 1; i <= n; i++) {
        cur = [i]
        let best = i
        for (let j = 1; j <= m; j++) {
            const cost = a.charCodeAt(i - 1) === b.charCodeAt(j - 1) ? 0 : 1
            let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            if (prev2 && i > 1 && j > 1 && a.charCodeAt(i - 1) === b.charCodeAt(j - 2) && a.charCodeAt(i - 2) === b.charCodeAt(j - 1))
                v = Math.min(v, prev2[j - 2] + 1)
            cur[j] = v
            if (v < best) best = v
        }
        if (best > max) return 99
        prev2 = prev; prev = cur
    }
    return prev[m]
}

// How far the typed word is from this token: 0 if the token contains it, otherwise the
// fewest slips against the token or against its start (the word may be half typed).
// A match against only the start of a longer token, or one that changes the first
// letter, counts half a slip worse, so "tacco" ranks "taco" above "account".
// -1 if it is not close.
function near(word, token) {
    if (token.indexOf(word) !== -1) return 0
    const max = allowed(word.length)
    if (max === 0) return -1
    const first = word.charCodeAt(0) === token.charCodeAt(0) ? 0 : 0.5
    let best = distance(word, token, max)
    if (best <= max) best += first
    for (let len = word.length - 1; len <= word.length + 1; len++) {
        if (len < 3 || len >= token.length) continue
        const d = distance(word, token.slice(0, len), max)
        if (d <= max) best = Math.min(best, d + 0.5 + first)
    }
    return best <= max + 1 && best < 99 ? best : -1
}

function tokens(text) { return text.toLowerCase().split(/[^a-z0-9]+/).filter(t => t.length > 1) }

// Total slips needed for every typed word to match some token (or -1 if any word matches none).
// `exact(word)` may say a word already matches by other means (substring, another name).
function score(words, toks, exact) {
    let total = 0
    for (const w of words) {
        if (exact && exact(w)) continue
        let best = -1
        for (const t of toks) {
            const d = near(w, t)
            if (d !== -1 && (best === -1 || d < best)) { best = d; if (d === 0) break }
        }
        if (best === -1) return -1
        total += best
    }
    return total
}
