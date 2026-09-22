.pragma library

function clamp(value, min, max) {
  var n = Number(value)
  if (!isFinite(n)) return min
  if (n < min) return min
  if (n > max) return max
  return n
}

function parseState(raw) {
  var parsed = {}
  try { parsed = JSON.parse(String(raw || "{}")) || {} } catch (e) { parsed = {} }
  return {
    device: String(parsed.device || ""),
    sensitivity: clamp(parsed.sensitivity, -1, 1),
    accel_profile: parsed.accel_profile === "flat" ? "flat" : "adaptive",
    scroll_factor: clamp(parsed.scroll_factor, 0.05, 5),
    natural_scroll: !!parsed.natural_scroll,
    disable_while_typing: parsed.disable_while_typing !== false,
    clickfinger_behavior: parsed.clickfinger_behavior !== false,
    speed: Math.round(clamp(parsed.speed !== undefined ? parsed.speed : (Number(parsed.sensitivity) + 1) * 50, 0, 100)),
    scroll_percent: Math.round(clamp(parsed.scroll_percent !== undefined ? parsed.scroll_percent : Number(parsed.scroll_factor) * 100, 10, 150))
  }
}

function speedToSensitivity(speed) {
  return Math.round((clamp(speed, 0, 100) / 50 - 1) * 1000) / 1000
}

function percentToScroll(percent) {
  return Math.round(clamp(percent, 10, 150)) / 100
}
