# Offline reference library, served on the tailnet.
#
# The ZIMs live in tank/reference/kiwix and are fetched by hand rather than
# through fetchurl: re-downloading a 119 GB Wikipedia dump because a hash moved
# would be a bad afternoon, and it is data, not a build input. Each is checked
# against the .sha256 published beside it at download time.
#
# The module builds a symlink farm in the store pointing at those paths, so the
# store entry is ~100 bytes rather than 122 GB.
#
# kiwix-serve refuses to open a partial ZIM, so a file only joins the library
# below once its checksum has passed.
{ ... }:
{
  # Opening the 119 GB Wikipedia ZIM takes kiwix-serve about 20 seconds, during
  # which the unit is active but nothing is listening on the port yet. Not a
  # fault - just worth knowing before concluding it is broken.
  services.kiwix-serve = {
    enable = true;
    port = 8090;

    # Gutenberg joins once `kiwix-fetch` finishes it and its .sha256 passes -
    # listing it early would take the whole server down rather than just that
    # one book collection.
    library = {
      ifixit = "/tank/reference/kiwix/ifixit_en_all_2025-12.zim";
      wikipedia = "/tank/reference/kiwix/wikipedia_en_all_maxi_2026-08.zim";
    };

    # Deliberately no openFirewall. Reachable over Tailscale only, through
    # networking.firewall.trustedInterfaces = [ "tailscale0" ] in default.nix -
    # this is a whole encyclopedia and a repair manual, but it is also an
    # unauthenticated HTTP server, and it has no business on the LAN.
    openFirewall = false;
  };
}
