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
      nixpkgs,
      nix-darwin,
      mac-app-util,
      nix-homebrew,
      ...
    }:
    let
      configuration =
        { pkgs, ... }:
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
            # TEMP: statix 0.5.8-unstable-2026-06-28 has a broken snapshot test
            # (useless_has_attr) and isn't in the binary cache yet, so it builds
            # from source and fails its checkPhase. Skip checks until a good
            # build is cached upstream, then drop this override.
            (pkgs.statix.overrideAttrs (_: {
              doCheck = false;
            }))
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
            pkgs.dbmate
            pkgs.devbox
            pkgs.direnv
            pkgs.google-cloud-sdk
            pkgs.grpcurl
            pkgs.ngrok
            pkgs.redis
            pkgs.supabase-cli
            pkgs.tenv

            # Apps
            pkgs.gcalcli
            pkgs.notion-app
            pkgs.obsidian
            pkgs.opencode
            pkgs.postman
            pkgs.slack
            pkgs.linear

            # macOS / system
            pkgs.aerospace
            pkgs.claude-code
            pkgs.desktoppr
            pkgs.ffmpeg
            pkgs.m1ddc
            pkgs.mise
            pkgs.sketchybar
          ];

          # --- Tailscale: remote access mesh (reach the NAS from this laptop) ---
          # Runs tailscaled as a launchd daemon (utun interface, no GUI app or
          # system extension needed). After deploy, run once:
          #   sudo tailscale up
          services.tailscale.enable = true;

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

          # Dim the external monitor with the sun. Runs periodically (not a
          # daemon), reading the tunable brightness curve from the script in
          # ~/.config/scripts. Adjust ADAPTIVE_* to change location/range/fade.
          launchd.user.agents.adaptive-brightness = {
            serviceConfig = {
              Label = "adaptive-brightness";
              ProgramArguments = [
                "${pkgs.python3}/bin/python3"
                "/Users/angusbuick/.config/scripts/adaptive-brightness"
              ];
              RunAtLoad = true;
              StartInterval = 300; # every 5 minutes
              EnvironmentVariables = {
                PATH = "/run/current-system/sw/bin:/usr/bin:/bin";
                ADAPTIVE_LAT = "51.5074";
                ADAPTIVE_LON = "-0.1278";
                ADAPTIVE_MAX = "100";
                ADAPTIVE_MIN = "5";
                ADAPTIVE_FADE = "60";
              };
              StandardOutPath = "/tmp/adaptive-brightness.log";
              StandardErrorPath = "/tmp/adaptive-brightness.log";
            };
          };

          # Syncthing: the Mac half of the live Obsidian vault sync with morty
          # (the NAS half is declared in hosts/nas/default.nix). This was
          # previously a stray `brew install`, so `homebrew.onActivation.cleanup
          # = "zap"` uninstalled it out from under the running process - hence
          # declaring it here. No --home flag: syncthing defaults to
          # ~/Library/Application Support/Syncthing on macOS, which keeps the
          # existing device identity and folder pairing. --no-restart hands
          # restarts to launchd's KeepAlive instead of syncthing restarting
          # itself.
          launchd.user.agents.syncthing = {
            serviceConfig = {
              Label = "syncthing";
              ProgramArguments = [
                "${pkgs.syncthing}/bin/syncthing"
                "serve"
                "--no-browser"
                "--no-restart"
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/syncthing.log";
              StandardErrorPath = "/tmp/syncthing.log";
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
              "uv"
            ];
            casks = [
              "ghostty"
              "chatgpt"
              "logi-options+"
              "figma"
              "spotify"
              "google-chrome"
              # 1Password: cask rather than nixpkgs `_1password-gui`, which does
              # support aarch64-darwin. Two reasons. (1) The macOS app must live
              # in /Applications for browser integration and Touch ID unlock;
              # nix installs to the store and symlinks, which 1Password's
              # signature/path checks don't reliably accept. (2) The cask is
              # auto_updates - for a password manager, shipping its own security
              # fixes beats waiting on a flake bump. nixpkgs currently lags:
              # gui 8.12.30 vs 8.12.33, cli 2.34.1 vs 2.38.1 (checked 2026-08-14).
              "1password"
              "1password-cli"
            ];
          };
          system = {
            activationScripts.postActivation.text = ''
              sudo -u angusbuick ${pkgs.desktoppr}/bin/desktoppr /Users/angusbuick/dotfiles/wallpapers/custom-bg-2.png
              # Turn the display off after 60 min idle (both AC and battery).
              /usr/bin/pmset -a displaysleep 60
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
                # AeroSpace owns window and workspace management, so the native
                # Mission Control overlay is redundant and steals ctrl+up from it.
                # 32 is the symbolic hotkey id for "Mission Control".
                "com.apple.symbolichotkeys" = {
                  AppleSymbolicHotKeys = {
                    "32" = {
                      enabled = false;
                    };
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

      # Build the NAS flake using:
      # $ sudo nixos-rebuild switch --flake .#nas
      nixosConfigurations."nas" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/nas ];
      };
    };
}
