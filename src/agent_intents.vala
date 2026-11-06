using Singularity.Git;

namespace Singularity.Apps.Git {

    internal class GitIntents : Object {
        private const string[] REMOTE_OPS = { "fetch", "pull", "push" };
        private const int DEFAULT_LOG = 30;
        private const long DIFF_LIMIT = 65536;
        private const string REPO = "\"path\":{\"type\":\"string\",\"description\":\"A folder inside the repository. Without it the repository shown in the window is used.\"}";

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static string list (string[] values) {
            var b = new StringBuilder ("[");
            for (int i = 0; i < values.length; i++) {
                if (i > 0) b.append (",");
                b.append ("\"").append (values[i]).append ("\"");
            }
            return b.append ("]").str;
        }

        private static string schema (string extra = "", string required = "") {
            string props = REPO + (extra != "" ? "," + extra : "");
            string req = required != "" ? ",\"required\":[" + required + "]" : "";
            return "{\"type\":\"object\",\"properties\":{" + props + "}" + req + "}";
        }

        private static string state_name (FileState s) {
            switch (s) {
                case FileState.UNTRACKED: return "untracked";
                case FileState.MODIFIED: return "modified";
                case FileState.ADDED: return "added";
                case FileState.DELETED: return "deleted";
                case FileState.RENAMED: return "renamed";
                case FileState.CONFLICTED: return "conflicted";
                default: return "type-changed";
            }
        }

        private static Json.Array changes (Gee.List<FileChange> files) {
            var a = new Json.Array ();
            foreach (var f in files) {
                var o = new Json.Object ();
                o.set_string_member ("file", f.path);
                o.set_string_member ("state", state_name (f.state));
                if (f.orig_path != null && f.orig_path != "") o.set_string_member ("from", f.orig_path);
                a.add_object_element (o);
            }
            return a;
        }

        private static void check (GitResult r) throws Error {
            if (r.ok) return;
            string detail = r.stderr_text.strip ();
            if (detail == "") detail = r.stdout_text.strip ();
            throw new IOError.FAILED ("git failed: %s", detail != "" ? detail : "exit code %d".printf (r.exit_code));
        }

        private static async GitRepo resolve (GitApp app, Json.Object args) throws Error {
            var w = app.shown_window ();
            string path = text (args, "path");
            if (path == "") {
                var cur = w.current_repo;
                if (cur == null) throw new IOError.NOT_FOUND ("no repository is open; give a path");
                return cur;
            }
            if (!FileUtils.test (path, FileTest.IS_DIR)) throw new IOError.NOT_FOUND ("%s is not a folder", path);
            string? top = yield GitRepo.discover (path);
            if (top == null) throw new IOError.NOT_FOUND ("%s is not inside a Git repository", path);
            var repo = w.find_repo (top);
            if (repo == null) {
                yield w.open_repo_at (top);
                repo = w.find_repo (top);
            }
            if (repo == null) throw new IOError.FAILED ("%s could not be opened", top);
            w.show_repo (repo);
            return repo;
        }

        private static async Json.Node status (GitRepo repo) {
            var st = yield repo.status ();
            var o = new Json.Object ();
            o.set_string_member ("repository", repo.path);
            o.set_string_member ("branch", st.branch);
            o.set_int_member ("ahead", st.ahead);
            o.set_int_member ("behind", st.behind);
            o.set_array_member ("staged", changes (st.staged));
            o.set_array_member ("unstaged", changes (st.unstaged));
            o.set_array_member ("untracked", changes (st.untracked));
            o.set_array_member ("conflicts", changes (st.conflicts));
            return obj (o);
        }

        private static string[] files (Json.Object args) {
            string[] out = {};
            if (args.has_member ("files")) {
                foreach (var n in args.get_array_member ("files").get_elements ()) out += n.get_string ();
            }
            return out;
        }

        private static async Json.Node handle (GitApp app, string name, Json.Object args) throws Error {
            if (name == "git_repositories") {
                var w = app.shown_window ();
                var a = new Json.Array ();
                foreach (var r in w.open_repos) a.add_string_element (r.path);
                var o = new Json.Object ();
                o.set_array_member ("repositories", a);
                o.set_string_member ("current", w.current_repo != null ? w.current_repo.path : "");
                return obj (o);
            }
            var repo = yield resolve (app, args);
            switch (name) {
                case "git_status":
                    return yield status (repo);
                case "git_log": {
                    int max = args.has_member ("limit") ? (int) args.get_int_member ("limit").clamp (1, 400) : DEFAULT_LOG;
                    string rev = text (args, "revision");
                    var log = yield repo.log (max, rev != "" ? rev : "HEAD");
                    var a = new Json.Array ();
                    foreach (var c in log) {
                        var co = new Json.Object ();
                        co.set_string_member ("hash", c.short_hash);
                        co.set_string_member ("subject", c.subject);
                        co.set_string_member ("author", c.author_name);
                        co.set_string_member ("date", c.date_iso);
                        var refs = new Json.Array ();
                        foreach (var r in c.refs) refs.add_string_element (r);
                        co.set_array_member ("refs", refs);
                        a.add_object_element (co);
                    }
                    var o = new Json.Object ();
                    o.set_string_member ("repository", repo.path);
                    o.set_array_member ("commits", a);
                    return obj (o);
                }
                case "git_branches": {
                    var a = new Json.Array ();
                    foreach (var b in yield repo.branches ()) {
                        var bo = new Json.Object ();
                        bo.set_string_member ("name", b.name);
                        bo.set_boolean_member ("remote", b.is_remote);
                        bo.set_boolean_member ("current", b.is_current);
                        if (b.upstream != null && b.upstream != "") bo.set_string_member ("upstream", b.upstream);
                        bo.set_int_member ("ahead", b.ahead);
                        bo.set_int_member ("behind", b.behind);
                        a.add_object_element (bo);
                    }
                    var o = new Json.Object ();
                    o.set_string_member ("repository", repo.path);
                    o.set_array_member ("branches", a);
                    return obj (o);
                }
                case "git_diff": {
                    string commit = text (args, "commit");
                    string file = text (args, "file");
                    bool staged = args.has_member ("staged") && args.get_boolean_member ("staged");
                    string diff;
                    if (commit != "") {
                        diff = yield repo.diff_commit (commit, file != "" ? file : null);
                    } else {
                        if (file == "") throw new IOError.INVALID_ARGUMENT ("give a file, or a commit");
                        diff = yield repo.diff_working (file, staged);
                        if (diff.strip () == "" && !staged && !(yield repo.is_tracked (file))) diff = yield repo.diff_untracked (file);
                    }
                    var o = new Json.Object ();
                    bool cut = diff.length > DIFF_LIMIT;
                    o.set_string_member ("diff", cut ? diff.substring (0, DIFF_LIMIT) : diff);
                    o.set_boolean_member ("truncated", cut);
                    return obj (o);
                }
                case "git_stage": {
                    bool unstage = args.has_member ("unstage") && args.get_boolean_member ("unstage");
                    bool all = args.has_member ("all") && args.get_boolean_member ("all");
                    string[] list = files (args);
                    if (!all && list.length == 0) throw new IOError.INVALID_ARGUMENT ("give files, or all");
                    if (all && !unstage) {
                        check (yield repo.stage_all ());
                    } else if (all) {
                        check (yield repo.run ({ "git", "reset", "-q" }));
                        repo.changed ();
                    } else {
                        foreach (var f in list) check (unstage ? yield repo.unstage (f) : yield repo.stage (f));
                    }
                    return yield status (repo);
                }
                case "git_discard": {
                    string[] list = files (args);
                    if (list.length == 0) throw new IOError.INVALID_ARGUMENT ("give the files to discard");
                    foreach (var f in list) check (yield repo.discard (f));
                    return yield status (repo);
                }
                case "git_commit": {
                    string message = text (args, "message").strip ();
                    if (message == "") throw new IOError.INVALID_ARGUMENT ("a commit message is required");
                    bool all = args.has_member ("all") && args.get_boolean_member ("all");
                    check (all ? yield repo.commit_all (message) : yield repo.commit (message));
                    var head = yield repo.log (1, "HEAD");
                    var o = new Json.Object ();
                    o.set_string_member ("repository", repo.path);
                    if (head.size > 0) {
                        o.set_string_member ("hash", head[0].short_hash);
                        o.set_string_member ("subject", head[0].subject);
                    }
                    return obj (o);
                }
                case "git_checkout": {
                    string branch = text (args, "branch").strip ();
                    if (branch == "") throw new IOError.INVALID_ARGUMENT ("a branch is required");
                    bool create = args.has_member ("create") && args.get_boolean_member ("create");
                    check (create ? yield repo.create_branch (branch, true) : yield repo.checkout (branch));
                    return yield status (repo);
                }
                default: {
                    string op = text (args, "operation");
                    if (!(op in REMOTE_OPS)) throw new IOError.INVALID_ARGUMENT ("unknown operation %s", op);
                    GitResult r;
                    if (op == "fetch") r = yield repo.fetch ();
                    else if (op == "pull") r = yield repo.pull ();
                    else r = yield repo.push ();
                    check (r);
                    return yield status (repo);
                }
            }
        }

        private static void add (GitApp app, string name, string description, string schema, Singularity.AppIntentRisk risk) {
            app.agent.add_async_intent (name, description, schema, risk, (args, reply) => {
                handle.begin (app, name, args, (o, res) => {
                    try {
                        reply (handle.end (res), null);
                    } catch (Error e) {
                        reply (null, e);
                    }
                });
            });
        }

        internal static void install (GitApp app) {
            add (app, "git_repositories", "List the repositories open in the window and the one shown.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ);
            add (app, "git_status", "Read the branch, how far it is ahead or behind its upstream, and the staged, unstaged, untracked and conflicted files. Opens the repository when a path is given.",
                schema (), Singularity.AppIntentRisk.READ);
            add (app, "git_log", "List the latest commits of the current branch or of a revision.",
                schema ("\"limit\":{\"type\":\"integer\"},\"revision\":{\"type\":\"string\"}"), Singularity.AppIntentRisk.READ);
            add (app, "git_branches", "List local and remote branches with their upstream.",
                schema (), Singularity.AppIntentRisk.READ);
            add (app, "git_diff", "Read the changes of a file in the working tree (or staged), or of a commit.",
                schema ("\"file\":{\"type\":\"string\"},\"staged\":{\"type\":\"boolean\"},\"commit\":{\"type\":\"string\"}"), Singularity.AppIntentRisk.READ);
            add (app, "git_stage", "Stage files for the next commit, or unstage them. all covers every change.",
                schema ("\"files\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"all\":{\"type\":\"boolean\"},\"unstage\":{\"type\":\"boolean\"}"), Singularity.AppIntentRisk.UNDOABLE);
            add (app, "git_discard", "Throw away the unstaged changes of files, restoring them as they were committed.",
                schema ("\"files\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}", "\"files\""), Singularity.AppIntentRisk.IRREVERSIBLE);
            add (app, "git_commit", "Commit the staged changes with a message; with all, stage every change first.",
                schema ("\"message\":{\"type\":\"string\"},\"all\":{\"type\":\"boolean\"}", "\"message\""), Singularity.AppIntentRisk.UNDOABLE);
            add (app, "git_checkout", "Switch to a branch, or create it from the current commit and switch to it.",
                schema ("\"branch\":{\"type\":\"string\"},\"create\":{\"type\":\"boolean\"}", "\"branch\""), Singularity.AppIntentRisk.UNDOABLE);
            add (app, "git_remote", "Talk to the remote: fetch, pull (fast-forward only) or push the current branch.",
                schema ("\"operation\":{\"type\":\"string\",\"enum\":" + list (REMOTE_OPS) + "}", "\"operation\""), Singularity.AppIntentRisk.IRREVERSIBLE);
        }
    }
}
