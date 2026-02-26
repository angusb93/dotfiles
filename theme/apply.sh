#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=colors.sh
source "$SCRIPT_DIR/colors.sh"

# --- Ghostty ---
ghostty_config="$REPO_DIR/ghostty/config"
if [ -f "$ghostty_config" ]; then
  # Remove any existing generated block
  sed -i '' '/^# \[theme:generated\]/,/^# \[\/theme:generated\]/d' "$ghostty_config"
  # Append generated block
  cat >> "$ghostty_config" <<EOF
# [theme:generated] — do not edit, run theme/apply.sh
background = $BASE00
foreground = $BASE05
cursor-color = $BASE05
cursor-text = $BASE00
selection-background = $BASE02
selection-foreground = $BASE05
palette = 0=#$BASE00
palette = 1=#cc6666
palette = 2=#66cc66
palette = 3=#$BASE0A
palette = 4=#$BASE0D
palette = 5=#$BASE0E
palette = 6=#$BASE0C
palette = 7=#$BASE05
palette = 8=#$BASE03
palette = 9=#cc6666
palette = 10=#66cc66
palette = 11=#$BASE0A
palette = 12=#$BASE0D
palette = 13=#$BASE0E
palette = 14=#$BASE0C
palette = 15=#$BASE07
# [/theme:generated]
EOF
  echo "✓ Ghostty config updated"
else
  echo "⚠ Ghostty config not found at $ghostty_config"
fi

# --- Tmux theme.conf ---
tmux_theme="$REPO_DIR/tmux/theme.conf"
cat > "$tmux_theme" <<EOF
# [theme:generated] — do not edit, run theme/apply.sh
set -g pane-active-border-style 'fg=#$BASE08,bg=default'
set -g pane-border-style 'fg=#$BASE03,bg=default'
set -g status-style 'bg=#$BASE00,fg=#$BASE05'
set -g status-justify centre
set -g status-left '#{?client_prefix,#[bg=#$BASE0A#,fg=#$BASE00#,bold] #S #[fg=#$BASE0A#,bg=#$BASE00],#[bg=#$BASE02#,fg=#$BASE05] #S #[fg=#$BASE02#,bg=#$BASE00]}'
set -g status-right '#[fg=#$BASE02,bg=#$BASE00]#[fg=#$BASE04,bg=#$BASE02] %H:%M '
set -g status-left-length 20
set -g status-right-length 20
set -g window-status-format '#[fg=#$BASE02,bg=#$BASE00]#[fg=#$BASE04,bg=#$BASE02] #I:#W #[fg=#$BASE02,bg=#$BASE00]'
set -g window-status-current-format '#[fg=#$BASE08,bg=#$BASE00]#[fg=#$BASE00,bg=#$BASE08,bold] #I:#W#{?window_zoomed_flag,(),} #[fg=#$BASE08,bg=#$BASE00]'
set -g window-status-separator ' '
set -g message-style 'bg=#$BASE02,fg=#$BASE05'
set -g mode-style 'bg=#$BASE02,fg=#$BASE05'
# [/theme:generated]
EOF
echo "✓ Tmux theme.conf generated"
if [ -n "${TMUX:-}" ]; then
  tmux source-file "$REPO_DIR/tmux/theme.conf" 2>/dev/null && echo "✓ Tmux reloaded"
fi

# --- Neovim colorscheme ---
nvim_colorscheme="$REPO_DIR/nvim/lua/plugins/colorscheme.lua"
cat > "$nvim_colorscheme" <<EOF
-- [theme:generated] — do not edit, run theme/apply.sh
return {
  -- Disable LazyVim default colorschemes
  { "folke/tokyonight.nvim", enabled = false },
  { "catppuccin/nvim", enabled = false },

  {
    "RRethy/base16-nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("base16-colorscheme").setup({
        base00 = "#$BASE00",
        base01 = "#$BASE01",
        base02 = "#$BASE02",
        base03 = "#$BASE03",
        base04 = "#$BASE04",
        base05 = "#$BASE05",
        base06 = "#$BASE06",
        base07 = "#$BASE07",
        base08 = "#$BASE08",
        base09 = "#$BASE09",
        base0A = "#$BASE0A",
        base0B = "#$BASE0B",
        base0C = "#$BASE0C",
        base0D = "#$BASE0D",
        base0E = "#$BASE0E",
        base0F = "#$BASE0F",
      })

      -- Override Snacks dashboard highlights
      local hl = vim.api.nvim_set_hl
      hl(0, "SnacksDashboardHeader", { fg = "#$BASE08" })
      hl(0, "SnacksDashboardIcon", { fg = "#$BASE0A" })
      hl(0, "SnacksDashboardKey", { fg = "#$BASE0A" })
      hl(0, "SnacksDashboardDesc", { fg = "#$BASE04" })
      hl(0, "SnacksDashboardFooter", { fg = "#$BASE03" })

      -- Picker
      hl(0, "SnacksPickerMatch", { fg = "#$BASE0A", bold = true })
      hl(0, "SnacksPickerBorder", { fg = "#$BASE03" })
      hl(0, "SnacksPickerInputBorder", { fg = "#$BASE03" })
      hl(0, "SnacksPickerListBorder", { fg = "#$BASE03" })
      hl(0, "SnacksPickerPreviewBorder", { fg = "#$BASE03" })
      hl(0, "SnacksPickerTitle", { fg = "#$BASE08", bold = true })
      hl(0, "SnacksPickerInputTitle", { fg = "#$BASE08", bold = true })
      hl(0, "SnacksPickerListTitle", { fg = "#$BASE08", bold = true })
      hl(0, "SnacksPickerPreviewTitle", { fg = "#$BASE08", bold = true })
      hl(0, "SnacksPickerListCursorLine", { bg = "#$BASE02", bold = true })
      hl(0, "SnacksPickerPrompt", { fg = "#$BASE0A" })
      hl(0, "SnacksPickerDir", { fg = "#$BASE03" })

      -- Floating windows (general)
      hl(0, "FloatTitle", { fg = "#$BASE08", bold = true })
      hl(0, "FloatBorder", { fg = "#$BASE03" })

      -- Lazygit (used by Snacks.lazygit theme mapping)
      hl(0, "LazyGitActiveBorder", { fg = "#$BASE08" })
      hl(0, "LazyGitUnstaged", { fg = "#cc6666" })
      hl(0, "LazyGitSelectedLine", { bg = "#$BASE01" })

      -- Override terminal ANSI red/green for lazygit staging & diffs
      vim.g.terminal_color_1  = "#cc6666"  -- red
      vim.g.terminal_color_2  = "#66cc66"  -- green
      vim.g.terminal_color_9  = "#cc6666"  -- bright red
      vim.g.terminal_color_10 = "#66cc66"  -- bright green

      -- Completion popup
      hl(0, "BlinkCmpMenuBorder", { fg = "#$BASE03" })
      hl(0, "BlinkCmpDocBorder", { fg = "#$BASE03" })
      hl(0, "BlinkCmpLabelMatch", { fg = "#$BASE0A", bold = true })
      hl(0, "BlinkCmpMenuSelection", { bg = "#$BASE02" })
    end,
  },

  -- Snacks lazygit theme overrides
  {
    "folke/snacks.nvim",
    opts = {
      lazygit = {
        theme = {
          activeBorderColor          = { fg = "LazyGitActiveBorder", bold = true },
          inactiveBorderColor        = { fg = "FloatBorder" },
          selectedLineBgColor        = { bg = "LazyGitSelectedLine", bold = true },
          unstagedChangesColor       = { fg = "LazyGitUnstaged" },
          defaultFgColor             = { fg = "Normal" },
          searchingActiveBorderColor = { fg = "LazyGitActiveBorder", bold = true },
        },
      },
    },
  },
}
-- [/theme:generated]
EOF
echo "✓ Neovim colorscheme.lua generated"

# --- Lazygit ---
lazygit_config="$HOME/Library/Application Support/lazygit/config.yml"
mkdir -p "$(dirname "$lazygit_config")"
cat > "$lazygit_config" <<EOF
# [theme:generated] — do not edit, run theme/apply.sh
gui:
  theme:
    activeBorderColor:
      - "#$BASE08"
      - bold
    inactiveBorderColor:
      - "#$BASE03"
    optionsTextColor:
      - "#$BASE04"
    selectedLineBgColor:
      - "#$BASE01"
      - bold
    selectedRangeBgColor:
      - "#$BASE01"
    unstagedChangesColor:
      - "#cc6666"
    defaultFgColor:
      - "#$BASE05"
git:
  paging:
    colorArg: always
    pager: "perl -pe 's/\\\\e\\\\[31m/\\\\e[38;2;204;102;102m/g; s/\\\\e\\\\[32m/\\\\e[38;2;102;204;102m/g'"
# [/theme:generated]
EOF
echo "✓ Lazygit config generated"

# --- Starship ---
starship_config="$REPO_DIR/starship/starship.toml"
sed \
  -e "s/{ACCENT}/#$BASE08/g" \
  -e "s/{BG}/#$BASE00/g" \
  -e "s/{DIR_BG}/#$BASE03/g" \
  -e "s/{DIR_FG}/#$BASE0B/g" \
  -e "s/{GIT_BG}/#$BASE02/g" \
  -e "s/{LANG_BG}/#$BASE01/g" \
  -e "s/{DARK_FG}/#$BASE04/g" \
  <<'EOF' > "$starship_config"
format = """
[░▒▓]({ACCENT})\
[  ](bg:{ACCENT} fg:{BG})\
[](bg:{DIR_BG} fg:{ACCENT})\
$directory\
[](fg:{DIR_BG} bg:{GIT_BG})\
$git_branch\
$git_status\
[](fg:{GIT_BG} bg:{LANG_BG})\
$nodejs\
$rust\
$golang\
$php\
[ ](fg:{LANG_BG})\
\n$character"""

[directory]
style = "fg:{DIR_FG} bg:{DIR_BG}"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = " "
"Pictures" = " "

[git_branch]
symbol = ""
style = "bg:{GIT_BG}"
format = '[[ $symbol $branch ](fg:{ACCENT} bg:{GIT_BG})]($style)'

[git_status]
style = "bg:{GIT_BG}"
format = '[[($all_status$ahead_behind )](fg:{ACCENT} bg:{GIT_BG})]($style)'

[nodejs]
symbol = ""
style = "bg:{LANG_BG}"
format = '[[ $symbol ($version) ](fg:{ACCENT} bg:{LANG_BG})]($style)'

[rust]
symbol = ""
style = "bg:{LANG_BG}"
format = '[[ $symbol ($version) ](fg:{ACCENT} bg:{LANG_BG})]($style)'

[golang]
symbol = ""
style = "bg:{LANG_BG}"
format = '[[ $symbol ($version) ](fg:{ACCENT} bg:{LANG_BG})]($style)'

[php]
symbol = ""
style = "bg:{LANG_BG}"
format = '[[ $symbol ($version) ](fg:{ACCENT} bg:{LANG_BG})]($style)'

# [time]
# disabled = false
# time_format = "%R" # Hour:Minute Format
# style = "bg:{BG}"
# format = '[[  $time ](fg:{DARK_FG} bg:{BG})]($style)'
EOF
echo "✓ Starship config generated"

echo ""
echo "Theme applied. Restart apps or reload configs to see changes."
