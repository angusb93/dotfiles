# Uptime Kuma: the thing that notices a service is down when nobody is looking.
#
# Homepage's dots only exist while a browser has the page open, so they answer
# "is it up right now, while I am looking at it". This answers "did it go down
# at 4am", which is a different question and the one that actually matters.
#
# Tailnet only, like everything else: listens on all interfaces, and the
# firewall is closed on every interface except tailscale0.
{ lib, ... }:
let
  state = "/fast/data/uptime-kuma";
in
{
  services.uptime-kuma = {
    enable = true;
    settings = {
      # ⚠️ mkForce on both. The module sets DATA_DIR without mkDefault, so a
      # plain definition here is a conflict, not an override.
      #
      # It has to move off /var/lib: restic backs up fast/{vault,data,media}
      # and tank/archive and nothing else, so state left in /var/lib has no
      # offsite copy at all. /fast/data/<service> is the convention every other
      # service here follows for exactly that reason.
      DATA_DIR = lib.mkForce "${state}/";
      HOST = lib.mkForce "0.0.0.0";
      PORT = lib.mkForce "3001";
    };
  };

  # ⚠️ The module runs this as a DynamicUser with a StateDirectory, which means
  # systemd puts the real directory in /var/lib/private/uptime-kuma and
  # symlinks to it - so bind-mounting /var/lib/uptime-kuma somewhere useful
  # silently backs up an empty directory. A fixed user avoids the whole dance
  # and matches sonarr, radarr and bazarr.
  users.users.uptime-kuma = {
    isSystemUser = true;
    group = "uptime-kuma";
    home = state;
  };
  users.groups.uptime-kuma = { };

  systemd.tmpfiles.rules = [
    "d ${state} 0750 uptime-kuma uptime-kuma -"
  ];

  systemd.services.uptime-kuma.serviceConfig = {
    DynamicUser = lib.mkForce false;
    StateDirectory = lib.mkForce "";
    User = "uptime-kuma";
    Group = "uptime-kuma";
    # The unit is ProtectSystem=strict, so the new data directory has to be
    # named explicitly or every write fails read-only.
    ReadWritePaths = [ state ];
  };
}
