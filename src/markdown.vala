// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // A deliberately small Markdown -> Pango-markup converter for GitHub release
    // notes (GTK has no Markdown widget). It covers what release notes actually
    // use — headings, bold, italic, inline code, links, bullet lists and tables —
    // and leaves anything else as literal text. Not a general Markdown engine.
    namespace Markdown {

        // Inline spans, applied to already-escaped text (so the inserted tags are
        // the only markup). Order matters: code first so it isn't reparsed, links
        // before emphasis, bold before italic so `**` isn't eaten by `*`.
        static string inline (string s) {
            string r = s;
            try {
                r = /`([^`]+)`/.replace (r, r.length, 0, "<tt>\\1</tt>");
                r = /\[([^\]]+)\]\(([^)\s]+)\)/.replace (r, r.length, 0, "<a href=\"\\2\">\\1</a>");
                r = /\*\*([^*]+)\*\*/.replace (r, r.length, 0, "<b>\\1</b>");
                r = /__([^_]+)__/.replace (r, r.length, 0, "<b>\\1</b>");
                r = /(?<![\w*])\*([^*\n]+)\*(?![\w*])/.replace (r, r.length, 0, "<i>\\1</i>");
                r = /(?<![\w_])_([^_\n]+)_(?![\w_])/.replace (r, r.length, 0, "<i>\\1</i>");
            } catch (RegexError e) {
                return s;
            }
            return r;
        }

        // Split a Markdown table row into trimmed cells, dropping the empty fields
        // a leading/trailing "|" produces.
        static GenericArray<string> table_cells (string row) {
            var cells = row.strip ().split ("|");
            var outc = new GenericArray<string> ();
            for (int i = 0; i < cells.length; i++) {
                if ((i == 0 || i == cells.length - 1) && cells[i].strip () == "")
                    continue;   // border pipe
                outc.add (cells[i].strip ());
            }
            return outc;
        }

        // A separator row is the "|---|:--:|" line under the header.
        static bool is_table_separator (string line) {
            var t = line.strip ();
            if (!t.contains ("|") || !t.contains ("-"))
                return false;
            return /^\|?[\s:|-]+\|?$/.match (t);
        }

        // Render a Markdown table as a monospace, column-aligned block (Pango has no
        // table support). @rows excludes the separator row; the first row is the head.
        static string render_table (GenericArray<GenericArray<string>> rows) {
            int cols = 0;
            for (int r = 0; r < rows.length; r++)
                cols = int.max (cols, rows[r].length);
            var width = new int[cols];
            for (int r = 0; r < rows.length; r++)
                for (int c = 0; c < rows[r].length; c++)
                    width[c] = int.max (width[c], rows[r][c].char_count ());

            var sb = new StringBuilder ("<tt>");
            for (int r = 0; r < rows.length; r++) {
                var line = new StringBuilder ();
                for (int c = 0; c < cols; c++) {
                    string cell = c < rows[r].length ? rows[r][c] : "";
                    line.append (cell);
                    int pad = width[c] - cell.char_count () + (c < cols - 1 ? 2 : 0);
                    for (int p = 0; p < pad; p++) line.append_c (' ');
                }
                string esc = GLib.Markup.escape_text (line.str.chomp ());
                if (r == 0)
                    sb.append ("<b>").append (esc).append ("</b>\n");
                else
                    sb.append (esc).append ("\n");
            }
            sb.append ("</tt>");
            return sb.str;
        }

        // Convert @md to Pango markup. The result is validated; if it doesn't parse
        // (unexpected input producing bad markup) the plain escaped text is returned
        // so the notes always render.
        public string to_pango (string md) {
            var lines = md.split ("\n");
            var sb = new StringBuilder ();
            int i = 0;
            while (i < lines.length) {
                string line = lines[i].chomp ();   // drop a trailing \r
                string t = line.strip ();

                // Table: a row of cells followed by a |---|---| separator.
                if (t.contains ("|") && i + 1 < lines.length && is_table_separator (lines[i + 1])) {
                    var rows = new GenericArray<GenericArray<string>> ();
                    rows.add (table_cells (line));
                    i += 2;   // skip header + separator
                    while (i < lines.length && lines[i].strip ().contains ("|")) {
                        rows.add (table_cells (lines[i].chomp ()));
                        i++;
                    }
                    sb.append (render_table (rows)).append ("\n");
                    continue;
                }

                if (t.has_prefix ("```")) { i++; continue; }   // fence markers

                int level = 0;
                while (level < line.length && line[level] == '#') level++;
                if (level > 0 && level <= 6 && level < line.length && line[level] == ' ') {
                    var text = inline (GLib.Markup.escape_text (line.substring (level + 1).strip ()));
                    sb.append ("<big><b>").append (text).append ("</b></big>\n");
                    i++;
                    continue;
                }

                if (t.has_prefix ("- ") || t.has_prefix ("* ") || t.has_prefix ("+ ")) {
                    sb.append ("  • ").append (inline (GLib.Markup.escape_text (t.substring (2)))).append ("\n");
                    i++;
                    continue;
                }

                sb.append (inline (GLib.Markup.escape_text (line))).append ("\n");
                i++;
            }

            string markup = sb.str.chomp ();
            // Sanity-check the result parses, so unexpected input can never leave the
            // label showing literal tags. Pango's own parser doesn't know GtkLabel's
            // <a> links, so validate with those stripped; the label still renders them.
            string check = markup;
            try {
                check = /<a [^>]*>/.replace (check, check.length, 0, "").replace ("</a>", "");
            } catch (RegexError e) {}
            try {
                Pango.parse_markup (check, -1, 0, null, null, null);
            } catch (Error e) {
                return GLib.Markup.escape_text (md.chomp ());
            }
            return markup;
        }

        // A Markdown table as a real Gtk.Grid: a monospace text block can't stay
        // aligned once long cells wrap on a narrow screen, so use a grid whose last
        // column expands and wraps instead.
        static Gtk.Widget build_grid (GenericArray<GenericArray<string>> rows) {
            int cols = 0;
            for (int r = 0; r < rows.length; r++)
                cols = int.max (cols, rows[r].length);
            var grid = new Gtk.Grid () {
                column_spacing = 16, row_spacing = 4, margin_top = 4, margin_bottom = 4
            };
            for (int r = 0; r < rows.length; r++) {
                for (int c = 0; c < rows[r].length; c++) {
                    string markup = inline (GLib.Markup.escape_text (rows[r][c]));
                    if (r == 0)
                        markup = "<b>" + markup + "</b>";
                    var lbl = new Gtk.Label (markup) {
                        use_markup = true, xalign = 0, yalign = 0, wrap = true, selectable = false
                    };
                    if (c == cols - 1)   // the wide column (e.g. file names) takes the slack
                        lbl.hexpand = true;
                    grid.attach (lbl, c, r, 1, 1);
                }
            }
            return grid;
        }

        // Flush accumulated non-table lines as one Pango label appended to @box.
        static void flush_text (Gtk.Box box, StringBuilder buf) {
            string markup = to_pango (buf.str);
            buf.erase ();
            if (markup.strip () == "")
                return;
            box.append (new Gtk.Label (markup) {
                use_markup = true, wrap = true, xalign = 0, yalign = 0, selectable = false
            });
        }

        // Render @md as a widget: paragraphs/headings/lists become Pango labels and
        // tables become grids, so notes display correctly even on a narrow screen.
        // Non-selectable; the caller puts it in a scroller.
        public Gtk.Widget render (string md) {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { margin_end = 12 };
            var lines = md.split ("\n");
            var buf = new StringBuilder ();

            int i = 0;
            while (i < lines.length) {
                if (lines[i].strip ().contains ("|") && i + 1 < lines.length
                    && is_table_separator (lines[i + 1])) {
                    flush_text (box, buf);
                    var rows = new GenericArray<GenericArray<string>> ();
                    rows.add (table_cells (lines[i].chomp ()));
                    i += 2;
                    while (i < lines.length && lines[i].strip ().contains ("|")) {
                        rows.add (table_cells (lines[i].chomp ()));
                        i++;
                    }
                    box.append (build_grid (rows));
                    continue;
                }
                buf.append (lines[i]).append_c ('\n');
                i++;
            }
            flush_text (box, buf);
            return box;
        }
    }
}
