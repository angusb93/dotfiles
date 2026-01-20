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
      nixpkgs,
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
            pkgs.neovim
            pkgs.tmux
            pkgs.git
            pkgs.gh
            pkgs.stow
            pkgs.google-chrome
            pkgs.bun
            pkgs.aerospace
            pkgs.obsidian
            pkgs.starship
            pkgs.fd
            pkgs.fzf
            pkgs.zoxide
            pkgs.sesh
            pkgs.lua
            pkgs.lazygit
            pkgs.ngrok
            pkgs.ripgrep
            pkgs.typescript
            pkgs.gallery-dl
            pkgs.vscode
            pkgs.slack
            pkgs.grpcurl
            pkgs.notion-app
            pkgs.git-lfs
            pkgs.code-cursor
            pkgs.opencode
            pkgs.go
            pkgs.direnv
            pkgs.google-cloud-sdk
            pkgs.devbox
            pkgs.nixfmt
            pkgs.redis
            pkgs.bore-cli
            pkgs.bash
            pkgs.nil # Nix LSP
            pkgs.stylua # Lua formatter
            pkgs.terraform-ls # Terraform LSP
            pkgs.statix # Nix linter
            pkgs.postman
            pkgs.tflint
            pkgs.ffmpeg
            pkgs.pnpm
            pkgs.yarn
            pkgs.nodePackages.vercel
          ];

          # Set up environment variables for pkg-config
          # environment.variables = {
          #   PKG_CONFIG_PATH = "${pkgs.pixman}/lib/pkgconfig:${pkgs.cairo}/lib/pkgconfig:${pkgs.pango}/lib/pkgconfig";
          # };

          homebrew = {
            enable = true;
            brews = [
              "tree-sitter-cli"
              "nvm"
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
            ];
          };
          system = {
            defaults = {
              dock = {
                autohide = true;
                orientation = "left";
                persistent-apps = [
                  "${pkgs.google-chrome}/Applications/Google Chrome.app"
                  "${pkgs.obsidian}/Applications/Obsidian.app"
                  "/Applications/Spotify.app"
                  "/Applications/Figma.app"
                  "/Applications/ChatGPT.app"
                  "/Applications/Ghostty.app"
                ];
              };
              trackpad.TrackpadThreeFingerDrag = false;
              NSGlobalDomain = {
                KeyRepeat = 2;
                AppleInterfaceStyle = "Dark";
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
