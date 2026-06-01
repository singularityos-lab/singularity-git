using Gtk;
using GLib;

namespace Singularity.Apps.Git {

    /**
     * Read-only unified-diff viewer built on GtkSourceView, with line-level
     * coloring for additions / deletions / hunk headers.
     */
    public class DiffView : Gtk.Box {
        private GtkSource.View view;
        private GtkSource.Buffer buffer;
        private TextTag tag_add;
        private TextTag tag_del;
        private TextTag tag_hunk;
        private TextTag tag_meta;

        public DiffView() {
            Object(orientation: Orientation.VERTICAL, spacing: 0);
            hexpand = true; vexpand = true;

            var scroll = new ScrolledWindow();
            scroll.hexpand = true; scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.AUTOMATIC;
            scroll.vscrollbar_policy = PolicyType.AUTOMATIC;

            buffer = new GtkSource.Buffer(null);
            var sv = new Singularity.Widgets.SourceView(buffer);
            sv.editable = false;
            sv.cursor_visible = false;
            sv.show_line_numbers = false;
            sv.top_margin = 0;
            sv.bottom_margin = 0;
            sv.left_margin = 8;
            sv.right_margin = 8;
            sv.add_css_class("git-diff-view");
            view = sv;
            scroll.set_child(view);
            append(scroll);

            tag_add  = buffer.create_tag("add",  "paragraph-background-rgba", rgba("#1f3a26"));
            tag_del  = buffer.create_tag("del",  "paragraph-background-rgba", rgba("#3a1f1f"));
            tag_hunk = buffer.create_tag("hunk", "foreground", "#3584e4", "weight", Pango.Weight.BOLD);
            tag_meta = buffer.create_tag("meta", "foreground", "#888888");
        }

        private Gdk.RGBA rgba(string hex) {
            var c = Gdk.RGBA();
            c.parse(hex);
            return c;
        }

        public void clear() {
            buffer.text = "";
        }

        public void show_diff(string diff) {
            buffer.text = diff;
            // Re-tag line by line.
            TextIter start, end;
            buffer.get_bounds(out start, out end);
            buffer.remove_all_tags(start, end);

            int line_count = buffer.get_line_count();
            for (int i = 0; i < line_count; i++) {
                TextIter ls, le;
                buffer.get_iter_at_line(out ls, i);
                le = ls;
                if (!le.ends_line()) le.forward_to_line_end();
                string line = buffer.get_text(ls, le, false);
                if (line.has_prefix("@@")) {
                    buffer.apply_tag(tag_hunk, ls, le);
                } else if (line.has_prefix("+++") || line.has_prefix("---") ||
                           line.has_prefix("diff ") || line.has_prefix("index ") ||
                           line.has_prefix("new file") || line.has_prefix("deleted file") ||
                           line.has_prefix("rename ") || line.has_prefix("similarity ")) {
                    buffer.apply_tag(tag_meta, ls, le);
                } else if (line.has_prefix("+")) {
                    var fle = ls;
                    if (!fle.ends_line()) fle.forward_to_line_end();
                    buffer.apply_tag(tag_add, ls, fle);
                } else if (line.has_prefix("-")) {
                    var fle = ls;
                    if (!fle.ends_line()) fle.forward_to_line_end();
                    buffer.apply_tag(tag_del, ls, fle);
                }
            }
        }

        public void show_message(string msg) {
            buffer.text = msg;
        }
    }
}
