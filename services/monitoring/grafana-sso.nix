{ config, pkgs, lib, gladstoneArgs, ... }:
let
  fqdn = "${gladstoneArgs.hostName}.tail21a653.ts.net";
  # TODO: fill in your Entra "Directory (tenant) ID" from the app registration.
  tenantId = "3923033c-2920-4d77-aaa8-46d2199a40f2";
  allowedDomains = "tryonmed.com";
  # TODO: object ID of the Entra security group allowed to sign in. Requires the
  # app registration to emit a groups claim (Token configuration -> Add groups
  # claim -> Security groups), else the token carries no groups and everyone is
  # denied.
  allowedGroups = "7ce40d56-6f78-4c7e-8ad1-c728af739d06";
in {
  # --- Grafana sign-in via Microsoft Entra ID (Azure AD) ---
  # OAuth needs HTTPS; TLS is terminated by `tailscale serve` below, so the
  # redirect URI is https://<fqdn>/login/azuread (no :3000).
  services.grafana.settings = {
    "auth.azuread" = {
      enabled = true;
      name = "Entra ID";
      allow_sign_up = true;
      # Injected from the agenix env file, never in the Nix store.
      client_id = "$__env{AZUREAD_CLIENT_ID}";
      client_secret = "$__env{AZUREAD_CLIENT_SECRET}";
      scopes = "openid email profile";
      auth_url = "https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/authorize";
      token_url = "https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token";
      allowed_domains = allowedDomains;
      allowed_groups = allowedGroups; # restrict sign-in to one Entra group
      role_attribute_strict = false;
    };
    # Everyone who signs in gets read-only unless mapped higher.
    users.auto_assign_org_role = "Viewer";
  };

  # Client id/secret as an environment file, managed by agenix.
  # File contents (see `agenix -e secrets/grafana-oauth-env.age`):
  #   AZUREAD_CLIENT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  #   AZUREAD_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  age.secrets.grafanaOauth = {
    file = ../../secrets/grafana-oauth-env.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };
  systemd.services.grafana.serviceConfig.EnvironmentFile =
    config.age.secrets.grafanaOauth.path;

  # Terminate TLS with Tailscale: https://<fqdn>/ -> http://127.0.0.1:3000.
  # Requires HTTPS + MagicDNS enabled in the tailnet admin console. Tailscale
  # auto-provisions and renews the cert for <fqdn>.
  systemd.services.tailscale-serve-grafana = {
    description = "Expose Grafana over Tailscale HTTPS";
    after = [ "tailscaled.service" "grafana.service" ];
    wants = [ "tailscaled.service" "grafana.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # If this errors, check `tailscale serve status` and the CLI syntax for
      # the installed version (unstable). Off on stop keeps state clean.
      ExecStart = "${pkgs.unstable.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:3000";
      ExecStop = "${pkgs.unstable.tailscale}/bin/tailscale serve --https=443 off";
    };
  };
}
