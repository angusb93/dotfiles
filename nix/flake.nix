{
  description = "Angus' nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    mac-app-util.url = "github:hraban/mac-app-util";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
  };

  outputs =
    {
      self,
      nix-darwin,
      mac-app-util,
      nix-homebrew,
      ...
    }:
    let
      configuration =
        { pkgs, config, ... }:
        {
          # List packages installed in system profile. To search by name, run:
          # $ nix-env -qaP | grep wget
          environment.systemPackages = [
            # Shell & terminal
            pkgs.bash
            pkgs.btop
            pkgs.fd
            pkgs.fzf
            pkgs.ripgrep
            pkgs.sesh
            pkgs.starship
            pkgs.tmux
            pkgs.zoxide

            # Git
            pkgs.gh
            pkgs.git
            pkgs.git-lfs
            pkgs.lazygit
            pkgs.stow

            # Editors
            pkgs.neovim

            # Languages & runtimes
            pkgs.bun
            pkgs.go
            pkgs.lua
            pkgs.pnpm
            pkgs.typescript
            pkgs.yarn

            # Language servers
            pkgs.bash-language-server
            pkgs.gopls
            pkgs.lua-language-server
            pkgs.marksman
            pkgs.nil
            pkgs.svelte-language-server
            pkgs.tailwindcss-language-server
            pkgs.taplo
            pkgs.terraform-ls
            pkgs.vscode-langservers-extracted # eslint, json, html, css
            pkgs.vtsls
            pkgs.yaml-language-server

            # Linters
            pkgs.biome
            pkgs.golangci-lint
            pkgs.markdownlint-cli2
            pkgs.shellcheck
            pkgs.statix
            pkgs.tflint

            # Formatters
            pkgs.gofumpt
            pkgs.gotools # goimports
            pkgs.nixfmt
            pkgs.prettier
            pkgs.shfmt
            pkgs.stylua

            # Cloud & infra
            pkgs.bore-cli
            pkgs.devbox
            pkgs.direnv
            pkgs.google-cloud-sdk
            pkgs.grpcurl
            pkgs.ngrok
            pkgs.redis
            pkgs.tenv

            # Apps
            pkgs.gcalcli
            pkgs.notion-app
            pkgs.obsidian
            pkgs.opencode
            pkgs.postman
            pkgs.slack

            # macOS / system
            pkgs.aerospace
            pkgs.claude-code
            pkgs.desktoppr
            pkgs.ffmpeg
            pkgs.mise
            pkgs.sketchybar
          ];

          launchd.user.agents.sketchybar = {
            serviceConfig = {
              Label = "sketchybar";
              ProgramArguments = [ "${pkgs.sketchybar}/bin/sketchybar" ];
              KeepAlive = true;
              RunAtLoad = true;
              EnvironmentVariables.PATH = "/run/current-system/sw/bin:/usr/bin:/bin:/opt/homebrew/bin";
              StandardOutPath = "/tmp/sketchybar.log";
              StandardErrorPath = "/tmp/sketchybar.log";
            };
          };

          # Set up environment variables for pkg-config
          # environment.variables = {
          #   PKG_CONFIG_PATH = "${pkgs.pixman}/lib/pkgconfig:${pkgs.cairo}/lib/pkgconfig:${pkgs.pango}/lib/pkgconfig";
          # };

          homebrew = {
            enable = true;
            onActivation.cleanup = "zap";
            brews = [
              "tree-sitter-cli"
              "pkg-config"
              "cairo"
              "pango"
              "libpng"
              "jpeg"
              "giflib"
              "librsvg"
            ];
            casks = [
              "ghostty"
              "chatgpt"
              "logi-options+"
              "figma"
              "spotify"
              "google-chrome"
            ];
          };
          system = {
            activationScripts.postActivation.text = ''
              sudo -u angusbuick ${pkgs.desktoppr}/bin/desktoppr /Users/angusbuick/dotfiles/wallpapers/custom-bg-2.png
            '';
            defaults = {
              dock = {
                autohide = true;
                orientation = "left";
                showMissionControlGestureEnabled = false;
                persistent-apps = [
                  "/Applications/Google Chrome.app"
                  "${pkgs.obsidian}/Applications/Obsidian.app"
                  "/Applications/Spotify.app"
                  "/Applications/Figma.app"
                  "/Applications/ChatGPT.app"
                  "/Applications/Ghostty.app"
                ];
              };
              trackpad.TrackpadThreeFingerDrag = false;
              trackpad.TrackpadThreeFingerVertSwipeGesture = 0;
              WindowManager.EnableStandardClickToShowDesktop = false;
              NSGlobalDomain = {
                KeyRepeat = 2;
                AppleInterfaceStyle = "Dark";
                _HIHideMenuBar = true;
              };
              CustomUserPreferences = {
                NSGlobalDomain = {
                  AppleReduceDesktopTinting = true;
                  NSUserKeyEquivalents = {
                    Minimize = "\\~\\$\\^\\@m";
                  };
                };
              };
            };
            primaryUser = "angusbuick";
            # Set Git commit hash for darwin-version.
            configurationRevision = self.rev or self.dirtyRev or null;
            # Used for backwards compatibility, please read the changelog before changing.
            # $ darwin-rebuild changelog
            stateVersion = 6;
          };

          # Necessary for using flakes on this system.
          nix.settings.experimental-features = "nix-command flakes";

          # Enable alternative shell support in nix-darwin.
          # programs.fish.enable = true;

          # The platform the configuration will be used on.
          nixpkgs.hostPlatform = "aarch64-darwin";

          # Allow unfree packages
          nixpkgs.config.allowUnfree = true;
        };
    in
    {
      # Build darwin flake using:
      # $ darwin-rebuild build --flake .#macbook
      darwinConfigurations."macbook" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          mac-app-util.darwinModules.default
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              # Install Homebrew under the default prefix
              enable = true;

              # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
              enableRosetta = true;

              # User owning the Homebrew prefix
              user = "angusbuick";

            };
          }
        ];
      };
    };
}
