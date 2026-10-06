using Gtk;
using Singularity;

namespace SingularityGitWidget {

    public class RepoStatusProvider : Object, OverviewWidgetProvider {
        public string id { get { return "git.repo-status"; } }
        public string provider_id { get { return "dev.sinty.git"; } }
        public string display_name { get { return _("Repository Status"); } }
        public string icon_name { get { return "dev.sinty.git"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[1];
                    _sizes[0] = WidgetSize(2, 1);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance(string instance_id, WidgetSize size, Variant? config) {
            string path = config != null && config.is_of_type(VariantType.STRING) ? config.get_string() : "";
            var instance = new RepoStatusInstance(path);
            instance.configure_requested.connect(() => configure_instance(instance_id));
            return instance;
        }

        public bool can_configure(string instance_id) {
            return true;
        }

        public void configure_instance(string instance_id) {
            var registry = OverviewWidgetRegistry.get_default();
            Variant? current = registry.get_instance_config(instance_id);
            string chosen = current != null && current.is_of_type(VariantType.STRING) ? current.get_string() : "";

            var dialog = new Singularity.Shell.ShellDialog.anchored(GLib.Application.get_default(), true, true, true, true);
            var box = new Box(Orientation.VERTICAL, 16);
            box.set_size_request(420, -1);
            box.margin_top = 24;
            box.margin_bottom = 24;
            box.margin_start = 24;
            box.margin_end = 24;

            var options = new Gee.ArrayList<Singularity.Core.AppSettingOption>();
            string[] seen = {};
            foreach (string path in recent_repositories()) {
                seen += path;
                options.add(option(path));
            }
            if (chosen != "" && !(chosen in seen)) options.insert(0, option(chosen));

            var group = new Singularity.Widgets.PreferencesGroup();
            group.title = _("Repository");
            Singularity.Widgets.SelectionRow? row = null;
            if (options.size > 0) {
                if (chosen == "") chosen = options[0].id;
                row = new Singularity.Widgets.SelectionRow.with_options(_("Show"), options, chosen);
                row.selected.connect((item) => chosen = item);
                group.add_row(row);
            }
            var pick_row = new Singularity.Widgets.ActionRow(_("Other Folder"), _("Any folder under Git version control"));
            var pick = new Button.with_label(_("Choose…"));
            pick.valign = Align.CENTER;
            pick.clicked.connect(() => {
                var chooser = new Gtk.FileDialog();
                chooser.title = _("Choose a Repository");
                chooser.select_folder.begin(dialog, null, (obj, res) => {
                    try {
                        var folder = chooser.select_folder.end(res);
                        if (folder != null && folder.get_path() != null) {
                            chosen = folder.get_path();
                            pick_row.subtitle = chosen;
                            if (row != null) row.sensitive = false;
                        }
                    } catch (Error e) {
                    }
                });
            });
            pick_row.add_suffix(pick);
            group.add_row(pick_row);
            box.append(group);

            var buttons = new Box(Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            var cancel = new Button.with_label(_("Cancel"));
            cancel.clicked.connect(() => dialog.close_dialog());
            buttons.append(cancel);
            var save = new Button.with_label(_("Save"));
            save.add_css_class("suggested-action");
            save.clicked.connect(() => {
                registry.save_instance_config(instance_id, chosen != "" ? new Variant.string(chosen) : null);
                dialog.close_dialog();
            });
            buttons.append(save);
            box.append(buttons);
            dialog.content_box.append(box);
            dialog.present();
        }

        private static Singularity.Core.AppSettingOption option(string path) {
            var opt = new Singularity.Core.AppSettingOption();
            opt.id = path;
            opt.label = Path.get_basename(path);
            return opt;
        }

        private static string[] recent_repositories() {
            string[] paths = {};
            var items = RecentManager.get_default().get_items();
            items.sort((a, b) => b.get_modified().compare(a.get_modified()));
            foreach (var info in items) {
                if (info.get_mime_type() != "inode/directory" || !info.has_application("singularity-git")) continue;
                string? path = File.new_for_uri(info.get_uri()).get_path();
                if (path == null || !FileUtils.test(Path.build_filename(path, ".git"), FileTest.EXISTS)) continue;
                if (!(path in paths)) paths += path;
                if (paths.length >= 10) break;
            }
            return paths;
        }
    }

    public class RepoStatusInstance : Box {
        public signal void configure_requested();

        private string path;
        private Label name_label;
        private Label branch_label;
        private Label changes_label;
        private Label sync_label;
        private uint timer = 0;
        private bool loading = false;

        public RepoStatusInstance(string path) {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            this.path = path;
            add_css_class("overview-widget-card");
            add_css_class("overview-git");
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;

            var row = new Box(Orientation.HORIZONTAL, 12);
            row.margin_start = 12;
            row.margin_end = 12;
            var icon = new Image.from_icon_name("dev.sinty.git");
            icon.pixel_size = 48;
            icon.valign = Align.CENTER;
            row.append(icon);

            var texts = new Box(Orientation.VERTICAL, 2);
            texts.valign = Align.CENTER;
            texts.hexpand = true;
            name_label = label("title-4");
            branch_label = label("caption");
            branch_label.add_css_class("dim-label");
            changes_label = label(null);
            sync_label = label("caption");
            sync_label.add_css_class("dim-label");
            texts.append(name_label);
            texts.append(branch_label);
            texts.append(changes_label);
            texts.append(sync_label);
            row.append(texts);

            var button = new Button();
            button.has_frame = false;
            button.add_css_class("flat");
            button.hexpand = true;
            button.vexpand = true;
            button.child = row;
            button.tooltip_text = path != "" ? path : _("Choose a repository");
            button.clicked.connect(() => open());
            append(button);

            if (path == "") {
                name_label.label = _("Repository Status");
                branch_label.label = "";
                changes_label.label = _("Choose a repository");
                sync_label.visible = false;
                return;
            }
            name_label.label = Path.get_basename(path);
            refresh.begin();
            timer = Timeout.add_seconds(30, () => {
                if (get_mapped()) refresh.begin();
                return Source.CONTINUE;
            });
            map.connect(() => refresh.begin());
            destroy.connect(() => {
                if (timer != 0) Source.remove(timer);
                timer = 0;
            });
        }

        private static Label label(string? css) {
            var l = new Label("");
            l.xalign = 0;
            l.ellipsize = Pango.EllipsizeMode.END;
            if (css != null) l.add_css_class(css);
            return l;
        }

        private void open() {
            if (path == "") {
                configure_requested();
                return;
            }
            var app = new DesktopAppInfo("dev.sinty.git.desktop");
            if (app == null) return;
            var uris = new List<string>();
            uris.append(File.new_for_path(path).get_uri());
            try {
                app.launch_uris(uris, Gdk.Display.get_default().get_app_launch_context());
            } catch (Error e) {
                warning("Git widget: %s", e.message);
            }
        }

        private async void refresh() {
            if (loading) return;
            loading = true;
            string output = "";
            bool ok = false;
            try {
                var proc = new Subprocess.newv({ "git", "-C", path, "status", "--porcelain=v2", "--branch" },
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string? stdout_text;
                yield proc.communicate_utf8_async(null, null, out stdout_text, null);
                ok = proc.get_successful();
                output = stdout_text ?? "";
            } catch (Error e) {
                ok = false;
            }
            loading = false;
            if (!ok) {
                branch_label.label = "";
                changes_label.label = _("Not a Git repository");
                sync_label.visible = false;
                return;
            }
            show_status(output);
        }

        private void show_status(string output) {
            string branch = "";
            string upstream = "";
            int ahead = 0;
            int behind = 0;
            int changes = 0;
            foreach (string line in output.split("\n")) {
                if (line.has_prefix("# branch.head ")) {
                    branch = line.substring(14).strip();
                } else if (line.has_prefix("# branch.upstream ")) {
                    upstream = line.substring(18).strip();
                } else if (line.has_prefix("# branch.ab ")) {
                    string[] parts = line.substring(12).strip().split(" ");
                    if (parts.length == 2) {
                        ahead = int.parse(parts[0].substring(1));
                        behind = int.parse(parts[1].substring(1));
                    }
                } else if (line.length > 1 && (line[0] == '1' || line[0] == '2' || line[0] == 'u' || line[0] == '?') && line[1] == ' ') {
                    changes++;
                }
            }
            branch_label.label = branch == "(detached)" ? _("Detached HEAD") : branch;
            if (changes == 0) {
                changes_label.label = _("No uncommitted changes");
            } else {
                changes_label.label = ngettext("%d uncommitted change", "%d uncommitted changes", changes).printf(changes);
            }
            sync_label.visible = true;
            if (upstream == "") {
                sync_label.label = _("No upstream branch");
            } else if (ahead == 0 && behind == 0) {
                sync_label.label = _("Up to date with %s").printf(upstream);
            } else if (behind == 0) {
                sync_label.label = ngettext("%d commit to push", "%d commits to push", ahead).printf(ahead);
            } else if (ahead == 0) {
                sync_label.label = ngettext("%d commit to pull", "%d commits to pull", behind).printf(behind);
            } else {
                sync_label.label = _("%d to push, %d to pull").printf(ahead, behind);
            }
        }
    }

    [CCode (cname = "singularity_git_widget_new")]
    public static Object singularity_git_widget_new() {
        return new RepoStatusProvider();
    }
}
