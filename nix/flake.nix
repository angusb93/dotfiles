{
  description = "Angus' nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    mac-app-util.url = "github:hraban/mac-app-util";
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, mac-app-util, nix-homebrew, homebrew-cask, ... }:
  let
    configuration = { pkgs, config, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages =
        [ pkgs.neovim
          pkgs.tmux
          pkgs.git
          pkgs.google-chrome
          pkgs.gh
          pkgs.stow
          pkgs.bun
          pkgs.nodejs_23
          pkgs.aerospace
          pkgs.obsidian
          pkgs.spotify
          pkgs.starship
          pkgs.fd
          pkgs.fzf
          pkgs.lua
          pkgs.lazygit
          pkgs.ngrok
          pkgs.ripgrep
          pkgs.typescript
          pkgs.nodePackages.ts-node
          pkgs.gallery-dl
          pkgs.vscode
          pkgs.slack
          pkgs.docker
        ];
	

	homebrew = {
		enable = true;
		casks = [
        "ghostty"
        "chatgpt"
        "logi-options+"
        "figma"
			];
		};
	system.defaults = {
    		dock.autohide = true;
		dock.persistent-apps = [ 
			"${pkgs.google-chrome}/Applications/Google Chrome.app"
			"${pkgs.obsidian}/Applications/Obsidian.app"
      "${pkgs.spotify}/Applications/spotify.app"
      "/Applications/Figma.app"
      "/Applications/ChatGPT.app"
      "/Applications/Ghostty.app"
			];
		NSGlobalDomain.KeyRepeat = 2;
		NSGlobalDomain.AppleInterfaceStyle = "Dark";

	};
      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

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
