// SPDX-License-Identifier: GPL-3.0-or-later
namespace TgWsProxy {

    // First-run wizard: walks through the few settings that actually need a
    // decision, then starts the proxy and hands over the tg:// link. Everything
    // else keeps its default and stays in Settings.
    //
    // Shown as a dialog over the window rather than as another ViewStack page:
    // the window's stack is the running app's navigation, and on Android a
    // dialog becomes a bottom sheet for free.
    [GtkTemplate (ui = "/space/ampernic/AnotherTGProxy/ui/setup-wizard.ui")]
    public class SetupWizard : Adw.Dialog {

        // A proxy that has not reported in by then is not going to.
        private const uint APPLY_TIMEOUT_SEC = 15;
        // How long to wait for a release check before treating silence as "current".
        private const uint UPDATE_PROBE_SEC = 8;

        [GtkChild] private unowned Gtk.Stack steps;
        [GtkChild] private unowned Gtk.Box dots_box;
        [GtkChild] private unowned Gtk.Stack update_stack;
        [GtkChild] private unowned Adw.StatusPage update_status;
        [GtkChild] private unowned Gtk.Button notes_btn;
        [GtkChild] private unowned Gtk.Button skip_update_btn;
        [GtkChild] private unowned Gtk.ProgressBar dl_bar;
        [GtkChild] private unowned Adw.StatusPage install_status;
        [GtkChild] private unowned Adw.StatusPage connection_page;
#if ANDROID
        [GtkChild] private unowned Adw.StatusPage autostart_page;
#endif
        [GtkChild] private unowned Adw.StatusPage status_page;
        [GtkChild] private unowned Gtk.Stack done_stack;
        [GtkChild] private unowned Adw.StatusPage error_status;

        [GtkChild] private unowned Gtk.Button skip_btn;
        [GtkChild] private unowned Adw.SpinRow port_row;
        [GtkChild] private unowned Adw.PasswordEntryRow secret_row;
        [GtkChild] private unowned Gtk.Button regen_btn;
        [GtkChild] private unowned Adw.EntryRow host_row;
        [GtkChild] private unowned Adw.SwitchRow autostart_row;
        [GtkChild] private unowned Adw.ToggleGroup status_mode_group;
        [GtkChild] private unowned Adw.ActionRow link_row;
        [GtkChild] private unowned Gtk.Button open_btn;
        [GtkChild] private unowned Gtk.Button copy_btn;
        [GtkChild] private unowned Gtk.Button support_btn;
        [GtkChild] private unowned Gtk.Button back_to_settings_btn;
        [GtkChild] private unowned Gtk.Revealer back_revealer;
        [GtkChild] private unowned Gtk.Button back_btn;
        [GtkChild] private unowned Gtk.Button next_btn;

        public signal void toast (string message);
        // The window owns the download/install flow; the wizard only asks for it.
        public signal void update_requested ();

        private Config cfg;
        private DaemonClient client;
        private ServiceController service;
        private Station.Updates? updater = null;
        private uint update_timer = 0;
        private string update_version = "";
        private string update_notes = "";
        private GenericArray<Gtk.Widget> pages = new GenericArray<Gtk.Widget> ();
        private string link = "";
        private bool applying = false;
        private uint apply_timer = 0;

        public void bind (Config cfg, DaemonClient client, ServiceController service,
                          Station.Updates? updater) {
            this.cfg = cfg;
            this.client = client;
            this.service = service;
            this.updater = updater;

            port_row.value = cfg.port;
            secret_row.text = cfg.secret;
            host_row.text = cfg.host;
            autostart_row.active = service.is_autostart ();

            drop_pointless_steps ();
            collect_pages ();

            regen_btn.clicked.connect (() => { secret_row.text = Config.gen_secret (); });
            secret_row.notify["text"].connect (update_nav);
            back_btn.clicked.connect (() => go (-1));
            next_btn.clicked.connect (() => {
                if (finished ()) { clear_timer (); force_close (); }
                else if (installing_update ()) quit_app ();
                else if (offering_update ()) update_requested ();
                else if (announcing_update ()) skip_this_version ();
                else go (1);
            });
            steps.notify["visible-child"].connect (update_nav);

            // Swiping between steps: on a phone the thumb reaches for it before it
            // reaches the buttons. Forward honours the same readiness check as the
            // Next button, so a swipe cannot skip past an unfinished step.
            var swipe = new Gtk.GestureSwipe ();
            swipe.swipe.connect ((vx, vy) => {
                double ax = (vx < 0) ? -vx : vx;
                double ay = (vy < 0) ? -vy : vy;
                if (ax < 200 || ax < ay) return;   // too slow, or a vertical scroll
                if (vx < 0) {
                    if (!finished () && !offering_update () && !installing_update ()
                        && !downloading_update () && step_ready (current ()))
                        go (1);
                } else {
                    go (-1);
                }
            });
            steps.add_controller (swipe);

            open_btn.clicked.connect (() => open_uri (link));
            copy_btn.clicked.connect (() => {
                if (link == "") return;
                get_clipboard ().set_text (link);
                toast (_("Link copied"));
            });
            support_btn.clicked.connect (() => open_uri (SUPPORT_CHANNEL));
            notes_btn.clicked.connect (show_release_notes);
            // Saying no here is about this release, not about updates in general:
            // remember it so nothing offers the same version again five seconds later.
            skip_update_btn.clicked.connect (() => {
                if (update_version != "") {
                    cfg.skipped_version = update_version;
                    cfg.save ();
                }
                go (1);
            });
            if (updater != null)
                updater.available.connect (on_update_available);
            back_to_settings_btn.clicked.connect (() => {
                done_stack.visible_child_name = "applying";
                go_to (index_of (connection_page));
            });

            // The dialog itself won't dismiss (can-close is false), but Esc and the
            // window's close button must still be a way out of the app — otherwise
            // an unfinished wizard holds the whole window hostage.
            close_attempt.connect (() => {
                var app = (get_root () as Gtk.Window)?.application;
                if (app != null) app.quit ();
            });

            client.status_changed.connect (on_status);
            // Without this the real reason (port taken, spawn failed) is lost and
            // the wizard just sits there until the timeout with nothing useful.
            service.failed.connect ((msg) => {
                if (applying) fail (msg);
            });
            update_nav ();
        }

        // Let the window close even though the wizard is modal and undismissable.
        public void release () {
            clear_timer ();
            force_close ();
        }

        // A step with nothing to ask is noise: drop it rather than show a page
        // whose only control is disabled or has a single choice.
        private void drop_pointless_steps () {
            // No updater means this delivery updates through a repository — there
            // is nothing to check and nothing to offer.
            if (updater == null)
                steps.remove (update_stack);
#if ANDROID
            // The engine lives in the activity process; there is no login autostart
            // to offer, and the foreground-service notification is the only status
            // display, so neither step has a question to ask.
            steps.remove (autostart_page);
            steps.remove (status_page);
#else
            var p = Platform.get_default ();
            fill_mode_toggles (status_mode_group, p, cfg.status_mode);
            if (status_mode_group.n_toggles < 2)
                steps.remove (status_page);
#endif
        }

        private void collect_pages () {
            pages = new GenericArray<Gtk.Widget> ();
            for (var c = steps.get_first_child (); c != null; c = c.get_next_sibling ())
                pages.add (c);
            // One dot per step that survived drop_pointless_steps.
            for (uint i = 0; i < pages.length; i++)
                dots_box.append (new Gtk.Label ("●"));
            mark_dots (0);
        }

        private void mark_dots (int active) {
            int i = 0;
            for (var c = dots_box.get_first_child (); c != null; c = c.get_next_sibling ()) {
                c.opacity = (i == active) ? 1.0 : 0.35;
                i++;
            }
        }

        private int index_of (Gtk.Widget w) {
            for (uint i = 0; i < pages.length; i++)
                if (pages[i] == w) return (int) i;
            return 0;
        }

        private int current () {
            var v = steps.get_visible_child ();
            return (v == null) ? 0 : index_of (v);
        }

        private void go (int delta) {
            int next = current () + delta;
            if (next < 0 || next >= pages.length) return;
            // Entering the final page is what commits the settings.
            if (pages[next] == done_stack)
                apply ();
            go_to (next);
        }

        private void go_to (int idx) {
            if (idx < 0 || idx >= pages.length) return;
            steps.set_visible_child (pages[idx]);
            mark_dots (idx);
            if (pages[idx] == update_stack)
                probe_update ();
        }

        // libstation only signals when something IS available, so "no update" is
        // the absence of that answer: give it a few seconds, then call it current.
        private void probe_update () {
            if (updater == null || update_stack.visible_child_name != "checking")
                return;
            updater.check ();
            update_timer = Timeout.add_seconds (UPDATE_PROBE_SEC, () => {
                update_timer = 0;
                if (update_stack.visible_child_name == "checking")
                    update_stack.visible_child_name = "uptodate";
                return Source.REMOVE;
            });
        }

        private void on_update_available (string version, string url, string notes) {
            if (update_timer != 0) {
                Source.remove (update_timer);
                update_timer = 0;
            }
            update_version = version;
            update_notes = notes;
            update_status.description = Platform.get_default ().updates_installable ()
                ? _("Version %s is ready to install.").printf (version)
                : _("Version %s has been released. It installs through the repository this app came from.").printf (version);
            update_stack.visible_child_name = "available";
            notes_btn.visible = notes != "";
            skip_update_btn.visible = Platform.get_default ().updates_installable ();
            update_nav ();
        }

        // Same presentation as the window's update dialog: the notes are Markdown
        // and get rendered as widgets rather than dumped as raw text.
        private void show_release_notes () {
            if (update_notes == "") return;
            var dlg = new Adw.Dialog () {
                title = _("Update available: %s").printf (update_version),
                content_width = 480
            };
            var tv = new Adw.ToolbarView ();
            tv.add_top_bar (new Adw.HeaderBar ());
            tv.content = new Gtk.ScrolledWindow () {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                max_content_height = 420,
                margin_top = 12, margin_bottom = 12,
                margin_start = 12, margin_end = 12,
                child = Markdown.render (update_notes)
            };
            dlg.child = tv;
            dlg.present (this);
        }

        private bool step_ready (int idx) {
            if (pages[idx] == connection_page)
                return secret_row.text.strip ().length == 32;
            return true;
        }

        // True while the update step is actually offering something to install:
        // there the primary button installs instead of moving on. Where a
        // repository installs the app the step only announces the release, so the
        // button stays "Next".
        private bool offering_update () {
            int idx = current ();
            return idx < pages.length
                && pages[idx] == update_stack
                && update_stack.visible_child_name == "available"
                && Platform.get_default ().updates_installable ();
        }

        private bool checking_update () {
            int idx = current ();
            return idx < pages.length
                && pages[idx] == update_stack
                && update_stack.visible_child_name == "checking";
        }

        private bool downloading_update () {
            int idx = current ();
            return idx < pages.length
                && pages[idx] == update_stack
                && update_stack.visible_child_name == "downloading";
        }

        // The installer has the file: whatever the wizard would ask next is a
        // question for the new version, which starts its own wizard.
        // The release exists but a repository installs it: nothing to press here
        // except "not this one", so that moves down to the primary button.
        private bool announcing_update () {
            int idx = current ();
            return idx < pages.length
                && pages[idx] == update_stack
                && update_stack.visible_child_name == "available"
                && !Platform.get_default ().updates_installable ();
        }

        private void skip_this_version () {
            if (update_version != "") {
                cfg.skipped_version = update_version;
                cfg.save ();
            }
            go (1);
        }

        private bool installing_update () {
            int idx = current ();
            return idx < pages.length
                && pages[idx] == update_stack
                && update_stack.visible_child_name == "installing";
        }

        private void quit_app () {
            var app = (get_root () as Gtk.Window)?.application;
            if (app != null) app.quit ();
        }

        // The window owns the updater and the install; it downloads on our behalf
        // and drives these, so the offer is not repeated in a dialog on top of a
        // step that just made the same offer.
        public void download_started () {
            dl_bar.fraction = 0;
            dl_bar.text = "";
            update_stack.visible_child_name = "downloading";
            update_nav ();
        }

        public void download_progress (double frac) {
            if (frac < 0) {
                dl_bar.pulse ();
                return;
            }
            dl_bar.fraction = frac;
            dl_bar.text = "%d %%".printf ((int) (frac * 100));
        }

        // Platforms that restart into the installer never get here; the ones that
        // hand the file over (macOS, Android's package installer) do, and the step
        // has to lead somewhere after that. The window words it: it knows how this
        // delivery installs.
        public void download_finished (string hint) {
            install_status.description = hint;
            update_stack.visible_child_name = "installing";
            update_nav ();
        }

        public void download_failed (string reason) {
            update_stack.visible_child_name = "available";
            update_nav ();
            toast (_("Download failed: %s").printf (reason));
        }

        // The proxy is up and the link is on screen: the primary button becomes
        // the way out. Kept in the bottom bar like every other step's, instead of
        // at the end of a page the user would have to scroll to reach.
        private bool finished () {
            int idx = current ();
            return idx < pages.length
                && pages[idx] == done_stack
                && done_stack.visible_child_name == "ready";
        }

        private void update_nav () {
            int idx = current ();
            if (idx >= pages.length) return;
            bool last = pages[idx] == done_stack;
            back_revealer.reveal_child = idx > 0 && !last;
            // On the final page the button only appears once there's an outcome
            // worth acting on; while applying or on error the page speaks for itself.
            // While the check is still running there is nothing to decide yet, and
            // a visible Next is too easy to hit past the step.
            next_btn.visible = (!last || finished ()) && !checking_update ();
            next_btn.sensitive = step_ready (idx) && !downloading_update ();
            if (finished ())
                next_btn.label = _("Start using");
            else if (installing_update ())
                next_btn.label = _("Quit");
            else if (offering_update ())
                next_btn.label = _("Update now");
            else if (announcing_update ())
                next_btn.label = _("Skip, I know what I'm doing");
            else if (downloading_update ())
                next_btn.label = _("Downloading…");
            else
                next_btn.label = (idx == pages.length - 2) ? _("Finish") : _("Next");
        }

        private void apply () {
            cfg.port = (int) port_row.value;
            var sec = secret_row.text.strip ();
            if (sec.length == 32) cfg.secret = sec;
            var h = host_row.text.strip ();
            if (h != "") cfg.host = h;
            if (status_mode_group.get_parent () != null
                && status_mode_group.active_name != null)
                cfg.status_mode = status_mode_group.active_name;
            cfg.autostart = autostart_row.active;
            cfg.setup_done = true;
            cfg.save ();
#if !ANDROID
            service.set_autostart (autostart_row.active);
#endif

            applying = true;
            done_stack.visible_child_name = "applying";
            // Same order Settings uses: the daemon rereads config.json on reload,
            // and is started only if it isn't up yet.
            client.send ("reload");
            if (!service.is_active ()) service.start ();

            apply_timer = Timeout.add_seconds (APPLY_TIMEOUT_SEC, () => {
                apply_timer = 0;
                if (applying)
                    fail (_("The proxy did not report back in time. Another copy may already be holding port %d — check the log for details.").printf (cfg.port));
                return Source.REMOVE;
            });
        }

        private void on_status (Status s) {
            if (!applying) return;
            if (s.error != "") {
                fail (s.error);
                return;
            }
            if (!s.running || s.secret.length != 32) return;

            applying = false;
            clear_timer ();
            link = proxy_link (s.host, s.port, s.secret);
            link_row.subtitle = link;
            done_stack.visible_child_name = "ready";
            update_nav ();
        }

        private void fail (string detail) {
            applying = false;
            clear_timer ();
            error_status.description = detail;
            done_stack.visible_child_name = "error";
            update_nav ();
        }

        private void clear_timer () {
            if (apply_timer != 0) {
                Source.remove (apply_timer);
                apply_timer = 0;
            }
            if (update_timer != 0) {
                Source.remove (update_timer);
                update_timer = 0;
            }
        }

        private void open_uri (string uri) {
            open_external_uri (this, uri, (message) => {
                toast (_("Failed to open the link: %s").printf (message));
            });
        }
    }
}
