# Typed settings for this pack's plugins in programs.uji (uji's home-manager
# module, which provides `ujiLib`). Importing this also loads the pack from
# the flake; set `programs.uji.packs.uji-plugins` to use a checkout instead.
self:
{
  config,
  lib,
  ujiLib,
  ...
}:

let
  inherit (lib) types;
  inherit (ujiLib) mkPlugin mkSetting;
  policy = types.enum [
    "allow"
    "ask"
    "deny"
  ];
  mcp = config.programs.uji.plugins.mcp;
in
{
  options.programs.uji.plugins = lib.mkOption {
    type = types.submodule {
      options = {
        statusline = mkPlugin { description = "statusline"; };

        planmode = mkPlugin {
          description = "planmode";
          settings = {
            allow =
              mkSetting (types.listOf types.str) [ ]
                "Command prefixes that run without asking while planning.";
            confirm = mkSetting types.bool true "`false` skips the accept picker at the end of a turn.";
            badge =
              mkSetting types.bool true
                "`false` leaves `planmode.Badge` off the screen, for a bar that shows it itself.";
            keys = mkSetting types.bool true "`false` leaves Ctrl+B unbound.";
            priority = mkSetting types.int 10 "The priority of its `before_tool` hook.";
          };
        };

        mcp = mkPlugin {
          description = "mcp";
          settings.servers = mkSetting (types.attrsOf (
            types.submodule {
              freeformType = types.attrsOf types.anything;
              options = {
                cmd = mkSetting (types.listOf types.str) null "The command of a stdio server.";
                cwd = mkSetting types.str null "Where a stdio server runs.";
                url = mkSetting types.str null "The address of an HTTP server.";
                token = mkSetting types.str null "The token for an HTTP server.";
              };
            }
          )) { } "Servers by name, each with `cmd` and optional `cwd`, or `url` and optional `token`.";
        };

        telescope = mkPlugin {
          description = "telescope";
          settings = {
            editor =
              mkSetting types.str null
                "The program that opens files. The plugin's default is `UJI_EDITOR`, then `VISUAL`, then `EDITOR`.";
            keys = mkSetting types.bool true "`false` leaves the keys unbound.";
          };
        };

        skills = mkPlugin {
          description = "skills";
          settings.roots = mkSetting (types.listOf types.str) [
            "~/.agents/skills"
            ".uji/skills"
            ".agents/skills"
          ] "Agent Skills folders.";
        };

        websearch = mkPlugin {
          description = "websearch";
          settings = {
            backend = mkSetting (types.enum [
              "exa"
              "searxng"
            ]) "exa" "Where searches go: Exa's service, or a SearXNG instance at `url`.";
            url = mkSetting types.str null "The SearXNG instance, for `backend = \"searxng\"`. `SEARXNG_URL` also sets it.";
            policy = mkSetting policy "allow" "Whether the tools ask before they run.";
            count = mkSetting types.int 5 "Results per search.";
            chars = mkSetting types.int 20000 "Characters of a page that `web_fetch` returns at most.";
            timeout = mkSetting types.int 30 "Seconds per request.";
          };
        };

        subagent = mkPlugin {
          description = "subagent";
          settings = {
            policy = mkSetting policy "allow" "Whether starting agents asks first.";
            scope = mkSetting (types.enum [
              "user"
              "project"
              "both"
            ]) "user" "Where agents come from when the model does not say.";
            confirm_project = mkSetting types.bool true "Ask before running an agent from the project.";
            max_tasks = mkSetting types.int 8 "The most tasks one call may run at the same time.";
            concurrency = mkSetting types.int 4 "How many of them run at once.";
            output = mkSetting types.int 51200 "Bytes of each answer kept when several run at once.";
          };
        };

        readonly = mkPlugin {
          description = "readonly";
          settings.paths = mkSetting (types.listOf types.str) [ ] "Directories the model can read but not change.";
        };

        themes = mkPlugin {
          description = "themes";
          settings.keys = mkSetting types.str null "A key in normal mode that opens the theme picker.";
        };

        claude_code = mkPlugin {
          description = "claude_code";
          settings = {
            command = mkSetting (types.listOf types.str) [ "claude" ] "The `claude` command and its arguments.";
            permission_mode = mkSetting types.str "default" "Claude Code's `--permission-mode`.";
            models = mkSetting (types.listOf types.str) [
              "claude-fable-5-1"
              "claude-opus-5-5"
              "claude-sonnet-5"
              "claude-haiku-4-5-20251001"
            ] "The models the provider offers.";
            id = mkSetting types.str "claude-code" "The provider's id.";
            name = mkSetting types.str "Claude Code" "The provider's name.";
          };
        };
      };
    };
  };

  config = {
    programs.uji.packs.uji-plugins = lib.mkDefault self;
    programs.uji.plugins = {
      statusline.enable = lib.mkDefault true;
      themes.enable = lib.mkDefault true;
      websearch.enable = lib.mkDefault true;
    };

    assertions = lib.optionals mcp.enable (
      lib.mapAttrsToList (name: server: {
        assertion = (server.cmd != null) != (server.url != null);
        message = "programs.uji.plugins.mcp.settings.servers.${name} needs either `cmd` or `url`.";
      }) (if mcp.settings.servers == null then { } else mcp.settings.servers)
    );
  };
}
