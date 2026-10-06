using Gtk;
using GLib;
using Singularity;

namespace Singularity.Apps.Git {

    public class GitApp : Singularity.Application {
        private GitWindow? window = null;

        public GitApp() {
            base("dev.sinty.git",
                 ApplicationFlags.HANDLES_OPEN | ApplicationFlags.HANDLES_COMMAND_LINE);
            add_main_option("open-repository", 0, OptionFlags.NONE, OptionArg.NONE,
                            _("Choose a repository to open"), null);
        }

        protected override void startup() {
            base.startup();
            var prov = new Gtk.CssProvider();
            prov.load_from_string(STYLE);
            var disp = Gdk.Display.get_default();
            if (disp != null)
                Gtk.StyleContext.add_provider_for_display(
                    disp, prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            setup_menu();
        }

        private void setup_menu() {
            var menu = new GLib.Menu();

            var file_menu = new GLib.Menu();
            var f1 = new GLib.Menu();
            f1.append(_("Open Repository…"), "win.open-repo");
            f1.append(_("Close Repository"), "win.close-repo");
            file_menu.append_section(null, f1);
            var f2 = new GLib.Menu();
            f2.append(_("Close Window"), "win.close");
            f2.append(_("Quit"), "app.quit");
            file_menu.append_section(null, f2);
            menu.append_submenu(_("File"), file_menu);

            var edit_menu = new GLib.Menu();
            edit_menu.append(_("Settings"), "app.settings");
            menu.append_submenu(_("Edit"), edit_menu);

            var view_menu = new GLib.Menu();
            var v1 = new GLib.Menu();
            v1.append(_("Working Changes"), "win.show-working");
            v1.append(_("Open Diff in New Window"), "win.detach-diff");
            view_menu.append_section(null, v1);
            var v2 = new GLib.Menu();
            v2.append(_("Refresh"), "win.refresh");
            view_menu.append_section(null, v2);
            menu.append_submenu(_("View"), view_menu);

            var repo_menu = new GLib.Menu();
            var sync = new GLib.Menu();
            sync.append(_("Fetch"), "win.fetch");
            sync.append(_("Pull"), "win.pull");
            sync.append(_("Push"), "win.push");
            repo_menu.append_section(null, sync);
            var changes = new GLib.Menu();
            changes.append(_("Stage All"), "win.stage-all");
            changes.append(_("Commit"), "win.commit");
            repo_menu.append_section(null, changes);
            var extra = new GLib.Menu();
            extra.append(_("New Branch…"), "win.new-branch");
            repo_menu.append_section(null, extra);
            menu.append_submenu(_("Repository"), repo_menu);

            set_menubar(menu);

            var settings_action = new SimpleAction("settings", null);
            settings_action.activate.connect(() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync(
                        BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings("dev.sinty.git");
                } catch (Error e) {
                    warning("Failed to open settings: %s", e.message);
                }
            });
            add_action(settings_action);

            set_accels_for_action("win.open-repo", { "<Control>o" });
            set_accels_for_action("win.close", { "<Control>w" });
            set_accels_for_action("win.refresh", { "<Control>r", "F5" });
            set_accels_for_action("win.commit", { "<Control>Return" });
            set_accels_for_action("app.settings", { "<Control>comma" });
        }

        protected override void activate() {
            ensure_window();
            window.present();
        }

        public override int command_line(ApplicationCommandLine cl) {
            ensure_window();
            string cwd = cl.get_cwd() ?? Environment.get_current_dir();
            var args = cl.get_arguments();
            // Only open a repo when an explicit path argument is given. When
            // launched from the icon (no args) just show the welcome page -
            // don't auto-probe the current directory.
            for (int i = 1; i < args.length; i++) {
                if (args[i].has_prefix("--")) continue;
                var f = File.new_for_commandline_arg_and_cwd(args[i], cwd);
                window.open_repo_at.begin(f.get_path());
            }
            window.present();
            if (cl.get_options_dict().contains("open-repository"))
                window.choose_repository();
            return 0;
        }

        public override void open(File[] files, string hint) {
            ensure_window();
            foreach (var f in files)
                window.open_repo_at.begin(f.get_path());
            window.present();
        }

        private void ensure_window() {
            if (window == null) window = new GitWindow(this);
        }

        private const string STYLE = """
        .git-repo-row { padding: 6px 10px; border-radius: 8px; }
        .git-repo-row.selected { background-color: alpha(@accent_bg_color, 0.18); }
        .git-branch-row { padding: 4px 10px; border-radius: 8px; }
        .git-branch-row.current { font-weight: 700; }
        .git-branch-row.current label { color: @accent_bg_color; }
        .git-commit-row { padding: 6px 10px; border-radius: 8px; }
        .git-commit-row.selected { background-color: alpha(@accent_bg_color, 0.20); }
        .git-commit-subject { font-weight: 600; }
        .git-ref-chip { background-color: alpha(@accent_bg_color, 0.25); border-radius: 6px;
                        padding: 0 6px; font-size: 11px; }
        .git-ref-chip.remote { background-color: alpha(@window_fg_color, 0.15); }
        .git-section-label { font-weight: 700; opacity: 0.6; font-size: 12px;
                             margin: 10px 8px 4px 8px; }
        .git-file-row { padding: 3px 8px; border-radius: 6px; }
        .git-file-row:hover { background-color: alpha(@window_fg_color, 0.08); }
        .git-state-M { color: @warning_color; }
        .git-state-A { color: @success_color; }
        .git-state-D { color: @error_color; }
        .git-state-U { color: @error_color; font-weight: 700; }
        .git-state-untracked { color: alpha(@text_color, 0.55); }
        .diff-add  { background-color: alpha(@success_color, 0.18); }
        .diff-del  { background-color: alpha(@error_color, 0.18); }
        .diff-hunk { color: @accent_color; }
        .git-commit-box { border-top: 1px solid alpha(@window_fg_color, 0.12); }
        .git-toolbar-pill { background-color: alpha(@window_fg_color, 0.08);
                            border-radius: 999px; padding: 2px; }
        .git-conflict-banner { background-color: alpha(@error_color, 0.18);
                               border-radius: 10px; padding: 8px 12px; }
        """;
    }
}
