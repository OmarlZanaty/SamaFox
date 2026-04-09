"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.firstStr = firstStr;
exports.intParam = intParam;
function firstStr(v) {
    if (typeof v === 'string')
        return v;
    if (Array.isArray(v) && typeof v[0] === 'string')
        return v[0];
    return undefined;
}
function intParam(v, fallback) {
    const s = firstStr(v);
    if (s == null)
        return fallback;
    const n = parseInt(s, 10);
    return Number.isFinite(n) ? n : fallback;
}
//# sourceMappingURL=http.js.map