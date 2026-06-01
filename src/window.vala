using Gtk;
using GLib;
using Gee;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps.Git {

    public enum ViewMode { WORKING, COMMIT }

    public class GitWindow : Singularity.Widgets.Window {
        private GitApp app;

        // Open repositories.
        private Gee.ArrayList<GitRepo> repos = new Gee.ArrayList<GitRepo>();
        private GitRepo? current = null;

        private ViewMode mode = ViewMode.WORKING;
        private string? selected_commit = null;
        // Files currently shown in the details pane (for the detach window).
        private Gee.ArrayList<DiffFileRef> _current_files = new Gee.ArrayList<DiffFileRef>();

        // Sidebar widgets.
        private ListBox repo_list;
        private Box     branches_box;     // holds local + remote sections
        private Label   repo_status_lbl;

        // Center (commit log).
        private ListBox commit_list;
        private Button  working_btn;
        private Label   working_badge;

        // Right (details).
        private Label    details_title;
        private Box      file_list_box;
        private DiffView diff_view;
        private Revealer commit_revealer;
        private TextView commit_msg;
        private Button   commit_btn;
        private Box      conflict_banner;

        public GitWindow(GitApp app) {
            Object(application: app);
            this.app = app;
            set_title("Git");
            set_default_size(1280, 800);
            build_ui();
        }

        // ── UI ──────────────────────────────────────────────────────────────
        private Stack content_stack;

        private void build_ui() {
            setup_toolbar();

            var outer = new Paned(Orientation.HORIZONTAL);
            outer.position = 280;
            outer.shrink_start_child = false;
            outer.set_start_child(build_sidebar());

            var inner = new Paned(Orientation.HORIZONTAL);
            inner.position = 460;
            inner.set_start_child(build_center());
            inner.set_end_child(build_details());
            outer.set_end_child(inner);

            content_stack = new Stack();
            content_stack.add_named(build_welcome(), "welcome");
            content_stack.add_named(outer, "main");
            content_stack.visible_child_name = "welcome";
            set_content(content_stack);
        }

        private Widget build_welcome() {
            var wp = new Singularity.Widgets.WelcomePage();
            wp.app_icon_name = "dev.sinty.git";
            wp.title = "Git";
            wp.subtitle = "Branches, commits, diffs and conflicts - across multiple repositories.";
            wp.add_action(
                "folder-open-symbolic",
                "Open Repository",
                "Pick a folder under Git version control\nto inspect its history and changes.",
                () => on_open_repo()
            );
            return wp;
        }

        private void show_main() {
            content_stack.visible_child_name = (repos.size > 0) ? "main" : "welcome";
        }

        // Repo-dependent toolbar buttons (disabled when no repo is open).
        private Button refresh_btn;
        private Button fetch_btn;
        private Button pull_btn;
        private Button push_btn;
        private Button branch_btn;

        private void setup_toolbar() {
            var open_btn = new Button.from_icon_name("folder-open-symbolic");
            open_btn.tooltip_text = "Open Repository…";
            open_btn.add_css_class("flat");
            open_btn.clicked.connect(on_open_repo);
            add_bubble_widget(open_btn);

            refresh_btn = new Button.from_icon_name("view-refresh-symbolic");
            refresh_btn.tooltip_text = "Refresh";
            refresh_btn.add_css_class("flat");
            refresh_btn.clicked.connect(() => { if (current != null) reload_repo.begin(); });
            add_bubble_widget(refresh_btn);

            branch_btn = new Button.from_icon_name("list-add-symbolic");
            branch_btn.tooltip_text = "New Branch…";
            branch_btn.add_css_class("flat");
            branch_btn.clicked.connect(on_new_branch);
            add_bubble_widget(branch_btn);

            // Fetch = sync (mail-send-receive is the reliable sync glyph;
            // emblem-synchronizing-symbolic is missing in the theme, so it
            // renders as tofu/emoji fallback).
            fetch_btn = new Button.from_icon_name("mail-send-receive-symbolic");
            fetch_btn.tooltip_text = "Fetch";
            fetch_btn.add_css_class("flat");
            fetch_btn.clicked.connect(() => run_repo_op.begin("fetch"));
            add_bubble_widget(fetch_btn);

            pull_btn = new Button.from_icon_name("folder-download-symbolic");
            pull_btn.tooltip_text = "Pull (fast-forward)";
            pull_btn.add_css_class("flat");
            pull_btn.clicked.connect(() => run_repo_op.begin("pull"));
            add_bubble_widget(pull_btn);

            push_btn = new Button.from_icon_name("send-to-symbolic");
            push_btn.tooltip_text = "Push";
            push_btn.add_css_class("flat");
            push_btn.clicked.connect(() => run_repo_op.begin("push"));
            add_bubble_widget(push_btn);

            add_bubble_icon("view-restore-symbolic",
                            "Open diff in a separate window",
                            () => detach_diff());

            update_toolbar_sensitivity();
        }

        // Hide repo actions when there's no open repository.
        private void update_toolbar_sensitivity() {
            bool has = (current != null);
            if (refresh_btn != null) refresh_btn.visible = has;
            if (fetch_btn != null)   fetch_btn.visible = has;
            if (pull_btn != null)    pull_btn.visible = has;
            if (push_btn != null)    push_btn.visible = has;
            if (branch_btn != null)  branch_btn.visible = has;
        }

        private Widget build_sidebar() {
            var box = new Box(Orientation.VERTICAL, 0);
            box.width_request = 260;

            var repos_lbl = new Label("REPOSITORIES");
            repos_lbl.add_css_class("git-section-label");
            repos_lbl.halign = Align.START;
            box.append(repos_lbl);

            repo_list = new ListBox();
            repo_list.selection_mode = SelectionMode.SINGLE;
            repo_list.add_css_class("navigation-sidebar");
            // Match the branches list horizontal inset.
            repo_list.margin_start = 4; repo_list.margin_end = 4;
            repo_list.row_selected.connect((row) => {
                if (row == null) return;
                int idx = row.get_index();
                if (idx >= 0 && idx < repos.size) select_repo(repos[idx]);
            });
            box.append(repo_list);

            var br_lbl = new Label("BRANCHES");
            br_lbl.add_css_class("git-section-label");
            br_lbl.halign = Align.START;
            box.append(br_lbl);

            var br_scroll = new ScrolledWindow();
            br_scroll.vexpand = true;
            br_scroll.hscrollbar_policy = PolicyType.NEVER;
            branches_box = new Box(Orientation.VERTICAL, 2);
            branches_box.margin_start = 4; branches_box.margin_end = 4;
            br_scroll.set_child(branches_box);
            box.append(br_scroll);

            repo_status_lbl = new Label("");
            repo_status_lbl.add_css_class("caption");
            repo_status_lbl.add_css_class("dim-label");
            repo_status_lbl.halign = Align.START;
            repo_status_lbl.margin_start = 10;
            repo_status_lbl.margin_top = 6; repo_status_lbl.margin_bottom = 6;
            repo_status_lbl.ellipsize = Pango.EllipsizeMode.END;
            box.append(repo_status_lbl);

            return box;
        }

        private Widget build_center() {
            var box = new Box(Orientation.VERTICAL, 0);
            box.width_request = 360;

            // "Working changes" pseudo-entry pinned on top.
            working_btn = new Button();
            working_btn.add_css_class("flat");
            working_btn.add_css_class("git-commit-row");
            var wb = new Box(Orientation.HORIZONTAL, 8);
            var wicon = new Image.from_icon_name("document-edit-symbolic");
            wb.append(wicon);
            var wlbl = new Label("Working Changes");
            wlbl.halign = Align.START; wlbl.hexpand = true;
            wlbl.add_css_class("git-commit-subject");
            wb.append(wlbl);
            working_badge = new Label("");
            working_badge.add_css_class("git-ref-chip");
            working_badge.visible = false;
            wb.append(working_badge);
            working_btn.set_child(wb);
            working_btn.clicked.connect(() => show_working_changes.begin());
            box.append(working_btn);

            box.append(new Separator(Orientation.HORIZONTAL));

            var scroll = new ScrolledWindow();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            commit_list = new ListBox();
            commit_list.selection_mode = SelectionMode.SINGLE;
            commit_list.add_css_class("navigation-sidebar");
            commit_list.row_activated.connect(on_commit_activated);
            scroll.set_child(commit_list);
            box.append(scroll);

            return box;
        }

        private Widget build_details() {
            var box = new Box(Orientation.VERTICAL, 0);
            box.margin_top = 5;

            // Kept for downstream `details_title.label = ...` calls but never appended.
            details_title = new Label("");

            // Conflict banner (hidden unless conflicts).
            conflict_banner = new Box(Orientation.HORIZONTAL, 8);
            conflict_banner.add_css_class("git-conflict-banner");
            conflict_banner.margin_start = 12; conflict_banner.margin_end = 12;
            conflict_banner.visible = false;
            var cb_icon = new Image.from_icon_name("dialog-warning-symbolic");
            conflict_banner.append(cb_icon);
            var cb_lbl = new Label("Merge conflicts - resolve files, then stage them.");
            cb_lbl.halign = Align.START; cb_lbl.hexpand = true;
            conflict_banner.append(cb_lbl);
            box.append(conflict_banner);

            // shrink false + resize true on both children makes the Paned start at 50/50.
            var split = new Paned(Orientation.VERTICAL);
            split.shrink_start_child = false;
            split.shrink_end_child   = false;
            split.resize_start_child = true;
            split.resize_end_child   = true;
            split.vexpand = true;

            var files_scroll = new ScrolledWindow();
            files_scroll.hscrollbar_policy = PolicyType.NEVER;
            files_scroll.propagate_natural_height = false;
            files_scroll.vexpand = true;
            file_list_box = new Box(Orientation.VERTICAL, 1);
            file_list_box.margin_start = 6; file_list_box.margin_end = 6;
            files_scroll.set_child(file_list_box);
            split.set_start_child(files_scroll);

            var bottom_box = new Box(Orientation.VERTICAL, 0);
            bottom_box.vexpand = true;
            diff_view = new DiffView();
            diff_view.vexpand = true;
            bottom_box.append(diff_view);

            // Commit message box (working mode only).
            commit_revealer = new Revealer();
            commit_revealer.transition_type = RevealerTransitionType.SLIDE_UP;
            var cbox = new Box(Orientation.VERTICAL, 6);
            cbox.add_css_class("git-commit-box");
            commit_msg = new TextView();
            commit_msg.wrap_mode = WrapMode.WORD_CHAR;
            commit_msg.add_css_class("git-commit-msg");
            // Placeholder via a sibling Label that hides as soon as the
            // buffer has text. GtkTextView has no placeholder property.
            var commit_overlay = new Overlay();
            commit_overlay.set_child(commit_msg);
            var commit_placeholder = new Label("Write a commit message...");
            commit_placeholder.add_css_class("dim-label");
            commit_placeholder.halign = Align.START;
            commit_placeholder.valign = Align.START;
            commit_placeholder.margin_top = 6;
            commit_placeholder.margin_start = 8;
            commit_placeholder.can_target = false;
            commit_overlay.add_overlay(commit_placeholder);
            commit_msg.buffer.changed.connect(() => {
                commit_placeholder.visible = (commit_msg.buffer.text == "");
            });
            var msg_scroll = new ScrolledWindow();
            msg_scroll.min_content_height = 56;
            msg_scroll.max_content_height = 120;
            msg_scroll.set_child(commit_overlay);
            cbox.append(msg_scroll);

            var crow_wrap = new Box(Orientation.VERTICAL, 0);
            crow_wrap.margin_bottom = 6;
            var crow = new Box(Orientation.HORIZONTAL, 8);
            var stage_all_btn = new Button.with_label("Stage All");
            stage_all_btn.clicked.connect(() => {
                if (current != null) current.stage_all.begin((o, r) => {
                    current.stage_all.end(r); show_working_changes.begin();
                });
            });
            crow.append(stage_all_btn);
            var spacer = new Box(Orientation.HORIZONTAL, 0); spacer.hexpand = true;
            crow.append(spacer);
            commit_btn = new Button.with_label("Commit");
            commit_btn.add_css_class("suggested-action");
            commit_btn.clicked.connect(on_commit);
            crow.append(commit_btn);
            crow_wrap.append(crow);
            cbox.append(crow_wrap);
            commit_revealer.set_child(cbox);
            bottom_box.append(commit_revealer);

            split.set_end_child(bottom_box);
            box.append(split);

            return box;
        }

        // ── Repo management ───────────────────────────────────────────────────
        public async void open_repo_at(string? p) {
            if (p == null) return;

            // A picked folder may itself be a repo, OR be a parent holding many
            // repos in subfolders. Discover every .git under it and open them all.
            var found = new Gee.ArrayList<string>();
            discover_repos(p, found, 0);

            if (found.size == 0) {
                // Nothing nested - p might still be a subdir of a repo. Ask git
                // directly so we can both open it and surface git's real error
                // (not found / dubious ownership / not a repo).
                var disc = yield GitRepo.run_in(p, { "git", "rev-parse", "--show-toplevel" });
                string top = disc.stdout_text.strip();
                if (!disc.ok || top == "") {
                    string detail = disc.stderr_text.strip();
                    if (detail == "" && disc.exit_code < 0)
                        detail = "Could not run git (is it installed and on PATH?)";
                    if (detail == "") detail = "No Git repositories found here.";
                    show_error("Can't open repository", "%s\n\n%s".printf(p, detail));
                    return;
                }
                found.add(top);
            }

            GitRepo? to_select = null;
            foreach (var top in found) {
                GitRepo? existing = null;
                foreach (var r in repos) if (r.path == top) { existing = r; break; }
                if (existing != null) {
                    if (to_select == null) to_select = existing;
                    continue;
                }
                var repo = new GitRepo(top);
                repo.changed.connect(() => { if (current == repo) reload_repo.begin(); });
                repos.add(repo);
                add_repo_row(repo);
                if (to_select == null) to_select = repo;
            }
            if (to_select != null) select_repo(to_select);
        }

        // Recursively collect repository roots (directories containing a .git)
        // under `dir`. Stops descending once a repo is found (its working tree
        // isn't searched for more), skips hidden dirs / node_modules / symlinks,
        // and is depth- and count-bounded so a huge tree can't hang the app.
        private void discover_repos(string dir, Gee.ArrayList<string> outp, int depth) {
            if (outp.size >= 200) return;
            if (FileUtils.test(Path.build_filename(dir, ".git"), FileTest.EXISTS)) {
                outp.add(dir);
                return;
            }
            if (depth >= 5) return;
            try {
                var d = Dir.open(dir, 0);
                string? name;
                while ((name = d.read_name()) != null) {
                    if (name.has_prefix(".")) continue;
                    if (name == "node_modules") continue;
                    string child = Path.build_filename(dir, name);
                    if (FileUtils.test(child, FileTest.IS_DIR)
                        && !FileUtils.test(child, FileTest.IS_SYMLINK)) {
                        discover_repos(child, outp, depth + 1);
                    }
                }
            } catch (Error e) {
                // Unreadable directory: skip it.
            }
        }

        private void add_repo_row(GitRepo repo) {
            var row = new ListBoxRow();
            row.add_css_class("git-repo-row");
            var b = new Box(Orientation.HORIZONTAL, 8);
            b.append(new Image.from_icon_name("folder-symbolic"));
            var lbl = new Label(repo.display_name);
            lbl.halign = Align.START; lbl.hexpand = true;
            lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            b.append(lbl);
            var close = new Button.from_icon_name("window-close-symbolic");
            close.add_css_class("flat");
            close.tooltip_text = "Close repository";
            close.clicked.connect(() => close_repo(repo));
            b.append(close);
            row.set_child(b);
            repo_list.append(row);
        }

        private void close_repo(GitRepo repo) {
            int idx = repos.index_of(repo);
            if (idx < 0) return;
            repos.remove(repo);
            var row = repo_list.get_row_at_index(idx);
            if (row != null) repo_list.remove(row);
            if (current == repo) {
                current = repos.size > 0 ? repos[0] : null;
                if (current != null) select_repo(current);
                else { clear_views(); set_title("Git"); }
            }
            update_toolbar_sensitivity();
            show_main();
        }

        private void select_repo(GitRepo repo) {
            current = repo;
            set_title("Git - " + repo.display_name);
            // sync sidebar selection highlight
            int idx = repos.index_of(repo);
            var row = repo_list.get_row_at_index(idx);
            if (row != null) repo_list.select_row(row);
            update_toolbar_sensitivity();
            show_main();
            reload_repo.begin();
        }

        private bool _reloading = false;
        private bool _reload_again = false;

        private async void reload_repo() {
            if (current == null) return;
            // Serialize: two overlapping reloads (e.g. fetch fires both the
            // `changed` signal AND an explicit reload) would each clear the
            // empty lists then both append, doubling every row. Coalesce.
            if (_reloading) { _reload_again = true; return; }
            _reloading = true;
            yield refresh_branches();
            yield refresh_log();
            if (mode == ViewMode.WORKING) yield show_working_changes();
            else if (selected_commit != null) yield show_commit(selected_commit);
            _reloading = false;
            if (_reload_again) { _reload_again = false; reload_repo.begin(); }
        }

        // ── Branches ───────────────────────────────────────────────────────
        private async void refresh_branches() {
            child_clear(branches_box);
            if (current == null) return;
            var bs = yield current.branches();
            // local first, then remotes
            append_branch_section("Local", bs, false);
            append_branch_section("Remote", bs, true);

            var st = yield current.status();
            string s = "on %s".printf(st.branch);
            if (st.ahead > 0) s += "  ↑%d".printf(st.ahead);
            if (st.behind > 0) s += "  ↓%d".printf(st.behind);
            repo_status_lbl.label = s;
        }

        private void append_branch_section(string title, Gee.ArrayList<BranchInfo> bs, bool remote) {
            bool any = false;
            foreach (var b in bs) if (b.is_remote == remote) { any = true; break; }
            if (!any) return;
            var lbl = new Label(title);
            lbl.add_css_class("git-section-label");
            lbl.halign = Align.START;
            branches_box.append(lbl);
            foreach (var b in bs) {
                if (b.is_remote != remote) continue;
                branches_box.append(make_branch_row(b));
            }
        }

        private Widget make_branch_row(BranchInfo b) {
            var btn = new Button();
            btn.add_css_class("flat");
            btn.add_css_class("git-branch-row");
            if (b.is_current) btn.add_css_class("current");
            var row = new Box(Orientation.HORIZONTAL, 6);
            row.append(new Image.from_icon_name(
                b.is_remote ? "network-server-symbolic" : "media-playlist-shuffle-symbolic"));
            var lbl = new Label(b.name);
            lbl.halign = Align.START; lbl.hexpand = true;
            lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            row.append(lbl);
            if (b.ahead > 0 || b.behind > 0) {
                var t = new Label("↑%d ↓%d".printf(b.ahead, b.behind));
                t.add_css_class("caption"); t.add_css_class("dim-label");
                row.append(t);
            }
            btn.set_child(row);
            string bname = b.name;
            btn.clicked.connect(() => {
                if (current == null) return;
                current.checkout.begin(bname, (o, r) => {
                    var res = current.checkout.end(r);
                    if (!res.ok) toast("Checkout failed: " + res.stderr_text);
                });
            });
            return btn;
        }

        // ── Commit log ───────────────────────────────────────────────────────
        private async void refresh_log() {
            child_clear_listbox(commit_list);
            if (current == null) return;
            var commits = yield current.log(500);
            foreach (var c in commits) {
                commit_list.append(make_commit_row(c));
            }
        }

        private Widget make_commit_row(CommitInfo c) {
            var row = new ListBoxRow();
            row.add_css_class("git-commit-row");
            row.set_data<string>("hash", c.hash);
            var b = new Box(Orientation.HORIZONTAL, 8);

            // Lane dot (simple graph hint).
            var dot = new Box(Orientation.HORIZONTAL, 0);
            dot.set_size_request(8 + c.lane * 10, 0);
            var marker = new Image.from_icon_name("media-record-symbolic");
            marker.pixel_size = 10;
            b.append(dot);
            b.append(marker);

            var col = new Box(Orientation.VERTICAL, 1);
            col.hexpand = true;
            var top = new Box(Orientation.HORIZONTAL, 6);
            // ref chips
            foreach (var rf in c.refs) {
                var chip = new Label(rf);
                chip.add_css_class("git-ref-chip");
                if (rf.has_prefix("origin/")) chip.add_css_class("remote");
                top.append(chip);
            }
            var subj = new Label(c.subject);
            subj.halign = Align.START; subj.hexpand = true;
            subj.ellipsize = Pango.EllipsizeMode.END;
            subj.add_css_class("git-commit-subject");
            top.append(subj);
            col.append(top);

            var meta = new Label("%s · %s · %s".printf(
                c.short_hash, c.author_name, c.relative_date));
            meta.halign = Align.START;
            meta.add_css_class("caption"); meta.add_css_class("dim-label");
            col.append(meta);
            b.append(col);

            row.set_child(b);
            return row;
        }

        private void on_commit_activated(ListBoxRow row) {
            string? h = row.get_data<string>("hash");
            if (h != null) show_commit.begin(h);
        }

        // ── Details: commit view ──────────────────────────────────────────────
        private async void show_commit(string hash) {
            if (current == null) return;
            mode = ViewMode.COMMIT;
            selected_commit = hash;
            commit_revealer.reveal_child = false;
            conflict_banner.visible = false;
            working_badge.visible = working_badge.visible; // unchanged

            details_title.label = "Commit " + hash.substring(0, int.min(10, hash.length));
            child_clear(file_list_box);
            _current_files.clear();
            var files = yield current.commit_files(hash);
            foreach (var f in files) {
                file_list_box.append(make_file_row(f, FileState.MODIFIED, "commit"));
                _current_files.add(new DiffFileRef(f, FileState.MODIFIED, "commit"));
            }
            string d = yield current.diff_commit(hash);
            diff_view.show_diff(d);
        }

        // ── Details: working changes ──────────────────────────────────────────
        private async void show_working_changes() {
            if (current == null) return;
            mode = ViewMode.WORKING;
            selected_commit = null;
            details_title.label = "Working Changes";
            commit_revealer.reveal_child = true;

            var st = yield current.status();
            conflict_banner.visible = st.has_conflicts;

            child_clear(file_list_box);
            _current_files.clear();
            int total = st.staged.size + st.unstaged.size + st.untracked.size + st.conflicts.size;
            working_badge.label = total.to_string();
            working_badge.visible = total > 0;

            if (st.conflicts.size > 0) {
                file_list_box.append(section_label("Conflicts"));
                foreach (var fc in st.conflicts) {
                    file_list_box.append(make_file_row(fc.path, FileState.CONFLICTED, "conflict"));
                    _current_files.add(new DiffFileRef(fc.path, FileState.CONFLICTED, "conflict"));
                }
            }
            if (st.staged.size > 0) {
                file_list_box.append(section_label("Staged"));
                foreach (var fc in st.staged) {
                    file_list_box.append(make_file_row(fc.path, fc.state, "staged"));
                    _current_files.add(new DiffFileRef(fc.path, fc.state, "staged"));
                }
            }
            if (st.unstaged.size > 0) {
                file_list_box.append(section_label("Changes"));
                foreach (var fc in st.unstaged) {
                    file_list_box.append(make_file_row(fc.path, fc.state, "unstaged"));
                    _current_files.add(new DiffFileRef(fc.path, fc.state, "unstaged"));
                }
            }
            if (st.untracked.size > 0) {
                file_list_box.append(section_label("Untracked"));
                foreach (var fc in st.untracked) {
                    file_list_box.append(make_file_row(fc.path, FileState.UNTRACKED, "untracked"));
                    _current_files.add(new DiffFileRef(fc.path, FileState.UNTRACKED, "untracked"));
                }
            }
            if (total == 0) {
                diff_view.show_message("Working tree clean - nothing to commit.");
            }
        }

        private Widget section_label(string t) {
            var l = new Label(t);
            l.add_css_class("git-section-label");
            l.halign = Align.START;
            return l;
        }

        private Widget make_file_row(string path, FileState st, string kind) {
            var row = new Box(Orientation.HORIZONTAL, 6);
            row.add_css_class("git-file-row");

            string letter = state_letter(st);
            var sl = new Label(letter);
            sl.add_css_class(state_css(st));
            sl.width_chars = 1;
            row.append(sl);

            var btn = new Button();
            btn.add_css_class("flat");
            btn.hexpand = true;
            var lbl = new Label(path);
            lbl.halign = Align.START; lbl.hexpand = true;
            lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            btn.set_child(lbl);
            btn.clicked.connect(() => on_file_clicked.begin(path, st, kind));
            row.append(btn);

            // Action button depends on kind.
            if (kind == "staged") {
                var unb = new Button.from_icon_name("list-remove-symbolic");
                unb.add_css_class("flat"); unb.tooltip_text = "Unstage";
                unb.clicked.connect(() => current.unstage.begin(path, (o, r) => {
                    current.unstage.end(r); show_working_changes.begin();
                }));
                row.append(unb);
            } else if (kind == "unstaged" || kind == "untracked") {
                var ad = new Button.from_icon_name("list-add-symbolic");
                ad.add_css_class("flat"); ad.tooltip_text = "Stage";
                ad.clicked.connect(() => current.stage.begin(path, (o, r) => {
                    current.stage.end(r); show_working_changes.begin();
                }));
                row.append(ad);
                if (kind == "unstaged") {
                    var disc = new Button.from_icon_name("edit-undo-symbolic");
                    disc.add_css_class("flat"); disc.tooltip_text = "Discard changes";
                    disc.clicked.connect(() => current.discard.begin(path, (o, r) => {
                        current.discard.end(r); show_working_changes.begin();
                    }));
                    row.append(disc);
                }
            } else if (kind == "conflict") {
                var open = new Button.from_icon_name("document-edit-symbolic");
                open.add_css_class("flat"); open.tooltip_text = "Open in editor";
                open.clicked.connect(() => open_in_editor(path));
                row.append(open);
                var mark = new Button.from_icon_name("object-select-symbolic");
                mark.add_css_class("flat"); mark.tooltip_text = "Mark resolved (stage)";
                mark.clicked.connect(() => current.stage_conflict_resolved.begin(path, (o, r) => {
                    current.stage_conflict_resolved.end(r); show_working_changes.begin();
                }));
                row.append(mark);
            }
            return row;
        }

        private async void on_file_clicked(string path, FileState st, string kind) {
            if (current == null) return;
            string d;
            if (kind == "commit") {
                d = yield current.diff_commit(selected_commit, path);
            } else if (kind == "staged") {
                d = yield current.diff_working(path, true);
            } else if (kind == "untracked") {
                d = yield current.diff_untracked(path);
            } else {
                d = yield current.diff_working(path, false);
            }
            if (d.strip() == "") diff_view.show_message("(no textual diff)");
            else diff_view.show_diff(d);
        }

        private void open_in_editor(string path) {
            if (current == null) return;
            string full = Path.build_filename(current.path, path);
            try {
                Process.spawn_command_line_async(
                    "/opt/local/bin/singularity-edit " + GLib.Shell.quote(full));
            } catch (Error e) {
                try { GLib.AppInfo.launch_default_for_uri(
                    File.new_for_path(full).get_uri(), null); } catch (Error e2) {}
            }
        }

        // ── Actions ───────────────────────────────────────────────────────────
        private void on_commit() {
            if (current == null) return;
            TextIter s, e;
            commit_msg.buffer.get_bounds(out s, out e);
            string msg = commit_msg.buffer.get_text(s, e, false).strip();
            if (msg == "") { toast("Enter a commit message."); return; }
            current.commit.begin(msg, (o, r) => {
                var res = current.commit.end(r);
                if (res.ok) { commit_msg.buffer.text = ""; show_working_changes.begin(); }
                else toast("Commit failed: " + res.stderr_text);
            });
        }

        private async void run_repo_op(string op) {
            if (current == null) return;
            GitResult res;
            if (op == "fetch") res = yield current.fetch();
            else if (op == "pull") res = yield current.pull();
            else if (op == "push") res = yield current.push();
            else return;
            if (!res.ok) toast(op + " failed: " + res.stderr_text);
            else toast(op + " ok");
            yield reload_repo();
        }

        // Held as a field: a FileChooserNative kept only as a local var gets
        // freed when on_open_repo() returns, BEFORE the portal delivers the
        // response - so the dialog opens, you pick a folder, and nothing
        // happens ("rimane muto").
        private Gtk.FileChooserNative? _open_dialog = null;

        private void on_open_repo() {
            _open_dialog = new Gtk.FileChooserNative(
                "Open Repository", this, Gtk.FileChooserAction.SELECT_FOLDER,
                "Open", "Cancel");
            _open_dialog.response.connect((id) => {
                if (id == Gtk.ResponseType.ACCEPT) {
                    var f = _open_dialog.get_file();
                    if (f != null) {
                        // get_path() can be null for portal-returned folders -
                        // fall back to resolving the URI so the picker isn't mute.
                        string? path = f.get_path();
                        if (path == null) {
                            try { path = Filename.from_uri(f.get_uri()); }
                            catch (Error e) { path = null; }
                        }
                        if (path != null) open_repo_at.begin(path);
                        else toast("Couldn't resolve the selected folder path.");
                    }
                }
                _open_dialog = null;
            });
            _open_dialog.show();
        }

        // Pop the diff out into its own window (Leafs/browser-style floating
        // controls) with the current changes listed on the left.
        private void detach_diff() {
            if (current == null || _current_files.size == 0) return;
            string title = (mode == ViewMode.COMMIT && selected_commit != null)
                ? "Commit %s".printf(selected_commit.substring(0, int.min(10, selected_commit.length)))
                : "Working Changes";
            // Copy the list so the window owns its own snapshot.
            var snapshot = new Gee.ArrayList<DiffFileRef>();
            foreach (var f in _current_files) snapshot.add(f);
            var win = new DiffWindow(app, current,
                (mode == ViewMode.COMMIT) ? selected_commit : null, title, snapshot);
            win.present();
        }

        private void on_new_branch() {
            if (current == null) return;
            // Use the shared Singularity dialog (same as Files' New Folder /
            // Properties), not a bare Gtk.Window.
            var dialog = new Singularity.Widgets.AppDialog(app, false);
            dialog.title = "New Branch";
            dialog.transient_for = this;
            dialog.set_default_size(380, 170);

            var box = new Box(Orientation.VERTICAL, 16);
            box.margin_top = 24; box.margin_bottom = 24;
            box.margin_start = 24; box.margin_end = 24;

            var entry = new Entry();
            entry.placeholder_text = "branch name";
            entry.hexpand = true;
            box.append(entry);

            var btn_box = new Box(Orientation.HORIZONTAL, 8);
            btn_box.halign = Align.END;
            var cancel = new Button.with_label("Cancel");
            cancel.add_css_class("flat");
            cancel.clicked.connect(() => dialog.close());
            var create = new Button.with_label("Create & Checkout");
            create.add_css_class("suggested-action");
            create.clicked.connect(() => {
                string name = entry.text.strip();
                if (name == "") return;
                current.create_branch.begin(name, true, (o, r) => {
                    var res = current.create_branch.end(r);
                    if (!res.ok) show_error("Branch failed", res.stderr_text.strip());
                });
                dialog.close();
            });
            btn_box.append(cancel);
            btn_box.append(create);
            box.append(btn_box);

            var key_ctrl = new EventControllerKey();
            key_ctrl.key_pressed.connect((kv, kc, mstate) => {
                if (kv == Gdk.Key.Return || kv == Gdk.Key.KP_Enter) { create.clicked(); return true; }
                return false;
            });
            entry.add_controller(key_ctrl);

            dialog.content_box.append(box);
            dialog.present();
        }

        // ── Helpers ───────────────────────────────────────────────────────────
        private void clear_views() {
            child_clear(branches_box);
            child_clear_listbox(commit_list);
            child_clear(file_list_box);
            diff_view.clear();
            repo_status_lbl.label = "";
        }

        private void child_clear(Box b) {
            Widget? c = b.get_first_child();
            while (c != null) { Widget n = c.get_next_sibling(); b.remove(c); c = n; }
        }

        private void child_clear_listbox(ListBox lb) {
            Widget? c = lb.get_first_child();
            while (c != null) { Widget n = c.get_next_sibling(); lb.remove(c); c = n; }
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

        private void toast(string msg) {
            details_title.set_tooltip_text(msg);
            warning("git: %s", msg);
        }

        // Visible, dismissable error (used for repo-open failures etc.).
        private void show_error(string title, string detail) {
            warning("git: %s - %s", title, detail);
            var dlg = new Gtk.AlertDialog("%s", title);
            dlg.set_detail(detail);
            dlg.set_modal(true);
            dlg.show(this);
        }
    }
}
