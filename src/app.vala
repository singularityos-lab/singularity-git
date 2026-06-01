using Gtk;
using GLib;
using Singularity;

namespace Singularity.Apps.Git {

    public class GitApp : Singularity.Application {
        private GitWindow? window = null;

        public GitApp() {
            base("dev.sinty.git",
                 ApplicationFlags.HANDLES_OPEN | ApplicationFlags.HANDLES_COMMAND_LINE);
        }

        protected override void startup() {
            base.startup();
            var prov = new Gtk.CssProvider();
            prov.load_from_string(STYLE);
            var disp = Gdk.Display.get_default();
            if (disp != null)
                Gtk.StyleContext.add_provider_for_display(
                    disp, prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
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
        .git-state-M { color: #e0a000; }
        .git-state-A { color: #33b35a; }
        .git-state-D { color: #e05c5c; }
        .git-state-U { color: #e05c5c; font-weight: 700; }
        .git-state-untracked { color: #888; }
        .diff-add  { background-color: alpha(#33b35a, 0.18); }
        .diff-del  { background-color: alpha(#e05c5c, 0.18); }
        .diff-hunk { color: #3584e4; }
        .git-commit-box { border-top: 1px solid alpha(@window_fg_color, 0.12); }
        .git-toolbar-pill { background-color: alpha(@window_fg_color, 0.08);
                            border-radius: 999px; padding: 2px; }
        .git-conflict-banner { background-color: alpha(#e05c5c, 0.18);
                               border-radius: 10px; padding: 8px 12px; }
        """;
    }
}
