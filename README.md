# Omarchy Glide

Pointer speed, scroll, and acceleration for the laptop touchpad on
[Omarchy](https://omarchy.org/). An external mouse is left alone.

Open the panel from **Super+Space → Setup → Input → Glide**, or search
“glide”. Changes apply live.

## Install

```bash
omarchy plugin add https://github.com/paytbidd/omarchy-glide.git --yes --enable
```

That clones `payton.glide` and enables the panel. The helper at
`scripts/omarchy-glide` is invoked from the panel; settings persist in
`~/.config/omarchy/touchpad.toml` and are also read by
`~/.config/hypr/input.lua` on Hyprland reload.

Update later with:

```bash
omarchy plugin update payton.glide
```

## Remove

```bash
omarchy plugin remove payton.glide
```

## What you get

- Panel `payton.glide` — speed, scroll, adaptive/flat acceleration, natural
  scrolling, ignore-while-typing, and a reset to Omarchy defaults
- `scripts/omarchy-glide` — `get`, `set`, `apply`, `reset`, `panel`

```bash
~/.config/omarchy/plugins/payton.glide/scripts/omarchy-glide get
~/.config/omarchy/plugins/payton.glide/scripts/omarchy-glide panel
```
