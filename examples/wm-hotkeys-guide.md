# WM Hotkeys Guide for tmux-sessionizer

Use this guide to launch `tmux-sessionizer.sh` from your window manager with a single keybind.

## FZF height autodetection

By default, picker height is automatic:

- Inside tmux: `40%`
- Outside tmux: `100%`

Set an override if needed:

```bash
export TMUX_SESSIONIZER_FZF_HEIGHT="50%"
```

## i3 (X11)

```i3
# Full terminal mode (recommended)
bindsym $mod+backslash exec --no-startup-id "alacritty --class tmux-sessionizer -e zsh -lc 'tmux-sessionizer.sh; exec zsh'"
for_window [class="tmux-sessionizer"] fullscreen enable

# Floating popup mode (optional)
# bindsym $mod+Shift+backslash exec --no-startup-id "alacritty --class tmux-sessionizer-popup -e zsh -lc 'TMUX_SESSIONIZER_FZF_HEIGHT=40% tmux-sessionizer.sh'"
# for_window [class="tmux-sessionizer-popup"] floating enable, resize set 800 600, move position center
```

## Sway (Wayland)

```sway
# Full terminal mode (recommended)
bindsym $mod+backslash exec alacritty --class tmux-sessionizer -e zsh -lc 'tmux-sessionizer.sh; exec zsh'
for_window [app_id="tmux-sessionizer"] fullscreen enable

# Floating popup mode (optional)
# bindsym $mod+Shift+backslash exec alacritty --class tmux-sessionizer-popup -e zsh -lc 'TMUX_SESSIONIZER_FZF_HEIGHT=40% tmux-sessionizer.sh'
# for_window [app_id="tmux-sessionizer-popup"] floating enable
```

## Hyprland (Wayland)

```ini
# Full terminal mode (recommended)
bind = SUPER, backslash, exec, alacritty --class tmux-sessionizer -e zsh -lc 'tmux-sessionizer.sh; exec zsh'
windowrulev2 = fullscreen,class:^(tmux-sessionizer)$

# Floating popup mode (optional)
# bind = SUPER SHIFT, backslash, exec, alacritty --class tmux-sessionizer-popup -e zsh -lc 'TMUX_SESSIONIZER_FZF_HEIGHT=40% tmux-sessionizer.sh'
# windowrulev2 = float,class:^(tmux-sessionizer-popup)$
# windowrulev2 = size 800 600,class:^(tmux-sessionizer-popup)$
# windowrulev2 = center,class:^(tmux-sessionizer-popup)$
```

## Terminal maximization tips

- Keep fullscreen rules keyed to terminal class/app_id so only sessionizer windows are affected.
- If your terminal does not support `--class`, use the terminal's equivalent class/app-id option.
- Use `exec zsh` (or your shell) after running sessionizer if you want the terminal to remain open.

## Troubleshooting

- If the picker looks too small, confirm you are launching outside tmux (or unset `TMUX_SESSIONIZER_FZF_HEIGHT`).
- If fullscreen does not apply, check class/app_id with your WM inspection tools.
- If keybind works manually but not from config, reload WM config and confirm terminal path is correct.
