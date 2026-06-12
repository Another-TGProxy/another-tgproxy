// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // A deliberately small Markdown -> Pango-markup converter for GitHub release
    // notes (GTK has no Markdown widget). It covers what release notes actually
    // use — headings, bold, italic, inline code, links and bullet lists — and
    // leaves anything else as literal text. Not a general Markdown engine.
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

        // Convert @md to Pango markup. The result is validated; if it doesn't parse
        // (unexpected input producing bad markup) the plain escaped text is returned
        // so the notes always render.
        public string to_pango (string md) {
            var sb = new StringBuilder ();
            foreach (unowned string raw in md.split ("\n")) {
                string line = raw.chomp ();          // drop a trailing \r
                string t = line.strip ();

                if (t.has_prefix ("```")) continue;  // fence markers: don't show them

                int level = 0;
                while (level < line.length && line[level] == '#') level++;
                if (level > 0 && level <= 6 && level < line.length && line[level] == ' ') {
                    var text = inline (GLib.Markup.escape_text (line.substring (level + 1).strip ()));
                    sb.append ("<big><b>").append (text).append ("</b></big>\n");
                    continue;
                }

                if (t.has_prefix ("- ") || t.has_prefix ("* ") || t.has_prefix ("+ ")) {
                    sb.append ("  • ").append (inline (GLib.Markup.escape_text (t.substring (2)))).append ("\n");
                    continue;
                }

                sb.append (inline (GLib.Markup.escape_text (line))).append ("\n");
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
    }
}
