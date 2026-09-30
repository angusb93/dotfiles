# A dedicated identity for the long-running agent services.
#
# ⚠️ Context, so nobody over-reads this: `telegram-agent` was *already* unable
# to become root. Its unit sets NoNewPrivileges=true, which blocks setuid, which
# blocks sudo outright - verified 2026-09-29. The `%wheel NOPASSWD: ALL` rule in
# sudoers is real but that unit cannot reach it.
#
# What this adds is UID separation, which buys two things the sandbox does not:
#
#  - Files the agent writes are no longer owned by `angus`, so an interactive
#    session cannot implicitly trust them. Today a session driven by a Telegram
#    message can write into ~angus/.config and ~angus/.local, and the next
#    interactive shell inherits whatever landed there.
#  - The masking list (.ssh, .config/op, .config/gh, ...) stops being the thing
#    standing between an agent and Angus's credentials. Separate homes mean
#    there is nothing to mask.
#
# The cost is that the agent needs its own Claude Code credential, because the
# module shares the running user's: "Home directory holding the agent's Claude
# auth and caches."
{ config, lib, pkgs, ... }:
let
  agentHome = "/var/lib/agent";
in
{
  users.groups.agent = { };

  users.users.agent = {
    isSystemUser = true;
    group = "agent";
    home = agentHome;
    createHome = true;
    description = "Long-running agent services (telegram-agent, and paseo/pi if reinstated)";
    # Deliberately not in wheel. Password is locked by default for a system
    # user, so this account cannot log in over SSH or at the console either.
    extraGroups = [ "vault" ];
    # Claude Code shells out, so it needs a working shell even though nobody
    # ever logs in as this user.
    shell = pkgs.bashInteractive;
  };

  # Shared write access to the vault, which both Angus and the agent edit.
  #
  # A dedicated group rather than reusing `users`: `users` also contains the
  # `kiosk` account that drives the TV, and a media player has no business
  # writing to the notes.
  users.groups.vault = { };
  users.users.angus.extraGroups = [ "vault" ];

  # The agent authenticates to Claude with its own long-lived OAuth token
  # rather than a copy of Angus's credential.
  #
  # ⚠️ The first attempt *was* a copy, and it broke within hours. OAuth refresh
  # tokens rotate: when Angus's interactive session refreshed, it invalidated
  # the copy, and the agent's own refresh then failed and zeroed its access
  # token. Two processes cannot share one OAuth credential.
  #
  # ⚠️ `claude /login` also cannot work over SSH - it waits for an OAuth
  # callback on localhost, which over SSH is the *laptop's* localhost, so the
  # login silently never completes. `claude setup-token` is the headless path.
  #
  # The token itself lives outside the flake, alongside the restic, rclone,
  # NordVPN and Kodi credentials. systemd reads EnvironmentFile as root before
  # the sandbox applies, so root-only 0600 is both sufficient and correct.
  systemd.services.telegram-agent.serviceConfig.EnvironmentFile =
    "/var/lib/morty-backup/claude-agent-token.env";

  systemd.tmpfiles.rules = [
    "d ${agentHome} 0750 agent agent -"
    "d ${agentHome}/.claude 0700 agent agent -"
    "d ${agentHome}/.cache 0700 agent agent -"
    "d ${agentHome}/.config 0700 agent agent -"
    "d ${agentHome}/.local 0700 agent agent -"
    "d ${agentHome}/telegram-agent 0700 agent agent -"
  ];
}
