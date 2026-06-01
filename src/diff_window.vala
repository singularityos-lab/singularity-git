using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps.Git {

    // One changed file shown in the detached diff window's sidebar.
    public class DiffFileRef : Object {
        public string path;
        public FileState state;
        public string kind;   // "commit" | "staged" | "unstaged" | "untracked" | "conflict"
        public DiffFileRef(string path, FileState state, string kind) {
            this.path = path; this.state = state; this.kind = kind;
        }
    }

    /**
     * Pops the diff out into its own window so it can be read full-size.
     * No toolbar: Leafs/browser-style floating bubbles (drag grip + close).
     * Left sidebar lists every change of the commit / working set; clicking a
     * file swaps the diff in place (one window, not many).
     */
    public class DiffWindow : Singularity.Widgets.Window {
        private GitRepo repo;
        private string? commit;          // null = working changes
        private DiffView diff_view;
        private ListBox file_list;
        private Gee.ArrayList<DiffFileRef> files;
        private DiffFileRef? selected = null;

        // Working-change actions, shown in the floating hover bubbles next to
        // the drag grip / close: edit / stage / unstage / restore. Hidden when
        // viewing a commit (read-only history).
        private Button edit_btn;
        private Button stage_btn;
        private Button unstage_btn;
        private Button restore_btn;
        private Box _actions_sep;

        public DiffWindow(Gtk.Application app, GitRepo repo, string? commit,
                          string title, Gee.ArrayList<DiffFileRef> files) {
            Object(application: app);
            this.repo = repo;
            this.commit = commit;
            this.files = files;
            set_title(title);
            set_default_size(1100, 760);

            // No toolbar: floating bubbles instead (drag + close).
            flat = true;
            show_close = false;

            var paned = new Paned(Orientation.HORIZONTAL);
            paned.position = 300;
            paned.shrink_start_child = false;

            // Left: file list.
            var left = new Box(Orientation.VERTICAL, 0);
            left.width_request = 260;
            var hdr = new Label(title);
            hdr.add_css_class("git-section-label");
            hdr.halign = Align.START;
            hdr.ellipsize = Pango.EllipsizeMode.END;
            hdr.margin_start = 10; hdr.margin_top = 12;
            left.append(hdr);
            var scroll = new ScrolledWindow();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            file_list = new ListBox();
            file_list.selection_mode = SelectionMode.SINGLE;
            file_list.add_css_class("navigation-sidebar");
            file_list.margin_start = 4; file_list.margin_end = 4;
            file_list.row_activated.connect(on_row_activated);
            file_list.row_selected.connect((r) => { if (r != null) on_row_activated(r); });
            scroll.set_child(file_list);
            left.append(scroll);
            paned.set_start_child(left);

            // Right: the diff.
            diff_view = new DiffView();
            paned.set_end_child(diff_view);

            // Floating bubbles over the whole thing.
            var hover = new HoverControls();
            hover.set_content(paned);

            // Working-change actions live in the bubbles, before the drag/close.
            edit_btn = new Button.from_icon_name("document-edit-symbolic");
            edit_btn.tooltip_text = _("Edit in editor");
            edit_btn.clicked.connect(() => { if (selected != null) open_in_editor(selected.path); });
            hover.add_control(edit_btn);

            stage_btn = new Button.from_icon_name("list-add-symbolic");
            stage_btn.tooltip_text = _("Stage");
            stage_btn.clicked.connect(() => act_stage());
            hover.add_control(stage_btn);

            unstage_btn = new Button.from_icon_name("list-remove-symbolic");
            unstage_btn.tooltip_text = _("Unstage");
            unstage_btn.clicked.connect(() => act_unstage());
            hover.add_control(unstage_btn);

            restore_btn = new Button.from_icon_name("edit-undo-symbolic");
            restore_btn.tooltip_text = _("Restore (discard changes)");
            restore_btn.clicked.connect(() => act_restore());
            hover.add_control(restore_btn);

            // Separator between the actions and the drag/close bubbles. Added as
            // a control so we can hide it (with the actions) in commit view.
            _actions_sep = new Box(Orientation.HORIZONTAL, 0);
            hover.add_control(_actions_sep);
            _actions_sep.remove_css_class("singularity-hover-btn");
            _actions_sep.add_css_class("singularity-hover-sep");

            var grip = new Button.from_icon_name("list-drag-handle-symbolic");
            grip.tooltip_text = _("Drag Window");
            var grip_drag = new Gtk.GestureDrag();
            grip_drag.drag_begin.connect((x, y) => {
                var surface = get_surface();
                if (surface is Gdk.Toplevel)
                    ((Gdk.Toplevel) surface).begin_move(grip_drag.get_device(), 1, x, y, Gdk.CURRENT_TIME);
            });
            grip.add_controller(grip_drag);
            hover.add_control(grip);

            hover.add_separator();

            var close_btn = new Button.from_icon_name("window-close-symbolic");
            close_btn.tooltip_text = _("Close");
            close_btn.clicked.connect(() => close());
            hover.add_control(close_btn);

            set_content(hover);

            // Populate + show the first file's diff.
            update_actions(); // hidden until a working-change row is selected
            populate();
        }

        private void populate() {
            string? cur_kind = null;
            ListBoxRow? first_file_row = null;
            int i = 0;
            foreach (var f in files) {
                // Group header whenever the section changes, so it's obvious
                // which files are staged vs not (working view only - a commit
                // is a single homogeneous set).
                if (commit == null && f.kind != cur_kind) {
                    cur_kind = f.kind;
                    file_list.append(make_section_header(section_title(f.kind)));
                }
                var row = new ListBoxRow();
                row.set_data<int>("idx", i);
                row.set_data<string>("fpath", f.path);
                row.add_css_class("git-file-row");
                var b = new Box(Orientation.HORIZONTAL, 6);
                var sl = new Label(state_letter(f.state));
                sl.add_css_class(state_css(f.state));
                sl.width_chars = 1;
                b.append(sl);
                var lbl = new Label(f.path);
                lbl.halign = Align.START; lbl.hexpand = true;
                lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
                b.append(lbl);
                row.set_child(b);
                file_list.append(row);
                if (first_file_row == null) first_file_row = row;
                i++;
            }
            if (first_file_row != null) {
                file_list.select_row(first_file_row);
            } else {
                diff_view.show_message("No changes.");
            }
        }

        private ListBoxRow make_section_header(string title) {
            var row = new ListBoxRow();
            row.selectable = false;
            row.activatable = false;
            var lbl = new Label(title);
            lbl.add_css_class("git-section-label");
            lbl.halign = Align.START;
            lbl.margin_start = 6;
            lbl.margin_top = 10;
            lbl.margin_bottom = 2;
            row.set_child(lbl);
            return row;
        }

        private string section_title(string kind) {
            switch (kind) {
                case "conflict":  return "Conflicts";
                case "staged":    return "Staged";
                case "unstaged":  return "Changes";
                case "untracked": return "Untracked";
                default:          return "Files";
            }
        }

        private void on_row_activated(ListBoxRow row) {
            int idx = row.get_data<int>("idx");
            if (idx < 0 || idx >= files.size) return;
            selected = files[idx];
            update_actions();
            load_diff.begin(selected);
        }

        // Show only the bubble actions that make sense for the selected change.
        // A commit's files are historical, so all actions stay hidden there.
        private void update_actions() {
            bool editable = (selected != null && selected.kind != "commit");
            _actions_sep.visible = editable;
            edit_btn.visible = editable;
            if (!editable) {
                stage_btn.visible = false;
                unstage_btn.visible = false;
                restore_btn.visible = false;
                return;
            }
            switch (selected.kind) {
                case "staged":
                    stage_btn.visible = false;
                    unstage_btn.visible = true;
                    restore_btn.visible = false;
                    break;
                case "unstaged":
                    stage_btn.visible = true;
                    stage_btn.tooltip_text = _("Stage");
                    unstage_btn.visible = false;
                    restore_btn.visible = true;
                    break;
                case "untracked":
                    stage_btn.visible = true;
                    stage_btn.tooltip_text = _("Stage");
                    unstage_btn.visible = false;
                    restore_btn.visible = false; // discard would delete a new file
                    break;
                case "conflict":
                    stage_btn.visible = true;     // stage = mark resolved
                    stage_btn.tooltip_text = _("Mark resolved (stage)");
                    unstage_btn.visible = false;
                    restore_btn.visible = false;
                    break;
                default:
                    stage_btn.visible = false;
                    unstage_btn.visible = false;
                    restore_btn.visible = false;
                    break;
            }
        }

        private void act_stage() {
            if (selected == null) return;
            string path = selected.path;
            repo.stage.begin(path, (o, r) => { repo.stage.end(r); refresh_files.begin(path); });
        }
        private void act_unstage() {
            if (selected == null) return;
            string path = selected.path;
            repo.unstage.begin(path, (o, r) => { repo.unstage.end(r); refresh_files.begin(path); });
        }
        private void act_restore() {
            if (selected == null) return;
            string path = selected.path;
            repo.discard.begin(path, (o, r) => { repo.discard.end(r); refresh_files.begin(path); });
        }

        private void open_in_editor(string path) {
            string full = Path.build_filename(repo.path, path);
            try {
                Process.spawn_command_line_async(
                    "/opt/local/bin/singularity-edit " + GLib.Shell.quote(full));
            } catch (Error e) {
                try { GLib.AppInfo.launch_default_for_uri(
                    File.new_for_path(full).get_uri(), null); } catch (Error e2) {}
            }
        }

        // Rebuild the file list from a fresh status after a stage/unstage/
        // restore (the file may have moved between sections). Tries to keep the
        // selection on `keep_path`. Working-changes mode only.
        private async void refresh_files(string? keep_path) {
            if (commit != null) return; // commit view is read-only
            var st = yield repo.status();
            var rebuilt = new Gee.ArrayList<DiffFileRef>();
            foreach (var fc in st.conflicts)
                rebuilt.add(new DiffFileRef(fc.path, FileState.CONFLICTED, "conflict"));
            foreach (var fc in st.staged)
                rebuilt.add(new DiffFileRef(fc.path, fc.state, "staged"));
            foreach (var fc in st.unstaged)
                rebuilt.add(new DiffFileRef(fc.path, fc.state, "unstaged"));
            foreach (var fc in st.untracked)
                rebuilt.add(new DiffFileRef(fc.path, FileState.UNTRACKED, "untracked"));
            files = rebuilt;

            // Re-render the list.
            ListBoxRow? c = file_list.get_row_at_index(0);
            while (c != null) { file_list.remove(c); c = file_list.get_row_at_index(0); }
            selected = null;
            populate();

            // Restore selection to the same path if it's still present. Match by
            // the stored path since section headers offset the row indices.
            if (keep_path != null) {
                int ridx = 0;
                ListBoxRow? r;
                while ((r = file_list.get_row_at_index(ridx)) != null) {
                    string? p = r.get_data<string>("fpath");
                    if (p != null && p == keep_path) { file_list.select_row(r); break; }
                    ridx++;
                }
            }
        }

        private async void load_diff(DiffFileRef f) {
            string d;
            if (f.kind == "commit")        d = yield repo.diff_commit(commit, f.path);
            else if (f.kind == "staged")   d = yield repo.diff_working(f.path, true);
            else if (f.kind == "untracked")d = yield repo.diff_untracked(f.path);
            else                            d = yield repo.diff_working(f.path, false);
            if (d.strip() == "") diff_view.show_message("(no textual diff)");
            else diff_view.show_diff(d);
        }

        private string state_letter(FileState st) {
            switch (st) {
                case FileState.MODIFIED:   return "M";
                case FileState.ADDED:      return "A";
                case FileState.DELETED:    return "D";
                case FileState.RENAMED:    return "R";
                case FileState.CONFLICTED: return "U";
                case FileState.UNTRACKED:  return "?";
                default: return "•";
            }
        }
        private string state_css(FileState st) {
            switch (st) {
                case FileState.ADDED:      return "git-state-A";
                case FileState.DELETED:    return "git-state-D";
                case FileState.CONFLICTED: return "git-state-U";
                case FileState.UNTRACKED:  return "git-state-untracked";
                default: return "git-state-M";
            }
        }
    }
}
